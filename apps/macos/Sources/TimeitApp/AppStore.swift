import AppKit
import Foundation
import Observation
import TimeitCore

enum Screen: String, CaseIterable, Identifiable {
    case overview, calendar, projects, reports
    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Vue d’ensemble"
        case .calendar: "Calendrier"
        case .projects: "Clients & projets"
        case .reports: "Rapports"
        }
    }
    var symbol: String {
        switch self {
        case .overview: "sparkles.rectangle.stack"
        case .calendar: "calendar"
        case .projects: "folder.fill"
        case .reports: "chart.bar.xaxis"
        }
    }
}
enum ReportPeriod {
    case week, month
    var component: Calendar.Component { self == .week ? .weekOfYear : .month }
}
struct EntryEditorRequest: Identifiable {
    let id = UUID()
    var entry: TimeEntry?
    var start: Date?
}
struct ProjectEditorRequest: Identifiable {
    let id = UUID()
    var project: Project?
}

@MainActor @Observable
final class AppStore {
    private(set) var state = LocalState()
    private(set) var isDemo = false
    private(set) var startupError: String?
    private(set) var syncLabel = "Sur ce Mac"
    private(set) var isSyncing = false
    private(set) var isConnecting = false
    private(set) var connected = false
    var errorMessage: String?
    var conflict: RemoteWorkspace?
    var screen: Screen? = .overview
    var period: ReportPeriod = .week
    var anchorDate = Date.now
    var projectFilter: UUID?
    var entryEditor: EntryEditorRequest?
    var projectEditor: ProjectEditorRequest?
    var showLauncher = false
    var launcherQuery = ""
    var timerTitle = ""
    var timerProjectID: UUID?
    var serverURL = UserDefaults.standard.string(forKey: "serverURL") ?? "http://127.0.0.1:4318"
    private var database: LocalDatabase?
    private var realDatabase: LocalDatabase?
    private var deletedEntries: [TimeEntry] = []
    private var syncTask: Task<Void, Never>?
    private let authentication = Authentication()
    private var localToken: String?
    private var connectionOwner: String?
    private var connectionGeneration = UUID()
    private var maintenanceTask: Task<Void, Never>?
    private var ratesCheckedFor: RatesFingerprint?

    var workspace: Workspace { state.document }
    var calendar: Calendar { workspace.calendar }
    var running: TimeEntry? { workspace.runningEntry }
    var canUndo: Bool { !deletedEntries.isEmpty }
    var interval: DateInterval { calendar.dateInterval(of: period.component, for: anchorDate)! }
    var calendarWeek: DateInterval { calendar.dateInterval(of: .weekOfYear, for: anchorDate)! }
    /// Entries of the selected project, or all entries when no filter is set.
    var filteredEntries: [TimeEntry] {
        guard let projectFilter else { return workspace.entries }
        return workspace.entries.filter { $0.projectID == projectFilter }
    }
    /// Filtered entries overlapping the selected period, newest first.
    var visibleEntries: [TimeEntry] {
        let interval = interval
        let now = Date.now
        return filteredEntries.filter { $0.start < interval.end && ($0.end ?? now) > interval.start }
            .sorted { $0.start > $1.start }
    }
    /// The project the next timer starts on: the chosen one, else the first active project.
    var nextTimerProject: Project? {
        workspace.activeProjects.first { $0.id == timerProjectID } ?? workspace.activeProjects.first
    }
    func canResume(_ entry: TimeEntry) -> Bool { workspace.project(entry.projectID)?.archived == false }
    /// The latest finished entry of each other active project, newest first.
    func recentResumable(limit: Int = 3) -> [TimeEntry] {
        var seen: Set<UUID> = running.map { [$0.projectID] } ?? []
        var result: [TimeEntry] = []
        for entry in workspace.entries.sorted(by: { $0.start > $1.start })
        where entry.end != nil && canResume(entry) && seen.insert(entry.projectID).inserted {
            result.append(entry)
            if result.count == limit { break }
        }
        return result
    }

