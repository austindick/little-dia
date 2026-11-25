# Site icons in the Recent list Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Each row of the ⌃⇧⌘N box's Recent list shows its site's icon, read from Dia's own icon store.

**Architecture:**
- When the box opens, the app asks every connected extension (one per Dia profile) for icons of the Recent pages whose
  site has none cached yet.
- Each extension reads Dia's favicon store through `chrome-extension://<id>/_favicon/` and replies with base64 PNGs, so
  no icon ever comes from the network.
- The app caches one PNG per host in Application Support. The box draws it, or a grey globe when there's none.

**Tech Stack:**
- Swift 6 with AppKit and Swift Testing.
- A Chrome MV3 extension (plain JS) tested with `node --test`.

**Spec:** `docs/superpowers/specs/2026-11-25-recent-site-icons-design.md`

## Global Constraints
- No network requests for icons, and no third-party favicon services.
- Icons are stored only on this Mac. *Clear Recent Pages* deletes them.
- Row: a 16pt icon with slightly rounded corners (radius 3) left of the title. With no icon, the SF Symbol `globe` in
  `tertiaryLabelColor`, at the same spot and size.
- Run `swift test`, `swift build` and `scripts/build-app.sh --install` as plain commands, never chained or piped (the
  sandbox breaks them otherwise).
- For test builds, `Extension/manifest.json` is `1.2.1.1`, so Dia reloads it. `appAndExtensionVersionsMatch` fails
  until release. At release both versions become 1.2.2 (Info.plist build 14), with the owner's go-ahead.
- Before committing, `git config user.email` must be `5875295+austindick@users.noreply.github.com`.

## Review Focus
1. **Dia's default icon.** For a page it has no icon for, `_favicon` returns Dia's generic globe instead of an error.
   Caching that as a site icon would hide the app's own placeholder and stop the site being asked again. Pinned in
   Task 2 (`knownIcons`).
2. **Odd hosts.** IP addresses, ports, `localhost`, uppercase hosts, and a URL with no host must never produce a bad
   or escaping file name. Pinned in Task 3 (`iconFileName`).
3. **Bad data.** Non-PNG data, invalid base64, or a huge payload from the extension must be dropped, not cached.
   Pinned in Task 3.
4. **Sites with no icon.** Opening the box again and again must not ask again for hosts already asked this launch.
   *Clear Recent Pages* resets that. Pinned in Task 3.
5. **No extension connected.** The box opens and shows globes, and nothing errors. Checked manually in Task 4.

---

### Task 1: Spike — does Dia serve `_favicon` to extensions?

Throwaway. Nothing from this task is committed.

**Files:**
- Modify (temporarily): `Extension/manifest.json`, `Extension/background.js`

- [ ] **Step 1: Add the permission and a probe.**
  - Add `"favicon"` to `permissions` in the manifest and set `"version": "1.2.1.1"`.
  - In `background.js`, after the extension posts `hello`, fetch
    `chrome.runtime.getURL("/_favicon/?pageUrl=" + encodeURIComponent("https://github.com/") + "&size=32")` and post
    `{type: "log", message: "favicon probe: <status> <content-type> <byteLength>"}`. Do the same for
    `https://no-such-site.invalid/`.
- [ ] **Step 2: Build and install.** Run `scripts/build-app.sh --install`. Dia reloads the extension; if it doesn't,
  the owner quits and reopens Dia.
- [ ] **Step 3: Read the probe.** Run `/usr/bin/log show --last 5m --predicate 'subsystem == "com.austindick.littledia"'`
  and grep for `favicon probe`.
  - **Expected:** status 200, `image/png`, and different byte lengths for github.com and the unknown site.
  - **If it isn't:** stop and tell the owner. The fallback (approach 2 in the spec, fetching `tab.favIconUrl`) needs a
    new plan.
- [ ] **Step 4: Revert the probe.** Run `git checkout Extension/background.js`. Keep the manifest change: Task 2 needs
  it.

### Task 2: Extension answers `favicons` requests

**Files:**
- Modify: `Extension/manifest.json` (keep `"favicon"` and `1.2.1.1` from Task 1)
- Modify: `Extension/bridge-logic.js`
- Modify: `Extension/background.js` (`handleAppMessage`)
- Test: `Extension/test/bridge-logic.test.mjs`

