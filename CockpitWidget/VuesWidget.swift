import Charts
import SwiftUI

// Les trois tailles du widget, sans WidgetKit : on peut les rendre hors du bureau pour les regarder.

/// Petit : le revenu du jour et sa courbe cumulée.
struct WidgetPetit: View {
    let r: ResumeWidget

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            EnTeteWidget(titre: "Revenu")
            ChiffreHeros(texte: r.revenu, police: Theme.Police.widgetHeros)
            Text(r.hier).font(Theme.Police.petit).foregroundStyle(Theme.secondaire)
            Courbe(valeurs: r.cumul, aire: true).padding(.top, Theme.Espace.m)
        }
    }
}

/// Moyen : le revenu à gauche, les quatre premiers chiffres de l'Accueil à droite.
struct WidgetMoyen: View {
    let r: ResumeWidget

    var body: some View {
        HStack(spacing: Theme.Espace.xxl) {
            WidgetPetit(r: r)
            Filet().frame(width: 1)
            Grid(horizontalSpacing: Theme.Espace.xl, verticalSpacing: Theme.Espace.xl) {
                ForEach(0..<2, id: \.self) { ligne in
                    GridRow {
                        ForEach(r.kpis.dropFirst(ligne * 2).prefix(2), id: \.libelle) { TuileKpi(kpi: $0) }
                    }
                }
            }
        }
    }
}

/// Grand : le revenu, sa courbe, puis les cinq chiffres de l'Accueil et les tâches à traiter, chacun avec sa courbe.
struct WidgetGrand: View {
    let r: ResumeWidget

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            EnTeteWidget(titre: "Cockpit", maj: r.maj)
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text("Revenu aujourd'hui").surtitre()
                HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.l) {
                    ChiffreHeros(texte: r.revenu, police: Theme.Police.widgetHerosGrand)
                    Pastille(texte: r.hier)
                }
                Text(r.detail).font(Theme.Police.petit).foregroundStyle(Theme.secondaire)
            }
            Courbe(valeurs: r.cumul, aire: true).frame(height: Theme.Taille.courbeWidget)
            Grid(horizontalSpacing: Theme.Espace.m, verticalSpacing: Theme.Espace.m) {
                ForEach(0..<2, id: \.self) { ligne in
                    GridRow {
                        ForEach(tuiles.dropFirst(ligne * 3).prefix(3), id: \.libelle) { kpi in
                            TuileKpi(kpi: kpi, courbe: true, couleur: kpi.libelle == Self.aTraiter && r.aTraiter > 0 ? Theme.ambre : nil)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .padding(Theme.Espace.m)
                                .fondBlanc(Theme.Blanc.bloc, rayon: Theme.Rayon.ligne)
                        }
                    }
                }
            }
        }
    }

    private static let aTraiter = "À traiter"

    private var tuiles: [ResumeWidget.Kpi] {
        r.kpis + [ResumeWidget.Kpi(libelle: Self.aTraiter, valeur: r.aTraiter.formatted(), delta: nil, ecart: nil,
                                   note: nil, serie: [])]
    }
}

/// Sans résumé : l'app n'a encore rien écrit.
struct WidgetVide: View {
    var body: some View {
        VStack(spacing: Theme.Espace.m) {
            Marque(taille: Theme.Taille.avatar).foregroundStyle(Theme.secondaire)
            Text("Ouvre Cockpit pour remplir le widget.")
                .font(Theme.Police.petit)
                .foregroundStyle(Theme.tertiaire)
                .multilineTextAlignment(.center)
        }
    }
}

/// Le fond du widget : la carte en verre noir de l'app.
struct FondWidget: View {
    var body: some View {
        ZStack {
            Theme.carte
            Theme.reflet
        }
    }
}

/// Le logo et un surtitre, l'heure de la collecte à droite.
private struct EnTeteWidget: View {
    let titre: String
    var maj: String?

    var body: some View {
        HStack(spacing: Theme.Espace.s + Theme.Espace.xs) {
            Marque(taille: Theme.Taille.marqueWidget).foregroundStyle(Theme.secondaire)
            Text(titre).surtitre()
            Spacer(minLength: 0)
            if let maj { Text("maj " + maj).font(Theme.Police.tag).foregroundStyle(Theme.tertiaire) }
        }
    }
}

private struct ChiffreHeros: View {
    let texte: String
    let police: Font

    var body: some View {
        Text(texte)
            .font(police)
            .tracking(-1.5)
            .monospacedDigit()
            .foregroundStyle(Theme.degradeHeros)
            .shadow(color: .white.opacity(Theme.Blanc.halo), radius: 16)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }
}

/// Un chiffre de l'Accueil : libellé, valeur, delta coloré par son ton et, si `courbe`, ses 14 derniers jours.
private struct TuileKpi: View {
    let kpi: ResumeWidget.Kpi
    var courbe = false
    /// Remplace la couleur de la valeur, l'ambre des tâches en attente.
    var couleur: Color?

    var body: some View {
        let ton = Ton(kpi.ecart)
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(kpi.libelle).font(Theme.Police.tag).textCase(.uppercase).foregroundStyle(Theme.tertiaire).lineLimit(1)
            Text(kpi.valeur)
                .font(Theme.Police.widgetKpi)
                .monospacedDigit()
                .foregroundStyle(couleur ?? Theme.texte)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(kpi.delta ?? kpi.note ?? " ")
                .font(Theme.Police.miniGras)
                .monospacedDigit()
                .foregroundStyle(kpi.delta == nil ? Theme.tertiaire : ton.couleur)
                .lineLimit(1)
            if courbe, !kpi.serie.isEmpty {
                Courbe(valeurs: kpi.serie, couleur: ton.trait).frame(height: Theme.Taille.sparklineWidget).padding(.top, Theme.Espace.xs)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Une courbe sans axes ; `aire` la pose sur le lavis de la courbe héros, un point lumineux au bout.
private struct Courbe: View {
    let valeurs: [Double?]
    var couleur: Color = Theme.accent
    var aire = false

    var body: some View {
        let points = valeurs.enumerated().compactMap { i, v in v.map { (x: i, y: $0) } }
        if points.count > 1, let bas = points.map(\.y).min(), let haut = points.map(\.y).max(), let fin = points.last {
            // un plancher sous le plus bas, pas zéro : la courbe garde son relief
            let plancher = bas - max((haut - bas) * 0.3, 1)
            Chart {
                ForEach(points, id: \.x) { p in
                    if aire {
                        AreaMark(x: .value("Jour", p.x), yStart: .value("Plancher", plancher), yEnd: .value("Valeur", p.y))
                            .foregroundStyle(Theme.lavis)
                            .interpolationMethod(.monotone)
                    }
                    LineMark(x: .value("Jour", p.x), y: .value("Valeur", p.y))
                        .foregroundStyle(couleur)
                        .lineStyle(Theme.trait)
                        .interpolationMethod(.monotone)
                }
                if aire {
                    PointMark(x: .value("Jour", fin.x), y: .value("Valeur", fin.y))
                        .symbol { Point(couleur: couleur, taille: Theme.Taille.pointMini) }
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXScale(domain: 0...max(valeurs.count - 1, 1))
            .chartYScale(domain: plancher...haut)
        } else {
            Filet().frame(height: 1).frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct Filet: View {
    var body: some View { Color.white.opacity(Theme.Blanc.bord) }
}
