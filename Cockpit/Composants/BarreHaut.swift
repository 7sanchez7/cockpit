import SwiftUI

/// La barre du haut : business à gauche, « Cockpit » au centre de la fenêtre entre deux pilules d'écrans,
/// sources, recherche et actualiser à droite.
struct BarreHaut: View {
    var body: some View {
        TroisTiers {
            ChoixBusiness()
            Navigation()
            HStack(spacing: Theme.Espace.m) {
                BandeSources()
                BoutonRecherche()
                BoutonActualiser()
            }
        }
        .frame(height: Theme.Taille.barreHaut)
    }
}

/// Gauche après les boutons de la fenêtre, droite au bord ; le centre reçoit la plus large bande centrée dans la
/// fenêtre que la gauche et la droite au plus serré lui laissent, puis la droite prend le reste.
private struct TroisTiers: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let tailles = subviews.map { $0.sizeThatFits(.unspecified) }
        let largeur = tailles.map(\.width).reduce(Theme.Taille.feux + Theme.Espace.xxl, +)
        return CGSize(width: proposal.width ?? largeur, height: tailles.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let gauche = subviews[0].sizeThatFits(.unspecified).width
        let droiteMin = subviews[2].sizeThatFits(ProposedViewSize(width: 0, height: nil)).width
        let debut = bounds.minX + Theme.Taille.feux
        let fin = bounds.maxX - Theme.Espace.xxl
        let min = debut + gauche + Theme.Espace.xl
        let demi = Swift.min(bounds.midX - min, fin - droiteMin - Theme.Espace.xl - bounds.midX)
        let centre = subviews[1].sizeThatFits(ProposedViewSize(width: 2 * demi, height: nil)).width
        let x = Swift.max(min, Swift.min(bounds.midX - centre / 2, fin - droiteMin - Theme.Espace.xl - centre))
        let place = ProposedViewSize(width: fin - x - centre - Theme.Espace.xl, height: nil)
        subviews[0].place(at: CGPoint(x: debut, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: centre, height: nil))
        subviews[2].place(at: CGPoint(x: fin, y: bounds.midY), anchor: .trailing, proposal: place)
    }
}

/// Le business affiché ; un menu pour en changer ou ouvrir les réglages.
private struct ChoixBusiness: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let tous = app.tousLesBusiness
        let choisi = tous.first { $0.id == app.selection }
        Menu {
            Button("Tous les business") { app.selection = nil }
            ForEach(tous) { b in
                Button(b.nom) { app.selection = b.id }
            }
            Divider()
            SettingsLink { Text("Réglages…") }
        } label: {
            HStack(spacing: Theme.Espace.m) {
                Avatar(business: choisi, taille: Theme.Taille.avatarMini)
                Text(choisi?.nom ?? "Tous")
                    .font(Theme.Police.ligne)
                    .foregroundStyle(Theme.texte)
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.Police.fleche)
                    .foregroundStyle(Theme.tertiaire)
            }
            .lineLimit(1)
            .padding(.leading, Theme.Espace.s + Theme.Espace.xs)
            .padding(.trailing, Theme.Espace.xl)
            .frame(height: Theme.Taille.bouton)
            .verre(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.appui)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(choisi == nil ? tous.map(\.nom).joined(separator: ", ") : "Changer de business")
    }
}

/// « Cockpit » entre deux pilules de verre, coupées avant SAV pour qu'elles fassent à peu près la même
/// largeur ; la pilule blanche glisse de l'ancien écran au nouveau, d'une pilule à l'autre.
private struct Navigation: View {
    @Namespace private var pilule

    var body: some View {
        let gauche = Ecran.allCases.prefix(while: { $0 != .aTraiter })
        Symetrie {
            groupe(gauche)
            HStack(spacing: Theme.Espace.m) {
                Marque(taille: Theme.Taille.marque)
                Text("Cockpit")
                    .font(Theme.Police.marque)
                    .tracking(-0.3)
            }
            .foregroundStyle(Theme.texte)
            .fixedSize()
            groupe(Ecran.allCases.dropFirst(gauche.count))
        }
    }