**Interfaces:**
- Consumes: the app message `{type: "favicons", pageURLs: [String]}`.
- Produces: the reply `{type: "favicons", icons: {[pageURL]: base64PNG}}`, containing only pages Dia has a real icon
  for. The reply is posted even when it's empty.

- [ ] **Step 1: Write the failing tests.**
  ```js
  test("faviconPath asks Dia's icon store for a page at 32px", () => {
    assert.equal(faviconPath("https://a.example/x?y=1"), "/_favicon/?pageUrl=https%3A%2F%2Fa.example%2Fx%3Fy%3D1&size=32");
  });
  test("knownIcons drops Dia's default icon and failed lookups", () => {
    assert.deepEqual(knownIcons({ "https://a/": "AAA", "https://b/": "DEF", "https://c/": null }, "DEF"), { "https://a/": "AAA" });
  });
  ```
- [ ] **Step 2: Run the tests.** Run `node --test 'Extension/test/*'`. Expected: they FAIL, because `faviconPath` and
  `knownIcons` aren't exported.
- [ ] **Step 3: Implement the two functions in `bridge-logic.js`.**
  - `export function faviconPath(pageUrl)`
  - `export function knownIcons(found, defaultIcon)`
- [ ] **Step 4: Handle `case "favicons"` in `handleAppMessage`.**
  - For each URL in `msg.pageURLs`, fetch `chrome.runtime.getURL(faviconPath(url))`. Convert a 200 response to base64
    (`arrayBuffer` → `btoa` over bytes); anything else becomes `null`.
  - Look up the default icon once per service-worker life the same way, with `https://no-such-site.invalid/`.
  - Post `{type: "favicons", icons: knownIcons(found, defaultIcon)}`.
- [ ] **Step 5: Run the tests.** Run `node --test 'Extension/test/*'`. Expected: all PASS.
- [ ] **Step 6: Commit.** `feat(extension): answer favicons requests from Dia's icon store`

### Task 3: Messages and the icon cache (core)

**Files:**
- Modify: `Sources/LittleDiaCore/Messages.swift`
- Create: `Sources/LittleDiaCore/SiteIcons.swift`
- Test: `Tests/LittleDiaCoreTests/MessagesTests.swift`
- Test (create): `Tests/LittleDiaCoreTests/SiteIconsTests.swift`

**Interfaces:**
- Produces:
  - `OutboundMessage.favicons(pageURLs: [String])`
  - `InboundMessage.favicons(icons: [String: String])`. Both use the wire keys `pageURLs` and `icons`, added to `Key`.
  - `@MainActor public final class SiteIcons` with:
    - `init(directory: URL)`
    - `func pngData(forPage url: String) -> Data?`
    - `func toAsk(for entries: [RecentPages.Entry]) -> [String]`: the page URLs to request. There's one per host that
      has no cached icon and hasn't been asked this launch, and the hosts returned are marked as asked.
    - `func store(_ icons: [String: String]) -> Bool`: true if anything new was written.
    - `func clear()`
  - `static func iconFileName(forPage url: String) -> String?`

- [ ] **Step 1: Write the failing tests.**
  - `MessagesTests`:
    - `encodesFaviconsRequestExactly`: `{"pageURLs":["https://a.example/"],"type":"favicons"}`, using the same
      sorted-keys comparison as the other "Exactly" tests.
    - `decodesFavicons`: `{"type":"favicons","icons":{"https://a.example/":"iVBO"}}` decodes to
      `.favicons(icons: ["https://a.example/": "iVBO"])`.
  - `SiteIconsTests` (each in a fresh folder under `FileManager.default.temporaryDirectory`; `png` is the 8-byte PNG
    signature plus a few bytes, base64-encoded):
    - `iconsAreKeptPerSite`: after storing for `https://Docs.Example.com/a`, `pngData(forPage: "https://docs.example.com/b")`
      returns the same bytes, and a new `SiteIcons` on the same folder still has them.
    - `fileNamesAreSafe`:
      - `iconFileName(forPage: "https://Docs.Example.com:8443/x") == "docs.example.com_8443.png"`
      - `"http://127.0.0.1/" → "127.0.0.1.png"`
      - `"http://localhost:3000/" → "localhost_3000.png"`
      - `"about:blank" → nil`
      - `"https://a/../../x" → "a.png"`
      - nothing returned ever contains `/`.
    - `badDataIsNotKept`: `store` with invalid base64, with base64 of non-PNG bytes, and with PNG over 256 KB each
      returns false, and `pngData` is nil.
    - `eachSiteIsAskedOncePerLaunch`: with entries for `a.example/1`, `a.example/2` and `b.example/1`, `toAsk`
      returns 2 URLs (one per host) the first time and `[]` the second. After `store` for a, a new `SiteIcons` asks
      only for b.
    - `clearForgetsIconsAndAsksAgain`: after `clear()`, `pngData` is nil, the folder has no `.png` files, and `toAsk`
      returns both hosts again.
