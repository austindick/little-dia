for (const mode of ["focused", "unfocused"]) {
  document.getElementById(mode).addEventListener("click", async () => {
    await chrome.runtime.sendMessage({ mode });
    window.close();
  });
}
