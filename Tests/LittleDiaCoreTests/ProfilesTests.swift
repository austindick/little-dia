import Foundation
import Testing
@testable import LittleDiaCore

private func makeUserData(profiles: [String: String], extensionIn: [String]) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cache = profiles.mapValues { ["name": $0] }
    try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache]]).write(to: dir.appendingPathComponent("Local State"))
    for folder in profiles.keys {
        let profileDir = dir.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let installed = extensionIn.contains(folder) ? #"{"extensions":{"settings":{"\#(ExtensionIdentity.chromiumID)":{}}}}"# : #"{"extensions":{"settings":{}}}"#
        try Data(installed.utf8).write(to: profileDir.appendingPathComponent("Preferences"))
    }
    return dir
}

/// Writes `token` where Chromium keeps the extension's `chrome.storage.local` in that profile.
private func storeToken(_ token: String, in folder: String, of dir: URL) throws {
    let storage = dir.appendingPathComponent(folder).appendingPathComponent("Local Extension Settings")
        .appendingPathComponent(ExtensionIdentity.chromiumID)
    try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    try Data("\u{1}\u{2}profileToken\u{4}\"\(token)\"".utf8).write(to: storage.appendingPathComponent("000003.log"))
}

@Test func readsTheProfileNamesAndWhichOneHasTheExtension() throws {
    let dir = try makeUserData(profiles: ["Profile 2": "Personal", "Profile 3": "Work"], extensionIn: ["Profile 3"])
    defer { try? FileManager.default.removeItem(at: dir) }
    let profiles = BrowserProfiles.load(userDataDirectory: dir)
    #expect(profiles?.current == "Work")
    #expect(profiles?.others == ["Personal"])
    #expect(profiles?.withExtension == ["Work"])
}

@Test func aSingleProfileHasNoOthers() throws {
    let dir = try makeUserData(profiles: ["Default": "Me"], extensionIn: ["Default"])
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(BrowserProfiles.load(userDataDirectory: dir)?.others == [])
}

@Test func listsEveryProfileWithTheExtension() throws {
    let dir = try makeUserData(profiles: ["Profile 2": "Personal", "Profile 3": "Work", "Profile 4": "Side"],
                               extensionIn: ["Profile 2", "Profile 3"])
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(BrowserProfiles.load(userDataDirectory: dir)?.withExtension == ["Personal", "Work"])
}

@Test func findsTheProfileAnExtensionTokenIsStoredIn() throws {
    let dir = try makeUserData(profiles: ["Profile 2": "Personal", "Profile 3": "Work"], extensionIn: ["Profile 2", "Profile 3"])
    defer { try? FileManager.default.removeItem(at: dir) }
    try storeToken("9B1D-personal", in: "Profile 2", of: dir)
    try storeToken("C3A0-work", in: "Profile 3", of: dir)
    #expect(BrowserProfiles.profile(holdingToken: "C3A0-work", userDataDirectory: dir) == "Work")
    #expect(BrowserProfiles.profile(holdingToken: "9B1D-personal", userDataDirectory: dir) == "Personal")
    #expect(BrowserProfiles.profile(holdingToken: "nowhere", userDataDirectory: dir) == nil)
}

@Test func opensThroughTheExtensionInTheMainWindowsProfile() {
    let ready = [1, 2]
    let profileOf = [1: "Work", 2: "Personal"]
    #expect(ProfileRouting.connection(for: "Work", ready: ready, profileOf: profileOf) == 1)
    #expect(ProfileRouting.connection(for: "Personal", ready: ready, profileOf: profileOf) == 2)
    // No extension there, or the profile isn't known: the caller falls back to the newest connection.
    #expect(ProfileRouting.connection(for: "Side", ready: ready, profileOf: profileOf) == nil)
    #expect(ProfileRouting.connection(for: nil, ready: ready, profileOf: profileOf) == nil)
    // A connection that closed isn't used.
    #expect(ProfileRouting.connection(for: "Personal", ready: [1], profileOf: profileOf) == nil)
}

@Test func noProfilesWithoutTheBrowsersFiles() {
    #expect(BrowserProfiles.load(userDataDirectory: URL(fileURLWithPath: "/nonexistent-\(UUID())")) == nil)
}

@Test func theProfileScriptEscapesTheURLAndName() {
    let script = DiaScript.openInProfile(url: #"https://x.com/?q="a"\b"#, profile: #"My "Work""#)
    #expect(script.contains(#"URL:"https://x.com/?q=\"a\"\\b""#))
    #expect(script.contains(#"profile "My \"Work\"""#))
    #expect(script.contains("tell application id \"company.thebrowser.dia\""))
}

@Test func allProfilesAreListedAlphabeticallyIncludingTheCurrentOne() {
    #expect(BrowserProfiles(current: "Work", others: ["Personal", "Side"]).all == ["Personal", "Side", "Work"])
}

@Test func openInFollowsTheProfileTheMainWindowIsShowing() {
    let profiles = BrowserProfiles(current: "Work", others: ["Personal"])
    #expect(profiles.destination(showing: "Personal", littleWindowIn: "Work") == "Personal")
    #expect(profiles.destination(showing: "Work", littleWindowIn: "Personal") == "Work")
}

@Test func openInFallsBackToTheLittleWindowsOwnProfile() {
    let profiles = BrowserProfiles(current: "Work", others: ["Personal"])
    #expect(profiles.destination(showing: nil, littleWindowIn: "Personal") == "Personal")
    // A profile renamed or removed since the names were read.
    #expect(profiles.destination(showing: "Side", littleWindowIn: "Personal") == "Personal")
    // Not known either: the first profile with the extension.
    #expect(profiles.destination(showing: nil, littleWindowIn: nil) == "Work")
}

@Test func activeProfileScriptAsksDiaForItsFrontWindow() {
    #expect(DiaScript.activeProfileName.contains("tell application id \"company.thebrowser.dia\""))
    #expect(DiaScript.activeProfileName.contains("name of active profile of window 1"))
}

@Test func openTabScriptEscapesAndTargetsDia() {
    let script = DiaScript.openTab(url: "chrome://extensions")
    #expect(script.contains("company.thebrowser.dia"))
    #expect(script.contains(#"{URL:"chrome://extensions"}"#))
    #expect(DiaScript.openTab(url: #"https://a.b/"x""#).contains(#"{URL:"https://a.b/\"x\""}"#))
}
