import Charts
import SwiftUI

/// L'écran d'ouverture, en trois colonnes : les réseaux à gauche, les chiffres au centre, le plan tiré de Notes à
/// droite. Au centre, le revenu brut de RevenueCat en tête puis les chiffres de la période choisie : aujourd'hui se compare à la même
/// heure une semaine avant ; 7, 30 ou 90 jours sont des jours complets jusqu'à hier, comparés à autant de jours avant.
struct EcranAccueil: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        let l = app.lectures
        let f = Fenetre(periode: app.periode, maintenant: app.maintenant)
        HStack(alignment: .top, spacing: Theme.Espace.xl) {
            PanneauReseau(ouvert: $app.reseauOuvert, comptes: l.reseau())
            Page(titre: "Accueil", sousTitre: f.sousTitre) {
                ChoixBoutique()
            } contenu: {
                heros(l, f)
                GrilleKPI(colonnes: 3) { six(l, f) }
                Rangee(poids: [1, 1]) {
                    semaine(l)
                    PanneauScore(score: l.score(jusqua: Jour.decale(Jour.cle(app.maintenant), jours: -1)))
                }
                Rangee(poids: [3, 2], hauteurDe: 0) {
                    actifs(l, f)
                    PanneauFil(evenements: l.fil(du: f.du, au: f.jour ? .distantFuture : f.au, limite: 40))
                }
                videos(l.videos(), f)
            }
            PanneauPlan(ouvert: $app.planOuvert, plan: l.plan(), taches: l.taches(),
                        erreur: l.derniersPassages()["notes"]?.erreur)
        }
    }

    /// Le revenu brut de la période en euros ; la courbe le cumule jour par jour, sur 30 jours pour aujourd'hui.
    private func heros(_ l: Lectures, _ f: Fenetre) -> HerosRevenu {
        let revenu = f.mesure(l, Metrique.revenu).map(Metrique.enEuros)
        let delta: String?
        let ton: Ton
        if f.jour {
            delta = l.valeur(Metrique.revenu, jour: Jour.decale(f.fin, jours: -1)).map { "hier " + Format.euros(Metrique.enEuros($0)) }
            ton = .neutre
        } else {
            delta = revenu.couverture ?? Format.evolution(revenu.valeur, revenu.avant)
            ton = Ton(Format.ecart(revenu.valeur, revenu.avant))
        }
        let n = f.jour ? Periode.mois.rawValue : f.n
        let points = l.revenuCumule(n, jusqua: f.fin).compactMap { p in Jour.date(p.jour).map { PointJour(date: $0, valeur: p.euros) } }
        let essais = f.mesure(l, Metrique.essais, j7: Metrique.essaisJ7).valeur
        let achats = f.mesure(l, Metrique.achats).valeur
        return HerosRevenu(valeur: revenu.valeur.map(Format.euros) ?? Format.vide,
                           delta: delta, ton: ton,
                           detail: [Format.nombre(essais, "essai"), Format.nombre(achats, "achat")].compactMap { $0 }.joined(separator: ", "),
                           jours: n, points: points)
    }

    @ViewBuilder
    private func six(_ l: Lectures, _ f: Fenetre) -> some View {
        let abonnes = f.mesure(l, Metrique.abonnes, cumul: .dernier)
        let ecartAbonnes = Format.ecart(abonnes.valeur, abonnes.avant)
        let mrr = f.mesure(l, Metrique.mrrBrut, cumul: .dernier).valeur
        CarteKPI(libelle: "Abonnés", valeur: abonnes.valeur.map(Format.entier) ?? Format.vide,
                 delta: Format.unites(ecartAbonnes), ton: Ton(ecartAbonnes), serie: abonnes.serie, grande: true,
                 note: "MRR " + (mrr.map { Format.euros(Metrique.enEuros($0)) } ?? Format.vide))

        let essais = f.mesure(l, Metrique.essais, j7: Metrique.essaisJ7)
        let ecartEssais = Format.ecart(essais.valeur, essais.avant)
        let enCours = f.mesure(l, Metrique.essaisActifs, cumul: .dernier).valeur
        CarteKPI(libelle: "Essais", valeur: essais.valeur.map(Format.entier) ?? Format.vide,
                 delta: essais.couverture ?? Format.unites(ecartEssais), ton: Ton(ecartEssais), serie: essais.serie, grande: true,
                 note: (enCours.map(Format.entier) ?? Format.vide) + " en cours")

        let installs = f.mesure(l, Metrique.installs, j7: Metrique.installsJ7)
        let conversion = installs.valeur.flatMap { $0 > 0 ? Format.pourcent((essais.valeur ?? 0) / $0) : nil }
        CarteKPI(libelle: "Installs", valeur: installs.valeur.map(Format.entier) ?? Format.vide,
                 delta: installs.couverture ?? Format.evolution(installs.valeur, installs.avant),
                 ton: Ton(Format.ecart(installs.valeur, installs.avant)), serie: installs.serie, grande: true,
                 note: (conversion ?? Format.vide) + " en essai")

        let actifs = f.mesure(l, Metrique.actifs, j7: Metrique.actifsJ7, cumul: .moyenne)
        let ronds = f.mesure(l, Metrique.ronds, j7: Metrique.rondsJ7).valeur
        CarteKPI(libelle: f.jour ? "Actifs" : "Actifs / jour", valeur: actifs.valeur.map(Format.entier) ?? Format.vide,
                 delta: actifs.couverture ?? Format.evolution(actifs.valeur, actifs.avant),
                 ton: Ton(Format.ecart(actifs.valeur, actifs.avant)), serie: actifs.serie, grande: true,
                 note: Format.nombre(ronds, "rond") ?? Format.vide)

        let vues = f.mesure(l, Metrique.vuesTikTok, j7: Metrique.vuesTikTokJ7)
        let publiees = l.publications(f.n, jusqua: f.fin).reduce(0, +)
        CarteKPI(libelle: "Vues TikTok", valeur: vues.valeur.map(Format.entier) ?? Format.vide,
                 delta: vues.couverture ?? Format.evolution(vues.valeur, vues.avant),
                 ton: Ton(Format.ecart(vues.valeur, vues.avant)), serie: vues.serie, grande: true,
                 note: (Format.nombre(publiees, "vidéo") ?? Format.vide) + (publiees < 2 ? " publiée" : " publiées"))

        if let (cle, ligne) = l.rangPrincipal() {
            let gain = ligne.gain(cle).map(Double.init)
            let aujourdhui = Jour.cle(app.maintenant)
            let note = Cumul.dernier.de(l.jours(Metrique.note, 7, jusqua: aujourdhui))
            let avis = Cumul.dernier.de(l.jours(Metrique.nbNotes, 7, jusqua: aujourdhui))
            CarteKPI(libelle: "Rang \(Classements.nomGenre(cle.genre)) \(cle.pays.uppercased())",
                     valeur: ligne.rangs[cle].map(Format.rang) ?? (ligne.lu == nil ? Format.vide : "hors top"),
                     delta: Format.unites(gain), ton: Ton(gain),
                     serie: l.rangJours(ligne.id, cle, f.jour ? 14 : f.n), inverse: true, grande: true,
                     note: note.map { "note " + Format.decimal($0, 2) + (avis.map { ", " + Format.entier($0) + " avis" } ?? "") }
                        ?? Format.vide)
        }
    }

    /// Le revenu brut jour par jour du lundi au dimanche contre la semaine d'avant, et les cumuls depuis lundi.
    private func semaine(_ l: Lectures) -> some View {
        let aujourdhui = Jour.cle(app.maintenant)
        let jours = Jour.semaine(de: aujourdhui)
        let courante = jours.firstIndex(of: aujourdhui) ?? jours.count - 1
        let dimanche = jours.last ?? aujourdhui
        func revenu(_ fin: String) -> [Double?] { l.jours(Metrique.revenu, 7, jusqua: fin).map { $0.map(Metrique.enEuros) } }
        func depuisLundi(_ v: [Double?]) -> Double? { Cumul.somme.de(Array(v.prefix(courante + 1))) }
        let a = revenu(dimanche), b = revenu(Jour.decale(dimanche, jours: -7))
        let devant = Color.white.opacity(Theme.Blanc.barre), fantome = Color.white.opacity(Theme.Blanc.repere)
        return Bloc(titre: "Cette semaine") {
            Legende(items: [("Revenu", devant), ("Semaine d'avant", fantome)])
        } contenu: {
            HStack(alignment: .top, spacing: Theme.Espace.panneau) {
                miniChiffre("Revenu", depuisLundi(a).map(Format.euros))
                miniChiffre("Essais", depuisLundi(l.jours(Metrique.essais, 7, jusqua: dimanche)).map(Format.entier))
                miniChiffre("Achats", depuisLundi(l.jours(Metrique.achats, 7, jusqua: dimanche)).map(Format.entier))
            }
            Spacer(minLength: 0)
            Barres(valeurs: a, avant: b, courante: courante,
                   axe: ["L", "M", "M", "J", "V", "S", "D"].enumerated().map { (index: $0.offset, texte: $0.element) }) { i in
                "\(Format.jourCourt(cle: jours[i])) : \(a[i].map(Format.euros) ?? Format.vide), "
                    + "semaine d'avant \(b[i].map(Format.euros) ?? Format.vide)"
            }
        }
    }

    private func miniChiffre(_ libelle: String, _ valeur: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Text(libelle).surtitre()
            Text(valeur ?? Format.vide)
                .font(Theme.Police.grand)
                .monospacedDigit()
                .foregroundStyle(Theme.texte)
                .contentTransition(.numericText())
        }
    }

    /// Aujourd'hui heure par heure contre le même jour une semaine avant ; sinon jour par jour contre la fenêtre d'avant.
    @ViewBuilder
    private func actifs(_ l: Lectures, _ f: Fenetre) -> some View {
        let devant = Color.white.opacity(Theme.Blanc.barre), fantome = Color.white.opacity(Theme.Blanc.repere)
        if f.jour {
            let semaine = Format.jourSemaine(app.maintenant)
            let a = l.heures(Metrique.actifsHeure, jour: f.fin)
            let b = l.heures(Metrique.actifsHeure, jour: Jour.decale(f.fin, jours: -7))
            Bloc(titre: "Actifs par heure") {
                Legende(items: [("Aujourd'hui", devant), (semaine.prefix(1).uppercased() + semaine.dropFirst() + " dernier", fantome)])
            } contenu: {
                Barres(valeurs: a, avant: b, courante: Jour.heure(app.maintenant),
                       axe: [0, 4, 8, 12, 16, 20, 23].map { (index: $0, texte: "\($0) h") }) { h in
                    "\(h) h : \(a[h].map(Format.entier) ?? Format.vide), une semaine avant \(b[h].map(Format.entier) ?? Format.vide)"
                }
            }
        } else {
            let deux = l.jours(Metrique.actifs, 2 * f.n, jusqua: f.fin)
            let a = Array(deux.suffix(f.n)), b = Array(deux.prefix(f.n))
            let jours = Jour.derniers(f.n, jusqua: f.fin)
            let reperes = Array(stride(from: 0, to: f.n - 1, by: max(f.n / 6, 1))) + [f.n - 1]
            Bloc(titre: "Actifs par jour") {
                Legende(items: [("\(f.n) derniers jours", devant), ("\(f.n) jours d'avant", fantome)])
            } contenu: {
                Barres(valeurs: a, avant: b,
                       axe: reperes.map { (index: $0, texte: Format.jourCourt(cle: jours[$0])) }) { i in
                    "\(Format.jourCourt(cle: jours[i])) : \(a[i].map(Format.entier) ?? Format.vide), "
                        + "\(f.n) jours avant : \(b[i].map(Format.entier) ?? Format.vide)"
                }
            }
        }
    }

    /// Aujourd'hui, les vidéos qui ont pris des vues sur 24 h ; sur N jours, celles publiées dans la fenêtre.
    /// Les relevés de vues sont trop récents pour mesurer un gain sur une période plus longue.
    private func videos(_ toutes: [LigneVideo], _ f: Fenetre) -> PanneauVideos {
        if f.jour {
            let tournent = toutes.filter { ($0.gain24h ?? 0) > 0 }.sorted { ($0.gain24h ?? 0) > ($1.gain24h ?? 0) }
            return PanneauVideos(titre: "Vidéos qui prennent des vues", vide: "Aucune vidéo n'a pris de vues sur 24 h.",
                                 videos: Array(tournent.prefix(8)))
        }
        let publiees = toutes.filter { $0.publieeLe.map { $0 >= f.du && $0 < f.au } ?? false }
        return PanneauVideos(titre: "Vidéos publiées", vide: "Aucune vidéo publiée sur la période.", videos: Array(publiees.prefix(8)))
    }
}

