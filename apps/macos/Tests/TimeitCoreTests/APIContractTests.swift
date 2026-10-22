import Foundation
import Testing

@testable import TimeitCore

@Test(.enabled(if: ProcessInfo.processInfo.environment["TIMEIT_API_TEST_URL"] != nil))
func nativeHTTPContract() async throws {
    let url = URL(string: ProcessInfo.processInfo.environment["TIMEIT_API_TEST_URL"]!)!
    let client = APIClient(baseURL: url, token: "local-development-token")
    #expect(try await client.configuration().developmentAuth)
    #expect(try await client.identity().id == "local-development")
    #expect(try await client.workspace().document == nil)
    var document = Workspace()
    let customer = Client(name: "Native contract")
    let project = Project(clientID: customer.id, name: "Wire round trip", currency: "KWD", hourlyRate: "42.123")
    document.clients = [customer]
    document.projects = [project]
    document.entries = [
        TimeEntry(
            project: project, title: "Running timer", start: .now.addingTimeInterval(-60),
            policy: document.taxPolicies[0])
    ]
    let request = SyncRequest(baseRevision: 0, document: document)
    let revision = try await client.upload(request).revision
    #expect(revision == 1)
    #expect(try await client.upload(request).revision == revision)
    let restored = try await client.workspace()
    #expect(restored.revision == revision)
    #expect(restored.document?.entries.first?.end == nil)
    #expect(restored.document?.entries.first?.hourlyRate == "42.123")
    #expect(restored.document?.taxPolicies.first?.effectiveFrom == document.taxPolicies.first?.effectiveFrom)
    #expect(abs(restored.document!.entries[0].start.timeIntervalSince(document.entries[0].start)) < 0.001)
    do {
        _ = try await client.upload(SyncRequest(baseRevision: 0, document: document))
        Issue.record("A stale native client must receive a conflict.")
    } catch APIError.conflict {}
    let identityRate = try await client.rate(base: "EUR", quote: "EUR", date: "2026-10-19")
    #expect(identityRate.rate == "1")
}
