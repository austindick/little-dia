# Lil Brow Wow Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Links clicked outside the browser open in a small Dia popup window on the macOS desktop you're on, signed in with your real Dia logins. The window has Copy and Move-to-Dia buttons on its title bar.

**Architecture:** A Swift menu-bar app is registered as the default browser. It receives every http/https link, works out where the window should go, and asks a Dia MV3 extension (through a native-messaging helper and a Unix socket) to open a `type: "popup"` window. The app finds that window through the Accessibility API and draws a small non-activating panel with two buttons over its title bar. Every failure path opens the link in Dia normally.

**Tech Stack:** Swift 6.4 toolchain (SwiftPM, Swift language mode 5, Swift Testing), AppKit, ApplicationServices (AX), ServiceManagement; Chrome Manifest V3 extension in plain JS, tested with `node --test` (Node 22). No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-23-lil-brow-wow-design.md`

## Global Constraints

- macOS 14.0 minimum (`platforms: [.macOS(.v14)]`, `LSMinimumSystemVersion` 14.0). swift-tools-version 6.0, `swiftLanguageModes: [.v5]`.
- No third-party dependencies, Swift or JS. The extension has no build step.
- Names:
  - App display name: `Lil Brow Wow`
  - Bundle ID: `com.lilbrowwow.LilBrowWow`
  - App executable: `LilBrowWow`
  - Helper executable: `lilbrow-host` (at `Contents/Helpers/`)
  - Native-messaging host name: `com.lilbrowwow.bridge`
  - Socket path: `~/Library/Application Support/LilBrowWow/bridge.sock`
  - Log subsystem: `com.lilbrowwow`
- Browser bundle IDs: Dia `company.thebrowser.dia`, Chrome `com.google.Chrome`.
- Little window default size 1000×750. Minimum 480×360. 40pt margin from the screen's visible edges.
- Timeouts:
  - Browser launch → extension ready: 10 s
  - Browser running but not ready: 2 s
  - `open` acknowledgement: 4 s
- **A link must never be lost:** every failure path ends in `openNormally` (open in the browser app explicitly, never through the default-browser handler).
- **Anti-goal:** a link clicked in another app must never switch you to a different desktop.
- Environment: `swift build` and `swift test` fail inside the Claude Code sandbox (xcrun cache in `/var/folders`), so run them with the sandbox disabled. `open` and `osascript` are also sandbox-blocked.
- Little-window buttons: `Copy` (SF Symbol `link`) and the browser name (SF Symbol `arrow.up.forward.app`, title e.g. `Dia`).

## Review Focus

1. **Cold start:** macOS launches the app *because of* a link, before the helper has reconnected. The link must still open little once the extension is ready (within the 2 s or 10 s waits). Test: `LinkRouter` "running but not ready, becomes ready during the wait" (Task 7), and `BridgeExtensionLink.waitUntilReady` returning true when a client connects mid-wait (Task 6).
2. **Pointer on a secondary display with negative coordinates:** the window must open centered on that display. Test: `ScreenGeometry` negative-x screen case (Task 3).
3. **Real-world URLs** (percent-encoding, query strings, fragments, very long Google Docs links) must arrive in the browser byte-for-byte. Test: `MessageCoding` round trip (Task 2).
4. **The browser quits or crashes mid-session:** the menu must show "Not Connected", and the next link must go through the launch path, not hang. Test: `BridgeServer` `notReadyAfterClientDisconnects` (Task 6).
5. **Two little windows with identical bounds** (two links clicked quickly): buttons must attach to the right window. Test: `matchLittleWindow` skips already-tracked candidates (Task 3).

---

## File Structure

```
Package.swift
Resources/Info.plist                     app Info.plist (URL types, HTML doc types, LSUIElement)
scripts/build-app.sh                     builds + assembles + signs build/LilBrowWow.app; --install
Sources/LilBrowCore/                     all testable logic
  Framing.swift                          NativeMessageFraming, FrameDecoder
  Messages.swift                         Bounds, OutboundMessage, InboundMessage, MessageCoding
  ScreenGeometry.swift                   ScreenContext, ScreenGeometry, WindowCandidate, matchLittleWindow, OverlayVisibility
  BrowserAdapter.swift                   BrowserAdapter, DesktopAssignment
  ExtensionIdentity.swift                chromiumID, nativeHostName
  NativeHostManifest.swift               manifest JSON + install
  UnixSocket.swift                       POSIX listen/connect/accept helpers
  HostRelay.swift                        stdin/stdout <-> socket relay used by lilbrow-host
  BridgeServer.swift                     socket server the helpers connect to
  BridgeExtensionLink.swift              ExtensionLink over BridgeServer (request/ack)
  Settings.swift                         FocusStrategy, LittleSettings, UserDefaultsSettings
  LittleWindowRegistry.swift             windowId -> url/bounds bookkeeping
  LinkRouter.swift                       routing + fallback decisions
Sources/lilbrow-host/main.swift
Sources/LilBrowWow/
  main.swift, AppDelegate.swift          wiring
  BrowserControlImpl.swift               NSWorkspace launch/open
  SystemIntegration.swift                default browser, Accessibility, login item, desktop assignment
  StatusMenu.swift                       NSStatusItem menu
  LittleWindowTracker.swift              AX matching/observing/raising
  TitleBarOverlay.swift                  NSPanel with Copy / Move buttons
