import asyncio
import gc
import json
import logging
import os
import re
import sys
import threading
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, Response, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

BASE_DIR = Path(__file__).resolve().parent
MODELS_DIR = BASE_DIR / "models"
LORAS_DIR = MODELS_DIR / "loras"
OUTPUTS_DIR = BASE_DIR / "outputs"
UPLOADS_DIR = OUTPUTS_DIR / "uploads"
COLAB_DIR = BASE_DIR / "colab"
FRONTEND_DIR = BASE_DIR / "frontend"

CONFIG_PATH = BASE_DIR / "config.json"
REGISTRY_PATH = MODELS_DIR / "registry.json"
LORA_REGISTRY_PATH = LORAS_DIR / "registry.json"
SESSIONS_PATH = OUTPUTS_DIR / "sessions.json"
DATASET_PATH = OUTPUTS_DIR / "train_dataset.jsonl"
FILES_META_PATH = OUTPUTS_DIR / "files_meta.json"
LOG_PATH = BASE_DIR / "backend.log"

OUTPUTS_DIR.mkdir(parents=True, exist_ok=True)
UPLOADS_DIR.mkdir(parents=True, exist_ok=True)
LORAS_DIR.mkdir(parents=True, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(LOG_PATH, encoding="utf-8"),
        logging.StreamHandler(),
    ],
)
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


