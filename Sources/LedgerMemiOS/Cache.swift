import Foundation
import SQLite3

/// Dependency-free SQLite-backed cache for memories. Wraps the C `sqlite3`
/// API directly so the package has zero third-party dependencies.
public final class MemoryCache: @unchecked Sendable {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "dev.proofly.getmnemo.cache")

    public init(path: String) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open(path, &handle)
        guard result == SQLITE_OK, let db = handle else {
            throw MnemoError.transport("sqlite open failed: \(result)")
        }
        self.db = db
        try migrate()
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Schema

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS memories (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            tags TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            workspace_id TEXT NOT NULL
        );
        CREATE INDEX IF NOT EXISTS memories_updated_at ON memories(updated_at DESC);
        """)
    }

    // MARK: - API

    public func upsert(_ memory: Memory) throws {
        try queue.sync {
            let sql = """
            INSERT INTO memories (id, text, tags, created_at, updated_at, workspace_id)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                text = excluded.text,
                tags = excluded.tags,
                updated_at = excluded.updated_at,
                workspace_id = excluded.workspace_id;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MnemoError.transport("prepare failed: \(errorMessage())")
            }
            defer { sqlite3_finalize(stmt) }
            let isoFormatter = ISO8601DateFormatter()
            sqlite3_bind_text(stmt, 1, memory.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, memory.text, -1, SQLITE_TRANSIENT)
            let tags = (try? String(data: JSONEncoder().encode(memory.tags), encoding: .utf8)) ?? "[]"
            sqlite3_bind_text(stmt, 3, tags, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, isoFormatter.string(from: memory.createdAt), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, isoFormatter.string(from: memory.updatedAt), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 6, memory.workspaceId, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw MnemoError.transport("upsert failed: \(errorMessage())")
            }
        }
    }

    public func upsertAll(_ memories: [Memory]) throws {
        for memory in memories { try upsert(memory) }
    }

    public func recent(limit: Int = 50) throws -> [Memory] {
        try queue.sync {
            var stmt: OpaquePointer?
            let sql = "SELECT id, text, tags, created_at, updated_at, workspace_id FROM memories ORDER BY updated_at DESC LIMIT ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MnemoError.transport("prepare failed: \(errorMessage())")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var memories: [Memory] = []
            let formatter = ISO8601DateFormatter()
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard
                    let idC = sqlite3_column_text(stmt, 0),
                    let textC = sqlite3_column_text(stmt, 1),
                    let tagsC = sqlite3_column_text(stmt, 2),
                    let createdC = sqlite3_column_text(stmt, 3),
                    let updatedC = sqlite3_column_text(stmt, 4),
                    let wsC = sqlite3_column_text(stmt, 5)
                else { continue }
                let tagsData = Data(String(cString: tagsC).utf8)
                let tags = (try? JSONDecoder().decode([String].self, from: tagsData)) ?? []
                let createdAt = formatter.date(from: String(cString: createdC)) ?? Date()
                let updatedAt = formatter.date(from: String(cString: updatedC)) ?? Date()
                memories.append(Memory(
                    id: String(cString: idC),
                    text: String(cString: textC),
                    tags: tags,
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    workspaceId: String(cString: wsC)
                ))
            }
            return memories
        }
    }

    public func remove(id: String) throws {
        try queue.sync {
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "DELETE FROM memories WHERE id = ?;", -1, &stmt, nil) == SQLITE_OK else {
                throw MnemoError.transport("prepare failed: \(errorMessage())")
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(stmt) == SQLITE_DONE else {
                throw MnemoError.transport("delete failed: \(errorMessage())")
            }
        }
    }

    // MARK: - Internals

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(error)
            throw MnemoError.transport("sqlite exec: \(message)")
        }
    }

    private func errorMessage() -> String {
        guard let raw = sqlite3_errmsg(db) else { return "unknown" }
        return String(cString: raw)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
