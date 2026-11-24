/* =========================================================
   YerelAI Studio · Centered Native Modal Settings Controller (v15.0)
   7-Category Claude/ChatGPT Layout · Hash Routing · Auto-Save
   Live QR Codes · Local Wi-Fi LAN · GitHub Static APK/iOS Bridge
   ========================================================= */
(() => {
  "use strict";

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));

  const VALID_TABS = new Set(["general", "desktop", "memory", "models", "extensions", "security", "admin", "colab"]);
  const ADMIN_ONLY_TABS = new Set(["models", "extensions", "security", "admin", "colab"]);

  let ctx = null;
  let activeTab = "general";
  let saveTimer = null;
  let tunnelRunning = false;
  let currentLanUrl = "";
  let isAdminUser = true;
  let selectedAdminActorId = null;

  function setSavePill(state) {
    const pill = $("#settings-save-pill");
    if (!pill) return;
    pill.classList.remove("is-saving", "is-err");
    if (state === "saving") {
      pill.classList.add("is-saving");
      pill.textContent = "Kaydediliyor...";
    } else if (state === "err") {
      pill.classList.add("is-err");
      pill.textContent = "Kaydedilemedi";
    } else {
      pill.textContent = "✓ Kaydedildi";
    }
  }

  function renderQrSvg(containerEl, urlText, emptyLabel = "Kapalı") {
    if (!containerEl) return;
    if (!urlText || !urlText.startsWith("http") || typeof window.qrcode !== "function") {
      containerEl.innerHTML = `<span class="qr-placeholder">${emptyLabel}</span>`;
      return;
    }
    try {
      const qr = window.qrcode(0, "M");
      qr.addData(urlText);
      qr.make();
      containerEl.innerHTML = qr.createSvgTag({ cellSize: 2, margin: 0, scalable: true });
    } catch (_) {
      containerEl.innerHTML = `<span class="qr-placeholder">QR Hazır</span>`;
    }
  }

  function syncThemeCards(themePref) {
    const pref = themePref || localStorage.getItem("yerelai_theme") || "dark";
    $$("#sp-theme-grid .sp-theme-card").forEach((card) => {
      card.classList.toggle("active", card.dataset.setTheme === pref);
    });
  }

  async function syncDesktopPrefsUI() {
    const grp = $("#desktop-only-prefs");
    const isDesktop = Boolean(window.yerelDesktop?.isElectron);
    if (grp) grp.hidden = !isDesktop;
    if (!isDesktop || !window.yerelDesktop?.getDesktopPrefs) return;
    try {
      const prefs = await window.yerelDesktop.getDesktopPrefs();
      const swAuto = $("#sw-desktop-autolaunch");
      const swTray = $("#sw-desktop-tray");
      const selHk = $("#sel-companion-hotkey");
      const kbdDisp = $("#kbd-companion-display");
      if (swAuto) swAuto.checked = Boolean(prefs.autoLaunch);
      if (swTray) swTray.checked = prefs.minimizeToTray !== false;
      if (selHk && prefs.companionHotkey) selHk.value = prefs.companionHotkey;
      if (kbdDisp && prefs.companionHotkey) kbdDisp.textContent = prefs.companionHotkey.replace(/\+/g, " + ");
    } catch (_) {}
  }

  function switchTab(tab, updateHash = true) {
    let next = VALID_TABS.has(tab) ? tab : "general";
    if (!isAdminUser && ADMIN_ONLY_TABS.has(next)) next = "general";
    activeTab = next;
    $$(".sp-nav-item").forEach((btn) => {
      const isAct = btn.dataset.spTab === next;
      btn.classList.toggle("active", isAct);
      btn.setAttribute("aria-selected", String(isAct));
    });
    $$(".sp-panel").forEach((panel) => {
      panel.hidden = panel.dataset.spPanel !== next;
    });
    if (next === "security") refreshTunnelStatus();
    if (next === "desktop") syncDesktopPrefsUI();
    if (next === "admin") loadAdminOverview();
    if (updateHash && $("#inspector") && !$("#inspector").hidden) {
      const desired = `#settings/${next}`;
      if (window.location.hash !== desired) {
        history.replaceState(null, "", desired);
      }
    }
  }

  function setAdminVisible(isAdmin) {
    isAdminUser = Boolean(isAdmin);
    $$(".sp-nav-item").forEach((btn) => {
      const tab = btn.dataset.spTab;
      if (ADMIN_ONLY_TABS.has(tab)) {
        btn.hidden = !isAdminUser;
      }
    });
    const navAdmin = $("#nav-tab-admin");
    if (navAdmin) navAdmin.hidden = !isAdminUser;
    if (!isAdminUser && ADMIN_ONLY_TABS.has(activeTab)) {
      switchTab("general", false);
    }
  }

  function escHtml(str) {
    return String(str || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function loadAdminOverview() {
    if (!isAdminUser) return;
    const listEl = $("#adm-profiles-list");
    const swGuest = $("#sw-admin-allow-guest");
    if (!listEl) return;
    try {
      const res = await fetch("/api/admin/overview");
      if (!res.ok) throw new Error("Admin verisi alınamadı");
      const data = await res.json();
      if (swGuest) swGuest.checked = data.allow_guest !== false;
      const profiles = Array.isArray(data.profiles) ? data.profiles : [];
      if (!profiles.length) {
        listEl.innerHTML = `<div class="muted-note">Henüz profil yok.</div>`;
        return;
      }
      listEl.innerHTML = profiles.map((p) => {
        const badge = p.role === "admin" ? "Admin" : (p.role === "guest" ? "Misafir" : "Üye");
        const canDel = p.actor_id !== "owner";
        return `
          <div class="adm-profile-row" data-actor="${escHtml(p.actor_id)}">
            <div class="adm-profile-info">
              <span class="adm-profile-name">${escHtml(p.display_name || p.username || p.actor_id)} <span class="badge-pill">${badge}</span></span>
              <span class="adm-profile-sub">ID: ${escHtml(p.actor_id)} · ${p.session_count || 0} sohbet · ${p.memory_count || 0} anı</span>
            </div>
            <div class="adm-profile-acts">
              <button class="btn-outline compact adm-btn-sessions" type="button" data-actor="${escHtml(p.actor_id)}" data-name="${escHtml(p.display_name || p.actor_id)}">Sohbetler</button>
              ${canDel ? `<button class="btn-outline compact danger adm-btn-del" type="button" data-actor="${escHtml(p.actor_id)}">Sil</button>` : ""}
            </div>
          </div>`;
      }).join("");
    } catch (err) {
      listEl.innerHTML = `<div class="muted-note">${escHtml(err.message)}</div>`;
    }
  }

  async function loadAdminActorSessions(actorId, displayName) {
    selectedAdminActorId = actorId;
    const box = $("#adm-sessions-box");
    const titleEl = $("#adm-sessions-title");
    const listEl = $("#adm-sessions-list");
    if (!box || !listEl) return;
    box.hidden = false;
    if (titleEl) titleEl.textContent = `${displayName || actorId} — Sohbetleri`;
    listEl.innerHTML = `<div class="muted-note">Yükleniyor...</div>`;
    try {
      const res = await fetch(`/api/admin/users/${encodeURIComponent(actorId)}/sessions`);
      if (!res.ok) throw new Error("Sohbetler alınamadı");
      const data = await res.json();
      const sessions = Array.isArray(data.sessions) ? data.sessions : [];
      if (!sessions.length) {
        listEl.innerHTML = `<div class="muted-note">Bu profile ait kayıtlı sohbet yok.</div>`;
        return;
      }
      listEl.innerHTML = sessions.map((s) => `
        <div class="adm-sess-row">
          <div>
            <strong>${escHtml(s.title || "Adsız Sohbet")}</strong>
            <div class="adm-profile-sub">${s.message_count || 0} mesaj · ${escHtml(s.updated_at || "")}</div>
          </div>
          <button class="btn-outline compact danger adm-btn-del-sess" type="button" data-sid="${escHtml(s.id)}">Sil</button>
        </div>
      `).join("");
    } catch (err) {
      listEl.innerHTML = `<div class="muted-note">${escHtml(err.message)}</div>`;
    }
  }

  function setOpen(open, tab = null, fromHash = false) {
    const page = $("#inspector");
    const btn = $("#btn-toggle-inspector");
    if (!page) return;
    const isOpen = Boolean(open);
    if (isOpen) {
      page.hidden = false;
      page.classList.add("open");
      page.setAttribute("aria-hidden", "false");
      btn?.classList.add("active");
      btn?.setAttribute("aria-expanded", "true");
      syncThemeCards(localStorage.getItem("yerelai_theme") || "dark");
      const selSend = $("#sel-send-mode");
      if (selSend) selSend.value = localStorage.getItem("yerelai_send_mode") || "enter";
      switchTab(tab || activeTab, !fromHash);
      if (!fromHash) {
        const targetHash = `#settings/${activeTab}`;
        if (window.location.hash !== targetHash) history.pushState(null, "", targetHash);
      }
    } else {
      page.classList.remove("open");
      page.hidden = true;
      page.setAttribute("aria-hidden", "true");
      btn?.classList.remove("active");
      btn?.setAttribute("aria-expanded", "false");
      if (!fromHash && window.location.hash.startsWith("#settings")) {
        history.pushState(null, "", window.location.pathname + window.location.search);
      }
    }
  }

  function scheduleAutoSave() {
    if (!ctx?.saveConfigSilent) return;
    setSavePill("saving");
    if (saveTimer) clearTimeout(saveTimer);
    saveTimer = setTimeout(async () => {
      const ok = await ctx.saveConfigSilent();
      setSavePill(ok ? "saved" : "err");
    }, 320);
  }

  function applyTunnelStatusToDOM(st) {
    const badge = $("#tunnel-status-badge");
    const inp = $("#inp-tunnel-url");
    const btnTog = $("#btn-tunnel-toggle");
    const btnCopy = $("#btn-tunnel-copy");
    if (!badge || !inp || !btnTog) return;

    tunnelRunning = Boolean(st.running);
    badge.textContent = st.running ? (st.mode === "named_domain" ? "Sabit Domain Aktif" : "Aktif") : st.url ? "Harici Aktif" : "Kapalı";
    badge.classList.toggle("ready", Boolean(st.running || st.url));
    inp.value = st.url || "";
    if (btnCopy) btnCopy.hidden = !st.url;
    btnTog.textContent = st.running ? "Tüneli Durdur" : "Tüneli Başlat";
    btnTog.disabled = !st.available;

    const swAuto = $("#sw-tunnel-autostart");
    if (swAuto) swAuto.checked = Boolean(st.auto_start);

    // QR codes: Live Tunnel & Fixed Home Wi-Fi LAN
    renderQrSvg($("#qr-tunnel-svg"), st.url || "", "Tünel kapalı");
    currentLanUrl = st.lan_url || "";
    const lblLan = $("#lbl-lan-url");
    if (lblLan && currentLanUrl) lblLan.textContent = currentLanUrl;
    renderQrSvg($("#qr-lan-svg"), currentLanUrl, "Wi-Fi Yok");

    // GitHub Permanent Static Bridge UI
    const ghBadge = $("#gh-sync-badge");
    const ghBox = $("#gh-static-links-box");
    const inpGhWeb = $("#inp-gh-web-url");
    const inpGhJson = $("#inp-gh-json-url");
    const lblGhSync = $("#lbl-gh-sync-time");
    const inpGhTok = $("#inp-gh-token");
    if (inpGhTok && st.has_github_token && !inpGhTok.value) {
      inpGhTok.value = "••••••••••••••••••••";
    }
    if (ghBadge) {
      if (st.static_json_url) {
        ghBadge.textContent = "Sabit Köprü Aktif";
        ghBadge.classList.add("ready");
      } else if (st.last_sync_error) {
        ghBadge.textContent = "Hata";
        ghBadge.classList.remove("ready");
      } else {
        ghBadge.textContent = "Yapılandırılmadı";
        ghBadge.classList.remove("ready");
      }
    }
    if (ghBox) {
      const hasStatic = Boolean(st.static_json_url && st.static_web_url);
      ghBox.hidden = !hasStatic;
      if (hasStatic) {
        if (inpGhWeb) inpGhWeb.value = st.static_web_url;
        if (inpGhJson) inpGhJson.value = st.static_json_url;
        renderQrSvg($("#qr-gh-svg"), st.static_web_url, "GitHub QR");
        if (lblGhSync) {
          lblGhSync.textContent = st.last_synced_at
            ? `Son otomatik senkronizasyon: ${st.last_synced_at}`
            : "Bu QR kod her zaman güncel tünelinize yönlendirir.";
        }
      }
    }

    const inpCfDom = $("#inp-cf-domain");
    const inpCfTok = $("#inp-cf-token");
    if (inpCfDom && st.cf_custom_domain && !inpCfDom.value) inpCfDom.value = st.cf_custom_domain;
    if (inpCfTok && st.has_cf_token && !inpCfTok.value) inpCfTok.value = "••••••••••••••••••••";
  }

  async function refreshTunnelStatus() {
    try {
      const res = await fetch("/api/tunnel/status");
      if (!res.ok) return;
      const st = await res.json();
      applyTunnelStatusToDOM(st);
    } catch (_) {}
  }

  async function toggleTunnel() {
    const btnTog = $("#btn-tunnel-toggle");
    if (!btnTog) return;
    btnTog.disabled = true;
    btnTog.textContent = tunnelRunning ? "Durduruluyor..." : "Başlatılıyor...";
    try {
      const endpoint = tunnelRunning ? "/api/tunnel/stop" : "/api/tunnel/start";
      const res = await fetch(endpoint, { method: "POST" });
      const st = await res.json();
      applyTunnelStatusToDOM(st);
      if (st.running && st.url) {
        ctx?.showToast?.("Uzaktan erişim tüneli açıldı ve QR kod hazırlandı", "ok", 3000);
      } else if (!st.running && !st.error) {
        ctx?.showToast?.("Tünel durduruldu", "ok", 2200);
      } else if (st.error) {
        ctx?.showToast?.(st.error, "err", 4200);
      }
    } catch (err) {
      ctx?.showToast?.(`Tünel hatası: ${err.message}`, "err", 3600);
    } finally {
      btnTog.disabled = false;
    }
  }

  function handleHashChange() {
    const h = window.location.hash || "";
    if (h.startsWith("#settings")) {
      const part = h.split("/")[1] || "general";
      setOpen(true, part, true);
    } else if ($("#inspector") && !$("#inspector").hidden) {
      setOpen(false, null, true);
    }
  }

  function init(bridge) {
    ctx = bridge;

    $$(".sp-nav-item").forEach((btn) => {
      btn.addEventListener("click", () => switchTab(btn.dataset.spTab, true));
    });

    $("#inspector")?.addEventListener("click", (e) => {
      if (e.target === $("#inspector")) setOpen(false);
    });

    $("#sp-theme-grid")?.addEventListener("click", (e) => {
      const card = e.target.closest(".sp-theme-card");
      if (!card) return;
      const t = card.dataset.setTheme;
      ctx?.applyTheme?.(t);
      syncThemeCards(t);
    });

    $("#sel-send-mode")?.addEventListener("change", (e) => {
      const mode = e.target.value === "ctrl_enter" ? "ctrl_enter" : "enter";
      localStorage.setItem("yerelai_send_mode", mode);
      setSavePill("saved");
      ctx?.showToast?.(mode === "ctrl_enter" ? "Ctrl + Enter ile gönderim aktif" : "Enter ile gönderim aktif", "ok", 1800);
    });

    // Desktop-only preferences
    $("#sw-desktop-autolaunch")?.addEventListener("change", async (e) => {
      await window.yerelDesktop?.setDesktopPref?.("autoLaunch", e.target.checked);
      setSavePill("saved");
    });
    $("#sw-desktop-tray")?.addEventListener("change", async (e) => {
      await window.yerelDesktop?.setDesktopPref?.("minimizeToTray", e.target.checked);
      setSavePill("saved");
    });
    $("#sel-companion-hotkey")?.addEventListener("change", async (e) => {
      const hk = e.target.value;
      await window.yerelDesktop?.setDesktopPref?.("companionHotkey", hk);
      const disp = $("#kbd-companion-display");
      if (disp) disp.textContent = hk.replace(/\+/g, " + ");
      setSavePill("saved");
      ctx?.showToast?.(`Hızlı Sor kısayolu: ${hk}`, "ok", 2200);
    });
    $("#btn-open-config-file")?.addEventListener("click", () => window.yerelDesktop?.openPath?.("config"));
    $("#btn-open-logs-dir")?.addEventListener("click", () => window.yerelDesktop?.openPath?.("logs"));

    // Full JSON data backup
    $("#btn-export-all-data")?.addEventListener("click", () => {
      const a = document.createElement("a");
      a.href = "/api/sessions/export-all";
      a.download = "";
      a.click();
      ctx?.showToast?.("Tüm sohbet ve hafıza yedeği indiriliyor", "ok", 2200);
    });

    // Tunnel + Auto-start + LAN + GitHub Permanent Bridge
    $("#btn-tunnel-toggle")?.addEventListener("click", toggleTunnel);
    $("#btn-tunnel-copy")?.addEventListener("click", async () => {
      const val = ($("#inp-tunnel-url")?.value || "").trim();
      if (!val) return;
      await navigator.clipboard.writeText(val);
      ctx?.showToast?.("Tünel adresi kopyalandı", "ok", 2000);
    });
    $("#btn-lan-copy")?.addEventListener("click", async () => {
      if (!currentLanUrl) return;
      await navigator.clipboard.writeText(currentLanUrl);
      ctx?.showToast?.(`Sabit Wi-Fi adresi kopyalandı: ${currentLanUrl}`, "ok", 2200);
    });
    $("#sw-tunnel-autostart")?.addEventListener("change", async (e) => {
      try {
        const res = await fetch("/api/tunnel/config", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ auto_start: e.target.checked }),
        });
        if (res.ok) applyTunnelStatusToDOM(await res.json());
        setSavePill("saved");
      } catch (_) {}
    });

    $("#btn-gh-save-sync")?.addEventListener("click", async () => {
      const btn = $("#btn-gh-save-sync");
      const tok = ($("#inp-gh-token")?.value || "").trim();
      if (!tok) return ctx?.showToast?.("GitHub Personal Access Token (gist yetkili) girin", "warn", 2600);
      if (btn) { btn.disabled = true; btn.textContent = "Senkronize Ediliyor..."; }
      try {
        const res = await fetch("/api/tunnel/config", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ github_token: tok, sync_github: true }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "GitHub senkronizasyonu başarısız");
        applyTunnelStatusToDOM(data);
        setSavePill("saved");
        ctx?.showToast?.("GitHub Sabit Domain & APK/iOS Köprüsü oluşturuldu!", "ok", 3200);
      } catch (err) {
        ctx?.showToast?.(err.message, "err", 4200);
      } finally {
        if (btn) { btn.disabled = false; btn.textContent = "Kaydet & Sabit Link Oluştur"; }
      }
    });

    $("#btn-gh-web-copy")?.addEventListener("click", async () => {
      const val = ($("#inp-gh-web-url")?.value || "").trim();
      if (!val) return;
      await navigator.clipboard.writeText(val);
      ctx?.showToast?.("Sabit Web / Safari giriş adresi kopyalandı", "ok", 2200);
    });
    $("#btn-gh-json-copy")?.addEventListener("click", async () => {
      const val = ($("#inp-gh-json-url")?.value || "").trim();
      if (!val) return;
      await navigator.clipboard.writeText(val);
      ctx?.showToast?.("Sabit APK / iOS JSON API adresi kopyalandı", "ok", 2200);
    });

    $("#btn-cf-token-save")?.addEventListener("click", async () => {
      const domVal = ($("#inp-cf-domain")?.value || "").trim();
      const tokVal = ($("#inp-cf-token")?.value || "").trim();
      try {
        const res = await fetch("/api/tunnel/config", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ cf_custom_domain: domVal, cf_named_token: tokVal }),
        });
        if (res.ok) applyTunnelStatusToDOM(await res.json());
        setSavePill("saved");
        ctx?.showToast?.("Sabit Cloudflare Tunnel ayarları kaydedildi", "ok", 2400);
      } catch (err) {
        ctx?.showToast?.(err.message, "err");
      }
    });

    // Admin & Multi-User Controls
    $("#sw-admin-allow-guest")?.addEventListener("change", async (e) => {
      try {
        const res = await fetch("/api/admin/settings", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ allow_guest: e.target.checked }),
        });
        if (!res.ok) throw new Error("Güncellenemedi");
        setSavePill("saved");
        ctx?.showToast?.(e.target.checked ? "Misafir erişimi açıldı" : "Misafir erişimi kapatıldı", "ok", 2200);
      } catch (err) {
        ctx?.showToast?.(err.message, "err");
      }
    });

    $("#btn-adm-add-user")?.addEventListener("click", async () => {
      const username = ($("#adm-user-name")?.value || "").trim();
      const displayName = ($("#adm-user-display")?.value || "").trim();
      const pin = ($("#adm-user-pin")?.value || "").trim();
      if (!username || pin.length < 4) {
        return ctx?.showToast?.("Kullanıcı adı ve en az 4 karakter şifre girin", "warn", 2600);
      }
      try {
        const res = await fetch("/api/admin/users", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ username, display_name: displayName || username, pin }),
        });
        const data = await res.json();
        if (!res.ok) throw new Error(data.detail || "Kullanıcı eklenemedi");
        if ($("#adm-user-name")) $("#adm-user-name").value = "";
        if ($("#adm-user-display")) $("#adm-user-display").value = "";
        if ($("#adm-user-pin")) $("#adm-user-pin").value = "";
        ctx?.showToast?.(`"${username}" kullanıcısı oluşturuldu`, "ok", 2400);
        loadAdminOverview();
      } catch (err) {
        ctx?.showToast?.(err.message, "err");
      }
    });

    $("#btn-adm-refresh")?.addEventListener("click", loadAdminOverview);
    $("#btn-adm-close-sess")?.addEventListener("click", () => {
      const box = $("#adm-sessions-box");
      if (box) box.hidden = true;
      selectedAdminActorId = null;
    });
    $("#btn-adm-clear-all-sess")?.addEventListener("click", async () => {
      if (!selectedAdminActorId) return;
      if (!confirm("Bu profilin tüm sohbet geçmişi silinsin mi?")) return;
      try {
        const res = await fetch(`/api/admin/users/${encodeURIComponent(selectedAdminActorId)}/sessions`, { method: "DELETE" });
        if (!res.ok) throw new Error("Silinemedi");
        ctx?.showToast?.("Profilin tüm sohbetleri temizlendi", "ok", 2200);
        loadAdminActorSessions(selectedAdminActorId);
        loadAdminOverview();
      } catch (err) {
        ctx?.showToast?.(err.message, "err");
      }
    });

    $("#adm-profiles-list")?.addEventListener("click", async (e) => {
      const btnSess = e.target.closest(".adm-btn-sessions");
      if (btnSess) {
        loadAdminActorSessions(btnSess.dataset.actor, btnSess.dataset.name);
        return;
      }
      const btnDel = e.target.closest(".adm-btn-del");
      if (btnDel) {
        const actor = btnDel.dataset.actor;
        if (!confirm(`"${actor}" profili ve tüm verileri silinsin mi?`)) return;
        try {
          const res = await fetch(`/api/admin/users/${encodeURIComponent(actor)}`, { method: "DELETE" });
          if (!res.ok) throw new Error("Profil silinemedi");
          ctx?.showToast?.("Profil silindi", "ok", 2000);
          if (selectedAdminActorId === actor && $("#adm-sessions-box")) {
            $("#adm-sessions-box").hidden = true;
            selectedAdminActorId = null;
          }
          loadAdminOverview();
        } catch (err) {
          ctx?.showToast?.(err.message, "err");
        }
      }
    });

    $("#adm-sessions-list")?.addEventListener("click", async (e) => {
      const btn = e.target.closest(".adm-btn-del-sess");
      if (!btn || !selectedAdminActorId) return;
      const sid = btn.dataset.sid;
      try {
        const res = await fetch(`/api/admin/users/${encodeURIComponent(selectedAdminActorId)}/sessions/${encodeURIComponent(sid)}`, { method: "DELETE" });
        if (!res.ok) throw new Error("Sohbet silinemedi");
        ctx?.showToast?.("Sohbet silindi", "ok", 1800);
        loadAdminActorSessions(selectedAdminActorId);
        loadAdminOverview();
      } catch (err) {
        ctx?.showToast?.(err.message, "err");
      }
    });

    // Auto-save triggers on all settings controls
    ["sw-auto-tts", "sw-web-search", "rng-temp", "rng-top-p", "rng-max-tokens", "rng-idle-min", "rng-lora-scale"].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.addEventListener("change", scheduleAutoSave);
    });
    $("#txt-system-prompt")?.addEventListener("input", scheduleAutoSave);

    window.addEventListener("hashchange", handleHashChange);
    if (window.location.hash.startsWith("#settings")) handleHashChange();
  }

  window.YerelSettings = {
    init,
    setOpen,
    switchTab,
    scheduleAutoSave,
    syncThemeCards,
    syncDesktopPrefsUI,
    refreshTunnelStatus,
    setAdminVisible,
    loadAdminOverview,
  };
})();
