// Runs in every page. Inside a little window, links that would open a new tab (and so pull you to the main
// window on another desktop) open another little window instead.
(async () => {
  let isLittle = false;
  try {
    isLittle = await chrome.runtime.sendMessage({ type: "isLittle" });
  } catch {
    return;
  }
  if (!isLittle) return;

  const { classifyClick } = globalThis.LittleDiaClickRules;
  const onClick = (event) => {
    const anchor = event.target instanceof Element ? event.target.closest("a[href]") : null;
    if (!anchor) return;
    const decision = classifyClick(
      { button: event.button, isTrusted: event.isTrusted, metaKey: event.metaKey, ctrlKey: event.ctrlKey, shiftKey: event.shiftKey, altKey: event.altKey },
      { href: anchor.href, target: anchor.target, hasDownload: anchor.hasAttribute("download") },
    );
    if (decision !== "little") return;
    event.preventDefault();
    event.stopImmediatePropagation();
    chrome.runtime.sendMessage({ type: "openLittle", url: anchor.href });
  };
  window.addEventListener("click", onClick, true);
  window.addEventListener("auxclick", onClick, true);
})();
