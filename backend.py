import asyncio
import base64
import gc
import hashlib
import hmac
import html as html_lib
import io
import ipaddress
import json
import logging
import mimetypes
import os
import re
import secrets
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import uuid
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import httpx
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from modules import exporters as exp_mgr
from modules import extensions as ext_mgr
from modules.mcp_client import LocalMcpManager
from modules.tunnel import tunnel_mgr
from modules.workspace import LocalWorkspaceManager

BASE_DIR = Path(__file__).resolve().parent
mcp_mgr = LocalMcpManager(BASE_DIR)
ws_mgr = LocalWorkspaceManager(BASE_DIR / "data")
MODELS_DIR = BASE_DIR / "models"
GGUF_DIR = MODELS_DIR / "gguf"
LORAS_DIR = MODELS_DIR / "loras"
OUTPUTS_DIR = BASE_DIR / "outputs"
UPLOADS_DIR = OUTPUTS_DIR / "uploads"
GENERATED_DIR = OUTPUTS_DIR / "generated"
COLAB_DIR = BASE_DIR / "colab"
FRONTEND_DIR = BASE_DIR / "frontend"
DATA_DIR = BASE_DIR / "data"
LIBRARY_DIR = DATA_DIR / "library"
RAG_INDEX_DIR = DATA_DIR / "rag_index"
RAG_META_PATH = RAG_INDEX_DIR / "meta.json"
RAG_EMB_PATH = RAG_INDEX_DIR / "embeddings.npy"
MEMORIES_PATH = DATA_DIR / "memories.json"
for _d in (LIBRARY_DIR, RAG_INDEX_DIR, GENERATED_DIR):
    _d.mkdir(parents=True, exist_ok=True)

CONFIG_PATH = BASE_DIR / "config.json"
REGISTRY_PATH = MODELS_DIR / "registry.json"
LORA_REGISTRY_PATH = LORAS_DIR / "registry.json"
SESSIONS_PATH = OUTPUTS_DIR / "sessions.json"
DATASET_PATH = OUTPUTS_DIR / "train_dataset.jsonl"
FILES_META_PATH = OUTPUTS_DIR / "files_meta.json"
LOG_PATH = BASE_DIR / "backend.log"
LLAMA_LOG_PATH = BASE_DIR / "llama_server.log"

LLAMA_SERVER_BIN = Path(
    os.environ.get(
        "LLAMA_SERVER_BIN",
        r"C:\Users\Salih\.unsloth\llama.cpp\build\bin\Release\llama-server.exe",
    )
)
LLAMA_SERVER_PORT = int(os.environ.get("LLAMA_SERVER_PORT", "8071"))
LLAMA_SERVER_URL = f"http://127.0.0.1:{LLAMA_SERVER_PORT}"

OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
LORAS_DIR.mkdir(parents=True, exist_ok=True)
GGUF_DIR.mkdir(parents=True, exist_ok=True)
CHAT_LOGS_DIR = BASE_DIR / "chat_logs"
CHAT_LOGS_DIR.mkdir(parents=True, exist_ok=True)


def _append_chat_archive(
    session_id: str,
    model_id: str,
    user_text: str,
    assistant_text: str,
    thinking_text: str = "",
    temperature: float = 0.73,
    auto_persona: str = "",
    web_searched: bool = False,
    tokens: int = 0,
    tps: float = 0.0,
) -> None:
    """Append every completed SEN.AI turn locally for conversation audit & future fine-tuning dataset curation."""
    if not (user_text or "").strip() or not (assistant_text or "").strip():
        return
    try:
        ts = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        rec = {
            "timestamp": ts,
            "session_id": session_id or "",
            "model": model_id or "",
            "temperature": round(float(temperature), 2),
            "auto_persona": auto_persona or "",
            "web_searched": bool(web_searched),
            "tokens": int(tokens or 0),
            "tps": round(float(tps or 0.0), 1),
            "user": user_text.strip(),
            "thinking": (thinking_text or "").strip(),
            "assistant": assistant_text.strip(),
        }
        jsonl_path = CHAT_LOGS_DIR / "sen_ai_conversations.jsonl"
        with open(jsonl_path, "a", encoding="utf-8") as fp:
            fp.write(json.dumps(rec, ensure_ascii=False) + "\n")

        md_path = CHAT_LOGS_DIR / "sen_ai_readable.md"
        meta_bits = [f"Model: `{model_id}`", f"Temp: `{rec['temperature']}`"]
        if auto_persona:
            meta_bits.append(f"Uzman: `{auto_persona}`")
        if web_searched:
            meta_bits.append("Web: `Evet`")
        if tokens:
            meta_bits.append(f"`{tps} tok/sn · {tokens} tok`")
        md_entry = (
            f"\n---\n### [{ts}] {' · '.join(meta_bits)}\n"
            f"**Kullanıcı:** {user_text.strip()}\n\n"
            f"**SEN.AI:** {assistant_text.strip()}\n"
        )
        with open(md_path, "a", encoding="utf-8") as fp:
            fp.write(md_entry)
    except Exception:
        pass

from logging.handlers import RotatingFileHandler


class _QuietStatusAccessFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        msg = record.getMessage()
        return '"/api/status ' not in msg and 'GET /api/status ' not in msg


_file_handler = RotatingFileHandler(LOG_PATH, maxBytes=2 * 1024 * 1024, backupCount=2, encoding="utf-8")
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        _file_handler,
        logging.StreamHandler(),
    ],
)
logging.getLogger("uvicorn.access").addFilter(_QuietStatusAccessFilter())
logger = logging.getLogger("yerelai")

THINKING_EFFORT_BUDGETS = {
    "off": 0,
    "low": 256,
    "medium": 768,
    "high": 2048,
}

