const state = {
  theme: localStorage.getItem("yerelai_theme") || "dark",
  models: [],
  loras: [],
  config: {},
  sessions: [],
  activeSessionId: null,
  messages: [],
  pendingAttachments: [],
  thinkingEffort: localStorage.getItem("yerelai_effort") || "medium",
  isGenerating: false,
  abortController: null,
  statusTimer: null,
  datasetModalCtx: null,
  rec: {
    active: false,
    stream: null,
    ctx: null,
    processor: null,
    analyser: null,
    chunks: [],
    rafId: null,
    timerId: null,
    startMs: 0,
  },
};

const els = {
  themeToggle: document.getElementById("btn-theme-toggle"),
  iconSun: document.getElementById("icon-sun"),
  iconMoon: document.getElementById("icon-moon"),
  sidebar: document.getElementById("sidebar"),
  btnMobileSidebar: document.getElementById("btn-mobile-sidebar"),
  btnNewChat: document.getElementById("btn-new-chat"),
  sessionSearch: document.getElementById("session-search"),
  sessionList: document.getElementById("session-list"),
  sessionFilesList: document.getElementById("session-files-list"),
  datasetCountBadge: document.getElementById("dataset-count-badge"),
  btnExportDataset: document.getElementById("btn-export-dataset"),
  btnDownloadColab: document.getElementById("btn-download-colab"),

  topStatusDot: document.getElementById("top-status-dot"),
  topModelName: document.getElementById("top-model-name"),
  topProfileBadge: document.getElementById("top-profile-badge"),
  vramDeviceName: document.getElementById("vram-device-name"),
  vramUsageText: document.getElementById("vram-usage-text"),
  vramFill: document.getElementById("vram-fill"),
  idleTimerBadge: document.getElementById("idle-timer-badge"),
  btnLoadModel: document.getElementById("btn-load-model"),
  btnUnloadModel: document.getElementById("btn-unload-model"),
  btnToggleInspector: document.getElementById("btn-toggle-inspector"),
  inspector: document.getElementById("inspector"),
  inspectorStateBadge: document.getElementById("inspector-state-badge"),

  dropZone: document.getElementById("drop-zone"),
  dragOverlay: document.getElementById("drag-overlay"),
  chatScroll: document.getElementById("chat-scroll"),
  welcomeHero: document.getElementById("welcome-hero"),
  messagesList: document.getElementById("messages-list"),

  effortPills: Array.from(document.querySelectorAll(".effort-pill")),
  chkAutoTts: document.getElementById("chk-auto-tts"),
  recordingBar: document.getElementById("recording-bar"),
  recWaveform: document.getElementById("rec-waveform"),
  recTimer: document.getElementById("rec-timer"),
  btnRecStop: document.getElementById("btn-rec-stop"),
  btnRecCancel: document.getElementById("btn-rec-cancel"),
  pendingAttachments: document.getElementById("pending-attachments"),
  fileInput: document.getElementById("file-input"),
  btnAttach: document.getElementById("btn-attach"),
  btnMic: document.getElementById("btn-mic"),
  promptInput: document.getElementById("prompt-input"),
  btnSend: document.getElementById("btn-send"),
  btnStop: document.getElementById("btn-stop"),

  selModel: document.getElementById("sel-model"),
  modelDesc: document.getElementById("model-desc"),
  selLora: document.getElementById("sel-lora"),
  rngLoraScale: document.getElementById("rng-lora-scale"),
  valLoraScale: document.getElementById("val-lora-scale"),
  selGpuProfile: document.getElementById("sel-gpu-profile"),
  rngTemp: document.getElementById("rng-temp"),
  valTemp: document.getElementById("val-temp"),
  rngTopP: document.getElementById("rng-top-p"),
  valTopP: document.getElementById("val-top-p"),
  rngMaxTokens: document.getElementById("rng-max-tokens"),
  valMaxTokens: document.getElementById("val-max-tokens"),
  rngIdleMin: document.getElementById("rng-idle-min"),
  valIdleMin: document.getElementById("val-idle-min"),
  txtSystemPrompt: document.getElementById("txt-system-prompt"),
  btnSaveConfig: document.getElementById("btn-save-config"),

  datasetModal: document.getElementById("dataset-modal"),
  btnModalClose: document.getElementById("btn-modal-close"),
  btnDsCancel: document.getElementById("btn-ds-cancel"),
  btnDsSave: document.getElementById("btn-ds-save"),
  dsUserInput: document.getElementById("ds-user-input"),
  dsAssistantInput: document.getElementById("ds-assistant-input"),
  toastContainer: document.getElementById("toast-container"),
};

function toast(msg, type = "info") {
  const div = document.createElement("div");
  div.className = `toast ${type}`;
  div.textContent = msg;
  els.toastContainer.appendChild(div);
  setTimeout(() => div.remove(), 4200);
}

async function apiFetch(url, opts = {}) {
  const headers = opts.body instanceof FormData ? {} : { "Content-Type": "application/json", ...(opts.headers || {}) };
  const res = await fetch(url, { ...opts, headers });
  if (!res.ok) {
    let detail = `HTTP ${res.status}`;
    try {
      const data = await res.json();
      detail = data.detail || detail;
    } catch {}
    throw new Error(detail);
  }
  return res.json();
}

