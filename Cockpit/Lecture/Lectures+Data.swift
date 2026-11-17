import Foundation

/// Un nœud de l'arbre des installs : ceux qui passent tous les filtres sur la période, ce qu'ils ont fait, ce que
/// RevenueCat dit de leur paiement. Rond fini et retours ne comptent que les installs depuis `PostHog.rondsDepuis`, et
/// J1, J7 les seuls jours d'install qui ont eu tout leur temps.
struct Segment: Hashable {
    let valeur: String
    let installs: Int
    let paywall: Int
    let essais: Int
    let directs: Int
    /// Installs mesurables pour le rond fini, et ceux qui en ont fini un.
    let baseRond: Int
    let ronds: Int
    /// Convertis que RevenueCat a vus payer : essais passés à payant et achats sans essai.
    let payants: Int
    let essaisPayes: Int
    /// Essais qui courent encore chez RevenueCat.
    let enCours: Int
    /// Convertis que RevenueCat n'a pas encore lus, ou qu'il ne connaît pas en production.
    let aVerifier: Int
    let baseJ1: Int
    let j1: Int
    let baseJ7: Int
    let j7: Int

    /// Sous ce nombre d'installs, un taux bouge trop d'un install à l'autre pour désigner le meilleur segment.
    static let minimum = 30

    var paywallVu: Double? { Segment.taux(paywall, installs) }
    var essai: Double? { Segment.taux(essais, installs) }
    var payant: Double? { Segment.taux(payants, installs) }
    /// Essais que RevenueCat ne voit plus courir : payés, annulés, ou pas encore lus.
    var essaisFinis: Int { essais - enCours }
    var essaiVersPayant: Double? { Segment.taux(essaisPayes, essaisFinis) }
    var rond: Double? { Segment.taux(ronds, baseRond) }
    var retourJ1: Double? { Segment.taux(j1, baseJ1) }
    var retourJ7: Double? { Segment.taux(j7, baseJ7) }

    static func taux(_ n: Int, _ sur: Int) -> Double? { sur > 0 ? Double(n) / Double(sur) : nil }
}

/// Un pas dans l'arbre : une réponse gardée ou écartée, ou une étape du tunnel passée.
enum Filtre: Hashable {
    /// Une valeur de la dimension ; la valeur vide garde ceux qui n'ont pas répondu, `Dimension.pasMesure` ceux d'avant
    /// la mesure.
    case valeur(Dimension, String)
    /// Tous sauf cette valeur.
    case sauf(Dimension, String)
    /// A passé l'écran de ce rang (1 à 17, `PostHog.ecrans`).
    case ecran(Int)
    /// A vu le paywall, depuis le tunnel ou une porte de l'app.
    case paywall
    case essai
    case payant
}

/// Un build de l'app, sa version et ses installs, du premier au dernier jour d'install.
struct Build: Hashable {
    let numero: String
    let version: String
    let debut: String
    let fin: String
    let installs: Int

    var filtre: Filtre { .valeur(.build, numero) }
}

/// Une porte du paywall sur la période.
struct LignePorte: Hashable {
    let porte: String
    let vues: Int
    let essais: Int
    let directs: Int

    var conversion: Double? { Segment.taux(essais + directs, vues) }
}

extension Lectures {
    // MARK: arbre des installs

    /// Le dernier jour d'install dont le retour JN est complet au dernier calcul des installs : un install de 23 h 59
    /// a jusqu'à minuit de J+N+2 pour finir un rond entre N et N+1 jours après.
    func completJusqua(_ n: Int) -> String {
        let cles = businesses.map { "posthog.horaire.\($0.id)" as Any? }
        let calcul = q("select min(valeur) as v from reglage where cle in \(dans)", cles).first?.date("v") ?? maintenant
        return Jour.decale(Jour.cle(calcul), jours: -n - 2)
    }

    /// Les installs de `debut` à `fin` qui passent tous les filtres.
    func noeud(_ filtres: [Filtre], du debut: String, au fin: String) -> Segment {
        agrege(filtres, cle: "''", ordre: "cle", du: debut, au: fin).first ?? Segment.vide
    }

