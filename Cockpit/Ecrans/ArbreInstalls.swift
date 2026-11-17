import SwiftUI

/// Mesures sans jeton dans Theme.
private enum Mesure {
    static let barre: CGFloat = 6
    /// Les valeurs montrées avant « + N autres ».
    static let lignes = 12
    static let colonnesDimensions = 8
    static let installs: CGFloat = 58
    static let taux: CGFloat = 86
    static let court: CGFloat = 48
    static let ecarter: CGFloat = 28
}

/// L'arbre des installs de `debut` à `fin` qui passent la racine : ceux de la période, ou d'un build. Le chemin dit
/// les filtres posés, du plus large au plus fin ; l'entonnoir et le tunnel montrent le nœud ouvert ; la table le
/// découpe par une dimension. Une marche, un écran ou une valeur cliqué descend d'un niveau, une valeur écartée garde
/// tous les autres, le chemin remonte.
struct ArbreInstalls: View {
    @Environment(AppState.self) private var app
    let l: Lectures
    let debut: String
    let fin: String
    /// Les filtres sous tous les nœuds, hors du chemin : le build choisi.
    let racine: [Filtre]

    /// L'ordre des découpages : où ils s'arrêtent, ce qui se vend, d'où ils viennent, puis qui ils sont.
    static let dimensions: [Dimension] = [
        .loin, .produit, .source, .age, .motivation, .blocage, .niveau, .langue,
        .maternelle, .zone, .pays, .interet, .notifs, .compte, .tuteur, .build,
    ]

    var body: some View {
        let chemin = app.chemin
        let noeuds = (0...chemin.count).map { l.noeud(racine + chemin.prefix($0), du: debut, au: fin) }
        let noeud = noeuds[chemin.count]
        let etapes: [(nom: String, n: Int)] = [(nom: "Installs", n: noeud.installs)]
            + zip(PostHog.ecrans, l.tunnel(racine + chemin, du: debut, au: fin)).map { (nom: $0.nom, n: $1) }
        FilAriane(racine: racine.first?.libelle ?? "Tous les installs", chemin: chemin, installs: noeuds.map(\.installs), aller: aller)
        Rangee(poids: [1, 1]) {
            Entonnoir(noeud: noeud, racine: noeuds[0], parent: chemin.isEmpty ? nil : noeuds[chemin.count - 1],
                      chemin: chemin, basculer: basculer)
            PanneauTunnel(etapes: etapes, choisie: chemin.lazy.compactMap(\.rang).first, choisir: passer)
        }
        Decoupe(dimension: app.decoupe, enfants: l.enfants(racine + chemin, par: app.decoupe, du: debut, au: fin),
                noeud: noeud, chemin: chemin, choisir: { d in withAnimation(Theme.Anim.navigation) { app.decoupe = d } },
                ouvrir: ouvrir, ecarter: { basculer(.sauf(app.decoupe, $0)) })
    }

    private func aller(_ chemin: [Filtre]) { withAnimation(Theme.Anim.navigation) { app.chemin = chemin } }

    /// Pose le filtre, ou le retire s'il est déjà posé.
    private func basculer(_ filtre: Filtre) {
        var c = app.chemin
        if let i = c.firstIndex(of: filtre) { c.remove(at: i) } else { c.append(filtre) }
        aller(c)
    }

    /// Garde ceux qui ont passé l'écran : un seul écran à la fois, le recliquer le retire.
    private func passer(_ rang: Int) {
        let avant = app.chemin.lazy.compactMap(\.rang).first
        aller(app.chemin.filter { $0.rang == nil } + (avant == rang ? [] : [.ecran(rang)]))
    }

    /// Descend dans la valeur et découpe par la dimension suivante pas encore posée ; une valeur posée se retire.
    private func ouvrir(_ valeur: String) {
        let filtre = Filtre.valeur(app.decoupe, valeur)
        let posee = app.chemin.contains(filtre)
        basculer(filtre)
        guard !posee else { return }
        let suite = Self.dimensions.drop { $0 != app.decoupe }.dropFirst() + Self.dimensions
        let libre = suite.first { d in !app.chemin.contains { $0.dimension == d } }
        withAnimation(Theme.Anim.navigation) { app.decoupe = libre ?? app.decoupe }
    }
}

