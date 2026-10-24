// Which clicks inside a little window should open another little window instead of a tab in the main window.
// A classic script (content scripts can't be modules): it publishes its function on globalThis.
(() => {
  /**
   * @param evt {{button: number, isTrusted?: boolean, metaKey?: boolean, ctrlKey?: boolean, shiftKey?: boolean, altKey?: boolean}}
   * @param anchor {{href: string, target: string, hasDownload: boolean}} href already absolute
   * @returns {"little" | "default"}
   */
  function classifyClick(evt, anchor) {
    // Only real clicks: a page script's synthetic click must not open windows (extension windows skip the popup blocker).
    if (evt.isTrusted === false) return "default";
    let protocol;
    try {
      protocol = new URL(anchor.href).protocol;
    } catch {
      return "default";
    }
    if (protocol !== "http:" && protocol !== "https:") return "default";
    if (anchor.hasDownload || evt.altKey) return "default";
    const opensNewTab =
      evt.button === 1 || evt.metaKey || evt.shiftKey || (evt.button === 0 && (anchor.target || "").toLowerCase() === "_blank");
    return opensNewTab ? "little" : "default";
  }

  globalThis.LilBrowClickRules = { classifyClick };
})();
