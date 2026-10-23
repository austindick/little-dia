# Spike: does a Dia popup open on the current desktop? (2026-10-23)

## Decision

- **Adapter: `dia`.**
- **Focus strategy:** the extension creates the popup with `focused: true`. Once the extension acknowledges `opened`, the app calls `NSRunningApplication.activate()` on Dia.
  - This replaces the plan's `FocusStrategy` enum (`focusOnCreate` / `createThenRaise`). It is the only approach that passed.
  - Bringing the window to the front needs no Accessibility permission and no private API.
- The macOS setting "When switching to an application, switch to a Space with open windows for the application" stays **on** (the owner's current default). No settings change is needed.

## Results

The owner stood on desktop 2 (Terminal). Dia's main window was on desktop 1. The popup was created by the spike extension 15 s after its button was clicked.

| Method | Result |
|---|---|
| Popup `focused: true`, nothing else | Lands on the **current desktop** with no switch, but stays **behind** the frontmost app. Chromium's own activation is ignored under macOS 14+ cooperative activation. |
| Popup `focused: false`, then the CLI probe raises it through AX and activates Dia | Stays behind. The CLI process is not an app, so its activation request is ignored. |
| Spike app (receives the link through LaunchServices) calls `yieldActivation` to Dia | The spike app is **not** active when the link arrives (`active=false`), so yielding does nothing. Stays behind. |
| M1: AX raise + `kAXMain` + app `kAXFrontmost` | The AX call returns success but is ignored. Stays behind. |
| M2: `NSWorkspace.openApplication(activates: true)` | Dia comes to the front but **switches to Dia's main-window desktop**, probably through Chromium's reopen handling. **Never use this.** |
| **M3: `NSRunningApplication.activate()` from the background app, after the popup exists** | **PASS.** Dia is frontmost, the popup is in front, and there is no desktop switch. |
| Chrome | Not testable. Company policy on this Mac blocks loading unpacked extensions in Chrome. |

## Other findings that matter for the build

- **Dia allows Load unpacked** in developer mode.
- **Popup geometry.** Dia treats the requested `left/top/width/height` as the page area and adds about 72 pt of title bar and address row *above* it. A request for (200, 150, 1000, 750) produces an actual window frame of (200, 78, 1000, 822). Left, width and **bottom edge** match the request; top and height do not.
- **The popup animates open.** Over about 0.5 s its size grows from roughly 986×812 to 1000×822. Frame matching has to tolerate this, or wait for it to settle.
- **Dia's AX focused window is the popup** right after creation, even when Dia isn't active.
- Ad-hoc code signing breaks the Accessibility grant on every rebuild. Signing with a stable identity (a self-signed one is fine) keeps it.
- M5, the private SkyLight front-process call, was not needed and is not used.
