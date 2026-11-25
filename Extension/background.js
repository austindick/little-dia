// Little Dia service worker: opens little windows (Dia popups) when the menu-bar app asks, and reports what
// happens to them. Talks to the app through the native-messaging helper `com.austindick.littledia.bridge`.
import { popupCreateOptions, pickMainWindowId, cascadeBounds, windowBounds, reportedBounds, makeSerial, nextReconnectDelay, addedHeight, isWebURL, opensAsLittleWindow, pageUpdate, faviconPath, knownIcons } from "./bridge-logic.js";

const HOST = "com.austindick.littledia.bridge";
// Height Dia adds above a popup's page area (measured 2026-10-23); used only if the app didn't send its measurement.
const DIA_CHROME_HEIGHT = 72;
let port = null;
let connectedAt = 0;
let reconnectDelay = 0;

// ---- Connection to the app ------------------------------------------------------------------------------------

function connect() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    console.warn("Little Dia: connectNative failed", e);
    port = null;
    return;
  }
  port.onMessage.addListener((msg) => {
    handleAppMessage(msg).catch((e) => console.error("Little Dia: handling", msg, e));
  });
  connectedAt = Date.now();
  port.onDisconnect.addListener(() => {
    console.warn("Little Dia: native host disconnected:", chrome.runtime.lastError?.message);
    port = null;
    // The helper exits after the app is updated; reconnecting starts the new one.
    reconnectDelay = nextReconnectDelay(reconnectDelay, Date.now() - connectedAt);
    setTimeout(connect, reconnectDelay);
  });
  sayHello();
}

/** Says hello with this copy's version and its profile token. */
async function sayHello() {
  const token = await profileToken().catch(() => undefined);
  post({ type: "hello", extensionVersion: chrome.runtime.getManifest().version, profileToken: token });
}

/**
 * A random ID kept in this profile's storage. The extension can't learn its Dia profile's name, but the app can find
 * which profile folder holds this ID. It's written again each time, so it's in the newest storage file.
 */
async function profileToken() {
  const { profileToken: stored } = await chrome.storage.local.get("profileToken");
  const token = stored ?? crypto.randomUUID();
  await chrome.storage.local.set({ profileToken: token });
  return token;
}

function post(msg) {
  if (!port) return;
  try {
    port.postMessage(msg);
  } catch (e) {
    console.warn("Little Dia: postMessage failed", e);
  }
}

chrome.runtime.onStartup.addListener(connect);
chrome.runtime.onInstalled.addListener(connect);
chrome.alarms.create("reconnect", { periodInMinutes: 1 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "reconnect") connect();
});
connect();

// ---- State (survives service-worker restarts) -------------------------------------------------------------------
// littleWindows: { [windowId]: { tabId, chrome, bounds, topOffset } } where chrome is the height the browser added above
// the page area, bounds is the window's last known page area, and topOffset is what the app had added to its top when
// asking Dia (see popupCreateOptions).

async function getState() {
  const s = await chrome.storage.session.get(["littleWindows", "lastNormalWindowId"]);
  return { littleWindows: s.littleWindows ?? {}, lastNormalWindowId: s.lastNormalWindowId ?? null };
}

// Updates run one at a time: windows opened by fast ⌘-clicks would otherwise overwrite each other's entries.
const serial = makeSerial();

function updateLittleWindows(change) {
  return serial(async () => {
    const { littleWindows } = await getState();
    change(littleWindows);
    await chrome.storage.session.set({ littleWindows });
  });
}

// ---- Little windows ---------------------------------------------------------------------------------------------

async function openLittleWindow({ url, bounds, focused = true, requestId, chromeHeight: measured, topOffset = 0 }) {
  const win = await chrome.windows.create(popupCreateOptions({ url, bounds, focused, topOffset }));
  // Dia reports 0x0 here; fall back to the request and the title-bar height the app measured.
  const added = addedHeight(win, bounds.height, measured ?? DIA_CHROME_HEIGHT);
  const pageBounds = reportedBounds(bounds, win);
  await updateLittleWindows((w) => { w[win.id] = { tabId: win.tabs?.[0]?.id, chrome: added, bounds: pageBounds, topOffset }; });
  const opened = { type: "opened", windowId: win.id, url, bounds: pageBounds };
  if (requestId) opened.requestId = requestId;
  post(opened);
  return win;
}