CODE_AND_TEXT_EXTS = {
    ".py", ".js", ".ts", ".jsx", ".tsx", ".html", ".css", ".scss",
    ".json", ".sql", ".md", ".txt", ".ps1", ".bat", ".sh",
    ".yaml", ".yml", ".xml", ".ini", ".cfg", ".log", ".env",
}
EXCEL_EXTS = {".xlsx", ".xls", ".csv"}
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp"}
AUDIO_EXTS = {".wav", ".mp3", ".ogg", ".flac", ".m4a", ".webm"}


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def save_json(path: Path, data: Any) -> None:
    tmp = path.with_suffix(".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    tmp.replace(path)


def _clamp(val: float, lo: float, hi: float) -> float:
    return max(lo, min(hi, float(val)))


AUTH_COOKIE_NAME = "yerelai_session"


def _hash_pin(pin: str, salt_hex: Optional[str] = None) -> str:
    salt = bytes.fromhex(salt_hex) if salt_hex else secrets.token_bytes(16)
    dk = hashlib.pbkdf2_hmac("sha256", pin.encode("utf-8"), salt, 120_000)
    return f"{salt.hex()}${dk.hex()}"


def _verify_pin(pin: str, stored_hash: str) -> bool:
    if not stored_hash or "$" not in stored_hash:
        return False
    salt_hex, expected_hex = stored_hash.split("$", 1)
    try:
        candidate = _hash_pin(pin, salt_hex).split("$", 1)[1]
        return hmac.compare_digest(candidate, expected_hex)
    except Exception:
        return False


def _get_auth_secret(cfg: Dict[str, Any]) -> str:
    sec = cfg.get("auth_secret")
    if sec and isinstance(sec, str) and len(sec) >= 32:
        return sec
    sec = secrets.token_hex(32)
    cfg["auth_secret"] = sec
    save_json(CONFIG_PATH, cfg)
    return sec


def _make_auth_token(cfg: Dict[str, Any]) -> str:
    secret = _get_auth_secret(cfg)
    pin_h = cfg.get("access_pin_hash", "")
    ts = str(int(time.time()))
    sig = hmac.new(secret.encode("utf-8"), f"{ts}:{pin_h[:16]}".encode("utf-8"), hashlib.sha256).hexdigest()
    return f"{ts}.{sig}"


def _verify_auth_token(token: str, cfg: Dict[str, Any]) -> bool:
    if not token or "." not in token:
        return False
    ts, sig = token.split(".", 1)
    if not ts.isdigit():
        return False
    if abs(time.time() - int(ts)) > 30 * 86400:
        return False
    secret = _get_auth_secret(cfg)
    pin_h = cfg.get("access_pin_hash", "")
    expected = hmac.new(secret.encode("utf-8"), f"{ts}:{pin_h[:16]}".encode("utf-8"), hashlib.sha256).hexdigest()
    return hmac.compare_digest(sig, expected)


def _is_local_request(request: Request) -> bool:
    # Cloudflare tunnel always forwards CF-Connecting-IP / X-Forwarded-For
    if request.headers.get("cf-connecting-ip") or request.headers.get("x-forwarded-for"):
        return False
    host = request.client.host if request.client else ""
    return host in ("127.0.0.1", "::1", "localhost")


def _resolve_local_hf_snapshot(repo_id: str) -> Optional[Path]:
    """Return local HuggingFace cache snapshot path if config + non-empty weights exist."""
    hf_home = Path(os.environ.get("HF_HOME", Path.home() / ".cache" / "huggingface"))
    cache_name = "models--" + repo_id.replace("/", "--")
    snaps_dir = hf_home / "hub" / cache_name / "snapshots"
    if not snaps_dir.exists():
        return None
    candidates = sorted(
        [p for p in snaps_dir.iterdir() if p.is_dir() and (p / "config.json").exists()],
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    for cand in candidates:
        weight_files = list(cand.glob("*.safetensors"))
        if not weight_files:
            continue
        all_valid = True
        for wf in weight_files:
            try:
                resolved = wf.resolve(strict=True)
                if resolved.stat().st_size <= 1_000_000:
                    all_valid = False
                    break
            except OSError:
                all_valid = False
                break
        if all_valid:
            return cand
    return None


def _resolve_local_gguf(model_meta: Dict[str, Any]) -> Optional[Tuple[Path, Path]]:
    """Return (gguf_path, mmproj_path) if both files exist cleanly on disk."""
    gguf_dir_name = model_meta.get("gguf_dir") or ""
    gguf_file = model_meta.get("gguf_file") or ""
    mmproj_file = model_meta.get("mmproj_file") or ""
    if not (gguf_dir_name and gguf_file and mmproj_file):
        return None
    folder = GGUF_DIR / gguf_dir_name
    m_path = folder / gguf_file
    mm_path = folder / mmproj_file
    try:
        if m_path.exists() and mm_path.exists():
            if m_path.stat().st_size > 500_000_000 and mm_path.stat().st_size > 100_000_000:
                return m_path, mm_path
    except OSError:
        return None
    return None


def _resolve_lora_type(lora_id: str) -> Tuple[Optional[str], Optional[Path]]:
    """Detect whether lora_id is a GGUF LoRA or PyTorch PEFT LoRA."""
    if not lora_id:
        return None, None
    lora_dir = LORAS_DIR / os.path.basename(lora_id)
    if not lora_dir.exists():
        return None, None
    ggufs = sorted(lora_dir.glob("*.gguf"))
    if ggufs:
        return "gguf", ggufs[0]
    if (lora_dir / "adapter_config.json").exists():
        return "pytorch", lora_dir
    return None, None


def _query_nvidia_smi() -> Dict[str, Any]:
    """Query GPU device name, total/used VRAM, utilization and per-PID compute memory via nvidia-smi."""
    info: Dict[str, Any] = {
        "available": False,
        "device": "CPU",
        "system_used_mb": 0,
        "total_mb": 0,
        "gpu_util": 0,
        "pid_mem": {},
    }
    try:
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        out_gpu = subprocess.check_output(
            ["nvidia-smi", "--query-gpu=name,memory.used,memory.total,utilization.gpu", "--format=csv,noheader,nounits"],
            timeout=2.0,
            creationflags=flags,
            text=True,
        ).strip()
        if out_gpu:
            parts = [p.strip() for p in out_gpu.splitlines()[0].split(",")]
            if len(parts) >= 3:
                info["available"] = True
                info["device"] = parts[0]
                info["system_used_mb"] = int(float(parts[1]))
                info["total_mb"] = int(float(parts[2]))
                if len(parts) >= 4 and "N/A" not in parts[3]:
                    info["gpu_util"] = int(float(parts[3]))

        out_apps = subprocess.check_output(
            ["nvidia-smi", "--query-compute-apps=pid,used_memory", "--format=csv,noheader,nounits"],
            timeout=2.0,
            creationflags=flags,
            text=True,
        ).strip()
        for line in out_apps.splitlines():
            cols = [c.strip() for c in line.split(",")]
            if len(cols) >= 2:
                try:
                    pid_val = int(cols[0])
                    mem_str = cols[1]
                    if mem_str and "N/A" not in mem_str:
                        info["pid_mem"][pid_val] = int(float(mem_str))
                except ValueError:
                    continue
    except Exception:
        pass
    return info


def _list_lora_adapters() -> List[Dict[str, Any]]:
    """Combine registry.json entries with auto-discovered adapters in models/loras/."""
    reg = load_json(LORA_REGISTRY_PATH, {"adapters": []})
    by_id: Dict[str, Dict[str, Any]] = {}
    for item in reg.get("adapters", []):
        if isinstance(item, dict) and item.get("id"):
            by_id[item["id"]] = dict(item)

    if LORAS_DIR.exists():
        for sub in sorted(LORAS_DIR.iterdir()):
            if not sub.is_dir():
                continue
            has_peft = (sub / "adapter_config.json").exists()
            has_gguf = any(sub.glob("*.gguf"))
            if has_peft or has_gguf:
                aid = sub.name
                entry = by_id.setdefault(aid, {
                    "id": aid,
                    "name": aid.replace("_", " ").replace("-", " ").title(),
                    "description": "Colab / Unsloth ile eğitilmiş yerel LoRA adaptörü.",
                    "base_model": "",
                    "default_scale": 1.0,
                })
                entry["path"] = str(sub)
                entry["available"] = True
    return list(by_id.values())


class EngineManager:
    """Thread-safe on-demand Gemma 4 GPU engine (GGUF Turbo llama-server + PyTorch LoRA fallback)."""

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.state: str = "unloaded"  # unloaded | loading | ready | generating | unloading | error
        self.engine_backend: str = "none"  # none | gguf_turbo | pytorch_bnb
        self.active_model_id: Optional[str] = None
        self.active_lora_id: str = ""
        self.applied_lora_scale: float = 1.0
        self.load_message: str = "GPU beklemede (model yüklü değil)"
        self.last_activity: float = 0.0
        self.model: Any = None
        self.processor: Any = None
        self.torch: Any = None
        self.llama_proc: Optional[subprocess.Popen] = None
        self._llama_log_fp: Any = None
        self._baseline_vram_mb: int = 0
        self._vram_cache_ts: float = 0.0
        self._vram_cache_data: Dict[str, Any] = {}
        self.active_profile: str = "turbo"
        self.active_context_length: int = 32768
        self.detected_vram_mb: int = 0
        self.stop_event = threading.Event()
        self.channel_tokens: Dict[str, int] = {}
        self.download_lock = threading.RLock()
        self.download_cancel_event = threading.Event()
        self.download_thread: Optional[threading.Thread] = None
        self.download_state: Dict[str, Any] = {
            "active": False,
            "status": "idle",  # idle | downloading | completed | cancelled | error
            "model_id": None,
            "model_name": "",
            "file_name": "",
            "file_index": 0,
            "file_count": 0,
            "downloaded_bytes": 0,
            "total_bytes": 0,
            "percent": 0.0,
            "speed_mbps": 0.0,
            "eta_seconds": 0,
            "error": "",
        }

    def get_download_status(self) -> Dict[str, Any]:
        with self.download_lock:
            return dict(self.download_state)

    def _get_remote_file_size(self, repo_id: str, filename: str) -> int:
        from huggingface_hub import hf_hub_url

        url = hf_hub_url(repo_id=repo_id, filename=filename)
        try:
            with httpx.Client(follow_redirects=True, timeout=20.0) as client:
                resp = client.head(url)
                cl = resp.headers.get("content-length") or resp.headers.get("x-linked-size")
                if cl and cl.isdigit():
                    return int(cl)
        except Exception as exc:
            logger.warning("HEAD size check failed for %s/%s: %s", repo_id, filename, exc)
        try:
            from huggingface_hub import HfApi

            infos = HfApi().get_paths_info(repo_id=repo_id, paths=[filename], repo_type="model")
            if infos and getattr(infos[0], "size", None):
                return int(infos[0].size)
        except Exception as exc:
            logger.warning("HfApi.get_paths_info failed for %s/%s: %s", repo_id, filename, exc)
        return 0

    def _download_gguf_model_files(self, model_meta: Dict[str, Any], update_load_msg: bool = False) -> Tuple[Path, Path]:
        from huggingface_hub import hf_hub_url

        repo_id = model_meta["gguf_repo"]
        gguf_dir = GGUF_DIR / model_meta["gguf_dir"]
        gguf_dir.mkdir(parents=True, exist_ok=True)
        files = [model_meta["gguf_file"], model_meta["mmproj_file"]]
        short_name = "Gemma 4 E4B" if "e4b" in model_meta["id"] else "Gemma 4 E2B"

        self.download_cancel_event.clear()
        with self.download_lock:
            self.download_state.update({
                "active": True,
                "status": "downloading",
                "model_id": model_meta["id"],
                "model_name": short_name,
                "file_name": files[0],
                "file_index": 1,
                "file_count": len(files),
                "downloaded_bytes": 0,
                "total_bytes": 0,
                "percent": 0.0,
                "speed_mbps": 0.0,
                "eta_seconds": 0,
                "error": "",
            })

        try:
            file_sizes = [self._get_remote_file_size(repo_id, fn) for fn in files]
            total_bytes = sum(s for s in file_sizes if s > 0)

            completed_before = 0
            for idx, fn in enumerate(files):
                target = gguf_dir / fn
                part = gguf_dir / f"{fn}.part"
                expected = file_sizes[idx]
                if target.exists() and target.stat().st_size > 1_000_000 and (expected == 0 or target.stat().st_size == expected):
                    completed_before += target.stat().st_size
                elif part.exists():
                    completed_before += part.stat().st_size

            with self.download_lock:
                self.download_state["total_bytes"] = total_bytes
                self.download_state["downloaded_bytes"] = completed_before
                if total_bytes > 0:
                    self.download_state["percent"] = round(min(99.9, (completed_before / total_bytes) * 100.0), 1)

            result_paths: List[Path] = []
            accumulated_done = 0
            ema_speed = 0.0

            with httpx.Client(follow_redirects=True, timeout=httpx.Timeout(30.0, read=90.0)) as client:
                for idx, fn in enumerate(files):
                    target = gguf_dir / fn
                    part = gguf_dir / f"{fn}.part"
                    expected = file_sizes[idx]

                    if target.exists() and target.stat().st_size > 1_000_000 and (expected == 0 or target.stat().st_size == expected):
                        accumulated_done += target.stat().st_size
                        result_paths.append(target)
                        continue

                    existing_part = part.stat().st_size if part.exists() else 0
                    if expected > 0 and existing_part >= expected:
                        os.replace(part, target)
                        accumulated_done += target.stat().st_size
                        result_paths.append(target)
                        continue

                    url = hf_hub_url(repo_id=repo_id, filename=fn)
                    headers = {"Range": f"bytes={existing_part}-"} if existing_part > 0 else {}
                    logger.info("Downloading %s (%d/%d) from %s (resume=%d)", fn, idx + 1, len(files), repo_id, existing_part)

                    with self.download_lock:
                        self.download_state["file_name"] = fn
                        self.download_state["file_index"] = idx + 1
                    if update_load_msg:
                        with self.lock:
                            self.load_message = f"{short_name} indiriliyor ({idx + 1}/{len(files)})..."

                    with client.stream("GET", url, headers=headers) as resp:
                        if resp.status_code not in (200, 206):
                            raise RuntimeError(f"İndirme HTTP {resp.status_code} ({fn})")

                        is_resume = resp.status_code == 206 and existing_part > 0
                        file_written = existing_part if is_resume else 0
                        if not is_resume:
                            cl_hdr = resp.headers.get("content-length")
                            if expected == 0 and cl_hdr and cl_hdr.isdigit():
                                expected = int(cl_hdr)
                                file_sizes[idx] = expected
                                total_bytes = sum(s for s in file_sizes if s > 0)

                        mode = "ab" if is_resume else "wb"
                        last_t = time.perf_counter()
                        last_bytes = file_written
                        with open(part, mode) as fp:
                            for chunk in resp.iter_bytes(chunk_size=512 * 1024):
                                if self.download_cancel_event.is_set():
                                    raise InterruptedError("İndirme kullanıcı tarafından iptal edildi.")
                                if not chunk:
                                    continue
                                fp.write(chunk)
                                file_written += len(chunk)

                                now_t = time.perf_counter()
                                dt = now_t - last_t
                                if dt >= 0.25:
                                    inst_mbps = ((file_written - last_bytes) / (1024 * 1024)) / max(dt, 1e-3)
                                    ema_speed = inst_mbps if ema_speed <= 0 else (0.35 * inst_mbps + 0.65 * ema_speed)
                                    last_t = now_t
                                    last_bytes = file_written

                                    cur_total_done = accumulated_done + file_written
                                    pct = round(min(99.9, (cur_total_done / total_bytes) * 100.0), 1) if total_bytes > 0 else 0.0
                                    rem_bytes = max(0, total_bytes - cur_total_done) if total_bytes > 0 else 0
                                    eta_sec = int(rem_bytes / max(ema_speed * 1024 * 1024, 1.0)) if ema_speed > 0.05 and rem_bytes > 0 else 0

                                    with self.download_lock:
                                        self.download_state.update({
                                            "downloaded_bytes": cur_total_done,
                                            "total_bytes": total_bytes,
                                            "percent": pct,
                                            "speed_mbps": round(ema_speed, 1),
                                            "eta_seconds": eta_sec,
                                        })
                                    if update_load_msg:
                                        with self.lock:
                                            self.load_message = f"{short_name} indiriliyor: %{pct:.1f} ({ema_speed:.1f} MB/sn)"

                    os.replace(part, target)
                    accumulated_done += target.stat().st_size
                    result_paths.append(target)

            with self.download_lock:
                self.download_state.update({
                    "active": False,
                    "status": "completed",
                    "downloaded_bytes": accumulated_done,
                    "total_bytes": max(total_bytes, accumulated_done),
                    "percent": 100.0,
                    "speed_mbps": 0.0,
                    "eta_seconds": 0,
                    "error": "",
                })
            logger.info("GGUF download completed for %s (%d bytes)", model_meta["id"], accumulated_done)
            return result_paths[0], result_paths[1]
        except InterruptedError as exc:
            with self.download_lock:
                self.download_state.update({
                    "active": False,
                    "status": "cancelled",
                    "speed_mbps": 0.0,
                    "eta_seconds": 0,
                    "error": str(exc),
                })
            logger.info("GGUF download cancelled for %s", model_meta["id"])
            raise
        except Exception as exc:
            with self.download_lock:
                self.download_state.update({
                    "active": False,
                    "status": "error",
                    "speed_mbps": 0.0,
                    "eta_seconds": 0,
                    "error": str(exc),
                })
            logger.exception("GGUF download failed for %s", model_meta["id"])
            raise

    def start_model_download(self, model_id: str) -> Dict[str, Any]:
        reg = load_json(REGISTRY_PATH, {"models": []})
        model_meta = next((m for m in reg.get("models", []) if m["id"] == model_id), None)
        if not model_meta:
            raise ValueError(f"Model bulunamadı: {model_id}")
        if not model_meta.get("gguf_repo"):
            raise ValueError("Bu model için GGUF indirme kaynağı tanımlı değil.")

        with self.download_lock:
            if self.download_state.get("active"):
                return dict(self.download_state)

        if _resolve_local_gguf(model_meta) is not None:
            short_name = "Gemma 4 E4B" if "e4b" in model_id else "Gemma 4 E2B"
            with self.download_lock:
                self.download_state.update({
                    "active": False,
                    "status": "completed",
                    "model_id": model_id,
                    "model_name": short_name,
                    "percent": 100.0,
                    "speed_mbps": 0.0,
                    "eta_seconds": 0,
                    "error": "",
                })
                return dict(self.download_state)

        def _worker():
            try:
                self._download_gguf_model_files(model_meta, update_load_msg=False)
            except Exception:
                pass

        t = threading.Thread(target=_worker, daemon=True)
        self.download_thread = t
        t.start()
        time.sleep(0.08)
        return self.get_download_status()

    def cancel_model_download(self) -> Dict[str, Any]:
        with self.download_lock:
            if self.download_state.get("active"):
                self.download_cancel_event.set()
                self.download_state["status"] = "cancelled"
        return self.get_download_status()

    def touch(self) -> None:
        self.last_activity = time.time()

    def get_vram_info(self, force: bool = False) -> Dict[str, Any]:
        now = time.time()
        if not force and self._vram_cache_data and (now - self._vram_cache_ts) < 1.5:
            return dict(self._vram_cache_data)

        smi = _query_nvidia_smi()
        if not smi["available"]:
            # Fall back to torch check only if nvidia-smi failed
            if self.torch is None:
                try:
                    import torch as _torch
                    self.torch = _torch
                except Exception:
                    pass
            if self.torch is not None and self.torch.cuda.is_available():
                smi["available"] = True
                smi["device"] = self.torch.cuda.get_device_name(0)
                smi["total_mb"] = int(self.torch.cuda.get_device_properties(0).total_memory / (1024 * 1024))
                smi["system_used_mb"] = int(self.torch.cuda.memory_reserved(0) / (1024 * 1024))

        if not smi["available"]:
            res = {
                "available": False,
                "device": "CPU",
                "used_mb": 0,
                "model_mb": 0,
                "system_used_mb": 0,
                "other_used_mb": 0,
                "allocated_mb": 0,
                "reserved_mb": 0,
                "total_mb": 0,
                "profile": "low_vram",
                "profile_label": "CPU Modu",
                "detected_vram_mb": 0,
                "engine_backend": self.engine_backend,
            }
            self._vram_cache_ts = now
            self._vram_cache_data = res
            return res

        total = int(smi["total_mb"])
        sys_used = int(smi["system_used_mb"])
        model_mb = 0
        reserved = sys_used

        if self.engine_backend == "gguf_turbo" and self.llama_proc is not None and self.llama_proc.poll() is None:
            pid_mem = smi["pid_mem"].get(self.llama_proc.pid, 0)
            if pid_mem > 0:
                model_mb = pid_mem
            elif self.state in ("ready", "generating"):
                diff = sys_used - self._baseline_vram_mb
                model_mb = diff if diff > 150 else 0
        elif self.engine_backend == "pytorch_bnb" and self.torch is not None and self.torch.cuda.is_available():
            model_mb = int(self.torch.cuda.memory_allocated(0) / (1024 * 1024))
            reserved = int(self.torch.cuda.memory_reserved(0) / (1024 * 1024))

        other_used = max(0, sys_used - model_mb)
        if self.detected_vram_mb == 0 and total > 0:
            self.detected_vram_mb = total
            cfg = load_json(CONFIG_PATH, {})
            user_prof = cfg.get("gpu_profile", "auto")
            if user_prof in ("turbo", "low_vram"):
                self.active_profile = user_prof
            else:
                self.active_profile = "low_vram" if total <= 5000 else "turbo"

        res = {
            "available": True,
            "device": smi["device"],
            "used_mb": model_mb,
            "model_mb": model_mb,
            "system_used_mb": sys_used,
            "other_used_mb": other_used,
            "allocated_mb": model_mb,
            "reserved_mb": reserved,
            "total_mb": total,
            "profile": self.active_profile,
            "profile_label": "Low-VRAM (4GB Uyumlu)" if self.active_profile == "low_vram" else "Turbo GPU (8GB+)",
            "detected_vram_mb": self.detected_vram_mb or total,
            "gpu_util": int(smi.get("gpu_util", 0)),
            "engine_backend": self.engine_backend,
        }
        self._vram_cache_ts = now
        self._vram_cache_data = res
        return res

    def get_status(self) -> Dict[str, Any]:
        cfg = load_json(CONFIG_PATH, {})
        timeout_min = float(cfg.get("idle_timeout_minutes", 15.0))
        idle_sec = 0.0
        remaining_sec = 0.0
        if self.state == "ready" and self.last_activity > 0:
            idle_sec = max(0.0, time.time() - self.last_activity)
            remaining_sec = max(0.0, timeout_min * 60.0 - idle_sec)
        vram = self.get_vram_info()
        return {
            "state": self.state,
            "engine_backend": self.engine_backend,
            "resolved_profile": self.active_profile,
            "active_model_id": self.active_model_id,
            "active_lora_id": self.active_lora_id,
            "lora_scale": self.applied_lora_scale,
            "load_message": self.load_message,
            "detail": self.load_message,
            "idle_seconds": round(idle_sec, 1),
            "remaining_seconds": round(remaining_sec, 1),
            "idle_remaining_sec": round(remaining_sec, 1),
            "idle_timeout_minutes": timeout_min,
            "context_length": int(self.active_context_length or cfg.get("context_length", 32768)),
            "vram": vram,
            "download": self.get_download_status(),
        }

    def unload_model(self) -> None:
        with self.lock:
            if self.state == "generating":
                raise RuntimeError("Aktif yanıt üretimi devam ederken VRAM boşaltılamaz.")
            self._unload_locked()

    def _unload_locked(self) -> None:
        self.state = "unloading"
        self.load_message = "VRAM boşaltılıyor..."
        try:
            if self.llama_proc is not None:
                try:
                    if self.llama_proc.poll() is None:
                        self.llama_proc.terminate()
                        try:
                            self.llama_proc.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            self.llama_proc.kill()
                            self.llama_proc.wait(timeout=3)
                except Exception as exc:
                    logger.warning("llama-server termination warning: %s", exc)
                self.llama_proc = None
            if self._llama_log_fp is not None:
                try:
                    self._llama_log_fp.close()
                except Exception:
                    pass
                self._llama_log_fp = None

            if self.model is not None:
                del self.model
                self.model = None
            if self.processor is not None:
                del self.processor
                self.processor = None
            gc.collect()
            if self.torch is not None and self.torch.cuda.is_available():
                self.torch.cuda.empty_cache()
                self.torch.cuda.ipc_collect()
        finally:
            self.engine_backend = "none"
            self.active_model_id = None
            self.active_lora_id = ""
            self.last_activity = 0.0
            self._vram_cache_ts = 0.0
            self.state = "unloaded"
            self.load_message = "GPU beklemede (VRAM temizlendi)"
            logger.info("Model unloaded and VRAM cleared.")

    def _should_use_gguf(self, model_meta: Dict[str, Any], lora_id: str) -> bool:
        if not LLAMA_SERVER_BIN.exists() or not model_meta.get("gguf_repo"):
            return False
        lora_kind, _ = _resolve_lora_type(lora_id)
        if lora_kind == "pytorch":
            return False
        return True

    def load_model(self, model_id: str, lora_id: str = "", lora_scale: float = 1.0, gpu_profile: Optional[str] = None) -> None:
        with self.lock:
            registry = load_json(REGISTRY_PATH, {"models": []})
            model_meta = next((m for m in registry.get("models", []) if m["id"] == model_id), None)
            if not model_meta:
                self.state = "error"
                self.load_message = f"Model bulunamadı: {model_id}"
                raise ValueError(self.load_message)

            use_gguf = self._should_use_gguf(model_meta, lora_id)
            target_backend = "gguf_turbo" if use_gguf else "pytorch_bnb"
            is_alive = (
                (target_backend == "gguf_turbo" and self.llama_proc is not None and self.llama_proc.poll() is None)
                or (target_backend == "pytorch_bnb" and self.model is not None)
            )
            if (
                self.state == "ready"
                and self.engine_backend == target_backend
                and self.active_model_id == model_id
                and self.active_lora_id == (lora_id or "")
                and abs(self.applied_lora_scale - float(lora_scale)) < 1e-3
                and is_alive
            ):
                self.touch()
                return
            if self.state in ("loading", "generating"):
                return

            if self.llama_proc is not None or self.model is not None:
                self._unload_locked()

            self.state = "loading"
            self.engine_backend = target_backend
            self.active_model_id = model_id
            self.active_lora_id = lora_id or ""
            self.applied_lora_scale = float(lora_scale)
            self.load_message = "GPU motoru hazırlanıyor..."

        try:
            smi = _query_nvidia_smi()
            total_vram_mb = int(smi["total_mb"])
            self._baseline_vram_mb = int(smi["system_used_mb"])
            cfg = load_json(CONFIG_PATH, {})
            user_prof = gpu_profile or cfg.get("gpu_profile", "auto")
            if user_prof in ("turbo", "low_vram"):
                profile = user_prof
            elif total_vram_mb > 0 and total_vram_mb <= 5000:
                profile = "low_vram"
            else:
                profile = "turbo"

            self.active_profile = profile
            self.detected_vram_mb = total_vram_mb
            profile_tag = "Low-VRAM 4GB" if profile == "low_vram" else "Turbo GPU"

            if use_gguf:
                paths = _resolve_local_gguf(model_meta)
                if paths is None:
                    paths = self._download_gguf_model_files(model_meta, update_load_msg=True)

                gguf_path, mmproj_path = paths
                with self.lock:
                    self.load_message = f"GGUF Turbo CUDA sunucusu başlatılıyor ({model_meta['name']})..."

                ngl_val = "auto" if (profile == "low_vram" and int(model_meta.get("vram_estimate_mb", 3400)) > 4200) else "all"
                cfg_ctx = int(cfg.get("context_length") or (8192 if profile == "low_vram" else 32768))
                if cfg_ctx not in (8192, 16384, 32768):
                    cfg_ctx = 8192 if profile == "low_vram" else 32768
                if profile == "low_vram" and cfg_ctx > 16384:
                    cfg_ctx = 8192
                self.active_context_length = cfg_ctx
                ctx_val = str(cfg_ctx)

                cmd = [
                    str(LLAMA_SERVER_BIN),
                    "-m", str(gguf_path),
                    "-mm", str(mmproj_path),
                    "--host", "127.0.0.1",
                    "--port", str(LLAMA_SERVER_PORT),
                    "-ngl", ngl_val,
                    "-fa", "on",
                    "-ctk", "q8_0",
                    "-ctv", "q8_0",
                    "-b", "2048",
                    "-ub", "1024",
                    "--cache-reuse", "256",
                    "-c", ctx_val,
                    "-np", "1",
                    "--jinja",
                    "--reasoning-format", "deepseek",
                    "--no-webui",
                ]
                lora_note = ""
                lora_kind, lora_path = _resolve_lora_type(lora_id)
                if lora_kind == "gguf" and lora_path is not None:
                    cmd.extend(["--lora-scaled", f"{lora_path}:{float(lora_scale):.2f}"])
                    lora_note = f" + LoRA:{lora_id} ({lora_scale:.1f}x)"

                llama_env = os.environ.copy()
                extra_dll_dirs = [
                    str(LLAMA_SERVER_BIN.parent),
                    str(Path(sys.prefix) / "Lib" / "site-packages" / "torch" / "lib"),
                ]
                existing_dll_dirs = [d for d in extra_dll_dirs if Path(d).exists()]
                if existing_dll_dirs:
                    llama_env["PATH"] = os.pathsep.join(existing_dll_dirs) + os.pathsep + llama_env.get("PATH", "")

                pre_smi = _query_nvidia_smi()
                if pre_smi.get("available"):
                    self._baseline_vram_mb = int(pre_smi["system_used_mb"])

                log_fp = open(LLAMA_LOG_PATH, "w", encoding="utf-8", errors="replace")
                flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
                proc = subprocess.Popen(
                    cmd,
                    stdout=log_fp,
                    stderr=subprocess.STDOUT,
                    env=llama_env,
                    creationflags=flags,
                )
                with self.lock:
                    self.llama_proc = proc
                    self._llama_log_fp = log_fp

                deadline = time.time() + 90.0
                healthy = False
                while time.time() < deadline:
                    if proc.poll() is not None:
                        try:
                            log_fp.flush()
                        except Exception:
                            pass
                        tail = ""
                        try:
                            tail = LLAMA_LOG_PATH.read_text(encoding="utf-8", errors="replace")[-1200:]
                        except Exception:
                            pass
                        raise RuntimeError(f"llama-server çıkış kodu {proc.returncode}: {tail.strip()}")
                    try:
                        r = httpx.get(f"{LLAMA_SERVER_URL}/health", timeout=1.5)
                        if r.status_code == 200:
                            healthy = True
                            break
                    except Exception:
                        pass
                    time.sleep(0.4)

                if not healthy:
                    raise RuntimeError("llama-server 90 saniye içinde hazır olmadı.")

                post_smi = _query_nvidia_smi()
                vram_delta = max(0, int(post_smi.get("system_used_mb", 0)) - self._baseline_vram_mb)
                try:
                    log_txt = LLAMA_LOG_PATH.read_text(encoding="utf-8", errors="replace")
                    offload_lines = [ln for ln in log_txt.splitlines() if "CUDA0" in ln or "offloaded" in ln]
                    logger.info("llama-server VRAM delta=%dMB | offload=%s", vram_delta, offload_lines[-3:])
                except Exception:
                    pass

                with self.lock:
                    self.engine_backend = "gguf_turbo"
                    self.state = "ready"
                    self._vram_cache_ts = 0.0
                    self.load_message = f"GGUF Turbo Hazır · {model_meta['name']}{lora_note} ({profile_tag})"
                    self.touch()
                logger.info("GGUF Turbo ready: %s%s pid=%s", model_id, lora_note, proc.pid)
                return

            # PyTorch bitsandbytes fallback (used for PyTorch PEFT LoRA or when llama-server unavailable)
            import torch
            from accelerate.hooks import remove_hook_from_module
            from transformers import AutoConfig, AutoProcessor, Gemma4ForConditionalGeneration

            self.torch = torch
            device = "cuda" if torch.cuda.is_available() else "cpu"
            if device == "cuda":
                torch.backends.cuda.matmul.allow_tf32 = True
                torch.backends.cudnn.allow_tf32 = True

            hf_repo = model_meta["hf_repo"]
            local_snap = _resolve_local_hf_snapshot(hf_repo)
            source_path = str(local_snap) if local_snap is not None else hf_repo
            is_local = local_snap is not None

            with self.lock:
                src_label = "Yerel Önbellek" if is_local else "HuggingFace İndirme"
                self.load_message = f"{model_meta['name']} yükleniyor ({src_label})..."

            logger.info(
                "Loading model=%s from=%s local=%s profile=%s vram=%dMB",
                model_id, source_path, is_local, profile, total_vram_mb,
            )

            processor = AutoProcessor.from_pretrained(source_path, local_files_only=is_local)
            model_cfg = AutoConfig.from_pretrained(source_path, local_files_only=is_local)
            q_cfg = getattr(model_cfg, "quantization_config", None)
            if q_cfg is not None:
                extra_skips = [
                    "model.audio_tower",
                    "model.vision_tower",
                    "model.embed_audio",
                    "model.embed_vision",
                    "model.language_model.embed_tokens",
                    "model.language_model.embed_tokens_per_layer",
                    "model.language_model.per_layer_model_projection",
                ]
                if isinstance(q_cfg, dict):
                    q_cfg["llm_int8_enable_fp32_cpu_offload"] = True
                    skips = list(q_cfg.get("llm_int8_skip_modules") or [])
                    for es in extra_skips:
                        if es not in skips:
                            skips.append(es)
                    q_cfg["llm_int8_skip_modules"] = skips
                else:
                    q_cfg.llm_int8_enable_fp32_cpu_offload = True
                    skips = list(getattr(q_cfg, "llm_int8_skip_modules", None) or [])
                    for es in extra_skips:
                        if es not in skips:
                            skips.append(es)
                    q_cfg.llm_int8_skip_modules = skips

            load_kwargs: Dict[str, Any] = {
                "config": model_cfg,
                "local_files_only": is_local,
                "low_cpu_mem_usage": True,
                "attn_implementation": "sdpa",
            }
            is_hybrid_offload = False
            if device == "cuda":
                compute_dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
                load_kwargs["dtype"] = compute_dtype
                if profile == "low_vram" and int(model_meta.get("vram_estimate_mb", 3000)) > 3600:
                    is_hybrid_offload = True
                    gpu_cap = max(2800, total_vram_mb - 550)
                    load_kwargs["device_map"] = "auto"
                    load_kwargs["max_memory"] = {0: f"{gpu_cap}MiB", "cpu": "12GiB"}
                else:
                    load_kwargs["device_map"] = {
                        "model.language_model.embed_tokens_per_layer": "cpu",
                        "model.language_model.embed_tokens": 0,
                        "model.language_model.per_layer_model_projection": 0,
                        "model.language_model.per_layer_projection_norm": 0,
                        "model.language_model.norm": 0,
                        "model.language_model.layers": 0,
                        "model.audio_tower": 0,
                        "model.vision_tower": 0,
                        "model.embed_audio": 0,
                        "model.embed_vision": 0,
                        "lm_head": 0,
                    }
            else:
                load_kwargs["dtype"] = torch.float32

            model = Gemma4ForConditionalGeneration.from_pretrained(source_path, **load_kwargs)

            # Pin PLE lookup table in CPU RAM & strip accelerate per-layer Python hooks for faster token/s
            if device == "cuda" and not is_hybrid_offload:
                lm = getattr(getattr(model, "model", model), "language_model", None)
                ple = getattr(lm, "embed_tokens_per_layer", None) if lm is not None else None
                if ple is not None and hasattr(ple, "_hf_hook") and hasattr(ple._hf_hook, "weights_map"):
                    cpu_w = ple._hf_hook.weights_map["weight"].detach().to("cpu")
                    remove_hook_from_module(model, recurse=True)
                    ple.weight = torch.nn.Parameter(cpu_w, requires_grad=False)
                    orig_ple_fwd = ple.forward

                    def _fast_cpu_ple(input_ids, _orig=orig_ple_fwd):
                        return _orig(input_ids.to("cpu")).to(input_ids.device, non_blocking=True)

                    ple.forward = _fast_cpu_ple
                else:
                    remove_hook_from_module(model, recurse=True)

            lora_note = ""
            if lora_id:
                lora_dir = LORAS_DIR / os.path.basename(lora_id)
                if lora_dir.exists() and (lora_dir / "adapter_config.json").exists():
                    with self.lock:
                        self.load_message = f"LoRA adaptörü bağlanıyor ({lora_id})..."
                    from peft import PeftModel
                    model = PeftModel.from_pretrained(model, str(lora_dir))
                    if abs(float(lora_scale) - 1.0) > 1e-3:
                        for mod in model.modules():
                            if hasattr(mod, "scaling") and isinstance(mod.scaling, dict):
                                for k in list(mod.scaling.keys()):
                                    mod.scaling[k] = float(mod.scaling[k]) * float(lora_scale)
                    lora_note = f" + LoRA:{lora_id} ({lora_scale:.1f}x)"
                else:
                    logger.warning("Requested LoRA adapter not found: %s", lora_dir)

            model.eval()

            # Tiny CUDA warmup so the first user prompt does not pay kernel-init latency
            if device == "cuda":
                try:
                    with self.lock:
                        self.load_message = "GPU çekirdekleri ısıtılıyor..."
                    warm_ids = processor.tokenizer("Merhaba", return_tensors="pt").to("cuda:0")
                    with torch.inference_mode():
                        _ = model.generate(**warm_ids, max_new_tokens=2, do_sample=False)
                    torch.cuda.empty_cache()
                except Exception as warm_exc:
                    logger.warning("CUDA warmup skipped: %s", warm_exc)

            tok = processor.tokenizer
            self.channel_tokens = {
                "thought_close": tok.convert_tokens_to_ids("<channel|>"),
                "turn_close": tok.convert_tokens_to_ids("<turn|>"),
                "eos": tok.eos_token_id if tok.eos_token_id is not None else 1,
            }

            profile_tag = "Low-VRAM 4GB" if profile == "low_vram" else "Turbo GPU"
            with self.lock:
                self.engine_backend = "pytorch_bnb"
                self.model = model
                self.processor = processor
                self.state = "ready"
                self.active_model_id = model_id
                self.load_message = f"Hazır · {model_meta['name']}{lora_note} ({profile_tag})"
                self.touch()
            logger.info("Model ready (PyTorch): %s%s", model_id, lora_note)
        except Exception as exc:
            logger.exception("Failed to load model %s", model_id)
            with self.lock:
                if self.llama_proc is not None:
                    try:
                        if self.llama_proc.poll() is None:
                            self.llama_proc.kill()
                    except Exception:
                        pass
                    self.llama_proc = None
                if self._llama_log_fp is not None:
                    try:
                        self._llama_log_fp.close()
                    except Exception:
                        pass
                    self._llama_log_fp = None
                self.engine_backend = "none"
                self.model = None
                self.processor = None
                gc.collect()
                if self.torch is not None and self.torch.cuda.is_available():
                    self.torch.cuda.empty_cache()
                self.state = "error"
                self.load_message = f"Yükleme hatası: {exc}"
            raise


engine = EngineManager()


def _parse_uploaded_file(file_path: Path, orig_name: str, saved_name: str) -> Dict[str, Any]:
    """Extract structured context from Excel, PDF, Word, Code, Image, or Audio files."""
    ext = file_path.suffix.lower()
    size_bytes = file_path.stat().st_size
    preview_url = f"/api/uploads/{saved_name}"

    def _base_meta(kind: str, summary: str, **extra: Any) -> Dict[str, Any]:
        return {
            "id": uuid.uuid4().hex[:10],
            "name": orig_name,
            "filename": orig_name,
            "saved_name": saved_name,
            "path": str(file_path),
            "kind": kind,
            "ext": ext,
            "size_bytes": size_bytes,
            "preview_url": preview_url,
            "url": preview_url,
            "summary": summary,
            "context_text": "",
            **extra,
        }

    if ext in IMAGE_EXTS:
        from PIL import Image
        with Image.open(file_path) as im:
            w, h = im.size
        return _base_meta("image", f"Görsel ({w}×{h}px)")

    if ext in AUDIO_EXTS:
        import librosa
        wav, _sr = librosa.load(str(file_path), sr=16000, mono=True)
        duration_sec = round(len(wav) / 16000.0, 2)
        return _base_meta("audio", f"Ses kaydı ({duration_sec} sn · 16kHz)", duration_sec=duration_sec)

    if ext in EXCEL_EXTS:
        import pandas as pd

        parts: List[str] = [f"### Dosya: {orig_name} (Tablo/Excel Analizi)"]
        sheet_summaries: List[str] = []
        if ext == ".csv":
            try:
                df = pd.read_csv(file_path)
            except UnicodeDecodeError:
                df = pd.read_csv(file_path, encoding="latin1")
            sheets = {"CSV": df}
        else:
            sheets = pd.read_excel(file_path, sheet_name=None)

        chart_spec: Optional[Dict[str, Any]] = None
        for sheet_name, df in sheets.items():
            rows, cols = df.shape
            sheet_summaries.append(f"{sheet_name}: {rows} satır × {cols} sütun")
            col_info = ", ".join(f"{c} ({df[c].dtype})" for c in df.columns)
            parts.append(f"\n#### Sayfa: `{sheet_name}` (TÜM VERİ: {rows} satır × {cols} sütun)")
            parts.append(f"- Sütunlar: {col_info}")

            null_counts = df.isna().sum()
            missing_cols = [f"{c}: {int(v)}" for c, v in null_counts.items() if v > 0]
            if missing_cols:
                parts.append(f"- Eksik Değerler: {', '.join(missing_cols[:8])}")

            num_df = df.select_dtypes(include="number")
            if not num_df.empty:
                totals_line = ", ".join(f"{c} Toplam={round(float(num_df[c].sum()), 2)}" for c in num_df.columns[:8])
                parts.append(f"- Tam Satır Toplamları ({rows} satır): {totals_line}")
                desc_md = num_df.describe().round(2).to_markdown()
                parts.append(f"\n**Sayısal Özet İstatistikler (Tüm {rows} Satır):**\n{desc_md}")

            cat_cols = [c for c in df.select_dtypes(include=["object", "category", "string"]).columns if 1 < df[c].nunique(dropna=True) <= 40]
            if cat_cols and not num_df.empty:
                g_col = cat_cols[0]
                v_col = num_df.columns[0]
                grouped = df.groupby(g_col, dropna=True)[v_col].sum().sort_values(ascending=False).head(10).round(2)
                if not grouped.empty:
                    grp_md = grouped.reset_index().to_markdown(index=False)
                    parts.append(f"\n**Kategorik Dağılım — `{g_col}` bazında `{v_col}` Toplamı (İlk 10):**\n{grp_md}")
                    if chart_spec is None:
                        chart_spec = {
                            "kind": "chart",
                            "title": f"{orig_name} — {g_col} / {v_col}",
                            "subtitle": f"Tüm {rows} satır üzerinden otomatik analiz",
                            "chart_type": "bar",
                            "labels": [str(x)[:24] for x in grouped.index.tolist()],
                            "dataset_label": str(v_col),
                            "values": [round(float(x), 2) for x in grouped.values.tolist()],
                        }
            elif chart_spec is None and not num_df.empty:
                v_col = num_df.columns[0]
                sample_s = num_df[v_col].dropna().head(12)
                if len(sample_s) >= 2:
                    lbl_col = df.columns[0] if df.columns[0] != v_col else None
                    lbls = [str(x)[:20] for x in df.loc[sample_s.index, lbl_col].tolist()] if lbl_col else [f"#{i+1}" for i in range(len(sample_s))]
                    chart_spec = {
                        "kind": "chart",
                        "title": f"{orig_name} — {v_col}",
                        "subtitle": f"İlk {len(sample_s)} kayıt (Toplam {rows} satır)",
                        "chart_type": "line" if len(sample_s) >= 6 else "bar",
                        "labels": lbls,
                        "dataset_label": str(v_col),
                        "values": [round(float(x), 2) for x in sample_s.tolist()],
                    }

            preview_rows = df.head(60)
            table_md = preview_rows.fillna("").to_markdown(index=False)
            parts.append(f"\n**Veri Önizleme (İlk {len(preview_rows)} satır):**\n{table_md}")
            if rows > 60:
                parts.append(f"\n*(Not: Yukarıdaki toplam ve grup istatistikleri tüm {rows} satır üzerinden hesaplanmıştır.)*")

        full_text = "\n".join(parts)
        return _base_meta("document", " · ".join(sheet_summaries), doc_type="excel", context_text=full_text[:28000], chart_spec=chart_spec)

    if ext == ".pdf":
        import fitz

        doc = fitz.open(str(file_path))
        page_count = len(doc)
        pages_text: List[str] = [f"### PDF Dokümanı: {orig_name} ({page_count} sayfa)"]
        for idx, page in enumerate(doc, start=1):
            txt = page.get_text("text").strip()
            if txt:
                pages_text.append(f"\n[Sayfa {idx}]\n{txt}")
        doc.close()
        full_text = "\n".join(pages_text)
        return _base_meta("document", f"PDF ({page_count} sayfa · {len(full_text)} karakter)", doc_type="pdf", context_text=full_text[:28000])

    if ext == ".docx":
        import docx

        d = docx.Document(str(file_path))
        blocks: List[str] = [f"### Word Dokümanı: {orig_name}"]
        for p in d.paragraphs:
            t = p.text.strip()
            if t:
                blocks.append(t)
        for t_idx, tbl in enumerate(d.tables, start=1):
            rows_md: List[str] = []
            for r_idx, row in enumerate(tbl.rows):
                cells = [c.text.strip().replace("\n", " ") for c in row.cells]
                rows_md.append("| " + " | ".join(cells) + " |")
                if r_idx == 0:
                    rows_md.append("| " + " | ".join(["---"] * len(cells)) + " |")
            if rows_md:
                blocks.append(f"\n[Tablo {t_idx}]\n" + "\n".join(rows_md))
        full_text = "\n\n".join(blocks)
        return _base_meta("document", f"Word ({len(d.paragraphs)} paragraf, {len(d.tables)} tablo)", doc_type="word", context_text=full_text[:28000])

    # Code / plain text fallback
    try:
        raw = file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raw = file_path.read_text(encoding="latin1", errors="replace")
    lang_tag = ext.lstrip(".") if ext else "text"
    full_text = f"### Kod / Metin Dosyası: {orig_name}\n```{lang_tag}\n{raw[:26000]}\n```"
    return _base_meta(
        "document",
        f"{lang_tag.upper()} ({len(raw.splitlines())} satır)",
        doc_type="code" if ext in CODE_AND_TEXT_EXTS else "text",
        context_text=full_text,
    )


def _strip_control_tokens(text: str) -> str:
    for tok in ("<|turn>", "<turn|>", "<eos>", "<pad>", "<bos>", "<|think|>"):
        text = text.replace(tok, "")
    return text


class _ThinkingStreamParser:
    """State-machine splitter for Gemma 4 <|channel>thought ... <channel|> streams."""

    OPEN_TAG = "<|channel>"
    CLOSE_TAG = "<channel|>"
    CONTROL_TOKENS = ("<|turn>", "<turn|>", "<eos>", "<pad>", "<bos>", "<|think|>")

    def __init__(self) -> None:
        self.buf = ""
        self.mode = "normal"  # normal | thought_header | thought

    def _longest_partial_suffix(self, s: str) -> int:
        markers = (self.OPEN_TAG, self.CLOSE_TAG, *self.CONTROL_TOKENS)
        max_k = 0
        for m in markers:
            limit = min(len(s), len(m) - 1)
            for k in range(1, limit + 1):
                if s.endswith(m[:k]) and k > max_k:
                    max_k = k
        return max_k

    def feed(self, chunk: str, final: bool = False) -> Tuple[str, str]:
        self.buf += chunk
        think_out: List[str] = []
        ans_out: List[str] = []

        while self.buf:
            if self.mode == "normal":
                idx = self.buf.find(self.OPEN_TAG)
                if idx != -1:
                    before = _strip_control_tokens(self.buf[:idx])
                    if before:
                        ans_out.append(before)
                    self.buf = self.buf[idx + len(self.OPEN_TAG):]
                    self.mode = "thought_header"
                    continue
                hold = 0 if final else self._longest_partial_suffix(self.buf)
                emit = self.buf if hold == 0 else self.buf[:-hold]
                self.buf = "" if hold == 0 else self.buf[-hold:]
                emit_clean = _strip_control_tokens(emit)
                if emit_clean:
                    ans_out.append(emit_clean)
                break

            if self.mode == "thought_header":
                nl = self.buf.find("\n")
                if nl != -1:
                    self.buf = self.buf[nl + 1:]
                    self.mode = "thought"
                    continue
                if final:
                    self.buf = ""
                    self.mode = "thought"
                break

            if self.mode == "thought":
                idx = self.buf.find(self.CLOSE_TAG)
                if idx != -1:
                    before = _strip_control_tokens(self.buf[:idx])
                    if before:
                        think_out.append(before)
                    self.buf = self.buf[idx + len(self.CLOSE_TAG):]
                    self.mode = "normal"
                    continue
                hold = 0 if final else self._longest_partial_suffix(self.buf)
                emit = self.buf if hold == 0 else self.buf[:-hold]
                self.buf = "" if hold == 0 else self.buf[-hold:]
                emit_clean = _strip_control_tokens(emit)
                if emit_clean:
                    think_out.append(emit_clean)
                break

        return "".join(think_out), "".join(ans_out)


def _format_sse(payload: Dict[str, Any]) -> str:
    return f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"


class ConfigUpdateRequest(BaseModel):
    idle_timeout_minutes: Optional[float] = None
    default_model_id: Optional[str] = None
    active_lora_id: Optional[str] = None
    lora_scale: Optional[float] = None
    gpu_profile: Optional[str] = None
    context_length: Optional[int] = None
    system_prompt: Optional[str] = None
    generation: Optional[Dict[str, Any]] = None


class LoadModelRequest(BaseModel):
    model_id: str
    lora_id: Optional[str] = ""
    lora_scale: Optional[float] = 1.0
    gpu_profile: Optional[str] = None


class ChatAttachment(BaseModel):
    id: str
    name: Optional[str] = None
    filename: Optional[str] = None
    kind: str  # image | audio | document
    path: Optional[str] = None
    preview_url: Optional[str] = None
    url: Optional[str] = None
    summary: Optional[str] = None
    context_text: Optional[str] = None


class ChatMessageInput(BaseModel):
    role: str
    content: str
    thinking: Optional[str] = ""
    attachments: Optional[List[ChatAttachment]] = None


class ChatRequest(BaseModel):
    session_id: Optional[str] = None
    project_id: Optional[str] = None
    skill_id: Optional[str] = None
    model_id: Optional[str] = None
    lora_id: Optional[str] = None
    lora_scale: Optional[float] = None
    thinking_effort: Optional[str] = "medium"
    web_search: Optional[bool] = False
    use_library: Optional[bool] = False
    user_city: Optional[str] = None
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    max_new_tokens: Optional[int] = None
    system_prompt: Optional[str] = None
    messages: List[ChatMessageInput]


class LocalRagLibrary:
    """0-VRAM CPU-based local PDF/DOCX/TXT RAG engine (all-MiniLM-L6-v2 + numpy cosine)."""

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self._embedder: Any = None
        self._embedder_failed = False

    def _get_embedder(self):
        if self._embedder is not None:
            return self._embedder
        if self._embedder_failed:
            return None
        try:
            from sentence_transformers import SentenceTransformer

            self._embedder = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2", device="cpu", local_files_only=True)
            logger.info("Local RAG embedder loaded on CPU (0 MB VRAM).")
            return self._embedder
        except Exception as exc:
            logger.warning("Local RAG SentenceTransformer unavailable, using lexical fallback: %s", exc)
            self._embedder_failed = True
            return None

    def _load_index(self) -> Tuple[Dict[str, Any], Any]:
        import numpy as np

        meta = load_json(RAG_META_PATH, {"docs": [], "chunks": []})
        if RAG_EMB_PATH.exists() and meta.get("chunks"):
            try:
                emb = np.load(str(RAG_EMB_PATH))
                if emb.shape[0] == len(meta["chunks"]):
                    return meta, emb
            except Exception:
                pass
        return meta, None

    def _save_index(self, meta: Dict[str, Any], emb: Any) -> None:
        import numpy as np

        save_json(RAG_META_PATH, meta)
        if emb is not None and len(meta.get("chunks", [])) > 0:
            np.save(str(RAG_EMB_PATH), emb.astype("float32"))
        elif RAG_EMB_PATH.exists():
            try:
                RAG_EMB_PATH.unlink()
            except Exception:
                pass

    def list_docs(self) -> List[Dict[str, Any]]:
        with self.lock:
            meta, _ = self._load_index()
            return meta.get("docs", [])

    def _extract_chunks(self, path: Path, orig_name: str) -> List[Dict[str, Any]]:
        ext = path.suffix.lower()
        pages: List[Tuple[int, str]] = []
        if ext == ".pdf":
            import fitz

            doc = fitz.open(str(path))
            for i, page in enumerate(doc, start=1):
                t = page.get_text("text").strip()
                if t:
                    pages.append((i, t))
            doc.close()
        elif ext == ".docx":
            import docx

            d = docx.Document(str(path))
            full = "\n".join(p.text.strip() for p in d.paragraphs if p.text.strip())
            if full:
                pages.append((1, full))
        else:
            try:
                txt = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                txt = path.read_text(encoding="latin1", errors="replace")
            if txt.strip():
                pages.append((1, txt.strip()))

        chunks: List[Dict[str, Any]] = []
        chunk_size, overlap = 720, 120
        for page_no, txt in pages:
            clean = re.sub(r"\s+", " ", txt).strip()
            pos = 0
            while pos < len(clean):
                piece = clean[pos : pos + chunk_size].strip()
                if len(piece) >= 30:
                    chunks.append({"page": page_no, "text": piece, "source": orig_name})
                if pos + chunk_size >= len(clean):
                    break
                pos += chunk_size - overlap
        return chunks

    def add_document(self, path: Path, orig_name: str, project_id: Optional[str] = None) -> Dict[str, Any]:
        import numpy as np

        raw_chunks = self._extract_chunks(path, orig_name)
        if not raw_chunks:
            raise ValueError("Belgeden okunabilir metin çıkarılamadı.")

        clean_pid = (project_id or "").strip() or None
        doc_id = uuid.uuid4().hex[:10]
        for ch in raw_chunks:
            ch["doc_id"] = doc_id
            ch["project_id"] = clean_pid

        doc_entry = {
            "id": doc_id,
            "name": orig_name,
            "path": str(path),
            "project_id": clean_pid,
            "chunk_count": len(raw_chunks),
            "added_at": datetime.now().isoformat(timespec="seconds"),
        }

        with self.lock:
            meta, old_emb = self._load_index()
            embedder = self._get_embedder()
            new_emb = None
            if embedder is not None:
                vecs = embedder.encode([c["text"] for c in raw_chunks], normalize_embeddings=True, show_progress_bar=False)
                vecs = np.asarray(vecs, dtype="float32")
                if old_emb is not None and len(old_emb) == len(meta["chunks"]):
                    new_emb = np.vstack([old_emb, vecs])
                elif not meta["chunks"]:
                    new_emb = vecs
                else:
                    all_texts = [c["text"] for c in meta["chunks"]] + [c["text"] for c in raw_chunks]
                    new_emb = np.asarray(embedder.encode(all_texts, normalize_embeddings=True, show_progress_bar=False), dtype="float32")

            meta["docs"].append(doc_entry)
            meta["chunks"].extend(raw_chunks)
            self._save_index(meta, new_emb)
        return doc_entry

    def delete_document(self, doc_id: str) -> None:
        with self.lock:
            meta, old_emb = self._load_index()
            target_doc = next((d for d in meta["docs"] if d["id"] == doc_id), None)
            if target_doc:
                try:
                    Path(target_doc["path"]).unlink(missing_ok=True)
                except Exception:
                    pass
            keep_indices = [i for i, c in enumerate(meta["chunks"]) if c.get("doc_id") != doc_id]
            meta["docs"] = [d for d in meta["docs"] if d["id"] != doc_id]
            meta["chunks"] = [meta["chunks"][i] for i in keep_indices]
            new_emb = old_emb[keep_indices] if (old_emb is not None and len(keep_indices) > 0) else None
            self._save_index(meta, new_emb)

    def query(self, question: str, top_k: int = 4, project_id: Optional[str] = None) -> List[Dict[str, Any]]:
        import numpy as np

        clean_pid = (project_id or "").strip() or None
        with self.lock:
            meta, emb = self._load_index()
            all_chunks = meta.get("chunks", [])
            if not all_chunks:
                return []

            # Project-scoped RAG isolation: active project sees its own docs + global (project_id=None) docs
            if clean_pid:
                allowed_idx = [i for i, c in enumerate(all_chunks) if c.get("project_id") in (clean_pid, None, "")]
            else:
                allowed_idx = [i for i, c in enumerate(all_chunks) if not c.get("project_id")]
                if not allowed_idx:
                    allowed_idx = list(range(len(all_chunks)))
            if not allowed_idx:
                return []

            chunks = [all_chunks[i] for i in allowed_idx]
            embedder = self._get_embedder()
            if embedder is not None and emb is not None and emb.shape[0] == len(all_chunks):
                sub_emb = emb[allowed_idx]
                q_vec = np.asarray(embedder.encode([question], normalize_embeddings=True, show_progress_bar=False)[0], dtype="float32")
                scores = sub_emb @ q_vec
                top_idx = np.argsort(scores)[::-1][:top_k]
                hits = []
                for idx in top_idx:
                    sc = float(scores[idx])
                    if sc >= 0.18:
                        c = dict(chunks[int(idx)])
                        c["score"] = round(sc, 3)
                        hits.append(c)
                return hits

            # Lexical keyword fallback if embeddings unavailable
            q_terms = [t for t in re.findall(r"[a-zA-ZçğıöşüÇĞİÖŞÜ0-9]{3,}", question.lower())]
            scored = []
            for c in chunks:
                low = c["text"].lower()
                s = sum(low.count(t) for t in q_terms)
                if s > 0:
                    scored.append((s, c))
            scored.sort(key=lambda x: x[0], reverse=True)
            return [dict(c, score=float(s)) for s, c in scored[:top_k]]


rag_library = LocalRagLibrary()


_WMO_TR = {
    0: ("Açık / Güneşli", "sun"),
    1: ("Çoğunlukla Açık", "sun"),
    2: ("Parçalı Bulutlu", "partly_cloudy"),
    3: ("Çok Bulutlu", "cloud"),
    45: ("Sisli", "fog"),
    48: ("Kırağılı Sis", "fog"),
    51: ("Hafif Çiseleme", "drizzle"),
    53: ("Orta Çiseleme", "drizzle"),
    55: ("Yoğun Çiseleme", "drizzle"),
    61: ("Hafif Yağmurlu", "rain"),
    63: ("Orta Yağmurlu", "rain"),
    65: ("Kuvvetli Yağışlı", "rain"),
    71: ("Hafif Kar Yağışlı", "snow"),
    73: ("Orta Kar Yağışlı", "snow"),
    75: ("Yoğun Kar Yağışlı", "snow"),
    80: ("Hafif Sağanak", "rain"),
    81: ("Sağanak Yağışlı", "rain"),
    82: ("Şiddetli Sağanak", "rain"),
    85: ("Kar Sağanağı", "snow"),
    86: ("Yoğun Kar Sağanağı", "snow"),
    95: ("Gök Gürültülü Fırtına", "storm"),
    96: ("Dolu ve Fırtına", "storm"),
    99: ("Şiddetli Fırtına", "storm"),
}

_TR_WEEKDAYS = ("Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz")


def _is_weather_text(text: str) -> bool:
    q_low = (text or "").lower()
    weather_pat = r"\b(?:hava\s+durumu|hava\s+nasıl|hava\s+tahmin\w*|hava\s+kaç|sıcaklık\s+kaç|kaç\s+derece|weather|forecast)\b"
    return bool(
        re.search(weather_pat, q_low)
        or ("hava" in q_low and any(w in q_low for w in ("bugün", "yarın", "hafta", "yağmur", "kar", "rüzgar", "nem", "sıcak", "soğuk")))
    )


def _extract_urls(text: str) -> List[str]:
    if not text:
        return []
    found = re.findall(r"https?://[^\s<>\"'()\[\]]+", text)
    cleaned: List[str] = []
    for u in found[:3]:
        u = u.rstrip(".,;:!?")
        if u not in cleaned:
            cleaned.append(u)
    return cleaned


def _is_safe_public_url(url: str) -> bool:
    try:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme not in ("http", "https") or not parsed.hostname:
            return False
        host = parsed.hostname.lower()
        if host in ("localhost", "127.0.0.1", "::1") or host.endswith(".local") or host.endswith(".internal"):
            return False
        for info in socket.getaddrinfo(host, parsed.port or (443 if parsed.scheme == "https" else 80)):
            ip_str = info[4][0]
            ip_obj = ipaddress.ip_address(ip_str)
            if ip_obj.is_private or ip_obj.is_loopback or ip_obj.is_link_local or ip_obj.is_reserved or ip_obj.is_multicast:
                return False
        return True
    except Exception:
        return False


def _should_run_web_search(query: str, history: Optional[List[Dict[str, str]]] = None) -> Tuple[bool, str]:
    q_low_tr = (query or "").replace("İ", "i").replace("I", "ı").lower().replace("\u0307", "")
    q_norm = re.sub(r"[?!.,;:\"'()]+", " ", q_low_tr).strip()
    q_norm = re.sub(r"\s+", " ", q_norm)
    if not q_norm:
        return False, "empty"

    # Direct URL in message always gets read
    if _extract_urls(query):
        return True, "direct_url"

    capability_patterns = (
        r"\bweb araştırması yapabilir misin",
        r"\binternete çıkabilir misin",
        r"\binternete erişimin var mı",
        r"\binternetten arama yapabiliyor musun",
        r"\bcanlı arama yapabiliyor musun",
    )
    if any(re.search(pat, q_norm) for pat in capability_patterns) and len(q_norm) < 70:
        return False, "meta_capability"

    # Broad Turkish & English chitchat / greeting / wellbeing / pleasantry filter
    chitchat_regex = re.compile(
        r"^(?:"
        r"selam\w*|merhaba\w*|slm|mrb|hey+|hi+|hello+|yo+|"
        r"günaydın\w*|gunaydin\w*|tünaydın\w*|iyi\s+(?:günler|akşamlar|geceler|sabahlar|çalışmalar)|"
        r"nasılsın\w*|nasilsin\w*|naber|ne\s+haber|iyi\s+misin\w*|nasıl\s+gidiyor|keyifler\s+nasıl|ne\s+yapıyorsun\w*|"
        r"iyiyim(?:\s+teşekkür\w*|\s+sağ\s*ol\w*|\s+sen\s+nasılsın\w*)?|"
        r"teşekkür\w*(?:\s+ederim)?|tesekkur\w*|sağ\s*ol\w*|sag\s*ol\w*|eyvallah|rica\s+ederim|"
        r"tamam|olur|peki|anladım|anladim|harika|süper|super|güzel|guzel|mükemmel|evet|hayır|ok|okay|"
        r"kimsin|sen\s+kimsin|adın\s+ne|neler\s+yapabilirsin|görüşürüz|hoşça\s*kal|bay\s*bay|"
        r"(?:selam\w*|merhaba\w*|günaydın\w*|iyi\s+(?:günler|akşamlar)|hey+|slm)?\s*(?:bugün|bugun|şimdi|dostum|kanka|hocam|asistan|sen)?\s*(?:nasılsın\w*|nasilsin\w*|naber|ne\s+haber|iyi\s+misin\w*|nasıl\s+gidiyor|keyifler\s+nasıl|ne\s+yapıyorsun\w*)(?:\s+(?:bugün|bugun))?"
        r")$",
        re.I,
    )
    if chitchat_regex.match(q_norm):
        return False, "chit_chat"

    # Self-awareness / local capability questions never need web search
    if re.search(r"\b(?:bilgisayarıma|dosyalarıma|sistemime)\s+erişimin\b|\b(?:excel|xlsx|pdf|word|docx)\s+(?:dosyası|raporu|belgesi)?\s*(?:oluştur|hazırla|yap|üret)", q_norm):
        return False, "local_task"

    # Only run live web search when the query actually needs fresh/external web facts, live data, or explicit search
    explicit_web_re = re.compile(
        r"(?:\b(?:araştır\w*|arastir\w*|internet\w*|web(?:'?[dt]e\w*|'?(?:de|da|den|dan))?|google\w*|güncel\w*|guncel\w*|"
        r"son\s+durum|son\s+sürüm|son\s+surum|"
        r"hava\s+durumu|hava\s+nasıl|sıcaklık|yağmur|kar\s+yağ|weather|forecast|"
        r"dolar|euro|eur|usd|gbp|sterlin|döviz|doviz|altın|altin|borsa|bitcoin|btc|eth|kripto|hisse|"
        r"fiyat\w*|kaç\s+tl|kac\s+tl|kaç\s+dolar|ne\s+kadar|ücreti|maç\w*|mac\w*|skor\w*|puan\s+durumu|lig\w*|"
        r"haber\w*|deprem|seçim|secim|kim\s+kazandı|ne\s+zaman\s+çıkacak|çıkış\s+tarihi|vizyon|konser|"
        r"2025|2026|2027|bugün\w*|bugun\w*|yarın\w*|yarin\w*|bu\s+hafta|dün\s+ne\s+oldu|"
        r"dokümantasyon|resmi\s+site|indirme\s+linki|kaynak\s+ver)\b)",
        re.I,
    )
    if explicit_web_re.search(q_norm):
        return True, "search"

    # Follow-up to a previous weather or finance question (e.g., "Peki Bolu için nasıl?")
    if history:
        prev_users = [m.get("content", "") for m in history if m.get("role") == "user" and m.get("content")]
        if prev_users and (_is_weather_text(prev_users[-1]) or re.search(r"\b(?:dolar|euro|altın|fiyat|haber|maç)\b", prev_users[-1], re.I)):
            if len(q_norm) <= 60:
                return True, "followup_search"

    # Otherwise skip unnecessary web search (horoscopes, general culture, advice, coding, casual chat)
    return False, "not_needed"


def _extract_weather_cities(query: str) -> List[str]:
    q = (query or "").strip()
    q_clean = re.sub(r"['’](?:da|de|ta|te|daki|deki|taki|teki|nın|nin|nun|nün|ın|in|un|ün|dan|den|tan|ten)\b", " ", q, flags=re.I)
    # Split potential multi-city separators ("Manisa ve Bolu", "İzmir, Ankara, İstanbul")
    chunks = re.split(r"\s*(?:,|\bve\b|\bile\b|/|\+)\s*", q_clean, flags=re.I)
    stop = {
        "hava", "durumu", "durumunu", "durum", "tahmini", "tahmin", "raporu",
        "nasıl", "nasil", "nasıldır", "nedir", "kaç", "kac", "derece", "sıcaklık", "sicaklik",
        "bugün", "bugun", "yarın", "yarin", "haftalık", "haftalik", "saatlik",
        "güncel", "guncel", "anlık", "anlik", "şu", "su", "an", "canlı", "canli",
        "weather", "forecast", "today", "tomorrow", "current", "in", "for", "at", "the",
        "il", "ili", "ilinde", "ilinin", "şehir", "sehir", "ilçe", "ilce",
        "için", "icin", "bana", "söyle", "soyle", "göster", "goster", "ver",
        "misin", "mısın", "mi", "mı", "mu", "mü", "lütfen", "lutfen", "acaba",
        "yağmur", "yagmur", "yağacak", "yagacak", "var", "ve", "bir", "peki", "ya",
        "karşılaştır", "karsilastir", "karşılaştırmalı", "tablo", "özetle", "ozetle", "de", "da", "ise",
    }
    cities: List[str] = []
    for ch in chunks:
        ch_clean = re.sub(r"[?!.,;:\"'()\[\]]+", " ", ch).strip()
        tokens = [t for t in ch_clean.split() if t and t.lower() not in stop and not t.isdigit()]
        if tokens:
            cand = " ".join(tokens[:2]).strip()
            if cand and cand.lower() not in {c.lower() for c in cities}:
                cities.append(cand)
    return cities[:4]


def _geocode_city(name: str) -> Optional[Dict[str, Any]]:
    raw = (name or "").strip()
    if not raw:
        return None
    # Strip attached Turkish locative/genitive suffixes cleanly (e.g. "boluda" -> "bolu", "izmirde" -> "izmir")
    keep_exact = {"isparta", "malta", "atlanta", "jakarta", "calcutta", "osaka"}
    stripped = raw
    if raw.lower() not in keep_exact and len(raw) >= 5:
        stripped = re.sub(r"(?:daki|deki|taki|teki|dan|den|tan|ten|da|de|ta|te|nın|nin|nun|nün)$", "", raw, flags=re.I).strip()

    attempts: List[str] = []
    if stripped and len(stripped) >= 3 and stripped.lower() != raw.lower():
        attempts.append(stripped)
    attempts.append(raw)

    for attempt in attempts:
        r = httpx.get(
            "https://geocoding-api.open-meteo.com/v1/search",
            params={"name": attempt, "count": 5, "language": "tr", "format": "json"},
            timeout=5.0,
        )
        if r.status_code == 200:
            results = r.json().get("results") or []
            if results:
                tr_hit = next((item for item in results if item.get("country_code") == "TR"), None)
                return tr_hit or results[0]
    return None


def _fetch_single_city_weather(city_guess: str) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, str]], str, bool]:
    try:
        place = _geocode_city(city_guess)
        if not place:
            return None, None, "", False
        lat = place["latitude"]
        lon = place["longitude"]
        city_name = place.get("name") or city_guess
        country = place.get("country") or ""

        fc = httpx.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat,
                "longitude": lon,
                "current": "temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m",
                "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
                "timezone": "auto",
                "forecast_days": 5,
            },
            timeout=6.0,
        )
        fc.raise_for_status()
        data = fc.json()
        cur = data.get("current") or {}
        daily = data.get("daily") or {}

        wcode = int(cur.get("weather_code", 0))
        cond_tr, icon_key = _WMO_TR.get(wcode, ("Parçalı Bulutlu", "partly_cloudy"))

        daily_list: List[Dict[str, Any]] = []
        dates = daily.get("time") or []
        maxs = daily.get("temperature_2m_max") or []
        mins = daily.get("temperature_2m_min") or []
        probs = daily.get("precipitation_probability_max") or []
        codes = daily.get("weather_code") or []

        for i, d_str in enumerate(dates[:5]):
            try:
                dt = datetime.strptime(d_str, "%Y-%m-%d")
                day_lbl = "Bugün" if i == 0 else ("Yarın" if i == 1 else _TR_WEEKDAYS[dt.weekday()])
            except Exception:
                day_lbl = d_str
            dc = int(codes[i]) if i < len(codes) and codes[i] is not None else 2
            d_cond, d_icon = _WMO_TR.get(dc, ("Bulutlu", "cloud"))
            daily_list.append({
                "date": d_str,
                "day_label": day_lbl,
                "max_c": round(float(maxs[i]), 1) if i < len(maxs) and maxs[i] is not None else None,
                "min_c": round(float(mins[i]), 1) if i < len(mins) and mins[i] is not None else None,
                "precip_prob": int(probs[i]) if i < len(probs) and probs[i] is not None else 0,
                "condition": d_cond,
                "icon": d_icon,
            })

        rich_card = {
            "kind": "weather",
            "city": city_name,
            "country": country,
            "updated_at": datetime.now().strftime("%d.%m.%Y %H:%M"),
            "current": {
                "temp_c": round(float(cur.get("temperature_2m", 0)), 1),
                "apparent_c": round(float(cur.get("apparent_temperature", 0)), 1),
                "humidity": int(cur.get("relative_humidity_2m", 0)),
                "wind_kmh": round(float(cur.get("wind_speed_10m", 0)), 1),
                "precipitation_mm": round(float(cur.get("precipitation", 0)), 1),
                "condition": cond_tr,
                "icon": icon_key,
                "weather_code": wcode,
            },
            "daily": daily_list,
        }

        source = {
            "title": f"{city_name} Canlı Hava Durumu — {cond_tr}, {rich_card['current']['temp_c']}°C",
            "url": f"https://open-meteo.com/en/docs#latitude={lat}&longitude={lon}",
            "domain": "open-meteo.com",
            "snippet": f"Anlık {rich_card['current']['temp_c']}°C (Hissedilen {rich_card['current']['apparent_c']}°C), Nem %{rich_card['current']['humidity']}, Rüzgar {rich_card['current']['wind_kmh']} km/sa.",
        }

        tbl_rows = ["| Gün | Durum | En Düşük | En Yüksek | Yağış Olasılığı |", "|---|---|---|---|---|"]
        for d in daily_list:
            tbl_rows.append(f"| {d['day_label']} ({d['date']}) | {d['condition']} | {d['min_c']}°C | {d['max_c']}°C | %{d['precip_prob']} |")

        ctx = (
            f"### CANLI METEOROLOJİ VERİSİ ({city_name}, {country} · Open-Meteo)\n"
            f"- Anlık Sıcaklık: **{rich_card['current']['temp_c']}°C** (Hissedilen: {rich_card['current']['apparent_c']}°C)\n"
            f"- Durum: **{cond_tr}**\n"
            f"- Nem: %{rich_card['current']['humidity']} · Rüzgar: {rich_card['current']['wind_kmh']} km/sa · Yağış: {rich_card['current']['precipitation_mm']} mm\n\n"
            + "\n".join(tbl_rows)
        )
        return rich_card, source, ctx, False
    except httpx.RequestError as exc:
        logger.warning("Open-Meteo weather unreachable: %s", exc)
        return None, None, "", True
    except Exception as exc:
        logger.warning("Open-Meteo weather error: %s", exc)
        return None, None, "", False