function applyTheme(theme) {
  state.theme = theme === "light" ? "light" : "dark";
  document.documentElement.setAttribute("data-theme", state.theme);
  localStorage.setItem("yerelai_theme", state.theme);
  if (els.iconSun && els.iconMoon) {
    els.iconSun.hidden = state.theme === "light";
    els.iconMoon.hidden = state.theme === "dark";
  }
}

function setThinkingEffort(effort) {
  state.thinkingEffort = effort;
  localStorage.setItem("yerelai_effort", effort);
  els.effortPills.forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.effort === effort);
  });
}

function escapeHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatInlineMarkdown(raw) {
  let s = escapeHtml(raw);
  s = s.replace(/`([^`\n]+)`/g, "<code>$1</code>");
  s = s.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  s = s.replace(/\*([^*]+)\*/g, "<em>$1</em>");
  return s;
}

function renderMarkdown(md) {
  if (!md) return "";
  const blocks = [];
  const fenceRe = /```([a-zA-Z0-9_+-]*)\n([\s\S]*?)```/g;
  let last = 0;
  let m;
  while ((m = fenceRe.exec(md)) !== null) {
    if (m.index > last) blocks.push({ type: "text", val: md.slice(last, m.index) });
    blocks.push({ type: "code", lang: m[1] || "kod", val: m[2] });
    last = fenceRe.lastIndex;
  }
  if (last < md.length) blocks.push({ type: "text", val: md.slice(last) });

  return blocks
    .map((b) => {
      if (b.type === "code") {
        const safeCode = escapeHtml(b.val);
        const encoded = encodeURIComponent(b.val);
        return `
          <div class="code-block-wrap">
            <div class="code-block-head">
              <span class="mono">${escapeHtml(b.lang)}</span>
              <button type="button" class="code-copy-btn" data-copy="${encoded}">Kodu Kopyala</button>
            </div>
            <pre><code>${safeCode}</code></pre>
          </div>`;
      }
      return renderTextSegment(b.val);
    })
    .join("");
}

function renderTextSegment(text) {
  const lines = text.split(/\r?\n/);
  const out = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (/^\s*\|.+\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|[\s:-]+\|\s*$/.test(lines[i + 1])) {
      const headers = line.trim().slice(1, -1).split("|").map((c) => formatInlineMarkdown(c.trim()));
      i += 2;
      const rows = [];
      while (i < lines.length && /^\s*\|.+\|\s*$/.test(lines[i])) {
        const cols = lines[i].trim().slice(1, -1).split("|").map((c) => formatInlineMarkdown(c.trim()));
        rows.push(cols);
        i++;
      }
      const thead = `<tr>${headers.map((h) => `<th>${h}</th>`).join("")}</tr>`;
      const tbody = rows.map((r) => `<tr>${r.map((c) => `<td>${c}</td>`).join("")}</tr>`).join("");
      out.push(`<div class="md-table-wrap"><table class="md-table"><thead>${thead}</thead><tbody>${tbody}</tbody></table></div>`);
      continue;
    }
    if (/^###\s+/.test(line)) {
      out.push(`<h3>${formatInlineMarkdown(line.replace(/^###\s+/, ""))}</h3>`);
      i++;
      continue;
    }
    if (/^##\s+/.test(line)) {
      out.push(`<h2>${formatInlineMarkdown(line.replace(/^##\s+/, ""))}</h2>`);
      i++;
      continue;
    }
    if (/^#\s+/.test(line)) {
      out.push(`<h1>${formatInlineMarkdown(line.replace(/^#\s+/, ""))}</h1>`);
      i++;
      continue;
    }
    if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*[-*]\s+/.test(lines[i])) {
        items.push(`<li>${formatInlineMarkdown(lines[i].replace(/^\s*[-*]\s+/, ""))}</li>`);
        i++;
      }
      out.push(`<ul>${items.join("")}</ul>`);
      continue;
    }
    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (i < lines.length && /^\s*\d+\.\s+/.test(lines[i])) {
        items.push(`<li>${formatInlineMarkdown(lines[i].replace(/^\s*\d+\.\s+/, ""))}</li>`);
        i++;
      }
      out.push(`<ol>${items.join("")}</ol>`);
      continue;
    }
    if (!line.trim()) {
      i++;
      continue;
    }
    out.push(`<p>${formatInlineMarkdown(line)}</p>`);
    i++;
  }
  return out.join("");
}

