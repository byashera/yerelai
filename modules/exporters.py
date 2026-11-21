"""YerelAI Studio — Document Exporters (Multi-Sheet Excel, Word, PDF), Turkish TTS & Python Sandbox."""
from __future__ import annotations

import asyncio
import base64
import logging
import os
import re
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional

logger = logging.getLogger("yerelai.exporters")


def safe_export_slug(title: str, default: str = "yerelai_dosya") -> str:
    tr_map = str.maketrans("çğıöşüÇĞİÖŞÜ", "cgiosuCGIOSU")
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "_", (title or "").translate(tr_map)).strip("_")
    return slug[:42] or default


def build_xlsx_export(payload: Dict[str, Any], generated_dir: Path) -> Dict[str, Any]:
    sheets_in = payload.get("sheets")
    title = str(payload.get("title") or "YerelAI_Tablo").strip()
    if not sheets_in:
        headers = payload.get("headers") or []
        rows = payload.get("rows") or []
        if not headers and not rows:
            raise ValueError("Tablo verisi boş.")
        sheets_in = [{"name": "Veri", "headers": headers, "rows": rows}]

    import openpyxl
    from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
    from openpyxl.utils import get_column_letter

    wb = openpyxl.Workbook()
    header_fill = PatternFill(start_color="1D4ED8", end_color="1D4ED8", fill_type="solid")
    zebra_fill = PatternFill(start_color="F1F5F9", end_color="F1F5F9", fill_type="solid")
    total_fill = PatternFill(start_color="DBEAFE", end_color="DBEAFE", fill_type="solid")
    header_font = Font(name="Calibri", size=11, bold=True, color="FFFFFF")
    body_font = Font(name="Calibri", size=11, color="0F172A")
    total_font = Font(name="Calibri", size=11, bold=True, color="1E3A8A")
    thin = Side(style="thin", color="CBD5E1")
    border = Border(left=thin, right=thin, top=thin, bottom=thin)

    used_sheet_names: set = set()
    total_rows_count = 0

    def _clean_sheet_name(raw_name: str, idx_s: int) -> str:
        clean = re.sub(r"[\[\]:*?/\\]+", " ", (raw_name or f"Sayfa {idx_s}")).strip()
        clean = re.sub(r"\s+", " ", clean)[:28] or f"Sayfa {idx_s}"
        base = clean
        n = 2
        while clean.lower() in used_sheet_names:
            clean = f"{base[:24]} {n}"
            n += 1
        used_sheet_names.add(clean.lower())
        return clean

    for s_idx, sh in enumerate(sheets_in, start=1):
        headers = sh.get("headers") or []
        rows = sh.get("rows") or []
        if not headers and not rows:
            continue
        ws = wb.active if s_idx == 1 else wb.create_sheet()
        ws.title = _clean_sheet_name(str(sh.get("name") or f"Sayfa {s_idx}"), s_idx)
        total_rows_count += len(rows)

        all_rows = ([headers] if headers else []) + list(rows)
        num_col_stats: Dict[int, Dict[str, Any]] = {}

        for r_idx, row_vals in enumerate(all_rows, start=1):
            for c_idx, val in enumerate(row_vals, start=1):
                raw = str(val).strip()
                cell_val: Any = raw
                num_fmt = None
                if r_idx > 1:
                    cleaned_num = re.sub(r"[$€₺£%\s]", "", raw)
                    if re.match(r"^-?\d{1,3}(?:,\d{3})+(?:\.\d+)?$", cleaned_num):
                        cleaned_num = cleaned_num.replace(",", "")
                    if re.match(r"^-?\d+(?:[.,]\d+)?$", cleaned_num):
                        try:
                            fval = float(cleaned_num.replace(",", "."))
                            is_dec = "." in cleaned_num or "," in cleaned_num
                            cell_val = fval if is_dec else int(round(fval))
                            num_fmt = "#,##0.00" if is_dec else "#,##0"
                            st_c = num_col_stats.setdefault(c_idx, {"count": 0, "is_dec": False})
                            st_c["count"] += 1
                            if is_dec:
                                st_c["is_dec"] = True
                        except Exception:
                            cell_val = raw
                cell = ws.cell(row=r_idx, column=c_idx, value=cell_val)
                cell.border = border
                cell.alignment = Alignment(vertical="center", wrap_text=True)
                if num_fmt:
                    cell.number_format = num_fmt
                if r_idx == 1 and headers:
                    cell.fill = header_fill
                    cell.font = header_font
                else:
                    cell.font = body_font
                    if r_idx % 2 == 1:
                        cell.fill = zebra_fill

        has_existing_total = any(str(r[0]).strip().lower().startswith("toplam") for r in rows if r)
        if headers and len(rows) >= 2 and not has_existing_total and num_col_stats:
            sum_row = len(all_rows) + 1
            for c_idx in range(1, len(headers) + 1):
                col_letter = get_column_letter(c_idx)
                hdr_low = str(headers[c_idx - 1] or "").lower()
                skip_sum = any(k in hdr_low for k in ("birim", "oran", "yüzde", "fiyat", "id", "kod", "tarih", "yıl"))
                if c_idx == 1:
                    cell = ws.cell(row=sum_row, column=c_idx, value="TOPLAM")
                elif not skip_sum and num_col_stats.get(c_idx, {}).get("count", 0) >= max(2, len(rows) // 2):
                    cell = ws.cell(row=sum_row, column=c_idx, value=f"=SUM({col_letter}2:{col_letter}{sum_row - 1})")
                    cell.number_format = "#,##0.00" if num_col_stats[c_idx].get("is_dec") else "#,##0"
                else:
                    cell = ws.cell(row=sum_row, column=c_idx, value="")
                cell.fill = total_fill
                cell.font = total_font
                cell.border = border
                cell.alignment = Alignment(vertical="center")

        max_row_ws = ws.max_row
        for c_idx in range(1, max((len(r) for r in all_rows), default=1) + 1):
            col_letter = get_column_letter(c_idx)
            max_len = max((len(str(ws.cell(row=r, column=c_idx).value or "")) for r in range(1, max_row_ws + 1)), default=10)
            ws.column_dimensions[col_letter].width = min(46, max(12, max_len + 4))
        ws.freeze_panes = "A2"

    fname = f"{safe_export_slug(title, 'YerelAI_Tablo')}_{datetime.now().strftime('%H%M%S')}.xlsx"
    out_path = generated_dir / fname
    wb.save(str(out_path))
    size_kb = round(out_path.stat().st_size / 1024.0, 1)
    sheet_note = f"{len(wb.sheetnames)} sayfa · " if len(wb.sheetnames) > 1 else ""
    return {
        "ok": True,
        "kind": "xlsx",
        "filename": fname,
        "url": f"/api/generated/{fname}",
        "size_kb": size_kb,
        "meta": f"Excel Çalışma Kitabı · {sheet_note}{total_rows_count} satır · {size_kb} KB",
    }


def build_docx_export(content: str, title: str, generated_dir: Path) -> Dict[str, Any]:
    import docx

    doc = docx.Document()
    doc.add_heading(title, level=1)
    for ln in content.splitlines():
        s = ln.strip()
        if not s or s.startswith("```"):
            continue
        plain = re.sub(r"\*\*([^*]+)\*\*", r"\1", s)
        plain = re.sub(r"`([^`]+)`", r"\1", plain)
        if s.startswith("#### "):
            doc.add_heading(plain[5:], level=4)
        elif s.startswith("### "):
            doc.add_heading(plain[4:], level=3)
        elif s.startswith("## "):
            doc.add_heading(plain[3:], level=2)
        elif s.startswith("# "):
            doc.add_heading(plain[2:], level=1)
        elif re.match(r"^[-*•]\s+", s):
            doc.add_paragraph(re.sub(r"^[-*•]\s+", "", plain), style="List Bullet")
        elif re.match(r"^\d+\.\s+", s):
            doc.add_paragraph(re.sub(r"^\d+\.\s+", "", plain), style="List Number")
        else:
            doc.add_paragraph(plain)

    fname = f"{safe_export_slug(title, 'YerelAI_Rapor')}_{datetime.now().strftime('%H%M%S')}.docx"
    out_path = generated_dir / fname
    doc.save(str(out_path))
    size_kb = round(out_path.stat().st_size / 1024.0, 1)
    return {
        "ok": True,
        "kind": "docx",
        "filename": fname,
        "url": f"/api/generated/{fname}",
        "size_kb": size_kb,
        "meta": f"Word Belgesi (.docx) · {size_kb} KB",
    }


def build_pdf_export(content: str, title: str, generated_dir: Path) -> Dict[str, Any]:
    import fitz

    doc = fitz.open()
    font_candidates = [
        Path(r"C:\Windows\Fonts\segoeui.ttf"),
        Path(r"C:\Windows\Fonts\arial.ttf"),
        Path(r"C:\Windows\Fonts\calibri.ttf"),
    ]
    font_path = next((str(p) for p in font_candidates if p.exists()), None)

    plain_text = re.sub(r"```[\s\S]*?```", lambda m: m.group(0).replace("```", ""), content)
    plain_text = re.sub(r"\*\*([^*]+)\*\*", r"\1", plain_text)
    plain_text = re.sub(r"`([^`]+)`", r"\1", plain_text)
    full_body = f"{title}\n{'=' * min(48, len(title))}\n\n{plain_text}"

    lines: List[str] = []
    for raw_ln in full_body.splitlines():
        if not raw_ln:
            lines.append("")
            continue
        while len(raw_ln) > 90:
            cut = raw_ln.rfind(" ", 0, 90)
            if cut <= 20:
                cut = 90
            lines.append(raw_ln[:cut])
            raw_ln = raw_ln[cut:].lstrip()
        lines.append(raw_ln)

    per_page = 46
    for start in range(0, max(1, len(lines)), per_page):
        page = doc.new_page(width=595, height=842)
        if font_path:
            page.insert_font(fontname="trfont", fontfile=font_path)
            fname_key = "trfont"
        else:
            fname_key = "helv"
        chunk_txt = "\n".join(lines[start : start + per_page])
        rect = fitz.Rect(46, 48, 549, 796)
        page.insert_textbox(rect, chunk_txt, fontsize=10.5, fontname=fname_key, color=(0.08, 0.11, 0.18), lineheight=1.45)

    fname = f"{safe_export_slug(title, 'YerelAI_Rapor')}_{datetime.now().strftime('%H%M%S')}.pdf"
    out_path = generated_dir / fname
    doc.save(str(out_path))
    doc.close()
    size_kb = round(out_path.stat().st_size / 1024.0, 1)
    return {
        "ok": True,
        "kind": "pdf",
        "filename": fname,
        "url": f"/api/generated/{fname}",
        "size_kb": size_kb,
        "meta": f"PDF Belgesi · {size_kb} KB",
    }


def build_zip_export(payload: Dict[str, Any], generated_dir: Path) -> Dict[str, Any]:
    import zipfile

    title = str(payload.get("title") or "YerelAI_Proje").strip()
    raw_files = payload.get("files") or []
    if not isinstance(raw_files, list) or not raw_files:
        raise ValueError("ZIP paketi için en az bir dosya gereklidir.")

    safe_title = re.sub(r"[^a-zA-Z0-9_\-ğüşıöçĞÜŞİÖÇ]", "_", title)[:44] or "YerelAI_Proje"
    fname = f"{safe_title}_{datetime.now().strftime('%H%M%S')}.zip"
    out_path = generated_dir / fname

    used_names: Dict[str, int] = {}
    written = 0
    with zipfile.ZipFile(out_path, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        for idx, item in enumerate(raw_files[:40]):
            if not isinstance(item, dict):
                continue
            raw_name = str(item.get("filename") or f"dosya_{idx + 1}.txt").strip()
            # Prevent path traversal and invalid Windows chars
            parts = [p for p in re.split(r"[\\/]+", raw_name) if p and p not in (".", "..")]
            clean_parts = [re.sub(r'[:*?"<>|]', "_", p)[:60] for p in parts]
            arcname = "/".join(clean_parts) if clean_parts else f"dosya_{idx + 1}.txt"
            if arcname.lower() in used_names:
                used_names[arcname.lower()] += 1
                stem, dot, ext = arcname.rpartition(".")
                if dot:
                    arcname = f"{stem}_{used_names[arcname.lower()]}.{ext}"
                else:
                    arcname = f"{arcname}_{used_names[arcname.lower()]}"
            else:
                used_names[arcname.lower()] = 1
            content = str(item.get("content") or "")
            zf.writestr(arcname, content.encode("utf-8"))
            written += 1

    if written == 0:
        out_path.unlink(missing_ok=True)
        raise ValueError("ZIP paketine eklenecek geçerli dosya bulunamadı.")

    size_kb = max(1, round(out_path.stat().st_size / 1024))
    return {
        "ok": True,
        "filename": fname,
        "url": f"/api/generated/{fname}",
        "file_count": written,
        "size_kb": size_kb,
        "meta": f"{written} Dosya · {size_kb} KB",
    }


def run_python_sandbox_sync(code: str) -> Dict[str, Any]:
    t0 = time.perf_counter()
    with tempfile.TemporaryDirectory(prefix="yerelai_py_") as tmpdir:
        tmp_p = Path(tmpdir)
        runner_code = (
            "import os, sys\n"
            "os.environ['MPLBACKEND'] = 'Agg'\n"
            "try:\n"
            "    import matplotlib.pyplot as _plt\n"
            "    _plot_i = [0]\n"
            "    def _auto_show(*a, **kw):\n"
            "        _plot_i[0] += 1\n"
            "        _plt.savefig(f'_plot_{_plot_i[0]}.png', dpi=130, bbox_inches='tight')\n"
            "        _plt.close('all')\n"
            "    _plt.show = _auto_show\n"
            "except Exception:\n"
            "    pass\n"
            + code
        )
        script_path = tmp_p / "main.py"
        script_path.write_text(runner_code, encoding="utf-8")
        try:
            proc = subprocess.run(
                [sys.executable, "-I", str(script_path)],
                cwd=str(tmp_p),
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=12,
            )
            elapsed = round(time.perf_counter() - t0, 2)
            images: List[str] = []
            for png in sorted(tmp_p.glob("*.png"))[:4]:
                b64 = base64.b64encode(png.read_bytes()).decode("ascii")
                images.append(f"data:image/png;base64,{b64}")
            return {
                "ok": proc.returncode == 0,
                "returncode": proc.returncode,
                "stdout": (proc.stdout or "")[:12000],
                "stderr": (proc.stderr or "")[:6000],
                "images": images,
                "elapsed_sec": elapsed,
            }
        except subprocess.TimeoutExpired:
            return {
                "ok": False,
                "returncode": -1,
                "stdout": "",
                "stderr": "Zaman aşımı (12 sn): Sonsuz döngü veya uzun işlem durduruldu.",
                "images": [],
                "elapsed_sec": 12.0,
            }


async def synthesize_turkish_tts(text: str, voice_pref: str = "tr-TR-AhmetNeural") -> tuple[bytes, str, str]:
    # Strip fenced code blocks (including yerel_card/mermaid/code), inline code, mcp_call, URLs & emojis silently
    clean_text = re.sub(r"```[\s\S]*?```", " ", text)
    clean_text = re.sub(r"<mcp_call>[\s\S]*?</mcp_call>", " ", clean_text)
    clean_text = re.sub(r"`[^`\n]+`", " ", clean_text)
    clean_text = re.sub(r"\[([^\]]+)\]\(https?://[^)]+\)", r"\1", clean_text)
    clean_text = re.sub(r"https?://\S+", " ", clean_text)
    clean_text = re.sub(r"^\s*\|?[\s:-]+\|[\s|:-]*$", " ", clean_text, flags=re.M)
    clean_text = re.sub(r"\$([^$]+)\$", r"\1", clean_text)
    clean_text = clean_text.replace("\\circ", " derece ").replace("\\text{", " ").replace("}", " ")
    # Remove all Unicode emojis, pictographs, dingbats, variation selectors & ZWJ
    clean_text = re.sub(
        r"[\U0001F000-\U0001FAFF\U00002600-\U000027BF\U00002300-\U000023FF\U00002B00-\U00002BFF\uFE0F\u200D\u20E3]+",
        " ",
        clean_text,
    )
    clean_text = re.sub(r"[`*_#>\[\]()|~]", " ", clean_text)
    clean_text = re.sub(r"\s+", " ", clean_text).strip()[:1800]
    if not clean_text:
        raise ValueError("Okunabilir metin bulunamadı.")

    if voice_pref != "offline-tolga":
        try:
            import edge_tts

            voice_name = voice_pref if voice_pref.startswith("tr-TR-") else "tr-TR-AhmetNeural"
            comm = edge_tts.Communicate(clean_text, voice=voice_name, rate="+20%")
            chunks: List[bytes] = []

            async def _collect_edge():
                async for ch in comm.stream():
                    if ch["type"] == "audio":
                        chunks.append(ch["data"])

            await asyncio.wait_for(_collect_edge(), timeout=15.0)
            audio_bytes = b"".join(chunks)
            if len(audio_bytes) > 200:
                return audio_bytes, "audio/mpeg", f"edge-neural:{voice_name}"
        except Exception as exc:
            logger.info("Edge Neural TTS skipped/offline (%s); falling back to WinRT Tolga.", exc)

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        wav_path = tf.name
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", encoding="utf-8", delete=False) as txt_f:
        txt_path = txt_f.name
        txt_f.write(clean_text)

    try:
        ps_script = (
            "Add-Type -AssemblyName System.Runtime.WindowsRuntime; "
            "$asTaskGeneric = ([System.WindowsRuntimeSystemExtensions].GetMethods() | "
            "Where-Object { $_.Name -eq 'AsTask' -and $_.GetParameters().Count -eq 1 -and "
            "$_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' })[0]; "
            "function Await($WinRtTask, $ResultType) { "
            "  $asTask = $asTaskGeneric.MakeGenericMethod($ResultType); "
            "  $netTask = $asTask.Invoke($null, @($WinRtTask)); "
            "  $netTask.Wait(-1) | Out-Null; return $netTask.Result "
            "}; "
            "$null = [Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media.SpeechSynthesis, ContentType = WindowsRuntime]; "
            "$synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer; "
            "$tr = [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices | Where-Object { $_.Language -like 'tr*' } | Select-Object -First 1; "
            "if ($tr) { $synth.Voice = $tr }; "
            f"$txt = [System.IO.File]::ReadAllText('{txt_path}', [System.Text.Encoding]::UTF8); "
            "$stream = Await ($synth.SynthesizeTextToStreamAsync($txt)) ([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]); "
            "$inStream = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($stream); "
            f"$fs = [System.IO.File]::Create('{wav_path}'); "
            "$inStream.CopyTo($fs); $fs.Close(); $inStream.Close(); $synth.Dispose();"
        )
        proc = await asyncio.to_thread(
            subprocess.run,
            ["powershell", "-NoProfile", "-Command", ps_script],
            capture_output=True,
            timeout=25,
        )
        if proc.returncode != 0 or not os.path.exists(wav_path) or os.path.getsize(wav_path) < 100:
            err_msg = proc.stderr.decode("utf-8", errors="ignore")[:200]
            raise RuntimeError(f"WinRT Türkçe ses üretimi başarısız: {err_msg}")
        return Path(wav_path).read_bytes(), "audio/wav", "winrt-tolga-tr-offline"
    finally:
        for p in (wav_path, txt_path):
            try:
                os.unlink(p)
            except OSError:
                pass
