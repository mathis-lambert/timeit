import Foundation
import GRDB

public struct SyncMetadata: Codable, Sendable {
    public var revision = 0
    public var localVersion = 0
    public var uploadedVersion = 0
    public var ownerID: String?
    public var pendingUpload: PendingUpload?
    public init() {}
    public var hasChanges: Bool { localVersion != uploadedVersion }
    public mutating func prepareUpload(document: Workspace) -> PendingUpload {
        if let pendingUpload { return pendingUpload }
        let pending = PendingUpload(
            request: SyncRequest(baseRevision: revision, document: document), localVersion: localVersion)
        pendingUpload = pending
        return pending
    }
    public mutating func acknowledge(revision: Int) {
        guard let pendingUpload else { return }
        self.revision = revision
        uploadedVersion = pendingUpload.localVersion
        self.pendingUpload = nil
    }
}

public struct PendingUpload: Codable, Sendable {
    public var request: SyncRequest
    public var localVersion: Int
}

public struct LocalState: Codable, Sendable {
    public var document = Workspace()
    public var sync = SyncMetadata()
    public var rates: [ExchangeRate] = []
    public init() {}
}

public final class LocalDatabase: Sendable {
    private let database: DatabaseQueue
    public init(path: String? = nil) throws {
        database = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("initial") { db in
            try db.create(table: "state") { table in
                table.column("id", .integer).primaryKey()
                table.column("json", .blob).notNull()
            }
            try db.create(table: "conflicts") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("createdAt", .datetime).notNull()
                table.column("json", .blob).notNull()
            }
        }
        try migrator.migrate(database)
    }
    public func load() throws -> LocalState {
        try database.read { db in
            guard let data = try Data.fetchOne(db, sql: "SELECT json FROM state WHERE id=1") else {
                return LocalState()
            }
            let state = try WireFormat.decoder().decode(LocalState.self, from: data)
            guard state.document.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
            return state
        }
    }
    public func save(_ state: LocalState) throws {
        let data = try WireFormat.encoder().encode(state)
        try database.write { db in
            try db.execute(
                sql: "INSERT INTO state(id,json) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET json=excluded.json",
                arguments: [data])
        }
    }
    public func preserveConflict(_ document: Workspace) throws {
        let data = try WireFormat.encoder().encode(document)
        try database.write { db in
            try db.execute(sql: "INSERT INTO conflicts(createdAt,json) VALUES(?,?)", arguments: [Date(), data])
        }
    }
    public enum StoreError: LocalizedError {
        case unsupportedVersion
        public var errorDescription: String? { "Ces données ont été créées par une version plus récente de Timeit." }
    }
}
