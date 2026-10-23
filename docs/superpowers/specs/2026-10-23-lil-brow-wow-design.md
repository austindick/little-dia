# Lil Brow Wow — a "Little Arc" for Dia

Design document, 2026-10-23. Working name taken from the project folder (`~/lil-brow-wow`). The name is my call.

## Calls I made (please check these while reading)

- The name "Lil Brow Wow" comes from the project folder.
- Tech: a Swift menu-bar app for macOS 14+; a Chrome MV3 extension in plain JS with no build step; a small native-messaging helper inside the app bundle.
- The title-bar buttons show only while the little window is frontmost, so they never float over other apps.
- Little windows open centered on the screen with the mouse pointer, at the last size you used (about 1000×750 the first time).
- If Dia isn't running, it launches in the background first. If the extension can't be reached, the link opens in Dia normally.
- The first throwaway test checks Chrome alongside Dia. If only Chrome passes, v1 targets Chrome, since you said you aren't tied to Dia.
- Mac App Store is ruled out, because the sandbox blocks the title-bar buttons. Sharing would be through GitHub.

## Context: why this exists

Arc stops working on **December 22, 2026**. The owner is moving to Dia (made by the same company). The Arc feature they will miss most is **Little Arc**. When you click a link in another app (Slack, Mail, Notes, etc.), Little Arc opens a small, minimal browser window **on the macOS desktop (Space) you are already on**. It does not open a tab in the main browser window, which may live on another desktop and pull you over there.

Why it matters to them: it keeps macOS desktops clean and in order. You preview or act on a link where you are. If it's worth keeping, you promote it to the main browser with one click.

What the owner told us:
- Most links they open this way are **signed-in work tools** (GitHub, Google Docs, Jira, Figma). The rest are public pages.
- Having to sign in separately inside the little window would be **"kinda a dealbreaker."** The little window must use their real browser logins.
- They are **not tied to Dia**. They would switch to Chrome, Zen, etc. if that gave a better result. Dia is the starting target.
- Start as a local build to prove the concept. Later, share it publicly, most likely as a public GitHub repo.

**Success looks like:** clicking a link in any non-browser app never moves you to another desktop. The page opens already signed in, in a small window with minimal UI, and one click moves it into the main Dia window.

## What we learned before designing (evidence)

- **Nothing on the market does this with your real logins.** SupaSidebar's Peek View is a mini window for any browser, but it opens on ⌘-click. Nothing says it catches links from other apps, or that it keeps your logins. SigmaOS and Orion have built-in mini windows, but they are separate browsers. Velja and Finicky only pick which browser opens a link.
- **Dia popup windows are already almost exactly right.** The owner ran `window.open(url, '_blank', 'popup,width=1000,height=750')` in Dia. The result was a small window with a title bar ("GitHub"), a read-only address row ("github.com") with a download icon, and the page **already signed in** as the owner. The only thing missing is a "Move to browser" button. The owner expected that.
- **Dia supports Chrome extensions and native messaging.** Reported in anthropics/claude-code#34830. Dia is built on Chromium (`ArcCore.framework`) and keeps a `SingletonSocket`.
- **Dia has an AppleScript dictionary** (`/Applications/Dia.app/Contents/Resources/Dia.sdef`). It covers windows, tabs (URL is read/write), profiles, and running JavaScript. Windows have **no bounds property**, so AppleScript can't position windows.
- **Dia may be building this itself.** The Dia 1.54.2 binary contains internal names such as `littleBrowserWindow`, `openExternalLinksInLittleBrowserEnabled`, `globalLittleBrowserHotkeyEnabled` and `littleBrowserMoveButton`. There is no user-visible text and no public announcement, so it's probably unfinished or switched off by a feature flag. If Dia ships it, Lil Brow Wow is still useful for other browsers.
- **Chrome's extension API can't move a tab out of a popup window.** `tabs.move` only works between "normal" windows. Moving to Dia therefore means reopening the URL in the main window, which reloads the page.

## How it works (the decided shape)

Three pieces:

1. **Menu-bar app (macOS, Swift).** It is registered as the system **default browser**, so macOS sends it every http/https link clicked outside a browser. It never renders web pages. It passes each link to Dia and draws the title-bar buttons.
2. **Dia extension (Chrome Manifest V3).** It runs inside Dia, so it has the owner's logins, extensions and password manager. On request it opens a Dia **popup window** (`chrome.windows.create({type: "popup", url, left, top, width, height})`). It also handles Copy URL and Move to Dia.
3. **Native messaging helper.** A small executable inside the app bundle. Dia launches it when the extension calls `chrome.runtime.connectNative`. It relays messages between the extension (stdin/stdout, 4-byte length-prefixed JSON) and the running menu-bar app over a local channel. The builder picks the channel; a Unix domain socket in the app's Application Support folder is the suggestion. The extension keeps the port open, which also keeps its MV3 service worker alive.

