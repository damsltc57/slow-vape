/// Counts observed approaches and departures, independently of the frame rate.
public struct PuffCounter {
    public enum Signal: Equatable {
        case near, away, absent, uncertain
    }

    private enum Phase {
        case unarmed
        case ready
        case approaching(since: Double)
        case held
        case departing(signal: Signal, since: Double)
    }

    private var phase = Phase.unarmed
    private var lastSample: Double?
    private var lastClearSample: Double?
    private let holdDuration = 0.40
    private let departureDuration = 0.12
    private let disappearanceDuration = 0.55
    private let maxGap = 0.38
    private let detectionGap = 0.30

    public init() {}

    public var isNearMouth: Bool {
        switch phase {
        case .approaching, .held: true
        default: false
        }
    }

    public mutating func update(_ signal: Signal, at time: Double) -> Bool {
        guard time.isFinite else { return false }
        if let lastSample, time <= lastSample || time - lastSample > maxGap {
            self = Self()
        }
        lastSample = time

        if signal == .uncertain {
            if let lastClearSample, time - lastClearSample > maxGap {
                phase = .unarmed
            }
            return false
        }

        // A short loss of the object is not a withdrawal. Wait for another
        // near-mouth observation before treating the gesture as a hold.
        if case .approaching = phase, signal == .absent,
           let lastClearSample, time - lastClearSample <= detectionGap {
            return false
        }

        lastClearSample = time
        switch (phase, signal) {
        case (.unarmed, .away), (.unarmed, .absent):
            phase = .ready
        case (.ready, .near):
            phase = .approaching(since: time)
        case (.approaching(let since), .near):
            if time - since >= holdDuration { phase = .held }
        case (.approaching, .away), (.approaching, .absent):
            phase = .ready
        case (.held, .away), (.held, .absent):
            phase = .departing(signal: signal, since: time)
        case (.departing, .near):
            phase = .held
        case (.departing(let previous, let since), .away),
             (.departing(let previous, let since), .absent):
            if signal != previous {
                phase = .departing(signal: signal, since: time)
            } else if time - since >= (signal == .away ? departureDuration : disappearanceDuration) {
                phase = .ready
                return true
            }
        default:
            break
        }
        return false
    }
}
