import CryptoKit
import Foundation

/// Avis, tâches « répondre à l'avis », changements d'état des versions et téléchargements par jour (rapports de ventes),
/// par l'API App Store Connect en lecture seule.
/// Voir docs/sources/app-store-connect.md. La note et le nombre de notes viennent de Classements.
struct AppStoreConnect: Source {
    let id = "asc"
    let nom = "App Store Connect"
    let cadence: TimeInterval = 60 * 60

    static let base = "https://api.appstoreconnect.apple.com/v1"
    /// Là où Apple et les outils de Roleo rangent la clé `AuthKey_<KEYID>.p8` ; elle n'en sort jamais.
    static let dossierCles = URL.homeDirectory.appending(path: ".appstoreconnect/private_keys")
    /// Un avis entre dans le fil s'il a moins de 7 jours.
    static let fenetreFil: TimeInterval = 7 * 86_400
    /// Rapports de ventes : les jours manquants des 90 derniers ; un jour sans téléchargement n'a pas de rapport (404),
    /// il vaut 0 passé 3 jours.
    static let historiqueVentes = 90
    static let retardVentes = 3
    /// Types de produit d'un premier téléchargement ; retéléchargements (3F…) et mises à jour (7F…) exclus.
    static let premiersTelechargements: Set<String> = ["1", "1F", "1T", "F1", "1E", "1EP", "1EU"]

    func collecte(_ ctx: Contexte) async throws -> Int {
        let suivis = ctx.businesses.filter { $0.config.appStoreId != nil && $0.config.ascIssuer != nil }
        guard !suivis.isEmpty else { throw SourceErreur.nonConfigure("aucun business avec appStoreId et ascIssuer") }
        let (kid, cle) = try Self.cle()
        let premier = try ctx.store.dernierSucces(id) == nil
        var lignes = 0
        for b in suivis {
            do {
                lignes += try await collecte(b, kid: kid, cle: cle, premier: premier, ctx)
            } catch {
                throw Self.nomme(error, b)
            }
        }
        return lignes
    }

    private func collecte(_ b: Business, kid: String, cle: P256.Signing.PrivateKey, premier: Bool,
                          _ ctx: Contexte) async throws -> Int {
        guard let app = b.config.appStoreId, let issuer = b.config.ascIssuer else { return 0 }
        let jeton = try Self.jeton(kid: kid, issuer: issuer, cle: cle)
        func lire(_ chemin: String) async throws -> Data {
            try await ctx.http.donnees(HTTP.requete(Self.base + chemin, jeton: jeton))
        }
        // 200 avis tiennent sur une page, bien au-delà de ce que l'app reçoit
        let avis = try Self.avis(try await lire("/apps/\(app)/customerReviews?sort=-createdDate&limit=200&include=response"),
                                 business: b.id)
        let version = try Self.version(try await lire("/apps/\(app)/appStoreVersions?limit=5"), business: b.id,
                                       app: app, at: premier ? nil : .now)
        let lignes = try Self.ecrire(avis, version: version, app: app, business: b.id, ctx.store)
        guard let vendeur = b.config.ascVendor else { return lignes }
        return lignes + (try await telechargements(b, app: app, vendeur: vendeur, jeton: jeton, ctx))
    }

    /// Les téléchargements des jours qui manquent, un rapport de ventes quotidien par jour.
    private func telechargements(_ b: Business, app: String, vendeur: String, jeton: String, _ ctx: Contexte) async throws -> Int {
        let aujourdhui = Jour.aujourdhui
        let lus = try ctx.store.db.query("select jour from serie where business = ? and metrique = ? and heure = -1",
                                         [b.id, Boutique.appStore.metrique(Metrique.telechargements)]).compactMap { $0.texte("jour") }
        var lignes = 0
        for jour in Self.aRelire(Set(lus), jusqua: aujourdhui) {
            var url = URLComponents(string: Self.base + "/salesReports")!
            url.queryItems = [("frequency", "DAILY"), ("reportType", "SALES"), ("reportSubType", "SUMMARY"),
                              ("vendorNumber", vendeur), ("reportDate", jour), ("version", "1_1")]
                .map { URLQueryItem(name: "filter[\($0.0)]", value: $0.1) }
            let n: Double
            do {
                let rapport = try await ctx.http.donnees(HTTP.requete(url.url!.absoluteString, jeton: jeton,
                                                                     entetes: ["Accept": "application/a-gzip"]))
                n = try Self.telechargements(rapport.starts(with: [0x1F, 0x8B]) ? try Notes.gunzip(rapport) : rapport, app: app)
            } catch SourceErreur.http(404, _) {
                guard jour <= Jour.decale(aujourdhui, jours: -Self.retardVentes) else { continue }
                n = 0
            }
            try Boutique.appStore.telechargements(b.id, jour: jour, n, ctx.store)
            lignes += 1
        }
        return lignes
    }

