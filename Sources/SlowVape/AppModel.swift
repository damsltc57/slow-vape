@preconcurrency import AVFoundation
import AppKit
import Observation
import SlowVapeCore
import UserNotifications

@MainActor
@Observable
final class AppModel {
    enum CameraStatus: Equatable {
        case paused, starting, running, failed(String)
    }

    var section = RootView.Section.dashboard
    private(set) var cameraStatus = CameraStatus.paused
    private(set) var frame: CameraFrame?
    private(set) var camera: Camera?
    private(set) var data = LocalData()
    private(set) var now = Date()
    private(set) var testCount = 0
    private(set) var storageError: String?
    private(set) var notificationsError: String?
    private(set) var liveSince: Date?
    private var lastUsableFrame: Date?
    private var lastCheckpoint = Date.distantPast
    private var generation = 0
    private var alertPolicy = AlertPolicy()
    private var warned: Set<UsageLimit> = []
    private var didLoad = false
    private let dataURL: URL
    var presentAlert: ((Set<UsageLimit>) -> Void)?
    var statusChanged: (() -> Void)?

    init(dataURL: URL) {
        self.dataURL = dataURL
        load()
    }

    func load() {
        do {
            data = try LocalData.read(from: dataURL)
            didLoad = true
            storageError = nil
        } catch {
            storageError = L10n.text("storage.readError")
        }
    }

    var preferences: Preferences { data.preferences }
    var setupComplete: Bool { data.setupComplete }
    var canStart: Bool {
        switch cameraStatus {
        case .paused, .failed: true
        default: false
        }
    }

    var isTracking: Bool { liveSince != nil }
    var usage: UsageSnapshot { UsageSnapshot(events: data.events, now: now, calendar: .current) }

    var reached: Set<UsageLimit> {
        let snapshot = usage
        return Set(UsageLimit.allCases.filter { limit in
            preferences[limit].map { snapshot[limit] >= $0 } == true
        })
    }

    var cameraMessage: String {
        switch cameraStatus {
        case .paused: L10n.text("camera.paused")
        case .starting: L10n.text("camera.starting")
        case .failed(let message): message
        case .running:
            if frame == nil { L10n.text("camera.waiting") }
            else if frame?.mouth == nil { L10n.text("camera.faceMissing") }
            else if !isTracking && setupComplete { L10n.text("camera.unavailable") }
            else if frame?.nearMouth == true { L10n.text("camera.nearLips") }
            else { L10n.text("camera.active") }
        }
    }

    func finishSetup(_ preferences: Preferences) {
        var next = data
        next.preferences = preferences
        next.setupComplete = true
        if persist(next) {
            testCount = 0
            frame = nil
            statusChanged?()
        }
    }

    func savePreferences(_ preferences: Preferences) {
        let before = data.preferences
        var next = data
        next.preferences = preferences
        guard persist(next) else { return }
        if preferences.sensitivity != before.sensitivity {
            camera?.setThreshold(threshold)
        }
        now = Date()
        refreshAlerts(onDetection: false)
    }

    func start() {
        guard canStart, didLoad else { return }
        generation += 1
        let request = generation
        cameraStatus = .starting
        statusChanged?()
        Task {
            let authorized: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
            guard request == generation else { return }
            guard authorized else {
                cameraStatus = .failed(L10n.text("camera.error.permission"))
                statusChanged?()
                return
            }
            let next = Camera { [weak self] update in
                DispatchQueue.main.async {
                    self?.receive(update, generation: request)
                }
            }
            camera = next
            next.start(threshold: threshold)
        }
    }

    func stop() {
        generation += 1
        camera?.stop()
        camera = nil
        frame = nil
        closeCoverage()
        cameraStatus = .paused
        statusChanged?()
    }

    func undoLast() {
        var next = data
        guard let latest = next.events.indices.max(by: { next.events[$0] < next.events[$1] }) else { return }
        next.events.remove(at: latest)
        if persist(next) { refreshAlerts(onDetection: false) }
    }

