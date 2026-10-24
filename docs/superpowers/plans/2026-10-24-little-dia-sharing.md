# Little Dia Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename Lil Brow Wow to Little Dia and make it installable, self-updating and robust enough to hand to a few coworkers, then publish it publicly on GitHub.

**Architecture:** The v1 shape stays: a menu-bar app registered as the default browser, a Dia MV3 extension, and a native-messaging helper relaying over a Unix socket. This milestone adds:
- in the core library: setup-status, peer-check, extension-installer, release/version and diagnostics logic, all unit-tested
- in the app: a setup window, a rewritten menu, an updater and Copy Diagnostics
- shell scripts for one-command install and releases

**Tech Stack:**
- Swift 6 toolchain (SwiftPM tools 6.0, language mode v5), macOS 14+, AppKit and SwiftUI (setup window only), Swift Testing
- Security.framework: SecCode / SecStaticCode
- OSLogStore
- Plain-JS MV3 extension tested with `node --test`
- bash, `gh`

**Spec:** `docs/superpowers/specs/2026-10-24-little-dia-sharing-design.md` (the v1 spec it builds on: `docs/superpowers/specs/2026-10-23-lil-brow-wow-design.md`)

## Global Constraints

**Names and identifiers (spec §1)**
- Display name `Little Dia`. App bundle `Little Dia.app`.
- Bundle ID `com.austindick.littledia`. Helper code-signing identifier `com.austindick.littledia.host`.
- Native host name `com.austindick.littledia.bridge`.
- Support folder `~/Library/Application Support/Little Dia/`. Log subsystem `com.austindick.littledia`.
- SwiftPM targets `LittleDiaCore`, `LittleDia`, `littledia-host`; test target `LittleDiaCoreTests`.
- JS global `LittleDiaClickRules`. Env vars `LITTLEDIA_SIGN_IDENTITY`, `LITTLEDIA_SOCKET`.
- Extension ID stays `ofecdibidhgnemdblacfbinlhngigjnm`: keep the manifest `key`.
- The project folder stays `~/lil-brow-wow`. Files under `docs/` keep their historical names.

**Repo and releases**
- Repo `austindick/little-dia`.
- Release asset `Little-Dia.zip`, at `https://github.com/austindick/little-dia/releases/latest/download/Little-Dia.zip`.
- Install command `curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash`.
- Latest-release API: `https://api.github.com/repos/austindick/little-dia/releases/latest`.
- First release `1.0.0`. The app's version (`CFBundleShortVersionString`) and the extension's `manifest.json` version must always be equal.

**Signing**
- Every build is signed with the self-signed identity **`Little Dia`**: `LITTLEDIA_SIGN_IDENTITY="Little Dia"`.
- Never the other certificate on this Mac; it belongs to another project.

**Exact copy**
- Not-affiliated line, verbatim: `Not affiliated with or endorsed by The Browser Company.`
- Menu, setup-window and status-line strings are given verbatim in Tasks 9–11.

**Privacy**
- Logs always mark URLs `privacy: .private`.
- Diagnostics also scrub anything shaped like `http(s)://…`.

**Owner go-ahead (stop and ask at the moment it happens; spec "Constraints")**
- creating and trusting the certificate (Task 1)
- removing the old install, its Accessibility and login-item entries, and the spike app (Task 3)
- making the repo public (Task 15)
- publishing any release (Task 15)

**Sandbox**
- Claude's sandbox blocks a few commands; run them with the sandbox disabled: `swift build`, `swift test`, git writes, `open`, `osascript`, `codesign`/`security` against the keychain, `gh` (network).
- Use `/usr/bin/log`, since `log` is a zsh builtin.

**Tests and commits**
- Swift tests: `swift test 2>&1 | tail -5`. Extension tests: `node --test 'Extension/test/*'`.
- Starting point: 87 Swift tests and 21 extension tests pass. Both suites stay green after every task.
- Work happens on branch `feat/sharing`, created from `main` before Task 1.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

**Unchanged v1 behavior**
- same-desktop little windows, real logins, never losing a link
- focus returning to the source app, the live move with no reload
- `Open in {profile}` and the profile menu
- links open normally when Dia isn't running

## Review Focus

1. **The updater replacing an app it can't safely replace.** The running app might be in `build/`, on a read-only volume, or have its parent folder missing. The update must refuse with a message and touch nothing. Test `refusesToReplaceOutsideAWritableFolder` in Task 11.
2. **An extension copy that fails halfway.** For example, the bundled folder is missing or unreadable. The installed extension must be left exactly as it was. Test `installKeepsOldCopyWhenSourceIsMissing` in Task 8.
3. **The peer check rejecting the real helper.** Symlinked or non-standardized paths such as `/Users/...` vs `/private/...`, or `..` components, must still match. Every rejection must be logged at notice level, so the owner can see it in Copy Diagnostics. Test `acceptsEquivalentHelperPaths` in Task 4.
4. **The setup window popping up on every launch for someone who is fully set up**, because Dia isn't running yet and the extension hasn't connected. An installed-but-not-connected extension counts as done. Test `installedButNotConnectedCountsAsDone` in Task 9.
5. **GitHub version strings.** `v1.0.0`, `1.0.10` vs `1.0.9`, and junk tags must compare correctly, or be ignored rather than offered. Tests `comparesNumericallyNotLexically` and `ignoresUnparseableTags` in Task 11.

---

### Task 1: The "Little Dia" signing certificate (owner present)

**Files:** none in the repo. Scratch: `$TMPDIR/little-dia-cert/`.

**Interfaces:**
- Produces: a valid code-signing identity named `Little Dia` in the login keychain, used by every later build.

- [ ] **Step 1: Create the feature branch**

Run: `git checkout -b feat/sharing`
Expected: `Switched to a new branch 'feat/sharing'`

- [ ] **Step 2: Ask the owner for the go-ahead**

Say: you're about to create a self-signed code-signing certificate named "Little Dia" in their login keychain. Their password will be needed once, to trust it. Wait for yes.

- [ ] **Step 3: Generate the key and certificate with `/usr/bin/openssl`**

- Use `/usr/bin/openssl` (LibreSSL), whose PKCS#12 output `security` can import. If it's missing, use Homebrew `openssl` with `-certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg sha1`.
- Certificate details:
  - RSA 2048, SHA-256, 7300 days, subject `CN=Little Dia`
  - extensions: `basicConstraints=critical,CA:false`, `keyUsage=critical,digitalSignature`, `extendedKeyUsage=critical,codeSigning`
- Export `little-dia.p12` with a random password. Show the password to the owner once.

- [ ] **Step 4: Import, and trust for code signing**

Run:
`security import little-dia.p12 -k ~/Library/Keychains/login.keychain-db -P "$PW" -T /usr/bin/codesign`
then
`security add-trusted-cert -r trustRoot -p codeSign -k ~/Library/Keychains/login.keychain-db little-dia.crt`

Tell the owner a password dialog is coming.

- [ ] **Step 5: Verify**

Run:
- `security find-identity -v -p codesigning`
- `cp /bin/echo $TMPDIR/sigtest && codesign -f -s "Little Dia" $TMPDIR/sigtest && codesign -dv $TMPDIR/sigtest 2>&1 | grep Authority`

Expected: the identity list includes `"Little Dia"`, and `Authority=Little Dia`.

