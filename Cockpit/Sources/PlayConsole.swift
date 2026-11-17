import Foundation
import Security

/// Les installs Play par jour, lus dans les rapports groupés de la Play Console (Cloud Storage) avec le compte de service
/// du business. Voir docs/sources/play-console.md.
struct PlayConsole: Source {
    let id = "playconsole"
    let nom = "Play Console"
    let cadence: TimeInterval = 3 * 3600
    /// La clé JSON du compte de service : `<business>-play-publisher.json`, hors du dépôt.
    static let dossierCles = URL.homeDirectory.appending(path: ".googleplay")
    static let portee = "https://www.googleapis.com/auth/devstorage.read_only"
    static let stockage = "https://storage.googleapis.com/storage/v1/b"
    /// Les mois relus à chaque passage : de quoi couvrir 91 jours.
    static let mois = 4

    func collecte(_ ctx: Contexte) async throws -> Int {
        let suivis = ctx.businesses.filter { !($0.config.playBucket ?? "").isEmpty && !($0.config.playPackage ?? "").isEmpty }
        guard !suivis.isEmpty else { throw SourceErreur.nonConfigure("aucun business n'a de bucket Play") }
        var lignes = 0
        for b in suivis {
            do {
                lignes += try await collecte(b, ctx)
            } catch SourceErreur.nonConfigure(let m) {
                throw SourceErreur.nonConfigure("\(b.nom) : \(m)")
            } catch {
                throw SourceErreur.commande("\(b.nom) : \(error.localizedDescription)")
            }
        }
        return lignes
    }

    private func collecte(_ b: Business, _ ctx: Contexte) async throws -> Int {
        let bucket = Self.bucket(b.config.playBucket ?? ""), paquet = b.config.playPackage ?? ""
        let jeton = try await Self.jeton(try Self.compte(Self.dossierCles.appending(path: "\(b.id)-play-publisher.json")), ctx.http)
        let prefixe = "stats/installs/installs_\(paquet)_"
        var liste = URLComponents(string: "\(Self.stockage)/\(bucket)/o")!
        liste.queryItems = [.init(name: "prefix", value: prefixe)]
        let objets = try await ctx.http.objet(HTTP.requete(liste.url!.absoluteString, jeton: jeton))
        let noms = (objets["items"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        var installs: [String: Double] = [:]
        for nom in Self.aLire(noms, prefixe: prefixe, jusqua: Jour.aujourdhui) {
            let url = "\(Self.stockage)/\(bucket)/o/\(nom.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? nom)?alt=media"
            installs.merge(try Self.installs(try await ctx.http.donnees(HTTP.requete(url, jeton: jeton)))) { $1 }
        }
        return try ctx.store.lot {
            for (jour, n) in installs { try Boutique.playStore.telechargements(b.id, jour: jour, n, ctx.store) }
            return installs.count
        }
    }
}

// MARK: rapports

extension PlayConsole {
    /// Les rapports `overview` des `mois` derniers mois, du plus ancien au plus récent.
    /// Le nom du bucket, que la config tienne le nom seul ou l'URI copiée dans la Play Console (`gs://pubsite_prod_rev_…/stats/…`).
    static func bucket(_ config: String) -> String {
        let s = config.trimmingCharacters(in: .whitespaces)
        return String((s.hasPrefix("gs://") ? s.dropFirst(5) : Substring(s)).prefix { $0 != "/" })
    }

    static func aLire(_ noms: [String], prefixe: String, jusqua aujourdhui: String) -> [String] {
        let debut = Jour.decale(aujourdhui, jours: -31 * (mois - 1)).prefix(7).replacingOccurrences(of: "-", with: "")
        return noms.filter { nom in
            guard nom.hasPrefix(prefixe), nom.hasSuffix("_overview.csv") else { return false }
            return nom.dropFirst(prefixe.count).prefix(6) >= debut
        }.sorted()
    }

    /// Un rapport `overview` (UTF-16, une ligne par jour) en `jour → installs` : la colonne « Daily User Installs »,
    /// les personnes qui installent l'app pour la première fois sur un de leurs appareils.
    static func installs(_ data: Data) throws -> [String: Double] {
        guard let texte = String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf8) else {
            throw SourceErreur.format("rapport Play illisible")
        }
        let lignes = texte.split(whereSeparator: \.isNewline).map { $0.split(separator: ",", omittingEmptySubsequences: false) }
        guard let entete = lignes.first?.map({ $0.trimmingCharacters(in: .whitespaces) }),
              let date = entete.firstIndex(of: "Date"), let colonne = entete.firstIndex(of: "Daily User Installs") else {
            throw SourceErreur.format("rapport Play sans colonnes Date et Daily User Installs")
        }
        var r: [String: Double] = [:]
        for l in lignes.dropFirst() where l.count == entete.count {
            guard let n = Double(l[colonne].trimmingCharacters(in: .whitespaces)) else {
                throw SourceErreur.format("rapport Play : « \(l[colonne]) » n'est pas un nombre")
            }
            r[String(l[date])] = n
        }
        return r
    }
}

// MARK: compte de service

extension PlayConsole {
    struct CompteService {
        var email: String
        var urlJeton: String
        var cle: SecKey
    }

