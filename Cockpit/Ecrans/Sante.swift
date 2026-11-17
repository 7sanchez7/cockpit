import Charts
import SwiftUI

/// L'écran Santé : les sources répondent-elles, l'IA tient-elle (reprises, 429, latence), combien coûte la journée.
struct Sante: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let l = app.lectures
        let jour = Jour.cle(app.maintenant)
        let serie = { (m: String) in l.jours(m, 14, jusqua: jour) }
        let passages = l.derniersPassages()
        let sources = app.collecteur.sources
        let pannes = sources.filter { passages[$0.id]?.etat == .erreur }.map(\.nom)
        let ok = sources.filter { passages[$0.id]?.etat == .ok }.count
        let echecs = l.valeur(Metrique.echecsIA, jour: jour)
        let echecs7 = l.jours(Metrique.echecsIA, 7, jusqua: jour).compactMap { $0 }
        let retours = l.valeur(Metrique.retoursNouveaux, jour: jour)
        Page(titre: "Santé", sousTitre: sousTitre(sources.count, pannes: pannes.count, passages: passages)) {
            GrilleKPI {
                CarteKPI(libelle: "Sources en panne", valeur: Format.entier(pannes.count),
                         delta: pannes.isEmpty ? "\(ok) ok" : pannes.joined(separator: ", "),
                         ton: pannes.isEmpty ? .positif : .negatif)
                CarteKPI(libelle: "Coût IA du jour", valeur: l.valeur(Metrique.coutIA, jour: jour).map(Format.euros) ?? Format.vide,
                         delta: l.valeur(Metrique.coutVoix, jour: jour).map(Format.dontVoix), serie: serie(Metrique.coutIA))
                CarteKPI(libelle: "Échecs IA du jour", valeur: echecs.map(Format.entier) ?? Format.vide,
                         delta: echecs7.isEmpty ? nil : "7 j : " + Format.entier(echecs7.reduce(0, +)),
                         ton: (echecs ?? 0) > 0 ? .negatif : .neutre, serie: serie(Metrique.echecsIA))
                CarteKPI(libelle: "Messages ouverts", valeur: l.valeur(Metrique.messagesOuverts, jour: jour).map(Format.entier) ?? Format.vide,
                         delta: retours.map { Format.entier($0) + ($0 > 1 ? " retours" : " retour") }, serie: serie(Metrique.messagesOuverts))
            }
            PanneauSources(passages: passages, succes: l.derniersSucces())
            Rangee(poids: [3, 2]) {
                PanneauIA()
                PanneauCout()
            }
            PanneauJournal()
        }
    }

    private func sousTitre(_ n: Int, pannes: Int, passages: [String: Passage]) -> String {
        var s = "\(n) sources, " + (pannes == 0 ? "aucune en panne" : "\(pannes) en panne")
        if let fin = passages.values.map(\.fin).max() { s += ", dernier passage " + Format.ilYa(fin, maintenant: app.maintenant) }
        if app.enPause { s += ", collecte en pause" }
        return s
    }
}

// MARK: sources

/// Une ligne par source : état, cadence, dernier passage, durée, lignes écrites, dernier succès, relance ; l'erreur dessous.
private struct PanneauSources: View {
    @Environment(AppState.self) private var app
    let passages: [String: Passage]
    let succes: [String: Date]

    private static let colonnes = [
        Colonne("Source", aligne: .leading), Colonne("Cadence", 64), Colonne("Dernier passage", 104), Colonne("Durée", 56),
        Colonne("Lignes", 64), Colonne("Dernier succès", 104), Colonne("", 96),
    ]