    /// Les jours des 90 derniers, hier compris, qui n'ont pas encore de valeur, du plus ancien au plus récent.
    static func aRelire(_ lus: Set<String>, jusqua aujourdhui: String) -> [String] {
        Jour.derniers(historiqueVentes, jusqua: Jour.decale(aujourdhui, jours: -1)).filter { !lus.contains($0) }
    }

    /// Un rapport de ventes quotidien (TSV) : la somme des `Units` des premiers téléchargements de l'app.
    static func telechargements(_ tsv: Data, app: String) throws -> Double {
        let lignes = String(decoding: tsv, as: UTF8.self).split(whereSeparator: \.isNewline).map {
            $0.split(separator: "\t", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        guard let entete = lignes.first, let type = entete.firstIndex(of: "Product Type Identifier"),
              let unites = entete.firstIndex(of: "Units"), let id = entete.firstIndex(of: "Apple Identifier") else {
            throw SourceErreur.format("rapport de ventes sans Product Type Identifier, Units ou Apple Identifier")
        }
        return lignes.dropFirst().reduce(0) { n, l in
            guard l.count > max(type, unites, id), l[id] == app, premiersTelechargements.contains(l[type]) else { return n }
            return n + (Double(l[unites]) ?? 0)
        }
    }

    /// Les avis, le fil (avis récents, état de version) et les tâches ; rend le nombre de lignes écrites.
    static func ecrire(_ avis: [Avis], version: Evenement?, app: String, business: String, _ store: Store,
                       maintenant: Date = .now) throws -> Int {
        let fil = filAvis(avis, app: app, maintenant: maintenant) + [version].compactMap { $0 }
        let aFaire = taches(avis, app: app)
        var lignes = avis.count + aFaire.count
        try store.lot {
            for a in avis { try store.avis(a) }
            for e in fil { if try store.fil(e) { lignes += 1 } }
        }
        try store.synchroniserTaches(source: "asc", business: business, aFaire)
        return lignes
    }

    // MARK: jeton

    /// La première clé `AuthKey_<KEYID>.p8` du dossier ; son KEYID vient du nom du fichier.
    static func cle(dossier: URL = dossierCles) throws -> (kid: String, cle: P256.Signing.PrivateKey) {
        let fichiers = (try? FileManager.default.contentsOfDirectory(atPath: dossier.path)) ?? []
        guard let nom = fichiers.filter({ $0.hasPrefix("AuthKey_") && $0.hasSuffix(".p8") }).sorted().first else {
            throw SourceErreur.nonConfigure("aucune clé AuthKey_<KEYID>.p8 dans ~/.appstoreconnect/private_keys")
        }
        let kid = String(nom.dropFirst("AuthKey_".count).dropLast(".p8".count))
        do {
            let pem = try String(contentsOf: dossier.appending(path: nom), encoding: .utf8)
            return (kid, try P256.Signing.PrivateKey(pemRepresentation: pem))
        } catch {
            throw SourceErreur.nonConfigure("clé \(nom) illisible")
        }
    }

    /// JWT ES256 d'App Store Connect, valable 19 minutes (Apple refuse au-delà de 20).
    static func jeton(kid: String, issuer: String, cle: P256.Signing.PrivateKey, maintenant: Date = .now) throws -> String {
        let iat = Int(maintenant.timeIntervalSince1970)
        let entete: [String: Any] = ["alg": "ES256", "kid": kid, "typ": "JWT"]
        let charge: [String: Any] = ["iss": issuer, "iat": iat, "exp": iat + 19 * 60, "aud": "appstoreconnect-v1"]
        return try JWT.jeton(entete: entete, charge: charge) { try cle.signature(for: $0).rawRepresentation }
    }

    // MARK: décodage

    private static func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SourceErreur.format("\(T.self) : \(error)")
        }
    }

    private static func date(_ texte: String) throws -> Date {
        guard let d = Date(iso: texte) else { throw SourceErreur.format("date illisible : \(texte)") }
        return d
    }

    /// `customerReviews` avec `include=response` : `relationships.response.data` est nul tant qu'on n'a pas répondu.
    static func avis(_ data: Data, business: String) throws -> [Avis] {
        struct Reponse: Decodable { let data: [R] }
        struct R: Decodable { let id: String; let attributes: A; let relationships: Liens? }
        struct A: Decodable {
            let rating: Int
            let title: String?
            let body: String?
            let reviewerNickname: String?
            let createdDate: String
            let territory: String?
        }
        struct Liens: Decodable { let response: Lien? }
        struct Lien: Decodable { let data: Ref? }
        struct Ref: Decodable { let id: String }
        return try decode(Reponse.self, data).data.map { r in
            let a = r.attributes
            return Avis(id: r.id, business: business, pays: a.territory, note: a.rating, titre: a.title, texte: a.body,
                        auteur: a.reviewerNickname, at: try date(a.createdDate),
                        repondu: r.relationships?.response?.data != nil)
        }
    }