### Link click flow

1. A link is clicked in Slack on desktop 2. Dia's main window is on desktop 1.
2. macOS hands the URL to the menu-bar app.
3. The app works out where the little window goes: centered on the screen that has the mouse pointer, at the last size used (default about 1000×750). It sends `{open, url, bounds}` to the extension through the helper.
4. The extension creates a Dia popup window at those bounds, and it appears on desktop 2. Whether it really lands on the current desktop without switching is the **#1 risk**; see Risks.
5. The app identifies that window through the macOS Accessibility API and attaches the title-bar buttons.

### The little window (owner-approved)

- **Dia's own popup UI.** Title bar with the page title, a read-only address row, and the download icon.
- **Two buttons drawn by the menu-bar app, sitting on the right side of the popup's title bar:** `[⧉ Copy]` and `[↗ Dia]`. They follow the window when it moves or resizes, and they show **only while that little window is the frontmost window**, so they never float over other apps. This needs macOS **Accessibility** permission. The owner picked this over an in-page floating pill and over "keyboard only," because it is closest to Little Arc.
- **Copy:** copies the little window's *current* URL (after any navigation) to the clipboard, with brief "Copied" feedback.
- **Move to Dia:** opens the current URL as a new, focused tab in the main Dia window (the most recently focused normal window), closes the little window, and takes you to Dia. Switching desktops here is intended. The page reloads, so scroll position and unsent form text are lost. That is accepted.
- **Keyboard shortcuts** for both actions, defined as extension commands. The builder picks keys that don't collide with Dia's own shortcuts.
- **Links inside the little window:**
  - Ordinary links navigate inside the same little window.
  - Links that would open a **new tab** (`target=_blank`, ⌘-click, a doc linking to another doc) open **another little window on the current desktop**. They never go to a tab in the main window (owner's choice). Approach: a content script in little windows catches those clicks first and asks the extension for a new little window. Page-script `window.open` calls that would become tabs are caught with `webNavigation.onCreatedNavigationTarget` and moved. This must be checked for desktop switches.
  - Real popups (OAuth, "Sign in with Google") behave as Dia normally handles them.
- **Each external link gets its own little window.** Windows aren't reused.

### Edge behavior (my calls, accepted by the owner in playback)

- **Profile:** little windows use the owner's **default Dia profile**, which is the one the extension is installed in. The menu shows which profile is connected.
- **Dia not running** *(changed by the owner on 2026-10-23, during the build)*: open the link in Dia's main window the normal way. Little windows only appear once Dia is already running. The original plan, launching Dia in the background and then opening a little window, lost links: Dia accepts popups created while it is still starting up but never shows them.
- **A little window that never reaches the screen:** if no new window of the requested width appears on the current desktop within about 2 s of the extension confirming it, the app closes that popup and opens the link in Dia normally. Dia is brought to the front only after the popup is on screen.
- **Extension unreachable** (disabled, not installed, or timed out): open the link in Dia the normal way. **A link must never get lost.**
- **Menu-bar menu (v1):**
  - on/off toggle (off sends every link straight to Dia normally)
  - connection status (Dia extension connected, Accessibility granted, default-browser status)
  - a "Set as default browser" helper
  - launch at login
  - quit

## Goals, non-goals, anti-goals

**Goals (v1, Dia only):** same-desktop little window, real Dia logins, minimal UI, Copy and Move to Dia in the title bar, new-tab links staying little, and reliable fallback.

**Non-goals for v1 (deferred to a later milestone):**
- A global hotkey that opens a blank little window (like Arc's ⌘⌥N). The owner wants it later.
- Auto-closing little windows that sit idle (Little Arc's archive). The owner wants it later.
- Other browsers: Chrome, Brave, Edge, Zen, Firefox. Keep every Dia-specific detail (bundle ID, native-messaging folder, popup quirks) behind one small "browser adapter" seam so these can be added. Chromium-family browsers should need only an adapter. Zen and Firefox need a Firefox build of the extension, since `browser.windows.create({type:"popup"})` and native messaging both exist there.
- Per-site rules, such as "always send zoom.us straight to Dia."
- Links clicked inside a **full-screen app**. macOS won't put another app's normal window on a full-screen desktop, so the little window will probably open on a regular desktop. The owner rarely uses full screen, so this is a known limitation: document it, and don't engineer around it.
- Keeping page state when moving to Dia.
- A built-in browser engine. **Rejected:** it would need a separate set of logins.
- The Mac App Store. **Ruled out:** App Store apps must be sandboxed, and the sandbox blocks both the Accessibility-based title-bar buttons and writing the native-messaging file into Dia's folder.

**Anti-goals (a failure even if it "works"):**
- Any link click from another app switches you to a different desktop.
- You have to sign in again inside the little window.
- A link disappears because something broke. Fallback must always open it somewhere.
- Heavy or noisy UI. It should feel as light as Little Arc.

## Constraints and environment

- The owner's Mac runs macOS 26.7, Xcode 27.1, Swift 6.4 and Dia 1.54.2. Arc, Chrome, Safari and Zen are also installed. Target **macOS 14+** so it can be shared later; that's my call.
- **Dia must not be assigned to a specific desktop** (Dock → Options → Assign To → None). Otherwise macOS puts every new Dia window on that desktop. Check for this during setup.
- Native-messaging folder for Dia: anthropics/claude-code#34830 reports `~/Library/Application Support/Dia/NativeMessagingHosts/`. Chromium convention would put it under `…/Dia/User Data/NativeMessagingHosts/`. **Verify which one Dia reads**, or install to both.
- During development the extension is loaded unpacked in Dia (developer mode). Pin its ID with a `key` in `manifest.json` so the native-messaging manifest's `allowed_origins` stays valid.

## Risks: check these first, in a throwaway spike, before building for real

1. **Same-desktop placement (the whole idea depends on it).** Put the browser's main window on desktop 1, stand on desktop 2, and have the extension create a popup. Does it appear on desktop 2 *without* macOS switching to desktop 1? Test with `focused: true`. Also test with `focused: false` followed by the app raising the window and activating the browser. The owner's Mac currently has the macOS setting "When switching to an application, switch to a Space with open windows for the application" **on** (the default), and Dia is **not** assigned to a desktop (both checked).
   - **Run the same test in Chrome alongside Dia.** The extension is the same, so the extra cost is small. The owner said they aren't tied to Dia (answered already), so if Dia fails and Chrome passes, v1 targets Chrome instead. That means the "browser adapter" seam (bundle ID, native-messaging folder, launch behavior) exists from day one, even with only one adapter filled in. Zen gets tested only if both Chromium browsers fail, because it needs a Firefox build of the extension.
   - **If a browser passes only after that setting is turned off, pause and ask the owner** before building on that result. They'll decide once they see the evidence (their choice). Record whether each browser passes with the setting on and with it off.
   - If nothing passes, stop and rethink before building anything else.
2. **Finding the popup through Accessibility, and tracking it smoothly.** Can the app reliably tell which Dia window is the new little window? Match by creation timing plus frame, using bounds the extension reports. Do overlay buttons follow drags and resizes acceptably? If tracking feels janky, the in-page pill is the fallback the owner saw.
3. **Dia specifics.** Loading unpacked extensions, the native-messaging folder, and whether new-tab links can be redirected without a desktop flash.

## Left to the builder

- Repo layout, project generation (an Xcode project or XcodeGen), and module boundaries. Use `git init` in `~/lil-brow-wow`.
- The app-to-helper channel, the message schema, and how the app is told about window IDs and bounds.
- How the app registers as the default browser: it must declare http/https URL types and HTML document types to appear in System Settings' default-browser list. It also needs to handle the `kAEGetURL` Apple Event.
- The look of the title-bar buttons (native, small, matching the title bar), the "Copied" feedback, and the keyboard shortcuts.
- The extension language. Plain JS with no build step is the suggestion.
- Logging and diagnostics.

## Verification (end to end, on the owner's Mac)

- **Automated:** unit tests for native-messaging framing (encode/decode), message routing, screen-coordinate conversion (AppKit's bottom-left origin vs Chromium's top-left), and the fallback logic (no extension → opens in Dia).
- **Manual checklist:**
  1. Put Dia on desktop 1. On desktop 2, click a GitHub link in Slack. A little window appears on desktop 2, signed in, and you are not moved.
  2. The title-bar buttons appear on the little window, follow it when dragged, and hide when another app's window is in front.
  3. Copy puts the current URL on the clipboard after navigating inside the little window.
  4. Move to Dia opens the page as a tab in the main window, closes the little window, and takes you to desktop 1.
  5. A `target=_blank` link inside the little window opens a second little window on desktop 2 with no desktop flash.
  6. Quit Dia, then click a link. Dia opens with the link in its main window, and no little window appears.
  7. Disable the extension, then click a link. It opens in Dia normally.
  8. Turn the menu-bar toggle off. Links open in Dia normally.
  9. `mailto:` and other non-web links are unaffected.

## Path to sharing (later milestone)

A public GitHub repo. App releases signed with a Developer ID and notarized; that needs the Apple Developer Program at $99/year, otherwise others hit Gatekeeper warnings. Optionally a Homebrew cask. The extension goes on the Chrome Web Store ($5 one-time), which Dia installs from.

## Next step after approval

Save this document to `~/lil-brow-wow/docs/superpowers/specs/2026-10-23-lil-brow-wow-design.md`, run `git init`, then write the implementation plan (superpowers:writing-plans). The plan starts with the Risk #1 spike.