private extension Filtre {
    var rang: Int? {
        if case .ecran(let r) = self { return r }
        return nil
    }

    /// La dimension d'une réponse gardée ou écartée.
    var dimension: Dimension? {
        switch self {
        case .valeur(let d, _), .sauf(let d, _): d
        default: nil
        }
    }
}

/// Les filtres posés, du plus large au plus fin, avec les installs de chaque nœud ; un clic remonte, la croix retire
/// ce seul filtre.
private struct FilAriane: View {
    let racine: String
    let chemin: [Filtre]
    let installs: [Int]
    let aller: ([Filtre]) -> Void

    var body: some View {
        HStack(spacing: Theme.Espace.m) {
            ScrollView(.horizontal) {
                HStack(spacing: Theme.Espace.s) {
                    miette(0, racine)
                    ForEach(Array(chemin.enumerated()), id: \.offset) { i, f in
                        Image(systemName: "chevron.right").font(Theme.Police.fleche).foregroundStyle(Theme.secondaire)
                        miette(i + 1, f.libelle)
                    }
                }
            }
            .scrollIndicators(.never)
            if !chemin.isEmpty {
                Button { aller([]) } label: {
                    Text("Tout effacer")
                        .font(Theme.Police.label)
                        .foregroundStyle(Theme.secondaire)
                        .padding(.horizontal, Theme.Espace.xl)
                        .frame(height: Theme.Taille.segment)
                        .contentShape(Capsule())
                }
                .buttonStyle(.appui)
            }
        }
        .padding(Theme.Espace.s)
        .verre(Capsule())
    }

    private func miette(_ k: Int, _ texte: String) -> some View {
        let courante = k == chemin.count
        return HStack(spacing: Theme.Espace.m) {
            Button { aller(Array(chemin.prefix(k))) } label: {
                HStack(spacing: Theme.Espace.m) {
                    Text(texte)
                        .font(courante ? Theme.Police.corpsGras : Theme.Police.ligne)
                        .foregroundStyle(courante ? Theme.texte : Theme.secondaire)
                    Text(Format.entier(installs[k]))
                        .font(Theme.Police.miniGras)
                        .monospacedDigit()
                        .foregroundStyle(courante ? Theme.accent : Theme.secondaire)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.appui)
            .help(courante ? "Le nœud ouvert, \(Format.entier(installs[k])) installs" : "Remonter ici")
            if k > 0 {
                Button { aller(chemin.enumerated().filter { $0.offset != k - 1 }.map(\.element)) } label: {
                    Image(systemName: "xmark")
                        .font(Theme.Police.coche)
                        .foregroundStyle(Theme.secondaire)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.appui)
                .help("Retirer ce seul filtre")
            }
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Espace.xl)
        .frame(height: Theme.Taille.segment)
        .background(courante ? Theme.doux(Theme.accent) : .white.opacity(Theme.Blanc.pilule), in: Capsule())
    }
}

/// Le nœud ouvert en entonnoir : installs, paywall vu, essai, payant, chacun rapporté aux installs du nœud et comparé
/// au nœud du dessus. Une marche cliquée garde ceux qui l'ont franchie.
private struct Entonnoir: View {
    let noeud: Segment
    let racine: Segment
    let parent: Segment?
    let chemin: [Filtre]
    let basculer: (Filtre) -> Void