    static func compte(_ fichier: URL) throws -> CompteService {
        guard let data = try? Data(contentsOf: fichier) else {
            throw SourceErreur.nonConfigure("clé du compte de service absente (~/.googleplay/\(fichier.lastPathComponent))")
        }
        guard let o = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = o["client_email"] as? String, let url = o["token_uri"] as? String, let pem = o["private_key"] as? String else {
            throw SourceErreur.format("clé du compte de service sans client_email, token_uri ou private_key")
        }
        return CompteService(email: email, urlJeton: url, cle: try cleRSA(pem))
    }

    /// Un jeton OAuth d'une heure, demandé avec un JWT RS256 signé par la clé du compte de service.
    static func jeton(_ c: CompteService, _ http: HTTP, maintenant: Date = .now) async throws -> String {
        var r = try HTTP.requete(c.urlJeton, methode: "POST", entetes: ["Content-Type": "application/x-www-form-urlencoded"])
        var corps = URLComponents()
        corps.queryItems = [.init(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:jwt-bearer"),
                            .init(name: "assertion", value: try assertion(c, maintenant: maintenant))]
        r.httpBody = Data((corps.percentEncodedQuery ?? "").utf8)
        guard let jeton = try await http.objet(r)["access_token"] as? String else {
            throw SourceErreur.format("jeton Google absent")
        }
        return jeton
    }

    static func assertion(_ c: CompteService, maintenant: Date) throws -> String {
        let iat = Int(maintenant.timeIntervalSince1970)
        let charge: [String: Any] = ["iss": c.email, "scope": portee, "aud": c.urlJeton, "iat": iat, "exp": iat + 3600]
        return try JWT.jeton(entete: ["alg": "RS256", "typ": "JWT"], charge: charge) { message in
            var erreur: Unmanaged<CFError>?
            guard let s = SecKeyCreateSignature(c.cle, .rsaSignatureMessagePKCS1v15SHA256, message as CFData, &erreur) else {
                throw SourceErreur.format("signature RS256 impossible")
            }
            return s as Data
        }
    }

    /// La clé privée RSA d'un PEM PKCS#8 (`BEGIN PRIVATE KEY`, le format des clés Google).
    static func cleRSA(_ pem: String) throws -> SecKey {
        let b64 = pem.split(whereSeparator: \.isNewline).filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: b64) else { throw SourceErreur.format("clé privée illisible") }
        let attributs: [CFString: Any] = [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPrivate]
        guard let cle = SecKeyCreateWithData(try pkcs1(der) as CFData, attributs as CFDictionary, nil) else {
            throw SourceErreur.format("clé privée RSA refusée")
        }
        return cle
    }

    /// La clé PKCS#1 dans une clé PKCS#8 : `SEQUENCE { INTEGER version, SEQUENCE algorithme, OCTET STRING clé }`.
    static func pkcs1(_ der: Data) throws -> Data {
        let o = [UInt8](der)
        var i = 0
        func element(_ tag: UInt8) throws -> Range<Int> {
            guard i + 1 < o.count, o[i] == tag else { throw SourceErreur.format("clé privée : DER inattendu") }
            var n = Int(o[i + 1])
            i += 2
            if n & 0x80 != 0 {
                let k = n & 0x7f
                guard k <= 4, i + k <= o.count else { throw SourceErreur.format("clé privée : DER inattendu") }
                n = o[i..<i + k].reduce(0) { $0 << 8 | Int($1) }
                i += k
            }
            guard i + n <= o.count else { throw SourceErreur.format("clé privée : DER tronqué") }
            return i..<i + n
        }
        _ = try element(0x30)
        i = try element(0x02).upperBound
        i = try element(0x30).upperBound
        return Data(o[try element(0x04)])
    }
}
