import Foundation
import Testing
@testable import LittleDiaCore

private func release(tag: String, assets: [String] = ["Little-Dia.zip"]) throws -> ReleaseInfo {
    let assetJSON = assets.map { #"{"name":"\#($0)","browser_download_url":"https://github.com/austindick/little-dia/releases/download/\#(tag)/\#($0)"}"# }
    let json = #"{"tag_name":"\#(tag)","name":"Little Dia","assets":[\#(assetJSON.joined(separator: ","))]}"#
    return try JSONDecoder().decode(ReleaseInfo.self, from: Data(json.utf8))
}

@Test func parsesVersionsWithOrWithoutV() {
    #expect(Version("v1.2.0") == Version("1.2.0"))
    #expect(Version("1.2.0") != nil)
}

@Test func comparesNumericallyNotLexically() {   // Review Focus 5
    #expect(Version("1.0.10")! > Version("1.0.9")!)
    #expect(Version("2.0.0")! > Version("1.9.9")!)
}

@Test func ignoresUnparseableTags() throws {   // Review Focus 5
    #expect(Version("latest") == nil)
    #expect(Version("1.2") == nil)
    #expect(UpdateOffer.decide(currentVersion: "1.0.0", release: try release(tag: "latest")) == nil)
}

@Test func decodesGitHubRelease() throws {
    let r = try release(tag: "v1.0.1")
    #expect(r.tagName == "v1.0.1")
    #expect(r.assets.map(\.name) == ["Little-Dia.zip"])
    #expect(r.assets.first?.browserDownloadURL.absoluteString == "https://github.com/austindick/little-dia/releases/download/v1.0.1/Little-Dia.zip")
}

@Test func offersANewerReleaseWithTheZip() throws {
    let offer = UpdateOffer.decide(currentVersion: "1.0.0", release: try release(tag: "v1.0.1"))
    #expect(offer?.version == "1.0.1")
    #expect(offer?.downloadURL.lastPathComponent == "Little-Dia.zip")
}

@Test func noOfferForTheSameVersion() throws {
    #expect(UpdateOffer.decide(currentVersion: "1.0.1", release: try release(tag: "v1.0.1")) == nil)
    #expect(UpdateOffer.decide(currentVersion: "1.1.0", release: try release(tag: "v1.0.1")) == nil)
}

@Test func noOfferWithoutTheZipAsset() throws {
    #expect(UpdateOffer.decide(currentVersion: "1.0.0", release: try release(tag: "v1.0.1", assets: ["notes.txt"])) == nil)
}

@Test func refusesToReplaceOutsideAWritableFolder() throws {   // Review Focus 1
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("ld-upd-\(UUID().uuidString)")
    let folder = root.appendingPathComponent("Applications")
    let app = folder.appendingPathComponent("X.app")
    try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    defer {
        chmod(folder.path, 0o755)
        try? FileManager.default.removeItem(at: root)
    }
    #expect(UpdateInstall.canReplace(appAt: app))
    #expect(!UpdateInstall.canReplace(appAt: folder))                                  // not an .app
    #expect(!UpdateInstall.canReplace(appAt: folder.appendingPathComponent("Y.app")))  // missing
    chmod(folder.path, 0o555)
    #expect(!UpdateInstall.canReplace(appAt: app))                                     // read-only parent
}

/// Review finding 1: a build run from the repo (build/Little Dia.app) must never be replaced by an update.
@Test func replacesOnlyAnAppInAnApplicationsFolder() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ld-upd-\(UUID().uuidString)")
    let installed = folder.appendingPathComponent("Applications/Little Dia.app")
    let built = folder.appendingPathComponent("build/Little Dia.app")
    try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: built, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    #expect(UpdateInstall.canReplace(appAt: installed))
    #expect(!UpdateInstall.canReplace(appAt: built))
}

/// Review finding 4: relaunching must wait for the old process to exit; `open` on a still-running app just activates it.
@Test func relaunchWaitsForTheOldProcessToExit() throws {
    let marker = FileManager.default.temporaryDirectory.appendingPathComponent("ld-relaunch-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: marker) }
    let oldApp = Process()
    oldApp.executableURL = URL(fileURLWithPath: "/bin/sleep")
    oldApp.arguments = ["0.5"]
    try oldApp.run()
    let started = Date()
    let relaunch = Process()
    relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
    relaunch.arguments = UpdateInstall.relaunchArguments(appPath: marker.path, waitingFor: oldApp.processIdentifier, opener: "/usr/bin/touch")
    try relaunch.run()
    relaunch.waitUntilExit()
    #expect(Date().timeIntervalSince(started) >= 0.4)
    #expect(FileManager.default.fileExists(atPath: marker.path))
}