    private func groupe(_ ecrans: some Collection<Ecran>) -> some View {
        HStack(spacing: Theme.Espace.xs) {
            ForEach(Array(ecrans)) { ItemNav(ecran: $0, pilule: pilule) }
        }
        .padding(Theme.Espace.s)
        .verre(Capsule())
        .fixedSize()
    }
}

/// Trois vues, celle du milieu au centre tant que la largeur le permet : la largeur idéale double la plus large des
/// deux autres, la plus serrée les colle.
private struct Symetrie: Layout {
    private let ecart = Theme.Espace.xxl

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let t = subviews.map { $0.sizeThatFits(.unspecified) }
        guard t.count == 3 else { return .zero }
        let serre = t[0].width + t[1].width + t[2].width + 2 * ecart
        let ideal = 2 * max(t[0].width, t[2].width) + t[1].width + 2 * ecart
        let largeur = proposal.width.map { max(serre, min($0, ideal)) } ?? ideal
        return CGSize(width: largeur, height: t.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let g = subviews[0].sizeThatFits(.unspecified).width
        let n = subviews[1].sizeThatFits(.unspecified).width
        let d = subviews[2].sizeThatFits(.unspecified).width
        let x = max(bounds.minX + g + ecart, min(bounds.midX - n / 2, bounds.maxX - d - ecart - n))
        subviews[0].place(at: CGPoint(x: x - ecart, y: bounds.midY), anchor: .trailing, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: x + n + ecart, y: bounds.midY), anchor: .leading, proposal: .unspecified)
    }
}

/// Un écran de la barre : texte gris, blanc au survol, noir sur la pilule blanche une fois choisi.
private struct ItemNav: View {
    @Environment(AppState.self) private var app
    let ecran: Ecran
    let pilule: Namespace.ID
    @State private var survol = false

    var body: some View {
        let actif = app.ecran == ecran
        Button { app.ecran = ecran } label: {
            HStack(spacing: Theme.Espace.m) {
                Text(ecran.titre)
                    .font(Theme.Police.ligne)
                    .foregroundStyle(actif ? Theme.fond : survol ? Theme.texte : Theme.secondaire)
                if ecran == .aTraiter, case let n = app.lectures.nbATraiter(), n > 0 {
                    Text("\(n)")
                        .font(Theme.Police.miniGras)
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(n)))
                        .foregroundStyle(actif ? Theme.fond : Theme.ambre)
                        .padding(.horizontal, Theme.Espace.m - 1)
                        .padding(.vertical, 1)
                        .background(actif ? Theme.fond.opacity(Theme.Blanc.actif) : Theme.doux(Theme.ambre), in: Capsule())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, Theme.Espace.xl + Theme.Espace.xs)
            .frame(height: Theme.Taille.segment)
            .background {
                if actif {
                    Capsule()
                        .fill(Theme.texte)
                        .shadow(color: .white.opacity(Theme.Blanc.halo), radius: Theme.Espace.l)
                        .matchedGeometryEffect(id: "pilule", in: pilule)
                } else if survol {
                    Capsule()
                        .fill(.white.opacity(Theme.Blanc.survol))
                        .transition(.opacity)
                }
            }
            .animation(Theme.Anim.survol, value: survol)
            .contentShape(Capsule())
        }
        .buttonStyle(.appui)
        .onHover { survol = $0 }
        .help("\(ecran.titre) (⌘\(String(ecran.raccourci)))")
    }
}

/// Un point par source et l'heure de la dernière collecte, les points seuls si la barre manque de place ; au
/// survol, l'état de chacune ; un clic ouvre Santé.
private struct BandeSources: View {
    @Environment(AppState.self) private var app
    @State private var survol = false

