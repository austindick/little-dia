import Foundation
import Testing
@testable import LittleDiaCore

private func makeUserData(profiles: [String: String], extensionIn: String?) throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let cache = profiles.mapValues { ["name": $0] }
    try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache]]).write(to: dir.appendingPathComponent("Local State"))
    for folder in profiles.keys {
        let profileDir = dir.appendingPathComponent(folder)
        try FileManager.default.createDirectory(at: profileDir, withIntermediateDirectories: true)
        let installed = folder == extensionIn ? #"{"extensions":{"settings":{"\#(ExtensionIdentity.chromiumID)":{}}}}"# : #"{"extensions":{"settings":{}}}"#
        try Data(installed.utf8).write(to: profileDir.appendingPathComponent("Preferences"))
    }
    return dir
}

@Test func readsTheProfileNamesAndWhichOneHasTheExtension() throws {
    let dir = try makeUserData(profiles: ["Profile 2": "Personal", "Profile 3": "Work"], extensionIn: "Profile 3")
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(BrowserProfiles.load(userDataDirectory: dir) == BrowserProfiles(current: "Work", others: ["Personal"]))
}

@Test func aSingleProfileHasNoOthers() throws {
    let dir = try makeUserData(profiles: ["Default": "Me"], extensionIn: "Default")
    defer { try? FileManager.default.removeItem(at: dir) }
    #expect(BrowserProfiles.load(userDataDirectory: dir) == BrowserProfiles(current: "Me", others: []))
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
