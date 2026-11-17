import Foundation
import SQLite3

/// Une ligne de résultat, colonnes par nom. Une colonne NULL est absente.
struct Ligne {
    let colonnes: [String: Any]

    func texte(_ c: String) -> String? { colonnes[c] as? String }
    func entier(_ c: String) -> Int? { (colonnes[c] as? Int64).map(Int.init) ?? (colonnes[c] as? Double).map { Int($0) } }
    func nombre(_ c: String) -> Double? { (colonnes[c] as? Double) ?? (colonnes[c] as? Int64).map(Double.init) }
    func date(_ c: String) -> Date? { texte(c).flatMap { Date(iso: $0) } }
    func donnees(_ c: String) -> Data? { colonnes[c] as? Data }
    func booleen(_ c: String) -> Bool { (entier(c) ?? 0) != 0 }
}

struct ErreurSQL: LocalizedError {
    let message: String
    var errorDescription: String? { "SQLite : \(message)" }
}

private let transitoire = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// SQLite3 sans dépendance. Paramètres : Int, Double, Bool, String, Date (écrite en ISO), nil.
final class Database {
    private var db: OpaquePointer?
    private var profondeur = 0

    /// `lecture` ouvre la base d'une autre app sans jamais l'écrire ni toucher à son journal.
    init(chemin: String, lecture: Bool = false) throws {
        let drapeaux = lecture ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        guard sqlite3_open_v2(chemin, &db, drapeaux, nil) == SQLITE_OK else {
            sqlite3_close(db)
            db = nil
            throw ErreurSQL(message: "ouverture de \(chemin) impossible")
        }
        sqlite3_busy_timeout(db, 5000)
        if !lecture { try script("pragma journal_mode = wal; pragma synchronous = normal;") }
    }

    isolated deinit { sqlite3_close(db) }

    /// Lignes modifiées par la dernière écriture.
    var changements: Int { Int(sqlite3_changes(db)) }

    /// Plusieurs instructions sans paramètres (le schéma).
    func script(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw erreur() }
    }

    func execute(_ sql: String, _ params: [Any?] = []) throws {
        _ = try query(sql, params)
    }

    func query(_ sql: String, _ params: [Any?] = []) throws -> [Ligne] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw erreur() }
        defer { sqlite3_finalize(stmt) }
        try lier(stmt, params)
        var lignes: [Ligne] = []
        while true {
            let r = sqlite3_step(stmt)
            if r == SQLITE_DONE { return lignes }
            guard r == SQLITE_ROW else { throw erreur() }
            var colonnes: [String: Any] = [:]
            for i in 0..<sqlite3_column_count(stmt) {
                let nom = String(cString: sqlite3_column_name(stmt, i))
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: colonnes[nom] = sqlite3_column_int64(stmt, i)
                case SQLITE_FLOAT: colonnes[nom] = sqlite3_column_double(stmt, i)
                case SQLITE_TEXT: colonnes[nom] = String(cString: sqlite3_column_text(stmt, i))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, i))
                    colonnes[nom] = sqlite3_column_blob(stmt, i).map { Data(bytes: $0, count: n) } ?? Data()
                default: break
                }
            }
            lignes.append(Ligne(colonnes: colonnes))
        }
    }

    func colonneExiste(_ table: String, _ colonne: String) throws -> Bool {
        try query("select name from pragma_table_info(?)", [table]).contains { $0.texte("name") == colonne }
    }

    /// Tout ou rien. Une transaction dans une transaction rejoint la première.
    func transaction<T>(_ f: () throws -> T) throws -> T {
        if profondeur > 0 { return try f() }
        try script("begin immediate")
        profondeur += 1
        defer { profondeur -= 1 }
        do {
            let r = try f()
            try script("commit")
            return r
        } catch {
            sqlite3_exec(db, "rollback", nil, nil, nil)
            throw error
        }
    }

    private func lier(_ stmt: OpaquePointer?, _ params: [Any?]) throws {
        for (i, p) in params.enumerated() {
            let n = Int32(i + 1)
            switch p {
            case .none: sqlite3_bind_null(stmt, n)
            case let v as Bool: sqlite3_bind_int64(stmt, n, v ? 1 : 0)
            case let v as Int: sqlite3_bind_int64(stmt, n, Int64(v))
            case let v as Int64: sqlite3_bind_int64(stmt, n, v)
            case let v as Double: sqlite3_bind_double(stmt, n, v)
            case let v as String: sqlite3_bind_text(stmt, n, v, -1, transitoire)
            case let v as Date: sqlite3_bind_text(stmt, n, v.iso, -1, transitoire)
            case let .some(v): throw ErreurSQL(message: "type non pris en charge : \(type(of: v))")
            }
        }
    }

    private func erreur() -> ErreurSQL {
        ErreurSQL(message: String(cString: sqlite3_errmsg(db)))
    }
}
