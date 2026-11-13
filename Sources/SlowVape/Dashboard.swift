import Charts
import SlowVapeCore
import SwiftUI

struct RootView: View {
    let model: AppModel
    let previewSound: (Double) -> Void
    let previewAlert: () -> Void

    enum Section: CaseIterable {
        case dashboard
        case settings

        var title: String {
            switch self {
            case .dashboard: L10n.text("dashboard.title")
            case .settings: L10n.text("settings.title")
            }
        }

        var icon: String { self == .dashboard ? "chart.bar.xaxis" : "slider.horizontal.3" }
    }

    var body: some View {
        Group {
            if model.setupComplete {
                HStack(spacing: 0) {
                    sidebar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 25) {
                            if let error = model.storageError {
                                Label(error, systemImage: "exclamationmark.circle")
                                    .foregroundStyle(Ink.red)
                            }
                            switch model.section {
                            case .dashboard: Dashboard(model: model, openSettings: { model.section = .settings })
                            case .settings: SettingsView(model: model, previewSound: previewSound, previewAlert: previewAlert)
                            }
                        }
                        .frame(maxWidth: 960, alignment: .leading)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 28)
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            } else {
                Onboarding(model: model)
            }
        }
        .frame(minWidth: 800, maxWidth: .infinity, minHeight: 580, maxHeight: .infinity)
        .background(Ink.background)
        .foregroundStyle(Ink.text)
        .tint(Ink.lime)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            Wordmark().padding(.horizontal, 9)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Section.allCases, id: \.self) { target in
                    Button {
                        model.section = target
                    } label: {
                        Label(target.title, systemImage: target.icon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .background(model.section == target ? Ink.lime.opacity(0.12) : .clear, in: .rect(cornerRadius: 8))
                    .foregroundStyle(model.section == target ? Ink.lime : Ink.muted)
                    .accessibilityAddTraits(model.section == target ? .isSelected : [])
                }
            }
            Spacer()
            Button(L10n.text("menu.quit")) { NSApp.terminate(nil) }
                .buttonStyle(.link)
                .foregroundStyle(Ink.muted)
                .padding(.horizontal, 9)
        }
        .frame(width: 151, alignment: .leading)
        .padding(15)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Ink.rail)
    }
}

