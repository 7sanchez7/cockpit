import Charts
import SwiftUI

/// Petite courbe d'une carte KPI, qui se trace à son apparition, un point lumineux au bout. Un jour sans relevé
/// coupe la courbe ; `inverse` pour un rang (plus bas = mieux) ; `libre` prend toute la place reçue.
struct Sparkline: View {
    let valeurs: [Double?]
    var couleur: Color = .white.opacity(Theme.Blanc.trait)
    var inverse = false
    var libre = false
    @State private var trace: CGFloat = 0

    var body: some View {
        GeometryReader { g in
            let courbe = Courbe(valeurs: valeurs, inverse: inverse)
            courbe
                .trim(from: 0, to: trace)
                .stroke(couleur, style: Theme.trait)
            if let bout = courbe.points(in: CGRect(origin: .zero, size: g.size)).compactMap({ $0 }).last {
                Point(couleur: couleur, taille: Theme.Taille.pointMini)
                    .position(bout)
                    .opacity(trace)
            }
        }
        .frame(width: libre ? nil : Theme.Taille.sparkline.width, height: libre ? nil : Theme.Taille.sparkline.height)
        .onAppear { withAnimation(Theme.Anim.trace) { trace = 1 } }
    }
}

/// Le trait d'une sparkline, levé aux jours sans relevé.
nonisolated private struct Courbe: Shape {
    let valeurs: [Double?]
    let inverse: Bool

    /// La place de chaque valeur dans `rect`, nil aux jours sans relevé.
    func points(in rect: CGRect) -> [CGPoint?] {
        let presentes = valeurs.compactMap { $0 }
        guard presentes.count > 1, let bas = presentes.min(), let haut = presentes.max() else { return [] }
        let ecart = max(haut - bas, 1e-9)
        let pas = rect.width / CGFloat(max(valeurs.count - 1, 1))
        return valeurs.enumerated().map { i, v in
            v.map { v in
                let r = (v - bas) / ecart
                let y = rect.height * CGFloat(inverse ? r : 1 - r)
                return CGPoint(x: CGFloat(i) * pas, y: min(max(y, 1), rect.height - 1))
            }
        }
    }

    func path(in rect: CGRect) -> Path {
        var trait = Path()
        var leve = true
        for p in points(in: rect) {
            guard let p else { leve = true; continue }
            if leve { trait.move(to: p) } else { trait.addLine(to: p) }
            leve = false
        }
        return trait
    }
}

/// Des barres côte à côte, « Actifs par heure » ou « par jour » : la période devant, celle d'avant en fantôme.
/// Elles poussent de gauche à droite à l'apparition.
struct Barres: View {
    let valeurs: [Double?]
    let avant: [Double?]
    /// Barre en cours, en accent avec un halo, les suivantes pas encore vécues ; nil pour une période finie.
    var courante: Int?
    /// Les repères de l'axe : l'index de la barre et son libellé.
    let axe: [(index: Int, texte: String)]
    /// L'infobulle d'une barre.
    let aide: (Int) -> String
    @State private var pousse = false

    private var plafond: Double { max((valeurs + avant).compactMap { $0 }.max() ?? 0, 1) }
    /// L'entrée dure autant pour 7 barres que pour 90.
    private var decalage: Double { Theme.Anim.decalageBarre * 24 / Double(max(valeurs.count, 1)) }

    var body: some View {
        VStack(spacing: Theme.Espace.m) {
            HStack(alignment: .bottom, spacing: valeurs.count > 31 ? Theme.Espace.xs : Theme.Espace.s) {
                ForEach(valeurs.indices, id: \.self) { i in
                    ZStack(alignment: .bottom) {
                        barre(avant[i], couleur: .white.opacity(Theme.Blanc.fantome))
                        if courante.map({ i <= $0 }) ?? true {
                            let enCours = i == courante
                            barre(valeurs[i], couleur: enCours ? Theme.accent : .white.opacity(Theme.Blanc.barre))
                                .shadow(color: enCours ? Theme.accent.opacity(0.75) : .clear, radius: 9)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .animation(Theme.Anim.entree.delay(Double(i) * decalage), value: pousse)
                    .help(aide(i))
                }
            }
            .frame(height: Theme.Taille.barresHeure)
            .onAppear { pousse = true }
            HStack {
                ForEach(axe, id: \.index) { r in
                    Text(r.texte)
                    if r.index != axe.last?.index { Spacer() }
                }
            }
            .font(Theme.Police.axe)
            .foregroundStyle(Theme.tertiaire)
        }
    }

    private func barre(_ v: Double?, couleur: Color) -> some View {
        RoundedRectangle(cornerRadius: Theme.Rayon.barre, style: .continuous)
            .fill(couleur)
            .frame(height: pousse ? Theme.Taille.barresHeure * CGFloat((v ?? 0) / plafond) : 0)
    }
}

/// La légende d'un graphique : un carré de couleur et son nom.
struct Legende: View {
    let items: [(texte: String, couleur: Color)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.texte) { item in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(item.couleur).frame(width: 8, height: 8)
                    Text(item.texte)
                }
            }
        }
        .font(Theme.Police.petit)
        .foregroundStyle(Theme.secondaire)
    }
}

/// L'axe des dates d'un graphique Swift Charts : grille discrète, libellés en police d'axe.
func axeDates(_ valeurs: AxisMarkValues, texte: @escaping @MainActor (Date) -> String = Format.jourCourt) -> some AxisContent {
    AxisMarks(values: valeurs) { v in
        AxisGridLine().foregroundStyle(.white.opacity(Theme.Blanc.grille))
        AxisValueLabel {
            if let d = v.as(Date.self) { Text(texte(d)) }
        }
        .font(Theme.Police.axe)
        .foregroundStyle(Theme.tertiaire)
    }
}

/// L'axe des nombres, à gauche ; `texte` rend nil pour taire une graduation.
func axeNombres(_ valeurs: AxisMarkValues = .automatic(desiredCount: 4),
                texte: @escaping @MainActor (Double) -> String?) -> some AxisContent {
    AxisMarks(position: .leading, values: valeurs) { v in
        AxisGridLine().foregroundStyle(.white.opacity(Theme.Blanc.grille))
        AxisValueLabel {
            if let x = v.as(Double.self), let t = texte(x) { Text(t) }
        }
        .font(Theme.Police.axe)
        .foregroundStyle(Theme.tertiaire)
    }
}
