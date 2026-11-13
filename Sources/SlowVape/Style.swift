import AppKit
import SwiftUI

enum Ink {
    static let background = Color(red: 0.072, green: 0.082, blue: 0.077)
    static let rail = Color(red: 0.098, green: 0.111, blue: 0.102)
    static let surface = Color(red: 0.118, green: 0.132, blue: 0.119)
    static let text = Color(red: 0.95, green: 0.96, blue: 0.92)
    static let muted = Color(red: 0.69, green: 0.73, blue: 0.68)
    static let lime = Color(red: 0.79, green: 0.89, blue: 0.48)
    static let amber = Color(red: 1, green: 0.73, blue: 0.43)
    static let red = Color(red: 1, green: 0.59, blue: 0.52)
    static let line = Color.white.opacity(0.13)
}

struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .foregroundStyle(Ink.background)
            .background(Ink.lime.opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.40),
                        in: RoundedRectangle(cornerRadius: 8))
    }
}

@MainActor
enum Brand {
    static let mark: NSImage? = Bundle.main.url(forResource: "BrandMark", withExtension: "png")
        .flatMap { NSImage(contentsOf: $0) }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 9) {
            if let mark = Brand.mark {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 19, height: 19)
                    .foregroundStyle(Ink.lime)
            }
            Text("Slow Vape").font(.system(size: 17, weight: .semibold))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Slow Vape")
    }
}

struct CameraTest: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color.black.opacity(0.54)
                if let camera = model.camera, model.cameraStatus == .running {
                    CameraPreview(session: camera.session, frame: model.frame)
                } else {
                    Image(systemName: "video.slash")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Ink.muted)
                        .accessibilityHidden(true)
                }
            }
            .frame(height: 204)
            .clipShape(.rect(cornerRadius: 12))
            .accessibilityLabel(L10n.text("camera.preview"))

            HStack {
                Text(model.cameraMessage)
                    .foregroundStyle(Ink.muted)
                    .font(.callout)
                Spacer()
                Button(model.canStart ? L10n.text("camera.start") : L10n.text("camera.pause")) {
                    if model.canStart { model.start() } else { model.stop() }
                }
            }
        }
    }
}

struct LimitsForm: View {
    @Binding var hourly: String
    @Binding var daily: String

    var body: some View {
        VStack(spacing: 0) {
            field(L10n.text("limits.lastHour"), caption: L10n.text("limits.hourlyCaption"), value: $hourly)
            Divider()
            field(L10n.text("limits.today"), caption: L10n.text("limits.dailyCaption"), value: $daily)
        }
        .padding(.horizontal, 16)
        .background(Ink.surface, in: .rect(cornerRadius: 12))
    }

    private func field(_ title: String, caption: String, value: Binding<String>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(caption).font(.callout).foregroundStyle(Ink.muted)
            }
            Spacer()
            TextField(title, text: value, prompt: Text("—"))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .accessibilityLabel(title)
                .monospacedDigit()
                .frame(width: 72)
                .controlSize(.large)
            Text(L10n.text("limits.unit")).font(.callout).foregroundStyle(Ink.muted)
        }
        .padding(.vertical, 14)
    }

    static func value(_ input: String) -> Int? {
        Int(input.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { (1...9999).contains($0) ? $0 : nil }
    }

    static func isValid(_ input: String) -> Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value(input) != nil
    }
}
