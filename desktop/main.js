const {
  app,
  BrowserWindow,
  Tray,
  Menu,
  globalShortcut,
  ipcMain,
  shell,
  desktopCapturer,
  screen,
  nativeImage,
  nativeTheme,
  Notification,
  session,
  dialog,
  clipboard,
} = require("electron");
const path = require("path");
const fs = require("fs");
const http = require("http");
const { spawn, execFileSync } = require("child_process");

const ROOT_DIR = path.resolve(__dirname, "..");
const STATE_FILE = path.join(__dirname, "window-state.json");
const BACKEND_URL = "http://127.0.0.1:8070";

function resolvePythonExe() {
  const candidates = [
    process.env.YERELAI_PYTHON,
    path.join(process.env.USERPROFILE || "", ".unsloth", "studio", "unsloth_studio", "Scripts", "python.exe"),
    path.join(ROOT_DIR, ".venv", "Scripts", "python.exe"),
    path.join(ROOT_DIR, "venv", "Scripts", "python.exe"),
  ].filter(Boolean);
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return p;
    } catch (_) {}
  }
  return "python";
}
const PYTHON_EXE = resolvePythonExe();
const ALLOWED_HOTKEYS = new Set(["Alt+Space", "Ctrl+Alt+Space", "Ctrl+Shift+Space"]);

let mainWin = null;
let splashWin = null;
let companionWin = null;
let tray = null;
let trayReady = false;
let trayPollTimer = null;
let lastTraySummary = "Beklemede";
let backendProc = null;
let isQuitting = false;
let shutdownDone = false;
let splashShownAt = 0;
let activeHotkey = null;
let winState = loadWindowState();

const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
}

function resolveEffectiveTheme(pref) {
  if (pref === "light") return "light";
  if (pref === "dark") return "dark";
  return nativeTheme.shouldUseDarkColors ? "dark" : "light";
}

function loadWindowState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const raw = JSON.parse(fs.readFileSync(STATE_FILE, "utf-8"));
      return {
        width: Number(raw.width) || 1380,
        height: Number(raw.height) || 880,
        x: typeof raw.x === "number" ? raw.x : undefined,
        y: typeof raw.y === "number" ? raw.y : undefined,
        maximized: Boolean(raw.maximized),
        theme: raw.theme === "dark" || raw.theme === "system" ? raw.theme : "light",
        minimizeToTray: raw.minimizeToTray !== false,
        companionHotkey: ALLOWED_HOTKEYS.has(raw.companionHotkey) ? raw.companionHotkey : "Alt+Space",
      };
    }
  } catch (_) {}
  return {
    width: 1380,
    height: 880,
    maximized: false,
    theme: "light",
    minimizeToTray: true,
    companionHotkey: "Alt+Space",
  };
}

function saveWindowState() {
  try {
    if (mainWin && !mainWin.isDestroyed()) {
      const isMax = mainWin.isMaximized();
      winState.maximized = isMax;
      if (!isMax) {
        const b = mainWin.getBounds();
        if (b.width >= 800 && b.height >= 500) {
          winState.width = b.width;
          winState.height = b.height;
          winState.x = b.x;
          winState.y = b.y;
        }
      }
    }
    fs.writeFileSync(STATE_FILE, JSON.stringify(winState, null, 2), "utf-8");
  } catch (_) {}
}

function isBoundsOnAnyDisplay(x, y, width, height) {
  if (typeof x !== "number" || typeof y !== "number") return false;
  const cx = x + Math.round(width / 2);
  const cy = y + Math.round(Math.min(height, 120) / 2);
  return screen.getAllDisplays().some((d) => {
    const wa = d.workArea;
    return cx >= wa.x && cx <= wa.x + wa.width && cy >= wa.y && cy <= wa.y + wa.height;
  });
}

