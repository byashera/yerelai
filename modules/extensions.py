"""YerelAI Studio — Plugins & Skills (Eklentiler & Beceriler) Manager."""
from __future__ import annotations

import ast
import json
import operator
import os
import re
import uuid
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

BASE_DIR = Path(__file__).resolve().parent.parent
DATA_DIR = BASE_DIR / "data"
SKILLS_DIR = BASE_DIR / "skills"
EXT_STATE_PATH = DATA_DIR / "extensions_state.json"
NOTES_PATH = DATA_DIR / "notes.json"
PROJECTS_PATH = DATA_DIR / "projects.json"

DATA_DIR.mkdir(parents=True, exist_ok=True)
SKILLS_DIR.mkdir(parents=True, exist_ok=True)

DEFAULT_SKILLS: List[Dict[str, str]] = [
    {
        "slug": "web-tasarimci",
        "name": "Web & UI Tasarımcısı",
        "description": "Apple, Linear ve Vercel kalitesinde 12-sütun Bento Grid, çalışan tema/filtre/modal etkileşimli tek dosya HTML/CSS/JS üretir.",
        "body": (
            "Sen kıdemli bir Ürün ve UI/UX Mühendisisin. "
            "Kullanıcı yalnızca 'neler ekleyebilirsin / geliştirme yapamaz mısın?' diye fikir soruyorsa ASLA kod yazma; 3-5 maddelik öneri sun ve onay iste. "
            "Kod istendiğinde Apple/Linear/Vercel kalitesinde tek dosya HTML/CSS/JS üret: "
            "12 sütunlu asimetrik Bento Grid (span 8 / span 4), çalışan Koyu/Açık Tema butonu, Kategori Filtre sekmeleri, "
            "kartlara tıklayınca açılan şık Detay Modalı, her karta özel farklı inline SVG ikon kullan; ASLA alert() veya [Adınız] yer tutucusu kullanma. "
            "Kod bloğundan sonra mutlaka 3-4 maddelik kısa Türkçe özet yaz."
        ),
    },
    {
        "slug": "excel-uzmani",
        "name": "Excel & Veri Uzmanı",
        "description": "Temiz Markdown tabloları, özet metrikler ve otomatik .xlsx indirilebilir çıktılar üretir.",
        "body": (
            "Verileri düzenli Markdown tabloları halinde sun. "
            "Toplam, ortalama, yüzde payı ve net aksiyon önerileri ekle; HTML tablo veya LaTeX kullanma. "
            "Kullanıcıya 'kopyala/çalıştır' veya 'LocalAI Studio' gibi teknik talimatlar yazma; doğrudan tabloyu ve kısa analizi sun."
        ),
    },
    {
        "slug": "kod-inceleyici",
        "name": "Kod İnceleyici (Security & Clean Code)",
        "description": "Verilen kodu güvenlik, performans, hata riski ve okunabilirlik açısından denetler.",
        "body": (
            "Verilen kodu şu 4 başlıkta kısa ve net incele: 1) Kritik Hatalar/Güvenlik, "
            "2) Performans İyileştirmeleri, 3) Temiz Kod & Mimari, 4) Düzeltilmiş Örnek Kod."
        ),
    },
    {
        "slug": "eposta-yazari",
        "name": "Profesyonel E-Posta Yazarı",
        "description": "Konu satırı ve tonuyla hazır kurumsal veya samimi Türkçe/İngilizce e-postalar yazar.",
        "body": (
            "Kullanıcının belirttiği amaca uygun net bir Konu başlığı ve akıcı, gereksiz uzatmasız, "
            "doğrudan gönderilmeye hazır profesyonel e-posta metni yaz."
        ),
    },
]

