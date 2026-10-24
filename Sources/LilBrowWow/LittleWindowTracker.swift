import AppKit
import ApplicationServices
import LilBrowCore
import os

struct TrackedWindow: Equatable {
    var windowId: Int
    /// Window frame in top-left coordinates (Accessibility / Chromium space).
    var frameTopLeft: CGRect
}

/// Finds little windows through the Accessibility API and follows them, reporting which one (if any) the title-bar
/// buttons belong on: the focused little window of the frontmost browser, on the current desktop.
@MainActor
final class LittleWindowTracker {
    private struct Entry {
        let element: AXUIElement
        var frame: CGRect
        /// The window server's number for this window, used to follow it live during drags.
        var windowNumber: CGWindowID?
        /// Height of the page area (the window minus the browser's title bar and address row).
        var pageHeight: CGFloat
    }

    private let onChange: (TrackedWindow?) -> Void
    private let onResize: (Int, Bounds) -> Void
    private let logger = Logger(subsystem: "com.lilbrowwow", category: "tracker")
    private var entries: [Int: Entry] = [:]
    private var browserPID: pid_t?
    private var observer: AXObserver?
    private var lastReported: TrackedWindow?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var followTimer: Timer?
    private var mouseWasDown = false
    /// The shown window is being dragged or resized: its buttons are hidden until the mouse is released.
    private var dragging = false
    /// The shown window as it was when the drag began, to tell a resize from a move.
    private var dragStart: TrackedWindow?

