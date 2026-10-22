import Charts
import SwiftUI
import TimeitCore

struct DashboardView: View {
    @Bindable var store: AppStore
    var body: some View {
        let entries = store.visibleEntries
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: store.periodTitle, subtitle: store.periodSubtitle) {
                    FilterChip(store: store)
                    PeriodControls(store: store)
                }
                TimerComposer(store: store)
                // Totals only move while a timer runs.
                TimelineView(.periodic(from: .now, by: store.running == nil ? 3600 : 30)) { context in
                    let summary = store.summary(entries: entries, now: context.date)
                    VStack(spacing: 20) {
                        MetricsRow(store: store, summary: summary)
                        HStack(alignment: .top, spacing: 16) {
                            WeeklyActivity(store: store, entries: entries, now: context.date).card()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            Breakdown(store: store, entries: entries, summary: summary, now: context.date).card()
                                .frame(width: 280).frame(maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
                SessionsCard(store: store, entries: entries)
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 64)
            .frame(maxWidth: 1160)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Metrics

private struct MetricsRow: View {
    let store: AppStore
    let summary: FinancialSummary
    var body: some View {
        let currency = store.workspace.profile.currency
        let goalSeconds = store.weeklyGoalSeconds * (store.period == .week ? 1 : 4.33)
        MetricStrip {
            Metric(
                label: "Temps travaillé", value: Display.duration(summary.seconds),
                detail: "\(Display.duration(summary.billableSeconds)) facturables"
            ) {
                let percent = Int((summary.seconds / goalSeconds * 100).rounded())
                VStack(spacing: 4) {
                    ProgressRing(value: summary.seconds / goalSeconds)
                    Text("\(percent) %").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.secondary)
                }
                .help("\(percent) % de l’objectif de \(store.workspace.profile.weeklyGoal) h par semaine")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(percent) % de l’objectif")
            }
            Metric(
                label: "Honoraires bruts", value: Display.money(summary.gross, currency: currency),
                detail: summary.unconvertedEntries.isEmpty
                    ? "Travail facturable · HT"
                    : "\(summary.unconvertedEntries.count) conversion(s) en attente",
                warning: !summary.unconvertedEntries.isEmpty)
            Metric(
                label: "Net estimé", value: Display.money(summary.net, currency: currency),
                detail: "Après cotisations et impôts", tint: Theme.positive)
        }
    }
}

/// Metrics side by side in one card, separated by dividers.
struct MetricStrip<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    if subview.id != subviews.first?.id { Divider().padding(.horizontal, 20) }
                    subview
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .card()
    }
}

struct Metric<Accessory: View>: View {
    let label: String
    let value: String
    let detail: String
    var warning = false
    var tint: Color = .primary
    @ViewBuilder var accessory: Accessory
    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).eyebrow()
                Text(value)
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint)
                    .lineLimit(1).minimumScaleFactor(0.6)
                HStack(spacing: 4) {
                    if warning { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange) }
                    Text(detail)
                }
                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            accessory
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

extension Metric where Accessory == EmptyView {
    init(label: String, value: String, detail: String, warning: Bool = false, tint: Color = .primary) {
        self.init(label: label, value: value, detail: detail, warning: warning, tint: tint) { EmptyView() }
    }
}

// MARK: - Breakdown