def _resolve_local_hf_snapshot(repo_id: str) -> Optional[Path]:
    """Return local HuggingFace cache snapshot path if config + weights exist."""
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
        has_weights = any(cand.glob("*.safetensors")) or (cand / "model.safetensors.index.json").exists()
        if has_weights:
            return cand
    return None


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
            if (sub / "adapter_config.json").exists():
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
    """Thread-safe on-demand Gemma 4 GPU engine with idle auto-unload and 4GB/8GB profiling."""

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.state: str = "unloaded"  # unloaded | loading | ready | generating | unloading | error
        self.active_model_id: Optional[str] = None
        self.active_lora_id: str = ""
        self.applied_lora_scale: float = 1.0
        self.load_message: str = "GPU beklemede (model yüklü değil)"
        self.last_activity: float = 0.0
        self.model: Any = None
        self.processor: Any = None
        self.torch: Any = None
        self.active_profile: str = "turbo"
        self.detected_vram_mb: int = 0
        self.stop_event = threading.Event()
        self.channel_tokens: Dict[str, int] = {}

    def touch(self) -> None:
        self.last_activity = time.time()

    def get_vram_info(self) -> Dict[str, Any]:
        if self.torch is None:
            try:
                import torch as _torch
                self.torch = _torch
            except Exception:
                return {
                    "available": False,
                    "device": "CPU",
                    "used_mb": 0,
                    "allocated_mb": 0,
                    "reserved_mb": 0,
                    "total_mb": 0,
                    "profile": "low_vram",
                    "profile_label": "CPU Modu",
                    "detected_vram_mb": 0,
                }
        if not self.torch.cuda.is_available():
            return {
                "available": False,
                "device": "CPU",
                "used_mb": 0,
                "allocated_mb": 0,
                "reserved_mb": 0,
                "total_mb": 0,
                "profile": "low_vram",
                "profile_label": "CPU Modu",
                "detected_vram_mb": 0,
            }
        used = int(self.torch.cuda.memory_allocated(0) / (1024 * 1024))
        reserved = int(self.torch.cuda.memory_reserved(0) / (1024 * 1024))
        total = int(self.torch.cuda.get_device_properties(0).total_memory / (1024 * 1024))
        name = self.torch.cuda.get_device_name(0)
        if self.detected_vram_mb == 0:
            self.detected_vram_mb = total
            cfg = load_json(CONFIG_PATH, {})
            user_prof = cfg.get("gpu_profile", "auto")
            if user_prof in ("turbo", "low_vram"):
                self.active_profile = user_prof
            else:
                self.active_profile = "low_vram" if total <= 5000 else "turbo"
        return {
            "available": True,
            "device": name,
            "used_mb": used,
            "allocated_mb": used,
            "reserved_mb": reserved,
            "total_mb": total,
            "profile": self.active_profile,
            "profile_label": "Low-VRAM (4GB Uyumlu)" if self.active_profile == "low_vram" else "Turbo GPU (8GB+)",
            "detected_vram_mb": self.detected_vram_mb or total,
        }

    def get_status(self) -> Dict[str, Any]:
        cfg = load_json(CONFIG_PATH, {})
        timeout_min = float(cfg.get("idle_timeout_minutes", 15.0))
        idle_sec = 0.0
        remaining_sec = 0.0
        if self.state == "ready" and self.last_activity > 0:
            idle_sec = max(0.0, time.time() - self.last_activity)
            remaining_sec = max(0.0, timeout_min * 60.0 - idle_sec)
        return {
            "state": self.state,
            "active_model_id": self.active_model_id,
            "active_lora_id": self.active_lora_id,
            "lora_scale": self.applied_lora_scale,
            "load_message": self.load_message,
            "idle_seconds": round(idle_sec, 1),
            "remaining_seconds": round(remaining_sec, 1),
            "idle_timeout_minutes": timeout_min,
            "vram": self.get_vram_info(),
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
            self.active_model_id = None
            self.active_lora_id = ""
            self.last_activity = 0.0
            self.state = "unloaded"
            self.load_message = "GPU beklemede (VRAM temizlendi)"
            logger.info("Model unloaded and VRAM cleared.")

    def load_model(self, model_id: str, lora_id: str = "", lora_scale: float = 1.0) -> None:
        with self.lock:
            if (
                self.state == "ready"
                and self.active_model_id == model_id
                and self.active_lora_id == (lora_id or "")
                and abs(self.applied_lora_scale - float(lora_scale)) < 1e-3
                and self.model is not None
            ):
                self.touch()
                return
            if self.state in ("loading", "generating"):
                return

            registry = load_json(REGISTRY_PATH, {"models": []})
            model_meta = next((m for m in registry.get("models", []) if m["id"] == model_id), None)
            if not model_meta:
                self.state = "error"
                self.load_message = f"Model bulunamadı: {model_id}"
                raise ValueError(self.load_message)

            if self.model is not None:
                self._unload_locked()

            self.state = "loading"
            self.active_model_id = model_id
            self.active_lora_id = lora_id or ""
            self.applied_lora_scale = float(lora_scale)
            self.load_message = "PyTorch & CUDA hazırlanıyor..."

        try:
            import torch
            from accelerate.hooks import remove_hook_from_module
            from transformers import AutoConfig, AutoProcessor, Gemma4ForConditionalGeneration

            self.torch = torch
            device = "cuda" if torch.cuda.is_available() else "cpu"
            total_vram_mb = 0
            if device == "cuda":
                total_vram_mb = int(torch.cuda.get_device_properties(0).total_memory / (1024 * 1024))
                torch.backends.cuda.matmul.allow_tf32 = True
                torch.backends.cudnn.allow_tf32 = True

            cfg = load_json(CONFIG_PATH, {})
            user_prof = cfg.get("gpu_profile", "auto")
            if user_prof in ("turbo", "low_vram"):
                profile = user_prof
            elif total_vram_mb > 0 and total_vram_mb <= 5000:
                profile = "low_vram"
            else:
                profile = "turbo"

            self.active_profile = profile
            self.detected_vram_mb = total_vram_mb

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
            }
            if device == "cuda":
                compute_dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16
                load_kwargs["dtype"] = compute_dtype
                if profile == "low_vram" and int(model_meta.get("vram_estimate_mb", 3000)) > 3600:
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

            # Pin PLE lookup table in CPU RAM so token lookups transfer 17 KB instead of 4.48 GB per step
            if device == "cuda":
                lm = getattr(getattr(model, "model", model), "language_model", None)
                ple = getattr(lm, "embed_tokens_per_layer", None) if lm is not None else None
                if ple is not None and hasattr(ple, "_hf_hook") and hasattr(ple._hf_hook, "weights_map"):
                    cpu_w = ple._hf_hook.weights_map["weight"].detach().to("cpu")
                    remove_hook_from_module(ple)
                    ple.weight = torch.nn.Parameter(cpu_w, requires_grad=False)
                    orig_ple_fwd = ple.forward

                    def _fast_cpu_ple(input_ids, _orig=orig_ple_fwd):
                        return _orig(input_ids.to("cpu")).to(input_ids.device, non_blocking=True)

                    ple.forward = _fast_cpu_ple

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

            tok = processor.tokenizer
            self.channel_tokens = {
                "thought_close": tok.convert_tokens_to_ids("<channel|>"),
                "turn_close": tok.convert_tokens_to_ids("<turn|>"),
                "eos": tok.eos_token_id if tok.eos_token_id is not None else 1,
            }

            profile_tag = "Low-VRAM 4GB" if profile == "low_vram" else "Turbo GPU"
            with self.lock:
                self.model = model
                self.processor = processor
                self.state = "ready"
                self.active_model_id = model_id
                self.load_message = f"Hazır · {model_meta['name']}{lora_note} ({profile_tag})"
                self.touch()
            logger.info("Model ready: %s%s", model_id, lora_note)
        except Exception as exc:
            logger.exception("Failed to load model %s", model_id)
            with self.lock:
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

    if ext in IMAGE_EXTS:
        from PIL import Image
        with Image.open(file_path) as im:
            w, h = im.size
        return {
            "id": uuid.uuid4().hex[:10],
            "name": orig_name,
            "saved_name": saved_name,
            "path": str(file_path),
            "kind": "image",
            "ext": ext,
            "size_bytes": size_bytes,
            "preview_url": preview_url,
            "summary": f"Görsel ({w}×{h}px)",
            "context_text": "",
        }

    if ext in AUDIO_EXTS:
        import librosa
        wav, sr = librosa.load(str(file_path), sr=16000, mono=True)
        duration_sec = round(len(wav) / 16000.0, 2)
        return {
            "id": uuid.uuid4().hex[:10],
            "name": orig_name,
            "saved_name": saved_name,
            "path": str(file_path),
            "kind": "audio",
            "ext": ext,
            "size_bytes": size_bytes,
            "duration_sec": duration_sec,
            "preview_url": preview_url,
            "summary": f"Ses kaydı ({duration_sec} sn · 16kHz)",
            "context_text": "",
        }

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

        for sheet_name, df in sheets.items():
            rows, cols = df.shape
            sheet_summaries.append(f"{sheet_name}: {rows} satır × {cols} sütun")
            col_info = ", ".join(f"{c} ({df[c].dtype})" for c in df.columns)
            parts.append(f"\n#### Sayfa: `{sheet_name}` ({rows} satır × {cols} sütun)")
            parts.append(f"- Sütunlar: {col_info}")

            num_df = df.select_dtypes(include="number")
            if not num_df.empty:
                desc_md = num_df.describe().round(2).to_markdown()
                parts.append(f"\n**Sayısal Özet İstatistikler:**\n{desc_md}")

            preview_rows = df.head(60)
            table_md = preview_rows.fillna("").to_markdown(index=False)
            parts.append(f"\n**Veri Önizleme (İlk {len(preview_rows)} satır):**\n{table_md}")
            if rows > 60:
                parts.append(f"\n*(Not: Tabloda toplam {rows} satır var; ilk 60 satır gösterildi.)*")

        full_text = "\n".join(parts)
        return {
            "id": uuid.uuid4().hex[:10],
            "name": orig_name,
            "saved_name": saved_name,
            "path": str(file_path),
            "kind": "document",
            "doc_type": "excel",
            "ext": ext,
            "size_bytes": size_bytes,
            "preview_url": preview_url,
            "summary": " · ".join(sheet_summaries),
            "context_text": full_text[:28000],
        }

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
        return {
            "id": uuid.uuid4().hex[:10],
            "name": orig_name,
            "saved_name": saved_name,
            "path": str(file_path),
            "kind": "document",
            "doc_type": "pdf",
            "ext": ext,
            "size_bytes": size_bytes,
            "preview_url": preview_url,
            "summary": f"PDF ({page_count} sayfa · {len(full_text)} karakter)",
            "context_text": full_text[:28000],
        }

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
        return {
            "id": uuid.uuid4().hex[:10],
            "name": orig_name,
            "saved_name": saved_name,
            "path": str(file_path),
            "kind": "document",
            "doc_type": "word",
            "ext": ext,
            "size_bytes": size_bytes,
            "preview_url": preview_url,
            "summary": f"Word ({len(d.paragraphs)} paragraf, {len(d.tables)} tablo)",
            "context_text": full_text[:28000],
        }

    # Code / plain text fallback
    try:
        raw = file_path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        raw = file_path.read_text(encoding="latin1", errors="replace")
    lang_tag = ext.lstrip(".") if ext else "text"
    full_text = f"### Kod / Metin Dosyası: {orig_name}\n```{lang_tag}\n{raw[:26000]}\n```"
    return {
        "id": uuid.uuid4().hex[:10],
        "name": orig_name,
        "saved_name": saved_name,
        "path": str(file_path),
        "kind": "document",
        "doc_type": "code" if ext in CODE_AND_TEXT_EXTS else "text",
        "ext": ext,
        "size_bytes": size_bytes,
        "preview_url": preview_url,
        "summary": f"{lang_tag.upper()} ({len(raw.splitlines())} satır)",
        "context_text": full_text,
    }


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
    system_prompt: Optional[str] = None
    generation: Optional[Dict[str, Any]] = None