private struct Dashboard: View {
    let model: AppModel
    let openSettings: () -> Void
    @State private var period = HistoryPeriod.hours
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.text("dashboard.title"))
                        .font(.system(size: 38, weight: .bold))
                        .tracking(-1.2)
                        .accessibilityAddTraits(.isHeader)
                    Text(model.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(L10n.locale)))
                        .font(.callout)
                        .foregroundStyle(Ink.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    Label(model.cameraMessage, systemImage: model.isTracking ? "waveform" : "pause.circle")
                        .foregroundStyle(model.isTracking ? Ink.lime : Ink.muted)
                        .font(.callout)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 260, alignment: .trailing)
                    Button(model.canStart ? L10n.text("camera.startTracking") : L10n.text("camera.pause")) {
                        if model.canStart { model.start() } else { model.stop() }
                    }
                    .controlSize(.large)
                }
            }

            let usage = model.usage
            HStack(spacing: 0) {
                budget(.hour, count: usage.hour)
                Rectangle().fill(Ink.line).frame(width: 1).padding(.vertical, 14)
                budget(.day, count: usage.day)
            }
            .background(alignment: .topTrailing) {
                LinearGradient(colors: [Ink.surface, Ink.rail], startPoint: .topTrailing, endPoint: .bottomLeading)
                    .clipShape(.rect(cornerRadius: 14))
            }

            history

            HStack {
                Button(L10n.text("dashboard.undo"), systemImage: "arrow.uturn.backward", action: model.undoLast)
                    .disabled(model.data.events.isEmpty)
                Spacer()
                Button(L10n.text("dashboard.editLimits"), action: openSettings)
            }
        }
    }

    private func budget(_ limit: UsageLimit, count: Int) -> some View {
        let target = model.preferences[limit]
        let ratio = target.map { Double(count) / Double($0) } ?? 0
        let color = ratio >= 1 ? Ink.red : ratio >= 0.8 ? Ink.amber : Ink.lime
        return VStack(alignment: .leading, spacing: 9) {
            Text(limit.title).font(.headline).foregroundStyle(Ink.muted)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(L10n.number(count))
                    .font(.system(size: 42, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                if let target {
                    Text(verbatim: "/ \(L10n.number(target))").font(.title3.monospacedDigit()).foregroundStyle(Ink.muted)
                } else {
                    Text(L10n.text("limits.unit")).font(.callout).foregroundStyle(Ink.muted)
                }
            }
            if let target {
                ProgressView(value: min(1, ratio))
                    .tint(color)
                    .accessibilityLabel(limit.shortTitle)
                    .accessibilityValue(L10n.format("limits.accessibility", L10n.number(count), L10n.number(target)))
                Text(ratio >= 1 ? L10n.text("limits.reached") : ratio >= 0.8 ? L10n.format("limits.approaching", L10n.remaining(target - count)) : L10n.remaining(target - count))
                    .font(.callout)
                    .foregroundStyle(ratio >= 0.8 ? color : Ink.muted)
            } else {
                Text(L10n.text("limits.disabled")).font(.callout).foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(17)
    }

    private var history: some View {
        let bins = model.bins(period)
        let selected = selection.flatMap(Int.init).flatMap { bins.indices.contains($0) ? bins[$0] : nil }
        let maxCount = max(1, bins.map(\.count).max() ?? 0)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(L10n.text("history.title")).font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Picker(L10n.text("history.period"), selection: $period) {
                    Text(L10n.text("history.hours")).tag(HistoryPeriod.hours)
                    Text(L10n.text("history.days")).tag(HistoryPeriod.days)
                    Text(L10n.text("history.weeks")).tag(HistoryPeriod.weeks)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 232)
                .onChange(of: period) { selection = nil }
            }

            HStack {
                Text(period == .hours ? L10n.text("history.hourly") : period == .days ? L10n.text("history.daily") : L10n.text("history.weekly"))
                    .foregroundStyle(Ink.muted)
                Spacer()
                Text(selected.map { bin in
                    "\(detailLabel(bin)) · \(bin.monitored ? L10n.puffs(bin.count) : L10n.text("history.untracked"))"
                } ?? L10n.puffs(bins.reduce(0) { $0 + $1.count }))
                .monospacedDigit()
            }
            .font(.callout)

            Chart {
                ForEach(Array(bins.enumerated()), id: \.element.id) { index, bin in
                    if bin.count == 0 {
                        PointMark(x: .value(L10n.text("history.period"), String(index)), y: .value(L10n.text("history.puffs"), 0))
                            .symbolSize(16)
                            .foregroundStyle(bin.monitored ? Ink.lime.opacity(0.52) : Ink.muted.opacity(0.36))
                            .accessibilityLabel(detailLabel(bin))
                            .accessibilityValue(bin.monitored ? L10n.puffs(0) : L10n.text("history.untracked"))
                    } else {
                        BarMark(x: .value(L10n.text("history.period"), String(index)), y: .value(L10n.text("history.puffs"), bin.count), width: .ratio(0.66))
                            .foregroundStyle(Ink.lime)
                            .cornerRadius(3)
                            .opacity(selection == nil || selection == String(index) ? 1 : 0.58)
                            .accessibilityLabel(detailLabel(bin))
                            .accessibilityValue(L10n.puffs(bin.count))
                    }
                }
            }
            .chartXSelection(value: $selection)
            .chartXScale(domain: bins.indices.map(String.init))
            .chartYScale(domain: 0 ... Double(maxCount))
            .chartXAxis {
                let stride = period == .hours ? 4 : period == .days ? 3 : 2
                AxisMarks(values: bins.indices.filter { $0 % stride == 0 }.map(String.init)) { axis in
                    AxisValueLabel {
                        if let rawIndex = axis.as(String.self), let index = Int(rawIndex), bins.indices.contains(index) {
                            Text(shortLabel(bins[index])).foregroundStyle(Ink.muted)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    if let tick = value.as(Double.self), tick.rounded() == tick {
                        AxisGridLine().foregroundStyle(Ink.line)
                        AxisValueLabel { Text(tick.formatted(.number.locale(L10n.locale))).foregroundStyle(Ink.muted) }
                    }
                }
            }
            .frame(height: 172)

            HStack(spacing: 14) {
                legend(L10n.text("history.puffs"), color: Ink.lime)
                legend(L10n.text("history.zero"), color: Ink.lime.opacity(0.34))
                legend(L10n.text("history.untracked"), color: Ink.muted.opacity(0.24))
            }
            if !bins.contains(where: \.monitored) {
                Text(L10n.text("history.empty")).font(.callout).foregroundStyle(Ink.muted)
            }
        }
    }

    private func shortLabel(_ bin: HistoryPeriod.Bin) -> String {
        if period == .hours {
            let hour = Calendar.current.component(.hour, from: bin.interval.start)
            return String(format: "%02d:00", hour)
        }
        return bin.interval.start.formatted(.dateTime.day().month(.abbreviated).locale(L10n.locale))
    }

    private func detailLabel(_ bin: HistoryPeriod.Bin) -> String {
        if period == .hours {
            let formatter = DateFormatter()
            formatter.locale = L10n.locale
            formatter.dateFormat = "HH:mm ZZZZZ"
            return formatter.string(from: bin.interval.start)
        }
        guard period == .weeks else { return shortLabel(bin) }
        return L10n.format("history.weekOf", shortLabel(bin))
    }

    private func legend(_ label: String, color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(label)
        }
        .font(.caption)
        .foregroundStyle(Ink.muted)
    }
}
