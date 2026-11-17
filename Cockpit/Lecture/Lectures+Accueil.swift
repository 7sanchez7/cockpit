import Foundation

/// Les lectures de l'Accueil : le plan tiré de Notes, les comptes du jour, le score de la semaine.
extension Lectures {
    /// Le plan de la note « Cockpit », dans l'ordre de la note ; il ne dépend pas du business affiché.
    func plan() -> [LignePlan] {
        q("select section, texte, coche, fait from plan order by ordre").map { l in
            LignePlan(section: l.texte("section") ?? "", texte: l.texte("texte") ?? "",
                      coche: l.booleen("coche"), fait: l.booleen("fait"))
        }
    }

    /// Chaque compte suivi avec ses vidéos publiées aujourd'hui, sa dernière publication et les vues prises sur 24 h.
    func reseau() -> [LigneReseau] {
        let minuit = Jour.date(Jour.cle(maintenant)) ?? maintenant
        var publiees: [String: (aujourdhui: Int, derniere: Date?)] = [:]
        for l in q("""
            select plateforme, compte, sum(publiee_le >= ?) as aujourdhui, max(publiee_le) as derniere
            from video where business in \(dans) group by plateforme, compte
            """, [minuit] + ids) {
            publiees["\(l.texte("plateforme") ?? ""):\(l.texte("compte") ?? "")"] = (l.entier("aujourdhui") ?? 0, l.date("derniere"))
        }
        var vues: [String: Int] = [:]
        for v in videos() {
            if let g = v.gain24h { vues["\(v.plateforme.rawValue):\(v.compte)", default: 0] += g }
        }
        return comptes().map { c in
            LigneReseau(compte: c, aujourdhui: publiees[c.id]?.aujourdhui ?? 0, derniere: publiees[c.id]?.derniere,
                        vues24h: vues[c.id])
        }
    }

    /// Les sept jours complets jusqu'à `fin` contre les sept d'avant, axe par axe.
    func score(jusqua fin: String) -> Score {
        func semaines(_ v: [Double?]) -> (courant: Double?, avant: Double?) {
            (Cumul.somme.de(Array(v.suffix(7))), Cumul.somme.de(Array(v.prefix(7))))
        }
        let videos = semaines(publications(14, jusqua: fin))
        let vues = semaines(jours(Metrique.vuesTikTok, 14, jusqua: fin))
        let installs = semaines(jours(Metrique.installs, 14, jusqua: fin))
        let essais = semaines(jours(Metrique.essais, 14, jusqua: fin))
        let revenu = semaines(jours(Metrique.revenu, 14, jusqua: fin))
        func taux(_ e: Double?, _ i: Double?) -> Double? { i.flatMap { $0 > 0 ? (e ?? 0) / $0 : nil } }
        return Score(axes: [
            AxeScore(nom: "Vidéos", note: Score.note(videos.courant, videos.avant)),
            AxeScore(nom: "Vues", note: Score.note(vues.courant, vues.avant)),
            AxeScore(nom: "Installs", note: Score.note(installs.courant, installs.avant)),
            AxeScore(nom: "Conversion", note: Score.note(taux(essais.courant, installs.courant), taux(essais.avant, installs.avant))),
            AxeScore(nom: "Revenu", note: Score.note(revenu.courant, revenu.avant)),
        ])
    }
}

extension Jour {
    /// Les sept jours de la semaine de `jour`, du lundi au dimanche.
    static func semaine(de jour: String) -> [String] {
        guard let d = date(jour) else { return [] }
        // weekday : 1 = dimanche, 2 = lundi
        let lundi = decale(jour, jours: -((calendrier.component(.weekday, from: d) + 5) % 7))
        return (0..<7).map { decale(lundi, jours: $0) }
    }
}

struct LigneReseau: Identifiable, Hashable {
    /// Le rythme visé par compte actif : trois vidéos par jour.
    static let videosParJour = 3

    var compte: LigneCompte
    /// Vidéos publiées depuis minuit, heure de Paris.
    var aujourdhui: Int
    var derniere: Date?
    /// Vues prises sur 24 h par ses vidéos ; nil sans relevé assez ancien.
    var vues24h: Int?

    var id: String { compte.id }
}

/// Un axe du score : la semaine écoulée rapportée à celle d'avant, sur 100.
struct AxeScore: Identifiable, Hashable {
    let nom: String
    /// Plafonnée à 100 : faire au moins aussi bien que la semaine d'avant ; nil sans référence.
    let note: Int?

    var id: String { nom }
}

/// Le score de l'Accueil, la moyenne de ses axes notés.
struct Score: Hashable {
    let axes: [AxeScore]

    var global: Int? {
        let notes = axes.compactMap(\.note)
        return notes.isEmpty ? nil : Int((Double(notes.reduce(0, +)) / Double(notes.count)).rounded())
    }

    /// L'axe le plus bas, s'il est sous 100.
    var faible: AxeScore? {
        axes.filter { ($0.note ?? 100) < 100 }.min { ($0.note ?? 0) < ($1.note ?? 0) }
    }

    static func note(_ courant: Double?, _ avant: Double?) -> Int? {
        guard let courant, let avant, avant > 0 else { return nil }
        return min(100, Int((100 * courant / avant).rounded()))
    }
}
