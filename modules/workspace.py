"""YerelAI Studio — Local Folder Workspace (Claude Code / Cowork Engine).

Provides safe, sandboxed read/list/write/git operations strictly inside the
user-selected local project folder.
"""

from __future__ import annotations

import json
import os
import subprocess
import threading
from pathlib import Path
from typing import Any, Dict, List, Optional

SKIP_DIRS = {
    ".git",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
    ".mypy_cache",
    ".pytest_cache",
    ".next",
    ".nuxt",
    "dist",
    "build",
    ".cloudflared",
    "models",
    ".idea",
    ".vs",
}

TEXT_EXTS = {
    ".py", ".js", ".ts", ".tsx", ".jsx", ".html", ".htm", ".css", ".scss",
    ".json", ".md", ".txt", ".yml", ".yaml", ".toml", ".ini", ".env",
    ".sql", ".sh", ".bat", ".ps1", ".xml", ".svg", ".csv", ".c", ".cpp",
    ".h", ".hpp", ".cs", ".java", ".go", ".rs", ".php", ".rb", ".vue",
}


class LocalWorkspaceManager:
    def __init__(self, data_dir: Path):
        self.data_dir = Path(data_dir)
        self.data_dir.mkdir(parents=True, exist_ok=True)
        self.state_path = self.data_dir / "workspace.json"
        self.lock = threading.RLock()

    def _load_root(self) -> Optional[Path]:
        if not self.state_path.exists():
            return None
        try:
            raw = json.loads(self.state_path.read_text(encoding="utf-8"))
            p = raw.get("root")
            if p and Path(p).is_dir():
                return Path(p).resolve()
        except Exception:
            pass
        return None

    def _save_root(self, root: Optional[Path]) -> None:
        self.state_path.write_text(
            json.dumps({"root": str(root) if root else None}, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )

    def _safe_resolve(self, rel_path: str) -> Path:
        root = self._load_root()
        if not root:
            raise ValueError("Aktif bir yerel çalışma alanı klasörü seçili değil.")
        clean = (rel_path or "").strip().lstrip("/\\")
        if not clean:
            raise ValueError("Dosya yolu boş olamaz.")
        target = (root / clean).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            raise ValueError("Güvenlik engeli: Çalışma alanı dışındaki dosyalara erişilemez.")
        return target

    def set_root(self, folder_path: str) -> Dict[str, Any]:
        p = Path((folder_path or "").strip()).expanduser()
        if not p.exists() or not p.is_dir():
            raise ValueError("Geçerli bir klasör yolu bulunamadı.")
        resolved = p.resolve()
        with self.lock:
            self._save_root(resolved)
        return self.get_state()

    def close(self) -> Dict[str, Any]:
        with self.lock:
            self._save_root(None)
        return self.get_state()

    def list_files(self, max_files: int = 220) -> List[Dict[str, Any]]:
        root = self._load_root()
        if not root:
            return []
        results: List[Dict[str, Any]] = []
        for cur_dir, dirs, files in os.walk(root):
            dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith("."))
            rel_dir = Path(cur_dir).relative_to(root)
            if len(rel_dir.parts) > 4:
                dirs[:] = []
                continue
            for fn in sorted(files):
                if fn.startswith(".") and fn not in (".env.example", ".gitignore"):
                    continue
                fp = Path(cur_dir) / fn
                ext = fp.suffix.lower()
                if ext and ext not in TEXT_EXTS:
                    continue
                try:
                    sz = fp.stat().st_size
                except OSError:
                    continue
                if sz > 512 * 1024:
                    continue
                rel = (rel_dir / fn).as_posix() if str(rel_dir) != "." else fn
                results.append({"path": rel, "name": fn, "size": sz, "ext": ext.lstrip(".") or "txt"})
                if len(results) >= max_files:
                    return results
        return results

    def get_git_summary(self) -> Dict[str, Any]:
        root = self._load_root()
        if not root or not (root / ".git").exists():
            return {"is_git": False, "branch": "", "status": "", "diff_stat": ""}
        flags = 0x08000000 if os.name == "nt" else 0
        def _run_git(args: List[str]) -> str:
            try:
                proc = subprocess.run(
                    ["git", *args],
                    cwd=str(root),
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=4,
                    creationflags=flags,
                )
                return (proc.stdout or "").strip()
            except Exception:
                return ""
        return {
            "is_git": True,
            "branch": _run_git(["rev-parse", "--abbrev-ref", "HEAD"]),
            "status": _run_git(["status", "--short"])[:4000],
            "diff_stat": _run_git(["diff", "--stat"])[:3000],
        }

    def get_state(self) -> Dict[str, Any]:
        root = self._load_root()
        if not root:
            return {"open": False, "root": None, "name": None, "is_git": False, "files": []}
        return {
            "open": True,
            "root": str(root),
            "name": root.name,
            "is_git": (root / ".git").exists(),
            "files": self.list_files(),
        }

    def read_file(self, rel_path: str) -> Dict[str, Any]:
        target = self._safe_resolve(rel_path)
        if not target.exists() or not target.is_file():
            raise FileNotFoundError("Dosya bulunamadı.")
        if target.stat().st_size > 256 * 1024:
            raise ValueError("Dosya boyutu 256 KB sınırını aşıyor.")
        content = target.read_text(encoding="utf-8", errors="replace")
        return {
            "ok": True,
            "path": rel_path.replace("\\", "/"),
            "name": target.name,
            "ext": target.suffix.lstrip(".").lower() or "txt",
            "content": content,
        }

    def write_file(self, rel_path: str, content: str) -> Dict[str, Any]:
        target = self._safe_resolve(rel_path)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(str(content), encoding="utf-8")
        return {
            "ok": True,
            "path": rel_path.replace("\\", "/"),
            "bytes": len(str(content).encode("utf-8")),
        }
