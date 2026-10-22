import AppKit
import SwiftUI
import TabularData
import TimeitCore
import UniformTypeIdentifiers

struct ReportsView: View {
    @Bindable var store: AppStore
    var body: some View {
        let entries = store.visibleEntries
        let summary = store.summary(entries: entries)
        let currency = store.workspace.profile.currency
        let rows = Dictionary(grouping: entries, by: \.projectID)
            .compactMap { id, entries in store.workspace.project(id).map { ($0, store.summary(entries: entries)) } }
            .sorted { $0.1.seconds > $1.1.seconds }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "Rapports", subtitle: store.periodSubtitle) {
                    FilterChip(store: store)
                    PeriodControls(store: store)
                }
                MetricStrip {
                    Metric(
                        label: "Temps travaillé", value: Display.duration(summary.seconds),
                        detail: "\(entries.count) sessions")
                    Metric(
                        label: "Honoraires HT", value: Display.money(summary.gross, currency: currency),
                        detail: summary.unconvertedEntries.isEmpty
                            ? "Convertis en \(currency)" : "Total partiel · conversions en attente",
                        warning: !summary.unconvertedEntries.isEmpty)
                    Metric(
                        label: "Net estimé", value: Display.money(summary.net, currency: currency),
                        detail: "Après prélèvements", tint: Theme.positive)
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("Client / projet").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Temps").frame(width: 150, alignment: .trailing)
                        Text("Brut HT").frame(width: 120, alignment: .trailing)
                        Text("Net estimé").frame(width: 120, alignment: .trailing)
                    }
                    .eyebrow().padding(.horizontal, 10).padding(.bottom, 8)
                    if rows.isEmpty {
                        EmptyState(
                            symbol: "chart.bar.xaxis", title: "Rien à rapporter",
                            detail: "Aucune session sur cette période."
                        ).frame(height: 220)
                    }
                    ForEach(rows, id: \.0.id) { project, total in
                        Divider()
                        HStack(spacing: 12) {
                            HStack(spacing: 10) {
                                ProjectMark(color: project.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(project.name).font(.system(size: 13, weight: .medium))
                                    Text(store.workspace.client(for: project)?.name ?? "").font(.system(size: 11.5))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            HStack(spacing: 10) {
                                ShareBar(value: total.seconds / max(1, summary.seconds), tint: project.color.tint)
                                Text(Display.duration(total.seconds)).frame(width: 60, alignment: .trailing)
                            }
                            .frame(width: 150, alignment: .trailing)
                            Text(
                                total.unconvertedEntries.isEmpty
                                    ? Display.money(total.gross, currency: currency) : "En attente"
                            ).frame(width: 120, alignment: .trailing)
                            Text(
                                total.unconvertedEntries.isEmpty
                                    ? Display.money(total.net, currency: currency) : "En attente"
                            ).foregroundStyle(Theme.positive).frame(width: 120, alignment: .trailing)
                        }
                        .font(.system(size: 13)).monospacedDigit()
                        .padding(.horizontal, 10).padding(.vertical, 10)
                    }
                }
                .card(padding: 10)
                HStack(spacing: 10) {
                    Label(
                        "Montants du travail effectué sur la période, pas des paiements reçus. Tarifs et prélèvements sont figés dans chaque session.",
                        systemImage: "info.circle"
                    )
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                    Button("Exporter CSV", systemImage: "tablecells") { exportCSV() }.buttonStyle(.glass)
                    Button("Relevé PDF", systemImage: "doc.richtext") { exportPDF() }.buttonStyle(.glassProminent)
                }
            }
            .padding(.horizontal, Theme.gutter).padding(.top, 12).padding(.bottom, 64)
            .frame(maxWidth: 1160).frame(maxWidth: .infinity)
        }
    }
    private func destination(type: UTType, name: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = name
        return panel.runModal() == .OK ? panel.url : nil
    }
    private func exportCSV() {
        guard
            let url = destination(
                type: .commaSeparatedText,
                name: "Timeit-\(WireFormat.day(store.interval.start, calendar: store.calendar)).csv")
        else { return }
        let entries = store.visibleEntries.sorted { $0.start < $1.start }
        var frame = DataFrame()
        func column(_ name: String, _ transform: (TimeEntry) -> String) {
            frame.append(column: Column(name: name, contents: entries.map(transform)))
        }
        // Export exact strings, avoiding numeric inference and spreadsheet formula execution.
        func safe(_ text: String) -> String {
            ["=", "+", "-", "@", "\t", "\r"].contains(String(text.prefix(1))) ? "'" + text : text
        }
        column("Client") {
            safe(store.workspace.project($0.projectID).flatMap { store.workspace.client(for: $0) }?.name ?? "")
        }
        column("Projet") { safe(store.workspace.project($0.projectID)?.name ?? "") }
        column("Activité") { safe($0.title) }
        column("Début ISO 8601") { $0.start.ISO8601Format() }
        column("Fin ISO 8601") { $0.end?.ISO8601Format() ?? "" }
        let interval = store.interval
        column("Secondes dans la période") { String(Int(store.trackedSeconds([$0], in: interval))) }
        column("Facturable") { $0.billable ? "oui" : "non" }
        column("Devise d’origine") { $0.currency }
        column("Tarif horaire") { $0.hourlyRate }
        column("Cotisations %") { $0.contributions }
        column("Impôts %") { $0.incomeTax }
        do { try frame.writeCSV(to: url) } catch { store.showError(error) }
    }
    private func exportPDF() {
        guard let url = destination(type: .pdf, name: "Relevé-Timeit.pdf") else { return }
        let entries = store.visibleEntries.filter(\.billable).sorted { $0.start < $1.start }
        let report = ReportPrintView(workspace: store.workspace, entries: entries, interval: store.interval)
        if !report.write(to: url) { store.errorMessage = "Le relevé PDF n’a pas pu être créé." }
    }
}

