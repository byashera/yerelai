"""YerelAI Studio — Cloudflare Tunnel, Local Wi-Fi LAN & GitHub Permanent Bridge Manager.

Supports:
  1. Cloudflare Quick Tunnel (`*.trycloudflare.com`)
  2. Cloudflare Named Tunnel (`cloudflared tunnel run --token <TOKEN>`) with Fixed Custom Domain
  3. Local Wi-Fi LAN URL (`http://192.168.x.x:8070`) for zero-latency same-network mobile access
  4. GitHub Gist Permanent Bridge (`yerelai_tunnel.json` + `yerelai_redirect.html`) so Android APK /
     iOS Apps and permanent browser bookmarks NEVER break when Quick Tunnel URLs change!
"""

from __future__ import annotations

import json
import os
import re
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Optional

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
DATA_DIR.mkdir(parents=True, exist_ok=True)
SETTINGS_PATH = DATA_DIR / "tunnel_settings.json"
CLOUDFLARED_BIN = BASE_DIR / ".cloudflared" / "cloudflared.exe"
TUNNEL_LOG = BASE_DIR / "tunnel.log"
URL_RE = re.compile(r"https://[a-z0-9-]+\.trycloudflare\.com", re.I)


def detect_lan_ip() -> str:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.settimeout(0.4)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            if ip and not ip.startswith("127."):
                return ip
    except Exception:
        pass
    try:
        ip = socket.gethostbyname(socket.gethostname())
        if ip and not ip.startswith("127."):
            return ip
    except Exception:
        pass
    return "127.0.0.1"


