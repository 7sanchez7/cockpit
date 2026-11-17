import Foundation

/// Ce qui a fait percer une vidéo, mesuré contre les autres vidéos de son compte (docs/ecrans.md § Vidéos).
///
/// Pour chaque mesure rapportée aux vues, la corrélation de rang (Spearman) entre la mesure et les vues, sur les
/// vidéos du compte, dit si elle porte les vues de ce compte. Le levier d'une vidéo est la mesure qui maximise
/// (rang de la vidéo dans le compte − 0,5) × corrélation : la plus au-dessus de ses autres vidéos, parmi celles qui comptent.
enum Percee {
    /// Sous ce nombre de vidéos qui ont la mesure, ni rang ni corrélation ne veulent rien dire.
    static let minimum = 8
    /// La seconde de la courbe de rétention qui dit l'accroche.
    static let accrocheS = 3

    enum Mesure: String, CaseIterable {
        case accroche, visionnage, completion, likes, commentaires, partages, enregistrements, abonnes

        var nom: String {
            switch self {
            case .accroche: "Accroche"
            case .visionnage: "Visionnage"
            case .completion: "Complétion"
            case .likes: "Likes"
            case .commentaires: "Commentaires"
            case .partages: "Partages"
            case .enregistrements: "Enregistrements"
            case .abonnes: "Abonnés"
            }
        }

        /// La valeur d'une vidéo ; l'accroche vient de sa courbe de rétention.
        func valeur(_ v: LigneVideo, accroche: Double?) -> Double? {
            func taux(_ n: Int?) -> Double? { n.flatMap { v.vues > 0 ? Double($0) / Double(v.vues) : nil } }
            return switch self {
            case .accroche: accroche
            case .visionnage: v.watchMoyenS.flatMap { w in v.dureeS.flatMap { $0 > 0 ? w / $0 : nil } }
            case .completion: v.completion
            case .likes: taux(v.likes)
            case .commentaires: taux(v.commentaires)
            case .partages: taux(v.partages)
            case .enregistrements: taux(v.enregistrements)
            case .abonnes: v.conversion
            }
        }

        /// « 0,09 % », « 3,8 ».
        func court(_ x: Double) -> String {
            self == .abonnes ? Format.decimal(x, 1) : Format.pourcent(x, decimales: x < 0.01 ? 2 : x < 0.1 ? 1 : 0)
        }

        /// « 58 % encore là à 3 s ».
        func texte(_ x: Double) -> String {
            let unite: String = switch self {
            case .accroche: "encore là à \(Percee.accrocheS) s"
            case .visionnage: "de la vidéo regardée en moyenne"
            case .completion: "vont jusqu'au bout"
            case .likes: "des vues likent"
            case .commentaires: "des vues commentent"
            case .partages: "des vues partagent"
            case .enregistrements: "des vues enregistrent"
            case .abonnes: "abonnés pour 1 000 vues"
            }
            return court(x) + " " + unite
        }
    }

    struct Levier: Equatable {
        var mesure: Mesure
        var valeur: Double
        var mediane: Double
        /// Part des autres vidéos du compte sous cette valeur, de 0 à 1.
        var rang: Double
        /// Corrélation de rang entre la mesure et les vues du compte.
        var poids: Double
        /// Plus de vues que la médiane du compte.
        var percee: Bool
    }

    /// Le levier de `v` parmi les vidéos de son compte ; nil si le compte a trop peu de vidéos ou si `v` ne
    /// dépasse sa médiane sur aucune mesure liée aux vues.
    static func levier(_ v: LigneVideo, parmi videos: [LigneVideo], accroches: [String: Double]) -> Levier? {
        let compte = compte(v, parmi: videos)
        guard compte.count >= minimum, compte.contains(where: { $0.id == v.id }) else { return nil }
        let vuesMediane = mediane(compte.map { Double($0.vues) })
        return Mesure.allCases.compactMap { m -> Levier? in
            let paires = compte.compactMap { w in m.valeur(w, accroche: accroches[w.id]).map { (Double(w.vues), $0) } }
            guard paires.count >= minimum, let x = m.valeur(v, accroche: accroches[v.id]) else { return nil }
            let sous = paires.filter { $0.1 < x }.count
            let egaux = paires.filter { $0.1 == x }.count - 1
            let rang = (Double(sous) + Double(egaux) / 2) / Double(paires.count - 1)
            let poids = spearman(paires)
            guard poids > 0, rang > 0.5 else { return nil }
            return Levier(mesure: m, valeur: x, mediane: mediane(paires.map(\.1)), rang: rang, poids: poids,
                          percee: Double(v.vues) > vuesMediane)
        }
        .max { ($0.rang - 0.5) * $0.poids < ($1.rang - 0.5) * $1.poids }
    }

    /// Les vidéos vues du compte de `v`, la base de comparaison.
    static func compte(_ v: LigneVideo, parmi videos: [LigneVideo]) -> [LigneVideo] {
        videos.filter { $0.plateforme == v.plateforme && $0.compte == v.compte && $0.vues > 0 }
    }

    /// Corrélation de rang de Spearman, de −1 à 1 ; les ex aequo prennent leur rang moyen.
    static func spearman(_ paires: [(Double, Double)]) -> Double {
        let a = rangs(paires.map(\.0)), b = rangs(paires.map(\.1))
        let n = Double(paires.count), ma = a.reduce(0, +) / n, mb = b.reduce(0, +) / n
        let cov = zip(a, b).map { ($0 - ma) * ($1 - mb) }.reduce(0, +)
        let va = a.map { ($0 - ma) * ($0 - ma) }.reduce(0, +), vb = b.map { ($0 - mb) * ($0 - mb) }.reduce(0, +)
        return va > 0 && vb > 0 ? cov / (va * vb).squareRoot() : 0
    }

    private static func rangs(_ x: [Double]) -> [Double] {
        let ordre = x.indices.sorted { x[$0] < x[$1] }
        var r = [Double](repeating: 0, count: x.count)
        var i = 0
        while i < ordre.count {
            var j = i
            while j + 1 < ordre.count, x[ordre[j + 1]] == x[ordre[i]] { j += 1 }
            for k in i...j { r[ordre[k]] = Double(i + j) / 2 }
            i = j + 1
        }
        return r
    }

    static func mediane(_ x: [Double]) -> Double {
        let s = x.sorted(), n = s.count
        guard n > 0 else { return 0 }
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }
}