/// Le choix de la période, en pilule de verre dans l'en-tête du revenu.
private struct ChoixPeriode: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Menu {
            Picker(selection: $app.periode) {
                ForEach(Periode.allCases, id: \.self) { Text($0.texte).tag($0) }
            } label: { EmptyView() }
                .pickerStyle(.inline)
        } label: {
            HStack(spacing: Theme.Espace.m) {
                Text(app.periode.texte)
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
        .help("Changer de période")
    }
}

/// Le revenu brut en héros : le chiffre en grand et son écart, les essais et achats de la période, l'aire du revenu
/// cumulé ; au survol, un repère et le cumul du jour visé.
private struct HerosRevenu: View {
    @Environment(AppState.self) private var app
    let valeur: String
    let delta: String?
    let ton: Ton
    let detail: String
    let jours: Int
    let points: [PointJour]
    @State private var vise: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            EnTetePanneau(titre: "Revenu") { ChoixPeriode() }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.xxl) {
                Chiffre(texte: valeur)
                    .heros()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let delta { Pastille(texte: delta, couleur: ton.couleur, police: Theme.Police.label) }
            }
            HStack(spacing: Theme.Espace.m) {
                Text(detail.isEmpty ? Format.vide : detail).font(Theme.Police.corps).foregroundStyle(Theme.secondaire)
                Spacer(minLength: Theme.Espace.m)
                Button { app.ecran = .data } label: {
                    HStack(spacing: Theme.Espace.s) {
                        Text("Tous les chiffres")
                        Image(systemName: "arrow.right").font(Theme.Police.fleche)
                    }
                    .font(Theme.Police.petit)
                    .foregroundStyle(Theme.secondaire)
                }
                .buttonStyle(.appui)
            }
            courbe
            Text("Brut cumulé sur \(jours) jours, TVA et commission Apple comprises").font(Theme.Police.tag).foregroundStyle(Theme.tertiaire)
        }
        .padding(Theme.Espace.panneau)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }

    @ViewBuilder
    private var courbe: some View {
        if points.count > 1, let bas = points.map(\.valeur).min(), let haut = points.map(\.valeur).max() {
            // l'aire part d'un plancher sous le plus bas, pas de zéro : la courbe garde son relief
            let marge = max((haut - bas) * 0.3, 1)
            let plancher = bas - marge
            let choisi = points.first { $0.date == vise }
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Jour", p.date), yStart: .value("Plancher", plancher), yEnd: .value("Revenu", p.valeur))
                        .foregroundStyle(Theme.lavis)
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Jour", p.date), y: .value("Revenu", p.valeur))
                        .foregroundStyle(Theme.accent)
                        .lineStyle(Theme.trait)
                        .interpolationMethod(.monotone)
                }
                if let p = choisi {
                    RuleMark(x: .value("Jour", p.date))
                        .foregroundStyle(.white.opacity(Theme.Blanc.serie))
                        .lineStyle(Theme.viseur)
                }
                if let p = choisi ?? points.last {
                    PointMark(x: .value("Jour", p.date), y: .value("Revenu", p.valeur))
                        .symbol { Point(couleur: Theme.accent) }
                        .annotation(position: .top, spacing: Theme.Espace.m,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if choisi != nil { bulle(p) }
                        }
                }
            }
            .chartYScale(domain: plancher...(haut + marge / 2))
            .chartXAxis { axeDates(.stride(by: .day, count: max(points.count / 5, 1))) }
            .chartYAxis { axeNombres { Format.entier($0) + " €" } }
            .chartOverlay { proxy in
                GeometryReader { g in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            guard case let .active(lieu) = phase, let cadre = proxy.plotFrame,
                                  let d = proxy.value(atX: lieu.x - g[cadre].origin.x, as: Date.self) else {
                                vise = nil
                                return
                            }
                            let proche = points.min { abs($0.date.timeIntervalSince(d)) < abs($1.date.timeIntervalSince(d)) }?.date
                            if proche != vise { vise = proche }
                        }
                }
            }
            .frame(height: Theme.Taille.graphiqueHeros)
            .revele()
            .animation(Theme.Anim.survol, value: vise)
            .sensoryFeedback(.alignment, trigger: vise)
            .environment(\.calendar, Jour.calendrier)
            .environment(\.timeZone, Jour.fuseau)
        } else {
            Vide(texte: "RevenueCat n'a pas encore écrit deux jours de revenu.")
                .frame(height: Theme.Taille.graphiqueHeros)
        }
    }

    private func bulle(_ p: PointJour) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(Format.jourCourt(p.date)).font(Theme.Police.tag).foregroundStyle(Theme.tertiaire)
            Text(Format.euros(p.valeur)).font(Theme.Police.corpsGras).monospacedDigit().foregroundStyle(Theme.texte)
        }
        .padding(.horizontal, Theme.Espace.l)
        .padding(.vertical, Theme.Espace.m)
        .background(Theme.releve, in: RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous)
                .strokeBorder(.white.opacity(Theme.Blanc.bordFort), lineWidth: 1)
        }
    }
}

