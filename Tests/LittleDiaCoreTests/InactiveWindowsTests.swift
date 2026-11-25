import Foundation
import Testing
@testable import LittleDiaCore

private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }
private let hour: TimeInterval = 3600

@MainActor @Test func anUntouchedWindowIsDueExactlyAtTheInterval() {
    let windows = InactiveWindows()
    windows.noteOpened(1, now: at(0))
    windows.noteInFront(nil, now: at(0))
    #expect(windows.due(now: at(59.9), after: hour) == [])
    #expect(windows.due(now: at(60), after: hour) == [1])
}

@MainActor @Test func comingBackToFrontRestartsTheCountdown() {
    let windows = InactiveWindows()
    windows.noteOpened(1, now: at(0))
    windows.noteInFront(1, now: at(40))
    windows.noteInFront(nil, now: at(41))
    #expect(windows.due(now: at(70), after: hour) == [])
    #expect(windows.due(now: at(101), after: hour) == [1])
}

@MainActor @Test func theWindowInFrontIsNeverDue() {
    let windows = InactiveWindows()
    windows.noteOpened(1, now: at(0))
    windows.noteInFront(1, now: at(0))
    #expect(windows.due(now: at(600), after: hour) == [])
}

@MainActor @Test func timeInFrontCountsAsActive() {
    let windows = InactiveWindows()
    windows.noteOpened(1, now: at(0))
    windows.noteInFront(1, now: at(0))
    windows.noteInFront(nil, now: at(50))
    #expect(windows.due(now: at(65), after: hour) == [])
    #expect(windows.due(now: at(110), after: hour) == [1])
}

@MainActor @Test func onlyTheStaleOnesAreDue() {
    let windows = InactiveWindows()
    windows.noteOpened(1, now: at(0))
    windows.noteOpened(2, now: at(30))
    windows.noteOpened(3, now: at(0))
    windows.noteInFront(3, now: at(0))
    #expect(windows.due(now: at(61), after: hour) == [1])
}

@MainActor @Test func aClosedWindowIsForgotten() {
    let windows = InactiveWindows()
    windows.noteOpened(1, now: at(0))
    windows.noteInFront(1, now: at(0))
    windows.noteClosed(1)
    windows.noteInFront(nil, now: at(1))
    #expect(windows.due(now: at(600), after: hour) == [])
}
