import Foundation

/// La période de l'Accueil et de Data : la journée en cours, ou des jours complets jusqu'à hier.
enum Periode: Int, CaseIterable {
    case jour = 1, semaine = 7, mois = 30, trimestre = 90

    var texte: String { self == .jour ? "Aujourd'hui" : "\(rawValue) j" }
}

/// Les jours de la période et la façon de les comparer.
struct Fenetre {
    let periode: Periode
    let maintenant: Date

    var jour: Bool { periode == .jour }
    var n: Int { periode.rawValue }
    /// Le dernier jour de la fenêtre : aujourd'hui, ou hier pour des jours complets.
    var fin: String { Jour.decale(Jour.cle(maintenant), jours: jour ? 0 : -1) }
    var debut: String { Jour.decale(fin, jours: 1 - n) }
    /// Minuit du premier jour et minuit après le dernier, à l'heure de Paris.
    var du: Date { Jour.date(debut) ?? maintenant }
    var au: Date { Jour.date(Jour.decale(fin, jours: 1)) ?? maintenant }

    /// Autant de jours juste avant ; nil pour aujourd'hui, une journée entamée ne se compare pas à une journée entière.
    var avant: (debut: String, fin: String)? { jour ? nil : (Jour.decale(debut, jours: -n), Jour.decale(debut, jours: -1)) }

    var sousTitre: String {
        if jour { return "\(Format.dateLongue(maintenant)), comparé à \(Format.jourSemaine(maintenant)) dernier à la même heure" }
        return "Du \(Format.jourCourt(cle: debut)) au \(Format.jourCourt(cle: fin)), comparé aux \(n) jours d'avant"
    }

    /// Aujourd'hui : la valeur du jour contre `j7` (même heure une semaine avant), ou contre J-7 entier pour un `dernier`.
    /// Sur N jours : la fenêtre cumulée contre celle d'avant, comparée seulement si celle-ci est relevée jour par jour.
    func mesure(_ l: Lectures, _ m: String, j7: String? = nil, cumul: Cumul = .somme) -> Chiffres {
        if jour {
            let avant = cumul == .dernier ? l.valeur(m, jour: Jour.decale(fin, jours: -7)) : j7.flatMap { l.valeur($0, jour: fin) }
            return Chiffres(valeur: l.valeur(m, jour: fin), avant: avant, serie: l.jours(m, 14, jusqua: fin))
        }
        let deux = l.jours(m, 2 * n, jusqua: fin)
        let avant = Array(deux.prefix(n)), courant = Array(deux.suffix(n))
        let releves = courant.compactMap { $0 }.count
        return Chiffres(valeur: cumul.de(courant), avant: avant.contains(nil) ? nil : cumul.de(avant), serie: courant,
                        jours: cumul != .dernier && releves > 0 && releves < n ? releves : nil)
    }
}

/// Comment une fenêtre de jours devient un chiffre : un total, une moyenne par jour, ou le dernier relevé (le MRR).
enum Cumul {
    case somme, moyenne, dernier

    func de(_ jours: [Double?]) -> Double? {
        let v = jours.compactMap { $0 }
        guard let d = v.last else { return nil }
        switch self {
        case .somme: return v.reduce(0, +)
        case .moyenne: return v.reduce(0, +) / Double(v.count)
        case .dernier: return d
        }
    }
}

/// Une carte : la valeur de la période, sa référence, la courbe.
struct Chiffres {
    let valeur: Double?
    let avant: Double?
    let serie: [Double?]
    /// Les jours relevés quand une somme ou une moyenne ne couvre qu'une partie de la période, sinon nul.
    var jours: Int? = nil

    /// « sur 8 j » quand la période n'est couverte qu'en partie.
    var couverture: String? { jours.map { "sur \($0) j" } }

    /// Les mêmes chiffres passés par `t`, par exemple des dollars en euros.
    func map(_ t: (Double) -> Double) -> Chiffres {
        Chiffres(valeur: valeur.map(t), avant: avant.map(t), serie: serie.map { $0.map(t) }, jours: jours)
    }
}