function fetchLocalJson(apiPath, method = "GET", timeoutMs = 2000) {
  return new Promise((resolve) => {
    const req = http.request(`${BACKEND_URL}${apiPath}`, { method, timeout: timeoutMs }, (res) => {
      let body = "";
      res.on("data", (ch) => { body += ch; });
      res.on("end", () => {
        try {
          resolve({ ok: res.statusCode >= 200 && res.statusCode < 400, data: JSON.parse(body) });
        } catch (_) {
          resolve({ ok: res.statusCode >= 200 && res.statusCode < 400, data: null });
        }
      });
    });
    req.on("error", () => resolve({ ok: false, data: null }));
    req.on("timeout", () => { req.destroy(); resolve({ ok: false, data: null }); });
    req.end();
  });
}

function postLocalApi(apiPath, timeoutMs = 2500) {
  return fetchLocalJson(apiPath, "POST", timeoutMs).then((r) => r.ok);
}

function checkBackendAlive() {
  return fetchLocalJson("/api/status", "GET", 1200).then((r) => r.ok);
}

function sendSplashStep(step, text, fade = false) {
  if (splashWin && !splashWin.isDestroyed()) {
    splashWin.webContents.send("splash:status", { step, text, fade });
  }
}

async function ensureBackendStarted() {
  sendSplashStep(1, "Yerel GPU motoru kontrol ediliyor...");
  if (await checkBackendAlive()) {
    sendSplashStep(2, "CUDA motoru hazır · Bağlanılıyor...");
    return true;
  }
  sendSplashStep(1, "FastAPI & CUDA motoru başlatılıyor...");
  try {
    backendProc = spawn(PYTHON_EXE, [path.join(ROOT_DIR, "backend.py")], {
      cwd: ROOT_DIR,
      windowsHide: true,
      stdio: "ignore",
    });
    backendProc.on("exit", () => { backendProc = null; });
  } catch (_) {
    return false;
  }

  for (let i = 0; i < 300; i++) {
    if (i === 4) sendSplashStep(2, "Donanım & kütüphaneler doğrulanıyor...");
    if (i === 35) sendSplashStep(2, "CUDA & Gemma 4 bileşenleri hazırlanıyor...");
    if (i === 90) sendSplashStep(2, "İlk kurulum paketleri tamamlanıyor...");
    if (await checkBackendAlive()) {
      sendSplashStep(3, "Stüdyo arayüzü hazırlanıyor...");
      return true;
    }
    await new Promise((r) => setTimeout(r, 300));
  }
  return false;
}

function getTitleBarOverlayColors(themePref) {
  const eff = resolveEffectiveTheme(themePref);
  if (eff === "light") {
    return { color: "#00000000", symbolColor: "#1f1b16", height: 44 };
  }
  return { color: "#00000000", symbolColor: "#e2e8f0", height: 44 };
}

function applyThemeToAllWindows() {
  const eff = resolveEffectiveTheme(winState.theme);
  if (mainWin && !mainWin.isDestroyed() && mainWin.setTitleBarOverlay) {
    try { mainWin.setTitleBarOverlay(getTitleBarOverlayColors(winState.theme)); } catch (_) {}
  }
  if (companionWin && !companionWin.isDestroyed()) {
    companionWin.webContents.send("desktop:theme", eff);
  }
}

function registerCompanionShortcut(hotkey) {
  const target = ALLOWED_HOTKEYS.has(hotkey) ? hotkey : "Alt+Space";
  if (activeHotkey) {
    try { globalShortcut.unregister(activeHotkey); } catch (_) {}
    activeHotkey = null;
  }
  try {
    const ok = globalShortcut.register(target, toggleCompanion);
    if (ok) activeHotkey = target;
    return ok;
  } catch (_) {
    return false;
  }
}