class TunnelManager:
    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.proc: Optional[subprocess.Popen] = None
        self.url: str = ""
        self.error: str = ""

    def get_settings(self) -> Dict[str, Any]:
        defaults = {
            "auto_start": False,
            "cf_named_token": "",
            "cf_custom_domain": "",
            "github_token": "",
            "github_gist_id": "",
            "github_owner": "",
            "static_json_url": "",
            "static_web_url": "",
            "last_synced_at": "",
            "last_sync_error": "",
        }
        if not SETTINGS_PATH.exists():
            return defaults
        try:
            raw = json.loads(SETTINGS_PATH.read_text(encoding="utf-8"))
            if isinstance(raw, dict):
                defaults.update(raw)
        except Exception:
            pass
        return defaults

    def save_settings(self, updates: Dict[str, Any]) -> Dict[str, Any]:
        with self.lock:
            cur = self.get_settings()
            for k in (
                "auto_start",
                "cf_named_token",
                "cf_custom_domain",
                "github_token",
                "github_gist_id",
                "github_owner",
                "static_json_url",
                "static_web_url",
                "last_synced_at",
                "last_sync_error",
            ):
                if k in updates and updates[k] is not None:
                    if k == "auto_start":
                        cur[k] = bool(updates[k])
                    else:
                        val = str(updates[k]).strip()
                        # Ignore masked token placeholders sent back from UI
                        if k in ("github_token", "cf_named_token") and val.startswith("••"):
                            continue
                        cur[k] = val
            if cur["cf_custom_domain"] and not cur["cf_custom_domain"].startswith(("http://", "https://")):
                cur["cf_custom_domain"] = "https://" + cur["cf_custom_domain"]
            cur["cf_custom_domain"] = cur["cf_custom_domain"].rstrip("/")
            tmp = SETTINGS_PATH.with_suffix(".tmp")
            tmp.write_text(json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
            os.replace(tmp, SETTINGS_PATH)
            return cur

    def _read_url_from_log(self) -> str:
        if not TUNNEL_LOG.exists():
            return ""
        try:
            txt = TUNNEL_LOG.read_text(encoding="utf-8", errors="ignore")
            matches = URL_RE.findall(txt)
            return matches[-1] if matches else ""
        except Exception:
            return ""

    def get_lan_url(self, port: int = 8070) -> str:
        ip = detect_lan_ip()
        return f"http://{ip}:{port}"

    def status(self, port: int = 8070) -> Dict[str, Any]:
        with self.lock:
            st = self.get_settings()
            lan_url = self.get_lan_url(port)
            alive = self.proc is not None and self.proc.poll() is None
            using_named = bool(st.get("cf_named_token"))

            if alive and not self.url:
                if using_named and st.get("cf_custom_domain"):
                    self.url = st["cf_custom_domain"]
                else:
                    self.url = self._read_url_from_log()

            active_url = self.url if alive else self._read_url_from_log()
            if not active_url and using_named and alive and st.get("cf_custom_domain"):
                active_url = st["cf_custom_domain"]

            return {
                "available": CLOUDFLARED_BIN.exists(),
                "running": alive,
                "managed": alive,
                "mode": "named_domain" if (using_named and st.get("cf_custom_domain")) else "quick_tunnel",
                "url": active_url,
                "lan_url": lan_url,
                "error": self.error,
                "auto_start": bool(st.get("auto_start")),
                "cf_custom_domain": st.get("cf_custom_domain", ""),
                "has_cf_token": bool(st.get("cf_named_token")),
                "has_github_token": bool(st.get("github_token")),
                "github_gist_id": st.get("github_gist_id", ""),
                "static_json_url": st.get("static_json_url", ""),
                "static_web_url": st.get("static_web_url", ""),
                "last_synced_at": st.get("last_synced_at", ""),
                "last_sync_error": st.get("last_sync_error", ""),
            }

    def start(self, port: int = 8070) -> Dict[str, Any]:
        with self.lock:
            if not CLOUDFLARED_BIN.exists():
                self.error = "cloudflared.exe bulunamadı."
                return self.status(port)
            if self.proc is not None and self.proc.poll() is None:
                if not self.url:
                    self.url = self._read_url_from_log()
                return self.status(port)

            st = self.get_settings()
            named_token = (st.get("cf_named_token") or "").strip()
            custom_domain = (st.get("cf_custom_domain") or "").strip()

            self.error = ""
            self.url = ""
            try:
                TUNNEL_LOG.unlink(missing_ok=True)
            except OSError:
                pass

            creation_flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            if named_token:
                argv = [
                    str(CLOUDFLARED_BIN),
                    "tunnel",
                    "--no-autoupdate",
                    "--logfile",
                    str(TUNNEL_LOG),
                    "run",
                    "--token",
                    named_token,
                ]
            else:
                argv = [
                    str(CLOUDFLARED_BIN),
                    "tunnel",
                    "--url",
                    f"http://127.0.0.1:{port}",
                    "--no-autoupdate",
                    "--logfile",
                    str(TUNNEL_LOG),
                ]

            self.proc = subprocess.Popen(
                argv,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                creationflags=creation_flags,
            )

        if named_token:
            time.sleep(1.6)
            with self.lock:
                if self.proc is None or self.proc.poll() is not None:
                    self.error = "Sabit Cloudflare Tunnel Token ile başlatılamadı (Token'ı kontrol edin)."
                else:
                    self.url = custom_domain or "https://(Sabit-Cloudflare-Tünel-Aktif)"
        else:
            deadline = time.time() + 10.5
            while time.time() < deadline:
                with self.lock:
                    if self.proc is None or self.proc.poll() is not None:
                        self.error = "Tünel başlatılamadı (internet bağlantınızı kontrol edin)."
                        break
                    found = self._read_url_from_log()
                    if found:
                        self.url = found
                        break
                time.sleep(0.35)

        # Auto-sync latest tunnel URL to GitHub Gist if configured
        st_after = self.get_settings()
        if self.url and st_after.get("github_token"):
            try:
                self.sync_github_bridge(port=port)
            except Exception:
                pass

        return self.status(port)

    def stop(self, port: int = 8070) -> Dict[str, Any]:
        with self.lock:
            if self.proc is not None:
                try:
                    if self.proc.poll() is None:
                        self.proc.terminate()
                        try:
                            self.proc.wait(timeout=3.0)
                        except subprocess.TimeoutExpired:
                            self.proc.kill()
                except Exception:
                    pass
                self.proc = None
            self.url = ""
            self.error = ""
            return self.status(port)

    # ---- GitHub Permanent Bridge (Static JSON for APK/iOS + Static Web Redirect) ----

    def sync_github_bridge(self, port: int = 8070) -> Dict[str, Any]:
        st = self.get_settings()
        gh_token = (st.get("github_token") or "").strip()
        if not gh_token:
            raise ValueError("GitHub Personal Access Token (gist yetkili) girilmedi.")

        cur_status = self.status(port)
        active_url = cur_status.get("url") or st.get("cf_custom_domain") or ""
        lan_url = cur_status.get("lan_url") or self.get_lan_url(port)
        now_iso = datetime.now().isoformat(timespec="seconds")

        json_payload = json.dumps(
            {
                "app": "YerelAI Studio",
                "url": active_url,
                "lan_url": lan_url,
                "running": bool(cur_status.get("running") and active_url),
                "updated_at": now_iso,
            },
            ensure_ascii=False,
            indent=2,
        )

        redirect_html = f"""<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover" />
  <title>YerelAI Studio · Bağlanılıyor</title>
  <style>
    body {{ margin:0; height:100dvh; display:flex; align-items:center; justify-content:center; background:#14161c; color:#eef0f4; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; text-align:center; padding:20px; }}
    .card {{ max-width:380px; width:100%; padding:28px 24px; border-radius:20px; background:#20242f; border:1px solid rgba(255,255,255,0.1); box-shadow:0 20px 50px rgba(0,0,0,0.4); }}
    h2 {{ margin:0 0 8px; font-size:19px; }}
    p {{ margin:0 0 18px; font-size:13.5px; color:#a1a9b8; line-height:1.45; }}
    a.btn {{ display:block; padding:12px 16px; border-radius:12px; background:#2563eb; color:#fff; text-decoration:none; font-weight:600; font-size:14px; margin-bottom:10px; }}
    a.sub {{ display:block; padding:10px 14px; border-radius:12px; background:rgba(255,255,255,0.06); color:#cbd5e1; text-decoration:none; font-size:12.5px; }}
  </style>
</head>
<body>
  <div class="card">
    <h2>YerelAI Studio</h2>
    <p id="msg">Aktif tünel adresine yönlendiriliyorsunuz...</p>
    <a class="btn" id="btn-tunnel" href="{active_url or '#'}">Tünel Üzerinden Aç</a>
    <a class="sub" id="btn-lan" href="{lan_url}">Aynı Wi-Fi Ağından Aç ({lan_url})</a>
  </div>
  <script>
    const target = {json.dumps(active_url)};
    if (target && target.startsWith("http")) {{
      setTimeout(() => {{ window.location.replace(target); }}, 180);
    }} else {{
      document.getElementById("msg").textContent = "Tünel şu an kapalı görünüyor. Aynı Wi-Fi ağındaysanız aşağıdaki yerel adresten bağlanabilirsiniz.";
    }}
  </script>
</body>
</html>"""

        gist_body = {
            "description": "YerelAI Studio — Sabit Mobil & APK/iOS Bağlantı Köprüsü",
            "public": False,
            "files": {
                "yerelai_tunnel.json": {"content": json_payload},
                "yerelai_redirect.html": {"content": redirect_html},
            },
        }

        gist_id = (st.get("github_gist_id") or "").strip()

        def _call_gh(method: str, endpoint: str, body_dict: Dict[str, Any]) -> Dict[str, Any]:
            req = urllib.request.Request(
                endpoint,
                data=json.dumps(body_dict).encode("utf-8"),
                headers={
                    "Authorization": f"Bearer {gh_token}",
                    "Accept": "application/vnd.github+json",
                    "Content-Type": "application/json",
                    "User-Agent": "YerelAI-Studio/14.0",
                    "X-GitHub-Api-Version": "2022-11-28",
                },
                method=method,
            )
            with urllib.request.urlopen(req, timeout=12) as resp:
                return json.loads(resp.read().decode("utf-8", errors="replace"))

        try:
            if gist_id:
                try:
                    res_data = _call_gh("PATCH", f"https://api.github.com/gists/{gist_id}", gist_body)
                except urllib.error.HTTPError as he:
                    if he.code == 404:
                        res_data = _call_gh("POST", "https://api.github.com/gists", gist_body)
                    else:
                        raise
            else:
                res_data = _call_gh("POST", "https://api.github.com/gists", gist_body)

            new_id = str(res_data.get("id") or gist_id)
            owner = str((res_data.get("owner") or {}).get("login") or st.get("github_owner") or "user")
            # Revisionless raw URLs ALWAYS serve the latest Gist revision without changing URL!
            static_json = f"https://gist.githubusercontent.com/{owner}/{new_id}/raw/yerelai_tunnel.json"
            static_web = f"https://htmlpreview.github.io/?https://gist.githubusercontent.com/{owner}/{new_id}/raw/yerelai_redirect.html"

            self.save_settings({
                "github_gist_id": new_id,
                "github_owner": owner,
                "static_json_url": static_json,
                "static_web_url": static_web,
                "last_synced_at": now_iso,
                "last_sync_error": "",
            })
            return self.status(port)
        except urllib.error.HTTPError as exc:
            err_detail = f"GitHub API Hatası (HTTP {exc.code}): Token 'gist' yetkisini kontrol edin."
            self.save_settings({"last_sync_error": err_detail})
            raise RuntimeError(err_detail)
        except Exception as exc:
            err_detail = f"GitHub senkronizasyon hatası: {exc}"
            self.save_settings({"last_sync_error": err_detail})
            raise RuntimeError(err_detail)


tunnel_mgr = TunnelManager()
