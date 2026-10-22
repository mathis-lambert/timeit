import Testing
import TimeitCore

@testable import TimeitApp

@MainActor @Test func demoCannotReplaceTheRealWorkspace() throws {
    let database = try LocalDatabase()
    var state = LocalState()
    state.document.profile.name = "Real workspace"
    try database.save(state)
    let store = AppStore(database: database)
    store.enterDemo()
    #expect(store.isDemo)
    #expect(!store.workspace.entries.isEmpty)
    _ = store.change { $0.profile.name = "Changed example" }
    #expect(try database.load().document.profile.name == "Real workspace")
    store.leaveDemo()
    #expect(!store.isDemo)
    #expect(store.workspace.profile.name == "Real workspace")
}

@MainActor @Test func switchingProjectsStopsThePreviousTimerAndPersistsTheNewOne() throws {
    let database = try LocalDatabase()
    var state = DemoData.make()
    let previous = TimeEntry(
        project: state.document.projects[0], title: "Earlier", start: .now.addingTimeInterval(-3600),
        policy: state.document.taxPolicies[0])
    state.document.entries.append(previous)
    try database.save(state)
    let store = AppStore(database: database)
    let project = store.workspace.projects[1]
    store.start(project: project, title: "Next")
    #expect(store.workspace.entries.filter { $0.end == nil }.count == 1)
    #expect(store.workspace.entries.first { $0.id == previous.id }?.end != nil)
    #expect(store.running?.projectID == project.id)
    #expect(try database.load().document.runningEntry?.title == "Next")
}

@MainActor @Test func deletingAndUndoingRestoresTheOriginalSnapshot() throws {
    let store = AppStore(database: try LocalDatabase(), demo: true)
    let original = store.workspace.entries[0]
    store.delete(original)
    #expect(!store.workspace.entries.contains { $0.id == original.id })
    #expect(store.canUndo)
    store.undoDelete()
    #expect(store.workspace.entries.first { $0.id == original.id } == original)
}

@MainActor @Test func archiveRetainsReportHistory() throws {
    let store = AppStore(database: try LocalDatabase(), demo: true)
    let project = store.workspace.projects[0]
    let count = store.workspace.entries.count
    store.archive(project)
    #expect(store.workspace.project(project.id)?.archived == true)
    #expect(store.workspace.entries.count == count)
    #expect(!store.workspace.activeProjects.contains { $0.id == project.id })
}

@MainActor @Test func resumeSuggestionsSkipTheRunningAndArchivedProjects() throws {
    let store = AppStore(database: try LocalDatabase(), demo: true)
    let running = store.workspace.projects[1]
    let archived = store.workspace.projects[2]
    store.start(project: running, title: "Now")
    store.archive(archived)
    let recent = store.recentResumable(limit: 10)
    #expect(!recent.isEmpty)
    #expect(Set(recent.map(\.projectID)).count == recent.count)
    #expect(!recent.contains { $0.projectID == running.id || $0.projectID == archived.id })
    #expect(recent.allSatisfy { $0.end != nil })
    #expect(recent == recent.sorted { $0.start > $1.start })
}

@MainActor @Test func nextTimerFallsBackToTheFirstActiveProject() throws {
    let store = AppStore(database: try LocalDatabase(), demo: true)
    store.timerProjectID = nil
    #expect(store.nextTimerProject?.id == store.workspace.activeProjects.first?.id)
    store.toggleTimer()
    #expect(store.running?.projectID == store.workspace.activeProjects.first?.id)
}

@MainActor @Test func paletteFiltersProjectsAndActionsAndRunsThem() throws {
    let store = AppStore(database: try LocalDatabase(), demo: true)
    let project = store.workspace.activeProjects[0]
    let matches = store.paletteCommands(matching: project.name, weekSeconds: [:])
    #expect(matches.first?.title == project.name)
    #expect(
        matches.allSatisfy {
            $0.title.localizedStandardContains(project.name) || $0.subtitle.localizedStandardContains(project.name)
        })
    store.showLauncher = true
    store.perform(try #require(matches.first))
    #expect(store.running?.projectID == project.id)
    #expect(!store.showLauncher)
    let stop = try #require(store.paletteCommands(matching: "", weekSeconds: [:]).first)
    #expect(stop.section == .timer)
    store.perform(stop)
    #expect(store.running == nil)
    #expect(store.paletteCommands(matching: "Calendrier", weekSeconds: [:]).map(\.title) == ["Calendrier"])
}
