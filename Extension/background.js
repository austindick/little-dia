// Lil Brow Wow service worker: opens little windows (Dia popups) when the menu-bar app asks, and reports what
// happens to them. Talks to the app through the native-messaging helper `com.lilbrowwow.bridge`.
import { popupCreateOptions, pickMainWindowId, cascadeBounds, windowBounds, chromeHeight, reportedBounds } from "./bridge-logic.js";

const HOST = "com.lilbrowwow.bridge";
// Height Dia adds above a popup's page area (measured 2026-10-23); used when Dia doesn't report window sizes.
const DIA_CHROME_HEIGHT = 72;
let port = null;

// ---- Connection to the app ------------------------------------------------------------------------------------

function connect() {
  if (port) return;
  try {
    port = chrome.runtime.connectNative(HOST);
  } catch (e) {
    console.warn("Lil Brow Wow: connectNative failed", e);
    port = null;
    return;
  }
  port.onMessage.addListener((msg) => {
    handleAppMessage(msg).catch((e) => console.error("Lil Brow Wow: handling", msg, e));
  });
  port.onDisconnect.addListener(() => {
    console.warn("Lil Brow Wow: native host disconnected:", chrome.runtime.lastError?.message);
    port = null;
  });
  post({ type: "hello", extensionVersion: chrome.runtime.getManifest().version });
}

function post(msg) {
  if (!port) return;
  try {
    port.postMessage(msg);
  } catch (e) {
    console.warn("Lil Brow Wow: postMessage failed", e);
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
// littleWindows: { [windowId]: { tabId, chrome, bounds } } where chrome is the height the browser added above the page
// area and bounds is the window's last known page area.

async function getState() {
  const s = await chrome.storage.session.get(["littleWindows", "lastNormalWindowId"]);
  return { littleWindows: s.littleWindows ?? {}, lastNormalWindowId: s.lastNormalWindowId ?? null };
}

async function updateLittleWindows(change) {
  const { littleWindows } = await getState();
  change(littleWindows);
  await chrome.storage.session.set({ littleWindows });
}

// ---- Little windows ---------------------------------------------------------------------------------------------

async function openLittleWindow({ url, bounds, focused = true, requestId }) {
  const win = await chrome.windows.create(popupCreateOptions({ url, bounds, focused }));
  // Dia reports 0x0 here; fall back to the request and assume Dia's usual title-bar height until a real size arrives.
  const addedHeight = win.height > 0 ? chromeHeight(bounds.height, win.height) : DIA_CHROME_HEIGHT;
  const pageBounds = reportedBounds(bounds, win);
  await updateLittleWindows((w) => { w[win.id] = { tabId: win.tabs?.[0]?.id, chrome: addedHeight, bounds: pageBounds }; });
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
  await openLittleWindow({ url, bounds: cascadeBounds(from), focused: true });
}

async function moveToMainWindow(windowId) {
  const { littleWindows, lastNormalWindowId } = await getState();
  const info = littleWindows[windowId];
  if (!info) return;
  const tab = await chrome.tabs.get(info.tabId);
  const url = tab.url || tab.pendingUrl;
  const normals = await chrome.windows.getAll({ windowTypes: ["normal"] });
  const mainId = pickMainWindowId(normals, lastNormalWindowId);
  if (mainId != null) {
    await chrome.tabs.create({ windowId: mainId, url, active: true });
    await chrome.windows.update(mainId, { focused: true });
  } else {
    await chrome.windows.create({ type: "normal", url, focused: true });
  }
  post({ type: "littleMoved", windowId });
  await chrome.windows.remove(windowId);
}

async function handleAppMessage(msg) {
  switch (msg.type) {
    case "open":
      try {
        await openLittleWindow({ url: msg.url, bounds: msg.bounds, focused: msg.focused, requestId: msg.requestId });
      } catch (e) {
        post({ type: "openFailed", requestId: msg.requestId, error: String(e) });
      }
      break;
    case "move":
      await moveToMainWindow(msg.windowId);
      break;
    case "close":
      // The app gave up on this window (it never reached the screen) and opened the link normally instead.
      await chrome.windows.remove(msg.windowId).catch(() => {});
      break;
    default:
      console.warn("Lil Brow Wow: unknown message from app", msg);
  }
}

// ---- Events about little windows ----------------------------------------------------------------------------

chrome.tabs.onUpdated.addListener(async (tabId, changeInfo, tab) => {
  if (!changeInfo.url) return;
  const { littleWindows } = await getState();
  if (littleWindows[tab.windowId]) post({ type: "littleURL", windowId: tab.windowId, url: changeInfo.url });
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

// ---- Links inside little windows ----------------------------------------------------------------------------

chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  const windowId = sender.tab?.windowId;
  if (msg.type === "isLittle") {
    getState().then(({ littleWindows }) => sendResponse(windowId != null && Boolean(littleWindows[windowId])));
    return true;   // responds asynchronously
  }
  if (msg.type === "openLittle" && windowId != null) {
    openFromLittleWindow(windowId, msg.url).catch((e) => console.error("Lil Brow Wow: openLittle", e));
  }
  return false;
});

// Backstop for new tabs the content script couldn't catch (e.g. window.open from page scripts): a new *tab* opened
// from a little window lands in the main window, so move it into a little window. Real popups stay as they are.
chrome.webNavigation.onCreatedNavigationTarget.addListener(async (details) => {
  const { littleWindows } = await getState();
  const sourceTab = await chrome.tabs.get(details.sourceTabId).catch(() => null);
  if (!sourceTab || !littleWindows[sourceTab.windowId]) return;
  const newTab = await chrome.tabs.get(details.tabId).catch(() => null);
  if (!newTab) return;
  const newWindow = await chrome.windows.get(newTab.windowId).catch(() => null);
  if (!newWindow || newWindow.type !== "normal") return;
  await chrome.tabs.remove(details.tabId);
  await openFromLittleWindow(sourceTab.windowId, details.url);
});