class LoadModelRequest(BaseModel):
    model_id: str
    lora_id: Optional[str] = ""
    lora_scale: Optional[float] = 1.0


class ChatAttachment(BaseModel):
    id: str
    name: str
    kind: str  # image | audio | document
    path: Optional[str] = None
    preview_url: Optional[str] = None
    summary: Optional[str] = None
    context_text: Optional[str] = None


class ChatMessageInput(BaseModel):
    role: str
    content: str
    thinking: Optional[str] = ""
    attachments: Optional[List[ChatAttachment]] = None


class ChatRequest(BaseModel):
    session_id: Optional[str] = None
    model_id: Optional[str] = None
    lora_id: Optional[str] = None
    lora_scale: Optional[float] = None
    thinking_effort: Optional[str] = "medium"
    temperature: Optional[float] = None
    top_p: Optional[float] = None
    max_new_tokens: Optional[int] = None
    system_prompt: Optional[str] = None
    messages: List[ChatMessageInput]


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
    try:
        yield
    finally:
        task.cancel()


app = FastAPI(title="YerelAI Studio API", version="1.0.0", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/api/status")
async def api_status():
    return engine.get_status()


@app.get("/api/models")
async def api_models():
    reg = load_json(REGISTRY_PATH, {"models": []})
    models = []
    for m in reg.get("models", []):
        entry = dict(m)
        snap = _resolve_local_hf_snapshot(m["hf_repo"])
        entry["cached_locally"] = snap is not None
        entry["local_snapshot"] = str(snap) if snap else ""
        models.append(entry)
    return {
        "models": models,
        "loras": _list_lora_adapters(),
        "vram": engine.get_vram_info(),
    }


@app.get("/api/config")
async def api_get_config():
    return load_json(CONFIG_PATH, {})


@app.put("/api/config")
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
        args=(req.model_id, req.lora_id or "", float(req.lora_scale if req.lora_scale is not None else 1.0)),
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


@app.post("/api/chat/stop")
async def api_stop_chat():
    engine.stop_event.set()
    return {"ok": True}


@app.post("/api/files/upload")
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


@app.post("/api/chat")
async def api_chat(req: ChatRequest):
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
    answer_max_tokens = int(_clamp(req.max_new_tokens if req.max_new_tokens is not None else gen_cfg.get("max_new_tokens", 2048), 64, 4096))
    system_prompt = req.system_prompt if req.system_prompt is not None else cfg.get("system_prompt", "")

    async def event_stream():
        engine.stop_event.clear()
        try:
            need_load = (
                engine.model is None
                or engine.active_model_id != model_id
                or engine.active_lora_id != (lora_id or "")
                or abs(engine.applied_lora_scale - lora_scale) > 1e-3
            )
            if need_load:
                yield _format_sse({"type": "status", "stage": "loading", "message": f"{model_id} GPU'ya yükleniyor..."})
                await asyncio.to_thread(engine.load_model, model_id, lora_id or "", lora_scale)

            with engine.lock:
                engine.state = "generating"
                engine.touch()
                model = engine.model
                processor = engine.processor
                torch = engine.torch

            yield _format_sse({"type": "status", "stage": "preparing", "message": "Bağlam ve medya hazırlanıyor..."})

            import librosa
            from PIL import Image
            from transformers import LogitsProcessor, LogitsProcessorList, StoppingCriteria, StoppingCriteriaList, TextIteratorStreamer

            images_list: List[Any] = []
            audios_list: List[Any] = []
            chat_messages: List[Dict[str, Any]] = []

            if system_prompt and system_prompt.strip():
                chat_messages.append({"role": "system", "content": system_prompt.strip()})

            files_db = load_json(FILES_META_PATH, {})
            for m in req.messages:
                role = "assistant" if m.role == "assistant" else "user"
                atts = m.attachments or []
                if role == "user" and atts:
                    content_parts: List[Dict[str, Any]] = []
                    doc_blocks: List[str] = []
                    for att in atts:
                        meta = files_db.get(att.id, {})
                        fpath = Path(att.path or meta.get("path") or "")
                        if att.kind == "image" and fpath.exists():
                            images_list.append(Image.open(fpath).convert("RGB"))
                            content_parts.append({"type": "image"})
                        elif att.kind == "audio" and fpath.exists():
                            wav, _ = librosa.load(str(fpath), sr=16000, mono=True)
                            audios_list.append(wav.astype("float32"))
                            content_parts.append({"type": "audio"})
                        elif att.kind == "document":
                            ctx = att.context_text or meta.get("context_text") or ""
                            if ctx:
                                doc_blocks.append(ctx)

                    text_body = m.content.strip()
                    if doc_blocks:
                        joined_docs = "\n\n---\n\n".join(doc_blocks)
                        text_body = f"{joined_docs}\n\n---\n\nKullanıcı İsteği:\n{text_body or 'Bu dokümanı/tabloyu detaylı incele ve özetle.'}"
                    if not text_body and audios_list:
                        text_body = "Bu ses kaydını dinle, ne söylendiğini anla ve doğrudan yanıtla."
                    elif not text_body and images_list:
                        text_body = "Bu görseli incele ve Türkçe açıkla."
                    content_parts.append({"type": "text", "text": text_body})
                    chat_messages.append({"role": "user", "content": content_parts})
                else:
                    chat_messages.append({"role": role, "content": m.content})

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

            total_max_tokens = min(4096, answer_max_tokens + think_budget)
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
            chunk_count = 0

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
                chunk_count += 1
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
                    "vram": engine.get_vram_info(),
                },
            })
        except Exception as exc:
            logger.exception("SSE chat error")
            yield _format_sse({"type": "error", "detail": str(exc)})
        finally:
            with engine.lock:
                if engine.model is not None:
                    engine.state = "ready"
                    engine.touch()
                else:
                    engine.state = "unloaded"

    return StreamingResponse(event_stream(), media_type="text/event-stream")