function buildBackendErrorHtml() {
  const eff = resolveEffectiveTheme(winState.theme);
  const bg = eff === "light" ? "#f3eee4" : "#14161c";
  const card = eff === "light" ? "#fdfbf7" : "#20242f";
  const tx = eff === "light" ? "#1f1b16" : "#eef0f4";
  const mu = eff === "light" ? "#6c6255" : "#a1a9b8";
  return "data:text/html;charset=utf-8," + encodeURIComponent(`<!DOCTYPE html>
<html lang="tr"><head><meta charset="UTF-8"><title>YerelAI Motor Hatası</title>
<style>
  body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:${bg};color:${tx};font-family:"Segoe UI",system-ui,sans-serif;}
  .box{max-width:440px;padding:28px;border-radius:18px;background:${card};border:1px solid rgba(148,163,184,.2);text-align:center;}
  h2{margin:0 0 8px;font-size:18px;} p{margin:0 0 18px;font-size:13.5px;color:${mu};line-height:1.5;}
  .row{display:flex;gap:10px;justify-content:center;}
  button{padding:9px 16px;border-radius:10px;border:none;font-weight:600;cursor:pointer;font-size:13px;}
  .p{background:#2563eb;color:#fff;} .g{background:rgba(148,163,184,.16);color:${tx};}
</style></head><body>
  <div class="box">
    <h2>YerelAI Motoru Başlatılamadı</h2>
    <p>Yerel FastAPI sunucusuna (127.0.0.1:8070) erişilemedi. Motoru yeniden başlatabilir veya günlük dosyasını inceleyebilirsiniz.</p>
    <div class="row">
      <button class="p" onclick="window.yerelDesktop?.restartBackend()">Motoru Yeniden Başlat</button>
      <button class="g" onclick="window.yerelDesktop?.openPath('logs')">Log Klasörünü Aç</button>
    </div>
  </div>
</body></html>`);
}