def _fetch_live_weather(query: str, force_weather: bool = False, fallback_city: Optional[str] = None) -> Tuple[List[Dict[str, Any]], List[Dict[str, str]], str, bool]:
    if not force_weather and not _is_weather_text(query):
        return [], [], "", False

    city_guesses = _extract_weather_cities(query)
    if not city_guesses and fallback_city and fallback_city.strip():
        city_guesses = [fallback_city.strip()]
    if not city_guesses:
        return [], [], "", False

    cards: List[Dict[str, Any]] = []
    sources: List[Dict[str, str]] = []
    ctxs: List[str] = []
    net_err = False
    seen_cities = set()

    for cg in city_guesses:
        card, src, ctx, err = _fetch_single_city_weather(cg)
        if err:
            net_err = True
        if card and card["city"].lower() not in seen_cities:
            seen_cities.add(card["city"].lower())
            cards.append(card)
            if src:
                sources.append(src)
            if ctx:
                ctxs.append(ctx)

    return cards, sources, "\n\n".join(ctxs), net_err


def _fetch_page_excerpt(url: str, max_chars: int = 1200) -> str:
    """Fetch a public web page safely (SSRF-checked) and return concise readable text excerpt."""
    if not _is_safe_public_url(url):
        return ""
    try:
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7",
        }
        r = httpx.get(url, headers=headers, timeout=4.5, follow_redirects=True)
        if not _is_safe_public_url(str(r.url)):
            return ""
        ctype = (r.headers.get("content-type") or "").lower()
        if r.status_code != 200 or ("text/html" not in ctype and "text/plain" not in ctype):
            return ""
        raw = r.text[:180_000]
        raw = re.sub(r"(?is)<(script|style|noscript|svg|nav|footer|header)[^>]*>.*?</\1>", " ", raw)
        text = html_lib.unescape(re.sub(r"<[^>]+>", " ", raw))
        text = re.sub(r"\s+", " ", text).strip()
        return text[:max_chars]
    except Exception:
        return ""


