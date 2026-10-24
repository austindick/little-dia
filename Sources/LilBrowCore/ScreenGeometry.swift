import CoreGraphics

/// The screen a little window should open on.
public struct ScreenContext: Equatable, Sendable {
    /// The screen's visible frame (minus menu bar and Dock) in AppKit coordinates (bottom-left origin).
    public var visibleFrame: CGRect
    /// Height of the primary screen, used to flip between AppKit and top-left (Chromium / Accessibility) coordinates.
    public var primaryScreenHeight: CGFloat

    public init(visibleFrame: CGRect, primaryScreenHeight: CGFloat) {
        self.visibleFrame = visibleFrame
        self.primaryScreenHeight = primaryScreenHeight
    }
}

public enum ScreenGeometry {
    public static let screenMargin: CGFloat = 40
    public static let minimumSize = CGSize(width: 480, height: 360)

    /// Centers a little window on `screen` and returns its page area in top-left coordinates. `size` is the page area
    /// (clamped to the minimum); `chromeHeight` is what the browser adds above it (Dia: its title bar and address row).
    /// The whole window, chrome included, is centered and kept inside the visible frame minus margins.
    public static func littleWindowBounds(size: CGSize, on screen: ScreenContext, chromeHeight: CGFloat = 0) -> Bounds {
        let visible = screen.visibleFrame
        let width = min(max(size.width, minimumSize.width), visible.width - 2 * screenMargin)
        let pageHeight = min(max(size.height, minimumSize.height), visible.height - 2 * screenMargin - chromeHeight)
        let windowHeight = pageHeight + chromeHeight
        let x = visible.minX + (visible.width - width) / 2
        let y = visible.minY + (visible.height - windowHeight) / 2
        let windowTop = screen.primaryScreenHeight - (y + windowHeight)
        return Bounds(left: Int(x.rounded(.down)), top: Int((windowTop + chromeHeight).rounded(.down)),
                      width: Int(width), height: Int(pageHeight))
    }

    /// The page area of a browser window whose title bar and address row (`chromeHeight`) sit above it.
    public static func pageBounds(ofWindow frame: CGRect, chromeHeight: CGFloat) -> Bounds {
        Bounds(left: Int(frame.minX), top: Int(frame.minY + chromeHeight),
               width: Int(frame.width), height: Int(frame.height - chromeHeight))
    }

    public static func appKitRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where the title-bar buttons sit: in the window's top-right corner, `inset` from both the top and the right edge
    /// (top-left coordinates).
    public static func overlayFrame(windowTopLeft: CGRect, overlaySize: CGSize, inset: CGFloat) -> CGRect {
        CGRect(x: windowTopLeft.maxX - inset - overlaySize.width, y: windowTopLeft.minY + inset,
               width: overlaySize.width, height: overlaySize.height)
    }
}

public struct WindowCandidate<ID: Hashable>: Equatable {
    public var id: ID
    /// Window frame in top-left coordinates.
    public var frame: CGRect

    public init(id: ID, frame: CGRect) {
        self.id = id
        self.frame = frame
    }
}

/// Finds the window the browser created for `bounds`. Dia adds its title bar and address row *above* the requested
/// page area, so only the left, right and bottom edges are compared. When several windows match, `preferring` (the
/// browser's focused window, which a new popup always is) wins.
public func matchLittleWindow<ID: Hashable>(_ candidates: [WindowCandidate<ID>], bounds: Bounds, excluding: Set<ID>,
                                            tolerance: CGFloat = 6, preferring: ID? = nil) -> ID? {
    let left = CGFloat(bounds.left)
    let right = CGFloat(bounds.left + bounds.width)
    let bottom = CGFloat(bounds.top + bounds.height)
    var best: (id: ID, score: CGFloat)?
    for candidate in candidates where !excluding.contains(candidate.id) {
        let deltas = [abs(candidate.frame.minX - left), abs(candidate.frame.maxX - right), abs(candidate.frame.maxY - bottom)]
        guard deltas.allSatisfy({ $0 <= tolerance }) else { continue }
        if candidate.id == preferring { return candidate.id }
        let score = deltas.reduce(0, +)
        if best == nil || score < best!.score {
            best = (candidate.id, score)
        }
    }
    return best?.id
}

public enum OverlayVisibility {
    /// The tracked window the title-bar buttons belong on right now, if any.
    public static func windowToShow<ID: Hashable>(frontmostPID: pid_t?, browserPID: pid_t?, focusedWindow: ID?, tracked: Set<ID>) -> ID? {
        guard let browserPID, frontmostPID == browserPID, let focusedWindow, tracked.contains(focusedWindow) else { return nil }
        return focusedWindow
    }
}
