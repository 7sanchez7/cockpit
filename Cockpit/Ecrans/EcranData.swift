import SwiftUI

/// Toute la data de l'app sur la période : l'argent, la conversion, l'arbre des installs, la rétention, l'usage.
/// Un build choisi remplace la période : la conversion, l'arbre et la rétention de ses installs, comparés au build d'avant.
struct EcranData: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let l = app.lectures
        let f = Fenetre(periode: app.periode, maintenant: app.maintenant)
        let builds = l.builds()
        let i = app.build.flatMap { b in builds.firstIndex { $0.numero == b } }
        let build = i.map { builds[$0] }
        // le build d'avant assez gros pour comparer
        let avant = i.flatMap { builds[($0 + 1)...].first { $0.installs >= Segment.minimum } }
        Page(titre: "Data", sousTitre: build.map { Self.sousTitre($0, avant: avant) } ?? f.sousTitre) {
            ChoixBoutique()
            ChoixBuild(builds: builds, choisi: build)
            Segmente(options: Periode.allCases.map { ($0.texte, Optional($0)) },
                     choix: Binding(get: { build == nil ? app.periode : nil },
                                    set: { app.periode = $0 ?? app.periode; app.build = nil }))
        } contenu: {
            if let build {
                conversion(l, build, avant: avant)
                arbre(l, debut: build.debut, fin: build.fin, racine: [build.filtre])
                retention(l, build, avant: avant)
            } else {
                argent(l, f)
                acquisition(l, f)
                conversion(l, f)
                arbre(l, debut: f.debut, fin: f.fin, racine: [])
                retention(l, f)
                usage(l, f)
            }
        }
    }

    /// « Build 49 (2.0.3), 919 installs du 8 au 14 nov., comparé au build 43 ».
    private static func sousTitre(_ b: Build, avant: Build?) -> String {
        "Build \(b.numero) (\(b.version)), \(Format.entier(b.installs)) installs du \(Format.jourCourt(cle: b.debut)) au "
            + "\(Format.jourCourt(cle: b.fin)), " + (avant.map { "comparé au build \($0.numero)" } ?? "aucun build d'avant à comparer")
    }

    /// « , comparés à ceux du build 43 », ou rien.
    private static func compare(_ avant: Build?) -> String { avant.map { ", comparés à ceux du build \($0.numero)" } ?? "" }

    // MARK: argent

    @ViewBuilder
    private func argent(_ l: Lectures, _ f: Fenetre) -> some View {
        let n = f.jour ? 14 : f.n, pas = max(n / 5, 1)
        TitreSection(titre: "Argent",
                     texte: "Le brut de RevenueCat, TVA et commission Apple comprises, en euros à \(Format.decimal(Metrique.eurParUSD, 2)) € le dollar.")
        GrilleKPI {
            carte("MRR", f.mesure(l, Metrique.mrrBrut, cumul: .dernier).map(Metrique.enEuros), Format.euros, delta: Self.euros)
            carte("Revenu", f.mesure(l, Metrique.revenu).map(Metrique.enEuros), Format.euros)
            carte("Abonnés", f.mesure(l, Metrique.abonnes, cumul: .dernier), Format.entier, delta: Self.unites)
            carte("Essais actifs", f.mesure(l, Metrique.essaisActifs, cumul: .dernier), Format.entier, delta: Self.unites)
            carte("Achats", f.mesure(l, Metrique.achats), Format.entier)
            carte("Revenu 28 j", f.mesure(l, Metrique.revenu28j, cumul: .dernier).map(Metrique.enEuros), Format.euros)
            carte("Coût IA", f.mesure(l, Metrique.coutIA), Format.euros, inverse: true)
            carte("Coût voix", f.mesure(l, Metrique.coutVoix), Format.euros, inverse: true)
        }
        PanneauObjectif(objectif: l.objectif(jour: Jour.cle(app.maintenant)), maintenant: app.maintenant)
        Rangee(poids: [2, 1], hauteurDe: 0) {
            VStack(spacing: Theme.Espace.xl) {
                Bloc(titre: "MRR") {
                    CourbeMRR(mrr: PointJour.serie(l.jours(Metrique.mrrBrut, n, jusqua: f.fin).map { $0.map(Metrique.enEuros) },
                                                   jusqua: f.fin), pas: pas)
                }
                Bloc(titre: "Achats par jour") {
                    BarresAchats(achats: PointJour.serie(l.jours(Metrique.achats, n, jusqua: f.fin), jusqua: f.fin),
                                 aujourdhui: Jour.date(Jour.cle(app.maintenant)), pas: pas)
                }
            }
            PanneauVentes(evenements: l.fil(du: f.du, au: f.jour ? .distantFuture : f.au, limite: 1000)
                .filter { $0.type == .achat || $0.type == .essai })
        }
    }

    // MARK: acquisition

    @ViewBuilder
    private func acquisition(_ l: Lectures, _ f: Fenetre) -> some View {
        TitreSection(titre: "Acquisition",
                     texte: "Téléchargements : comptés par le store, app ouverte ou non, avec un à trois jours de retard. Installs : premier lancement vu par PostHog. Nouveaux clients : premier lancement vu par RevenueCat.")
        GrilleKPI {
            carte("Téléchargements", f.mesure(l, Metrique.telechargements), Format.entier)
            carte("Installs", f.mesure(l, Metrique.installs, j7: Metrique.installsJ7), Format.entier)
            carte("Nouveaux clients", f.mesure(l, Metrique.nouveauxClients), Format.entier)
        }
    }

    // MARK: conversion

    @ViewBuilder
    private func conversion(_ l: Lectures, _ f: Fenetre) -> some View {
        let premier = l.premierInstall()
        let tous = premier.map { _ in l.noeud([], du: f.debut, au: f.fin) }
        // la fenêtre d'avant ne se compare que si les installs la couvrent entière
        let avant = f.avant.flatMap { a in premier.flatMap { $0 <= a.debut ? l.noeud([], du: a.debut, au: a.fin) : nil } }
        TitreSection(titre: "Conversion",
                     texte: "Les installs de la période et ce qu'ils ont fait depuis. Payant : RevenueCat les a vus payer, après un essai ou sans.")
        cartesConversion(tous, avant: avant, jours: l.parJour(du: f.jour ? Jour.decale(f.fin, jours: -13) : f.debut, au: f.fin))
        PanneauPortes(portes: l.portes(du: f.debut, au: f.fin))
    }

    @ViewBuilder
    private func conversion(_ l: Lectures, _ b: Build, avant: Build?) -> some View {
        TitreSection(titre: "Conversion",
                     texte: "Les installs du build et ce qu'ils ont fait depuis\(Self.compare(avant)). L'argent, l'acquisition, l'usage et les portes du paywall ne se découpent pas par build.")
        cartesConversion(l.noeud([b.filtre], du: b.debut, au: b.fin),
                         avant: avant.map { l.noeud([$0.filtre], du: $0.debut, au: $0.fin) },
                         jours: l.parJour([b.filtre], du: b.debut, au: b.fin))
    }

    /// Les installs et ce qu'ils ont fait, comparés à `avant`, jour d'install par jour en sparkline.
    private func cartesConversion(_ tous: Segment?, avant: Segment?, jours: [Segment]) -> some View {
        let chiffres = { (v: (Segment) -> Double?) in Chiffres(valeur: tous.flatMap(v), avant: avant.flatMap(v), serie: jours.map(v)) }
        return GrilleKPI {
            carte("Installs", chiffres { Double($0.installs) }, Format.entier)
            let paywall = chiffres { Double($0.paywall) }
            CarteKPI(libelle: "Paywall vu", valeur: paywall.valeur.map(Format.entier) ?? Format.vide,
                     delta: tous?.paywallVu.map { Format.pourcent($0) + " des installs" }, serie: paywall.serie)
            carte("Essais gratuits", chiffres { Double($0.essais) }, Format.entier)
            carte("Payants", chiffres { Double($0.payants) }, Format.entier)
            carte("Install → essai", chiffres(\.essai), Self.taux, delta: Format.points)
            carte("Install → payant", chiffres(\.payant), Self.taux, delta: Format.points)
            carte("Essai → payant", chiffres(\.essaiVersPayant), Self.taux, delta: Format.points)
            carte("Retour J1", chiffres(\.retourJ1), Self.taux, delta: Format.points)
        }
    }

    // MARK: arbre

    @ViewBuilder
    private func arbre(_ l: Lectures, debut: String, fin: String, racine: [Filtre]) -> some View {
        TitreSection(titre: "Arbre des installs",
                     texte: "Clique une marche, un écran du tunnel ou une valeur pour descendre ; le chemin du haut remonte. Chaque nœud dit combien de ses installs prennent l'essai et paient, et l'écart en points avec le nœud du dessus.")
        ArbreInstalls(l: l, debut: debut, fin: fin, racine: racine)
    }

    // MARK: rétention

    @ViewBuilder
    private func retention(_ l: Lectures, _ f: Fenetre) -> some View {
        let taille = f.jour ? 7 : f.n
        let cohortes = l.cohortes(du: Jour.decale(f.fin, jours: -(2 * taille + 32)), au: f.fin)
        TitreSection(titre: "Rétention",
                     texte: "Installs qui finissent un rond N jours après : les \(taille) dernières cohortes complètes, comparées aux \(taille) d'avant. Mesuré depuis le \(Format.jourCourt(cle: PostHog.rondsDepuis)), quand les ronds ont commencé à remonter.")
        GrilleKPI {
            ForEach(TableCohortes.colonnes, id: \.titre) { c in
                let r = cohortes.retour(c.jn, taille: taille)
                retour(c.titre, c.jn, cohortes, r, avant: r?.avant)
            }
        }
        TableCohortes(cohortes: Array(cohortes.prefix(max(f.n, 35))))
    }

    @ViewBuilder
    private func retention(_ l: Lectures, _ b: Build, avant: Build?) -> some View {
        let cohortes = l.cohortes([b.filtre], du: b.debut, au: b.fin)
        let precedentes = avant.map { l.cohortes([$0.filtre], du: $0.debut, au: $0.fin) } ?? []
        TitreSection(titre: "Rétention",
                     texte: "Installs du build qui finissent un rond N jours après, sur toutes ses cohortes complètes\(Self.compare(avant)). Mesuré depuis le \(Format.jourCourt(cle: PostHog.rondsDepuis)).")
        GrilleKPI {
            ForEach(TableCohortes.colonnes, id: \.titre) { c in
                retour(c.titre, c.jn, cohortes, cohortes.retour(c.jn, taille: cohortes.count),
                       avant: precedentes.retour(c.jn, taille: precedentes.count)?.taux)
            }
        }
        TableCohortes(cohortes: cohortes)
    }

    /// Taux pondéré, écart en points avec la référence, taux de chaque cohorte en sparkline.
    private func retour(_ titre: String, _ jn: KeyPath<Cohorte, Int?>, _ cohortes: [Cohorte], _ r: TauxRetour?,
                        avant: Double?) -> CarteKPI {
        let nombre = r.map { "\($0.cohortes) cohorte\($0.cohortes > 1 ? "s" : "")" }
        return CarteKPI(libelle: "Retour \(titre)", valeur: r.map { Self.taux($0.taux) } ?? Format.vide,
                        delta: Format.points(r?.taux, avant) ?? nombre,
                        ton: Ton(Format.ecart(r?.taux, avant)), serie: cohortes.serie(jn))
    }

    // MARK: usage

    @ViewBuilder
    private func usage(_ l: Lectures, _ f: Fenetre) -> some View {
        let actifs = f.mesure(l, Metrique.actifs, j7: Metrique.actifsJ7, cumul: .moyenne)
        TitreSection(titre: "Usage et coûts", texte: "Les actifs du jour, ce qu'ils font et ce qu'ils coûtent en IA.")
        GrilleKPI {
            carte(f.jour ? "Actifs" : "Actifs / jour", actifs, Format.entier)
            carte("Ronds finis", f.mesure(l, Metrique.ronds, j7: Metrique.rondsJ7), Format.entier)
            carte("Ronds par actif", Self.ratio(f.mesure(l, Metrique.ronds, j7: Metrique.rondsJ7, cumul: .moyenne), actifs),
                  { Format.decimal($0, 2) })
            // pour 100 : par actif, il s'arrondit à 0,00 €
            carte("Coût IA / 100 actifs", Self.ratio(f.mesure(l, Metrique.coutIA, cumul: .moyenne), actifs),
                  { Format.euros($0 * 100) }, inverse: true)
        }
    }

    // MARK: outils

    private func carte(_ libelle: String, _ c: Chiffres, _ texte: (Double) -> String,
                       delta: @MainActor (Double?, Double?) -> String? = Format.evolution, inverse: Bool = false) -> CarteKPI {
        CarteKPI(libelle: libelle, valeur: c.valeur.map(texte) ?? Format.vide, delta: c.couverture ?? delta(c.valeur, c.avant),
                 ton: Ton(Format.ecart(c.valeur, c.avant), inverse: inverse), serie: c.serie)
    }

    private static func taux(_ v: Double) -> String { Format.pourcent(v, decimales: 1) }

    private static func euros(_ a: Double?, _ b: Double?) -> String? { Format.ecart(a, b).map { Format.signe($0, Format.euros) } }

    private static func unites(_ a: Double?, _ b: Double?) -> String? { Format.ecart(a, b).map { $0 == 0 ? "= 0" : Format.delta($0) } }

    /// `a` par `b`, jour par jour et sur la période ; une période couverte en partie ne compte que les jours relevés des deux.
    private static func ratio(_ a: Chiffres, _ b: Chiffres) -> Chiffres {
        func d(_ x: Double?, _ y: Double?) -> Double? {
            guard let x, let y, y > 0 else { return nil }
            return x / y
        }
        let serie = zip(a.serie, b.serie).map(d)
        guard a.jours != nil || b.jours != nil else {
            return Chiffres(valeur: d(a.valeur, b.valeur), avant: d(a.avant, b.avant), serie: serie)
        }
        let paires = zip(a.serie, b.serie).compactMap { x, y in x.flatMap { x in y.map { (x, $0) } } }
        return Chiffres(valeur: d(paires.map(\.0).reduce(0, +), paires.map(\.1).reduce(0, +)), avant: nil, serie: serie,
                        jours: paires.isEmpty ? nil : paires.count)
    }
}