BUILTIN_PLUGINS: List[Dict[str, Any]] = [
    {
        "id": "notes_todo",
        "name": "Notlar & Yapılacaklar",
        "description": "Sohbette 'not al: ...' veya 'yapılacak ekle: ...' dediğinizde yerel not defterine kaydeder.",
        "icon": "notes",
        "default_enabled": True,
    },
    {
        "id": "datetime_tr",
        "name": "Canlı Tarih & Saat",
        "description": "Modelin her sohbette güncel Türkiye tarih, gün ve saatini doğru bilmesini sağlar.",
        "icon": "clock",
        "default_enabled": True,
    },
    {
        "id": "calculator",
        "name": "Hassas Hesaplayıcı",
        "description": "Matematiksel ifadeleri yerel Python AST motoruyla hatasız hesaplar.",
        "icon": "calc",
        "default_enabled": True,
    },
    {
        "id": "python_sandbox",
        "name": "Yerel Python Çalıştırıcı",
        "description": "Python kod kartlarında tek tıkla güvenli yerel çalıştırma ve çıktı/grafik önizleme sunar.",
        "icon": "terminal",
        "default_enabled": True,
    },
    {
        "id": "web_bridge",
        "name": "Canlı Web & Döviz Köprüsü",
        "description": "İnternet araştırması, hava durumu ve canlı döviz kurları araçlarını etkinleştirir.",
        "icon": "globe",
        "default_enabled": True,
    },
    {
        "id": "webhook_custom",
        "name": "Özel Webhook Eklentisi",
        "description": "Kendi yerel/HTTP webhook ucunuza (n8n, Make, Home Assistant) JSON bildirim gönderir.",
        "icon": "webhook",
        "default_enabled": False,
    },
]


def _load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return default


def _save_json(path: Path, data: Any) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def _slugify(text: str) -> str:
    tr_map = str.maketrans("ğüşıöçĞÜŞİÖÇ", "gusiocGUSIOC")
    s = (text or "").translate(tr_map).lower()
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s[:40] or f"beceri-{uuid.uuid4().hex[:5]}"


def ensure_default_skills() -> None:
    if any(SKILLS_DIR.glob("*/SKILL.md")):
        return
    for sk in DEFAULT_SKILLS:
        folder = SKILLS_DIR / sk["slug"]
        folder.mkdir(parents=True, exist_ok=True)
        md_content = (
            f"---\n"
            f"name: {sk['name']}\n"
            f"description: {sk['description']}\n"
            f"---\n\n"
            f"{sk['body']}\n"
        )
        (folder / "SKILL.md").write_text(md_content, encoding="utf-8")


def _parse_skill_md(path: Path) -> Dict[str, Any]:
    raw = path.read_text(encoding="utf-8", errors="replace").strip()
    slug = path.parent.name
    name = slug.replace("-", " ").title()
    desc = ""
    body = raw
    m = re.match(r"^---\s*\n([\s\S]*?)\n---\s*\n([\s\S]*)$", raw)
    if m:
        fm, body = m.group(1), m.group(2).strip()
        for ln in fm.splitlines():
            if ":" in ln:
                k, v = ln.split(":", 1)
                k = k.strip().lower()
                v = v.strip().strip("\"'")
                if k == "name" and v:
                    name = v
                elif k == "description" and v:
                    desc = v
    if not desc:
        desc = (body.splitlines()[0] if body else "Özel Beceri")[:120]
    return {
        "id": slug,
        "slug": slug,
        "name": name,
        "description": desc,
        "body": body[:2000],
        "path": str(path),
    }


def _load_ext_state() -> Dict[str, Any]:
    st = _load_json(EXT_STATE_PATH, {})
    if not isinstance(st, dict):
        st = {}
    st.setdefault("plugins", {})
    st.setdefault("skills", {})
    st.setdefault("webhook_url", "")
    return st


def list_extensions() -> Dict[str, Any]:
    ensure_default_skills()
    st = _load_ext_state()

    plugins = []
    for p in BUILTIN_PLUGINS:
        pid = p["id"]
        enabled = bool(st["plugins"].get(pid, p["default_enabled"]))
        entry = {**p, "enabled": enabled}
        if pid == "webhook_custom":
            entry["webhook_url"] = st.get("webhook_url", "")
        plugins.append(entry)

    skills = []
    for sk_file in sorted(SKILLS_DIR.glob("*/SKILL.md")):
        try:
            sk = _parse_skill_md(sk_file)
            sk["enabled"] = bool(st["skills"].get(sk["id"], True))
            skills.append(sk)
        except Exception:
            continue

    return {
        "plugins": plugins,
        "skills": skills,
        "notes": list_notes(),
        "webhook_url": st.get("webhook_url", ""),
    }