def _fetch_live_finance(query: str) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, str]], str]:
    q_low = (query or "").lower()
    fin_pat = r"\b(?:dolar|euro|eur|usd|gbp|sterlin|döviz|doviz|kur|kurlar|altın|altin|gram\s+altın|çeyrek\s+altın|xau)\b"
    if not re.search(fin_pat, q_low):
        return None, None, ""
    try:
        r = httpx.get("https://open.er-api.com/v6/latest/USD", timeout=5.0)
        if r.status_code != 200:
            return None, None, ""
        rates = (r.json().get("rates") or {})
        usd_try = float(rates.get("TRY", 0))
        eur_per_usd = float(rates.get("EUR", 0))
        gbp_per_usd = float(rates.get("GBP", 0))
        if usd_try <= 0 or eur_per_usd <= 0 or gbp_per_usd <= 0:
            return None, None, ""
        eur_try = usd_try / eur_per_usd
        gbp_try = usd_try / gbp_per_usd
        items = [
            {"code": "USD / TRY", "name": "ABD Doları", "rate": round(usd_try, 2), "symbol": "$"},
            {"code": "EUR / TRY", "name": "Euro", "rate": round(eur_try, 2), "symbol": "€"},
            {"code": "GBP / TRY", "name": "İngiliz Sterlini", "rate": round(gbp_try, 2), "symbol": "£"},
        ]
        card = {
            "kind": "finance",
            "title": "Canlı Döviz Kurları (TRY)",
            "updated_at": datetime.now().strftime("%d.%m.%Y %H:%M"),
            "items": items,
        }
        src = {
            "title": f"Canlı Döviz Kurları — USD {usd_try:.2f} ₺ · EUR {eur_try:.2f} ₺",
            "url": "https://www.exchangerate-api.com/",
            "domain": "open.er-api.com",
            "snippet": f"1 USD = {usd_try:.2f} TL, 1 EUR = {eur_try:.2f} TL, 1 GBP = {gbp_try:.2f} TL",
        }
        ctx = (
            f"### CANLI DÖVİZ KURLARI ({card['updated_at']} · open.er-api.com)\n"
            f"- 1 USD = {usd_try:.2f} TL\n"
            f"- 1 EUR = {eur_try:.2f} TL\n"
            f"- 1 GBP = {gbp_try:.2f} TL"
        )
        return card, src, ctx
    except Exception as exc:
        logger.warning("Finance rate fetch error: %s", exc)
        return None, None, ""


def _resolve_followup_intent(query: str, history: Optional[List[Dict[str, str]]]) -> Tuple[str, bool]:
    """Detect short elliptical follow-ups (e.g., 'Bolu için nasıl' after 'Manisa hava durumu')."""
    if not history or len(query) > 65:
        return query, False
    prev_users = [m.get("content", "") for m in history if m.get("role") == "user" and m.get("content")]
    if not prev_users:
        return query, False
    last_prev = prev_users[-1]
    q_low = query.lower()

    # Check if any recent user turn was a weather question and current is a short follow-up
    recent_weather_turn = any(_is_weather_text(pm) for pm in prev_users[-2:])
    if recent_weather_turn and not _is_weather_text(query):
        followup_weather_cues = ("için", "icin", "nasıl", "nasil", "peki", "ya ", "durum", "bir de", "birde", "orada", "yarın", "hafta")
        if any(c in q_low for c in followup_weather_cues) or len(query.split()) <= 4:
            cities = _extract_weather_cities(query)
            if cities:
                return f"{' ve '.join(cities)} hava durumu", True

    # Elliptical web-search follow-up ("internette araştırır mısın özelliklerini", "internette ne diyor bu burçlar için")
    if re.search(r"\b(?:internet\w*|araştır\w*|arastir\w*|web\w*)\b", q_low):
        deictic = re.search(r"\b(?:bu|bunu|bunlar\w*|onun|onların|özellik\w*|hakkında|detay\w*|dedim|bak)\b", q_low) or len(query.split()) <= 6
        if deictic:
            # Find the most recent substantive previous user message as topic anchor
            anchor = ""
            for pm in reversed(prev_users):
                pm_clean = pm.strip()
                if pm_clean and not re.match(r"^(?:selam|merhaba|anladım|peki|internette\s+dedim)", pm_clean.lower()):
                    anchor = pm_clean
                    break
            if anchor and anchor.lower() not in q_low:
                cleaned_cur = re.sub(r"\b(?:anladım|birde|bir\s+de|peki|lütfen|misin|mısın|internette\w*|araştır\w*|dedim|ben|sana)\b", " ", query, flags=re.I)
                cleaned_cur = re.sub(r"\s+", " ", cleaned_cur).strip(" ?!.,")
                merged = f"{anchor} {cleaned_cur}".strip()[:160]
                return merged, False
    return query, False


def _perform_web_search(query: str, max_results: int = 5, history: Optional[List[Dict[str, str]]] = None, allow_general_search: bool = True, user_city: Optional[str] = None) -> Dict[str, Any]:
    """Smart conversation-aware web search (intent filter + follow-up memory + multi-city weather + direct URL reader + ddgs)."""
    clean_q = re.sub(r"\s+", " ", (query or "").strip())[:240]
    direct_urls = _extract_urls(clean_q)

    # Direct URL reading works even when general web_search toggle is off
    if not allow_general_search:
        if not direct_urls:
            return {"online": True, "skipped": True, "reason": "disabled", "query": clean_q, "sources": [], "rich_cards": [], "rich_card": None, "context": "", "warning": ""}
        sources: List[Dict[str, str]] = []
        ctx_parts: List[str] = []
        for u in direct_urls:
            txt = _fetch_page_excerpt(u, max_chars=3600)
            if txt:
                dom = urllib.parse.urlparse(u).netloc.replace("www.", "")
                sources.append({"title": f"Doğrudan Sayfa: {dom}", "url": u, "domain": dom, "snippet": txt[:180]})
                ctx_parts.append(f"[{len(sources)}] {u}\nSayfa İçeriği:\n{txt}")
        return {
            "online": True,
            "skipped": False if sources else True,
            "reason": "direct_url",
            "query": clean_q,
            "sources": sources,
            "rich_cards": [],
            "rich_card": None,
            "context": "\n\n".join(ctx_parts),
            "warning": "" if sources else "Paylaşılan bağlantı okunamadı veya erişime kapalı.",
        }

    should, reason = _should_run_web_search(clean_q, history=history)
    if not should:
        return {
            "online": True,
            "skipped": True,
            "reason": reason,
            "query": clean_q,
            "sources": [],
            "rich_cards": [],
            "rich_card": None,
            "context": "",
            "warning": "",
        }

    eff_q, inherited_weather = _resolve_followup_intent(clean_q, history)
    sources: List[Dict[str, str]] = []
    ctx_parts: List[str] = []

    # 1. Direct URLs in prompt (read full excerpt)
    for u in direct_urls:
        txt = _fetch_page_excerpt(u, max_chars=3200)
        if txt:
            dom = urllib.parse.urlparse(u).netloc.replace("www.", "")
            sources.append({"title": f"Doğrudan Sayfa: {dom}", "url": u, "domain": dom, "snippet": txt[:180]})
            ctx_parts.append(f"[{len(sources)}] {u}\nSayfa İçeriği:\n{txt}")

    # 2. Live Open-Meteo multi-city weather (with follow-up memory + optional device user_city!)
    weather_cards, weather_srcs, weather_ctx, weather_net_err = _fetch_live_weather(
        eff_q, force_weather=inherited_weather, fallback_city=user_city
    )
    if weather_srcs:
        sources.extend(weather_srcs)
    if weather_ctx:
        ctx_parts.append(weather_ctx)

    # If user asked for weather without specifying a city and no device location is available, ask cleanly instead of random web search
    weather_need_city = bool(
        (inherited_weather or _is_weather_text(eff_q))
        and not weather_cards
        and not _extract_weather_cities(eff_q)
        and not (user_city and user_city.strip())
    )
    if weather_need_city:
        return {
            "online": True,
            "skipped": False,
            "reason": "weather_need_city",
            "weather_need_city": True,
            "query": eff_q,
            "sources": [],
            "rich_cards": [],
            "rich_card": None,
            "context": "",
            "warning": "",
        }

    # 3. Live Currency / Finance card
    fin_card, fin_src, fin_ctx = _fetch_live_finance(eff_q)
    all_cards: List[Dict[str, Any]] = list(weather_cards)
    if fin_card:
        all_cards.append(fin_card)
    if fin_src:
        sources.append(fin_src)
    if fin_ctx:
        ctx_parts.append(fin_ctx)

    q_low = eff_q.lower()
    skip_ddgs = bool(
        (direct_urls and sources)
        or (weather_cards and not any(w in q_low for w in ("aylık", "30 günlük", "15 günlük")))
        or (fin_card is not None and "altın" not in q_low and "altin" not in q_low)
    )

    ddgs_failed = False
    raw_hits: List[Dict[str, str]] = []
    if not skip_ddgs:
        low_quality_domains = {
            "tiktok.com", "forumsal.org", "falvfal.com", "kizlarsoruyor.com",
            "binkelam.com", "pinterest.com", "instagram.com", "facebook.com",
            "threads.net", "quora.com", "dailymotion.com", "uludagsozluk.com",
        }
        try:
            from ddgs import DDGS
            hits = list(DDGS().text(eff_q, region="tr-tr", max_results=max_results + 5))
            for item in hits:
                if len(raw_hits) >= max_results:
                    break
                href = (item.get("href") or "").strip()
                title = (item.get("title") or "").strip()
                body = (item.get("body") or "").strip()
                if href.startswith("http") and title:
                    domain = urllib.parse.urlparse(href).netloc.replace("www.", "").lower()
                    if any(domain == b or domain.endswith("." + b) for b in low_quality_domains):
                        continue
                    raw_hits.append({
                        "title": title,
                        "url": href,
                        "domain": domain,
                        "snippet": body,
                    })
        except Exception as exc:
            logger.warning("DDGS search error: %s", exc)
            ddgs_failed = True

    if raw_hits:
        top_urls = [h["url"] for h in raw_hits[:3]]
        excerpts: List[str] = ["", "", ""]
        try:
            with ThreadPoolExecutor(max_workers=3) as pool:
                excerpts = list(pool.map(_fetch_page_excerpt, top_urls))
        except Exception:
            pass

        for idx, hit in enumerate(raw_hits):
            sources.append({
                "title": hit["title"],
                "url": hit["url"],
                "domain": hit["domain"],
                "snippet": hit["snippet"],
            })
            page_txt = excerpts[idx] if idx < len(excerpts) else ""
            detail_txt = page_txt if len(page_txt) > len(hit["snippet"]) + 40 else hit["snippet"]
            ctx_parts.append(f"[{len(sources)}] {hit['title']} ({hit['domain']})\nÖzet/İçerik: {detail_txt}\nURL: {hit['url']}")

    if not sources and (weather_net_err or ddgs_failed):
        is_online = False
        try:
            probe = httpx.head("https://api.open-meteo.com", timeout=3.0)
            is_online = probe.status_code < 500
        except Exception:
            is_online = False
        if not is_online:
            return {
                "online": False,
                "skipped": False,
                "query": eff_q,
                "sources": [],
                "rich_cards": [],
                "rich_card": None,
                "context": "",
                "warning": "Cihazda internet bağlantısı bulunamadığı için canlı web araştırması yapılamadı; yerel model bilgisiyle yanıtlanıyor.",
            }

    return {
        "online": True,
        "skipped": False,
        "query": eff_q,
        "sources": sources,
        "rich_cards": all_cards,
        "rich_card": all_cards[0] if all_cards else None,
        "context": "\n\n".join(ctx_parts),
        "warning": "" if sources else "İnternet erişimi aktif ancak bu sorgu için harici web sonucu bulunamadı; yerel bilgiyle yanıtlanıyor.",
    }