function speakText(text) {
  if (!text) return;
  const clean = text.replace(/```[\s\S]*?```/g, " kod bloğu ").replace(/[`*_#>\[\]]/g, " ").trim();
  if ("speechSynthesis" in window) {
    window.speechSynthesis.cancel();
    const voices = window.speechSynthesis.getVoices();
    const trVoice = voices.find((v) => v.lang && v.lang.toLowerCase().startsWith("tr"));
    if (trVoice || voices.length > 0) {
      const utter = new SpeechSynthesisUtterance(clean.slice(0, 1400));
      utter.lang = "tr-TR";
      if (trVoice) utter.voice = trVoice;
      utter.rate = 1.04;
      window.speechSynthesis.speak(utter);
      return;
    }
  }
  fetch("/api/tts", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text: clean }),
  })
    .then((r) => (r.ok ? r.blob() : Promise.reject()))
    .then((blob) => {
      const url = URL.createObjectURL(blob);
      const audio = new Audio(url);
      audio.play().catch(() => {});
    })
    .catch(() => toast("Çevrimdışı seslendirme başlatılamadı.", "err"));
}

function renderStatus(status) {
  if (!status) return;
  const v = status.vram || {};
  const st = status.state || "unloaded";
  els.topStatusDot.className = `status-dot ${st}`;
  const stateLabels = {
    unloaded: "Beklemede",
    loading: "Yükleniyor...",
    ready: "GPU Hazır",
    generating: "Üretiyor",
    unloading: "Temizleniyor",
    error: "Hata",
  };
  els.inspectorStateBadge.textContent = stateLabels[st] || st;
  els.topProfileBadge.textContent = v.profile_label || "Otomatik";
  els.vramDeviceName.textContent = (v.device || "CPU").replace("NVIDIA GeForce ", "");
  const used = Number(v.allocated_mb ?? v.used_mb ?? 0);
  const total = Number(v.total_mb || 0);
  els.vramUsageText.textContent = `${used} / ${total} MB`;
  const pct = total > 0 ? Math.min(100, Math.round((used / total) * 100)) : 0;
  els.vramFill.style.width = `${pct}%`;

  const activeModel = state.models.find((m) => m.id === (status.active_model_id || els.selModel.value));
  if (activeModel) {
    els.topModelName.textContent = activeModel.name.replace(" (4-Bit Multimodal)", "");
  }

  const loaded = st === "ready" || st === "generating";
  els.btnLoadModel.hidden = loaded || st === "loading";
  els.btnUnloadModel.hidden = !loaded;

  if (st === "ready" && status.remaining_seconds > 0) {
    const mins = Math.floor(status.remaining_seconds / 60);
    const secs = Math.floor(status.remaining_seconds % 60);
    els.idleTimerBadge.textContent = `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
    els.idleTimerBadge.hidden = false;
  } else {
    els.idleTimerBadge.hidden = true;
  }
}

async function refreshStatus() {
  try {
    const st = await apiFetch("/api/status");
    renderStatus(st);
  } catch {}
}

async function loadInitialData() {
  try {
    const [mData, cfg, sData, dData] = await Promise.all([
      apiFetch("/api/models"),
      apiFetch("/api/config"),
      apiFetch("/api/sessions"),
      apiFetch("/api/dataset"),
    ]);

    state.models = mData.models || [];
    state.loras = mData.loras || [];
    state.config = cfg || {};
    state.sessions = sData.sessions || [];
    els.datasetCountBadge.textContent = `${dData.count || 0} örnek`;

    // Populate models dropdown
    els.selModel.innerHTML = "";
    state.models.forEach((m) => {
      const opt = document.createElement("option");
      opt.value = m.id;
      const cacheTag = m.cached_locally ? " [Hazır]" : " [İndirilecek]";
      opt.textContent = `${m.name}${cacheTag}`;
      els.selModel.appendChild(opt);
    });
    if (cfg.default_model_id) els.selModel.value = cfg.default_model_id;
    updateModelDesc();

    // Populate LoRA dropdown
    els.selLora.innerHTML = '<option value="">Adaptör Yok (Temel Model)</option>';
    state.loras.forEach((l) => {
      const opt = document.createElement("option");
      opt.value = l.id;
      opt.textContent = `${l.name}`;
      els.selLora.appendChild(opt);
    });
    if (cfg.active_lora_id) els.selLora.value = cfg.active_lora_id;
    els.rngLoraScale.value = cfg.lora_scale ?? 1.0;
    els.valLoraScale.textContent = `${Number(els.rngLoraScale.value).toFixed(1)}x`;

    els.selGpuProfile.value = cfg.gpu_profile || "auto";
    const g = cfg.generation || {};
    setThinkingEffort(g.thinking_effort || state.thinkingEffort);
    els.rngTemp.value = g.temperature ?? 0.7;
    els.valTemp.textContent = Number(els.rngTemp.value).toFixed(2);
    els.rngTopP.value = g.top_p ?? 0.95;
    els.valTopP.textContent = Number(els.rngTopP.value).toFixed(2);
    els.rngMaxTokens.value = g.max_new_tokens ?? 2048;
    els.valMaxTokens.textContent = els.rngMaxTokens.value;
    els.rngIdleMin.value = cfg.idle_timeout_minutes ?? 15;
    els.valIdleMin.textContent = `${els.rngIdleMin.value} dk`;
    els.txtSystemPrompt.value = cfg.system_prompt || "";
    els.chkAutoTts.checked = !!g.auto_tts;

    renderSessions();
    if (state.sessions.length > 0) {
      openSession(state.sessions[0].id);
    } else {
      startNewSession();
    }
    await refreshStatus();
  } catch (err) {
    toast(`Başlangıç verileri yüklenemedi: ${err.message}`, "err");
  }
}

function updateModelDesc() {
  const m = state.models.find((x) => x.id === els.selModel.value);
  if (m) {
    els.modelDesc.textContent = `${m.effective_params} · ~${m.vram_estimate_mb} MB VRAM · ${m.description}`;
  }
}

function startNewSession() {
  state.activeSessionId = `s_${Date.now().toString(36)}`;
  state.messages = [];
  state.pendingAttachments = [];
  renderPendingAttachments();
  renderMessages();
  renderSessions();
}

function openSession(id) {
  const s = state.sessions.find((x) => x.id === id);
  if (!s) return;
  state.activeSessionId = s.id;
  state.messages = JSON.parse(JSON.stringify(s.messages || []));
  renderMessages();
  renderSessions();
}

async function persistActiveSession() {
  if (!state.activeSessionId || state.messages.length === 0) return;
  const firstUser = state.messages.find((m) => m.role === "user");
  const title = (firstUser?.content || "Sesli / Dosyalı Sohbet").slice(0, 56);
  try {
    const res = await apiFetch("/api/sessions", {
      method: "POST",
      body: JSON.stringify({
        id: state.activeSessionId,
        title,
        messages: state.messages,
      }),
    });
    const idx = state.sessions.findIndex((s) => s.id === state.activeSessionId);
    if (idx >= 0) state.sessions.splice(idx, 1);
    state.sessions.unshift(res.session);
    renderSessions();
  } catch {}
}

async function deleteSession(id, e) {
  e.stopPropagation();
  try {
    await apiFetch(`/api/sessions/${id}`, { method: "DELETE" });
    state.sessions = state.sessions.filter((s) => s.id !== id);
    if (state.activeSessionId === id) {
      if (state.sessions.length > 0) openSession(state.sessions[0].id);
      else startNewSession();
    } else {
      renderSessions();
    }
  } catch {}
}

function renderSessions() {
  const q = (els.sessionSearch.value || "").trim().toLowerCase();
  const filtered = state.sessions.filter((s) => !q || (s.title || "").toLowerCase().includes(q));
  els.sessionList.innerHTML = "";
  if (filtered.length === 0) {
    els.sessionList.innerHTML = '<div class="muted-empty">Kayıtlı sohbet yok</div>';
    return;
  }
  filtered.forEach((s) => {
    const btn = document.createElement("div");
    btn.className = `session-item ${s.id === state.activeSessionId ? "active" : ""}`;
    btn.innerHTML = `<span class="session-title">${escapeHtml(s.title)}</span><button type="button" class="session-del" title="Sil">&times;</button>`;
    btn.addEventListener("click", () => openSession(s.id));
    btn.querySelector(".session-del").addEventListener("click", (e) => deleteSession(s.id, e));
    els.sessionList.appendChild(btn);
  });
}

function renderSessionFiles() {
  const seen = new Map();
  state.messages.forEach((m) => {
    (m.attachments || []).forEach((a) => seen.set(a.id, a));
  });
  state.pendingAttachments.forEach((a) => seen.set(a.id, a));
  if (seen.size === 0) {
    els.sessionFilesList.innerHTML = '<div class="muted-empty">Henüz dosya eklenmedi</div>';
    return;
  }
  els.sessionFilesList.innerHTML = "";
  seen.forEach((a) => {
    const d = document.createElement("div");
    d.className = "file-mini-item";
    d.innerHTML = `<strong>${escapeHtml(a.name)}</strong><span>${escapeHtml(a.summary || a.kind)}</span>`;
    els.sessionFilesList.appendChild(d);
  });
}

function renderPendingAttachments() {
  if (state.pendingAttachments.length === 0) {
    els.pendingAttachments.hidden = true;
    els.pendingAttachments.innerHTML = "";
    renderSessionFiles();
    return;
  }
  els.pendingAttachments.hidden = false;
  els.pendingAttachments.innerHTML = "";
  state.pendingAttachments.forEach((att, idx) => {
    const icon = att.kind === "image" ? "🖼️" : att.kind === "audio" ? "🎙️" : "📄";
    const chip = document.createElement("span");
    chip.className = "att-chip";
    chip.innerHTML = `<span>${icon} ${escapeHtml(att.name)} (${escapeHtml(att.summary || "")})</span><button type="button">&times;</button>`;
    chip.querySelector("button").addEventListener("click", () => {
      state.pendingAttachments.splice(idx, 1);
      renderPendingAttachments();
    });
    els.pendingAttachments.appendChild(chip);
  });
  renderSessionFiles();
}

function renderMessages() {
  els.welcomeHero.hidden = state.messages.length > 0;
  els.messagesList.innerHTML = "";
  state.messages.forEach((m, idx) => {
    els.messagesList.appendChild(createMessageNode(m, idx));
  });
  renderSessionFiles();
  els.chatScroll.scrollTop = els.chatScroll.scrollHeight;
}

function createMessageNode(m, idx) {
  const row = document.createElement("div");
  row.className = `msg-row ${m.role}`;
  const bubble = document.createElement("div");
  bubble.className = "msg-bubble";

  if (m.attachments && m.attachments.length > 0) {
    const attRow = document.createElement("div");
    attRow.className = "msg-att-row";
    m.attachments.forEach((a) => {
      if (a.kind === "image" && a.preview_url) {
        const img = document.createElement("img");
        img.src = a.preview_url;
        img.alt = a.name;
        img.className = "att-img-thumb";
        attRow.appendChild(img);
      } else if (a.kind === "audio" && a.preview_url) {
        const aud = document.createElement("audio");
        aud.controls = true;
        aud.src = a.preview_url;
        attRow.appendChild(aud);
      } else {
        const chip = document.createElement("span");
        chip.className = "att-chip-msg";
        chip.textContent = `📄 ${a.name} · ${a.summary || ""}`;
        attRow.appendChild(chip);
      }
    });
    bubble.appendChild(attRow);
  }

  if (m.role === "user") {
    const p = document.createElement("div");
    p.style.whiteSpace = "pre-wrap";
    p.textContent = m.content || (m.attachments?.length ? "(Ekli medya/dosya gönderildi)" : "");
    bubble.appendChild(p);
  } else {
    if (m.thinking || m._isThinkingLive) {
      const det = document.createElement("details");
      det.className = `thinking-box ${m._isThinkingLive ? "is-thinking" : ""}`;
      if (m._isThinkingLive) det.open = true;
      const summary = document.createElement("summary");
      summary.textContent = m._isThinkingLive
        ? "💭 Düşünülüyor (Akıl Yürütme Süreci)..."
        : `💭 Düşünme Süreci (${m.stats?.effort || state.thinkingEffort})`;
      const tc = document.createElement("div");
      tc.className = "thinking-content";
      tc.textContent = m.thinking || "";
      det.appendChild(summary);
      det.appendChild(tc);
      bubble.appendChild(det);
    }

    const md = document.createElement("div");
    md.className = "msg-markdown";
    md.innerHTML = renderMarkdown(m.content || (m._streaming ? "..." : ""));
    bubble.appendChild(md);

    if (!m._streaming) {
      const footer = document.createElement("div");
      footer.className = "msg-footer";
      const statsText = m.stats
        ? `${m.stats.tps} token/sn · ${m.stats.elapsed_sec}s · ${m.stats.tokens} token`
        : "Yerel Gemma 4";
      footer.innerHTML = `
        <span class="msg-stats mono">${escapeHtml(statsText)}</span>
        <div class="msg-actions">
          <button type="button" class="btn-outline-xs" data-act="speak">🔊 Seslendir</button>
          <button type="button" class="btn-outline-xs" data-act="copy">📋 Kopyala</button>
          <button type="button" class="btn-outline-xs accent" data-act="dataset">⭐ Colab Setine Ekle</button>
        </div>`;
      footer.querySelector('[data-act="speak"]').addEventListener("click", () => speakText(m.content));
      footer.querySelector('[data-act="copy"]').addEventListener("click", () => {
        navigator.clipboard.writeText(m.content || "");
        toast("Yanıt panoya kopyalandı.", "ok");
      });
      footer.querySelector('[data-act="dataset"]').addEventListener("click", () => openDatasetModal(idx));
      bubble.appendChild(footer);
    }
  }

  row.appendChild(bubble);
  return row;
}

function openDatasetModal(assistantIdx) {
  let userMsg = "";
  for (let i = assistantIdx - 1; i >= 0; i--) {
    if (state.messages[i].role === "user") {
      userMsg = state.messages[i].content || "";
      break;
    }
  }
  const assistMsg = state.messages[assistantIdx]?.content || "";
  els.dsUserInput.value = userMsg;
  els.dsAssistantInput.value = assistMsg;
  els.datasetModal.hidden = false;
}

async function saveDatasetModal() {
  try {
    await apiFetch("/api/dataset", {
      method: "POST",
      body: JSON.stringify({
        system_prompt: els.txtSystemPrompt.value,
        user_text: els.dsUserInput.value,
        assistant_text: els.dsAssistantInput.value,
        model_id: els.selModel.value,
        thinking_effort: state.thinkingEffort,
      }),
    });
    const d = await apiFetch("/api/dataset");
    els.datasetCountBadge.textContent = `${d.count || 0} örnek`;
    els.datasetModal.hidden = true;
    toast("Örnek Colab eğitim setine eklendi.", "ok");
  } catch (err) {
    toast(`Kaydedilemedi: ${err.message}`, "err");
  }
}

async function uploadFiles(fileList) {
  for (const f of Array.from(fileList)) {
    const fd = new FormData();
    fd.append("file", f);
    try {
      toast(`İşleniyor: ${f.name}...`);
      const meta = await apiFetch("/api/files/upload", { method: "POST", body: fd });
      state.pendingAttachments.push(meta);
      renderPendingAttachments();
      toast(`Hazır: ${meta.name} (${meta.summary})`, "ok");
    } catch (err) {
      toast(`Dosya hatası (${f.name}): ${err.message}`, "err");
    }
  }
}

async function sendMessage(overrideText = null) {
  if (state.isGenerating) return;
  const text = (overrideText !== null ? overrideText : els.promptInput.value).trim();
  if (!text && state.pendingAttachments.length === 0) return;

  const userMsg = {
    role: "user",
    content: text,
    attachments: [...state.pendingAttachments],
  };
  state.messages.push(userMsg);
  if (overrideText === null) {
    els.promptInput.value = "";
    els.promptInput.style.height = "auto";
  }
  state.pendingAttachments = [];
  renderPendingAttachments();

  const assistantMsg = {
    role: "assistant",
    content: "",
    thinking: "",
    _streaming: true,
    _isThinkingLive: state.thinkingEffort !== "off",
    stats: null,
  };
  state.messages.push(assistantMsg);
  renderMessages();

  state.isGenerating = true;
  els.btnSend.hidden = true;
  els.btnStop.hidden = false;
  state.abortController = new AbortController();

  const assistantNodeIdx = state.messages.length - 1;
  const payloadMessages = state.messages.slice(0, -1).map((m) => ({
    role: m.role,
    content: m.content || "",
    attachments: (m.attachments || []).map((a) => ({
      id: a.id,
      name: a.name,
      kind: a.kind,
      path: a.path,
      preview_url: a.preview_url,
      summary: a.summary,
      context_text: a.context_text,
    })),
  }));

  try {
    const res = await fetch("/api/chat", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      signal: state.abortController.signal,
      body: JSON.stringify({
        session_id: state.activeSessionId,
        model_id: els.selModel.value,
        lora_id: els.selLora.value,
        lora_scale: Number(els.rngLoraScale.value),
        thinking_effort: state.thinkingEffort,
        temperature: Number(els.rngTemp.value),
        top_p: Number(els.rngTopP.value),
        max_new_tokens: Number(els.rngMaxTokens.value),
        system_prompt: els.txtSystemPrompt.value,
        messages: payloadMessages,
      }),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);

    const reader = res.body.getReader();
    const decoder = new TextDecoder("utf-8");
    let sseBuf = "";

    const updateAssistantDOM = () => {
      const node = els.messagesList.children[assistantNodeIdx];
      if (!node) return;
      const fresh = createMessageNode(assistantMsg, assistantNodeIdx);
      els.messagesList.replaceChild(fresh, node);
      els.chatScroll.scrollTop = els.chatScroll.scrollHeight;
    };

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      sseBuf += decoder.decode(value, { stream: true });
      const parts = sseBuf.split("\n\n");
      sseBuf = parts.pop() || "";

      for (const part of parts) {
        const line = part.trim();
        if (!line.startsWith("data:")) continue;
        let ev;
        try {
          ev = JSON.parse(line.slice(5).trim());
        } catch {
          continue;
        }
        if (ev.type === "status") {
          els.inspectorStateBadge.textContent = ev.message || "Çalışıyor...";
          refreshStatus();
        } else if (ev.type === "thinking_delta") {
          assistantMsg._isThinkingLive = true;
          assistantMsg.thinking += ev.delta;
          updateAssistantDOM();
        } else if (ev.type === "answer_delta") {
          assistantMsg._isThinkingLive = false;
          assistantMsg.content += ev.delta;
          updateAssistantDOM();
        } else if (ev.type === "completed") {
          assistantMsg._isThinkingLive = false;
          assistantMsg._streaming = false;
          if (ev.thinking) assistantMsg.thinking = ev.thinking;
          if (ev.answer) assistantMsg.content = ev.answer;
          assistantMsg.stats = ev.stats || null;
          updateAssistantDOM();
          if (ev.stats?.vram) renderStatus({ state: "ready", active_model_id: els.selModel.value, vram: ev.stats.vram, remaining_seconds: 900 });
          if (els.chkAutoTts.checked && assistantMsg.content) {
            speakText(assistantMsg.content);
          }
        } else if (ev.type === "error") {
          throw new Error(ev.detail || "Üretim hatası");
        }
      }
    }
  } catch (err) {
    assistantMsg._streaming = false;
    assistantMsg._isThinkingLive = false;
    if (err.name !== "AbortError") {
      assistantMsg.content = assistantMsg.content || `Hata: ${err.message}`;
      toast(`Üretim hatası: ${err.message}`, "err");
    }
    renderMessages();
  } finally {
    state.isGenerating = false;
    els.btnSend.hidden = false;
    els.btnStop.hidden = true;
    await persistActiveSession();
    await refreshStatus();
  }
}