    var body: some View {
        Bloc(titre: "Sources") {
            Toggle(isOn: Binding(get: { app.enPause }, set: { app.enPause = $0 })) {
                Text("Collecte en pause").font(Theme.Police.petit).foregroundStyle(app.enPause ? Theme.ambre : Theme.secondaire)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(Theme.ambre)
        } contenu: {
            VStack(spacing: 0) {
                EnTeteTableau(colonnes: Self.colonnes)
                ForEach(Array(app.collecteur.sources.enumerated()), id: \.element.id) { i, s in ligne(i, s) }
            }
        }
    }

    private func ligne(_ i: Int, _ s: any Source) -> some View {
        let p = passages[s.id]
        let etat = EtatSource(passage: p, enCours: app.collecteur.enCours.contains(s.id))
        let c = Self.colonnes
        return VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            HStack(spacing: Theme.Espace.l) {
                c[0].cellule {
                    HStack(spacing: Theme.Espace.m) {
                        Point(couleur: etat.couleur)
                        Text(s.nom).font(Theme.Police.ligne).foregroundStyle(Theme.texte).lineLimit(1)
                    }
                    .help(etat.texte)
                }
                c[1].cellule { Text(Format.cadence(s.cadence)) }
                c[2].cellule {
                    Text(p.map { Format.ilYa($0.debut, maintenant: app.maintenant) } ?? Format.vide)
                        .help(p.map { Format.jourHeure($0.debut) } ?? "")
                }
                c[3].cellule { Text(p.map { Format.passage($0.fin.timeIntervalSince($0.debut)) } ?? Format.vide) }
                c[4].cellule { Text(p.map { Format.entier($0.lignes) } ?? Format.vide) }
                c[5].cellule { Text(succes[s.id].map { Format.ilYa($0, maintenant: app.maintenant) } ?? "jamais") }
                c[6].cellule { BoutonRelancer(id: s.id) }
            }
            if let p, p.etat != .ok, let erreur = p.erreur {
                Text(uneLigne(erreur))
                    .font(Theme.Police.mini)
                    .foregroundStyle(p.etat == .erreur ? Theme.ambre : Theme.secondaire)
                    .lineLimit(2)
                    .textSelection(.enabled)
                    .help(erreur)
                    .padding(.leading, Theme.Taille.point + Theme.Espace.m)
            }
        }
        .font(Theme.Police.petit)
        .monospacedDigit()
        .foregroundStyle(Theme.secondaire)
        .padding(.horizontal, Theme.Espace.l)
        .padding(.vertical, Theme.Espace.s)
        .frame(minHeight: Theme.Taille.ligneVideo)
        .fondBlanc(i % 2 == 0 ? Theme.Blanc.ligne : 0, rayon: Theme.Rayon.ligne)
    }
}

/// Relance une source tout de suite, même en pause ; tourne tant que la source est en cours.
struct BoutonRelancer: View {
    @Environment(AppState.self) private var app
    let id: String

    var body: some View {
        let enCours = app.collecteur.enCours.contains(id)
        Button { app.collecteur.relancer(id) } label: {
            HStack(spacing: Theme.Espace.s) {
                Image(systemName: "arrow.clockwise").symbolEffect(.rotate, isActive: enCours)
                Text(enCours ? "En cours" : "Relancer")
            }
            .font(Theme.Police.miniGras)
            .foregroundStyle(enCours ? Theme.secondaire : Theme.texte)
            .padding(.horizontal, Theme.Espace.l)
            .padding(.vertical, Theme.Espace.s)
            .fondBlanc(Theme.Blanc.pilule, rayon: Theme.Rayon.ligne)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appui)
        .disabled(enCours)
    }
}

// MARK: IA

/// Un fournisseur IA sur une journée.
private struct LigneIA: Identifiable {
    let id: String
    let nom: String
    let couleur: Color
    let requetes: Double
    let q429: Double
    let erreurs: Double
    let latence: Double?
}

/// Les requêtes d'un fournisseur sur une heure, une part de barre empilée.
private struct BarreIA: Identifiable {
    let heure: String
    let nom: String
    let n: Double
    var id: String { heure + nom }
}

/// L'IA d'une journée par fournisseur : requêtes et part (les reprises), 429, erreurs, latence ; les requêtes par heure empilées.
private struct PanneauIA: View {
    @Environment(AppState.self) private var app
    @State private var hier = false

