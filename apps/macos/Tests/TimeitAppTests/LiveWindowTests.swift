import AppKit
import PDFKit
import SwiftUI
import Testing
import TimeitCore

@testable import TimeitApp

/// Tests that need a logged-in window server: Liquid Glass only draws in a live window.
/// Serialized because the render-cost check measures the whole process.
@MainActor @Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["TIMEIT_RENDER_DIR"] != nil))
struct LiveWindowTests {
    /// Shows each screen in a floating window and captures it into TIMEIT_RENDER_DIR.
    @Test func nativeViewPreviews() async throws {
        let directory = URL(fileURLWithPath: ProcessInfo.processInfo.environment["TIMEIT_RENDER_DIR"]!)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = AppStore(database: try LocalDatabase(), demo: true)
        NSApplication.shared.setActivationPolicy(.regular)
        func render<V: View>(_ view: V, name: String, size: NSSize, appearance: NSAppearance.Name = .darkAqua)
            async throws
        {
            let window = NSWindow(
                contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size),
                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.titlebarAppearsTransparent = true
            window.appearance = NSAppearance(named: appearance)
            window.level = .floating
            window.contentView = NSHostingView(rootView: view.tint(Theme.accent))
            window.orderFrontRegardless()
            try await Task.sleep(for: .seconds(2))
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = [
                "-x", "-o", "-l", String(window.windowNumber), directory.appendingPathComponent(name + ".png").path,
            ]
            try capture.run()
            capture.waitUntilExit()
            window.orderOut(nil)
            #expect(capture.terminationStatus == 0)
        }
        let windowSize = NSSize(width: 1280, height: 860)
        try await render(ContentView(store: store), name: "dashboard-dark", size: windowSize)
        try await render(ContentView(store: store), name: "dashboard-light", size: windowSize, appearance: .aqua)
        store.screen = .calendar
        try await render(ContentView(store: store), name: "calendar", size: windowSize)
        store.screen = .projects
        try await render(ContentView(store: store), name: "projects", size: windowSize)
        store.screen = .reports
        try await render(ContentView(store: store), name: "reports", size: windowSize, appearance: .aqua)
        store.screen = .overview
        store.start(project: store.workspace.projects[1], title: "Composants et interactions")
        try await render(ContentView(store: store), name: "running-timer", size: windowSize)
        try await render(
            MenuBarView(store: store).background(.regularMaterial), name: "menu-bar",
            size: NSSize(width: 340, height: 520))
        try await render(
            ProjectEditor(store: store, request: ProjectEditorRequest()), name: "project-editor",
            size: NSSize(width: 580, height: 600))
        try await render(
            EntryEditor(store: store, request: EntryEditorRequest(entry: store.workspace.entries[0])),
            name: "session-editor", size: NSSize(width: 580, height: 500))
        try await render(
            MonthCalendar(selection: .now, calendar: store.calendar, latest: .now) { _ in }.padding(12),
            name: "date-picker", size: NSSize(width: 260, height: 300))
        try await render(
            ComboboxList(
                options: Locale.commonISOCurrencyCodes.sorted().prefix(12).map {
                    ComboboxOption(id: $0, title: $0, detail: Locale.current.localizedString(forCurrencyCode: $0))
                },
                selection: "EUR", searchPrompt: "Code ou nom de devise…", create: nil,
                onPick: { _ in }, onCreate: { _ in }, onClose: {}),
            name: "combobox", size: NSSize(width: 300, height: 340))
        store.showLauncher = true
        try await render(ContentView(store: store), name: "command-palette", size: windowSize)
        let reportURL = directory.appendingPathComponent("activity-report.pdf")
        let report = ReportPrintView(
            workspace: store.workspace, entries: store.workspace.entries.filter(\.billable),
            interval: store.calendar.dateInterval(of: .month, for: .now)!)
        #expect(report.write(to: reportURL))
        let pdf = try #require(PDFDocument(url: reportURL))
        #expect(pdf.pageCount >= 2)
        #expect(pdf.string?.contains("Relevé d’activité") == true)
        #expect(pdf.string?.contains("Cotisations") == false)
        if let first = pdf.page(at: 0),
            let tiff = first.thumbnail(of: NSSize(width: 595, height: 842), for: .mediaBox).tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:])
        {
            try png.write(to: directory.appendingPathComponent("activity-report-page-1.png"))
        }
    }

    /// A running timer must not keep the window recompositing every frame.
    @Test func runningTimerStaysCheapToRender() async throws {
        let store = AppStore(database: try LocalDatabase(), demo: true)
        NSApplication.shared.setActivationPolicy(.regular)
        store.start(project: store.workspace.projects[1], title: "Mesure")
        func cpuSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        for screen in [Screen.overview, .calendar] {
            store.screen = screen
            let window = NSWindow(
                contentRect: NSRect(x: 80, y: 80, width: 1280, height: 860),
                styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
            window.level = .floating
            window.contentView = NSHostingView(rootView: ContentView(store: store))
            window.orderFrontRegardless()
            try await Task.sleep(for: .seconds(2))
            let start = cpuSeconds()
            try await Task.sleep(for: .seconds(5))
            let share = (cpuSeconds() - start) / 5
            window.orderOut(nil)
            #expect(share < 0.1, "\(screen) used \(Int(share * 100)) % CPU with a running timer")
        }
    }
}