/// Le score de la semaine : un radar des axes sur 100, leur moyenne et l'axe le plus bas.
private struct PanneauScore: View {
    let score: Score

    var body: some View {
        Bloc(titre: "Score") {
            Text("7 j contre 7 j").font(Theme.Police.tag).foregroundStyle(Theme.tertiaire)
        } contenu: {
            Radar(axes: score.axes)
                .frame(maxWidth: .infinity)
                .frame(height: Theme.Taille.radar)
                .help(score.axes.map { "\($0.nom) : \($0.note.map(String.init) ?? Format.vide)" }.joined(separator: ", "))
            HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
                Text(score.global.map(String.init) ?? Format.vide)
                    .font(Theme.Police.kpi)
                    .monospacedDigit()
                    .foregroundStyle(Theme.texte)
                    .contentTransition(.numericText())
                Text("/ 100").font(Theme.Police.petit).foregroundStyle(Theme.tertiaire)
                Spacer(minLength: Theme.Espace.m)
                Text(faible)
                    .font(Theme.Police.petit)
                    .foregroundStyle(Theme.secondaire)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
        }
    }

    private var faible: String {
        if let f = score.faible, let n = f.note { return "Point faible : \(f.nom.lowercased()), \(n) % de la semaine d'avant" }
        return score.global == nil ? "Pas encore deux semaines relevées." : "Tout tient ou progresse."
    }
}

