"""YerelAI Studio — Lightweight Local MCP (Model Context Protocol) Client (JSON-RPC 2.0).

Supports user-approved local `stdio` and `http` MCP servers with zero external dependencies,
plus built-in offline Python MCP servers for Filesystem, SQLite, Git, and Web Fetch.
"""

from __future__ import annotations

import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

BASE_PROJECT_DIR = Path(__file__).resolve().parent.parent
BUILTIN_MCP_SCRIPT = str(Path(__file__).resolve().parent / "builtin_mcp_server.py")
DESKTOP_DIR = str(Path.home() / "Desktop")


def _split_win_args(args_str: str) -> List[str]:
    """Splits command-line arguments WITHOUT eating Windows backslashes."""
    if not args_str or not args_str.strip():
        return []
    parts = shlex.split(args_str.strip(), posix=False)
    cleaned: List[str] = []
    for p in parts:
        if len(p) >= 2 and ((p[0] == '"' and p[-1] == '"') or (p[0] == "'" and p[-1] == "'")):
            p = p[1:-1]
        cleaned.append(p)
    return cleaned


def _resolve_command(cmd: str) -> str:
    """Resolves Windows commands (.exe / .cmd / .bat) and built-in Python alias."""
    c = (cmd or "").strip()
    if c in ("__PYTHON__", "python", "python3"):
        return sys.executable
    extra_paths = [
        r"C:\Program Files\nodejs",
        str(Path(sys.executable).parent),
        str(Path.home() / ".local" / "bin"),
    ]
    cur_path = os.environ.get("PATH", "")
    search_path = os.pathsep.join([*extra_paths, cur_path])
    found = shutil.which(c, path=search_path)
    return found or c


MCP_PRESETS: List[Dict[str, Any]] = [
    {
        "id": "filesystem",
        "name": "Dosya Sistemi",
        "transport": "stdio",
        "command": "python",
        "args": f'"{BUILTIN_MCP_SCRIPT}" --mode filesystem --root "{DESKTOP_DIR}"',
        "desc": "Seçili klasördeki dosyaları listeleme, okuma ve arama (%100 çevrimdışı yerleşik)",
    },
    {
        "id": "sqlite",
        "name": "SQLite Veritabanı",
        "transport": "stdio",
        "command": "python",
        "args": f'"{BUILTIN_MCP_SCRIPT}" --mode sqlite --db "{BASE_PROJECT_DIR / "data" / "yerelai.db"}"',
        "desc": "Yerel SQLite veritabanı tablo ve SELECT sorgulama (%100 çevrimdışı yerleşik)",
    },
    {
        "id": "git",
        "name": "Git Deposu",
        "transport": "stdio",
        "command": "python",
        "args": f'"{BUILTIN_MCP_SCRIPT}" --mode git --repo "{BASE_PROJECT_DIR}"',
        "desc": "Git durum, commit geçmişi ve diff inceleme (%100 çevrimdışı yerleşik)",
    },
    {
        "id": "fetch",
        "name": "Web Fetch",
        "transport": "stdio",
        "command": "python",
        "args": f'"{BUILTIN_MCP_SCRIPT}" --mode fetch',
        "desc": "Web sayfalarını temiz metin olarak çekme (%100 çevrimdışı yerleşik)",
    },
]