    static func lienAvis(_ app: String) -> String {
        "https://appstoreconnect.apple.com/apps/\(app)/distribution/activity/ios/ratingsResponses"
    }

    /// Une tâche par avis de 3 étoiles ou moins sans réponse ; 1 ou 2 étoiles en alerte.
    static func taches(_ avis: [Avis], app: String) -> [Tache] {
        avis.filter { $0.note <= 3 && !$0.repondu }.map { a in
            let titre = a.titre.map { ", « \($0.prefix(60)) »" } ?? ""
            return Tache(cle: "avis:\(a.id)", texte: "Répondre à \(a.auteur ?? "un avis")\(titre)",
                         etiquette: "\(a.note) ★", ton: a.note <= 2 ? .alerte : .neutre, lien: lienAvis(app))
        }
    }

    /// Les avis de moins de 7 jours, en lignes AVIS du fil.
    static func filAvis(_ avis: [Avis], app: String, maintenant: Date = .now) -> [Evenement] {
        avis.filter { $0.at >= maintenant.addingTimeInterval(-fenetreFil) }.map { a in
            let etoiles = String(repeating: "★", count: a.note) + String(repeating: "☆", count: max(0, 5 - a.note))
            return Evenement(id: "asc:avis:\(a.id)", business: a.business, at: a.at, type: .avis,
                             texte: [etoiles, a.titre].compactMap { $0 }.joined(separator: " "), lien: lienAvis(app))
        }
    }

    /// L'état de la version iOS la plus récente, en ligne VERSION : une ligne par état, donc une par changement.
    /// `at` nil (premier passage) date la ligne de la création de la version, sinon du passage qui voit le changement.
    static func version(_ data: Data, business: String, app: String, at: Date?) throws -> Evenement? {
        struct Reponse: Decodable { let data: [V] }
        struct V: Decodable { let id: String; let attributes: A }
        struct A: Decodable { let versionString: String; let appStoreState: String; let platform: String?; let createdDate: String }
        let versions = try decode(Reponse.self, data).data.filter { ($0.attributes.platform ?? "IOS") == "IOS" }
        guard let v = try versions.max(by: { try date($0.attributes.createdDate) < date($1.attributes.createdDate) }) else {
            return nil
        }
        let a = v.attributes
        return Evenement(id: "asc:version:\(v.id):\(a.appStoreState)", business: business, at: try at ?? date(a.createdDate),
                         type: .version, texte: "\(a.versionString) \(etat(a.appStoreState))",
                         lien: "https://appstoreconnect.apple.com/apps/\(app)/distribution")
    }

    static func etat(_ code: String) -> String {
        switch code {
        case "PREPARE_FOR_SUBMISSION": "en préparation"
        case "READY_FOR_REVIEW": "prête pour l'examen"
        case "WAITING_FOR_REVIEW": "en attente d'examen"
        case "IN_REVIEW": "en examen"
        case "ACCEPTED": "acceptée"
        case "PENDING_DEVELOPER_RELEASE": "validée, à publier"
        case "PENDING_APPLE_RELEASE": "validée, publication par Apple"
        case "PROCESSING_FOR_APP_STORE", "PROCESSING_FOR_DISTRIBUTION": "en traitement"
        case "READY_FOR_SALE", "READY_FOR_DISTRIBUTION": "en vente"
        case "REJECTED": "refusée"
        case "METADATA_REJECTED": "métadonnées refusées"
        case "DEVELOPER_REJECTED": "retirée de l'examen"
        case "INVALID_BINARY": "binaire invalide"
        case "WAITING_FOR_EXPORT_COMPLIANCE": "en attente de conformité export"
        case "REMOVED_FROM_SALE", "DEVELOPER_REMOVED_FROM_SALE": "retirée de la vente"
        case "REPLACED_WITH_NEW_VERSION": "remplacée"
        default: code.lowercased().replacingOccurrences(of: "_", with: " ")
        }
    }

    /// Le message d'erreur nomme le business (`Roleo : HTTP 401 …`).
    static func nomme(_ error: Error, _ b: Business) -> Error {
        switch error {
        case SourceErreur.nonConfigure(let m): SourceErreur.nonConfigure("\(b.nom) : \(m)")
        case SourceErreur.http(let code, let m): SourceErreur.http(code, "\(b.nom) : \(m)")
        case SourceErreur.format(let m): SourceErreur.format("\(b.nom) : \(m)")
        case SourceErreur.commande(let m): SourceErreur.commande("\(b.nom) : \(m)")
        default: error
        }
    }
}
