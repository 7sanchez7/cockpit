import Foundation

/// Le MRR brut de RevenueCat face à l'objectif mensuel, en euros au taux `Metrique.eurParUSD`.
struct Objectif {
    let cibleEUR: Double
    let mrrEUR: Double
    /// Gain de MRR par jour sur les 30 derniers jours ; nil sans relevé 30 jours avant.
    let rythmeParJourEUR: Double?

    var part: Double { cibleEUR > 0 ? min(max(mrrEUR / cibleEUR, 0), 1) : 0 }
    var resteEUR: Double { max(cibleEUR - mrrEUR, 0) }

    /// Quand le MRR atteindrait la cible à ce rythme ; nil s'il ne monte pas ou s'il faudrait plus de cinq ans.
    func arrivee(depuis maintenant: Date) -> Date? {
        guard resteEUR > 0, let r = rythmeParJourEUR, r > 0 else { return nil }
        let jours = resteEUR / r
        return jours <= 5 * 365 ? maintenant.addingTimeInterval(jours * 86_400) : nil
    }
}

/// Le retour JN de cohortes complètes, pondéré par leurs installs.
struct TauxRetour: Equatable {
    let taux: Double
    let cohortes: Int
    /// Le même taux sur autant de cohortes juste avant ; nil s'il n'y en a pas assez.
    let avant: Double?
}

extension Cohorte {
    /// JN rapporté aux installs ; nil tant que la cohorte n'a pas eu N + 1 jours.
    func taux(_ jn: KeyPath<Cohorte, Int?>) -> Double? {
        guard installs > 0, let n = self[keyPath: jn] else { return nil }
        return Double(n) / Double(installs)
    }
}

extension [Cohorte] {
    /// Taux pondéré des `taille` cohortes complètes les plus récentes (liste la plus récente d'abord),
    /// comparé aux `taille` d'avant si elles sont toutes là.
    func retour(_ jn: KeyPath<Cohorte, Int?>, taille: Int = 7) -> TauxRetour? {
        let completes = filter { $0.installs > 0 && $0[keyPath: jn] != nil }
        func pondere(_ c: ArraySlice<Cohorte>) -> Double {
            Double(c.reduce(0) { $0 + ($1[keyPath: jn] ?? 0) }) / Double(c.reduce(0) { $0 + $1.installs })
        }
        let recentes = completes.prefix(taille)
        guard !recentes.isEmpty else { return nil }
        let precedentes = completes.dropFirst(taille).prefix(taille)
        return TauxRetour(taux: pondere(recentes), cohortes: recentes.count,
                          avant: recentes.count == taille && precedentes.count == taille ? pondere(precedentes) : nil)
    }

    /// Le taux JN de chaque cohorte complète, de la plus ancienne à la plus récente.
    func serie(_ jn: KeyPath<Cohorte, Int?>) -> [Double] {
        reversed().compactMap { $0.taux(jn) }
    }
}

extension Lectures {
    // MARK: argent

    func objectif(jour: String) -> Objectif? {
        guard let mrr = valeur(Metrique.mrrBrut, jour: jour) else { return nil }
        let avant = valeur(Metrique.mrrBrut, jour: Jour.decale(jour, jours: -30))
        return Objectif(cibleEUR: businesses.reduce(0) { $0 + $1.config.objectifMensuelEUR },
                        mrrEUR: Metrique.enEuros(mrr),
                        rythmeParJourEUR: avant.map { Metrique.enEuros(mrr - $0) / 30 })
    }

    /// Le revenu brut en euros cumulé jour par jour sur les `n` jours jusqu'à `fin`, les jours sans relevé sautés.
    func revenuCumule(_ n: Int, jusqua fin: String) -> [(jour: String, euros: Double)] {
        var total = 0.0
        return zip(Jour.derniers(n, jusqua: fin), jours(Metrique.revenu, n, jusqua: fin)).compactMap { cle, v in
            guard let v else { return nil }
            total += Metrique.enEuros(v)
            return (cle, total)
        }
    }

    /// Somme des `n` jours jusqu'à `jusqua` ; nil si aucun n'a de relevé.
    func somme(_ m: String, _ n: Int, jusqua: String) -> Double? {
        let v = jours(m, n, jusqua: jusqua).compactMap { $0 }
        return v.isEmpty ? nil : v.reduce(0, +)
    }

    // MARK: tunnel

    /// L'étape qui perd le plus de monde par rapport à la précédente ; nil sans perte.
    static func plusGrossePerte(_ etapes: [(nom: String, n: Int)]) -> Int? {
        let pertes = etapes.indices.dropFirst().map { (i: $0, perte: etapes[$0 - 1].n - etapes[$0].n) }
        guard let pire = pertes.max(by: { $0.perte < $1.perte }), pire.perte > 0 else { return nil }
        return pire.i
    }
}
