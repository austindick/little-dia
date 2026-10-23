// Throwaway probe: does a new browser popup land on THIS desktop without switching away?
// Usage: swift spike/probe.swift <browserBundleID> [--raise]
import AppKit
import ApplicationServices

let args = CommandLine.arguments.dropFirst()
guard let bundleID = args.first else {
    print("usage: swift spike/probe.swift <browserBundleID> [--raise]")
    exit(2)
}
let shouldRaise = args.contains("--raise")

guard let browser = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
    print("FAIL: \(bundleID) is not running")
    exit(1)
}
let browserPID = browser.processIdentifier

if shouldRaise {
    let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(options) {
        print("This terminal app needs Accessibility access (System Settings → Privacy & Security → Accessibility). Grant it, then rerun.")
        exit(1)
    }
}

struct WindowInfo {
    let number: Int
    let pid: pid_t
    let layer: Int
    let bounds: CGRect
}

func windows(onScreenOnly: Bool) -> [WindowInfo] {
    let option: CGWindowListOption = onScreenOnly ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll]
    let raw = CGWindowListCopyWindowInfo(option, kCGNullWindowID) as? [[String: Any]] ?? []
    return raw.compactMap { d in
        guard let number = d[kCGWindowNumber as String] as? Int,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t,
              let layer = d[kCGWindowLayer as String] as? Int,
              let boundsDict = d[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDict) else { return nil }
        return WindowInfo(number: number, pid: pid, layer: layer, bounds: bounds)
    }
}

// Dia treats the requested size as the page area and adds ~72pt of its own title/address bar above it,
// so a 1000x750 request comes back as about 1000x822.
func looksLikeLittleWindow(_ r: CGRect) -> Bool {
    abs(r.width - 1000) <= 40 && r.height >= 710 && r.height <= 900
}

// Snapshot the browser's existing windows BEFORE the owner clicks the spike button.
let existingBrowserWindows = Set(windows(onScreenOnly: false).filter { $0.pid == browserPID }.map(\.number))

print("Probe ready for \(bundleID) (pid \(browserPID))\(shouldRaise ? " with --raise" : "").")
print("Now: go to the browser's desktop, click a spike button, come back here, and press Return.")
print("Press Return when you're back on this desktop")
_ = readLine()

guard let front = NSWorkspace.shared.frontmostApplication else {
    print("FAIL: no frontmost app")
    exit(1)
}
let homeWindows = Set(windows(onScreenOnly: true).filter { $0.pid == front.processIdentifier && $0.layer == 0 }.map(\.number))
if homeWindows.isEmpty {
    print("FAIL: frontmost app \(front.localizedName ?? "?") has no on-screen windows to watch")
    exit(1)
}
print("Watching \(front.localizedName ?? "?") (\(homeWindows.count) window(s)) for 25 s…")

func check() -> (appeared: WindowInfo?, switched: Bool) {
    let onScreen = windows(onScreenOnly: true)
    let onScreenNumbers = Set(onScreen.map(\.number))
    let appeared = onScreen.first {
        $0.pid == browserPID && $0.layer == 0 && !existingBrowserWindows.contains($0.number) && looksLikeLittleWindow($0.bounds)
    }
    let switched = homeWindows.isDisjoint(with: onScreenNumbers)
    return (appeared, switched)
}

func raise(_ target: WindowInfo) -> Bool {
    let app = AXUIElementCreateApplication(browserPID)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let axWindows = value as? [AXUIElement] else { return false }
    for w in axWindows {
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &sizeRef) == .success else { continue }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        let frame = CGRect(origin: pos, size: size)
        if abs(frame.minX - target.bounds.minX) <= 4, abs(frame.minY - target.bounds.minY) <= 4,
           abs(frame.width - target.bounds.width) <= 4, abs(frame.height - target.bounds.height) <= 4 {
            AXUIElementPerformAction(w, kAXRaiseAction as CFString)
            browser.activate()
            return true
        }
    }
    return false
}

// Diagnostic timeline: print every change in new windows, home-window visibility and frontmost app.
func timelineState() -> [String] {
    let all = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    var lines: [String] = []
    for d in all {
        guard let number = d[kCGWindowNumber as String] as? Int,
              let pid = d[kCGWindowOwnerPID as String] as? pid_t,
              let boundsDict = d[kCGWindowBounds as String] as? NSDictionary,
              let b = CGRect(dictionaryRepresentation: boundsDict) else { continue }
        let isNewBrowserWindow = pid == browserPID && !existingBrowserWindows.contains(number)
        let isNewBigWindow = pid != browserPID && b.width >= 600 && b.height >= 400 && !homeWindows.contains(number)
            && !initialAllWindows.contains(number)
        guard isNewBrowserWindow || isNewBigWindow else { continue }
        let owner = d[kCGWindowOwnerName as String] as? String ?? "?"
        let layer = d[kCGWindowLayer as String] as? Int ?? -1
        let onscreen = d[kCGWindowIsOnscreen as String] as? Bool ?? false
        lines.append("new window #\(number) owner=\(owner) layer=\(layer) \(Int(b.width))x\(Int(b.height)) at (\(Int(b.minX)),\(Int(b.minY))) onThisDesktop=\(onscreen)")
    }
    let onScreenNumbers = Set(windows(onScreenOnly: true).map(\.number))
    lines.append("home windows visible: \(homeWindows.intersection(onScreenNumbers).count)/\(homeWindows.count)")
    lines.append("frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
    return lines.sorted()
}
let initialAllWindows = Set(windows(onScreenOnly: false).map(\.number))

let start = Date()
let deadline = start.addingTimeInterval(25)
var lastState: [String] = []
var result = check()
while Date() < deadline {
    let state = timelineState()
    if state != lastState {
        let t = String(format: "%5.1fs", Date().timeIntervalSince(start))
        for line in state where !lastState.contains(line) { print("  \(t)  \(line)") }
        lastState = state
    }
    let now = check()
    if result.appeared == nil { result.appeared = now.appeared }
    result.switched = result.switched || now.switched
    Thread.sleep(forTimeInterval: 0.1)
}

// Let any late activation / desktop switch happen before judging.
Thread.sleep(forTimeInterval: 1.5)
let settled = check()
result = (settled.appeared ?? result.appeared, settled.switched)

if let w = result.appeared, shouldRaise, !result.switched {
    print("Window appeared at \(w.bounds) — raising it and activating the browser…")
    let raised = raise(w)
    print(raised ? "Raised." : "Could not find the window through Accessibility.")
    Thread.sleep(forTimeInterval: 1.0)
    result = check()
}

let appeared = result.appeared != nil
if let w = result.appeared {
    print("New browser window on this desktop: \(w.bounds)")
    // On-screen list is ordered front to back.
    let order = windows(onScreenOnly: true).filter { $0.layer == 0 }.map(\.number)
    if let wi = order.firstIndex(of: w.number) {
        let homeIndex = order.firstIndex { homeWindows.contains($0) } ?? Int.max
        print(wi < homeIndex ? "Little window is IN FRONT of \(front.localizedName ?? "home app")" : "Little window is BEHIND \(front.localizedName ?? "home app")")
    }
}
print("Frontmost app now: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
if appeared && !result.switched {
    print("PASS: little window on this desktop, no switch")
} else {
    print("FAIL: appeared=\(appeared) switched=\(result.switched)")
}
