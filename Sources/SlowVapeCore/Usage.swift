import Foundation

public enum UsageLimit: String, CaseIterable, Hashable, Sendable {
    case hour, day
}

public struct UsageSnapshot: Equatable, Sendable {
    public let hour: Int
    public let day: Int

    public init(events: [Date], now: Date, calendar: Calendar) {
        let start = calendar.startOfDay(for: now)
        var hour = 0
        var day = 0
        for event in events where event <= now {
            if event > now - 3_600 { hour += 1 }
            if event >= start { day += 1 }
        }
        self.hour = hour
        self.day = day
    }

    public subscript(limit: UsageLimit) -> Int {
        limit == .hour ? hour : day
    }
}

public enum HistoryPeriod: String, CaseIterable, Sendable {
    case hours, days, weeks

    public struct Bin: Identifiable, Sendable {
        public var id: Date { interval.start }
        public let interval: DateInterval
        public let count: Int
        public let monitored: Bool
    }

    public func bins(events: [Date], coverage: [DateInterval], now: Date, calendar: Calendar) -> [Bin] {
        let unit: Calendar.Component
        let length: Int
        switch self {
        case .hours: (unit, length) = (.hour, 0)
        case .days: (unit, length) = (.day, 14)
        case .weeks: (unit, length) = (.weekOfYear, 8)
        }
        let anchor = self == .hours ? calendar.dateInterval(of: .day, for: now) : calendar.dateInterval(of: unit, for: now)
        guard let anchor else { return [] }
        let start = self == .hours ? anchor.start : calendar.date(byAdding: unit, value: 1 - length, to: anchor.start)
        guard var cursor = start else { return [] }
        var result: [Bin] = []
        while cursor < anchor.end, let next = calendar.date(byAdding: unit, value: 1, to: cursor), next > cursor {
            let end = min(next, now)
            let count = events.lazy.filter { $0 >= cursor && $0 < next && $0 <= now }.count
            let monitored = count > 0 || (cursor < end && coverage.contains { $0.start < end && $0.end > cursor })
            result.append(Bin(interval: DateInterval(start: cursor, end: next), count: count, monitored: monitored))
            cursor = next
        }
        return result
    }
}

public struct AlertPolicy: Sendable {
    private var previous: Set<UsageLimit> = []
    private var lastAlert: [UsageLimit: Date] = [:]

    public init() {}

    public mutating func evaluate(reached: Set<UsageLimit>, at now: Date, onDetection: Bool) -> Set<UsageLimit> {
        previous.formIntersection(reached)
        guard onDetection else { return [] }
        let new = reached.subtracting(previous)
        let reminders = reached.filter { limit in
            lastAlert[limit].map { now.timeIntervalSince($0) >= 900 } == true
        }
        let announced = new.union(reminders)
        for limit in announced { lastAlert[limit] = now }
        previous = reached
        return announced
    }
}