    /// Le nœud découpé par valeur de la dimension, le plus gros d'abord (par rang pour l'écran atteint, le plus récent
    /// d'abord pour le build) ;
    /// un install à plusieurs réponses compte dans chacune, un install d'avant la mesure va sous `Dimension.pasMesure`.
    func enfants(_ filtres: [Filtre], par d: Dimension, du debut: String, au fin: String) -> [Segment] {
        let sans = d.mesureeDepuis.map { "case when i.jour < '\($0)' then '\(Dimension.pasMesure)' else '' end" } ?? "''"
        return agrege(filtres, cle: "coalesce(v.value, \(sans))", jointure: "left join json_each(i.valeurs, '$.\(d.rawValue)') v",
               ordre: d == .loin ? "cast(cle as integer)" : d == .build ? "cast(cle as integer) desc" : "installs desc, cle",
               du: debut, au: fin)
    }

    /// Le tunnel du nœud : combien ont passé chaque écran, rang 1 à 17.
    func tunnel(_ filtres: [Filtre], du debut: String, au fin: String) -> [Int] {
        let rangs = PostHog.ecrans.indices.map { $0 + 1 }
        let (clauses, valeurs) = Self.clauses(filtres)
        guard let l = q("""
            select \(rangs.map { "sum(i.loin >= \($0)) as e\($0)" }.joined(separator: ", "))
            from install i left join paiement p on p.business = i.business and p.client = i.client
            where i.business in \(dans) and i.jour between ? and ?\(clauses)
            """, ids + [debut, fin] + valeurs).first else { return [] }
        return rangs.map { l.entier("e\($0)") ?? 0 }
    }

    /// La cohorte entière jour d'install par jour, du plus ancien au plus récent ; `valeur` y est le jour.
    func parJour(_ filtres: [Filtre] = [], du debut: String, au fin: String) -> [Segment] {
        agrege(filtres, cle: "i.jour", ordre: "cle", du: debut, au: fin)
    }

    /// Les builds des installs, le plus récent d'abord.
    func builds() -> [Build] {
        q("""
            select b.value as numero, max(json_extract(i.valeurs, '$.version[0]')) as version, min(i.jour) as debut,
                max(i.jour) as fin, count(*) as installs
            from install i join json_each(i.valeurs, '$.build') b
            where i.business in \(dans)
            group by numero order by cast(numero as integer) desc
            """, ids).map { l in
            Build(numero: l.texte("numero") ?? "", version: l.texte("version") ?? "", debut: l.texte("debut") ?? "",
                  fin: l.texte("fin") ?? "", installs: l.entier("installs") ?? 0)
        }
    }

    /// Le premier jour d'install détaillé ; nil avant le premier calcul.
    func premierInstall() -> String? {
        q("select min(jour) as j from install where business in \(dans)", ids).first?.texte("j")
    }

    /// Une cohorte par jour d'install de `debut` à `fin` parmi ceux qui passent les filtres, mesurée depuis
    /// `PostHog.rondsDepuis`, la plus récente d'abord ; un Jn reste nul tant qu'il est incomplet.
    func cohortes(_ filtres: [Filtre] = [], du debut: String, au fin: String) -> [Cohorte] {
        let complet = [1, 7, 14, 30].map(completJusqua)
        let debut = max(debut, PostHog.rondsDepuis)
        let (clauses, valeurs) = Self.clauses(filtres)
        return q("""
            select i.jour as jour, count(*) as installs, sum(i.j1) as j1, sum(i.j7) as j7, sum(i.j14) as j14,
                sum(i.j30) as j30
            from install i left join paiement p on p.business = i.business and p.client = i.client
            where i.jour between ? and ? and i.business in \(dans)\(clauses)
            group by i.jour order by i.jour desc
            """, [debut, fin] + ids + valeurs).map { l in
            let jour = l.texte("jour") ?? ""
            let jn = zip(complet, ["j1", "j7", "j14", "j30"]).map { jour <= $0 ? l.entier($1) : nil }
            return Cohorte(jour: jour, installs: l.entier("installs") ?? 0, j1: jn[0], j7: jn[1], j14: jn[2], j30: jn[3])
        }
    }