/* Native 16 kHz Mono WAV Browser Microphone Recorder */
function encodeWav16k(samples, sampleRate = 16000) {
  const len = samples.length;
  const buf = new ArrayBuffer(44 + len * 2);
  const view = new DataView(buf);
  const writeStr = (off, str) => {
    for (let i = 0; i < str.length; i++) view.setUint8(off + i, str.charCodeAt(i));
  };
  writeStr(0, "RIFF");
  view.setUint32(4, 36 + len * 2, true);
  writeStr(8, "WAVE");
  writeStr(12, "fmt ");
  view.setUint32(16, 16, true);
  view.setUint16(20, 1, true);
  view.setUint16(22, 1, true);
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true);
  view.setUint16(32, 2, true);
  view.setUint16(34, 16, true);
  writeStr(36, "data");
  view.setUint32(40, len * 2, true);
  let offset = 44;
  for (let i = 0; i < len; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7fff, true);
    offset += 2;
  }
  return new Blob([buf], { type: "audio/wav" });
}

function downsampleTo16k(float32Arr, inRate) {
  if (inRate === 16000) return float32Arr;
  const ratio = inRate / 16000;
  const outLen = Math.round(float32Arr.length / ratio);
  const out = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const start = Math.floor(i * ratio);
    const end = Math.min(float32Arr.length, Math.floor((i + 1) * ratio));
    let sum = 0;
    let count = 0;
    for (let j = start; j < end; j++) {
      sum += float32Arr[j];
      count++;
    }
    out[i] = count > 0 ? sum / count : float32Arr[start] || 0;
  }
  return out;
}

