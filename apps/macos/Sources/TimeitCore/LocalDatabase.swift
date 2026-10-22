import Foundation
import GRDB

public struct SyncMetadata: Sendable {
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

public struct LocalState: Sendable {
    public var document = Workspace()
    public var sync = SyncMetadata()
    public var rates: [ExchangeRate] = []
    public init() {}
}

/// Local SQLite store. The document, sync bookkeeping and rate cache live in separate tables so an edit
/// rewrites only the document, and a sync step rewrites only its bookkeeping.
public final class LocalDatabase: Sendable {
    private let database: DatabaseQueue
    public init(path: String? = nil) throws {
        database = try path.map { try DatabaseQueue(path: $0) } ?? DatabaseQueue()
        var migrator = DatabaseMigrator()
        migrator.registerMigration("schema") { db in
            try db.create(table: "workspace") { table in
                table.column("id", .integer).primaryKey(onConflict: .replace)
                table.column("document", .blob).notNull()
                table.column("localVersion", .integer).notNull()
            }
            try db.create(table: "sync") { table in
                table.column("id", .integer).primaryKey(onConflict: .replace)
                table.column("revision", .integer).notNull()
                table.column("uploadedVersion", .integer).notNull()
                table.column("ownerID", .text)
                table.column("pendingUpload", .blob)
            }
            try db.create(table: "rate") { table in
                table.column("key", .text).primaryKey(onConflict: .replace)
                table.column("value", .blob).notNull()
            }
            try db.create(table: "conflict") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("createdAt", .datetime).notNull()
                table.column("document", .blob).notNull()
            }
        }
        try migrator.migrate(database)
    }

    public func load() throws -> LocalState {
        try database.read { db in
            let decoder = WireFormat.decoder()
            var state = LocalState()
            if let row = try Row.fetchOne(db, sql: "SELECT document, localVersion FROM workspace WHERE id = 1") {
                state.document = try decoder.decode(Workspace.self, from: row["document"] as Data)
                state.sync.localVersion = row["localVersion"]
            }
            guard state.document.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
            if let row = try Row.fetchOne(
                db, sql: "SELECT revision, uploadedVersion, ownerID, pendingUpload FROM sync WHERE id = 1")
            {
                state.sync.revision = row["revision"]
                state.sync.uploadedVersion = row["uploadedVersion"]
                state.sync.ownerID = row["ownerID"]
                state.sync.pendingUpload = try (row["pendingUpload"] as Data?).map {
                    try decoder.decode(PendingUpload.self, from: $0)
                }
            }
            state.rates = try Data.fetchAll(db, sql: "SELECT value FROM rate ORDER BY key").map {
                try decoder.decode(ExchangeRate.self, from: $0)
            }
            return state
        }
    }

    /// Persists a local edit: the document and its version, nothing else.
    public func saveEdit(_ document: Workspace, localVersion: Int) throws {
        let data = try WireFormat.encoder().encode(document)
        try database.write { try Self.writeDocument(data, localVersion: localVersion, in: $0) }
    }

    /// Persists sync bookkeeping. The local version is owned by `saveEdit`.
    public func saveSync(_ sync: SyncMetadata) throws {
        let pending = try sync.pendingUpload.map { try WireFormat.encoder().encode($0) }
        try database.write { try Self.writeSync(sync, pending: pending, in: $0) }
    }

    public func saveRates(_ rates: [ExchangeRate]) throws {
        let encoder = WireFormat.encoder()
        let rows = try rates.map { ($0.key, try encoder.encode($0)) }
        try database.write { db in
            for (key, value) in rows {
                try db.execute(sql: "INSERT INTO rate(key, value) VALUES(?, ?)", arguments: [key, value])
            }
        }
    }

    /// Writes the document and sync bookkeeping in one transaction, for steps that change both (remote
    /// document applied, conflict resolved). A document being replaced can be kept as a conflict backup.
    /// The rate cache is written separately with `saveRates`.
    public func save(_ state: LocalState, preservingConflict replaced: Workspace? = nil) throws {
        let encoder = WireFormat.encoder()
        let document = try encoder.encode(state.document)
        let pending = try state.sync.pendingUpload.map { try encoder.encode($0) }
        let backup = try replaced.map { try encoder.encode($0) }
        try database.write { db in
            try Self.writeDocument(document, localVersion: state.sync.localVersion, in: db)
            try Self.writeSync(state.sync, pending: pending, in: db)
            if let backup {
                try db.execute(
                    sql: "INSERT INTO conflict(createdAt, document) VALUES(?, ?)", arguments: [Date(), backup])
            }
        }
    }

    private static func writeDocument(_ data: Data, localVersion: Int, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO workspace(id, document, localVersion) VALUES(1, ?, ?)", arguments: [data, localVersion])
    }
    private static func writeSync(_ sync: SyncMetadata, pending: Data?, in db: Database) throws {
        try db.execute(
            sql: "INSERT INTO sync(id, revision, uploadedVersion, ownerID, pendingUpload) VALUES(1, ?, ?, ?, ?)",
            arguments: [sync.revision, sync.uploadedVersion, sync.ownerID, pending])
    }

    public enum StoreError: LocalizedError {
        case unsupportedVersion
        public var errorDescription: String? { "Ces données ont été créées par une version plus récente de Timeit." }
    }
}
