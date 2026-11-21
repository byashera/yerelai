const { contextBridge, ipcRenderer } = require("electron");

contextBridge.exposeInMainWorld("yerelDesktop", {
  isElectron: true,
  platform: process.platform,
  setTheme: (theme) => ipcRenderer.send("desktop:set-theme", theme),
  setProgress: (val) => ipcRenderer.send("desktop:set-progress", val),
  notify: (title, body) => ipcRenderer.send("desktop:notify", { title, body }),
  captureScreen: (fromMain = false) => ipcRenderer.invoke("desktop:capture-screen", Boolean(fromMain)),
  pickFolder: () => ipcRenderer.invoke("desktop:pick-folder"),
  listWindows: () => ipcRenderer.invoke("desktop:list-windows"),
  captureSource: (sourceId, fromMain = false) => ipcRenderer.invoke("desktop:capture-source", { sourceId, fromMain: Boolean(fromMain) }),
  readClipboard: () => ipcRenderer.invoke("desktop:read-clipboard"),
  openExternal: (url) => ipcRenderer.send("desktop:open-external", url),
  submitCompanion: (payload) => ipcRenderer.send("desktop:companion-submit", payload),
  hideCompanion: () => ipcRenderer.send("desktop:companion-hide"),
  getDesktopPrefs: () => ipcRenderer.invoke("desktop:get-prefs"),
  setDesktopPref: (key, value) => ipcRenderer.invoke("desktop:set-pref", { key, value }),
  openPath: (kind) => ipcRenderer.invoke("desktop:open-path", kind),
  restartBackend: () => ipcRenderer.invoke("desktop:restart-backend"),
  onInjectPrompt: (cb) => {
    ipcRenderer.removeAllListeners("desktop:inject-prompt");
    ipcRenderer.on("desktop:inject-prompt", (_ev, data) => cb(data));
  },
  onContextAsk: (cb) => {
    ipcRenderer.removeAllListeners("desktop:context-ask");
    ipcRenderer.on("desktop:context-ask", (_ev, text) => cb(text));
  },
  onOpenSettings: (cb) => {
    ipcRenderer.removeAllListeners("desktop:open-settings");
    ipcRenderer.on("desktop:open-settings", (_ev, tab) => cb(tab));
  },
  onSplashStatus: (cb) => {
    ipcRenderer.removeAllListeners("splash:status");
    ipcRenderer.on("splash:status", (_ev, data) => cb(data));
  },
  onThemeChange: (cb) => {
    ipcRenderer.removeAllListeners("desktop:theme");
    ipcRenderer.on("desktop:theme", (_ev, theme) => cb(theme));
  },
});

window.addEventListener("DOMContentLoaded", () => {
  document.documentElement.classList.add("is-electron-desktop");
});