def toggle_plugin(plugin_id: str, enabled: bool, webhook_url: Optional[str] = None) -> Dict[str, Any]:
    st = _load_ext_state()
    st["plugins"][plugin_id] = bool(enabled)
    if webhook_url is not None:
        st["webhook_url"] = webhook_url.strip()[:300]
    _save_json(EXT_STATE_PATH, st)
    return list_extensions()


def toggle_skill(skill_id: str, enabled: bool) -> Dict[str, Any]:
    st = _load_ext_state()
    st["skills"][skill_id] = bool(enabled)
    _save_json(EXT_STATE_PATH, st)
    return list_extensions()


def save_skill(name: str, description: str, body: str, raw_markdown: Optional[str] = None) -> Dict[str, Any]:
    ensure_default_skills()
    if raw_markdown and raw_markdown.strip():
        clean_raw = raw_markdown.strip()
        m_name = re.search(r"^name\s*:\s*(.+)$", clean_raw, re.M | re.I)
        slug = _slugify(m_name.group(1).strip() if m_name else (name or "ozel-beceri"))
        folder = SKILLS_DIR / slug
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "SKILL.md").write_text(clean_raw + "\n", encoding="utf-8")
    else:
        slug = _slugify(name or "ozel-beceri")
        folder = SKILLS_DIR / slug
        folder.mkdir(parents=True, exist_ok=True)
        md = f"---\nname: {name.strip()[:80]}\ndescription: {description.strip()[:180]}\n---\n\n{body.strip()}\n"
        (folder / "SKILL.md").write_text(md, encoding="utf-8")
    st = _load_ext_state()
    st["skills"][slug] = True
    _save_json(EXT_STATE_PATH, st)
    return list_extensions()


def delete_skill(skill_id: str) -> Dict[str, Any]:
    safe = os.path.basename(skill_id)
    folder = SKILLS_DIR / safe
    if folder.exists() and folder.is_dir():
        for p in folder.rglob("*"):
            if p.is_file():
                p.unlink(missing_ok=True)
        try:
            folder.rmdir()
        except OSError:
            pass
    st = _load_ext_state()
    st["skills"].pop(safe, None)
    _save_json(EXT_STATE_PATH, st)
    return list_extensions()


def list_notes() -> List[Dict[str, Any]]:
    items = _load_json(NOTES_PATH, [])
    return items if isinstance(items, list) else []


def add_note(text: str, source: str = "manual") -> Dict[str, Any]:
    clean = re.sub(r"\s+", " ", (text or "")).strip()[:280]
    items = list_notes()
    item = {
        "id": uuid.uuid4().hex[:10],
        "text": clean,
        "done": False,
        "source": source,
        "created_at": datetime.now().isoformat(timespec="seconds"),
    }
    items.insert(0, item)
    _save_json(NOTES_PATH, items[:100])
    return item


def toggle_note(note_id: str) -> List[Dict[str, Any]]:
    items = list_notes()
    for it in items:
        if it.get("id") == note_id:
            it["done"] = not bool(it.get("done"))
    _save_json(NOTES_PATH, items)
    return items


def delete_note(note_id: str) -> List[Dict[str, Any]]:
    items = [it for it in list_notes() if it.get("id") != note_id]
    _save_json(NOTES_PATH, items)
    return items


def extract_note_command(text: str) -> Optional[str]:
    if not text:
        return None
    m = re.match(
        r"^\s*(?:lütfen\s+)?(?:not\s+al|notlara\s+ekle|yapılacak(?:lara)?\s+ekle|görev\s+ekle)\s*[:,\-–]?\s*(.+)$",
        text.strip(),
        re.I | re.S,
    )
    if not m:
        return None
    val = re.sub(r"\s+", " ", m.group(1)).strip(" .\"'")
    return val[:280] if len(val) >= 2 else None


