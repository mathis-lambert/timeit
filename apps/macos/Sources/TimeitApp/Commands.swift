import SwiftUI
import TimeitCore

/// In-app shortcuts, shared by the menus, the command palette and Settings.
enum AppShortcut: CaseIterable {
    case newSession, newProject, toggleTimer, palette, today, undoDelete

    var key: KeyEquivalent {
        switch self {
        case .newSession, .newProject: "n"
        case .toggleTimer: .return
        case .palette: "k"
        case .today: "t"
        case .undoDelete: "z"
        }
    }
    var modifiers: EventModifiers { self == .newProject ? [.command, .shift] : .command }
    var label: String {
        switch self {
        case .newSession: "⌘N"
        case .newProject: "⌘⇧N"
        case .toggleTimer: "⌘↩"
        case .palette: "⌘K"
        case .today: "⌘T"
        case .undoDelete: "⌘Z"
        }
    }
    var title: String {
        switch self {
        case .newSession: "Nouvelle session"
        case .newProject: "Nouveau projet"
        case .toggleTimer: "Démarrer / arrêter"
        case .palette: "Palette de commandes"
        case .today: "Revenir à aujourd’hui"
        case .undoDelete: "Annuler une suppression"
        }
    }
}

extension View {
    func keyboardShortcut(_ shortcut: AppShortcut) -> some View {
        keyboardShortcut(shortcut.key, modifiers: shortcut.modifiers)
    }
}

/// One row of the command palette.
struct PaletteCommand: Identifiable {
    enum Kind {
        case stop
        case start(Project)
        case newSession, newProject
        case navigate(Screen)
    }
    enum Section: String {
        case timer = "Timer"
        case start = "Démarrer"
        case actions = "Actions"
    }

    let kind: Kind
    let title: String
    let subtitle: String
    /// Time tracked this week, shown next to projects.
    var detail: String? = nil

    var id: String {
        switch kind {
        case .stop: "stop"
        case .start(let project): project.id.uuidString
        case .newSession: "new-session"
        case .newProject: "new-project"
        case .navigate(let screen): screen.rawValue
        }
    }
    var section: Section {
        switch kind {
        case .stop: .timer
        case .start: .start
        case .newSession, .newProject, .navigate: .actions
        }
    }
    var symbol: String {
        switch kind {
        case .stop: "stop.fill"
        case .start: "circle.fill"
        case .newSession: "plus"
        case .newProject: "folder.badge.plus"
        case .navigate(let screen): screen.symbol
        }
    }
    var tint: Color {
        switch kind {
        case .stop: Theme.accent
        case .start(let project): project.color.tint
        default: .secondary
        }
    }
    var shortcut: AppShortcut? {
        switch kind {
        case .stop: .toggleTimer
        case .newSession: .newSession
        case .newProject: .newProject
        case .start, .navigate: nil
        }
    }
}

extension AppStore {
    /// Commands matching `query`: stop the running timer, start a project, then actions and screens.
    func paletteCommands(matching query: String, weekSeconds: [UUID: TimeInterval]) -> [PaletteCommand] {
        let query = query.trimmingCharacters(in: .whitespaces)
        func matches(_ values: String...) -> Bool {
            query.isEmpty || values.contains { $0.localizedStandardContains(query) }
        }
        var result: [PaletteCommand] = []
        if let entry = running, matches("arrêter", "stop", "timer") {
            result.append(PaletteCommand(kind: .stop, title: "Arrêter le timer", subtitle: entry.displayTitle))
        }
        for project in workspace.activeProjects {
            let client = workspace.client(for: project)?.name ?? ""
            guard matches(project.name, client) else { continue }
            let week = weekSeconds[project.id] ?? 0
            result.append(
                PaletteCommand(
                    kind: .start(project), title: project.name, subtitle: client,
                    detail: week > 0 ? Display.duration(week) : nil))
        }
        let actions =
            [
                PaletteCommand(kind: .newSession, title: "Nouvelle session", subtitle: "Ajouter du temps passé"),
                PaletteCommand(kind: .newProject, title: "Nouveau projet", subtitle: "Client, tarif, couleur"),
            ]
            + Screen.allCases.map { PaletteCommand(kind: .navigate($0), title: $0.title, subtitle: "Aller à") }
        result += actions.filter { matches($0.title, $0.subtitle) }
        return result
    }

    func perform(_ command: PaletteCommand) {
        showLauncher = false
        switch command.kind {
        case .stop: stop()
        case .start(let project): start(project: project)
        case .newSession: entryEditor = EntryEditorRequest()
        case .newProject: projectEditor = ProjectEditorRequest()
        case .navigate(let screen): self.screen = screen
        }
    }
}