class DatasetEntryRequest(BaseModel):
    system_prompt: Optional[str] = ""
    user_text: str
    assistant_text: str
    model_id: Optional[str] = ""
    thinking_effort: Optional[str] = ""


class SaveSessionRequest(BaseModel):
    id: str
    title: str
    messages: List[Dict[str, Any]]
    updated_at: Optional[str] = None
    pinned: Optional[bool] = False
    project_id: Optional[str] = None


class DownloadModelRequest(BaseModel):
    model_id: str


class PinVerifyRequest(BaseModel):
    pin: str


class PinSetRequest(BaseModel):
    pin: str = ""
    current_pin: Optional[str] = ""
    local_bypass: Optional[bool] = True


class MemoryCreateRequest(BaseModel):
    text: str


def _load_memories() -> List[Dict[str, Any]]:
    items = load_json(MEMORIES_PATH, [])
    return items if isinstance(items, list) else []


def _save_memories(items: List[Dict[str, Any]]) -> None:
    save_json(MEMORIES_PATH, items[:60])


def _extract_memory_command(text: str) -> Optional[str]:
    if not text:
        return None
    m = re.match(
        r"^\s*(?:lütfen\s+)?(?:bunu\s+hatırla|şunu\s+hatırla|aklında\s+tut|hafızaya\s+(?:ekle|kaydet)|hafızana\s+(?:ekle|kaydet)|beni\s+şöyle\s+hatırla)\s*[:,\-–]?\s*(.+)$",
        text.strip(),
        re.I | re.S,
    )
    if not m:
        return None
    val = re.sub(r"\s+", " ", m.group(1)).strip(" .\"'")
    return val[:280] if len(val) >= 3 else None


@asynccontextmanager
async def lifespan(_app: FastAPI):
    async def _idle_watcher():
        while True:
            await asyncio.sleep(15)
            try:
                cfg = load_json(CONFIG_PATH, {})
                timeout_min = float(cfg.get("idle_timeout_minutes", 15.0))
                if (
                    engine.state == "ready"
                    and engine.last_activity > 0
                    and (time.time() - engine.last_activity) >= timeout_min * 60.0
                ):
                    logger.info("Idle timeout (%.1f min) reached; unloading model.", timeout_min)
                    engine.unload_model()
            except Exception:
                logger.exception("Idle watcher error")

    task = asyncio.create_task(_idle_watcher())
    if tunnel_mgr.get_settings().get("auto_start"):
        asyncio.get_running_loop().run_in_executor(None, tunnel_mgr.start, 8070)
    try:
        yield
    finally:
        task.cancel()
        tunnel_mgr.stop()
        with engine.lock:
            engine._unload_locked()


app = FastAPI(title="YerelAI Studio API", version="2.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


def _is_native_ios_client(request: Request) -> bool:
    return request.headers.get("x-senai-client", "").strip().lower() == "ios-native"


@app.middleware("http")
async def pin_auth_middleware(request: Request, call_next):
    path = request.url.path
    if (path.startswith("/api/workspace") or path.startswith("/api/mcp")) and not _is_local_request(request):
        return JSONResponse(status_code=403, content={"detail": "Bu özellik yalnızca yerel masaüstü uygulamasında kullanılabilir."})
    if path.startswith("/api/") and not path.startswith("/api/auth/") and path != "/api/image-resolve":
        cfg = load_json(CONFIG_PATH, {})
        if cfg.get("pin_enabled") and cfg.get("access_pin_hash"):
            local_bypass = cfg.get("pin_local_bypass", True)
            if not (local_bypass and _is_local_request(request)) and not _is_native_ios_client(request):
                tok = request.cookies.get(AUTH_COOKIE_NAME, "")
                if not _verify_auth_token(tok, cfg):
                    return JSONResponse(status_code=401, content={"detail": "PIN kilidi aktif. Devam etmek için PIN girin.", "locked": True})
    return await call_next(request)


_IMG_RESOLVE_CACHE: Dict[str, Tuple[float, bytes, str]] = {}
_IMG_CACHE_TTL_SEC = 21600  # 6 hours


def _fetch_resolved_image_sync(query: str) -> Optional[Tuple[bytes, str]]:
    key = re.sub(r"\s+", " ", (query or "").strip().lower())[:120]
    if not key:
        return None
    now = time.time()
    cached = _IMG_RESOLVE_CACHE.get(key)
    if cached and (now - cached[0]) < _IMG_CACHE_TTL_SEC:
        return cached[1], cached[2]

    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept-Language": "tr-TR,tr;q=0.9,en-US;q=0.8",
    }
    try:
        r = httpx.get(
            "https://www.bing.com/images/search",
            params={"q": query, "first": 1, "adlt": "moderate"},
            headers=headers,
            timeout=6.0,
            follow_redirects=True,
        )
        if r.status_code != 200:
            return None
        urls = re.findall(r'murl&quot;:&quot;(https?://[^&]+?)&quot;', r.text)
        blocked_ext = (".svg", ".gif", ".ico", ".webp.html")
        for raw_u in urls[:8]:
            u = html_lib.unescape(raw_u)
            u_low = u.lower()
            if any(u_low.endswith(ext) for ext in blocked_ext):
                continue
            if not _is_safe_public_url(u):
                continue
            try:
                ir = httpx.get(u, headers=headers, timeout=4.5, follow_redirects=True)
                if ir.status_code != 200 or not _is_safe_public_url(str(ir.url)):
                    continue
                ctype = (ir.headers.get("content-type") or "").split(";")[0].strip().lower()
                if not ctype.startswith("image/") or "svg" in ctype:
                    continue
                data = ir.content
                if len(data) < 2048 or len(data) > 4_000_000:
                    continue
                if len(_IMG_RESOLVE_CACHE) >= 300:
                    oldest_k = min(_IMG_RESOLVE_CACHE.keys(), key=lambda k: _IMG_RESOLVE_CACHE[k][0])
                    _IMG_RESOLVE_CACHE.pop(oldest_k, None)
                _IMG_RESOLVE_CACHE[key] = (now, data, ctype)
                return data, ctype
            except Exception:
                continue
    except Exception:
        return None
    return None


@app.get("/api/image-resolve")
async def api_image_resolve(q: str = ""):
    clean_q = re.sub(r"\s+", " ", (q or "").strip())[:120]
    if not clean_q:
        raise HTTPException(status_code=400, detail="q gerekli")
    hit = await asyncio.to_thread(_fetch_resolved_image_sync, clean_q)
    if not hit:
        raise HTTPException(status_code=404, detail="Görsel bulunamadı")
    data, ctype = hit
    return Response(
        content=data,
        media_type=ctype,
        headers={"Cache-Control": "public, max-age=86400"},
    )


@app.get("/api/auth/status")
@app.get("/api/auth/state")
async def api_auth_state(request: Request):
    cfg = load_json(CONFIG_PATH, {})
    enabled = bool(cfg.get("pin_enabled") and cfg.get("access_pin_hash"))
    local_bypass = bool(cfg.get("pin_local_bypass", True))
    is_local = _is_local_request(request)
    if not enabled or (local_bypass and is_local) or _is_native_ios_client(request):
        unlocked = True
    else:
        unlocked = _verify_auth_token(request.cookies.get(AUTH_COOKIE_NAME, ""), cfg)
    return {
        "pin_enabled": enabled,
        "local_bypass": local_bypass,
        "is_local": is_local,
        "unlocked": unlocked,
    }


@app.post("/api/auth/verify")
async def api_auth_verify(req: PinVerifyRequest):
    cfg = load_json(CONFIG_PATH, {})
    if not (cfg.get("pin_enabled") and cfg.get("access_pin_hash")):
        return {"ok": True, "unlocked": True}
    if not _verify_pin(req.pin.strip(), cfg.get("access_pin_hash", "")):
        raise HTTPException(status_code=401, detail="Hatalı PIN.")
    token = _make_auth_token(cfg)
    resp = JSONResponse({"ok": True, "unlocked": True})
    resp.set_cookie(AUTH_COOKIE_NAME, token, httponly=True, samesite="lax", max_age=30 * 86400)
    return resp


@app.post("/api/auth/set-pin")
async def api_auth_set_pin(req: PinSetRequest, request: Request):
    cfg = load_json(CONFIG_PATH, {})
    currently_enabled = bool(cfg.get("pin_enabled") and cfg.get("access_pin_hash"))
    if currently_enabled and not _is_local_request(request):
        tok = request.cookies.get(AUTH_COOKIE_NAME, "")
        if not _verify_auth_token(tok, cfg):
            raise HTTPException(status_code=401, detail="PIN değiştirmek için önce kilidi açın.")

    new_pin = (req.pin or "").strip()
    if req.local_bypass is not None:
        cfg["pin_local_bypass"] = bool(req.local_bypass)

    if not new_pin:
        cfg["pin_enabled"] = False
        cfg["access_pin_hash"] = ""
        save_json(CONFIG_PATH, cfg)
        resp = JSONResponse({"ok": True, "pin_enabled": False, "local_bypass": cfg.get("pin_local_bypass", True)})
        resp.delete_cookie(AUTH_COOKIE_NAME)
        return resp

    if len(new_pin) < 4 or len(new_pin) > 24:
        raise HTTPException(status_code=400, detail="PIN en az 4, en fazla 24 karakter olmalıdır.")

    cfg["access_pin_hash"] = _hash_pin(new_pin)
    cfg["pin_enabled"] = True
    save_json(CONFIG_PATH, cfg)
    token = _make_auth_token(cfg)
    resp = JSONResponse({"ok": True, "pin_enabled": True, "local_bypass": cfg.get("pin_local_bypass", True)})
    resp.set_cookie(AUTH_COOKIE_NAME, token, httponly=True, samesite="lax", max_age=30 * 86400)
    return resp


@app.get("/api/status")
async def api_status():
    return engine.get_status()


@app.get("/api/models")
async def api_models():
    reg = load_json(REGISTRY_PATH, {"models": []})
    models = []
    use_gguf_engine = LLAMA_SERVER_BIN.exists()
    for m in reg.get("models", []):
        entry = dict(m)
        snap = _resolve_local_hf_snapshot(m["hf_repo"])
        gguf_paths = _resolve_local_gguf(m)
        entry["gguf_cached"] = gguf_paths is not None
        entry["bnb_cached"] = snap is not None
        entry["cached_locally"] = (gguf_paths is not None) if (use_gguf_engine and m.get("gguf_repo")) else (snap is not None)
        entry["local_snapshot"] = str(gguf_paths[0]) if gguf_paths else (str(snap) if snap else "")
        entry["download_size_gb"] = 6.0 if "e4b" in m["id"] else 4.1
        models.append(entry)
    return {
        "models": models,
        "loras": _list_lora_adapters(),
        "vram": engine.get_vram_info(),
        "engine_capabilities": {
            "gguf_turbo_available": use_gguf_engine,
        },
    }


@app.get("/api/config")
async def api_get_config():
    return load_json(CONFIG_PATH, {})


@app.put("/api/config")
@app.post("/api/config")
async def api_put_config(req: ConfigUpdateRequest):
    cfg = load_json(CONFIG_PATH, {})
    if req.idle_timeout_minutes is not None:
        cfg["idle_timeout_minutes"] = _clamp(req.idle_timeout_minutes, 1.0, 180.0)
    if req.default_model_id is not None:
        cfg["default_model_id"] = req.default_model_id
    if req.active_lora_id is not None:
        cfg["active_lora_id"] = req.active_lora_id
    if req.lora_scale is not None:
        cfg["lora_scale"] = _clamp(req.lora_scale, 0.0, 2.5)
    if req.gpu_profile is not None and req.gpu_profile in ("auto", "low_vram", "turbo"):
        cfg["gpu_profile"] = req.gpu_profile
        if req.gpu_profile in ("low_vram", "turbo"):
            engine.active_profile = req.gpu_profile
        else:
            v = engine.get_vram_info()
            engine.active_profile = "low_vram" if (v["total_mb"] > 0 and v["total_mb"] <= 5000) else "turbo"
    if req.context_length is not None and int(req.context_length) in (8192, 16384, 32768):
        cfg["context_length"] = int(req.context_length)
        if engine.state == "unloaded":
            engine.active_context_length = int(req.context_length)
    if req.system_prompt is not None:
        cfg["system_prompt"] = req.system_prompt
    if req.generation is not None:
        cfg.setdefault("generation", {}).update(req.generation)
    save_json(CONFIG_PATH, cfg)
    return cfg


@app.post("/api/model/load")
async def api_load_model(req: LoadModelRequest):
    if engine.state == "loading":
        return engine.get_status()
    threading.Thread(
        target=engine.load_model,
        args=(req.model_id, req.lora_id or "", float(req.lora_scale if req.lora_scale is not None else 1.0), req.gpu_profile),
        daemon=True,
    ).start()
    await asyncio.sleep(0.05)
    return engine.get_status()


@app.post("/api/model/unload")
async def api_unload_model():
    try:
        engine.unload_model()
        return engine.get_status()
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))


@app.post("/api/model/download")
async def api_download_model(req: DownloadModelRequest):
    try:
        dl = engine.start_model_download(req.model_id)
        return {"ok": True, "download": dl}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/api/model/download/cancel")
async def api_cancel_download():
    dl = engine.cancel_model_download()
    return {"ok": True, "download": dl}


@app.post("/api/chat/stop")
async def api_stop_chat():
    engine.stop_event.set()
    return {"ok": True}


@app.post("/api/files/upload")
@app.post("/api/upload")
async def api_upload_file(file: UploadFile = File(...)):
    orig_name = file.filename or "dosya.bin"
    ext = Path(orig_name).suffix.lower() or ".bin"
    saved_name = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}{ext}"
    target = UPLOADS_DIR / saved_name
    content = await file.read()
    target.write_bytes(content)
    try:
        meta = _parse_uploaded_file(target, orig_name, saved_name)
    except Exception as exc:
        logger.exception("File parse failed for %s", orig_name)
        raise HTTPException(status_code=400, detail=f"Dosya çözümlenemedi ({orig_name}): {exc}")

    db = load_json(FILES_META_PATH, {})
    db[meta["id"]] = meta
    save_json(FILES_META_PATH, db)
    return meta


@app.get("/api/uploads/{filename}")
async def api_get_upload(filename: str):
    safe_name = os.path.basename(filename)
    path = UPLOADS_DIR / safe_name
    if not path.exists():
        raise HTTPException(status_code=404, detail="Dosya bulunamadı.")
    return FileResponse(str(path))


@app.get("/api/library")
async def api_list_library(project_id: Optional[str] = None):
    docs = rag_library.list_docs()
    if project_id:
        docs = [d for d in docs if d.get("project_id") in (project_id, None, "")]
    return {"docs": docs}


@app.post("/api/library/upload")
async def api_upload_library(file: UploadFile = File(...), project_id: Optional[str] = Form(None)):
    orig_name = file.filename or "belge.txt"
    ext = Path(orig_name).suffix.lower()
    if ext not in (".pdf", ".docx", ".txt", ".md", ".csv"):
        raise HTTPException(status_code=400, detail="Kütüphane yalnızca PDF, DOCX, TXT, MD ve CSV destekler.")
    saved_name = f"{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:8]}{ext}"
    target = LIBRARY_DIR / saved_name
    target.write_bytes(await file.read())
    try:
        doc = await asyncio.to_thread(rag_library.add_document, target, orig_name, project_id)
        return {"ok": True, "doc": doc}
    except Exception as exc:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail=f"Belge indekslenemedi: {exc}")


@app.delete("/api/library/{doc_id}")
async def api_delete_library(doc_id: str):
    await asyncio.to_thread(rag_library.delete_document, doc_id)
    return {"ok": True}


@app.post("/api/export/zip")
async def api_export_zip(payload: Dict[str, Any]):
    try:
        return exp_mgr.build_zip_export(payload, GENERATED_DIR)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/export/xlsx")
async def api_export_xlsx(payload: Dict[str, Any]):
    try:
        return exp_mgr.build_xlsx_export(payload, GENERATED_DIR)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/export/docx")
async def api_export_docx(payload: Dict[str, Any]):
    content = str(payload.get("content") or "").strip()
    title = str(payload.get("title") or "YerelAI_Rapor").strip()
    if not content:
        raise HTTPException(status_code=400, detail="İçerik boş.")
    return exp_mgr.build_docx_export(content, title, GENERATED_DIR)


@app.post("/api/export/pdf")
async def api_export_pdf(payload: Dict[str, Any]):
    content = str(payload.get("content") or "").strip()
    title = str(payload.get("title") or "YerelAI_Rapor").strip()
    if not content:
        raise HTTPException(status_code=400, detail="İçerik boş.")
    return exp_mgr.build_pdf_export(content, title, GENERATED_DIR)


@app.get("/api/generated/{filename}")
async def api_get_generated_file(filename: str):
    safe = os.path.basename(filename)
    path = GENERATED_DIR / safe
    if not path.exists():
        raise HTTPException(status_code=404, detail="Üretilen dosya bulunamadı.")
    return FileResponse(str(path), filename=safe)


def _extract_markdown_tables(md_text: str) -> List[Dict[str, Any]]:
    """Extracts Markdown pipe tables into openpyxl-ready sheet dicts."""
    if not md_text or "|" not in md_text:
        return []
    lines = md_text.replace("\r\n", "\n").splitlines()
    sheets: List[Dict[str, Any]] = []
    i = 0
    while i < len(lines) - 1:
        ln = lines[i].strip()
        nxt = lines[i + 1].strip()
        if "|" in ln and re.match(r"^\|?[\s:\-]+(?:\|[\s:\-]+)+\|?$", nxt):
            def _split_row(r: str) -> List[str]:
                s = r.strip()
                if s.startswith("|"):
                    s = s[1:]
                if s.endswith("|"):
                    s = s[:-1]
                return [c.strip().replace("**", "").replace("`", "") for c in s.split("|")]

            headers = _split_row(ln)
            rows: List[List[str]] = []
            j = i + 2
            while j < len(lines):
                rl = lines[j].strip()
                if not rl or "|" not in rl or re.match(r"^\|?[\s:\-]+(?:\|[\s:\-]+)+\|?$", rl):
                    break
                cells = _split_row(rl)
                if len(cells) >= 2:
                    if len(cells) < len(headers):
                        cells += [""] * (len(headers) - len(cells))
                    rows.append(cells[: len(headers)])
                j += 1
            if len(headers) >= 2 and rows:
                title = f"Sayfa {len(sheets) + 1}"
                if i > 0:
                    prev_ln = re.sub(r"^[#*\-\s]+", "", lines[i - 1]).strip(" :")
                    if 2 <= len(prev_ln) <= 30 and "|" not in prev_ln:
                        title = prev_ln
                sheets.append({"name": title, "headers": headers, "rows": rows})
            i = j
        else:
            i += 1
    return sheets


