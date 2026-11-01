import SwiftUI
import TimeitCore

struct ContentView: View {
    @Bindable var store: AppStore
    var body: some View {
        NavigationSplitView {
            Sidebar(store: store).navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 280)
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
                if store.showLauncher {
                    CommandPalette(store: store)
                        .transition(.opacity)
                        .zIndex(10)
                }
            }
            .animation(Motion.quick, value: store.showLauncher)
            .frame(minWidth: 720, minHeight: 600)
            .navigationTitle(store.screen?.title ?? "Timeit")
            .navigationSubtitle(store.windowSubtitle)
            .toolbar { WindowToolbar(store: store) }
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
}

// MARK: - Toolbar

/// Items present on every screen: the running timer, the example workspace, the project filter, search and add.
private struct WindowToolbar: ToolbarContent {
    @Bindable var store: AppStore
    var body: some ToolbarContent {
        if let entry = store.running {
            ToolbarItem(placement: .primaryAction) { RunningTimerItem(store: store, entry: entry) }
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        if let id = store.projectFilter, let project = store.workspace.project(id) {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.projectFilter = nil
                } label: {
                    Label(project.name, systemImage: "line.3.horizontal.decrease.circle.fill")
                        .labelStyle(.titleAndIcon)
                }
                .help("Retirer le filtre")
            }
        }
        if store.isDemo {
            ToolbarItem(placement: .primaryAction) {
                Button("Quitter l’exemple") { store.leaveDemo() }
                    .help("Revenir à votre espace. Les données d’exemple sont effacées.")
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.showLauncher = true
            } label: {
                Label("Palette de commandes", systemImage: "magnifyingglass")
            }
            .help("Palette de commandes (⌘K)")
            Button {
                store.entryEditor = EntryEditorRequest()
            } label: {
                Label("Ajouter une session", systemImage: "plus")
            }
            .help("Ajouter une session (⌘N)")
            .disabled(store.workspace.projects.isEmpty)
        }
    }
}

/// The running timer, on every screen: project, elapsed time and Stop.
private struct RunningTimerItem: View {
    let store: AppStore
    let entry: TimeEntry
    var body: some View {
        let project = store.workspace.project(entry.projectID)
        HStack(spacing: 8) {
            Button {
                store.screen = .overview
            } label: {
                HStack(spacing: 6) {
                    ProjectMark(color: project?.color ?? .coral)
                    Text(project?.name ?? "Timer").lineLimit(1)
                    TimelineView(.periodic(from: entry.start, by: 1)) { context in
                        Text(Display.duration(entry.duration(at: context.date), seconds: true))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                .padding(.leading, 4)
            }
            .buttonStyle(.plain)
            .help(entry.displayTitle)
            Button(action: store.stop) {
                Label("Arrêter", systemImage: "stop.fill")
            }
            .labelStyle(.iconOnly)
            .help("Arrêter le timer (⌘↩)")
        }
    }
}

/// Period navigation in the toolbar, like Calendar: a week/month switch and previous, today, next.
struct PeriodToolbar: ToolbarContent {
    @Bindable var store: AppStore
    var showsPeriod = true
    var body: some ToolbarContent {
        if showsPeriod {
            ToolbarItem(placement: .navigation) {
                Picker("Période", selection: $store.period) {
                    Text("Semaine").tag(ReportPeriod.week)
                    Text("Mois").tag(ReportPeriod.month)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        ToolbarItem(placement: .navigation) {
            ControlGroup {
                Button {
                    store.navigate(-1)
                } label: {
                    Label("Précédent", systemImage: "chevron.left")
                }
                Button("Aujourd’hui") { store.anchorDate = .now }
                Button {
                    store.navigate(1)
                } label: {
                    Label("Suivant", systemImage: "chevron.right")
                }
            }
            .fixedSize()
        }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Bindable var store: AppStore
    var body: some View {
        let weekSeconds = store.weekSecondsByProject
        List(selection: $store.screen) {
            Section {
                ForEach(Screen.allCases) { screen in
                    Label(screen.title, systemImage: screen.symbol).tag(screen)
                }
            }
            Section("Projets") {
                ForEach(store.workspace.activeProjects) { project in
                    let filtered = store.projectFilter == project.id
                    Button {
                        store.projectFilter = filtered ? nil : project.id
                        if store.screen != .calendar { store.screen = .overview }
                    } label: {
                        HStack {
                            Label {
                                Text(project.name).lineLimit(1)
                            } icon: {
                                Image(systemName: filtered ? "circle.inset.filled" : "circle.fill")
                                    .foregroundStyle(project.color.tint)
                                    .imageScale(.small)
                            }
                            Spacer(minLength: 4)
                            if store.running?.projectID == project.id {
                                Image(systemName: "record.circle").foregroundStyle(.secondary)
                                    .accessibilityLabel("En cours")
                            } else if let seconds = weekSeconds[project.id], seconds > 0 {
                                Text(Display.duration(seconds)).monospacedDigit().foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(filtered ? "Retirer le filtre" : "Afficher uniquement \(project.name)")
                    .contextMenu {
                        Button("Modifier…") { store.projectEditor = ProjectEditorRequest(project: project) }
                        Button("Démarrer") { store.start(project: project) }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 6) {
                Image(systemName: store.isDemo ? "sparkles" : store.connected ? "checkmark.icloud" : "internaldrive")
                Text(store.syncLabel).lineLimit(1)
                Spacer(minLength: 0)
                if store.isSyncing { ProgressView().controlSize(.mini) }
            }
            .font(.footnote).foregroundStyle(.secondary)
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }
}

// MARK: - Welcome

private struct WelcomeView: View {
    let store: AppStore
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "clock")
                .font(.title).foregroundStyle(Theme.accent)
                .frame(width: 56, height: 56)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(spacing: 6) {
                Text("Bienvenue dans Timeit").font(.title2.weight(.semibold))
                Text(
                    "Créez un projet pour lancer votre premier timer.\nVos données sont enregistrées sur ce Mac."
                )
                .foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            HStack(spacing: 8) {
                Button("Explorer un exemple") { store.enterDemo() }
                    .buttonStyle(TimeitButtonStyle(kind: .outline, large: true))
                Button {
                    store.projectEditor = ProjectEditorRequest()
                } label: {
                    Label("Créer un projet", systemImage: "plus")
                }
                .buttonStyle(TimeitButtonStyle(kind: .primary, large: true))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension AppStore {
    var periodSubtitle: String {
        let range = screen == .calendar ? calendarWeek : interval
        let end = range.end.addingTimeInterval(-1)
        return
            "\(range.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated).year()))"
    }
    /// The window subtitle: the period shown, or the workspace kind where periods do not apply.
    var windowSubtitle: String {
        let detail =
            screen == .projects
            ? "\(workspace.clients.count) clients · \(workspace.activeProjects.count) projets actifs" : periodSubtitle
        return isDemo ? "Exemple · \(detail)" : detail
    }
}

struct ConflictView: View {
    let store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Deux versions de votre espace", systemImage: "arrow.triangle.branch")
                .font(.title2.weight(.semibold))
            Text(
                "Votre Mac et le serveur ont été modifiés séparément. Choisissez la version à conserver. Une copie de l’autre version sera enregistrée localement avant le remplacement."
            ).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Conserver ce Mac") { store.resolveConflict(useLocal: true) }.buttonStyle(.outline)
                Spacer()
                Button("Utiliser le serveur") { store.resolveConflict(useLocal: false) }
                    .keyboardShortcut(.defaultAction).buttonStyle(.primary)
            }
        }.padding(28).frame(width: 480)
    }
}