    var body: some View {
        Bloc(titre: "Entonnoir du nœud") {
            if noeud.installs > 0, noeud.installs < Segment.minimum {
                Pastille(texte: "taux fragiles", couleur: Theme.ambre)
                    .help("Moins de \(Segment.minimum) installs : un install de plus bouge les taux de plusieurs points")
            }
        } contenu: {
            if noeud.installs == 0 {
                Vide(texte: "Aucun install ne passe ces filtres sur la période.")
            } else {
                let n = noeud
                VStack(spacing: Theme.Espace.xs) {
                    marche("Installs", n.installs, Theme.secondaire, filtre: nil, taux: nil,
                           sous: parent == nil ? nil : "\(Format.pourcent(Double(n.installs) / Double(max(racine.installs, 1)), decimales: 1)) de tous les installs")
                    passage(n.paywallVu, "voient le paywall", perte: n.installs - n.paywall)
                    marche("Paywall vu", n.paywall, Theme.bleu, filtre: .paywall, taux: \.paywallVu, sous: nil)
                    passage(Segment.taux(n.essais, n.paywall), "prennent l'essai", perte: n.paywall - n.essais)
                    marche("Essai gratuit", n.essais, Theme.violet, filtre: .essai, taux: \.essai,
                           sous: n.enCours > 0 ? "dont \(Format.entier(n.enCours)) en cours" : nil)
                    passage(n.essaiVersPayant, "des essais finis paient", perte: n.essaisFinis - n.essaisPayes)
                    marche("Payant", n.payants, Theme.succes, filtre: .payant, taux: \.payant,
                           sous: n.payants > n.essaisPayes ? "dont \(Format.entier(n.payants - n.essaisPayes)) sans essai" : nil)
                }
                Spacer(minLength: 0)
                tuiles(n)
            }
        }
    }

    @ViewBuilder
    private func marche(_ nom: String, _ nombre: Int, _ couleur: Color, filtre: Filtre?, taux: KeyPath<Segment, Double?>?,
                        sous: String?) -> some View {
        if let filtre {
            let posee = chemin.contains(filtre)
            Button { basculer(filtre) } label: {
                corps(nom, nombre, couleur, taux: taux, sous: sous, coche: posee)
                    .fondBlanc(posee ? Theme.Blanc.actif : Theme.Blanc.ligne, rayon: Theme.Rayon.tache)
            }
            .buttonStyle(.appuiCarte)
            .help(posee ? "Retirer ce filtre" : "Garder ceux qui sont passés par « \(nom) »")
        } else {
            corps(nom, nombre, couleur, taux: nil, sous: sous, coche: nil)
                .fondBlanc(Theme.Blanc.ligne, rayon: Theme.Rayon.tache)
        }
    }

