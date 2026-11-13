import CoreGraphics
import Testing
@testable import LittleDiaCore

private let primary = ScreenContext(visibleFrame: CGRect(x: 0, y: 0, width: 1600, height: 976), primaryScreenHeight: 1000)
private let target = Bounds(left: 300, top: 137, width: 1000, height: 750)

@Test func centersOnPrimary() {
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: primary) == Bounds(left: 300, top: 137, width: 1000, height: 750))
}

@Test func centersOnSecondaryWithNegativeX() {   // Review Focus 2
    let s = ScreenContext(visibleFrame: CGRect(x: -1440, y: 100, width: 1440, height: 876), primaryScreenHeight: 1000)
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: s) == Bounds(left: -1220, top: 87, width: 1000, height: 750))
}

@Test func clampsOversize() {
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 3000, height: 2000), on: primary) == Bounds(left: 40, top: 64, width: 1520, height: 896))
}

@Test func enforcesMinimum() {
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 100, height: 100), on: primary) == Bounds(left: 560, top: 332, width: 480, height: 360))
}

@Test func floorsFractions() {
    let s = ScreenContext(visibleFrame: CGRect(x: 0, y: 0, width: 1601, height: 977), primaryScreenHeight: 1000)
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: s) == Bounds(left: 300, top: 136, width: 1000, height: 750))
}

@Test func convertsTopLeftToAppKit() {
    #expect(ScreenGeometry.appKitRect(fromTopLeft: CGRect(x: 300, y: 137, width: 1000, height: 750), primaryScreenHeight: 1000) == CGRect(x: 300, y: 113, width: 1000, height: 750))
}

@Test func overlaySitsInTheTitleBarsTopRightCorner() {
    #expect(ScreenGeometry.overlayFrame(windowTopLeft: CGRect(x: 300, y: 137, width: 1000, height: 750), overlaySize: CGSize(width: 120, height: 23),
                                        topInset: 5, rightInset: 5)
            == CGRect(x: 1175, y: 142, width: 120, height: 23))
}

@Test func overlaySizeIsRoundedUpSoNothingIsClipped() {   // the panel's width would otherwise round down
    #expect(ScreenGeometry.overlayFrame(windowTopLeft: CGRect(x: 300, y: 137, width: 1000, height: 750), overlaySize: CGSize(width: 120.4, height: 22.6),
                                        topInset: 5, rightInset: 6)
            == CGRect(x: 1173, y: 142, width: 121, height: 23))
}

@Test func matchesWithinTolerance() {
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 303, y: 135, width: 997, height: 752))], bounds: target, excluding: []) == 1)
}

@Test func rejectsOutsideTolerance() {
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 310, y: 137, width: 1000, height: 750))], bounds: target, excluding: []) == nil)
}

@Test func matchesDiaWindowWithChromeAboveRequestedBounds() {   // spike: Dia adds ~72pt above the requested page area
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 300, y: 65, width: 1000, height: 822))], bounds: target, excluding: []) == 1)
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 300, y: 137, width: 1000, height: 822))], bounds: target, excluding: []) == nil)
}

@Test func skipsTrackedTwin() {   // Review Focus 5
    let f = CGRect(x: 300, y: 137, width: 1000, height: 750)
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: f), WindowCandidate(id: 2, frame: f)], bounds: target, excluding: [1]) == 2)
}

@Test func prefersClosest() {
    #expect(matchLittleWindow([WindowCandidate(id: 1, frame: CGRect(x: 304, y: 137, width: 1000, height: 750)),
                               WindowCandidate(id: 2, frame: CGRect(x: 301, y: 137, width: 1000, height: 750))],
                              bounds: target, excluding: []) == 2)
}

