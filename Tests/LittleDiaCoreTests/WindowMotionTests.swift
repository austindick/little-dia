import CoreGraphics
import Testing
@testable import LittleDiaCore

private let small = CGRect(x: 300, y: 137, width: 1000, height: 822)
private let large = CGRect(x: 0, y: 25, width: 1600, height: 951)

/// Feeds `frames` one tick at a time and returns every event, with the tick it happened on.
private func run(_ motion: inout WindowMotion, _ ticks: [(CGRect, Bool)]) -> [(Int, WindowMotion.Event)] {
    ticks.enumerated().compactMap { index, tick in motion.tick(frame: tick.0, mouseDown: tick.1).map { (index, $0) } }
}

private func still(_ frame: CGRect, _ count: Int, mouseDown: Bool = false) -> [(CGRect, Bool)] {
    Array(repeating: (frame, mouseDown), count: count)
}

private func step(_ from: CGRect, _ to: CGRect, _ fraction: CGFloat) -> CGRect {
    CGRect(x: from.minX + (to.minX - from.minX) * fraction, y: from.minY + (to.minY - from.minY) * fraction,
           width: from.width + (to.width - from.width) * fraction, height: from.height + (to.height - from.height) * fraction)
}

@Test func aStillWindowNeverMoves() {
    var motion = WindowMotion()
    #expect(run(&motion, still(small, 30) + still(small, 30, mouseDown: true)).isEmpty)
}

@Test func aZoomWithTheMouseUpHidesAtOnceAndEndsOnceStill() {
    var motion = WindowMotion()
    let animation = (1...15).map { (step(small, large, CGFloat($0) / 15), false) }
    let events = run(&motion, still(small, 3) + animation + still(large, WindowMotion.stillTicksToEnd))
    #expect(events.count == 2)
    #expect(events.first?.0 == 3 && events.first?.1 == .started)   // the first changed frame
    #expect(events.last?.0 == 3 + 15 + WindowMotion.stillTicksToEnd - 1 && events.last?.1 == .ended(byHand: false))
}

@Test func aZoomStartedOnTheSecondClickIsNotAResizeByHand() {
    var motion = WindowMotion()
    let pressed = (1...3).map { (step(small, large, CGFloat($0) / 15), true) }
    let released = (4...15).map { (step(small, large, CGFloat($0) / 15), false) }
    let events = run(&motion, still(small, 2, mouseDown: true) + pressed + released + still(large, WindowMotion.stillTicksToEnd))
    #expect(events.map(\.1) == [.started, .ended(byHand: false)])
}

@Test func aResizeByHandEndsWhenReleasedAndStill() {
    var motion = WindowMotion()
    let dragging = (1...10).map { (step(small, large, CGFloat($0) / 10), true) }
    let events = run(&motion, still(small, 2, mouseDown: true) + dragging + still(large, 20, mouseDown: true)
                              + still(large, WindowMotion.stillTicksToEnd))
    #expect(events.map(\.1) == [.started, .ended(byHand: true)])
    #expect(events.last?.0 == 2 + 10 + 20 + WindowMotion.stillTicksToEnd - 1)   // not while the mouse is still held
}

@Test func aSnapAfterReleaseIsNotAResizeByHand() {
    var motion = WindowMotion()
    let dragging = (1...5).map { (step(small, large, CGFloat($0) / 10), true) }
    let snapping = (6...10).map { (step(small, large, CGFloat($0) / 10), false) }
    let events = run(&motion, still(small, 2, mouseDown: true) + dragging + snapping + still(large, WindowMotion.stillTicksToEnd))
    #expect(events.map(\.1) == [.started, .ended(byHand: false)])
}

@Test func aPauseInTheAnimationShorterThanTheWaitDoesNotEndIt() {
    var motion = WindowMotion()
    let middle = step(small, large, 0.5)
    let events = run(&motion, still(small, 2) + [(middle, false)] + still(middle, WindowMotion.stillTicksToEnd - 1)
                              + [(large, false)] + still(large, WindowMotion.stillTicksToEnd))
    #expect(events.map(\.1) == [.started, .ended(byHand: false)])
}

@Test func resetForgetsTheLastFrame() {
    var motion = WindowMotion()
    _ = run(&motion, still(small, 3))
    motion.reset()
    #expect(run(&motion, still(large, 3)).isEmpty)   // a window shown somewhere new isn't moving
    #expect(!motion.moving)
}

// A title-bar double-click zooms by animating a picture of the window: its real frame jumps once, at the end.

@Test func anExpectedZoomHidesUntilTheJumpThenEndsOnceStill() {
    var motion = WindowMotion()
    _ = run(&motion, still(small, 3))
    motion.expectChange(within: 45)
    #expect(motion.moving)
    let events = run(&motion, still(small, 20) + still(large, 1 + WindowMotion.stillTicksToEnd))
    #expect(events.count == 1)
    #expect(events.first?.0 == 20 + WindowMotion.stillTicksToEnd && events.first?.1 == .ended(byHand: false))
}

@Test func anExpectedChangeThatNeverComesEndsAfterTheWait() {
    var motion = WindowMotion()
    _ = run(&motion, still(small, 3))
    motion.expectChange(within: 45)
    let events = run(&motion, still(small, 60))
    #expect(events.count == 1)
    #expect(events.first?.0 == 44 && events.first?.1 == .ended(byHand: false))
}

@Test func expectingAChangeWhileAlreadyMovingChangesNothing() {
    var motion = WindowMotion()
    let dragging = (1...5).map { (step(small, large, CGFloat($0) / 5), true) }
    _ = run(&motion, still(small, 2, mouseDown: true) + dragging)
    motion.expectChange(within: 45)
    let events = run(&motion, still(large, 3, mouseDown: true) + still(large, WindowMotion.stillTicksToEnd))
    #expect(events.map(\.1) == [.ended(byHand: true)])
}