/// Mesures sans jeton dans Theme.
private enum Mesure {
    static let ligne: CGFloat = 24
}

/// Le build dont Data montre les installs à la place de la période.
private struct ChoixBuild: View {
    @Environment(AppState.self) private var app
    let builds: [Build]
    let choisi: Build?

    var body: some View {
        Menu {
            Picker(selection: Binding(get: { choisi?.numero }, set: { app.build = $0 })) {
                Text("Tous les builds").tag(String?.none)
                ForEach(builds, id: \.numero) { b in
                    Text("Build \(b.numero) · \(b.version) · \(Format.entier(b.installs)) installs").tag(Optional(b.numero))
                }
            } label: { EmptyView() }
                .pickerStyle(.inline)
        } label: {
            HStack(spacing: Theme.Espace.m) {
                Text(choisi.map { "Build \($0.numero)" } ?? "Tous les builds")
                    .font(Theme.Police.ligne)
                    .foregroundStyle(Theme.texte)
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.up.chevron.down")
                    .font(Theme.Police.fleche)
                    .foregroundStyle(Theme.tertiaire)
            }
            .lineLimit(1)
            .padding(.horizontal, Theme.Espace.xl)
            .frame(height: Theme.Taille.bouton)
            .verre(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .buttonStyle(.appui)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Voir les installs d'un seul build")
    }
}

/// Le titre d'une section de l'écran Data et ce qu'elle mesure.
private struct TitreSection: View {
    let titre: String
    let texte: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(titre).font(Theme.Police.grand).foregroundStyle(Theme.texte)
            Text(texte).font(Theme.Police.petit).foregroundStyle(Theme.secondaire)
        }
        .padding(.top, Theme.Espace.xl)
    }
}