- [ ] **Step 6: Backup handoff**

- Ask the owner to save `little-dia.p12` and its password in their password manager.
- Once they confirm, delete `$TMPDIR/little-dia-cert/`.
- Nothing to commit.

---

### Task 2: Rename everything to Little Dia

**Files:**
- Move:
  - `Sources/LilBrowCore` → `Sources/LittleDiaCore`
  - `Sources/LilBrowWow` → `Sources/LittleDia`
  - `Sources/lilbrow-host` → `Sources/littledia-host`
  - `Tests/LilBrowCoreTests` → `Tests/LittleDiaCoreTests`
- Modify:
  - `Package.swift`, `Resources/Info.plist`, `scripts/build-app.sh`
  - `Extension/manifest.json`, `Extension/background.js`, `Extension/click-rules.js`, `Extension/content.js`
  - every Swift file importing or naming the old modules, loggers or queue labels
  - `Sources/LittleDiaCore/Messages.swift` (`LilBrowCore.Key` → `LittleDiaCore.Key`)
- Test:
  - `Tests/LittleDiaCoreTests/AdapterAndManifestTests.swift`
  - `Extension/test/click-rules.test.cjs`

**Interfaces:**
- Produces:
  - `ExtensionIdentity.nativeHostName == "com.austindick.littledia.bridge"`
  - `NativeHostManifest` description `"Little Dia bridge"`
  - helper at `Little Dia.app/Contents/Helpers/littledia-host`
  - executable `Little Dia.app/Contents/MacOS/LittleDia`
  - `globalThis.LittleDiaClickRules`

- [ ] **Step 1: Update the tests to the new names**

In `AdapterAndManifestTests.swift`:
- `manifestJSONHasRequiredFields` expects `json["name"] as? String == "com.austindick.littledia.bridge"` and `json["description"] as? String == "Little Dia bridge"`.
- Add `infoPlistUsesTheNewName`. It reads `Resources/Info.plist` via the same `#filePath` repo-root trick as `chromiumIDMatchesManifestKey`, then:

```swift
#expect(plist["CFBundleIdentifier"] as? String == "com.austindick.littledia")
#expect(plist["CFBundleName"] as? String == "Little Dia")
#expect(plist["CFBundleExecutable"] as? String == "LittleDia")
```

In `click-rules.test.cjs`, read `globalThis.LittleDiaClickRules`.

- [ ] **Step 2: Run the tests to make sure they fail**

Run: `swift test --filter AdapterAndManifest 2>&1 | tail -5; node --test 'Extension/test/*' 2>&1 | tail -3`
Expected: Swift FAIL (old host name and plist values). Node FAIL (`Cannot destructure property 'classifyClick' of undefined`).

- [ ] **Step 3: Do the rename**

- `git mv` the four directories.
- Edit `Package.swift`:
  - package name `LittleDia`
  - products `LittleDia` and `littledia-host`
  - targets `LittleDiaCore`, `LittleDia` (depends on `LittleDiaCore`), `littledia-host`, `LittleDiaCoreTests`
- Replace across `Sources/`, `Tests/`, `Extension/`, `Resources/`, `scripts/` using the Global Constraints table:
  - `import LilBrowCore` / `@testable import LilBrowCore`
  - every `Logger(subsystem: "com.lilbrowwow"`
  - `DispatchQueue(label: "com.lilbrowwow.bridge.io")` → `com.austindick.littledia.bridge.io`
  - the support folder name `"LilBrowWow"` → `"Little Dia"` in `AppDelegate`
  - `Contents/Helpers/lilbrow-host` → `littledia-host`
  - `LILBROW_SOCKET`
  - user-visible strings `Lil Brow Wow` → `Little Dia`, including menu titles, `NSAppleEventsUsageDescription`, the `"Lil Brow Wow: …"` console prefixes and the status item's accessibility description
  - `HOST` in `background.js`
  - the click-rules global, in `click-rules.js` and `content.js`
- Test helpers: `makeSocketPath` prefix `ld-`; `"lbw-test-"` suite names → `"ld-test-"`.
- `Info.plist`: `CFBundleIdentifier`, `CFBundleName`/`CFBundleDisplayName` `Little Dia`, `CFBundleExecutable` `LittleDia`.
- `manifest.json`: `"name": "Little Dia"`. Keep `key` and `version`.
- `scripts/build-app.sh`:
  - `APP="build/Little Dia.app"`, quoted everywhere (the name has a space)
  - products `LittleDia` and `littledia-host`
  - `IDENTITY="${LITTLEDIA_SIGN_IDENTITY:--}"`
  - sign the helper with `--identifier com.austindick.littledia.host`
  - `--install` destination `"$HOME/Applications/Little Dia.app"`, using `pkill -x LittleDia`
  - update the header comment

- [ ] **Step 4: Run all tests and check nothing old is left**

Run:
- `swift test 2>&1 | tail -3; node --test 'Extension/test/*' 2>&1 | tail -3`
- `grep -rniE "lilbrow|lil brow" Sources Tests Extension Resources scripts Package.swift`

Expected: 88 Swift tests pass, 21 extension tests pass, and grep prints nothing.

- [ ] **Step 5: Build the app**

Run: `LITTLEDIA_SIGN_IDENTITY="Little Dia" scripts/build-app.sh && codesign -dv "build/Little Dia.app" 2>&1 | grep -E "Identifier|Authority" && codesign -dv "build/Little Dia.app/Contents/Helpers/littledia-host" 2>&1 | grep Identifier`
Expected:
- `Identifier=com.austindick.littledia`
- `Authority=Little Dia`
- helper `Identifier=com.austindick.littledia.host`

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "refactor: rename Lil Brow Wow to Little Dia"
```

---

### Task 3: Retire the old install and the spike (owner go-ahead)

**Files:**
- Delete: `spike/` (tracked files, plus the untracked `spike/LBWSpike.app`)
- Modify: `.gitignore` (drop the two `spike/` lines)

**Interfaces:**
- Consumes: Task 2's `scripts/build-app.sh --install`.

- [ ] **Step 1: Read the spike app's bundle ID before deleting anything**

Run: `/usr/libexec/PlistBuddy -c "Print CFBundleIdentifier" spike/LBWSpikeApp/Info.plist`
Expected: the bundle ID. Record it for Step 3.

- [ ] **Step 2: Ask the owner for the go-ahead**

List exactly what goes:
- `~/Applications/LilBrowWow.app`
- `com.lilbrowwow.bridge.json` in both `~/Library/Application Support/Dia/NativeMessagingHosts` and `…/Dia/User Data/NativeMessagingHosts`
- `~/Library/Application Support/LilBrowWow`
- defaults domain `com.lilbrowwow.LilBrowWow`
- the Accessibility entries for the old app and the spike app
- `spike/LBWSpike.app` and its `lbwspike://` registration

Ask them to untick **Launch at Login** in the old app's menu first. Wait for yes.

- [ ] **Step 3: Clean up**

1. `pkill -x LilBrowWow`, then remove the files and folders listed in Step 2.
2. `defaults delete com.lilbrowwow.LilBrowWow`.
3. `tccutil reset Accessibility com.lilbrowwow.LilBrowWow`, and the same with the spike bundle ID.
4. `lsregister -u spike/LBWSpike.app`.
5. `git rm -r spike` and `rm -rf spike`.
6. Edit `.gitignore`.