@Test func overlayOnlyForFocusedTrackedWindowOfFrontmostBrowser() {
    #expect(OverlayVisibility.windowToShow(frontmostPID: 10, browserPID: 10, focusedWindow: 5, tracked: [5]) == 5)
    #expect(OverlayVisibility.windowToShow(frontmostPID: 11, browserPID: 10, focusedWindow: 5, tracked: [5]) == nil)
    #expect(OverlayVisibility.windowToShow(frontmostPID: 10, browserPID: 10, focusedWindow: 6, tracked: [5]) == nil)
}

@Test func pageAreaOfAResizedWindow() {   // Dia's window = page area + ~72pt of title bar and address row above it
    #expect(ScreenGeometry.pageBounds(ofWindow: CGRect(x: 300, y: 65, width: 1100, height: 872), chromeHeight: 72)
            == Bounds(left: 300, top: 137, width: 1100, height: 800))
}

@Test func centersTheWholeWindowIncludingTheBrowsersTitleBar() {   // review #2: Dia adds 72pt above the page area
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 1000, height: 750), on: primary, chromeHeight: 72)
            == Bounds(left: 300, top: 173, width: 1000, height: 750))
}

@Test func clampsSoTheTitleBarStaysOnScreen() {
    #expect(ScreenGeometry.littleWindowBounds(size: CGSize(width: 3000, height: 2000), on: primary, chromeHeight: 72)
            == Bounds(left: 40, top: 136, width: 1520, height: 824))
}

@Test func prefersTheFocusedWindowWhenSeveralMatch() {   // review #3: the new popup is the browser's focused window
    let f = CGRect(x: 300, y: 137, width: 1000, height: 750)
    let twins = [WindowCandidate(id: 1, frame: f), WindowCandidate(id: 2, frame: f)]
    #expect(matchLittleWindow(twins, bounds: target, excluding: [], preferring: 2) == 2)
    #expect(matchLittleWindow(twins, bounds: target, excluding: [], preferring: 9) == 1)
}

@Test func diaIsAskedForASpotOffsetByTheDifferenceInScreenHeights() {
    // Dia converts a popup's position with the height of the screen it goes on, not the main screen's: on a
    // 1440pt Studio Display beside a 1117pt main laptop screen, it lands 323pt higher than asked.
    let studio = ScreenContext(visibleFrame: CGRect(x: 1728, y: -323, width: 2560, height: 1410), primaryScreenHeight: 1117,
                               screenHeight: 1440)
    #expect(ScreenGeometry.diaTopOffset(on: studio) == 323)
    #expect(ScreenGeometry.diaTopOffset(on: primary) == 0)
}

@Test func aWindowPlacedHigherIsMovedBackToWhereItWasAskedFor() {
    // Asked for page 300,137 1000x750; Dia added its 72pt title bar above but put the window at the top of the screen.
    #expect(ScreenGeometry.requestedOrigin(ofWindow: CGRect(x: 300, y: 30, width: 1000, height: 822), bounds: target)
            == CGPoint(x: 300, y: 65))
    // Where it was asked for (within a few points): left alone.
    #expect(ScreenGeometry.requestedOrigin(ofWindow: CGRect(x: 301, y: 63, width: 1000, height: 822), bounds: target) == nil)
}

@Test func takesTheFocusedWindowPlacedHigherOnAnotherScreen() {   // Dia put one 250pt higher on a non-main display
    let higher = [WindowCandidate(id: 1, frame: CGRect(x: 300, y: 30, width: 1000, height: 822))]
    #expect(matchLittleWindow(higher, bounds: target, excluding: [], preferring: 1) == 1)
    // Only the focused window, untracked, at the requested left and right edges.
    #expect(matchLittleWindow(higher, bounds: target, excluding: []) == nil)
    #expect(matchLittleWindow(higher, bounds: target, excluding: [1], preferring: 1) == nil)
    let elsewhere = [WindowCandidate(id: 1, frame: CGRect(x: 340, y: 30, width: 1000, height: 822))]
    #expect(matchLittleWindow(elsewhere, bounds: target, excluding: [], preferring: 1) == nil)
}
