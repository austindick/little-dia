# Lil Brow Wow

Little Arc for [Dia](https://www.diabrowser.com). When you click a link in another app (Slack, Mail, Notes, …),
it opens in a small Dia window **on the macOS desktop you're already on**, instead of pulling you over to wherever
Dia's main window lives. You stay signed in, because it really is Dia.

The little window has two buttons on its title bar:

- **Copy** (the link icon) copies the page's current URL.
- **↗ Dia** moves the page into Dia's main window, keeping your scroll position and anything you've typed, and takes you there.

Closing a little window puts you back in the app you came from. Resize one and the next ones open at that size
(1200×750 to start).

Arc stops working on December 22, 2026; this exists to keep the one Arc feature Dia doesn't have.

## How it works

```
link clicked in Slack ─▶ Lil Brow Wow (default browser, menu bar)
                              │  native messaging (lilbrow-host helper)
                              ▼
                         Dia extension ─▶ chrome.windows.create({type: "popup"}) on this desktop
```

- **Lil Brow Wow** (`Sources/LilBrowWow`) is a menu-bar app registered as the default browser. It never shows web pages.
  - It works out where the little window goes (centered on the screen with the pointer).
  - Once the window is on screen, it brings Dia forward.
  - It draws the title-bar buttons, finding the window through the Accessibility API.
- **The extension** (`Extension/`) runs inside Dia, so it has your logins, extensions and password manager. It:
  - opens the popup
  - reports navigation
  - moves the live tab into the main window
  - turns new-tab links inside a little window into more little windows
- **`lilbrow-host`** is the native-messaging helper Dia launches for the extension. It relays messages to the app over a Unix socket.
- `Sources/LilBrowCore` holds the tested logic: framing, the message protocol, geometry, the router and focus handling.

If anything goes wrong, the link opens in Dia normally, so a link is never lost. If Dia isn't running, links open in
its main window the usual way; little windows start once Dia is open.

## Setup

Requires macOS 14+ and Dia.

1. **Build and install** (needs Xcode or the Swift toolchain):
   ```bash
   LILBROW_SIGN_IDENTITY="<your code-signing identity>" scripts/build-app.sh --install
   ```
   This installs `~/Applications/LilBrowWow.app` and launches it; look for the overlapping-windows icon in the menu bar.
   Use a stable signing identity (a self-signed one is fine). With the default ad-hoc signature, macOS forgets the
   Accessibility permission on every rebuild.
2. **Make it the default browser:** menu-bar icon → *Make Lil Brow Wow the Default Browser…*, then confirm.
3. **Load the extension in Dia:** open `chrome://extensions`, turn on **Developer mode**, click **Load unpacked**,
   and choose the `Extension` folder. The menu should then say *Dia Extension: Connected*. Little windows use the Dia
   profile you load it in.
4. **Grant Accessibility** (for the title-bar buttons): menu-bar icon → *Grant Accessibility Access…*, then turn on
   Lil Brow Wow.
5. **Make sure Dia isn't pinned to one desktop:** Dock → right-click Dia → Options → Assign To → **None**. The menu
   warns you if it is.

Turn little windows off at any time with *Open Links in Little Windows* in the menu; links then go straight to Dia.

## Known limitations

- **Full-screen apps:** macOS won't put another app's window on a full-screen desktop, so a link clicked there can't
  open a little window. After about 2 seconds it opens in Dia's main window instead.
- **Briefly drawn behind:** the little window can appear behind the current app for a few hundredths of a second
  before coming forward. Bringing Dia forward before the window exists would switch desktops.
- **Buttons hide while you drag or resize** the little window, and come back when you let go.
- **No title-bar buttons without Accessibility access.** Grant it from the menu.
- **The menu shows only whether the extension is connected,** not which Dia profile it's in. Extensions can't read
  Dia's profile names.
- **No keyboard shortcuts** in v1.
- **Only Dia is supported for now.** The browser-specific details live in `BrowserAdapter`. Chromium browsers need an
  adapter, and Firefox/Zen need a Firefox build of the extension.
- Dia may ship its own version of this: its app contains an unreleased "Little Browser".

## Troubleshooting

- **App log:** `/usr/bin/log stream --predicate 'subsystem == "com.lilbrowwow"'`
  - In zsh, plain `log` is a shell builtin, so use the full path.
  - The log records each link's outcome, the extension connecting, little windows opening and closing, and why focus did or didn't return.
- ***Extension: Not Connected***
  1. Reload the extension in Dia.
  2. Check that `~/Library/Application Support/Dia/NativeMessagingHosts/com.lilbrowwow.bridge.json` exists. The app writes it on launch.
- **Buttons missing:** check *Accessibility: Granted* in the menu. After a rebuild with ad-hoc signing, remove Lil Brow
  Wow from the Accessibility list and add it again.

## Development

```bash
swift test                                  # app logic (Swift Testing)
node --test 'Extension/test/*.test.*'       # extension logic
scripts/build-app.sh --install              # build, sign, install, launch
```

Design and plan: `docs/superpowers/specs/2026-10-23-lil-brow-wow-design.md`,
`docs/superpowers/plans/2026-10-23-lil-brow-wow.md`. The spike that proved the approach (a Dia popup opens on the
current desktop, and how to bring it forward without switching desktops) is in
`docs/superpowers/spikes/2026-10-23-same-desktop.md`.

### Later

- A global hotkey for a blank little window (Arc's ⌘⌥N).
- Auto-closing little windows left idle.
- More browsers.
- Signed, notarized releases (Apple Developer Program) and the extension on the Chrome Web Store.