    private func agrege(_ filtres: [Filtre], cle: String, jointure: String = "", ordre: String,
                        du debut: String, au fin: String) -> [Segment] {
        let r = PostHog.rondsDepuis, c1 = completJusqua(1), c7 = completJusqua(7)
        let (clauses, valeurs) = Self.clauses(filtres)
        return q("""
            select \(cle) as cle, count(*) as installs, sum(i.paywall) as paywall, sum(i.essai) as essais,
                sum(i.direct) as directs, sum(p.etat = 'paye') as payants,
                sum(i.essai and p.etat = 'paye') as essais_payes, sum(i.essai and p.etat = 'essai') as en_cours,
                sum((i.essai or i.direct) and coalesce(p.etat, 'inconnu') = 'inconnu') as a_verifier,
                sum(i.jour >= ?) as base_rond, sum(i.jour >= ? and i.rond) as ronds,
                sum(i.jour between ? and ?) as base_j1, sum(i.jour between ? and ? and i.j1) as j1,
                sum(i.jour between ? and ?) as base_j7, sum(i.jour between ? and ? and i.j7) as j7
            from install i left join paiement p on p.business = i.business and p.client = i.client \(jointure)
            where i.business in \(dans) and i.jour between ? and ?\(clauses)
            group by cle order by \(ordre)
            """, [r, r, r, c1, r, c1, r, c7, r, c7] + ids + [debut, fin] + valeurs).map { l in
            Segment(valeur: l.texte("cle") ?? "", installs: l.entier("installs") ?? 0, paywall: l.entier("paywall") ?? 0,
                    essais: l.entier("essais") ?? 0, directs: l.entier("directs") ?? 0,
                    baseRond: l.entier("base_rond") ?? 0, ronds: l.entier("ronds") ?? 0,
                    payants: l.entier("payants") ?? 0, essaisPayes: l.entier("essais_payes") ?? 0,
                    enCours: l.entier("en_cours") ?? 0, aVerifier: l.entier("a_verifier") ?? 0,
                    baseJ1: l.entier("base_j1") ?? 0, j1: l.entier("j1") ?? 0,
                    baseJ7: l.entier("base_j7") ?? 0, j7: l.entier("j7") ?? 0)
        }
    }

    /// Les filtres en SQL, chacun précédé de `and`, et leurs paramètres.
    private static func clauses(_ filtres: [Filtre]) -> (String, [Any?]) {
        var sql = "", valeurs: [Any?] = []
        for f in filtres {
            switch f {
            case .valeur(let d, let v):
                let (c, p) = condition(d, v)
                sql += " and (\(c))"
                valeurs += p
            case .sauf(let d, let v):
                let (c, p) = condition(d, v)
                sql += " and not (\(c))"
                valeurs += p
            case .ecran(let rang):
                sql += " and i.loin >= ?"
                valeurs.append(rang)
            case .paywall: sql += " and i.paywall"
            case .essai: sql += " and i.essai"
            case .payant: sql += " and p.etat = 'paye'"
            }
        }
        return (sql, valeurs)
    }

    /// L'install a cette valeur ; la valeur vide : pas de réponse alors que la question était posée.
    private static func condition(_ d: Dimension, _ v: String) -> (String, [Any?]) {
        let aucune = "not exists (select 1 from json_each(i.valeurs, '$.\(d.rawValue)'))"
        switch (v, d.mesureeDepuis) {
        case ("", nil): return (aucune, [])
        case ("", let depuis?): return ("\(aucune) and i.jour >= ?", [depuis])
        case (Dimension.pasMesure, let depuis): return ("\(aucune) and i.jour < ?", [depuis ?? ""])
        default: return ("exists (select 1 from json_each(i.valeurs, '$.\(d.rawValue)') where value = ?)", [v])
        }
    }

    // MARK: portes

    /// Les portes du paywall sur la période, la plus vue d'abord.
    func portes(du debut: String, au fin: String) -> [LignePorte] {
        q("""
            select porte, sum(vues) as vues, sum(essais) as essais, sum(directs) as directs
            from porte where jour between ? and ? and business in \(dans)
            group by porte order by vues desc, essais + directs desc
            """, [debut, fin] + ids).map { l in
            LignePorte(porte: l.texte("porte") ?? "", vues: l.entier("vues") ?? 0, essais: l.entier("essais") ?? 0,
                       directs: l.entier("directs") ?? 0)
        }
    }
}

extension Segment {
    static let vide = Segment(valeur: "", installs: 0, paywall: 0, essais: 0, directs: 0, baseRond: 0, ronds: 0, payants: 0, essaisPayes: 0,
                              enCours: 0, aVerifier: 0, baseJ1: 0, j1: 0, baseJ7: 0, j7: 0)
}