@app.get("/api/sessions")
async def api_list_sessions():
    sessions = load_json(SESSIONS_PATH, [])
    return {"sessions": sessions}


@app.post("/api/sessions")
async def api_save_session(req: SaveSessionRequest):
    sessions = load_json(SESSIONS_PATH, [])
    now_iso = req.updated_at or datetime.now().isoformat(timespec="seconds")
    updated = {
        "id": req.id,
        "title": req.title[:80] or "Yeni Sohbet",
        "messages": req.messages,
        "updated_at": now_iso,
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


@app.get("/api/dataset")
async def api_list_dataset():
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
    return {"entries": entries, "count": len(entries)}


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
async def api_export_dataset():
    if not DATASET_PATH.exists():
        return Response(
            content="",
            media_type="application/x-ndjson",
            headers={"Content-Disposition": 'attachment; filename="yerelai_unsloth_dataset.jsonl"'},
        )
    lines: List[str] = []
    with open(DATASET_PATH, "r", encoding="utf-8") as f:
        for line in f:
            raw = line.strip()
            if not raw:
                continue
            try:
                obj = json.loads(raw)
                lines.append(json.dumps({"messages": obj["messages"]}, ensure_ascii=False))
            except Exception:
                continue
    content = "\n".join(lines) + ("\n" if lines else "")
    return Response(
        content=content.encode("utf-8"),
        media_type="application/x-ndjson",
        headers={"Content-Disposition": 'attachment; filename="yerelai_unsloth_dataset.jsonl"'},
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
    """Offline Windows speech synthesis fallback (no VRAM used)."""
    text = str(payload.get("text", "")).strip()
    if not text:
        raise HTTPException(status_code=400, detail="Metin boş.")
    import subprocess
    import tempfile

    clean_text = re.sub(r"```[\s\S]*?```", " kod bloğu ", text)
    clean_text = re.sub(r"[`*_#>\[\]()]", " ", clean_text)[:1200]
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        wav_path = tf.name
    try:
        ps_script = (
            "Add-Type -AssemblyName System.Speech; "
            "$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; "
            "$v = $s.GetInstalledVoices() | Where-Object { $_.VoiceInfo.Culture.Name -like 'tr*' } | Select-Object -First 1; "
            "if ($v) { $s.SelectVoice($v.VoiceInfo.Name) }; "
            f"$s.SetOutputToWaveFile('{wav_path}'); "
            "$txt = [Console]::In.ReadToEnd(); "
            "$s.Speak($txt); $s.Dispose();"
        )
        proc = await asyncio.to_thread(
            subprocess.run,
            ["powershell", "-NoProfile", "-Command", ps_script],
            input=clean_text.encode("utf-8"),
            capture_output=True,
            timeout=20,
        )
        if proc.returncode != 0 or not os.path.exists(wav_path) or os.path.getsize(wav_path) < 100:
            raise RuntimeError("Windows SAPI ses üretimi başarısız.")
        data = Path(wav_path).read_bytes()
        return Response(content=data, media_type="audio/wav")
    finally:
        try:
            os.unlink(wav_path)
        except OSError:
            pass


if FRONTEND_DIR.exists():
    app.mount("/", StaticFiles(directory=str(FRONTEND_DIR), html=True), name="frontend")


if __name__ == "__main__":
    if sys.stdout is None:
        sys.stdout = open(os.devnull, "w", encoding="utf-8")
    if sys.stderr is None:
        sys.stderr = open(os.devnull, "w", encoding="utf-8")
    uvicorn.run(app, host="127.0.0.1", port=8070, log_config=None)