/// Un radar : deux anneaux, un rayon par axe, le polygone des notes ; un axe sans note reste au centre, son nom grisé.
private struct Radar: View {
    let axes: [AxeScore]

    var body: some View {
        Canvas { ctx, taille in
            let n = axes.count
            guard n > 2 else { return }
            let centre = CGPoint(x: taille.width / 2, y: taille.height / 2)
            // la place des libellés autour du radar
            let r = taille.height / 2 - Theme.Espace.xxl - Theme.Espace.xl
            func angle(_ i: Int) -> Double { -.pi / 2 + 2 * .pi * Double(i) / Double(n) }
            func point(_ i: Int, _ part: Double) -> CGPoint {
                CGPoint(x: centre.x + r * part * cos(angle(i)), y: centre.y + r * part * sin(angle(i)))
            }
            func polygone(_ parts: [Double]) -> Path {
                Path { p in
                    p.move(to: point(0, parts[0]))
                    for i in 1..<parts.count { p.addLine(to: point(i, parts[i])) }
                    p.closeSubpath()
                }
            }
            let grille = GraphicsContext.Shading.color(.white.opacity(Theme.Blanc.grille))
            for anneau in [0.5, 1] { ctx.stroke(polygone(Array(repeating: anneau, count: n)), with: grille, lineWidth: 1) }
            for i in 0..<n {
                ctx.stroke(Path { p in p.move(to: centre); p.addLine(to: point(i, 1)) }, with: grille, lineWidth: 1)
            }
            let notes = polygone(axes.map { Double($0.note ?? 0) / 100 })
            ctx.fill(notes, with: .color(.white.opacity(Theme.Blanc.selection)))
            ctx.stroke(notes, with: .color(Theme.accent), style: Theme.trait)
            for (i, axe) in axes.enumerated() {
                let a = angle(i)
                ctx.draw(Text(axe.nom).font(Theme.Police.tag).foregroundStyle(axe.note == nil ? Theme.tertiaire : Theme.secondaire),
                         at: point(i, 1 + Theme.Espace.xl / r),
                         anchor: UnitPoint(x: 0.5 - 0.5 * cos(a), y: 0.5 - 0.5 * sin(a)))
            }
        }
    }
}

/// Le panneau vidéos de l'Accueil : un clic ouvre le détail dans l'écran Vidéos.
private struct PanneauVideos: View {
    @Environment(AppState.self) private var app
    let titre: String
    let vide: String
    let videos: [LigneVideo]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EnTetePanneau(titre: titre) { PastilleSeuil() }
                .padding(.horizontal, Theme.Espace.panneau)
                .padding(.bottom, Theme.Espace.l)
            if videos.isEmpty {
                Vide(texte: vide)
            } else {
                TableVideos(videos: videos, maintenant: app.maintenant) { v in
                    app.videoChoisie = v.id
                    app.ecran = .videos
                }
                .padding(.horizontal, Theme.Espace.l)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Espace.xxl)
        .padding(.bottom, Theme.Espace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }
}