Tests/LilBrowCoreTests/*.swift
Extension/
  manifest.json, background.js, bridge-logic.js, click-rules.js, content.js
  test/bridge-logic.test.mjs, test/click-rules.test.cjs
spike/                                   Task 0 only (throwaway)
docs/superpowers/spikes/2026-10-23-same-desktop.md
README.md
```

---

### Task 0: Same-desktop spike (throwaway, GATE)

**Run by the main session together with the owner, not a subagent.** It needs the owner to switch desktops and watch.

**Files:**
- Create: `spike/extension/manifest.json`, `spike/extension/popup.html`, `spike/extension/popup.js`, `spike/extension/background.js`, `spike/probe.swift`
- Create: `docs/superpowers/spikes/2026-10-23-same-desktop.md` (results)

- [ ] **Step 1: Build the spike extension.**
  - MV3, name `LBW Space Spike`, `action.default_popup = popup.html`, a module service worker, no permissions needed.
  - The popup has two buttons: `Focused (15 s)` and `Unfocused (15 s)`. Each sends `{mode: "focused" | "unfocused"}` to the background.
  - The background waits 15 000 ms, then calls `chrome.windows.create({type: "popup", url: "https://github.com", left: 200, top: 150, width: 1000, height: 750, focused: mode === "focused"})`.

- [ ] **Step 2: Write `spike/probe.swift`.** Usage: `swift spike/probe.swift <browserBundleID> [--raise]`.
  1. Prints `Press Return when you're back on this desktop`, then waits for Return.
  2. Snapshots the on-screen windows (`CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)`): the frontmost app's layer-0 windows, and the set of the browser's window numbers.
  3. Polls every 100 ms for 25 s.
     - A **new** browser window that is on-screen, layer 0, about 1000×750 (±40), counts as `appeared`.
     - Every snapshotted frontmost-app window going off-screen counts as `switched`.
  4. With `--raise`, once `appeared` happens: find that window through AX (`AXUIElementCreateApplication(pid)` → `kAXWindowsAttribute`, matching on position and size), call `AXUIElementPerformAction(win, kAXRaiseAction)`, then call `NSRunningApplication(processIdentifier:)?.activate()`. Wait 1 s and re-check both conditions.
  5. Prints `PASS: little window on this desktop, no switch` or `FAIL: appeared=<bool> switched=<bool>`.
  6. Prompts for Accessibility permission (`AXIsProcessTrustedWithOptions`) if `--raise` is given.

- [ ] **Step 3: The owner loads `spike/extension` unpacked** in Dia and in Chrome: the browser's extensions page, then Developer mode, then Load unpacked. Record whether Dia allows unpacked loading.

- [ ] **Step 4: Run the matrix** with the owner. Put the browser's normal window on desktop 1 and a Terminal window on desktop 2. The macOS setting "When switching to an application, switch to a Space with open windows" stays **on**. For each cell:
  1. In Terminal on desktop 2, start the probe.
  2. Swipe to desktop 1 and click a spike button.
  3. Swipe back to desktop 2 and press Return.

  | Browser | Mode | Probe flag |
  |---|---|---|
  | Dia | Focused | — |
  | Dia | Unfocused | `--raise` |
  | Chrome | Focused | — |
  | Chrome | Unfocused | `--raise` |

- [ ] **Step 5: Record results** in `docs/superpowers/spikes/2026-10-23-same-desktop.md`: one PASS/FAIL row per cell, plus anything the owner saw, such as a desktop "flash".

- [ ] **Step 6: GATE. Stop and report to the owner.** Then decide:
  - If Dia passes in either mode: adapter = `dia`, and `FocusStrategy` default = `focusOnCreate` if Focused passed, otherwise `createThenRaise`.
  - If only Chrome passes: adapter = `chrome`, with the same rule for the strategy.
  - If nothing passes: repeat the failing cells with the setting **off**. If they pass now, **ask the owner** whether turning the setting off is acceptable before going on (their decision). If nothing passes at all, stop the plan and rethink with the owner.
  - Write the chosen adapter and strategy at the top of the spike notes. Tasks 7 and 9 read them.

- [ ] **Step 7: Commit**

```bash
git add spike docs/superpowers/spikes
git commit -m "spike: same-desktop popup placement results"
```

---

### Task 1: Swift package and native-messaging framing

**Files:**
- Create: `Package.swift`, `Sources/LilBrowCore/Framing.swift`, `Sources/LilBrowWow/main.swift` (placeholder `print("LilBrowWow")`), `Sources/lilbrow-host/main.swift` (placeholder)
- Test: `Tests/LilBrowCoreTests/FramingTests.swift`

**Interfaces:**
- Produces:
  - `NativeMessageFraming.maxFrameSize: Int = 1_048_576`
  - `NativeMessageFraming.encode(_ payload: Data) -> Data`
  - `struct FrameDecoder { init(); mutating func append(_ chunk: Data) throws -> [Data] }`
  - `enum FramingError: Error, Equatable { case frameTooLarge(Int) }`

- [ ] **Step 1: Write `Package.swift`.**
  - Products: executables `LilBrowWow` and `lilbrow-host`.
  - Targets:
    - `LilBrowCore` (library)
    - `LilBrowWow` (executableTarget, depends on Core)
    - `lilbrow-host` (executableTarget, depends on Core)
    - `LilBrowCoreTests` (testTarget)
  - Set `swiftLanguageModes: [.v5]` and `platforms: [.macOS(.v14)]`.
- [ ] **Step 2: Write the failing tests** (Swift Testing):

```swift
@Test func encodePrefixesLittleEndianLength() {
    #expect(NativeMessageFraming.encode(Data("{}".utf8)) == Data([2, 0, 0, 0, 0x7B, 0x7D]))
}
@Test func decodesFrameSplitAcrossChunks() throws {
    var d = FrameDecoder(); let frame = NativeMessageFraming.encode(Data("{\"a\":1}".utf8))
    #expect(try d.append(frame.prefix(3)).isEmpty)
    #expect(try d.append(frame.dropFirst(3)) == [Data("{\"a\":1}".utf8)])
}
@Test func decodesTwoFramesInOneChunk() throws {
    var d = FrameDecoder()
    let chunk = NativeMessageFraming.encode(Data("1".utf8)) + NativeMessageFraming.encode(Data("22".utf8))
    #expect(try d.append(chunk) == [Data("1".utf8), Data("22".utf8)])
}
@Test func rejectsOversizeFrame() {
    var d = FrameDecoder(); var n = UInt32(2_000_000).littleEndian
    #expect(throws: FramingError.frameTooLarge(2_000_000)) { try d.append(Data(bytes: &n, count: 4)) }
}
```

- [ ] **Step 3: Run** `swift test --filter FramingTests`. Expected: FAIL (compile error: `cannot find 'NativeMessageFraming'`).
- [ ] **Step 4: Implement** `Framing.swift` per the Interfaces.
- [ ] **Step 5: Run** `swift test --filter FramingTests`. Expected: 4 tests pass.
- [ ] **Step 6: Commit:** `git add Package.swift Sources Tests && git commit -m "feat: package skeleton and native-messaging framing"`

---

### Task 2: Message protocol

**Files:**
- Create: `Sources/LilBrowCore/Messages.swift`
- Test: `Tests/LilBrowCoreTests/MessagesTests.swift`

**Interfaces:**
- Produces:
  - `struct Bounds: Codable, Equatable, Sendable { var left, top, width, height: Int }`
  - `enum OutboundMessage: Equatable, Sendable`, with cases:
    - `open(requestId: String, url: URL, bounds: Bounds, focused: Bool)`
    - `move(windowId: Int)`
  - `enum InboundMessage: Equatable, Sendable`, with cases:
    - `hostHello(browserBundleID: String, browserPID: Int32)`
    - `hello(extensionVersion: String)`
    - `opened(requestId: String?, windowId: Int, url: URL, bounds: Bounds)`
    - `openFailed(requestId: String, error: String)`
    - `littleURL(windowId: Int, url: URL)`
    - `littleBounds(windowId: Int, bounds: Bounds)`
    - `littleClosed(windowId: Int)`
    - `copy(url: URL)`
  - `enum MessageCoding`, with:
    - `static func encode(_: OutboundMessage) throws -> Data`
    - `static func encode(_: InboundMessage) throws -> Data`
    - `static func decodeInbound(_: Data) throws -> InboundMessage`
    - `static func decodeOutbound(_: Data) throws -> OutboundMessage`
- Wire format: a JSON object with a `"type"` key equal to the case name. Field names are exactly the associated-value labels, and URLs are encoded as `absoluteString`. The encoder uses `[.sortedKeys, .withoutEscapingSlashes]`. An unknown `type` throws.

- [ ] **Step 1: Write the failing tests:**

```swift
let b = Bounds(left: 300, top: 137, width: 1000, height: 750)
@Test func encodesOpenExactly() throws {
    let data = try MessageCoding.encode(OutboundMessage.open(requestId: "r1", url: URL(string: "https://github.com/")!, bounds: b, focused: true))
    #expect(String(decoding: data, as: UTF8.self) == #"{"bounds":{"height":750,"left":300,"top":137,"width":1000},"focused":true,"requestId":"r1","type":"open","url":"https://github.com/"}"#)
}
@Test func encodesMoveExactly() throws {
    #expect(String(decoding: try MessageCoding.encode(OutboundMessage.move(windowId: 42)), as: UTF8.self) == #"{"type":"move","windowId":42}"#)
}
@Test func decodesOpenedWithoutRequestId() throws {
    let json = #"{"type":"opened","windowId":42,"url":"https://github.com/pulls","bounds":{"left":300,"top":137,"width":1000,"height":750}}"#
    #expect(try MessageCoding.decodeInbound(Data(json.utf8)) == .opened(requestId: nil, windowId: 42, url: URL(string: "https://github.com/pulls")!, bounds: b))
}
@Test func rejectsUnknownType() { #expect(throws: (any Error).self) { try MessageCoding.decodeInbound(Data(#"{"type":"bogus"}"#.utf8)) } }
@Test func realWorldURLSurvivesRoundTrip() throws {   // Review Focus 3
    let s = "https://docs.google.com/document/d/1AbC_xyz/edit?usp=sharing&q=caf%C3%A9%20au%20lait#heading=h.2x"
    let m = InboundMessage.littleURL(windowId: 7, url: URL(string: s)!)
    let back = try MessageCoding.decodeInbound(try MessageCoding.encode(m))
    guard case .littleURL(_, let url) = back else { Issue.record("wrong case"); return }
    #expect(url.absoluteString == s)
}
@Test func hostHelloRoundTrips() throws {
    let m = InboundMessage.hostHello(browserBundleID: "company.thebrowser.dia", browserPID: 1234)
    #expect(try MessageCoding.decodeInbound(try MessageCoding.encode(m)) == m)
}
```

- [ ] **Step 2: Run** `swift test --filter MessagesTests`. Expected: FAIL (compile error).
- [ ] **Step 3: Implement** `Messages.swift`. Hand-write `Codable` keyed on `"type"`.
- [ ] **Step 4: Run** `swift test --filter MessagesTests`. Expected: 6 pass.
- [ ] **Step 5: Commit:** `git commit -am "feat: bridge message protocol"` (after `git add` of new files).

---

### Task 3: Screen geometry, window matching, overlay visibility

**Files:**
- Create: `Sources/LilBrowCore/ScreenGeometry.swift`
- Test: `Tests/LilBrowCoreTests/ScreenGeometryTests.swift`

**Interfaces:**
- Consumes: `Bounds` (Task 2).
- Produces:
  - `struct ScreenContext: Equatable { var visibleFrame: CGRect /* AppKit, bottom-left origin */; var primaryScreenHeight: CGFloat }`
  - `enum ScreenGeometry`, with:
    - `static let screenMargin: CGFloat = 40`
    - `static let minimumSize = CGSize(width: 480, height: 360)`
    - `static func littleWindowBounds(size: CGSize, on screen: ScreenContext) -> Bounds`
      - Clamps the size to at least `minimumSize` and at most the visible frame minus 2×margin.
      - Centers it in the visible frame in AppKit coordinates.
      - Converts to top-left: `left = floor(x)`, `top = floor(primaryScreenHeight - (y + h))`.
    - `static func appKitRect(fromTopLeft r: CGRect, primaryScreenHeight h: CGFloat) -> CGRect`
    - `static func overlayFrame(windowTopLeft: CGRect, overlaySize: CGSize, titleBarHeight: CGFloat, rightInset: CGFloat) -> CGRect`
      - Returns top-left coordinates: `x = maxX - rightInset - w`, `y = minY + (titleBarHeight - h) / 2`.
  - `struct WindowCandidate<ID: Hashable>: Equatable { var id: ID; var frame: CGRect /* top-left */ }`
  - `func matchLittleWindow<ID: Hashable>(_ candidates: [WindowCandidate<ID>], bounds: Bounds, excluding: Set<ID>, tolerance: CGFloat = 6) -> ID?`
    - Considers only candidates whose four edges each differ by ≤ tolerance and that aren't excluded.
    - Returns the smallest total difference, with ties going to the first.
  - `enum OverlayVisibility { static func windowToShow<ID: Hashable>(frontmostPID: pid_t?, browserPID: pid_t?, focusedWindow: ID?, tracked: Set<ID>) -> ID? }`
    - Returns the focused window only when the frontmost app is the browser and the focused window is tracked.

- [ ] **Step 1: Write the failing tests:**

```swift
let primary = ScreenContext(visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 976), primaryScreenHeight: 1000)
@Test func centersOnPrimary() { #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: primary) == Bounds(left: 300, top: 137, width: 1000, height: 750)) }
@Test func centersOnSecondaryWithNegativeX() {   // Review Focus 2
    let s = ScreenContext(visibleFrame: CGRect(x: -1440, y: 100, width: 1440, height: 876), primaryScreenHeight: 1000)
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: s) == Bounds(left: -1220, top: 87, width: 1000, height: 750))
}
@Test func clampsOversize() { #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 3000, height: 2000), on: primary) == Bounds(left: 40, top: 64, width: 1520, height: 896)) }
@Test func enforcesMinimum() { #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 100, height: 100), on: primary) == Bounds(left: 560, top: 332, width: 480, height: 360)) }
@Test func floorsFractions() {
    let s = ScreenContext(visibleFrame: CGRect(x: 0, y: 0, width: 1601, height: 977), primaryScreenHeight: 1000)
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: s) == Bounds(left: 300, top: 136, width: 1000, height: 750))
}
@Test func convertsTopLeftToAppKit() { #expect(ScreenGeometry.appKitRect(fromTopLeft: CGRect(x: 300, y: 137, width: 1000, height: 750), primaryScreenHeight: 1000) == CGRect(x: 300, y: 113, width: 1000, height: 750)) }
@Test func overlaySitsRightOfTitleBar() { #expect(ScreenGeometry.overlayFrame(windowTopLeft: CGRect(x: 300, y: 137, width: 1000, height: 750), overlaySize: CGSize(width: 120, height: 20), titleBarHeight: 28, rightInset: 8) == CGRect(x: 1172, y: 141, width: 120, height: 20)) }
let target = Bounds(left: 300, top: 137, width: 1000, height: 750)
@Test func matchesWithinTolerance() { #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 303, y: 135, width: 997, height: 752))], bounds: target, excluding: []) == 1) }
@Test func rejectsOutsideTolerance() { #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 310, y: 137, width: 1000, height: 750))], bounds: target, excluding: []) == nil) }
@Test func skipsTrackedTwin() {   // Review Focus 5
    let f = CGRect(x: 300, y: 137, width: 1000, height: 750)
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: f), WindowCandidate(id: 2, frame: f)], bounds: target, excluding: [1]) == 2)
}
@Test func prefersClosest() { #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 304, y: 137, width: 1000, height: 750)), WindowCandidate(id: 2, frame: CGRect(x: 301, y: 137, width: 1000, height: 750))], bounds: target, excluding: []) == 2) }
@Test func overlayOnlyForFocusedTrackedWindowOfFrontmostBrowser() {
    #expect(OverlayVisibility.windowToShow(frontmostPID: 10, browserPID: 10, focusedWindow: 5, tracked: [5]) == 5)
    #expect(OverlayVisibility.windowToShow(frontmostPID: 11, browserPID: 10, focusedWindow: 5, tracked: [5]) == nil)
    #expect(OverlayVisibility.windowToShow(frontmostPID: 10, browserPID: 10, focusedWindow: 6, tracked: [5]) == nil)
}
```

- [ ] **Step 2: Run** `swift test --filter ScreenGeometryTests`. Expected: FAIL (compile error).
- [ ] **Step 3: Implement** `ScreenGeometry.swift` per the Interfaces.
- [ ] **Step 4: Run** `swift test --filter ScreenGeometryTests`. Expected: all pass.
- [ ] **Step 5: Commit:** `git commit -m "feat: little-window geometry and window matching"`

---

### Task 4: Browser adapters, extension identity, host manifest

**Files:**
- Create:
  - `Sources/LilBrowCore/BrowserAdapter.swift`
  - `Sources/LilBrowCore/ExtensionIdentity.swift`
  - `Sources/LilBrowCore/NativeHostManifest.swift`
  - `Extension/manifest.json` (identity fields only for now)
- Test: `Tests/LilBrowCoreTests/AdapterAndManifestTests.swift`

**Interfaces:**
- Produces:
  - `struct BrowserAdapter: Equatable, Sendable { let name: String; let bundleID: String; let nativeHostDirectories: [String] }`. Directories are relative to `~/Library/Application Support`.
    - `.dia` = `("Dia", "company.thebrowser.dia", ["Dia/NativeMessagingHosts", "Dia/User Data/NativeMessagingHosts"])`. Installing to both resolves the spec's open question about which folder Dia reads.
    - `.chrome` = `("Chrome", "com.google.Chrome", ["Google/Chrome/NativeMessagingHosts"])`
    - `static let all: [BrowserAdapter]`
    - `static func forBundleID(_: String) -> BrowserAdapter?`
  - `enum ExtensionIdentity { static let chromiumID: String; static let nativeHostName = "com.lilbrowwow.bridge" }`
  - `enum NativeHostManifest`, with:
    - `static func json(hostExecutablePath: String) throws -> Data`
      - Keys: `name`, `description` (`"Lil Brow Wow bridge"`), `path`, `type` (`"stdio"`), and `allowed_origins` (`["chrome-extension://<chromiumID>/"]`).
    - `static func install(hostExecutablePath: String, adapter: BrowserAdapter, applicationSupport: URL) throws -> [URL]`
      - Creates each directory and writes `com.lilbrowwow.bridge.json` into it.
      - Returns the paths written.
  - `enum DesktopAssignment { static func isAssigned(bundleID: String, appBindings: [String: Any]) -> Bool }`. Keys in `com.apple.spaces` `app-bindings` are lowercased bundle IDs.

- [ ] **Step 1: Generate the extension key** (the private key is not kept):

```bash
openssl genrsa -out "$TMPDIR/lbw.pem" 2048
openssl rsa -in "$TMPDIR/lbw.pem" -pubout -outform DER | base64 -b 0          # -> manifest "key"
openssl rsa -in "$TMPDIR/lbw.pem" -pubout -outform DER | shasum -a 256 | head -c 32 | tr '0-9a-f' 'a-p'   # -> chromiumID
rm "$TMPDIR/lbw.pem"
```

  Write `Extension/manifest.json` with `manifest_version: 3`, `name: "Lil Brow Wow"`, `version: "0.1.0"`, `description`, and `key`. Put the ID in `ExtensionIdentity.chromiumID`.

- [ ] **Step 2: Write the failing tests:**
  - `chromiumIDMatchesManifestKey`: read `Extension/manifest.json` through `#filePath` (three levels up). Base64-decode `key`, take its SHA-256 (CryptoKit), map the first 32 hex characters with `0-9a-f` → `a-p`, and expect the result to equal `ExtensionIdentity.chromiumID`.
  - `manifestJSONHasRequiredFields`: decode `json(hostExecutablePath: "/x/lilbrow-host")` and expect:
    - `name == "com.lilbrowwow.bridge"`
    - `path == "/x/lilbrow-host"`
    - `type == "stdio"`
    - `allowed_origins == ["chrome-extension://\(ExtensionIdentity.chromiumID)/"]`
  - `installWritesBothDiaLocations`: install into a temp directory and expect both `Dia/NativeMessagingHosts/com.lilbrowwow.bridge.json` and `Dia/User Data/NativeMessagingHosts/com.lilbrowwow.bridge.json` to exist.
  - `detectsDesktopAssignment`: `isAssigned(bundleID: "company.thebrowser.dia", appBindings: ["company.thebrowser.dia": "SPACE-UUID"]) == true`; an empty dictionary gives `false`.
  - `adapterLookup`: `BrowserAdapter.forBundleID("com.google.Chrome") == .chrome`.
- [ ] **Step 3: Run** `swift test --filter AdapterAndManifestTests`. Expected: FAIL.
- [ ] **Step 4: Implement** the three files.
- [ ] **Step 5: Run** `swift test --filter AdapterAndManifestTests`. Expected: pass.
- [ ] **Step 6: Commit:** `git commit -m "feat: browser adapters, pinned extension ID, host manifest"`

---

### Task 5: Unix socket helpers, host relay, `lilbrow-host`

**Files:**
- Create: `Sources/LilBrowCore/UnixSocket.swift`, `Sources/LilBrowCore/HostRelay.swift`
- Modify: `Sources/lilbrow-host/main.swift`
- Test: `Tests/LilBrowCoreTests/HostRelayTests.swift`

**Interfaces:**
- Consumes: `NativeMessageFraming`, `FrameDecoder`, `MessageCoding`, `InboundMessage.hostHello`.
- Produces:
  - `enum UnixSocket`, with:
    - `static func listen(path: String) throws -> Int32`, which unlinks any stale path first and uses backlog 8
    - `static func connect(path: String) throws -> Int32`
    - `static func accept(_ fd: Int32) throws -> Int32`
  - `enum UnixSocketError: Error { case pathTooLong, sys(Int32) }`
  - `final class HostRelay { init(input: FileHandle, output: FileHandle, socketPath: String, hello: InboundMessage, retryInterval: TimeInterval = 1.0); func run() }`. `run()` blocks until input reaches EOF.
- Behavior:
  - Connects, retrying every `retryInterval`. On each connect it first writes the framed `hello`.
  - Relays whole frames verbatim: input → socket and socket → output.
  - Input frames that arrive while disconnected are dropped.
  - Socket EOF triggers a reconnect. Input EOF closes the socket and returns.

- [ ] **Step 1: Write the failing tests.** Each uses `Pipe()`s for input and output, and a test listener at `NSTemporaryDirectory() + "lbw-<8 chars>.sock"`. The relay runs on a background thread.
  - `sendsHostHelloFirst`: the first frame read from the accepted socket equals `MessageCoding.encode(.hostHello(browserBundleID: "test.browser", browserPID: 1))`.
  - `relaysInputFramesToSocket`: write framed `{"type":"hello","extensionVersion":"0.1.0"}` to input, and the socket receives those identical bytes.
  - `relaysSocketFramesToOutput`: the socket writes a framed `move` message, and the output pipe yields the identical frame.
  - `reconnectsAfterServerDrops`: close the accepted fd. A new connection is accepted within 2 s (`retryInterval: 0.1`) and starts with `hostHello` again.
  - `returnsOnInputEOF`: close input's write end, and `run()` returns within 1 s.
- [ ] **Step 2: Run** `swift test --filter HostRelayTests`. Expected: FAIL.
- [ ] **Step 3: Implement** `UnixSocket` with POSIX calls, and `HostRelay` with two pump threads.
- [ ] **Step 4: Implement `lilbrow-host/main.swift`.**
  - Socket path: `ProcessInfo.environment["LILBROW_SOCKET"]` if set, otherwise the Global Constraints path.
  - Browser identity: walk the parent-process chain (`getppid()`, then `sysctl` `KERN_PROC_PID` for ancestors, up to 5 levels) to the first `NSRunningApplication(processIdentifier:)?.bundleIdentifier`, falling back to `"unknown"`. Send it as `hostHello(browserBundleID:browserPID:)`.
  - Run `HostRelay(input: .standardInput, output: .standardOutput, …)`.
  - Log to stderr only. stdout is the protocol channel.
- [ ] **Step 5: Run** `swift test --filter HostRelayTests && swift build --product lilbrow-host`. Expected: tests pass and the build succeeds.
- [ ] **Step 6: Commit:** `git commit -m "feat: native-messaging host relay"`

---

### Task 6: Bridge server and request/ack link

**Files:**
- Create: `Sources/LilBrowCore/BridgeServer.swift`, `Sources/LilBrowCore/BridgeExtensionLink.swift`
- Test: `Tests/LilBrowCoreTests/BridgeTests.swift`, with a small test client helper that frames and unframes over `UnixSocket.connect`.

**Interfaces:**
- Consumes: `UnixSocket`, `FrameDecoder`, `MessageCoding`, `OutboundMessage`, `InboundMessage`.
- Produces:
  - `protocol BridgeServerDelegate: AnyObject`, with:
    - `func bridge(_ s: BridgeServer, didReceive m: InboundMessage, fromBrowser bundleID: String)`
    - `func bridgeConnectionsChanged(_ s: BridgeServer)`
  - `final class BridgeServer`, with:
    - `init(socketPath: String, queue: DispatchQueue = .main)`
    - `weak var delegate`
    - `start() throws`, `stop()`
    - `isReady(browser: String) -> Bool`
    - `browserPID(for: String) -> pid_t?`
    - `send(_: OutboundMessage, to: String) -> Bool`
    - A connection becomes **ready** once it has received `hostHello` and then `hello`. `send` targets the most recently readied live connection for that bundle ID. `hostHello` is consumed and not forwarded; every other message is forwarded to the delegate on `queue`. Frames that fail to decode are logged and skipped, and the connection stays open.
  - `protocol ExtensionLink: AnyObject`, with:
    - `func isReady(browser: String) -> Bool`
    - `func waitUntilReady(browser: String, timeout: Duration) async -> Bool`
    - `func open(_ r: OpenRequest, browser: String, timeout: Duration) async -> OpenResult`
  - `struct OpenRequest: Equatable { var requestId: String; var url: URL; var bounds: Bounds; var focused: Bool }`
  - `enum OpenResult: Equatable { case opened(windowId: Int), failed(String), timedOut }`
  - `@MainActor final class BridgeExtensionLink: ExtensionLink, BridgeServerDelegate`, with:
    - `init(server: BridgeServer)`, which sets itself as the delegate
    - `var onEvent: ((InboundMessage, String) -> Void)?`, called for every forwarded message after pending requests are resolved
    - `var onConnectionsChanged: (() -> Void)?`

- [ ] **Step 1: Write the failing tests.**
  - `becomesReadyAfterHostHelloAndHello`: not ready after `hostHello` alone, ready after `hello`, and `browserPID(for:) == 99`.
  - `sendsToMostRecentReadyConnection`: two clients for the same bundle ID; only the second receives `move(windowId: 42)`.
  - `notReadyAfterClientDisconnects` (Review Focus 4): the client closes, `isReady` becomes false, and `bridgeConnectionsChanged` fires.
  - `skipsUndecodableFrames`: after sending `{"type":"bogus"}`, a following `littleClosed` is still delivered.
  - `openResolvesOnMatchingAck`: the client replies `opened(requestId: "r1", windowId: 42, …)` and `open` returns `.opened(windowId: 42)`.
  - `openTimesOut`: with no reply and a 200 ms timeout, it returns `.timedOut`.
  - `openFailedIsReported`: an `openFailed` reply returns `.failed("boom")`.
  - `waitUntilReadyReturnsTrueWhenClientArrivesMidWait` (Review Focus 1): the client connects 300 ms into a 2 s wait, and the wait returns true.
- [ ] **Step 2: Run** `swift test --filter BridgeTests`. Expected: FAIL.
- [ ] **Step 3: Implement** both files. Use `DispatchSource` read sources per fd on a private queue and hop to `queue` for state and callbacks. Pending opens are `[requestId: CheckedContinuation]` with a timeout task.
- [ ] **Step 4: Run** `swift test --filter BridgeTests`. Expected: pass.
- [ ] **Step 5: Commit:** `git commit -m "feat: bridge server and extension link"`

---

### Task 7: Settings, registry, link router

**Files:**
- Create: `Sources/LilBrowCore/Settings.swift`, `Sources/LilBrowCore/LittleWindowRegistry.swift`, `Sources/LilBrowCore/LinkRouter.swift`
- Test: `Tests/LilBrowCoreTests/RouterTests.swift`, `Tests/LilBrowCoreTests/RegistryAndSettingsTests.swift`

**Interfaces:**
- Consumes: `ExtensionLink`, `OpenRequest`, `OpenResult`, `ScreenContext`, `ScreenGeometry`, `BrowserAdapter`, `InboundMessage`, `Bounds`.
- Produces:
  - `enum FocusStrategy: String, Sendable { case focusOnCreate, createThenRaise }`
  - `protocol LittleSettings: AnyObject { var isEnabled: Bool { get }; var littleWindowSize: CGSize { get }; var browser: BrowserAdapter { get }; var focusStrategy: FocusStrategy { get } }`
  - `final class UserDefaultsSettings: LittleSettings`
    - `init(defaults: UserDefaults = .standard)`
    - Settable `isEnabled` and `focusStrategy`, plus `func rememberSize(_ b: Bounds)`
    - Keys and defaults:
      - `enabled` → true
      - `littleWindowWidth` / `littleWindowHeight` → 1000 / 750
      - `browserBundleID` → adapter chosen in Task 0
      - `focusStrategy` → strategy chosen in Task 0
  - `struct LittleWindowInfo: Equatable { var windowId: Int; var browserBundleID: String; var url: URL; var bounds: Bounds }`
  - `final class LittleWindowRegistry`
    - `func apply(_ m: InboundMessage, from bundleID: String)`, which handles `opened`, `littleURL`, `littleBounds` and `littleClosed` and ignores everything else
    - `func info(for windowId: Int) -> LittleWindowInfo?`
  - `protocol BrowserControl: AnyObject { func isRunning(bundleID: String) -> Bool; func launchInBackground(bundleID: String) async -> Bool; func openNormally(_ url: URL, bundleID: String) }`
  - `struct RouterTimeouts { var launchToReady: Duration = .seconds(10); var runningToReady: Duration = .seconds(2); var openAck: Duration = .seconds(4) }`
  - `enum FallbackReason: Equatable { case disabled, notWebURL, launchFailed, notReady, openFailed, timedOut }`
  - `enum RouteOutcome: Equatable { case little(windowId: Int), openedNormally(FallbackReason) }`
  - `@MainActor final class LinkRouter`
    - `init(settings: LittleSettings, link: ExtensionLink, browser: BrowserControl, screen: @escaping () -> ScreenContext, timeouts: RouterTimeouts = .init(), makeRequestID: @escaping () -> String = { UUID().uuidString })`
    - `func route(_ url: URL) async -> RouteOutcome`
- Routing rules, in order:
  1. Disabled → `openNormally` (`.disabled`).
  2. Scheme not http/https → `openNormally` (`.notWebURL`).
  3. Browser not running → `launchInBackground`. If that fails, fall back (`.launchFailed`). Otherwise wait up to `launchToReady`; if it never becomes ready, fall back (`.notReady`).
  4. Running but not ready → wait up to `runningToReady`; if still not ready, fall back (`.notReady`).
  5. Send `OpenRequest`:
     - `bounds = ScreenGeometry.littleWindowBounds(size: settings.littleWindowSize, on: screen())`
     - `focused = (settings.focusStrategy == .focusOnCreate)`
  6. Result: `.opened(id)` → `.little(id)`; `.failed` → fall back (`.openFailed`); `.timedOut` → fall back (`.timedOut`).

  Every fallback calls `browser.openNormally(url, bundleID: settings.browser.bundleID)` exactly once.

- [ ] **Step 1: Write the failing tests** with `FakeLink`, `FakeBrowser` (records calls) and `FakeSettings`, using timeouts of 50–200 ms.
  - `disabledOpensNormally`: `.openedNormally(.disabled)`, and `link.openCalls` is empty.
  - `fileURLOpensNormally`: `.notWebURL`.
  - `readyBrowserOpensLittle`: `.little(windowId: 42)`. The recorded request has `bounds == Bounds(left: 300, top: 137, width: 1000, height: 750)` (using the primary `ScreenContext` from Task 3) and `focused == true`.
  - `createThenRaiseSendsUnfocused`: `focused == false`.
  - `notRunningLaunchesThenOpens`: `launchInBackground` is called once, and the result is `.little`.
  - `launchFailureFallsBack`: `.launchFailed`, and `openNormally` is called once.
  - `neverReadyFallsBack`: `.notReady`.
  - `runningNotReadyBecomesReadyDuringWait` (Review Focus 1): `.little`.
  - `ackTimeoutFallsBack`: `.timedOut`, and `openNormally` is called once.
  - `openFailedFallsBack`: `.openFailed`.
  - `registryTracksURLChanges`: after `opened`, `info(for: 42)?.url` is the opened URL. After `littleURL`, it is the new URL. After `littleClosed`, it is nil.
  - `settingsDefaultsAndRememberSize`: on a fresh suite, `littleWindowSize == CGSize(width: 1000, height: 750)` and `isEnabled == true`. After `rememberSize(Bounds(left: 0, top: 0, width: 900, height: 700))`, the size is 900×700.
- [ ] **Step 2: Run** `swift test --filter "RouterTests|RegistryAndSettingsTests"`. Expected: FAIL.
- [ ] **Step 3: Implement** the three files.
- [ ] **Step 4: Run** the same filter. Expected: pass.
- [ ] **Step 5: Commit:** `git commit -m "feat: settings, little-window registry, link router"`

---

### Task 8: Extension core (bridge, open, move, events)

**Files:**
- Modify: `Extension/manifest.json`
- Create: `Extension/background.js`, `Extension/bridge-logic.js`, `Extension/test/bridge-logic.test.mjs`

**Interfaces:**
- Consumes: the wire format from Task 2, and the host name `com.lilbrowwow.bridge`.
- Produces (`bridge-logic.js`, ES module):
  - `popupCreateOptions({url, bounds, focused})` → `{type: "popup", url, left, top, width, height, focused}`
  - `pickMainWindowId(normalWindows, lastNormalId)`. Returns `lastNormalId` if it is in the list, otherwise the first `focused` window, otherwise the first window, otherwise `null`.
  - `cascadeBounds(bounds, offset = 30)` → `{left: left + 30, top: top + 30, width, height}`
  - `windowBounds(w)` → `{left: w.left, top: w.top, width: w.width, height: w.height}`
- `chrome.storage.session` keys:
  - `littleWindows`: `{[windowId]: tabId}`
  - `lastNormalWindowId`: number

- [ ] **Step 1: Write the failing tests** (`node:test`, `assert/strict`):
  - `popupCreateOptions` maps fields exactly.
  - `pickMainWindowId([{id: 1}, {id: 2, focused: true}], 1) === 1`
  - `pickMainWindowId([{id: 1}, {id: 2, focused: true}], 9) === 2`
  - `pickMainWindowId([], 1) === null`
  - `cascadeBounds({left: 300, top: 137, width: 1000, height: 750})` deep-equals `{left: 330, top: 167, width: 1000, height: 750}`.
- [ ] **Step 2: Run** `node --test Extension/test/`. Expected: FAIL (module not found).
- [ ] **Step 3: Implement** `bridge-logic.js`.
- [ ] **Step 4: Update `manifest.json`** with:
  - `permissions: ["nativeMessaging", "tabs", "webNavigation", "storage", "alarms"]`
  - `host_permissions: ["<all_urls>"]`
  - `background: {service_worker: "background.js", type: "module"}`
- [ ] **Step 5: Implement `background.js`:**
  - `connect()` calls `chrome.runtime.connectNative("com.lilbrowwow.bridge")` and posts `{type: "hello", extensionVersion: chrome.runtime.getManifest().version}`.
    - It is called at top level, and from `runtime.onStartup`, `runtime.onInstalled`, and a 1-minute `alarms` alarm named `reconnect` (only when not connected).
    - On `onDisconnect`, it logs `chrome.runtime.lastError` and clears the port.
  - **`open`:**
    1. Call `chrome.windows.create(popupCreateOptions(msg))`.
    2. Record `littleWindows[win.id] = win.tabs[0].id`.
    3. Post `{type: "opened", requestId, windowId, url, bounds: windowBounds(win)}`.
    4. On error, post `{type: "openFailed", requestId, error: String(e)}`.
  - **`move`:**
    1. Read the URL from the little window's tab.
    2. Pick the main window with `pickMainWindowId(await chrome.windows.getAll({windowTypes: ["normal"]}), lastNormalWindowId)`.
    3. If there is one: `tabs.create({windowId, url, active: true})`, then `windows.update(windowId, {focused: true})`. Otherwise: `windows.create({type: "normal", url, focused: true})`.
    4. `windows.remove(littleId)`.
  - **Events for little windows only:**
    - `tabs.onUpdated` with `changeInfo.url` → `littleURL`
    - `windows.onBoundsChanged` → `littleBounds`
    - `windows.onRemoved` → `littleClosed`, and delete the entry
  - `windows.onFocusChanged`: when the focused window's type is `normal`, store `lastNormalWindowId`.
- [ ] **Step 6: Run** `node --test Extension/test/`. Expected: pass.
- [ ] **Step 7: Manual smoke test.** Load `Extension/` unpacked in the chosen browser. Its service-worker console shows `Specified native messaging host not found` (expected until Task 9) and no other errors.
- [ ] **Step 8: Commit:** `git commit -m "feat: extension bridge, open and move"`

---

### Task 9: App shell, default browser, status menu, end-to-end open

**Files:**
- Create:
  - `Resources/Info.plist`
  - `scripts/build-app.sh`
  - `Sources/LilBrowWow/AppDelegate.swift`
  - `Sources/LilBrowWow/BrowserControlImpl.swift`
  - `Sources/LilBrowWow/SystemIntegration.swift`
  - `Sources/LilBrowWow/StatusMenu.swift`
- Modify: `Sources/LilBrowWow/main.swift`

**Interfaces:**
- Consumes: `BridgeServer`, `BridgeExtensionLink`, `LinkRouter`, `UserDefaultsSettings`, `LittleWindowRegistry`, `NativeHostManifest`, `BrowserAdapter`, `DesktopAssignment`, `BrowserControl`.
- Produces:
  - `final class BrowserControlImpl: BrowserControl`. It uses `NSWorkspace.openApplication(at:configuration:)` with `activates = false` for background launch, and `NSWorkspace.open([url], withApplicationAt:configuration:)` for `openNormally`.
  - `enum SystemIntegration`, with:
    - `isDefaultBrowser() -> Bool`, which compares the bundle ID of `urlForApplication(toOpen: https://example.com)`
    - `makeDefaultBrowser() async`, which calls `setDefaultApplication(at:toOpenURLsWithScheme:)` for `http` and `https`
    - `isAccessibilityTrusted(prompt: Bool) -> Bool`
    - `launchAtLogin: Bool` (get/set through `SMAppService.mainApp`)
    - `isBrowserAssignedToDesktop(_ bundleID: String) -> Bool`, which reads `CFPreferencesCopyAppValue("app-bindings", "com.apple.spaces")` and passes it to `DesktopAssignment`
- Info.plist:
  - `CFBundleIdentifier`, `CFBundleName` = `Lil Brow Wow`, `CFBundleExecutable` = `LilBrowWow`
  - `CFBundleShortVersionString` 0.1.0, `CFBundleVersion` 1
  - `LSUIElement` true, `LSMinimumSystemVersion` 14.0
  - `CFBundleURLTypes`: one entry, schemes `http` and `https`
  - `CFBundleDocumentTypes`: `public.html` and `public.xhtml`, role `Viewer`, `LSHandlerRank` `Default`
- Menu (exact titles; `<B>` = adapter name):
  - `Open Links in Little Windows` (checkmark)
  - separator
  - `<B> Extension: Connected` / `<B> Extension: Not Connected` (disabled item)
  - `Accessibility: Granted` / `Grant Accessibility Access…`
  - `Default Browser: Lil Brow Wow` / `Make Lil Brow Wow the Default Browser…`
  - only when the browser is assigned to a desktop: `⚠︎ <B> is assigned to one desktop — set Dock › Options › Assign To › None`
  - `Launch at Login` (checkmark)
  - separator
  - `Quit Lil Brow Wow` (⌘Q)
  - Status icon: SF Symbol `macwindow.on.rectangle`, template image. The menu refreshes in `menuWillOpen`.

- [ ] **Step 1: Write `build-app.sh`.**
  1. `swift build -c release` for both products.
  2. Assemble `build/LilBrowWow.app`: binary in `Contents/MacOS/`, helper in `Contents/Helpers/`, plus `Contents/Info.plist`.
  3. `codesign --force --sign "${LILBROW_SIGN_IDENTITY:--}"` the helper, then the app.
  4. With `--install`:
     - `pkill -x LilBrowWow || true`
     - replace `~/Applications/LilBrowWow.app`
     - `lsregister -f` it, using `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`
     - `open` it

  Note in the script header: with ad-hoc signing (`-`), Accessibility must be re-granted after every rebuild. Setting `LILBROW_SIGN_IDENTITY` to a stable self-signed identity avoids that. A stable self-signed identity is enough.
- [ ] **Step 2: Implement `AppDelegate`.** Build everything in `applicationWillFinishLaunching`, so URLs delivered at launch are handled:
  - settings
  - `BridgeServer` at the socket path (create the folder first) → `start()`
  - `BridgeExtensionLink`, with two handlers:
    - `link.onEvent`: `registry.apply(message, from: bundleID)`, plus `settings.rememberSize(bounds)` on `littleBounds`, then log.
    - `link.onConnectionsChanged`: refresh the menu.
  - `LittleWindowRegistry`
  - `LinkRouter`. `screen` = the `NSScreen` containing `NSEvent.mouseLocation` (falling back to `NSScreen.main`) plus `NSScreen.screens[0].frame.height`.
  - `NativeHostManifest.install` for every adapter whose app is installed (`NSWorkspace.urlForApplication(withBundleIdentifier:)`), with `hostExecutablePath = Bundle.main.bundleURL/Contents/Helpers/lilbrow-host`
  - the status menu

  `application(_:open urls:)` runs one `Task { for url in urls { let outcome = await router.route(url); log(outcome) } }`. Log through `Logger(subsystem: "com.lilbrowwow", category: "router")`.
- [ ] **Step 3: Implement** `BrowserControlImpl`, `SystemIntegration` and `StatusMenu` per the Interfaces.
- [ ] **Step 4: Run** `swift test && scripts/build-app.sh --install` (sandbox disabled). Expected: all tests pass, and the app appears in the menu bar.
- [ ] **Step 5: End-to-end check with the owner.** Watch `log stream --predicate 'subsystem == "com.lilbrowwow"'` in parallel.
  1. Choose `Make Lil Brow Wow the Default Browser…` and confirm the macOS dialog.
  2. Reload the extension in the browser. The menu now shows `Extension: Connected`.
  3. Browser on desktop 1, owner on desktop 2: click a GitHub link in Slack. Expected: a signed-in little window on desktop 2 with no switch (spec checklist 1). If this fails here but passed in Task 0, stop and debug before going on.
  4. Disable the extension, then click a link. Expected: it opens normally in the browser (checklist 7).
  5. Turn the toggle off, then click a link. Expected: it opens normally (checklist 8).
  6. Quit the browser, then click a link. Expected: the browser launches and a little window appears (checklist 6).
  7. Click a `mailto:` link. Expected: Mail opens and nothing reaches the app (checklist 9).
- [ ] **Step 6: Commit:** `git commit -m "feat: menu-bar app, default browser, end-to-end little windows"`

---

### Task 10: New-tab links stay little, and keyboard shortcuts

**Files:**
- Create: `Extension/click-rules.js` (classic script), `Extension/content.js`, `Extension/test/click-rules.test.cjs`
- Modify: `Extension/manifest.json`, `Extension/background.js`

**Interfaces:**
- Consumes: `cascadeBounds`, `popupCreateOptions` and `windowBounds` (Task 8); the `opened` and `copy` wire messages (Task 2).
- Produces:
  - `globalThis.LilBrowClickRules.classifyClick(evt, anchor)` → `"little"` or `"default"`
    - `evt = {button, metaKey, ctrlKey, shiftKey, altKey}`
    - `anchor = {href, target, hasDownload}`, where `href` is already absolute
    - Returns `"little"` only when **all** of these hold:
      - the protocol is `http:` or `https:`
      - there is no download attribute
      - Alt is not held
      - and **any** of: `button === 1`, `metaKey`, `shiftKey`, or (`button === 0` and `target.toLowerCase() === "_blank"`)
  - Content-script messages: `{type: "isLittle"}` → boolean, and `{type: "openLittle", url}`.
  - Extension-initiated little windows post `opened` with **no** `requestId`, so the app tracks them like the others.

- [ ] **Step 1: Write the failing tests** (`click-rules.test.cjs` requires `../click-rules.js`, then reads `globalThis.LilBrowClickRules`). Base anchor is `{href: "https://x.com/a", target: "", hasDownload: false}` unless stated.

  | evt | anchor | expected |
  |---|---|---|
  | `{button:0}` | base | `default` |
  | `{button:0}` | `target:"_blank"` | `little` |
  | `{button:0}` | `target:"_BLANK"` | `little` |
  | `{button:0, metaKey:true}` | base | `little` |
  | `{button:1}` | base | `little` |
  | `{button:0, shiftKey:true}` | base | `little` |
  | `{button:0}` | `target:"_blank"`, `href:"mailto:a@b.c"` | `default` |
  | `{button:0}` | `target:"_blank"`, `hasDownload:true` | `default` |
  | `{button:0, altKey:true}` | `target:"_blank"` | `default` |
  | `{button:0}` | `target:"results-frame"` | `default` |

- [ ] **Step 2: Run** `node --test Extension/test/`. Expected: the new tests fail.
- [ ] **Step 3: Implement `click-rules.js`.**
- [ ] **Step 4: Implement `content.js`** (runs after `click-rules.js`).
  - At `document_start` it sends `isLittle`.
  - If true, it adds capture-phase `click` and `auxclick` listeners on `window`. The handler finds `event.target.closest("a[href]")` and classifies it.
  - On `"little"`: `preventDefault()`, `stopImmediatePropagation()`, then send `openLittle`.
- [ ] **Step 5: Update `manifest.json`.**
  - `content_scripts`: `{matches: ["<all_urls>"], js: ["click-rules.js", "content.js"], run_at: "document_start"}`
  - `commands`:
    - `copy-url` (`suggested_key.mac: "Command+Shift+C"`, description `Copy page URL`)
    - `move-to-main` (`suggested_key.mac: "Alt+Command+O"`, description `Move little window to main window`)
- [ ] **Step 6: Extend `background.js`.**
  - **`isLittle`:** respond with whether `sender.tab.windowId` is in `littleWindows`.
  - **`openLittle`:**
    1. Get the source window.
    2. Create a popup with `cascadeBounds(windowBounds(src))` and `focused: true`.
    3. Record it.
    4. Post `opened` with no `requestId`.
  - **`webNavigation.onCreatedNavigationTarget`:** applies when `sourceTabId` belongs to a little window **and** the new tab's window type is `normal`.
    1. `tabs.remove(tabId)`.
    2. Open a little window for `details.url`, cascaded from the source.
  - **Commands:**
    - `copy-url` posts `{type: "copy", url}` for the active tab of the last-focused window.
    - `move-to-main` runs the existing move logic when the focused window is a little window; otherwise it does nothing.
- [ ] **Step 7: Run** `node --test Extension/test/`. Expected: all pass.
- [ ] **Step 8: Manual check with the owner.**
  1. In a little window, ⌘-click a link and click a `target=_blank` link. Each gives a second little window on the same desktop with no flash (spec checklist 5).
  2. Use "Sign in with Google" on some site. The OAuth popup still works.
  3. Both shortcuts fire in little windows. In a normal window, Dia's own shortcuts still work.
  4. If a suggested key conflicts with Dia, switch to `Alt+Shift+C` / `Alt+Shift+O` and note it.
- [ ] **Step 9: Commit:** `git commit -m "feat: new-tab links open little; copy/move shortcuts"`

---

### Task 11: Title-bar buttons (Accessibility tracking and overlay), GATE on feel

**Files:**
- Create: `Sources/LilBrowWow/LittleWindowTracker.swift`, `Sources/LilBrowWow/TitleBarOverlay.swift`
- Modify: `Sources/LilBrowWow/AppDelegate.swift`

**Interfaces:**
- Consumes:
  - `matchLittleWindow`, `WindowCandidate`, `OverlayVisibility.windowToShow` and `ScreenGeometry.overlayFrame`/`appKitRect` (Task 3)
  - `BridgeServer.browserPID(for:)` and `send(.move)` (Task 6)
  - `LittleWindowRegistry.info(for:)` (Task 7)
  - `SystemIntegration.isAccessibilityTrusted` (Task 9)
- Produces:
  - `@MainActor final class LittleWindowTracker`, with:
    - `init(onChange: @escaping (TrackedWindow?) -> Void)`, which reports the window the overlay should sit on, or nil
    - `func track(windowId: Int, bounds: Bounds, browserPID: pid_t) async -> Bool`. It polls the browser's `kAXWindowsAttribute` every 100 ms for up to 2 s and matches on AX position and size, which are already top-left.
    - `func raise(windowId: Int) async`. It waits until the window is tracked, then calls `AXRaise` and `NSRunningApplication.activate()`.
    - `func untrack(windowId: Int)`
  - `struct TrackedWindow: Equatable { var windowId: Int; var frameTopLeft: CGRect }`
  - `@MainActor final class TitleBarOverlay`, with:
    - `init(browserName: String, onCopy: @escaping (Int) -> Void, onMove: @escaping (Int) -> Void)`
    - `func show(_ w: TrackedWindow, primaryScreenHeight: CGFloat)`
    - `func hide()`
    - `func flashCopied()`, which changes the Copy title to `Copied` for 1.2 s
- Constants (in `TitleBarOverlay`): `titleBarHeight = 28`, `rightInset = 8`, overlay height 20. Tune `titleBarHeight` against the real Dia popup.
- Tracker observes:
  - per window: `kAXMovedNotification`, `kAXResizedNotification`, `kAXUIElementDestroyedNotification`
  - on the browser app element: `kAXFocusedWindowChangedNotification`
  - `NSWorkspace` `didActivateApplication`, `activeSpaceDidChange`, and `didTerminateApplication` (browser quits → untrack all)

  After each event it recomputes `OverlayVisibility.windowToShow` and calls `onChange`. The AX observer's run-loop source goes on the main run loop.
- Overlay panel:
  - `NSPanel`, `[.borderless, .nonactivatingPanel]`
  - `level .floating`
  - `collectionBehavior [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]`
  - clear background, no shadow, `hidesOnDeactivate = false`
  - two small `NSButton`s per Global Constraints, sized to fit

- [ ] **Step 1: Implement `LittleWindowTracker`.**
- [ ] **Step 2: Implement `TitleBarOverlay`.**
- [ ] **Step 3: Wire them in `AppDelegate`.**
  - On every `opened` event: `tracker.track(windowId:bounds:browserPID:)`.
  - After `router.route` returns `.little(id)` with `focusStrategy == .createThenRaise`: `tracker.raise(windowId: id)`.
  - `onChange` → `overlay.show` / `hide`.
  - `onCopy(id)` → write `registry.info(for: id)?.url` to `NSPasteboard.general`, then `flashCopied()`.
  - `onMove(id)` → `server.send(.move(windowId: id), to: browser)`, then `tracker.untrack`.
  - Inbound `copy(url)` (keyboard command) → pasteboard, plus `flashCopied()` if the overlay is visible.
  - If Accessibility isn't trusted, little windows still open with no buttons. The menu item from Task 9 prompts for access.
- [ ] **Step 4: Run** `swift test && LILBROW_SIGN_IDENTITY="<stable identity>" scripts/build-app.sh --install`. Then grant Accessibility.
- [ ] **Step 5: Manual check with the owner** (spec checklist 2–4):
  1. The buttons sit on the right of the title bar.
  2. They follow the window when it's dragged or resized.
  3. They hide when another app is in front, and when the desktop changes.
  4. Copy puts the current URL on the clipboard after navigating inside the window.
  5. Move to Dia opens a tab in the main window, closes the little window, and lands on desktop 1.
  6. Two links clicked quickly each get their own buttons.
- [ ] **Step 6: GATE.** Ask the owner whether the buttons feel right. If tracking lags badly enough to bother them, stop and offer the in-page pill they saw earlier (their decision).
- [ ] **Step 7: Commit:** `git commit -m "feat: title-bar Copy and Move buttons"`

---

### Task 12: README and full checklist

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write `README.md`.**
  - What it is, and why.
  - Setup:
    1. Build and install (`scripts/build-app.sh --install`, and the signing identity note).
    2. Make it the default browser.
    3. Load `Extension/` unpacked (Developer mode).
    4. Grant Accessibility.
    5. Make sure the browser isn't assigned to a desktop.
  - Shortcuts.
  - Known limitations:
    - Full-screen apps.
    - Move reloads the page.
    - Little windows use the profile that has the extension; the menu shows connection status only, because extensions can't read Dia's profile name.
    - No buttons or shortcuts on browser-internal pages.
    - Dia may ship its own "Little Browser".
  - Troubleshooting: `log stream --predicate 'subsystem == "com.lilbrowwow"'`, and the extension's service-worker console.
- [ ] **Step 2: Run the spec's full manual checklist (items 1–9) with the owner.** Record PASS/FAIL per item in the commit message body.
- [ ] **Step 3: Commit:** `git commit -m "docs: README and v1 checklist results"`
