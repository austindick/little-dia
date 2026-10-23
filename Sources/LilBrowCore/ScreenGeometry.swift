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

    /// Centers a window of `size` (clamped to the minimum and to the visible frame minus margins) on `screen`,
    /// returned in top-left coordinates.
    public static func littleWindowBounds(size: CGSize, on screen: ScreenContext) -> Bounds {
        let visible = screen.visibleFrame
        let width = min(max(size.width, minimumSize.width), visible.width - 2 * screenMargin)
        let height = min(max(size.height, minimumSize.height), visible.height - 2 * screenMargin)
        let x = visible.minX + (visible.width - width) / 2
        let y = visible.minY + (visible.height - height) / 2
        return Bounds(left: Int(x.rounded(.down)),
                      top: Int((screen.primaryScreenHeight - (y + height)).rounded(.down)),
                      width: Int(width), height: Int(height))
    }

    public static func appKitRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Where the title-bar buttons sit: right-aligned and vertically centered in the window's title bar (top-left coordinates).
    public static func overlayFrame(windowTopLeft: CGRect, overlaySize: CGSize, titleBarHeight: CGFloat, rightInset: CGFloat) -> CGRect {
        CGRect(x: windowTopLeft.maxX - rightInset - overlaySize.width,
               y: windowTopLeft.minY + (titleBarHeight - overlaySize.height) / 2,
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
/// page area, so only the left, right and bottom edges are compared.
public func matchLittleWindow<ID: Hashable>(_ candidates: [WindowCandidate<ID>], bounds: Bounds, excluding: Set<ID>, tolerance: CGFloat = 6) -> ID? {
    let left = CGFloat(bounds.left)
    let right = CGFloat(bounds.left + bounds.width)
    let bottom = CGFloat(bounds.top + bounds.height)
    var best: (id: ID, score: CGFloat)?
    for candidate in candidates where !excluding.contains(candidate.id) {
        let deltas = [abs(candidate.frame.minX - left), abs(candidate.frame.maxX - right), abs(candidate.frame.maxY - bottom)]
        guard deltas.allSatisfy({ $0 <= tolerance }) else { continue }
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