    /// Une couleur par fournisseur, stable sur 14 jours, dans l'ordre des catégories ; ni vert ni rouge, réservés aux états.
    private static let palette: [Color] = [Theme.orange, Theme.bleu, Theme.aqua, Theme.violet, .white.opacity(Theme.Blanc.serie)]
    private static let colonnes = [
        Colonne("Fournisseur", aligne: .leading), Colonne("Requêtes", 72), Colonne("Part", 52), Colonne("429", 56),
        Colonne("Erreurs", 60), Colonne("Latence", 72),
    ]

    var body: some View {
        let l = app.lectures
        let aujourdhui = Jour.cle(app.maintenant)
        let jour = hier ? Jour.decale(aujourdhui, jours: -1) : aujourdhui
        let lignes = Self.lignes(l, jour: jour, couleursDepuis: Jour.decale(aujourdhui, jours: -13))
        Bloc(titre: "IA par fournisseur") {
            Segmente(options: [("Aujourd'hui", false), ("Hier", true)], choix: $hier)
        } contenu: {
            if lignes.isEmpty {
                Vide(texte: "Aucun appel IA relevé ce jour-là : la source Firebase doit tourner.")
            } else {
                tableau(lignes)
                Legende(items: lignes.map { ($0.nom, $0.couleur) })
                graphique(l, lignes, jour: jour)
            }
        }
    }

    private static func lignes(_ l: Lectures, jour: String, couleursDepuis: String) -> [LigneIA] {
        l.fournisseursIA(depuis: couleursDepuis).enumerated().compactMap { i, f -> LigneIA? in
            guard let n = l.valeur(Metrique.requetesIA(f), jour: jour), n > 0 else { return nil }
            return LigneIA(id: f, nom: Firebase.noms[f] ?? f, couleur: palette[min(i, palette.count - 1)], requetes: n,
                           q429: l.valeur(Metrique.q429IA(f), jour: jour) ?? 0,
                           erreurs: l.valeur(Metrique.erreursIA(f), jour: jour) ?? 0,
                           latence: l.valeur(Metrique.latenceIA(f), jour: jour, moyenne: true))
        }
        .sorted { $0.requetes > $1.requetes }
    }

    private func tableau(_ lignes: [LigneIA]) -> some View {
        let total = lignes.map(\.requetes).reduce(0, +)
        let c = Self.colonnes
        return VStack(spacing: 0) {
            EnTeteTableau(colonnes: c)
            ForEach(Array(lignes.enumerated()), id: \.element.id) { i, f in
                HStack(spacing: Theme.Espace.l) {
                    c[0].cellule { Text(f.nom).font(Theme.Police.ligne).foregroundStyle(Theme.texte) }
                    c[1].cellule { Text(Format.entier(f.requetes)).foregroundStyle(Theme.texte) }
                    c[2].cellule { Text(Format.pourcent(f.requetes / total)) }
                    c[3].cellule { taux(f.q429, sur: f.requetes) }
                    c[4].cellule { taux(f.erreurs, sur: f.requetes) }
                    c[5].cellule { Text(f.latence.map { Format.entier($0) + " ms" } ?? Format.vide) }
                }
                .font(Theme.Police.petit)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaire)
                .padding(.horizontal, Theme.Espace.l)
                .frame(height: Theme.Taille.ligneVideo)
                .fondBlanc(i % 2 == 0 ? Theme.Blanc.ligne : 0, rayon: Theme.Rayon.ligne)
            }
        }
    }

    /// Part d'échecs, ambre dès le premier.
    private func taux(_ n: Double, sur total: Double) -> some View {
        Text(Format.pourcent(n / total, decimales: 1))
            .foregroundStyle(n > 0 ? Theme.ambre : Theme.secondaire)
            .help(Format.entier(n) + " sur " + Format.entier(total))
    }

    private func graphique(_ l: Lectures, _ lignes: [LigneIA], jour: String) -> some View {
        let barres = lignes.flatMap { f in
            l.heures(Metrique.requetesIA(f.id), jour: jour).enumerated().compactMap { h, n -> BarreIA? in
                guard let n, n > 0 else { return nil }
                return BarreIA(heure: String(h), nom: f.nom, n: n)
            }
        }
        return Chart(barres) { b in
            BarMark(x: .value("Heure", b.heure), y: .value("Requêtes", b.n))
                .foregroundStyle(by: .value("Fournisseur", b.nom))
        }
        .chartForegroundStyleScale(domain: lignes.map(\.nom), range: lignes.map(\.couleur))
        .chartLegend(.hidden)
        .chartXScale(domain: (0..<24).map { String($0) })
        .chartXAxis {
            // une heure sur quatre ; `values:` ne filtre pas un axe de catégories
            AxisMarks { v in
                AxisValueLabel {
                    if let h = v.as(String.self), let n = Int(h), n % 4 == 0 { Text(h + " h") }
                }
                .font(Theme.Police.axe)
                .foregroundStyle(Theme.tertiaire)
            }
        }
        .chartYAxis { axeNombres(.automatic(desiredCount: 3), texte: Format.compact) }
        .frame(height: Theme.Taille.graphique)
        .revele()
    }
}