- [ ] **Step 4: Install the renamed app and reconnect**

1. Run `LITTLEDIA_SIGN_IDENTITY="Little Dia" scripts/build-app.sh --install`.
2. The owner clicks *Make Little Dia the Default Browser…* and *Grant Accessibility Access…* in the menu.
3. The owner presses the reload icon for the extension on Dia's `chrome://extensions` page (it's still loaded from the repo's `Extension/`).

Expected: the menu shows `Dia Extension: Connected` and `Accessibility: Granted`.

- [ ] **Step 5: Smoke test**

The owner clicks a Slack link on a desktop without Dia's main window. Expected:
- the little window opens there, signed in
- the buttons appear
- Open in Work moves the tab with no reload
- closing the window returns focus to Slack

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "chore: remove the throwaway spike"
```

---

### Task 4: Only the real extension may connect

**Files:**
- Modify:
  - `Sources/LittleDiaCore/UnixSocket.swift`
  - `Sources/LittleDiaCore/BridgeServer.swift`
  - `Sources/LittleDiaCore/BrowserAdapter.swift`
  - `Sources/littledia-host/main.swift`, which now uses the shared `ProcessTree.parentPID`
  - `Sources/LittleDia/AppDelegate.swift`
- Create:
  - `Sources/LittleDiaCore/PeerCheck.swift`
  - `Sources/LittleDia/PeerVerifier.swift`
- Test:
  - `Tests/LittleDiaCoreTests/BridgeTests.swift`
  - `Tests/LittleDiaCoreTests/PeerCheckTests.swift`

**Interfaces:**
- Produces:
  - `UnixSocket.peerPID(_ fd: Int32) -> pid_t?`, using `getsockopt(SOL_LOCAL, LOCAL_PEERPID)`
  - `UnixSocket.listen(path:)` leaves the socket file at mode `0600`
  - `ProcessTree.parentPID(of: pid_t) -> pid_t?`, moved from `littledia-host/main.swift` into Core
  - `BridgeServer.init(socketPath: String, acceptPeer: @escaping @Sendable (pid_t) -> Bool = { _ in true })`. On accept, a missing peer PID or a `false` closes the socket at once and logs `rejected connection from pid <n>` at notice level.
  - `BrowserAdapter.codeRequirement: String?`. For `.dia`: `anchor apple generic and identifier "company.thebrowser.dia" and certificate leaf[subject.OU] = "S6N382Y83G"`. For `.chrome`: nil.
  - `PeerCheck.isTrusted(peer: pid_t, helperPath: String, executablePath: (pid_t) -> String?, parent: (pid_t) -> pid_t?, hasValidSignature: (pid_t) -> Bool, isBrowser: (pid_t) -> Bool) -> Bool`. True only when all hold:
    - the peer's executable path equals `helperPath`, after `URL(fileURLWithPath:).resolvingSymlinksInPath().standardizedFileURL.path` on both
    - `hasValidSignature(peer)`
    - the peer has a parent
    - `isBrowser(parent)`
  - App: `PeerVerifier.make(helperPath: String, browserRequirement: String?) -> @Sendable (pid_t) -> Bool`, which wires `PeerCheck` to:
    - `proc_pidpath`
    - `ProcessTree.parentPID`
    - `SecCodeCopyGuestWithAttributes` with `kSecGuestAttributePid`, then `SecCodeCheckValidity` (no requirement for the helper; `SecRequirementCreateWithString(browserRequirement)` for the parent)

- [ ] **Step 1: Write the failing tests**

`PeerCheckTests.swift` uses fake closures over a table:

```swift
@Test func acceptsTheBundledHelperLaunchedByTheBrowser()   // path match, valid sig, parent 10, isBrowser(10) → true
@Test func rejectsAnotherExecutable()                       // path "/tmp/evil" → false
@Test func rejectsAnInvalidSignature()                      // hasValidSignature false → false
@Test func rejectsAHelperNotLaunchedByTheBrowser()          // isBrowser(parent) false → false
@Test func rejectsAPeerWithoutParent()                      // parent nil → false
@Test func acceptsEquivalentHelperPaths()                   // "/Users/x/Applications/Little Dia.app/Contents/Helpers/../Helpers/littledia-host" vs the plain path → true
@Test func diaRequirementPinsDiasTeam() { #expect(BrowserAdapter.dia.codeRequirement?.contains("S6N382Y83G") == true) }
```

`BridgeTests.swift`:

```swift
@Test func peerPIDIsTheConnectingProcess()       // listen + connect in-process; peerPID(accepted) == getpid()
@Test func socketFileIsOwnerOnly()               // after listen, stat(path).st_mode & 0o777 == 0o600
@MainActor @Test func rejectedPeerIsClosedAndNeverReady()   // BridgeServer(socketPath:, acceptPeer: { _ in false });
    // client sends hostHello; client.reader.next() returns nil (EOF); !server.isReady(browser:)
@Test func parentPIDOfThisProcess() { #expect(ProcessTree.parentPID(of: getpid()) == getppid()) }
```

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter "PeerCheck|Bridge" 2>&1 | tail -5`
Expected: compile failure (`PeerCheck`, `peerPID`, `ProcessTree`, `acceptPeer`, `codeRequirement` not found).

- [ ] **Step 3: Implement**

Core:
- `UnixSocket.peerPID`.
- `chmod(path, 0o600)` after `bind` in `listen`.
- `ProcessTree` (moved from the helper).
- `PeerCheck`.
- `BrowserAdapter.codeRequirement` (new `init` parameter, default nil).
- `BridgeServer` takes `acceptPeer` and checks it in the accept handler on `ioQueue`, before `add`.

App:
- `PeerVerifier`.
- `AppDelegate` creates the support folder with `[.posixPermissions: 0o700]`, and calls `setAttributes` for an existing one.
- `BridgeServer(socketPath:acceptPeer:)` with `PeerVerifier.make(helperPath: <bundle>/Contents/Helpers/littledia-host, browserRequirement: settings.browser.codeRequirement)`.

Helper: `littledia-host/main.swift` uses `ProcessTree.parentPID`.

- [ ] **Step 4: Run the tests to make sure they pass**

Run: `swift test 2>&1 | tail -3`
Expected: all pass (88 + 11 = 99).

- [ ] **Step 5: Real-world check**

1. Run `LITTLEDIA_SIGN_IDENTITY="Little Dia" scripts/build-app.sh --install`. The owner clicks a link: a little window opens. The menu says Connected.
2. Run `python3 -c 'import socket,struct,json,os;s=socket.socket(socket.AF_UNIX);s.connect(os.path.expanduser("~/Library/Application Support/Little Dia/bridge.sock"));m=json.dumps({"type":"hostHello","browserBundleID":"company.thebrowser.dia","browserPID":1}).encode();s.send(struct.pack("<I",len(m))+m);print(s.recv(10))'`.

Expected:
- the Python client prints `b''`
- `/usr/bin/log show --last 1m --predicate 'subsystem == "com.austindick.littledia"' | grep rejected` shows the rejection

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: accept bridge connections only from the bundled helper launched by Dia"
```

---

### Task 5: A dropped connection fails in-flight opens

**Files:**
- Modify: `Sources/LittleDiaCore/BridgeServer.swift`, `Sources/LittleDiaCore/BridgeExtensionLink.swift`, the call sites in `Sources/LittleDia/AppDelegate.swift`
- Test: `Tests/LittleDiaCoreTests/BridgeTests.swift`

**Interfaces:**
- Produces:
  - `BridgeServer.send(_:to:) -> Int?`, `@discardableResult`: the connection ID it went to, nil if none. Callers that tested `Bool` now test `!= nil`.
  - `BridgeServerDelegate.bridge(_ server: BridgeServer, connectionClosed id: Int)`, with an empty default in a protocol extension.
  - `BridgeExtensionLink` fails every pending open sent on a closed connection with `.failed("connection lost")`.

- [ ] **Step 1: Write the failing test**

```swift
@MainActor @Test func inFlightOpenFailsWhenItsConnectionDrops() async throws {
    // server + link; client ready(); start link.open(request, browser:, timeout: .seconds(5)) in a Task;
    // client.readOutbound() receives the open; client.close()
    // result == .failed("connection lost"), and it arrives in under 1 second (measure with ContinuousClock)
}
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `swift test --filter inFlightOpenFails 2>&1 | tail -5`
Expected: FAIL. The result is `.timedOut` after 5 s.

- [ ] **Step 3: Implement**

- `remove(_:notify:)` calls `delegate?.bridge(self, connectionClosed: id)`.
- `pendingOpens` stores `(continuation, connectionID)`.

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -3`
Expected: all pass (100).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "fix: fall back at once when the extension disconnects mid-open"
```

---

### Task 6: Small fixes (no display, the Accessibility observer, unused `copy`, right-click modifiers)

**Files:**
- Modify:
  - `Sources/LittleDiaCore/LinkRouter.swift`
  - `Sources/LittleDiaCore/Messages.swift`
  - `Sources/LittleDia/AppDelegate.swift`
  - `Sources/LittleDia/LittleWindowTracker.swift`
  - `Extension/click-rules.js`
- Test: `RouterTests.swift`, `MessagesTests.swift`, `Extension/test/click-rules.test.cjs`

**Interfaces:**
- Produces:
  - `LinkRouter.init(…, screen: @escaping () -> ScreenContext?, …)`
  - a new `FallbackReason.noScreen`
  - `InboundMessage` without `.copy`

- [ ] **Step 1: Write the failing tests**

- `RouterTests`: `noScreenOpensNormally`. The router is built with `screen: { nil }`; it expects `.openedNormally(.noScreen)` and `link.openCalls.isEmpty`.
- `MessagesTests`: `rejectsCopyMessage`. `#expect(throws: (any Error).self) { try MessageCoding.decodeInbound(Data(#"{"type":"copy","url":"https://a.b/"}"#.utf8)) }`.
- Click rules, new cases:
  - `[{ button: 2, metaKey: true }, base, "default"]`
  - `[{ button: 2, shiftKey: true }, base, "default"]`
  - `[{ button: 1, shiftKey: true }, base, "little"]`

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter "noScreen|rejectsCopy" 2>&1 | tail -5; node --test 'Extension/test/*' 2>&1 | tail -3`
Expected:
- Swift: the router test doesn't compile (`screen` can't return nil), and the copy message still decodes.
- Node: the two `button: 2` cases fail.

- [ ] **Step 3: Implement**

- Router: `guard let screenContext = screen() else { return fallback(.noScreen) }`.
- `AppDelegate.currentScreen() -> ScreenContext?` returns nil when `NSScreen.screens` is empty.
- Remove `.copy` from `InboundMessage` (its decode, encode, the `describe` case and the handler in `AppDelegate`).
- Click rules: `opensNewTab = evt.button === 1 || (evt.button === 0 && (evt.metaKey || evt.shiftKey || target === "_blank"))`.
- Tracker:
  - when Dia terminates, and before replacing an observer in `startObserving`, call `CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)`
  - log `stopped observing browser <pid>`

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -3; node --test 'Extension/test/*' 2>&1 | tail -3`
Expected: Swift 102 pass; extension 24 pass.

- [ ] **Step 5: Manual check of the tracker change**

1. Install the build, quit Dia, reopen it, then open a link.
2. The buttons appear.
3. The log shows `stopped observing browser`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "fix: guard missing displays, release the AX observer, drop the unused copy message, ignore right-click modifiers"
```

---

### Task 7: Measure Dia's title-bar height

**Files:**
- Modify:
  - `Sources/LittleDiaCore/Settings.swift`, `LinkRouter.swift`, `BridgeExtensionLink.swift` (`OpenRequest`), `Messages.swift`
  - `Sources/LittleDia/LittleWindowTracker.swift`, `AppDelegate.swift`
  - `Extension/bridge-logic.js`, `Extension/background.js`
- Test: `RegistryAndSettingsTests.swift`, `RouterTests.swift`, `MessagesTests.swift`, `Extension/test/bridge-logic.test.mjs`

**Interfaces:**
- Produces:
  - **Settings:**
    - `LittleSettings.chromeHeight: CGFloat`, a new protocol requirement
    - `UserDefaultsSettings.chromeHeight`, default `browser.chromeHeight` (72), key `chromeHeight`
    - `UserDefaultsSettings.rememberChromeHeight(_ height: CGFloat)`, which stores only values in `20...200`
  - **Messages:**
    - `OpenRequest.chromeHeight: Int`
    - `OutboundMessage.open(requestId:url:bounds:focused:chromeHeight:)`, encoded with key `chromeHeight`
  - **Router:** uses `settings.chromeHeight` for `ScreenGeometry.littleWindowBounds` and for the request.
  - **Tracker:** `LittleWindowTracker.init(onChange:onResize:onSettled:)`. `onSettled(windowId, measuredChromeHeight)` reports the settled frame height minus the entry's `pageHeight`.
  - **JS:**
    - `addedHeight(win, requestedHeight, fallback)` returns `chromeHeight(requestedHeight, win.height)` when `win.height > 0`, else `fallback`
    - `openLittleWindow` takes `chromeHeight` and stores `addedHeight(win, bounds.height, chromeHeight ?? DIA_CHROME_HEIGHT)`

- [ ] **Step 1: Write the failing tests**

- `settingsRemembersAPlausibleChromeHeight`: default 72; `rememberChromeHeight(80)` gives 80; `rememberChromeHeight(500)` leaves 80; `rememberChromeHeight(5)` leaves 80.
- `routerUsesTheMeasuredChromeHeight`: with `FakeSettings.chromeHeight = 90`, `link.openCalls[0].chromeHeight == 90`. The request's bounds equal `ScreenGeometry.littleWindowBounds(size: settings.littleWindowSize, on: primary, chromeHeight: 90)`.
  - Add `var chromeHeight: CGFloat = 72` to `FakeSettings`.
- `encodesOpenExactly` becomes `{"bounds":{"height":750,"left":300,"top":137,"width":1000},"chromeHeight":72,"focused":true,"requestId":"r1","type":"open","url":"https://github.com/"}`.
- JS:
  - `addedHeight({height: 0}, 750, 80) === 80`
  - `addedHeight({height: 822}, 750, 80) === 72`

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter "ChromeHeight|encodesOpenExactly" 2>&1 | tail -5; node --test 'Extension/test/*' 2>&1 | tail -3`
Expected: compile failure in Swift; `addedHeight is not a function` in node.

- [ ] **Step 3: Implement**

Follow the interfaces above. In `AppDelegate`, `onSettled` calls `settings.rememberChromeHeight` and logs `measured title bar <h>pt`.

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -3; node --test 'Extension/test/*' 2>&1 | tail -3`
Expected: Swift 104 pass; extension 26 pass.

- [ ] **Step 5: Manual check**

1. Install, reload the extension in Dia, open two links.
2. The log shows `measured title bar 72pt`.
3. Windows land centered with the buttons placed as before.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: measure Dia's title-bar height instead of assuming 72pt"
```

---

### Task 8: The extension ships inside the app and updates itself

**Files:**
- Create: `Sources/LittleDiaCore/ExtensionInstaller.swift`
- Modify:
  - `Sources/LittleDiaCore/Messages.swift`
  - `Sources/LittleDia/AppDelegate.swift`
  - `Extension/background.js`, `Extension/manifest.json`, `Resources/Info.plist`
  - `scripts/build-app.sh`
- Test: `Tests/LittleDiaCoreTests/ExtensionInstallerTests.swift`, `MessagesTests.swift`

**Interfaces:**
- Produces:
  - **`ExtensionInstaller`:**
    - `version(ofExtensionAt folder: URL) -> String?`, which reads `manifest.json` `version`
    - `installIfNeeded(bundled: URL, installed: URL) throws -> Bool`:
      - copies when `installed` is missing or the versions differ
      - copies to a temporary sibling folder, then swaps it in with `FileManager.replaceItemAt`
      - never touches `installed` if `bundled` is unreadable (throws)
      - returns whether it copied
    - `needsReload(connectedVersion: String, bundledVersion: String) -> Bool`
  - **Messages:** `OutboundMessage.ping`, encoded `{"type":"ping"}`, and `OutboundMessage.reload`, encoded `{"type":"reload"}`.
  - **App:**
    - **At launch:** `installIfNeeded(bundled: Bundle.main.resourceURL!/Extension, installed: <support>/Extension)`.
    - **On every connections change:** sends `.ping` to the configured browser.
    - **On `.hello(version)`:** stores the version as `lastExtensionVersion`; if `needsReload` says so, sends `.reload`.
  - **Extension:** `"ping"` → `post({type: "hello", extensionVersion})`; `"reload"` → `chrome.runtime.reload()`.
  - **Build:** `build-app.sh` copies `Extension/` to `Contents/Resources/Extension`, without `test/`. This happens before signing, so the extension is sealed into the app's signature.
  - **Versions:** both bump to `0.2.0`, in `Info.plist` and `manifest.json`.

- [ ] **Step 1: Write the failing tests**

All use temp folders with small `manifest.json` files.
- `readsTheManifestVersion`
- `installsWhenMissing`: returns true; the files are present.
- `skipsWhenVersionsMatch`: returns false; a marker file in `installed` survives.
- `replacesWhenVersionsDiffer`: returns true; the new version is installed; the old marker is gone.
- `installKeepsOldCopyWhenSourceIsMissing`: throws; `installed` is unchanged.
- `needsReloadOnlyWhenVersionsDiffer`.
- `encodesPingAndReloadExactly`.

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter "ExtensionInstaller|PingAndReload" 2>&1 | tail -5`
Expected: compile failure (`ExtensionInstaller`, `.ping` and `.reload` not found).

- [ ] **Step 3: Implement**

Follow the interfaces above.

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -3; node --test 'Extension/test/*' 2>&1 | tail -3`
Expected: Swift 111 pass; extension 26 pass.

- [ ] **Step 5: Manual check**

1. Install. `~/Library/Application Support/Little Dia/Extension/manifest.json` says `0.2.0`.
2. In Dia, the owner removes the repo-loaded extension and loads the support-folder copy (Load unpacked).
3. Links work.
4. Temporarily set both versions to `0.2.1` and reinstall. Without the owner doing anything, the log shows `hello 0.2.0`, then the reload, then `hello 0.2.1`.
5. Revert to `0.2.0` and reinstall.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: bundle the extension in the app and reload it after updates"
```

---

### Task 9: Setup status and the setup window

**Files:**
- Create:
  - `Sources/LittleDiaCore/SetupStatus.swift`
  - `Sources/LittleDia/SetupWindow.swift`: SwiftUI `SetupView`, an `ObservableObject` `SetupModel`, and an `NSWindowController` subclass `SetupWindowController`
- Modify:
  - `Sources/LittleDiaCore/BrowserProfiles.swift` (`DiaScript.openTab`)
  - `Sources/LittleDiaCore/Settings.swift` (`hasLaunchedBefore`)
  - `Sources/LittleDia/AppDelegate.swift`
- Test: `Tests/LittleDiaCoreTests/SetupStatusTests.swift`, `ProfilesTests.swift`

**Interfaces:**
- Produces:

```swift
public enum ExtensionState: Equatable, Sendable { case connected, installed, missing }
public enum MenuLine: Equatable, Sendable { case allSet(profile: String?), problem(String) }
public struct SetupStatus: Equatable, Sendable {
    public var isDefaultBrowser: Bool
    public var extensionState: ExtensionState
    public var accessibilityGranted: Bool
    public var browserPinnedToDesktop: Bool
    public var profile: String?
    public init(...)                  // memberwise
    public var requiredDone: Bool     // isDefaultBrowser && extensionState != .missing && accessibilityGranted
    public var menuLine: MenuLine     // first problem in this order, else .allSet(profile)
}
```

- **Problem strings**, verbatim and in order:
  1. `Not the default browser`
  2. `Dia extension not installed`
  3. `Title-bar buttons need Accessibility`
  4. `Dia is pinned to one desktop`
- **Display text:** `MenuLine.allSet` reads `All set · <profile>`, or `All set` when the profile is nil.
- **Extension state** is computed by the app:
  - `.connected` when `link.isReady(browser:)`
  - else `.installed` when `BrowserProfiles.load(...)` is non-nil (the extension's ID is in a profile's preferences)
  - else `.missing`
- **`DiaScript.openTab(url: String) -> String`:** AppleScript that makes a new tab with that URL in window 1 and activates Dia.
- **`UserDefaultsSettings.hasLaunchedBefore: Bool`**, default false.
- **Setup window**, title `Set Up Little Dia`. Rows and copy, verbatim from the approved mockup:
  1. **Make it your default browser.** Done text `Links from other apps come here first.` Button `Set as Default`.
  2. **Add the extension to Dia.**
     - Steps: `Open Dia's Extensions page` / `Turn on Developer mode (top right)` / `Drag the Little Dia folder onto the page`.
     - Buttons: `Open Extensions Page`, `Show Folder`.
     - Waiting text: `Waiting for the extension…`.
     - Hint: `Add it in the Dia profile you want little windows to use.`
  3. **Allow the title-bar buttons.** Text `Turn on Little Dia under Accessibility so it can show Copy and Open in Dia.` Button `Open Settings`.
  4. **Dia is pinned to one desktop**, shown only when pinned. Text `Dock → right-click Dia → Options → Assign To → None`.
  - **Footer:** checkbox `Open at login`, and button `Done`, enabled only when `requiredDone`.
- **Behavior:**
  - The model refreshes every 1 s while the window is visible.
  - **On first launch** (`!hasLaunchedBefore`): set `SystemIntegration.launchAtLogin = true` and `hasLaunchedBefore = true`.
  - **Auto-open:** at `applicationDidFinishLaunching`, if `!status.requiredDone`, show the window and `NSApp.activate()`.

- [ ] **Step 1: Find out what Dia accepts, before building the extension row**

Run: `osascript -e 'tell application id "company.thebrowser.dia" to make new tab at end of tabs of window 1 with properties {URL:"chrome://extensions"}'`
Then ask the owner:
- whether it opened the Extensions page
- whether dragging `~/Library/Application Support/Little Dia/Extension` onto that page (with Developer mode on) loads it

Record both results in the ledger, then pick the copy:
- If the AppleScript fails: `Open Extensions Page` copies `chrome://extensions` to the clipboard and the step reads `Paste chrome://extensions into Dia's address bar`.
- If dragging fails: the third step reads `Click Load unpacked and choose the Little Dia folder (⌘⇧G, then paste)`, and `Show Folder` also copies the folder path.

- [ ] **Step 2: Write the failing tests**

- `allDoneIsAllSetWithProfile`: `.allSet(profile: "Work")`, `requiredDone`.
- `installedButNotConnectedCountsAsDone`: `extensionState: .installed`, so `requiredDone` and `.allSet`.
- `missingExtensionIsTheProblem`: `.problem("Dia extension not installed")`, `!requiredDone`.
- `problemsAreReportedInOrder`: everything wrong gives `.problem("Not the default browser")`.
- `pinnedIsAProblemButNotRequired`: `requiredDone` is true, and `menuLine == .problem("Dia is pinned to one desktop")`.
- `openTabScriptEscapesAndTargetsDia`: `DiaScript.openTab(url: "chrome://extensions")` contains `company.thebrowser.dia` and `{URL:"chrome://extensions"}`.
- `firstLaunchFlagDefaultsFalseAndPersists`.

- [ ] **Step 3: Run them to make sure they fail**

Run: `swift test --filter "SetupStatus|openTabScript|firstLaunch" 2>&1 | tail -5`
Expected: compile failure.

- [ ] **Step 4: Implement**

Core types first, then the window. Reuse:
- `SystemIntegration.makeDefaultBrowser`, `isAccessibilityTrusted(prompt:)`, `openAccessibilitySettings`, `isBrowserAssignedToDesktop`, `launchAtLogin`
- `runAppleScript` and `BrowserProfiles.load` from `AppDelegate`
- `NSWorkspace.shared.activateFileViewerSelecting` for `Show Folder`

- [ ] **Step 5: Run all tests**

Run: `swift test 2>&1 | tail -3`
Expected: 118 pass.

- [ ] **Step 6: Manual check (owner)**

With everything already set up, relaunch the app: no window appears. Then:
1. In System Settings, set the default browser to Dia.
2. Relaunch: the window opens with row 1 unticked.
3. Click Set as Default and confirm: the row ticks within 1 s.
4. Disable the extension in Dia: row 2 shows Waiting.
5. Re-enable it: the row ticks.
6. Done becomes enabled.

- [ ] **Step 7: Commit**

```bash
git add -A && git commit -m "feat: setup window that ticks itself off"
```

---

### Task 10: The new menu, About and Copy Diagnostics

**Files:**
- Create: `Sources/LittleDiaCore/Diagnostics.swift`
- Modify: `Sources/LittleDia/StatusMenu.swift` (rewritten), `Sources/LittleDia/AppDelegate.swift`
- Test: `Tests/LittleDiaCoreTests/DiagnosticsTests.swift`

**Interfaces:**
- Consumes: `SetupStatus` / `MenuLine` (Task 9), `lastExtensionVersion` (Task 8), `settings.chromeHeight` (Task 7).
- Produces:
  - `Diagnostics.report(appVersion: String, extensionVersion: String?, macOSVersion: String, browserVersion: String?, status: SetupStatus, profiles: BrowserProfiles?, chromeHeight: CGFloat, logLines: [String]) -> String`
    - plain text with one `Key: value` line per fact
    - then `Recent log:` and at most the last 300 log lines
    - every `https?://\S+` replaced with `<url>`
  - **Menu**, in this order, with these exact titles:
    - `Open Links in Little Windows` (checkmark toggle)
    - separator
    - the status line: `MenuLine` text. When it's a problem, clicking it opens setup; otherwise it's disabled.
    - `Setup…`
    - separator
    - `Copy Diagnostics`
    - `About Little Dia`
    - separator
    - `Quit Little Dia` (⌘Q)
    - (`Check for Updates…` is inserted above `Copy Diagnostics` in Task 11.)
  - **About:** `NSApp.orderFrontStandardAboutPanel(options:)`. The credits contain `https://github.com/austindick/little-dia` as a link, plus the not-affiliated line. Call `NSApp.activate()` first.
  - **Copy Diagnostics log lines:** `OSLogStore(scope: .currentProcessIdentifier)`, entries from the last hour whose subsystem is `com.austindick.littledia`, formatted `HH:mm:ss [category] message`.

- [ ] **Step 1: Write the failing tests**

- `reportListsVersionsAndStatus`: contains `App: 1.0.0`, `Extension: 0.2.0`, `Dia: 1.54.2`, `Status: All set · Work`, `Profiles: Personal, Work (extension in Work)`, `Title bar: 72pt`.
- `reportScrubsURLs`: a log line `opened https://secret.example/a?b=c` comes out as `opened <url>`.
- `reportKeepsOnlyTheLast300LogLines`.
- `reportHandlesMissingValues`: nil extension version gives `Extension: not connected`; nil profiles gives `Profiles: none found`.

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter Diagnostics 2>&1 | tail -5`
Expected: compile failure.

- [ ] **Step 3: Implement**

`Diagnostics`, then the menu rewrite. The old status-line items and the *Launch at Login* item are removed; launch at login now lives in the setup window.

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -3`
Expected: 122 pass.

- [ ] **Step 5: Manual check**

1. The menu matches the order above and shows `All set · Work`.
2. Copy Diagnostics pastes into a text editor with versions and recent log lines, and no URLs.
3. The About panel shows the version, a GitHub link and the not-affiliated line.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: one-line status menu, About panel and Copy Diagnostics"
```

---

### Task 11: Check for Updates

**Files:**
- Create:
  - `Sources/LittleDiaCore/Release.swift` (`Version`, `ReleaseInfo`, `UpdateOffer`, `ReleaseSource`, `UpdateInstall`)
  - `Sources/LittleDia/Updater.swift`
- Modify: `Sources/LittleDia/StatusMenu.swift`, `Sources/LittleDia/AppDelegate.swift`, `Sources/LittleDiaCore/Settings.swift` (`lastUpdateCheck: Date?`)
- Test: `Tests/LittleDiaCoreTests/ReleaseTests.swift`

**Interfaces:**
- Produces:

```swift
public struct Version: Comparable, Sendable { public init?(_ string: String) }   // "1.2.3" or "v1.2.3"; three numeric parts; else nil
public struct ReleaseInfo: Decodable, Sendable { public let tagName: String; public let assets: [Asset]
    public struct Asset: Decodable, Sendable { public let name: String; public let browserDownloadURL: URL } }   // snake_case keys
public struct UpdateOffer: Equatable, Sendable { public let version: String; public let downloadURL: URL
    public static func decide(currentVersion: String, release: ReleaseInfo, assetName: String = ReleaseSource.assetName) -> UpdateOffer? }
public enum ReleaseSource { public static let latestReleaseURL: URL; public static let assetName = "Little-Dia.zip" }
public enum UpdateInstall { public static func canReplace(appAt bundleURL: URL, fileManager: FileManager = .default) -> Bool }
    // true only when the path ends in ".app", the item exists and its parent folder is writable
```

- **`Updater` (app):**
  - `check(userInitiated: Bool) async`. It GETs `latestReleaseURL` with `Accept: application/vnd.github+json` and publishes `state`:
    - `.idle`, `.checking`, `.upToDate`
    - `.available(UpdateOffer)`
    - `.failed(String)`
  - **Automatic checks:** at launch (after 10 s) and on an hourly timer, but only when `lastUpdateCheck` is more than 24 h old.
  - `install(_ offer: UpdateOffer) async`, in order:
    1. Refuse unless `UpdateInstall.canReplace(Bundle.main.bundleURL)`.
    2. Download to a temp folder and run `ditto -x -k` on it.
    3. Find `Little Dia.app` in the result.
    4. Verify `SecStaticCodeCheckValidity(newApp, [], ownDesignatedRequirement)`, where the requirement comes from `SecCodeCopySelf` and `SecCodeCopyDesignatedRequirement`.
    5. `FileManager.trashItem` the running bundle, then move the new app to the same path.
    6. Launch `/bin/sh -c 'sleep 1; open "<path>"'`, then `NSApp.terminate(nil)`.
    7. Any failure leaves the current app in place and sets `.failed(reason)`.
- **Menu:** `Check for Updates…` goes above `Copy Diagnostics`.
  - When an update is available, it reads `Update to <version>…` and installs on click.
  - User-initiated results show an `NSAlert`:
    - `Little Dia <version> is up to date.`
    - `Couldn't check for updates: <reason>`
    - `Couldn't update: <reason>`

- [ ] **Step 1: Write the failing tests**

- `parsesVersionsWithOrWithoutV`: `Version("v1.2.0") == Version("1.2.0")`.
- `comparesNumericallyNotLexically`: `Version("1.0.10")! > Version("1.0.9")!`.
- `ignoresUnparseableTags`: `Version("latest") == nil`, and `decide` returns nil for such a tag.
- `decodesGitHubRelease`: a sample JSON with `tag_name`, `assets[].name` and `browser_download_url`.
- `offersANewerReleaseWithTheZip`.
- `noOfferForTheSameVersion`.
- `noOfferWithoutTheZipAsset`.
- `refusesToReplaceOutsideAWritableFolder`:
  - false for a path not ending in `.app`
  - false for a missing item
  - false when the parent folder is made read-only with `chmod 0o555` (restore it in `defer`)
  - true for a temp `X.app` folder

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter Release 2>&1 | tail -5`
Expected: compile failure.

- [ ] **Step 3: Implement**

Core types first, then `Updater` and the menu wiring.

- [ ] **Step 4: Run all tests**

Run: `swift test 2>&1 | tail -3`
Expected: 130 pass.

- [ ] **Step 5: Manual check (failure path only, since the repo is still private)**

Choose *Check for Updates…*. Expected: an alert reading `Couldn't check for updates: …` (the private repo returns 404), and nothing changes. The success path is checked in Task 15.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "feat: check for updates and install them in place"
```

---

### Task 12: Install script, release script and version 1.0.0

**Files:**
- Create: `install.sh` (repo root, executable), `scripts/release.sh`, `scripts/test-install.sh`
- Modify: `scripts/build-app.sh` (universal build), `Resources/Info.plist` and `Extension/manifest.json` (→ `1.0.0`)
- Test: `Tests/LittleDiaCoreTests/AdapterAndManifestTests.swift` (`appAndExtensionVersionsMatch`), `scripts/test-install.sh`

**Interfaces:**
- **`install.sh`:**
  - **No argument:** downloads the release asset URL from Global Constraints with `curl -fsSL`.
  - **A path to a zip:** installs that instead.
  - **`--uninstall`:** see below.
  - **Environment overrides, for tests:**
    - `LITTLEDIA_APPS_DIR`, default `$HOME/Applications`
    - `LITTLEDIA_APP_SUPPORT`, default `$HOME/Library/Application Support`
    - `LITTLEDIA_NO_OPEN=1`, which skips `pkill` and `open`
  - **Install steps:**
    1. `pkill -x LittleDia || true`.
    2. Create the apps folder.
    3. Remove any old `Little Dia.app`, then `ditto -x -k` into the folder.
    4. `lsregister -f`.
    5. Run `open`; on failure, sleep 2 s and run it once more.
    6. Print `Little Dia is installed. Follow the setup window to finish.`
  - **Uninstall** removes:
    - the app
    - `$LITTLEDIA_APP_SUPPORT/Little Dia`
    - `com.austindick.littledia.bridge.json` in both `Dia/NativeMessagingHosts` and `Dia/User Data/NativeMessagingHosts`

    Then it prints two follow-up instructions, verbatim:
    - `Set Dia as your default browser: System Settings → Desktop & Dock → Default web browser.`
    - `Remove the Little Dia extension in Dia: chrome://extensions.`
- **`scripts/release.sh [--dry-run]`:**
  - Refuses with an error if:
    - the tree isn't clean
    - the branch isn't `main` (skipped with `--dry-run`)
    - the `Info.plist` version ≠ the `manifest.json` version
  - Runs `LITTLEDIA_SIGN_IDENTITY="Little Dia" scripts/build-app.sh`.
  - `ditto -c -k --keepParent "build/Little Dia.app" build/Little-Dia.zip`.
  - Without `--dry-run`: `gh release create "v$VERSION" build/Little-Dia.zip --title "Little Dia $VERSION" --generate-notes`.
- **`build-app.sh`:**
  - Builds with `swift build -c release --arch arm64 --arch x86_64` and copies from the matching `--show-bin-path`.
  - If that fails, it falls back to a native-arch build and prints a warning. The README then says Apple silicon only (Task 14).

- [ ] **Step 1: Write the failing tests**

- **`appAndExtensionVersionsMatch`** reads both files via `#filePath`. It expects `plist["CFBundleShortVersionString"] == manifest["version"]` and that the version equals `"1.0.0"`.
- **`scripts/test-install.sh`:**
  1. Builds a fake zip containing `Little Dia.app/Contents/Info.plist` in a temp folder.
  2. Runs `LITTLEDIA_NO_OPEN=1 LITTLEDIA_APPS_DIR=$T/apps LITTLEDIA_APP_SUPPORT=$T/support bash install.sh $T/fake.zip`.
  3. Asserts `$T/apps/Little Dia.app` exists.
  4. Creates fake manifests in both Dia folders under `$T/support`.
  5. Runs `--uninstall` with the same variables.
  6. Asserts the app, `$T/support/Little Dia` and both manifests are gone, and the output contains `Desktop & Dock`.
  7. Exits non-zero on any failure and prints `test-install: OK` on success.

- [ ] **Step 2: Run them to make sure they fail**

Run: `swift test --filter appAndExtensionVersionsMatch 2>&1 | tail -3; bash scripts/test-install.sh`
Expected: Swift FAIL (`0.2.0 != 1.0.0`); test-install FAIL (`install.sh` missing).

- [ ] **Step 3: Implement**

Write the scripts, bump both versions to `1.0.0`, and make `build-app.sh` universal.

- [ ] **Step 4: Run the tests and a dry-run release**

Run:
- `swift test 2>&1 | tail -3`
- `bash scripts/test-install.sh`
- `scripts/release.sh --dry-run`
- `lipo -archs "build/Little Dia.app/Contents/MacOS/LittleDia"`
- `rm -rf $TMPDIR/z && mkdir $TMPDIR/z && ditto -x -k build/Little-Dia.zip $TMPDIR/z && codesign --verify --deep --strict "$TMPDIR/z/Little Dia.app" && echo VERIFIED`

Expected:
- 131 Swift tests pass
- `test-install: OK`
- `lipo` prints `x86_64 arm64`, or a recorded fallback ruling
- `VERIFIED`

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: one-command install, uninstall and release scripts; version 1.0.0"
```

---

### Task 13: App icon (owner picks)

**Files:**
- Create: `scripts/make-icon.swift`, `Resources/AppIcon.icns`
- Modify: `Resources/Info.plist` (`CFBundleIconFile` = `AppIcon`), `scripts/build-app.sh` (copy the icon into `Contents/Resources`)

- [ ] **Step 1: Show the options**

- Restart the brainstorming visual companion with the sandbox disabled: `start-server.sh --project-dir ~/lil-brow-wow`.
- Push `icon-options.html` with three inline-SVG drafts at 256 px and 32 px. Each shows a small window in front of a larger one. No Dia logo, no Dia gradient, no Dia colors.
- The owner picks one, or asks for changes. Iterate with `icon-options-v2.html` etc.

- [ ] **Step 2: Render the chosen design**

- `scripts/make-icon.swift` draws the chosen design with CoreGraphics into `$TMPDIR/AppIcon.iconset` at the sizes `iconutil` expects (16–1024, @1x and @2x).
- `iconutil -c icns` writes `Resources/AppIcon.icns`.

Run: `swift scripts/make-icon.swift && file Resources/AppIcon.icns`
Expected: `Mac OS X icon`.

- [ ] **Step 3: Wire it in, build, check**

Run: `LITTLEDIA_SIGN_IDENTITY="Little Dia" scripts/build-app.sh --install`
Expected: the icon appears in Finder (`~/Applications`), in the About panel, in the setup window title and in the Accessibility list.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "feat: app icon"
```

---

### Task 14: README, license and docs cleanup

**Files:**
- Create: `LICENSE`
- Rewrite: `README.md`
- Modify:
  - `docs/superpowers/spikes/2026-10-23-same-desktop.md`
  - `docs/superpowers/plans/2026-10-23-lil-brow-wow.md`
  - (both name the other project's certificate)
- Optional: `docs/images/little-window.png`

- [ ] **Step 1: Ask the owner for a screenshot**

Ask for a screenshot of a little window showing its title-bar buttons, saved to `docs/images/little-window.png`. If they'd rather not, the README goes without one.

- [ ] **Step 2: Write `LICENSE`**

MIT, `Copyright (c) 2026 Austin Dick`.

- [ ] **Step 3: Rewrite `README.md`**

Sections in this order:
- **Little Dia:** what it is, in two sentences, then the screenshot.
- **Install:** the one-line command, the requirements (macOS 14+, Dia; Apple silicon only if Task 12 fell back), what happens next.
- **Setup:** the four rows of the setup window, in plain words.
- **Using it:** Copy, Open in {profile}, the profile menu, focus returning, the size being remembered, the toggle, and that little windows only appear once Dia is running.
- **Updating:** Check for Updates.
- **Uninstall:** `curl -fsSL https://raw.githubusercontent.com/austindick/little-dia/main/install.sh | bash -s -- --uninstall`, plus the two follow-ups.
- **Troubleshooting:** Copy Diagnostics, then send it to Austin; the common fixes.
- **Known limitations:** carried from the current README and updated: full-screen apps, the brief draw-behind, buttons hiding during drags, Dia only.
- **How it works:** the diagram from the current README, renamed.
- **Development:**
  - build from source
  - make your own self-signed certificate and set `LITTLEDIA_SIGN_IDENTITY`
  - run the tests
  - `scripts/release.sh`
- **The not-affiliated line**, and **License**.

- [ ] **Step 4: Scrub machine-specific mentions**

- In both docs, replace the other project's certificate name with `a stable self-signed identity`.
- Run a case-insensitive `grep -rn` (excluding `.git`, `.build`, `build`, `.superpowers`) for the other certificate's name and the owner's employer.

Expected: no output.

- [ ] **Step 5: Check that every command in the README matches a real script or flag**

Run: `grep -oE "(install\.sh|scripts/[a-z-]+\.sh)[^\`]*" README.md | sort -u`
Expected: every script and flag listed exists. Read the output against `install.sh` and `scripts/`.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "docs: README for coworkers, MIT license, scrub machine-specific notes"
```

---

### Task 15: Merge, go public, release 1.0.0, verify the update path (owner go-ahead at each step)

**Files:**
- Modify: `Resources/Info.plist`, `Extension/manifest.json` (→ `1.0.1` in Step 6)

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: Run the full suites on `feat/sharing`, then finish the branch**

Use superpowers:finishing-a-development-branch: merge to `main` locally, rerun the tests on `main`, and `git push origin main`.

Run: `swift test 2>&1 | tail -3; node --test 'Extension/test/*' 2>&1 | tail -3; bash scripts/test-install.sh`
Expected: all green.

- [ ] **Step 2: Go public (owner go-ahead)**

Ask; on yes, run `gh repo edit austindick/little-dia --visibility public --accept-visibility-change-consequences`.
Expected: `gh repo view --json visibility` shows `PUBLIC`.

- [ ] **Step 3: Release 1.0.0 (owner go-ahead)**

Run: `scripts/release.sh`
Expected: `https://github.com/austindick/little-dia/releases/tag/v1.0.0` with `Little-Dia.zip` attached.

- [ ] **Step 4: Fresh install with the real command (owner)**

1. Run `bash install.sh --uninstall`, then remove the extension in Dia.
2. Run the one-line install command from the README.
3. Walk through the setup window.

Expected: all four rows behave as in Task 9, and the menu shows `All set · Work`.

- [ ] **Step 5: Full manual checklist (owner)**

Run the spec's checklist items 1, 2, 3 (every v1 behavior), 5 and 6. Item 6 means running uninstall and the one-liner again.

- [ ] **Step 6: Exercise the update path (owner go-ahead to publish 1.0.1)**

1. Bump both versions to `1.0.1` and commit `chore: 1.0.1`. Push, then run `scripts/release.sh`.
2. In the installed 1.0.0, choose *Check for Updates…*.

Expected:
- the menu offers `Update to 1.0.1…`
- clicking it relaunches into 1.0.1
- Accessibility is still granted (the buttons appear)
- the extension reloads itself to 1.0.1: Copy Diagnostics shows `Extension: 1.0.1`
- no developer-mode clicks were needed

- [ ] **Step 7: Optional fresh-account test**

This is the owner's call: create a test macOS user and run the one-liner there, to walk the coworker path from zero.

- [ ] **Step 8: Hand off**

Tell the owner it's ready to send to one coworker first, and give them the one-line command to paste.