- [ ] **Step 2: Run the tests.** Run `swift test`. Expected: compile FAIL on the missing cases and type.
- [ ] **Step 3: Implement the message cases** in `Messages.swift`, following the existing `case` / `encode` / `decode`
  pattern.
- [ ] **Step 4: Implement `SiteIcons.swift`.**
  - **File names:** the host is lowercased, `:port` becomes `_port`, and only `[a-z0-9.-]` is allowed. Anything else,
    or no host, gives nil.
  - **Writes:** atomic.
  - **The "asked" set:** in memory only.
  - **Size limit:** 256 KB.
  - **PNG check:** the data must start with bytes `89 50 4E 47 0D 0A 1A 0A`.
- [ ] **Step 5: Run the tests.** Run `swift test`. Expected: all PASS except `appAndExtensionVersionsMatch`, which is
  expected to fail on the test version.
- [ ] **Step 6: Commit.** `feat: Recent page icon cache and favicons messages`

### Task 4: Ask, store and draw (app)

**Files:**
- Modify: `Sources/LittleDia/AppDelegate.swift`. Changes:
  - a `siteIcons` property;
  - `addressBox.show` at line ~254;
  - `handle` (~line 279);
  - `clearRecentPages` (~line 201);
  - the `describe` line for logging (~line 582).
- Modify: `Sources/LittleDia/AddressBox.swift`. Changes: `show(recent:…)` at line ~255, and `RecentCell` at
  line ~736.

**Interfaces:**
- Consumes: from Task 3, `SiteIcons` and `.favicons` in both directions.
- Produces:
  - `AddressBox.show(recent: RecentPages, icon: @escaping (String) -> NSImage?, onSubmit:)`
  - `AddressBox.iconsChanged()`, which reloads the visible rows' icons and keeps the selection.

- [ ] **Step 1: Wire up `AppDelegate`.**
  - `siteIcons = SiteIcons(directory: <Application Support>/Little Dia/Site Icons)`.
  - **Opening the box:** pass `icon: { [siteIcons] in siteIcons.pngData(forPage: $0).flatMap(NSImage.init(data:)) }`.
    Then, if `siteIcons.toAsk(for: recentPages.entries)` isn't empty, send `.favicons(pageURLs:)` to every
    `server.readyConnections(for: settings.browser.bundleID)`.
  - **On `.favicons(icons)`:** `if siteIcons.store(icons) { addressBox.iconsChanged() }`. Log only the count, never URLs.
  - **On Clear Recent Pages:** also call `siteIcons.clear()`.
- [ ] **Step 2: Add the icon to `RecentCell`.**
  - **Image view:** an `NSImageView` 16×16 at `textInset` from the leading edge, centred vertically, with
    `wantsLayer`, `layer.cornerRadius = 3` and `masksToBounds`.
  - **Title:** its leading edge moves to the icon's trailing edge + 8.
  - **Drawing:** `show(_:now:icon:)` sets the site image, or `NSImage(systemSymbolName: "globe", …)` with
    `contentTintColor = .tertiaryLabelColor`. Clear the tint when it's a site image.
- [ ] **Step 3: Build and install.** Run `swift build`, then `scripts/build-app.sh --install`.
- [ ] **Step 4: Check it by hand.**
  - Open a couple of little windows, then press ⌃⇧⌘N and choose *Show recent*. Pages from before the change also get
    icons, possibly a moment after the list first appears.
  - A site with no icon shows the grey globe.
  - Light mode and dark mode both look right.
  - *Clear Recent Pages* empties `~/Library/Application Support/Little Dia/Site Icons`.
  - With Dia quit, the box still opens and shows globes, and the log has no errors.
- [ ] **Step 5: Commit.** `feat: site icons in the Recent list`, after the owner has looked at it.