/// Le coût IA d'un jour.
private struct CoutJour: Identifiable {
    let id: String
    let euros: Double
}

/// Le coût IA des 14 derniers jours et le total du mois ; survoler une barre donne son coût et sa part de voix.
private struct PanneauCout: View {
    @Environment(AppState.self) private var app
    @State private var choisi: String?

    var body: some View {
        let l = app.lectures
        let jour = Jour.cle(app.maintenant)
        let cles = Jour.derniers(14, jusqua: jour)
        let barres = zip(cles, l.jours(Metrique.coutIA, 14, jusqua: jour)).compactMap { c, v in v.map { CoutJour(id: c, euros: $0) } }
        let mois = l.jours(Metrique.coutIA, Jour.calendrier.component(.day, from: app.maintenant), jusqua: jour).compactMap { $0 }
        let vu = choisi ?? jour
        let cout = l.valeur(Metrique.coutIA, jour: vu)
        let voix = l.valeur(Metrique.coutVoix, jour: vu)
        Bloc(titre: "Coût IA, 14 jours") {
            if !mois.isEmpty { Pastille(texte: "Ce mois : " + Format.euros(mois.reduce(0, +))) }
        } contenu: {
            if barres.isEmpty {
                Vide(texte: "Aucun coût relevé : la source Firebase doit tourner.")
            } else {
                Chart(barres) { b in
                    BarMark(x: .value("Jour", b.id), y: .value("Coût", b.euros))
                        .foregroundStyle(b.id == vu ? Theme.accent : .white.opacity(Theme.Blanc.barre))
                        .cornerRadius(Theme.Rayon.barre)
                }
                .chartXScale(domain: cles)
                .chartXSelection(value: $choisi)
                .chartXAxis {
                    // un jour sur quatre en partant d'aujourd'hui
                    AxisMarks { v in
                        AxisValueLabel {
                            if let c = v.as(String.self), let i = cles.firstIndex(of: c), (cles.count - 1 - i) % 4 == 0 {
                                Text(Format.jourCourt(cle: c))
                            }
                        }
                        .font(Theme.Police.axe)
                        .foregroundStyle(Theme.tertiaire)
                    }
                }
                .chartYAxis { axeNombres(.automatic(desiredCount: 3), texte: Format.euros) }
                .frame(height: Theme.Taille.graphique)
                .revele()
                VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                    Text("\(Format.jourCourt(cle: vu)) : \(cout.map(Format.euros) ?? Format.vide)" + (voix.map { ", " + Format.dontVoix($0) } ?? ""))
                        .font(Theme.Police.petit)
                        .monospacedDigit()
                        .foregroundStyle(Theme.texte)
                    Text("Texte et voix ; la voix suit le jour UTC.").font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
                }
            }
        }
    }
}