async function startMicRecording() {
  if (state.rec.active) return;
  try {
    const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    const src = ctx.createMediaStreamSource(stream);
    const analyser = ctx.createAnalyser();
    analyser.fftSize = 64;
    const processor = ctx.createScriptProcessor(4096, 1, 1);
    const chunks = [];
    processor.onaudioprocess = (e) => {
      chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
    };
    src.connect(analyser);
    analyser.connect(processor);
    processor.connect(ctx.destination);

    state.rec = {
      active: true,
      stream,
      ctx,
      processor,
      analyser,
      chunks,
      rafId: null,
      timerId: null,
      startMs: Date.now(),
    };

    els.recordingBar.hidden = false;
    els.btnMic.classList.add("recording");
    drawWaveform();
    state.rec.timerId = setInterval(() => {
      const sec = Math.floor((Date.now() - state.rec.startMs) / 1000);
      els.recTimer.textContent = `${String(Math.floor(sec / 60)).padStart(2, "0")}:${String(sec % 60).padStart(2, "0")}`;
    }, 250);
  } catch (err) {
    toast(`Mikrofon açılamadı: ${err.message}`, "err");
  }
}

function drawWaveform() {
  if (!state.rec.active || !state.rec.analyser) return;
  const canvas = els.recWaveform;
  const g = canvas.getContext("2d");
  const data = new Uint8Array(state.rec.analyser.frequencyBinCount);
  const loop = () => {
    if (!state.rec.active) return;
    state.rec.analyser.getByteFrequencyData(data);
    g.clearRect(0, 0, canvas.width, canvas.height);
    const barW = Math.max(3, Math.floor(canvas.width / data.length));
    for (let i = 0; i < data.length; i++) {
      const h = Math.max(3, (data[i] / 255) * canvas.height);
      g.fillStyle = "#f0713d";
      g.fillRect(i * (barW + 2), (canvas.height - h) / 2, barW, h);
    }
    state.rec.rafId = requestAnimationFrame(loop);
  };
  loop();
}

