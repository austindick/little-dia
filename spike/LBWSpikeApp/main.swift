// Throwaway spike app: receives lbwspike://<mode> the way Lil Brow Wow will receive links,
// then tries to bring the next new Dia popup to the front without switching desktops.
// Tries several ways to bring the popup to the front once it has finished animating open.
import AppKit
import ApplicationServices

let diaID = "company.thebrowser.dia"
let logURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("lil-brow-wow/spike/result.log")

func log(_ s: String) {
    let line = s + "\n"
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
    } else {
        try? Data(line.utf8).write(to: logURL)
    }
}

struct Win { let number: Int; let pid: pid_t; let layer: Int; let bounds: CGRect; let onscreen: Bool }

func allWindows() -> [Win] {
    let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
    return raw.compactMap { d in
        guard let n = d[kCGWindowNumber as String] as? Int, let pid = d[kCGWindowOwnerPID as String] as? pid_t,
              let layer = d[kCGWindowLayer as String] as? Int, let bd = d[kCGWindowBounds as String] as? NSDictionary,
              let b = CGRect(dictionaryRepresentation: bd) else { return nil }
        return Win(number: n, pid: pid, layer: layer, bounds: b, onscreen: d[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }
}

/// On-screen layer-0 window numbers, front to back.
func onScreenOrder() -> [Int] {
    let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    return raw.compactMap { d in (d[kCGWindowLayer as String] as? Int) == 0 ? d[kCGWindowNumber as String] as? Int : nil }
}

func looksLikeLittleWindow(_ r: CGRect) -> Bool { abs(r.width - 1000) <= 40 && r.height >= 710 && r.height <= 900 }

func axWindow(pid: pid_t, matching r: CGRect, tolerance: CGFloat = 4) -> AXUIElement? {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
          let wins = value as? [AXUIElement] else { return nil }
    return wins.first { frame(of: $0).map { abs($0.minX - r.minX) <= tolerance && abs($0.minY - r.minY) <= tolerance && abs($0.width - r.width) <= tolerance } ?? false }
}

func frame(of w: AXUIElement) -> CGRect? {
    var p: CFTypeRef?, s: CFTypeRef?
    guard AXUIElementCopyAttributeValue(w, kAXPositionAttribute as CFString, &p) == .success,
          AXUIElementCopyAttributeValue(w, kAXSizeAttribute as CFString, &s) == .success else { return nil }
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(p as! AXValue, .cgPoint, &pt); AXValueGetValue(s as! AXValue, .cgSize, &sz)
    return CGRect(origin: pt, size: sz)
}

func focusedWindowFrame(pid: pid_t) -> CGRect? {
    let app = AXUIElementCreateApplication(pid)
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success, let v = value else { return nil }
    return frame(of: v as! AXUIElement)
}

enum SkyLight {
    typealias SetFront = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UInt32, UInt32) -> Int32
    typealias PostEvent = @convention(c) (UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<UInt8>) -> Int32
    typealias GetPSN = @convention(c) (pid_t, UnsafeMutablePointer<ProcessSerialNumber>) -> Int32

    static func focus(pid: pid_t, windowID: UInt32) -> String {
        guard let sl = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let hi = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_LAZY),
              let f1 = dlsym(sl, "_SLPSSetFrontProcessWithOptions"),
              let f2 = dlsym(sl, "SLPSPostEventRecordTo"),
              let f3 = dlsym(hi, "GetProcessForPID") else { return "symbols unavailable" }
        let setFront = unsafeBitCast(f1, to: SetFront.self)
        let post = unsafeBitCast(f2, to: PostEvent.self)
        let getPSN = unsafeBitCast(f3, to: GetPSN.self)
        var psn = ProcessSerialNumber()
        guard getPSN(pid, &psn) == 0 else { return "GetProcessForPID failed" }
        let r1 = setFront(&psn, windowID, 0x200)  // kCPSUserGenerated
        var wid = windowID
        var bytes = [UInt8](repeating: 0, count: 0xf8)
        bytes[0x04] = 0xf8
        bytes[0x3a] = 0x10
        withUnsafeBytes(of: &wid) { raw in for i in 0..<4 { bytes[0x3c + i] = raw[i] } }
        for i in 0x20..<0x30 { bytes[i] = 0xff }
        bytes[0x08] = 0x01
        let r2 = post(&psn, &bytes)
        bytes[0x08] = 0x02
        let r3 = post(&psn, &bytes)
        return "setFront=\(r1) key1=\(r2) key2=\(r3)"
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    var timer: Timer?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        run(startAt: url.host ?? "m3")
    }

    // Mode "auto": wait for the popup to finish animating, then try activation methods in order
    // until the popup is frontmost on this desktop without a desktop switch.
    func run(startAt: String) {
        guard let dia = NSRunningApplication.runningApplications(withBundleIdentifier: diaID).first else {
            log("FAIL: Dia is not running"); NSApp.terminate(nil); return
        }
        let me = getpid()
        let start = Date()
        func t() -> String { String(format: "%5.1fs", Date().timeIntervalSince(start)) }

        log("==== start=\(startAt) at \(Date())")
        log("\(t())  received link: spike app active=\(NSApp.isActive) frontmost=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")")
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(opts) {
            log("FAIL: LBWSpike needs Accessibility access. Grant it in System Settings → Privacy & Security → Accessibility, then rerun.")
            NSApp.terminate(nil); return
        }

        let pid = dia.processIdentifier
        let existingDia = Set(allWindows().filter { $0.pid == pid }.map(\.number))
        let home = Set(allWindows().filter { $0.onscreen && $0.layer == 0 && $0.pid != pid && $0.pid != me }.map(\.number))
        log("\(t())  watching \(home.count) window(s) on this desktop")

        var switched = false
        var little: Win?
        var lastBounds: CGRect?
        var stableTicks = 0
        var lastFront = ""

        func check() -> (front: Bool, inFront: Bool) {
            let order = onScreenOrder()
            let inFront = little.map { w in
                (order.firstIndex(of: w.number) ?? Int.max) < (order.firstIndex { home.contains($0) } ?? Int.max)
            } ?? false
            return (NSWorkspace.shared.frontmostApplication?.processIdentifier == pid, inFront)
        }

        func finish(_ verdict: String) {
            log("\(t())  result: switched=\(switched) \(verdict)")
            NSApp.terminate(nil)
        }

        typealias Attempt = (name: String, run: (AXUIElement?, Win) -> Void)
        let attempts: [Attempt] = [
            ("M3 dia.activate() from background", { _, _ in
                log("\(t())    activate returned \(dia.activate())")
            }),
            ("M4 activate self, then dia.activate(from: self)", { _, _ in
                NSApp.activate()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    log("\(t())    spike app active=\(NSApp.isActive)")
                    log("\(t())    activate(from:) returned \(dia.activate(from: NSRunningApplication.current, options: []))")
                }
            }),
            ("M5 private SkyLight: front process with popup window + make key", { ax, w in
                let ok = SkyLight.focus(pid: pid, windowID: UInt32(w.number))
                if let ax { AXUIElementPerformAction(ax, kAXRaiseAction as CFString) }
                log("\(t())    SkyLight focus returned \(ok)")
            }),
        ]
        let startIndex = ["m3": 0, "m4": 1, "m5": 2][startAt] ?? 0

        func tryAttempt(_ i: Int) {
            guard i < attempts.count else { finish("FAIL: no method brought the popup to the front"); return }
            guard let w = little else { return }
            let ax = axWindow(pid: pid, matching: w.bounds, tolerance: 8)
            log("\(t())  trying \(attempts[i].name) (AX window found: \(ax != nil))")
            attempts[i].run(ax, w)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let c = check()
                log("\(t())    -> diaFrontmost=\(c.front) popupInFront=\(c.inFront) switched=\(switched)")
                if switched { finish("FAIL: \(attempts[i].name) switched desktops") }
                else if c.front && c.inFront { finish("PASS with \(attempts[i].name)") }
                else { tryAttempt(i + 1) }
            }
        }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            let wins = allWindows()
            let onscreenNumbers = Set(wins.filter(\.onscreen).map(\.number))
            if !home.isEmpty && home.isDisjoint(with: onscreenNumbers) && !switched {
                switched = true; log("\(t())  DESKTOP SWITCHED (home windows no longer visible)")
            }
            let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
            if front != lastFront { log("\(t())  frontmost: \(front)"); lastFront = front }

            if little == nil || stableTicks < 3 {
                if let w = wins.first(where: { $0.pid == pid && $0.layer == 0 && $0.onscreen
                                               && !existingDia.contains($0.number) && looksLikeLittleWindow($0.bounds) }) {
                    if little == nil { log("\(t())  popup appeared on this desktop: \(w.bounds)") }
                    little = w
                    stableTicks = (w.bounds == lastBounds) ? stableTicks + 1 : 0
                    lastBounds = w.bounds
                    if stableTicks == 3 {
                        log("\(t())  popup settled at \(w.bounds); before any action: diaFrontmost=\(check().front) popupInFront=\(check().inFront)")
                        self?.timer?.invalidate()
                        // Keep watching for desktop switches while attempts run.
                        self?.timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                            let on = Set(allWindows().filter(\.onscreen).map(\.number))
                            if !home.isEmpty && home.isDisjoint(with: on) && !switched {
                                switched = true; log("\(t())  DESKTOP SWITCHED (home windows no longer visible)")
                            }
                        }
                        tryAttempt(startIndex)
                    }
                }
            }
            if Date().timeIntervalSince(start) > 30 && little == nil { finish("FAIL: popup never appeared") }
        }
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