@app.post("/api/chat")
async def api_chat(req: ChatRequest, request: Request):
    is_local_req = _is_local_request(request)
    if not req.messages:
        raise HTTPException(status_code=400, detail="Mesaj listesi boş olamaz.")
    if engine.state == "generating":
        raise HTTPException(status_code=409, detail="Aktif başka bir yanıt üretiliyor.")

    cfg = load_json(CONFIG_PATH, {})
    gen_cfg = cfg.get("generation", {})
    model_id = req.model_id or cfg.get("default_model_id", "gemma-4-e2b-4bit")
    lora_id = req.lora_id if req.lora_id is not None else cfg.get("active_lora_id", "")
    lora_scale = float(req.lora_scale if req.lora_scale is not None else cfg.get("lora_scale", 1.0))

    effort = (req.thinking_effort or gen_cfg.get("thinking_effort", "medium")).lower()
    if effort not in THINKING_EFFORT_BUDGETS:
        effort = "medium"
    think_budget = THINKING_EFFORT_BUDGETS[effort]
    enable_thinking = effort != "off"

    temperature = _clamp(req.temperature if req.temperature is not None else gen_cfg.get("temperature", 0.7), 0.0, 2.0)
    top_p = _clamp(req.top_p if req.top_p is not None else gen_cfg.get("top_p", 0.95), 0.05, 1.0)
    answer_max_tokens = int(_clamp(req.max_new_tokens if req.max_new_tokens is not None else gen_cfg.get("max_new_tokens", 4096), 64, 8192))
    system_prompt = req.system_prompt if req.system_prompt is not None else cfg.get("system_prompt", "")
    do_web_search = bool(req.web_search if req.web_search is not None else gen_cfg.get("web_search", False))
    do_library_rag = bool(req.use_library)

    async def event_stream():
        engine.stop_event.clear()
        web_result: Optional[Dict[str, Any]] = None
        rag_hits: List[Dict[str, Any]] = []
        try:
            reg = load_json(REGISTRY_PATH, {"models": []})
            m_meta = next((m for m in reg.get("models", []) if m["id"] == model_id), {})

            last_user_msg = next((m.content for m in reversed(req.messages) if m.role == "user" and m.content.strip()), "")
            prev_user_msg = ""
            user_msgs_only = [m.content for m in req.messages if m.role == "user" and m.content.strip()]
            if len(user_msgs_only) >= 2:
                prev_user_msg = user_msgs_only[-2]

            # Deterministic Server-Side "Convert Previous Table to Excel (.xlsx)" Intercept (0% LLM hallucination!)
            wants_excel_convert = bool(
                last_user_msg
                and re.search(r"\b(?:excel|xlsx)\b", last_user_msg, re.I)
                and re.search(r"(?:çevir|dönüştür|aktar|dosya(?:sı|sına)?\s*(?:yap|oluştur|ver|indir|çıkar)|olarak\s*(?:ver|indir|kaydet))", last_user_msg, re.I)
                and re.search(r"(?:bu\s+|yukarıdaki|örnek|mevcut|son\s+)?(?:tablo|veri|liste|bunu)", last_user_msg, re.I)
            )
            if wants_excel_convert:
                prev_tables: List[Dict[str, Any]] = []
                for pm in reversed(req.messages[:-1]):
                    if pm.role == "assistant" and pm.content and "|" in pm.content:
                        found_t = _extract_markdown_tables(pm.content)
                        if found_t:
                            prev_tables = found_t
                            break
                if prev_tables:
                    yield _format_sse({"type": "auto_persona", "name": "Veri & Excel Analisti"})
                    yield _format_sse({"type": "status", "stage": "preparing", "message": "Excel (.xlsx) dosyası oluşturuluyor..."})
                    title_guess = prev_tables[0].get("name") or "YerelAI_Excel_Tablosu"
                    if title_guess.startswith("Sayfa "):
                        title_guess = "YerelAI_Veri_Tablosu"
                    exp = await asyncio.to_thread(
                        exp_mgr.build_xlsx_export,
                        {"title": title_guess, "sheets": prev_tables},
                        GENERATED_DIR,
                    )
                    yield _format_sse({
                        "type": "rich_card",
                        "card": {
                            "kind": "file_download",
                            "file_kind": "xlsx",
                            "filename": exp["filename"],
                            "url": exp["url"],
                            "meta": exp["meta"],
                        },
                    })
                    ans_text = (
                        f"Önceki tablonuz formüllü ve biçimlendirilmiş gerçek Excel (`.xlsx`) dosyasına dönüştürüldü (**{exp['filename']}**).\n\n"
                        "- Sütun genişlikleri, başlık biçimleri ve sayısal toplamlar otomatik ayarlandı.\n"
                        "- Aşağıdaki yeşil dosya kartından tek tıkla indirebilirsiniz."
                    )
                    yield _format_sse({"type": "answer_delta", "delta": ans_text})
                    yield _format_sse({
                        "type": "completed",
                        "thinking": "",
                        "answer": ans_text,
                        "stopped": False,
                        "stats": {"elapsed_sec": 0.12, "tokens": 42, "tps": 350.0, "effort": "off", "engine": "xlsx_direct"},
                    })
                    return

            # Persistent Cross-Chat Memory: auto-capture explicit "bunu hatırla:" commands
            mem_capture = _extract_memory_command(last_user_msg)
            if mem_capture:
                mems = _load_memories()
                if not any(it.get("text", "").lower() == mem_capture.lower() for it in mems):
                    new_mem = {
                        "id": uuid.uuid4().hex[:10],
                        "text": mem_capture,
                        "created_at": datetime.now().isoformat(timespec="seconds"),
                        "source": "chat",
                    }
                    mems.insert(0, new_mem)
                    _save_memories(mems)
                    yield _format_sse({"type": "memory_saved", "item": new_mem})

            # Notes & Todo Plugin auto-capture ("not al: ..." / "yapılacak ekle: ...")
            note_capture = ext_mgr.extract_note_command(last_user_msg)
            if note_capture:
                ext_now = ext_mgr.list_extensions()
                notes_on = any(p["id"] == "notes_todo" and p["enabled"] for p in ext_now["plugins"])
                if notes_on:
                    new_note = ext_mgr.add_note(note_capture, source="chat")
                    yield _format_sse({"type": "note_saved", "item": new_note})

            if do_library_rag and last_user_msg:
                yield _format_sse({"type": "status", "stage": "rag", "message": "Yerel belge kütüphanesi taranıyor..."})
                rag_hits = await asyncio.to_thread(rag_library.query, last_user_msg, 4, req.project_id)
                if rag_hits:
                    yield _format_sse({
                        "type": "rich_card",
                        "card": {
                            "kind": "rag_sources",
                            "title": f"Yerel Kütüphane · {len(rag_hits)} eşleşme",
                            "hits": [{"source": h["source"], "page": h["page"], "score": h.get("score", 0), "excerpt": h["text"][:180]} for h in rag_hits],
                        },
                    })

            # Emit automatic chart cards for Excel/CSV attachments on the latest user turn
            files_db_pre = load_json(FILES_META_PATH, {})
            last_u_obj = next((m for m in reversed(req.messages) if m.role == "user"), None)
            if last_u_obj and last_u_obj.attachments:
                for att in last_u_obj.attachments:
                    meta_p = files_db_pre.get(att.id, {})
                    if meta_p.get("chart_spec"):
                        yield _format_sse({"type": "rich_card", "card": meta_p["chart_spec"]})

            hist_for_search = [{"role": m.role, "content": m.content} for m in req.messages[:-1][-6:]]
            has_direct_url = bool(last_user_msg and _extract_urls(last_user_msg))
            is_consultative_q = bool(
                last_user_msg
                and re.search(
                    r"(?:neler\s+ekleyebilir|ne\s+ekleyebilir|geliştirme\s+yapamaz\s+mısın|nasıl\s+geliştirebilir|önerin\s+ne|neler\s+yapabiliriz|başka\s+ne\s+ekle)",
                    last_user_msg,
                    re.I,
                )
            )
            _excel_kw_re = r"\b(?:excel|xlsx|csv|tablo|envanter|stok|bütçe|maaş|satış\s+tablosu|örnek\s+veri)\b"
            _data_cont_re = r"\b(?:oluştur|çevir|çevirir|dönüştür|aktar|ekle|düzenle|güncelle|sırala|hesapla|veri|örnek|liste|sütun|satır|dosya|indir)\b"
            is_excel_context = bool(
                (last_user_msg and re.search(_excel_kw_re, last_user_msg, re.I))
                or (
                    prev_user_msg
                    and last_user_msg
                    and re.search(_excel_kw_re, prev_user_msg, re.I)
                    and re.search(_data_cont_re, last_user_msg, re.I)
                )
            )
            is_local_code_turn = bool(
                last_user_msg
                and not has_direct_url
                and not re.search(r"\b(?:hava\s+durumu|döviz|kur|haber|fiyat|kaç\s+tl|kaç\s+dolar|araştır|internette|güncel)\b", last_user_msg, re.I)
                and (
                    is_consultative_q
                    or is_excel_context
                    or req.skill_id in ("web-tasarimci", "kod-inceleyici", "eposta-yazari", "excel-uzmani")
                    or re.search(r"\b(?:html|css|javascript|python|portfolyo|arayüz|kodu|tasarım\s+yap)\b", last_user_msg, re.I)
                )
            )
            if last_user_msg and (do_web_search or has_direct_url) and not is_local_code_turn:
                yield _format_sse({"type": "status", "stage": "web_search", "sites_count": 1, "message": "Sayfa okunuyor..." if (has_direct_url and not do_web_search) else "Web siteleri taranıyor..."})
                web_result = await asyncio.to_thread(_perform_web_search, last_user_msg, 5, hist_for_search, do_web_search, req.user_city)
                if not web_result.get("skipped", False):
                    if web_result.get("sources"):
                        yield _format_sse({"type": "status", "stage": "web_search", "sites_count": len(web_result["sources"]), "message": f"{len(web_result['sources'])} web sitesi incelendi"})
                    yield _format_sse({
                        "type": "web_search",
                        "online": web_result["online"],
                        "query": web_result["query"],
                        "sources": web_result["sources"],
                        "warning": web_result["warning"],
                    })
                cards_to_emit = web_result.get("rich_cards") or ([web_result["rich_card"]] if web_result.get("rich_card") else [])
                for card_obj in cards_to_emit:
                    yield _format_sse({
                        "type": "rich_card",
                        "card": card_obj,
                    })

            desired_ctx = int(cfg.get("context_length") or (8192 if engine.active_profile == "low_vram" else 32768))
            if desired_ctx not in (8192, 16384, 32768):
                desired_ctx = 32768
            if engine.active_profile == "low_vram" and desired_ctx > 16384:
                desired_ctx = 8192

            with engine.lock:
                desired_backend = "gguf_turbo" if engine._should_use_gguf(m_meta, lora_id or "") else "pytorch_bnb"
                backend_alive = (
                    (engine.llama_proc is not None and engine.llama_proc.poll() is None)
                    if desired_backend == "gguf_turbo"
                    else (engine.model is not None)
                )
                need_load = (
                    not backend_alive
                    or engine.engine_backend != desired_backend
                    or engine.active_model_id != model_id
                    or engine.active_lora_id != (lora_id or "")
                    or abs(engine.applied_lora_scale - lora_scale) > 1e-3
                    or (desired_backend == "gguf_turbo" and engine.active_context_length != desired_ctx)
                )
            if need_load:
                yield _format_sse({"type": "status", "stage": "loading", "message": f"{model_id} GPU'ya yükleniyor..."})
                await asyncio.to_thread(engine.load_model, model_id, lora_id or "", lora_scale)

            with engine.lock:
                engine.state = "generating"
                engine.touch()
                active_backend = engine.engine_backend
                model = engine.model
                processor = engine.processor
                torch = engine.torch

            yield _format_sse({"type": "status", "stage": "preparing", "message": "Bağlam ve medya hazırlanıyor..."})

            import librosa
            import soundfile as sf
            from PIL import Image

            eff_system_prompt = (system_prompt or "").strip()

            # Universal Conversational Discipline & Format Rule (prevents unrequested 500-line dumps)
            eff_system_prompt = (
                f"{eff_system_prompt}\n\n"
                "İLETİŞİM VE ONAY KURALI: Kullanıcı yalnızca 'yapabilir misin / oluşturabilir misin?' gibi kısa bir yetenek sorusu soruyorsa veya konu/veri/sütun belirtmediyse "
                "ASLA kendiliğinden uzun kod veya uydurma örnek dökme; 2-3 cümlede yapabileceğini söyle ve hangi konu/verileri istediğini kısaca sor. "
                "Kod veya HTML dosyası ürettiğin yanıtlarında, kod bloğunu (```) kapattıktan sonra MUTLAKA 2-4 maddelik kısa Türkçe özet (öne çıkan özellikler ve yapılanlar) yaz; yanıtı asla sadece kod bloğuyla açıklaması olmadan bırakma. "
                "Excel tablosu veya .xlsx dosyası istendiğinde ASLA HTML yazma; doğrudan temiz Markdown tablosu oluştur. "
                "YERLEŞİK DOSYA ÜRETİCİ KURALI: SEN.AI oluşturduğun Markdown tablolarını otomatik olarak gerçek, formüllü .xlsx Excel dosyasına dönüştürüp kullanıcıya indirme kartı sunar! "
                "Bu yüzden ASLA 'Ben metin tabanlı yapay zekâyım, Excel dosyası oluşturamam' veya 'Bu tabloyu Excel'e kopyalayıp yapıştırabilirsin' gibi ifadeler KULLANMA; doğrudan veriyi düzenli Markdown tablosu olarak sun ve dosyanın hazır olduğunu belirt. "
                "Kullanıcıya ASLA 'LocalAI Studio', 'kopyalayıp çalıştırın' gibi yapay teknik yönergeler söyleme; uygulama adı her zaman SEN.AI'dır."
            ).strip()

            if is_consultative_q:
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "KRİTİK DANIŞMA / ÖNERİ SORUSU KURALI: Kullanıcı şu an yeni kod yazmanı DEĞİL, mevcut çalışmaya neler eklenebileceğini veya nasıl geliştirilebileceğini soruyor! "
                    "Bu yanıtta ASLA kod bloğu (```html vb.) YAZMA. Yalnızca 4-5 maddelik somut, yaratıcı geliştirme önerisi sun ve sonunda 'Hangilerini koda eklememi istersiniz?' diye onay iste."
                ).strip()

            # Smart Auto-Persona Routing (automatically selects specialist expertise per turn based on user need)
            auto_persona_name = None
            auto_persona_prompt = None
            att_exts = " ".join(
                str((a.get("filename") or a.get("name")) if isinstance(a, dict) else (getattr(a, "filename", None) or getattr(a, "name", None) or "")).lower()
                for m in req.messages[-2:]
                for a in (m.attachments or [])
            )
            if req.skill_id == "web-tasarimci" or (last_user_msg and re.search(r"\b(?:html|css|web\s*sitesi|landing\s*page|arayüz|dashboard|portfolyo|ui\s*tasarım|bento)\b", last_user_msg, re.I)):
                auto_persona_name = "Web & UI Tasarımcısı"
                auto_persona_prompt = "Aktif Uzmanlık: Kıdemli Web & UI/UX Tasarımcısı (Apple/Linear/Vercel tasarım sistemi, modern CSS Grid & mikro-etkileşimler)."
            elif req.skill_id == "excel-uzmani" or ".xlsx" in att_exts or ".csv" in att_exts or is_excel_context:
                auto_persona_name = "Veri & Excel Analisti"
                auto_persona_prompt = "Aktif Uzmanlık: Kıdemli Veri & Excel Analisti (Net Markdown tabloları, toplam/ortalama/yüzde kırılımları ve karar önerileri)."
            elif req.skill_id == "kod-inceleyici" or (last_user_msg and re.search(r"\b(?:python|javascript|typescript|sql|algoritma|hata\s+ayıkla|bug|refactor|함수|class\s+|def\s+|api\s+yaz)\b", last_user_msg, re.I)):
                auto_persona_name = "Kıdemli Yazılımcı"
                auto_persona_prompt = "Aktif Uzmanlık: Kıdemli Baş Yazılım Mühendisi (Temiz, güvenli, modüler, üretim kalitesinde kod ve kısa mimari açıklama)."
            elif last_user_msg and re.search(r"\b(?:çevir|tercüme|ingilizceye|türkçeye|translate)\b", last_user_msg, re.I):
                auto_persona_name = "Çevirmen (TR ↔ EN)"
                auto_persona_prompt = "Aktif Uzmanlık: Profesyonel Teknik ve Edebi Çevirmen (Doğal akış ve terminoloji uyumu)."
            elif last_user_msg and re.search(r"\b(?:özetle|özet\s+çıkar|maddeler\s+halinde\s+özet)\b", last_user_msg, re.I):
                auto_persona_name = "Özet & Editör"
                auto_persona_prompt = "Aktif Uzmanlık: Baş Editör (Yapılandırılmış yönetici özeti, kritik bulgular ve eylem maddeleri)."

            if auto_persona_name and auto_persona_prompt:
                eff_system_prompt = f"{eff_system_prompt}\n\n[{auto_persona_prompt}]".strip()
                yield _format_sse({"type": "auto_persona", "name": auto_persona_name})

            # Dynamic Temperature & Conversational Personality Engine (v18.0)
            is_technical_turn = bool(
                auto_persona_name in ("Web & UI Tasarımcısı", "Veri & Excel Analisti", "Kıdemli Yazılımcı")
                or req.skill_id in ("web-tasarimci", "kod-inceleyici", "excel-uzmani")
                or is_excel_context
            )
            eff_temp = float(temperature)
            if 0.64 <= eff_temp <= 0.82:
                eff_temp = 0.68 if is_technical_turn else 0.73

            is_brief_request = bool(last_user_msg and re.search(r"\b(?:kısaca|kisaca|kısa\s+özet|tek\s+cümle|özetçe)\b", last_user_msg, re.I))
            is_broad_clarify_request = bool(
                last_user_msg
                and re.search(
                    r"^(?:bana\s+film\s+önerisi\s+yapar\s+mısın\??|film\s+öner(?:isi)?\??|burç\s+uyumu\s+karşılaştırmak\s+istiyorum|günlük\s+veya\s+haftalık\s+plan\s+oluşturmak\s+istiyorum|plan\s+yap(?:ar\s+mısın)?\??)$",
                    last_user_msg.strip(),
                    re.I,
                )
            )

            if not is_technical_turn:
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "[SOHBET VE RİTİM KURALI — CHATGPT SEVİYESİ DOĞALLIK]:\n"
                    "1) İçten, zeki, net ve akıcı Türkçe konuş. ASLA abartılı yapay metaforlar, robotik yapay zekâ uyarıları veya kullanıcının söylemediği varsayımlar üretme.\n"
                    "2) BELİRSİZ / GENEL İSTEKLERDE ÖNCE SOR: Kullanıcı tercih belirtmeden 'Film öner', 'Burç uyumu karşılaştırmak istiyorum', 'Günlük/haftalık plan oluşturmak istiyorum' veya 'Tarot/Arcana bak' dediyse rastgele liste boşaltma! Önce sıcak 1 cümleyle gir, ardından konuya uygun tek emojili 4–6 kısa şıkla tek netleştirme sorusu sor (ör. filmde tür + son beğendiği 1-2 film; burçta hangi burçlar/yükselenler; planda günlük mü haftalık mı + hedefi).\n"
                    "3) 4 ADIMLI AKICI RİTİM: Kısa sıcak giriş (1–2 cümle) → kalın başlık + tek emojili kısa maddeler (her madde max 1 cümle) → net kişisel fikir satırı ('**Benim yorumum:**' veya '**Benim ilk tercihim:**') → derinleşmeye uygun konularda sonda merak uyandıran 3–4 şıklı kısa yönlendirme sorusu ('Biraz daha derine inelim: Hangisini merak ediyorsun?').\n"
                    "4) UZUNLUK UYUMU: Kullanıcı 'kısaca' dediyse gereksiz uzatma; 5–6 net madde ve 1 kısa yorumla bitir.\n"
                    "5) EMOJİ DİSİPLİNİ: Cümle ortasına rastgele emoji serpiştirme; emojileri yalnızca başlık veya liste maddesi başında tek ve anlamlı biçimde kullan."
                ).strip()
            else:
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "[TEKNİK SUNUM TONU]: Kod, tablo ve teknik analizleri hatasız, öz ve tertemiz sun; giriş/özet başlıklarında gerekirse sade tek bir emoji (✨, 📊, ⚡) kullanabilirsin."
                ).strip()

            # Contextual Rich Visual Cards (sen_card: media_list / image_compare / scorecard / compatibility / checklist / rating)
            is_visual_card_turn = bool(
                last_user_msg
                and not is_technical_turn
                and not is_brief_request
                and not is_broad_clarify_request
                and re.search(
                    r"(?:uyum|uyumlu\s+mu|karşılaştır|kıyasla|\bvs\b|hangisi\s+daha\s+iyi|farkı\s+ne|burç.*uyum|aşk\s+uyumu|arcana|tarot|"
                    r"öner\w*|tavsiye|film|dizi|kitap|oyun|mekan|mekân|gezi|rota|plan\w*|program|rutin|tarif|liste\s+yap|puanla|incele|koltuk|kumaş|ürün)",
                    last_user_msg,
                    re.I,
                )
            )
            if is_visual_card_turn:
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "[GÖRSEL KART YETENEĞİ]: Yanıtı görsel olarak zenginleştirmek için uygunsa TAM OLARAK BİR TANE geçerli ```sen_card JSON bloğu ekle (arayüz gerçek HD görselleri 'image_query' alanından otomatik çeker; ASLA URL uydurma):\n"
                    "1) Görselli Liste (film, dizi, kitap, ürün, tarot/arcana): "
                    '```sen_card\n{"kind":"media_list","title":"Sana önereceğim filmler","items":[{"title":"Shutter Island","year":"2010","subtitle":"Gizem, psikoloji ve akıl oyunları. Sonuna kadar merak ettirir.","badge":"İlk önerim","image_query":"Shutter Island movie poster"},{"title":"Se7en","year":"1995","subtitle":"Karanlık suç hikâyesi ve unutulmaz final.","image_query":"Se7en 1995 movie poster"}]}\n```\n'
                    "2) 2'li Görselli Karşılaştırma (ürün, kumaş, burç, cihaz): "
                    '```sen_card\n{"kind":"image_compare","title":"Kadife Kumaş vs Suni Deri","left":{"name":"Kadife kumaş","emoji":"🛋️","subtitle":"Yumuşak ve nefes alan","image_query":"velvet fabric texture dark","points":["Daha az terletir","Yazın konforludur"]},"right":{"name":"Suni deri","emoji":"✨","subtitle":"Şık ve kolay silinen","image_query":"faux leather texture black","points":["Nemli bezle kolay temizlenir","Daha şık görünür"]},"verdict":"Günde 4+ saat oturuyorsan kadife kumaş daha rahat eder."}\n```\n'
                    "3) Skor & Uyumluluk Kartı (burç, ilişki, analiz): "
                    '```sen_card\n{"kind":"scorecard","title":"AKREP ♏ × OĞLAK ♑","badge":"Yüksek uyum","score":"9/10","subtitle":"Genel uyum puanı","metrics":[{"emoji":"❤️","label":"Aşk","value":"9/10"},{"emoji":"🔥","label":"Tutku","value":"9,5/10"},{"emoji":"🛡️","label":"Güven ve sadakat","value":"10/10"}],"strengths":["Karşılıklı sadakat ve güven"],"challenges":["İki tarafın da inatçı olması"],"summary":"Birbirlerine alan tanıdıklarında çok sağlam bir bağ kurarlar."}\n```\n'
                    "4) İnteraktif Günlük/Haftalık Plan: "
                    '```sen_card\n{"kind":"checklist","title":"Verimli Gün Planı","badge":"5 Adım","steps":[{"label":"Sabah yürüyüşü ve kahve","meta":"08:30"},{"label":"Derin odak çalışma bloğu","meta":"10:00"}]}\n```\n'
                    "JSON tek parça ve hatasız olsun; kartın altında kısa kişisel yorumunu ve gerekirse derinleştirme sorunu ekle."
                ).strip()

            # Keep quick weather/finance checks crisp without forced therapist follow-ups
            if web_result and (web_result.get("rich_cards") or web_result.get("rich_card")):
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "[KISA BİLGİ KURALI]: Kullanıcı hızlı bir hava durumu veya döviz bilgisi istedi. 2-3 kısa, doğal ve faydalı cümleyle özetle; sonunda 'kendini nasıl hissediyorsun?' gibi yapay terapist soruları sorma."
                ).strip()

            # Active Claude Project Instructions (if session belongs to a project)
            if req.project_id:
                prj = next((p for p in ext_mgr.list_projects() if p.get("id") == req.project_id), None)
                if prj and prj.get("instructions"):
                    eff_system_prompt = (
                        f"{eff_system_prompt}\n\n"
                        f"[AKTİF PROJE: {prj['name']}]\n{prj['instructions']}\n[/AKTİF PROJE]"
                    ).strip()

            # Active Plugins & Skills context (live TR date/time, notes, calculator, active skill)
            ext_block = ext_mgr.build_extension_prompt_block(last_user_msg, req.skill_id)
            if ext_block:
                eff_system_prompt = f"{eff_system_prompt}\n\n{ext_block}".strip()

            if is_local_req:
                mcp_ctx = mcp_mgr.build_prompt_context()
                if mcp_ctx:
                    eff_system_prompt = (
                        f"{eff_system_prompt}\n\n{mcp_ctx}\n"
                        "(NOT: MCP dosya araçları YALNIZCA yerel diskteki dosyalar içindir; internet araştırması için ASLA MCP search_files kullanma.)"
                    ).strip()

            saved_mems = _load_memories()
            if saved_mems:
                mem_lines = "\n".join(f"- {it.get('text', '').strip()}" for it in saved_mems[:16] if it.get("text"))
                if mem_lines:
                    eff_system_prompt = (
                        f"{eff_system_prompt}\n\n"
                        "[KULLANICI HAKKINDA KALICI HAFIZA — DOĞAL ŞEKİLDE DİKKATE AL]\n"
                        f"{mem_lines}\n"
                        "[/KALICI HAFIZA]"
                    ).strip()
            if enable_thinking:
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "KRİTİK DÜŞÜNME DİLİ KURALI: İçsel düşünme (thought/reasoning) kanalında ASLA İngilizce ('Thinking Process:', 'Analyze the Request:') yazma! "
                    "Düşünmeye HER ZAMAN 'Düşünme Süreci:' diyerek başla ve her kelimeyi %100 akıcı TÜRKÇE yaz."
                ).strip()
            if not is_consultative_q and last_user_msg and re.search(r"\b(?:html|web\s*sitesi|landing\s*page|arayüz|dashboard|portfolyo|css\s+tasarım|web\s+sayfa)\b", last_user_msg, re.I):
                eff_system_prompt = (
                    f"{eff_system_prompt}\n\n"
                    "ÜST DÜZEY WEB & UI TASARIM MİMARİSİ (APPLE / LINEAR / VERCEL STANDARDI):\n"
                    "1. Tek dosyada eksiksiz, görsel olarak çarpıcı HTML5 + CSS3 + Vanilla JS üret. ASLA 'window.alert()', '[Adınız Soyadınız]' gibi yer tutucular veya her kartta aynı tekrarlanan SVG ikonunu kullanma!\n"
                    "2. Tasarım Sistemi: ':root' (koyu mat grafit #0b0d13 / #131722) ve '[data-theme=\"light\"]' (sıcak krem #f8fafc / #ffffff) değişkenleri tanımla; üst navigasyonda gerçekten çalışan Koyu/Açık Tema değiştirici butonu olsun.\n"
                    "3. Düzen & Bento Grid: 'backdrop-filter: blur(20px)' yüzen cam üst bar, ışıltılı rozetli Hero bölümü, 12 sütunlu asimetrik Bento Grid ('grid-column: span 8' ve 'span 4' kartlar, '@media (max-width:768px)' tek sütun), ince cam kenarlığı ('inset 0 1px 0 rgba(255,255,255,0.09)') ve her karta özel anlamlı farklı inline SVG ikon/mini metrik barı kullan.\n"
                    "4. Gerçek Etkileşim: Çalışan Kategori Filtreleme sekmeleri (Tümü / Web / AI / Tasarım vb.), kartlara tıklayınca açılan şık Detay Modalı (ESC ve arka plan tıklamasıyla kapanan) ve canlı arama/filtreleme veya etkileşimli iletişim formu geri bildirimi (toast) ekle.\n"
                    "5. Kod bloğunu (```html ... ```) kapattıktan sonra MUTLAKA 3-4 maddelik kısa Türkçe özet (tasarımda yer alan bölümler ve çalışan etkileşimli özellikler) yaz."
                ).strip()
            if do_web_search:
                eff_system_prompt = re.sub(
                    r"tamamen çevrimdışı çalışan",
                    "canlı web erişimli ve yerel GPU hızlandırmalı",
                    eff_system_prompt,
                    flags=re.I,
                )
                if web_result and web_result.get("reason") == "meta_capability":
                    web_rule = "Canlı web araştırması ve gerçek zamanlı hava durumu erişimi şu an AÇIK; kullanıcıya web araştırması yapabildiğini kısaca ve netçe belirt."
                else:
                    web_rule = (
                        "Canlı web araştırması ve gerçek zamanlı veri erişimi şu an AÇIK. "
                        "Sağlanan güncel verileri ve web kaynaklarını kullanarak doğrudan kullanıcının sorusunu Türkçe ve net yanıtla; "
                        "veriler uygunsa düzenli Markdown tablosu kullan. İnternete erişemediğini asla söyleme (yalnızca açıkça internet yok uyarısı verildiyse hariç)."
                    )
                eff_system_prompt = f"{eff_system_prompt}\n\n{web_rule}".strip()

            files_db = load_json(FILES_META_PATH, {})
            last_user_idx = max((i for i, msg in enumerate(req.messages) if msg.role == "user"), default=-1)

            prepared_turns: List[Dict[str, Any]] = []
            for idx_m, m in enumerate(req.messages):
                role = "assistant" if m.role == "assistant" else "user"
                atts = m.attachments or []
                web_prefix = ""
                if idx_m == last_user_idx and web_result is not None and not web_result.get("skipped", False):
                    emitted_cards = web_result.get("rich_cards") or ([web_result["rich_card"]] if web_result.get("rich_card") else [])
                    has_weather_cards = any(c.get("kind") == "weather" for c in emitted_cards)
                    has_finance_cards = any(c.get("kind") == "finance" for c in emitted_cards)
                    if has_weather_cards and web_result.get("context"):
                        web_prefix = (
                            f"[ARKA PLAN METEOROLOJİ VERİSİ — KULLANICI GÖNDERMEDİ · {datetime.now().strftime('%d.%m.%Y %H:%M')}]\n"
                            f"{web_result['context']}\n"
                            "[/ARKA PLAN]\n"
                            "KURAL: Üstte canlı hava durumu kartı ve 5 günlük tahmin kullanıcıya görsel olarak zaten gösterildi. "
                            "Aynı sıcaklık listesini, nem/rüzgar maddelerini ve 5 günlük tabloyu tekrar yazma. "
                            "ASLA 'Sağladığınız verilere göre', 'Web araştırması sonuçlarını temel alarak', 'Aşağıda bulabilirsiniz' gibi giriş cümleleri yazma. "
                            "Doğrudan 2-3 cümlelik sıcak, doğal bir özet ve pratik tavsiye (giyim/yağış/rüzgar) yaz. "
                            "LaTeX ($...$, \\circ, \\text{}) kesinlikle kullanma.\n\n"
                        )
                    elif has_finance_cards and web_result.get("context"):
                        web_prefix = (
                            f"[ARKA PLAN DÖVİZ VERİSİ — KULLANICI GÖNDERMEDİ · {datetime.now().strftime('%d.%m.%Y %H:%M')}]\n"
                            f"{web_result['context']}\n"
                            "[/ARKA PLAN]\n"
                            "KURAL: Üstte canlı döviz kurları kartı kullanıcıya zaten gösterildi. "
                            "Yalnızca sorulan döviz kurunu 1-2 cümlede net ve doğal Türkçe yanıtla; hava durumu veya ilgisiz konulara kesinlikle girme, meta-giriş cümlesi yazma.\n\n"
                        )
                    elif web_result.get("context"):
                        web_prefix = (
                            f"[ARKA PLAN GÜNCEL BİLGİ — KULLANICI GÖNDERMEDİ · {datetime.now().strftime('%d.%m.%Y %H:%M')}]\n"
                            f"{web_result['context']}\n"
                            "[/ARKA PLAN]\n"
                            "KURAL: Bu arka plan bilgisini kendi doğal bilgin gibi kullanarak soruyu doğrudan, akıcı Türkçe yanıtla. "
                            "ASLA 'Sağladığınız canlı web araştırması sonuçlarını temel alarak', 'Verdiğiniz kaynaklara göre', 'Aşağıda bulabilirsiniz' gibi gereksiz giriş cümleleri yazma. "
                            "Karşılaştırma veya veriler için düzenli Markdown tablosu kullanabilirsin; LaTeX ($...$) kullanma.\n\n"
                        )
                    elif web_result.get("weather_need_city"):
                        web_prefix = (
                            "[Sistem Notu: Kullanıcı şehir belirtmeden hava durumunu sordu ve cihaz konum bilgisi alınamadı. "
                            "Tek kısa ve samimi cümleyle konum bilgisine ulaşamadığını belirtip hangi şehrin hava durumunu öğrenmek istediğini sor (ör. 'Konum bilgine ulaşamadım 📍 Hangi şehrin hava durumunu öğrenmek istersin?'). Başka bir şey uydurma.]\n\n"
                        )
                    elif not web_result.get("online", True):
                        web_prefix = (
                            "[Sistem Notu: Şu an internet bağlantısı olmadığı için canlı veri çekilemedi. "
                            "İnternete erişilemediğini tek cümleyle nazikçe belirtip yerel bilginle yardımcı ol.]\n\n"
                        )

                img_paths: List[Path] = []
                aud_paths: List[Path] = []
                doc_blocks: List[str] = []
                if role == "user" and atts:
                    for att in atts:
                        meta = files_db.get(att.id, {})
                        fpath = Path(att.path or meta.get("path") or "")
                        if att.kind == "image" and fpath.exists():
                            img_paths.append(fpath)
                        elif att.kind == "audio" and fpath.exists():
                            aud_paths.append(fpath)
                        elif att.kind == "document":
                            ctx = att.context_text or meta.get("context_text") or ""
                            if ctx:
                                doc_blocks.append(ctx)

                text_body = m.content.strip()
                if idx_m == last_user_idx and rag_hits:
                    rag_ctx = "\n\n".join(f"[{h['source']} · Sayfa {h['page']}]\n{h['text']}" for h in rag_hits)
                    web_prefix = (
                        f"[ARKA PLAN KÜTÜPHANE KAYNAKLARI — KULLANICI GÖNDERMEDİ]\n{rag_ctx}\n[/ARKA PLAN]\n"
                        "KURAL: Soruyu yukarıdaki yerel belge parçalarına dayanarak, kaynak ve sayfa belirterek doğrudan ve doğal Türkçe yanıtla.\n\n"
                    ) + web_prefix
                if doc_blocks:
                    joined_docs = "\n\n---\n\n".join(doc_blocks)
                    text_body = f"{joined_docs}\n\n---\n\nKullanıcı İsteği:\n{text_body or 'Bu dokümanı/tabloyu detaylı incele ve özetle.'}"
                if not text_body and aud_paths:
                    text_body = "Bu ses kaydını dinle, ne söylendiğini anla ve doğrudan Türkçe yanıtla."
                elif not text_body and img_paths:
                    text_body = "Bu görseli incele ve Türkçe açıkla."

                prepared_turns.append({
                    "role": role,
                    "text": web_prefix + text_body,
                    "img_paths": img_paths,
                    "aud_paths": aud_paths,
                })

            total_max_tokens = min(4096, answer_max_tokens + think_budget)

            # ------------------------------------------------------------------
            # PATH A: GGUF Turbo (llama-server CUDA) — ~70-110+ tok/s on RTX 4060
            # ------------------------------------------------------------------
            if active_backend == "gguf_turbo":
                openai_msgs: List[Dict[str, Any]] = []
                if eff_system_prompt:
                    openai_msgs.append({"role": "system", "content": eff_system_prompt})

                for turn in prepared_turns:
                    if turn["role"] == "user" and (turn["img_paths"] or turn["aud_paths"]):
                        parts_oai: List[Dict[str, Any]] = []
                        for ip in turn["img_paths"]:
                            mime = mimetypes.guess_type(str(ip))[0] or "image/jpeg"
                            b64 = base64.b64encode(ip.read_bytes()).decode("ascii")
                            parts_oai.append({"type": "image_url", "image_url": {"url": f"data:{mime};base64,{b64}"}})
                        for ap in turn["aud_paths"]:
                            wav, _ = librosa.load(str(ap), sr=16000, mono=True)
                            buf_wav = io.BytesIO()
                            sf.write(buf_wav, wav.astype("float32"), 16000, format="WAV", subtype="PCM_16")
                            b64_a = base64.b64encode(buf_wav.getvalue()).decode("ascii")
                            parts_oai.append({"type": "input_audio", "input_audio": {"data": b64_a, "format": "wav"}})
                        parts_oai.append({"type": "text", "text": turn["text"]})
                        openai_msgs.append({"role": "user", "content": parts_oai})
                    else:
                        openai_msgs.append({"role": turn["role"], "content": turn["text"]})

                if enable_thinking and openai_msgs and openai_msgs[-1].get("role") == "user":
                    tr_think_cue = "\n\n[Not: Düşünme sürecini de tamamen Türkçe yaz, 'Thinking Process' yazma.]"
                    last_c = openai_msgs[-1]["content"]
                    if isinstance(last_c, str):
                        openai_msgs[-1]["content"] = last_c + tr_think_cue
                    elif isinstance(last_c, list) and last_c and last_c[-1].get("type") == "text":
                        last_c[-1]["text"] = str(last_c[-1].get("text", "")) + tr_think_cue

                # Dynamic Context Window Guard (8K / 16K / 32K, preserves system prompt + newest turns)
                ctx_limit = int(engine.active_context_length or desired_ctx or 32768)
                max_prompt_tokens = int(ctx_limit * 0.78)

                def _est_msg_tokens(msg_obj: Dict[str, Any]) -> int:
                    c = msg_obj.get("content", "")
                    if isinstance(c, str):
                        return max(4, int(len(c) / 3.4) + 6)
                    total_c = 0
                    for p in c:
                        if p.get("type") == "text":
                            total_c += int(len(p.get("text", "")) / 3.4)
                        else:
                            total_c += 320
                    return max(16, total_c)

                est_ctx_tokens = sum(_est_msg_tokens(m_o) for m_o in openai_msgs)
                sys_offset = 1 if (openai_msgs and openai_msgs[0].get("role") == "system") else 0
                while est_ctx_tokens > max_prompt_tokens and len(openai_msgs) > sys_offset + 2:
                    removed = openai_msgs.pop(sys_offset)
                    est_ctx_tokens -= _est_msg_tokens(removed)

                avail_out_tokens = max(1024, ctx_limit - est_ctx_tokens - 160)
                hard_cap = 6144 if engine.active_profile == "low_vram" else 10240
                effective_max_tokens = min(hard_cap, avail_out_tokens, answer_max_tokens + think_budget)

                llama_payload: Dict[str, Any] = {
                    "messages": openai_msgs,
                    "stream": True,
                    "stream_options": {"include_usage": True},
                    "temperature": float(eff_temp if eff_temp > 0.05 else 0.0),
                    "top_p": float(top_p),
                    "top_k": 64,
                    "max_tokens": int(effective_max_tokens),
                    "chat_template_kwargs": {"enable_thinking": enable_thinking},
                    "reasoning_budget": int(think_budget) if enable_thinking else 0,
                }

                t0 = time.perf_counter()
                yield _format_sse({"type": "status", "stage": "generating", "message": "Yanıt üretiliyor (GGUF Turbo)...", "effort": effort})

                parser = _ThinkingStreamParser()
                full_thinking: List[str] = []
                full_answer: List[str] = []
                srv_timings: Dict[str, Any] = {}
                usage_tokens = 0
                streamed_pieces = 0

                async with httpx.AsyncClient(timeout=None) as client:
                    async with client.stream("POST", f"{LLAMA_SERVER_URL}/v1/chat/completions", json=llama_payload) as lresp:
                        if lresp.status_code != 200:
                            err_body = (await lresp.aread()).decode("utf-8", errors="replace")[:400]
                            raise RuntimeError(f"llama-server HTTP {lresp.status_code}: {err_body}")
                        async for raw_line in lresp.aiter_lines():
                            if engine.stop_event.is_set():
                                break
                            if not raw_line or not raw_line.startswith("data: "):
                                continue
                            data_str = raw_line[6:].strip()
                            if data_str == "[DONE]":
                                break
                            try:
                                chunk_obj = json.loads(data_str)
                            except Exception:
                                continue

                            if chunk_obj.get("timings"):
                                srv_timings = chunk_obj["timings"]
                            if chunk_obj.get("usage") and chunk_obj["usage"].get("completion_tokens"):
                                usage_tokens = int(chunk_obj["usage"]["completion_tokens"])

                            choices = chunk_obj.get("choices") or []
                            if not choices:
                                continue
                            delta = choices[0].get("delta") or {}

                            r_chunk = delta.get("reasoning_content")
                            if r_chunk:
                                streamed_pieces += 1
                                full_thinking.append(r_chunk)
                                yield _format_sse({"type": "thinking_delta", "delta": r_chunk})

                            c_chunk = delta.get("content")
                            if c_chunk:
                                streamed_pieces += 1
                                t_d, a_d = parser.feed(c_chunk, final=False)
                                if t_d:
                                    full_thinking.append(t_d)
                                    yield _format_sse({"type": "thinking_delta", "delta": t_d})
                                if a_d:
                                    full_answer.append(a_d)
                                    yield _format_sse({"type": "answer_delta", "delta": a_d})

                t_tail, a_tail = parser.feed("", final=True)
                if t_tail:
                    full_thinking.append(t_tail)
                    yield _format_sse({"type": "thinking_delta", "delta": t_tail})
                if a_tail:
                    full_answer.append(a_tail)
                    yield _format_sse({"type": "answer_delta", "delta": a_tail})

                elapsed = max(0.05, time.perf_counter() - t0)
                pred_n = int(srv_timings.get("predicted_n") or usage_tokens or streamed_pieces or 1)
                if srv_timings.get("predicted_per_second"):
                    tps = round(float(srv_timings["predicted_per_second"]), 1)
                else:
                    tps = round(pred_n / elapsed, 1)

                final_answer_str = "".join(full_answer).strip()
                final_thinking_str = "".join(full_thinking).strip()
                if is_local_req:
                    mcp_calls = mcp_mgr.parse_mcp_calls(final_answer_str)
                    if mcp_calls:
                        yield _format_sse({"type": "mcp_tool_request", "calls": mcp_calls})
                _append_chat_archive(
                    session_id=req.session_id or "",
                    model_id=model_id,
                    user_text=last_user_msg,
                    assistant_text=final_answer_str,
                    thinking_text=final_thinking_str,
                    temperature=eff_temp,
                    auto_persona=auto_persona_name or "",
                    web_searched=bool(web_result and not web_result.get("skipped")),
                    tokens=pred_n,
                    tps=tps,
                )

                yield _format_sse({
                    "type": "completed",
                    "thinking": "".join(full_thinking).strip(),
                    "answer": final_answer_str,
                    "stopped": engine.stop_event.is_set(),
                    "stats": {
                        "elapsed_sec": round(elapsed, 2),
                        "tokens": pred_n,
                        "tps": tps,
                        "effort": effort,
                        "engine": "gguf_turbo",
                        "context_used_est": est_ctx_tokens + pred_n,
                        "context_limit": ctx_limit,
                        "vram": engine.get_vram_info(force=True),
                    },
                })
                return

            # ------------------------------------------------------------------
            # PATH B: PyTorch Fallback (only when PyTorch PEFT LoRA active)
            # ------------------------------------------------------------------
            from transformers import LogitsProcessor, LogitsProcessorList, StoppingCriteria, StoppingCriteriaList, TextIteratorStreamer

            images_list: List[Any] = []
            audios_list: List[Any] = []
            chat_messages: List[Dict[str, Any]] = []
            if eff_system_prompt:
                chat_messages.append({"role": "system", "content": eff_system_prompt})

            for turn in prepared_turns:
                if turn["role"] == "user" and (turn["img_paths"] or turn["aud_paths"]):
                    c_parts: List[Dict[str, Any]] = []
                    for ip in turn["img_paths"]:
                        images_list.append(Image.open(ip).convert("RGB"))
                        c_parts.append({"type": "image"})
                    for ap in turn["aud_paths"]:
                        wav, _ = librosa.load(str(ap), sr=16000, mono=True)
                        audios_list.append(wav.astype("float32"))
                        c_parts.append({"type": "audio"})
                    c_parts.append({"type": "text", "text": turn["text"]})
                    chat_messages.append({"role": "user", "content": c_parts})
                else:
                    chat_messages.append({"role": turn["role"], "content": turn["text"]})

            prompt_text = processor.apply_chat_template(
                chat_messages,
                tokenize=False,
                add_generation_prompt=True,
                enable_thinking=enable_thinking,
            )

            proc_kwargs: Dict[str, Any] = {"text": prompt_text, "return_tensors": "pt"}
            if images_list:
                proc_kwargs["images"] = images_list
            if audios_list:
                proc_kwargs["audio"] = audios_list

            inputs = processor(**proc_kwargs)
            model_device = torch.device("cuda:0") if torch.cuda.is_available() else torch.device("cpu")
            model_dtype = model.dtype if hasattr(model, "dtype") else torch.bfloat16
            moved: Dict[str, Any] = {}
            for k, v in inputs.items():
                if hasattr(v, "to"):
                    if v.is_floating_point():
                        moved[k] = v.to(device=model_device, dtype=model_dtype)
                    else:
                        moved[k] = v.to(device=model_device)
                else:
                    moved[k] = v

            prompt_len = int(moved["input_ids"].shape[-1])
            thought_close_id = engine.channel_tokens.get("thought_close", 101)
            turn_close_id = engine.channel_tokens.get("turn_close", 106)
            eos_id = engine.channel_tokens.get("eos", 1)
            eos_ids = list({int(eos_id), int(turn_close_id)})

            class ThinkingBudgetLogitsProcessor(LogitsProcessor):
                def __init__(self, p_len: int, budget: int, close_tok: int) -> None:
                    self.p_len = p_len
                    self.budget = budget
                    self.close_tok = close_tok
                    self.closed = False

                def __call__(self, input_ids, scores):
                    if self.closed or self.budget <= 0:
                        return scores
                    gen_len = int(input_ids.shape[-1]) - self.p_len
                    if gen_len <= 0:
                        return scores
                    gen_slice = input_ids[0, self.p_len:]
                    if (gen_slice == self.close_tok).any():
                        self.closed = True
                        return scores
                    if gen_len >= self.budget:
                        forced = torch.full_like(scores, float("-inf"))
                        forced[:, self.close_tok] = 0.0
                        self.closed = True
                        return forced
                    return scores

            class StopEventCriteria(StoppingCriteria):
                def __call__(self, input_ids, scores, **kwargs) -> bool:
                    return engine.stop_event.is_set()

            streamer = TextIteratorStreamer(
                processor.tokenizer,
                skip_prompt=True,
                skip_special_tokens=False,
            )

            logits_processors = LogitsProcessorList()
            if enable_thinking and think_budget > 0:
                logits_processors.append(ThinkingBudgetLogitsProcessor(prompt_len, think_budget, int(thought_close_id)))

            gen_kwargs: Dict[str, Any] = {
                **moved,
                "streamer": streamer,
                "max_new_tokens": total_max_tokens,
                "eos_token_id": eos_ids,
                "pad_token_id": processor.tokenizer.pad_token_id or 0,
                "use_cache": True,
                "do_sample": temperature > 0.05,
                "logits_processor": logits_processors,
                "stopping_criteria": StoppingCriteriaList([StopEventCriteria()]),
            }
            if temperature > 0.05:
                gen_kwargs["temperature"] = temperature
                gen_kwargs["top_p"] = top_p
                gen_kwargs["top_k"] = 64

            gen_error: List[BaseException] = []

            def _run_generate():
                try:
                    with torch.inference_mode():
                        model.generate(**gen_kwargs)
                except BaseException as exc:
                    gen_error.append(exc)
                    logger.exception("Generation error")

            t0 = time.perf_counter()
            gen_thread = threading.Thread(target=_run_generate, daemon=True)
            gen_thread.start()

            yield _format_sse({"type": "status", "stage": "generating", "message": "Yanıt üretiliyor...", "effort": effort})

            parser = _ThinkingStreamParser()
            full_thinking: List[str] = []
            full_answer: List[str] = []
            loop = asyncio.get_running_loop()

            def _next_chunk():
                try:
                    return next(streamer)
                except StopIteration:
                    return None

            while True:
                chunk = await loop.run_in_executor(None, _next_chunk)
                if chunk is None:
                    break
                t_delta, a_delta = parser.feed(chunk, final=False)
                if t_delta:
                    full_thinking.append(t_delta)
                    yield _format_sse({"type": "thinking_delta", "delta": t_delta})
                if a_delta:
                    full_answer.append(a_delta)
                    yield _format_sse({"type": "answer_delta", "delta": a_delta})

            t_tail, a_tail = parser.feed("", final=True)
            if t_tail:
                full_thinking.append(t_tail)
                yield _format_sse({"type": "thinking_delta", "delta": t_tail})
            if a_tail:
                full_answer.append(a_tail)
                yield _format_sse({"type": "answer_delta", "delta": a_tail})

            gen_thread.join(timeout=2.0)
            if gen_error:
                raise RuntimeError(str(gen_error[0]))

            elapsed = max(0.05, time.perf_counter() - t0)
            thinking_str = "".join(full_thinking).strip()
            answer_str = "".join(full_answer).strip()
            approx_tokens = max(
                1,
                len(processor.tokenizer.encode(thinking_str + "\n" + answer_str, add_special_tokens=False)),
            )
            tps = round(approx_tokens / elapsed, 1)

            mcp_calls = mcp_mgr.parse_mcp_calls(answer_str)
            if mcp_calls:
                yield _format_sse({"type": "mcp_tool_request", "calls": mcp_calls})

            yield _format_sse({
                "type": "completed",
                "thinking": thinking_str,
                "answer": answer_str,
                "stopped": engine.stop_event.is_set(),
                "stats": {
                    "elapsed_sec": round(elapsed, 2),
                    "tokens": approx_tokens,
                    "tps": tps,
                    "effort": effort,
                    "engine": "pytorch_bnb",
                    "vram": engine.get_vram_info(force=True),
                },
            })
        except Exception as exc:
            logger.exception("SSE chat error")
            yield _format_sse({"type": "error", "detail": str(exc)})
        finally:
            with engine.lock:
                alive = (
                    (engine.engine_backend == "gguf_turbo" and engine.llama_proc is not None and engine.llama_proc.poll() is None)
                    or (engine.engine_backend == "pytorch_bnb" and engine.model is not None)
                )
                if alive:
                    engine.state = "ready"
                    engine.touch()
                else:
                    engine.state = "unloaded"

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache, no-transform",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@app.get("/api/sessions")
async def api_list_sessions():
    sessions = load_json(SESSIONS_PATH, [])
    return {"sessions": sessions}


