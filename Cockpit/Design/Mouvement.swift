import SwiftUI

/// Un gros chiffre qui roule : part de zéros à son apparition, roule à chaque changement.
struct Chiffre: View {
    let texte: String
    @State private var affiche: String?

    var body: some View {
        Text(affiche ?? Self.zeros(texte))
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear(perform: rouler)
            .onChange(of: texte, rouler)
    }

    private func rouler() { withAnimation(Theme.Anim.chiffre) { affiche = texte } }

    /// « 1 234 € » → « 0 000 € » : la même largeur, d'où le roulement.
    static func zeros(_ texte: String) -> String { String(texte.map { $0.isWholeNumber ? "0" : $0 }) }
}

/// L'écran qui arrive glisse dans le sens de la barre du haut et se précise ; celui qui part s'efface.
struct Bascule: Transition {
    /// 1 : l'écran vient de la droite ; -1 : de la gauche.
    let sens: CGFloat

    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .offset(x: phase == .willAppear ? sens * 2 * Theme.Anim.glisse : 0)
            .scaleEffect(phase.isIdentity ? 1 : phase == .willAppear ? Theme.Anim.reduit : 1 / Theme.Anim.reduit)
            .blur(radius: phase.isIdentity ? 0 : Theme.Anim.flou)
    }
}

/// La carte de la palette : descend un peu et grandit en s'ouvrant, l'inverse en se fermant.
struct Surgit: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .opacity(phase.isIdentity ? 1 : 0)
            .scaleEffect(phase.isIdentity ? 1 : Theme.Anim.appui, anchor: .top)
            .offset(y: phase.isIdentity ? 0 : -Theme.Anim.glisse)
    }
}

/// Un bloc qui entre à son tour : monte de quelques points et apparaît, `rang` fois le décalage après le premier.
private struct Entree: ViewModifier {
    let rang: Int
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : Theme.Anim.glisse)
            .scaleEffect(visible ? 1 : Theme.Anim.reduit, anchor: .top)
            .onAppear {
                let attente = Double(min(rang, Theme.Anim.rangMax)) * Theme.Anim.decalage
                withAnimation(Theme.Anim.entree.delay(attente)) { visible = true }
            }
    }
}

/// Une carte qui se soulève sous la souris.
private struct Survolable: ViewModifier {
    @State private var survol = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(survol ? Theme.Anim.survolEchelle : 1)
            .brightness(survol ? Theme.Anim.survolLumiere : 0)
            .animation(Theme.Anim.survol, value: survol)
            .onHover { survol = $0 }
    }
}

/// Un graphique qui se dévoile de gauche à droite à son apparition. Le masque déborde pour ne rien couper autour.
private struct Revele: ViewModifier {
    @State private var ouvert = false

    func body(content: Content) -> some View {
        content
            .mask {
                Rectangle()
                    .scale(x: ouvert ? 1 : 0, y: 1, anchor: .leading)
                    .padding(-Theme.Espace.panneau)
            }
            .onAppear { withAnimation(Theme.Anim.trace) { ouvert = true } }
    }
}

/// Reduce Motion : plus aucune animation, ni implicite ni `withAnimation`.
private struct Sobre: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduire

    func body(content: Content) -> some View {
        content.transaction { t in
            if reduire {
                t.animation = nil
                t.disablesAnimations = true
            }
        }
    }
}

/// Le style de tous les boutons : s'enfonce à l'appui, revient en ressort.
struct Appui: ButtonStyle {
    var echelle = Theme.Anim.appui

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? echelle : 1)
            .animation(Theme.Anim.survol, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == Appui {
    static var appui: Appui { Appui() }
    /// Une grosse carte s'enfonce moins.
    static var appuiCarte: Appui { Appui(echelle: Theme.Anim.appuiCarte) }
}

extension View {
    func entree(rang: Int) -> some View { modifier(Entree(rang: rang)) }
    func survolable() -> some View { modifier(Survolable()) }
    func revele() -> some View { modifier(Revele()) }
    func sobre() -> some View { modifier(Sobre()) }
}
