# Little Dia: getting it ready to share

Design document, approved 2026-10-24. This is the second milestone; the v1 design is `docs/superpowers/specs/2026-10-23-lil-brow-wow-design.md`.

## Calls I made (please check these while reading)

- **Install for free.** Coworkers install with one Terminal command, which avoids Gatekeeper's warning, and load the extension in Dia's Developer mode. We skip both paid routes: the $99/yr Apple developer account and the $5 Chrome Web Store listing.
- **Signing details.** A new self-signed certificate, **"Little Dia"** (you decided on a new one rather than reuse the certificate of another project).
  - Valid for 20 years.
  - Used for both releases and local builds.
  - Back it up once to your password manager. If it's lost, every coworker has to grant Accessibility once more.
- **Repo timing.** The repo is private while I polish, then made public.
- **Identifiers.** The project folder stays `~/lil-brow-wow`. Everything else is renamed, including the app ID and code module names. The extension ID stays the same.
- **Setup window behavior.** It opens on any launch while a required step is unfinished, not only the first time.
- **Docs.** `docs/superpowers` (design, plan and spike notes) stays in the public repo. `spike/` is deleted.
- **Icon.** I'll show you 2–3 options before picking one.

## Context: why this milestone

v1 works well for the owner day to day ("Nothing major comes to mind, it's been working well"). The next goal is to share it with **a few coworkers who are also moving from Arc to Dia**. They are "somewhat comfortable" with technical setup, "but the fewer steps the better."

Today, installing means building from source with Xcode, plus five manual steps. The app also has rough edges that matter once it runs on Macs we can't watch.

**Success looks like this:** a coworker pastes one command, clicks through a setup window that ticks itself off, and has the same little windows the owner has. When something goes wrong on their Mac, they can send a useful report with one click. The project is on GitHub, public, under the owner's personal account.

**Owner decisions, made in conversation:**
- **Who it's for:** a few coworkers moving from Arc to Dia, somewhat technical; the fewer setup steps the better.
- **Setup:** the coworker setup flow and menu shown in the mockup (approved: "This looks good").
- **Repo:** public, on the owner's **personal** GitHub (`austindick`), never an employer's.
- **Commit authorship:** `Austin Dick <5875295+austindick@users.noreply.github.com>`. **Done already:** all 41 commits were rewritten, and the repo's own `user.email` is set to that address. The old history is kept only as the local backup ref `refs/original/refs/heads/main`.
- **Name:** **Little Dia.** It's purpose-built for Dia. If Dia ships an official version, this project gets thrown away, so how long the name lasts doesn't matter.
- **Signing:** use a **new, differently named certificate**. The certificate already on this Mac belongs to a separate project.
- **Deferred:** auto-closing idle windows and the blank-little-window hotkey.
- **Scope:** the six-part list below, which the owner approved: "Nothing's missing."

## Goals, non-goals, anti-goals

**Goals:**
- One-command install.
- A setup window that ticks itself off.
- A one-line "All set" menu.
- In-place updates for both the app and the extension.
- Copy Diagnostics.
- The rename to Little Dia.
- Fixes that make it robust on other people's Macs.
- A public repo with a coworker-ready README.

**Non-goals:**
- Notarization or a Developer ID.
- A Chrome Web Store listing.
- Browsers other than Dia.
- Auto-closing idle windows, and the blank-window hotkey (both deferred).
- Telemetry.
- Re-attaching buttons to little windows that were opened before the app restarted (the owner said leave it).

**Anti-goals (a failure even if it "works"):**
- A coworker gets stuck in setup without knowing what to do next.
- An update makes them grant Accessibility again, or silently breaks the extension.
- Anything suggests the project is an official Dia product.
- Diagnostics leak the URLs people browse.
- Any v1 behavior regresses: same-desktop windows, real logins, never losing a link, focus returning to the source app, the live move with no reload, the profile menu.

## The decided shape

### 1. Rename to Little Dia (my calls, except the name)

Everything except the folder and the extension ID gets the new name:

| Item | Old | New |
|---|---|---|
| Display name | Lil Brow Wow | Little Dia |
| App bundle | `LilBrowWow.app` | `Little Dia.app` |
| Bundle ID | `com.lilbrowwow.LilBrowWow` | `com.austindick.littledia` |
| Native host name | `com.lilbrowwow.bridge` | `com.austindick.littledia.bridge` |
| Support folder | `~/Library/Application Support/LilBrowWow/` | `~/Library/Application Support/Little Dia/` |
| Log subsystem | `com.lilbrowwow` | `com.austindick.littledia` |
| SwiftPM targets | `LilBrowCore`, `LilBrowWow`, `lilbrow-host` | `LittleDiaCore`, `LittleDia`, `littledia-host` |
| JS global | `LilBrowClickRules` | `LittleDiaClickRules` |
| Signing env var | `LILBROW_SIGN_IDENTITY` | `LITTLEDIA_SIGN_IDENTITY` |
| Socket env var | `LILBROW_SOCKET` | `LITTLEDIA_SOCKET` |

