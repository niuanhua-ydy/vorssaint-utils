import Foundation
import SQLite3

public enum SQLValue {
    case null
    case int(Int64)
    case double(Double)
    case text(String)
    case blob(Data)
}

public struct SQLiteError: Error, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public var description: String { "SQLite error \(code): \(message)" }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 对 SQLite C API 的最小封装。非线程安全，调用方（ClipStore）负责串行化访问。
final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?
    /// 已编译语句缓存：避免每次执行都重新编译 SQL（含触发器程序）。动态 SQL 过多时整体清空。
    private var statements: [String: OpaquePointer] = [:]
    private static let statementCacheLimit = 128

    init(path: String) throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "open failed"
            sqlite3_close(handle)
            throw SQLiteError(code: rc, message: message)
        }
        sqlite3_busy_timeout(handle, 3000)
        registerFunctions()
    }

    /// 注册自定义 SQL 函数，供触发器维护短词索引使用
    private func registerFunctions() {
        sqlite3_create_function_v2(handle, "clipnote_segment", 1, SQLITE_UTF8 | SQLITE_DETERMINISTIC, nil, { ctx, _, argv in
            guard let value = argv?[0], let text = sqlite3_value_text(value) else {
                sqlite3_result_null(ctx)
                return
            }
            let segmented = Segmenter.segment(String(cString: text))
            sqlite3_result_text(ctx, segmented, -1, SQLITE_TRANSIENT)
        }, nil, nil, nil)
    }

    deinit {
        statements.values.forEach { sqlite3_finalize($0) }
        sqlite3_close_v2(handle)
    }

    var lastInsertRowID: Int64 { sqlite3_last_insert_rowid(handle) }
    var changes: Int { Int(sqlite3_changes(handle)) }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError(code: rc, message: message)
        }
    }

    func run(_ sql: String, _ params: [SQLValue] = []) throws {
        let stmt = try prepare(sql, params)
        defer { sqlite3_reset(stmt) }
        let rc = sqlite3_step(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else { throw lastError(rc) }
    }

    func query<T>(_ sql: String, _ params: [SQLValue] = [], map: (Row) -> T) throws -> [T] {
        let stmt = try prepare(sql, params)
        // 用完立即 reset，释放读快照，避免长时间占用 WAL
        defer { sqlite3_reset(stmt) }
        var results: [T] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                results.append(map(Row(stmt: stmt!)))
            } else if rc == SQLITE_DONE {
                break
            } else {
                throw lastError(rc)
            }
        }
        return results
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String, _ params: [SQLValue]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        if let cached = statements[sql] {
            stmt = cached
            sqlite3_reset(cached)
            sqlite3_clear_bindings(cached)
        } else {
            if statements.count >= Self.statementCacheLimit {
                statements.values.forEach { sqlite3_finalize($0) }
                statements.removeAll()
            }
            let rc = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &stmt, nil)
            guard rc == SQLITE_OK else { throw lastError(rc) }
            statements[sql] = stmt
        }
        for (i, value) in params.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .null: sqlite3_bind_null(stmt, idx)
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .double(let v): sqlite3_bind_double(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .blob(let v):
                _ = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT) }
            }
        }
        return stmt
    }

    private func lastError(_ rc: Int32) -> SQLiteError {
        SQLiteError(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }

    struct Row {
        let stmt: OpaquePointer

        func int(_ i: Int32) -> Int64 { sqlite3_column_int64(stmt, i) }
        func double(_ i: Int32) -> Double { sqlite3_column_double(stmt, i) }
        func isNull(_ i: Int32) -> Bool { sqlite3_column_type(stmt, i) == SQLITE_NULL }
        func text(_ i: Int32) -> String {
            guard let p = sqlite3_column_text(stmt, i) else { return "" }
            return String(cString: p)
        }
        func optionalText(_ i: Int32) -> String? { isNull(i) ? nil : text(i) }
        func data(_ i: Int32) -> Data? {
            guard let p = sqlite3_column_blob(stmt, i) else { return nil }
            return Data(bytes: p, count: Int(sqlite3_column_bytes(stmt, i)))
        }
        func optionalInt(_ i: Int32) -> Int64? { isNull(i) ? nil : int(i) }
    }
}
