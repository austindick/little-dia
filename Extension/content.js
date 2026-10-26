// Runs in every page. Inside a little window, links that would open a new tab (and so pull you to the main
// window on another desktop) open another little window instead, and the app hears whether Back can go anywhere.
(async () => {
  let isLittle = false;
  try {
    isLittle = await chrome.runtime.sendMessage({ type: "isLittle" });
  } catch {
    return;
  }
  if (!isLittle) return;

  // Tells the app whether this page has somewhere to go back to, for the title bar's Back button: on load, after
  // in-page navigations, and when Back restores a page from the browser's cache (its scripts don't run again).
  const reportHistory = () =>
    chrome.runtime.sendMessage({ type: "history", canGoBack: globalThis.navigation?.canGoBack === true }).catch(() => {});
  reportHistory();
  globalThis.navigation?.addEventListener("currententrychange", reportHistory);
  window.addEventListener("pageshow", (event) => { if (event.persisted) reportHistory(); });

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
