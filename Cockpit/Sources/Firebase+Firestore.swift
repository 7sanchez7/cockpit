import Foundation

/// Firestore en REST : `batchGet` et `runQuery` lisent ; `commit` écrit, pour le SAV seulement (docs/sources/firebase.md).
struct Firestore {
    let projet: String
    let http: HTTP
    let jeton: String

    private var racine: String { "projects/\(projet)/databases/(default)/documents" }

    /// Les documents trouvés parmi `ids`, rangés par id, réduits à `champs`. Cent par appel.
    func documents(_ collection: String, _ ids: [String], champs: [String]) async throws -> [String: Document] {
        var trouves: [String: Document] = [:]
        for debut in stride(from: 0, to: ids.count, by: 100) {
            let noms = ids[debut..<min(debut + 100, ids.count)].map { "\(racine)/\(collection)/\($0)" }
            let corps: [String: Any] = ["documents": noms, "mask": ["fieldPaths": champs]]
            for l in try await http.json([Lu].self, requete(":batchGet", corps)) {
                if let d = l.found {
                    trouves[d.id] = d
                } else if l.missing == nil {
                    throw SourceErreur.format("batchGet \(collection) : ni found ni missing")
                }
            }
        }
        return trouves
    }

    /// Les documents de `collection` dont `champ` vaut `valeur` (typée, `["booleanValue": true]`), réduits à `champs`
    /// (nil : tous les champs).
    func ou(_ collection: String, _ champ: String, egal valeur: [String: Any], champs: [String]?) async throws -> [Document] {
        var structure: [String: Any] = [
            "from": [["collectionId": collection]],
            "where": ["fieldFilter": ["field": ["fieldPath": champ], "op": "EQUAL", "value": valeur] as [String: Any]],
        ]
        if let champs { structure["select"] = Self.selection(champs) }
        return try await requete(structure)
    }

    /// Les `limite` derniers documents de `collection` par `ordre` décroissant, réduits à `champs` (nil : tous) ;
    /// `parent` vise une sous-collection (`users/<uid>`). Un document sans `ordre` n'en fait pas partie.
    func derniers(_ collection: String, sous parent: String? = nil, ordre: String, limite: Int,
                  champs: [String]? = nil) async throws -> [Document] {
        var structure: [String: Any] = [
            "from": [["collectionId": collection]],
            "orderBy": [["field": ["fieldPath": ordre], "direction": "DESCENDING"] as [String: Any]],
            "limit": limite,
        ]
        if let champs { structure["select"] = Self.selection(champs) }
        return try await requete(structure, parent: parent)
    }

    /// Écrit tout ou rien (`ecriture`, `["delete": nom]`).
    func commit(_ ecritures: [[String: Any]]) async throws {
        _ = try await http.donnees(requete(":commit", ["writes": ecritures]))
    }

    /// Remplace les `champs` de `chemin` (`users/<uid>`) sans toucher aux autres ; `existe` false crée le document
    /// et échoue s'il est déjà là, true échoue s'il n'existe pas.
    func ecriture(_ chemin: String, _ champs: [String: Any?], existe: Bool) throws -> [String: Any] {
        [
            "update": ["name": "\(racine)/\(chemin)", "fields": try champs.mapValues(Self.valeur)] as [String: Any],
            "updateMask": ["fieldPaths": Array(champs.keys)],
            "currentDocument": ["exists": existe],
        ]
    }

    /// Une valeur Swift en valeur typée de Firestore REST.
    static func valeur(_ v: Any?) throws -> [String: Any] {
        switch v {
        case .none: ["nullValue": NSNull()]
        case let b as Bool: ["booleanValue": b]
        case let n as Int: ["integerValue": String(n)]
        case let s as String: ["stringValue": s]
        case let d as Date: ["timestampValue": Date.isoFractions.string(from: d)]
        case let m as [String: Any?]: ["mapValue": ["fields": try m.mapValues(valeur)]]
        case let .some(x): throw SourceErreur.format("valeur Firestore non prise en charge : \(type(of: x))")
        }
    }