private func entete(_ texte: String) -> some View {
    Text(texte).font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
}

/// Le meilleur taux d'une colonne, s'il y a au moins deux lignes assez grandes pour comparer et qu'il dépasse zéro.
func meilleur(_ taux: [Double?]) -> Double? {
    let t = taux.compactMap { $0 }
    return t.count >= 2 ? t.max().flatMap { $0 > 0 ? $0 : nil } : nil
}

/// Un taux : blanc et gras s'il est le meilleur, gris si sa base est trop petite.
struct Taux: View {
    let t: Double?
    let meilleur: Bool
    let fiable: Bool

    var body: some View {
        Text(t.map { Format.pourcent($0, decimales: 1) } ?? Format.vide)
            .font(meilleur ? Theme.Police.miniGras : Theme.Police.mini)
            .foregroundStyle(meilleur ? Theme.accent : fiable ? Theme.texte : Theme.secondaire)
            .help(fiable ? "" : "Moins de \(Segment.minimum) installs : taux fragile")
    }
}

/// Les portes d'où s'ouvre le paywall, leurs vues et ce qu'elles convertissent.
private struct PanneauPortes: View {
    let portes: [LignePorte]

    var body: some View {
        Bloc(titre: "Portes du paywall") {
            Text("d'où il s'ouvre").font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
        } contenu: {
            if portes.isEmpty {
                Vide(texte: "Aucune vue du paywall sur la période.")
            } else {
                let haut = meilleur(portes.map { $0.vues >= Segment.minimum ? $0.conversion : nil })
                Grid(alignment: .trailing, horizontalSpacing: Theme.Espace.m, verticalSpacing: Theme.Espace.xs) {
                    GridRow {
                        entete("Porte").gridColumnAlignment(.leading)
                        entete("Vues")
                        entete("Essais")
                        entete("Directs")
                        entete("Conv.")
                    }
                    ForEach(portes, id: \.porte) { p in
                        let fiable = p.vues >= Segment.minimum
                        GridRow {
                            Text(p.nom).foregroundStyle(Theme.texte).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text(Format.entier(p.vues))
                            Text(Format.entier(p.essais))
                            Text(Format.entier(p.directs))
                            Taux(t: p.conversion, meilleur: fiable && p.conversion != nil && p.conversion == haut, fiable: fiable)
                        }
                        .frame(minHeight: Mesure.ligne)
                    }
                }
                .font(Theme.Police.mini)
                .monospacedDigit()
                .foregroundStyle(Theme.texte)
            }
        }
    }
}
