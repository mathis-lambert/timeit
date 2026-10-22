import AppKit
import KeyboardShortcuts
import SwiftUI
import TimeitCore

extension KeyboardShortcuts.Name {
    static let toggleTimer = Self("toggleTimer", initial: .init(.t, modifiers: [.command, .shift]))
}

@main
struct TimeitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = AppStore()
    var body: some Scene {
        Window("Timeit", id: "main") {
            ContentView(store: store)
                .tint(Theme.accent)
                .task { await store.restoreConnection() }
                .onAppear {
                    KeyboardShortcuts.onKeyUp(for: .toggleTimer) { [store] in store.toggleTimer() }
                }
        }
        .defaultSize(width: 1180, height: 800)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Nouvelle session…") { store.entryEditor = EntryEditorRequest() }.keyboardShortcut("n")
                Button("Nouveau projet…") { store.projectEditor = ProjectEditorRequest() }.keyboardShortcut(
                    "n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Annuler la suppression") { store.undoDelete() }.keyboardShortcut("z").disabled(!store.canUndo)
            }
            CommandMenu("Suivi") {
                Button(store.running == nil ? "Démarrer le timer" : "Arrêter le timer") { store.toggleTimer() }
                    .keyboardShortcut(.return, modifiers: .command)
                Button("Choisir un projet…") { store.showLauncher = true }.keyboardShortcut("k")
                Divider()
                Button("Synchroniser") { Task { await store.synchronize() } }.keyboardShortcut("r").disabled(
                    !store.connected)
                Button("Revenir à aujourd’hui") { store.anchorDate = .now }.keyboardShortcut("t")
            }
        }
        MenuBarExtra("Timeit", systemImage: store.running == nil ? "circle.dotted" : "record.circle") {
            MenuBarView(store: store).tint(Theme.accent)
        }.menuBarExtraStyle(.window)
        Settings { SettingsView(store: store).tint(Theme.accent) }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows.first { $0.identifier?.rawValue == "main" || $0.title == "Timeit" }?.makeKeyAndOrderFront(
                nil)
        }
        return true
    }
}