    /// Une marche : le compte, sa part des installs du nœud en barre, l'écart avec le nœud du dessus.
    private func corps(_ nom: String, _ nombre: Int, _ couleur: Color, taux: KeyPath<Segment, Double?>?, sous: String?,
                       coche: Bool?) -> some View {
        let part = Double(nombre) / Double(max(noeud.installs, 1))
        return VStack(spacing: Theme.Espace.m) {
            HStack(spacing: Theme.Espace.l) {
                Point(couleur: couleur)
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    Text(nom).font(Theme.Police.label).foregroundStyle(Theme.secondaire)
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
                        Chiffre(texte: Format.entier(nombre)).font(Theme.Police.grand).foregroundStyle(Theme.texte)
                        if let sous { Text(sous).font(Theme.Police.mini).foregroundStyle(Theme.secondaire) }
                    }
                }
                Spacer(minLength: Theme.Espace.m)
                if let taux {
                    VStack(alignment: .trailing, spacing: Theme.Espace.xs) {
                        Text(Format.pourcent(part, decimales: 1))
                            .font(Theme.Police.h2)
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(couleur)
                        ecart(taux)
                    }
                }
                if let coche {
                    Image(systemName: coche ? "checkmark.circle.fill" : "plus.circle")
                        .font(Theme.Police.icone)
                        .foregroundStyle(coche ? couleur : Theme.secondaire)
                }
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(Theme.Blanc.pilule))
                    Capsule().fill(couleur).frame(width: max(g.size.width * part, Mesure.barre))
                }
            }
            .frame(height: Mesure.barre)
        }
        .padding(.horizontal, Theme.Espace.xl)
        .padding(.vertical, Theme.Espace.l)
        .contentShape(Rectangle())
    }

    /// L'écart en points avec le nœud du dessus : vert s'il gagne, rouge s'il perd, gris si le nœud est trop petit.
    @ViewBuilder
    private func ecart(_ taux: KeyPath<Segment, Double?>) -> some View {
        if let parent, let texte = Format.points(noeud[keyPath: taux], parent[keyPath: taux]) {
            let e = Format.ecart(noeud[keyPath: taux], parent[keyPath: taux]) ?? 0
            let fiable = noeud.installs >= Segment.minimum
            Pastille(texte: texte, couleur: !fiable || abs(e) < 0.0005 ? Theme.secondaire : e > 0 ? Theme.succes : Theme.danger,
                     police: Theme.Police.tag)
                .help("Le nœud du dessus : \(parent[keyPath: taux].map { Format.pourcent($0, decimales: 1) } ?? Format.vide)")
        }
    }

    /// Le passage d'une marche à la suivante : son taux et ceux qu'il perd.
    private func passage(_ t: Double?, _ texte: String, perte: Int) -> some View {
        HStack(spacing: Theme.Espace.m) {
            Image(systemName: "arrow.down").font(Theme.Police.fleche)
            Text("\(t.map { Format.pourcent($0, decimales: 1) } ?? Format.vide) \(texte)")
            Spacer(minLength: Theme.Espace.m)
            if perte > 0 { Text(Format.delta(Double(-perte))).help("Perdus à ce passage") }
        }
        .font(Theme.Police.mini)
        .monospacedDigit()
        .foregroundStyle(Theme.secondaire)
        .padding(.horizontal, Theme.Espace.xl)
        .padding(.vertical, Theme.Espace.xs)
    }

    private func tuiles(_ n: Segment) -> some View {
        let pc = { (t: Double?) in t.map { Format.pourcent($0, decimales: 1) } ?? Format.vide }
        return Grid(horizontalSpacing: Theme.Espace.m, verticalSpacing: Theme.Espace.m) {
            GridRow {
                tuile("Achats sans essai", Format.entier(n.directs), aide: "Achats lancés depuis le paywall sans essai, cartes refusées comprises : Payant dit lesquels ont été encaissés")
                tuile("Essais en cours", Format.entier(n.enCours), aide: "Essais que RevenueCat voit encore courir")
                tuile("À vérifier", Format.entier(n.aVerifier),
                      aide: "Convertis que RevenueCat n'a pas encore lus, ou qu'il ne connaît pas en production")
                tuile("Rond fini", pc(n.rond),
                      aide: "\(Format.entier(n.ronds)) sur \(Format.entier(n.baseRond)) installs depuis le \(Format.jourCourt(cle: PostHog.rondsDepuis)) ont fini au moins un rond")
            }
            GridRow {
                tuile("Retour J1", pc(n.retourJ1),
                      aide: "\(Format.entier(n.j1)) sur \(Format.entier(n.baseJ1)) installs assez anciens, depuis le \(Format.jourCourt(cle: PostHog.rondsDepuis)), ont fini un rond le lendemain")
                tuile("Retour J7", pc(n.retourJ7),
                      aide: "\(Format.entier(n.j7)) sur \(Format.entier(n.baseJ7)) installs assez anciens, depuis le \(Format.jourCourt(cle: PostHog.rondsDepuis)), ont fini un rond 7 jours après")
                tuile("Part des installs", pc(Segment.taux(n.installs, racine.installs)),
                      aide: "\(Format.entier(n.installs)) des \(Format.entier(racine.installs)) installs en haut de l'arbre")
                tuile("Part du nœud au-dessus", pc(parent.flatMap { Segment.taux(n.installs, $0.installs) }),
                      aide: parent.map { "\(Format.entier(n.installs)) des \(Format.entier($0.installs)) installs du nœud au-dessus" } ?? "Aucun filtre posé")
            }
        }
    }

    private func tuile(_ libelle: String, _ valeur: String, aide: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(libelle).font(Theme.Police.tag).foregroundStyle(Theme.secondaire).lineLimit(1)
            Text(valeur).font(Theme.Police.ligne).monospacedDigit().foregroundStyle(Theme.texte)
        }
        .padding(.horizontal, Theme.Espace.l)
        .padding(.vertical, Theme.Espace.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fondBlanc(Theme.Blanc.ligne, rayon: Theme.Rayon.ligne)
        .help(aide)
    }
}

