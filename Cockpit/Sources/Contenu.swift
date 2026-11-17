import Foundation

/// Voir docs/sources/contenu.md.
struct Contenu: Source {
    let id = "contenu"
    let nom = "Contenu"
    let cadence: TimeInterval = 15 * 60

    /// Le verdict d'une vidéo est attendu 7 jours après sa sortie ; 3 jours de retard de plus, la tâche passe en alerte.
    static let delaiVerdict = 7
    static let retardAlerte = 3

    /// Ce qu'une fiche `contenu/bank` dit de sa vidéo.
    struct Fiche: Equatable {
        var chemin = ""
        /// Le dossier du format (`comment-dire`).
        var dossier = ""
        /// Le frontmatter, sans les commentaires ni les champs vides.
        var champs: [String: String] = [:]
        var titre: String?
        var verdict = false
        /// La date du nom de fichier (`2026-10-13-…`), sinon sa création.
        var date: Date?
    }

    func collecte(_ ctx: Contexte) async throws -> Int {
        let suivis = ctx.businesses.filter { !($0.config.contenuDir ?? "").isEmpty }
        guard !suivis.isEmpty else { throw SourceErreur.nonConfigure("aucun dossier de fiches dans les réglages") }
        var lignes = 0
        for b in suivis {
            do {
                lignes += try Self.ecrire(Self.lire(NSString(string: b.config.contenuDir ?? "").expandingTildeInPath),
                                          business: b.id, ctx.store)
            } catch SourceErreur.nonConfigure(let m) {
                throw SourceErreur.nonConfigure("\(b.nom) : \(m)")
            } catch {
                throw SourceErreur.commande("\(b.nom) : \(error.localizedDescription)")
            }
        }
        return lignes
    }

    /// Les fiches `<famille>/<format>/*.md` et `<famille>/<format>/fait/*.md` du dossier.
    static func lire(_ racine: String) throws -> [Fiche] {
        guard FileManager.default.fileExists(atPath: racine) else {
            throw SourceErreur.nonConfigure("dossier de fiches introuvable : \(racine)")
        }
        return try FileManager.default.subpathsOfDirectory(atPath: racine).sorted().compactMap { relatif in
            let parties = relatif.split(separator: "/")
            guard relatif.hasSuffix(".md"), parties.count == 3 || (parties.count == 4 && parties[2] == "fait") else { return nil }
            let chemin = racine + "/" + relatif
            var f = fiche(try String(contentsOfFile: chemin, encoding: .utf8))
            f.chemin = chemin
            f.dossier = String(parties[1])
            let creation = try FileManager.default.attributesOfItem(atPath: chemin)[.creationDate] as? Date
            f.date = Jour.date(String(parties[parties.count - 1].prefix(10))) ?? creation
            return f
        }
    }

    /// Le frontmatter, le titre et la présence d'un `## Verdict`. Le titre est la première ligne `# ` sans la date
    /// de tête ; si c'est un slug (`4-astuces-draguer`), la ligne `Titre : ` du script, sinon le slug sans tirets.
    static func fiche(_ texte: String) -> Fiche {
        var f = Fiche()
        var lignes = texte.components(separatedBy: .newlines)[...]
        if lignes.first == "---" {
            lignes = lignes.dropFirst()
            while let l = lignes.first, l != "---" {
                lignes = lignes.dropFirst()
                let sansCommentaire = l.replacing(/\s+#.*$/, with: "")
                guard let deuxPoints = sansCommentaire.firstIndex(of: ":") else { continue }
                let cle = sansCommentaire[..<deuxPoints].trimmingCharacters(in: .whitespaces)
                let valeur = sansCommentaire[sansCommentaire.index(after: deuxPoints)...].trimmingCharacters(in: .whitespaces)
                if !valeur.isEmpty { f.champs[cle] = valeur }
            }
        }
        var entete: String?
        var ligneTitre: String?
        for l in lignes {
            if entete == nil, l.hasPrefix("# ") {
                entete = String(l.dropFirst(2)).replacing(/^\d{4}-\d{2}-\d{2}\s+[—–-]\s+/, with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            if ligneTitre == nil, let m = l.firstMatch(of: /^Titre ?: *(.+)$/) {
                ligneTitre = String(m.1).trimmingCharacters(in: .whitespaces)
            }
            if l.hasPrefix("## Verdict") { f.verdict = true }
        }
        if let entete, !entete.contains(" ") {
            f.titre = ligneTitre ?? entete.replacing("-", with: " ")
        } else {
            f.titre = entete
        }
        return f
    }

    /// L'id et le compte d'un lien `https://www.tiktok.com/@compte/video/123`.
    static func video(url: String) -> (id: String, compte: String)? {
        guard let m = url.firstMatch(of: /tiktok\.com\/@([A-Za-z0-9._]+)\/video\/(\d+)/) else { return nil }
        return (String(m.2), String(m.1))
    }

    /// Écrit les vidéos des fiches et synchronise les tâches de verdict. Rend le nombre de lignes écrites.
    static func ecrire(_ fiches: [Fiche], business: String, _ store: Store, aujourdhui: String = Jour.aujourdhui) throws -> Int {
        var taches: [Tache] = []
        var videos = 0
        try store.lot {
            for f in fiches {
                guard let url = f.champs["tiktok"], let v = video(url: url) else { continue }
                let titre = f.titre ?? v.id
                try store.ficheVideo(FicheVideo(id: v.id, business: business, compte: v.compte, url: url, titre: titre,
                                                format: f.champs["format"] ?? f.dossier, fiche: f.chemin, verdict: f.verdict))
                videos += 1
                let publiee = try store.db.query("select publiee_le from video where id = ?", [v.id]).first?.date("publiee_le")
                guard !f.verdict, let sortie = publiee ?? f.date else { continue }
                let echeance = Jour.decale(Jour.cle(sortie), jours: delaiVerdict)
                guard echeance <= aujourdhui else { continue }
                taches.append(Tache(cle: "verdict:\(v.id)", texte: "Verdict : \(titre)", etiquette: dateCourte(echeance),
                                    ton: Jour.decale(echeance, jours: retardAlerte) < aujourdhui ? .alerte : .neutre,
                                    echeance: echeance, lien: URL(fileURLWithPath: f.chemin).absoluteString))
            }
        }
        try store.synchroniserTaches(source: "contenu", business: business, taches)
        return videos + taches.count
    }

    private static let formatCourt: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = Jour.fuseau
        f.dateFormat = "d MMM"
        return f
    }()

    /// `2026-11-17` → « 17 nov. »
    static func dateCourte(_ jour: String) -> String {
        Jour.date(jour).map(formatCourt.string) ?? jour
    }
}
