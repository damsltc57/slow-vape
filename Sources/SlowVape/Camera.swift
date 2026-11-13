@preconcurrency import AVFoundation
import CoreImage
import Foundation
import SlowVapeCore
import Vision

struct CameraFrame: Sendable {
    let mouth: CGRect?
    let vape: VapeDetection?
    let isTracked: Bool
    let nearMouth: Bool
    let countedPuff: Bool
}

enum CameraUpdate: Sendable {
    case running, frame(CameraFrame), failure(String)
}

/// All capture and analysis state is owned by the serial queue. The preview
/// reads the session through AVCaptureVideoPreviewLayer's own synchronization.
final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "slow-vape.camera", qos: .userInitiated)
    private let onUpdate: @Sendable (CameraUpdate) -> Void
    private let faces = VNDetectFaceLandmarksRequest()
    private let hands = VNDetectHumanHandPoseRequest()
    private var detector: VapeDetector?
    private var configured = false
    private var lastFrameTime = -Double.infinity
    private var counter = PuffCounter()
    private var tracker = VapeTracker()
    private var grip = VapeGrip()
    private var threshold: Float = 0.40
    private var failureCount = 0

    init(onUpdate: @escaping @Sendable (CameraUpdate) -> Void) {
        self.onUpdate = onUpdate
        super.init()
        hands.maximumHandCount = 2
    }

    func start(threshold: Float) {
        queue.async {
            self.threshold = threshold
            do {
                if self.detector == nil {
                    guard let url = Bundle.main.url(forResource: "VapeDetector", withExtension: "mlmodelc")
                    else { throw DetectorError.missingModel }
                    self.detector = try VapeDetector(url: url)
                }
                if !self.configured { try self.configure() }
                self.lastFrameTime = -.infinity
                self.resetAnalysis()
                self.failureCount = 0
                self.session.startRunning()
                self.onUpdate(self.session.isRunning
                    ? .running : .failure(L10n.text("camera.error.start")))
            } catch {
                self.onUpdate(.failure(error is CameraError || error is DetectorError
                    ? error.localizedDescription : L10n.text("camera.error.stream")))
            }
        }
    }

    func stop() {
        queue.async {
            if self.session.isRunning { self.session.stopRunning() }
            self.resetAnalysis()
        }
    }

    func setThreshold(_ value: Float) {
        queue.async {
            self.threshold = value
            self.resetAnalysis()
        }
    }

    private func resetAnalysis() {
        counter = PuffCounter()
        tracker.reset()
        grip = VapeGrip()
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(for: .video) else {
            throw CameraError.noDevice
        }
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        guard session.canAddInput(input) else { throw CameraError.configuration }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw CameraError.configuration
        }
        session.addOutput(output)
        output.setSampleBufferDelegate(self, queue: queue)
        configured = true
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        dispatchPrecondition(condition: .onQueue(queue))
        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        guard time.isFinite, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer), let detector else { return }
        if time < lastFrameTime {
            lastFrameTime = -.infinity
            resetAnalysis()
        }
        guard time - lastFrameTime >= 0.085 else { return }
        lastFrameTime = time

        do {
            let frame = try analyze(pixels, detector: detector, time: time)
            failureCount = 0
            onUpdate(.frame(frame))
        } catch {
            resetAnalysis()
            failureCount += 1
            if failureCount == 3 {
                onUpdate(.failure(error is DetectorError ? error.localizedDescription : L10n.text("camera.error.stream")))
            }
        }
    }

    private func analyze(_ pixels: CVPixelBuffer, detector: VapeDetector, time: Double) throws -> CameraFrame {
        let tracked = tracker.advance(on: pixels, at: time)
        try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([faces])
        let face = faces.results?.max {
            $0.boundingBox.width < $1.boundingBox.width
        }
        guard let face, let lips = face.landmarks?.outerLips, !lips.normalizedPoints.isEmpty else {
            _ = counter.update(.uncertain, at: time)
            return CameraFrame(mouth: nil, vape: nil, isTracked: false, nearMouth: false, countedPuff: false)
        }

        let box = face.boundingBox
        let points = lips.normalizedPoints
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 0
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 0
        let mouth = CGRect(
            x: box.minX + minX * box.width, y: box.minY + minY * box.height,
            width: (maxX - minX) * box.width, height: (maxY - minY) * box.height
        )
        let image = CIImage(cvPixelBuffer: pixels)
        let focus = CGRect(
            x: mouth.midX - box.width * 1.6, y: mouth.midY - box.height * 0.95,
            width: box.width * 3.2, height: box.height * 1.65
        )
        let region = CGRect(
            x: focus.minX * image.extent.width, y: focus.minY * image.extent.height,
            width: focus.width * image.extent.width, height: focus.height * image.extent.height
        )
        var candidates = try detector.detections(in: image, region: region, threshold: threshold)
        if candidates.isEmpty, tracked == nil,
           region.intersection(image.extent).width < image.extent.width * 0.85 {
            candidates = try detector.detections(in: image, region: image.extent, threshold: threshold)
        }

        let near = candidates.first { isNear($0.bounds, mouth: mouth, face: box) }
        let detected: VapeDetection?
        if let tracked, near == nil || isNear(tracked, mouth: mouth, face: box) {
            detected = candidates.first { VapeTracker.matches($0.bounds, tracked) }
        } else {
            detected = near ?? candidates.first
        }
        if let detected { tracker.confirm(detected.bounds, on: pixels, at: time) }

        let isTracked = detected == nil && tracked != nil
        let best = detected ?? tracked.map { VapeDetection(bounds: $0, score: 0) }
        var signal: PuffCounter.Signal
        if let best {
            let distance = horizontalAndVerticalDistance(best.bounds, mouth)
            if isNear(best.bounds, mouth: mouth, face: box) {
                signal = .near
            } else if distance.x > box.width * 0.18 || distance.y > box.height * 0.13 {
                signal = .away
            } else {
                signal = .uncertain
            }
        } else {
            signal = .absent
        }
        // When only a fragment of the vape is visible, its box can sit below
        // the lips. Follow the confirmed grip through contact and withdrawal.
        let canConfirmGrip = detected.map {
            let gap = horizontalAndVerticalDistance($0.bounds, mouth)
            return gap.x <= box.width * 0.30 && gap.y <= box.height * 0.32
        } ?? false
        if grip.isActive || (signal != .near && canConfirmGrip) {
            let confirmedVape = canConfirmGrip ? detected?.bounds : nil
            let wasActive = grip.isActive
            let observations: [VNHumanHandPoseObservation]
            do {
                try VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([hands])
                observations = hands.results ?? []
            } catch {
                observations = []
            }
            let handSignal = grip.signal(observations: observations, confirmedVape: confirmedVape,
                                         mouth: mouth, face: box, time: time)
            if let handSignal, detected == nil || signal != .near {
                signal = handSignal
            }
            if wasActive, !grip.isActive, handSignal == .uncertain {
                counter = PuffCounter()
            }
        }
        let counted = counter.update(signal, at: time)
        return CameraFrame(mouth: mouth, vape: best, isTracked: isTracked, nearMouth: counter.isNearMouth, countedPuff: counted)
    }

    private func isNear(_ vape: CGRect, mouth: CGRect, face: CGRect) -> Bool {
        let distance = horizontalAndVerticalDistance(vape, mouth)
        return distance.x <= face.width * 0.10 && distance.y <= face.height * 0.075
    }

    private func horizontalAndVerticalDistance(_ first: CGRect, _ second: CGRect) -> CGPoint {
        CGPoint(x: max(first.minX - second.maxX, second.minX - first.maxX, 0),
                y: max(first.minY - second.maxY, second.minY - first.maxY, 0))
    }
}

private enum CameraError: LocalizedError {
    case noDevice, configuration

    var errorDescription: String? {
        switch self {
        case .noDevice: L10n.text("camera.error.noDevice")
        case .configuration: L10n.text("camera.error.configuration")
        }
    }
}
