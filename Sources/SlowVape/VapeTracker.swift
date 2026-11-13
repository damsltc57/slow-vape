import CoreVideo
import Vision

/// Bridges short detector dropouts using a recently recognized vape.
struct VapeTracker {
    private var handler = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var lastDetectionTime: Double?
    private var lastFrameTime: Double?
    private var lastBounds: CGRect?

    mutating func advance(on pixels: CVPixelBuffer, at time: Double) -> CGRect? {
        guard let request, let lastDetectionTime, let lastFrameTime, let lastBounds,
              time - lastDetectionTime <= 0.65, time - lastFrameTime <= 0.28,
              let result = observation(for: request, on: pixels),
              result.confidence >= 0.55, Self.matches(result.boundingBox, lastBounds) else {
            reset()
            return nil
        }

        request.inputObservation = result
        self.lastFrameTime = time
        self.lastBounds = result.boundingBox
        return result.boundingBox
    }

    mutating func confirm(_ bounds: CGRect, on pixels: CVPixelBuffer, at time: Double) {
        if let lastBounds, request != nil, Self.matches(bounds, lastBounds) {
            lastDetectionTime = time
            return
        }

        reset()
        let request = VNTrackObjectRequest(
            detectedObjectObservation: VNDetectedObjectObservation(boundingBox: bounds)
        )
        request.trackingLevel = .accurate
        guard let result = observation(for: request, on: pixels) else {
            self = Self()
            return
        }
        request.inputObservation = result
        self.request = request
        lastDetectionTime = time
        lastFrameTime = time
        lastBounds = bounds
    }

    mutating func reset() {
        guard request != nil else { return }
        self = Self()
    }

    static func matches(_ first: CGRect, _ second: CGRect) -> Bool {
        guard first.width > 0, first.height > 0, second.width > 0, second.height > 0 else { return false }
        let intersection = first.intersection(second)
        let area = intersection.width * intersection.height
        let smaller = min(first.width * first.height, second.width * second.height)
        let larger = max(first.width * first.height, second.width * second.height)
        return !intersection.isEmpty && area >= smaller * 0.35 && larger <= smaller * 4
    }

    private func observation(for request: VNTrackObjectRequest, on pixels: CVPixelBuffer) -> VNDetectedObjectObservation? {
        do {
            try handler.perform([request], on: pixels, orientation: .up)
            return request.results?.first as? VNDetectedObjectObservation
        } catch {
            return nil
        }
    }
}