private struct Breakdown: View {
    let store: AppStore
    let entries: [TimeEntry]
    let summary: FinancialSummary
    let now: Date
    private struct Slice: Identifiable {
        let project: Project
        let seconds: TimeInterval
        var id: UUID { project.id }
    }
    var body: some View {
        let currency = store.workspace.profile.currency
        let slices = Dictionary(grouping: entries, by: \.projectID)
            .compactMap { id, entries -> Slice? in
                guard let project = store.workspace.project(id) else { return nil }
                let seconds = store.trackedSeconds(entries, in: store.interval, now: now)
                return seconds > 0 ? Slice(project: project, seconds: seconds) : nil
            }
            .sorted { $0.seconds > $1.seconds }
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Répartition")
            HStack(spacing: 14) {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Temps", slice.seconds), innerRadius: .ratio(0.66), angularInset: 1.5)
                        .cornerRadius(2)
                        .foregroundStyle(slice.project.color.tint)
                }
                .chartLegend(.hidden)
                .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(slices.prefix(5)) { slice in
                        HStack(spacing: 6) {
                            ProjectMark(color: slice.project.color, size: 6)
                            Text(slice.project.name).lineLimit(1)
                            Spacer(minLength: 2)
                            Text("\(Int((slice.seconds / max(1, summary.seconds) * 100).rounded())) %")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
            Divider()
            VStack(spacing: 8) {
                row("Cotisations", Display.money(summary.contributions, currency: currency))
                row("Impôts", Display.money(summary.incomeTax, currency: currency))
                HStack {
                    Text("À provisionner").fontWeight(.semibold)
                    Spacer()
                    Text(Display.money(summary.contributions + summary.incomeTax, currency: currency))
                        .fontWeight(.semibold).monospacedDigit()
                }
                .font(.system(size: 12.5))
            }
            Text("Selon les taux de votre compte, figés avec chaque session.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
    }
    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
        .font(.system(size: 12))
    }
}

// MARK: - Weekly chart

struct WeeklyActivity: View {
    let store: AppStore
    /// Built once per refresh, so hovering the chart does not recompute it.
    private let points: [Point]
    @State private var selectedDay: Date?
    private struct Point: Identifiable {
        let day: Date
        let project: Project
        let hours: Double
        var id: String { "\(day.timeIntervalSince1970):\(project.id)" }
    }
    init(store: AppStore, entries: [TimeEntry], now: Date) {
        self.store = store
        let calendar = store.calendar
        let interval = store.interval
        // Segments are already split at local midnight, so one pass buckets them by day and project.
        var seconds: [Date: [UUID: TimeInterval]] = [:]
        for entry in entries {
            for segment in Finance.segments(of: entry, within: interval, now: now, calendar: calendar) {
                seconds[calendar.startOfDay(for: segment.start), default: [:]][entry.projectID, default: 0] +=
                    segment.duration
            }
        }
        let order = Dictionary(uniqueKeysWithValues: store.workspace.projects.enumerated().map { ($1.id, $0) })
        points = seconds.flatMap { day, byProject in
            byProject.compactMap { id, total in
                store.workspace.project(id).map { Point(day: day, project: $0, hours: total / 3600) }
            }
        }
        .sorted { ($0.day, order[$0.project.id] ?? 0) < ($1.day, order[$1.project.id] ?? 0) }
    }
    var body: some View {
        let totals = Dictionary(grouping: points) { $0.day }.mapValues { $0.reduce(0) { $0 + $1.hours } }
        let average = totals.isEmpty ? 0 : totals.values.reduce(0, +) / Double(totals.count)
        let selectedTotal = selectedDay.map { totals[store.calendar.startOfDay(for: $0)] ?? 0 }
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(
                title: store.period == .week ? "Rythme de la semaine" : "Rythme du mois",
                subtitle: selectedDay.map { $0.formatted(.dateTime.weekday(.wide).day().month(.wide)) }
                    ?? "Moyenne \(Display.duration(average * 3600)) par jour travaillé"
            ) {
                Text(Display.duration((selectedTotal ?? totals.values.reduce(0, +)) * 3600))
                    .font(.system(size: 17, weight: .medium, design: .rounded)).monospacedDigit()
            }
            Chart {
                ForEach(points) { point in
                    BarMark(
                        x: .value("Jour", point.day, unit: .day), y: .value("Heures", point.hours),
                        width: .ratio(store.period == .week ? 0.4 : 0.65)
                    )
                    .foregroundStyle(point.project.color.tint)
                    .opacity(
                        selectedDay == nil || store.calendar.isDate(point.day, inSameDayAs: selectedDay!) ? 1 : 0.35
                    )
                    .accessibilityLabel(
                        "\(point.project.name), \(point.day.formatted(.dateTime.weekday().day().month()))"
                    )
                    .accessibilityValue(Display.duration(point.hours * 3600))
                }
                if average > 0 {
                    RuleMark(y: .value("Moyenne", average))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .foregroundStyle(.secondary.opacity(0.6))
                }
            }
            .chartXSelection(value: $selectedDay)
            .chartXScale(domain: store.interval.start...store.interval.end.addingTimeInterval(-1))
            .chartYScale(domain: 0...max(8, (totals.values.max() ?? 8) * 1.1))
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: store.period == .week ? 1 : 5)) { value in
                    AxisValueLabel(centered: true) {
                        if let date = value.as(Date.self) {
                            let today = store.calendar.isDateInToday(date)
                            Text(
                                date.formatted(
                                    store.period == .week ? .dateTime.weekday(.abbreviated) : .dateTime.day())
                            )
                            .font(.system(size: 10.5, weight: today ? .semibold : .regular))
                            .foregroundStyle(today ? Theme.accent : .secondary)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Theme.divider)
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text("\(Int(hours)) h").font(.system(size: 9.5)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minHeight: 160)
        }
    }
}

// MARK: - Sessions

private struct SessionsCard: View {
    let store: AppStore
    let entries: [TimeEntry]
    var body: some View {
        let byDay = Dictionary(grouping: entries) { store.calendar.startOfDay(for: $0.start) }
        let shown = Dictionary(grouping: entries.prefix(14)) { store.calendar.startOfDay(for: $0.start) }
            .sorted { $0.key > $1.key }
        VStack(alignment: .leading, spacing: 6) {
            CardHeader(title: "Dernières sessions", subtitle: "\(entries.count) sur la période") {
                Button("Voir le calendrier") { store.screen = .calendar }
                    .buttonStyle(.link).font(.system(size: 12))
            }
            .padding(.horizontal, 6).padding(.bottom, 4)
            if entries.isEmpty {
                EmptyState(
                    symbol: "clock", title: "Rien sur cette période",
                    detail: "Lancez un timer ou ajoutez une session.",
                    action: "Ajouter une session"
                ) { store.entryEditor = EntryEditorRequest() }.frame(height: 240)
            } else {
                ForEach(shown, id: \.key) { day, dayEntries in
                    HStack {
                        Text(dayLabel(day)).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Text(Display.duration((byDay[day] ?? dayEntries).reduce(0) { $0 + $1.duration() }))
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 2)
                    ForEach(dayEntries) { entry in EntryRow(store: store, entry: entry) }
                }
            }
        }
        .card(padding: 12)
    }
    private func dayLabel(_ day: Date) -> String {
        if store.calendar.isDateInToday(day) { return "Aujourd’hui" }
        if store.calendar.isDateInYesterday(day) { return "Hier" }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized
    }
}

struct EntryRow: View {
    let store: AppStore
    let entry: TimeEntry
    @State private var hovered = false
    var body: some View {
        let project = store.workspace.project(entry.projectID)
        let resumable = store.canResume(entry)
        HStack(spacing: 12) {
            ProjectMark(color: project?.color ?? .coral)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.displayTitle).font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(
                        store.workspace.label(forProject: entry.projectID))
                    if !entry.billable { Text("· Non facturable") }
                }
                .font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 10)
            Text(
                Display.timeRange(entry, calendar: store.calendar)
            )
            .font(.system(size: 11.5)).foregroundStyle(.secondary).monospacedDigit()
            Group {
                if entry.end == nil {
                    TimelineView(.periodic(from: entry.start, by: 60)) { context in
                        Text(Display.duration(entry.duration(at: context.date)))
                    }
                } else {
                    Text(Display.duration(entry.duration()))
                }
            }
            .font(.system(size: 13, weight: .medium)).monospacedDigit().frame(width: 60, alignment: .trailing)
            Button {
                store.resume(entry)
            } label: {
                Image(systemName: "play.fill").font(.system(size: 10))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.accent)
            .frame(width: 22)
            .opacity(hovered ? 1 : 0)
            .help("Reprendre cette activité")
            .accessibilityLabel("Reprendre \(entry.title)")
            .disabled(!resumable)
        }
        .padding(.vertical, 8).padding(.horizontal, 8)
        .hoverHighlight()
        .liveLens(entry.end == nil ? project?.color.tint ?? Theme.accent : nil, radius: Theme.rowRadius)
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { store.entryEditor = EntryEditorRequest(entry: entry) }
        .contextMenu {
            Button("Modifier…", systemImage: "pencil") { store.entryEditor = EntryEditorRequest(entry: entry) }
            Button("Reprendre cette activité", systemImage: "play") { store.resume(entry) }
                .disabled(!resumable)
            Divider()
            Button("Supprimer", systemImage: "trash", role: .destructive) { store.delete(entry) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Modifier") { store.entryEditor = EntryEditorRequest(entry: entry) }
    }
}
