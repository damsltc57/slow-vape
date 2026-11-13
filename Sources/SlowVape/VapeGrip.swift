import CoreGraphics
import SlowVapeCore
import Vision

/// Uses the hand only after the detector has seen a vape in that grip.
struct VapeGrip {
    private struct Hand {
        let wrist: CGPoint
        let tips: [CGPoint]
        let bounds: CGRect
    }

    private var wrist: CGPoint?
    private var lastSeen = -Double.infinity
    private var lastVape = -Double.infinity
    private var withdrawalStarted: Double?

    var isActive: Bool { wrist != nil }

    mutating func signal(
        observations: [VNHumanHandPoseObservation],
        confirmedVape: CGRect?,
        mouth: CGRect,
        face: CGRect,
        time: Double
    ) -> PuffCounter.Signal? {
        let hands = observations.compactMap(Self.hand)
        if let wrist, time - lastSeen <= 0.30, time - lastVape <= 4 {
            guard let hand = hands.min(by: {
                distance($0.wrist, wrist, relativeTo: face) < distance($1.wrist, wrist, relativeTo: face)
            }), distance(hand.wrist, wrist, relativeTo: face) <= 0.45 else {
                withdrawalStarted = nil
                return .uncertain
            }

            self.wrist = hand.wrist
            lastSeen = time
            if let confirmedVape, overlapsGrip(confirmedVape, hand: hand, face: face) {
                lastVape = time
            }

            let distances = hand.tips.map { offset($0, from: mouth, relativeTo: face) }
            if distances.contains(where: Self.isNearMouth) {
                withdrawalStarted = nil
                return .near
            }
            if distances.allSatisfy({ $0.x >= 0.32 || $0.y >= 0.23 }) {
                if let started = withdrawalStarted, time - started >= 0.12 {
                    self = Self()
                } else if withdrawalStarted == nil {
                    withdrawalStarted = time
                }
                return .away
            }

            withdrawalStarted = nil
            return .uncertain
        }

        if isActive {
            self = Self()
            return .uncertain
        }
        guard let confirmedVape, let hand = hands.first(where: { hand in
            overlapsGrip(confirmedVape, hand: hand, face: face) && hand.tips.contains {
                Self.isNearMouth(offset($0, from: mouth, relativeTo: face))
            }
        }) else { return nil }

        wrist = hand.wrist
        lastSeen = time
        lastVape = time
        return .near
    }

    private func overlapsGrip(_ vape: CGRect, hand: Hand, face: CGRect) -> Bool {
        let expandedGrip = hand.bounds.insetBy(dx: -0.08 * face.width, dy: -0.05 * face.height)
        let overlap = vape.intersection(expandedGrip)
        return !overlap.isEmpty && overlap.width * overlap.height >= 0.25 * vape.width * vape.height
    }

    private static func isNearMouth(_ gap: CGPoint) -> Bool {
        gap.x <= 0.23 && gap.y <= 0.16
    }

    private func offset(_ point: CGPoint, from bounds: CGRect, relativeTo face: CGRect) -> CGPoint {
        CGPoint(x: max(bounds.minX - point.x, point.x - bounds.maxX, 0) / face.width,
                y: max(bounds.minY - point.y, point.y - bounds.maxY, 0) / face.height)
    }

    private func distance(_ first: CGPoint, _ second: CGPoint, relativeTo face: CGRect) -> CGFloat {
        hypot((first.x - second.x) / face.width, (first.y - second.y) / face.height)
    }

    private static func hand(_ observation: VNHumanHandPoseObservation) -> Hand? {
        guard let points = try? observation.recognizedPoints(.all),
              let wrist = points[.wrist], wrist.confidence >= 0.4 else { return nil }
        let tips = [VNHumanHandPoseObservation.JointName.thumbTip, .indexTip, .middleTip]
            .compactMap { points[$0] }
            .filter { $0.confidence >= 0.35 }
            .map(\.location)
        let reliable = points.values.filter { $0.confidence >= 0.35 }
        guard tips.count >= 2, let first = reliable.first else { return nil }
        var minX = first.location.x
        var minY = first.location.y
        var maxX = minX
        var maxY = minY
        for point in reliable.dropFirst() {
            minX = min(minX, point.location.x)
            minY = min(minY, point.location.y)
            maxX = max(maxX, point.location.x)
            maxY = max(maxY, point.location.y)
        }
        return Hand(wrist: wrist.location, tips: tips,
                    bounds: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    }
}
