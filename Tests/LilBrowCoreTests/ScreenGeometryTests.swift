import CoreGraphics
import Testing
@testable import LilBrowCore

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
                                        topInset: 5, rightInset: 6)
            == CGRect(x: 1174, y: 142, width: 120, height: 23))
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