function createSplashWindow() {
  splashShownAt = Date.now();
  const eff = resolveEffectiveTheme(winState.theme);
  splashWin = new BrowserWindow({
    width: 400,
    height: 276,
    frame: false,
    transparent: true,
    hasShadow: false,
    backgroundColor: "#00000000",
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    center: true,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  splashWin.loadFile(path.join(__dirname, "splash.html"), { query: { theme: eff } });
}

function createMainWindow(backendOk = true) {
  const iconPath = path.join(__dirname, "icon.png");
  const eff = resolveEffectiveTheme(winState.theme);
  const validPos = isBoundsOnAnyDisplay(winState.x, winState.y, winState.width, winState.height);

  mainWin = new BrowserWindow({
    width: winState.width,
    height: winState.height,
    ...(validPos ? { x: winState.x, y: winState.y } : { center: true }),
    minWidth: 960,
    minHeight: 620,
    show: false,
    icon: iconPath,
    title: "SEN.AI",
    backgroundColor: eff === "light" ? "#f9f9f8" : "#171719",
    titleBarStyle: "hidden",
    titleBarOverlay: getTitleBarOverlayColors(winState.theme),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
      spellcheck: true,
    },
  });

  if (backendOk) {
    session.defaultSession.clearCache().catch(() => {}).finally(() => {
      if (mainWin && !mainWin.isDestroyed()) mainWin.loadURL(BACKEND_URL);
    });
  } else {
    mainWin.loadURL(buildBackendErrorHtml());
  }

  mainWin.webContents.on("did-fail-load", (_ev, code, _desc, url) => {
    if (code !== -3 && url && url.startsWith(BACKEND_URL)) {
      mainWin.loadURL(buildBackendErrorHtml());
    }
  });

  // Native Windows 11 Right-Click Context Menu (Spelling + Copy/Paste + Ask YerelAI)
  mainWin.webContents.on("context-menu", (_ev, params) => {
    const template = [];
    if (params.misspelledWord && params.dictionarySuggestions?.length) {
      for (const s of params.dictionarySuggestions.slice(0, 4)) {
        template.push({ label: s, click: () => mainWin.webContents.replaceMisspelling(s) });
      }
      template.push({ type: "separator" });
    }
    if (params.selectionText && params.selectionText.trim().length > 1) {
      const sel = params.selectionText.trim();
      template.push({
        label: "Seçili Metni SEN.AI'ya Sor",
        click: () => mainWin.webContents.send("desktop:context-ask", sel),
      });
      template.push({ type: "separator" });
    }
    if (params.isEditable) {
      template.push(
        { label: "Geri Al", role: "undo" },
        { label: "Yinele", role: "redo" },
        { type: "separator" },
        { label: "Kes", role: "cut", enabled: params.editFlags.canCut },
        { label: "Kopyala", role: "copy", enabled: params.editFlags.canCopy },
        { label: "Yapıştır", role: "paste", enabled: params.editFlags.canPaste },
        { label: "Tümünü Seç", role: "selectAll" }
      );
    } else if (params.selectionText) {
      template.push({ label: "Kopyala", role: "copy" });
    }
    if (template.length) {
      Menu.buildFromTemplate(template).popup({ window: mainWin });
    }
  });

  let revealed = false;
  const revealMain = () => {
    if (revealed || !mainWin || mainWin.isDestroyed()) return;
    revealed = true;
    const elapsed = Date.now() - splashShownAt;
    const minHold = Math.max(0, 1900 - elapsed);
    setTimeout(() => {
      sendSplashStep(3, "Hazır — açılıyor...", true);
      setTimeout(() => {
        if (splashWin && !splashWin.isDestroyed()) {
          splashWin.close();
          splashWin = null;
        }
        if (mainWin && !mainWin.isDestroyed() && !mainWin.isVisible()) {
          if (winState.maximized) mainWin.maximize();
          mainWin.show();
          mainWin.focus();
        }
      }, 240);
    }, minHold);
  };

  mainWin.once("ready-to-show", revealMain);
  setTimeout(revealMain, 4200);

  mainWin.on("resize", saveWindowState);
  mainWin.on("move", saveWindowState);

  mainWin.webContents.setWindowOpenHandler(({ url }) => {
    if (url && (url.startsWith("http://") || url.startsWith("https://"))) {
      if (!url.startsWith(BACKEND_URL)) {
        shell.openExternal(url);
        return { action: "deny" };
      }
    }
    return {
      action: "allow",
      overrideBrowserWindowOptions: {
        autoHideMenuBar: true,
        width: 1080,
        height: 760,
        icon: iconPath,
        title: "YerelAI Önizleme",
      },
    };
  });

  mainWin.on("close", (e) => {
    saveWindowState();
    if (!isQuitting && trayReady && winState.minimizeToTray) {
      e.preventDefault();
      mainWin.hide();
    }
  });
}

function createCompanionWindow() {
  const wa = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
  const w = 660;
  const h = 116;
  companionWin = new BrowserWindow({
    width: w,
    height: h,
    x: wa.x + Math.round((wa.width - w) / 2),
    y: wa.y + 110,
    frame: false,
    transparent: true,
    hasShadow: false,
    backgroundColor: "#00000000",
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });
  companionWin.loadFile(path.join(__dirname, "companion.html"));
  companionWin.webContents.once("did-finish-load", () => {
    companionWin.webContents.send("desktop:theme", resolveEffectiveTheme(winState.theme));
  });
  companionWin.on("blur", () => {
    if (companionWin && !companionWin.isDestroyed()) companionWin.hide();
  });
}

function toggleCompanion() {
  if (!companionWin || companionWin.isDestroyed()) createCompanionWindow();
  if (companionWin.isVisible()) {
    companionWin.hide();
  } else {
    const wa = screen.getDisplayNearestPoint(screen.getCursorScreenPoint()).workArea;
    companionWin.setPosition(wa.x + Math.round((wa.width - 660) / 2), wa.y + 110);
    companionWin.webContents.send("desktop:theme", resolveEffectiveTheme(winState.theme));
    companionWin.show();
    companionWin.focus();
  }
}

function showMainWindow() {
  if (!mainWin || mainWin.isDestroyed()) createMainWindow(true);
  if (mainWin.isMinimized()) mainWin.restore();
  mainWin.show();
  mainWin.focus();
}

function getAutoLaunchEnabled() {
  try {
    return Boolean(app.getLoginItemSettings().openAtLogin);
  } catch (_) {
    return false;
  }
}

function setAutoLaunchEnabled(enabled) {
  try {
    app.setLoginItemSettings({
      openAtLogin: Boolean(enabled),
      path: process.execPath,
      args: [__dirname],
    });
    return true;
  } catch (_) {
    return false;
  }
}

function rebuildTrayMenu() {
  if (!tray || tray.isDestroyed()) return;
  const hk = winState.companionHotkey || "Alt+Space";
  tray.setToolTip(`SEN.AI · ${lastTraySummary} (${hk})`);
  const menu = Menu.buildFromTemplate([
    { label: `GPU: ${lastTraySummary}`, enabled: false },
    { type: "separator" },
    { label: "SEN.AI'yı Aç", click: showMainWindow },
    { label: `Hızlı Sor (${hk})`, click: toggleCompanion },
    {
      label: "Stüdyo Ayarları",
      click: () => {
        showMainWindow();
        if (mainWin && !mainWin.isDestroyed()) mainWin.webContents.send("desktop:open-settings", "desktop");
      },
    },
    { type: "separator" },
    {
      label: "Windows ile Otomatik Başlat",
      type: "checkbox",
      checked: getAutoLaunchEnabled(),
      click: (item) => {
        setAutoLaunchEnabled(item.checked);
        rebuildTrayMenu();
      },
    },
    { label: "Yerel Web Arayüzünü Aç (Tarayıcı)", click: () => shell.openExternal(BACKEND_URL) },
    {
      label: "GPU VRAM Boşalt",
      click: async () => {
        await postLocalApi("/api/model/unload", 3000);
        refreshTrayStatus();
      },
    },
    { type: "separator" },
    {
      label: "Tam Çıkış (GPU & Motoru Kapat)",
      click: () => {
        isQuitting = true;
        app.quit();
      },
    },
  ]);
  tray.setContextMenu(menu);
}

async function refreshTrayStatus() {
  if (!trayReady) return;
  const res = await fetchLocalJson("/api/status", "GET", 1500);
  if (res.ok && res.data) {
    const st = res.data;
    const gpuName = st.vram?.device ? String(st.vram.device).replace("NVIDIA GeForce ", "") : "GPU";
    const loaded = st.model_loaded ? (st.active_model_id?.includes("e2b") ? "Gemma 4 E2B" : "Gemma 4 E4B") : "Beklemede";
    const usedMb = st.vram?.model_mb ? ` · ${st.vram.model_mb} MB` : "";
    lastTraySummary = `${gpuName} · ${loaded}${usedMb}`;
  } else {
    lastTraySummary = "Motor Çevrimdışı";
  }
  rebuildTrayMenu();
}

function createTray() {
  try {
    const iconImg = nativeImage.createFromPath(path.join(__dirname, "icon.png"));
    tray = new Tray(iconImg.resize({ width: 16, height: 16 }));
    trayReady = true;
    rebuildTrayMenu();
    tray.on("click", () => {
      if (mainWin && mainWin.isVisible()) mainWin.focus();
      else showMainWindow();
    });
    refreshTrayStatus();
    trayPollTimer = setInterval(refreshTrayStatus, 15000);
  } catch (_) {
    trayReady = false;
  }
}

async function capturePrimaryScreen(fromMain = false) {
  const wasCompVis = companionWin && !companionWin.isDestroyed() && companionWin.isVisible();
  const wasMainVis = Boolean(fromMain) && mainWin && !mainWin.isDestroyed() && mainWin.isVisible();
  if (wasCompVis) companionWin.hide();
  if (wasMainVis) mainWin.hide();
  await new Promise((r) => setTimeout(r, 180));

  const cursorDisp = screen.getDisplayNearestPoint(screen.getCursorScreenPoint());
  const sources = await desktopCapturer.getSources({
    types: ["screen"],
    thumbnailSize: { width: 1440, height: 810 },
  });
  const matched = sources.find((s) => String(s.display_id) === String(cursorDisp.id)) || sources[0];
  const dataUrl = matched ? matched.thumbnail.toDataURL() : null;

  if (wasMainVis && mainWin && !mainWin.isDestroyed()) {
    mainWin.show();
    mainWin.focus();
  }
  if (wasCompVis && companionWin && !companionWin.isDestroyed()) {
    companionWin.show();
    companionWin.focus();
  }
  return dataUrl;
}

async function gracefulShutdown() {
  if (shutdownDone) return;
  shutdownDone = true;
  if (trayPollTimer) clearInterval(trayPollTimer);
  saveWindowState();
  globalShortcut.unregisterAll();

  try {
    await Promise.all([
      postLocalApi("/api/model/unload", 2500),
      postLocalApi("/api/tunnel/stop", 1500),
    ]);
  } catch (_) {}

  if (backendProc && backendProc.pid) {
    try {
      execFileSync("taskkill", ["/PID", String(backendProc.pid), "/T", "/F"], { windowsHide: true, timeout: 3000 });
    } catch (_) {
      try { backendProc.kill(); } catch (__) {}
    }
    backendProc = null;
  }
}

// ---- IPC Handlers ----

ipcMain.on("desktop:set-theme", (_ev, theme) => {
  winState.theme = theme === "light" || theme === "system" ? theme : "dark";
  saveWindowState();
  applyThemeToAllWindows();
});

ipcMain.on("desktop:set-progress", (_ev, val) => {
  if (mainWin && !mainWin.isDestroyed()) {
    try { mainWin.setProgressBar(typeof val === "number" ? val : -1); } catch (_) {}
  }
});

ipcMain.on("desktop:notify", (_ev, { title, body }) => {
  if (mainWin && !mainWin.isDestroyed() && !mainWin.isFocused() && Notification.isSupported()) {
    try {
      const n = new Notification({ title: title || "YerelAI Studio", body: body || "", icon: path.join(__dirname, "icon.png") });
      n.on("click", showMainWindow);
      n.show();
    } catch (_) {}
  }
});

ipcMain.handle("desktop:capture-screen", async (_ev, fromMain) => capturePrimaryScreen(Boolean(fromMain)));

ipcMain.handle("desktop:pick-folder", async () => {
  if (!mainWin || mainWin.isDestroyed()) return null;
  const res = await dialog.showOpenDialog(mainWin, {
    title: "Yerel Çalışma Alanı Klasörü Seçin",
    properties: ["openDirectory"],
  });
  if (res.canceled || !res.filePaths?.length) return null;
  return res.filePaths[0];
});

ipcMain.handle("desktop:list-windows", async () => {
  try {
    const sources = await desktopCapturer.getSources({
      types: ["screen", "window"],
      thumbnailSize: { width: 320, height: 180 },
      fetchWindowIcons: false,
    });
    return sources
      .filter((s) => s.name && s.name !== "YerelAI Studio" && s.name !== "YerelAI Hızlı Sor")
      .slice(0, 12)
      .map((s) => ({
        id: s.id,
        name: s.name,
        kind: s.id.startsWith("screen:") ? "screen" : "window",
        thumb: s.thumbnail.toDataURL(),
      }));
  } catch (_) {
    return [];
  }
});

ipcMain.handle("desktop:capture-source", async (_ev, { sourceId, fromMain }) => {
  const wasMainVis = Boolean(fromMain) && mainWin && !mainWin.isDestroyed() && mainWin.isVisible();
  if (wasMainVis && String(sourceId).startsWith("screen:")) {
    mainWin.hide();
    await new Promise((r) => setTimeout(r, 180));
  }
  const sources = await desktopCapturer.getSources({
    types: ["screen", "window"],
    thumbnailSize: { width: 1440, height: 900 },
  });
  const matched = sources.find((s) => s.id === sourceId) || sources[0];
  const dataUrl = matched ? matched.thumbnail.toDataURL() : null;
  if (wasMainVis && mainWin && !mainWin.isDestroyed()) {
    mainWin.show();
    mainWin.focus();
  }
  return dataUrl;
});

ipcMain.handle("desktop:read-clipboard", async () => {
  try {
    return clipboard.readText() || "";
  } catch (_) {
    return "";
  }
});

ipcMain.handle("desktop:get-prefs", async () => ({
  autoLaunch: getAutoLaunchEnabled(),
  minimizeToTray: winState.minimizeToTray,
  companionHotkey: winState.companionHotkey,
  theme: winState.theme,
}));

ipcMain.handle("desktop:set-pref", async (_ev, { key, value }) => {
  if (key === "autoLaunch") {
    setAutoLaunchEnabled(Boolean(value));
  } else if (key === "minimizeToTray") {
    winState.minimizeToTray = Boolean(value);
    saveWindowState();
  } else if (key === "companionHotkey" && ALLOWED_HOTKEYS.has(value)) {
    winState.companionHotkey = value;
    saveWindowState();
    registerCompanionShortcut(value);
  }
  rebuildTrayMenu();
  return {
    ok: true,
    autoLaunch: getAutoLaunchEnabled(),
    minimizeToTray: winState.minimizeToTray,
    companionHotkey: winState.companionHotkey,
  };
});

ipcMain.handle("desktop:open-path", async (_ev, kind) => {
  try {
    if (kind === "config") {
      await shell.openPath(path.join(ROOT_DIR, "config.json"));
      return { ok: true };
    }
    if (kind === "mcp") {
      const p = path.join(ROOT_DIR, "mcp_servers.json");
      if (fs.existsSync(p)) shell.showItemInFolder(p);
      else await shell.openPath(ROOT_DIR);
      return { ok: true };
    }
    shell.showItemInFolder(path.join(ROOT_DIR, "backend.log"));
    return { ok: true };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
});

ipcMain.handle("desktop:restart-backend", async () => {
  const ok = await ensureBackendStarted();
  if (ok && mainWin && !mainWin.isDestroyed()) {
    mainWin.loadURL(BACKEND_URL);
  }
  refreshTrayStatus();
  return { ok };
});

ipcMain.on("desktop:open-external", (_ev, url) => {
  if (url && /^https?:\/\//i.test(url)) shell.openExternal(url);
});

ipcMain.on("desktop:companion-hide", () => {
  if (companionWin && !companionWin.isDestroyed()) companionWin.hide();
});

ipcMain.on("desktop:companion-submit", (_ev, payload) => {
  if (companionWin && !companionWin.isDestroyed()) companionWin.hide();
  showMainWindow();
  if (mainWin && !mainWin.isDestroyed()) {
    mainWin.webContents.send("desktop:inject-prompt", payload);
  }
});

nativeTheme.on("updated", () => {
  if (winState.theme === "system") applyThemeToAllWindows();
});

app.on("second-instance", () => showMainWindow());

app.whenReady().then(async () => {
  // Apply clean CSP header for local backend responses (eliminates Electron security warning)
  session.defaultSession.webRequest.onHeadersReceived(
    { urls: [`${BACKEND_URL}/*`] },
    (details, callback) => {
      const headers = { ...details.responseHeaders };
      headers["Content-Security-Policy"] = [
        "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob: http://127.0.0.1:8070 https://fonts.googleapis.com https://fonts.gstatic.com; img-src 'self' data: blob: https: http:; connect-src 'self' http://127.0.0.1:8070 ws://127.0.0.1:8070 https:;",
      ];
      callback({ responseHeaders: headers });
    }
  );

  createSplashWindow();
  const backendOk = await ensureBackendStarted();
  createMainWindow(backendOk);
  createCompanionWindow();
  createTray();
  registerCompanionShortcut(winState.companionHotkey);
});

app.on("before-quit", (e) => {
  if (!shutdownDone) {
    e.preventDefault();
    isQuitting = true;
    gracefulShutdown().finally(() => app.exit(0));
  }
});

app.on("window-all-closed", () => {
  if (isQuitting) app.quit();
});
