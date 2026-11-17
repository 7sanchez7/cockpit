import SwiftUI

extension Theme {
    /// Le reflet d'une carte : un blanc qui s'éteint vers le bas.
    static let reflet = LinearGradient(colors: [.white.opacity(0.035), .white.opacity(0.005)], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.45))
    /// L'arête claire en haut d'une carte.
    static let arete = LinearGradient(colors: [.white.opacity(0.1), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.12))
    /// L'aire sous la courbe héros : un blanc qui s'éteint vers le bas.
    static let lavis = LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0)], startPoint: .top, endPoint: .bottom)
    /// Le chiffre héros et le nom de l'app : blanc en haut, éteint vers le bas.
    static let degradeHeros = LinearGradient(stops: [.init(color: .white, location: 0.3), .init(color: .white.opacity(0.52), location: 1)], startPoint: .top, endPoint: .bottom)
}

/// La carte en verre noir : fond `carte`, reflet en haut, filet, arête claire, ombre longue.
struct Verre<S: InsettableShape>: ViewModifier {
    let forme: S

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    forme.fill(Theme.carte).shadow(color: .black.opacity(0.6), radius: 24, y: 18)
                    forme.fill(Theme.reflet)
                }
            }
            .overlay {
                ZStack {
                    forme.strokeBorder(.white.opacity(Theme.Blanc.bord), lineWidth: 1)
                    forme.strokeBorder(Theme.arete, lineWidth: 1)
                }
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func verre<S: InsettableShape>(_ forme: S) -> some View { modifier(Verre(forme: forme)) }

    func verre(rayon: CGFloat) -> some View { verre(RoundedRectangle(cornerRadius: rayon, style: .continuous)) }

    /// Fond d'une ligne ou d'un bloc dans une carte.
    func fondBlanc(_ opacite: Double, rayon: CGFloat) -> some View {
        background(.white.opacity(opacite), in: RoundedRectangle(cornerRadius: rayon, style: .continuous))
    }

    /// Le petit titre en capitales d'une carte.
    func surtitre() -> some View {
        font(Theme.Police.surtitre).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.tertiaire).lineLimit(1)
    }

    /// Le chiffre héros : dégradé blanc et halo.
    func heros() -> some View {
        font(Theme.Police.heros)
            .tracking(-3)
            .foregroundStyle(Theme.degradeHeros)
            .shadow(color: .white.opacity(Theme.Blanc.halo), radius: 28)
    }
}

/// Une pilule colorée : delta d'un KPI, tag du fil, étiquette d'une tâche.
struct Pastille: View {
    let texte: String
    var couleur: Color = Theme.secondaire
    var police: Font = Theme.Police.miniGras
    var largeurMin: CGFloat?

    var body: some View {
        Text(texte)
            .font(police)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(Theme.Anim.chiffre, value: texte)
            .lineLimit(1)
            .foregroundStyle(couleur)
            .padding(.horizontal, Theme.Espace.m)
            .padding(.vertical, 3)
            .frame(minWidth: largeurMin)
            .background(Theme.doux(couleur), in: Capsule())
    }
}

/// Le point d'état d'une source ou du fil, avec son halo.
struct Point: View {
    let couleur: Color
    var taille: CGFloat = Theme.Taille.point

    var body: some View {
        Circle()
            .fill(couleur)
            .frame(width: taille, height: taille)
            .shadow(color: couleur.opacity(0.8), radius: 4)
    }
}

/// Le titre d'une carte en surtitre, son complément à droite.
struct EnTetePanneau<Droite: View>: View {
    let titre: String
    @ViewBuilder var droite: Droite

    var body: some View {
        HStack(spacing: Theme.Espace.m) {
            Text(titre).surtitre()
            Spacer(minLength: Theme.Espace.m)
            droite
        }
        .frame(minHeight: Theme.Taille.segment - Theme.Espace.s)
    }
}

extension EnTetePanneau where Droite == EmptyView {
    init(titre: String) { self.init(titre: titre) { EmptyView() } }
}

/// Une carte titrée : surtitre, contenu.
struct Panneau<Droite: View, Contenu: View>: View {
    let titre: String
    @ViewBuilder var droite: Droite
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xl) {
            EnTetePanneau(titre: titre) { droite }
            contenu
        }
        .padding(Theme.Espace.panneau)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }
}

extension Panneau where Droite == EmptyView {
    init(titre: String, @ViewBuilder contenu: () -> Contenu) {
        self.init(titre: titre, droite: { EmptyView() }, contenu: contenu)
    }
}

/// Message d'une carte sans données, avec ce qu'il faut faire.
struct Vide: View {
    let texte: String

    var body: some View {
        Text(texte)
            .font(Theme.Police.petit)
            .foregroundStyle(Theme.tertiaire)
            .frame(maxWidth: .infinity, minHeight: 60)
    }
}
