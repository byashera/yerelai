"""YerelAI Studio — Built-in Zero-Dependency Python MCP Server (JSON-RPC 2.0 over stdio).

Provides 4 offline-ready MCP tool suites out of the box without requiring external
`npx` or `uvx` package downloads:
  1. --mode filesystem --root <dir>
  2. --mode sqlite     --db <file.db>
  3. --mode git        --repo <dir>
  4. --mode fetch
"""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.request
from pathlib import Path
from typing import Any, Dict, List


def _safe_path(root: Path, rel: str) -> Path:
    clean = (rel or ".").strip().lstrip("/\\")
    target = (root / clean).resolve()
    target.relative_to(root.resolve())
    return target


def get_tools(mode: str) -> List[Dict[str, Any]]:
    if mode == "filesystem":
        return [
            {"name": "list_directory", "description": "Klasördeki dosya ve alt klasörleri listeler (parametre: path)"},
            {"name": "read_text_file", "description": "Metin dosyasının içeriğini okur (parametre: path)"},
            {"name": "search_files", "description": "Dosya adlarında veya içeriklerinde kelime arar (parametre: query)"},
        ]
    if mode == "sqlite":
        return [
            {"name": "list_tables", "description": "SQLite veritabanındaki tabloları ve şemalarını listeler"},
            {"name": "query_sql", "description": "Salt okunur SELECT SQL sorgusu çalıştırır (parametre: sql)"},
        ]
    if mode == "git":
        return [
            {"name": "git_status", "description": "Git çalışma alanı durumunu ve aktif dalı (branch) döndürür"},
            {"name": "git_log", "description": "Son commit geçmişini listeler (parametre: limit)"},
            {"name": "git_diff", "description": "Çalışma alanındaki güncel kod farklarını (diff) döndürür"},
        ]
    if mode == "fetch":
        return [
            {"name": "fetch_webpage", "description": "Verilen URL adresindeki web sayfasını temiz metin olarak çeker (parametre: url)"},
        ]
    return []


