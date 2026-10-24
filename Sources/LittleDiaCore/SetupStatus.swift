import Foundation

/// Whether the browser has the extension: talking to the app right now; installed in a profile while the browser
/// isn't running (so it can't connect); or missing, which includes the browser running without it connecting
/// (not added, disabled, or broken).
public enum ExtensionState: Equatable, Sendable {
    case connected, installed, missing
}

/// The menu's one status line.
public enum MenuLine: Equatable, Sendable {
    case allSet(profile: String?)
    case problem(String)

    public var text: String {
        switch self {
        case let .allSet(profile?): return "All set · \(profile)"
        case .allSet(nil): return "All set"
        case let .problem(text): return text
        }
    }
}

/// Everything the setup window and the menu's status line report.
public struct SetupStatus: Equatable, Sendable {
    public var isDefaultBrowser: Bool
    public var extensionState: ExtensionState
    public var accessibilityGranted: Bool
    public var browserPinnedToDesktop: Bool
    /// The browser profile the extension is in.
    public var profile: String?

    public init(isDefaultBrowser: Bool, extensionState: ExtensionState, accessibilityGranted: Bool,
                browserPinnedToDesktop: Bool, profile: String?) {
        self.isDefaultBrowser = isDefaultBrowser
        self.extensionState = extensionState
        self.accessibilityGranted = accessibilityGranted
        self.browserPinnedToDesktop = browserPinnedToDesktop
        self.profile = profile
    }

    /// Nothing done; a placeholder before the app can check.
    public static let unknown = SetupStatus(isDefaultBrowser: false, extensionState: .missing, accessibilityGranted: false,
                                            browserPinnedToDesktop: false, profile: nil)

    /// The steps the setup window must see done. Being pinned to a desktop is a warning, not a step.
    public var requiredDone: Bool {
        isDefaultBrowser && extensionState != .missing && accessibilityGranted
    }

    public var menuLine: MenuLine {
        if !isDefaultBrowser { return .problem("Not the default browser") }
        if extensionState == .missing { return .problem("Dia extension not connected") }
        if !accessibilityGranted { return .problem("Title-bar buttons need Accessibility") }
        if browserPinnedToDesktop { return .problem("Dia is pinned to one desktop") }
        return .allSet(profile: profile)
    }
}