async function stopMicRecording(sendNow) {
  if (!state.rec.active) return;
  const { stream, ctx, processor, chunks, rafId, timerId } = state.rec;
  state.rec.active = false;
  if (rafId) cancelAnimationFrame(rafId);
  if (timerId) clearInterval(timerId);
  try { processor.disconnect(); } catch {}
  try { stream.getTracks().forEach((t) => t.stop()); } catch {}
  const sampleRate = ctx?.sampleRate || 48000;
  try { await ctx.close(); } catch {}
  els.recordingBar.hidden = true;
  els.btnMic.classList.remove("recording");

  if (!sendNow || chunks.length === 0) return;

  const totalLen = chunks.reduce((acc, c) => acc + c.length, 0);
  const merged = new Float32Array(totalLen);
  let pos = 0;
  for (const c of chunks) {
    merged.set(c, pos);
    pos += c.length;
  }
  const wav16k = encodeWav16k(downsampleTo16k(merged, sampleRate), 16000);
  const file = new File([wav16k], `sesli_komut_${Date.now()}.wav`, { type: "audio/wav" });
  await uploadFiles([file]);
  await sendMessage(els.promptInput.value.trim() || "");
}

/* Wire Events */
applyTheme(state.theme);
els.themeToggle.addEventListener("click", () => applyTheme(state.theme === "dark" ? "light" : "dark"));
els.btnMobileSidebar.addEventListener("click", () => els.sidebar.classList.toggle("open"));
els.btnToggleInspector.addEventListener("click", () => {
  els.inspector.classList.toggle("collapsed");
  els.btnToggleInspector.classList.toggle("active");
});