/** Opens `url` in a new little window offset from the little window it came from. */
async function openFromLittleWindow(sourceWindowId, url) {
  const { littleWindows } = await getState();
  const source = littleWindows[sourceWindowId];
  if (!source) return;
  const current = await chrome.windows.get(sourceWindowId).catch(() => null);
  const from = current && current.width > 0 ? windowBounds(current, source.chrome) : source.bounds;
  // Same screen as its source, so Dia needs the same correction (windows.get reports the window where it really is).
  await openLittleWindow({ url, bounds: cascadeBounds(from), focused: true, chromeHeight: source.chrome,
                           topOffset: source.topOffset ?? 0 });
}

async function moveToMainWindow(windowId) {
  const { littleWindows, lastNormalWindowId } = await getState();
  const info = littleWindows[windowId];
  if (!info) return;
  const normals = await chrome.windows.getAll({ windowTypes: ["normal"], populate: true });   // pickMainWindowId looks at tabs
  const mainId = pickMainWindowId(normals, lastNormalWindowId);

  // Best: move the live tab, so the page isn't reloaded. Chrome's API refuses tabs leaving popup windows; try anyway.
  if (mainId != null) {
    try {
      await chrome.tabs.move(info.tabId, { windowId: mainId, index: -1 });
      await chrome.tabs.update(info.tabId, { active: true });
      post({ type: "log", message: "move: moved the live tab (no reload)" });
      post({ type: "littleMoved", windowId });
      return;
    } catch (e) {
      post({ type: "log", message: `move: live tab move refused (${e?.message ?? e}); reopening the URL instead` });
    }
  }

  const tab = await chrome.tabs.get(info.tabId);
  const url = tab.url || tab.pendingUrl;
  if (mainId != null) {
    await chrome.tabs.create({ windowId: mainId, url, active: true });
  } else {
    await chrome.windows.create({ type: "normal", url, focused: true });
  }
  // The app closes the little window (natively) and brings the browser forward: Dia ignores windows.remove and
  // windows.update({focused}) for popups.
  post({ type: "littleMoved", windowId });
}

/** A page's icon from Dia's icon store, as base64 PNG, or null. */
async function readIcon(pageUrl) {
  try {
    const response = await fetch(chrome.runtime.getURL(faviconPath(pageUrl)));
    if (!response.ok) return null;
    const bytes = new Uint8Array(await response.arrayBuffer());
    let binary = "";
    for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
    return btoa(binary);
  } catch {
    return null;
  }
}

/** Dia's generic icon, which it gives for any page it has no icon for. */
let defaultIcon;

async function sendIcons(pageURLs) {
  defaultIcon ??= await readIcon("https://no-such-site.invalid/");
  const found = {};
  for (const url of pageURLs ?? []) found[url] = await readIcon(url);
  post({ type: "favicons", icons: knownIcons(found, defaultIcon) });
}

async function handleAppMessage(msg) {
  switch (msg.type) {
    case "favicons":
      await sendIcons(msg.pageURLs);
      break;
    case "open":
      try {
        await openLittleWindow({ url: msg.url, bounds: msg.bounds, focused: msg.focused, requestId: msg.requestId, chromeHeight: msg.chromeHeight, topOffset: msg.topOffset });
      } catch (e) {
        post({ type: "openFailed", requestId: msg.requestId, error: String(e) });
      }
      break;
    case "move":
      await moveToMainWindow(msg.windowId);
      break;
    case "back": {
      const { littleWindows } = await getState();
      const tabId = littleWindows[msg.windowId]?.tabId;
      if (tabId != null) await chrome.tabs.goBack(tabId).catch(() => {});
      break;
    }
    case "reloadPage": {
      // ⌘R / ⌘⇧R in a little window: Dia doesn't reload popups itself.
      const { littleWindows } = await getState();
      const tabId = littleWindows[msg.windowId]?.tabId;
      if (tabId != null) await chrome.tabs.reload(tabId, { bypassCache: msg.bypassCache === true }).catch(() => {});
      break;
    }
    case "close":
      // The app gave up on this window (it never reached the screen) and opened the link normally instead.
      await chrome.windows.remove(msg.windowId).catch(() => {});
      break;
    case "ping":
      await sayHello();
      break;
    case "reload":
      // The app installed a newer copy of this extension in the folder Dia loads it from.
      chrome.runtime.reload();
      break;
    default:
      console.warn("Little Dia: unknown message from app", msg);
  }
}