def safe_eval_math(expr: str) -> Optional[str]:
    cleaned = (expr or "").strip().replace(",", ".").replace("×", "*").replace("÷", "/")
    if not re.match(r"^[0-9\s\+\-\*\/\(\)\.%]+$", cleaned) or not re.search(r"[\+\-\*\/]", cleaned):
        return None
    ops = {
        ast.Add: operator.add,
        ast.Sub: operator.sub,
        ast.Mult: operator.mul,
        ast.Div: operator.truediv,
        ast.Mod: operator.mod,
        ast.Pow: operator.pow,
        ast.USub: operator.neg,
        ast.UAdd: operator.pos,
    }

    def _ev(node: ast.AST) -> float:
        if isinstance(node, ast.Constant) and isinstance(node.value, (int, float)):
            return float(node.value)
        if isinstance(node, ast.BinOp) and type(node.op) in ops:
            return float(ops[type(node.op)](_ev(node.left), _ev(node.right)))
        if isinstance(node, ast.UnaryOp) and type(node.op) in ops:
            return float(ops[type(node.op)](_ev(node.operand)))
        raise ValueError("unsupported")

    try:
        tree = ast.parse(cleaned, mode="eval")
        val = _ev(tree.body)
        if abs(val - round(val)) < 1e-9:
            return str(int(round(val)))
        return f"{val:.6f}".rstrip("0").rstrip(".")
    except Exception:
        return None


def list_projects() -> List[Dict[str, Any]]:
    items = _load_json(PROJECTS_PATH, [])
    return items if isinstance(items, list) else []


def save_project(name: str, instructions: str = "", color: str = "#3b82f6", project_id: Optional[str] = None) -> Dict[str, Any]:
    items = list_projects()
    pid = project_id or f"prj_{uuid.uuid4().hex[:8]}"
    existing = next((p for p in items if p.get("id") == pid), None)
    entry = {
        "id": pid,
        "name": (name or "Yeni Proje").strip()[:60],
        "instructions": (instructions or "").strip()[:1600],
        "color": color if re.match(r"^#[0-9a-fA-F]{6}$", color or "") else "#3b82f6",
        "created_at": existing.get("created_at") if existing else datetime.now().isoformat(timespec="seconds"),
    }
    items = [p for p in items if p.get("id") != pid]
    items.insert(0, entry)
    _save_json(PROJECTS_PATH, items[:30])
    return entry


def delete_project(project_id: str) -> List[Dict[str, Any]]:
    items = [p for p in list_projects() if p.get("id") != project_id]
    _save_json(PROJECTS_PATH, items)
    return items


def build_extension_prompt_block(user_msg: str, active_skill_id: Optional[str] = None) -> str:
    ext = list_extensions()
    plugins_map = {p["id"]: p["enabled"] for p in ext["plugins"]}
    blocks: List[str] = []

    if plugins_map.get("datetime_tr", True):
        now = datetime.now()
        days_tr = ("Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar")
        blocks.append(f"Güncel Tarih/Saat (TR): {now.strftime('%d.%m.%Y %H:%M')} ({days_tr[now.weekday()]})")

    if plugins_map.get("notes_todo", True) and user_msg and re.search(r"\b(?:notlar|notlarım|yapılacak|görevler|listem)\b", user_msg, re.I):
        notes = ext.get("notes", [])
        if notes:
            n_lines = "\n".join(f"- [{'x' if n.get('done') else ' '}] {n.get('text')}" for n in notes[:15])
            blocks.append(f"[YEREL NOTLAR & YAPILACAKLAR]\n{n_lines}\n[/NOTLAR]")

    if plugins_map.get("calculator", True) and user_msg:
        calc_res = safe_eval_math(user_msg)
        if calc_res is not None:
            blocks.append(f"[HASSAS HESAPLAYICI SONUCU]: {user_msg.strip()} = {calc_res}")

    if active_skill_id:
        sk = next((s for s in ext["skills"] if s["id"] == active_skill_id and s.get("enabled", True)), None)
        if sk:
            blocks.append(f"[AKTİF BECERİ: {sk['name']}]\n{sk['body']}\n[/AKTİF BECERİ]")

    return "\n\n".join(blocks).strip()