els.btnNewChat.addEventListener("click", startNewSession);
els.sessionSearch.addEventListener("input", renderSessions);

els.effortPills.forEach((btn) => {
  btn.addEventListener("click", () => setThinkingEffort(btn.dataset.effort));
});

els.btnAttach.addEventListener("click", () => els.fileInput.click());
els.fileInput.addEventListener("change", (e) => {
  if (e.target.files?.length) uploadFiles(e.target.files);
  e.target.value = "";
});

els.btnMic.addEventListener("click", () => {
  if (state.rec.active) stopMicRecording(true);
  else startMicRecording();
});
els.btnRecStop.addEventListener("click", () => stopMicRecording(true));
els.btnRecCancel.addEventListener("click", () => stopMicRecording(false));

els.promptInput.addEventListener("input", () => {
  els.promptInput.style.height = "auto";
  els.promptInput.style.height = `${Math.min(180, els.promptInput.scrollHeight)}px`;
});
els.promptInput.addEventListener("keydown", (e) => {
  if (e.key === "Enter" && !e.shiftKey) {
    e.preventDefault();
    sendMessage();
  }
});
els.btnSend.addEventListener("click", () => sendMessage());
els.btnStop.addEventListener("click", async () => {
  await apiFetch("/api/chat/stop", { method: "POST" }).catch(() => {});
  state.abortController?.abort();
});

