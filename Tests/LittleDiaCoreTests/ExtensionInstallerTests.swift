import Foundation
import Testing
@testable import LittleDiaCore

/// A temp folder with `bundled/` (an extension at `bundledVersion`) and a path for `installed/`.
private struct Folders {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ld-ext-\(UUID().uuidString)")
    var bundled: URL { root.appendingPathComponent("bundled") }
    var installed: URL { root.appendingPathComponent("installed") }

    init(bundledVersion: String?) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let bundledVersion { try writeExtension(at: bundled, version: bundledVersion) }
    }

    func writeExtension(at folder: URL, version: String, marker: String? = nil) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(#"{"manifest_version":3,"name":"Little Dia","version":"\#(version)"}"#.utf8)
            .write(to: folder.appendingPathComponent("manifest.json"))
        if let marker { try Data().write(to: folder.appendingPathComponent(marker)) }
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}

@Test func readsTheManifestVersion() throws {
    let f = try Folders(bundledVersion: "0.2.0"); defer { f.remove() }
    #expect(ExtensionInstaller.version(ofExtensionAt: f.bundled) == "0.2.0")
    #expect(ExtensionInstaller.version(ofExtensionAt: f.installed) == nil)
}

@Test func installsWhenMissing() throws {
    let f = try Folders(bundledVersion: "0.2.0"); defer { f.remove() }
    #expect(try ExtensionInstaller.installIfNeeded(bundled: f.bundled, installed: f.installed))
    #expect(ExtensionInstaller.version(ofExtensionAt: f.installed) == "0.2.0")
}

@Test func skipsWhenVersionsMatch() throws {
    let f = try Folders(bundledVersion: "0.2.0"); defer { f.remove() }
    try f.writeExtension(at: f.installed, version: "0.2.0", marker: "keep-me")
    #expect(try !ExtensionInstaller.installIfNeeded(bundled: f.bundled, installed: f.installed))
    #expect(FileManager.default.fileExists(atPath: f.installed.appendingPathComponent("keep-me").path))
}

@Test func replacesWhenVersionsDiffer() throws {
    let f = try Folders(bundledVersion: "0.2.1"); defer { f.remove() }
    try f.writeExtension(at: f.installed, version: "0.2.0", marker: "old-file")
    #expect(try ExtensionInstaller.installIfNeeded(bundled: f.bundled, installed: f.installed))
    #expect(ExtensionInstaller.version(ofExtensionAt: f.installed) == "0.2.1")
    #expect(!FileManager.default.fileExists(atPath: f.installed.appendingPathComponent("old-file").path))
}

@Test func installKeepsOldCopyWhenSourceIsMissing() throws {   // Review Focus 2
    let f = try Folders(bundledVersion: nil); defer { f.remove() }
    try f.writeExtension(at: f.installed, version: "0.2.0", marker: "keep-me")
    #expect(throws: (any Error).self) { try ExtensionInstaller.installIfNeeded(bundled: f.bundled, installed: f.installed) }
    #expect(ExtensionInstaller.version(ofExtensionAt: f.installed) == "0.2.0")
    #expect(FileManager.default.fileExists(atPath: f.installed.appendingPathComponent("keep-me").path))
}

@Test func needsReloadOnlyWhenVersionsDiffer() {
    #expect(ExtensionInstaller.needsReload(connectedVersion: "0.2.0", bundledVersion: "0.2.1"))
    #expect(!ExtensionInstaller.needsReload(connectedVersion: "0.2.1", bundledVersion: "0.2.1"))
}

/// If Dia loaded the extension from some other folder, reloading never changes its version: ask once, not forever.
@Test func asksEachProfilesExtensionToReload() {
    var policy = ExtensionReloadPolicy()
    // Two profiles with the extension; an older copy can't say which profile it's in.
    let first = policy.shouldReload(connectedVersion: "1.0.2", bundledVersion: "1.0.3", copies: 2)
    let second = policy.shouldReload(connectedVersion: "1.0.2", bundledVersion: "1.0.3", copies: 2)
    // A copy Dia loads from another folder comes back unchanged; it isn't asked forever.
    let third = policy.shouldReload(connectedVersion: "1.0.2", bundledVersion: "1.0.3", copies: 2)
    #expect(first)
    #expect(second)
    #expect(!third)
}

@Test func asksForAReloadOnlyOncePerVersion() {
    var policy = ExtensionReloadPolicy()
    let first = policy.shouldReload(connectedVersion: "0.2.0", bundledVersion: "0.2.1")
    let again = policy.shouldReload(connectedVersion: "0.2.0", bundledVersion: "0.2.1")
    let current = policy.shouldReload(connectedVersion: "0.2.1", bundledVersion: "0.2.1")
    let nextVersion = policy.shouldReload(connectedVersion: "0.2.1", bundledVersion: "0.2.2")
    #expect(first)
    #expect(!again)
    #expect(!current)
    #expect(nextVersion)
}
