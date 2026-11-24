/* =========================================================
   YerelAI Studio · Aether Prism Frontend Controller
   GGUF Turbo Streaming · Live Weather & Data Tables
   Authentic Turkish TTS · Zero Native <select>
   ========================================================= */
(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const EFFORT_META = {
    off: { label: "Kapalı", budget: "0 tok", tone: "off", desc: "Doğrudan hızlı yanıt (düşünme adımı kapalı)." },
    low: { label: "Düşük", budget: "256 tok", tone: "low", desc: "Kısa akıl yürütme (256 token bütçesi)." },
    medium: { label: "Orta", budget: "768 tok", tone: "medium", desc: "Dengeli akıl yürütme (768 token bütçesi)." },
    high: { label: "Yüksek", budget: "2048 tok", tone: "high", desc: "Derin analiz ve hata ayıklama (2048 token bütçesi)." },
  };

  const PROFILE_LABELS = {
    auto: "Otomatik Algıla (4GB / 8GB+)",
    low_vram: "Low-VRAM (4GB Laptop Uyumlu)",
    turbo: "Turbo GPU (8GB+ Tam GPU)",
  };

  const TTS_LABELS = {
    "tr-TR-AhmetNeural": "Ahmet (Neural TR · Erkek)",
    "tr-TR-EmelNeural": "Emel (Neural TR · Kadın)",
    "offline-tolga": "Tolga (Yalnızca Çevrimdışı TR)",
  };

  const CTX_LABELS = {
    "8192": "8K Token (Hafif · En Az VRAM)",
    "16384": "16K Token (Dengeli · Oyunla Uyumlu)",
    "32768": "32K Token (Uzun Sohbet · 8GB VRAM)",
  };

  const SLASH_COMMANDS = [
    { cmd: "/web", desc: "Canlı web araştırmasını aç ve sor", tag: "Araştır", tone: "", icon: "globe", run: () => { syncWebSearchUI(true); return ""; } },
    { cmd: "/kod", desc: "Kıdemli yazılımcı + yüksek akıl yürütme", tag: "Mod", tone: "", icon: "code", run: () => { setTemporaryMode("Kıdemli Yazılımcı", PERSONAS.find((p) => p.id === "coder")?.prompt || ""); updateEffortPill("high", true); return ""; } },
    { cmd: "/tasarım", desc: "Apple / Linear / Bento Grid HTML & UI tasarımı", tag: "Mod", tone: "skill", icon: "code", run: () => { setTemporaryMode("Web & UI Tasarımcısı", PERSONAS.find((p) => p.id === "designer")?.prompt || ""); return "Modern Bento Grid ve etkileşimli HTML tasarım yap: "; } },
    { cmd: "/özet", desc: "Metni veya dosyayı maddeler halinde özetle", tag: "Mod", tone: "ok", icon: "file", run: () => { setTemporaryMode("Özet & Editör", PERSONAS.find((p) => p.id === "editor")?.prompt || ""); return "Şunu en kritik maddeler halinde özetle:\n"; } },
    { cmd: "/çevir", desc: "Profesyonel Türkçe ↔ İngilizce çeviri", tag: "Mod", tone: "ok", icon: "globe", run: () => { setTemporaryMode("Çevirmen (TR ↔ EN)", PERSONAS.find((p) => p.id === "translator")?.prompt || ""); return "Şunu doğal ve akıcı şekilde çevir:\n"; } },
    { cmd: "/tablo", desc: "Excel (.xlsx) & Markdown tablosu hazırla", tag: "Excel", tone: "ok", icon: "table", run: () => { setTemporaryMode("Veri & Excel Analisti", PERSONAS.find((p) => p.id === "analyst")?.prompt || ""); return "Düzenli Markdown tablosu ve Excel çıktısı olarak hazırla: "; } },
    { cmd: "/hatırla", desc: "Sohbetler arası kalıcı hafızaya kaydet", tag: "Memory", tone: "warn", icon: "star", run: () => "Bunu hatırla: " },
    { cmd: "/not", desc: "Yerel Notlar & Yapılacaklar listesine ekle", tag: "Eklenti", tone: "warn", icon: "file", run: () => "Not al: " },
    { cmd: "/compact", desc: "Uzun sohbet bağlamını akıllıca sıkıştır ve rahatlat", tag: "Bağlam", tone: "ok", icon: "spark", run: () => { runManualCompact(); return null; } },
    { cmd: "/temiz", desc: "Yeni temiz sohbet başlat", tag: "Sohbet", tone: "", icon: "plus", run: () => { startNewChat(); return null; } },
  ];

  const CODE_LANG_META = {
    html: { ext: "html", cls: "lang-html", label: "HTML Sayfası", fallback: "index.html", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>` },
    htm: { ext: "html", cls: "lang-html", label: "HTML Sayfası", fallback: "index.html", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>` },
    python: { ext: "py", cls: "lang-py", label: "Python Betiği", fallback: "script.py", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2c-3 0-4 1.5-4 3.5V8h8v1H6.5C4.5 9 3 10.5 3 13s1.5 4 3.5 4H8v-2.5C8 12.5 9.5 11 11.5 11h5c1.4 0 2.5-1.1 2.5-2.5V5.5C19 3.5 17 2 12 2z"/><path d="M12 22c3 0 4-1.5 4-3.5V16H8v-1h9.5c2 0 3.5-1.5 3.5-4s-1.5-4-3.5-4H16v2.5c0 2-1.5 3.5-3.5 3.5h-5C6.1 13 5 14.1 5 15.5v3C5 20.5 7 22 12 22z"/></svg>` },
    py: { ext: "py", cls: "lang-py", label: "Python Betiği", fallback: "script.py", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2c-3 0-4 1.5-4 3.5V8h8v1H6.5C4.5 9 3 10.5 3 13s1.5 4 3.5 4H8v-2.5C8 12.5 9.5 11 11.5 11h5c1.4 0 2.5-1.1 2.5-2.5V5.5C19 3.5 17 2 12 2z"/><path d="M12 22c3 0 4-1.5 4-3.5V16H8v-1h9.5c2 0 3.5-1.5 3.5-4s-1.5-4-3.5-4H16v2.5c0 2-1.5 3.5-3.5 3.5h-5C6.1 13 5 14.1 5 15.5v3C5 20.5 7 22 12 22z"/></svg>` },
    javascript: { ext: "js", cls: "lang-js", label: "JavaScript Modülü", fallback: "app.js", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M10 10v5a2 2 0 0 1-2 2H7"/><path d="M14 15.5c.5.7 1.2 1 2 1 1.1 0 1.8-.6 1.8-1.4 0-.8-.5-1.2-1.6-1.6l-.6-.2c-1-.4-1.5-.9-1.5-1.7 0-1 .8-1.6 1.9-1.6.8 0 1.4.3 1.8.8"/></svg>` },
    js: { ext: "js", cls: "lang-js", label: "JavaScript Modülü", fallback: "app.js", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M10 10v5a2 2 0 0 1-2 2H7"/><path d="M14 15.5c.5.7 1.2 1 2 1 1.1 0 1.8-.6 1.8-1.4 0-.8-.5-1.2-1.6-1.6l-.6-.2c-1-.4-1.5-.9-1.5-1.7 0-1 .8-1.6 1.9-1.6.8 0 1.4.3 1.8.8"/></svg>` },
    typescript: { ext: "ts", cls: "lang-ts", label: "TypeScript Modülü", fallback: "app.ts", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 10h5M9.5 10v7"/><path d="M14 15.5c.5.7 1.2 1 2 1 1.1 0 1.8-.6 1.8-1.4 0-.8-.5-1.2-1.6-1.6l-.6-.2c-1-.4-1.5-.9-1.5-1.7 0-1 .8-1.6 1.9-1.6.8 0 1.4.3 1.8.8"/></svg>` },
    ts: { ext: "ts", cls: "lang-ts", label: "TypeScript Modülü", fallback: "app.ts", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="3"/><path d="M7 10h5M9.5 10v7"/><path d="M14 15.5c.5.7 1.2 1 2 1 1.1 0 1.8-.6 1.8-1.4 0-.8-.5-1.2-1.6-1.6l-.6-.2c-1-.4-1.5-.9-1.5-1.7 0-1 .8-1.6 1.9-1.6.8 0 1.4.3 1.8.8"/></svg>` },
    css: { ext: "css", cls: "lang-css", label: "CSS Stil Dosyası", fallback: "styles.css", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 2L2 7l10 5 10-5-10-5z"/><path d="M2 17l10 5 10-5"/><path d="M2 12l10 5 10-5"/></svg>` },
    sql: { ext: "sql", cls: "lang-sql", label: "SQL Sorgusu", fallback: "query.sql", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><ellipse cx="12" cy="5" rx="9" ry="3"/><path d="M21 12c0 1.66-4 3-9 3s-9-1.34-9-3"/><path d="M3 5v14c0 1.66 4 3 9 3s9-1.34 9-3V5"/></svg>` },
    json: { ext: "json", cls: "lang-json", label: "JSON Veri Dosyası", fallback: "data.json", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 3H7a2 2 0 0 0-2 2v5a2 2 0 0 1-2 2 2 2 0 0 1 2 2v5c0 1.1.9 2 2 2h1"/><path d="M16 21h1a2 2 0 0 0 2-2v-5c0-1.1.9-2 2-2a2 2 0 0 1-2-2V5a2 2 0 0 0-2-2h-1"/></svg>` },
    svg: { ext: "svg", cls: "lang-svg", label: "SVG Vektör Grafiği", fallback: "graphic.svg", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 22 8.5 22 15.5 12 22 2 15.5 2 8.5 12 2"/><line x1="12" y1="22" x2="12" y2="15.5"/><polyline points="22 8.5 12 15.5 2 8.5"/></svg>` },
    powershell: { ext: "ps1", cls: "lang-code", label: "PowerShell Betiği", fallback: "script.ps1", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>` },
    ps1: { ext: "ps1", cls: "lang-code", label: "PowerShell Betiği", fallback: "script.ps1", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>` },
    bash: { ext: "sh", cls: "lang-code", label: "Kabuk Betiği", fallback: "script.sh", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>` },
    sh: { ext: "sh", cls: "lang-code", label: "Kabuk Betiği", fallback: "script.sh", svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/></svg>` },
  };

  const GENERAL_DEFAULT_PROMPT =
    "Sen YerelAI Studio üzerinde çalışan sıcakkanlı, doğal, zeki ve samimi bir yapay zekâ asistanısın. Varsayılan olarak akıcı Türkçe konuş. Gündelik sohbetlerde doğal bir insan gibi sıcak ve kısa yanıt ver; 'Ben bir yapay zekâ modeliyim, duygularım yok' gibi robotik kalıpları ASLA kullanma. Doğrudan konuya gir; 'Sağladığınız verilere göre' gibi gereksiz giriş cümleleri kurma. Sayılar ve birimler için asla LaTeX ($...$) kullanma.";

  const PERSONAS = [
    {
      id: "auto",
      name: "✨ Otomatik (Akıllı Seçim)",
      prompt: GENERAL_DEFAULT_PROMPT,
    },
    {
      id: "general",
      name: "Genel Asistan",
      prompt: GENERAL_DEFAULT_PROMPT,
    },
    {
      id: "coder",
      name: "Kıdemli Yazılımcı",
      prompt:
        "Sen kıdemli bir yazılım mimarı ve geliştiricisin. Temiz, güvenli, modern ve doğrudan çalıştırılabilir kod yaz. Kod bloğundan sonra 2-4 maddelik kısa Türkçe özet yaz; kullanıcı yalnızca fikir/öneri soruyorsa kod yazmadan önce önerilerini sunup onay iste.",
    },
    {
      id: "analyst",
      name: "Veri & Excel Analisti",
      prompt:
        "Sen uzman bir veri ve iş analistisin. Excel/CSV tablolarını, sayısal eğilimleri, toplamları ve anomalileri keskin bir şekilde analiz et. Bulgularını düzenli Markdown tabloları, yüzdeler ve net aksiyon önerileriyle sun; LaTeX kullanma.",
    },
    {
      id: "translator",
      name: "Çevirmen (TR ↔ EN)",
      prompt:
        "Sen profesyonel bir Türkçe ↔ İngilizce çevirmensin. Verilen metni doğal, akıcı ve bağlama sadık şekilde diğer dile çevir. Ekstra açıklama istenmedikçe doğrudan çeviriyi sun.",
    },
    {
      id: "editor",
      name: "Özet & Editör",
      prompt:
        "Sen deneyimli bir editörsün. Uzun metinleri, PDF veya raporları en kritik maddeler halinde özetle; dil ve üslup düzeltmelerini akıcı, profesyonel Türkçe ile yap.",
    },
    {
      id: "designer",
      name: "Web & UI Tasarımcısı",
      prompt:
        "Sen ödüllü bir modern web ve UI/UX mühendisisin. Kullanıcı yalnızca 'neler ekleyebilirsin?' diye fikir soruyorsa kod yazma, önce 3-5 maddelik öneri sun. Kod istendiğinde 12 sütunlu asimetrik Bento Grid, çalışan Koyu/Açık Tema butonu, Kategori Filtresi, Detay Modalı ve her karta özel farklı inline SVG ikon içeren Apple/Linear/Vercel kalitesinde tek dosya HTML/CSS/JS üret; asla alert() kullanma ve koddan sonra 3-4 maddelik Türkçe özet yaz.",
    },
  ];

  const PRISM_E2B_SVG = `<svg viewBox="0 0 24 24" fill="none"><polygon points="12,2.5 21,9 17.5,20.5 6.5,20.5 3,9" stroke="currentColor" stroke-width="1.9" fill="currentColor" fill-opacity="0.18"/><polygon points="13,6 8.5,13 12,13 11,18 15.5,11 12,11" fill="#ffffff" opacity="0.92"/></svg>`;
  const PRISM_E4B_SVG = `<svg viewBox="0 0 24 24" fill="none"><polygon points="12,2 20.5,7 20.5,17 12,22 3.5,17 3.5,7" stroke="currentColor" stroke-width="1.8" fill="currentColor" fill-opacity="0.18"/><polygon points="12,5.5 17.5,12 12,18.5 6.5,12" stroke="#ffffff" stroke-width="1.4" fill="currentColor" fill-opacity="0.32"/><circle cx="12" cy="12" r="2.1" fill="#ffffff"/></svg>`;
  const PRISM_SVG = PRISM_E2B_SVG;

  const CMD_ICONS = {
    plus: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>`,
    theme: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2"/></svg>`,
    sliders: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="4" y1="21" x2="4" y2="14"/><line x1="4" y1="10" x2="4" y2="3"/><line x1="12" y1="21" x2="12" y2="12"/><line x1="12" y1="8" x2="12" y2="3"/><line x1="20" y1="21" x2="20" y2="16"/><line x1="20" y1="12" x2="20" y2="3"/></svg>`,
    globe: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
    sidebar: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><rect x="3" y="3" width="18" height="18" rx="3"/><line x1="9" y1="3" x2="9" y2="21"/></svg>`,
    bolt: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>`,
    power: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M18.36 6.64a9 9 0 1 1-12.73 0"/><line x1="12" y1="2" x2="12" y2="12"/></svg>`,
    cube: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><polygon points="12 2 21 7 21 17 12 22 3 17 3 7"/></svg>`,
    chat: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>`,
  };

  const WEATHER_SVGS = {
    sun: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"/></svg>`,
    partly_cloudy: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M12 2v2M4.93 4.93l1.41 1.41M2 12h2M17.5 19H9a5 5 0 0 1-.5-9.98A4 4 0 0 1 16 11a3.5 3.5 0 0 1 1.5 8z"/></svg>`,
    cloud: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M17.5 19H9a5 5 0 0 1-.4-9.98 6 6 0 0 1 11.4 1.48A4 4 0 0 1 17.5 19z"/></svg>`,
    fog: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M4 14h16M6 18h12M17.5 10H9a4 4 0 0 1 0-8 5 5 0 0 1 9.5 2A3.5 3.5 0 0 1 17.5 10z"/></svg>`,
    drizzle: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M17.5 15H9a4 4 0 0 1-.4-7.98A5.5 5.5 0 0 1 19 8.5 3.5 3.5 0 0 1 17.5 15zM9 19v1M13 19v1M17 19v1"/></svg>`,
    rain: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M17.5 14H9a4 4 0 0 1-.4-7.98A5.5 5.5 0 0 1 19 7.5 3.5 3.5 0 0 1 17.5 14zM8 18l-1 3M12 18l-1 3M16 18l-1 3"/></svg>`,
    snow: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M17.5 14H9a4 4 0 0 1-.4-7.98A5.5 5.5 0 0 1 19 7.5 3.5 3.5 0 0 1 17.5 14z"/><circle cx="9" cy="19" r="1"/><circle cx="13" cy="20" r="1"/><circle cx="16.5" cy="18.5" r="1"/></svg>`,
    storm: `<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M17.5 14H9a4 4 0 0 1-.4-7.98A5.5 5.5 0 0 1 19 7.5 3.5 3.5 0 0 1 17.5 14z"/><polyline points="13 14 10 19 14 19 11 23"/></svg>`,
  };

  const SVG_ICONS = {
    speak: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/></svg>`,
    copy: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>`,
    thumbUp: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M14 9V5a3 3 0 0 0-3-3l-4 9v11h11.28a2 2 0 0 0 2-1.7l1.38-9a2 2 0 0 0-2-2.3zM7 22H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2h3"/></svg>`,
    thumbDown: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M10 15v4a3 3 0 0 0 3 3l4-9V2H5.72a2 2 0 0 0-2 1.7l-1.38 9a2 2 0 0 0 2 2.3zm7-13h2.67A2.31 2.31 0 0 1 22 4v7a2.31 2.31 0 0 1-2.33 2H17"/></svg>`,
    share: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>`,
    star: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/></svg>`,
    trash: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6"/><path d="M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>`,
    file: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/></svg>`,
    globe: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/></svg>`,
    warn: `<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M10.29 3.86L1.82 18a2 2 0 0 0 1.71 3h16.94a2 2 0 0 0 1.71-3L13.71 3.86a2 2 0 0 0-3.42 0z"/><line x1="12" y1="9" x2="12" y2="13"/><line x1="12" y1="17" x2="12.01" y2="17"/></svg>`,
    check: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`,
    okCircle: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="20 6 9 17 4 12"/></svg>`,
    edit: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>`,
    refresh: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="23 4 23 10 17 10"/><path d="M20.49 15a9 9 0 1 1-2.12-9.36L23 10"/></svg>`,
    pin: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 17v5"/><path d="M9 10.76a2 2 0 0 1-1.11 1.79l-1.78.9A2 2 0 0 0 5 15.24V16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-.76a2 2 0 0 0-1.11-1.79l-1.78-.9A2 2 0 0 1 15 10.76V7a1 1 0 0 1 1-1 2 2 0 0 0 0-4H8a2 2 0 0 0 0 4 1 1 0 0 1 1 1z"/></svg>`,
    table: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M3 9h18M3 15h18M9 3v18"/></svg>`,
    download: `<svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>`,
    xClose: `<svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>`,
    dots: `<svg width="14" height="14" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.9"/><circle cx="12" cy="12" r="1.9"/><circle cx="19" cy="12" r="1.9"/></svg>`,
    docExport: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z"/><polyline points="14 2 14 8 20 8"/><line x1="12" y1="18" x2="12" y2="12"/><polyline points="9 15 12 18 15 15"/></svg>`,
    chevLeft: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><polyline points="15 18 9 12 15 6"/></svg>`,
    chevRight: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>`,
    eye: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>`,
    code: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>`,
    play: `<svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="6 4 20 12 6 20 6 4"/></svg>`,
    spark: `<svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9L12 3z"/></svg>`,
    fork: `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="18" r="3"/><circle cx="6" cy="6" r="3"/><circle cx="18" cy="6" r="3"/><path d="M18 9v1a2 2 0 0 1-2 2H8a2 2 0 0 1-2-2V9"/><path d="M12 12v3"/></svg>`,
  };

  const state = {
    config: {},
    models: [],
    loras: [],
    sessions: [],
    dataset: [],
    notifications: [],
    unreadNotifs: 0,
    activeSessionId: null,
    messages: [],
    pendingAttachments: [],
    selectedModelId: "gemma-4-e2b-qat-mtp",
    selectedLoraId: "",
    gpuProfile: "auto",
    contextLength: 32768,
    memories: [],
    plugins: [],
    skills: [],
    notes: [],
    projects: [],
    activeProjectId: null,
    activeSkillId: null,
    tempPersonaPrompt: "",
    tempModeLabel: "",
    ttsSpeed: Number(localStorage.getItem("yerelai_tts_speed") || "1") || 1,
    slashActiveIdx: 0,
    slashItems: [],
    artTab: "preview",
    artViewport: "desktop",
    thinkingEffort: "medium",
    webSearch: false,
    useLibrary: false,
    libraryDocs: [],
    handsFree: false,
    activePersonaId: localStorage.getItem("yerelai_persona_mode") || "auto",
    pendingDeleteSid: null,
    pendingDeleteRow: null,
    ctxMenuSid: null,
    ctxMenuRow: null,
    vadSpeechSeen: false,
    vadLastSoundTs: 0,
    ttsVoice: "tr-TR-AhmetNeural",
    autoTts: false,
    isGenerating: false,
    abortController: null,
    statusTimer: null,
    download: { active: false, status: "idle", model_id: null, percent: 0, downloaded_bytes: 0, total_bytes: 0, speed_mbps: 0, eta_seconds: 0 },
    lastDownloadStatus: "idle",
    activeTtsUrl: null,
    activeSpeakBtn: null,
    activeArtifact: null,
    cmdActiveIdx: 0,
    cmdItems: [],
    isRecording: false,
    recAudioCtx: null,
    recStream: null,
    recProcessor: null,
    recAnalyser: null,
    recChunks: [],
    recStartTime: 0,
    recTimerId: null,
    recRafId: null,
    isTemporaryChat: false,
    temporaryPersonalized: false,
    actor: { actor_id: "owner", role: "admin", display_name: "Admin", is_admin: true, is_local: true },
    cachedGeoLocation: null,
    activeMoreMenuMsgIdx: null,
  };

  const dom = {
    html: document.documentElement,
    studioShell: $(".studio-shell"),
    sidebar: $("#sidebar"),
    mainArea: $("#main-area"),
    inspector: $("#inspector"),
    drawerBackdrop: $("#drawer-backdrop"),
    btnCloseInspector: $("#btn-close-inspector"),
    btnCollapseSidebar: $("#btn-collapse-sidebar"),
    btnOpenCmd: $("#btn-open-cmd"),
    heroGreetingLead: $("#hero-greeting-lead"),
    heroHwText: $("#hero-hw-text"),
    btnScrollBottom: $("#btn-scroll-bottom"),
    cmdPaletteModal: $("#cmd-palette-modal"),
    cmdInput: $("#cmd-input"),
    cmdResults: $("#cmd-results"),
    artifactDrawer: $("#artifact-drawer"),
    workspaceBody: $(".workspace-body"),
    artifactResizer: $("#artifact-resizer"),
    artifactStage: $("#artifact-stage"),
    artifactVersionBar: $("#artifact-version-bar"),
    artifactVerPills: $("#artifact-ver-pills"),
    artifactEditStatus: $("#artifact-edit-status"),
    artifactEditorWrap: $("#artifact-editor-wrap"),
    artifactLineNums: $("#artifact-line-nums"),
    artifactCodeEditor: $("#artifact-code-editor"),
    artifactCodeView: $("#artifact-code-view"),
    artifactDiffView: $("#artifact-diff-view"),
    artTabPreview: $("#art-tab-preview"),
    artTabCode: $("#art-tab-code"),
    artTabDiff: $("#art-tab-diff"),
    artTabs: $("#art-tabs"),
    artVpBar: $("#art-vp-bar"),
    btnArtifactRun: $("#btn-artifact-run"),
    btnArtifactCopy: $("#btn-artifact-copy"),
    btnArtifactSaveDisk: $("#btn-artifact-save-disk"),
    btnArtifactZip: $("#btn-artifact-zip"),
    btnWsOpen: $("#btn-ws-open"),
    wsActiveBar: $("#ws-active-bar"),
    wsName: $("#ws-name"),
    btnWsGit: $("#btn-ws-git"),
    btnWsClose: $("#btn-ws-close"),
    wsFilesList: $("#ws-files-list"),
    windowPickerModal: $("#window-picker-modal"),
    windowPickerGrid: $("#window-picker-grid"),
    btnWinPickerClose: $("#btn-win-picker-close"),
    btnWinPickerClip: $("#btn-win-picker-clip"),
    gitStatusModal: $("#git-status-modal"),
    gitBranchChip: $("#git-branch-chip"),
    gitStatusPre: $("#git-status-pre"),
    btnGitClose: $("#btn-git-close"),
    mcpServersCount: $("#mcp-servers-count"),
    mcpPresetsRow: $("#mcp-presets-row"),
    mcpServersList: $("#mcp-servers-list"),
    mcpNameInp: $("#mcp-name-inp"),
    mcpTransportSel: $("#mcp-transport-sel"),
    mcpCmdInp: $("#mcp-cmd-inp"),
    mcpArgsInp: $("#mcp-args-inp"),
    btnMcpAdd: $("#btn-mcp-add"),
    artifactPyOutput: $("#artifact-py-output"),
    pyOutStatus: $("#py-out-status"),
    pyOutText: $("#py-out-text"),
    pyOutImages: $("#py-out-images"),
    btnPyOutClose: $("#btn-py-out-close"),
    slashMenu: $("#slash-menu"),
    activeModeStrip: $("#active-mode-strip"),
    activeModeLabel: $("#active-mode-label"),
    btnClearMode: $("#btn-clear-mode"),
    projectsList: $("#projects-list"),
    btnNewProject: $("#btn-new-project"),
    projectModal: $("#project-modal"),
    btnProjectClose: $("#btn-project-close"),
    btnPrjCancel: $("#btn-prj-cancel"),
    btnPrjSave: $("#btn-prj-save"),
    prjNameInput: $("#prj-name-input"),
    prjInstInput: $("#prj-inst-input"),
    ttsSpeedSeg: $("#tts-speed-seg"),
    lblTtsSpeed: $("#lbl-tts-speed"),
    extPluginsCount: $("#ext-plugins-count"),
    extPluginsList: $("#ext-plugins-list"),
    extWebhookRow: $("#ext-webhook-row"),
    inpWebhookUrl: $("#inp-webhook-url"),
    btnWebhookTest: $("#btn-webhook-test"),
    skillFileInput: $("#skill-file-input"),
    btnImportSkill: $("#btn-import-skill"),
    extSkillsList: $("#ext-skills-list"),
    extNotesCount: $("#ext-notes-count"),
    inpNoteAdd: $("#inp-note-add"),
    btnNoteAdd: $("#btn-note-add"),
    extNotesList: $("#ext-notes-list"),
    artifactLangTag: $("#artifact-lang-tag"),
    artifactTitle: $("#artifact-title"),
    artifactIframe: $("#artifact-iframe"),
    btnArtifactDownload: $("#btn-artifact-download"),
    btnArtifactNewtab: $("#btn-artifact-newtab"),
    btnArtifactClose: $("#btn-artifact-close"),
    btnThemeToggle: $("#btn-theme-toggle"),
    iconSun: $("#icon-sun"),
    iconMoon: $("#icon-moon"),
    btnMobileSidebar: $("#btn-mobile-sidebar"),
    btnMobileSidebarClose: $("#btn-mobile-sidebar-close"),
    btnComposerTools: $("#btn-composer-tools"),
    composerToolsMenu: $("#composer-tools-menu"),
    ctmWebState: $("#ctm-web-state"),
    ctmRagState: $("#ctm-rag-state"),
    chipWebActive: $("#chip-web-active"),
    chipRagActive: $("#chip-rag-active"),
    dsSftCount: $("#ds-sft-count"),
    dsDislikeCount: $("#ds-dislike-count"),
    dsDpoCount: $("#ds-dpo-count"),
    btnInspExportDpo: $("#btn-insp-export-dpo"),
    dislikeModal: $("#dislike-feedback-modal"),
    dislikeReasons: $("#dislike-reasons"),
    inpDislikeCorrection: $("#inp-dislike-correction"),
    btnDislikeClose: $("#btn-dislike-close"),
    btnDislikeCancel: $("#btn-dislike-cancel"),
    btnDislikeSave: $("#btn-dislike-save"),
    btnToggleInspector: $("#btn-toggle-inspector"),
    btnNewChat: $("#btn-new-chat"),
    pageBreadcrumb: $("#page-breadcrumb"),
    chatExportActions: $("#chat-export-actions"),
    btnExportMd: $("#btn-export-md"),
    btnExportPdf: $("#btn-export-pdf"),
    btnTempChat: $("#btn-temp-chat"),
    tempChatHero: $("#temp-chat-hero"),
    btnTempPersonalize: $("#btn-temp-personalize"),
    btnChatOutputs: $("#btn-chat-outputs"),
    chatOutputsPopover: $("#chat-outputs-popover"),
    chatOutputsList: $("#chat-outputs-list"),
    chatOutputsCount: $("#chat-outputs-count"),
    btnChatOutputsClose: $("#btn-chat-outputs-close"),
    btnActorChip: $("#btn-actor-chip"),
    actorChipLabel: $("#actor-chip-label"),
    ctxMeterPill: $("#ctx-meter-pill"),
    ctxPillRingFg: $("#ctx-pill-ring-fg"),
    ctxMeterPct: $("#ctx-meter-pct"),
    ctxWarnBanner: $("#ctx-warn-banner"),
    ctxWarnRingFg: $("#ctx-warn-ring-fg"),
    ctxWarnText: $("#ctx-warn-text"),
    btnCtxCompactNow: $("#btn-ctx-compact-now"),
    thinkingSliderCard: $("#thinking-slider-card"),
    tsLevelLabel: $("#ts-level-label"),
    tsTrack: $("#ts-track"),
    tsFill: $("#ts-fill"),
    tsParticlesCanvas: $("#ts-particles-canvas"),
    tsThumb: $("#ts-thumb"),
    starterPillsRow: $("#starter-pills-row"),
    msgMoreMenu: $("#msg-more-menu"),
    msgMoreMeta: $("#msg-more-meta"),
    sourcesModal: $("#sources-modal"),
    sourcesModalCount: $("#sources-modal-count"),
    sourcesModalBody: $("#sources-modal-body"),
    btnSourcesModalClose: $("#btn-sources-modal-close"),
    pinLockOverlay: $("#pin-lock-overlay"),
    inpLoginUsername: $("#inp-login-username"),
    inpPinUnlock: $("#inp-pin-unlock"),
    btnPinUnlock: $("#btn-pin-unlock"),
    btnGuestContinue: $("#btn-guest-continue"),
    btnLoginClose: $("#btn-login-close"),
    pinLockErr: $("#pin-lock-err"),
    pinStatusBadge: $("#pin-status-badge"),
    inpPinNew: $("#inp-pin-new"),
    swPinLocalBypass: $("#sw-pin-local-bypass"),
    btnPinSave: $("#btn-pin-save"),
    btnPinRemove: $("#btn-pin-remove"),
    sessionSearch: $("#session-search"),
    sessionList: $("#session-list"),
    sessionFilesLabel: $("#session-files-label"),
    sessionFilesList: $("#session-files-list"),
    libraryFileInput: $("#library-file-input"),
    btnLibraryUpload: $("#btn-library-upload"),
    libraryDocsList: $("#library-docs-list"),
    btnRagToggle: $("#btn-rag-toggle"),
    btnHandsFree: $("#btn-handsfree"),
    personaGrid: $("#persona-grid"),
    renameSessionModal: $("#rename-session-modal"),
    renameSessionInput: $("#rename-session-input"),
    btnRenameClose: $("#btn-rename-close"),
    btnRenameCancel: $("#btn-rename-cancel"),
    btnRenameSave: $("#btn-rename-save"),
    confirmDeleteModal: $("#confirm-delete-modal"),
    confirmDeleteDesc: $("#confirm-delete-desc"),
    btnConfirmDelCancel: $("#btn-confirm-del-cancel"),
    btnConfirmDelOk: $("#btn-confirm-del-ok"),
    sessionCtxMenu: $("#session-ctx-menu"),
    ctxPinLabel: $("#ctx-pin-label"),
    gpuCard: $("#gpu-card"),
    gpuStateText: $("#gpu-state-text"),
    gpuDetailText: $("#gpu-detail-text"),
    gpuUtilBadge: $("#gpu-util-badge"),
    gpuEngineTag: $("#gpu-engine-tag"),
    idleCountdown: $("#idle-countdown"),
    vramDevice: $("#vram-device"),
    vramModelMb: $("#vram-model-mb"),
    vramNumbers: $("#vram-numbers"),
    vramFillOther: $("#vram-fill-other"),
    vramFill: $("#vram-fill"),
    gpuDlStrip: $("#gpu-dl-strip"),
    gpuDlName: $("#gpu-dl-name"),
    gpuDlPct: $("#gpu-dl-pct"),
    gpuDlFill: $("#gpu-dl-fill"),
    gpuDlBytes: $("#gpu-dl-bytes"),
    gpuDlSpeed: $("#gpu-dl-speed"),
    btnGpuDlCancel: $("#btn-gpu-dl-cancel"),
    btnGpuLoad: $("#btn-gpu-load"),
    btnGpuUnload: $("#btn-gpu-unload"),
    topDlRingWrap: $("#top-dl-ring-wrap"),
    topDlRingFg: $("#top-dl-ring-fg"),
    topDlPct: $("#top-dl-pct"),
    topProfileChip: $("#top-profile-chip"),
    topModelPill: $("#top-model-pill"),
    btnNotifBell: $("#btn-notif-bell"),
    notifBadge: $("#notif-badge"),
    notifPopover: $("#notif-popover"),
    btnNotifClear: $("#btn-notif-clear"),
    notifList: $("#notif-list"),
    datasetCountBadge: $("#dataset-count-badge"),
    btnExportDataset: $("#btn-export-dataset"),
    btnDownloadColab: $("#btn-download-colab"),
    dropZone: $("#drop-zone"),
    dragOverlay: $("#drag-overlay"),
    chatScroll: $("#chat-scroll"),
    welcomeHero: $("#welcome-hero"),
    messagesList: $("#messages-list"),
    composerCard: $("#composer-card"),
    promptInput: $("#prompt-input"),
    fileInput: $("#file-input"),
    btnAttach: $("#btn-attach"),
    pendingAttachments: $("#pending-attachments"),
    btnComposerPicker: $("#btn-composer-picker"),
    composerPrism: $("#composer-prism"),
    composerPillLabel: $("#composer-pill-label"),
    composerEffortDot: $("#composer-effort-dot"),
    composerPopover: $("#composer-popover"),
    effortSegBar: $("#effort-seg-bar"),
    effortPillIndicator: $("#effort-pill-indicator"),
    effortTokenBadge: $("#effort-token-badge"),
    effortHintBox: $("#effort-hint-box"),
    effortDescLine: $("#effort-desc-line"),
    composerModelList: $("#composer-model-list"),
    btnWebToggle: $("#btn-web-toggle"),
    btnMic: $("#btn-mic"),
    btnSend: $("#btn-send"),
    btnStop: $("#btn-stop"),
    recordingBar: $("#recording-bar"),
    recWaveform: $("#rec-waveform"),
    recTimer: $("#rec-timer"),
    btnRecStop: $("#btn-rec-stop"),
    btnRecCancel: $("#btn-rec-cancel"),
    inspModelCards: $("#insp-model-cards"),
    gpuProfileDd: $("#gpu-profile-dd"),
    lblGpuProfile: $("#lbl-gpu-profile"),
    ctxSizeDd: $("#ctx-size-dd"),
    lblCtxSize: $("#lbl-ctx-size"),
    memoryCountBadge: $("#memory-count-badge"),
    inpMemoryAdd: $("#inp-memory-add"),
    btnMemoryAdd: $("#btn-memory-add"),
    memoryList: $("#memory-list"),
    ttsVoiceDd: $("#tts-voice-dd"),
    lblTtsVoice: $("#lbl-tts-voice"),
    loraDd: $("#lora-dd"),
    lblLora: $("#lbl-lora"),
    menuLora: $("#menu-lora"),
    swAutoTts: $("#sw-auto-tts"),
    swWebSearch: $("#sw-web-search"),
    rngTemp: $("#rng-temp"),
    valTemp: $("#val-temp"),
    rngTopP: $("#rng-top-p"),
    valTopP: $("#val-top-p"),
    rngMaxTokens: $("#rng-max-tokens"),
    valMaxTokens: $("#val-max-tokens"),
    rngIdleMin: $("#rng-idle-min"),
    valIdleMin: $("#val-idle-min"),
    rngLoraScale: $("#rng-lora-scale"),
    valLoraScale: $("#val-lora-scale"),
    txtSystemPrompt: $("#txt-system-prompt"),
    btnSaveConfig: $("#btn-save-config"),
    inspDsCount: $("#insp-ds-count"),
    btnInspExportDs: $("#btn-insp-export-ds"),
    btnInspColabNb: $("#btn-insp-colab-nb"),
    inspDatasetList: $("#insp-dataset-list"),
    audioEl: $("#audio-el"),
    datasetModal: $("#dataset-modal"),
    dsUserInput: $("#ds-user-input"),
    dsAssistantInput: $("#ds-assistant-input"),
    btnModalClose: $("#btn-modal-close"),
    btnDsCancel: $("#btn-ds-cancel"),
    btnDsSave: $("#btn-ds-save"),
    lightboxModal: $("#lightbox-modal"),
    lightboxImg: $("#lightbox-img"),
    btnLightboxClose: $("#btn-lightbox-close"),
    toastRegion: $("#toast-region"),
  };

  function escHtml(str) {
    return String(str ?? "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function formatSec(sec) {
    const s = Math.max(0, Math.floor(Number(sec) || 0));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }

  function nowHHMM() {
    const d = new Date();
    return `${String(d.getHours()).padStart(2, "0")}:${String(d.getMinutes()).padStart(2, "0")}`;
  }

  function newId(prefix = "s") {
    return `${prefix}_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 7)}`;
  }

  async function apiJson(url, opts = {}) {
    const res = await fetch(url, opts);
    if (!res.ok) {
      let msg = `HTTP ${res.status}`;
      try {
        const j = await res.json();
        msg = j.detail || j.error || msg;
      } catch (_) {}
      throw new Error(msg);
    }
    return res.json();
  }

  function showToast(message, type = "ok", duration = 3800) {
    const el = document.createElement("div");
    el.className = `toast toast-${type}`;
    el.innerHTML = `<span class="toast-dot"></span><span>${escHtml(message)}</span><span class="toast-bar"></span>`;
    dom.toastRegion.appendChild(el);
    const bar = $(".toast-bar", el);
    if (bar) bar.style.animationDuration = `${duration}ms`;

    const dismiss = () => {
      if (el.classList.contains("leaving")) return;
      el.classList.add("leaving");
      setTimeout(() => el.remove(), 380);
    };
    el.addEventListener("click", dismiss);
    setTimeout(dismiss, duration);
  }

  function pushNotification(title, desc = "", type = "ok") {
    state.notifications.unshift({ id: newId("n"), title, desc, type, time: nowHHMM() });
    if (state.notifications.length > 25) state.notifications.pop();
    if (!dom.notifPopover.classList.contains("open")) state.unreadNotifs += 1;
    renderNotifications();
  }

  function renderNotifications() {
    if (state.unreadNotifs > 0) {
      dom.notifBadge.hidden = false;
      dom.notifBadge.textContent = String(state.unreadNotifs);
      dom.notifBadge.classList.remove("has-unread");
      void dom.notifBadge.offsetWidth;
      dom.notifBadge.classList.add("has-unread");
    } else {
      dom.notifBadge.hidden = true;
    }

    if (!state.notifications.length) {
      dom.notifList.innerHTML = `
        <div class="notif-empty-state">
          <span class="notif-empty-ico" aria-hidden="true">${SVG_ICONS.okCircle}</span>
          <span>Tüm bildirimler temiz — yeni etkinlik yok.</span>
        </div>`;
      return;
    }
    dom.notifList.innerHTML = state.notifications
      .map(
        (n) => `
      <div class="notif-item type-${escHtml(n.type)}" data-nid="${escHtml(n.id)}">
        <span class="notif-ico">${n.type === "err" || n.type === "warn" ? SVG_ICONS.warn : SVG_ICONS.okCircle}</span>
        <div>
          <div class="notif-item-title">${escHtml(n.title)}</div>
          ${n.desc ? `<div class="notif-item-desc">${escHtml(n.desc)}</div>` : ""}
        </div>
        <div class="notif-item-right">
          <span class="notif-item-time mono">${escHtml(n.time)}</span>
          <button type="button" class="notif-dismiss-btn" data-dismiss-nid="${escHtml(n.id)}" title="Kaldır" aria-label="Bildirimi kaldır">${SVG_ICONS.xClose}</button>
        </div>
      </div>`
      )
      .join("");
  }

  function clearNotificationsAnimated() {
    if (!state.notifications.length) return;
    const rows = $$(".notif-item", dom.notifList);
    rows.forEach((el, idx) => {
      setTimeout(() => el.classList.add("is-clearing"), idx * 45);
    });
    const clearBtn = dom.btnNotifClear;
    if (clearBtn) {
      clearBtn.classList.add("is-cleared");
      const sp = $("span", clearBtn);
      if (sp) sp.textContent = "Temizlendi";
      setTimeout(() => {
        clearBtn.classList.remove("is-cleared");
        if (sp) sp.textContent = "Temizle";
      }, 1400);
    }
    const waitMs = Math.min(480, rows.length * 45 + 260);
    setTimeout(() => {
      state.notifications = [];
      state.unreadNotifs = 0;
      renderNotifications();
    }, waitMs);
  }

  /* =========================================================
     Theme Toggle & Popovers
     ========================================================= */
  function resolveTheme(pref) {
    if (pref === "light") return "light";
    if (pref === "dark") return "dark";
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
  }

  function applyTheme(theme) {
    const pref = theme === "light" || theme === "system" ? theme : "dark";
    const eff = resolveTheme(pref);
    dom.html.setAttribute("data-theme", eff);
    localStorage.setItem("yerelai_theme", pref);
    dom.iconSun.hidden = eff === "light";
    dom.iconMoon.hidden = eff === "dark";
    window.YerelSettings?.syncThemeCards?.(pref);
    window.yerelDesktop?.setTheme?.(pref);
  }

  if (window.matchMedia) {
    window.matchMedia("(prefers-color-scheme: dark)").addEventListener?.("change", () => {
      if ((localStorage.getItem("yerelai_theme") || "dark") === "system") applyTheme("system");
    });
  }

  function toggleTheme() {
    const next = dom.html.getAttribute("data-theme") === "dark" ? "light" : "dark";
    dom.btnThemeToggle.classList.add("is-spinning");
    setTimeout(() => dom.btnThemeToggle.classList.remove("is-spinning"), 460);
    if (document.startViewTransition) document.startViewTransition(() => applyTheme(next));
    else applyTheme(next);
  }

  function closeAllPopovers(except = null) {
    if (except !== "composer") {
      dom.composerPopover.classList.remove("open");
      dom.btnComposerPicker.classList.remove("is-open");
      dom.btnComposerPicker.setAttribute("aria-expanded", "false");
      setTimeout(() => {
        if (!dom.composerPopover.classList.contains("open")) dom.composerPopover.hidden = true;
      }, 220);
    }
    if (except !== "tools" && dom.composerToolsMenu) {
      dom.composerToolsMenu.hidden = true;
      dom.btnComposerTools?.setAttribute("aria-expanded", "false");
    }
    if (except !== "notif") {
      dom.notifPopover.classList.remove("open");
      setTimeout(() => {
        if (!dom.notifPopover.classList.contains("open")) dom.notifPopover.hidden = true;
      }, 220);
    }
    $$(".custom-select-wrap").forEach((wrap) => {
      if (wrap.id === except) return;
      const btn = $(".format-trigger-btn", wrap);
      const menu = $(".format-dropdown-menu", wrap);
      if (btn) {
        btn.classList.remove("is-open");
        btn.setAttribute("aria-expanded", "false");
      }
      if (menu) menu.hidden = true;
    });
  }

  function setupCustomDropdown(wrapEl, onSelect) {
    const btn = $(".format-trigger-btn", wrapEl);
    const menu = $(".format-dropdown-menu", wrapEl);
    btn.addEventListener("click", (e) => {
      e.stopPropagation();
      const willOpen = menu.hidden;
      closeAllPopovers(willOpen ? wrapEl.id : null);
      menu.hidden = !willOpen;
      btn.classList.toggle("is-open", willOpen);
      btn.setAttribute("aria-expanded", String(willOpen));
    });
    menu.addEventListener("click", (e) => {
      const item = e.target.closest(".format-item");
      if (!item) return;
      e.stopPropagation();
      const val = item.dataset.val ?? "";
      $$(".format-item", menu).forEach((el) => el.classList.toggle("selected", el === item));
      menu.hidden = true;
      btn.classList.remove("is-open");
      btn.setAttribute("aria-expanded", "false");
      onSelect(val, item);
    });
  }

  function setCustomDropdownValue(wrapEl, labelEl, val, fallbackLabel = "") {
    const items = $$(".format-item", wrapEl);
    let matchedText = fallbackLabel;
    items.forEach((it) => {
      const isMatch = (it.dataset.val ?? "") === String(val ?? "");
      it.classList.toggle("selected", isMatch);
      if (isMatch) {
        const sp = $("span", it);
        if (sp) matchedText = sp.textContent;
      }
    });
    if (labelEl && matchedText) labelEl.textContent = matchedText;
  }

  const EFFORT_LEVELS = ["off", "low", "medium", "high"];
  let tsParticlesRaf = null;
  let tsParticles = [];

  function stopCosmicParticles() {
    if (tsParticlesRaf) {
      cancelAnimationFrame(tsParticlesRaf);
      tsParticlesRaf = null;
    }
    const cvs = dom.tsParticlesCanvas;
    if (cvs) {
      const ctx2d = cvs.getContext("2d");
      if (ctx2d) ctx2d.clearRect(0, 0, cvs.width, cvs.height);
    }
  }

  function startCosmicParticles() {
    const cvs = dom.tsParticlesCanvas;
    if (!cvs) return;
    if (window.matchMedia?.("(prefers-reduced-motion: reduce)")?.matches) return;
    if (state.thinkingEffort !== "high" || dom.composerPopover?.hidden) {
      stopCosmicParticles();
      return;
    }
    if (tsParticlesRaf) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const rect = cvs.getBoundingClientRect();
    const w = Math.max(120, Math.round(rect.width || 240));
    const h = Math.max(20, Math.round(rect.height || 26));
    cvs.width = w * dpr;
    cvs.height = h * dpr;
    const g = cvs.getContext("2d");
    g.scale(dpr, dpr);

    if (!tsParticles.length) {
      for (let i = 0; i < 18; i++) {
        tsParticles.push({
          x: Math.random() * w,
          y: 4 + Math.random() * (h - 8),
          r: 0.9 + Math.random() * 1.4,
          vx: -(0.65 + Math.random() * 1.45),
          alpha: 0.35 + Math.random() * 0.6,
          tint: i % 3 === 0 ? "#ffe4e6" : (i % 3 === 1 ? "#fda4af" : "#fb7185"),
        });
      }
    }
    const tick = () => {
      if (state.thinkingEffort !== "high" || dom.composerPopover?.hidden) {
        stopCosmicParticles();
        return;
      }
      g.clearRect(0, 0, w, h);
      for (const p of tsParticles) {
        p.x += p.vx;
        if (p.x < -6) {
          p.x = w - 6 + Math.random() * 6;
          p.y = 4 + Math.random() * (h - 8);
        }
        g.globalAlpha = p.alpha;
        g.fillStyle = p.tint;
        g.beginPath();
        g.arc(p.x, p.y, p.r, 0, Math.PI * 2);
        g.fill();
      }
      g.globalAlpha = 1;
      tsParticlesRaf = requestAnimationFrame(tick);
    };
    tsParticlesRaf = requestAnimationFrame(tick);
  }

  function setSliderVisualPosition(frac) {
    const f = Math.max(0, Math.min(1, frac));
    if (dom.tsFill) dom.tsFill.style.width = f <= 0.02 ? "0%" : `${Math.round(f * 100)}%`;
    if (dom.tsThumb) dom.tsThumb.style.left = `calc(13px + (100% - 26px) * ${f.toFixed(4)})`;
  }

  function updateEffortPill(effort, animate = true) {
    const eff = EFFORT_META[effort] ? effort : "medium";
    const meta = EFFORT_META[eff];
    const idx = Math.max(0, EFFORT_LEVELS.indexOf(eff));
    const frac = idx / 3;
    state.thinkingEffort = eff;

    if (dom.thinkingSliderCard) {
      dom.thinkingSliderCard.dataset.level = eff;
      $$(".ts-lbl-btn", dom.thinkingSliderCard).forEach((b) => {
        b.classList.toggle("active", b.dataset.effort === eff);
      });
    }
    if (dom.tsLevelLabel) dom.tsLevelLabel.textContent = meta.label;
    if (dom.tsTrack) {
      dom.tsTrack.setAttribute("aria-valuenow", String(idx));
      dom.tsTrack.setAttribute("aria-valuetext", meta.label);
    }
    if (!animate && dom.thinkingSliderCard) {
      dom.thinkingSliderCard.classList.add("is-dragging");
      setSliderVisualPosition(frac);
      requestAnimationFrame(() => dom.thinkingSliderCard?.classList.remove("is-dragging"));
    } else {
      setSliderVisualPosition(frac);
    }

    if (dom.effortHintBox) dom.effortHintBox.dataset.effort = eff;
    if (dom.effortTokenBadge) dom.effortTokenBadge.textContent = meta.budget;
    if (dom.composerEffortDot) dom.composerEffortDot.dataset.effort = eff;
    if (dom.effortDescLine) dom.effortDescLine.textContent = meta.desc;
    updateComposerPillLabel();

    if (eff === "high" && dom.composerPopover && !dom.composerPopover.hidden) {
      startCosmicParticles();
    } else {
      stopCosmicParticles();
    }
  }

  function initThinkingSlider() {
    const track = dom.tsTrack;
    const card = dom.thinkingSliderCard;
    if (!track || !card) return;

    const fracFromClientX = (clientX) => {
      const r = track.getBoundingClientRect();
      if (r.width <= 0) return 0;
      return Math.max(0, Math.min(1, (clientX - r.left - 13) / Math.max(1, r.width - 26)));
    };
    const levelFromFrac = (f) => EFFORT_LEVELS[Math.min(3, Math.max(0, Math.round(f * 3)))];

    let dragging = false;
    track.addEventListener("pointerdown", (e) => {
      dragging = true;
      card.classList.add("is-dragging");
      track.setPointerCapture?.(e.pointerId);
      const f = fracFromClientX(e.clientX);
      setSliderVisualPosition(f);
      const lv = levelFromFrac(f);
      card.dataset.level = lv;
      if (dom.tsLevelLabel) dom.tsLevelLabel.textContent = EFFORT_META[lv].label;
      if (lv === "high") startCosmicParticles();
      else stopCosmicParticles();
    });
    track.addEventListener("pointermove", (e) => {
      if (!dragging) return;
      const f = fracFromClientX(e.clientX);
      setSliderVisualPosition(f);
      const lv = levelFromFrac(f);
      if (card.dataset.level !== lv) {
        card.dataset.level = lv;
        if (dom.tsLevelLabel) dom.tsLevelLabel.textContent = EFFORT_META[lv].label;
        if (lv === "high") startCosmicParticles();
        else stopCosmicParticles();
      }
    });
    const finishDrag = (e) => {
      if (!dragging) return;
      dragging = false;
      card.classList.remove("is-dragging");
      const f = fracFromClientX(e.clientX);
      updateEffortPill(levelFromFrac(f), true);
      window.YerelSettings?.scheduleAutoSave?.();
    };
    track.addEventListener("pointerup", finishDrag);
    track.addEventListener("pointercancel", finishDrag);

    track.addEventListener("keydown", (e) => {
      const curIdx = Math.max(0, EFFORT_LEVELS.indexOf(state.thinkingEffort));
      if (e.key === "ArrowRight" || e.key === "ArrowUp") {
        e.preventDefault();
        updateEffortPill(EFFORT_LEVELS[Math.min(3, curIdx + 1)], true);
        window.YerelSettings?.scheduleAutoSave?.();
      } else if (e.key === "ArrowLeft" || e.key === "ArrowDown") {
        e.preventDefault();
        updateEffortPill(EFFORT_LEVELS[Math.max(0, curIdx - 1)], true);
        window.YerelSettings?.scheduleAutoSave?.();
      }
    });

    card.addEventListener("click", (e) => {
      const btn = e.target.closest(".ts-lbl-btn");
      if (!btn) return;
      updateEffortPill(btn.dataset.effort, true);
      window.YerelSettings?.scheduleAutoSave?.();
    });
  }

  function getActiveModelObj() {
    return state.models.find((m) => m.id === state.selectedModelId) || state.models[0] || null;
  }

  function getShortModelName(m) {
    if (!m) return "Gemma 4 E2B";
    return m.id.includes("e4b") ? "Gemma 4 E4B" : "Gemma 4 E2B";
  }

  function updateComposerPillLabel() {
    const m = getActiveModelObj();
    const shortName = getShortModelName(m);
    const isE4b = m && m.id.includes("e4b");
    dom.composerPrism.classList.toggle("e4b", Boolean(isE4b));
    dom.composerPrism.innerHTML = isE4b ? PRISM_E4B_SVG : PRISM_E2B_SVG;
    dom.composerPillLabel.textContent = `${shortName} · ${EFFORT_META[state.thinkingEffort]?.label || "Orta"}`;
    dom.topModelPill.textContent = shortName;
  }

  function syncWebSearchUI(enabled) {
    state.webSearch = Boolean(enabled);
    dom.btnWebToggle.classList.toggle("active", state.webSearch);
    dom.btnWebToggle.setAttribute("aria-pressed", String(state.webSearch));
    dom.swWebSearch.checked = state.webSearch;
    if (dom.ctmWebState) dom.ctmWebState.textContent = state.webSearch ? "Açık" : "Kapalı";
    if (dom.chipWebActive) dom.chipWebActive.hidden = !state.webSearch;
  }

  /* =========================================================
     Models, LoRA & Config (Fixed PUT/POST + Registry Fields)
     ========================================================= */
  function formatBytesGb(bytes) {
    const b = Number(bytes || 0);
    if (b <= 0) return "0.00 GB";
    if (b >= 1024 * 1024 * 1024) return `${(b / (1024 * 1024 * 1024)).toFixed(2)} GB`;
    return `${(b / (1024 * 1024)).toFixed(0)} MB`;
  }

  function formatEta(sec) {
    const s = Math.max(0, Math.round(Number(sec || 0)));
    if (s <= 0) return "";
    if (s < 60) return `~${s} sn`;
    const m = Math.floor(s / 60);
    const rem = s % 60;
    return rem > 0 ? `~${m} dk ${rem} sn` : `~${m} dk`;
  }

  function buildModelDlBoxHtml(dl) {
    const pct = Math.min(100, Math.max(0, Number(dl.percent || 0)));
    const bytesTxt = dl.total_bytes > 0 ? `${formatBytesGb(dl.downloaded_bytes)} / ${formatBytesGb(dl.total_bytes)}` : "Boyut hesaplanıyor...";
    const speedTxt = dl.speed_mbps > 0 ? `${Number(dl.speed_mbps).toFixed(1)} MB/sn` : "Başlatılıyor...";
    const etaTxt = formatEta(dl.eta_seconds);
    const fileNote = dl.file_count ? `Dosya ${dl.file_index || 1}/${dl.file_count}` : "İndiriliyor";
    return `
      <div class="model-dl-box" data-dl-box="${escHtml(dl.model_id || "")}">
        <div class="model-dl-top">
          <span class="model-dl-file">${escHtml(fileNote)} · ${escHtml(dl.file_name || "")}</span>
          <span class="model-dl-pct mono">%${pct.toFixed(1)}</span>
          <span role="button" tabindex="0" class="dl-cancel-mini" data-dl-action="cancel" title="İndirmeyi İptal Et" aria-label="İndirmeyi İptal Et">✕</span>
        </div>
        <div class="dl-track"><div class="dl-fill" style="width:${pct.toFixed(1)}%"></div></div>
        <div class="model-dl-stats mono">
          <span>${escHtml(bytesTxt)}</span>
          <span>${escHtml(speedTxt)}${etaTxt ? ` · ${escHtml(etaTxt)}` : ""}</span>
        </div>
      </div>`;
  }

  function renderModelsUI() {
    if (!state.models.length) return;
    const dl = state.download || {};

    const getModelVisual = (m) => {
      const isE4b = m.id.includes("e4b");
      const shortTitle = m.short_name || (isE4b ? "Gemma 4 E4B" : "Gemma 4 E2B");
      const roleTag = isE4b ? "Derin" : "Turbo";
      const vramMb = m.vram_estimate_mb || (isE4b ? 5600 : 3400);
      const vramGb = (Number(vramMb) / 1000).toFixed(1);
      const dlSizeGb = m.download_size_gb || (isE4b ? 6.0 : 4.1);
      const activeCore = isE4b ? "4.5B" : "2.3B";
      const svg = isE4b ? PRISM_E4B_SVG : PRISM_E2B_SVG;
      const isDownloading = Boolean(dl.active && dl.model_id === m.id);
      return { isE4b, shortTitle, roleTag, vramMb, vramGb, dlSizeGb, activeCore, svg, isDownloading };
    };

    dom.inspModelCards.innerHTML = state.models
      .map((m) => {
        const v = getModelVisual(m);
        const isSel = m.id === state.selectedModelId;
        const badgeTxt = v.isDownloading ? `%${Number(dl.percent || 0).toFixed(1)}` : m.cached_locally ? "Hazır" : `↓ İndir (~${v.dlSizeGb} GB)`;
        const paramsTxt = m.effective_params || v.activeCore;
        return `
        <button type="button" class="model-mini-card ${v.isE4b ? "is-e4b" : ""} ${isSel ? "selected" : ""} ${v.isDownloading ? "is-downloading" : ""}" data-model-id="${escHtml(m.id)}">
          <span class="prism-mark md ${v.isE4b ? "e4b" : ""}" aria-hidden="true">${v.svg}</span>
          <div class="model-mini-body">
            <div class="model-mini-top">
              <span class="model-mini-title">${escHtml(v.shortTitle)} <span class="vp-role-chip ${v.isE4b ? "e4b" : ""}">${escHtml(v.roleTag)}</span></span>
              <span class="model-badge ${m.cached_locally || v.isDownloading ? "ready" : ""}">${escHtml(badgeTxt)}</span>
            </div>
            <div class="model-mini-desc">${escHtml(paramsTxt)} · ~${escHtml(v.vramMb)} MB VRAM</div>
          </div>
          <span class="model-check" aria-hidden="true">${SVG_ICONS.check}</span>
          ${v.isDownloading ? buildModelDlBoxHtml(dl) : ""}
        </button>`;
      })
      .join("");

    dom.composerModelList.innerHTML = state.models
      .map((m) => {
        const v = getModelVisual(m);
        const isSel = m.id === state.selectedModelId;
        const statusCls = v.isDownloading ? "is-dl-active" : m.cached_locally ? "ready" : "dl-cta";
        const statusTxt = v.isDownloading ? `%${Number(dl.percent || 0).toFixed(1)}` : m.cached_locally ? "Hazır" : `↓ İndir (${v.dlSizeGb} GB)`;
        return `
        <button type="button" class="vp-row ${v.isE4b ? "is-e4b" : ""} ${isSel ? "selected" : ""} ${v.isDownloading ? "is-downloading" : ""}" data-model-id="${escHtml(m.id)}">
          <div class="vp-row-main">
            <span class="prism-mark vp-ico ${v.isE4b ? "e4b" : ""}" aria-hidden="true">${v.svg}</span>
            <div class="vp-model-copy">
              <div class="vp-model-head">
                <span class="vp-model-title">${escHtml(v.shortTitle)}</span>
                <span class="vp-role-chip ${v.isE4b ? "e4b" : ""}">${escHtml(v.roleTag)}</span>
              </div>
              <div class="vp-model-sub">${escHtml(v.activeCore)} · ~${escHtml(v.vramGb)} GB VRAM · Ses &amp; Görsel</div>
            </div>
            <div class="vp-model-right">
              <span class="vp-status-pill ${statusCls}" ${!m.cached_locally && !v.isDownloading ? 'data-dl-action="start"' : ""}>${escHtml(statusTxt)}</span>
              ${m.cached_locally ? `<span class="vp-check-circle" aria-hidden="true">${SVG_ICONS.check}</span>` : ""}
            </div>
          </div>
          ${v.isDownloading ? buildModelDlBoxHtml(dl) : ""}
        </button>`;
      })
      .join("");

    updateComposerPillLabel();
  }

  async function refreshModels() {
    try {
      const modelsData = await apiJson("/api/models");
      state.models = modelsData.models || [];
      state.loras = modelsData.loras || [];
      renderModelsUI();
      renderLorasUI();
    } catch (_) {}
  }

  async function startModelDownload(modelId) {
    if (!modelId) return;
    if (state.download?.active) {
      showToast("Zaten aktif bir model indirmesi sürüyor", "warn", 2600);
      return;
    }
    const m = state.models.find((x) => x.id === modelId);
    const label = getShortModelName(m);
    showToast(`${label} indiriliyor... (sohbetiniz kesintiye uğramaz)`, "ok", 3200);
    try {
      const res = await apiJson("/api/model/download", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model_id: modelId }),
      });
      if (res.download) {
        updateDownloadUI(res.download);
      }
      scheduleNextPoll(500);
    } catch (err) {
      showToast(`İndirme başlatılamadı: ${err.message}`, "err", 4200);
    }
  }

  async function cancelModelDownload() {
    try {
      const res = await apiJson("/api/model/download/cancel", { method: "POST" });
      if (res.download) updateDownloadUI(res.download);
      showToast("İndirme duraklatıldı (kaldığı yerden devam edilebilir)", "warn", 3200);
    } catch (err) {
      showToast(`İptal hatası: ${err.message}`, "err", 3200);
    }
  }

  function selectModel(modelId) {
    if (!modelId) return;
    state.selectedModelId = modelId;
    renderModelsUI();
    window.YerelSettings?.scheduleAutoSave?.();
    showToast(`${getShortModelName(getActiveModelObj())} seçildi`, "ok", 2200);
  }

  function renderLorasUI() {
    const opts = [{ id: "", name: "Adaptör Yok (Temel Model)" }, ...state.loras];
    dom.menuLora.innerHTML = opts
      .map(
        (l) => `
      <button type="button" class="format-item ${l.id === state.selectedLoraId ? "selected" : ""}" data-val="${escHtml(l.id)}">
        <span>${escHtml(l.name || l.id)}</span>
        <span class="check-mark">✓</span>
      </button>`
      )
      .join("");
    setCustomDropdownValue(dom.loraDd, dom.lblLora, state.selectedLoraId, "Adaptör Yok (Temel Model)");
  }

  function applyConfigToUI(cfg) {
    state.config = cfg || {};
    const gen = cfg.generation || {};
    state.selectedModelId = cfg.default_model_id || state.selectedModelId;
    if (state.models.length && !state.models.some((m) => m.id === state.selectedModelId)) {
      state.selectedModelId = state.models[0].id;
    }
    state.selectedLoraId = cfg.active_lora_id || "";
    state.gpuProfile = cfg.gpu_profile || "auto";
    state.contextLength = Number(cfg.context_length || 32768);
    state.ttsVoice = gen.tts_voice || "tr-TR-AhmetNeural";
    state.autoTts = Boolean(gen.auto_tts);

    updateEffortPill(gen.thinking_effort || "medium", false);
    syncWebSearchUI(Boolean(gen.web_search));

    dom.swAutoTts.checked = state.autoTts;
    dom.rngTemp.value = gen.temperature ?? 0.7;
    dom.valTemp.textContent = Number(dom.rngTemp.value).toFixed(2);
    dom.rngTopP.value = gen.top_p ?? 0.95;
    dom.valTopP.textContent = Number(dom.rngTopP.value).toFixed(2);
    dom.rngMaxTokens.value = gen.max_new_tokens ?? 3072;
    dom.valMaxTokens.textContent = String(dom.rngMaxTokens.value);
    dom.rngIdleMin.value = cfg.idle_timeout_minutes ?? 25;
    dom.valIdleMin.textContent = `${dom.rngIdleMin.value} dk`;
    dom.rngLoraScale.value = cfg.lora_scale ?? 1.0;
    dom.valLoraScale.textContent = `${Number(dom.rngLoraScale.value).toFixed(1)}x`;
    dom.txtSystemPrompt.value = cfg.system_prompt || "";

    setCustomDropdownValue(dom.gpuProfileDd, dom.lblGpuProfile, state.gpuProfile, PROFILE_LABELS[state.gpuProfile]);
    if (dom.ctxSizeDd) {
      setCustomDropdownValue(dom.ctxSizeDd, dom.lblCtxSize, String(state.contextLength), CTX_LABELS[String(state.contextLength)] || CTX_LABELS["32768"]);
    }
    setCustomDropdownValue(dom.ttsVoiceDd, dom.lblTtsVoice, state.ttsVoice, TTS_LABELS[state.ttsVoice]);
    renderModelsUI();
    renderLorasUI();
  }

  function buildConfigPayload() {
    return {
      idle_timeout_minutes: Number(dom.rngIdleMin.value),
      default_model_id: state.selectedModelId,
      active_lora_id: state.selectedLoraId,
      lora_scale: Number(dom.rngLoraScale.value),
      gpu_profile: state.gpuProfile,
      context_length: Number(state.contextLength || 32768),
      generation: {
        thinking_effort: state.thinkingEffort,
        temperature: Number(dom.rngTemp.value),
        top_p: Number(dom.rngTopP.value),
        max_new_tokens: Number(dom.rngMaxTokens.value),
        auto_tts: dom.swAutoTts.checked,
        web_search: state.webSearch,
        tts_voice: state.ttsVoice,
      },
      system_prompt: dom.txtSystemPrompt.value.trim(),
    };
  }

  async function saveConfigSilent() {
    const payload = buildConfigPayload();
    try {
      await apiJson("/api/config", {
        method: "PUT",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      state.config = payload;
      return true;
    } catch (_) {
      return false;
    }
  }

  async function saveConfig() {
    const ok = await saveConfigSilent();
    if (ok) {
      showToast("Ayarlar kalıcı olarak kaydedildi", "ok");
      pushNotification("Ayarlar Kaydedildi", "Model, TTS ve profil tercihleri güncellendi.", "ok");
    } else {
      showToast("Ayarlar kaydedilemedi", "err");
    }
  }

  /* =========================================================
     Dual-Telemetry Live GPU Card
     ========================================================= */
  function updateDownloadUI(dl) {
    const prevStatus = state.lastDownloadStatus || "idle";
    const prevActive = Boolean(state.download?.active);
    const next = dl || { active: false, status: "idle", model_id: null, percent: 0 };
    state.download = next;

    const isActive = Boolean(next.active);
    const pct = Math.min(100, Math.max(0, Number(next.percent || 0)));

    if (dom.gpuDlStrip) {
      dom.gpuDlStrip.hidden = !isActive;
      if (isActive) {
        dom.gpuDlName.textContent = `${next.model_name || "Model"} (${next.file_index || 1}/${next.file_count || 2})`;
        dom.gpuDlPct.textContent = `%${pct.toFixed(1)}`;
        dom.gpuDlFill.style.width = `${pct.toFixed(1)}%`;
        dom.gpuDlBytes.textContent = next.total_bytes > 0 ? `${formatBytesGb(next.downloaded_bytes)} / ${formatBytesGb(next.total_bytes)}` : "Boyut hesaplanıyor...";
        const eta = formatEta(next.eta_seconds);
        dom.gpuDlSpeed.textContent = `${Number(next.speed_mbps || 0).toFixed(1)} MB/sn${eta ? ` · ${eta}` : ""}`;
      }
    }

    if (dom.topDlRingWrap && dom.topDlRingFg && dom.topDlPct) {
      dom.topDlRingWrap.hidden = !isActive;
      if (isActive) {
        const circ = 43.98;
        dom.topDlRingFg.style.strokeDashoffset = (circ * (1 - pct / 100)).toFixed(2);
        dom.topDlPct.textContent = `%${Math.round(pct)}`;
      }
    }
    window.yerelDesktop?.setProgress?.(isActive ? Math.max(0.02, pct / 100) : -1);

    if (isActive || prevActive !== isActive) {
      renderModelsUI();
    }

    if (prevStatus === "downloading" && next.status === "completed") {
      showToast(`${next.model_name || "Model"} indirildi ve kullanıma hazır`, "ok", 4200);
      pushNotification("Model İndirildi", `${next.model_name || "Model"} diske kaydedildi ve GPU'ya yüklenmeye hazır.`, "ok");
      refreshModels();
    } else if (prevStatus === "downloading" && next.status === "error") {
      showToast(`İndirme hatası: ${next.error || "Bilinmeyen hata"}`, "err", 5200);
      pushNotification("İndirme Hatası", next.error || "Model indirilemedi.", "err");
      refreshModels();
    } else if (prevStatus === "downloading" && next.status === "cancelled") {
      refreshModels();
    }

    state.lastDownloadStatus = next.status || "idle";
  }

  function updateGpuCard(st) {
    const s = st.state || "unloaded";
    dom.gpuCard.className = `gpu-card state-${s}`;
    const dlActive = Boolean(st.download && st.download.active);
    document.body.dataset.studioState = dlActive ? "downloading" : s;

    const stateLabels = {
      unloaded: "Beklemede",
      loading: "Yükleniyor...",
      ready: "GPU Hazır",
      generating: "Üretiliyor...",
      unloading: "Boşaltılıyor...",
      error: "Hata",
    };
    dom.gpuStateText.textContent = stateLabels[s] || s;

    const msgText = st.load_message || st.detail;
    const defaultMsgs = {
      ready: "Model GPU VRAM üzerinde aktif",
      loading: "Model GPU VRAM'e yükleniyor...",
      generating: "Aktif yanıt üretiliyor...",
      unloaded: "GPU beklemede (model yüklü değil)",
    };
    dom.gpuDetailText.textContent = msgText || defaultMsgs[s] || "GPU hazır";

    const backendTagMap = { gguf_turbo: "GGUF Turbo", pytorch_bnb: "PyTorch 4-Bit", none: "Beklemede" };
    dom.gpuEngineTag.textContent = backendTagMap[st.engine_backend] || (s === "ready" || s === "generating" ? "Aktif" : "Beklemede");

    const v = st.vram || {};
    const modelMb = Number(v.model_mb ?? v.used_mb ?? 0);
    const sysUsedMb = Number(v.system_used_mb ?? modelMb);
    const totalMb = Number(v.total_mb || 0);
    const gpuUtil = Number(v.gpu_util ?? 0);

    if (dom.gpuUtilBadge) {
      dom.gpuUtilBadge.textContent = `GPU: %${gpuUtil}`;
      const externalBusy = gpuUtil >= 40 && s !== "generating";
      dom.gpuUtilBadge.classList.toggle("is-busy", externalBusy);
      dom.gpuUtilBadge.title = externalBusy
        ? `Harici uygulama/oyun GPU kullanıyor (%${gpuUtil}) — üretim hızını etkileyebilir`
        : `Anlık GPU Çekirdek Yükü: %${gpuUtil}`;
    }

    const sysPct = totalMb > 0 ? Math.min(1, Math.max(0, sysUsedMb / totalMb)) : 0;
    const modPct = totalMb > 0 ? Math.min(1, Math.max(0, modelMb / totalMb)) : 0;

    const shortDev = (v.device || "GPU").replace("NVIDIA GeForce ", "");
    dom.vramDevice.textContent = shortDev;
    dom.vramModelMb.textContent = `Model: ${modelMb} MB`;
    dom.vramNumbers.textContent = totalMb > 0 ? `Kart: ${sysUsedMb} / ${totalMb} MB` : "CPU Modu";
    dom.vramFillOther.style.transform = `scaleX(${sysPct.toFixed(3)})`;
    dom.vramFill.style.transform = `scaleX(${modPct.toFixed(3)})`;

    if (dom.heroHwText && totalMb > 0) {
      const gbStr = (totalMb / 1024).toFixed(1);
      const profTxt = st.resolved_profile === "low_vram" ? "Low-VRAM" : "GGUF Turbo";
      dom.heroHwText.textContent = `${shortDev} · ${gbStr} GB VRAM · ${profTxt}`;
    }

    const rem = st.remaining_seconds ?? st.idle_remaining_sec;
    if (rem != null && s === "ready") {
      dom.idleCountdown.hidden = false;
      dom.idleCountdown.textContent = formatSec(rem);
    } else {
      dom.idleCountdown.hidden = true;
    }

    const isLoaded = s === "ready" || s === "generating";
    dom.btnGpuLoad.hidden = isLoaded;
    dom.btnGpuLoad.disabled = s === "loading";
    dom.btnGpuUnload.hidden = !isLoaded;

    if (st.resolved_profile) {
      dom.topProfileChip.textContent = st.resolved_profile === "turbo" ? "Turbo" : "Low-VRAM";
    }
    if (st.context_length) {
      state.contextLength = Number(st.context_length);
    }

    if (st.download) {
      updateDownloadUI(st.download);
    }
  }

  function scheduleNextPoll(delayMs = null) {
    if (state.statusTimer) clearTimeout(state.statusTimer);
    const fast = Boolean(state.download?.active || state.isGenerating);
    const wait = delayMs !== null ? delayMs : fast ? 750 : 2800;
    state.statusTimer = setTimeout(async () => {
      await pollStatus();
      scheduleNextPoll();
    }, wait);
  }

  async function pollStatus() {
    try {
      const st = await apiJson("/api/status");
      updateGpuCard(st);
      return st;
    } catch (_) {
      dom.gpuStateText.textContent = "Bağlantı yok";
      dom.gpuCard.className = "gpu-card state-error";
      return null;
    }
  }

  async function loadModelOnGpu() {
    dom.btnGpuLoad.disabled = true;
    dom.gpuCard.className = "gpu-card state-loading";
    dom.gpuStateText.textContent = "Yükleniyor...";
    dom.gpuDetailText.textContent = "GPU motoru başlatılıyor...";
    showToast("Model GPU VRAM'e yükleniyor...", "ok", 2800);
    try {
      await apiJson("/api/model/load", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model_id: state.selectedModelId,
          lora_id: state.selectedLoraId || "",
          lora_scale: Number(dom.rngLoraScale.value),
          gpu_profile: state.gpuProfile,
        }),
      });
      // Poll without artificial 108s timeout while downloading or loading
      while (true) {
        await new Promise((r) => setTimeout(r, 700));
        const st = await apiJson("/api/status");
        updateGpuCard(st);
        if (st.state === "ready") {
          showToast("Model GPU'da hazır (GGUF Turbo)", "ok");
          pushNotification("GPU Hazır", `${getShortModelName(getActiveModelObj())} aktif.`, "ok");
          await refreshModels();
          break;
        }
        if (st.state === "error" || st.state === "unloaded") {
          showToast(st.load_message || "Model yüklenemedi", "err", 5000);
          break;
        }
      }
    } catch (err) {
      showToast(`Model yüklenemedi: ${err.message}`, "err", 5000);
      pollStatus();
    } finally {
      dom.btnGpuLoad.disabled = false;
    }
  }

  async function unloadModelFromGpu() {
    try {
      const res = await apiJson("/api/model/unload", { method: "POST" });
      updateGpuCard(res);
      showToast("GPU VRAM temizlendi", "ok");
    } catch (err) {
      showToast(`VRAM boşaltılamadı: ${err.message}`, "err");
    }
  }

  /* =========================================================
     Sessions & File Uploads
     ========================================================= */
  async function loadSessions() {
    try {
      const data = await apiJson("/api/sessions");
      state.sessions = data.sessions || [];
      renderSessionList();
    } catch (_) {}
  }

  function getSessionDateGroup(s) {
    if (s.pinned) return "Sabitlenenler";
    if (!s.updated_at) return "Daha Eski";
    const dt = new Date(s.updated_at);
    if (Number.isNaN(dt.getTime())) return "Daha Eski";
    const now = new Date();
    const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const diffDays = Math.floor((startOfToday - new Date(dt.getFullYear(), dt.getMonth(), dt.getDate())) / 86400000);
    if (diffDays <= 0) return "Bugün";
    if (diffDays === 1) return "Dün";
    if (diffDays <= 7) return "Bu Hafta";
    return "Daha Eski";
  }

  let searchTimer = null;
  let globalSearchMap = null;

  function renderSessionList() {
    const q = (dom.sessionSearch.value || "").trim().toLowerCase();
    const list = state.sessions.filter((s) => {
      if (state.activeProjectId && s.project_id !== state.activeProjectId) return false;
      if (!q) return true;
      if ((s.title || "").toLowerCase().includes(q)) return true;
      if (globalSearchMap && globalSearchMap.has(s.id)) return true;
      return false;
    });
    if (!list.length) {
      dom.sessionList.innerHTML = `<div class="muted-empty">${q ? "Eşleşen sohbet veya mesaj yok" : "Henüz sohbet kaydı yok"}</div>`;
      return;
    }
    const groupOrder = ["Sabitlenenler", "Bugün", "Dün", "Bu Hafta", "Daha Eski"];
    const buckets = Object.fromEntries(groupOrder.map((g) => [g, []]));
    list.forEach((s) => {
      const g = getSessionDateGroup(s);
      (buckets[g] || buckets["Daha Eski"]).push(s);
    });

    const parts = [];
    let rowIdx = 0;
    for (const g of groupOrder) {
      if (!buckets[g].length) continue;
      parts.push(`<div class="session-group-label">${g}</div>`);
      for (const s of buckets[g]) {
        const isPin = Boolean(s.pinned);
        const snip = q && globalSearchMap ? globalSearchMap.get(s.id) : "";
        parts.push(`
          <div class="hrow ${s.id === state.activeSessionId ? "active" : ""} ${isPin ? "is-pinned" : ""}" style="--i:${Math.min(rowIdx++, 10)}" data-sid="${escHtml(s.id)}">
            ${isPin ? `<span class="hrow-pin-ico" aria-hidden="true">${SVG_ICONS.pin}</span>` : `<span class="hrow-dot"></span>`}
            <span class="hrow-copy-col">
              <span class="hrow-title" title="${escHtml(s.title || "Sohbet")}">${escHtml(s.title || "Sohbet")}</span>
              ${snip && snip !== "Başlık eşleşmesi" ? `<span class="hrow-snippet" title="${escHtml(snip)}">${escHtml(snip)}</span>` : ""}
            </span>
            <div class="hrow-actions">
              <button type="button" class="hact btn-sess-menu" data-sid="${escHtml(s.id)}" title="Seçenekler" aria-label="Sohbet Seçenekleri">${SVG_ICONS.dots}</button>
            </div>
          </div>`);
      }
    }
    dom.sessionList.innerHTML = parts.join("");
  }

  function handleSessionSearchInput() {
    const q = (dom.sessionSearch.value || "").trim();
    if (searchTimer) clearTimeout(searchTimer);
    if (q.length < 2) {
      globalSearchMap = null;
      renderSessionList();
      return;
    }
    renderSessionList();
    searchTimer = setTimeout(async () => {
      try {
        const res = await apiJson(`/api/sessions/search?q=${encodeURIComponent(q)}`);
        const map = new Map();
        (res.matches || []).forEach((m) => map.set(m.id, m.snippet || ""));
        globalSearchMap = map;
        renderSessionList();
      } catch (_) {}
    }, 180);
  }

  function openSessionCtxMenu(sid, rowEl, btnEl) {
    const menu = dom.sessionCtxMenu;
    if (!menu) return;
    if (!menu.hidden && state.ctxMenuSid === sid) {
      closeSessionCtxMenu();
      return;
    }
    const sess = state.sessions.find((s) => s.id === sid);
    state.ctxMenuSid = sid;
    state.ctxMenuRow = rowEl;
    if (dom.ctxPinLabel) dom.ctxPinLabel.textContent = sess?.pinned ? "Sabitlemeyi Kaldır" : "Sabitle";
    const r = btnEl.getBoundingClientRect();
    menu.hidden = false;
    const mw = menu.offsetWidth || 180;
    const mh = menu.offsetHeight || 120;
    const left = Math.min(window.innerWidth - mw - 12, Math.max(12, r.right - mw + 8));
    const top = Math.min(window.innerHeight - mh - 12, r.bottom + 6);
    menu.style.left = `${left}px`;
    menu.style.top = `${top}px`;
  }

  function closeSessionCtxMenu() {
    state.ctxMenuSid = null;
    state.ctxMenuRow = null;
    if (dom.sessionCtxMenu) dom.sessionCtxMenu.hidden = true;
  }

  async function togglePinSession(sid) {
    const sess = state.sessions.find((s) => s.id === sid);
    if (!sess) return;
    sess.pinned = !sess.pinned;
    renderSessionList();
    try {
      await apiJson("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: sess.id, title: sess.title || "Sohbet", messages: sess.messages || [], updated_at: sess.updated_at, pinned: sess.pinned }),
      });
    } catch (_) {}
  }

  function startRenameSession(sid) {
    const sess = state.sessions.find((s) => s.id === sid);
    if (!sess || !dom.renameSessionModal || !dom.renameSessionInput) return;
    state.pendingRenameSid = sid;
    dom.renameSessionInput.value = sess.title || "Sohbet";
    dom.renameSessionModal.hidden = false;
    requestAnimationFrame(() => {
      dom.renameSessionInput.focus();
      dom.renameSessionInput.select();
    });
  }

  function closeRenameModal() {
    state.pendingRenameSid = null;
    if (dom.renameSessionModal) dom.renameSessionModal.hidden = true;
  }

  async function commitRenameSession() {
    const sid = state.pendingRenameSid;
    if (!sid || !dom.renameSessionInput) return closeRenameModal();
    const sess = state.sessions.find((s) => s.id === sid);
    const val = dom.renameSessionInput.value.trim();
    closeRenameModal();
    if (!sess || !val || val === sess.title) return;
    sess.title = val.slice(0, 80);
    if (state.activeSessionId === sid) dom.pageBreadcrumb.textContent = sess.title;
    renderSessionList();
    try {
      await apiJson("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: sess.id,
          title: sess.title,
          messages: sess.messages || [],
          updated_at: sess.updated_at,
          pinned: Boolean(sess.pinned),
          project_id: sess.project_id || null,
        }),
      });
      showToast("Sohbet başlığı güncellendi", "ok", 1800);
    } catch (_) {
      showToast("Başlık kaydedilemedi", "err", 2200);
    }
  }

  function exportActiveChatMarkdown() {
    if (!state.messages.length) return showToast("Dışa aktarılacak mesaj yok", "warn", 2200);
    const title = dom.pageBreadcrumb.textContent || "YerelAI Sohbet";
    const md = [`# ${title}`, `_Dışa aktarım: ${new Date().toLocaleString("tr-TR")}_`, ""];
    state.messages.forEach((m) => {
      md.push(m.role === "user" ? "### Kullanıcı" : `### YerelAI (${m.model_id?.includes("e4b") ? "Gemma 4 E4B" : "Gemma 4 E2B"})`);
      md.push(m.content || "");
      md.push("");
    });
    const blob = new Blob([md.join("\n")], { type: "text/markdown;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `yerelai_sohbet_${Date.now()}.md`;
    a.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    showToast("Sohbet Markdown (.md) olarak indirildi", "ok", 2200);
  }

  function exportActiveChatPdf() {
    if (!state.messages.length) return showToast("Yazdırılacak mesaj yok", "warn", 2200);
    window.print();
  }

  function updateContextMeter(usedEst = null, limit = null) {
    if (!dom.ctxMeterPill) return;
    if (!state.messages.length) {
      dom.ctxMeterPill.hidden = true;
      if (dom.ctxWarnBanner) dom.ctxWarnBanner.hidden = true;
      return;
    }
    const effLimit = Number(limit || state.contextLength || 32768);
    let est = usedEst;
    if (est === null) {
      const totalChars = state.messages.reduce((acc, m) => acc + (m.content?.length || 0) + (m.thinking?.length || 0), 0);
      est = Math.round(totalChars / 3.4) + 180;
    }
    const pct = Math.min(100, Math.max(1, Math.round((est / Math.max(1024, effLimit)) * 100)));
    const dashTotal = 44;
    const dashOffset = (dashTotal * (1 - pct / 100)).toFixed(1);

    dom.ctxMeterPill.hidden = pct < 25;
    if (dom.ctxMeterPct) dom.ctxMeterPct.textContent = `%${pct}`;
    if (dom.ctxPillRingFg) dom.ctxPillRingFg.style.strokeDashoffset = dashOffset;
    dom.ctxMeterPill.classList.toggle("is-warn", pct >= 70 && pct < 88);
    dom.ctxMeterPill.classList.toggle("is-danger", pct >= 88);
    dom.ctxMeterPill.title = `Bağlam doluluğu: ~${est} / ${effLimit} token (Sıkıştırmak için tıklayın)`;

    if (dom.ctxWarnBanner) {
      const showWarn = pct >= 80 && state.messages.length >= 6;
      dom.ctxWarnBanner.hidden = !showWarn;
      dom.ctxWarnBanner.classList.toggle("is-danger", pct >= 90);
      if (dom.ctxWarnRingFg) dom.ctxWarnRingFg.style.strokeDashoffset = dashOffset;
      if (dom.ctxWarnText) {
        dom.ctxWarnText.textContent = pct >= 90
          ? `Bağlam %${pct} dolu — performans ve doğruluk için konuşmayı şimdi sıkıştırın.`
          : `Bağlam %${pct} doluluğa ulaştı — konuşmayı sıkıştırarak bellek açabilirsiniz.`;
      }
    }
  }

  async function runManualCompact() {
    if (state.isGenerating) {
      showToast("Yanıt üretimi bittikten sonra bağlamı sıkıştırabilirsiniz", "warn", 2400);
      return;
    }
    if (state.messages.length < 4) {
      showToast("Sıkıştırılacak kadar uzun sohbet geçmişi yok", "warn", 2200);
      return;
    }
    if (dom.btnCtxCompactNow) {
      dom.btnCtxCompactNow.disabled = true;
      dom.btnCtxCompactNow.textContent = "Sıkıştırılıyor...";
    }
    showToast("Sohbet bağlamı akıllıca özetleniyor...", "ok", 2200);
    try {
      const res = await apiJson("/api/sessions/compact", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          session_id: state.activeSessionId || "",
          messages: state.messages.map((m) => ({
            role: m.role,
            content: m.content || "",
            thinking: m.thinking || "",
            attachments: m.attachments || [],
          })),
          keep_recent: 4,
          context_limit: Number(state.contextLength || 32768),
        }),
      });
      if (!res.compacted) {
        showToast("Bağlam zaten yeterince kısa", "ok", 2200);
        return;
      }
      const nextMsgs = Array.isArray(res.messages) ? res.messages : state.messages;
      state.messages = nextMsgs;
      renderAllMessages();
      const divider = document.createElement("div");
      divider.className = "compact-divider-card";
      divider.innerHTML = `<span>✦</span><span><strong>Bağlam sıkıştırıldı:</strong> ${res.compacted_count || 0} eski mesaj özetlendi (~%${res.before_pct || 0} → ~%${res.after_pct || 0}).</span>`;
      dom.messagesList.insertAdjacentElement("afterbegin", divider);
      updateContextMeter(res.after_tokens, state.contextLength || 32768);
      await saveCurrentSession();
      showToast(`Bağlam %${res.before_pct} → %${res.after_pct} seviyesine indirildi`, "ok", 3000);
    } catch (err) {
      showToast(`Sıkıştırma hatası: ${err.message}`, "err", 3600);
    } finally {
      if (dom.btnCtxCompactNow) {
        dom.btnCtxCompactNow.disabled = false;
        dom.btnCtxCompactNow.textContent = "Şimdi Sıkıştır";
      }
    }
  }

  /* =========================================================
     Persistent Cross-Chat Memory (ChatGPT-Style)
     ========================================================= */
  async function loadMemories() {
    try {
      const data = await apiJson("/api/memories");
      state.memories = data.memories || [];
      renderMemories();
    } catch (_) {}
  }

  function renderMemories() {
    if (dom.memoryCountBadge) {
      dom.memoryCountBadge.textContent = String(state.memories.length);
      dom.memoryCountBadge.classList.toggle("ready", state.memories.length > 0);
    }
    if (!dom.memoryList) return;
    if (!state.memories.length) {
      dom.memoryList.innerHTML = `<div class="muted-empty">Henüz kalıcı hafıza kaydı yok</div>`;
      return;
    }
    dom.memoryList.innerHTML = state.memories
      .map(
        (m) => `
      <div class="mem-item">
        <span>${escHtml(m.text)}</span>
        <button type="button" class="mem-del-btn" data-mem-del="${escHtml(m.id)}" title="Hafızadan Sil" aria-label="Sil">${SVG_ICONS.xClose}</button>
      </div>`
      )
      .join("");
  }

  async function addMemoryFromInput() {
    const text = (dom.inpMemoryAdd?.value || "").trim();
    if (!text) return;
    try {
      const res = await apiJson("/api/memories", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text }),
      });
      state.memories = res.memories || [];
      if (dom.inpMemoryAdd) dom.inpMemoryAdd.value = "";
      renderMemories();
      showToast("Kalıcı hafızaya eklendi", "ok", 2200);
    } catch (err) {
      showToast(`Hafıza eklenemedi: ${err.message}`, "err", 3200);
    }
  }

  async function deleteMemory(memId) {
    try {
      const res = await apiJson(`/api/memories/${encodeURIComponent(memId)}`, { method: "DELETE" });
      state.memories = res.memories || [];
      renderMemories();
      showToast("Hafıza kaydı silindi", "ok", 1800);
    } catch (err) {
      showToast(`Silinemedi: ${err.message}`, "err", 2600);
    }
  }

  function startNewChat() {
    if (state.isGenerating) stopGeneration();
    state.activeSessionId = newId("chat");
    state.messages = [];
    state.pendingAttachments = [];
    dom.pageBreadcrumb.textContent = "Yeni Sohbet";
    renderPendingAttachments();
    renderSessionFiles();
    renderAllMessages();
    renderSessionList();
    dom.promptInput.focus();
  }

  async function openSession(sid) {
    if (state.isGenerating) stopGeneration();
    try {
      let data = state.sessions.find((s) => s.id === sid && Array.isArray(s.messages));
      if (!data) {
        data = await apiJson(`/api/sessions/${encodeURIComponent(sid)}`);
      }
      state.activeSessionId = data.id;
      state.messages = data.messages || [];
      dom.pageBreadcrumb.textContent = data.title || "Sohbet";
      renderAllMessages();
      renderSessionFiles();
      renderSessionList();
      dom.sidebar.classList.remove("open", "mobile-open");
      dom.drawerBackdrop?.classList.remove("open");
    } catch (err) {
      showToast(`Sohbet açılamadı: ${err.message}`, "err");
    }
  }

  function requestDeleteSession(sid, rowEl) {
    const sess = state.sessions.find((s) => s.id === sid);
    const title = sess?.title || "Bu sohbet";
    state.pendingDeleteSid = sid;
    state.pendingDeleteRow = rowEl || null;
    if (dom.confirmDeleteDesc) {
      dom.confirmDeleteDesc.textContent = `"${title}" kalıcı olarak silinecek ve geri alınamayacaktır.`;
    }
    if (dom.confirmDeleteModal) dom.confirmDeleteModal.hidden = false;
  }

  function closeDeleteConfirm() {
    state.pendingDeleteSid = null;
    state.pendingDeleteRow = null;
    if (dom.confirmDeleteModal) dom.confirmDeleteModal.hidden = true;
  }

  async function deleteSession(sid, rowEl) {
    if (rowEl) rowEl.classList.add("is-leaving");
    try {
      await apiJson(`/api/sessions/${encodeURIComponent(sid)}`, { method: "DELETE" });
      state.sessions = state.sessions.filter((s) => s.id !== sid);
      if (state.activeSessionId === sid) startNewChat();
      showToast("Sohbet silindi", "ok", 1800);
      setTimeout(renderSessionList, 190);
    } catch (err) {
      if (rowEl) rowEl.classList.remove("is-leaving");
      showToast(`Silinemedi: ${err.message}`, "err");
    }
  }

  /* =========================================================
     0-VRAM Local Document Library (RAG) & Expert Personas
     ========================================================= */
  async function loadLibrary() {
    try {
      const data = await apiJson("/api/library");
      state.libraryDocs = data.docs || [];
      renderLibraryDocs();
    } catch (_) {}
  }

  function renderLibraryDocs() {
    if (!dom.libraryDocsList) return;
    const activePid = state.activeProjectId || null;
    const visibleDocs = state.libraryDocs.filter((d) => {
      if (!activePid) return true;
      return !d.project_id || d.project_id === activePid;
    });
    if (!visibleDocs.length) {
      dom.libraryDocsList.innerHTML = `<div class="muted-empty">${activePid ? "Bu projede belge yok" : "Henüz belge indekslenmedi"}</div>`;
      return;
    }
    dom.libraryDocsList.innerHTML = visibleDocs
      .map((d) => {
        const prj = d.project_id ? state.projects.find((p) => p.id === d.project_id) : null;
        const prjBadge = prj ? `<span class="lib-prj-tag" title="Proje İzole RAG">${escHtml(prj.name)}</span>` : "";
        return `
      <div class="file-mini-item lib-doc-item">
        <span class="file-mini-ico" aria-hidden="true">${SVG_ICONS.file}</span>
        <div class="file-mini-copy">
          <strong title="${escHtml(d.name)}">${escHtml(d.name)}${prjBadge}</strong>
          <span class="mono">${escHtml(d.chunk_count)} parça · 0 VRAM</span>
        </div>
        <button type="button" class="lib-del-btn" data-lib-del="${escHtml(d.id)}" title="Kütüphaneden Kaldır" aria-label="Kaldır">${SVG_ICONS.xClose}</button>
      </div>`;
      })
      .join("");
  }

  async function uploadLibraryFile(file) {
    if (!file) return;
    showToast(`${file.name} indeksleniyor (CPU)...`, "ok", 2600);
    const fd = new FormData();
    fd.append("file", file);
    if (state.activeProjectId) fd.append("project_id", state.activeProjectId);
    try {
      const res = await apiJson("/api/library/upload", { method: "POST", body: fd });
      await loadLibrary();
      syncRagToggleUI(true);
      const scopeHint = state.activeProjectId ? " (Aktif Projeye Özel)" : "";
      showToast(`${res.doc?.name || file.name} kütüphaneye eklendi${scopeHint} (${res.doc?.chunk_count || 0} parça)`, "ok", 3200);
    } catch (err) {
      showToast(`Kütüphane hatası: ${err.message}`, "err", 4200);
    }
  }

  async function deleteLibraryDoc(docId) {
    try {
      await apiJson(`/api/library/${encodeURIComponent(docId)}`, { method: "DELETE" });
      await loadLibrary();
      showToast("Belge kütüphaneden kaldırıldı", "ok", 2000);
    } catch (err) {
      showToast(`Kaldırılamadı: ${err.message}`, "err");
    }
  }

  function syncRagToggleUI(enabled) {
    state.useLibrary = Boolean(enabled);
    dom.btnRagToggle?.classList.toggle("active", state.useLibrary);
    dom.btnRagToggle?.setAttribute("aria-pressed", String(state.useLibrary));
    if (dom.ctmRagState) dom.ctmRagState.textContent = state.useLibrary ? "Açık" : "Kapalı";
    if (dom.chipRagActive) dom.chipRagActive.hidden = !state.useLibrary;
  }

  function renderPersonasUI() {
    if (!dom.personaGrid) return;
    dom.personaGrid.innerHTML = PERSONAS.map(
      (p) => `<button type="button" class="persona-chip ${state.activePersonaId === p.id ? "active" : ""}" data-persona-id="${escHtml(p.id)}">${escHtml(p.name)}</button>`
    ).join("");
  }

  function applyPersona(pid) {
    const p = PERSONAS.find((x) => x.id === pid);
    if (!p) return;
    state.activePersonaId = p.id;
    localStorage.setItem("yerelai_persona_mode", p.id);
    dom.txtSystemPrompt.value = p.prompt;
    renderPersonasUI();
    saveConfigSilent();
    showToast(p.id === "auto" ? "Akıllı Otomatik Uzman seçimi aktif" : `Persona aktif: ${p.name}`, "ok", 2000);
  }

  async function saveCurrentSession() {
    if (state.isTemporaryChat) return;
    if (!state.messages.length) return;
    if (!state.activeSessionId) state.activeSessionId = newId("chat");
    const firstUser = state.messages.find((m) => m.role === "user");
    const title = ((firstUser?.content || "Yeni Sohbet").replace(/\s+/g, " ").trim()).slice(0, 44) || "Yeni Sohbet";
    dom.pageBreadcrumb.textContent = title;
    try {
      await apiJson("/api/sessions", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          id: state.activeSessionId,
          title,
          messages: state.messages,
          project_id: state.activeProjectId || null,
        }),
      });
      await loadSessions();
    } catch (_) {}
  }

  function renderSessionFiles() {
    const items = [];
    const seen = new Set();
    const pushItem = (key, item) => {
      if (!key || seen.has(key)) return;
      seen.add(key);
      items.push(item);
    };
    const collectAtts = (arr) => {
      (arr || []).forEach((a) => {
        const fname = a?.name || a?.filename;
        if (!a || !fname) return;
        pushItem(`att:${a.id || fname}`, {
          name: fname,
          sub: a.summary || a.kind || "Yüklenen dosya",
          url: a.url || a.preview_url || "",
          ico: "📎",
        });
      });
    };
    state.messages.forEach((m) => {
      collectAtts(m.attachments);
      const allCards = [...(m.file_cards || []), ...(m.rich_cards || [])];
      allCards.forEach((c) => {
        if (c && c.kind === "file_download" && c.filename) {
          pushItem(`file:${c.url || c.filename}`, {
            name: c.filename,
            sub: c.meta || (c.file_kind || "Çıktı").toUpperCase(),
            url: c.url || "",
            ico: "📄",
          });
        }
      });
    });
    collectAtts(state.pendingAttachments);

    if (dom.chatOutputsCount) {
      dom.chatOutputsCount.textContent = String(items.length);
      dom.chatOutputsCount.hidden = items.length === 0;
    }
    if (dom.chatOutputsList) {
      if (!items.length) {
        dom.chatOutputsList.innerHTML = `<div class="muted-empty">Bu sohbette henüz dosya veya çıktı yok</div>`;
      } else {
        dom.chatOutputsList.innerHTML = items.map((it) => {
          const tag = it.url ? "a" : "div";
          const hrefAttr = it.url ? `href="${escHtml(it.url)}" target="_blank" rel="noopener"` : "";
          return `<${tag} class="chat-output-row" ${hrefAttr}>
            <span class="chat-output-ico">${it.ico}</span>
            <span class="chat-output-meta">
              <span class="chat-output-name" title="${escHtml(it.name)}">${escHtml(it.name)}</span>
              <span class="chat-output-sub">${escHtml(it.sub)}</span>
            </span>
          </${tag}>`;
        }).join("");
      }
    }
  }

  async function uploadFiles(fileList) {
    const files = Array.from(fileList || []);
    if (!files.length) return;
    for (const file of files) {
      const fd = new FormData();
      fd.append("file", file);
      try {
        const att = await apiJson("/api/files/upload", { method: "POST", body: fd });
        state.pendingAttachments.push(att);
        showToast(`${att.name || att.filename || file.name} eklendi`, "ok", 2200);
      } catch (err) {
        showToast(`${file.name} yüklenemedi: ${err.message}`, "err");
      }
    }
    renderPendingAttachments();
    renderSessionFiles();
  }

  function renderPendingAttachments() {
    if (!state.pendingAttachments.length) {
      dom.pendingAttachments.hidden = true;
      dom.pendingAttachments.innerHTML = "";
      return;
    }
    dom.pendingAttachments.hidden = false;
    dom.pendingAttachments.innerHTML = state.pendingAttachments
      .map((a, i) => {
        const fname = a.name || a.filename || "Dosya";
        const imgUrl = a.preview_url || a.url;
        if (a.kind === "image" && imgUrl) {
          return `
          <div class="att-thumb-card" data-full-src="${escHtml(imgUrl)}" title="${escHtml(fname)} — Büyütmek için tıklayın">
            <img class="att-thumb-img" src="${escHtml(imgUrl)}" alt="${escHtml(fname)}" />
            <button type="button" class="att-thumb-remove" data-att-idx="${i}" aria-label="Görseli Kaldır">×</button>
          </div>`;
        }
        return `
        <span class="att-chip">
          <span>${escHtml(fname)}</span>
          <button type="button" data-att-idx="${i}" aria-label="Kaldır">×</button>
        </span>`;
      })
      .join("");
  }

  /* =========================================================
     Rich Weather Cards & Interactive Markdown Tables
     ========================================================= */
  function buildLocalSvgChart(card) {
    const labels = card.labels || [];
    const values = (card.values || []).map((v) => Number(v) || 0);
    if (!labels.length || !values.length) return "";
    const W = 640;
    const H = 220;
    const padL = 48;
    const padR = 18;
    const padT = 18;
    const padB = 42;
    const plotW = W - padL - padR;
    const plotH = H - padT - padB;
    const maxV = Math.max(...values, 1);
    const minV = Math.min(0, ...values);
    const span = Math.max(1e-6, maxV - minV);
    const isLine = card.chart_type === "line";

    const gridLines = [0, 0.25, 0.5, 0.75, 1]
      .map((f) => {
        const y = (padT + plotH * (1 - f)).toFixed(1);
        const val = (minV + span * f).toFixed(0);
        return `<line x1="${padL}" y1="${y}" x2="${W - padR}" y2="${y}" stroke="currentColor" stroke-opacity="0.12" stroke-dasharray="3 3"/><text x="${padL - 8}" y="${Number(y) + 3}" text-anchor="end" font-size="10" fill="currentColor" opacity="0.6">${val}</text>`;
      })
      .join("");

    let bodySvg = "";
    if (isLine) {
      const pts = values.map((v, i) => {
        const x = padL + (values.length === 1 ? plotW / 2 : (i / (values.length - 1)) * plotW);
        const y = padT + plotH * (1 - (v - minV) / span);
        return [x, y, v, labels[i] || ""];
      });
      const poly = pts.map((p) => `${p[0].toFixed(1)},${p[1].toFixed(1)}`).join(" ");
      bodySvg = `<polyline fill="none" stroke="#3b82f6" stroke-width="2.6" stroke-linejoin="round" stroke-linecap="round" points="${poly}"/>` +
        pts.map((p) => `<circle cx="${p[0].toFixed(1)}" cy="${p[1].toFixed(1)}" r="4" fill="#06b6d4" stroke="#fff" stroke-width="1.4"><title>${escHtml(p[3])}: ${p[2]}</title></circle><text x="${p[0].toFixed(1)}" y="${H - 12}" text-anchor="middle" font-size="9.5" fill="currentColor" opacity="0.72">${escHtml(String(p[3]).slice(0, 10))}</text>`).join("");
    } else {
      const step = plotW / values.length;
      const barW = Math.max(12, Math.min(44, step * 0.62));
      bodySvg = values
        .map((v, i) => {
          const h = Math.max(2, ((v - minV) / span) * plotH);
          const x = padL + i * step + (step - barW) / 2;
          const y = padT + plotH - h;
          const lbl = String(labels[i] || "").slice(0, 10);
          return `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${barW.toFixed(1)}" height="${h.toFixed(1)}" rx="5" fill="url(#yerelChartGrad)"><title>${escHtml(labels[i])}: ${v}</title></rect><text x="${(x + barW / 2).toFixed(1)}" y="${(y - 5).toFixed(1)}" text-anchor="middle" font-size="9.5" font-weight="600" fill="currentColor" opacity="0.85">${v}</text><text x="${(x + barW / 2).toFixed(1)}" y="${H - 12}" text-anchor="middle" font-size="9.5" fill="currentColor" opacity="0.72">${escHtml(lbl)}</text>`;
        })
        .join("");
    }

    return `<svg class="local-svg-chart" viewBox="0 0 ${W} ${H}" xmlns="http://www.w3.org/2000/svg"><defs><linearGradient id="yerelChartGrad" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="#06b6d4"/><stop offset="100%" stop-color="#3b82f6"/></linearGradient></defs>${gridLines}${bodySvg}</svg>`;
  }

  function hydrateChartsInNode(rootEl) {
    if (!rootEl) return;
    $$(".rich-chart-card[data-chart-json]", rootEl).forEach((cardEl) => {
      if (cardEl.dataset.chartRendered === "1") return;
      cardEl.dataset.chartRendered = "1";
      let spec;
      try {
        spec = JSON.parse(cardEl.dataset.chartJson);
      } catch (_) {
        return;
      }
      const stage = $(".rich-chart-stage", cardEl);
      const engineBadge = $(".chart-engine-badge", cardEl);
      if (!stage) return;

      if (typeof window.Chart === "function") {
        if (engineBadge) engineBadge.textContent = "Chart.js";
        stage.innerHTML = `<canvas></canvas>`;
        const canvas = $("canvas", stage);
        const isDark = dom.html.getAttribute("data-theme") === "dark";
        const tickColor = isDark ? "#94a3b8" : "#475569";
        const gridColor = isDark ? "rgba(148,163,184,0.12)" : "rgba(15,23,42,0.08)";
        new window.Chart(canvas.getContext("2d"), {
          type: spec.chart_type === "line" ? "line" : "bar",
          data: {
            labels: spec.labels || [],
            datasets: [
              {
                label: spec.dataset_label || "Değer",
                data: spec.values || [],
                backgroundColor: spec.chart_type === "line" ? "rgba(6, 182, 212, 0.2)" : "rgba(59, 130, 246, 0.78)",
                borderColor: "#06b6d4",
                borderWidth: 2,
                borderRadius: 6,
                tension: 0.32,
                fill: spec.chart_type === "line",
              },
            ],
          },
          options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: { legend: { labels: { color: tickColor } } },
            scales: {
              x: { ticks: { color: tickColor }, grid: { color: gridColor } },
              y: { ticks: { color: tickColor }, grid: { color: gridColor } },
            },
          },
        });
      } else {
        if (engineBadge) engineBadge.textContent = "Yerel SVG";
        stage.innerHTML = buildLocalSvgChart(spec);
      }
    });
  }

  function buildFileCardsHtml(cards, hasTables = false) {
    if (!cards || !cards.length) return "";
    return cards
      .filter((c) => c && c.kind === "file_download")
      .map((card) => {
        const kind = (card.file_kind || "xlsx").toLowerCase();
        const icoLabel = kind === "pdf" ? "PDF" : kind === "docx" ? "DOCX" : "XLSX";
        const toggleBtn =
          kind === "xlsx" && hasTables
            ? `<button type="button" class="cfc-btn btn-fdc-toggle-tables" data-expanded="0">${SVG_ICONS.table}<span>Tabloyu Gör</span></button>`
            : "";
        return `
        <div class="file-download-card">
          <span class="fdc-ico ${escHtml(kind)} mono" aria-hidden="true">${escHtml(icoLabel)}</span>
          <div class="fdc-copy">
            <span class="fdc-name" title="${escHtml(card.filename || "Dosya")}">${escHtml(card.filename || "Dosya")}</span>
            <span class="fdc-meta">${escHtml(card.meta || "İndirmeye hazır")}</span>
          </div>
          <div class="fdc-actions">
            ${toggleBtn}
            <a class="fdc-dl-btn" href="${escHtml(card.url || "#")}" download="${escHtml(card.filename || "dosya")}">
              ${SVG_ICONS.download}
              <span>İndir</span>
            </a>
          </div>
        </div>`;
      })
      .join("");
  }

  function buildRichCardsHtml(cards) {
    if (!cards || !cards.length) return "";
    return cards
      .filter((c) => c && c.kind !== "file_download")
      .map((card) => {
        if (card.kind === "weather") {
          const cur = card.current || {};
          const curIco = WEATHER_SVGS[cur.icon] || WEATHER_SVGS.partly_cloudy;
          const daysHtml = (card.daily || [])
            .map(
              (d) => `
            <div class="weather-day-tile">
              <span class="w-day-name">${escHtml(d.day_label)}</span>
              <span class="w-day-ico">${WEATHER_SVGS[d.icon] || WEATHER_SVGS.cloud}</span>
              <span class="w-day-temps mono">${escHtml(d.max_c)}° <span>/ ${escHtml(d.min_c)}°</span></span>
              <span class="w-day-rain mono">%${escHtml(d.precip_prob)} yağış</span>
            </div>`
            )
            .join("");
          return `
          <div class="rich-weather-card">
            <div class="weather-top">
              <div class="weather-loc">
                <strong>${escHtml(card.city)}${card.country ? `, ${escHtml(card.country)}` : ""}</strong>
                <span>Canlı Meteoroloji · ${escHtml(card.updated_at || "")}</span>
              </div>
              <div class="weather-now">
                <div>
                  <div class="weather-temp-big mono">${escHtml(cur.temp_c)}°C</div>
                  <div class="weather-cond-lbl">${escHtml(cur.condition || "")}</div>
                </div>
                <div class="weather-icon-box" aria-hidden="true">${curIco}</div>
              </div>
            </div>
            <div class="weather-pills">
              <span class="weather-stat-pill mono">Hissedilen: ${escHtml(cur.apparent_c)}°C</span>
              <span class="weather-stat-pill mono">Nem: %${escHtml(cur.humidity)}</span>
              <span class="weather-stat-pill mono">Rüzgar: ${escHtml(cur.wind_kmh)} km/sa</span>
              <span class="weather-stat-pill mono">Yağış: ${escHtml(cur.precipitation_mm)} mm</span>
            </div>
            <div class="weather-forecast-grid">${daysHtml}</div>
          </div>`;
        }

        if (card.kind === "finance") {
          const tiles = (card.items || [])
            .map(
              (it) => `
            <div class="finance-tile">
              <span class="finance-code mono">${escHtml(it.code)}</span>
              <span class="finance-val mono">${escHtml(it.rate)} ₺</span>
              <span class="finance-name">${escHtml(it.name)}</span>
            </div>`
            )
            .join("");
          return `
          <div class="rich-finance-card">
            <div class="finance-head">
              <strong>${escHtml(card.title || "Canlı Döviz Kurları")}</strong>
              <span class="mono">${escHtml(card.updated_at || "")}</span>
            </div>
            <div class="finance-grid">${tiles}</div>
          </div>`;
        }

        if (card.kind === "rag_sources") {
          const items = (card.hits || [])
            .map(
              (h) => `
            <div class="rag-hit-item">
              <div class="rag-hit-head">
                <span>${escHtml(h.source)}</span>
                <span class="mono">Sayfa ${escHtml(h.page)}</span>
              </div>
              <div class="rag-hit-excerpt">${escHtml(h.excerpt)}...</div>
            </div>`
            )
            .join("");
          return `
          <details class="rag-sources-card">
            <summary>${SVG_ICONS.file}<span>${escHtml(card.title || "Yerel Kütüphane Kaynakları")}</span></summary>
            <div class="rag-hit-list">${items}</div>
          </details>`;
        }

        if (card.kind === "chart") {
          const encoded = escHtml(JSON.stringify(card));
          return `
          <div class="rich-chart-card" data-chart-json="${encoded}">
            <div class="rich-chart-head">
              <div class="rich-chart-title">
                <strong>${escHtml(card.title || "Veri Grafiği")}</strong>
                <span>${escHtml(card.subtitle || "")}</span>
              </div>
              <div class="rich-chart-tools">
                <span class="md-table-badge chart-engine-badge mono">Grafik</span>
                <button type="button" class="btn-text-xs accent btn-chart-png">${SVG_ICONS.download}<span>PNG</span></button>
              </div>
            </div>
            <div class="rich-chart-stage"></div>
          </div>`;
        }

        if (card.kind === "file_download") {
          const kind = (card.file_kind || "xlsx").toLowerCase();
          const icoLabel = kind === "pdf" ? "PDF" : kind === "docx" ? "DOCX" : "XLSX";
          return `
          <div class="file-download-card">
            <span class="fdc-ico ${escHtml(kind)} mono" aria-hidden="true">${escHtml(icoLabel)}</span>
            <div class="fdc-copy">
              <span class="fdc-name" title="${escHtml(card.filename || "Dosya")}">${escHtml(card.filename || "Dosya")}</span>
              <span class="fdc-meta">${escHtml(card.meta || "İndirmeye hazır")}</span>
            </div>
            <a class="fdc-dl-btn" href="${escHtml(card.url || "#")}" download="${escHtml(card.filename || "dosya")}">
              ${SVG_ICONS.download}
              <span>İndir</span>
            </a>
          </div>`;
        }

        return "";
      })
      .join("");
  }

  function renderThinkingMd(raw) {
    if (!raw) return "";
    const lines = escHtml(raw).split("\n");
    const out = [];
    let inUl = false;
    const closeUl = () => {
      if (inUl) {
        out.push("</ul>");
        inUl = false;
      }
    };
    for (const ln of lines) {
      const t = ln.trim();
      const liM = t.match(/^(?:[-*•]|\d+\.)\s+(.+)$/);
      if (liM) {
        if (!inUl) {
          out.push("<ul>");
          inUl = true;
        }
        out.push(`<li>${formatInlineMd(liM[1])}</li>`);
      } else {
        closeUl();
        if (t) out.push(`<p>${formatInlineMd(t)}</p>`);
      }
    }
    closeUl();
    return out.join("");
  }

  function cleanLatexUnits(str) {
    if (!str) return "";
    return String(str)
      .replace(/\$([^$\n]{1,64})\$/g, (_, inner) => {
        if (/\\[a-zA-Z]+/.test(inner) || /\^\\circ/.test(inner) || /^[\d.,:\s\-–+%°]+$/.test(inner)) {
          return inner
            .replace(/\^\\circ\s*\\text\{([^}]*)\}/g, "°$1")
            .replace(/\^\\circ/g, "°")
            .replace(/\\text\{([^}]*)\}/g, "$1")
            .replace(/\\times/g, "×")
            .replace(/\\approx/g, "≈")
            .replace(/\\le\b/g, "≤")
            .replace(/\\ge\b/g, "≥")
            .replace(/\\%/g, "%")
            .replace(/\s+/g, " ")
            .trim();
        }
        return `$${inner}$`;
      })
      .replace(/\^\\circ\s*\\text\{([^}]*)\}/g, "°$1")
      .replace(/\^\\circ/g, "°");
  }

  function formatInlineMd(escapedStr) {
    return String(escapedStr ?? "")
      .replace(/`([^`\n]+)`/g, "<code>$1</code>")
      .replace(/\*\*([^*\n]+)\*\*/g, "<strong>$1</strong>")
      .replace(/\*([^*\n]+)\*/g, "<em>$1</em>")
      .replace(/\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)/g, `<a href="$2" target="_blank" rel="noopener noreferrer">$1</a>`);
  }

  function highlightCode(rawCode, lang = "") {
    const l = (lang || "").toLowerCase();
    const lines = rawCode.replace(/\n$/, "").split("\n");
    const isHtml = l === "html" || l === "htm" || l === "xml" || l === "svg";
    const isCss = l === "css" || l === "scss";
    const isJson = l === "json";

    const highlightLine = (rawLine) => {
      const escaped = escHtml(rawLine);
      if (isHtml) {
        return escaped.replace(
          /(&lt;!--[\s\S]*?--&gt;)|(&lt;\/?[a-zA-Z][\w:-]*)|(\s[a-zA-Z:-]+(?==))|(&quot;[^&]*?&quot;)/g,
          (m, com, tag, attr, str) => {
            if (com) return `<span class="tok-com">${com}</span>`;
            if (tag) return `<span class="tok-tag">${tag}</span>`;
            if (attr) return `<span class="tok-attr">${attr}</span>`;
            if (str) return `<span class="tok-str">${str}</span>`;
            return m;
          }
        );
      }
      if (isCss) {
        return escaped.replace(
          /(\/\*[\s\S]*?\*\/)|(&quot;[^&]*?&quot;|'[^']*')|([a-zA-Z-]+(?=\s*:))|(#[0-9a-fA-F]{3,8}\b|\b\d+(?:\.\d+)?(?:px|rem|em|%|vh|vw|s|ms|deg)?\b)/g,
          (m, com, str, prop, num) => {
            if (com) return `<span class="tok-com">${com}</span>`;
            if (str) return `<span class="tok-str">${str}</span>`;
            if (prop) return `<span class="tok-prop">${prop}</span>`;
            if (num) return `<span class="tok-num">${num}</span>`;
            return m;
          }
        );
      }
      if (isJson) {
        return escaped.replace(
          /(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;)(\s*:)?|\b(true|false|null)\b|\b(-?\d+(?:\.\d+)?)\b/g,
          (m, str, colon, kw, num) => {
            if (str && colon) return `<span class="tok-prop">${str}</span>${colon}`;
            if (str) return `<span class="tok-str">${str}</span>`;
            if (kw) return `<span class="tok-kw">${kw}</span>`;
            if (num) return `<span class="tok-num">${num}</span>`;
            return m;
          }
        );
      }
      const tokenRe =
        /(#[^\n]*|\/\/[^\n]*|\/\*[\s\S]*?\*\/)|(&quot;(?:\\.|[^&]|&(?!quot;))*?&quot;|'(?:\\.|[^'\\\n])*')|\b(def|class|return|import|from|as|if|elif|else|for|while|try|except|finally|with|async|await|yield|pass|break|continue|lambda|in|and|or|not|True|False|None|const|let|var|function|export|default|new|this|typeof|SELECT|FROM|WHERE|JOIN|LEFT|RIGHT|INNER|GROUP|ORDER|BY|LIMIT|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE)\b|\b(\d+(?:\.\d+)?)\b|\b([a-zA-Z_]\w*)(?=\()/g;
      return escaped.replace(tokenRe, (m, com, str, kw, num, fn) => {
        if (com) return `<span class="tok-com">${com}</span>`;
        if (str) return `<span class="tok-str">${str}</span>`;
        if (kw) return `<span class="tok-kw">${kw}</span>`;
        if (num) return `<span class="tok-num">${num}</span>`;
        if (fn) return `<span class="tok-fn">${fn}</span>`;
        return m;
      });
    };

    const htmlLines = lines
      .map(
        (ln, i) =>
          `<span class="code-line"><span class="code-ln mono">${i + 1}</span><span class="code-lc">${highlightLine(ln)}</span></span>`
      )
      .join("");
    return { htmlLines, lineCount: lines.length };
  }

  function guessCodeFilename(code, lang) {
    const l = (lang || "").toLowerCase();
    const meta = CODE_LANG_META[l] || { ext: l && /^[a-z0-9]{1,5}$/.test(l) ? l : "txt", fallback: "kod_dosyasi.txt" };
    const slugify = (s) =>
      String(s || "")
        .toLowerCase()
        .replace(/ğ/g, "g").replace(/ü/g, "u").replace(/ş/g, "s").replace(/ı/g, "i").replace(/ö/g, "o").replace(/ç/g, "c")
        .replace(/[^a-z0-9]+/g, "_")
        .replace(/^_+|_+$/g, "")
        .slice(0, 32);

    if (l === "html" || l === "htm") {
      const m = code.match(/<title[^>]*>([^<]{2,60})<\/title>/i);
      const sl = m ? slugify(m[1].split("|")[0].split("-")[0]) : "";
      return sl ? `${sl}.html` : meta.fallback;
    }
    if (l === "python" || l === "py") {
      const m = code.match(/^\s*(?:class|def)\s+([A-Za-z_][A-Za-z0-9_]{2,32})/m);
      const sl = m ? slugify(m[1]) : "";
      return sl && sl !== "main" ? `${sl}.py` : meta.fallback;
    }
    if (l === "javascript" || l === "js" || l === "typescript" || l === "ts") {
      const m = code.match(/\b(?:class|function)\s+([A-Za-z_][A-Za-z0-9_]{2,32})/);
      const sl = m ? slugify(m[1]) : "";
      return sl ? `${sl}.${meta.ext}` : meta.fallback;
    }
    return meta.fallback;
  }

  function hydrateRichContent(rootEl) {
    if (!rootEl) return;
    hydrateChartsInNode(rootEl);

    if (typeof window.katex !== "undefined" && window.katex.render) {
      $$(".katex-block[data-katex-expr]", rootEl).forEach((el) => {
        if (el.dataset.katexDone === "1") return;
        el.dataset.katexDone = "1";
        try {
          window.katex.render(el.dataset.katexExpr || "", el, { displayMode: true, throwOnError: false });
        } catch (_) {
          el.textContent = el.dataset.katexExpr || "";
        }
      });
    } else {
      $$(".katex-block[data-katex-expr]", rootEl).forEach((el) => {
        if (!el.textContent) el.textContent = el.dataset.katexExpr || "";
      });
    }

    if (typeof window.mermaid !== "undefined" && window.mermaid.render) {
      const isDark = dom.html.getAttribute("data-theme") === "dark";
      try {
        window.mermaid.initialize({ startOnLoad: false, theme: isDark ? "dark" : "default", securityLevel: "loose" });
      } catch (_) {}
      $$(".mermaid-stage[data-mermaid-src]", rootEl).forEach((el, i) => {
        if (el.dataset.mermaidDone === "1") return;
        el.dataset.mermaidDone = "1";
        const src = el.dataset.mermaidSrc || "";
        const uid = `mmd_${Date.now().toString(36)}_${i}_${Math.random().toString(36).slice(2, 6)}`;
        window.mermaid
          .render(uid, src)
          .then((res) => {
            if (res && res.svg) el.innerHTML = res.svg;
          })
          .catch(() => {
            el.innerHTML = `<pre class="mono" style="margin:0;font-size:12px;">${escHtml(src)}</pre>`;
          });
      });
    }
  }

  function renderMarkdown(raw, opts = {}) {
    if (!raw) return "";
    const isStreaming = Boolean(opts.isStreaming);
    let src = String(raw)
      .replace(/\r\n/g, "\n")
      .replace(/<mcp_call>[\s\S]*?<\/mcp_call>/g, "")
      .replace(/<mcp_call>[\s\S]*$/g, "");
    // Gracefully close an unclosed code fence while streaming or if truncated
    const fenceCount = (src.match(/^```/gm) || []).length;
    const hadUnclosedFence = fenceCount % 2 === 1;
    if (hadUnclosedFence) {
      src += "\n```";
    }
    const allFenceMatches = src.match(/```([\w-]*)\n?([\s\S]*?)```/g) || [];
    const totalFences = allFenceMatches.length;
    let fenceSeq = 0;

    const codeBlocks = [];
    let text = src.replace(/```([\w-]*)\n?([\s\S]*?)```/g, (_, lang, code) => {
      fenceSeq += 1;
      const isActivelyStreamingThisBlock = isStreaming && hadUnclosedFence && fenceSeq === totalFences;
      const idx = codeBlocks.length;
      const rawLang = (lang || "kod").trim().toLowerCase();
      const safeLang = escHtml(rawLang);

      // Zero-Flash Streaming Detection for sen_card / yerel_card / JSON card (NEVER flashes raw code block!)
      const isCardFence =
        rawLang === "sen_card" || rawLang === "sen-card" ||
        rawLang === "yerel_card" || rawLang === "yerel-card" ||
        ((rawLang === "json" || rawLang === "") && /"kind"\s*:\s*"(?:media_list|image_compare|image_spotlight|compare|compatibility|scorecard|rating|checklist|choice_card)"/.test(code));
      const isStreamingCardPrefix =
        isActivelyStreamingThisBlock &&
        (
          (rawLang.length > 0 && ("sen_card".startsWith(rawLang) || "yerel_card".startsWith(rawLang))) ||
          ((rawLang === "" || rawLang === "json") && /^\s*(?:\{|$)/.test(code))
        );

      if (isCardFence || isStreamingCardPrefix) {
        if (isActivelyStreamingThisBlock) {
          const kindM = code.match(/"kind"\s*:\s*"([a-z_]+)"/);
          const detectedKind = kindM ? kindM[1] : "";
          let skelBody = `<div class="yc-skel-line yc-shimmer" style="width:62%"></div><div class="yc-skel-line yc-shimmer" style="width:88%"></div><div class="yc-skel-line yc-shimmer" style="width:45%"></div>`;
          if (detectedKind === "media_list") {
            skelBody = [0, 1, 2].map(() => `<div class="yc-skel-media-row"><div class="yc-skel-thumb yc-shimmer"></div><div style="flex:1;display:flex;flex-direction:column;gap:8px;"><div class="yc-skel-line yc-shimmer" style="width:55%"></div><div class="yc-skel-line yc-shimmer" style="width:85%"></div><div class="yc-skel-line yc-shimmer" style="width:36%"></div></div></div>`).join("");
          } else if (detectedKind === "image_compare" || detectedKind === "compare") {
            skelBody = `<div class="yc-skel-grid-2"><div><div class="yc-skel-img-box yc-shimmer"></div><div class="yc-skel-line yc-shimmer" style="width:70%;margin-top:8px;"></div></div><div><div class="yc-skel-img-box yc-shimmer"></div><div class="yc-skel-line yc-shimmer" style="width:70%;margin-top:8px;"></div></div></div>`;
          } else if (detectedKind === "image_spotlight") {
            skelBody = `<div class="yc-skel-img-box yc-shimmer" style="aspect-ratio:16/9;"></div><div class="yc-skel-line yc-shimmer" style="width:48%"></div><div class="yc-skel-line yc-shimmer" style="width:80%"></div>`;
          }
          codeBlocks.push(
            `<div class="yc-skel-card" aria-busy="true">
              <div class="yc-skel-head"><span class="ws-live-dot"></span><span>Görsel kart hazırlanıyor...</span></div>
              ${skelBody}
            </div>`
          );
          return `\u0000CODEBLOCK_${idx}\u0000`;
        }
        try {
          const cardObj = JSON.parse(code.trim());
          const imgUrl = (q) => `/api/image-resolve?q=${encodeURIComponent(String(q || "").trim())}`;
          const imgTag = (src, alt) =>
            `<img src="${src}" alt="${escHtml(alt || "")}" loading="lazy" onload="this.parentElement.classList.remove('is-loading');this.parentElement.classList.add('is-loaded')" onerror="this.parentElement.classList.remove('is-loading');this.style.display='none'" />`;
          const fmtTen = (v) => {
            if (typeof v === "string" && v.trim()) return escHtml(v.trim());
            const num = Number(v);
            if (Number.isNaN(num)) return "9/10";
            const ten = num <= 10 ? num : num / 10;
            return `${String(ten.toFixed(1)).replace(/\.0$/, "").replace(".", ",")}/10`;
          };

          if (cardObj && cardObj.kind === "image_spotlight") {
            const q = cardObj.image_query || cardObj.title || "";
            const facts = Array.isArray(cardObj.facts) ? cardObj.facts.slice(0, 6) : [];
            const factsHtml = facts.length
              ? `<div class="yc-spotlight-facts">${facts.map((f) => `<span class="yc-spotlight-fact">${escHtml(f.label || "")}<strong>${escHtml(f.value || "")}</strong></span>`).join("")}</div>`
              : "";
            codeBlocks.push(
              `<div class="yc-spotlight-card">
                <div class="yc-spotlight-hero yc-img-wrap is-loading">
                  ${cardObj.badge ? `<span class="yc-spotlight-badge">${escHtml(cardObj.badge)}</span>` : ""}
                  ${imgTag(cardObj.image_url || imgUrl(q), cardObj.title)}
                </div>
                <div class="yc-spotlight-body">
                  <div class="yc-spotlight-title">${escHtml(cardObj.title || "")}</div>
                  ${cardObj.subtitle ? `<div class="yc-spotlight-sub">${escHtml(cardObj.subtitle)}</div>` : ""}
                  ${factsHtml}
                </div>
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }

          if (cardObj && cardObj.kind === "choice_card" && Array.isArray(cardObj.options)) {
            const multi = Boolean(cardObj.multi_select);
            const optsHtml = cardObj.options.slice(0, 12).map((opt) => {
              const lbl = typeof opt === "string" ? opt : (opt.label || opt.title || "");
              return `<button type="button" class="yc-choice-opt" data-choice-val="${escHtml(lbl)}">${escHtml(lbl)}</button>`;
            }).join("");
            codeBlocks.push(
              `<div class="yc-choice-card" data-multi="${multi ? "1" : "0"}">
                <div class="yc-choice-title">${escHtml(cardObj.title || "Seçiminizi yapın")}</div>
                ${cardObj.subtitle ? `<div class="yc-choice-sub">${escHtml(cardObj.subtitle)}</div>` : ""}
                <div class="yc-choice-options">${optsHtml}</div>
                <button type="button" class="yc-choice-submit" disabled>${escHtml(cardObj.submit_label || "Devam Et")}</button>
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }

          if (cardObj && cardObj.kind === "media_list" && Array.isArray(cardObj.items)) {
            const rowsHtml = cardObj.items.slice(0, 10).map((it, ii) => {
              const q = it.image_query || it.title || "";
              const yr = it.year ? ` <span class="yc-media-year">(${escHtml(String(it.year))})</span>` : "";
              const badge = it.badge ? `<span class="yc-green-pill">${escHtml(it.badge)}</span>` : "";
              const sc = it.score ? `<span class="yc-media-score">★ ${escHtml(String(it.score))}</span>` : "";
              return `<div class="yc-media-row">
                <div class="yc-media-thumb yc-img-wrap is-loading">${imgTag(it.image_url || imgUrl(q), it.title)}</div>
                <div class="yc-media-body">
                  <div class="yc-media-title">${ii + 1}. ${escHtml(it.title || "")}${yr}</div>
                  ${it.subtitle ? `<div class="yc-media-sub">${escHtml(it.subtitle)}</div>` : ""}
                  ${(badge || sc) ? `<div class="yc-media-meta">${badge}${sc}</div>` : ""}
                </div>
              </div>`;
            }).join("");
            codeBlocks.push(
              `<div class="yc-media-list">
                ${cardObj.title ? `<div class="yc-media-heading">${escHtml(cardObj.title)}</div>` : ""}
                ${rowsHtml}
                ${cardObj.summary ? `<div class="yc-media-summary">${escHtml(cardObj.summary)}</div>` : ""}
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }

          if (cardObj && (cardObj.kind === "image_compare" || (cardObj.kind === "compare" && (cardObj.left?.image_query || cardObj.right?.image_query))) && cardObj.left && cardObj.right) {
            const renderImgSide = (side) => {
              const pts = Array.isArray(side.points) ? side.points.slice(0, 6) : [];
              const q = side.image_query || side.name || "";
              return `<div class="yc-imgcmp-col">
                <div class="yc-imgcmp-photo yc-img-wrap is-loading">${imgTag(side.image_url || imgUrl(q), side.name)}</div>
                <div class="yc-imgcmp-name">${escHtml(side.name || "")} ${side.emoji ? escHtml(side.emoji) : ""}</div>
                ${side.subtitle ? `<div class="yc-imgcmp-sub">${escHtml(side.subtitle)}</div>` : ""}
                ${pts.length ? `<ul class="yc-side-pts">${pts.map((p) => `<li>${escHtml(p)}</li>`).join("")}</ul>` : ""}
              </div>`;
            };
            codeBlocks.push(
              `<div class="yc-imgcmp-wrap">
                ${cardObj.title ? `<div class="yc-media-heading">${escHtml(cardObj.title)}</div>` : ""}
                <div class="yc-imgcmp-grid">${renderImgSide(cardObj.left)}${renderImgSide(cardObj.right)}</div>
                ${cardObj.verdict ? `<div class="yc-verdict"><strong>✨ Özet:</strong> ${escHtml(cardObj.verdict)}</div>` : ""}
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }

          if (cardObj && (cardObj.kind === "compatibility" || cardObj.kind === "scorecard")) {
            const metrics = Array.isArray(cardObj.metrics) ? cardObj.metrics.slice(0, 10) : [];
            const profiles = Array.isArray(cardObj.profiles) ? cardObj.profiles.slice(0, 2) : [];
            const strengths = Array.isArray(cardObj.strengths) ? cardObj.strengths.slice(0, 6) : [];
            const challenges = Array.isArray(cardObj.challenges) ? cardObj.challenges.slice(0, 6) : [];
            const profilesHtml = profiles.length
              ? `<div class="yc-sc-profiles">${profiles.map((p) => `<div class="yc-sc-prof">
                  ${p.emoji ? `<div class="yc-sc-prof-em">${escHtml(p.emoji)}</div>` : ""}
                  <div class="yc-sc-prof-title">${escHtml(p.title || "")}</div>
                  ${p.subtitle ? `<div class="yc-sc-prof-sub">${escHtml(p.subtitle)}</div>` : ""}
                  ${p.traits ? `<div class="yc-sc-prof-traits">${escHtml(p.traits)}</div>` : ""}
                </div>`).join("")}</div>`
              : "";
            const rowsHtml = metrics.map((m) => {
              const lbl = `${m.emoji ? `${escHtml(m.emoji)} ` : ""}${escHtml(m.label || "")}`;
              const val = fmtTen(m.value ?? m.score);
              return `<div class="yc-sc-row"><span>${lbl}</span><strong class="mono">${val}</strong></div>`;
            }).join("");
            codeBlocks.push(
              `<div class="yc-card yc-scorecard">
                <div class="yc-sc-top">
                  <div class="yc-title">${escHtml(cardObj.title || "Uyum Analizi")}</div>
                  ${cardObj.badge ? `<span class="yc-green-pill">${escHtml(cardObj.badge)}</span>` : ""}
                </div>
                ${profilesHtml}
                <div class="yc-sc-hero">
                  <div class="yc-sc-big mono">${fmtTen(cardObj.score)}</div>
                  <div class="yc-sc-sub">${escHtml(cardObj.subtitle || "Genel uyum puanı")}</div>
                  ${cardObj.note ? `<div class="yc-sc-note">${escHtml(cardObj.note)}</div>` : ""}
                </div>
                ${rowsHtml ? `<div class="yc-sc-table"><div class="yc-sc-th"><span>Kategori</span><span>Puan</span></div>${rowsHtml}</div>` : ""}
                ${strengths.length ? `<div class="yc-sc-sec"><strong>Güçlü yönleri</strong><ul>${strengths.map((s) => `<li>${escHtml(s)}</li>`).join("")}</ul></div>` : ""}
                ${challenges.length ? `<div class="yc-sc-sec"><strong>Zorlanabilecekleri</strong><ul>${challenges.map((c) => `<li>${escHtml(c)}</li>`).join("")}</ul></div>` : ""}
                ${cardObj.summary ? `<div class="yc-summary"><strong>✨ Özet:</strong> ${escHtml(cardObj.summary)}</div>` : ""}
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }
          if (cardObj && cardObj.kind === "compare" && cardObj.left && cardObj.right) {
            const renderSide = (side, cls) => {
              const pts = Array.isArray(side.points) ? side.points.slice(0, 5) : [];
              const sc = side.score != null ? `<span class="yc-side-score mono">%${Math.max(0, Math.min(100, Math.round(Number(side.score) || 0)))}</span>` : "";
              return `<div class="yc-compare-col ${cls}">
                <div class="yc-side-head">
                  <span class="yc-side-name">${side.emoji ? `${escHtml(side.emoji)} ` : ""}${escHtml(side.name || "")}</span>
                  ${sc}
                </div>
                <ul class="yc-side-pts">${pts.map((p) => `<li>${escHtml(p)}</li>`).join("")}</ul>
              </div>`;
            };
            codeBlocks.push(
              `<div class="yc-card yc-compare">
                <div class="yc-compare-title">${escHtml(cardObj.title || "Karşılaştırma")}</div>
                <div class="yc-compare-grid">
                  ${renderSide(cardObj.left, "is-left")}
                  ${renderSide(cardObj.right, "is-right")}
                </div>
                ${cardObj.verdict ? `<div class="yc-verdict"><strong>✨ Özet:</strong> ${escHtml(cardObj.verdict)}</div>` : ""}
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }
          if (cardObj && cardObj.kind === "rating") {
            const tags = Array.isArray(cardObj.tags) ? cardObj.tags.slice(0, 4) : [];
            const pts = Array.isArray(cardObj.points) ? cardObj.points.slice(0, 4) : [];
            codeBlocks.push(
              `<div class="yc-card yc-rating">
                <div class="yc-compat-head">
                  <div class="yc-title-col">
                    <div class="yc-title">${cardObj.emoji ? `${escHtml(cardObj.emoji)} ` : ""}${escHtml(cardObj.title || "Öneri")}</div>
                    ${tags.length ? `<div class="yc-tag-row">${tags.map((t) => `<span class="yc-badge">${escHtml(t)}</span>`).join("")}</div>` : ""}
                  </div>
                  ${cardObj.score ? `<span class="yc-rating-pill mono">★ ${escHtml(String(cardObj.score))}</span>` : ""}
                </div>
                ${pts.length ? `<ul class="yc-rating-pts">${pts.map((p) => `<li>${escHtml(p)}</li>`).join("")}</ul>` : ""}
                ${cardObj.summary ? `<div class="yc-summary">${escHtml(cardObj.summary)}</div>` : ""}
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }
          if (cardObj && cardObj.kind === "checklist" && Array.isArray(cardObj.steps || cardObj.items)) {
            const steps = (cardObj.steps || cardObj.items).slice(0, 10);
            const stepsHtml = steps.map((st) => {
              const lbl = typeof st === "string" ? st : (st.label || st.text || "");
              const done = typeof st === "object" && Boolean(st.done);
              return `<label class="yc-cl-item ${done ? "is-done" : ""}"><input type="checkbox" ${done ? "checked" : ""} /><span>${escHtml(lbl)}</span></label>`;
            }).join("");
            const doneCount = steps.filter((s) => typeof s === "object" && s.done).length;
            const pct = steps.length ? Math.round((doneCount / steps.length) * 100) : 0;
            codeBlocks.push(
              `<div class="yc-checklist-card">
                <div class="yc-cl-head">
                  <div class="yc-cl-title">${escHtml(cardObj.title || "Kontrol Listesi")}</div>
                  <span class="yc-cl-pct mono">%${pct}</span>
                </div>
                <div class="yc-cl-bar"><div class="yc-cl-fill" style="width:${pct}%"></div></div>
                <div class="yc-cl-items">${stepsHtml}</div>
              </div>`
            );
            return `\u0000CODEBLOCK_${idx}\u0000`;
          }
        } catch (_) {
          // Fallback to normal code block if malformed JSON
        }
      }

      // Mermaid Diagram Card
      if (rawLang === "mermaid" && code.trim().length > 6 && !isActivelyStreamingThisBlock) {
        const cleanMmd = code.trim();
        codeBlocks.push(
          `<div class="mermaid-card">
            <div class="mermaid-head"><span class="mono">Mermaid Diyagramı</span></div>
            <div class="mermaid-stage" data-mermaid-src="${escHtml(cleanMmd)}"><pre class="mono" style="margin:0;font-size:12px;">${escHtml(cleanMmd)}</pre></div>
          </div>`
        );
        return `\u0000CODEBLOCK_${idx}\u0000`;
      }

      const { htmlLines, lineCount } = highlightCode(code, rawLang);
      const canPreview = rawLang === "html" || rawLang === "htm" || rawLang === "svg";
      const isPython = rawLang === "python" || rawLang === "py";
      const isScrollable = lineCount > 20;
      const expandBtn = isScrollable ? `<button type="button" class="code-expand-btn">Genişlet</button>` : "";
      const previewBtn = canPreview
        ? `<button type="button" class="code-preview-btn" data-lang="${safeLang}">Canlı Önizle</button>`
        : "";
      const livePill = isActivelyStreamingThisBlock ? `<span class="code-streaming-pill mono">Yazılıyor</span>` : "";

      // Claude-style single downloadable/openable SVG Code Card ONLY once the block is closed
      let fileCardHtml = "";
      let collapseRawBlock = false;
      if (!isActivelyStreamingThisBlock && lineCount >= 10 && code.trim().length >= 80) {
        collapseRawBlock = true;
        const langMeta = CODE_LANG_META[rawLang] || {
          ext: "txt",
          cls: "lang-code",
          label: `${rawLang.toUpperCase()} Kodu`,
          fallback: "kod.txt",
          svg: `<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="16 18 22 12 16 6"/><polyline points="8 6 2 12 8 18"/></svg>`,
        };
        const fname = guessCodeFilename(code, rawLang);
        const kb = Math.max(0.1, new Blob([code]).size / 1024).toFixed(1);
        const openBtnLabel = canPreview ? "Önizle" : "Kodu Aç";
        const openBtnIcon = canPreview ? SVG_ICONS.eye : SVG_ICONS.code;
        const pyRunEnabled = !state.plugins.length || state.plugins.some((p) => p.id === "python_sandbox" && p.enabled);
        const runBtnHtml = isPython && pyRunEnabled
          ? `<button type="button" class="cfc-btn run btn-cfc-run">${SVG_ICONS.play}<span>Çalıştır</span></button>`
          : "";
        fileCardHtml = `
        <div class="code-file-card" data-code-fname="${escHtml(fname)}" data-code-lang="${safeLang}">
          <span class="cfc-ico ${langMeta.cls}" aria-hidden="true">${langMeta.svg}</span>
          <div class="cfc-copy">
            <span class="cfc-name mono" title="${escHtml(fname)}">${escHtml(fname)}</span>
            <span class="cfc-meta">${escHtml(langMeta.label)} · ${lineCount} satır · ${kb} KB</span>
          </div>
          <div class="cfc-actions">
            ${runBtnHtml}
            <button type="button" class="cfc-btn btn-cfc-preview">${openBtnIcon}<span>${openBtnLabel}</span></button>
            <button type="button" class="cfc-btn primary btn-cfc-download">${SVG_ICONS.download}<span>İndir</span></button>
          </div>
        </div>`;
      }

      codeBlocks.push(
        `<div class="code-block-group ${collapseRawBlock ? "is-collapsed-to-card" : ""}">
          <div class="code-block-wrap ${isScrollable ? "is-scrollable" : ""}">
            <div class="code-block-head">
              <span class="code-head-left">
                <span class="code-lang-pill mono">${safeLang}</span>
                <span class="code-meta mono">${lineCount} satır</span>
                ${livePill}
              </span>
              <span class="code-head-actions">
                ${expandBtn}
                ${previewBtn}
                <button type="button" class="code-copy-btn">Kopyala</button>
              </span>
            </div>
            <pre><code>${htmlLines}</code></pre>
          </div>
          ${fileCardHtml}
        </div>`
      );
      return `\u0000CODEBLOCK_${idx}\u0000`;
    });

    // KaTeX Display Math Blocks ($$ ... $$)
    const mathBlocks = [];
    text = text.replace(/\$\$([\s\S]+?)\$\$/g, (_, expr) => {
      const idx = mathBlocks.length;
      const cleanExpr = expr.trim();
      mathBlocks.push(`<div class="katex-block" data-katex-expr="${escHtml(cleanExpr)}"></div>`);
      return `\u0000MATHBLOCK_${idx}\u0000`;
    });

    text = escHtml(cleanLatexUnits(text));

    // Interactive Framed Tables (with inline Markdown parsed inside every cell!)
    const tableBlocks = [];
    text = text.replace(/(^\|.+\|\n\|[-:| ]+\|\n(?:\|.+\|\n?)*)/gm, (tableBlock) => {
      const rows = tableBlock.trim().split("\n");
      if (rows.length < 2) return tableBlock;
      const parseCells = (r) =>
        r
          .trim()
          .replace(/^\|/, "")
          .replace(/\|$/, "")
          .split("|")
          .map((c) => formatInlineMd(c.trim()));
      const headers = parseCells(rows[0]);
      const bodyRows = rows.slice(2).map(parseCells);
      const th = headers.map((h) => `<th>${h}</th>`).join("");
      const formatTableCell = (cell) => {
        const plain = cell.replace(/<[^>]+>/g, "").trim();
        if (/^(Çok iyi|En iyi|Mükemmel|Harika|Önerilen|Güçlü)$/i.test(plain)) {
          return `<span class="tbl-badge-good">${cell}</span>`;
        }
        return cell;
      };
      const trs = bodyRows.map((r) => `<tr>${r.map((c) => `<td>${formatTableCell(c)}</td>`).join("")}</tr>`).join("");
      const idx = tableBlocks.length;
      tableBlocks.push(
        `<div class="md-table-card">
          <div class="md-table-toolbar">
            <span class="md-table-head-left">
              <span class="md-table-ico" aria-hidden="true">${SVG_ICONS.table}</span>
              <span>Veri Tablosu</span>
              <span class="md-table-badge mono">${bodyRows.length} satır · ${headers.length} sütun</span>
            </span>
            <div class="md-table-tools">
              <button type="button" class="btn-text-xs btn-tbl-copy">${SVG_ICONS.copy}<span>Kopyala</span></button>
              <button type="button" class="btn-text-xs btn-tbl-csv">${SVG_ICONS.download}<span>CSV</span></button>
              <button type="button" class="btn-text-xs accent btn-tbl-xlsx">${SVG_ICONS.download}<span>Excel (.xlsx)</span></button>
            </div>
          </div>
          <div class="md-table-wrap"><table class="md-table"><thead><tr>${th}</tr></thead><tbody>${trs}</tbody></table></div>
        </div>`
      );
      return `\u0000TABLEBLOCK_${idx}\u0000`;
    });

    text = text
      .replace(/^##### (.+)$/gm, (_, h) => `<h5>${formatInlineMd(h)}</h5>`)
      .replace(/^#### (.+)$/gm, (_, h) => `<h4>${formatInlineMd(h)}</h4>`)
      .replace(/^### (.+)$/gm, (_, h) => `<h3>${formatInlineMd(h)}</h3>`)
      .replace(/^## (.+)$/gm, (_, h) => `<h2>${formatInlineMd(h)}</h2>`)
      .replace(/^# (.+)$/gm, (_, h) => `<h1>${formatInlineMd(h)}</h1>`);

    const lines = text.split("\n");
    const out = [];
    let inUl = false;
    let inOl = false;
    let inTask = false;
    let inBq = false;
    const closeLists = () => {
      if (inUl) { out.push("</ul>"); inUl = false; }
      if (inOl) { out.push("</ol>"); inOl = false; }
      if (inTask) { out.push("</ul>"); inTask = false; }
    };
    const closeBq = () => {
      if (inBq) { out.push("</blockquote>"); inBq = false; }
    };

    for (const line of lines) {
      const trimmed = line.trim();
      if (/^(?:---+|\*\*\*+|___+)$/.test(trimmed)) {
        closeLists();
        closeBq();
        out.push(`<hr class="md-hr" />`);
        continue;
      }
      const bqM = line.match(/^\s*&gt;\s?(.*)$/);
      if (bqM) {
        closeLists();
        if (!inBq) { out.push("<blockquote>"); inBq = true; }
        if (bqM[1].trim()) out.push(`<p>${formatInlineMd(bqM[1])}</p>`);
        continue;
      } else {
        closeBq();
      }

      const taskM = line.match(/^\s*[-*•]\s+\[([ xX])\]\s+(.+)$/);
      const ulM = !taskM ? line.match(/^\s*[-*•]\s+(.+)$/) : null;
      const olM = !taskM ? line.match(/^\s*\d+\.\s+(.+)$/) : null;
      if (taskM) {
        if (inUl || inOl) closeLists();
        if (!inTask) { out.push(`<ul class="md-task-list">`); inTask = true; }
        const done = taskM[1].toLowerCase() === "x";
        out.push(`<li class="md-task-item ${done ? "done" : ""}"><span class="md-task-check" aria-hidden="true">${done ? "✓" : ""}</span><span>${formatInlineMd(taskM[2])}</span></li>`);
      } else if (ulM) {
        if (inOl || inTask) closeLists();
        if (!inUl) { out.push("<ul>"); inUl = true; }
        out.push(`<li>${formatInlineMd(ulM[1])}</li>`);
      } else if (olM) {
        if (inUl || inTask) closeLists();
        if (!inOl) { out.push("<ol>"); inOl = true; }
        out.push(`<li>${formatInlineMd(olM[1])}</li>`);
      } else {
        closeLists();
        if (!trimmed) out.push("");
        else if (
          trimmed.startsWith("<h") ||
          trimmed.startsWith("<div") ||
          trimmed.startsWith("\u0000CODEBLOCK_") ||
          trimmed.startsWith("\u0000TABLEBLOCK_") ||
          trimmed.startsWith("\u0000MATHBLOCK_")
        ) {
          out.push(trimmed);
        } else {
          out.push(`<p>${formatInlineMd(trimmed)}</p>`);
        }
      }
    }
    closeLists();
    closeBq();

    let html = out.join("\n");
    codeBlocks.forEach((blk, idx) => {
      html = html.replace(`\u0000CODEBLOCK_${idx}\u0000`, blk);
    });
    tableBlocks.forEach((tbl, idx) => {
      html = html.replace(`\u0000TABLEBLOCK_${idx}\u0000`, tbl);
    });
    mathBlocks.forEach((mb, idx) => {
      html = html.replace(`\u0000MATHBLOCK_${idx}\u0000`, mb);
    });
    return html;
  }

  function getDomainFromUrl(u) {
    try {
      return new URL(u).hostname.replace(/^www\./, "");
    } catch (_) {
      return "";
    }
  }

  function faviconUrlFor(urlOrDomain) {
    const domName = urlOrDomain.includes("://") ? getDomainFromUrl(urlOrDomain) : String(urlOrDomain || "").replace(/^www\./, "");
    if (!domName) return "";
    return `https://www.google.com/s2/favicons?domain=${encodeURIComponent(domName)}&sz=32`;
  }

  function openSourcesModal(sources) {
    if (!dom.sourcesModal || !dom.sourcesModalBody) return;
    const list = Array.isArray(sources) ? sources : [];
    if (dom.sourcesModalCount) dom.sourcesModalCount.textContent = `${list.length} site`;
    dom.sourcesModalBody.innerHTML = list.map((s) => {
      const host = s.domain || getDomainFromUrl(s.url || "");
      const fav = faviconUrlFor(s.url || host);
      return `<a class="source-card-item" href="${escHtml(s.url || "#")}" target="_blank" rel="noopener noreferrer">
        ${fav ? `<img class="source-card-fav" src="${fav}" alt="" loading="lazy" onerror="this.style.display='none'" />` : ""}
        <div class="source-card-info">
          <div class="source-card-title">${escHtml(s.title || host || "Kaynak")}</div>
          <div class="source-card-host mono">${escHtml(host)}</div>
          ${s.snippet ? `<div class="source-card-snip">${escHtml(s.snippet)}</div>` : ""}
        </div>
      </a>`;
    }).join("") || `<div class="muted-empty">Kaynak bulunamadı</div>`;
    dom.sourcesModal.hidden = false;
  }

  function buildWebSearchHtml(ws) {
    if (!ws || ws.skipped) return "";
    if (ws.online === false) {
      return `<span class="web-sources-pill is-offline" title="${escHtml(ws.warning || "Çevrimdışı")}">${SVG_ICONS.warn}<span>Çevrimdışı</span></span>`;
    }
    if (ws.sources && ws.sources.length) {
      const favs = ws.sources.slice(0, 3).map((s) => {
        const f = faviconUrlFor(s.url || s.domain || "");
        return f ? `<img src="${f}" alt="" loading="lazy" onerror="this.style.display='none'" />` : "";
      }).join("");
      return `<button type="button" class="web-sources-btn btn-open-sources" title="Web kaynaklarını görüntüle">
        <span class="ws-fav-stack" aria-hidden="true">${favs}</span>
        <span>Kaynaklar (${ws.sources.length})</span>
      </button>`;
    }
    return "";
  }

  function buildAttachmentsHtml(atts) {
    if (!atts || !atts.length) return "";
    return `<div class="msg-att-row">${atts
      .map((a) => {
        const fname = a.name || a.filename || "Dosya";
        const url = a.preview_url || a.url;
        if (a.kind === "image" && url) {
          return `<img class="att-img-thumb" src="${escHtml(url)}" alt="${escHtml(fname)}" data-full-src="${escHtml(url)}" />`;
        }
        return `<span class="att-doc-badge">${SVG_ICONS.file}<span>${escHtml(fname)}</span></span>`;
      })
      .join("")}</div>`;
  }

  function buildMcpApprovalHtml(calls, msgIdx) {
    if (!Array.isArray(calls) || !calls.length) return "";
    return calls
      .map((c, cIdx) => {
        const st = c.status || "pending";
        const stLabel = st === "approved" ? "✓ Çalıştırıldı" : st === "error" ? "✕ Hata" : st === "rejected" ? "Reddedildi" : "Onay Bekliyor";
        const stCls = st === "approved" ? "ok" : st === "error" ? "err" : st === "rejected" ? "rejected" : "";
        const argsJson = JSON.stringify(c.arguments || {}, null, 2);
        const actionsHtml =
          st === "pending"
            ? `<div class="mcp-approval-actions">
                <button type="button" class="btn-solid btn-sm" data-mcp-approve="${msgIdx}:${cIdx}">İzin Ver ve Çalıştır</button>
                <button type="button" class="btn-ghost btn-sm" data-mcp-reject="${msgIdx}:${cIdx}">Reddet</button>
              </div>`
            : "";
        const resHtml = c.result_text ? `<pre class="mcp-approval-result mono">${escHtml(c.result_text.slice(0, 2400))}</pre>` : "";
        return `
        <div class="mcp-approval-card">
          <div class="mcp-approval-head">
            <div class="mcp-approval-title">
              <span class="lang-chip mono">MCP</span>
              <span>${escHtml(c.server_name || c.server_id)}</span>
              <span class="mcp-tool-chip">${escHtml(c.tool)}</span>
            </div>
            <span class="mcp-approval-status ${stCls}">${stLabel}</span>
          </div>
          <div class="mcp-approval-body">
            <pre class="mcp-approval-args mono">${escHtml(argsJson)}</pre>
            ${actionsHtml}
            ${resHtml}
          </div>
        </div>`;
      })
      .join("");
  }

  function createMessageNode(msg, idx, isLive = false) {
    const row = document.createElement("div");
    row.className = `msg-row ${msg.role}`;
    row.dataset.msgIdx = String(idx);

    if (msg.role === "user") {
      row.innerHTML = `${buildAttachmentsHtml(msg.attachments)}<div class="user-msg-wrap"><button type="button" class="hact btn-msg-edit" data-tip="Düzenle ve Yeniden Gönder" aria-label="Düzenle">${SVG_ICONS.edit}</button><div class="user-bubble">${escHtml(msg.content || "")}</div></div>`;
      return row;
    }

    const isE4b = (msg.model_id || state.selectedModelId).includes("e4b");
    const modelLabel = isE4b ? "Gemma 4 E4B" : "Gemma 4 E2B";
    const statsText = msg.stats
      ? `${msg.stats.tps} tok/sn · ${msg.stats.elapsed_sec}s · ${msg.stats.tokens} token`
      : isLive
        ? "Üretiliyor..."
        : "";

    const thinkSec = msg.thinking_sec ? `${msg.thinking_sec} sn` : "";
    const thinkDoneLabel = thinkSec ? `${thinkSec} düşündü` : "Düşünme sürecini gör";
    const wsLiveDoneHtml =
      !isLive && msg.web_search?.sources?.length
        ? `<div class="web-search-live-pill"><span class="ws-live-dot"></span><span>${msg.web_search.sources.length} web sitesi araştırıldı</span></div>`
        : "";

    row.innerHTML = `
      <div class="assistant-shell">
        <div class="assistant-avatar-col">
          <span class="prism-mark sm ${isE4b ? "e4b" : ""} ${isLive ? "is-live" : ""}" aria-hidden="true">${isE4b ? PRISM_E4B_SVG : PRISM_E2B_SVG}</span>
        </div>
        <div class="assistant-body-col">
          <div class="assistant-head">
            <div class="assistant-name-row">
              <span class="assistant-name">SEN.AI</span>
              ${msg.auto_persona ? `<span class="assistant-meta-pill persona-auto-badge">Uzman: ${escHtml(msg.auto_persona)}</span>` : ""}
            </div>
          </div>

          <div class="assistant-surface ${isLive ? "is-streaming" : ""}">
            <div class="web-search-live-slot">${wsLiveDoneHtml}</div>
            <div class="rich-cards-slot">${buildRichCardsHtml(msg.rich_cards)}</div>
            <details class="thinking-board ${isLive ? "is-live" : ""}" ${msg.thinking ? "" : "hidden"}>
              <summary>
                <span aria-hidden="true">✦</span>
                <span class="thinking-title">${isLive ? "Düşünüyor..." : thinkDoneLabel}</span>
                <span class="thinking-timer mono"></span>
                <span class="think-chev" aria-hidden="true">▸</span>
              </summary>
              <div class="thinking-content">${renderThinkingMd(msg.thinking || "")}</div>
            </details>
            <div class="msg-markdown ${isLive ? "is-streaming" : ""}">${renderMarkdown(msg.content || "")}</div>
            <div class="mcp-calls-slot">${buildMcpApprovalHtml(msg.mcp_calls, idx)}</div>
            <div class="file-cards-slot"></div>
          </div>

          <div class="msg-action-bar">
            <div class="msg-actions-left">
              ${
                Array.isArray(msg.variants) && msg.variants.length > 1
                  ? `<div class="msg-branch-nav">
                      <button type="button" class="msg-branch-btn" data-branch-dir="-1" ${(msg.variantIdx ?? msg.variants.length - 1) <= 0 ? "disabled" : ""} aria-label="Önceki yanıt">${SVG_ICONS.chevLeft}</button>
                      <span class="msg-branch-count mono">${(msg.variantIdx ?? msg.variants.length - 1) + 1} / ${msg.variants.length}</span>
                      <button type="button" class="msg-branch-btn" data-branch-dir="1" ${(msg.variantIdx ?? msg.variants.length - 1) >= msg.variants.length - 1 ? "disabled" : ""} aria-label="Sonraki yanıt">${SVG_ICONS.chevRight}</button>
                    </div>`
                  : ""
              }
              <button type="button" class="msg-act-btn btn-msg-copy" data-tip="Kopyala" aria-label="Kopyala">${SVG_ICONS.copy}</button>
              <button type="button" class="msg-act-btn btn-msg-like ${msg.rating === "like" ? "active" : ""}" data-tip="Beğen" aria-label="Beğen">${SVG_ICONS.thumbUp}</button>
              <button type="button" class="msg-act-btn btn-msg-dislike ${msg.rating === "dislike" ? "active-down" : ""}" data-tip="Beğenme" aria-label="Beğenme">${SVG_ICONS.thumbDown}</button>
              <button type="button" class="msg-act-btn btn-msg-speak" data-tip="Seslendir" aria-label="Seslendir">${SVG_ICONS.speak}</button>
              <button type="button" class="msg-act-btn btn-msg-share" data-tip="Paylaş" aria-label="Paylaş">${SVG_ICONS.share}</button>
              <button type="button" class="msg-act-btn btn-msg-more" data-tip="Diğer seçenekler" aria-label="Diğer seçenekler">${SVG_ICONS.dots}</button>
              <div class="web-sources-slot">${buildWebSearchHtml(msg.web_search)}</div>
            </div>
            <div class="msg-actions-right">
              <span class="msg-stats-subtle mono">${escHtml(statsText)}</span>
            </div>
          </div>
        </div>
      </div>`;

    // Populate bottom file-cards slot (separating file downloads from top weather/finance/RAG cards)
    const allFileCards = [
      ...(Array.isArray(msg.file_cards) ? msg.file_cards : []),
      ...(Array.isArray(msg.rich_cards) ? msg.rich_cards.filter((c) => c && c.kind === "file_download") : []),
    ];
    if (allFileCards.length) {
      const fileSlot = $(".file-cards-slot", row);
      const tableCards = $$(".md-table-card", row);
      const hasXlsx = allFileCards.some((c) => (c.file_kind || "").toLowerCase() === "xlsx");
      if (hasXlsx && !isLive && tableCards.length) {
        collapseTableCardsInNode(row, true);
      }
      if (fileSlot) {
        fileSlot.innerHTML = buildFileCardsHtml(allFileCards, tableCards.length > 0);
      }
    }
    return row;
  }

  function collapseTableCardsInNode(rootEl, collapsed) {
    if (!rootEl) return;
    $$(".md-table-card", rootEl).forEach((tc) => {
      tc.classList.toggle("is-collapsed-to-xlsx", collapsed);
      // Also collapse/restore the immediate preceding heading (H1-H5) and adjacent <hr> so no orphan title floats
      const prev = tc.previousElementSibling;
      if (prev && /^H[1-5]$/.test(prev.tagName)) {
        prev.classList.toggle("is-collapsed-to-xlsx", collapsed);
        const beforeH = prev.previousElementSibling;
        if (beforeH && beforeH.tagName === "HR") {
          beforeH.classList.toggle("is-collapsed-to-xlsx", collapsed);
        }
      }
    });
  }

  async function forkChatAt(msgIdx) {
    if (state.isGenerating) return;
    const sliced = state.messages.slice(0, msgIdx + 1).map((m) => JSON.parse(JSON.stringify(m)));
    if (!sliced.length) return;
    const baseTitle = (dom.pageBreadcrumb.textContent || "Sohbet").replace(/\s*\(Dal\)$/, "");
    const nextTitle = `${baseTitle} (Dal)`.slice(0, 76);
    state.activeSessionId = newId("chat");
    state.messages = sliced;
    dom.pageBreadcrumb.textContent = nextTitle;
    renderAllMessages();
    await saveCurrentSession();
    showToast("Sohbet bu noktadan dallandırıldı", "ok", 2600);
  }

  function renderAllMessages() {
    const hasMsgs = state.messages.length > 0;
    dom.welcomeHero.hidden = hasMsgs || state.isTemporaryChat;
    if (dom.tempChatHero) dom.tempChatHero.hidden = hasMsgs || !state.isTemporaryChat;
    if (dom.starterPillsRow) dom.starterPillsRow.hidden = hasMsgs || state.isTemporaryChat;
    dom.dropZone?.classList.toggle("is-empty-chat", !hasMsgs);
    if (dom.chatExportActions) dom.chatExportActions.hidden = !hasMsgs;
    dom.messagesList.innerHTML = "";
    state.messages.forEach((m, idx) => dom.messagesList.appendChild(createMessageNode(m, idx, false)));
    hydrateRichContent(dom.messagesList);
    updateContextMeter();
    renderSessionFiles();
    scrollToBottom(false);
  }

  function openInlineMessageEdit(rowEl, idx) {
    if (state.isGenerating) return;
    const msg = state.messages[idx];
    if (!msg || msg.role !== "user") return;
    const wrap = $(".user-msg-wrap", rowEl);
    if (!wrap) return;
    const box = document.createElement("div");
    box.className = "inline-edit-box";
    box.innerHTML = `
      <textarea rows="3">${escHtml(msg.content || "")}</textarea>
      <div class="inline-edit-actions">
        <button type="button" class="btn-ghost btn-sm btn-edit-cancel">İptal</button>
        <button type="button" class="btn-solid btn-sm btn-edit-submit">Kaydet ve Gönder</button>
      </div>`;
    wrap.replaceWith(box);
    const ta = $("textarea", box);
    ta.focus();
    ta.setSelectionRange(ta.value.length, ta.value.length);

    $(".btn-edit-cancel", box).addEventListener("click", () => renderAllMessages());
    const submit = () => {
      const nextText = ta.value.trim();
      if (!nextText) return;
      const keptAtts = msg.attachments || [];
      state.messages = state.messages.slice(0, idx);
      state.pendingAttachments = keptAtts;
      renderAllMessages();
      sendMessage(nextText);
    };
    $(".btn-edit-submit", box).addEventListener("click", submit);
    ta.addEventListener("keydown", (e) => {
      if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); submit(); }
      else if (e.key === "Escape") { e.preventDefault(); renderAllMessages(); }
    });
  }

  function snapshotAssistantVariant(m) {
    return {
      content: m.content || "",
      thinking: m.thinking || "",
      rich_cards: Array.isArray(m.rich_cards) ? [...m.rich_cards] : [],
      web_search: m.web_search || null,
      stats: m.stats || null,
      model_id: m.model_id || state.selectedModelId,
      thinking_effort: m.thinking_effort || state.thinkingEffort,
    };
  }

  function switchMessageVariant(msgIdx, dir) {
    const msg = state.messages[msgIdx];
    if (!msg || !Array.isArray(msg.variants) || msg.variants.length < 2) return;
    const cur = msg.variantIdx ?? msg.variants.length - 1;
    const next = Math.max(0, Math.min(msg.variants.length - 1, cur + dir));
    if (next === cur) return;
    const v = msg.variants[next];
    msg.variantIdx = next;
    msg.content = v.content || "";
    msg.thinking = v.thinking || "";
    msg.rich_cards = Array.isArray(v.rich_cards) ? [...v.rich_cards] : [];
    msg.web_search = v.web_search || null;
    msg.stats = v.stats || null;
    msg.model_id = v.model_id || msg.model_id;
    msg.thinking_effort = v.thinking_effort || msg.thinking_effort;
    renderAllMessages();
    saveCurrentSession();
  }

  function regenerateAssistantAt(idx) {
    if (state.isGenerating) return;
    let userIdx = -1;
    for (let i = idx - 1; i >= 0; i--) {
      if (state.messages[i]?.role === "user") { userIdx = i; break; }
    }
    if (userIdx === -1) return;
    const curAssistant = state.messages[idx];
    let priorVariants = [];
    if (curAssistant && curAssistant.role === "assistant") {
      priorVariants =
        Array.isArray(curAssistant.variants) && curAssistant.variants.length
          ? [...curAssistant.variants]
          : [snapshotAssistantVariant(curAssistant)];
    }
    const prevUser = state.messages[userIdx];
    const promptText = prevUser.content || "";
    const keptAtts = prevUser.attachments || [];
    state.messages = state.messages.slice(0, userIdx);
    state.pendingAttachments = keptAtts;
    renderAllMessages();
    sendMessage(promptText, { priorVariants });
  }

  function scrollToBottom(smooth = false) {
    dom.chatScroll.scrollTo({ top: dom.chatScroll.scrollHeight, behavior: smooth ? "smooth" : "auto" });
  }

  function isNearBottom() {
    const el = dom.chatScroll;
    return el.scrollHeight - el.scrollTop - el.clientHeight < 140;
  }

  /* =========================================================
     Chat Streaming (SSE + rAF + Rich Weather Cards)
     ========================================================= */
  async function sendMessage(overrideText = null, opts = {}) {
    if (state.isGenerating) return;
    closeSlashMenu();
    const text = (overrideText !== null ? overrideText : dom.promptInput.value).trim();
    const atts = [...state.pendingAttachments];
    if (!text && !atts.length) return;

    if (!state.activeSessionId) state.activeSessionId = newId("chat");

    const userMsg = {
      role: "user",
      content: text || (atts.some((a) => a.kind === "audio") ? "Bu ses kaydını dinleyip yanıtla." : "Eklediğim dosyaları analiz et."),
      attachments: atts,
    };
    state.messages.push(userMsg);
    state.pendingAttachments = [];
    dom.promptInput.value = "";
    autoResizeTextarea();
    renderPendingAttachments();
    renderSessionFiles();

    dom.welcomeHero.hidden = true;
    if (dom.tempChatHero) dom.tempChatHero.hidden = true;
    if (dom.starterPillsRow) dom.starterPillsRow.hidden = true;
    dom.dropZone?.classList.remove("is-empty-chat");
    if (dom.chatExportActions) dom.chatExportActions.hidden = false;
    dom.messagesList.appendChild(createMessageNode(userMsg, state.messages.length - 1, false));

    const priorVariants = Array.isArray(opts.priorVariants) && opts.priorVariants.length ? [...opts.priorVariants] : null;
    const assistantMsg = {
      role: "assistant",
      content: "",
      thinking: "",
      thinking_sec: null,
      created_at: new Date().toISOString(),
      rich_cards: [],
      web_search: null,
      stats: null,
      model_id: state.selectedModelId,
      thinking_effort: state.thinkingEffort,
      variants: priorVariants ? [...priorVariants] : undefined,
      variantIdx: priorVariants ? priorVariants.length : undefined,
    };
    state.messages.push(assistantMsg);
    const msgNode = createMessageNode(assistantMsg, state.messages.length - 1, true);
    dom.messagesList.appendChild(msgNode);
    scrollToBottom(true);

    const orbEl = $(".prism-mark", msgNode);
    const surfaceEl = $(".assistant-surface", msgNode);
    const wsLiveSlotEl = $(".web-search-live-slot", msgNode);
    const richSlotEl = $(".rich-cards-slot", msgNode);
    const webSlotEl = $(".web-sources-slot", msgNode);
    const thinkBoard = $(".thinking-board", msgNode);
    const thinkTitle = $(".thinking-title", msgNode);
    const thinkTimerEl = $(".thinking-timer", msgNode);
    const thinkContentEl = $(".thinking-content", msgNode);
    const mdEl = $(".msg-markdown", msgNode);
    const mcpSlotEl = $(".mcp-calls-slot", msgNode);
    const statsEl = $(".msg-stats-subtle", msgNode);
    const assistantMsgIdx = state.messages.length - 1;
    let wsLiveCount = 0;

    state.isGenerating = true;
    state.abortController = new AbortController();
    dom.composerCard?.classList.add("is-generating");
    dom.btnSend.hidden = true;
    dom.btnStop.hidden = false;

    const genStart = performance.now();
    let rafScheduled = false;
    let dirtyThink = false;
    let dirtyText = false;
    let userPinnedUp = false;
    let lastScrollTop = dom.chatScroll.scrollTop;

    const onStreamUserScroll = () => {
      const cur = dom.chatScroll.scrollTop;
      const distBottom = dom.chatScroll.scrollHeight - cur - dom.chatScroll.clientHeight;
      if (cur < lastScrollTop - 6 && distBottom > 36) {
        userPinnedUp = true;
      } else if (distBottom <= 28) {
        userPinnedUp = false;
      }
      lastScrollTop = cur;
    };
    const onStreamTouchStart = () => {
      const distBottom = dom.chatScroll.scrollHeight - dom.chatScroll.scrollTop - dom.chatScroll.clientHeight;
      if (distBottom > 42) userPinnedUp = true;
    };
    dom.chatScroll.addEventListener("scroll", onStreamUserScroll, { passive: true });
    dom.chatScroll.addEventListener("touchstart", onStreamTouchStart, { passive: true });

    const flushFrame = () => {
      rafScheduled = false;
      const stick = !userPinnedUp && isNearBottom();
      if (dirtyThink) {
        dirtyThink = false;
        thinkBoard.hidden = false;
        thinkContentEl.innerHTML = renderThinkingMd(assistantMsg.thinking);
        thinkTimerEl.textContent = `${((performance.now() - genStart) / 1000).toFixed(1)}s`;
      }
      if (dirtyText) {
        dirtyText = false;
        if (!thinkBoard.hidden && thinkBoard.classList.contains("is-live")) {
          thinkBoard.classList.remove("is-live");
          const sec = Math.max(1, Math.round((performance.now() - genStart) / 1000));
          assistantMsg.thinking_sec = sec;
          thinkTitle.textContent = `${sec} sn düşündü`;
          if (thinkTimerEl) thinkTimerEl.textContent = "";
          thinkBoard.open = false;
        }
        // In-place live code block streaming update so user wheel/scrollbar scrolling inside <pre> is NEVER interrupted!
        const fenceMatches = assistantMsg.content.match(/```([\w-]*)\n([\s\S]*?)(?:```|$)/g) || [];
        const existingPres = $$(".code-block-wrap pre", mdEl);
        const fenceCountRaw = (assistantMsg.content.match(/^```/gm) || []).length;
        const isCurrentlyInsideCodeFence = fenceCountRaw % 2 === 1;

        if (isCurrentlyInsideCodeFence && existingPres.length === fenceMatches.length && existingPres.length > 0) {
          const lastIdx = existingPres.length - 1;
          const activePre = existingPres[lastIdx];
          const activeWrap = activePre.closest(".code-block-wrap");
          const rawBlock = fenceMatches[lastIdx];
          const firstNl = rawBlock.indexOf("\n");
          const rawLang = (firstNl > 3 ? rawBlock.slice(3, firstNl) : "kod").trim().toLowerCase();
          const rawCode = firstNl >= 0 ? rawBlock.slice(firstNl + 1).replace(/```$/, "") : "";
          const { htmlLines, lineCount } = highlightCode(rawCode, rawLang);
          const codeEl = $("code", activePre);
          const metaEl = activeWrap ? $(".code-meta", activeWrap) : null;
          const wasNearPreBottom = activePre.scrollHeight - activePre.scrollTop - activePre.clientHeight < 42;
          const userPinnedUp = activePre.dataset.userScrolledUp === "1";

          if (codeEl) codeEl.innerHTML = htmlLines;
          if (metaEl) metaEl.textContent = `${lineCount} satır`;
          if (activeWrap && lineCount > 20) activeWrap.classList.add("is-scrollable");
          if (!userPinnedUp && wasNearPreBottom) {
            activePre.scrollTop = activePre.scrollHeight;
          }
        } else {
          const prevPreStates = existingPres.map((p) => ({
            top: p.scrollTop,
            left: p.scrollLeft,
            pinnedUp: p.dataset.userScrolledUp === "1",
            atBottom: p.scrollHeight - p.scrollTop - p.clientHeight < 42,
          }));
          const prevTableScrolls = $$(".md-table-wrap", mdEl).map((w) => w.scrollLeft);
          mdEl.innerHTML = renderMarkdown(assistantMsg.content, { isStreaming: true });
          $$(".md-table-wrap", mdEl).forEach((w, i) => {
            if (prevTableScrolls[i]) w.scrollLeft = prevTableScrolls[i];
          });
          $$(".code-block-wrap pre", mdEl).forEach((p, i) => {
            const stPrev = prevPreStates[i];
            if (!stPrev) {
              p.scrollTop = p.scrollHeight;
            } else {
              p.scrollLeft = stPrev.left;
              if (stPrev.pinnedUp) p.dataset.userScrolledUp = "1";
              p.scrollTop = (!stPrev.pinnedUp && stPrev.atBottom) ? p.scrollHeight : stPrev.top;
            }
          });
        }
      }
      if (stick) scrollToBottom(false);
    };

    let lastRenderTs = 0;
    const scheduleFlush = () => {
      if (!rafScheduled) {
        rafScheduled = true;
        requestAnimationFrame((ts) => {
          if (ts - lastRenderTs < 28 && !engineStopRequested) {
            rafScheduled = false;
            setTimeout(() => {
              if (dirtyThink || dirtyText) scheduleFlush();
            }, 22);
            return;
          }
          lastRenderTs = ts;
          flushFrame();
        });
      }
    };
    let engineStopRequested = false;

    try {
      // Optional automatic geolocation for weather/local queries (cached once, silent fallback)
      let userLocation = state.cachedGeoLocation || null;
      const needsGeo = /\b(hava\s*durumu|bugün\s*hava|yarın\s*hava|burada|yakınımda|yakınımdaki|konumum|eczan|restoran|kafe)\b/i.test(userMsg.content || "");
      if (needsGeo && !userLocation && navigator.geolocation) {
        userLocation = await new Promise((resolve) => {
          const t = setTimeout(() => resolve(null), 1600);
          navigator.geolocation.getCurrentPosition(
            (pos) => {
              clearTimeout(t);
              const loc = { lat: Number(pos.coords.latitude.toFixed(4)), lon: Number(pos.coords.longitude.toFixed(4)) };
              state.cachedGeoLocation = loc;
              resolve(loc);
            },
            () => { clearTimeout(t); resolve(null); },
            { timeout: 1500, maximumAge: 600000 }
          );
        });
      }

      const payload = {
        session_id: state.activeSessionId,
        project_id: state.activeProjectId || null,
        skill_id: state.activeSkillId || null,
        model_id: state.selectedModelId,
        lora_id: state.selectedLoraId || null,
        lora_scale: Number(dom.rngLoraScale.value),
        thinking_effort: state.thinkingEffort,
        web_search: state.webSearch,
        use_library: state.useLibrary,
        ignore_memory: Boolean(state.isTemporaryChat && !state.temporaryPersonalized),
        user_location: userLocation,
        temperature: Number(dom.rngTemp.value),
        top_p: Number(dom.rngTopP.value),
        max_new_tokens: Number(dom.rngMaxTokens.value),
        system_prompt: (state.tempPersonaPrompt || dom.txtSystemPrompt.value || "").trim(),
        messages: state.messages.slice(0, -1).map((m) => ({
          role: m.role,
          content: m.content,
          thinking: m.thinking || "",
          attachments: m.attachments || [],
        })),
      };

      const res = await fetch("/api/chat", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
        signal: state.abortController.signal,
      });

      if (!res.ok) {
        let errTxt = `HTTP ${res.status}`;
        try {
          const j = await res.json();
          errTxt = j.detail || errTxt;
        } catch (_) {}
        throw new Error(errTxt);
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder("utf-8");
      let buf = "";

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const events = buf.split("\n\n");
        buf = events.pop() || "";

        for (const chunk of events) {
          const line = chunk.split("\n").find((l) => l.startsWith("data: "));
          if (!line) continue;
          let ev;
          try {
            ev = JSON.parse(line.slice(6));
          } catch (_) {
            continue;
          }

          if (ev.type === "memory_saved" && ev.item) {
            showToast(`Kalıcı hafızaya eklendi: "${ev.item.text.slice(0, 48)}"`, "ok", 3400);
            loadMemories();
          } else if (ev.type === "note_saved" && ev.item) {
            showToast(`Notlara eklendi: "${ev.item.text.slice(0, 48)}"`, "ok", 3200);
            loadExtensions();
          } else if (ev.type === "context_compacted") {
            showToast(`Bağlam otomatik optimize edildi (${ev.compacted_count || 0} eski mesaj özetlendi: %${ev.before_pct || 0} → %${ev.after_pct || 0})`, "ok", 3600);
            if (ev.after_tokens) updateContextMeter(ev.after_tokens, state.contextLength || 32768);
          } else if (ev.type === "web_search") {
            assistantMsg.web_search = ev;
            webSlotEl.innerHTML = buildWebSearchHtml(ev);
            if (wsLiveSlotEl) {
              const cnt = Array.isArray(ev.sources) ? ev.sources.length : wsLiveCount;
              wsLiveSlotEl.innerHTML = cnt > 0
                ? `<div class="web-search-live-pill"><span class="ws-live-dot"></span><span>${cnt} web sitesi araştırıldı</span></div>`
                : "";
            }
            if (ev.online === false) {
              showToast("İnternet bağlantısı yok: Web araştırması yapılamadı", "warn", 4600);
              pushNotification("Çevrimdışı Uyarı", ev.warning || "Cihaz internete çıkamadı.", "warn");
            }
          } else if (ev.type === "rich_card" && ev.card) {
            assistantMsg.rich_cards.push(ev.card);
            richSlotEl.innerHTML = buildRichCardsHtml(assistantMsg.rich_cards);
            hydrateChartsInNode(richSlotEl);
            scrollToBottom(true);
          } else if (ev.type === "status") {
            if (ev.stage === "web_search" && wsLiveSlotEl) {
              wsLiveCount = Math.max(wsLiveCount + 1, Number(ev.count || 1));
              const domTxt = ev.domain ? `<span class="ws-live-domain mono">(${escHtml(ev.domain)})</span>` : "";
              wsLiveSlotEl.innerHTML = `<div class="web-search-live-pill is-live"><span class="ws-live-dot"></span><span>${wsLiveCount} web sitesi inceleniyor...</span>${domTxt}</div>`;
            }
            if (ev.message && !assistantMsg.content) statsEl.textContent = ev.message;
          } else if (ev.type === "thinking_delta" || ev.type === "thinking") {
            assistantMsg.thinking += ev.delta || "";
            dirtyThink = true;
            scheduleFlush();
          } else if (ev.type === "answer_delta" || ev.type === "text") {
            assistantMsg.content += ev.delta || "";
            dirtyText = true;
            scheduleFlush();
          } else if (ev.type === "auto_persona" && ev.name) {
            assistantMsg.auto_persona = ev.name;
            const nameRow = $(".assistant-name-row", msgNode);
            if (nameRow && !$(".persona-auto-badge", nameRow)) {
              const badge = document.createElement("span");
              badge.className = "assistant-meta-pill persona-auto-badge";
              badge.textContent = `Uzman: ${ev.name}`;
              nameRow.appendChild(badge);
            }
          } else if (ev.type === "mcp_tool_request" && Array.isArray(ev.calls) && ev.calls.length) {
            assistantMsg.mcp_calls = ev.calls.map((c) => ({ ...c, status: "pending" }));
            if (mcpSlotEl) mcpSlotEl.innerHTML = buildMcpApprovalHtml(assistantMsg.mcp_calls, assistantMsgIdx);
            scrollToBottom(true);
          } else if (ev.type === "completed" || ev.type === "done") {
            const st = ev.stats || ev;
            assistantMsg.stats = { tps: st.tps, elapsed_sec: st.elapsed_sec, tokens: st.tokens };
            if (st.context_used_est) updateContextMeter(st.context_used_est, st.context_limit || state.contextLength || 32768);
            else updateContextMeter();
          } else if (ev.type === "error") {
            throw new Error(ev.detail || ev.error || "Bilinmeyen üretim hatası");
          }
        }
      }

      if (dirtyThink || dirtyText) flushFrame();
      // Ensure code-only responses always have a brief Turkish explanation below/above the file card
      if (assistantMsg.content && /```[\s\S]{80,}?```/.test(assistantMsg.content)) {
        const proseOnly = assistantMsg.content
          .replace(/```[\s\S]*?```/g, "")
          .replace(/<mcp_call>[\s\S]*?<\/mcp_call>/g, "")
          .trim();
        if (proseOnly.length < 22) {
          assistantMsg.content += "\n\n**Özet:** İstenen kod ve arayüz yapısı eksiksiz hazırlandı. Aşağıdaki dosya kartından **Önizle / Kodu Aç** ile sağ panelde canlı inceleyebilir, düzenleyebilir veya doğrudan indirebilirsiniz.";
        }
      }
      // Final non-streaming render so completed 10+ line code blocks collapse cleanly into Claude-style SVG cards
      mdEl.innerHTML = renderMarkdown(assistantMsg.content, { isStreaming: false });
      orbEl.classList.remove("is-live");
      surfaceEl.classList.remove("is-streaming");
      mdEl.classList.remove("is-streaming");
      thinkBoard.classList.remove("is-live");
      if (!thinkBoard.hidden) {
        const sec = assistantMsg.thinking_sec || Math.max(1, Math.round((performance.now() - genStart) / 1000));
        assistantMsg.thinking_sec = sec;
        thinkTitle.textContent = `${sec} sn düşündü`;
        if (thinkTimerEl) thinkTimerEl.textContent = "";
      }
      statsEl.textContent = assistantMsg.stats
        ? `${assistantMsg.stats.tps} tok/sn · ${assistantMsg.stats.elapsed_sec}s · ${assistantMsg.stats.tokens} token`
        : "";

      if (Array.isArray(assistantMsg.variants)) {
        assistantMsg.variants.push(snapshotAssistantVariant(assistantMsg));
        assistantMsg.variantIdx = assistantMsg.variants.length - 1;
        const leftBar = $(".msg-actions-left", msgNode);
        if (leftBar && !$(".msg-branch-nav", leftBar)) {
          const navHtml = `<div class="msg-branch-nav"><button type="button" class="msg-branch-btn" data-branch-dir="-1" aria-label="Önceki yanıt">${SVG_ICONS.chevLeft}</button><span class="msg-branch-count mono">${assistantMsg.variantIdx + 1} / ${assistantMsg.variants.length}</span><button type="button" class="msg-branch-btn" data-branch-dir="1" disabled aria-label="Sonraki yanıt">${SVG_ICONS.chevRight}</button></div>`;
          leftBar.insertAdjacentHTML("afterbegin", navHtml);
        }
      }

      hydrateRichContent(msgNode);
      await maybeGenerateFileCard(userMsg.content, assistantMsg, msgNode, richSlotEl);

      // Smart Auto Title for new sessions on the first exchange
      if (state.messages.length <= 2 && dom.pageBreadcrumb.textContent === "Yeni Sohbet") {
        try {
          const tRes = await apiJson("/api/sessions/autotitle", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ user_text: userMsg.content }),
          });
          if (tRes?.title) dom.pageBreadcrumb.textContent = tRes.title;
        } catch (_) {}
      }

      await saveCurrentSession();
      pollStatus();
      window.yerelDesktop?.notify?.("SEN.AI Yanıtı Hazır", (assistantMsg.content || "").replace(/[#*`]/g, "").slice(0, 110));

      if ((dom.swAutoTts.checked || state.handsFree) && assistantMsg.content.trim()) {
        const spkBtn = $(".btn-msg-speak", msgNode);
        speakText(assistantMsg.content, spkBtn);
      }
    } catch (err) {
      orbEl.classList.remove("is-live");
      surfaceEl.classList.remove("is-streaming");
      mdEl.classList.remove("is-streaming");
      thinkBoard.classList.remove("is-live");
      if (err.name === "AbortError") {
        statsEl.textContent = "Durduruldu";
        showToast("Üretim durduruldu", "warn", 2200);
      } else {
        assistantMsg.content = assistantMsg.content || `Üretim hatası: ${err.message}`;
        mdEl.innerHTML = renderMarkdown(assistantMsg.content);
        statsEl.textContent = "Hata";
        showToast(err.message, "err", 4800);
        pushNotification("Üretim Hatası", err.message, "err");
      }
    } finally {
      dom.chatScroll.removeEventListener("scroll", onStreamUserScroll);
      dom.chatScroll.removeEventListener("touchstart", onStreamTouchStart);
      state.isGenerating = false;
      state.abortController = null;
      dom.composerCard?.classList.remove("is-generating");
      dom.btnSend.hidden = false;
      dom.btnStop.hidden = true;
    }
  }

  function stopGeneration() {
    if (state.abortController) {
      state.abortController.abort();
      fetch("/api/chat/stop", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ session_id: state.activeSessionId || "" }),
      }).catch(() => {});
    }
  }

  /* =========================================================
     Clean Inline Message Read-Aloud (Zero Bottom Player Dock)
     ========================================================= */
  function resetSpeakBtn(btn) {
    if (!btn) return;
    btn.classList.remove("is-busy", "is-playing");
    btn.innerHTML = SVG_ICONS.speak;
    btn.setAttribute("data-tip", "Türkçe Seslendir");
  }

  function stopSpeaking() {
    dom.audioEl.pause();
    dom.audioEl.currentTime = 0;
    if (state.activeSpeakBtn) {
      resetSpeakBtn(state.activeSpeakBtn);
      state.activeSpeakBtn = null;
    }
  }

  async function speakText(text, triggerBtn = null) {
    const clean = (text || "").trim();
    if (!clean) return;

    // Clicking the active speaking button toggles stop cleanly
    if (triggerBtn && state.activeSpeakBtn === triggerBtn && !dom.audioEl.paused) {
      stopSpeaking();
      return;
    }

    stopSpeaking();
    state.activeSpeakBtn = triggerBtn;
    if (triggerBtn) {
      triggerBtn.classList.add("is-busy");
      triggerBtn.setAttribute("data-tip", "Ses hazırlanıyor...");
    }

    try {
      const res = await fetch("/api/tts", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: clean, voice: state.ttsVoice }),
      });
      if (!res.ok) throw new Error(`TTS HTTP ${res.status}`);

      const blob = await res.blob();
      if (state.activeTtsUrl) URL.revokeObjectURL(state.activeTtsUrl);
      state.activeTtsUrl = URL.createObjectURL(blob);
      dom.audioEl.src = state.activeTtsUrl;
      dom.audioEl.playbackRate = Number(state.ttsSpeed || 1);
      await dom.audioEl.play();

      if (triggerBtn) {
        triggerBtn.classList.remove("is-busy");
        triggerBtn.classList.add("is-playing");
        triggerBtn.setAttribute("data-tip", "Seslendirmeyi Durdur");
        triggerBtn.innerHTML = `<span class="speak-eq" aria-hidden="true"><i></i><i></i><i></i></span><span>Durdur</span>`;
      }
    } catch (err) {
      resetSpeakBtn(triggerBtn);
      state.activeSpeakBtn = null;
      showToast(`Türkçe seslendirme hatası: ${err.message}`, "err", 4200);
    }
  }

  function setupAudioPlayer() {
    dom.audioEl.addEventListener("ended", () => {
      if (state.activeSpeakBtn) {
        resetSpeakBtn(state.activeSpeakBtn);
        state.activeSpeakBtn = null;
      }
      if (state.handsFree && !state.isGenerating && !state.isRecording) {
        setTimeout(() => {
          if (state.handsFree && !state.isGenerating && !state.isRecording) startRecording();
        }, 450);
      }
    });
  }

  /* =========================================================
     16 kHz Mono WAV Microphone Recorder
     ========================================================= */
  function encodeWav16k(samples, srcRate) {
    const targetRate = 16000;
    let data = samples;
    if (srcRate !== targetRate) {
      const ratio = srcRate / targetRate;
      const newLen = Math.round(samples.length / ratio);
      data = new Float32Array(newLen);
      for (let i = 0; i < newLen; i++) data[i] = samples[Math.min(samples.length - 1, Math.floor(i * ratio))];
    }
    const buf = new ArrayBuffer(44 + data.length * 2);
    const view = new DataView(buf);
    const writeStr = (off, s) => {
      for (let i = 0; i < s.length; i++) view.setUint8(off + i, s.charCodeAt(i));
    };
    writeStr(0, "RIFF");
    view.setUint32(4, 36 + data.length * 2, true);
    writeStr(8, "WAVE");
    writeStr(12, "fmt ");
    view.setUint32(16, 16, true);
    view.setUint16(20, 1, true);
    view.setUint16(22, 1, true);
    view.setUint32(24, targetRate, true);
    view.setUint32(28, targetRate * 2, true);
    view.setUint16(32, 2, true);
    view.setUint16(34, 16, true);
    writeStr(36, "data");
    view.setUint32(40, data.length * 2, true);
    let off = 44;
    for (let i = 0; i < data.length; i++, off += 2) {
      const s = Math.max(-1, Math.min(1, data[i]));
      view.setInt16(off, s < 0 ? s * 0x8000 : s * 0x7fff, true);
    }
    return new Blob([buf], { type: "audio/wav" });
  }

  async function startRecording() {
    if (state.isRecording) return;
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const AudioCtx = window.AudioContext || window.webkitAudioContext;
      const ctx = new AudioCtx();
      const src = ctx.createMediaStreamSource(stream);
      const analyser = ctx.createAnalyser();
      analyser.fftSize = 128;
      const proc = ctx.createScriptProcessor(4096, 1, 1);
      state.recChunks = [];
      proc.onaudioprocess = (e) => {
        if (state.isRecording) state.recChunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
      };
      src.connect(analyser);
      analyser.connect(proc);
      proc.connect(ctx.destination);

      state.recStream = stream;
      state.recAudioCtx = ctx;
      state.recProcessor = proc;
      state.recAnalyser = analyser;
      state.isRecording = true;
      state.recStartTime = Date.now();
      state.vadSpeechSeen = false;
      state.vadLastSoundTs = Date.now();
      dom.btnMic.classList.add("recording");
      dom.recordingBar.hidden = false;
      dom.recTimer.textContent = "00:00";

      state.recTimerId = setInterval(() => {
        const sec = Math.floor((Date.now() - state.recStartTime) / 1000);
        dom.recTimer.textContent = `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(sec % 60).padStart(2, "0")}`;
      }, 300);

      const drawWave = () => {
        if (!state.isRecording) return;
        const c = dom.recWaveform;
        const g = c.getContext("2d");
        const arr = new Uint8Array(analyser.frequencyBinCount);
        analyser.getByteFrequencyData(arr);
        g.clearRect(0, 0, c.width, c.height);
        const bars = 16;
        const gap = 4;
        const barW = Math.max(4, Math.floor((c.width - gap * (bars - 1)) / bars));
        const totalW = bars * barW + (bars - 1) * gap;
        const startX = Math.floor((c.width - totalW) / 2);
        const grad = g.createLinearGradient(0, 0, c.width, 0);
        grad.addColorStop(0, "#06b6d4");
        grad.addColorStop(0.5, "#3b82f6");
        grad.addColorStop(1, "#6366f1");
        g.fillStyle = grad;
        for (let i = 0; i < bars; i++) {
          const bin = Math.min(arr.length - 1, Math.floor((i * arr.length) / (bars * 1.6)));
          const amp = arr[bin] / 255;
          const h = Math.max(4, Math.round(amp * (c.height - 2)));
          const x = startX + i * (barW + gap);
          const y = Math.floor((c.height - h) / 2);
          g.beginPath();
          if (g.roundRect) g.roundRect(x, y, barW, h, 3);
          else g.rect(x, y, barW, h);
          g.fill();
        }
        // Hands-Free VAD silence detection (~1.6s pause after speech triggers auto-send)
        if (state.handsFree) {
          let sum = 0;
          for (let i = 0; i < arr.length; i++) sum += arr[i];
          const avg = sum / Math.max(1, arr.length);
          const nowTs = Date.now();
          if (avg > 22) {
            state.vadSpeechSeen = true;
            state.vadLastSoundTs = nowTs;
          } else if (state.vadSpeechSeen && nowTs - state.vadLastSoundTs > 1600 && nowTs - state.recStartTime > 900) {
            finishRecording(true);
            return;
          }
        }
        state.recRafId = requestAnimationFrame(drawWave);
      };
      drawWave();
    } catch (err) {
      showToast(`Mikrofon erişimi alınamadı: ${err.message}`, "err");
    }
  }

  async function finishRecording(shouldSend) {
    if (!state.isRecording) return;
    state.isRecording = false;
    clearInterval(state.recTimerId);
    cancelAnimationFrame(state.recRafId);
    dom.btnMic.classList.remove("recording");
    dom.recordingBar.hidden = true;
    const sampleRate = state.recAudioCtx?.sampleRate || 44100;
    try {
      state.recProcessor?.disconnect();
      state.recStream?.getTracks().forEach((t) => t.stop());
      await state.recAudioCtx?.close();
    } catch (_) {}

    if (!shouldSend || !state.recChunks.length) return;
    const totalLen = state.recChunks.reduce((acc, c) => acc + c.length, 0);
    const merged = new Float32Array(totalLen);
    let offset = 0;
    for (const c of state.recChunks) {
      merged.set(c, offset);
      offset += c.length;
    }
    const wavBlob = encodeWav16k(merged, sampleRate);
    const file = new File([wavBlob], `ses_kaydi_${Date.now()}.wav`, { type: "audio/wav" });
    await uploadFiles([file]);
    if (!dom.promptInput.value.trim()) await sendMessage("Bu ses kaydını dikkatlice dinle ve Türkçe yanıtla.");
    else await sendMessage();
  }

  /* =========================================================
     Colab Dataset Hub
     ========================================================= */
  async function loadDataset() {
    try {
      const data = await apiJson("/api/dataset");
      state.dataset = data.entries || [];
      state.datasetStats = {
        sft: data.sft_count ?? state.dataset.length,
        dislike: data.dislike_count ?? 0,
        dpo: data.dpo_count ?? 0,
      };
      renderDatasetUI();
    } catch (_) {}
  }

  function renderDatasetUI() {
    const cnt = state.dataset.length;
    const stats = state.datasetStats || { sft: cnt, dislike: 0, dpo: 0 };
    const lbl = `${cnt} örnek`;
    dom.datasetCountBadge.textContent = lbl;
    dom.inspDsCount.textContent = lbl;
    if (dom.dsSftCount) dom.dsSftCount.textContent = `👍 SFT: ${stats.sft}`;
    if (dom.dsDislikeCount) dom.dsDislikeCount.textContent = `👎 Reddedilen: ${stats.dislike}`;
    if (dom.dsDpoCount) dom.dsDpoCount.textContent = `⚡ DPO Çifti: ${stats.dpo}`;
    if (!cnt) {
      dom.inspDatasetList.innerHTML = `<div class="muted-empty">Henüz oylama veya eğitim örneği eklenmedi.</div>`;
      return;
    }
    dom.inspDatasetList.innerHTML = state.dataset
      .slice()
      .reverse()
      .slice(0, 20)
      .map((e) => {
        const u = (e.messages || []).find((m) => m.role === "user")?.content || "Örnek";
        const tag = e.rating === "dislike" ? (e.corrected_text ? "⚡" : "👎") : "👍";
        return `
        <div class="ds-mini-item">
          <span title="${escHtml(u)}">${tag} ${escHtml(u)}</span>
          <button type="button" class="hact danger btn-del-ds" data-ds-id="${escHtml(e.id)}" title="Sil">${SVG_ICONS.trash}</button>
        </div>`;
      })
      .join("");
  }

  function openDatasetModal(userText, assistantText) {
    dom.dsUserInput.value = userText || "";
    dom.dsAssistantInput.value = assistantText || "";
    dom.datasetModal.hidden = false;
  }

  async function saveDatasetEntry() {
    const u = dom.dsUserInput.value.trim();
    const a = dom.dsAssistantInput.value.trim();
    if (!u || !a) return showToast("Soru ve yanıt alanları boş olamaz", "warn");
    try {
      await apiJson("/api/dataset", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          system_prompt: dom.txtSystemPrompt.value.trim(),
          user_text: u,
          assistant_text: a,
          model_id: state.selectedModelId,
          thinking_effort: state.thinkingEffort,
        }),
      });
      dom.datasetModal.hidden = true;
      await loadDataset();
      showToast("Colab eğitim setine eklendi", "ok");
    } catch (err) {
      showToast(`Kaydedilemedi: ${err.message}`, "err");
    }
  }

  function autoResizeTextarea() {
    dom.promptInput.style.height = "auto";
    dom.promptInput.style.height = `${Math.min(180, dom.promptInput.scrollHeight)}px`;
  }

  function extractTableMatrix(tableEl) {
    return Array.from(tableEl.querySelectorAll("tr")).map((tr) =>
      Array.from(tr.querySelectorAll("th, td")).map((td) => td.textContent.replace(/\s+/g, " ").trim())
    );
  }

  async function exportTableToXlsx(tableEl, title = "YerelAI_Tablo") {
    const matrix = extractTableMatrix(tableEl);
    if (!matrix.length) return;
    try {
      const res = await apiJson("/api/export/xlsx", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title, headers: matrix[0], rows: matrix.slice(1) }),
      });
      if (res.url) {
        const a = document.createElement("a");
        a.href = res.url;
        a.download = res.filename || "tablo.xlsx";
        a.click();
        showToast(`${res.filename} indirildi`, "ok", 2200);
      }
    } catch (err) {
      showToast(`Excel oluşturulamadı: ${err.message}`, "err", 3600);
    }
  }

  function findHeadingBeforeTableCard(cardEl) {
    let prev = cardEl?.previousElementSibling;
    let steps = 0;
    while (prev && steps < 4) {
      if (/^H[1-5]$/.test(prev.tagName)) {
        const clean = prev.textContent.replace(/^[\p{Emoji_Presentation}\p{Extended_Pictographic}\s:.-]+/u, "").trim();
        if (clean.length >= 2) return clean;
      }
      prev = prev.previousElementSibling;
      steps += 1;
    }
    return "";
  }

  async function maybeGenerateFileCard(userText, assistantMsg, msgNode) {
    if (!assistantMsg?.content) return;
    // Skip if backend already emitted a direct file_download card for this turn
    const alreadyHasXlsx =
      (assistantMsg.rich_cards || []).some((c) => c && c.kind === "file_download" && c.file_kind === "xlsx") ||
      (assistantMsg.file_cards || []).some((c) => c && c.file_kind === "xlsx");
    if (alreadyHasXlsx) {
      const fileSlotEl = $(".file-cards-slot", msgNode);
      const allFc = [
        ...(assistantMsg.file_cards || []),
        ...(assistantMsg.rich_cards || []).filter((c) => c && c.kind === "file_download"),
      ];
      if (fileSlotEl && allFc.length) fileSlotEl.innerHTML = buildFileCardsHtml(allFc, false);
      return;
    }

    const q = (userText || "").toLowerCase();
    const prevUserMsgs = state.messages.filter((m) => m.role === "user").slice(-2).map((m) => (m.content || "").toLowerCase()).join(" ");
    const wantsCreate = /\b(?:oluştur|hazırla|yap|üret|çıkar|ver|indir|export|çevir|çevirir|dönüştür|aktar|kaydet)\b/.test(q);
    if (!wantsCreate) return;

    const wantsXlsx = /\b(?:excel|xlsx|tablo\s+dosyası)\b/.test(prevUserMsgs);
    const wantsPdf = /\bpdf\b/.test(q);
    const wantsDocx = /\b(?:word|docx)\b/.test(q);
    const fallbackTitle = "YerelAI_Veri_Tablosu";

    try {
      let exported = null;
      const tableCards = $$(".md-table-card", msgNode);
      if (wantsXlsx) {
        const sheets = [];
        let smartTitle = "";
        tableCards.forEach((tc, i) => {
          const tbl = $(".md-table", tc);
          if (!tbl) return;
          const matrix = extractTableMatrix(tbl);
          if (matrix.length >= 2) {
            const heading = findHeadingBeforeTableCard(tc);
            const cleanHead = heading.replace(/^örnek\s+veri\s+seti\s*:\s*/i, "").trim();
            if (!smartTitle && cleanHead) smartTitle = cleanHead;
            sheets.push({
              name: cleanHead || (i === 0 ? "Veri" : `Analiz ${i + 1}`),
              headers: matrix[0],
              rows: matrix.slice(1),
            });
          }
        });
        if (sheets.length) {
          exported = await apiJson("/api/export/xlsx", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ title: (smartTitle || fallbackTitle).slice(0, 44), sheets }),
          });
        }
      } else if (wantsPdf) {
        const firstH = $("h1, h2, h3", msgNode)?.textContent?.trim() || "YerelAI_Rapor";
        exported = await apiJson("/api/export/pdf", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: firstH.slice(0, 44), content: assistantMsg.content }),
        });
      } else if (wantsDocx) {
        const firstH = $("h1, h2, h3", msgNode)?.textContent?.trim() || "YerelAI_Rapor";
        exported = await apiJson("/api/export/docx", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ title: firstH.slice(0, 44), content: assistantMsg.content }),
        });
      }

      if (exported && exported.url) {
        if (!Array.isArray(assistantMsg.file_cards)) assistantMsg.file_cards = [];
        assistantMsg.file_cards.push({
          kind: "file_download",
          file_kind: exported.kind,
          filename: exported.filename,
          url: exported.url,
          meta: exported.meta,
        });
        if (exported.kind === "xlsx" && tableCards.length) {
          collapseTableCardsInNode(msgNode, true);
        }
        const fileSlotEl = $(".file-cards-slot", msgNode);
        if (fileSlotEl) {
          fileSlotEl.innerHTML = buildFileCardsHtml(assistantMsg.file_cards, tableCards.length > 0);
        }
      }
    } catch (err) {
      console.warn("Auto file card export skipped:", err);
    }
  }

  function setInspectorOpen(open, tab = null) {
    if (window.YerelSettings) {
      window.YerelSettings.setOpen(open, tab);
      return;
    }
    const isOpen = Boolean(open);
    dom.inspector.hidden = !isOpen;
    dom.inspector.classList.toggle("open", isOpen);
    dom.inspector.setAttribute("aria-hidden", String(!isOpen));
  }

  function updateEditorLineNumbers(text) {
    if (!dom.artifactLineNums) return;
    const count = Math.max(1, String(text || "").split("\n").length);
    const lines = [];
    for (let i = 1; i <= count; i++) lines.push(i);
    dom.artifactLineNums.textContent = lines.join("\n");
  }

  function buildArtifactPreviewHtml(code, lang) {
    const linkGuardScript = `<script>document.addEventListener('click',function(e){var a=e.target.closest('a[href]');if(!a)return;var h=a.getAttribute('href')||'';if(h.startsWith('#')){e.preventDefault();var id=h.slice(1);var t=id?document.getElementById(id):null;if(t)t.scrollIntoView({behavior:'smooth'});else window.scrollTo({top:0,behavior:'smooth'});}else if(/^https?:\\/\\//i.test(h)){a.setAttribute('target','_blank');a.setAttribute('rel','noopener noreferrer');}else{e.preventDefault();}});<\/script>`;
    let docHtml =
      lang === "svg"
        ? `<!DOCTYPE html><html><body style="margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#f8fafc;">${code}</body></html>`
        : code;
    return /<\/body>/i.test(docHtml) ? docHtml.replace(/<\/body>/i, `${linkGuardScript}</body>`) : `${docHtml}${linkGuardScript}`;
  }

  function collectSessionCodeFiles() {
    const files = [];
    const fenceRe = /```([a-zA-Z0-9_+-]*)\n([\s\S]*?)```/g;
    state.messages.forEach((m) => {
      if (m.role !== "assistant" || !m.content) return;
      let match;
      while ((match = fenceRe.exec(m.content)) !== null) {
        const lang = (match[1] || "txt").toLowerCase();
        const code = (match[2] || "").trimEnd();
        if (code.length < 15) continue;
        files.push({ filename: guessCodeFilename(code, lang), lang, code });
      }
    });
    return files;
  }

  function collectArtifactVersions(filename, lang, currentCode) {
    const all = collectSessionCodeFiles();
    const matches = all.filter((f) => f.filename === filename || (f.lang === lang && (lang === "html" || lang === "svg" || lang === "python" || lang === "py")));
    const versions = [];
    matches.forEach((m) => {
      if (!versions.length || versions[versions.length - 1].code !== m.code) {
        versions.push({ label: `v${versions.length + 1}`, code: m.code });
      }
    });
    if (!versions.length || versions[versions.length - 1].code !== currentCode) {
      versions.push({ label: `v${versions.length + 1}`, code: currentCode });
    }
    return versions;
  }

  function computeLineDiff(oldText, newText) {
    const a = String(oldText || "").split("\n");
    const b = String(newText || "").split("\n");
    const m = a.length;
    const n = b.length;
    if (m * n > 250000) {
      // Fast fallback for very large files
      const out = [];
      const maxL = Math.max(m, n);
      for (let i = 0; i < maxL; i++) {
        if (a[i] === b[i]) out.push({ type: "eq", oldLn: i + 1, newLn: i + 1, text: b[i] });
        else {
          if (i < m) out.push({ type: "del", oldLn: i + 1, newLn: "", text: a[i] });
          if (i < n) out.push({ type: "add", oldLn: "", newLn: i + 1, text: b[i] });
        }
      }
      return out;
    }
    const dp = Array.from({ length: m + 1 }, () => new Uint16Array(n + 1));
    for (let i = m - 1; i >= 0; i--) {
      for (let j = n - 1; j >= 0; j--) {
        dp[i][j] = a[i] === b[j] ? dp[i + 1][j + 1] + 1 : Math.max(dp[i + 1][j], dp[i][j + 1]);
      }
    }
    const rows = [];
    let i = 0, j = 0;
    while (i < m && j < n) {
      if (a[i] === b[j]) {
        rows.push({ type: "eq", oldLn: i + 1, newLn: j + 1, text: a[i] });
        i++; j++;
      } else if (dp[i + 1][j] >= dp[i][j + 1]) {
        rows.push({ type: "del", oldLn: i + 1, newLn: "", text: a[i] });
        i++;
      } else {
        rows.push({ type: "add", oldLn: "", newLn: j + 1, text: b[j] });
        j++;
      }
    }
    while (i < m) { rows.push({ type: "del", oldLn: i + 1, newLn: "", text: a[i++] }); }
    while (j < n) { rows.push({ type: "add", oldLn: "", newLn: j + 1, text: b[j++] }); }
    return rows;
  }

  function renderArtifactDiff() {
    if (!dom.artifactDiffView || !state.activeArtifact) return;
    const versions = state.artifactVersions || [];
    const curCode = state.activeArtifact.code || "";
    const baseCode = state.activeArtifact.baseCode != null
      ? state.activeArtifact.baseCode
      : (versions.length >= 2 ? versions[versions.length - 2].code : curCode);
    const rows = computeLineDiff(baseCode, curCode);
    let adds = 0, dels = 0;
    rows.forEach((r) => { if (r.type === "add") adds++; else if (r.type === "del") dels++; });
    const baseLabel = state.activeArtifact.baseLabel || (versions.length >= 2 ? versions[versions.length - 2].label : "Orijinal");
    const curLabel = state.activeArtifact.edited ? "Canlı Düzenleme" : (versions.length ? versions[versions.length - 1].label : "Güncel");
    dom.artifactDiffView.innerHTML = `
      <div class="diff-summary-bar">
        <span>${escHtml(baseLabel)} ↔ ${escHtml(curLabel)}</span>
        <span><span class="diff-stat-add">+${adds}</span><span class="diff-stat-del">-${dels}</span></span>
      </div>
      <table class="diff-table"><tbody>
        ${rows.map((r) => `
          <tr class="diff-row ${r.type}">
            <td class="diff-ln">${r.oldLn}</td>
            <td class="diff-ln">${r.newLn}</td>
            <td class="diff-sign">${r.type === "add" ? "+" : r.type === "del" ? "-" : " "}</td>
            <td>${escHtml(r.text)}</td>
          </tr>`).join("")}
      </tbody></table>`;
  }

  function renderArtifactVersionBar() {
    const versions = state.artifactVersions || [];
    const hasDiff = versions.length >= 2 || Boolean(state.activeArtifact?.edited);
    if (dom.artTabDiff) dom.artTabDiff.hidden = !hasDiff;
    if (dom.artifactVersionBar) dom.artifactVersionBar.hidden = !state.activeArtifact;
    if (!dom.artifactVerPills || !state.activeArtifact) return;
    dom.artifactVerPills.innerHTML = versions
      .map((v, idx) => `<button type="button" class="art-ver-pill ${idx === state.activeArtifact.verIdx ? "active" : ""}" data-art-ver="${idx}">${escHtml(v.label)}</button>`)
      .join("") + (state.activeArtifact.edited ? `<span class="art-ver-pill active">Düzenlendi</span>` : "");
    if (dom.artifactEditStatus) {
      dom.artifactEditStatus.textContent = state.activeArtifact.edited ? "Canlı senkronize · Ctrl+S" : "Canlı Editör · Ctrl+S";
    }
  }

  function setArtifactTab(tab) {
    const allowed = ["preview", "code", "diff"];
    state.artTab = allowed.includes(tab) ? tab : "preview";
    const isPreview = state.artTab === "preview";
    const isCode = state.artTab === "code";
    const isDiff = state.artTab === "diff";
    dom.artTabPreview?.classList.toggle("active", isPreview);
    dom.artTabPreview?.setAttribute("aria-selected", String(isPreview));
    dom.artTabCode?.classList.toggle("active", isCode);
    dom.artTabCode?.setAttribute("aria-selected", String(isCode));
    dom.artTabDiff?.classList.toggle("active", isDiff);
    dom.artTabDiff?.setAttribute("aria-selected", String(isDiff));
    if (dom.artVpBar) dom.artVpBar.hidden = !isPreview;
    if (dom.artifactIframe) dom.artifactIframe.hidden = !isPreview;
    if (dom.artifactEditorWrap) dom.artifactEditorWrap.hidden = !isCode;
    if (dom.artifactCodeView) dom.artifactCodeView.hidden = true;
    if (dom.artifactDiffView) dom.artifactDiffView.hidden = !isDiff;
    if (isDiff) renderArtifactDiff();
    if (dom.artifactStage) dom.artifactStage.classList.toggle("has-vp-frame", isPreview && state.artViewport !== "desktop");
  }

  function setArtifactViewport(vp) {
    state.artViewport = vp === "tablet" || vp === "mobile" ? vp : "desktop";
    $$(".art-vp-btn", dom.artVpBar || document).forEach((b) => b.classList.toggle("active", b.dataset.vp === state.artViewport));
    if (dom.artifactIframe) {
      dom.artifactIframe.classList.toggle("vp-tablet", state.artViewport === "tablet");
      dom.artifactIframe.classList.toggle("vp-mobile", state.artViewport === "mobile");
    }
    if (dom.artifactStage) {
      dom.artifactStage.classList.toggle("has-vp-frame", state.artTab === "preview" && state.artViewport !== "desktop");
    }
  }

  function setArtifactOpen(open, code = "", lang = "html", titleOverride = "", initialTab = null) {
    const isOpen = Boolean(open);
    const isMobileOverlay = window.innerWidth <= 1024;
    if (isOpen) {
      setInspectorOpen(false);
      const l = (lang || "html").toLowerCase();
      const canPreview = l === "html" || l === "htm" || l === "svg";
      const isPython = l === "python" || l === "py";
      const filename = titleOverride || guessCodeFilename(code, l);
      const versions = collectArtifactVersions(filename, l, code);
      state.artifactVersions = versions;
      const verIdx = versions.length - 1;
      const baseCode = versions.length >= 2 ? versions[versions.length - 2].code : code;
      const baseLabel = versions.length >= 2 ? versions[versions.length - 2].label : "v1";

      state.activeArtifact = { code, lang: l, canPreview, filename, verIdx, baseCode, baseLabel, edited: false };

      const upper = l.toUpperCase();
      dom.artifactLangTag.textContent = upper;
      dom.artifactTitle.textContent = filename || (upper === "SVG" ? "SVG Vektör" : "Canlı Önizleme");

      if (dom.artTabs) dom.artTabs.hidden = false;
      if (dom.artTabPreview) dom.artTabPreview.hidden = !canPreview;
      if (dom.btnArtifactNewtab) dom.btnArtifactNewtab.hidden = !canPreview;
      if (dom.btnArtifactRun) dom.btnArtifactRun.hidden = !isPython;
      if (dom.btnArtifactSaveDisk) dom.btnArtifactSaveDisk.hidden = true;
      if (dom.artifactPyOutput) dom.artifactPyOutput.hidden = true;

      const sessionFiles = collectSessionCodeFiles();
      if (dom.btnArtifactZip) dom.btnArtifactZip.hidden = sessionFiles.length < 2;

      if (canPreview) {
        dom.artifactIframe.srcdoc = buildArtifactPreviewHtml(code, l);
      } else {
        dom.artifactIframe.srcdoc = "";
      }

      if (dom.artifactCodeEditor) {
        dom.artifactCodeEditor.value = code;
        updateEditorLineNumbers(code);
      }
      renderArtifactVersionBar();

      setArtifactTab(initialTab || (canPreview ? "preview" : "code"));
      setArtifactViewport("desktop");

      dom.artifactDrawer.setAttribute("aria-hidden", "false");
      if (dom.artifactResizer) dom.artifactResizer.hidden = isMobileOverlay;
      dom.workspaceBody?.classList.toggle("has-artifact-split", !isMobileOverlay);
      requestAnimationFrame(() => dom.artifactDrawer.classList.add("open"));
      if (isMobileOverlay) {
        dom.drawerBackdrop.hidden = false;
        requestAnimationFrame(() => dom.drawerBackdrop.classList.add("open"));
      }
    } else {
      dom.artifactDrawer.classList.remove("open");
      dom.artifactDrawer.setAttribute("aria-hidden", "true");
      if (dom.artifactResizer) dom.artifactResizer.hidden = true;
      dom.workspaceBody?.classList.remove("has-artifact-split");
      if (!dom.inspector.classList.contains("open")) {
        dom.drawerBackdrop.classList.remove("open");
        setTimeout(() => {
          if (!dom.drawerBackdrop.classList.contains("open")) dom.drawerBackdrop.hidden = true;
        }, 240);
      }
    }
  }

  async function runPythonSandbox(code) {
    if (!code?.trim()) return;
    if (dom.artifactPyOutput) dom.artifactPyOutput.hidden = false;
    if (dom.pyOutStatus) dom.pyOutStatus.textContent = "Python Sandbox çalışıyor...";
    if (dom.pyOutText) {
      dom.pyOutText.textContent = "";
      dom.pyOutText.classList.remove("has-err");
    }
    if (dom.pyOutImages) dom.pyOutImages.innerHTML = "";
    try {
      const res = await apiJson("/api/sandbox/python", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ code }),
      });
      const ok = Boolean(res.ok);
      if (dom.pyOutStatus) {
        dom.pyOutStatus.textContent = ok
          ? `Tamamlandı (${res.elapsed_sec}s · Çıkış: 0)`
          : `Hata (${res.elapsed_sec}s · Çıkış: ${res.returncode})`;
      }
      const combined = [res.stdout, res.stderr].filter(Boolean).join("\n").trim() || "(Çıktı üretilmedi)";
      if (dom.pyOutText) {
        dom.pyOutText.textContent = combined;
        dom.pyOutText.classList.toggle("has-err", !ok && Boolean(res.stderr));
      }
      if (dom.pyOutImages && Array.isArray(res.images) && res.images.length) {
        dom.pyOutImages.innerHTML = res.images
          .map((src) => `<img src="${src}" alt="Python Grafik Çıktısı" class="att-img-thumb" data-full-src="${src}" />`)
          .join("");
      }
    } catch (err) {
      if (dom.pyOutStatus) dom.pyOutStatus.textContent = "Sandbox Hatası";
      if (dom.pyOutText) {
        dom.pyOutText.textContent = err.message;
        dom.pyOutText.classList.add("has-err");
      }
    }
  }

  function setTemporaryMode(label, promptText = "", skillId = null) {
    state.tempModeLabel = label || "";
    state.tempPersonaPrompt = promptText || "";
    state.activeSkillId = skillId || null;
    if (dom.activeModeStrip && dom.activeModeLabel) {
      const show = Boolean(state.tempModeLabel);
      dom.activeModeStrip.hidden = !show;
      if (show) dom.activeModeLabel.textContent = `Mod: ${state.tempModeLabel}`;
    }
  }

  function clearTemporaryMode() {
    setTemporaryMode("", "", null);
    showToast("Varsayılan Genel Asistan moduna dönüldü", "ok", 1800);
  }

  /* =========================================================
     Slash (/) Quick Command & Skills Popover + Doc Export
     ========================================================= */
  function closeSlashMenu() {
    if (!dom.slashMenu) return;
    dom.slashMenu.hidden = true;
    state.slashItems = [];
    state.slashActiveIdx = 0;
  }

  function renderSlashMenu() {
    if (!dom.slashMenu) return;
    const val = dom.promptInput.value || "";
    if (!val.startsWith("/") || /\s/.test(val)) {
      closeSlashMenu();
      return;
    }
    const q = val.toLowerCase();
    const skillCmds = (state.skills || [])
      .filter((s) => s.enabled !== false)
      .map((s) => ({
        cmd: `/${s.slug}`,
        desc: s.description || s.name,
        tag: "Beceri",
        tone: "skill",
        icon: "spark",
        run: () => {
          setTemporaryMode(`Beceri: ${s.name}`, "", s.id);
          return "";
        },
      }));
    const combined = [...SLASH_COMMANDS, ...skillCmds];
    const items = combined.filter((c) => c.cmd.toLowerCase().includes(q) || c.desc.toLowerCase().includes(q));
    if (!items.length) {
      closeSlashMenu();
      return;
    }
    state.slashItems = items;
    state.slashActiveIdx = Math.min(state.slashActiveIdx, items.length - 1);
    dom.slashMenu.hidden = false;
    const getSlashIco = (key) => SVG_ICONS[key] || CMD_ICONS[key] || SVG_ICONS.spark;
    dom.slashMenu.innerHTML =
      `<div class="slash-menu-head"><span>Hızlı Komutlar &amp; Beceriler</span><span class="mono">↑↓ · Enter</span></div>` +
      items
        .map(
          (c, i) => `
      <button type="button" class="slash-item ${i === state.slashActiveIdx ? "active" : ""}" data-slash-idx="${i}">
        <span class="slash-item-left">
          <span class="slash-ico-box ${escHtml(c.tone || "")}" aria-hidden="true">${getSlashIco(c.icon)}</span>
          <span class="slash-text-col">
            <span class="slash-cmd mono">${escHtml(c.cmd)}</span>
            <span class="slash-desc">${escHtml(c.desc)}</span>
          </span>
        </span>
        <span class="slash-tag mono">${escHtml(c.tag)}</span>
      </button>`
        )
        .join("");
  }

  /* =========================================================
     Faz 5: Extensions (Plugins & Skills), Notes, Projects, TTS Speed
     ========================================================= */
  async function loadExtensions() {
    try {
      const data = await apiJson("/api/extensions");
      state.plugins = data.plugins || [];
      state.skills = data.skills || [];
      state.notes = data.notes || [];
      renderExtensionsUI(data.webhook_url || "");
    } catch (_) {}
  }

  function renderExtensionsUI(webhookUrl = null) {
    if (dom.extPluginsCount) {
      const onCnt = state.plugins.filter((p) => p.enabled).length;
      dom.extPluginsCount.textContent = `${onCnt} aktif`;
    }
    if (dom.extPluginsList) {
      dom.extPluginsList.innerHTML = state.plugins
        .map(
          (p) => `
        <div class="ext-card">
          <div class="ext-card-copy">
            <strong>${escHtml(p.name)}</strong>
            <span>${escHtml(p.description)}</span>
          </div>
          <label class="ios-switch sm">
            <input type="checkbox" data-plugin-id="${escHtml(p.id)}" ${p.enabled ? "checked" : ""} />
            <span class="ios-track"><span class="ios-thumb"></span></span>
          </label>
        </div>`
        )
        .join("");
    }
    const whPlugin = state.plugins.find((p) => p.id === "webhook_custom");
    if (dom.extWebhookRow) dom.extWebhookRow.hidden = !whPlugin?.enabled;
    if (dom.inpWebhookUrl && webhookUrl !== null) dom.inpWebhookUrl.value = webhookUrl;

    if (dom.extSkillsList) {
      dom.extSkillsList.innerHTML = state.skills.length
        ? state.skills
            .map(
              (s) => `
          <div class="ext-card">
            <div class="ext-card-copy">
              <strong>/${escHtml(s.slug)} · ${escHtml(s.name)}</strong>
              <span>${escHtml(s.description)}</span>
            </div>
            <div class="ext-card-right">
              <label class="ios-switch sm">
                <input type="checkbox" data-skill-toggle="${escHtml(s.id)}" ${s.enabled !== false ? "checked" : ""} />
                <span class="ios-track"><span class="ios-thumb"></span></span>
              </label>
              <button type="button" class="mem-del-btn" data-skill-del="${escHtml(s.id)}" title="Beceriyi Sil">${SVG_ICONS.xClose}</button>
            </div>
          </div>`
            )
            .join("")
        : `<div class="muted-empty">Henüz beceri bulunmuyor</div>`;
    }

    if (dom.extNotesCount) dom.extNotesCount.textContent = String(state.notes.length);
    if (dom.extNotesList) {
      dom.extNotesList.innerHTML = state.notes.length
        ? state.notes
            .map(
              (n) => `
          <div class="mem-item ${n.done ? "done" : ""}">
            <button type="button" class="note-item-check ${n.done ? "done" : ""}" data-note-toggle="${escHtml(n.id)}" aria-label="Tamamlandı">${n.done ? "✓" : ""}</button>
            <span>${escHtml(n.text)}</span>
            <button type="button" class="mem-del-btn" data-note-del="${escHtml(n.id)}" aria-label="Sil">${SVG_ICONS.xClose}</button>
          </div>`
            )
            .join("")
        : `<div class="muted-empty">Henüz not eklenmedi</div>`;
    }
  }

  async function loadProjects() {
    try {
      const data = await apiJson("/api/projects");
      state.projects = data.projects || [];
      renderProjectsUI();
    } catch (_) {}
  }

  function renderProjectsUI() {
    if (!dom.projectsList) return;
    const allRow = `
      <button type="button" class="prj-row ${!state.activeProjectId ? "active" : ""}" data-prj-id="">
        <span class="prj-left"><span class="prj-dot" style="background:var(--accent)"></span><span class="prj-name">Tüm Sohbetler</span></span>
      </button>`;
    const rows = state.projects
      .map(
        (p) => `
      <div class="prj-row ${state.activeProjectId === p.id ? "active" : ""}" data-prj-id="${escHtml(p.id)}" role="button" tabindex="0">
        <span class="prj-left"><span class="prj-dot" style="background:${escHtml(p.color || "#3b82f6")}"></span><span class="prj-name" title="${escHtml(p.name)}">${escHtml(p.name)}</span></span>
        <button type="button" class="lib-del-btn" data-prj-del="${escHtml(p.id)}" title="Projeyi Sil" aria-label="Sil">${SVG_ICONS.xClose}</button>
      </div>`
      )
      .join("");
    dom.projectsList.innerHTML = allRow + rows;
  }

  function setTtsSpeed(spd) {
    const val = [1, 1.25, 1.5].includes(Number(spd)) ? Number(spd) : 1;
    state.ttsSpeed = val;
    localStorage.setItem("yerelai_tts_speed", String(val));
    if (dom.audioEl) dom.audioEl.playbackRate = val;
    if (dom.lblTtsSpeed) dom.lblTtsSpeed.textContent = `${val.toFixed(val === 1 ? 1 : 2)}x`;
    $$(".tts-spd-btn", dom.ttsSpeedSeg || document).forEach((b) => b.classList.toggle("active", Number(b.dataset.speed) === val));
  }

  function applySlashCommand(idx) {
    const item = state.slashItems[idx];
    if (!item) return;
    closeSlashMenu();
    const nextVal = item.run();
    if (nextVal !== null && nextVal !== undefined) {
      dom.promptInput.value = nextVal;
      autoResizeTextarea();
      dom.promptInput.focus();
    } else {
      dom.promptInput.value = "";
      autoResizeTextarea();
    }
  }

  async function exportMessageDocument(msg, asPdf = false) {
    if (!msg?.content?.trim()) return;
    const kind = asPdf ? "pdf" : "docx";
    const titleBase = (dom.pageBreadcrumb.textContent || "YerelAI_Rapor").slice(0, 48);
    showToast(`${kind.toUpperCase()} dosyası hazırlanıyor...`, "ok", 1800);
    try {
      const res = await apiJson(`/api/export/${kind}`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ title: titleBase, content: msg.content }),
      });
      if (res?.url) {
        const a = document.createElement("a");
        a.href = res.url;
        a.download = res.filename || `yerelai_rapor.${kind}`;
        a.click();
        showToast(`${res.filename} indirildi`, "ok", 2600);
      }
    } catch (err) {
      showToast(`Belge oluşturulamadı: ${err.message}`, "err", 3600);
    }
  }

  /* =========================================================
     Command Palette (Ctrl K)
     ========================================================= */
  function buildCmdPaletteItems(query) {
    const q = (query || "").trim().toLowerCase();
    const actions = [
      { id: "new_chat", group: "Hızlı Eylemler", label: "Yeni Sohbet Başlat", hint: "Temiz tuval", icon: CMD_ICONS.plus, run: () => startNewChat() },
      { id: "toggle_theme", group: "Hızlı Eylemler", label: "Tema Değiştir (Obsidian / Seramik)", hint: "Görünüm", icon: CMD_ICONS.theme, run: () => toggleTheme() },
      { id: "open_settings", group: "Hızlı Eylemler", label: "Ayarlar & Colab Çekmecesini Aç", hint: "Panel", icon: CMD_ICONS.sliders, run: () => setInspectorOpen(true) },
      { id: "toggle_web", group: "Hızlı Eylemler", label: state.webSearch ? "Canlı Web Araştırmasını Kapat" : "Canlı Web Araştırmasını Aç", hint: "Araştır", icon: CMD_ICONS.globe, run: () => syncWebSearchUI(!state.webSearch) },
      { id: "toggle_rag", group: "Hızlı Eylemler", label: state.useLibrary ? "Yerel Kütüphane (RAG) Kapat" : "Yerel Kütüphane (RAG) Aç", hint: "0 VRAM", icon: SVG_ICONS.file, run: () => syncRagToggleUI(!state.useLibrary) },
      ...PERSONAS.map((p) => ({
        id: `persona_${p.id}`,
        group: "Uzman Personalar",
        label: `Persona: ${p.name}`,
        hint: "Rol",
        icon: CMD_ICONS.sliders,
        run: () => applyPersona(p.id),
      })),
      { id: "toggle_sidebar", group: "Hızlı Eylemler", label: "Kenar Çubuğunu Daralt / Genişlet", hint: "Odak modu", icon: CMD_ICONS.sidebar, run: () => toggleSidebarCollapse() },
      { id: "export_md", group: "Hızlı Eylemler", label: "Aktif Sohbeti Markdown (.md) İndir", hint: "Dışa aktar", icon: SVG_ICONS.download, run: () => exportActiveChatMarkdown() },
      { id: "export_pdf", group: "Hızlı Eylemler", label: "Aktif Sohbeti Yazdır / PDF Kaydet", hint: "PDF", icon: CMD_ICONS.chat, run: () => exportActiveChatPdf() },
      { id: "gpu_load", group: "GPU Motoru", label: "Modeli GPU VRAM'e Yükle", hint: "GGUF Turbo", icon: CMD_ICONS.bolt, run: () => loadModelOnGpu() },
      { id: "gpu_unload", group: "GPU Motoru", label: "GPU VRAM'i Boşalt", hint: "Bellek temizle", icon: CMD_ICONS.power, run: () => unloadModelFromGpu() },
      ...state.models.map((m) => ({
        id: `model_${m.id}`,
        group: "Modeller",
        label: `${m.name} Seç`,
        hint: m.cached_locally ? "Hazır" : "İndirilecek",
        icon: CMD_ICONS.cube,
        run: () => selectModel(m.id),
      })),
      ...state.sessions.slice(0, 12).map((s) => ({
        id: `sess_${s.id}`,
        group: "Sohbet Geçmişi",
        label: s.title || "Sohbet",
        hint: "Aç",
        icon: CMD_ICONS.chat,
        run: () => openSession(s.id),
      })),
    ];
    return q ? actions.filter((a) => a.label.toLowerCase().includes(q) || a.group.toLowerCase().includes(q)) : actions;
  }

  function renderCmdPalette() {
    const items = buildCmdPaletteItems(dom.cmdInput.value);
    state.cmdItems = items;
    state.cmdActiveIdx = Math.min(state.cmdActiveIdx, Math.max(0, items.length - 1));
    if (!items.length) {
      dom.cmdResults.innerHTML = `<div class="muted-empty">Eşleşen komut veya sohbet bulunamadı.</div>`;
      return;
    }
    let lastGroup = "";
    const parts = [];
    items.forEach((it, idx) => {
      if (it.group !== lastGroup) {
        lastGroup = it.group;
        parts.push(`<div class="cmd-group-label">${escHtml(it.group)}</div>`);
      }
      parts.push(
        `<button type="button" class="cmd-item ${idx === state.cmdActiveIdx ? "active" : ""}" data-cmd-idx="${idx}">
          <span class="cmd-item-left"><span class="cmd-ico" aria-hidden="true">${it.icon || ""}</span><span>${escHtml(it.label)}</span></span>
          <span class="cmd-item-hint mono">${escHtml(it.hint)}</span>
        </button>`
      );
    });
    dom.cmdResults.innerHTML = parts.join("");
  }

  function openCmdPalette() {
    closeAllPopovers();
    dom.cmdPaletteModal.hidden = false;
    dom.cmdInput.value = "";
    state.cmdActiveIdx = 0;
    renderCmdPalette();
    requestAnimationFrame(() => dom.cmdInput.focus());
  }

  function closeCmdPalette() {
    dom.cmdPaletteModal.hidden = true;
  }

  function toggleSidebarCollapse() {
    const collapsed = dom.studioShell.classList.toggle("sidebar-collapsed");
    localStorage.setItem("yerelai_sidebar_collapsed", collapsed ? "1" : "0");
    dom.btnCollapseSidebar?.classList.toggle("active", collapsed);
  }

  function updateScrollBottomPill() {
    const el = dom.chatScroll;
    const distFromBottom = el.scrollHeight - el.scrollTop - el.clientHeight;
    const show = distFromBottom > 180 && state.messages.length > 0;
    if (show) {
      dom.btnScrollBottom.hidden = false;
      requestAnimationFrame(() => dom.btnScrollBottom.classList.add("visible"));
    } else {
      dom.btnScrollBottom.classList.remove("visible");
      setTimeout(() => {
        if (!dom.btnScrollBottom.classList.contains("visible")) dom.btnScrollBottom.hidden = true;
      }, 220);
    }
  }

  function wireEvents() {
    const setMobileSidebarOpen = (open) => {
      const isOpen = Boolean(open);
      dom.sidebar?.classList.toggle("open", isOpen);
      dom.sidebar?.classList.toggle("mobile-open", isOpen);
      if (dom.drawerBackdrop) {
        if (isOpen) {
          dom.drawerBackdrop.hidden = false;
          requestAnimationFrame(() => dom.drawerBackdrop.classList.add("open"));
        } else {
          dom.drawerBackdrop.classList.remove("open");
          setTimeout(() => {
            if (!dom.drawerBackdrop.classList.contains("open")) dom.drawerBackdrop.hidden = true;
          }, 220);
        }
      }
    };

    dom.btnThemeToggle.addEventListener("click", toggleTheme);
    dom.btnNewChat.addEventListener("click", () => {
      setMobileSidebarOpen(false);
      startNewChat();
    });
    dom.btnMobileSidebar.addEventListener("click", () => {
      const willOpen = !dom.sidebar.classList.contains("open");
      setMobileSidebarOpen(willOpen);
    });
    dom.btnMobileSidebarClose?.addEventListener("click", () => setMobileSidebarOpen(false));
    dom.btnCollapseSidebar?.addEventListener("click", toggleSidebarCollapse);
    dom.btnOpenCmd?.addEventListener("click", openCmdPalette);
    dom.btnToggleInspector.addEventListener("click", () => {
      setMobileSidebarOpen(false);
      setInspectorOpen(!dom.inspector.classList.contains("open"));
    });
    dom.btnCloseInspector.addEventListener("click", () => setInspectorOpen(false));
    dom.btnArtifactClose?.addEventListener("click", () => setArtifactOpen(false));
    dom.drawerBackdrop.addEventListener("click", () => {
      setMobileSidebarOpen(false);
      setInspectorOpen(false);
      setArtifactOpen(false);
    });

    // Swipe-left gesture to close mobile sidebar drawer smoothly
    let sbTouchStartX = 0;
    dom.sidebar?.addEventListener("touchstart", (e) => {
      if (e.touches?.length) sbTouchStartX = e.touches[0].clientX;
    }, { passive: true });
    dom.sidebar?.addEventListener("touchend", (e) => {
      if (!dom.sidebar.classList.contains("open") || !e.changedTouches?.length) return;
      if (sbTouchStartX - e.changedTouches[0].clientX > 55) setMobileSidebarOpen(false);
    }, { passive: true });

    // Unified "+" Add & Tools Popover
    dom.btnComposerTools?.addEventListener("click", (e) => {
      e.stopPropagation();
      const willOpen = Boolean(dom.composerToolsMenu?.hidden);
      closeAllPopovers(willOpen ? "tools" : null);
      if (dom.composerToolsMenu) {
        dom.composerToolsMenu.hidden = !willOpen;
        dom.btnComposerTools.setAttribute("aria-expanded", String(willOpen));
      }
    });
    dom.composerToolsMenu?.addEventListener("click", (e) => {
      if (e.target.closest(".ctm-item")) {
        dom.composerToolsMenu.hidden = true;
        dom.btnComposerTools?.setAttribute("aria-expanded", "false");
      }
    });
    dom.chipWebActive?.addEventListener("click", () => {
      syncWebSearchUI(false);
      showToast("Web araştırması kapatıldı", "ok", 1600);
    });
    dom.chipRagActive?.addEventListener("click", () => {
      syncRagToggleUI(false);
      showToast("Bilgi Kütüphanesi (RAG) kapatıldı", "ok", 1600);
    });

    dom.btnInspExportDpo?.addEventListener("click", () => {
      const a = document.createElement("a");
      a.href = "/api/dataset/export?fmt=dpo";
      a.download = "";
      a.click();
      showToast("DPO tercih çiftleri (JSONL) indiriliyor", "ok", 2200);
    });

    dom.chatScroll.addEventListener("scroll", updateScrollBottomPill, { passive: true });
    dom.btnScrollBottom?.addEventListener("click", () => scrollToBottom(true));

    // Command Palette events
    dom.cmdInput?.addEventListener("input", () => {
      state.cmdActiveIdx = 0;
      renderCmdPalette();
    });
    dom.cmdInput?.addEventListener("keydown", (e) => {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        state.cmdActiveIdx = Math.min(state.cmdItems.length - 1, state.cmdActiveIdx + 1);
        renderCmdPalette();
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        state.cmdActiveIdx = Math.max(0, state.cmdActiveIdx - 1);
        renderCmdPalette();
      } else if (e.key === "Enter") {
        e.preventDefault();
        const chosen = state.cmdItems[state.cmdActiveIdx];
        if (chosen) {
          closeCmdPalette();
          chosen.run();
        }
      }
    });
    dom.cmdResults?.addEventListener("click", (e) => {
      const btn = e.target.closest(".cmd-item");
      if (!btn) return;
      const chosen = state.cmdItems[Number(btn.dataset.cmdIdx)];
      if (chosen) {
        closeCmdPalette();
        chosen.run();
      }
    });
    dom.cmdPaletteModal?.addEventListener("click", (e) => {
      if (e.target === dom.cmdPaletteModal) closeCmdPalette();
    });

    // Artifact actions (Split-Pane Tabs, Viewports, Draggable Resizer, Download, New Tab)
    dom.artTabPreview?.addEventListener("click", () => setArtifactTab("preview"));
    dom.artTabCode?.addEventListener("click", () => setArtifactTab("code"));
    dom.artTabDiff?.addEventListener("click", () => setArtifactTab("diff"));
    dom.artVpBar?.addEventListener("click", (e) => {
      const btn = e.target.closest(".art-vp-btn");
      if (btn) setArtifactViewport(btn.dataset.vp);
    });
    if (dom.artifactResizer && dom.workspaceBody) {
      dom.artifactResizer.addEventListener("pointerdown", (e) => {
        e.preventDefault();
        dom.artifactResizer.classList.add("dragging");
        dom.workspaceBody.classList.add("is-resizing");
        if (dom.artifactIframe) dom.artifactIframe.style.pointerEvents = "none";
        const onMove = (mv) => {
          const rect = dom.workspaceBody.getBoundingClientRect();
          const pct = Math.min(70, Math.max(30, ((rect.right - mv.clientX) / Math.max(300, rect.width)) * 100));
          dom.workspaceBody.style.setProperty("--art-width", `${pct.toFixed(1)}%`);
        };
        const onUp = () => {
          dom.artifactResizer.classList.remove("dragging");
          dom.workspaceBody.classList.remove("is-resizing");
          if (dom.artifactIframe) dom.artifactIframe.style.pointerEvents = "";
          window.removeEventListener("pointermove", onMove);
          window.removeEventListener("pointerup", onUp);
        };
        window.addEventListener("pointermove", onMove);
        window.addEventListener("pointerup", onUp);
      });
    }
    dom.btnArtifactCopy?.addEventListener("click", async () => {
      if (!state.activeArtifact?.code) return;
      await navigator.clipboard.writeText(state.activeArtifact.code);
      showToast("Kod panoya kopyalandı", "ok", 1800);
    });
    dom.btnArtifactRun?.addEventListener("click", () => {
      if (state.activeArtifact?.code) runPythonSandbox(state.activeArtifact.code);
    });
    dom.btnPyOutClose?.addEventListener("click", () => {
      if (dom.artifactPyOutput) dom.artifactPyOutput.hidden = true;
    });
    dom.pyOutImages?.addEventListener("click", (e) => {
      const img = e.target.closest("img");
      if (img) {
        dom.lightboxImg.src = img.src;
        dom.lightboxModal.hidden = false;
      }
    });
    dom.btnClearMode?.addEventListener("click", clearTemporaryMode);
    dom.btnArtifactDownload?.addEventListener("click", () => {
      if (!state.activeArtifact) return;
      const ext = state.activeArtifact.lang === "svg" ? "svg" : "html";
      const blob = new Blob([state.activeArtifact.code], { type: "text/plain;charset=utf-8" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = state.activeArtifact.filename || `yerelai_artifact_${Date.now()}.${ext}`;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    });
    dom.btnArtifactSaveDisk?.addEventListener("click", async () => {
      const wsPath = state.activeArtifact?.workspacePath;
      if (!wsPath) return;
      try {
        await apiJson("/api/workspace/write", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: wsPath, content: state.activeArtifact.code || "" }),
        });
        state.activeArtifact.baseCode = state.activeArtifact.code || "";
        state.activeArtifact.edited = false;
        renderArtifactVersionBar();
        showToast(`Diske kaydedildi: ${wsPath}`, "ok", 2400);
      } catch (err) {
        showToast(`Kaydetme hatası: ${err.message}`, "err", 3200);
      }
    });

    dom.btnArtifactZip?.addEventListener("click", async () => {
      const files = collectSessionCodeFiles();
      if (!files.length) return showToast("İndirilecek kod dosyası bulunamadı", "warn", 2000);
      if (state.activeArtifact?.edited && state.activeArtifact.filename) {
        const idx = files.findIndex((f) => f.filename === state.activeArtifact.filename);
        if (idx >= 0) files[idx].code = state.activeArtifact.code;
        else files.push({ filename: state.activeArtifact.filename, code: state.activeArtifact.code });
      }
      try {
        const res = await apiJson("/api/export/zip", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            title: dom.pageBreadcrumb?.textContent || "YerelAI_Proje",
            files: files.map((f) => ({ filename: f.filename, content: f.code })),
          }),
        });
        const a = document.createElement("a");
        a.href = res.url;
        a.download = res.filename;
        a.click();
        showToast(`${res.file_count} dosya ZIP paketi olarak indirildi`, "ok", 2600);
      } catch (err) {
        showToast(`ZIP hatası: ${err.message}`, "err", 3200);
      }
    });

    // Live Editable Code Editor (Tab indent, Ctrl+S instant preview, debounced live sync)
    let liveEditTimer = null;
    const syncLiveEditor = (immediate = false) => {
      if (!state.activeArtifact || !dom.artifactCodeEditor) return;
      const val = dom.artifactCodeEditor.value;
      state.activeArtifact.code = val;
      state.activeArtifact.edited = true;
      updateEditorLineNumbers(val);
      renderArtifactVersionBar();
      const applyPreview = () => {
        if (state.activeArtifact?.canPreview && dom.artifactIframe) {
          dom.artifactIframe.srcdoc = buildArtifactPreviewHtml(state.activeArtifact.code, state.activeArtifact.lang);
        }
      };
      clearTimeout(liveEditTimer);
      if (immediate) applyPreview();
      else liveEditTimer = setTimeout(applyPreview, 350);
    };
    dom.artifactCodeEditor?.addEventListener("input", () => syncLiveEditor(false));
    dom.artifactCodeEditor?.addEventListener("scroll", () => {
      if (dom.artifactLineNums) dom.artifactLineNums.scrollTop = dom.artifactCodeEditor.scrollTop;
    });
    dom.artifactCodeEditor?.addEventListener("keydown", (e) => {
      if (e.key === "Tab") {
        e.preventDefault();
        const el = dom.artifactCodeEditor;
        const s = el.selectionStart;
        const end = el.selectionEnd;
        el.value = el.value.slice(0, s) + "  " + el.value.slice(end);
        el.selectionStart = el.selectionEnd = s + 2;
        syncLiveEditor(false);
      } else if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "s") {
        e.preventDefault();
        syncLiveEditor(true);
        showToast("Canlı kod değişikliği önizlemeye uygulandı", "ok", 1600);
      }
    });
    dom.artifactVerPills?.addEventListener("click", (e) => {
      const btn = e.target.closest("[data-art-ver]");
      if (!btn || !state.activeArtifact) return;
      const idx = Number(btn.dataset.artVer);
      const ver = state.artifactVersions?.[idx];
      if (!ver) return;
      state.activeArtifact.verIdx = idx;
      state.activeArtifact.code = ver.code;
      state.activeArtifact.edited = false;
      if (dom.artifactCodeEditor) {
        dom.artifactCodeEditor.value = ver.code;
        updateEditorLineNumbers(ver.code);
      }
      if (state.activeArtifact.canPreview && dom.artifactIframe) {
        dom.artifactIframe.srcdoc = buildArtifactPreviewHtml(ver.code, state.activeArtifact.lang);
      }
      renderArtifactVersionBar();
      if (state.artTab === "diff") renderArtifactDiff();
    });

    dom.btnArtifactNewtab?.addEventListener("click", () => {
      if (!state.activeArtifact) return;
      const w = window.open("", "_blank");
      if (w) {
        w.document.open();
        w.document.write(state.activeArtifact.code);
        w.document.close();
      }
    });

    dom.sessionSearch.addEventListener("input", handleSessionSearchInput);
    document.addEventListener("keydown", (e) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        if (dom.cmdPaletteModal.hidden) openCmdPalette();
        else closeCmdPalette();
      } else if ((e.ctrlKey || e.metaKey) && e.key === ",") {
        e.preventDefault();
        setInspectorOpen(Boolean(dom.inspector?.hidden));
      } else if ((e.ctrlKey || e.metaKey) && !e.shiftKey && e.key.toLowerCase() === "n") {
        if (window.yerelDesktop) {
          e.preventDefault();
          setInspectorOpen(false);
          startNewChat();
          dom.promptInput?.focus();
        }
      } else if (e.key === "Escape") {
        closeAllPopovers();
        closeCmdPalette();
        setInspectorOpen(false);
        setArtifactOpen(false);
        dom.datasetModal.hidden = true;
        dom.lightboxModal.hidden = true;
        if (dom.windowPickerModal) dom.windowPickerModal.hidden = true;
        if (dom.gitStatusModal) dom.gitStatusModal.hidden = true;
        if (dom.dislikeModal) dom.dislikeModal.hidden = true;
        if (dom.sourcesModal) dom.sourcesModal.hidden = true;
        if (dom.msgMoreMenu) dom.msgMoreMenu.hidden = true;
        if (dom.chatOutputsPopover) dom.chatOutputsPopover.hidden = true;
        closeRenameModal();
        closeDeleteConfirm();
        closeSessionCtxMenu();
        stopCosmicParticles();
      }
    });
    document.addEventListener("click", (e) => {
      closeAllPopovers();
      closeSessionCtxMenu();
      stopCosmicParticles();
      if (dom.msgMoreMenu && !dom.msgMoreMenu.hidden && !dom.msgMoreMenu.contains(e.target) && !e.target.closest(".btn-msg-more")) {
        dom.msgMoreMenu.hidden = true;
      }
      if (dom.chatOutputsPopover && !dom.chatOutputsPopover.hidden && !dom.chatOutputsPopover.contains(e.target) && !e.target.closest("#btn-chat-outputs")) {
        dom.chatOutputsPopover.hidden = true;
      }
      $$(".web-sources-pill-wrap[open]").forEach((det) => {
        if (!det.contains(e.target)) det.removeAttribute("open");
      });
    });

    dom.btnNotifBell.addEventListener("click", (e) => {
      e.stopPropagation();
      const willOpen = !dom.notifPopover.classList.contains("open");
      closeAllPopovers(willOpen ? "notif" : null);
      if (willOpen) {
        dom.notifPopover.hidden = false;
        requestAnimationFrame(() => dom.notifPopover.classList.add("open"));
        state.unreadNotifs = 0;
        renderNotifications();
      } else closeAllPopovers();
    });
    dom.notifPopover.addEventListener("click", (e) => {
      e.stopPropagation();
      const dis = e.target.closest("[data-dismiss-nid]");
      if (dis) {
        const nid = dis.dataset.dismissNid;
        const itemEl = dis.closest(".notif-item");
        if (itemEl) itemEl.classList.add("is-clearing");
        setTimeout(() => {
          state.notifications = state.notifications.filter((n) => n.id !== nid);
          renderNotifications();
        }, 280);
      }
    });
    dom.btnNotifClear.addEventListener("click", clearNotificationsAnimated);
    dom.btnExportMd?.addEventListener("click", exportActiveChatMarkdown);
    dom.btnExportPdf?.addEventListener("click", exportActiveChatPdf);

    const dlJsonl = () => (window.location.href = "/api/dataset/export");
    const dlNotebook = () => (window.location.href = "/api/colab/notebook");
    dom.btnExportDataset.addEventListener("click", dlJsonl);
    dom.btnDownloadColab.addEventListener("click", dlNotebook);
    dom.btnInspExportDs.addEventListener("click", dlJsonl);
    dom.btnInspColabNb.addEventListener("click", dlNotebook);

    dom.btnGpuLoad.addEventListener("click", loadModelOnGpu);
    dom.btnGpuUnload.addEventListener("click", unloadModelFromGpu);
    dom.btnGpuDlCancel?.addEventListener("click", (e) => {
      e.stopPropagation();
      cancelModelDownload();
    });

    dom.sessionList.addEventListener("click", (e) => {
      const menuBtn = e.target.closest(".btn-sess-menu");
      if (menuBtn) {
        e.stopPropagation();
        return openSessionCtxMenu(menuBtn.dataset.sid, menuBtn.closest(".hrow"), menuBtn);
      }
      const row = e.target.closest(".hrow");
      if (row) openSession(row.dataset.sid);
    });

    dom.sessionCtxMenu?.addEventListener("click", (e) => {
      e.stopPropagation();
      const item = e.target.closest("[data-sess-act]");
      if (!item) return;
      const act = item.dataset.sessAct;
      const sid = state.ctxMenuSid;
      const rowEl = state.ctxMenuRow;
      closeSessionCtxMenu();
      if (!sid) return;
      if (act === "pin") togglePinSession(sid);
      else if (act === "rename") startRenameSession(sid, rowEl);
      else if (act === "delete") requestDeleteSession(sid, rowEl);
    });

    dom.starterPillsRow?.addEventListener("click", (e) => {
      const pill = e.target.closest(".starter-pill");
      if (!pill) return;
      const act = pill.dataset.action;
      if (act === "excel") dom.fileInput?.click();
      else if (act === "voice") startRecording();
      else if (act === "code") {
        updateEffortPill("high", true);
        dom.promptInput.value = "Python ile hızlı bir veri analiz scripti yaz: ";
        autoResizeTextarea();
        dom.promptInput.focus();
      } else if (act === "web") {
        syncWebSearchUI(true);
        dom.promptInput.value = "Bugün teknoloji ve yapay zeka gündemindeki en önemli gelişmeleri özetle.";
        autoResizeTextarea();
        dom.promptInput.focus();
      }
    });

    dom.btnTempChat?.addEventListener("click", () => {
      state.isTemporaryChat = !state.isTemporaryChat;
      dom.btnTempChat.classList.toggle("active", state.isTemporaryChat);
      dom.btnTempChat.setAttribute("aria-pressed", String(state.isTemporaryChat));
      if (state.isTemporaryChat) {
        startNewChat();
        dom.pageBreadcrumb.textContent = "Geçici Sohbet";
        showToast("Geçici sohbet modu açık — geçmişe kaydedilmez", "ok", 2200);
      } else {
        startNewChat();
        showToast("Normal sohbet moduna dönüldü", "ok", 1800);
      }
    });

    dom.btnTempPersonalize?.addEventListener("click", () => {
      state.temporaryPersonalized = !state.temporaryPersonalized;
      dom.btnTempPersonalize.classList.toggle("active", state.temporaryPersonalized);
      dom.btnTempPersonalize.setAttribute("aria-pressed", String(state.temporaryPersonalized));
      showToast(state.temporaryPersonalized ? "Geçici sohbette kalıcı hafıza aktif" : "Geçici sohbette hafıza kapalı", "ok", 1800);
    });

    dom.btnChatOutputs?.addEventListener("click", (e) => {
      e.stopPropagation();
      if (!dom.chatOutputsPopover) return;
      const willOpen = dom.chatOutputsPopover.hidden;
      closeAllPopovers();
      dom.chatOutputsPopover.hidden = !willOpen;
      if (willOpen) renderSessionFiles();
    });
    dom.btnChatOutputsClose?.addEventListener("click", () => {
      if (dom.chatOutputsPopover) dom.chatOutputsPopover.hidden = true;
    });

    dom.btnCtxCompactNow?.addEventListener("click", runManualCompact);
    dom.ctxMeterPill?.addEventListener("click", () => {
      if (state.messages.length >= 4) runManualCompact();
      else showToast("Sohbet bağlamı şu an oldukça ferah", "ok", 1800);
    });

    dom.btnSourcesModalClose?.addEventListener("click", () => { if (dom.sourcesModal) dom.sourcesModal.hidden = true; });
    dom.sourcesModal?.addEventListener("click", (e) => { if (e.target === dom.sourcesModal) dom.sourcesModal.hidden = true; });

    dom.btnActorChip?.addEventListener("click", () => {
      if (!dom.pinLockOverlay) return;
      dom.pinLockOverlay.hidden = false;
      if (dom.btnLoginClose) dom.btnLoginClose.hidden = false;
      setTimeout(() => dom.inpLoginUsername?.focus(), 60);
    });
    dom.btnLoginClose?.addEventListener("click", () => {
      if (dom.pinLockOverlay) dom.pinLockOverlay.hidden = true;
    });
    dom.btnGuestContinue?.addEventListener("click", () => {
      if (dom.pinLockOverlay) dom.pinLockOverlay.hidden = true;
    });

    dom.btnComposerPicker.addEventListener("click", (e) => {
      e.stopPropagation();
      const willOpen = !dom.composerPopover.classList.contains("open");
      closeAllPopovers(willOpen ? "composer" : null);
      if (willOpen) {
        dom.composerPopover.hidden = false;
        dom.btnComposerPicker.classList.add("is-open");
        dom.btnComposerPicker.setAttribute("aria-expanded", "true");
        requestAnimationFrame(() => {
          dom.composerPopover.classList.add("open");
          updateEffortPill(state.thinkingEffort, false);
        });
      } else {
        closeAllPopovers();
        stopCosmicParticles();
      }
    });
    dom.composerPopover.addEventListener("click", (e) => e.stopPropagation());
    initThinkingSlider();
    dom.composerModelList.addEventListener("click", (e) => {
      const cancelBtn = e.target.closest('[data-dl-action="cancel"]');
      if (cancelBtn) {
        e.stopPropagation();
        cancelModelDownload();
        return;
      }
      const row = e.target.closest(".vp-row");
      if (!row) return;
      const mid = row.dataset.modelId;
      const modelObj = state.models.find((m) => m.id === mid);
      if (modelObj && !modelObj.cached_locally) {
        if (!state.download?.active) startModelDownload(mid);
        return;
      }
      selectModel(mid);
      closeAllPopovers();
    });

    dom.btnWebToggle.addEventListener("click", () => {
      syncWebSearchUI(!state.webSearch);
      showToast(state.webSearch ? "Web araştırması aktif" : "Web araştırması kapatıldı", "ok", 1800);
    });
    dom.swWebSearch.addEventListener("change", () => syncWebSearchUI(dom.swWebSearch.checked));

    dom.btnRagToggle?.addEventListener("click", () => {
      syncRagToggleUI(!state.useLibrary);
      showToast(state.useLibrary ? "Yerel PDF kütüphanesi (RAG) aktif" : "Yerel kütüphane kapatıldı", "ok", 1800);
    });
    dom.btnLibraryUpload?.addEventListener("click", () => dom.libraryFileInput?.click());
    dom.libraryFileInput?.addEventListener("change", () => {
      const f = dom.libraryFileInput.files?.[0];
      if (f) uploadLibraryFile(f);
      dom.libraryFileInput.value = "";
    });
    dom.libraryDocsList?.addEventListener("click", (e) => {
      const del = e.target.closest("[data-lib-del]");
      if (del) deleteLibraryDoc(del.dataset.libDel);
    });

    dom.btnHandsFree?.addEventListener("click", () => {
      state.handsFree = !state.handsFree;
      dom.btnHandsFree.classList.toggle("active", state.handsFree);
      dom.btnHandsFree.setAttribute("aria-pressed", String(state.handsFree));
      if (state.handsFree) {
        showToast("Eller Serbest Sesli Sohbet açıldı — konuşun, durduğunuzda otomatik gönderilir", "ok", 3400);
        if (!state.isRecording && !state.isGenerating) startRecording();
      } else {
        showToast("Eller Serbest mod kapatıldı", "ok", 1800);
        if (state.isRecording) finishRecording(false);
        stopSpeaking();
      }
    });

    dom.personaGrid?.addEventListener("click", (e) => {
      const chip = e.target.closest(".persona-chip");
      if (chip) applyPersona(chip.dataset.personaId);
    });

    dom.btnRenameClose?.addEventListener("click", closeRenameModal);
    dom.btnRenameCancel?.addEventListener("click", closeRenameModal);
    dom.btnRenameSave?.addEventListener("click", commitRenameSession);
    dom.renameSessionModal?.addEventListener("click", (e) => {
      if (e.target === dom.renameSessionModal) closeRenameModal();
    });
    dom.renameSessionInput?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); commitRenameSession(); }
      else if (e.key === "Escape") { e.preventDefault(); closeRenameModal(); }
    });

    dom.btnConfirmDelCancel?.addEventListener("click", closeDeleteConfirm);
    dom.confirmDeleteModal?.addEventListener("click", (e) => {
      if (e.target === dom.confirmDeleteModal) closeDeleteConfirm();
    });
    dom.btnConfirmDelOk?.addEventListener("click", () => {
      const sid = state.pendingDeleteSid;
      const rowEl = state.pendingDeleteRow;
      closeDeleteConfirm();
      if (sid) deleteSession(sid, rowEl);
    });

    dom.promptInput.addEventListener("input", () => {
      autoResizeTextarea();
      state.slashActiveIdx = 0;
      renderSlashMenu();
    });
    dom.promptInput.addEventListener("paste", (e) => {
      const files = e.clipboardData?.files;
      if (files && files.length > 0) {
        e.preventDefault();
        uploadFiles(files);
      }
    });
    dom.promptInput.addEventListener("keydown", (e) => {
      if (dom.slashMenu && !dom.slashMenu.hidden && state.slashItems.length) {
        if (e.key === "ArrowDown") {
          e.preventDefault();
          state.slashActiveIdx = (state.slashActiveIdx + 1) % state.slashItems.length;
          renderSlashMenu();
          return;
        }
        if (e.key === "ArrowUp") {
          e.preventDefault();
          state.slashActiveIdx = (state.slashActiveIdx - 1 + state.slashItems.length) % state.slashItems.length;
          renderSlashMenu();
          return;
        }
        if (e.key === "Enter" || e.key === "Tab") {
          e.preventDefault();
          applySlashCommand(state.slashActiveIdx);
          return;
        }
        if (e.key === "Escape") {
          e.preventDefault();
          closeSlashMenu();
          return;
        }
      }
      const sendMode = localStorage.getItem("yerelai_send_mode") || "enter";
      const shouldSend = sendMode === "ctrl_enter" ? (e.key === "Enter" && (e.ctrlKey || e.metaKey)) : (e.key === "Enter" && !e.shiftKey);
      if (shouldSend) {
        e.preventDefault();
        sendMessage();
      }
    });
    dom.slashMenu?.addEventListener("click", (e) => {
      const btn = e.target.closest(".slash-item");
      if (btn) applySlashCommand(Number(btn.dataset.slashIdx));
    });
    dom.btnSend.addEventListener("click", () => sendMessage());
    dom.btnStop.addEventListener("click", stopGeneration);

    dom.btnAttach.addEventListener("click", () => dom.fileInput.click());
    dom.fileInput.addEventListener("change", () => {
      uploadFiles(dom.fileInput.files);
      dom.fileInput.value = "";
    });
    dom.pendingAttachments.addEventListener("click", (e) => {
      const btn = e.target.closest("button[data-att-idx]");
      if (btn) {
        e.stopPropagation();
        state.pendingAttachments.splice(Number(btn.dataset.attIdx), 1);
        renderPendingAttachments();
        renderSessionFiles();
        return;
      }
      const thumb = e.target.closest(".att-thumb-card");
      if (thumb?.dataset.fullSrc) {
        dom.lightboxImg.src = thumb.dataset.fullSrc;
        dom.lightboxModal.hidden = false;
      }
    });

    let dragDepth = 0;
    dom.dropZone.addEventListener("dragenter", (e) => {
      e.preventDefault();
      dragDepth += 1;
      dom.dragOverlay.hidden = false;
    });
    dom.dropZone.addEventListener("dragover", (e) => e.preventDefault());
    dom.dropZone.addEventListener("dragleave", (e) => {
      e.preventDefault();
      dragDepth = Math.max(0, dragDepth - 1);
      if (dragDepth === 0) dom.dragOverlay.hidden = true;
    });
    dom.dropZone.addEventListener("drop", (e) => {
      e.preventDefault();
      dragDepth = 0;
      dom.dragOverlay.hidden = true;
      if (e.dataTransfer?.files?.length) uploadFiles(e.dataTransfer.files);
    });

    dom.btnMic.addEventListener("click", () => (state.isRecording ? finishRecording(true) : startRecording()));
    dom.btnRecStop.addEventListener("click", () => finishRecording(true));
    dom.btnRecCancel.addEventListener("click", () => finishRecording(false));

    $$(".insp-tab").forEach((tab) => {
      tab.addEventListener("click", () => {
        const target = tab.dataset.insp;
        $$(".insp-tab").forEach((t) => t.classList.toggle("active", t === tab));
        $("#insp-settings").hidden = target !== "settings";
        const extPane = $("#insp-extensions");
        if (extPane) extPane.hidden = target !== "extensions";
        $("#insp-colab").hidden = target !== "colab";
      });
    });

    // TTS Speed Selector
    dom.ttsSpeedSeg?.addEventListener("click", (e) => {
      const btn = e.target.closest(".tts-spd-btn");
      if (btn) setTtsSpeed(Number(btn.dataset.speed));
    });

    // Extensions (Plugins, Skills, Notes) Events
    dom.extPluginsList?.addEventListener("change", async (e) => {
      const cb = e.target.closest("input[data-plugin-id]");
      if (!cb) return;
      try {
        const res = await apiJson("/api/extensions/plugin", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: cb.dataset.pluginId, enabled: cb.checked, webhook_url: dom.inpWebhookUrl?.value }),
        });
        state.plugins = res.plugins || [];
        renderExtensionsUI(res.webhook_url || "");
        showToast("Eklenti güncellendi", "ok", 1800);
      } catch (err) {
        showToast(err.message, "err");
      }
    });
    dom.btnWebhookTest?.addEventListener("click", async () => {
      const url = (dom.inpWebhookUrl?.value || "").trim();
      try {
        await apiJson("/api/extensions/plugin", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ id: "webhook_custom", enabled: true, webhook_url: url }),
        });
        const r = await apiJson("/api/extensions/webhook/test", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ url }),
        });
        showToast(`Webhook bağlantısı başarılı (HTTP ${r.status_code})`, "ok", 2600);
      } catch (err) {
        showToast(err.message, "err", 3600);
      }
    });
    dom.btnImportSkill?.addEventListener("click", () => dom.skillFileInput?.click());
    dom.skillFileInput?.addEventListener("change", async () => {
      const f = dom.skillFileInput.files?.[0];
      dom.skillFileInput.value = "";
      if (!f) return;
      const raw = await f.text();
      try {
        const res = await apiJson("/api/extensions/skill", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name: f.name.replace(/\.[^.]+$/, ""), raw_markdown: raw }),
        });
        state.skills = res.skills || [];
        renderExtensionsUI();
        showToast(`Beceri eklendi: ${f.name}`, "ok", 2600);
      } catch (err) {
        showToast(`Beceri eklenemedi: ${err.message}`, "err");
      }
    });
    dom.extSkillsList?.addEventListener("change", async (e) => {
      const cb = e.target.closest("input[data-skill-toggle]");
      if (!cb) return;
      const res = await apiJson("/api/extensions/skill/toggle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ id: cb.dataset.skillToggle, enabled: cb.checked }),
      });
      state.skills = res.skills || [];
      renderExtensionsUI();
    });
    dom.extSkillsList?.addEventListener("click", async (e) => {
      const del = e.target.closest("[data-skill-del]");
      if (!del) return;
      const res = await apiJson(`/api/extensions/skill/${encodeURIComponent(del.dataset.skillDel)}`, { method: "DELETE" });
      state.skills = res.skills || [];
      renderExtensionsUI();
      showToast("Beceri silindi", "ok", 1800);
    });
    const addNoteAct = async () => {
      const txt = (dom.inpNoteAdd?.value || "").trim();
      if (!txt) return;
      const res = await apiJson("/api/notes", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ text: txt }),
      });
      state.notes = res.notes || [];
      if (dom.inpNoteAdd) dom.inpNoteAdd.value = "";
      renderExtensionsUI();
    };
    dom.btnNoteAdd?.addEventListener("click", addNoteAct);
    dom.inpNoteAdd?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); addNoteAct(); }
    });
    dom.extNotesList?.addEventListener("click", async (e) => {
      const tog = e.target.closest("[data-note-toggle]");
      if (tog) {
        const res = await apiJson(`/api/notes/${encodeURIComponent(tog.dataset.noteToggle)}/toggle`, { method: "POST" });
        state.notes = res.notes || [];
        renderExtensionsUI();
        return;
      }
      const del = e.target.closest("[data-note-del]");
      if (del) {
        const res = await apiJson(`/api/notes/${encodeURIComponent(del.dataset.noteDel)}`, { method: "DELETE" });
        state.notes = res.notes || [];
        renderExtensionsUI();
      }
    });

    // Projects (Claude Projects) Events
    dom.btnNewProject?.addEventListener("click", () => {
      if (dom.prjNameInput) dom.prjNameInput.value = "";
      if (dom.prjInstInput) dom.prjInstInput.value = "";
      if (dom.projectModal) dom.projectModal.hidden = false;
      setTimeout(() => dom.prjNameInput?.focus(), 40);
    });
    dom.btnProjectClose?.addEventListener("click", () => (dom.projectModal.hidden = true));
    dom.btnPrjCancel?.addEventListener("click", () => (dom.projectModal.hidden = true));
    dom.btnPrjSave?.addEventListener("click", async () => {
      const name = (dom.prjNameInput?.value || "").trim();
      if (!name) return showToast("Proje adı girin", "warn", 2000);
      try {
        const res = await apiJson("/api/projects", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ name, instructions: dom.prjInstInput?.value || "" }),
        });
        state.projects = res.projects || [];
        state.activeProjectId = res.project?.id || null;
        dom.projectModal.hidden = true;
        renderProjectsUI();
        renderSessionList();
        renderLibraryDocs();
        showToast(`Proje oluşturuldu: ${name}`, "ok", 2400);
      } catch (err) {
        showToast(err.message, "err");
      }
    });
    dom.projectsList?.addEventListener("click", async (e) => {
      const del = e.target.closest("[data-prj-del]");
      if (del) {
        e.stopPropagation();
        const pid = del.dataset.prjDel;
        const res = await apiJson(`/api/projects/${encodeURIComponent(pid)}`, { method: "DELETE" });
        state.projects = res.projects || [];
        if (state.activeProjectId === pid) state.activeProjectId = null;
        renderProjectsUI();
        renderSessionList();
        renderLibraryDocs();
        showToast("Proje silindi", "ok", 1800);
        return;
      }
      const row = e.target.closest("[data-prj-id]");
      if (row) {
        state.activeProjectId = row.dataset.prjId || null;
        renderProjectsUI();
        renderSessionList();
        renderLibraryDocs();
      }
    });

    // Local Folder Workspace (Claude Code / Cowork)
    dom.btnWsOpen?.addEventListener("click", async () => {
      let picked = null;
      if (window.yerelDesktop?.pickFolder) {
        picked = await window.yerelDesktop.pickFolder();
      } else {
        picked = window.prompt("Açmak istediğiniz yerel proje klasör yolunu girin (örn: C:\\proje):");
      }
      if (!picked || !picked.trim()) return;
      try {
        const res = await apiJson("/api/workspace/open", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ path: picked.trim() }),
        });
        state.workspace = res;
        renderWorkspaceUI();
        showToast(`Çalışma alanı açıldı: ${res.name}`, "ok", 2200);
      } catch (err) {
        showToast(`Klasör açılamadı: ${err.message}`, "err", 3200);
      }
    });
    dom.btnWsClose?.addEventListener("click", async () => {
      try {
        state.workspace = await apiJson("/api/workspace/close", { method: "POST" });
        renderWorkspaceUI();
        showToast("Çalışma alanı kapatıldı", "ok", 1800);
      } catch (_) {}
    });
    dom.btnWsGit?.addEventListener("click", async () => {
      try {
        const g = await apiJson("/api/workspace/git");
        if (dom.gitBranchChip) dom.gitBranchChip.textContent = g.branch || "HEAD";
        if (dom.gitStatusPre) {
          const st = g.status || "(Çalışma ağacı temiz — bekleyen değişiklik yok)";
          const df = g.diff_stat ? `\n\n--- Diff Özeti ---\n${g.diff_stat}` : "";
          dom.gitStatusPre.textContent = st + df;
        }
        if (dom.gitStatusModal) dom.gitStatusModal.hidden = false;
      } catch (err) {
        showToast(`Git bilgisi alınamadı: ${err.message}`, "err");
      }
    });
    dom.btnGitClose?.addEventListener("click", () => { if (dom.gitStatusModal) dom.gitStatusModal.hidden = true; });
    dom.gitStatusModal?.addEventListener("click", (e) => { if (e.target === dom.gitStatusModal) dom.gitStatusModal.hidden = true; });
    dom.btnWinPickerClose?.addEventListener("click", () => { if (dom.windowPickerModal) dom.windowPickerModal.hidden = true; });
    dom.windowPickerModal?.addEventListener("click", (e) => { if (e.target === dom.windowPickerModal) dom.windowPickerModal.hidden = true; });

    dom.wsFilesList?.addEventListener("click", async (e) => {
      const addBtn = e.target.closest("[data-ws-attach]");
      if (addBtn) {
        e.stopPropagation();
        const rel = addBtn.dataset.wsAttach;
        try {
          const f = await apiJson(`/api/workspace/file?path=${encodeURIComponent(rel)}`);
          const block = `Dosya: \`${f.path}\`\n\`\`\`${f.ext}\n${f.content.slice(0, 8000)}\n\`\`\`\n\n`;
          dom.promptInput.value = block + (dom.promptInput.value || "");
          autoResizeTextarea();
          dom.promptInput.focus();
          showToast(`${f.name} sohbet bağlamına eklendi`, "ok", 2000);
        } catch (err) {
          showToast(err.message, "err");
        }
        return;
      }
      const row = e.target.closest("[data-ws-file]");
      if (!row) return;
      const rel = row.dataset.wsFile;
      try {
        const f = await apiJson(`/api/workspace/file?path=${encodeURIComponent(rel)}`);
        setArtifactOpen(true, f.content, f.ext || "txt", f.path, "code");
        if (state.activeArtifact) {
          state.activeArtifact.workspacePath = f.path;
          state.activeArtifact.baseCode = f.content;
          state.activeArtifact.baseLabel = "Disk";
          if (dom.btnArtifactSaveDisk) dom.btnArtifactSaveDisk.hidden = false;
        }
      } catch (err) {
        showToast(`Dosya açılamadı: ${err.message}`, "err");
      }
    });

    dom.mcpPresetsRow?.addEventListener("click", (e) => {
      const chip = e.target.closest("[data-mcp-preset]");
      if (!chip) return;
      const preset = (state.mcpPresets || []).find((p) => p.id === chip.dataset.mcpPreset);
      if (!preset) return;
      if (dom.mcpNameInp) dom.mcpNameInp.value = preset.name || "";
      if (dom.mcpTransportSel) dom.mcpTransportSel.value = preset.transport || "stdio";
      if (dom.mcpCmdInp) dom.mcpCmdInp.value = preset.command || "";
      if (dom.mcpArgsInp) dom.mcpArgsInp.value = preset.args || "";
      dom.mcpArgsInp?.focus();
      showToast(`${preset.name} şablonu dolduruldu — yolu düzenleyip "+ MCP Ekle"ye basın`, "ok", 2600);
    });

    // Claude Desktop-style MCP Tool Approval Card handlers inside chat messages
    dom.messagesList?.addEventListener("click", async (e) => {
      const rejBtn = e.target.closest("[data-mcp-reject]");
      if (rejBtn) {
        const [mIdx, cIdx] = rejBtn.dataset.mcpReject.split(":").map(Number);
        const msg = state.messages[mIdx];
        const call = msg?.mcp_calls?.[cIdx];
        if (!call || call.status !== "pending") return;
        call.status = "rejected";
        const row = rejBtn.closest(".msg-row");
        const slot = row ? $(".mcp-calls-slot", row) : null;
        if (slot) slot.innerHTML = buildMcpApprovalHtml(msg.mcp_calls, mIdx);
        saveCurrentSession();
        showToast("MCP araç çağrısı reddedildi", "warn", 1800);
        return;
      }
      const appBtn = e.target.closest("[data-mcp-approve]");
      if (appBtn) {
        if (state.isGenerating) return;
        const [mIdx, cIdx] = appBtn.dataset.mcpApprove.split(":").map(Number);
        const msg = state.messages[mIdx];
        const call = msg?.mcp_calls?.[cIdx];
        if (!call || call.status !== "pending") return;
        appBtn.disabled = true;
        appBtn.textContent = "Çalıştırılıyor...";
        try {
          const res = await apiJson(`/api/mcp/servers/${encodeURIComponent(call.server_id)}/call`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ tool: call.tool, arguments: call.arguments || {} }),
          });
          call.status = res.ok ? "approved" : "error";
          call.result_text = res.text || "(Boş yanıt)";
          const row = appBtn.closest(".msg-row");
          const slot = row ? $(".mcp-calls-slot", row) : null;
          if (slot) slot.innerHTML = buildMcpApprovalHtml(msg.mcp_calls, mIdx);
          await saveCurrentSession();
          // Feed verified MCP output back to Gemma 4 for final Turkish synthesis
          sendMessage(`[MCP ARAÇ SONUCU · ${call.server_name} / ${call.tool}]\n${call.result_text.slice(0, 3500)}\n\nBu yerel araç sonucunu kullanıcıya net ve Türkçe olarak özetle.`);
        } catch (err) {
          call.status = "error";
          call.result_text = `Hata: ${err.message}`;
          const row = appBtn.closest(".msg-row");
          const slot = row ? $(".mcp-calls-slot", row) : null;
          if (slot) slot.innerHTML = buildMcpApprovalHtml(msg.mcp_calls, mIdx);
          showToast(`MCP çalıştırma hatası: ${err.message}`, "err", 3400);
        }
      }
    });

    // Local MCP Servers Management (Settings -> Extensions)
    dom.btnMcpAdd?.addEventListener("click", async () => {
      const name = (dom.mcpNameInp?.value || "").trim();
      const transport = dom.mcpTransportSel?.value || "stdio";
      const cmdOrUrl = (dom.mcpCmdInp?.value || "").trim();
      const args = (dom.mcpArgsInp?.value || "").trim();
      if (!name || !cmdOrUrl) return showToast("Sunucu adı ve komut/URL zorunludur", "warn", 2400);
      try {
        const payload = transport === "http"
          ? { name, transport, url: cmdOrUrl, enabled: true }
          : { name, transport, command: cmdOrUrl, args, enabled: true };
        const res = await apiJson("/api/mcp/servers", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
        state.mcpServers = res.servers || [];
        if (dom.mcpNameInp) dom.mcpNameInp.value = "";
        if (dom.mcpCmdInp) dom.mcpCmdInp.value = "";
        if (dom.mcpArgsInp) dom.mcpArgsInp.value = "";
        renderMcpServersUI();
        showToast(`MCP sunucusu eklendi: ${name}`, "ok", 2200);
      } catch (err) {
        showToast(err.message, "err", 3200);
      }
    });
    dom.mcpServersList?.addEventListener("click", async (e) => {
      const toggleBtn = e.target.closest("[data-mcp-toggle]");
      if (toggleBtn) {
        const sid = toggleBtn.dataset.mcpToggle;
        const srv = (state.mcpServers || []).find((s) => s.id === sid);
        if (!srv) return;
        try {
          const res = await apiJson(`/api/mcp/servers/${encodeURIComponent(sid)}`, {
            method: "PATCH",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ enabled: !srv.enabled }),
          });
          state.mcpServers = res.servers || [];
          renderMcpServersUI();
        } catch (err) {
          showToast(err.message, "err");
        }
        return;
      }
      const discBtn = e.target.closest("[data-mcp-discover]");
      if (discBtn) {
        const sid = discBtn.dataset.mcpDiscover;
        discBtn.disabled = true;
        discBtn.textContent = "Taranıyor...";
        try {
          const res = await apiJson(`/api/mcp/servers/${encodeURIComponent(sid)}/discover`, { method: "POST" });
          state.mcpServers = res.servers || [];
          renderMcpServersUI();
          showToast(`${res.server?.tools?.length || 0} MCP aracı keşfedildi`, "ok", 2400);
        } catch (err) {
          await loadMcpServers();
          showToast(`MCP tarama hatası: ${err.message}`, "err", 3800);
        }
        return;
      }
      const delBtn = e.target.closest("[data-mcp-del]");
      if (delBtn) {
        const sid = delBtn.dataset.mcpDel;
        try {
          const res = await apiJson(`/api/mcp/servers/${encodeURIComponent(sid)}`, { method: "DELETE" });
          state.mcpServers = res.servers || [];
          renderMcpServersUI();
          showToast("MCP sunucusu kaldırıldı", "ok", 1800);
        } catch (err) {
          showToast(err.message, "err");
        }
      }
    });

    dom.inspModelCards.addEventListener("click", (e) => {
      const cancelBtn = e.target.closest('[data-dl-action="cancel"]');
      if (cancelBtn) {
        e.stopPropagation();
        cancelModelDownload();
        return;
      }
      const card = e.target.closest(".model-mini-card");
      if (!card) return;
      const mid = card.dataset.modelId;
      const modelObj = state.models.find((m) => m.id === mid);
      if (modelObj && !modelObj.cached_locally) {
        if (!state.download?.active) startModelDownload(mid);
        return;
      }
      selectModel(mid);
    });

    setupCustomDropdown(dom.gpuProfileDd, (val) => {
      state.gpuProfile = val;
      dom.lblGpuProfile.textContent = PROFILE_LABELS[val] || val;
      window.YerelSettings?.scheduleAutoSave?.();
    });
    if (dom.ctxSizeDd) {
      setupCustomDropdown(dom.ctxSizeDd, (val) => {
        state.contextLength = Number(val || 32768);
        dom.lblCtxSize.textContent = CTX_LABELS[String(state.contextLength)] || val;
        updateContextMeter();
        window.YerelSettings?.scheduleAutoSave?.();
      });
    }
    dom.btnMemoryAdd?.addEventListener("click", addMemoryFromInput);
    dom.inpMemoryAdd?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); addMemoryFromInput(); }
    });
    dom.memoryList?.addEventListener("click", (e) => {
      const del = e.target.closest("[data-mem-del]");
      if (del) deleteMemory(del.dataset.memDel);
    });
    setupCustomDropdown(dom.ttsVoiceDd, (val) => {
      state.ttsVoice = val;
      dom.lblTtsVoice.textContent = TTS_LABELS[val] || val;
      window.YerelSettings?.scheduleAutoSave?.();
    });
    setupCustomDropdown(dom.loraDd, (val, item) => {
      state.selectedLoraId = val;
      const sp = $("span", item);
      if (sp) dom.lblLora.textContent = sp.textContent;
      window.YerelSettings?.scheduleAutoSave?.();
    });

    dom.rngTemp.addEventListener("input", () => (dom.valTemp.textContent = Number(dom.rngTemp.value).toFixed(2)));
    dom.rngTopP.addEventListener("input", () => (dom.valTopP.textContent = Number(dom.rngTopP.value).toFixed(2)));
    dom.rngMaxTokens.addEventListener("input", () => (dom.valMaxTokens.textContent = String(dom.rngMaxTokens.value)));
    dom.rngIdleMin.addEventListener("input", () => (dom.valIdleMin.textContent = `${dom.rngIdleMin.value} dk`));
    dom.rngLoraScale.addEventListener("input", () => (dom.valLoraScale.textContent = `${Number(dom.rngLoraScale.value).toFixed(1)}x`));
    dom.btnSaveConfig.addEventListener("click", saveConfig);

    dom.inspDatasetList.addEventListener("click", async (e) => {
      const btn = e.target.closest(".btn-del-ds");
      if (!btn) return;
      try {
        await apiJson(`/api/dataset/${encodeURIComponent(btn.dataset.dsId)}`, { method: "DELETE" });
        await loadDataset();
        showToast("Örnek silindi", "ok", 1800);
      } catch (err) {
        showToast(`Silinemedi: ${err.message}`, "err");
      }
    });

    // Messages stream delegation (Tables Copy/CSV, Code Copy, Lightbox, Speak, Copy, Colab)
    dom.messagesList.addEventListener("click", async (e) => {
      const img = e.target.closest(".att-img-thumb");
      if (img) {
        dom.lightboxImg.src = img.dataset.fullSrc || img.src;
        dom.lightboxModal.hidden = false;
        return;
      }

      const tblCopy = e.target.closest(".btn-tbl-copy");
      if (tblCopy) {
        const tbl = tblCopy.closest(".md-table-card")?.querySelector("table");
        if (tbl) {
          const tsv = extractTableMatrix(tbl)
            .map((r) => r.join("\t"))
            .join("\n");
          await navigator.clipboard.writeText(tsv);
          showToast("Tablo Excel uyumlu kopyalandı", "ok", 2000);
        }
        return;
      }

      const tblCsv = e.target.closest(".btn-tbl-csv");
      if (tblCsv) {
        const tbl = tblCsv.closest(".md-table-card")?.querySelector("table");
        if (tbl) {
          const csv = extractTableMatrix(tbl)
            .map((r) => r.map((c) => `"${c.replace(/"/g, '""')}"`).join(";"))
            .join("\r\n");
          const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
          const url = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = url;
          a.download = `yerelai_tablo_${Date.now()}.csv`;
          a.click();
          setTimeout(() => URL.revokeObjectURL(url), 1000);
          showToast("CSV dosyası indirildi", "ok", 2000);
        }
        return;
      }

      const codePreview = e.target.closest(".code-preview-btn");
      if (codePreview) {
        const pre = codePreview.closest(".code-block-wrap")?.querySelector("pre");
        if (pre) {
          const rawCode = Array.from(pre.querySelectorAll(".code-lc"))
            .map((el) => el.textContent)
            .join("\n");
          setArtifactOpen(true, rawCode, codePreview.dataset.lang || "html");
        }
        return;
      }

      const cfcRun = e.target.closest(".btn-cfc-run");
      if (cfcRun) {
        const card = cfcRun.closest(".code-file-card");
        const pre = cfcRun.closest(".code-block-group")?.querySelector("pre");
        if (pre && card) {
          const rawCode = Array.from(pre.querySelectorAll(".code-lc")).map((el) => el.textContent).join("\n");
          setArtifactOpen(true, rawCode, card.dataset.codeLang || "python", card.dataset.codeFname || "", "code");
          runPythonSandbox(rawCode);
        }
        return;
      }

      const cfcPreview = e.target.closest(".btn-cfc-preview");
      if (cfcPreview) {
        const card = cfcPreview.closest(".code-file-card");
        const pre = cfcPreview.closest(".code-block-group")?.querySelector("pre");
        if (pre && card) {
          const rawCode = Array.from(pre.querySelectorAll(".code-lc")).map((el) => el.textContent).join("\n");
          setArtifactOpen(true, rawCode, card.dataset.codeLang || "html", card.dataset.codeFname || "");
        }
        return;
      }

      const cfcDownload = e.target.closest(".btn-cfc-download");
      if (cfcDownload) {
        const card = cfcDownload.closest(".code-file-card");
        const pre = cfcDownload.closest(".code-block-group")?.querySelector("pre");
        if (pre && card) {
          const rawCode = Array.from(pre.querySelectorAll(".code-lc")).map((el) => el.textContent).join("\n");
          const fname = card.dataset.codeFname || `kod_${Date.now()}.txt`;
          const blob = new Blob([rawCode], { type: "text/plain;charset=utf-8" });
          const url = URL.createObjectURL(blob);
          const a = document.createElement("a");
          a.href = url;
          a.download = fname;
          a.click();
          setTimeout(() => URL.revokeObjectURL(url), 1000);
          showToast(`${fname} indirildi`, "ok", 2200);
        }
        return;
      }

      const fdcToggle = e.target.closest(".btn-fdc-toggle-tables");
      if (fdcToggle) {
        const msgRow = fdcToggle.closest(".msg-row");
        if (msgRow) {
          const expanded = fdcToggle.dataset.expanded === "1";
          const next = !expanded;
          fdcToggle.dataset.expanded = next ? "1" : "0";
          collapseTableCardsInNode(msgRow, !next);
          const sp = $("span", fdcToggle);
          if (sp) sp.textContent = next ? "Tabloyu Gizle" : "Tabloyu Gör";
        }
        return;
      }

      const tblXlsx = e.target.closest(".btn-tbl-xlsx");
      if (tblXlsx) {
        const tbl = tblXlsx.closest(".md-table-card")?.querySelector("table");
        if (tbl) await exportTableToXlsx(tbl, dom.pageBreadcrumb.textContent || "YerelAI_Tablo");
        return;
      }

      const codeExpand = e.target.closest(".code-expand-btn");
      if (codeExpand) {
        const wrap = codeExpand.closest(".code-block-wrap");
        if (wrap) {
          const exp = wrap.classList.toggle("is-expanded");
          codeExpand.textContent = exp ? "Daralt" : "Genişlet";
        }
        return;
      }

      const codeCopy = e.target.closest(".code-copy-btn");
      if (codeCopy) {
        const pre = codeCopy.closest(".code-block-wrap")?.querySelector("pre");
        if (pre) {
          const lineNodes = pre.querySelectorAll(".code-lc");
          const rawCode = lineNodes.length
            ? Array.from(lineNodes)
                .map((el) => el.textContent)
                .join("\n")
            : pre.textContent || "";
          await navigator.clipboard.writeText(rawCode);
          codeCopy.classList.add("is-copied");
          codeCopy.textContent = "✓ Kopyalandı";
          setTimeout(() => {
            codeCopy.classList.remove("is-copied");
            codeCopy.textContent = "Kopyala";
          }, 1600);
        }
        return;
      }

      const chartPng = e.target.closest(".btn-chart-png");
      if (chartPng) {
        const card = chartPng.closest(".rich-chart-card");
        const canvas = card?.querySelector("canvas");
        const svg = card?.querySelector("svg.local-svg-chart");
        if (canvas) {
          const a = document.createElement("a");
          a.href = canvas.toDataURL("image/png");
          a.download = `yerelai_grafik_${Date.now()}.png`;
          a.click();
          showToast("Grafik PNG olarak indirildi", "ok", 1800);
        } else if (svg) {
          const xml = new XMLSerializer().serializeToString(svg);
          const img = new Image();
          img.onload = () => {
            const c = document.createElement("canvas");
            c.width = 1280;
            c.height = 440;
            const g = c.getContext("2d");
            g.fillStyle = dom.html.getAttribute("data-theme") === "dark" ? "#0c1220" : "#ffffff";
            g.fillRect(0, 0, c.width, c.height);
            g.drawImage(img, 0, 0, c.width, c.height);
            const a = document.createElement("a");
            a.href = c.toDataURL("image/png");
            a.download = `yerelai_grafik_${Date.now()}.png`;
            a.click();
            showToast("Grafik PNG olarak indirildi", "ok", 1800);
          };
          img.src = "data:image/svg+xml;charset=utf-8," + encodeURIComponent(xml);
        }
        return;
      }

      const choiceOpt = e.target.closest(".yc-choice-opt");
      if (choiceOpt) {
        const card = choiceOpt.closest(".yc-choice-card");
        if (card) {
          const isMulti = card.dataset.multi === "1";
          if (!isMulti) {
            $$(".yc-choice-opt", card).forEach((o) => { if (o !== choiceOpt) o.classList.remove("selected"); });
          }
          choiceOpt.classList.toggle("selected");
          const anySel = $$(".yc-choice-opt.selected", card).length > 0;
          const subBtn = $(".yc-choice-submit", card);
          if (subBtn) subBtn.disabled = !anySel;
        }
        return;
      }

      const choiceSubmit = e.target.closest(".yc-choice-submit");
      if (choiceSubmit) {
        const card = choiceSubmit.closest(".yc-choice-card");
        if (card && !state.isGenerating) {
          const chosen = $$(".yc-choice-opt.selected", card).map((o) => o.dataset.choiceVal || o.textContent.trim()).filter(Boolean);
          if (chosen.length) {
            choiceSubmit.disabled = true;
            sendMessage(`Seçimim: ${chosen.join(", ")}`);
          }
        }
        return;
      }

      const clChk = e.target.closest(".yc-cl-item input[type='checkbox']");
      if (clChk) {
        const item = clChk.closest(".yc-cl-item");
        const card = clChk.closest(".yc-checklist-card");
        if (item) item.classList.toggle("is-done", clChk.checked);
        if (card) {
          const all = $$(".yc-cl-item input[type='checkbox']", card);
          const done = all.filter((c) => c.checked).length;
          const pct = all.length ? Math.round((done / all.length) * 100) : 0;
          const fill = $(".yc-cl-fill", card);
          const pctEl = $(".yc-cl-pct", card);
          if (fill) fill.style.width = `${pct}%`;
          if (pctEl) pctEl.textContent = `%${pct}`;
        }
        return;
      }

      const row = e.target.closest(".msg-row");
      if (!row) return;
      const msgIdx = Number(row.dataset.msgIdx);
      const msg = state.messages[msgIdx];
      if (!msg) return;

      const srcBtn = e.target.closest(".btn-open-sources");
      if (srcBtn) {
        if (msg.web_search?.sources?.length) openSourcesModal(msg.web_search.sources);
        return;
      }

      const shareBtn = e.target.closest(".btn-msg-share");
      if (shareBtn) {
        const txt = msg.content || "";
        if (navigator.share) {
          navigator.share({ title: "SEN.AI Yanıtı", text: txt }).catch(() => {});
        } else {
          await navigator.clipboard.writeText(txt);
          showToast("Yanıt paylaşım için panoya kopyalandı", "ok", 2000);
        }
        return;
      }

      const moreBtn = e.target.closest(".btn-msg-more");
      if (moreBtn && dom.msgMoreMenu) {
        e.stopPropagation();
        const isSameOpen = !dom.msgMoreMenu.hidden && state.activeMoreMenuMsgIdx === msgIdx;
        if (isSameOpen) {
          dom.msgMoreMenu.hidden = true;
          state.activeMoreMenuMsgIdx = null;
          return;
        }
        state.activeMoreMenuMsgIdx = msgIdx;
        const dtStr = msg.created_at ? new Date(msg.created_at).toLocaleString("tr-TR", { hour: "2-digit", minute: "2-digit", day: "2-digit", month: "short" }) : "";
        const spdStr = msg.stats ? `${msg.stats.tps} tok/sn · ${msg.stats.tokens} token` : "";
        if (dom.msgMoreMeta) {
          dom.msgMoreMeta.textContent = [dtStr, spdStr].filter(Boolean).join(" · ") || "SEN.AI Yanıtı";
        }
        const srcItem = $('[data-mm-act="sources"]', dom.msgMoreMenu);
        if (srcItem) srcItem.hidden = !(msg.web_search?.sources?.length > 0);
        const r = moreBtn.getBoundingClientRect();
        dom.msgMoreMenu.hidden = false;
        const mw = dom.msgMoreMenu.offsetWidth || 248;
        const mh = dom.msgMoreMenu.offsetHeight || 180;
        const left = Math.min(window.innerWidth - mw - 12, Math.max(12, r.left));
        const top = r.bottom + mh + 12 > window.innerHeight ? Math.max(12, r.top - mh - 6) : r.bottom + 6;
        dom.msgMoreMenu.style.left = `${left}px`;
        dom.msgMoreMenu.style.top = `${top}px`;
        return;
      }

      const branchBtn = e.target.closest(".msg-branch-btn");
      if (branchBtn) return switchMessageVariant(msgIdx, Number(branchBtn.dataset.branchDir || 0));

      const editBtn = e.target.closest(".btn-msg-edit");
      if (editBtn) return openInlineMessageEdit(row, msgIdx);

      const regenBtn = e.target.closest(".btn-msg-regen");
      if (regenBtn) return regenerateAssistantAt(msgIdx);

      const forkBtn = e.target.closest(".btn-msg-fork");
      if (forkBtn) return forkChatAt(msgIdx);

      const docBtn = e.target.closest(".btn-msg-doc");
      if (docBtn) return exportMessageDocument(msg, Boolean(e.shiftKey));

      const speakBtn = e.target.closest(".btn-msg-speak");
      if (speakBtn) return speakText(msg.content, speakBtn);

      const copyBtn = e.target.closest(".btn-msg-copy");
      if (copyBtn) {
        await navigator.clipboard.writeText(msg.content || "");
        copyBtn.classList.add("is-copied");
        copyBtn.innerHTML = SVG_ICONS.check;
        setTimeout(() => {
          copyBtn.classList.remove("is-copied");
          copyBtn.innerHTML = SVG_ICONS.copy;
        }, 1500);
        return;
      }

      const likeBtn = e.target.closest(".btn-msg-like");
      if (likeBtn) {
        const idx = Number(row.dataset.msgIdx);
        const prevUser = state.messages.slice(0, idx).reverse().find((m) => m.role === "user");
        const nextRating = msg.rating === "like" ? "none" : "like";
        try {
          await apiJson("/api/dataset/rate", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              user_text: prevUser?.content || "",
              assistant_text: msg.content || "",
              rating: nextRating,
              model_id: msg.model_id || state.selectedModelId,
              thinking_effort: msg.thinking_effort || state.thinkingEffort,
              system_prompt: dom.txtSystemPrompt?.value || "",
            }),
          });
          msg.rating = nextRating === "none" ? null : "like";
          likeBtn.classList.toggle("active", msg.rating === "like");
          $(".btn-msg-dislike", row)?.classList.remove("active", "active-down");
          await loadDataset();
          await saveCurrentSession();
          showToast(msg.rating === "like" ? "👍 Beğenildi ve eğitim setine eklendi" : "Beğeni kaldırıldı", "ok", 2000);
        } catch (err) {
          showToast(`Kaydedilemedi: ${err.message}`, "err");
        }
        return;
      }

      const dislikeBtn = e.target.closest(".btn-msg-dislike");
      if (dislikeBtn) {
        const idx = Number(row.dataset.msgIdx);
        const prevUser = state.messages.slice(0, idx).reverse().find((m) => m.role === "user");
        if (msg.rating === "dislike") {
          try {
            await apiJson("/api/dataset/rate", {
              method: "POST",
              headers: { "Content-Type": "application/json" },
              body: JSON.stringify({
                user_text: prevUser?.content || "",
                assistant_text: msg.content || "",
                rating: "none",
                model_id: msg.model_id || state.selectedModelId,
                thinking_effort: msg.thinking_effort || state.thinkingEffort,
                system_prompt: dom.txtSystemPrompt?.value || "",
              }),
            });
            msg.rating = null;
            dislikeBtn.classList.remove("active", "active-down");
            await loadDataset();
            await saveCurrentSession();
            showToast("Geri bildirim kaldırıldı", "ok", 1800);
          } catch (err) {
            showToast(`Kaydedilemedi: ${err.message}`, "err");
          }
          return;
        }
        state.pendingDislike = { idx, row, msg, userText: prevUser?.content || "", reason: "" };
        $$(".dislike-reason-chip", dom.dislikeReasons || document).forEach((c) => c.classList.remove("active"));
        if (dom.inpDislikeCorrection) dom.inpDislikeCorrection.value = "";
        if (dom.dislikeModal) dom.dislikeModal.hidden = false;
        return;
      }
    });

    // Floating ••• Message More Menu Actions
    dom.msgMoreMenu?.addEventListener("click", (e) => {
      e.stopPropagation();
      const btn = e.target.closest("[data-mm-act]");
      if (!btn) return;
      const act = btn.dataset.mmAct;
      const idx = state.activeMoreMenuMsgIdx;
      dom.msgMoreMenu.hidden = true;
      state.activeMoreMenuMsgIdx = null;
      if (idx == null) return;
      const msg = state.messages[idx];
      if (!msg) return;
      if (act === "regen") regenerateAssistantAt(idx);
      else if (act === "fork") forkChatAt(idx);
      else if (act === "sources" && msg.web_search?.sources?.length) openSourcesModal(msg.web_search.sources);
      else if (act === "docx") exportMessageDocument(msg, Boolean(e.shiftKey));
    });

    // Dislike Feedback & DPO Correction Modal Listeners
    dom.dislikeReasons?.addEventListener("click", (e) => {
      const chip = e.target.closest(".dislike-reason-chip");
      if (!chip || !state.pendingDislike) return;
      $$(".dislike-reason-chip", dom.dislikeReasons).forEach((c) => c.classList.remove("active"));
      chip.classList.add("active");
      state.pendingDislike.reason = chip.dataset.reason || "";
    });
    const closeDislikeModal = () => {
      state.pendingDislike = null;
      if (dom.dislikeModal) dom.dislikeModal.hidden = true;
    };
    dom.btnDislikeClose?.addEventListener("click", closeDislikeModal);
    dom.btnDislikeCancel?.addEventListener("click", closeDislikeModal);
    dom.dislikeModal?.addEventListener("click", (e) => { if (e.target === dom.dislikeModal) closeDislikeModal(); });
    dom.btnDislikeSave?.addEventListener("click", async () => {
      const pd = state.pendingDislike;
      if (!pd) return closeDislikeModal();
      const corrected = (dom.inpDislikeCorrection?.value || "").trim();
      try {
        await apiJson("/api/dataset/rate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            user_text: pd.userText,
            assistant_text: pd.msg.content || "",
            rating: "dislike",
            reason: pd.reason || "",
            corrected_text: corrected,
            model_id: pd.msg.model_id || state.selectedModelId,
            thinking_effort: pd.msg.thinking_effort || state.thinkingEffort,
            system_prompt: dom.txtSystemPrompt?.value || "",
          }),
        });
        pd.msg.rating = "dislike";
        $(".btn-msg-dislike", pd.row)?.classList.add("active");
        $(".btn-msg-like", pd.row)?.classList.remove("active");
        closeDislikeModal();
        await loadDataset();
        await saveCurrentSession();
        showToast(corrected ? "👎 Geri bildirim ve ⚡ DPO tercih çifti kaydedildi" : "👎 Geri bildirim kaydedildi", "ok", 2600);
      } catch (err) {
        showToast(`Kaydedilemedi: ${err.message}`, "err");
      }
    });

    dom.btnModalClose.addEventListener("click", () => (dom.datasetModal.hidden = true));
    dom.btnDsCancel.addEventListener("click", () => (dom.datasetModal.hidden = true));
    dom.btnDsSave.addEventListener("click", saveDatasetEntry);
    dom.btnLightboxClose.addEventListener("click", () => (dom.lightboxModal.hidden = true));
    dom.lightboxModal.addEventListener("click", (e) => {
      if (e.target === dom.lightboxModal) dom.lightboxModal.hidden = true;
    });

    dom.btnPinUnlock?.addEventListener("click", unlockWithPin);
    dom.inpPinUnlock?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") { e.preventDefault(); unlockWithPin(); }
    });
    dom.btnPinSave?.addEventListener("click", () => savePinSettings(false));
    dom.btnPinRemove?.addEventListener("click", () => savePinSettings(true));

    setupAudioPlayer();
  }

  function applyPinUiState(auth) {
    if (!auth) return;
    if (dom.pinStatusBadge) {
      dom.pinStatusBadge.textContent = auth.pin_enabled ? "Aktif" : "Kapalı";
      dom.pinStatusBadge.classList.toggle("ready", Boolean(auth.pin_enabled));
    }
    if (dom.swPinLocalBypass && typeof auth.local_bypass === "boolean") {
      dom.swPinLocalBypass.checked = auth.local_bypass;
    }
    if (dom.pinLockOverlay) {
      dom.pinLockOverlay.hidden = Boolean(auth.unlocked);
      if (!auth.unlocked) setTimeout(() => dom.inpPinUnlock?.focus(), 60);
    }
  }

  async function checkAuthState() {
    try {
      const me = await apiJson("/api/auth/me");
      state.actor = me;
      window.YerelSettings?.setAdminVisible?.(Boolean(me.is_admin));
      if (dom.btnActorChip && dom.actorChipLabel) {
        const showChip = !me.is_local || !me.is_admin;
        dom.btnActorChip.hidden = !showChip;
        dom.btnActorChip.classList.toggle("is-guest", me.role === "guest");
        dom.actorChipLabel.textContent = me.role === "guest" ? "Misafir · Giriş" : (me.display_name || me.actor_id || "Hesap");
      }
      if (dom.btnGuestContinue) dom.btnGuestContinue.hidden = !me.allow_guest;
      applyPinUiState({ pin_enabled: me.pin_enabled, local_bypass: me.local_bypass, unlocked: me.unlocked });
      return Boolean(me.unlocked);
    } catch (_) {
      try {
        const auth = await apiJson("/api/auth/state");
        applyPinUiState(auth);
        return Boolean(auth.unlocked);
      } catch (_) {
        return true;
      }
    }
  }

  async function unlockWithPin() {
    const username = (dom.inpLoginUsername?.value || "").trim();
    const pin = (dom.inpPinUnlock?.value || "").trim();
    if (!pin) return;
    if (dom.pinLockErr) dom.pinLockErr.hidden = true;
    try {
      const res = await fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, pin }),
      });
      if (!res.ok) {
        if (dom.pinLockErr) dom.pinLockErr.hidden = false;
        dom.inpPinUnlock?.select();
        return;
      }
      if (dom.inpPinUnlock) dom.inpPinUnlock.value = "";
      if (dom.pinLockOverlay) dom.pinLockOverlay.hidden = true;
      showToast("Giriş başarılı", "ok", 1800);
      await checkAuthState();
      await loadStudioBootstrap();
    } catch (err) {
      showToast(`Doğrulama hatası: ${err.message}`, "err");
    }
  }

  async function savePinSettings(remove = false) {
    const pin = remove ? "" : (dom.inpPinNew?.value || "").trim();
    if (!remove && pin.length < 4) {
      showToast("PIN en az 4 karakter olmalıdır", "warn", 2600);
      return;
    }
    try {
      const res = await apiJson("/api/auth/set-pin", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ pin, local_bypass: Boolean(dom.swPinLocalBypass?.checked) }),
      });
      if (dom.inpPinNew) dom.inpPinNew.value = "";
      applyPinUiState({ pin_enabled: res.pin_enabled, local_bypass: res.local_bypass, unlocked: true });
      showToast(res.pin_enabled ? "Uzaktan erişim PIN kilidi aktif edildi" : "PIN kilidi kaldırıldı", "ok", 2800);
    } catch (err) {
      showToast(`PIN ayarlanamadı: ${err.message}`, "err", 3800);
    }
  }

  async function loadMcpServers() {
    try {
      const data = await apiJson("/api/mcp/servers");
      state.mcpServers = data.servers || [];
      state.mcpPresets = data.presets || [];
      renderMcpServersUI();
    } catch (_) {}
  }

  function renderMcpServersUI() {
    const list = state.mcpServers || [];
    if (dom.mcpServersCount) dom.mcpServersCount.textContent = `${list.length} sunucu`;
    if (dom.mcpPresetsRow) {
      const presets = state.mcpPresets || [];
      dom.mcpPresetsRow.innerHTML = presets
        .map((p) => `<button type="button" class="mcp-preset-chip" data-mcp-preset="${escHtml(p.id)}" title="${escHtml(p.desc || "")}">+ ${escHtml(p.name)}</button>`)
        .join("");
    }
    if (!dom.mcpServersList) return;
    if (!list.length) {
      dom.mcpServersList.innerHTML = `<div class="muted-empty">Henüz yerel MCP sunucusu tanımlanmadı</div>`;
      return;
    }
    dom.mcpServersList.innerHTML = list
      .map((s) => {
        const targetText = s.transport === "http" ? s.url : `${s.command} ${(s.args || []).join(" ")}`.trim();
        const toolsHtml = (s.tools || []).length
          ? `<div class="mcp-tools-wrap">${s.tools.map((t) => `<span class="mcp-tool-chip" title="${escHtml(t.description || "")}">${escHtml(t.name)}</span>`).join("")}</div>`
          : "";
        const errHtml = s.last_error ? `<div class="mcp-err-line">${escHtml(s.last_error)}</div>` : "";
        return `
        <div class="mcp-card">
          <div class="mcp-card-top">
            <div class="mcp-card-title">
              <span>${escHtml(s.name)}</span>
              <span class="lang-chip mono">${escHtml(s.transport.toUpperCase())}</span>
            </div>
            <div class="mcp-card-actions">
              <button type="button" class="btn-ghost btn-sm" data-mcp-discover="${escHtml(s.id)}">Araçları Tara</button>
              <button type="button" class="btn-ghost btn-sm" data-mcp-toggle="${escHtml(s.id)}">${s.enabled ? "Aktif" : "Pasif"}</button>
              <button type="button" class="icon-btn xs" data-mcp-del="${escHtml(s.id)}" title="Kaldır" aria-label="Kaldır">${SVG_ICONS.xClose}</button>
            </div>
          </div>
          <div class="mcp-card-meta mono">${escHtml(targetText)}</div>
          ${toolsHtml}
          ${errHtml}
        </div>`;
      })
      .join("");
  }

  async function loadWorkspace() {
    try {
      state.workspace = await apiJson("/api/workspace");
      renderWorkspaceUI();
    } catch (_) {}
  }

  function renderWorkspaceUI() {
    const ws = state.workspace || { open: false, files: [] };
    if (dom.wsActiveBar) dom.wsActiveBar.hidden = !ws.open;
    if (dom.wsFilesList) dom.wsFilesList.hidden = !ws.open;
    if (!ws.open) return;
    if (dom.wsName) {
      dom.wsName.textContent = ws.name || "Klasör";
      dom.wsName.title = ws.root || "";
    }
    if (dom.btnWsGit) dom.btnWsGit.hidden = !ws.is_git;
    if (!dom.wsFilesList) return;
    const files = ws.files || [];
    if (!files.length) {
      dom.wsFilesList.innerHTML = `<div class="muted-empty">Okunabilir metin dosyası bulunamadı</div>`;
      return;
    }
    dom.wsFilesList.innerHTML = files
      .slice(0, 120)
      .map(
        (f) => `
      <div class="ws-file-row" data-ws-file="${escHtml(f.path)}" title="${escHtml(f.path)} (Düzenlemek için tıkla)">
        <span class="ws-file-path mono">${escHtml(f.path)}</span>
        <button type="button" class="ws-file-add" data-ws-attach="${escHtml(f.path)}" title="Sohbete Bağlam Olarak Ekle">+</button>
      </div>`
      )
      .join("");
  }

  async function loadStudioBootstrap() {
    try {
      const [modelsData, cfg] = await Promise.all([apiJson("/api/models"), apiJson("/api/config")]);
      state.models = modelsData.models || [];
      state.loras = modelsData.loras || [];
      applyConfigToUI(cfg);
    } catch (err) {
      showToast(`Başlangıç verileri yüklenemedi: ${err.message}`, "err");
    }
    renderPersonasUI();
    setTtsSpeed(state.ttsSpeed);
    const isLocalHost = Boolean(window.yerelDesktop?.isElectron) || location.hostname === "127.0.0.1" || location.hostname === "localhost";
    const bootTasks = [loadSessions(), loadDataset(), loadLibrary(), loadMemories(), loadExtensions(), loadProjects(), pollStatus()];
    if (isLocalHost) bootTasks.push(loadMcpServers(), loadWorkspace());
    await Promise.all(bootTasks);
    scheduleNextPoll();
  }

  function setDynamicGreeting() {
    if (!dom.heroGreetingLead) return;
    const h = new Date().getHours();
    let txt = "Bugün";
    if (h >= 5 && h < 12) txt = "Günaydın,";
    else if (h >= 12 && h < 18) txt = "İyi günler,";
    else if (h >= 18 && h < 23) txt = "İyi akşamlar,";
    else txt = "İyi geceler,";
    dom.heroGreetingLead.textContent = txt;
  }

  async function init() {
    applyTheme(localStorage.getItem("yerelai_theme") || "dark");
    if (localStorage.getItem("yerelai_sidebar_collapsed") === "1") {
      dom.studioShell?.classList.add("sidebar-collapsed");
      dom.btnCollapseSidebar?.classList.add("active");
    }
    setDynamicGreeting();
    wireEvents();

    // Mobile new-chat button & live code <pre> scroll intent tracking
    $("#btn-mobile-new-chat")?.addEventListener("click", () => {
      dom.sidebar?.classList.remove("mobile-open");
      if (dom.drawerBackdrop) dom.drawerBackdrop.hidden = true;
      startNewChat();
    });
    dom.messagesList?.addEventListener(
      "scroll",
      (e) => {
        const pre = e.target.closest?.(".code-block-wrap pre");
        if (!pre) return;
        const distFromBottom = pre.scrollHeight - pre.scrollTop - pre.clientHeight;
        pre.dataset.userScrolledUp = distFromBottom > 38 ? "1" : "0";
      },
      { capture: true, passive: true }
    );

    // iOS 26-27 / Android Dynamic VisualViewport Keyboard Sync
    if (window.visualViewport) {
      const syncViewportHeight = () => {
        document.documentElement.style.setProperty("--vvh", `${Math.round(window.visualViewport.height)}px`);
      };
      window.visualViewport.addEventListener("resize", syncViewportHeight, { passive: true });
      syncViewportHeight();
    }

    // Electron Desktop Native Bridge (Appshot + Alt+Space Companion Injection)
    if (window.yerelDesktop?.isElectron) {
      document.documentElement.classList.add("is-electron-desktop");
      window.yerelDesktop.setTheme(localStorage.getItem("yerelai_theme") || "dark");

      const attachDataUrlAsPng = async (dataUrl, name = "ekran_goruntusu.png") => {
        const res = await fetch(dataUrl);
        const blob = await res.blob();
        const file = new File([blob], name, { type: "image/png" });
        await uploadFiles([file]);
      };

      $("#btn-desktop-shot")?.addEventListener("click", async () => {
        if (window.yerelDesktop.listWindows && dom.windowPickerModal && dom.windowPickerGrid) {
          const wins = await window.yerelDesktop.listWindows();
          if (wins.length) {
            dom.windowPickerGrid.innerHTML = wins
              .map(
                (w) => `
              <button type="button" class="win-picker-card" data-win-src="${escHtml(w.id)}" title="${escHtml(w.name)}">
                <img src="${w.thumb}" alt="" />
                <span>${escHtml(w.name)}</span>
              </button>`
              )
              .join("");
            dom.windowPickerModal.hidden = false;
            return;
          }
        }
        const dataUrl = await window.yerelDesktop.captureScreen(true);
        if (dataUrl) {
          await attachDataUrlAsPng(dataUrl, `ekran_${Date.now()}.png`);
          dom.promptInput?.focus();
        }
      });

      dom.windowPickerGrid?.addEventListener("click", async (e) => {
        const card = e.target.closest("[data-win-src]");
        if (!card) return;
        const srcId = card.dataset.winSrc;
        if (dom.windowPickerModal) dom.windowPickerModal.hidden = true;
        const dataUrl = await window.yerelDesktop.captureSource(srcId, true);
        if (dataUrl) {
          await attachDataUrlAsPng(dataUrl, `pencere_${Date.now()}.png`);
          dom.promptInput?.focus();
        }
      });

      dom.btnWinPickerClip?.addEventListener("click", async () => {
        if (dom.windowPickerModal) dom.windowPickerModal.hidden = true;
        const txt = await window.yerelDesktop.readClipboard?.();
        if (txt && txt.trim()) {
          dom.promptInput.value = `${dom.promptInput.value ? dom.promptInput.value + "\n\n" : ""}${txt.trim().slice(0, 4000)}`;
          autoResizeTextarea();
          dom.promptInput.focus();
          showToast("Windows panosu sohbete eklendi", "ok", 1800);
        } else {
          showToast("Panoda metin bulunamadı", "warn", 1800);
        }
      });

      window.yerelDesktop.onContextAsk?.((selText) => {
        if (!selText) return;
        setInspectorOpen(false);
        dom.promptInput.value = `Şu metni kısaca açıkla:\n\n"${selText}"`;
        autoResizeTextarea();
        dom.promptInput.focus();
      });

      window.yerelDesktop.onOpenSettings?.((tab) => {
        setInspectorOpen(true, tab || "desktop");
      });

      window.yerelDesktop.onInjectPrompt(async (payload) => {
        if (!payload) return;
        setInspectorOpen(false);
        syncWebSearchUI(Boolean(payload.webSearch));
        updateEffortPill(payload.highEffort ? "high" : "off", false);
        if (payload.screenshot) {
          await attachDataUrlAsPng(payload.screenshot, `ekran_${Date.now()}.png`);
        }
        const txt = (payload.text || "").trim();
        if (txt || payload.screenshot) {
          sendMessage(txt || "Bu ekran görüntüsünü incele ve Türkçe açıkla.");
        }
      });
    }

    // Sidebar nav & collapsible GPU capsule (works on both Desktop & Mobile/Web)
    const closeMobileNavIfOpen = () => {
      dom.sidebar?.classList.remove("open", "mobile-open");
      dom.drawerBackdrop?.classList.remove("open");
    };
    $("#dnav-search")?.addEventListener("click", () => {
      closeMobileNavIfOpen();
      openCmdPalette();
    });
    $("#dnav-extensions")?.addEventListener("click", () => {
      closeMobileNavIfOpen();
      setInspectorOpen(true, "extensions");
    });
    $("#dnav-settings")?.addEventListener("click", () => {
      closeMobileNavIfOpen();
      setInspectorOpen(true, "general");
    });
    dom.gpuCard?.addEventListener("click", (e) => {
      if (e.target.closest("button")) return;
      dom.gpuCard.classList.toggle("is-expanded");
    });

    // v17.0: Automatic iOS Detection, visualViewport Keyboard Lock & Clean Mobile Controls
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
    if (isIOS) document.documentElement.classList.add("is-ios");
    if ("ontouchstart" in window || navigator.maxTouchPoints > 0) document.documentElement.classList.add("is-touch");

    const syncMobileViewport = () => {
      if (window.innerWidth > 820) return;
      const vv = window.visualViewport;
      const h = vv ? Math.round(vv.height) : window.innerHeight;
      document.documentElement.style.setProperty("--vvh", `${h}px`);
      if (vv && vv.offsetTop > 0) window.scrollTo(0, 0);
      if (document.activeElement === dom.promptInput) {
        setTimeout(() => scrollToBottom(false), 60);
      }
    };
    if (window.visualViewport) {
      window.visualViewport.addEventListener("resize", syncMobileViewport);
      window.visualViewport.addEventListener("scroll", syncMobileViewport);
    }
    window.addEventListener("orientationchange", () => setTimeout(syncMobileViewport, 200));
    syncMobileViewport();

    // Mobile Top-Bar Model Picker Pill (#active-engine-badge opens #composer-popover on <= 820px)
    $("#active-engine-badge")?.addEventListener("click", (e) => {
      if (window.innerWidth > 820) return;
      e.stopPropagation();
      // Portal out of backdrop-filter .composer-card so position:fixed anchors to true viewport top!
      if (dom.composerPopover && dom.composerPopover.parentElement !== document.body) {
        document.body.appendChild(dom.composerPopover);
      }
      const willOpen = !dom.composerPopover.classList.contains("open");
      closeAllPopovers(willOpen ? "composer" : null);
      if (willOpen) {
        dom.composerPopover.hidden = false;
        dom.btnComposerPicker?.classList.add("is-open");
        dom.btnComposerPicker?.setAttribute("aria-expanded", "true");
        requestAnimationFrame(() => {
          dom.composerPopover.classList.add("open");
          updateEffortPill(state.thinkingEffort, false);
        });
      }
    });

    // Mobile Sidebar Search, Theme & Settings Footer Buttons
    $("#mobile-session-search")?.addEventListener("input", (e) => {
      if (dom.sessionSearch) dom.sessionSearch.value = e.target.value;
      handleSessionSearchInput();
    });
    $("#btn-mobile-sb-theme")?.addEventListener("click", () => {
      const cur = document.documentElement.dataset.theme === "light" ? "dark" : "light";
      applyTheme(cur);
    });
    $("#btn-mobile-sb-settings")?.addEventListener("click", () => {
      closeMobileNavIfOpen();
      setInspectorOpen(true, "general");
    });

    window.YerelSettings?.init({
      saveConfigSilent,
      applyTheme,
      showToast,
      closeArtifact: () => setArtifactOpen(false),
    });
    renderNotifications();

    const unlocked = await checkAuthState();
    if (unlocked) {
      await loadStudioBootstrap();
    }
  }

  document.addEventListener("DOMContentLoaded", init);
})();
