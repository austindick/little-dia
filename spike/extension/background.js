chrome.runtime.onMessage.addListener((msg) => {
  console.log("spike: scheduling", msg.mode, "popup in 15 s");
  setTimeout(async () => {
    const win = await chrome.windows.create({
      type: "popup", url: "https://github.com",
      left: 200, top: 150, width: 1000, height: 750,
      focused: msg.mode === "focused",
    });
    console.log("spike: created window", win.id, win.left, win.top, win.width, win.height);
  }, 15000);
});