- **Extension ID:** keep the pinned `key`, so `ofecdibidhgnemdblacfbinlhngigjnm` stays.
- **Repo:** `github.com/austindick/little-dia`.
- **No migration code.** Only the owner has the old install. Cleaning it up is a one-time manual checklist (see Verification).

### 2. Install and releases (my calls, except the new certificate)

- **Signing certificate.** A self-signed code-signing certificate named **"Little Dia"**, valid for 20 years, in the owner's login keychain. Every build is signed with it: releases and the owner's local builds (`LITTLEDIA_SIGN_IDENTITY="Little Dia"`).
  - **Why it matters:** the same certificate and identifier on every version is what lets coworkers keep the Accessibility permission through updates.
  - **Creating it:** generate a key and certificate with `openssl` (code-signing extended key usage), then import them into the login keychain with `security import`.
  - **Trusting it for code signing:** `security add-trusted-cert … -p codeSign`, or Keychain Access's Certificate Assistant. Either way, macOS asks the owner for their password, so the owner does that step.
  - **Backup:** export a `.p12` once, to be kept in the owner's password manager. It never goes in the repo.

- **The install command** is the line in the README:
  `curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash`
- **What `install.sh` does:**
  - Downloads `https://github.com/austindick/little-dia/releases/latest/download/Little-Dia.zip`.
  - Quits a running copy, unzips with `ditto` into `~/Applications` (creating it if needed), and registers the app with LaunchServices.
  - Opens the app, retrying once on the -600 error as `build-app.sh` does.
  - Files downloaded with curl carry no quarantine flag, so Gatekeeper never prompts.
- **Script options:**
  - `install.sh <path-to-zip>` installs a local zip, for testing before a release is public.
  - `install.sh --uninstall` removes the app, the support folder and both native-host manifests. It then tells the person to pick Dia as default browser again and remove the extension in Dia.
- **`scripts/release.sh`:**
  - Builds and signs, then zips with `ditto -c -k --keepParent`.
  - Refuses to run if the app's version (`CFBundleShortVersionString`) and the extension's `manifest.json` version differ.
  - Creates release `v<version>` with `gh` and attaches `Little-Dia.zip`.
- **The first release is 1.0.0.**
- **Architecture:** a universal build (Apple silicon and Intel) if `swift build --arch arm64 --arch x86_64` handles it cleanly. Otherwise Apple silicon only, and the README says so.

### 3. Extension delivery and updates (my calls)

- **Where the extension lives:** `Little Dia.app/Contents/Resources/Extension`.
  - On every launch, if the bundled copy's version differs from the one at `~/Library/Application Support/Little Dia/Extension`, the app copies it there.
  - Dia loads the extension unpacked from that stable folder, so it survives app updates.
- **When the versions differ:** the extension's existing `hello` already reports its version. If it differs from the bundled one, the app sends a new `reload` message, and the extension calls `chrome.runtime.reload()`, which re-reads the folder.
- **Check for Updates:**
  - The app asks the GitHub API for the latest release (`releases/latest`), on demand from the menu and automatically once a day.
  - If a newer version exists, the menu shows "Update to X…". It **never installs without a click**.
  - Installing downloads the zip, unzips it to a temporary folder, and checks that the new app satisfies the running app's designated requirement (same identifier, same certificate). Then it replaces the app and relaunches.
  - If the check fails, nothing changes and the menu says why.

### 4. Setup window and menu (owner approved the mockup; details are my calls)

**Setup window (title "Set Up Little Dia")**

Rows, each with a live status that refreshes about once a second while the window is open:
- **Make it your default browser:** **Set as Default** calls the existing `SystemIntegration.makeDefaultBrowser()`.
- **Add the extension to Dia:**
  - Three numbered steps: open Dia's Extensions page, turn on **Developer mode**, drag the Little Dia folder onto the page.
  - Buttons: **Open Extensions Page** and **Show Folder**.
  - Status: "Waiting for the extension…" until a `hostHello` arrives.
  - The copy says to do this in the Dia profile you want little windows to use.
- **Allow the title-bar buttons:** **Open Settings** prompts for Accessibility and opens its settings pane, using the existing functions in `SystemIntegration`.
- **Dia is pinned to one desktop:** shown only when `isBrowserAssignedToDesktop` says so, with the Dock instructions.
- **Footer:**
  - An **Open at login** checkbox, checked by default, which registers the login item on the first launch.
  - **Done**, enabled once the three required rows are done.
