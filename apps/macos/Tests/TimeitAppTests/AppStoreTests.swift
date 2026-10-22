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
