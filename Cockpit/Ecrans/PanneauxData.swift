import Charts
import SwiftUI

/// Mesures sans jeton dans Theme.
private enum Mesure {
    static let jauge: CGFloat = 10
    static let ligne: CGFloat = 24
    static let barre: CGFloat = 8
    static let nomEtape: CGFloat = 130
    static let table: CGFloat = 420
    /// Opacité blanche d'une case : plancher, plus la part du taux le plus haut de la colonne.
    static let caseMin = 0.06
    static let caseEtendue = 0.4
}

struct PointJour: Identifiable {
    let date: Date
    let valeur: Double
    var id: Date { date }

    /// Les jours relevés d'une série finissant à `jour`, en dates de Paris.
    static func serie(_ valeurs: [Double?], jusqua jour: String) -> [PointJour] {
        zip(Jour.derniers(valeurs.count, jusqua: jour), valeurs).compactMap { cle, v in
            guard let v, let date = Jour.date(cle) else { return nil }
            return PointJour(date: date, valeur: v)
        }
    }
}

/// Le MRR brut en euros face à l'objectif : jauge, reste à gagner, arrivée au rythme des 30 derniers jours.
struct PanneauObjectif: View {
    let objectif: Objectif?
    let maintenant: Date

    var body: some View {
        if let o = objectif {
            Panneau(titre: "Objectif \(Format.euros(o.cibleEUR)) par mois") {
                Pastille(texte: Format.pourcent(o.part, decimales: 1), couleur: Theme.accent)
            } contenu: {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
                    Chiffre(texte: Format.euros(o.mrrEUR))
                        .font(Theme.Police.kpi)
                        .tracking(-0.6)
                        .foregroundStyle(Theme.texte)
                    Text("de MRR").font(Theme.Police.corps).foregroundStyle(Theme.secondaire)
                    Spacer(minLength: Theme.Espace.xl)
                    Text(o.resteEUR > 0 ? "Reste \(Format.euros(o.resteEUR)) par mois" : "Objectif atteint")
                        .font(Theme.Police.ligne)
                        .monospacedDigit()
                        .foregroundStyle(Theme.texte)
                }
                GeometryReader { g in
                    Capsule().fill(Theme.accent).frame(width: max(g.size.width * o.part, Mesure.jauge))
                }
                .frame(height: Mesure.jauge)
                .padding(Theme.Espace.s)
                .verre(Capsule())
                if let r = o.rythmeParJourEUR {
                    Text(rythme(r, arrivee: o.arrivee(depuis: maintenant)))
                        .font(Theme.Police.petit)
                        .foregroundStyle(Theme.secondaire)
                }
            }
        } else {
            Panneau(titre: "Objectif") {
                Vide(texte: "RevenueCat n'a pas encore écrit le MRR du jour.")
            }
        }
    }

    private func rythme(_ parJour: Double, arrivee: Date?) -> String {
        let texte = "Au rythme des 30 derniers jours, \(Format.signe(parJour * 30, Format.euros)) de MRR par mois"
        return arrivee.map { texte + " : objectif atteint vers \(Format.moisAnnee($0))." } ?? texte + "."
    }
}

/// Le MRR brut en euros ; un repère tous les `pas` jours.
struct CourbeMRR: View {
    let mrr: [PointJour]
    let pas: Int

    var body: some View {
        Chart(mrr) { p in
            LineMark(x: .value("Jour", p.date, unit: .day), y: .value("MRR", p.valeur))
                .foregroundStyle(Theme.accent)
                .lineStyle(Theme.trait)
        }
        .chartXAxis { axeDates(.stride(by: .day, count: pas)) }
        .chartYAxis { axeNombres { Format.entier($0) + " €" } }
        .frame(height: Theme.Taille.graphiqueHaut)
        .revele()
        .environment(\.calendar, Jour.calendrier)
        .environment(\.timeZone, Jour.fuseau)
    }
}

/// Les achats de chaque jour, aujourd'hui en blanc.
struct BarresAchats: View {
    let achats: [PointJour]
    let aujourdhui: Date?
    let pas: Int

    var body: some View {
        Chart(achats) { p in
            BarMark(x: .value("Jour", p.date, unit: .day), y: .value("Achats", p.valeur))
                .foregroundStyle(p.date == aujourdhui ? Theme.accent : .white.opacity(Theme.Blanc.barre))
                .cornerRadius(Theme.Rayon.barre)
        }
        .chartXAxis { axeDates(.stride(by: .day, count: pas)) }
        .chartYAxis { axeNombres(texte: Format.entier) }
        .frame(height: Theme.Taille.graphiqueHaut)
        .revele()
        .environment(\.calendar, Jour.calendrier)
        .environment(\.timeZone, Jour.fuseau)
    }
}

/// Les achats et essais du fil sur la période, avec leur jour.
struct PanneauVentes: View {
    let evenements: [Evenement]