// ---- Events about little windows ----------------------------------------------------------------------------

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  const page = pageUpdate(changeInfo, tab);
  if (!page) return;
  const { littleWindows } = await getState();
  if (littleWindows[tab.windowId]) post({ type: "littleURL", windowId: tab.windowId, url: page.url, title: page.title });
});

chrome.windows.onBoundsChanged.addListener(async (win) => {
  const { littleWindows } = await getState();
  const info = littleWindows[win.id];
  if (!info) return;
  const bounds = windowBounds(win, info.chrome);
  await updateLittleWindows((w) => { if (w[win.id]) w[win.id].bounds = bounds; });
  post({ type: "littleBounds", windowId: win.id, bounds });
});

chrome.windows.onRemoved.addListener(async (windowId) => {
  const { littleWindows } = await getState();
  if (!littleWindows[windowId]) return;
  await updateLittleWindows((w) => { delete w[windowId]; });
  post({ type: "littleClosed", windowId });
});

chrome.windows.onFocusChanged.addListener(async (windowId) => {
  if (windowId === chrome.windows.WINDOW_ID_NONE) return;
  try {
    const win = await chrome.windows.get(windowId);
    if (win.type === "normal") await chrome.storage.session.set({ lastNormalWindowId: windowId });
  } catch {
    // The window closed before we looked at it.
  }
});

// ---- Pages in little windows ---------------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const windowId = sender.tab?.windowId;
  if (msg.type === "isLittle") {
    getState().then(({ littleWindows }) => sendResponse(windowId != null && Boolean(littleWindows[windowId])));
    return true;   // responds asynchronously
  }
  if (msg.type === "history" && windowId != null) {
    getState().then(({ littleWindows }) => {
      if (littleWindows[windowId]) post({ type: "littleHistory", windowId, canGoBack: msg.canGoBack === true });
    });
  }
  if (msg.type === "openLittle" && windowId != null) {
    openFromLittleWindow(windowId, msg.url).catch((e) => post({ type: "log", message: `openLittle failed: ${e?.message ?? e}` }));
  }
  return false;
});

// Backstop for new tabs the content script couldn't catch (e.g. window.open from page scripts): Dia puts a new *tab*
// opened from a little window in the main window, sometimes after first putting it in the little window itself, so
// open it in a little window instead. Real popups stay as they are (see opensAsLittleWindow). Only web pages move: a
// page script could otherwise open a data: or chrome:// URL as a top-level page, which Chrome blocks pages from doing
// themselves.
chrome.webNavigation.onCreatedNavigationTarget.addListener(async (details) => {
  if (!isWebURL(details.url)) return;
  const { littleWindows } = await getState();
  const sourceTab = await chrome.tabs.get(details.sourceTabId).catch(() => null);
  const source = sourceTab && littleWindows[sourceTab.windowId];
  if (!source) return;
  const newTab = await chrome.tabs.get(details.tabId).catch(() => null);
  if (!newTab) return;
  const newWindow = await chrome.windows.get(newTab.windowId).catch(() => null);
  if (!newWindow || !opensAsLittleWindow(newTab, newWindow, { windowId: sourceTab.windowId, tabId: source.tabId })) return;
  await chrome.tabs.remove(details.tabId);
  post({ type: "log", message: `new tab from little window ${sourceTab.windowId} (in a ${newWindow.type} window) opens in a little window` });
  await openFromLittleWindow(sourceTab.windowId, details.url);
});