private struct ShareBar: View {
    let value: Double
    let tint: Color
    var body: some View {
        Capsule().fill(Color.primary.opacity(0.07)).frame(width: 64, height: 4)
            .overlay(alignment: .leading) {
                Capsule().fill(tint).frame(width: 64 * min(1, max(0, value)), height: 4)
            }
            .accessibilityHidden(true)
    }
}

@MainActor final class ReportPrintView: NSView {
    private let workspace: Workspace
    private let entries: [TimeEntry]
    private let interval: DateInterval
    private static let pageWidth: CGFloat = 530
    private static let pageHeight: CGFloat = 778
    private static let rowsPerPage = 14
    private let pageCount: Int
    override var isFlipped: Bool { true }
    init(workspace: Workspace, entries: [TimeEntry], interval: DateInterval) {
        self.workspace = workspace
        self.entries = entries
        self.interval = interval
        pageCount = max(1, (entries.count + Self.rowsPerPage - 1) / Self.rowsPerPage)
        super.init(frame: NSRect(x: 0, y: 0, width: Self.pageWidth, height: CGFloat(pageCount) * Self.pageHeight))
    }
    required init?(coder: NSCoder) { nil }
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: pageCount)
        return true
    }
    override func rectForPage(_ page: Int) -> NSRect {
        NSRect(x: 0, y: CGFloat(page - 1) * Self.pageHeight, width: Self.pageWidth, height: Self.pageHeight)
    }
    func write(to url: URL) -> Bool {
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.paperSize = NSSize(width: 595, height: 842)
        info.topMargin = 32
        info.bottomMargin = 32
        info.leftMargin = 32
        info.rightMargin = 32
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        let operation = NSPrintOperation(view: self, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        return operation.run()
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        func text(
            _ string: String, x: CGFloat, y: CGFloat, size: CGFloat = 10, bold: Bool = false, width: CGFloat = 500
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            (string as NSString).draw(
                in: NSRect(x: x, y: y, width: width, height: size * 1.6),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
                    .foregroundColor: NSColor.black, .paragraphStyle: paragraph,
                ])
        }
        for page in 0..<pageCount {
            let top = CGFloat(page) * Self.pageHeight
            guard rectForPage(page + 1).intersects(dirtyRect) else { continue }
            text("timeit / Relevé d’activité", x: 0, y: top, size: 23, bold: true)
            text(workspace.profile.name, x: 0, y: top + 42, size: 12)
            text(
                "\(interval.start.formatted(date: .abbreviated, time: .omitted)) – \(interval.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))",
                x: 0, y: top + 64)
            text("DATE", x: 0, y: top + 105, bold: true)
            text("PROJET / ACTIVITÉ", x: 90, y: top + 105, bold: true)
            text("DURÉE", x: 455, y: top + 105, bold: true)
            var y = top + 132
            for entry in entries.dropFirst(page * Self.rowsPerPage).prefix(Self.rowsPerPage) {
                text(entry.start.formatted(date: .abbreviated, time: .omitted), x: 0, y: y, width: 85)
                text(
                    workspace.label(forProject: entry.projectID, separator: " / "), x: 90,
                    y: y, bold: true, width: 350)
                text(entry.title, x: 90, y: y + 15, size: 9, width: 350)
                let seconds = Finance.seconds(of: entry, within: interval, now: .now, calendar: workspace.calendar)
                text(Display.duration(seconds), x: 455, y: y, width: 75)
                y += 42
            }
            text("\(page + 1) / \(pageCount)", x: 455, y: top + 750, size: 9, width: 75)
        }
    }
}