    var body: some View {
        let passages = app.lectures.derniersPassages()
        let sources = app.collecteur.sources.map { s in
            (source: s, etat: EtatSource(passage: passages[s.id], enCours: app.collecteur.enCours.contains(s.id)))
        }
        Button { app.ecran = .sante } label: {
            let points = HStack(spacing: Theme.Espace.s) {
                ForEach(sources, id: \.source.id) { Point(couleur: $0.etat.couleur, taille: Theme.Taille.pointMini) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Espace.m) {
                    points
                    Text(Self.derniere(passages, maintenant: app.maintenant))
                        .font(Theme.Police.tag)
                        .foregroundStyle(Theme.secondaire)
                        .contentTransition(.numericText())
                        .fixedSize()
                }
                points
            }
            .padding(.horizontal, Theme.Espace.xl)
            .frame(height: Theme.Taille.bouton)
            .verre(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.appui)
        .onHover { survol = $0 }
        .overlay(alignment: .topTrailing) {
            if survol {
                DetailSources(sources: sources, passages: passages, derniere: Self.derniere(passages, maintenant: app.maintenant))
                    .offset(y: Theme.Taille.bouton + Theme.Espace.m)
                    .transition(Surgit())
                    .allowsHitTesting(false)
            }
        }
        .animation(Theme.Anim.survol, value: survol)
    }

    static func derniere(_ passages: [String: Passage], maintenant: Date) -> String {
        guard let fin = passages.values.map(\.fin).max() else { return "Aucune collecte" }
        return "Collecte " + Format.ilYa(fin, maintenant: maintenant)
    }
}

/// La bulle sous la bande : chaque source, son état et son erreur s'il y en a une.
private struct DetailSources: View {
    let sources: [(source: any Source, etat: EtatSource)]
    let passages: [String: Passage]
    let derniere: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            Text("Sources").surtitre()
            ForEach(sources, id: \.source.id) { s in
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    HStack(spacing: Theme.Espace.m) {
                        Point(couleur: s.etat.couleur)
                        Text(s.source.nom).foregroundStyle(Theme.texte)
                        Spacer(minLength: Theme.Espace.m)
                        Text(s.etat.texte).foregroundStyle(s.etat == .ok ? Theme.secondaire : s.etat.couleur)
                    }
                    .font(Theme.Police.petit)
                    if s.etat == .panne, let erreur = passages[s.source.id]?.erreur {
                        Text(erreur)
                            .font(Theme.Police.mini)
                            .foregroundStyle(Theme.tertiaire)
                            .lineLimit(2)
                            .padding(.leading, Theme.Taille.point + Theme.Espace.m)
                    }
                }
            }
            Text(derniere).font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
        }
        .padding(Theme.Espace.xxl)
        .frame(width: Theme.Taille.bulle, alignment: .leading)
        .verre(rayon: Theme.Rayon.bloc)
    }
}

private struct BoutonRecherche: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Button { app.palette = true } label: {
            HStack(spacing: Theme.Espace.m) {
                Image(systemName: "magnifyingglass").font(Theme.Police.symbole)
                Text("⌘K").font(Theme.Police.tag)
            }
            .foregroundStyle(Theme.secondaire)
            .padding(.horizontal, Theme.Espace.xl)
            .frame(height: Theme.Taille.bouton)
            .verre(Capsule())
            .contentShape(Capsule())
            .fixedSize()
        }
        .buttonStyle(.appui)
        .survolable()
        .help("Rechercher (⌘K)")
    }
}

private struct BoutonActualiser: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let enCours = !app.collecteur.enCours.isEmpty
        Button { app.collecteur.relancer() } label: {
            Image(systemName: "arrow.clockwise")
                .font(Theme.Police.icone)
                .foregroundStyle(enCours ? Theme.texte : Theme.secondaire)
                .symbolEffect(.rotate, isActive: enCours)
                .frame(width: Theme.Taille.bouton, height: Theme.Taille.bouton)
                .verre(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.appui)
        .survolable()
        .help(enCours ? "Collecte en cours" : "Tout relancer (⌘R)")
    }
}

/// L'état affiché d'une source : point et mot.
enum EtatSource: Equatable {
    case ok, panne, aRegler, enCours, jamais

    init(passage: Passage?, enCours: Bool) {
        if enCours { self = .enCours; return }
        switch passage?.etat {
        case .ok: self = .ok
        case .erreur: self = .panne
        case .nonConfigure: self = .aRegler
        case nil: self = .jamais
        }
    }

    var texte: String {
        switch self {
        case .ok: "ok"
        case .panne: "panne"
        case .aRegler: "à régler"
        case .enCours: "…"
        case .jamais: "jamais lue"
        }
    }

    var couleur: Color {
        switch self {
        case .ok: Theme.succes
        case .panne: Theme.danger
        case .aRegler, .jamais: Theme.tertiaire
        case .enCours: Theme.texte
        }
    }
}
