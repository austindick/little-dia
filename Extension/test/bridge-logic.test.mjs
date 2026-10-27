import { test } from "node:test";
import assert from "node:assert/strict";
import { popupCreateOptions, pickMainWindowId, cascadeBounds, windowBounds, chromeHeight, nextReconnectDelay, addedHeight, isWebURL } from "../bridge-logic.js";

const bounds = { left: 300, top: 137, width: 1000, height: 750 };

test("popupCreateOptions maps fields exactly", () => {
  assert.deepEqual(popupCreateOptions({ url: "https://github.com/", bounds, focused: true }), {
    type: "popup", url: "https://github.com/", left: 300, top: 137, width: 1000, height: 750, focused: true,
  });
});

test("pickMainWindowId prefers the last normal window", () => {
  assert.equal(pickMainWindowId([{ id: 1 }, { id: 2, focused: true }], 1), 1);
});

test("pickMainWindowId falls back to the focused window, then the first", () => {
  assert.equal(pickMainWindowId([{ id: 1 }, { id: 2, focused: true }], 9), 2);
  assert.equal(pickMainWindowId([{ id: 1 }, { id: 2 }], null), 1);
});

test("pickMainWindowId skips a window with no tabs, which Dia keeps hidden", () => {
  // Seen on a coworker's Mac (2026-10-27): an empty normal window listed first, nothing focused, no last window.
  const hidden = { id: 1, tabs: [] }, shown = { id: 2, tabs: [{ id: 10 }, { id: 11 }] };
  assert.equal(pickMainWindowId([hidden, shown], null), 2);
  assert.equal(pickMainWindowId([hidden, shown], 1), 2);
  assert.equal(pickMainWindowId([{ ...hidden, focused: true }, shown], null), 2);
});

test("pickMainWindowId still uses an empty window when it's the only kind there is", () => {
  assert.equal(pickMainWindowId([{ id: 1, tabs: [] }], null), 1);
});

test("pickMainWindowId returns null with no normal windows", () => {
  assert.equal(pickMainWindowId([], 1), null);
});

test("cascadeBounds offsets by 30", () => {
  assert.deepEqual(cascadeBounds(bounds), { left: 330, top: 167, width: 1000, height: 750 });
});

test("chromeHeight is the extra height the browser added above the page area", () => {
  assert.equal(chromeHeight(750, 822), 72);   // Dia (2026-10-23 spike)
  assert.equal(chromeHeight(750, 750), 0);    // browsers that report the page area
  assert.equal(chromeHeight(750, 700), 0);    // clamped by a small screen: never negative
});

test("windowBounds reports the page area the browser was asked for", () => {
  assert.deepEqual(windowBounds({ left: 200, top: 78, width: 1000, height: 822 }, 72), { left: 200, top: 150, width: 1000, height: 750 });
  assert.deepEqual(windowBounds({ left: 200, top: 150, width: 1000, height: 750 }), { left: 200, top: 150, width: 1000, height: 750 });
});

test("reportedBounds falls back to the request when the browser reports a 0x0 window", async () => {
  const { reportedBounds } = await import("../bridge-logic.js");
  // Dia returns windows from create() with zero bounds.
  assert.deepEqual(reportedBounds(bounds, { left: 0, top: 0, width: 0, height: 0 }), bounds);
  assert.deepEqual(reportedBounds(bounds, { left: 300, top: 65, width: 1000, height: 822 }), { left: 300, top: 137, width: 1000, height: 750 });
});

test("serial runs async updates one at a time, in order", async () => {
  const { makeSerial } = await import("../bridge-logic.js");
  const serial = makeSerial();
  const log = [];
  const step = (name, ms) => serial(async () => {
    log.push(`start ${name}`);
    await new Promise((r) => setTimeout(r, ms));
    log.push(`end ${name}`);
  });
  await Promise.all([step("a", 20), step("b", 1)]);
  assert.deepEqual(log, ["start a", "end a", "start b", "end b"]);
});

test("serial keeps going after a failed update", async () => {
  const { makeSerial } = await import("../bridge-logic.js");
  const serial = makeSerial();
  await assert.rejects(serial(async () => { throw new Error("boom"); }));
  assert.equal(await serial(async () => "ok"), "ok");
});

test("nextReconnectDelay starts at one second", () => {
  assert.equal(nextReconnectDelay(0, 0), 1000);
});

test("nextReconnectDelay doubles while the helper keeps dropping quickly, up to a minute", () => {
  assert.equal(nextReconnectDelay(1000, 500), 2000);
  assert.equal(nextReconnectDelay(60000, 0), 60000);
});

test("nextReconnectDelay resets after a connection that lasted", () => {
  assert.equal(nextReconnectDelay(8000, 45000), 1000);
});

test("addedHeight falls back to the app's measured value when Dia reports no size", () => {
  assert.equal(addedHeight({ height: 0 }, 750, 80), 80);
});

test("addedHeight uses the reported window height when there is one", () => {
  assert.equal(addedHeight({ height: 822 }, 750, 80), 72);
});

test("isWebURL accepts only http and https", () => {
  assert.equal(isWebURL("https://x.com/a"), true);
  assert.equal(isWebURL("http://x.com/"), true);
  for (const url of ["data:text/html,<h1>hi</h1>", "javascript:alert(1)", "chrome://settings", "file:///etc/hosts",
                     "about:blank", "not a url", ""]) {
    assert.equal(isWebURL(url), false, url);
  }
});
