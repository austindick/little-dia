import Foundation
import Testing
@testable import LittleDiaCore

private func status(defaultBrowser: Bool = true, extensionState: ExtensionState = .connected, accessibility: Bool = true,
                    pinned: Bool = false, profile: String? = "Work") -> SetupStatus {
    SetupStatus(isDefaultBrowser: defaultBrowser, extensionState: extensionState, accessibilityGranted: accessibility,
                browserPinnedToDesktop: pinned, profile: profile)
}

@Test func allDoneIsAllSetWithProfile() {
    #expect(status().requiredDone)
    #expect(status().menuLine == .allSet(profile: "Work"))
    #expect(status().menuLine.text == "All set · Work")
    #expect(status(profile: nil).menuLine.text == "All set")
}

/// Review Focus 4: with Dia not running yet, the extension isn't connected, but it is installed; that must not pop
/// the setup window open on every launch.
@Test func installedButNotConnectedCountsAsDone() {
    let s = status(extensionState: .installed)
    #expect(s.requiredDone)
    #expect(s.menuLine == .allSet(profile: "Work"))
}

@Test func missingExtensionIsTheProblem() {
    let s = status(extensionState: .missing)
    #expect(!s.requiredDone)
    #expect(s.menuLine == .problem("Dia extension not connected"))
}

@Test func problemsAreReportedInOrder() {
    let s = status(defaultBrowser: false, extensionState: .missing, accessibility: false, pinned: true)
    #expect(s.menuLine == .problem("Not the default browser"))
    #expect(status(accessibility: false, pinned: true).menuLine == .problem("Title-bar buttons need Accessibility"))
}

@Test func pinnedIsAProblemButNotRequired() {
    let s = status(pinned: true)
    #expect(s.requiredDone)
    #expect(s.menuLine == .problem("Dia is pinned to one desktop"))
}

@MainActor @Test func firstLaunchFlagDefaultsFalseAndPersists() {
    let suite = "ld-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    #expect(!UserDefaultsSettings(defaults: defaults).hasLaunchedBefore)
    UserDefaultsSettings(defaults: defaults).hasLaunchedBefore = true
    #expect(UserDefaultsSettings(defaults: defaults).hasLaunchedBefore)
}
