import Testing
@testable import LilBrowCore

@MainActor private final class Recorder {
    var canCloseNatively = true
    var calls: [String] = []
    lazy var move = MoveToMain(
        sendMove: { id in self.calls.append("sendMove \(id)") },
        showMainWindow: { self.calls.append("showMainWindow") },
        closeNatively: { id in self.calls.append("closeNatively \(id)"); return self.canCloseNatively },
        closeViaExtension: { id in self.calls.append("closeViaExtension \(id)") })
}

@MainActor @Test func startingAMoveSwitchesToTheMainWindowRightAway() {
    let r = Recorder()
    r.move.start(windowId: 42)
    #expect(r.calls == ["sendMove 42", "showMainWindow"])
}

@MainActor @Test func onceThePageHasMovedTheLittleWindowCloses() {
    let r = Recorder()
    r.move.handle(.littleMoved(windowId: 42))
    #expect(r.calls == ["closeNatively 42"])
}

@MainActor @Test func fallsBackToTheExtensionWhenItCannotCloseTheWindowItself() {
    let r = Recorder()
    r.canCloseNatively = false
    r.move.handle(.littleMoved(windowId: 42))
    #expect(r.calls == ["closeNatively 42", "closeViaExtension 42"])
}

@MainActor @Test func ignoresOtherMessages() {
    let r = Recorder()
    r.move.handle(.littleClosed(windowId: 42))
    #expect(r.calls.isEmpty)
}
