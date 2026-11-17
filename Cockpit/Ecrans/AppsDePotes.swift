import Charts
import SwiftUI

/// Où sont nos apps et celles des potes dans le top 200 de l'App Store, pays par pays : rang au dernier passage et
/// gain depuis la veille, courbe sur 30 jours de l'app choisie, ajout et arrêt du suivi.
struct AppsDePotes: View {
    @Environment(AppState.self) private var app
    @State private var liste = Liste.gratuit
    @State private var toutesCategories = false
    @State private var choisie: String?
    @State private var paysCourbe: String?

    var body: some View {
        let l = app.lectures
        let lignes = l.apps()
        let pays = paysSuivis
        let ligne = lignes.first { $0.id == choisie } ?? lignes.first
        Page(titre: "Apps de potes", sousTitre: sousTitre(lignes, pays)) {
            Bloc(titre: "Top 200") {
                HStack(spacing: Theme.Espace.m) {
                    Segmente(options: Liste.allCases.map { ($0.nom, $0) }, choix: $liste)
                    Segmente(options: [("Sa catégorie", false), ("Toutes", true)], choix: $toutesCategories)
                }
            } contenu: {
                if lignes.first?.lu == nil {
                    Vide(texte: "La source Classements n'a encore rien lu.")
                } else {
                    TableClassements(lignes: lignes, pays: pays, cle: cle, choisie: ligne?.id) { choisie = $0 }
                }
                AjoutApp { choisie = $0 }
            }
            if let ligne, ligne.lu != nil, !pays.isEmpty {
                let p = paysCourbe.flatMap { pays.contains($0) ? $0 : nil } ?? pays[0]
                Rangee(poids: [2, 1]) {
                    Bloc(titre: "Rang sur 30 jours") {
                        Segmente(options: pays.map { ($0.uppercased(), $0) },
                                choix: Binding(get: { p }, set: { paysCourbe = $0 }))
                    } contenu: {
                        let c = cle(ligne.app, p)
                        Text("\(ligne.app.nom), \(liste.rawValue), \(Classements.nomGenre(c.genre)), \(Classements.nomPays(p))")
                            .font(Theme.Police.petit)
                            .foregroundStyle(Theme.secondaire)
                            .lineLimit(1)
                        CourbeRang(valeurs: l.rangJours(ligne.id, c, 30), jusqua: Jour.cle(app.maintenant))
                    }
                    DetailApp(ligne: ligne, pays: pays, genre: cle(ligne.app, p).genre)
                }
            }
        }
    }

    /// Les pays des business affichés, dans l'ordre de leur config.
    private var paysSuivis: [String] {
        var r: [String] = []
        for p in app.affiches.flatMap(\.config.pays) where !r.contains(p) { r.append(p) }
        return r
    }

    /// Le classement d'une app dans un pays : sa catégorie (celle du business pour les nôtres) ou toutes.
    private func cle(_ a: Appli, _ pays: String) -> CleRang {
        let sienne = app.tousLesBusiness.first { $0.id == a.business }?.config.genre ?? a.genre
        return CleRang(pays: pays, genre: toutesCategories ? Classements.toutesCategories : sienne ?? Classements.toutesCategories,
                       liste: liste)
    }

    /// « 3 apps suivies dont 1 à nous, 4 pays, lu il y a 2 h ».
    private func sousTitre(_ lignes: [LigneApp], _ pays: [String]) -> String {
        guard !lignes.isEmpty else { return "Aucune app suivie" }
        let nous = lignes.filter(\.estANous).count
        let apps = lignes.count == 1 ? "1 app suivie" : "\(lignes.count) apps suivies"
        let lu = lignes.first?.lu.map { "lu \(Format.ilYa($0, maintenant: app.maintenant))" } ?? "jamais lu"
        return "\(apps) dont \(nous) à nous, \(pays.count) pays, \(lu)"
    }
}

/// Une ligne par app suivie, une colonne par pays : rang et gain depuis la veille. Un clic choisit l'app.
private struct TableClassements: View {
    let lignes: [LigneApp]
    let pays: [String]
    let cle: (Appli, String) -> CleRang
    let choisie: String?
    let choisir: (String) -> Void

    private static let colonne: CGFloat = 96