    init(database suppliedDatabase: LocalDatabase? = nil, demo: Bool = false) {
        do {
            let db = try suppliedDatabase ?? LocalDatabase(path: Self.defaultDatabasePath())
            database = db
            realDatabase = db
            state = try db.load()
            timerProjectID = workspace.activeProjects.first?.id
            if demo || (suppliedDatabase == nil && CommandLine.arguments.contains("--demo")) { enterDemo() }
        } catch { startupError = error.localizedDescription }
    }
    private static func defaultDatabasePath() throws -> String {
        let folder = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appendingPathComponent("Timeit", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("timeit.sqlite").path
    }

    func summary(entries: [TimeEntry], now: Date = .now) -> FinancialSummary {
        Finance.summarize(
            entries, currency: workspace.profile.currency, period: interval, rates: state.rates, now: now,
            calendar: calendar)
    }
    /// Time inside `interval`, without the currency work a full summary does.
    func trackedSeconds(_ entries: [TimeEntry], in interval: DateInterval, now: Date = .now) -> TimeInterval {
        let calendar = calendar
        return entries.reduce(0) { $0 + Finance.seconds(of: $1, within: interval, now: now, calendar: calendar) }
    }
    /// Time tracked per project during the current calendar week.
    var weekSecondsByProject: [UUID: TimeInterval] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [:] }
        let now = Date.now
        let overlapping = workspace.entries.filter { $0.start < week.end && ($0.end ?? now) > week.start }
        return Dictionary(grouping: overlapping, by: \.projectID).mapValues { trackedSeconds($0, in: week, now: now) }
    }
    var weeklyGoalSeconds: TimeInterval { Double(max(1, workspace.profile.weeklyGoal)) * 3600 }
    /// Share of the weekly goal reached this calendar week, for the brand ring.
    var weekProgress: Double { goalProgress(weekSecondsByProject) }
    func goalProgress(_ weekSeconds: [UUID: TimeInterval]) -> Double {
        weekSeconds.values.reduce(0, +) / weeklyGoalSeconds
    }
    func navigate(_ direction: Int) {
        anchorDate = calendar.date(
            byAdding: screen == .calendar ? .weekOfYear : period.component, value: direction, to: anchorDate)!
    }
    func showError(_ error: Error) { errorMessage = error.localizedDescription }

    @discardableResult
    func change(_ body: (inout Workspace) -> Void) -> Bool {
        guard let database else {
            errorMessage = startupError ?? "Le stockage n’est pas disponible."
            return false
        }
        var next = state
        body(&next.document)
        next.sync.localVersion += 1
        do {
            try database.saveEdit(next.document, localVersion: next.sync.localVersion)
            state = next
            scheduleSync()
            return true
        } catch {
            showError(error)
            return false
        }
    }

    func start(project: Project, title: String? = nil) {
        let now = Date.now
        let cleanTitle = (title ?? timerTitle).trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanTitle.count <= 500 else {
            errorMessage = "La description est limitée à 500 caractères."
            return
        }
        guard !project.archived else { return }
        if change({ document in
            Self.closeRunning(&document, at: now)
            document.entries.append(
                TimeEntry(project: project, title: cleanTitle, start: now, policy: document.policy(at: now)))
        }) {
            timerProjectID = project.id
            timerTitle = ""
        }
    }
    func stop() {
        let now = Date.now
        change { Self.closeRunning(&$0, at: now) }
    }
    /// Ends the running entry at `now`, or drops it when it lasted under a second.
    private static func closeRunning(_ document: inout Workspace, at now: Date) {
        guard let index = document.entries.firstIndex(where: { $0.end == nil }) else { return }
        if document.entries[index].duration(at: now) >= 1 {
            document.entries[index].end = now
        } else {
            document.entries.remove(at: index)
        }
    }
    func toggleTimer() {
        if running != nil {
            stop()
        } else if let project = nextTimerProject {
            start(project: project)
        } else {
            projectEditor = ProjectEditorRequest()
        }
    }
    func resume(_ entry: TimeEntry) {
        guard canResume(entry), let project = workspace.project(entry.projectID) else { return }
        start(project: project, title: entry.title)
    }
    func save(entry: TimeEntry) -> Bool {
        if let message = EntryValidation.message(for: entry) {
            errorMessage = message
            return false
        }
        return change { document in
            if let index = document.entries.firstIndex(where: { $0.id == entry.id }) {
                document.entries[index] = entry
            } else {
                document.entries.append(entry)
            }
        }
    }
    func delete(_ entry: TimeEntry) {
        if change({ $0.entries.removeAll { $0.id == entry.id } }) { deletedEntries.append(entry) }
    }
    func undoDelete() {
        guard var entry = deletedEntries.last else { return }
        if entry.end == nil && running != nil { entry.end = max(.now, entry.start.addingTimeInterval(1)) }
        if change({ $0.entries.append(entry) }) { deletedEntries.removeLast() }
    }
    func move(_ entry: TimeEntry, _ move: CalendarMove) {
        guard entry.end != nil, move != CalendarMove(minutes: 0, resizing: move.resizing) else { return }
        _ = save(entry: move.applied(to: entry, calendar: calendar))
    }
    func save(project: Project, client: Client?) -> Bool {
        let saved = change { document in
            if let client, !document.clients.contains(where: { $0.id == client.id }) { document.clients.append(client) }
            if let index = document.projects.firstIndex(where: { $0.id == project.id }) {
                document.projects[index] = project
            } else {
                document.projects.append(project)
            }
        }
        if saved && timerProjectID == nil { timerProjectID = project.id }
        return saved
    }
    func archive(_ project: Project) {
        if running?.projectID == project.id { stop() }
        change { document in
            if let index = document.projects.firstIndex(where: { $0.id == project.id }) {
                document.projects[index].archived.toggle()
            }
        }
        if workspace.project(timerProjectID ?? UUID())?.archived == true {
            timerProjectID = workspace.activeProjects.first?.id
        }
    }
    func updateProfile(name: String, currency: String, goal: Int, contributions: String, incomeTax: String) -> Bool {
        change { document in
            document.profile.name = name
            document.profile.currency = currency
            document.profile.weeklyGoal = goal
            let old = document.policy(at: .now)
            if old.contributions != contributions || old.incomeTax != incomeTax {
                document.taxPolicies.append(
                    TaxPolicy(effectiveFrom: .now, contributions: contributions, incomeTax: incomeTax))
            }
        }
    }
    /// Abandons in-flight sync work; late responses from the old generation are ignored.
    private func invalidateSync() {
        syncTask?.cancel()
        connectionGeneration = UUID()
        isSyncing = false
    }
    func enterDemo() {
        do {
            invalidateSync()
            let demo = try LocalDatabase()
            let data = DemoData.make()
            try demo.save(data)
            try demo.saveRates(data.rates)
            database = demo
            state = data
            isDemo = true
            connected = false
            syncLabel = "Espace d’exemple"
            timerProjectID = workspace.activeProjects.first?.id
            projectFilter = nil
            anchorDate = .now
            screen = .overview
        } catch { showError(error) }
    }
    func leaveDemo() {
        do {
            guard let realDatabase else { return }
            connectionGeneration = UUID()
            state = try realDatabase.load()
            database = realDatabase
            isDemo = false
            timerProjectID = workspace.activeProjects.first?.id
            projectFilter = nil
            syncLabel = "Sur ce Mac"
        } catch { showError(error) }
    }

    private static let loopbackHosts: Set = ["127.0.0.1", "localhost", "::1"]
    private func endpoint() throws -> URL {
        guard let url = URL(string: serverURL), let host = url.host, url.user == nil, url.password == nil,
            url.query == nil, url.fragment == nil,
            url.scheme == "https" || (url.scheme == "http" && Self.loopbackHosts.contains(host))
        else {
            throw ConnectionError.invalidURL
        }
        return url
    }
    private func api() async throws -> APIClient {
        let url = try endpoint()
        let token: String
        if let localToken { token = localToken } else { token = try await authentication.accessToken() }
        return APIClient(baseURL: url, token: token)
    }
    func restoreConnection() async {
        if maintenanceTask == nil {
            maintenanceTask = Task { [weak self] in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(60)) } catch { return }
                    await self?.synchronize()
                }
            }
        }
        guard !isDemo, !connected, UserDefaults.standard.bool(forKey: "cloudEnabled") else { return }
        await connect(interactive: false)
    }
    func connect(interactive: Bool = true) async {
        guard !isDemo, !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let url = try endpoint()
            let configuration = try await APIClient(baseURL: url).configuration()
            if configuration.developmentAuth {
                guard Self.loopbackHosts.contains(url.host ?? "") else {
                    throw ConnectionError.invalidURL
                }
                localToken = "local-development-token"
            } else {
                localToken = nil
                if interactive {
                    try await authentication.signIn(configuration: configuration, server: url)
                } else if !authentication.restore(server: url) {
                    throw APIError.unauthorized
                }
            }
            let client = try await api()
            let identity = try await client.identity()
            let owner = url.absoluteString + "|" + identity.id
            if let existing = state.sync.ownerID, existing != owner { throw ConnectionError.differentAccount }
            connectionOwner = owner
            connectionGeneration = UUID()
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
            UserDefaults.standard.set(true, forKey: "cloudEnabled")
            connected = true
            await synchronize()
        } catch {
            if interactive { showError(error) }
            syncLabel = "Connexion requise"
        }
    }
    func disconnect() {
        invalidateSync()
        connected = false
        localToken = nil
        connectionOwner = nil
        authentication.signOut()
        syncLabel = "Sur ce Mac"
        UserDefaults.standard.set(false, forKey: "cloudEnabled")
    }
    private func scheduleSync() {
        guard connected, !isDemo else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }
    func synchronize() async {
        guard connected, !isDemo, !isSyncing, conflict == nil, let database else { return }
        let generation = connectionGeneration
        isSyncing = true
        syncLabel = "Synchronisation…"
        defer { if generation == connectionGeneration { isSyncing = false } }
        do {
            let client = try await api()
            if state.sync.pendingUpload != nil {
                try await sendPending(using: client, database: database, generation: generation)
            }
            let remote = try await client.workspace()
            guard generation == connectionGeneration else { return }
            if let remoteDocument = remote.document, remote.revision != state.sync.revision {
                if state.sync.hasChanges {
                    conflict = remote
                    syncLabel = "Conflit à résoudre"
                    return
                }
                var next = state
                next.document = remoteDocument
                next.sync.revision = remote.revision
                next.sync.ownerID = connectionOwner
                try database.save(next)
                state = next
            }
            if state.sync.hasChanges || remote.document == nil {
                var next = state
                _ = next.sync.prepareUpload(document: workspace)
                try database.saveSync(next.sync)
                state = next
                try await sendPending(using: client, database: database, generation: generation)
            }
            guard generation == connectionGeneration else { return }
            syncLabel = state.sync.hasChanges ? "Modifications en attente" : "À jour"
            await refreshRates(using: client, generation: generation)
            if state.sync.hasChanges { scheduleSync() }
        } catch APIError.conflict {
            guard generation == connectionGeneration else { return }
            do {
                let remote = try await api().workspace()
                if generation == connectionGeneration {
                    conflict = remote
                    syncLabel = "Conflit à résoudre"
                }
            } catch { syncLabel = "Hors ligne · enregistré sur ce Mac" }
        } catch APIError.unauthorized {
            if generation == connectionGeneration {
                connected = false
                syncLabel = "Connexion requise"
            }
        } catch {
            if generation == connectionGeneration { syncLabel = "Hors ligne · enregistré sur ce Mac" }
        }
    }
    private func sendPending(using client: APIClient, database: LocalDatabase, generation: UUID) async throws {
        guard let pending = state.sync.pendingUpload else { return }
        let result = try await client.upload(pending.request)
        guard generation == connectionGeneration else { throw CancellationError() }
        var next = state
        next.sync.acknowledge(revision: result.revision)
        next.sync.ownerID = connectionOwner
        try database.saveSync(next.sync)
        state = next
    }
    private func refreshRates(using client: APIClient, generation: UUID) async {
        // Rescanning history is only needed after the document or the rate cache changed.
        let fingerprint = RatesFingerprint(state)
        guard fingerprint != ratesCheckedFor, let database else { return }
        let currency = workspace.profile.currency
        let fullPeriod = DateInterval(start: .distantPast, end: .now)
        let present = Set(state.rates.map(\.key))
        var needed: [String: (base: String, day: String)] = [:]
        for entry in workspace.entries where entry.billable && entry.currency != currency {
            for segment in Finance.segments(of: entry, within: fullPeriod, now: .now, calendar: calendar) {
                let key = Finance.rateKey(for: entry, segment: segment, currency: currency, calendar: calendar)
                if !present.contains(key) {
                    needed[key] = (entry.currency, WireFormat.day(segment.start, calendar: calendar))
                }
            }
        }
        // Bounded sequential requests keep first sync gentle on the provider; results are saved once.
        var fetched: [ExchangeRate] = []
        var complete = needed.count <= 100
        for (_, pair) in needed.sorted(by: { $0.key < $1.key }).prefix(100) {
            guard let rate = try? await client.rate(base: pair.base, quote: currency, date: pair.day) else {
                complete = false
                break
            }
            fetched.append(rate)
        }
        guard generation == connectionGeneration else { return }
        if !fetched.isEmpty {
            var next = state
            let keys = Set(fetched.map(\.key))
            next.rates.removeAll { keys.contains($0.key) }
            next.rates.append(contentsOf: fetched)
            do {
                try database.saveRates(fetched)
                state = next
            } catch {
                return
            }
        }
        if complete { ratesCheckedFor = RatesFingerprint(state) }
    }
    /// Identifies the inputs of a rate scan: synced document, local edits and cached rates.
    private struct RatesFingerprint: Equatable {
        let revision: Int
        let localVersion: Int
        let rateCount: Int
        init(_ state: LocalState) {
            revision = state.sync.revision
            localVersion = state.sync.localVersion
            rateCount = state.rates.count
        }
    }
    func resolveConflict(useLocal: Bool) {
        guard let remote = conflict, let remoteDocument = remote.document, let database else { return }
        do {
            var next = state
            next.sync.revision = remote.revision
            next.sync.pendingUpload = nil
            if !useLocal {
                next.document = remoteDocument
                next.sync.uploadedVersion = next.sync.localVersion
            } else {
                next.sync.localVersion += 1
            }
            next.sync.ownerID = connectionOwner
            try database.save(next, preservingConflict: useLocal ? remoteDocument : workspace)
            state = next
            conflict = nil
            Task { await synchronize() }
        } catch { showError(error) }
    }
    enum ConnectionError: LocalizedError {
        case invalidURL, differentAccount
        var errorDescription: String? {
            switch self {
            case .invalidURL: "Utilisez une adresse HTTPS, ou HTTP uniquement pour un serveur local."
            case .differentAccount:
                "Cet espace local appartient à un autre compte. Utilisez le compte initial pour éviter de mélanger les données."
            }
        }
    }
}
