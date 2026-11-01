import Foundation
import Testing
import TimeitCore

@testable import TimeitApp

private actor RateProvider {
    var calls = 0
    var offline = false

    func setOffline(_ value: Bool) { offline = value }
    func get(_ base: String, _ quote: String, _ day: String) throws -> ExchangeRate {
        calls += 1
        if offline || base == "GBP" { throw APIError.server(502) }
        return ExchangeRate(
            base: base, quote: quote, requestedDate: day, observedDate: day, rate: "0.9", source: "fixture")
    }
}

@MainActor
private func foreignWorkspace() -> LocalState {
    var state = LocalState()
    let client = Client(name: "Local client")
    let project = Project(clientID: client.id, name: "Foreign project", currency: "USD", hourlyRate: "100")
    state.document.clients = [client]
    state.document.projects = [project]
    var entry = TimeEntry(
        project: project, title: "Local work", start: .now.addingTimeInterval(-1800),
        policy: state.document.taxPolicies[0])
    entry.end = .now.addingTimeInterval(-60)
    state.document.entries = [entry]
    return state
}

@MainActor @Test func ratesRefreshWithoutCloudAndPersistWithoutChangingWorkspaceOrSync() async throws {
    let database = try LocalDatabase()
    let original = foreignWorkspace()
    try database.save(original)
    let persisted = try database.load()
    let provider = RateProvider()
    let store = AppStore(database: database, fetchRate: { try await provider.get($0, $1, $2) })
    #expect(!store.connected)
    #expect(!AppStore.cloudAvailable)
    await store.refreshRates()
    #expect(!store.state.rates.isEmpty)
    #expect(store.summary(entries: store.workspace.entries).unconvertedEntries.isEmpty)
    let saved = try database.load()
    #expect(saved.document == persisted.document)
    #expect(saved.sync.revision == original.sync.revision)
    #expect(saved.sync.localVersion == original.sync.localVersion)
    #expect(saved.sync.uploadedVersion == original.sync.uploadedVersion)
    #expect(saved.sync.ownerID == original.sync.ownerID)
    #expect(saved.sync.pendingUpload == nil)
    let calls = await provider.calls
    await provider.setOffline(true)
    let reopened = AppStore(database: database, fetchRate: { try await provider.get($0, $1, $2) })
    await reopened.refreshRates()
    #expect(await provider.calls == calls)
    #expect(reopened.summary(entries: reopened.workspace.entries).gross > 0)
}

@MainActor @Test func missingRatesRemainRetryableAndDoNotBlockOtherCurrencies() async throws {
    let database = try LocalDatabase()
    var original = foreignWorkspace()
    var unsupported = original.document.entries[0]
    unsupported.id = UUID()
    unsupported.currency = "GBP"
    original.document.entries.append(unsupported)
    try database.save(original)
    let provider = RateProvider()
    await provider.setOffline(true)
    let store = AppStore(database: database, fetchRate: { try await provider.get($0, $1, $2) })
    await store.refreshRates()
    #expect(store.state.rates.isEmpty)
    await provider.setOffline(false)
    await store.refreshRates()
    #expect(store.summary(entries: store.workspace.entries).unconvertedEntries == [unsupported.id])
    #expect(!store.isRefreshingRates)
}

private actor DelayedRateProvider {
    var continuation: CheckedContinuation<ExchangeRate, Never>?
    var result: ExchangeRate?
    func get(_ base: String, _ quote: String, _ day: String) async -> ExchangeRate {
        result = ExchangeRate(
            base: base, quote: quote, requestedDate: day, observedDate: day, rate: "0.9", source: "fixture")
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitUntilRequested() async { while continuation == nil { await Task.yield() } }
    func finish() {
        continuation?.resume(returning: result!)
        continuation = nil
    }
}

@MainActor @Test func lateRatesCannotWriteIntoTheExampleWorkspace() async throws {
    let database = try LocalDatabase()
    try database.save(foreignWorkspace())
    let provider = DelayedRateProvider()
    let store = AppStore(database: database, fetchRate: { await provider.get($0, $1, $2) })
    let refresh = Task { await store.refreshRates() }
    await provider.waitUntilRequested()
    store.enterDemo()
    let example = store.state.rates
    await provider.finish()
    await refresh.value
    #expect(store.state.rates == example)
    #expect(try database.load().rates.isEmpty)
    await store.refreshRates()
    #expect(!store.isRefreshingRates)
}

@MainActor @Test func unavailableRatesCannotStarveLaterPagesOfHistory() async throws {
    let database = try LocalDatabase()
    var original = foreignWorkspace()
    let entry = original.document.entries[0]
    for day in 1...100 {
        var missing = entry
        missing.id = UUID()
        missing.currency = "GBP"
        missing.start = Calendar.current.startOfDay(for: .now).addingTimeInterval(Double(-day * 86400) + 3600)
        missing.end = missing.start.addingTimeInterval(600)
        original.document.entries.append(missing)
    }
    try database.save(original)
    let provider = RateProvider()
    let store = AppStore(database: database, fetchRate: { try await provider.get($0, $1, $2) })
    await store.refreshRates()
    #expect(store.state.rates.isEmpty)
    await store.refreshRates()
    #expect(store.state.rates.contains { $0.base == "USD" })
}
