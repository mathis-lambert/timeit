import SwiftUI
import TimeitCore

extension AppStore {
    /// Time inside `interval`, without the currency work a full summary does.
    func trackedSeconds(_ entries: [TimeEntry], in interval: DateInterval, now: Date = .now) -> TimeInterval {
        entries.reduce(0) { total, entry in
            total
                + Finance.segments(of: entry, within: interval, now: now, calendar: calendar).reduce(0) {
                    $0 + $1.duration
                }
        }
    }
    /// Time tracked per project during the current calendar week.
    var weekSecondsByProject: [UUID: TimeInterval] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: .now) else { return [:] }
        return Dictionary(grouping: workspace.entries, by: \.projectID).mapValues { trackedSeconds($0, in: week) }
    }
    /// Share of the weekly goal reached this calendar week, for the brand ring.
    var weekProgress: Double {
        weekSecondsByProject.values.reduce(0, +) / Double(max(1, workspace.profile.weeklyGoal) * 3600)
    }
}

struct ContentView: View {
    @Bindable var store: AppStore
    var body: some View {
        NavigationSplitView {
            Sidebar(store: store).navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            ZStack(alignment: .top) {
                if let error = store.startupError {
                    EmptyState(
                        symbol: "externaldrive.badge.exclamationmark", title: "Le stockage n’est pas disponible",
                        detail: error)
                } else if store.workspace.projects.isEmpty {
                    WelcomeView(store: store)
                } else {
                    screen
                }
                if store.isDemo { demoBadge }
                if store.showLauncher {
                    CommandPalette(store: store)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(Motion.quick, value: store.showLauncher)
            .frame(minWidth: 760, minHeight: 640)
            .toolbar(removing: .title)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.showLauncher = true
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            Text("Rechercher, démarrer…").foregroundStyle(.secondary)
                            Spacer(minLength: 16)
                            KeyCap("⌘K")
                        }
                        .font(.system(size: 12.5)).padding(.horizontal, 4).frame(width: 250)
                    }
                    .help("Palette de commandes (⌘K)")
                    .accessibilityLabel("Ouvrir la palette de commandes")
                }
                ToolbarSpacer(.fixed, placement: .primaryAction)
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        store.entryEditor = EntryEditorRequest()
                    } label: {
                        Label("Ajouter une session", systemImage: "plus")
                    }.help("Ajouter une session (⌘N)").disabled(store.workspace.projects.isEmpty)
                }
            }
        }
        .sheet(item: $store.entryEditor) { request in EntryEditor(store: store, request: request) }
        .sheet(item: $store.projectEditor) { request in ProjectEditor(store: store, request: request) }
        .sheet(isPresented: Binding(get: { store.conflict != nil }, set: { _ in })) { ConflictView(store: store) }
        .alert(
            "L’action n’a pas pu être terminée",
            isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
        ) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    @ViewBuilder private var screen: some View {
        switch store.screen ?? .overview {
        case .overview: DashboardView(store: store)
        case .calendar: CalendarView(store: store)
        case .projects: ProjectsView(store: store)
        case .reports: ReportsView(store: store)
        }
    }

    private var demoBadge: some View {
        VStack {
            Spacer()
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Theme.accent)
                Text("Espace d’exemple").fontWeight(.semibold)
                Text("Données fictives, effacées en quittant.").foregroundStyle(.secondary)
                Button("Revenir à mon espace") { store.leaveDemo() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).fontWeight(.medium)
            }
            .font(.system(size: 11.5))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .glassEffect(.regular, in: .capsule)
            .padding(.bottom, 18)
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var store: AppStore
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        let weekSeconds = store.weekSecondsByProject
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 22, progress: store.weekProgress)
                Wordmark(size: 21)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 14)
            .help("L’anneau se remplit avec votre objectif hebdomadaire")
            List(selection: $store.screen) {
                Section {
                    ForEach(Screen.allCases) { screen in
                        Label(screen.title, systemImage: screen.symbol).tag(screen)
                    }
                }
                Section("Projets") {
                    ForEach(store.workspace.activeProjects.prefix(8)) { project in
                        let filtered = store.projectFilter == project.id
                        Button {
                            store.projectFilter = filtered ? nil : project.id
                            if store.screen != .calendar { store.screen = .overview }
                        } label: {
                            HStack(spacing: 10) {
                                ProjectMark(color: project.color, size: 8).frame(width: 16)
                                Text(project.name).lineLimit(1)
                                Spacer(minLength: 4)
                                if filtered {
                                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                                        .foregroundStyle(project.color.tint)
                                } else if store.running?.projectID == project.id {
                                    Image(systemName: "record.circle").foregroundStyle(project.color.tint)
                                        .accessibilityLabel("En cours")
                                } else {
                                    if let seconds = weekSeconds[project.id], seconds > 0 {
                                        Text(Display.duration(seconds)).font(.system(size: 10.5)).monospacedDigit()
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }.contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(filtered ? "Retirer le filtre" : "Filtrer sur \(project.name)")
                    }
                    Button {
                        store.projectEditor = ProjectEditorRequest()
                    } label: {
                        Label("Nouveau projet", systemImage: "plus").foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            footer
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            if let entry = store.running {
                Button {
                    store.screen = .overview
                } label: {
                    HStack(spacing: 8) {
                        LiveDot(color: store.workspace.project(entry.projectID)?.color.tint ?? Theme.accent, size: 6)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.title.isEmpty ? "Sans description" : entry.title).font(
                                .system(size: 11.5, weight: .semibold)
                            ).lineLimit(1)
                            Text(store.workspace.project(entry.projectID)?.name ?? "").font(.system(size: 10))
                                .foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(Display.duration(entry.duration(at: context.date), seconds: true))
                                .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(
                        (store.workspace.project(entry.projectID)?.color.tint ?? Theme.accent).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                Image(systemName: store.isDemo ? "sparkles" : store.connected ? "checkmark.icloud" : "internaldrive")
                Text(store.syncLabel).lineLimit(1)
                Spacer(minLength: 0)
                if store.isSyncing { ProgressView().controlSize(.mini) }
            }
            .font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.horizontal, 6)
            Button {
                openSettings()
            } label: {
                HStack(spacing: 10) {
                    Text(String(store.workspace.profile.name.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.workspace.profile.name).font(.system(size: 12, weight: .semibold))
                        Text("Réglages").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "gearshape").foregroundStyle(.secondary)
                }
                .padding(6)
                .hoverHighlight()
            }
            .buttonStyle(.plain).help("Ouvrir les réglages")
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    let store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            BrandMark(size: 40, progress: 0.72)
            VStack(alignment: .leading, spacing: 10) {
                Text("Faites de la place\npour votre travail.")
                    .font(.system(size: 38, weight: .bold)).tracking(-1.2)
                Text("Vos projets, votre temps et ce qu’il rapporte.\nTout commence avec un premier projet.")
                    .font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(4)
            }
            HStack(spacing: 12) {
                Button("Créer mon premier projet") { store.projectEditor = ProjectEditorRequest() }
                    .buttonStyle(.glassProminent)
                Button("Explorer un exemple") { store.enterDemo() }
                    .buttonStyle(.glass)
            }
            .controlSize(.large)
            Label("Vos données restent sur ce Mac. Le cloud est facultatif.", systemImage: "lock.shield")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(64)
    }
}

// MARK: - Period controls

struct PeriodControls: View {
    @Bindable var store: AppStore
    var showPicker = true
    var body: some View {
        HStack(spacing: 10) {
            if showPicker {
                Picker("Période", selection: $store.period) {
                    Text("Semaine").tag(ReportPeriod.week)
                    Text("Mois").tag(ReportPeriod.month)
                }
                .pickerStyle(.segmented).labelsHidden().fixedSize()
            }
            ControlGroup {
                Button {
                    store.navigate(-1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Période précédente").accessibilityLabel("Période précédente")
                Button("Aujourd’hui") { store.anchorDate = .now }
                Button {
                    store.navigate(1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Période suivante").accessibilityLabel("Période suivante")
            }
            .fixedSize()
        }
    }
}

extension AppStore {
    var periodSubtitle: String {
        let range = screen == .calendar ? calendarWeek : interval
        let end = range.end.addingTimeInterval(-1)
        return
            "\(range.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    var periodTitle: String {
        let current = calendar.isDate(
            anchorDate, equalTo: .now, toGranularity: period == .week || screen == .calendar ? .weekOfYear : .month)
        if screen == .calendar {
            return current ? "Cette semaine" : "Semaine \(calendar.component(.weekOfYear, from: anchorDate))"
        }
        if current { return period == .week ? "Votre semaine, en clair." : "Votre mois, en clair." }
        return period == .week
            ? "Semaine \(calendar.component(.weekOfYear, from: anchorDate))"
            : anchorDate.formatted(.dateTime.month(.wide).year()).capitalized
    }
}

/// Filter chip shown under page titles while a project filter is active.
struct FilterChip: View {
    let store: AppStore
    var body: some View {
        if let id = store.projectFilter, let project = store.workspace.project(id) {
            Button {
                store.projectFilter = nil
            } label: {
                HStack(spacing: 6) {
                    ProjectMark(color: project.color, size: 7)
                    Text(project.name).fontWeight(.medium)
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(project.color.tint.opacity(0.14), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Retirer le filtre")
        }
    }
}

struct ConflictView: View {
    let store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Deux versions de votre espace", systemImage: "arrow.triangle.branch")
                .font(.system(size: 20, weight: .bold))
            Text(
                "Votre Mac et le serveur ont été modifiés séparément. Choisissez la version à conserver. Une copie de l’autre version sera enregistrée localement avant le remplacement."
            ).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Conserver ce Mac") { store.resolveConflict(useLocal: true) }.buttonStyle(.glass)
                Spacer()
                Button("Utiliser le serveur") { store.resolveConflict(useLocal: false) }.buttonStyle(.glassProminent)
            }.controlSize(.large)
        }.padding(28).frame(width: 480)
    }
}
