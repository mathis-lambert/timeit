import AppKit
import SwiftUI
import TimeitCore

// MARK: - Composer

/// The primary surface: an idle composer that morphs into the running timer.
struct TimerComposer: View {
    @Bindable var store: AppStore
    @Namespace private var glass
    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                if let entry = store.running {
                    running(entry)
                } else {
                    idle
                }
            }
        }
    }

    private var idle: some View {
        Group {
            HStack(spacing: 12) {
                Image(systemName: "pencil.line").foregroundStyle(.tertiary)
                TextField("Sur quoi travaillez-vous ?", text: $store.timerTitle)
                    .textFieldStyle(.plain).font(.system(size: 15))
                    .onSubmit(start)
                    .accessibilityLabel("Description de l’activité")
                ProjectChip(store: store)
            }
            .padding(.leading, 16).padding(.trailing, 8).frame(height: 52)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .glassEffectID("bar", in: glass)
            Button(action: start) {
                Image(systemName: "play.fill").font(.system(size: 16, weight: .semibold))
                    .frame(width: 52, height: 52)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(Theme.accent).interactive(), in: .circle)
            .glassEffectID("action", in: glass)
            .disabled(store.timerProjectID == nil)
            .help("Démarrer (↩)")
            .accessibilityLabel("Démarrer le timer")
        }
    }

    private func running(_ entry: TimeEntry) -> some View {
        let project = store.workspace.project(entry.projectID)
        let tint = project?.color.tint ?? Theme.accent
        return Group {
            HStack(spacing: 12) {
                LiveDot(color: tint, size: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        store.entryEditor = EntryEditorRequest(entry: entry)
                    } label: {
                        Text(entry.title.isEmpty ? "Sans description" : entry.title)
                            .font(.system(size: 15, weight: .semibold)).lineLimit(1)
                    }
                    .buttonStyle(.plain).help("Modifier le timer actif")
                    Text(
                        [project.flatMap { store.workspace.client(for: $0) }?.name, project?.name]
                            .compactMap { $0 }.joined(separator: " · ")
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 12)
                TimelineView(.periodic(from: entry.start, by: 1)) { context in
                    Text(Display.duration(entry.duration(at: context.date), seconds: true))
                        .font(.system(size: 26, weight: .medium, design: .rounded)).monospacedDigit()
                }
            }
            .padding(.leading, 16).padding(.trailing, 20).frame(height: 64)
            .glassEffect(.regular.tint(tint.opacity(0.12)), in: .rect(cornerRadius: 16))
            .glassEffectID("bar", in: glass)
            Button {
                withAnimation(Motion.standard) { store.stop() }
            } label: {
                Image(systemName: "stop.fill").font(.system(size: 16, weight: .semibold))
                    .frame(width: 64, height: 64)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .glassEffect(.regular.tint(tint).interactive(), in: .circle)
            .glassEffectID("action", in: glass)
            .help("Arrêter (⌘↩)")
            .accessibilityLabel("Arrêter le timer")
        }
    }

    private func start() {
        guard store.timerProjectID != nil else { return }
        withAnimation(Motion.standard) { store.toggleTimer() }
    }
}

