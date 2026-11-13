import Foundation
import SlowVapeCore

struct Preferences: Codable, Equatable {
    var hourlyLimit: Int?
    var dailyLimit: Int?
    var volume = 0.65
    var sensitivity = 0.45
    var startCameraAtLaunch = false
    var gentleNotifications = false

    subscript(limit: UsageLimit) -> Int? {
        limit == .hour ? hourlyLimit : dailyLimit
    }
}

struct LocalData: Codable {
    var preferences = Preferences()
    var setupComplete = false
    var events: [Date] = []
    var coverage: [DateInterval] = []

    static func read(from url: URL) throws -> Self {
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return Self()
        }
    }

    func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}

extension UsageLimit {
    var title: String {
        switch self {
        case .hour: L10n.text("limits.lastHour")
        case .day: L10n.text("limits.today")
        }
    }

    var shortTitle: String {
        switch self {
        case .hour: L10n.text("limits.hourly")
        case .day: L10n.text("limits.daily")
        }
    }
}
