# Little Dia

Little Arc for [Dia](https://www.diabrowser.com). Click a link in Slack, Mail, Notes or any other app, and it opens in a
small Dia window **on the macOS desktop you're already on**, instead of pulling you over to wherever Dia's main window
lives. You stay signed in, because it really is Dia.

Arc stops working on December 22, 2026; this keeps the one Arc feature Dia doesn't have.

## Install

Requires macOS 14 or later and [Dia](https://www.diabrowser.com). Paste this into Terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash
```

It installs `Little Dia.app` in `~/Applications` and opens it. Look for the overlapping-windows icon in the menu bar,
and the setup window.

Little Dia isn't notarized by Apple. Installing with the command above avoids the warning macOS shows for apps
downloaded in a browser.

## Setup

The setup window ticks each step off as you finish it:

1. **Make it your default browser.** Links from other apps come to Little Dia first; it hands them to Dia.
2. **Add the extension to Dia.** Click *Open Extensions Page* and turn on **Developer mode** (top right). Click
   *Show Folder*, then drag the highlighted **Extension** folder onto the page (or click **Load unpacked** and choose
   it). It lives at `~/Library/Application Support/Little Dia/Extension`. Add it in the Dia profile you want little
   windows to use.
3. **Allow the title-bar buttons.** Turn on Little Dia in System Settings › Privacy & Security › Accessibility.
4. Only if it's needed: **Dia is pinned to one desktop.** Dock › right-click Dia › Options › Assign To › None.

Reopen it any time from the menu bar: *Setup…*.

## Using it

- Click a link in any app: it opens in a little window on this desktop.
- The little window's title bar has two buttons:
  - **Copy** (the link icon) copies the page's current URL.
  - **Open in Work** (your profile's name) moves the page into Dia's main window, keeping your scroll position and
    anything you've typed, and takes you there. The **⌄** next to it opens the page in another of your Dia profiles.
- Links inside a little window that would open a new tab open another little window instead.
- Closing a little window puts you back in the app you came from.
- Resize one and the next ones open at that size.
- If Dia isn't running, links open in its main window as usual; little windows start once Dia is open.
- Turn little windows off any time with *Open Links in Little Windows* in the menu.

## Updating

Choose *Check for Updates…* in the menu. Little Dia also checks once a day and shows *Update to …* in the menu when
there's a new version; it never installs without your click. The extension updates itself along with the app.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash -s -- --uninstall
```

Then:

- Set Dia as your default browser: System Settings › Desktop & Dock › Default web browser.
- Remove the Little Dia extension in Dia: `chrome://extensions`.

## Troubleshooting

- **The menu's status line names the problem.** Click it to open the setup window.
- **Something's off?** Choose *Copy Diagnostics* and paste it into a message to whoever shared Little Dia with you.
  It has versions, setup status and recent log lines; web addresses are left out.
- **"Dia extension not connected":** in Dia's `chrome://extensions`, check that Little Dia is turned on, and that it was
  loaded from `~/Library/Application Support/Little Dia/Extension`. Then click its reload icon.
- **No buttons on little windows:** check that Little Dia is turned on in System Settings › Privacy & Security ›
  Accessibility.
- **The app's log:** `/usr/bin/log stream --predicate 'subsystem == "com.austindick.littledia"'`. (In zsh, plain
  `log` is a shell builtin, so use the full path.)

## Known limitations

- **Full-screen apps:** macOS won't put another app's window on a full-screen desktop, so a link clicked there opens in
  Dia's main window after about 2 seconds.
- **Briefly drawn behind:** a new little window can appear behind the current app for a few hundredths of a second
  before coming forward.
- **Buttons hide while you drag or resize** a little window, and come back when you let go.
- **Dia only.** Dia's app contains an unreleased "Little Browser", so Dia may ship its own version of this one day.

## How it works

```
link clicked in Slack ─▶ Little Dia (default browser, menu bar)
                              │  native messaging (littledia-host helper)
                              ▼
                         Dia extension ─▶ chrome.windows.create({type: "popup"}) on this desktop
```

- **Little Dia** (`Sources/LittleDia`) is a menu-bar app registered as the default browser. It never shows web pages.
  It works out where the little window goes, brings Dia forward once the window is on screen, and draws the title-bar
  buttons, finding the window through the Accessibility API.
- **The extension** (`Extension/`) runs inside Dia, so it has your logins, extensions and password manager. It opens
  the popup, reports navigation, moves the live tab into the main window, and turns new-tab links inside a little
  window into more little windows. The app ships it and keeps Dia's copy up to date.
- **`littledia-host`** is the native-messaging helper Dia launches for the extension. It relays messages to the app
  over a Unix socket that only the app's own helper, launched by Dia, may use.
- `Sources/LittleDiaCore` holds the tested logic: the message protocol, geometry, routing, focus handling, setup
  status, updates and diagnostics.

If anything goes wrong, the link opens in Dia normally, so a link is never lost.

## Development

You need Xcode (or the Swift 6 toolchain) and Node.js for the extension tests.

```bash
swift test                                  # app logic (Swift Testing)
node --test 'Extension/test/*'              # extension logic
bash scripts/test-install.sh                # install.sh, in a temp folder
scripts/build-app.sh --install              # build, sign, install, launch
```

Sign your builds with a stable identity, or macOS will forget the Accessibility permission on every rebuild. A
self-signed one is fine: Keychain Access › Certificate Assistant › Create a Certificate…, with *Certificate Type:
Code Signing*. Then build with `LITTLEDIA_SIGN_IDENTITY="<its name>" scripts/build-app.sh --install`.

Releases are made with `scripts/release.sh` from `main`, signed with the project's "Little Dia" certificate; that's
what lets an update keep its Accessibility permission.

Design notes, plans and the spike that proved the approach are in `docs/superpowers/`.

---

Not affiliated with or endorsed by The Browser Company.

Licensed under the [MIT License](LICENSE).
