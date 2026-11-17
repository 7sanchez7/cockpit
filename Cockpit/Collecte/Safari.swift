import Foundation

/// Les sessions de Safari (TikTok, Instagram, Facebook), lues dans ses fichiers `Cookies.binarycookies` : Cockpit doit
/// avoir l'accès complet au disque. Aucune valeur de cookie n'est affichée, écrite ou mise dans une erreur.
enum Safari {
    static let donnees = URL.homeDirectory.appending(path: "Library/Containers/com.apple.Safari/Data/Library")

    struct Cookie: Equatable {
        var domaine: String
        var nom: String
        var valeur: String
        var expire: Date
        var cree = Date.distantPast
    }

    /// Les cookies d'un domaine (`tiktok.com`) dans le profil Safari où l'on s'est connecté le plus récemment.
    /// Lève `.nonConfigure` sans accès complet au disque, ou sans session sur ce site.
    static func cookies(_ domaine: String, requis: String) throws -> [String: String] {
        var profils: [[Cookie]] = []
        do {
            for fichier in try fichiers() {
                do {
                    profils.append(try lire(Data(contentsOf: fichier)))
                } catch CocoaError.fileReadNoSuchFile {
                    continue
                }
            }
        } catch CocoaError.fileReadNoPermission {
            throw SourceErreur.nonConfigure(
                "Safari illisible : donner l'accès complet au disque à Cockpit (Réglages Système, Confidentialité et sécurité)")
        }
        guard let s = plusRecente(profils, domaine: domaine, requis: requis, maintenant: .now) else {
            throw SourceErreur.nonConfigure("pas de session dans Safari : se connecter sur \(domaine) dans Safari")
        }
        return s
    }

    /// D'où vient la session : pour chaque fichier lu, son profil, le nombre de cookies du domaine et les dates du
    /// cookie `requis`. Des dates et des comptes, jamais une valeur.
    static func provenance(_ domaine: String, requis: String) -> String {
        let jour = Date.ISO8601FormatStyle().year().month().day()
        let lignes = ((try? fichiers()) ?? []).map { f -> String in
            let profil = f.path.contains("WebsiteDataStore") ? String(f.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent.prefix(8)) : "défaut"
            guard let cookies = try? lire(Data(contentsOf: f)) else { return "\(profil) illisible" }
            let du = cookies.filter { dans($0, domaine) }
            let r = du.filter { $0.nom == requis }.map { "\(requis) créé \($0.cree.formatted(jour)) expire \($0.expire.formatted(jour))" }
            return "\(profil) : \(du.count) cookies" + (r.isEmpty ? "" : ", " + r.joined(separator: ", "))
        }
        return lignes.joined(separator: " ; ")
    }

    /// La session du profil dont le cookie `requis` a été créé en dernier : un vieux profil garde parfois une session
    /// que le site refuse.
    static func plusRecente(_ profils: [[Cookie]], domaine: String, requis: String, maintenant: Date) -> [String: String]? {
        let candidates = profils.compactMap { cookies -> (session: [String: String], cree: Date)? in
            let s = session(cookies, domaine: domaine, maintenant: maintenant)
            guard s[requis] != nil else { return nil }
            let cree = cookies.filter { $0.nom == requis && dans($0, domaine) }.map(\.cree).max() ?? .distantPast
            return (s, cree)
        }
        return candidates.max { $0.cree < $1.cree }?.session
    }

    /// L'en-tête `Cookie` d'un domaine.
    static func entete(_ domaine: String, requis: String) throws -> String {
        try cookies(domaine, requis: requis).map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    /// Les cookies encore valides de `domaine` et de ses sous-domaines, par nom ; pour un nom en double, le plus récent.
    static func session(_ cookies: [Cookie], domaine: String, maintenant: Date) -> [String: String] {
        let retenus = cookies.filter { dans($0, domaine) && $0.expire > maintenant && !$0.valeur.isEmpty }
        return Dictionary(grouping: retenus, by: \.nom).compactMapValues { $0.max { $0.cree < $1.cree }?.valeur }
    }

    private static func dans(_ cookie: Cookie, _ domaine: String) -> Bool {
        cookie.domaine == domaine || cookie.domaine.hasSuffix(".\(domaine)")
    }

    /// Le format `cook` : nombre et tailles des pages en big-endian ; dans chaque page, les décalages des cookies, puis
    /// chaque cookie en little-endian (taille, décalages de ses chaînes terminées par un zéro, expiration puis création
    /// en secondes depuis 2001).
    static func lire(_ donnees: Data) throws -> [Cookie] {
        let o = [UInt8](donnees)
        let illisible = CocoaError(.fileReadCorruptFile)
        guard o.count >= 8, o.prefix(4).elementsEqual("cook".utf8) else { throw illisible }
        func entier(_ i: Int, grandBoutiste: Bool = false) throws -> Int {
            guard i >= 0, i + 4 <= o.count else { throw illisible }
            let octets = grandBoutiste ? Array(o[i..<i + 4]) : o[i..<i + 4].reversed()
            return octets.reduce(0) { $0 << 8 | Int($1) }
        }
        func date(_ i: Int) throws -> Date {
            guard i >= 0, i + 8 <= o.count else { throw illisible }
            let bits = o[i..<i + 8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            return Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits))
        }
        func chaine(_ i: Int, fin: Int) throws -> String {
            guard i >= 0, i < fin, let zero = o[i..<fin].firstIndex(of: 0) else { throw illisible }
            return String(decoding: o[i..<zero], as: UTF8.self)
        }
        let pages = try entier(4, grandBoutiste: true)
        var page = 8 + 4 * pages
        var cookies: [Cookie] = []
        for p in 0..<pages {
            for c in 0..<(try entier(page + 4)) {
                let debut = try page + entier(page + 8 + 4 * c)
                let fin = try debut + entier(debut)
                guard fin <= o.count else { throw illisible }
                cookies.append(try Cookie(domaine: chaine(debut + entier(debut + 16), fin: fin),
                                          nom: chaine(debut + entier(debut + 20), fin: fin),
                                          valeur: chaine(debut + entier(debut + 28), fin: fin),
                                          expire: date(debut + 40), cree: date(debut + 48)))
            }
            page += try entier(8 + 4 * p, grandBoutiste: true)
        }
        return cookies
    }

    /// Le profil par défaut, puis les profils créés dans Safari.
    private static func fichiers() throws -> [URL] {
        let profils = donnees.appending(path: "WebKit/WebsiteDataStore")
        var autres: [URL] = []
        do {
            autres = try FileManager.default.contentsOfDirectory(at: profils, includingPropertiesForKeys: nil)
                .map { $0.appending(path: "Cookies/Cookies.binarycookies") }
                .sorted { $0.path < $1.path }
        } catch CocoaError.fileReadNoSuchFile {
            // aucun profil
        }
        return [donnees.appending(path: "Cookies/Cookies.binarycookies")] + autres
    }
}