def run_tool(mode: str, root_or_db: str, name: str, args: Dict[str, Any]) -> str:
    if mode == "filesystem":
        base = Path(root_or_db or ".").expanduser().resolve()
        if not base.exists():
            return f"Klasör bulunamadı: {base}"
        if name == "list_directory":
            target = _safe_path(base, str(args.get("path") or "."))
            if not target.is_dir():
                return f"Klasör değil: {target.name}"
            entries = []
            for p in sorted(target.iterdir(), key=lambda x: (not x.is_dir(), x.name.lower()))[:80]:
                kind = "[KLASÖR]" if p.is_dir() else f"({p.stat().st_size} B)"
                entries.append(f"{p.name} {kind}")
            return "\n".join(entries) if entries else "(Klasör boş)"
        if name == "read_text_file":
            target = _safe_path(base, str(args.get("path") or ""))
            if not target.is_file():
                return f"Dosya bulunamadı: {target.name}"
            return target.read_text(encoding="utf-8", errors="replace")[:12000]
        if name == "search_files":
            q = str(args.get("query") or "").strip().lower()
            if not q:
                return "Arama terimi (query) boş."
            hits = []
            for p in base.rglob("*"):
                if len(hits) >= 30:
                    break
                if p.is_file() and q in p.name.lower():
                    hits.append(str(p.relative_to(base)))
            return "\n".join(hits) if hits else "Eşleşen dosya bulunamadı."

    elif mode == "sqlite":
        db_path = Path(root_or_db or "veri.db").expanduser().resolve()
        if not db_path.exists():
            return f"SQLite dosyası henüz mevcut değil: {db_path}"
        conn = sqlite3.connect(str(db_path))
        try:
            cur = conn.cursor()
            if name == "list_tables":
                rows = cur.execute("SELECT name, sql FROM sqlite_master WHERE type='table'").fetchall()
                return "\n\n".join(f"{r[0]}:\n{r[1]}" for r in rows) if rows else "(Tablo yok)"
            if name == "query_sql":
                sql = str(args.get("sql") or "").strip()
                if not sql.lower().startswith("select"):
                    return "Güvenlik kuralı: Yalnızca SELECT sorgularına izin verilir."
                rows = cur.execute(sql).fetchmany(50)
                cols = [d[0] for d in (cur.description or [])]
                return json.dumps({"columns": cols, "rows": rows}, ensure_ascii=False, indent=2)
        finally:
            conn.close()

    elif mode == "git":
        repo = Path(root_or_db or ".").expanduser().resolve()
        if not repo.exists():
            return f"Proje klasörü bulunamadı: {repo}"
        git_dir = repo / ".git"
        if not git_dir.exists():
            return f"Bilgi: '{repo.name}' klasöründe henüz .git deposu başlatılmamış (git init yapılmamış)."
        flags = 0x08000000 if os.name == "nt" else 0
        def _git(cmd_args: List[str]) -> str:
            try:
                pr = subprocess.run(
                    ["git", *cmd_args],
                    cwd=str(repo),
                    capture_output=True,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    timeout=5,
                    creationflags=flags,
                )
                return (pr.stdout or pr.stderr or "").strip()
            except FileNotFoundError:
                head_file = git_dir / "HEAD"
                head_txt = head_file.read_text(encoding="utf-8", errors="replace").strip() if head_file.exists() else "HEAD"
                return f"Git durum bilgisi (.git/HEAD): {head_txt}"
            except Exception as exc:
                return f"Git komutu çalıştırılamadı: {exc}"

        if name == "git_status":
            return _git(["status", "--short", "--branch"]) or "Çalışma ağacı temiz."
        if name == "git_log":
            lim = max(1, min(30, int(args.get("limit") or 10)))
            return _git(["log", f"-n{lim}", "--oneline"])
        if name == "git_diff":
            return (_git(["diff", "--stat"]) or "Bekleyen fark (diff) yok.")[:8000]

    elif mode == "fetch":
        if name == "fetch_webpage":
            url = str(args.get("url") or "").strip()
            if not url.startswith(("http://", "https://")):
                return "Geçerli bir http:// veya https:// URL adresi girin."
            req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 YerelAI-MCP/1.0"})
            with urllib.request.urlopen(req, timeout=10) as resp:
                raw_html = resp.read().decode("utf-8", errors="replace")
            cleaned = re.sub(r"<(script|style)[^>]*>[\s\S]*?</\1>", " ", raw_html, flags=re.I)
            cleaned = re.sub(r"<[^>]+>", " ", cleaned)
            cleaned = html.unescape(re.sub(r"\s+", " ", cleaned)).strip()
            return cleaned[:10000]

    return f"Bilinmeyen araç: {name}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", default="filesystem")
    parser.add_argument("--root", default=".")
    parser.add_argument("--db", default="veri.db")
    parser.add_argument("--repo", default=".")
    ns, _ = parser.parse_known_args()

    target_path = ns.db if ns.mode == "sqlite" else (ns.repo if ns.mode == "git" else ns.root)

    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line.startswith("{"):
            continue
        try:
            msg = json.loads(line)
        except Exception:
            continue
        req_id = msg.get("id")
        method = msg.get("method")
        params = msg.get("params") or {}

        if method == "initialize":
            resp = {
                "jsonrpc": "2.0",
                "id": req_id,
                "result": {
                    "protocolVersion": "2024-11-05",
                    "capabilities": {"tools": {}},
                    "serverInfo": {"name": f"yerelai-builtin-{ns.mode}", "version": "13.0"},
                },
            }
            print(json.dumps(resp, ensure_ascii=False), flush=True)
        elif method == "tools/list":
            resp = {"jsonrpc": "2.0", "id": req_id, "result": {"tools": get_tools(ns.mode)}}
            print(json.dumps(resp, ensure_ascii=False), flush=True)
        elif method == "tools/call":
            t_name = str(params.get("name") or "")
            t_args = params.get("arguments") if isinstance(params.get("arguments"), dict) else {}
            try:
                out_text = run_tool(ns.mode, target_path, t_name, t_args)
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": [{"type": "text", "text": out_text}], "isError": False},
                }
            except Exception as exc:
                resp = {
                    "jsonrpc": "2.0",
                    "id": req_id,
                    "result": {"content": [{"type": "text", "text": f"Hata: {exc}"}], "isError": True},
                }
            print(json.dumps(resp, ensure_ascii=False), flush=True)


if __name__ == "__main__":
    main()
