import Foundation

/// Dia's "clean up inactive tabs" setting, which says how long a little window can go unlooked-at before Little Dia
/// closes it. Dia keeps it in its own defaults: a flag, and the interval as the name of one of its choices.
public enum DiaTabCleanup {
    static let domain = "company.thebrowser.dia"
    static let enabledKey = "autoCleanInactiveTabsEnabled"
    static let thresholdKey = "autoCleanInactiveTabsThreshold"

    private static let hour: TimeInterval = 3600
    private static let day: TimeInterval = 86400
    /// Dia's interval choices, by the names it stores.
    private static let intervals: [String: TimeInterval] = [
        "oneHour": hour, "twelveHours": 12 * hour, "twentyFourHours": day, "oneDay": day, "threeDays": 3 * day,
        "sevenDays": 7 * day, "fourteenDays": 14 * day, "twoWeeks": 14 * day, "thirtyDays": 30 * day, "oneMonth": 30 * day,
    ]

    /// The interval Dia cleans tabs up after, or nil when its cleanup is off or set to a choice this doesn't know.
    /// A missing flag counts as on, and a missing interval is Dia's default, 12 hours.
    public static func interval(enabled: Any?, threshold: Any?) -> TimeInterval? {
        if let enabled {
            guard let on = enabled as? NSNumber, on.boolValue else { return nil }
        }
        guard let threshold else { return 12 * hour }
        guard let name = threshold as? String else { return nil }
        return intervals[name]
    }

    /// Dia's current setting, read fresh so a change made in Dia counts without relaunching.
    public static func read() -> TimeInterval? {
        let app = domain as CFString
        CFPreferencesAppSynchronize(app)
        return interval(enabled: CFPreferencesCopyAppValue(enabledKey as CFString, app),
                        threshold: CFPreferencesCopyAppValue(thresholdKey as CFString, app))
    }

    /// "1 Hour", "24 Hours", "3 Days": for the menu. Up to a day reads in hours, as Dia's choices do.
    public static func label(_ interval: TimeInterval) -> String {
        func unit(_ count: Int, _ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s")" }
        if interval < hour { return unit(Int((interval / 60).rounded()), "Minute") }
        if interval <= day { return unit(Int((interval / hour).rounded()), "Hour") }
        return unit(Int((interval / day).rounded()), "Day")
    }
}