    func bins(_ period: HistoryPeriod) -> [HistoryPeriod.Bin] {
        var coverage = data.coverage
        if let start = liveSince, let end = lastUsableFrame, end > start {
            coverage.append(DateInterval(start: start, end: end))
        }
        return period.bins(events: data.events, coverage: coverage, now: now, calendar: .current)
    }

    func tick() {
        now = Date()
        if let lastUsableFrame, now.timeIntervalSince(lastUsableFrame) > 3 {
            closeCoverage()
        } else if let lastUsableFrame, now.timeIntervalSince(lastCheckpoint) >= 15 {
            checkpoint(to: lastUsableFrame)
        }
        refreshAlerts(onDetection: false)
    }

    func setGentleNotifications(_ enabled: Bool) async -> Bool {
        notificationsError = nil
        if enabled {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
                guard granted else {
                    notificationsError = L10n.text("notifications.denied")
                    return false
                }
            } catch {
                notificationsError = L10n.text("notifications.error")
                return false
            }
        }
        var next = preferences
        next.gentleNotifications = enabled
        savePreferences(next)
        return preferences.gentleNotifications == enabled
    }

    private var threshold: Float { Float(0.65 - preferences.sensitivity * 0.55) }

    private func receive(_ update: CameraUpdate, generation request: Int) {
        guard request == generation else { return }
        switch update {
        case .running:
            cameraStatus = .running
            statusChanged?()
        case .frame(let frame):
            self.frame = frame
            guard setupComplete else {
                if frame.countedPuff { testCount += 1 }
                return
            }
            let at = Date()
            if frame.mouth != nil {
                if let lastUsableFrame, at.timeIntervalSince(lastUsableFrame) > 3 { closeCoverage() }
                if liveSince == nil {
                    liveSince = at
                    lastCheckpoint = at
                    statusChanged?()
                }
                lastUsableFrame = at
            }
            if frame.countedPuff {
                now = at
                var next = data
                next.events.append(at)
                if persist(next) { refreshAlerts(onDetection: true) }
            }
        case .failure(let error):
            stop()
            cameraStatus = .failed(error)
            statusChanged?()
        }
    }

    private func checkpoint(to end: Date) {
        guard let start = liveSince, end > start, end > lastCheckpoint else { return }
        var next = data
        if let index = next.coverage.indices.last, next.coverage[index].start == start {
            next.coverage[index] = DateInterval(start: start, end: end)
        } else {
            next.coverage.append(DateInterval(start: start, end: end))
        }
        if persist(next) { lastCheckpoint = end }
    }

    private func closeCoverage() {
        if let end = lastUsableFrame { checkpoint(to: end) }
        let wasTracking = isTracking
        liveSince = nil
        lastUsableFrame = nil
        if wasTracking { statusChanged?() }
    }

    @discardableResult
    private func persist(_ next: LocalData) -> Bool {
        guard didLoad else { return false }
        do {
            try next.write(to: dataURL)
            data = next
            storageError = nil
            return true
        } catch {
            storageError = L10n.text("storage.writeError")
            return false
        }
    }

    private func refreshAlerts(onDetection: Bool) {
        guard setupComplete else { return }
        let exceeded = reached
        let announcement = alertPolicy.evaluate(reached: exceeded, at: now, onDetection: onDetection)
        if !announcement.isEmpty { presentAlert?(exceeded) }

        let snapshot = usage
        let close = Set(UsageLimit.allCases.filter { limit in
            guard let target = preferences[limit] else { return false }
            return snapshot[limit] < target && Double(snapshot[limit]) >= Double(target) * 0.8
        })
        if onDetection, preferences.gentleNotifications, let limit = UsageLimit.allCases.first(where: { close.contains($0) && !warned.contains($0) }) {
            let content = UNMutableNotificationContent()
            content.title = L10n.text("notifications.warning")
            content.body = L10n.format("notifications.body", L10n.number(snapshot[limit]), L10n.number(preferences[limit] ?? 0), limit.title)
            let request = UNNotificationRequest(identifier: "slow-vape-warning-\(limit.rawValue)", content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
        // Keep a warning latched while the corresponding threshold is still reached.
        warned = close.union(exceeded)
        statusChanged?()
    }
}
