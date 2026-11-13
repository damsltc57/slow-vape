import SwiftUI

struct Onboarding: View {
    let model: AppModel
    @State private var step = 0
    @State private var hourly = ""
    @State private var daily = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var headingFocused: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                Wordmark()
                Spacer()
                VStack(alignment: .leading, spacing: 15) {
                    progress(L10n.text("welcome.step"), index: 0)
                    progress(L10n.text("welcome.limitsStep"), index: 1)
                    progress(L10n.text("welcome.cameraStep"), index: 2)
                }
                Spacer()
                Label(L10n.text("welcome.privacy"), systemImage: "lock")
                    .font(.caption)
                    .foregroundStyle(Ink.muted)
            }
            .frame(width: 164, alignment: .leading)
            .padding(24)
            .background(Ink.rail)

            ScrollView {
                VStack(alignment: .leading, spacing: 21) {
                    switch step {
                    case 0: welcome
                    case 1: limits
                    default: test
                    }
                    if let error = model.storageError {
                        Text(error).foregroundStyle(Ink.red)
                        Button(L10n.text("storage.retry"), action: model.load)
                    }
                    controls
                }
                .frame(maxWidth: 570, alignment: .leading)
                .padding(.horizontal, 30)
                .padding(.vertical, 34)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .background {
                RadialGradient(colors: [Ink.surface, Ink.background], center: .topTrailing,
                               startRadius: 10, endRadius: 610)
            }
        }
    }

    private func progress(_ title: String, index: Int) -> some View {
        HStack(spacing: 9) {
            Image(systemName: index < step ? "checkmark.circle.fill" : index == step ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(index <= step ? Ink.lime : Ink.muted)
                .accessibilityHidden(true)
            Text(title)
                .font(.callout.weight(index == step ? .semibold : .regular))
                .foregroundStyle(index == step ? Ink.text : Ink.muted)
        }
        .accessibilityAddTraits(index == step ? .isSelected : [])
    }

    private func heading(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 44, weight: .bold))
            .tracking(-1.7)
            .accessibilityAddTraits(.isHeader)
            .focusable()
            .focused($headingFocused)
    }

    private var welcome: some View {
        Group {
            heading(L10n.text("welcome.title"))
            Text(L10n.text("welcome.intro"))
                .font(.title3)
                .foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 14) {
                Label(L10n.text("welcome.how"), systemImage: "viewfinder")
                Label(L10n.text("welcome.data"), systemImage: "lock")
                Label(L10n.text("welcome.alert"), systemImage: "bell")
            }
            .font(.callout)
            .foregroundStyle(Ink.text)
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: .rect(cornerRadius: 12))
        }
    }

    private var limits: some View {
        Group {
            heading(L10n.text("welcome.limitsTitle"))
            Text(L10n.text("welcome.limitsBody"))
                .font(.title3)
                .foregroundStyle(Ink.muted)
            LimitsForm(hourly: $hourly, daily: $daily)
            if !valid {
                Text(L10n.text("limits.invalid")).font(.callout).foregroundStyle(Ink.red)
            }
        }
    }

    private var test: some View {
        Group {
            heading(L10n.text("welcome.cameraTitle"))
            Text(L10n.text("welcome.cameraBody"))
                .foregroundStyle(Ink.muted)
            CameraTest(model: model)
            Text(L10n.format("welcome.testCount", L10n.number(model.testCount)))
                .font(.callout.monospacedDigit())
                .foregroundStyle(Ink.muted)
                .contentTransition(.numericText())
        }
    }

    private var valid: Bool { LimitsForm.isValid(hourly) && LimitsForm.isValid(daily) }

    private var controls: some View {
        HStack(spacing: 12) {
            Button(step == 2 ? L10n.text("welcome.dashboard") : step == 0 ? L10n.text("welcome.begin") : L10n.text("welcome.continue")) {
                if step == 2 {
                    var settings = model.preferences
                    settings.hourlyLimit = LimitsForm.value(hourly)
                    settings.dailyLimit = LimitsForm.value(daily)
                    model.finishSetup(settings)
                } else {
                    go(to: step + 1)
                }
            }
            .buttonStyle(PrimaryButton())
            .disabled(step == 1 && !valid)
            if step > 0 {
                Button(L10n.text("welcome.back")) {
                    if step == 2 { model.stop() }
                    go(to: step - 1)
                }
            }
        }
    }

    private func go(to newStep: Int) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { step = newStep }
        headingFocused = true
    }
}