// MARK: journal

/// Les 30 derniers passages de la collecte, filtrables par source ; l'erreur en ambre.
private struct PanneauJournal: View {
    @Environment(AppState.self) private var app
    @State private var source: String?

    private static let colonnes = [
        Colonne("Début", 104, aligne: .leading), Colonne("Source", 136, aligne: .leading), Colonne("Durée", 52),
        Colonne("Lignes", 60), Colonne("Erreur", aligne: .leading),
    ]

    var body: some View {
        let sources = app.collecteur.sources
        let noms = Dictionary(sources.map { ($0.id, $0.nom) }, uniquingKeysWith: { a, _ in a })
        let passages = app.lectures.journal(source, limite: 30)
        let c = Self.colonnes
        Bloc(titre: "Journal") {
            Picker("Source", selection: $source) {
                Text("Toutes les sources").tag(String?.none)
                ForEach(sources, id: \.id) { s in Text(s.nom).tag(Optional(s.id)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
        } contenu: {
            if passages.isEmpty {
                Vide(texte: "Aucun passage : la collecte n'a pas encore tourné.")
            } else {
                VStack(spacing: 0) {
                    EnTeteTableau(colonnes: c)
                    ForEach(Array(passages.enumerated()), id: \.element) { i, p in
                        HStack(spacing: Theme.Espace.l) {
                            c[0].cellule { Text(Format.jourHeure(p.debut)) }
                            c[1].cellule {
                                HStack(spacing: Theme.Espace.m) {
                                    Point(couleur: EtatSource(passage: p, enCours: false).couleur)
                                    Text(noms[p.source] ?? p.source).foregroundStyle(Theme.texte).lineLimit(1)
                                }
                            }
                            c[2].cellule { Text(Format.passage(p.fin.timeIntervalSince(p.debut))) }
                            c[3].cellule { Text(Format.entier(p.lignes)) }
                            c[4].cellule {
                                Text(p.erreur.map(uneLigne) ?? "")
                                    .foregroundStyle(p.etat == .erreur ? Theme.ambre : Theme.secondaire)
                                    .lineLimit(1)
                                    .help(p.erreur ?? "")
                            }
                        }
                        .font(Theme.Police.petit)
                        .monospacedDigit()
                        .foregroundStyle(Theme.secondaire)
                        .padding(.horizontal, Theme.Espace.l)
                        .frame(height: Theme.Taille.ligneFil)
                        .fondBlanc(i % 2 == 0 ? Theme.Blanc.ligne : 0, rayon: Theme.Rayon.ligne)
                    }
                }
            }
        }
    }
}

// MARK: tableaux

/// Une colonne de tableau : largeur fixe, ou la place restante si nil.
private struct Colonne {
    let titre: String
    let largeur: CGFloat?
    let aligne: Alignment

    init(_ titre: String, _ largeur: CGFloat? = nil, aligne: Alignment = .trailing) {
        self.titre = titre
        self.largeur = largeur
        self.aligne = aligne
    }

    @ViewBuilder
    func cellule<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        if let largeur {
            c().frame(width: largeur, alignment: aligne)
        } else {
            c().frame(maxWidth: .infinity, alignment: aligne)
        }
    }
}

/// La ligne de titres d'un tableau, aux largeurs de ses colonnes.
private struct EnTeteTableau: View {
    let colonnes: [Colonne]

    var body: some View {
        HStack(spacing: Theme.Espace.l) {
            ForEach(colonnes.indices, id: \.self) { i in colonnes[i].cellule { Text(colonnes[i].titre) } }
        }
        .font(Theme.Police.miniGras.weight(.bold))
        .foregroundStyle(Theme.secondaire)
        .padding(.horizontal, Theme.Espace.l)
        .padding(.bottom, Theme.Espace.s)
    }
}

/// Une erreur sur une ligne : sauts de ligne et retraits d'un traceback repliés en espaces.
private func uneLigne(_ texte: String) -> String {
    texte.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}