    var body: some View {
        Bloc(titre: "Achats et essais") {
            Text("\(evenements.count) dans le fil").font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
        } contenu: {
            if evenements.isEmpty {
                Vide(texte: "Aucun achat ni essai dans le fil sur la période.")
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Espace.xs) {
                        ForEach(Array(evenements.enumerated()), id: \.element.id) { i, e in
                            LigneFil(e: e, premiere: i == 0, avecJour: true)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

/// Une ligne par jour d'install, la plus récente en haut ; l'opacité blanche d'une case suit son taux dans la colonne.
struct TableCohortes: View {
    let cohortes: [Cohorte]

    static let colonnes: [(titre: String, jn: KeyPath<Cohorte, Int?>)] = [("J1", \.j1), ("J7", \.j7), ("J14", \.j14), ("J30", \.j30)]

    var body: some View {
        Bloc(titre: "Cohortes") {
            Text("rond fini N jours après l'install, depuis le \(Format.jourCourt(cle: PostHog.rondsDepuis))").font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
        } contenu: {
            if cohortes.isEmpty {
                Vide(texte: "La source PostHog n'a pas encore calculé les cohortes.")
            } else {
                let plafonds = Self.colonnes.map { c in cohortes.compactMap { $0.taux(c.jn) }.max() ?? 0 }
                ScrollView {
                    Grid(horizontalSpacing: Theme.Espace.s, verticalSpacing: Theme.Espace.xs) {
                        GridRow {
                            entete("Jour").gridColumnAlignment(.leading)
                            entete("Installs").gridColumnAlignment(.trailing)
                            ForEach(Self.colonnes, id: \.titre) { c in entete(c.titre).frame(maxWidth: .infinity) }
                        }
                        ForEach(cohortes, id: \.jour) { c in
                            GridRow {
                                jour(c, Format.jourCourt(cle: c.jour))
                                jour(c, Format.entier(c.installs))
                                ForEach(Array(Self.colonnes.enumerated()), id: \.element.titre) { i, col in
                                    caseTaux(c.taux(col.jn), plafond: plafonds[i])
                                }
                            }
                        }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: min(CGFloat(cohortes.count + 1) * (Mesure.ligne + Theme.Espace.xs), Mesure.table))
            }
        }
    }

    private func entete(_ texte: String) -> some View {
        Text(texte).font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
    }

    /// Jour et installs, pâles et en italique tant que la cohorte n'a pas de J1.
    private func jour(_ c: Cohorte, _ texte: String) -> some View {
        let ouverte = c.j1 == nil
        return Text(texte)
            .font(Theme.Police.mini)
            .italic(ouverte)
            .monospacedDigit()
            .foregroundStyle(ouverte ? Theme.secondaire : Theme.texte)
            .help(ouverte ? "Cohorte ouverte, J1 pas encore atteint" : "")
    }

    private func caseTaux(_ t: Double?, plafond: Double) -> some View {
        Text(t.map { Format.pourcent($0, decimales: 1) } ?? "")
            .font(Theme.Police.mini)
            .monospacedDigit()
            .foregroundStyle(Theme.texte)
            .frame(maxWidth: .infinity, minHeight: Mesure.ligne)
            .background(Theme.accent.opacity(t.map { Mesure.caseMin + Mesure.caseEtendue * $0 / max(plafond, 1e-9) } ?? 0),
                        in: RoundedRectangle(cornerRadius: Theme.Rayon.barre, style: .continuous))
    }
}

/// Le tunnel d'onboarding : chaque étape rapportée aux installs, la perte depuis la précédente, la pire en ambre.
/// Avec `choisir`, une étape se clique ; `choisie` est surlignée.
struct PanneauTunnel: View {
    let etapes: [(nom: String, n: Int)]
    var choisie: Int?
    var choisir: ((Int) -> Void)?

    var body: some View {
        Bloc(titre: "Tunnel d'onboarding") {
            Text(choisir == nil ? "écran le plus loin atteint" : "clique un écran pour garder ceux qui l'ont passé")
                .font(Theme.Police.mini)
                .foregroundStyle(Theme.secondaire)
        } contenu: {
            if let premier = etapes.first?.n, premier > 0 {
                let pire = Lectures.plusGrossePerte(etapes)
                VStack(spacing: Theme.Espace.xs) {
                    ForEach(Array(etapes.enumerated()), id: \.offset) { i, e in
                        let l = ligne(e, premier: premier, perte: i > 0 ? etapes[i - 1].n - e.n : 0, pire: i == pire, choisie: i == choisie)
                        if let choisir, i > 0 {
                            Button { choisir(i) } label: { l }
                                .buttonStyle(.appuiCarte)
                                .help(i == choisie ? "Retirer ce filtre" : "Garder ceux qui ont passé « \(e.nom) »")
                        } else {
                            l
                        }
                    }
                }
            } else {
                Vide(texte: "Aucun install sur la période.")
            }
        }
    }

    private func ligne(_ e: (nom: String, n: Int), premier: Int, perte: Int, pire: Bool, choisie: Bool) -> some View {
        let part = Double(e.n) / Double(premier)
        return HStack(spacing: Theme.Espace.m) {
            Text(e.nom)
                .foregroundStyle(Theme.texte)
                .lineLimit(1)
                .frame(width: Mesure.nomEtape, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(Theme.Blanc.pilule))
                    Capsule().fill(pire ? Theme.ambre : Theme.accent).frame(width: g.size.width * part)
                }
            }
            .frame(height: Mesure.barre)
            Text(Format.entier(e.n)).foregroundStyle(Theme.texte).frame(minWidth: 36, alignment: .trailing)
            Text(Format.pourcent(part)).foregroundStyle(Theme.secondaire).frame(minWidth: 40, alignment: .trailing)
            Text(perte > 0 ? Format.delta(Double(-perte)) : "")
                .font(pire ? Theme.Police.miniGras : Theme.Police.mini)
                .foregroundStyle(pire ? Theme.ambre : Theme.secondaire)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .font(Theme.Police.mini)
        .monospacedDigit()
        .padding(.horizontal, Theme.Espace.m)
        .frame(height: Theme.Taille.ligneFil)
        .fondBlanc(choisie ? Theme.Blanc.actif : 0, rayon: Theme.Rayon.ligne)
        .contentShape(Rectangle())
    }
}
