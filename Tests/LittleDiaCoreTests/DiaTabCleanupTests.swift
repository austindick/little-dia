import Foundation
import Testing
@testable import LittleDiaCore

private let hour: TimeInterval = 3600
private let day: TimeInterval = 86400

@Test func cleanupOffInDiaGivesNoInterval() {
    #expect(DiaTabCleanup.interval(enabled: false, threshold: "twentyFourHours") == nil)
    #expect(DiaTabCleanup.interval(enabled: 0, threshold: nil) == nil)
}

@Test func aMissingFlagCountsAsOn() {
    #expect(DiaTabCleanup.interval(enabled: nil, threshold: "oneHour") == hour)
}

@Test func aMissingThresholdIsDiasTwelveHours() {
    #expect(DiaTabCleanup.interval(enabled: true, threshold: nil) == 12 * hour)
    #expect(DiaTabCleanup.interval(enabled: 1, threshold: nil) == 12 * hour)
}

@Test func twentyFourHoursAsDiaStoresIt() {
    #expect(DiaTabCleanup.interval(enabled: true, threshold: "twentyFourHours") == 86400)
}

@Test func everyKnownIntervalName() {
    let expected: [String: TimeInterval] = [
        "oneHour": hour, "twelveHours": 12 * hour, "twentyFourHours": day, "oneDay": day, "threeDays": 3 * day,
        "sevenDays": 7 * day, "fourteenDays": 14 * day, "twoWeeks": 14 * day, "thirtyDays": 30 * day, "oneMonth": 30 * day,
    ]
    for (name, seconds) in expected {
        #expect(DiaTabCleanup.interval(enabled: true, threshold: name) == seconds, "\(name)")
    }
}

@Test func anUnknownOrMistypedThresholdGivesNoInterval() {
    #expect(DiaTabCleanup.interval(enabled: true, threshold: "fortnightAndABit") == nil)
    #expect(DiaTabCleanup.interval(enabled: true, threshold: 86400) == nil)
    #expect(DiaTabCleanup.interval(enabled: "yes", threshold: "oneHour") == nil)
}

@Test func intervalLabels() {
    #expect(DiaTabCleanup.label(hour) == "1 Hour")
    #expect(DiaTabCleanup.label(12 * hour) == "12 Hours")
    #expect(DiaTabCleanup.label(day) == "24 Hours")
    #expect(DiaTabCleanup.label(3 * day) == "3 Days")
    #expect(DiaTabCleanup.label(30 * day) == "30 Days")
    #expect(DiaTabCleanup.label(120) == "2 Minutes")
}