    var body: some View {
        VStack(spacing: Theme.Espace.xs) {
            HStack(spacing: Theme.Espace.l) {
                Text("App").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(pays, id: \.self) { p in
                    Text(Classements.nomPays(p)).lineLimit(1).frame(width: Self.colonne, alignment: .trailing)
                }
            }
            .font(Theme.Police.miniGras)
            .foregroundStyle(Theme.secondaire)
            .padding(.horizontal, Theme.Espace.l)
            .padding(.bottom, Theme.Espace.s)
            ForEach(Array(lignes.enumerated()), id: \.element.id) { i, ligne in
                Button { choisir(ligne.id) } label: {
                    HStack(spacing: Theme.Espace.l) {
                        IconeApp(id: ligne.app.id)
                        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                            HStack(spacing: Theme.Espace.m) {
                                Text(ligne.app.nom).font(Theme.Police.ligne).foregroundStyle(Theme.texte).lineLimit(1)
                                if ligne.estANous { Pastille(texte: "à nous", couleur: Theme.accent, police: Theme.Police.tag) }
                            }
                            Text(infos(ligne.app)).font(Theme.Police.mini).foregroundStyle(Theme.secondaire).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        ForEach(pays, id: \.self) { p in
                            CelluleRang(ligne: ligne, cle: cle(ligne.app, p)).frame(width: Self.colonne, alignment: .trailing)
                        }
                    }
                    .padding(.horizontal, Theme.Espace.l)
                    .padding(.vertical, Theme.Espace.m)
                    .fondBlanc(ligne.id == choisie ? Theme.Blanc.actif : i % 2 == 0 ? Theme.Blanc.ligne : 0, rayon: Theme.Rayon.ligne)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.appuiCarte)
            }
        }
    }

    /// « Tony Sanchez · Éducation · ★ 4,7 · 73 notes ».
    private func infos(_ a: Appli) -> String {
        [a.editeur, a.genre.map(Classements.nomGenre), a.note.map { "★ " + Format.decimal($0, 1) },
         a.nbNotes.map { Format.entier($0) + " notes" }].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Le rang et, dessous, les places gagnées depuis la veille : vert si l'app monte, rouge si elle descend.
private struct CelluleRang: View {
    let ligne: LigneApp
    let cle: CleRang

    var body: some View {
        if let p = ligne.rangs[cle] {
            let gain = ligne.gain(cle)
            VStack(alignment: .trailing, spacing: 0) {
                Text(Format.rang(p)).font(Theme.Police.corpsGras).foregroundStyle(Theme.texte)
                if let gain {
                    Text(gain == 0 ? "= 0" : Format.delta(Double(gain)))
                        .font(Theme.Police.mini)
                        .foregroundStyle(Ton(Double(gain)).couleur)
                }
            }
            .monospacedDigit()
        } else {
            Text(ligne.lu == nil ? Format.vide : "hors top").font(Theme.Police.petit).foregroundStyle(Theme.secondaire)
        }
    }
}

/// La meilleure place du jour sur 30 jours, 1er en haut ; un jour hors top coupe la courbe.
private struct CourbeRang: View {
    let valeurs: [Double?]
    let jusqua: String

    private var jours: [String] { Jour.derniers(valeurs.count, jusqua: jusqua) }

    /// Les jours classés, chaque suite de jours consécutifs dans son tronçon.
    private var points: [(date: Date, rang: Double, troncon: Int)] {
        var r: [(date: Date, rang: Double, troncon: Int)] = []
        var troncon = 0
        for (j, v) in zip(jours, valeurs) {
            guard let v, let d = Jour.date(j) else {
                troncon += 1
                continue
            }
            r.append((d, v, troncon))
        }
        return r
    }

    var body: some View {
        let points = points
        if let debut = jours.first.flatMap(Jour.date), let fin = jours.last.flatMap(Jour.date), !points.isEmpty {
            Chart(points.indices, id: \.self) { i in
                LineMark(x: .value("Jour", points[i].date), y: .value("Rang", points[i].rang),
                         series: .value("Tronçon", points[i].troncon))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(Theme.trait)
                PointMark(x: .value("Jour", points[i].date), y: .value("Rang", points[i].rang))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(Theme.Taille.pointCourbe)
            }
            .chartXScale(domain: debut...fin, range: .plotDimension(padding: Theme.Espace.panneau))
            .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Double.self) { d in
                // au moins 10 places d'écart, sinon un rang stable n'a pas de graduation
                guard let bas = d.min(), let haut = d.max() else { return }
                d += [max(1, bas - 5), haut + 5]
            })
            .chartXAxis { axeDates(.stride(by: .day, count: 7)) }
            .chartYAxis { axeNombres { $0 >= 1 && $0 == $0.rounded() ? Format.rang(Int($0)) : nil } }
            .frame(height: Theme.Taille.graphique)
            .revele()
        } else {
            Vide(texte: "Hors top 200 ces 30 derniers jours.")
                .frame(height: Theme.Taille.graphique)
        }
    }
}