@app.get("/api/sessions/search")
async def api_search_sessions(q: str = ""):
    needle = (q or "").strip().lower()
    if len(needle) < 2:
        return {"matches": []}
    sessions = load_json(SESSIONS_PATH, [])
    matches: List[Dict[str, Any]] = []
    for s in sessions:
        title = str(s.get("title") or "Sohbet")
        if needle in title.lower():
            matches.append({"id": s.get("id"), "title": title, "snippet": "Başlık eşleşmesi", "updated_at": s.get("updated_at")})
            continue
        for m in s.get("messages") or []:
            txt = str(m.get("content") or "")
            pos = txt.lower().find(needle)
            if pos >= 0:
                start = max(0, pos - 36)
                end = min(len(txt), pos + len(needle) + 64)
                snip = re.sub(r"\s+", " ", txt[start:end]).strip()
                matches.append({
                    "id": s.get("id"),
                    "title": title,
                    "snippet": ("…" if start > 0 else "") + snip + ("…" if end < len(txt) else ""),
                    "updated_at": s.get("updated_at"),
                })
                break
        if len(matches) >= 20:
            break
    return {"matches": matches}


@app.get("/api/sessions/export-all")
async def api_export_all_data():
    bundle = {
        "app": "YerelAI Studio",
        "exported_at": datetime.now().isoformat(timespec="seconds"),
        "sessions": load_json(SESSIONS_PATH, []),
        "memories": _load_memories(),
        "notes": ext_mgr.list_notes(),
        "projects": ext_mgr.list_projects(),
    }
    raw = json.dumps(bundle, ensure_ascii=False, indent=2).encode("utf-8")
    fname = f"YerelAI_Yedek_{datetime.now().strftime('%Y%m%d_%H%M')}.json"
    return Response(
        content=raw,
        media_type="application/json; charset=utf-8",
        headers={"Content-Disposition": f'attachment; filename="{fname}"'},
    )


