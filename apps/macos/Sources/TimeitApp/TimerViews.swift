import AppKit
import SwiftUI
import TimeitCore

// MARK: - Composer

/// The primary surface on the overview: describe the work, pick a project, start. While a timer runs it
/// shows what is running and how long, with Stop.
struct TimerComposer: View {
    @Bindable var store: AppStore
    var body: some View {
        Group {
            if let entry = store.running {
                running(entry)
            } else {
                idle
            }
        }
        .shellAnimation(value: store.running?.id)
    }

    private var idle: some View {
        HStack(spacing: 10) {
            TextField("Sur quoi travaillez-vous ?", text: $store.timerTitle)
                .textFieldStyle(.roundedBorder)
                .onSubmit(store.toggleTimer)
                .accessibilityLabel("Description de l’activité")
            ProjectPicker(store: store).frame(maxWidth: 220)
            Button(action: store.toggleTimer) {
                Label("Démarrer", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(store.nextTimerProject == nil)
            .help("Démarrer le timer (↩)")
        }
        .controlSize(.large)
        .card(padding: 14)
    }

    private func running(_ entry: TimeEntry) -> some View {
        let tint = store.workspace.project(entry.projectID)?.color.tint ?? Theme.accent
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Button {
                    store.entryEditor = EntryEditorRequest(entry: entry)
                } label: {
                    Text(entry.displayTitle).font(.headline).lineLimit(1)
                }
                .buttonStyle(.plain).help("Modifier le timer actif")
                Label {
                    Text(store.workspace.label(forProject: entry.projectID))
                } icon: {
                    Image(systemName: "circle.fill").foregroundStyle(tint).imageScale(.small)
                }
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 12)
            TimelineView(.periodic(from: entry.start, by: 1)) { context in
                Text(Display.duration(entry.duration(at: context.date), seconds: true))
                    .font(.system(.title, weight: .medium)).monospacedDigit()
            }
            Button(action: store.stop) {
                Label("Arrêter", systemImage: "stop.fill")
            }
            .controlSize(.large)
            .help("Arrêter le timer (⌘↩)")
        }
        .padding(14)
        .liveLens(tint, radius: Theme.cardRadius)
    }
}

/// The project the next timer starts on.
struct ProjectPicker: View {
    @Bindable var store: AppStore
    var body: some View {
        Picker("Projet", selection: $store.timerProjectID) {
            ForEach(store.workspace.activeProjects) { project in
                Text(project.name).tag(Optional(project.id))
            }
        }
        .labelsHidden()
        .tint(.primary)
        .help("Projet du prochain timer")
    }
}

// MARK: - Menu bar

struct MenuBarView: View {
    @Bindable var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Timeit").font(.headline)
                if store.isDemo { Text("Exemple").font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                Button {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Label("Réglages", systemImage: "gearshape")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Réglages")
            }
            timer
            let recent = store.recentResumable()
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Reprendre").fieldLabel().padding(.horizontal, 8).padding(.bottom, 4)
                    ForEach(recent) { entry in
                        let project = store.workspace.project(entry.projectID)
                        MenuRow {
                            store.resume(entry)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.displayTitle).lineLimit(1)
                                    Text(project?.name ?? "").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "circle.fill")
                                    .foregroundStyle(project?.color.tint ?? Theme.accent).imageScale(.small)
                            }
                        }
                    }
                }
            }
            Divider()
            VStack(spacing: 0) {
                MenuRow {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Text("Ouvrir Timeit")
                }
                MenuRow {
                    NSApp.terminate(nil)
                } label: {
                    Text("Quitter Timeit")
                }
            }
        }
        .padding(12).frame(width: 300)
    }

    private var timer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let entry = store.running {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.workspace.label(forProject: entry.projectID)).font(.subheadline)
                        .foregroundStyle(.secondary)
                    TimelineView(.periodic(from: entry.start, by: 1)) { context in
                        Text(Display.duration(entry.duration(at: context.date), seconds: true))
                            .font(.system(size: 34, weight: .medium)).monospacedDigit()
                    }
                    Text(entry.displayTitle).lineLimit(2)
                }
                Button(action: store.stop) {
                    Label("Arrêter", systemImage: "stop.fill").frame(maxWidth: .infinity)
                }
            } else {
                TextField("Sur quoi travaillez-vous ?", text: $store.timerTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(store.toggleTimer)
                    .accessibilityLabel("Description de l’activité")
                ProjectPicker(store: store)
                Button(action: store.toggleTimer) {
                    Label("Démarrer", systemImage: "play.fill").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.nextTimerProject == nil)
            }
        }
        .controlSize(.large)
    }
}

/// A full-width row that highlights under the pointer, like a menu item.
private struct MenuRow<Label: View>: View {
    let action: () -> Void
    @ViewBuilder var label: Label
    var body: some View {
        Button(action: action) {
            label.frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .hoverHighlight()
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Command palette

/// Keyboard-first palette: type to filter projects and actions, arrows to move, Return to run.
struct CommandPalette: View {
    @Bindable var store: AppStore
    @FocusState private var focused: Bool
    @State private var selection = 0
    /// Weekly totals shown next to projects; computed once per opening, not per keystroke.
    @State private var weekSeconds: [UUID: TimeInterval] = [:]
    private static let radius: CGFloat = 16

    var body: some View {
        let items = store.paletteCommands(matching: store.launcherQuery, weekSeconds: weekSeconds)
        ZStack(alignment: .top) {
            Color.black.opacity(0.12).ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.title3).foregroundStyle(.secondary)
                    TextField("Démarrer un projet, créer, naviguer…", text: $store.launcherQuery)
                        .textFieldStyle(.plain).font(.title3)
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
                                    Text(item.section.rawValue).font(.subheadline.weight(.medium))
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
                        Text(items[selection].section == .actions ? "Ouvrir" : "Lancer")
                        KeyCap("↩")
                    }
                    Text("Naviguer").padding(.leading, 8)
                    KeyCap("↑")
                    KeyCap("↓")
                }
                .font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 12).frame(height: 36)
            }
            .frame(width: 600)
            // Clip the results, not the glass, so the glass keeps sampling what lies under the panel.
            .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
            .glass(.panel, radius: Self.radius)
            .lightRing(Theme.accent, radius: Self.radius)
            .panelShadow()
            .padding(.top, 64)
        }
        .onAppear {
            store.launcherQuery = ""
            selection = 0
            weekSeconds = store.weekSecondsByProject
            focused = true
        }
        .onChange(of: store.launcherQuery) { selection = 0 }
    }

    private func row(_ item: PaletteCommand, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol).imageScale(item.section == .start ? .small : .medium)
                .foregroundStyle(item.tint).frame(width: 20)
            Text(item.title).lineLimit(1)
            Text(item.subtitle).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 8)
            if let shortcut = item.shortcut { KeyCap(shortcut.label) }
            if let detail = item.detail {
                Text(detail).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10).frame(height: 36)
        .background {
            if selected {
                Color.clear.glass(
                    .selection, tint: item.section == .start ? item.tint : nil, radius: Theme.rowRadius)
            }
        }
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        selection = (selection + delta + count) % count
    }
    private func run(_ items: [PaletteCommand]) {
        guard items.indices.contains(selection) else { return }
        store.perform(items[selection])
    }
    private func close() {
        store.showLauncher = false
    }
}
