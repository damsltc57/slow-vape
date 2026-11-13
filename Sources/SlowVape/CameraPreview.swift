@preconcurrency import AVFoundation
import AppKit
import SwiftUI

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let frame: CameraFrame?

    func makeNSView(context: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_ view: PreviewView, context: Context) {
        view.preview.session = session
        view.frameData = frame
        view.updateBoxes()
    }
}

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    var frameData: CameraFrame?
    private let mouthLayer = CAShapeLayer()
    private let vapeLayer = CAShapeLayer()

    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(preview)
        layer?.addSublayer(mouthLayer)
        layer?.addSublayer(vapeLayer)
        preview.videoGravity = .resizeAspect
        for overlay in [mouthLayer, vapeLayer] {
            overlay.fillColor = NSColor.clear.cgColor
            overlay.lineWidth = 2
        }
        mouthLayer.strokeColor = NSColor.white.withAlphaComponent(0.82).cgColor
        vapeLayer.strokeColor = NSColor(srgbRed: 0.55, green: 0.88, blue: 0.76, alpha: 1).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        mouthLayer.frame = bounds
        vapeLayer.frame = bounds
        CATransaction.commit()
        updateBoxes()
    }

    func updateBoxes() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mouthLayer.path = path(frameData?.mouth)
        vapeLayer.path = path(frameData?.vape?.bounds)
        vapeLayer.lineDashPattern = frameData?.isTracked == true ? [5, 4] : nil
        CATransaction.commit()
    }

    private func path(_ rect: CGRect?) -> CGPath? {
        guard let rect else { return nil }
        let topLeft = CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
        let converted = preview.layerRectConverted(fromMetadataOutputRect: topLeft)
        let layerRect = CGRect(
            x: converted.minX, y: bounds.height - converted.maxY,
            width: converted.width, height: converted.height
        )
        return CGPath(roundedRect: layerRect, cornerWidth: 4, cornerHeight: 4, transform: nil)
    }
}
