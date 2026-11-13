import CoreImage
import CoreML
import Foundation

struct VapeDetection: Sendable {
    let bounds: CGRect
    let score: Float
}

enum DetectorError: LocalizedError {
    case missingModel, invalidModel, failedPrediction

    var errorDescription: String? {
        switch self {
        case .missingModel: L10n.text("camera.error.modelMissing")
        case .invalidModel: L10n.text("camera.error.modelInvalid")
        case .failedPrediction: L10n.text("camera.error.prediction")
        }
    }
}

final class VapeDetector {
    private let model: MLModel
    private let inputName: String
    private let outputName: String
    private let vapeIndex: Int
    private let cigaretteIndex: Int
    private let size: Int
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private let canvas: CVPixelBuffer

    init(url: URL) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: configuration)
        let description = model.modelDescription
        guard let input = description.inputDescriptionsByName.values.first,
              let image = input.imageConstraint, image.pixelsWide == image.pixelsHigh,
              let output = description.outputDescriptionsByName.values.first,
              let shape = output.multiArrayConstraint?.shape.map(\.intValue),
              shape.count == 3, shape[0] == 1, shape[2] > 0,
              let metadata = description.metadata[.creatorDefinedKey] as? [String: String],
              let classNames = metadata["class_names"],
              let labels = try? JSONDecoder().decode([String].self, from: Data(classNames.utf8)),
              let vapeIndex = labels.firstIndex(of: "vape"),
              let cigaretteIndex = labels.firstIndex(of: "cigarette"),
              shape[1] == 4 + labels.count else {
            throw DetectorError.invalidModel
        }
        inputName = input.name
        outputName = output.name
        size = image.pixelsWide
        self.vapeIndex = vapeIndex
        self.cigaretteIndex = cigaretteIndex

        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            nil, size, size, kCVPixelFormatType_32BGRA, nil, &buffer
        )
        guard status == kCVReturnSuccess, let buffer else { throw DetectorError.invalidModel }
        canvas = buffer
    }

    func detections(in image: CIImage, region: CGRect, threshold: Float) throws -> [VapeDetection] {
        let crop = region.intersection(image.extent).integral
        guard crop.width > 1, crop.height > 1 else { return [] }
        let side = CGFloat(size)
        let scale = min(side / crop.width, side / crop.height)
        let fitted = CGRect(
            x: (side - crop.width * scale) / 2,
            y: (side - crop.height * scale) / 2,
            width: crop.width * scale, height: crop.height * scale
        )
        let letterboxed = image.cropped(to: crop)
            .transformed(by: .init(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: .init(scaleX: scale, y: scale))
            .transformed(by: .init(translationX: fitted.minX, y: fitted.minY))
        let gray = CIImage(color: CIColor(red: 0.447, green: 0.447, blue: 0.447))
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        ci.render(letterboxed.composited(over: gray).cropped(to: bounds),
                  to: canvas, bounds: bounds, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))

        let input = try MLDictionaryFeatureProvider(
            dictionary: [inputName: MLFeatureValue(pixelBuffer: canvas)]
        )
        let result = try model.prediction(from: input)
        guard let output = result.featureValue(for: outputName)?.multiArrayValue,
              output.dataType == .float32 else { throw DetectorError.failedPrediction }

        var candidates: [VapeDetection] = []
        output.withUnsafeBufferPointer(ofType: Float.self) { values in
            let rowStride = output.strides[1].intValue
            let columnStride = output.strides[2].intValue
            for i in 0..<output.shape[2].intValue {
                let offset = i * columnStride
                let score = values[(4 + vapeIndex) * rowStride + offset]
                let cigarette = values[(4 + cigaretteIndex) * rowStride + offset]
                guard score >= threshold, score >= cigarette else { continue }

                let x = CGFloat(values[offset])
                let y = CGFloat(values[rowStride + offset])
                let width = CGFloat(values[2 * rowStride + offset])
                let height = CGFloat(values[3 * rowStride + offset])
                guard x.isFinite, y.isFinite, width.isFinite, height.isFinite,
                      width > 0, height > 0 else { continue }
                let box = CGRect(x: x - width / 2, y: side - y - height / 2, width: width, height: height)
                    .intersection(fitted)
                guard !box.isEmpty else { continue }
                let frame = image.extent
                let normalized = CGRect(
                    x: ((box.minX - fitted.minX) / scale + crop.minX - frame.minX) / frame.width,
                    y: ((box.minY - fitted.minY) / scale + crop.minY - frame.minY) / frame.height,
                    width: box.width / scale / frame.width,
                    height: box.height / scale / frame.height
                )
                guard normalized.width * normalized.height < 0.98 else { continue }
                candidates.append(VapeDetection(bounds: normalized, score: score))
            }
        }

        var kept: [VapeDetection] = []
        for candidate in candidates.sorted(by: { $0.score > $1.score }) {
            let overlaps = kept.contains { previous in
                let intersection = previous.bounds.intersection(candidate.bounds)
                guard !intersection.isEmpty else { return false }
                let area = intersection.width * intersection.height
                let union = previous.bounds.width * previous.bounds.height
                    + candidate.bounds.width * candidate.bounds.height - area
                return area / union > 0.45
            }
            if !overlaps { kept.append(candidate) }
            if kept.count == 12 { break }
        }
        return kept
    }
}