/// Project selector for the next timer, used by the composer and the menu bar.
struct ProjectChip: View {
    @Bindable var store: AppStore
    var body: some View {
        let project = store.timerProjectID.flatMap(store.workspace.project)
        Menu {
            Picker("Projet", selection: $store.timerProjectID) {
                ForEach(store.workspace.activeProjects) { item in
                    Text(item.name).tag(Optional(item.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                if let project { ProjectMark(color: project.color, size: 7) }
                Text(project?.name ?? "Choisir un projet").lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8.5, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10).frame(height: 28)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Projet du prochain timer")
        .accessibilityLabel("Projet : \(project?.name ?? "aucun")")
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                BrandMark(size: 16, progress: store.weekProgress)
                Wordmark(size: 15)
                if store.isDemo {
                    Text("Exemple").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
                .help("Réglages").accessibilityLabel("Réglages")
            }
            timer
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reprendre").eyebrow().padding(.leading, 6).padding(.bottom, 4)
                    ForEach(recent) { entry in
                        let project = store.workspace.project(entry.projectID)
                        Button {
                            store.resume(entry)
                        } label: {
                            HStack(spacing: 10) {
                                ProjectMark(color: project?.color ?? .coral)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.title.isEmpty ? "Sans description" : entry.title)
                                        .font(.system(size: 12.5)).lineLimit(1)
                                    Text(project?.name ?? "").font(.system(size: 10.5)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.fill").font(.system(size: 9)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 5).hoverHighlight()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Divider()
            HStack {
                Button("Ouvrir Timeit") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quitter") { NSApp.terminate(nil) }.foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless).font(.system(size: 12))
        }
        .padding(14).frame(width: 320)
    }

    private var timer: some View {
        let tint = store.running.flatMap { store.workspace.project($0.projectID)?.color.tint } ?? Theme.accent
        return VStack(alignment: .leading, spacing: 10) {
            if let entry = store.running {
                HStack(spacing: 6) {
                    LiveDot(color: tint, size: 7)
                    Text(store.workspace.project(entry.projectID)?.name ?? "").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(tint)
                }
                TimelineView(.periodic(from: entry.start, by: 1)) { context in
                    Text(Display.duration(entry.duration(at: context.date), seconds: true))
                        .font(.system(size: 38, weight: .medium, design: .rounded)).monospacedDigit()
                }
                Text(entry.title.isEmpty ? "Sans description" : entry.title)
                    .font(.system(size: 13, weight: .medium)).lineLimit(2)
            } else {
                TextField("Sur quoi travaillez-vous ?", text: $store.timerTitle)
                    .textFieldStyle(.roundedBorder).controlSize(.large)
                    .onSubmit { store.toggleTimer() }
                    .accessibilityLabel("Description de l’activité")
                ProjectChip(store: store)
            }
            Button {
                store.toggleTimer()
            } label: {
                Label(
                    store.running == nil ? "Démarrer" : "Arrêter",
                    systemImage: store.running == nil ? "play.fill" : "stop.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent).controlSize(.large)
            .tint(tint)
            .disabled(store.running == nil && store.timerProjectID == nil)
        }
        .card(padding: 14)
    }

    private var recent: [TimeEntry] {
        var seen = Set<UUID>()
        return Array(
            store.workspace.entries.sorted { $0.start > $1.start }.filter { entry in
                guard store.workspace.project(entry.projectID)?.archived == false, entry.end != nil,
                    entry.projectID != store.running?.projectID
                else {
                    return false
                }
                return seen.insert(entry.projectID).inserted
            }.prefix(3))
    }
}

// MARK: - Command palette

/// Keyboard-first palette: type to filter projects and actions, arrows to move, Return to run.
struct CommandPalette: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool
    @State private var selection = 0

    private struct Command: Identifiable {
        let id: String
        let section: String
        let title: String
        let subtitle: String
        let symbol: String
        let tint: Color
        let accessory: String
        let run: () -> Void
    }

    private var commands: [Command] {
        let query = store.launcherQuery.trimmingCharacters(in: .whitespaces)
        func matches(_ values: String...) -> Bool {
            query.isEmpty || values.contains { $0.localizedStandardContains(query) }
        }
        var result: [Command] = []
        if let entry = store.running, matches("arrêter", "stop", "timer") {
            result.append(
                Command(
                    id: "stop", section: "Timer", title: "Arrêter le timer",
                    subtitle: entry.title.isEmpty ? "Sans description" : entry.title, symbol: "stop.fill",
                    tint: Theme.accent, accessory: "⌘↩"
                ) { store.stop() })
        }
        let weekSeconds = store.weekSecondsByProject
        for project in store.workspace.activeProjects {
            let client = store.workspace.client(for: project)?.name ?? ""
            guard matches(project.name, client) else { continue }
            let week = weekSeconds[project.id] ?? 0
            result.append(
                Command(
                    id: project.id.uuidString, section: "Démarrer", title: project.name,
                    subtitle: client, symbol: "circle.fill", tint: project.color.tint,
                    accessory: week > 0 ? Display.duration(week) : ""
                ) { store.start(project: project) })
        }
        let actions: [(String, String, String, String, () -> Void)] = [
            ("Nouvelle session", "Ajouter du temps passé", "plus", "⌘N", { store.entryEditor = EntryEditorRequest() }),
            (
                "Nouveau projet", "Client, tarif, couleur", "folder.badge.plus", "⌘⇧N",
                { store.projectEditor = ProjectEditorRequest() }
            ),
            (Screen.overview.title, "Aller à", Screen.overview.symbol, "", { store.screen = .overview }),
            (Screen.calendar.title, "Aller à", Screen.calendar.symbol, "", { store.screen = .calendar }),
            (Screen.projects.title, "Aller à", Screen.projects.symbol, "", { store.screen = .projects }),
            (Screen.reports.title, "Aller à", Screen.reports.symbol, "", { store.screen = .reports }),
        ]
        for action in actions where matches(action.0, action.1) {
            result.append(
                Command(
                    id: action.0, section: "Actions", title: action.0, subtitle: action.1, symbol: action.2,
                    tint: .secondary, accessory: action.3, run: action.4))
        }
        return result
    }

    var body: some View {
        let items = commands
        ZStack(alignment: .top) {
            Color.black.opacity(0.12).ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(.secondary)
                    TextField("Démarrer un projet, créer, naviguer…", text: $store.launcherQuery)
                        .textFieldStyle(.plain).font(.system(size: 17))
                        .focused($focused)
                        .onSubmit { run(items) }
                        .onKeyPress(.downArrow) {
                            move(1, count: items.count)
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            move(-1, count: items.count)
                            return .handled
                        }
                        .onKeyPress(.escape) {
                            close()
                            return .handled
                        }
                    KeyCap("esc")
                }
                .padding(.horizontal, 16).frame(height: 52)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if items.isEmpty {
                                Text("Aucun résultat pour « \(store.launcherQuery) »").foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity).padding(.vertical, 32)
                            }
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                if index == 0 || items[index - 1].section != item.section {
                                    Text(item.section).font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 10).padding(.top, index == 0 ? 4 : 10).padding(
                                            .bottom, 4)
                                }
                                row(item, selected: index == selection)
                                    .id(index)
                                    .onTapGesture {
                                        selection = index
                                        run(items)
                                    }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: selection) { _, value in proxy.scrollTo(value) }
                }
                Divider()
                HStack(spacing: 6) {
                    Spacer()
                    if items.indices.contains(selection) {
                        Text(items[selection].section == "Actions" ? "Ouvrir" : "Lancer")
                        KeyCap("↩")
                    }
                    Text("Naviguer").padding(.leading, 8)
                    KeyCap("↑")
                    KeyCap("↓")
                }
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                .padding(.horizontal, 12).frame(height: 36)
            }
            .frame(width: 600)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
            .padding(.top, 64)
        }
        .onAppear {
            store.launcherQuery = ""
            selection = 0
            focused = true
        }
        .onChange(of: store.launcherQuery) { selection = 0 }
    }

    private func row(_ item: Command, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).font(.system(size: item.symbol == "circle.fill" ? 8 : 13))
                .foregroundStyle(item.tint).frame(width: 20)
            Text(item.title).font(.system(size: 13.5)).lineLimit(1)
            Text(item.subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if item.accessory.hasPrefix("⌘") {
                KeyCap(item.accessory)
            } else if !item.accessory.isEmpty {
                Text(item.accessory).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.08 : 0))
        )
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }
    private func run(_ items: [Command]) {
        guard items.indices.contains(selection) else { return }
        let command = items[selection]
        close()
        command.run()
    }
    private func close() {
        store.showLauncher = false
    }
}