class LocalMcpManager:
    def __init__(self, base_dir: Path):
        self.base_dir = Path(base_dir)
        self.store_path = self.base_dir / "mcp_servers.json"
        self.lock = threading.RLock()
        self._auto_heal_broken_presets()

    def _load(self) -> List[Dict[str, Any]]:
        if not self.store_path.exists():
            return []
        try:
            data = json.loads(self.store_path.read_text(encoding="utf-8"))
            return data if isinstance(data, list) else []
        except Exception:
            return []

    def _save(self, items: List[Dict[str, Any]]) -> None:
        self.store_path.write_text(
            json.dumps(items, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _auto_heal_broken_presets(self) -> None:
        """Upgrades any previously saved broken npx/uvx or backslash-stripped preset entries."""
        with self.lock:
            items = self._load()
            if not items:
                return
            changed = False
            preset_by_name = {p["name"].lower(): p for p in MCP_PRESETS}
            for s in items:
                nm = str(s.get("name") or "").strip().lower()
                joined_args = " ".join(s.get("args") or [])
                has_broken_path = "C:Users" in joined_args or "C:proje" in joined_args
                is_failed_ext = s.get("command") in ("npx", "uvx") and (s.get("last_error") or has_broken_path)
                if nm in preset_by_name and (has_broken_path or is_failed_ext):
                    pr = preset_by_name[nm]
                    s["command"] = "python"
                    s["args"] = _split_win_args(pr["args"])
                    s["last_error"] = None
                    changed = True
            if changed:
                self._save(items)

    def list_servers(self) -> List[Dict[str, Any]]:
        with self.lock:
            return self._load()

    def list_presets(self) -> List[Dict[str, Any]]:
        return list(MCP_PRESETS)

    def upsert_server(
        self,
        name: str,
        transport: str = "stdio",
        command: str = "",
        args: Any = None,
        url: str = "",
        enabled: bool = True,
        server_id: Optional[str] = None,
    ) -> Dict[str, Any]:
        clean_name = (name or "").strip()[:60]
        if not clean_name:
            raise ValueError("MCP sunucu adı boş olamaz.")
        tr = "http" if str(transport).lower() == "http" else "stdio"

        if isinstance(args, str):
            arg_list = _split_win_args(args)
        elif isinstance(args, list):
            arg_list = [str(a).strip() for a in args if str(a).strip()]
        else:
            arg_list = []

        cmd = (command or "").strip()
        endpoint = (url or "").strip()
        if tr == "stdio" and not cmd:
            raise ValueError("stdio MCP sunucusu için komut gereklidir (örn: python, npx, uvx).")
        if tr == "http" and not endpoint.startswith(("http://", "https://")):
            raise ValueError("HTTP MCP sunucusu için geçerli http:// veya https:// adresi gereklidir.")

        with self.lock:
            items = self._load()
            sid = (server_id or "").strip() or f"mcp_{uuid.uuid4().hex[:8]}"
            existing = next((s for s in items if s.get("id") == sid), None)
            entry = {
                "id": sid,
                "name": clean_name,
                "transport": tr,
                "command": cmd,
                "args": arg_list,
                "url": endpoint,
                "enabled": bool(enabled),
                "tools": existing.get("tools", []) if existing else [],
                "last_checked": existing.get("last_checked") if existing else None,
                "last_error": None,
                "updated_at": datetime.now().isoformat(timespec="seconds"),
            }
            if existing:
                items = [entry if s.get("id") == sid else s for s in items]
            else:
                items.append(entry)
            self._save(items)

        # Auto-discover tools immediately on add so the user doesn't see an empty/broken card
        try:
            return self.discover_tools(sid)
        except Exception:
            with self.lock:
                return next((s for s in self._load() if s.get("id") == sid), entry)

    def toggle_server(self, server_id: str, enabled: bool) -> Optional[Dict[str, Any]]:
        with self.lock:
            items = self._load()
            target = None
            for s in items:
                if s.get("id") == server_id:
                    s["enabled"] = bool(enabled)
                    s["updated_at"] = datetime.now().isoformat(timespec="seconds")
                    target = s
                    break
            if target is not None:
                self._save(items)
            return target

    def delete_server(self, server_id: str) -> List[Dict[str, Any]]:
        with self.lock:
            items = [s for s in self._load() if s.get("id") != server_id]
            self._save(items)
            return items

    # ---- Low-level JSON-RPC 2.0 Transports ----

    def _rpc_http(self, url: str, method: str, params: Optional[Dict[str, Any]] = None, timeout: float = 10.0) -> Dict[str, Any]:
        payload = {
            "jsonrpc": "2.0",
            "id": int(time.time() * 1000) % 1000000,
            "method": method,
            "params": params or {},
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json", "Accept": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw = resp.read().decode("utf-8", errors="replace")
                data = json.loads(raw)
        except urllib.error.URLError as exc:
            raise RuntimeError(f"HTTP bağlantı hatası: {exc.reason}")
        except Exception as exc:
            raise RuntimeError(f"HTTP MCP yanıt hatası: {exc}")

        if "error" in data and data["error"]:
            err = data["error"]
            raise RuntimeError(err.get("message", str(err)) if isinstance(err, dict) else str(err))
        return data.get("result") or {}

    def _rpc_stdio(self, command: str, args: List[str], method: str, params: Optional[Dict[str, Any]] = None, timeout: float = 15.0) -> Dict[str, Any]:
        resolved_cmd = _resolve_command(command)
        argv = [resolved_cmd, *args]
        creationflags = 0x08000000 if os.name == "nt" else 0
        env = os.environ.copy()
        if os.name == "nt":
            env["PATH"] = r"C:\Program Files\nodejs" + os.pathsep + env.get("PATH", "")
            env["PYTHONIOENCODING"] = "utf-8"

        try:
            proc = subprocess.Popen(
                argv,
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                encoding="utf-8",
                errors="replace",
                shell=False,
                env=env,
                creationflags=creationflags,
            )
        except FileNotFoundError:
            raise RuntimeError(f"Komut bulunamadı: {command}")
        except Exception as exc:
            raise RuntimeError(f"MCP işlemi başlatılamadı: {exc}")

        try:
            init_req = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {},
                    "clientInfo": {"name": "YerelAI-Studio", "version": "13.0"},
                },
            }
            notif = {"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}
            call_req = {"jsonrpc": "2.0", "id": 2, "method": method, "params": params or {}}

            batch_in = "\n".join([json.dumps(init_req), json.dumps(notif), json.dumps(call_req)]) + "\n"
            stdout_data, stderr_data = proc.communicate(input=batch_in, timeout=timeout)

            target_resp = None
            for line in (stdout_data or "").splitlines():
                line = line.strip()
                if not line.startswith("{"):
                    continue
                try:
                    msg = json.loads(line)
                except Exception:
                    continue
                if msg.get("id") == 2:
                    target_resp = msg
                    break

            if target_resp is None:
                err_hint = (stderr_data or "").strip()[:320]
                raise RuntimeError(f"MCP sunucusundan JSON-RPC yanıtı alınamadı. {err_hint}".strip())

            if "error" in target_resp and target_resp["error"]:
                err = target_resp["error"]
                raise RuntimeError(err.get("message", str(err)) if isinstance(err, dict) else str(err))
            return target_resp.get("result") or {}
        except subprocess.TimeoutExpired:
            proc.kill()
            raise RuntimeError(f"MCP sunucusu {int(timeout)} sn içinde yanıt vermedi.")
        finally:
            try:
                if proc.poll() is None:
                    proc.terminate()
                    proc.wait(timeout=2)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass

    def _dispatch(self, srv: Dict[str, Any], method: str, params: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        if srv.get("transport") == "http":
            return self._rpc_http(srv.get("url", ""), method, params)
        return self._rpc_stdio(srv.get("command", ""), srv.get("args") or [], method, params)

    def discover_tools(self, server_id: str) -> Dict[str, Any]:
        with self.lock:
            items = self._load()
            srv = next((s for s in items if s.get("id") == server_id), None)
        if not srv:
            raise KeyError("MCP sunucusu bulunamadı.")

        try:
            res = self._dispatch(srv, "tools/list", {})
            raw_tools = res.get("tools") if isinstance(res, dict) else []
            tools = []
            for t in raw_tools or []:
                if isinstance(t, dict) and t.get("name"):
                    tools.append({
                        "name": str(t["name"]),
                        "description": str(t.get("description") or "")[:240],
                    })
            err_msg = None
        except Exception as exc:
            tools = srv.get("tools", [])
            err_msg = str(exc)

        with self.lock:
            items = self._load()
            for s in items:
                if s.get("id") == server_id:
                    s["tools"] = tools
                    s["last_checked"] = datetime.now().isoformat(timespec="seconds")
                    s["last_error"] = err_msg
                    srv = s
                    break
            self._save(items)

        if err_msg:
            raise RuntimeError(err_msg)
        return srv

    def call_tool(self, server_id: str, tool_name: str, arguments: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
        with self.lock:
            srv = next((s for s in self._load() if s.get("id") == server_id), None)
        if not srv:
            raise KeyError("MCP sunucusu bulunamadı.")
        if not srv.get("enabled"):
            raise RuntimeError("Bu MCP sunucusu pasif durumda; önce etkinleştirin.")
        res = self._dispatch(srv, "tools/call", {"name": tool_name, "arguments": arguments or {}})
        blocks = res.get("content") if isinstance(res, dict) else None
        text_parts = []
        if isinstance(blocks, list):
            for b in blocks:
                if isinstance(b, dict) and b.get("type") == "text":
                    text_parts.append(str(b.get("text") or ""))
                elif isinstance(b, dict):
                    text_parts.append(json.dumps(b, ensure_ascii=False))
        return {
            "ok": not bool(res.get("isError")) if isinstance(res, dict) else True,
            "tool": tool_name,
            "server": srv.get("name"),
            "text": "\n".join(text_parts).strip() if text_parts else json.dumps(res, ensure_ascii=False)[:4000],
            "raw": res,
        }

    def build_prompt_context(self) -> str:
        active = [s for s in self.list_servers() if s.get("enabled") and s.get("tools")]
        if not active:
            return ""
        lines = [
            "[BAĞLI YEREL MCP ARAÇLARI]",
            "Kullanıcı bu yerel araçlardan birini gerektiren bir işlem isterse, yanıtının sonuna şu XML bloğunu ekle ve sonucu bekle:",
            '<mcp_call>{"server_id":"SUNUCU_ID","tool":"ARAC_ADI","arguments":{}}</mcp_call>',
            "Sadece aşağıdaki aktif sunucular ve araçlar geçerlidir (her çağrı kullanıcı onayından geçer):",
        ]
        for s in active[:6]:
            sid = s.get("id", "")
            tool_bits = []
            for t in s.get("tools", [])[:12]:
                desc = (t.get("description") or "").strip()[:80]
                tool_bits.append(f"{t['name']}" + (f" ({desc})" if desc else ""))
            lines.append(f'- server_id="{sid}" ({s["name"]}): ' + "; ".join(tool_bits))
        return "\n".join(lines)

    def parse_mcp_calls(self, text: str) -> List[Dict[str, Any]]:
        if not text or "<mcp_call>" not in text:
            return []
        active_map = {s.get("id"): s for s in self.list_servers() if s.get("enabled")}
        if not active_map:
            return []
        calls: List[Dict[str, Any]] = []
        for match in re.finditer(r"<mcp_call>\s*(\{[\s\S]*?\})\s*</mcp_call>", text):
            try:
                obj = json.loads(match.group(1))
            except Exception:
                continue
            if not isinstance(obj, dict):
                continue
            sid = str(obj.get("server_id") or "").strip()
            tool_name = str(obj.get("tool") or "").strip()
            args = obj.get("arguments")
            if not isinstance(args, dict):
                args = {}
            srv = active_map.get(sid)
            if not srv and tool_name:
                srv = next((s for s in active_map.values() if any(t.get("name") == tool_name for t in s.get("tools", []))), None)
            if not srv or not tool_name:
                continue
            known_tools = {t.get("name") for t in srv.get("tools", [])}
            if known_tools and tool_name not in known_tools:
                continue
            calls.append({
                "id": uuid.uuid4().hex[:8],
                "server_id": srv["id"],
                "server_name": srv.get("name", srv["id"]),
                "tool": tool_name,
                "arguments": args,
            })
            if len(calls) >= 3:
                break
        return calls