    private static func selection(_ champs: [String]) -> [String: Any] {
        ["fields": champs.map { ["fieldPath": $0] }]
    }

    /// Lance une requête structurée, à la racine ou sous `parent`.
    private func requete(_ structure: [String: Any], parent: String? = nil) async throws -> [Document] {
        let chemin = parent.map { "/\($0):runQuery" } ?? ":runQuery"
        // une réponse sans `document` ne porte que readTime : aucun résultat
        return try await http.json([Trouve].self, requete(chemin, ["structuredQuery": structure])).compactMap(\.document)
    }

    private func requete(_ methode: String, _ corps: [String: Any]) throws -> URLRequest {
        try HTTP.requete("https://firestore.googleapis.com/v1/\(racine)\(methode)", methode: "POST", jeton: jeton,
                         corps: corps, entetes: ["x-goog-user-project": projet])
    }

    private struct Lu: Decodable {
        let found: Document?
        let missing: String?
    }

    private struct Trouve: Decodable {
        let document: Document?
    }

    /// Un document lu en REST, ses champs décodés.
    struct Document: Decodable {
        let name: String
        let fields: [String: Valeur]?

        var id: String { String(name.split(separator: "/").last ?? "") }

        subscript(_ champ: String) -> Valeur? { fields?[champ] }
    }

    /// Une valeur typée de Firestore REST : `{"integerValue": "22"}`, `{"mapValue": {"fields": …}}`…
    indirect enum Valeur: Decodable, Equatable {
        case entier(Int), reel(Double), texte(String), booleen(Bool), instant(Date)
        case carte([String: Valeur]), liste([Valeur]), nul

        var nombre: Double? {
            switch self {
            case .entier(let n): Double(n)
            case .reel(let x): x
            default: nil
            }
        }

        var texte: String? { if case .texte(let s) = self { s } else { nil } }
        var instant: Date? { if case .instant(let d) = self { d } else { nil } }
        var booleen: Bool? { if case .booleen(let b) = self { b } else { nil } }

        subscript(_ cle: String) -> Valeur? { if case .carte(let m) = self { m[cle] } else { nil } }

        private enum Cle: String, CodingKey {
            case integerValue, doubleValue, stringValue, booleanValue, timestampValue, mapValue, arrayValue, nullValue
            case fields, values
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Cle.self)
            if let s = try c.decodeIfPresent(String.self, forKey: .integerValue) {
                // int64 en chaîne
                guard let n = Int(s) else {
                    throw DecodingError.dataCorruptedError(forKey: .integerValue, in: c, debugDescription: "entier illisible")
                }
                self = .entier(n)
            } else if let x = try c.decodeIfPresent(Double.self, forKey: .doubleValue) {
                self = .reel(x)
            } else if let s = try c.decodeIfPresent(String.self, forKey: .stringValue) {
                self = .texte(s)
            } else if let b = try c.decodeIfPresent(Bool.self, forKey: .booleanValue) {
                self = .booleen(b)
            } else if let s = try c.decodeIfPresent(String.self, forKey: .timestampValue) {
                guard let d = Date(iso: s) else {
                    throw DecodingError.dataCorruptedError(forKey: .timestampValue, in: c, debugDescription: "instant illisible")
                }
                self = .instant(d)
            } else if c.contains(.mapValue) {
                let m = try c.nestedContainer(keyedBy: Cle.self, forKey: .mapValue)
                self = .carte(try m.decodeIfPresent([String: Valeur].self, forKey: .fields) ?? [:])
            } else if c.contains(.arrayValue) {
                let l = try c.nestedContainer(keyedBy: Cle.self, forKey: .arrayValue)
                self = .liste(try l.decodeIfPresent([Valeur].self, forKey: .values) ?? [])
            } else if c.contains(.nullValue) {
                self = .nul
            } else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "type Firestore non lu"))
            }
        }
    }
}