/// Une colonne de la découpe : un compte, son taux s'il en a un, la base qui dit si le taux est fiable.
private struct Colonne {
    let titre: String
    let aide: String
    let largeur: CGFloat
    var n: KeyPath<Segment, Int>?
    var taux: KeyPath<Segment, Double?>?
    let base: KeyPath<Segment, Int>

    /// Ce qui trie la colonne : le taux, sinon le compte.
    func cle(_ s: Segment) -> Double? { taux.map { s[keyPath: $0] } ?? n.map { Double(s[keyPath: $0]) } }

    static let toutes = [
        Colonne(titre: "Installs", aide: "Installs de la valeur sur la période", largeur: Mesure.installs, n: \.installs, base: \.installs),
        Colonne(titre: "Paywall", aide: "Ont vu le paywall, sur les installs", largeur: Mesure.taux, n: \.paywall, taux: \.paywallVu,
                base: \.installs),
        Colonne(titre: "Essai", aide: "Ont pris l'essai gratuit, sur les installs", largeur: Mesure.taux, n: \.essais, taux: \.essai,
                base: \.installs),
        Colonne(titre: "Payant", aide: "Payants vus par RevenueCat, essais passés à payant et achats sans essai, sur les installs",
                largeur: Mesure.taux, n: \.payants, taux: \.payant, base: \.installs),
        Colonne(titre: "Essai payé", aide: "Essais finis qui ont payé, sur les essais finis", largeur: Mesure.taux, n: \.essaisPayes,
                taux: \.essaiVersPayant, base: \.essaisFinis),
        Colonne(titre: "Rond", aide: "Ont fini au moins un rond, sur les installs depuis la mesure des ronds", largeur: Mesure.court,
                taux: \.rond, base: \.baseRond),
        Colonne(titre: "J1", aide: "Ont fini un rond le lendemain, sur les installs assez anciens depuis la mesure des ronds",
                largeur: Mesure.court, taux: \.retourJ1, base: \.baseJ1),
        Colonne(titre: "J7", aide: "Ont fini un rond 7 jours après, sur les installs assez anciens depuis la mesure des ronds",
                largeur: Mesure.court, taux: \.retourJ7, base: \.baseJ7),
    ]
}

/// Le nœud comparé valeur par valeur : les dimensions au-dessus, puis chaque valeur avec son entonnoir en chiffres et ses
/// retours. Une ligne cliquée descend dans la valeur, l'œil barré l'écarte ; un en-tête cliqué trie, les taux fragiles en
/// dernier, les installs d'avant la mesure toujours au bout.
private struct Decoupe: View {
    let dimension: Dimension
    let enfants: [Segment]
    let noeud: Segment
    let chemin: [Filtre]
    let choisir: (Dimension) -> Void
    let ouvrir: (String) -> Void
    let ecarter: (String) -> Void
    @State private var tri: String?
    @State private var tout = false

    var body: some View {
        Bloc(titre: "Comparer par \(dimension.nom.lowercased())") {
            Text("clique une valeur pour n'en garder que ses installs, l'œil barré pour l'écarter"
                 + (dimension.multiple ? " ; plusieurs réponses par install, les parts se recoupent" : ""))
                .font(Theme.Police.mini)
                .foregroundStyle(Theme.secondaire)
        } contenu: {
            dimensions
            table
        }
        .onChange(of: dimension) { tout = false }
    }

