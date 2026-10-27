import CoreGraphics

/// Whether a little window is moving, from readings of its frame taken about 60 times a second. Buttons drawn by
/// another app can't move in lockstep with the window, so they hide as soon as its frame starts changing (a drag, a
/// resize, or an animation such as zooming) and come back once the mouse is up and the frame has held still.
public struct WindowMotion: Sendable {
    public enum Event: Equatable, Sendable {
        case started
        /// `byHand`: the user moved or resized the window with the mouse, and it stopped when they let go. Zooms,
        /// snapping into a tile and Mission Control keep the window changing after the mouse is released.
        case ended(byHand: Bool)
    }

    /// How many readings in a row the frame must hold still, with the mouse up, before a motion is over (~100ms).
    public static let stillTicksToEnd = 6

    public private(set) var moving = false
    private var lastFrame: CGRect?
    private var stillTicks = 0
    private var changedWhileDown = false
    private var changedWhileUp = false
    /// Readings left to wait for an expected change before giving up on it.
    private var awaitingChange: Int?

    public init() {}

    /// The window is about to change before its frame shows it: a title-bar double-click zooms by animating a picture
    /// of the window, and the real frame jumps once, at the end. Counts it as moving now, for up to `ticks` readings
    /// until the frame changes. Does nothing if it's already moving.
    public mutating func expectChange(within ticks: Int) {
        guard !moving else { return }
        moving = true
        stillTicks = 0
        changedWhileDown = false
        changedWhileUp = true   // not a resize by hand
        awaitingChange = ticks
    }

    /// Takes one reading of the window's frame and whether the left mouse button is down.
    public mutating func tick(frame: CGRect, mouseDown: Bool) -> Event? {
        defer { lastFrame = frame }
        let changed = lastFrame.map { $0 != frame } ?? false
        if !moving {
            guard changed else { return nil }
            moving = true
            stillTicks = 0
            changedWhileDown = mouseDown
            changedWhileUp = !mouseDown
            return .started
        }
        if changed {
            awaitingChange = nil
            if mouseDown { changedWhileDown = true } else { changedWhileUp = true }
        }
        if let remaining = awaitingChange {
            guard remaining > 1 else {
                moving = false
                awaitingChange = nil
                return .ended(byHand: false)
            }
            awaitingChange = remaining - 1
            return nil
        }
        if changed || mouseDown {
            stillTicks = 0
            return nil
        }
        stillTicks += 1
        guard stillTicks >= Self.stillTicksToEnd else { return nil }
        moving = false
        return .ended(byHand: changedWhileDown && !changedWhileUp)
    }

    /// Forgets the window's frame, for when the buttons stop showing or move to another window.
    public mutating func reset() {
        self = WindowMotion()
    }
}
