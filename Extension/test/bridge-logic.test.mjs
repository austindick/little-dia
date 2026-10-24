import { test } from "node:test";
import assert from "node:assert/strict";
import { popupCreateOptions, pickMainWindowId, cascadeBounds, windowBounds, chromeHeight, nextReconnectDelay } from "../bridge-logic.js";

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