    private var dimensions: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Espace.s), count: Mesure.colonnesDimensions),
                  spacing: Theme.Espace.s) {
            ForEach(ArbreInstalls.dimensions, id: \.self) { d in
                let actif = d == dimension
                let posees = chemin.compactMap { f -> String? in
                    switch f {
                    case .valeur(d, let v): d.libelle(v)
                    case .sauf(d, let v): "sauf \(d.libelle(v))"
                    default: nil
                    }
                }
                Button { choisir(d) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(d.nom)
                            .font(actif ? Theme.Police.corpsGras : Theme.Police.ligne)
                            .foregroundStyle(actif ? Theme.texte : Theme.secondaire)
                        if !posees.isEmpty {
                            Text(posees.joined(separator: ", ")).font(Theme.Police.tag).foregroundStyle(Theme.accent)
                        }
                    }
                    .lineLimit(1)
                    .padding(.horizontal, Theme.Espace.l)
                    .frame(maxWidth: .infinity, minHeight: Theme.Taille.bouton, alignment: .leading)
                    .fondBlanc(actif ? Theme.Blanc.actif : Theme.Blanc.ligne, rayon: Theme.Rayon.ligne)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.appuiCarte)
                .help(posees.isEmpty ? "Découper par \(d.nom.lowercased())" : "Déjà filtré : \(posees.joined(separator: ", "))")
            }
        }
    }

    @ViewBuilder
    private var table: some View {
        let mesures = enfants.filter { $0.valeur != Dimension.pasMesure }
        let lignes = trier(mesures) + enfants.filter { $0.valeur == Dimension.pasMesure }
        let montrees = tout ? lignes : Array(lignes.prefix(Mesure.lignes))
        let aucun = Colonne.toutes.map { _ in Double?.none }
        let hauts = Colonne.toutes.map { c in
            meilleur(mesures.map { s in s[keyPath: c.base] >= Segment.minimum ? c.taux.flatMap { s[keyPath: $0] } : nil })
        }
        VStack(spacing: 0) {
            entetes
            if enfants.isEmpty {
                Vide(texte: "Aucune valeur sur ce nœud.")
            }
            ForEach(Array(montrees.enumerated()), id: \.element.valeur) { i, s in
                let libelle = dimension.libelle(s.valeur)
                let posee = chemin.contains(.valeur(dimension, s.valeur))
                HStack(spacing: 0) {
                    Button { ouvrir(s.valeur) } label: {
                        rangee(s, hauts: s.valeur == Dimension.pasMesure ? aucun : hauts) { valeur(libelle, s) }
                    }
                    .buttonStyle(.appuiCarte)
                    .help(posee ? "Retirer « \(libelle) » du chemin" : "N'en garder que « \(libelle) »")
                    Button { ecarter(s.valeur) } label: {
                        Image(systemName: "eye.slash")
                            .font(Theme.Police.coche)
                            .foregroundStyle(Theme.secondaire)
                            .frame(width: Mesure.ecarter, height: Theme.Taille.ligneVideo)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.appui)
                    .help("Écarter « \(libelle) » : garder tous les autres")
                    .accessibilityLabel("Écarter \(libelle)")
                    .opacity(posee ? 0 : 1)
                    .disabled(posee)
                }
                .fondBlanc(posee ? Theme.Blanc.actif : i % 2 == 0 ? Theme.Blanc.ligne : 0, rayon: Theme.Rayon.ligne)
            }
            if lignes.count > Mesure.lignes {
                Button { withAnimation(Theme.Anim.navigation) { tout.toggle() } } label: {
                    Text(tout ? "Moins de valeurs" : "+ \(lignes.count - Mesure.lignes) autres valeurs")
                        .font(Theme.Police.label)
                        .foregroundStyle(Theme.secondaire)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.Taille.ligneFil)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.appui)
            }
            if !enfants.isEmpty {
                rangee(noeud, hauts: aucun) {
                    Text("Tout le nœud").foregroundStyle(Theme.secondaire).padding(.horizontal, Theme.Espace.m)
                }
                .padding(.trailing, Mesure.ecarter)
                .overlay(alignment: .top) { Rectangle().fill(.white.opacity(Theme.Blanc.grille)).frame(height: 1) }
            }
        }
    }

    private var entetes: some View {
        HStack(spacing: Theme.Espace.m) {
            cellule(nil, aligne: .leading) { Text(dimension.nom).foregroundStyle(Theme.secondaire) }
            ForEach(Colonne.toutes, id: \.titre) { c in
                let actif = tri == c.titre
                cellule(c.largeur) {
                    Button { withAnimation(Theme.Anim.navigation) { tri = actif ? nil : c.titre } } label: {
                        HStack(spacing: Theme.Espace.xs) {
                            if actif { Image(systemName: "chevron.down").font(Theme.Police.coche) }
                            Text(c.titre)
                        }
                        .foregroundStyle(actif ? Theme.texte : Theme.secondaire)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.appui)
                    .help(c.aide + (actif ? ". Clique pour revenir à l'ordre de base." : ". Clique pour trier."))
                }
            }
        }
        .font(Theme.Police.miniGras.weight(.bold))
        .lineLimit(1)
        .padding(.horizontal, Theme.Espace.l)
        .padding(.top, Theme.Espace.s)
        .padding(.bottom, 6)
        .padding(.trailing, Mesure.ecarter)
    }

    private func rangee<Nom: View>(_ s: Segment, hauts: [Double?], @ViewBuilder nom: () -> Nom) -> some View {
        HStack(spacing: Theme.Espace.m) {
            cellule(nil, aligne: .leading) { nom() }
            ForEach(Array(Colonne.toutes.enumerated()), id: \.offset) { k, c in
                cellule(c.largeur) { chiffre(s, c, haut: hauts[k]) }
            }
        }
        .font(Theme.Police.petit)
        .monospacedDigit()
        .padding(.horizontal, Theme.Espace.l)
        .frame(height: Theme.Taille.ligneVideo)
        .contentShape(Rectangle())
    }

    /// La valeur, sa part des installs du nœud en barre derrière.
    private func valeur(_ libelle: String, _ s: Segment) -> some View {
        let part = Segment.taux(s.installs, noeud.installs) ?? 0
        return HStack(spacing: Theme.Espace.m) {
            Text(libelle).foregroundStyle(s.valeur == Dimension.pasMesure ? Theme.secondaire : Theme.texte).truncationMode(.tail)
            Spacer(minLength: Theme.Espace.s)
            Text(Format.pourcent(part, decimales: 1)).font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
        }
        .lineLimit(1)
        .padding(.horizontal, Theme.Espace.m)
        .padding(.vertical, Theme.Espace.s)
        .frame(maxHeight: .infinity)
        .background(alignment: .leading) {
            GeometryReader { g in
                RoundedRectangle(cornerRadius: Theme.Rayon.barre, style: .continuous)
                    .fill(.white.opacity(Theme.Blanc.pilule))
                    .frame(width: g.size.width * min(part, 1))
            }
            .padding(.vertical, Theme.Espace.s)
        }
    }

    /// Le compte en gris puis le taux ; seul le compte quand la colonne n'a pas de taux.
    private func chiffre(_ s: Segment, _ c: Colonne, haut: Double?) -> some View {
        let base = s[keyPath: c.base]
        let fiable = base >= Segment.minimum
        return HStack(spacing: Theme.Espace.s) {
            if let n = c.n {
                Text(Format.entier(s[keyPath: n]))
                    .font(c.taux == nil ? Theme.Police.petit : Theme.Police.mini)
                    .foregroundStyle(c.taux == nil ? Theme.texte : Theme.secondaire)
            }
            if let t = c.taux {
                let v = s[keyPath: t]
                Taux(t: v, meilleur: fiable && v != nil && v == haut, fiable: fiable)
            }
        }
        .help(c.taux == nil ? "" : "\(c.n.map { Format.entier(s[keyPath: $0]) } ?? "") sur \(Format.entier(base))")
    }

    /// Tri par la colonne choisie, du plus haut au plus bas, les bases trop petites en dernier.
    private func trier(_ segments: [Segment]) -> [Segment] {
        guard let tri, let c = Colonne.toutes.first(where: { $0.titre == tri }) else { return segments }
        return segments.enumerated().sorted { a, b in
            let fa = a.element[keyPath: c.base] >= Segment.minimum, fb = b.element[keyPath: c.base] >= Segment.minimum
            if fa != fb { return fa }
            let ka = c.cle(a.element) ?? -1, kb = c.cle(b.element) ?? -1
            return ka != kb ? ka > kb : a.offset < b.offset
        }.map(\.element)
    }

    private func cellule<C: View>(_ largeur: CGFloat?, aligne: Alignment = .trailing, @ViewBuilder _ c: () -> C) -> some View {
        Group {
            if let largeur {
                c().frame(width: largeur, alignment: aligne)
            } else {
                c().frame(maxWidth: .infinity, alignment: aligne)
            }
        }
    }
}