@app.get("/api/sessions/{session_id}")
async def api_get_session(session_id: str):
    sessions = load_json(SESSIONS_PATH, [])
    found = next((s for s in sessions if s.get("id") == session_id), None)
    if found is None:
        raise HTTPException(status_code=404, detail="Sohbet bulunamadı.")
    return found


@app.post("/api/sessions")
async def api_save_session(req: SaveSessionRequest):
    sessions = load_json(SESSIONS_PATH, [])
    now_iso = req.updated_at or datetime.now().isoformat(timespec="seconds")
    existing = next((s for s in sessions if s.get("id") == req.id), {})
    updated = {
        "id": req.id,
        "title": req.title[:80] or "Yeni Sohbet",
        "messages": req.messages,
        "updated_at": now_iso,
        "pinned": bool(req.pinned if req.pinned is not None else existing.get("pinned", False)),
        "project_id": req.project_id if req.project_id is not None else existing.get("project_id", None),
    }
    sessions = [s for s in sessions if s.get("id") != req.id]
    sessions.insert(0, updated)
    sessions = sessions[:50]
    save_json(SESSIONS_PATH, sessions)
    return {"ok": True, "session": updated}


@app.delete("/api/sessions/{session_id}")
async def api_delete_session(session_id: str):
    sessions = load_json(SESSIONS_PATH, [])
    sessions = [s for s in sessions if s.get("id") != session_id]
    save_json(SESSIONS_PATH, sessions)
    return {"ok": True}


@app.get("/api/memories")
async def api_list_memories():
    return {"memories": _load_memories()}


@app.post("/api/memories")
async def api_add_memory(req: MemoryCreateRequest):
    txt = re.sub(r"\s+", " ", (req.text or "")).strip()[:280]
    if len(txt) < 2:
        raise HTTPException(status_code=400, detail="Hafıza metni boş olamaz.")
    items = _load_memories()
    if any(it.get("text", "").lower() == txt.lower() for it in items):
        return {"ok": True, "memories": items, "duplicate": True}
    item = {
        "id": uuid.uuid4().hex[:10],
        "text": txt,
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "source": "manual",
    }
    items.insert(0, item)
    _save_memories(items)
    return {"ok": True, "item": item, "memories": items}


@app.delete("/api/memories/{mem_id}")
async def api_delete_memory(mem_id: str):
    items = [it for it in _load_memories() if it.get("id") != mem_id]
    _save_memories(items)
    return {"ok": True, "memories": items}


# =========================================================================
# Faz 5 Endpoints: Extensions (Plugins & Skills), Notes, Projects,
# Local Python Sandbox & Smart Auto Title
# =========================================================================
@app.get("/api/extensions")
async def api_list_extensions():
    return ext_mgr.list_extensions()


@app.post("/api/extensions/plugin")
async def api_toggle_plugin(payload: Dict[str, Any]):
    pid = str(payload.get("id") or "").strip()
    if not pid:
        raise HTTPException(status_code=400, detail="Eklenti kimliği gerekli.")
    return ext_mgr.toggle_plugin(pid, bool(payload.get("enabled", True)), payload.get("webhook_url"))


@app.post("/api/extensions/skill/toggle")
async def api_toggle_skill(payload: Dict[str, Any]):
    sid = str(payload.get("id") or "").strip()
    if not sid:
        raise HTTPException(status_code=400, detail="Beceri kimliği gerekli.")
    return ext_mgr.toggle_skill(sid, bool(payload.get("enabled", True)))


@app.post("/api/extensions/skill")
async def api_save_skill(payload: Dict[str, Any]):
    name = str(payload.get("name") or "").strip()
    desc = str(payload.get("description") or "").strip()
    body = str(payload.get("body") or "").strip()
    raw_md = payload.get("raw_markdown")
    if not raw_md and (not name or not body):
        raise HTTPException(status_code=400, detail="Beceri adı ve yönergesi gerekli.")
    return ext_mgr.save_skill(name, desc, body, raw_markdown=str(raw_md) if raw_md else None)


@app.delete("/api/extensions/skill/{skill_id}")
async def api_delete_skill(skill_id: str):
    return ext_mgr.delete_skill(skill_id)


@app.post("/api/extensions/webhook/test")
async def api_test_webhook(payload: Dict[str, Any]):
    url = str(payload.get("url") or "").strip()
    if not url or not re.match(r"^https?://", url, re.I):
        raise HTTPException(status_code=400, detail="Geçerli bir http:// veya https:// webhook adresi girin.")
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            r = await client.post(url, json={"source": "YerelAI Studio", "event": "test", "timestamp": datetime.now().isoformat()})
            return {"ok": r.status_code < 400, "status_code": r.status_code}
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"Webhook erişilemedi: {exc}")


@app.get("/api/notes")
async def api_list_notes():
    return {"notes": ext_mgr.list_notes()}


@app.post("/api/notes")
async def api_add_note(payload: Dict[str, Any]):
    txt = str(payload.get("text") or "").strip()
    if not txt:
        raise HTTPException(status_code=400, detail="Not metni boş olamaz.")
    item = ext_mgr.add_note(txt, source="manual")
    return {"ok": True, "item": item, "notes": ext_mgr.list_notes()}


@app.post("/api/notes/{note_id}/toggle")
async def api_toggle_note(note_id: str):
    return {"ok": True, "notes": ext_mgr.toggle_note(note_id)}


@app.delete("/api/notes/{note_id}")
async def api_delete_note(note_id: str):
    return {"ok": True, "notes": ext_mgr.delete_note(note_id)}


@app.get("/api/projects")
async def api_list_projects():
    return {"projects": ext_mgr.list_projects()}


@app.post("/api/projects")
async def api_save_project(payload: Dict[str, Any]):
    name = str(payload.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="Proje adı boş olamaz.")
    item = ext_mgr.save_project(
        name=name,
        instructions=str(payload.get("instructions") or ""),
        color=str(payload.get("color") or "#3b82f6"),
        project_id=payload.get("id"),
    )
    return {"ok": True, "project": item, "projects": ext_mgr.list_projects()}


@app.delete("/api/projects/{project_id}")
async def api_delete_project(project_id: str):
    return {"ok": True, "projects": ext_mgr.delete_project(project_id)}


# ---- Local MCP (Model Context Protocol) Client Bridge ----

@app.get("/api/mcp/servers")
async def api_list_mcp_servers():
    return {"servers": mcp_mgr.list_servers(), "presets": mcp_mgr.list_presets()}


@app.get("/api/mcp/presets")
async def api_list_mcp_presets():
    return {"presets": mcp_mgr.list_presets()}


@app.post("/api/mcp/servers")
async def api_upsert_mcp_server(payload: Dict[str, Any]):
    try:
        srv = mcp_mgr.upsert_server(
            name=str(payload.get("name") or ""),
            transport=str(payload.get("transport") or "stdio"),
            command=str(payload.get("command") or ""),
            args=payload.get("args"),
            url=str(payload.get("url") or ""),
            enabled=bool(payload.get("enabled", True)),
            server_id=payload.get("id"),
        )
        return {"ok": True, "server": srv, "servers": mcp_mgr.list_servers()}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.patch("/api/mcp/servers/{server_id}")
async def api_toggle_mcp_server(server_id: str, payload: Dict[str, Any]):
    srv = mcp_mgr.toggle_server(server_id, bool(payload.get("enabled", True)))
    if not srv:
        raise HTTPException(status_code=404, detail="MCP sunucusu bulunamadı.")
    return {"ok": True, "server": srv, "servers": mcp_mgr.list_servers()}


@app.delete("/api/mcp/servers/{server_id}")
async def api_delete_mcp_server(server_id: str):
    return {"ok": True, "servers": mcp_mgr.delete_server(server_id)}


@app.post("/api/mcp/servers/{server_id}/discover")
async def api_discover_mcp_tools(server_id: str):
    try:
        srv = await asyncio.to_thread(mcp_mgr.discover_tools, server_id)
        return {"ok": True, "server": srv, "servers": mcp_mgr.list_servers()}
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc))


@app.post("/api/mcp/servers/{server_id}/call")
async def api_call_mcp_tool(server_id: str, payload: Dict[str, Any]):
    tool_name = str(payload.get("tool") or "").strip()
    if not tool_name:
        raise HTTPException(status_code=400, detail="Araç adı (tool) gereklidir.")
    try:
        res = await asyncio.to_thread(mcp_mgr.call_tool, server_id, tool_name, payload.get("arguments") or {})
        return res
    except KeyError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except Exception as exc:
        raise HTTPException(status_code=502, detail=str(exc))


# ---- Local Folder Workspace (Claude Code / Cowork) ----

@app.get("/api/workspace")
async def api_get_workspace():
    return ws_mgr.get_state()


@app.post("/api/workspace/open")
async def api_open_workspace(payload: Dict[str, Any]):
    folder = str(payload.get("path") or "").strip()
    try:
        return {"ok": True, **ws_mgr.set_root(folder)}
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/workspace/close")
async def api_close_workspace():
    return {"ok": True, **ws_mgr.close()}


@app.get("/api/workspace/file")
async def api_read_workspace_file(path: str = ""):
    try:
        return ws_mgr.read_file(path)
    except FileNotFoundError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/workspace/write")
async def api_write_workspace_file(payload: Dict[str, Any]):
    rel_path = str(payload.get("path") or "").strip()
    content = str(payload.get("content") or "")
    try:
        return ws_mgr.write_file(rel_path, content)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.get("/api/workspace/git")
async def api_workspace_git():
    return await asyncio.to_thread(ws_mgr.get_git_summary)


@app.post("/api/sandbox/python")
async def api_run_python_sandbox(payload: Dict[str, Any]):
    code = str(payload.get("code") or "")
    if not code.strip():
        raise HTTPException(status_code=400, detail="Çalıştırılacak Python kodu boş.")
    if len(code) > 30000:
        raise HTTPException(status_code=400, detail="Kod boyutu sandbox sınırını (30 KB) aşıyor.")

    # Basic safety guardrail against destructive OS commands
    blocked = re.search(
        r"\b(?:os\.system|os\.popen|shutil\.rmtree|subprocess\.(?:run|Popen|call|check_output)|ctypes\.windll|winreg)\b",
        code,
    )
    if blocked:
        raise HTTPException(status_code=400, detail=f"Güvenlik kısıtı: '{blocked.group(0)}' sandbox içinde engellendi.")

    return await asyncio.to_thread(exp_mgr.run_python_sandbox_sync, code)


@app.get("/api/tunnel/status")
async def api_tunnel_status():
    return tunnel_mgr.status(8070)


@app.post("/api/tunnel/start")
async def api_tunnel_start():
    return await asyncio.to_thread(tunnel_mgr.start, 8070)


@app.post("/api/tunnel/stop")
async def api_tunnel_stop():
    return await asyncio.to_thread(tunnel_mgr.stop, 8070)


@app.post("/api/tunnel/config")
async def api_tunnel_config(payload: Dict[str, Any]):
    tunnel_mgr.save_settings(payload)
    st = tunnel_mgr.get_settings()
    if payload.get("sync_github") and st.get("github_token"):
        try:
            return await asyncio.to_thread(tunnel_mgr.sync_github_bridge, 8070)
        except Exception as exc:
            raise HTTPException(status_code=400, detail=str(exc))
    return tunnel_mgr.status(8070)


@app.post("/api/tunnel/sync-github")
async def api_tunnel_sync_github():
    try:
        return await asyncio.to_thread(tunnel_mgr.sync_github_bridge, 8070)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@app.post("/api/sessions/autotitle")
async def api_session_autotitle(payload: Dict[str, Any]):
    user_text = re.sub(r"\s+", " ", str(payload.get("user_text") or "")).strip()
    if not user_text:
        return {"title": "Yeni Sohbet"}
    cleaned = re.sub(r"https?://\S+", "", user_text)
    cleaned = re.sub(r"^(?:lütfen|bana|selam|merhaba|acaba|şimdi)\s+", "", cleaned, flags=re.I)
    cleaned = re.sub(r"[?!.,:;]+$", "", cleaned).strip()
    words = cleaned.split()
    title = " ".join(words[:6])[:48].strip()
    if title:
        title = title[0].upper() + title[1:]
    return {"title": title or "Yeni Sohbet"}


def _load_dataset_entries() -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    if DATASET_PATH.exists():
        with open(DATASET_PATH, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    try:
                        entries.append(json.loads(line))
                    except Exception:
                        continue
    return entries


def _build_dpo_pairs(entries: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Builds Unsloth DPO/ORPO {prompt, chosen, rejected} pairs from feedback ratings."""
    pairs: List[Dict[str, Any]] = []
    likes_by_prompt: Dict[str, str] = {}
    for e in entries:
        msgs = e.get("messages") or []
        u = next((m.get("content", "").strip() for m in msgs if m.get("role") == "user"), "")
        a = next((m.get("content", "").strip() for m in msgs if m.get("role") == "assistant"), "")
        rating = e.get("rating", "like")
        if rating == "like" and u and a:
            likes_by_prompt[u.lower()] = a

    seen = set()
    for e in entries:
        if e.get("rating") != "dislike":
            continue
        msgs = e.get("messages") or []
        u = next((m.get("content", "").strip() for m in msgs if m.get("role") == "user"), "")
        rej = next((m.get("content", "").strip() for m in msgs if m.get("role") == "assistant"), "")
        chosen = (e.get("corrected_text") or "").strip() or likes_by_prompt.get(u.lower(), "")
        if u and rej and chosen and chosen != rej:
            key = (u.lower(), chosen[:80], rej[:80])
            if key not in seen:
                seen.add(key)
                pairs.append({
                    "prompt": u,
                    "chosen": chosen,
                    "rejected": rej,
                    "reason": e.get("reason") or "",
                })
    return pairs


@app.get("/api/dataset")
async def api_list_dataset():
    entries = _load_dataset_entries()
    sft_count = sum(1 for e in entries if e.get("rating", "like") == "like" or (e.get("corrected_text") or "").strip())
    dislike_count = sum(1 for e in entries if e.get("rating") == "dislike")
    dpo_pairs = _build_dpo_pairs(entries)
    return {
        "entries": entries,
        "count": len(entries),
        "sft_count": sft_count,
        "dislike_count": dislike_count,
        "dpo_count": len(dpo_pairs),
    }


@app.post("/api/dataset/rate")
async def api_rate_dataset_entry(payload: Dict[str, Any]):
    user_text = str(payload.get("user_text") or "").strip()
    assistant_text = str(payload.get("assistant_text") or "").strip()
    rating = "dislike" if str(payload.get("rating") or "").lower() == "dislike" else "like"
    reason = str(payload.get("reason") or "").strip()[:120]
    corrected = str(payload.get("corrected_text") or "").strip()
    sys_prompt = str(payload.get("system_prompt") or "").strip()
    if not user_text or not assistant_text:
        raise HTTPException(status_code=400, detail="Soru ve yanıt boş olamaz.")

    msgs: List[Dict[str, str]] = []
    if sys_prompt:
        msgs.append({"role": "system", "content": sys_prompt})
    msgs.append({"role": "user", "content": user_text})
    msgs.append({"role": "assistant", "content": assistant_text})

    entry = {
        "id": uuid.uuid4().hex[:10],
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "rating": rating,
        "reason": reason,
        "corrected_text": corrected,
        "model_id": str(payload.get("model_id") or ""),
        "thinking_effort": str(payload.get("thinking_effort") or ""),
        "messages": msgs,
    }
    with open(DATASET_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")

    entries = _load_dataset_entries()
    return {
        "ok": True,
        "entry": entry,
        "count": len(entries),
        "sft_count": sum(1 for e in entries if e.get("rating", "like") == "like" or (e.get("corrected_text") or "").strip()),
        "dislike_count": sum(1 for e in entries if e.get("rating") == "dislike"),
        "dpo_count": len(_build_dpo_pairs(entries)),
    }


@app.post("/api/dataset")
async def api_add_dataset_entry(req: DatasetEntryRequest):
    if not req.user_text.strip() or not req.assistant_text.strip():
        raise HTTPException(status_code=400, detail="Soru ve yanıt boş olamaz.")

    msgs: List[Dict[str, str]] = []
    if req.system_prompt and req.system_prompt.strip():
        msgs.append({"role": "system", "content": req.system_prompt.strip()})
    msgs.append({"role": "user", "content": req.user_text.strip()})
    msgs.append({"role": "assistant", "content": req.assistant_text.strip()})

    entry = {
        "id": uuid.uuid4().hex[:10],
        "created_at": datetime.now().isoformat(timespec="seconds"),
        "rating": "like",
        "reason": "",
        "corrected_text": "",
        "model_id": req.model_id or "",
        "thinking_effort": req.thinking_effort or "",
        "messages": msgs,
    }
    with open(DATASET_PATH, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")
    return {"ok": True, "entry": entry}


@app.delete("/api/dataset/{entry_id}")
async def api_delete_dataset_entry(entry_id: str):
    if not DATASET_PATH.exists():
        return {"ok": True}
    kept: List[str] = []
    with open(DATASET_PATH, "r", encoding="utf-8") as f:
        for line in f:
            raw = line.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
                if obj.get("id") != entry_id:
                    kept.append(raw)
            except Exception:
                continue
    with open(DATASET_PATH, "w", encoding="utf-8") as f:
        for raw in kept:
            f.write(raw + "\n")
    return {"ok": True}


@app.get("/api/dataset/export")
async def api_export_dataset(fmt: str = "sft"):
    entries = _load_dataset_entries()
    mode = (fmt or "sft").strip().lower()
    if mode == "dpo":
        pairs = _build_dpo_pairs(entries)
        lines = [json.dumps({"prompt": p["prompt"], "chosen": p["chosen"], "rejected": p["rejected"]}, ensure_ascii=False) for p in pairs]
        content = "\n".join(lines) + ("\n" if lines else "")
        return Response(
            content=content.encode("utf-8"),
            media_type="application/x-ndjson",
            headers={"Content-Disposition": 'attachment; filename="yerelai_dpo_preferences.jsonl"'},
        )

    lines: List[str] = []
    for obj in entries:
        rating = obj.get("rating", "like")
        corrected = (obj.get("corrected_text") or "").strip()
        if rating == "like":
            lines.append(json.dumps({"messages": obj["messages"]}, ensure_ascii=False))
        elif rating == "dislike" and corrected:
            fixed_msgs = [dict(m) for m in (obj.get("messages") or [])]
            for m in fixed_msgs:
                if m.get("role") == "assistant":
                    m["content"] = corrected
            lines.append(json.dumps({"messages": fixed_msgs}, ensure_ascii=False))
    content = "\n".join(lines) + ("\n" if lines else "")
    return Response(
        content=content.encode("utf-8"),
        media_type="application/x-ndjson",
        headers={"Content-Disposition": 'attachment; filename="yerelai_unsloth_sft.jsonl"'},
    )


@app.get("/api/colab/notebook")
async def api_download_colab_notebook():
    nb = COLAB_DIR / "Gemma4_YerelAI_Colab_FineTune.ipynb"
    if not nb.exists():
        raise HTTPException(status_code=404, detail="Colab notebook bulunamadı.")
    return FileResponse(
        str(nb),
        media_type="application/x-ipynb+json",
        filename="Gemma4_YerelAI_Colab_FineTune.ipynb",
    )


@app.post("/api/tts")
async def api_offline_tts(payload: Dict[str, Any]):
    """Authentic Turkish TTS: Edge Neural (online) -> Windows 11 WinRT Tolga tr-TR (offline)."""
    text = str(payload.get("text", "")).strip()
    voice_pref = str(payload.get("voice", "tr-TR-AhmetNeural")).strip()
    if not text:
        raise HTTPException(status_code=400, detail="Metin boş.")
    try:
        audio_bytes, media_type, engine_tag = await exp_mgr.synthesize_turkish_tts(text, voice_pref)
        return Response(content=audio_bytes, media_type=media_type, headers={"X-TTS-Engine": engine_tag})
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc))


if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")


if __name__ == "__main__":
    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w", encoding="utf-8")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w", encoding="utf-8")
    uvicorn.run(app, host="0.0.0.0", port=8070, log_config=None)