/// L'app choisie dans chaque pays et chaque liste ; « Ne plus suivre » pour une app de pote.
private struct DetailApp: View {
    @Environment(AppState.self) private var app
    let ligne: LigneApp
    let pays: [String]
    let genre: Int

    var body: some View {
        Bloc(titre: "Tous les classements") {
            Text(Classements.nomGenre(genre)).font(Theme.Police.mini).foregroundStyle(Theme.secondaire).lineLimit(1)
        } contenu: {
            Grid(alignment: .trailing, horizontalSpacing: Theme.Espace.l, verticalSpacing: Theme.Espace.m) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(Liste.allCases, id: \.self) { l in Text(l.nom) }
                }
                .font(Theme.Police.miniGras)
                .foregroundStyle(Theme.secondaire)
                ForEach(pays, id: \.self) { p in
                    GridRow {
                        Text(Classements.nomPays(p)).font(Theme.Police.petit).foregroundStyle(Theme.texte).lineLimit(1)
                        ForEach(Liste.allCases, id: \.self) { l in
                            CelluleRang(ligne: ligne, cle: CleRang(pays: p, genre: genre, liste: l))
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if !ligne.estANous {
                Button { app.ecrire { try $0.suivre(ligne.id, false) } } label: {
                    Text("Ne plus suivre")
                        .font(Theme.Police.label)
                        .foregroundStyle(Theme.secondaire)
                        .padding(.horizontal, Theme.Espace.xl)
                        .frame(height: Theme.Taille.segment)
                        .verre(Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.appui)
                .help("Retire \(ligne.app.nom) du suivi ; ses rangs passés restent en base.")
            }
        }
    }
}

/// Le champ d'ajout : un id ou un lien App Store, l'app est cherchée puis suivie. L'erreur reste affichée.
private struct AjoutApp: View {
    @Environment(AppState.self) private var app
    let ajoutee: (String) -> Void
    @State private var saisie = ""
    @State private var enCours = false
    @State private var retour: (texte: String, erreur: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            HStack(spacing: Theme.Espace.m) {
                TextField("Id ou lien App Store d'une app de pote", text: $saisie)
                    .textFieldStyle(.plain)
                    .font(Theme.Police.ligne)
                    .foregroundStyle(Theme.texte)
                    .padding(.horizontal, Theme.Espace.xxl)
                    .frame(height: Theme.Taille.bouton)
                    .verre(Capsule())
                    .onSubmit(ajouter)
                Button(action: ajouter) {
                    HStack(spacing: Theme.Espace.s) {
                        Image(systemName: "plus").font(Theme.Police.tag)
                        Text(enCours ? "Recherche…" : "Suivre").font(Theme.Police.label)
                    }
                    .foregroundStyle(saisie.isEmpty || enCours ? Theme.secondaire : Theme.accent)
                    .padding(.horizontal, Theme.Espace.xxl)
                    .frame(height: Theme.Taille.bouton)
                    .verre(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.appui)
                .disabled(saisie.isEmpty || enCours)
            }
            if let retour {
                Text(retour.texte)
                    .font(Theme.Police.petit)
                    .foregroundStyle(retour.erreur ? Theme.ambre : Theme.secondaire)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, Theme.Espace.s)
    }

    private func ajouter() {
        guard !enCours, !saisie.isEmpty else { return }
        guard let id = Classements.idApp(saisie) else {
            retour = ("Ni un id ni un lien App Store : colle l'id (123456789) ou le lien apps.apple.com/…/id123456789.", true)
            return
        }
        enCours = true
        retour = nil
        Task {
            do {
                let a = try await Classements.ajouterApp(id, store: app.store, http: HTTP())
                saisie = ""
                retour = ("\(a.nom) suivie : ses rangs arrivent au prochain passage de Classements, ou tout de suite avec ⌘R.", false)
                ajoutee(a.id)
            } catch {
                retour = (error.localizedDescription, true)
            }
            enCours = false
            app.store.aChange()
        }
    }
}

private extension Liste {
    var nom: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}