- **When it opens:** by itself on launch while any required row is unfinished, at most once per launch. The menu can always open it.
- **The two unverified buttons:**
  - Builder checks early whether Dia accepts **Open Extensions Page** (`chrome://extensions` through Dia's AppleScript `make new tab`) and dragging a folder onto that page.
  - Fallbacks: copy `chrome://extensions` to the clipboard with "paste into Dia's address bar"; or the **Load unpacked** picker, with the folder path copied for ⌘⇧G.
  - The row's wording follows whichever works.

**Menu (from the mockup)**

```
✓ Open Links in Little Windows
───
All set · <profile>          (or the first problem, e.g. "Dia extension not connected")
Setup…
───
Check for Updates…           (becomes "Update to X…" when one is available)
Copy Diagnostics
About Little Dia
───
Quit Little Dia   ⌘Q
```

- **Status line:**
  - Clicking a problem line opens the setup window.
  - `<profile>` is the Dia profile the extension is in (`BrowserProfiles.current`).
  - **When Dia isn't running:** the line doesn't claim "not connected". It reports the extension as installed when a profile's Preferences list its ID (`BrowserProfiles.load` already checks this).
- **About:** the standard About panel, with the version, the GitHub link, and "Not affiliated with or endorsed by The Browser Company."
- **Copy Diagnostics puts this on the clipboard:**
  - app, extension, macOS and Dia versions
  - each setup row's status
  - profile names found, and which one has the extension
  - the measured title-bar height
  - the last hour of the app's own log, read with `OSLogStore(scope: .currentProcessIdentifier)`
  - URLs stay redacted, because the logs already mark them `.private`

### 5. Robustness on other Macs (my calls; most are the deferred v1 review items)

- **Only the real extension may talk to the app.**
  - The support folder gets mode 0700 and the socket 0600.
  - On accept, the app checks two signatures with the peer's process ID (`LOCAL_PEERPID`):
    - The peer must be the bundled `littledia-host`, signed by the same certificate as the app.
    - Its parent process must be the configured browser (Dia's bundle ID).
  - Anything else is closed.
  - Why: otherwise any process running as the user could connect last, become the "newest ready" connection, and receive every clicked URL.
- **A dropped connection fails in-flight opens immediately.** `BridgeExtensionLink` resolves pending opens on that connection as `.failed`, so the router falls back to Dia right away instead of waiting for the timeout.
- **No display, no crash:** the `screens[0]` uses are guarded, and with no screen the link opens normally.
- **The Accessibility observer's run-loop source is removed** when Dia quits.
- **The unused inbound `copy` message is removed.**
- **Modifier clicks:** they count only on the left or middle button, in `click-rules.js`.
- **Measured title-bar height:**
  - Once a little window settles, the app records its window height minus the page height it asked for, and uses that instead of the fixed 72pt for the next placement.
  - The app sends this value with each `open`, so the extension's `reportedBounds` uses the same number, instead of `DIA_CHROME_HEIGHT` in `background.js`.
- **The 60Hz drag timer stays as is.** It only checks the mouse button while the mouse is up, so it costs next to nothing.

### 6. Public-repo cleanup (my calls)

- **README rewritten for coworkers:**
  - what it is, with a screenshot
  - install, the setup window, updating, uninstall, troubleshooting (including Copy Diagnostics), known limitations
  - the not-affiliated line
  - a "Development" section at the end
- **License:** MIT, "Copyright (c) 2026 Austin Dick".
- **Delete `spike/`**, both the tracked files and the built `LBWSpike.app`.
- **Machine-specific notes:** replace the docs' mentions of the other project's certificate with "a stable self-signed identity". The README's Development section explains how to make your own certificate for local builds.
- **App icon:** our own, never Dia's logo or colors. I show the owner 2–3 options in the mockup browser tab before committing one.
  - It's built by a checked-in script into an `.icns`.
  - The menu-bar icon stays the SF Symbol.

## Constraints

- macOS 14+.
- Coworkers' Macs are company-managed like the owner's. Dia allows loading an unpacked extension there; Chrome doesn't.
- No Apple developer account, and no notarization.
- **These need the owner's go-ahead at the moment they happen:**
  - creating the GitHub repo
  - creating and trusting the "Little Dia" certificate (the owner types the password)
  - making it public
  - publishing a release
  - the cleanup of the owner's old install, which removes an Accessibility entry and a login item

## Left to the builder

- SwiftUI or AppKit for the setup window.
- The exact text of status lines.
- The diagnostics format.
- The update check's HTTP and version-compare code.
- How the peer-signature check is done (e.g. `SecCodeCopyGuestWithAttributes` with the peer PID).
- The structure of the release script.
- The icon designs.
- The order of tasks. Suggested: rename first, so later work lands on final names; then robustness; then setup and menu; then updates; then the release; then repo cleanup.

## Critical files

- **Rename (every file):** `Package.swift`, `Resources/Info.plist`, `scripts/build-app.sh`, `Extension/manifest.json`, `Extension/background.js`, `Extension/click-rules.js`, every `Sources/` and `Tests/` file.
- **Identity:** `Sources/LilBrowCore/ExtensionIdentity.swift`, `NativeHostManifest.swift`.
- **Socket checks, dropped connections:** `Sources/LilBrowCore/BridgeServer.swift`, `BridgeExtensionLink.swift`, `UnixSocket.swift`.
- **Router and geometry:** `LinkRouter.swift`, `ScreenGeometry.swift`, `BrowserAdapter.swift` (the measured title-bar height).
- **Menu and setup:** `Sources/LilBrowWow/StatusMenu.swift` (rewritten), `SystemIntegration.swift` (reused by the setup window), `AppDelegate.swift` (wiring, extension copy and `reload`, updater), `LittleWindowTracker.swift` (title-bar height measurement, removing the run-loop source).
- **New:**
  - in `LittleDia`: `SetupWindow`, `Updater`, `Diagnostics`
  - in `LittleDiaCore`: `SetupStatus`, `ReleaseInfo`/version compare, `ExtensionInstaller` (the copy-and-reload decision)
  - repo root: `install.sh`, `scripts/release.sh`, `scripts/make-icon.*`, `LICENSE`, a new `README.md`
- **Reused:**
  - `BrowserProfiles.load` (`Sources/LilBrowCore/BrowserProfiles.swift`): the profile name and whether the extension is installed
  - `DiaScript` (the AppleScript for "Open Extensions Page")
  - `runAppleScript` in `AppDelegate`
  - `SystemIntegration.*`

## Verification

**Automated**

Run with `swift test` and `node --test 'Extension/test/*'`; today 87 Swift and 21 extension tests pass, and all must stay green. New tests cover:
- the version compare and choosing the release asset
- the decision of when to copy and reload the extension
- the setup status model, including the "Dia not running but extension installed" case
- dropped connections failing in-flight opens
- the socket peer check rejecting a process that isn't ours
- the measured title-bar height being used for placement and sent with `open`
- the diagnostics leaving URLs out
- the click rules ignoring right-clicks with modifiers
- `release.sh` refusing mismatched versions

**Owner's old install: cleanup, then a clean install**

With the owner's go-ahead:
1. Quit the old app and delete `~/Applications/LilBrowWow.app`.
2. Remove `com.lilbrowwow.bridge.json` from both Dia NativeMessagingHosts folders, `~/Library/Application Support/LilBrowWow`, and the defaults for `com.lilbrowwow.LilBrowWow`.
3. Remove the old extension from Dia, and the old Accessibility and login-item entries.
4. Unregister and delete `LBWSpike.app`, and remove its Accessibility entry.
5. Install with `install.sh <local zip>`, signed with the new "Little Dia" certificate, and go through the setup window from scratch.

**Manual checklist (owner's Mac)**

1. The setup window ticks off each row live. Done is enabled only when the required rows are done. Closing it and relaunching reopens it only if something is unfinished.
2. The menu shows "All set · Work". Disabling the extension in Dia turns that line into a problem, and clicking it opens setup. With Dia quit, it still says All set.
3. All v1 behaviors from the v1 checklist still pass: same-desktop window, signed in, buttons, Copy, Open in profile and the profile menu, the live move with no reload, focus returning on close, new-tab links opening little windows, fallback when Dia isn't running, the toggle off, `mailto:` unaffected.
4. Install 1.0.0, then publish a test 1.0.1. **Check for Updates** offers it, installs it and relaunches; Accessibility is still granted; the extension reloads with the new version, with no developer-mode clicks.
5. Copy Diagnostics pastes useful text that contains no URLs.
6. `install.sh --uninstall` leaves nothing behind except the default-browser choice and the extension, and it prints instructions for both.

**After going public:** run the real one-line command on the owner's Mac. Optionally, run it in a fresh macOS user account to walk the coworker path from zero (the owner's call). Then send it to one coworker before the rest.

## Next steps after approval

1. Save this document to `docs/superpowers/specs/2026-10-24-little-dia-sharing-design.md` and commit.
2. Create the **private** repo `austindick/little-dia` and push `main`. Once the push is confirmed, delete the local backup ref `refs/original/refs/heads/main`.
3. Write the implementation plan (superpowers:writing-plans).