    /// - Parameter onResize: called with the new page-area bounds when the user finishes resizing a little window.
    init(onChange: @escaping (TrackedWindow?) -> Void, onResize: @escaping (Int, Bounds) -> Void) {
        self.onChange = onChange
        self.onResize = onResize
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.recompute() }
            })
        }
        workspaceObservers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, pid == self.browserPID else { return }
                self.entries.removeAll()
                self.observer = nil
                self.browserPID = nil
                self.recompute()
            }
        })
    }

    /// Finds the browser window created for `bounds` (polling while it animates open) and starts following it.
    func track(windowId: Int, bounds: Bounds, browserPID pid: pid_t) async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        if pid != browserPID { startObserving(pid) }
        let appElement = AXUIElementCreateApplication(pid)
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while clock.now < deadline {
            let windows = axWindows(of: appElement)
            let taken = Set(windows.indices.filter { i in entries.values.contains { CFEqual($0.element, windows[i]) } })
            let candidates = windows.indices.compactMap { i in frame(of: windows[i]).map { WindowCandidate(id: i, frame: $0) } }
            if let index = matchLittleWindow(candidates, bounds: bounds, excluding: taken), let frame = frame(of: windows[index]) {
                let element = windows[index]
                entries[windowId] = Entry(element: element, frame: frame, pageHeight: CGFloat(bounds.height))
                if let observer {
                    let refcon = Unmanaged.passUnretained(self).toOpaque()
                    for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                        AXObserverAddNotification(observer, element, notification as CFString, refcon)
                    }
                }
                logger.notice("tracking little window \(windowId) at \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))")
                recompute()
                // The window is still animating open and the browser is still taking focus: look again shortly.
                Task { @MainActor [weak self] in
                    for delay in [150, 400, 800] as [Int] {
                        try? await Task.sleep(for: .milliseconds(delay))
                        self?.recompute()
                    }
                }
                return true
            }
            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.error("could not find little window \(windowId) through Accessibility")
        return false
    }

    func untrack(windowId: Int) {
        guard let entry = entries.removeValue(forKey: windowId) else { return }
        if let observer {
            for notification in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverRemoveNotification(observer, entry.element, notification as CFString)
            }
        }
        recompute()
    }

    /// Presses the window's close button, exactly as clicking it would. False if the window isn't tracked or has none.
    func close(windowId: Int) -> Bool {
        guard let element = entries[windowId]?.element else { return false }
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
              let button, CFGetTypeID(button) == AXUIElementGetTypeID() else { return false }
        return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
    }

    // MARK: Accessibility plumbing

    private func startObserving(_ pid: pid_t) {
        entries.removeAll()
        browserPID = pid
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, notification, refcon in
            guard let refcon else { return }
            let tracker = Unmanaged<LittleWindowTracker>.fromOpaque(refcon).takeUnretainedValue()
            MainActor.assumeIsolated { tracker.handle(notification as String, element: element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            logger.error("could not observe browser \(pid)")
            observer = nil
            return
        }
        observer = created
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        AXObserverAddNotification(created, AXUIElementCreateApplication(pid), kAXFocusedWindowChangedNotification as CFString, refcon)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
    }

    private func handle(_ notification: String, element: AXUIElement) {
        switch notification {
        case kAXUIElementDestroyedNotification:
            if let id = entries.first(where: { CFEqual($0.value.element, element) })?.key { untrack(windowId: id) }
        case kAXMovedNotification, kAXResizedNotification:
            if let id = entries.first(where: { CFEqual($0.value.element, element) })?.key, let frame = frame(of: element) {
                entries[id]?.frame = frame
            }
            recompute()
        default:
            recompute()
        }
    }

    private func recompute() {
        if dragging { return }   // stay hidden until the drag ends
        var visible: TrackedWindow?
        if let pid = browserPID {
            let focusedID = focusedWindow(of: pid).flatMap { focused in entries.first { CFEqual($0.value.element, focused) }?.key }
            if let id = OverlayVisibility.windowToShow(frontmostPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
                                                       browserPID: pid, focusedWindow: focusedID, tracked: Set(entries.keys)),
               let entry = entries[id],
               let number = entry.windowNumber ?? onThisDesktop(frame(of: entry.element) ?? entry.frame, pid: pid),
               let server = serverInfo(of: number), server.onScreen {
                // The window server's frame is live; Accessibility's can be stale mid-drag.
                entries[id]?.frame = server.frame
                entries[id]?.windowNumber = number
                visible = TrackedWindow(windowId: id, frameTopLeft: server.frame)
            }
        }
        report(visible)
    }

    private func report(_ visible: TrackedWindow?) {
        if visible == nil { stopFollowing() } else { startFollowing() }
        guard visible != lastReported else { return }
        lastReported = visible
        onChange(visible)
    }

    // MARK: Hiding during drags
    // Buttons drawn by another app can't move in lockstep with the window, so they hide while the window is being
    // dragged or resized and come back where it ends up. The window server reports the window's frame live; check it
    // every frame while the buttons are showing and the mouse is held down.

    private func startFollowing() {
        guard followTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.followTick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
    }

    private func stopFollowing() {
        followTimer?.invalidate()
        followTimer = nil
        mouseWasDown = false
    }

    private func followTick() {
        let mouseDown = NSEvent.pressedMouseButtons & 1 == 1
        defer { mouseWasDown = mouseDown }
        if !mouseDown {
            if dragging {
                dragging = false
                noteResize()
                lastReported = nil
                recompute()   // reappear where the window ended up
            }
            return
        }
        guard !dragging, let shown = lastReported, let number = entries[shown.windowId]?.windowNumber,
              let frame = serverInfo(of: number)?.frame, frame != shown.frameTopLeft else { return }
        dragging = true
        dragStart = shown
        onChange(nil)
    }

    /// If the drag that just ended changed the window's size, report the new page area.
    private func noteResize() {
        guard let start = dragStart, let entry = entries[start.windowId], let number = entry.windowNumber,
              let end = serverInfo(of: number)?.frame else { return }
        dragStart = nil
        guard abs(end.width - start.frameTopLeft.width) > 1 || abs(end.height - start.frameTopLeft.height) > 1 else { return }
        let chromeHeight = max(0, start.frameTopLeft.height - entry.pageHeight)
        let page = ScreenGeometry.pageBounds(ofWindow: end, chromeHeight: chromeHeight)
        entries[start.windowId]?.pageHeight = CGFloat(page.height)
        onResize(start.windowId, page)
    }

    private func serverInfo(of number: CGWindowID) -> (frame: CGRect, onScreen: Bool)? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], number) as? [[String: Any]])?.first,
              let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
              let frame = CGRect(dictionaryRepresentation: boundsInfo) else { return nil }
        return (frame, info[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }

    private func axWindows(of app: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private func focusedWindow(of pid: pid_t) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }

    /// Accessibility can't say which desktop a window is on; the window server's on-screen list can. Returns the
    /// window server's number for the window if it is on this desktop. Loose match: the window may still be animating.
    private func onThisDesktop(_ frame: CGRect, pid: pid_t) -> CGWindowID? {
        let raw = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in raw {
            guard (info[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  let number = info[kCGWindowNumber as String] as? Int,
                  let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsInfo) else { continue }
            if abs(bounds.minX - frame.minX) <= 12 && abs(bounds.maxY - frame.maxY) <= 12 && abs(bounds.width - frame.width) <= 24 {
                return CGWindowID(number)
            }
        }
        return nil
    }
}
