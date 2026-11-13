import Foundation
import Testing
@testable import SlowVapeCore

private var paris: Calendar {
    var calendar = Calendar(identifier: .iso8601)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
}

@Test func rollingHourAndCalendarDayDivergeAtMidnight() {
    let now = date("2026-11-13T23:20:00Z")
    let events = [
        date("2026-11-13T22:20:00Z"), date("2026-11-13T22:40:00Z"),
        date("2026-11-13T23:05:00Z"), date("2026-11-13T23:20:01Z")
    ]
    let usage = UsageSnapshot(events: events, now: now, calendar: paris)
    #expect(usage.hour == 2)
    #expect(usage.day == 1)
}

@Test func historyShowsMonitoredZeroSeparatelyAndHandlesClockChange() {
    let now = date("2026-10-25T08:00:00Z")
    let start = paris.startOfDay(for: now)
    let bins = HistoryPeriod.hours.bins(
        events: [start + 3_900], coverage: [DateInterval(start: start, duration: 7_200)],
        now: now, calendar: paris
    )
    #expect(bins.count == 25)
    #expect(bins[0].count == 0 && bins[0].monitored)
    #expect(bins[1].count == 1 && bins[1].monitored)
    #expect(!bins[2].monitored)
}

@Test func limitsAlertOncePerCrossingAndRepeatOnlyOnALaterDetection() {
    let now = date("2026-11-13T20:00:00Z")
    var policy = AlertPolicy()
    #expect(policy.evaluate(reached: [.hour], at: now, onDetection: true) == [.hour])
    #expect(policy.evaluate(reached: [.hour], at: now + 899, onDetection: true).isEmpty)
    #expect(policy.evaluate(reached: [.hour], at: now + 900, onDetection: false).isEmpty)
    #expect(policy.evaluate(reached: [.hour], at: now + 901, onDetection: true) == [.hour])
    #expect(policy.evaluate(reached: [.hour, .day], at: now + 902, onDetection: true) == [.day])
    #expect(policy.evaluate(reached: [.day], at: now + 903, onDetection: false).isEmpty)
    #expect(policy.evaluate(reached: [.hour, .day], at: now + 904, onDetection: true) == [.hour])
}

@Test func clockRefreshDoesNotConsumeAnAlertBeforeTheNextDetection() {
    let now = date("2026-11-13T20:00:00Z")
    var policy = AlertPolicy()
    #expect(policy.evaluate(reached: [.day], at: now, onDetection: false).isEmpty)
    #expect(policy.evaluate(reached: [.day], at: now + 1, onDetection: true) == [.day])
}