els.messagesList.addEventListener("click", (e) => {
  const btn = e.target.closest(".code-copy-btn");
  if (!btn) return;
  navigator.clipboard.writeText(decodeURIComponent(btn.dataset.copy || ""));
  btn.textContent = "Kopyalandı!";
  setTimeout(() => (btn.textContent = "Kodu Kopyala"), 1400);
});

document.querySelectorAll(".starter-card").forEach((card) => {
  card.addEventListener("click", () => {
    const act = card.dataset.action;
    if (act === "excel" || act === "doc") els.fileInput.click();
    else if (act === "voice") startMicRecording();
    else if (act === "code") {
      setThinkingEffort("high");
      els.promptInput.value = "Python ile CSV dosyasını okuyup özet grafik oluşturan temiz bir betik yaz.";
      els.promptInput.focus();
    }
  });
});

["dragenter", "dragover"].forEach((ev) => {
  els.dropZone.addEventListener(ev, (e) => {
    e.preventDefault();
    els.dragOverlay.hidden = false;
  });
});
["dragleave", "drop"].forEach((ev) => {
  els.dropZone.addEventListener(ev, (e) => {
    e.preventDefault();
    els.dragOverlay.hidden = true;
  });
});
els.dropZone.addEventListener("drop", (e) => {
  if (e.dataTransfer?.files?.length) uploadFiles(e.dataTransfer.files);
});

els.selModel.addEventListener("change", updateModelDesc);
els.rngLoraScale.addEventListener("input", () => (els.valLoraScale.textContent = `${Number(els.rngLoraScale.value).toFixed(1)}x`));
els.rngTemp.addEventListener("input", () => (els.valTemp.textContent = Number(els.rngTemp.value).toFixed(2)));
els.rngTopP.addEventListener("input", () => (els.valTopP.textContent = Number(els.rngTopP.value).toFixed(2)));
els.rngMaxTokens.addEventListener("input", () => (els.valMaxTokens.textContent = els.rngMaxTokens.value));
els.rngIdleMin.addEventListener("input", () => (els.valIdleMin.textContent = `${els.rngIdleMin.value} dk`));

els.btnSaveConfig.addEventListener("click", async () => {
  try {
    await apiFetch("/api/config", {
      method: "PUT",
      body: JSON.stringify({
        default_model_id: els.selModel.value,
        active_lora_id: els.selLora.value,
        lora_scale: Number(els.rngLoraScale.value),
        gpu_profile: els.selGpuProfile.value,
        idle_timeout_minutes: Number(els.rngIdleMin.value),
        system_prompt: els.txtSystemPrompt.value,
        generation: {
          thinking_effort: state.thinkingEffort,
          temperature: Number(els.rngTemp.value),
          top_p: Number(els.rngTopP.value),
          max_new_tokens: Number(els.rngMaxTokens.value),
          auto_tts: els.chkAutoTts.checked,
        },
      }),
    });
    toast("Ayarlar kaydedildi.", "ok");
    refreshStatus();
  } catch (err) {
    toast(`Kaydedilemedi: ${err.message}`, "err");
  }
});

els.btnLoadModel.addEventListener("click", async () => {
  try {
    await apiFetch("/api/model/load", {
      method: "POST",
      body: JSON.stringify({
        model_id: els.selModel.value,
        lora_id: els.selLora.value,
        lora_scale: Number(els.rngLoraScale.value),
      }),
    });
    toast("Model GPU belleğine yükleniyor...");
    refreshStatus();
  } catch (err) {
    toast(`Model yüklenemedi: ${err.message}`, "err");
  }
});

els.btnUnloadModel.addEventListener("click", async () => {
  try {
    await apiFetch("/api/model/unload", { method: "POST" });
    toast("VRAM tamamen boşaltıldı.", "ok");
    refreshStatus();
  } catch (err) {
    toast(`Boşaltılamadı: ${err.message}`, "err");
  }
});

els.btnExportDataset.addEventListener("click", () => (window.location.href = "/api/dataset/export"));
els.btnDownloadColab.addEventListener("click", () => (window.location.href = "/api/colab/notebook"));
els.btnModalClose.addEventListener("click", () => (els.datasetModal.hidden = true));
els.btnDsCancel.addEventListener("click", () => (els.datasetModal.hidden = true));
els.btnDsSave.addEventListener("click", saveDatasetModal);

loadInitialData();
state.statusTimer = setInterval(refreshStatus, 3000);
