import ServiceManagement
import SlowVapeCore
import SwiftUI

struct SettingsView: View {
    let model: AppModel
    let previewSound: (Double) -> Void
    let previewAlert: () -> Void

    @State private var hourly = ""
    @State private var daily = ""
    @State private var launchStatus = SMAppService.Status.notRegistered
    @State private var launchError: String?
    @State private var requestingNotifications = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(L10n.text("settings.title")).font(.system(size: 38, weight: .bold)).tracking(-1.2)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.text("settings.limits")).font(.title2.weight(.semibold))
                LimitsForm(hourly: $hourly, daily: $daily)
                HStack {
                    Text(valid ? L10n.text("settings.limitsHint") : L10n.text("limits.invalid"))
                        .font(.callout)
                        .foregroundStyle(valid ? Ink.muted : Ink.red)
                    Spacer()
                    Button(L10n.text("settings.save")) {
                        edit {
                            $0.hourlyLimit = LimitsForm.value(hourly)
                            $0.dailyLimit = LimitsForm.value(daily)
                        }
                    }
                    .buttonStyle(PrimaryButton())
                    .disabled(!valid)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 13) {
                Text(L10n.text("settings.alerts")).font(.title2.weight(.semibold))
                HStack {
                    Slider(value: Binding(get: { model.preferences.volume }, set: { value in edit { $0.volume = value } }), in: 0...1) {
                        Text(L10n.text("settings.volume"))
                    }
                    .accessibilityValue(model.preferences.volume.formatted(.percent))
                    .frame(maxWidth: 310)
                    Text(model.preferences.volume.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(Ink.muted)
                        .frame(width: 50, alignment: .trailing)
                    Button(L10n.text("settings.play")) { previewSound(model.preferences.volume) }
                    Button(L10n.text("settings.previewAlert"), action: previewAlert)
                }
                Text(L10n.text("settings.reminder"))
                    .font(.callout)
                    .foregroundStyle(Ink.muted)
                Toggle(L10n.text("settings.warning"), isOn: notificationBinding(\.gentleNotifications))
                    .disabled(requestingNotifications)
                Toggle(L10n.text("settings.puffNotifications"), isOn: notificationBinding(\.puffNotifications))
                    .disabled(requestingNotifications)
                if let error = model.notificationsError {
                    Text(error).font(.callout).foregroundStyle(Ink.amber)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 13) {
                Text(L10n.text("settings.camera")).font(.title2.weight(.semibold))
                Toggle(L10n.text("settings.login"), isOn: Binding(
                    get: { launchStatus == .enabled || launchStatus == .requiresApproval }, set: { value in setLaunchAtLogin(value) }
                ))
                if launchStatus == .requiresApproval {
                    Button(L10n.text("settings.loginSystem")) { SMAppService.openSystemSettingsLoginItems() }
                }
                if let launchError { Text(launchError).font(.callout).foregroundStyle(Ink.amber) }
                Toggle(L10n.text("settings.autostart"), isOn: Binding(
                    get: { model.preferences.startCameraAtLaunch }, set: { value in edit { $0.startCameraAtLaunch = value } }
                ))
                Slider(value: Binding(
                    get: { model.preferences.sensitivity }, set: { value in edit { $0.sensitivity = value } }
                ), in: 0...1) { Text(L10n.text("settings.sensitivity")) }
                    .frame(maxWidth: 350)
                CameraTest(model: model)
            }
        }
        .onAppear {
            hourly = model.preferences.hourlyLimit.map(String.init) ?? ""
            daily = model.preferences.dailyLimit.map(String.init) ?? ""
            launchStatus = SMAppService.mainApp.status
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchStatus = SMAppService.mainApp.status
        }
    }

    private var valid: Bool { LimitsForm.isValid(hourly) && LimitsForm.isValid(daily) }

    private func notificationBinding(_ setting: WritableKeyPath<Preferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.preferences[keyPath: setting] },
            set: { enabled in
                requestingNotifications = true
                Task {
                    await model.setNotification(setting, enabled: enabled)
                    requestingNotifications = false
                }
            }
        )
    }

    private func edit(_ change: (inout Preferences) -> Void) {
        var settings = model.preferences
        change(&settings)
        model.savePreferences(settings)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        launchError = nil
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            launchError = L10n.text("settings.loginError")
        }
        launchStatus = SMAppService.mainApp.status
    }
}

struct LimitAlertView: View {
    let model: AppModel
    let limits: Set<UsageLimit>
    let demo: Bool
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 25))
                .foregroundStyle(Ink.red)
                .accessibilityHidden(true)
            Text(demo ? L10n.text("alert.preview") : L10n.text("alert.reachedTitle"))
                .font(.system(size: 42, weight: .bold))
                .tracking(-1.3)
                .accessibilityAddTraits(.isHeader)
            Text(demo ? L10n.text("alert.previewMessage") : L10n.text("alert.message"))
                .font(.title3)
                .foregroundStyle(Ink.text)
            if !demo {
                let usage = model.usage
                ForEach(UsageLimit.allCases.filter { limits.contains($0) }, id: \.self) { limit in
                    if let goal = model.preferences[limit] {
                        Text(L10n.format("alert.count", limit.title, L10n.number(usage[limit]), L10n.number(goal)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(Ink.red)
                    }
                }
            }
            Spacer(minLength: 3)
            Button(L10n.text("alert.close"), action: dismiss)
                .buttonStyle(PrimaryButton())
                .keyboardShortcut(.defaultAction)
                .onExitCommand(perform: dismiss)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Color(red: 0.26, green: 0.11, blue: 0.10), Ink.background],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .foregroundStyle(Ink.text)
    }
}
