const { test } = require("node:test");
const assert = require("node:assert/strict");
require("../click-rules.js");
const { classifyClick } = globalThis.LilBrowClickRules;

const base = { href: "https://x.com/a", target: "", hasDownload: false };
const cases = [
  [{ button: 0 }, base, "default"],
  [{ button: 0 }, { ...base, target: "_blank" }, "little"],
  [{ button: 0 }, { ...base, target: "_BLANK" }, "little"],
  [{ button: 0, metaKey: true }, base, "little"],
  [{ button: 1 }, base, "little"],
  [{ button: 0, shiftKey: true }, base, "little"],
  [{ button: 0 }, { ...base, target: "_blank", href: "mailto:a@b.c" }, "default"],
  [{ button: 0 }, { ...base, target: "_blank", hasDownload: true }, "default"],
  [{ button: 0, altKey: true }, { ...base, target: "_blank" }, "default"],
  [{ button: 0 }, { ...base, target: "results-frame" }, "default"],
  [{ button: 0, isTrusted: false }, { ...base, target: "_blank" }, "default"],   // a page script's fake click
];

for (const [evt, anchor, expected] of cases) {
  test(`classifyClick(${JSON.stringify(evt)}, ${JSON.stringify(anchor)}) is ${expected}`, () => {
    assert.equal(classifyClick(evt, anchor), expected);
  });
}
