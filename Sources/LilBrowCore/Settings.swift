import CoreGraphics
import Foundation

@MainActor
public protocol LittleSettings: AnyObject {
    var isEnabled: Bool { get }
    var littleWindowSize: CGSize { get }
    var browser: BrowserAdapter { get }
}

@MainActor
public final class UserDefaultsSettings: LittleSettings {
    private enum Key {
        static let enabled = "enabled"
        static let width = "littleWindowWidth"
        static let height = "littleWindowHeight"
        static let browser = "browserBundleID"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled: true,
            Key.width: 1000.0,
            Key.height: 750.0,
            Key.browser: BrowserAdapter.dia.bundleID,   // chosen by the 2026-10-23 same-desktop spike
        ])
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    public var littleWindowSize: CGSize {
        CGSize(width: defaults.double(forKey: Key.width), height: defaults.double(forKey: Key.height))
    }

    public var browser: BrowserAdapter {
        BrowserAdapter.forBundleID(defaults.string(forKey: Key.browser) ?? "") ?? .dia
    }

    /// Little windows open at the size the user last left one at. Bounds are the page area the extension reports.
    public func rememberSize(_ bounds: Bounds) {
        defaults.set(Double(bounds.width), forKey: Key.width)
        defaults.set(Double(bounds.height), forKey: Key.height)
    }
}
