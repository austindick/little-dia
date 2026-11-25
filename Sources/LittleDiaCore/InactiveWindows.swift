import Foundation

/// When each open little window was last in front, to tell which ones nobody has looked at for a while. A window
/// counts as looked at for as long as it stays in front, so its countdown starts when it leaves the front.
@MainActor
public final class InactiveWindows {
    private var lastActive: [Int: Date] = [:]
    private var inFront: Int?

    public init() {}

    public func noteOpened(_ id: Int, now: Date) {
        lastActive[id] = now
    }

    /// The window now in front (nil: none). Stamps the one leaving the front and the one arriving.
    public func noteInFront(_ id: Int?, now: Date) {
        if let previous = inFront, lastActive[previous] != nil { lastActive[previous] = now }
        if let id, lastActive[id] != nil { lastActive[id] = now }
        inFront = id
    }

    public func noteClosed(_ id: Int) {
        lastActive.removeValue(forKey: id)
        if inFront == id { inFront = nil }
    }

    /// The windows not in front for at least `interval`, oldest first. The window in front is never one of them.
    public func due(now: Date, after interval: TimeInterval) -> [Int] {
        lastActive.filter { $0.key != inFront && now.timeIntervalSince($0.value) >= interval }
            .sorted { ($0.value, $0.key) < ($1.value, $1.key) }
            .map(\.key)
    }
}
