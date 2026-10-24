import Testing
@testable import LilBrowCore

@MainActor private final class Recorder {
    var canCloseNatively = true
    var scriptSucceeds = true
    var calls: [String] = []
    lazy var sender = SendToProfile(
        urlOf: { _ in "https://github.com/pulls" },
        forget: { self.calls.append("forget \($0)") },
        closeNatively: { self.calls.append("closeNatively \($0)"); return self.canCloseNatively },
        closeViaExtension: { self.calls.append("closeViaExtension \($0)") },
        openInProfile: { url, profile in self.calls.append("openInProfile \(profile) \(url)"); return self.scriptSucceeds },
        openNormally: { self.calls.append("openNormally \($0)") },
        settle: .milliseconds(5))
}

@MainActor @Test func closesTheLittleWindowThenOpensThePageInTheOtherProfile() async {
    let r = Recorder()
    await r.sender.send(windowId: 42, to: "Personal")
    #expect(r.calls == ["forget 42", "closeNatively 42", "openInProfile Personal https://github.com/pulls"])
}

@MainActor @Test func opensNormallyWhenScriptingDiaFails() async {   // e.g. the Automation permission was denied
    let r = Recorder()
    r.scriptSucceeds = false
    await r.sender.send(windowId: 42, to: "Personal")
    #expect(r.calls.last == "openNormally https://github.com/pulls")
}

@MainActor @Test func closesThroughTheExtensionIfItCannotCloseNatively() async {
    let r = Recorder()
    r.canCloseNatively = false
    await r.sender.send(windowId: 42, to: "Personal")
    #expect(r.calls.contains("closeViaExtension 42"))
}
