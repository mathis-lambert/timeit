import Foundation
import Testing

@testable import TimeitCore

@Test func interruptedUploadReusesItsIdentifierAndDoesNotMarkNewEditsAsUploaded() throws {
    var state = LocalState()
    state.sync.localVersion = 1
    state.document.profile.name = "First edit"
    let first = state.sync.prepareUpload(document: state.document)
    let database = try LocalDatabase()
    try database.save(state)
    var restored = try database.load()
    restored.document.profile.name = "Second edit during upload"
    restored.sync.localVersion += 1
    let retry = restored.sync.prepareUpload(document: restored.document)
    #expect(retry.request.mutationID == first.request.mutationID)
    #expect(retry.request.document.profile.name == "First edit")
    restored.sync.acknowledge(revision: 1)
    #expect(restored.sync.hasChanges)
    let second = restored.sync.prepareUpload(document: restored.document)
    #expect(second.request.baseRevision == 1)
    #expect(second.request.mutationID != first.request.mutationID)
    #expect(second.request.document.profile.name == "Second edit during upload")
    restored.sync.acknowledge(revision: 2)
    #expect(!restored.sync.hasChanges)
}
