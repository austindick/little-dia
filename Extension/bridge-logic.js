// Pure helpers for the service worker, kept separate so they can be tested with `node --test`.

/** chrome.windows.create options for a little window. */
export function popupCreateOptions({ url, bounds, focused }) {
  return { type: "popup", url, left: bounds.left, top: bounds.top, width: bounds.width, height: bounds.height, focused };
}

/** The normal window "Move to main window" should use: the last one focused, else the focused one, else the first. */
export function pickMainWindowId(normalWindows, lastNormalId) {
  if (normalWindows.some((w) => w.id === lastNormalId)) return lastNormalId;
  const focused = normalWindows.find((w) => w.focused);
  if (focused) return focused.id;
  return normalWindows.length > 0 ? normalWindows[0].id : null;
}

/** Bounds for a little window opened from another one: offset so both stay visible. */
export function cascadeBounds(bounds, offset = 30) {
  return { left: bounds.left + offset, top: bounds.top + offset, width: bounds.width, height: bounds.height };
}

/**
 * Height the browser added above the requested page area. Dia treats create()'s bounds as the page area and puts
 * ~72pt of title bar and address row on top, then reports the full window; other browsers report what was asked for.
 */
export function chromeHeight(requestedHeight, createdHeight) {
  return Math.max(0, createdHeight - requestedHeight);
}

/**
 * The title-bar height to remember for a window the browser just created: measured from the window when the browser
 * reports its size, otherwise the value the app measured and sent with the request.
 */
export function addedHeight(win, requestedHeight, fallback) {
  return win.height > 0 ? chromeHeight(requestedHeight, win.height) : fallback;
}

/** A window's bounds expressed as the page area, the same space chrome.windows.create() takes. */
export function windowBounds(w, chrome = 0) {
  return { left: w.left, top: w.top + chrome, width: w.width, height: w.height - chrome };
}

/**
 * Page-area bounds to report for a window the browser just created. Dia returns 0x0 from create(), in which case the
 * requested bounds are the best answer.
 */
export function reportedBounds(requested, win) {
  if (!(win.width > 0 && win.height > 0)) return requested;
  return windowBounds(win, chromeHeight(requested.height, win.height));
}

/**
 * Returns a function that runs async tasks one at a time, in call order, so read-modify-write updates of shared
 * state can't interleave. A failed task doesn't stop later ones.
 */
export function makeSerial() {
  let tail = Promise.resolve();
  return (task) => {
    const run = tail.then(task, task);
    tail = run.catch(() => {});
    return run;
  };
}

/**
 * How long to wait before reconnecting after the native helper went away. The helper exits after an update so the
 * browser can start the new one; reconnect quickly then, but back off (up to a minute) if it keeps dropping at once.
 */
export function nextReconnectDelay(previousDelayMs, connectedForMs) {
  if (connectedForMs >= 30000) return 1000;
  return Math.min(Math.max(previousDelayMs * 2, 1000), 60000);
}
