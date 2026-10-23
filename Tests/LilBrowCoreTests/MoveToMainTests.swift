import Testing
@testable import LilBrowCore

@MainActor private final class Recorder {
    var canCloseNatively = true
    var calls: [String] = []
    lazy var move = MoveToMain(
        closeNatively: { id in self.calls.append("closeNatively \(id)"); return self.canCloseNatively },
        closeViaExtension: { id in self.calls.append("closeViaExtension \(id)") },
        activateBrowser: { self.calls.append("activateBrowser") },
        settle: .milliseconds(5))
}

@MainActor @Test func closesTheLittleWindowThenTakesYouToTheBrowser() async {
    let r = Recorder()
    await r.move.handle(.littleMoved(windowId: 42))
    #expect(r.calls == ["closeNatively 42", "activateBrowser"])
}

@MainActor @Test func fallsBackToTheExtensionWhenItCannotCloseTheWindowItself() async {
    let r = Recorder()
    r.canCloseNatively = false
    await r.move.handle(.littleMoved(windowId: 42))
    #expect(r.calls == ["closeNatively 42", "closeViaExtension 42", "activateBrowser"])
}

@MainActor @Test func ignoresOtherMessages() async {
    let r = Recorder()
    await r.move.handle(.littleClosed(windowId: 42))
    #expect(r.calls.isEmpty)
}
