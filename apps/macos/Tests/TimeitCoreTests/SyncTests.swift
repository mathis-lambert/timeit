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

@Test func eachWriteOnlyTouchesItsOwnPart() throws {
    let database = try LocalDatabase()
    var state = LocalState()
    state.sync.localVersion = 2
    let pending = state.sync.prepareUpload(document: state.document)
    try database.save(state)
    let rate = ExchangeRate(
        base: "USD", quote: "EUR", requestedDate: "2026-10-19", observedDate: "2026-10-17", rate: "0.89", source: "Test"
    )
    try database.saveRates([rate])

    state.document.profile.name = "Edited"
    try database.saveEdit(state.document, localVersion: 3)
    var restored = try database.load()
    #expect(restored.document.profile.name == "Edited")
    #expect(restored.sync.localVersion == 3)
    #expect(restored.sync.pendingUpload?.request.mutationID == pending.request.mutationID)
    #expect(restored.rates == [rate])

    restored.sync.acknowledge(revision: 7)
    try database.saveSync(restored.sync)
    var corrected = rate
    corrected.rate = "0.9"
    try database.saveRates([corrected])
    let final = try database.load()
    #expect(final.sync.revision == 7)
    #expect(final.sync.pendingUpload == nil)
    #expect(final.sync.localVersion == 3)
    #expect(final.document.profile.name == "Edited")
    #expect(final.rates == [corrected])
}
