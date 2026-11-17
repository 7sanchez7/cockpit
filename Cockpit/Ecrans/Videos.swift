import Charts
import SwiftUI

/// Toutes les vidéos des comptes suivis, toutes plateformes : les comptes et leurs abonnés en haut, la grille des
/// miniatures (ou le tableau) triée et filtrée, le détail de la vidéo choisie avec son watch time.
struct Videos: View {
    @Environment(AppState.self) private var app
    @State private var tri = Tri.recentes
    @State private var plateforme: Plateforme?
    /// L'id du compte choisi dans les cartes (`tiktok:holaestony`).
    @State private var compte: String?
    @State private var grille = true

    enum Tri: String, CaseIterable {
        case recentes = "Récentes", vues = "Vues", gain = "24 h", engagement = "Engagement", conversion = "Conversion"
    }

    var body: some View {
        let l = app.lectures
        let toutes = l.videos()
        let comptes = l.comptes()
        let plateformes = Plateforme.allCases.filter { p in comptes.contains { $0.plateforme == p } }
        let filtre = plateforme.flatMap { plateformes.contains($0) ? $0 : nil }
        let choisi = compte.flatMap { id in comptes.contains { $0.id == id } ? id : nil }
        let liste = triees(toutes.filter {
            (filtre == nil || $0.plateforme == filtre) && (choisi == nil || Compte.id($0.plateforme, $0.compte) == choisi)
        })
        Page(titre: "Vidéos", sousTitre: sousTitre(l, toutes, comptes)) {
            RangeeComptes(comptes: comptes.filter { filtre == nil || $0.plateforme == filtre },
                          choisi: Binding(get: { choisi }, set: { compte = $0 }))
            Rangee(poids: [2, 1], hauteurDe: 1) {
                PanneauVideos(videos: liste, tri: $tri, grille: $grille,
                              plateformes: plateformes.count > 1 ? plateformes : [],
                              plateforme: Binding(get: { filtre }, set: { plateforme = $0; compte = nil }))
                DetailChoisi(videos: liste, toutes: toutes, lectures: l, sansCompte: comptes.isEmpty)
            }
        }
    }

    /// « 218 vidéos sur 4 comptes, 5 publiées en 7 j, dernier relevé il y a 3 min ».
    private func sousTitre(_ l: Lectures, _ toutes: [LigneVideo], _ comptes: [LigneCompte]) -> String {
        guard !comptes.isEmpty else { return "Aucun compte suivi" }
        let publiees = l.publications(7, jusqua: Jour.cle(app.maintenant)).reduce(0, +)
        let releve = toutes.map(\.releveLe).max().map { "dernier relevé \(Format.ilYa($0, maintenant: app.maintenant))" }
        return ["\(Format.entier(toutes.count)) vidéos sur \(comptes.count) comptes",
                "\(Format.entier(publiees)) publiées en 7 j", releve ?? "aucun relevé"].joined(separator: ", ")
    }

    private func triees(_ v: [LigneVideo]) -> [LigneVideo] {
        // les vidéos sans la mesure du tri passent après les autres
        func par(_ f: (LigneVideo) -> Double?) -> [LigneVideo] {
            v.sorted { (f($0) ?? -.infinity) > (f($1) ?? -.infinity) }
        }
        return switch tri {
        case .recentes: par { $0.publieeLe?.timeIntervalSince1970 }
        case .vues: par { Double($0.vues) }
        case .gain: par { $0.gain24h.map(Double.init) }
        case .engagement: par(\.engagement)
        case .conversion: par(\.conversion)
        }
    }

    /// La mesure d'une vidéo pour le tri choisi, dite en pastille sur sa miniature.
    static func mesure(_ v: LigneVideo, _ tri: Tri, maintenant: Date) -> String? {
        switch tri {
        case .recentes: v.publieeLe.map { Format.age($0, maintenant: maintenant) }
        case .vues: nil
        case .gain: v.gain24h.map { Format.delta(Double($0), compacte: true) }
        case .engagement: v.engagement.map { Format.pourcent($0, decimales: 1) }
        case .conversion: v.conversion.map { Format.decimal($0, 1) + " / 1k" }
        }
    }
}

private enum Mesure {
    static let carteCompte: CGFloat = 232
    static let avatar: CGFloat = 30
    static let caseMin: CGFloat = 150
    static let caseMax: CGFloat = 190
    static let compteur: CGFloat = 128
    static let champ: CGFloat = 240
    static let contour: CGFloat = 1.5
    static let nomPart: CGFloat = 112
    static let valeurPart: CGFloat = 40
    static let barrePart: CGFloat = 6
}

// MARK: comptes

/// Une carte par compte suivi, qui défile à l'horizontale, et la carte + pour en suivre un autre.
private struct RangeeComptes: View {
    let comptes: [LigneCompte]
    @Binding var choisi: String?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Espace.xl) {
                ForEach(comptes) { c in
                    CarteCompte(c: c, choisi: c.id == choisi) { choisi = choisi == c.id ? nil : c.id }
                }
                CarteAjout()
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .scrollIndicators(.never)
    }
}

/// Un compte : avatar, abonnés, gain sur 7 jours, courbe ; un clic filtre la grille, le clic droit l'édite.
private struct CarteCompte: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var ouvrir
    let c: LigneCompte
    let choisi: Bool
    let choisir: () -> Void

    var body: some View {
        Button(action: choisir) {
            VStack(alignment: .leading, spacing: Theme.Espace.l) {
                HStack(spacing: Theme.Espace.m) {
                    Miniature(cle: Miniatures.avatar(c.id), plateforme: c.plateforme)
                        .frame(width: Mesure.avatar, height: Mesure.avatar)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 0) {
                        Text("@" + c.handle).font(Theme.Police.label).foregroundStyle(Theme.texte).lineLimit(1)
                        Text(c.actif ? c.plateforme.nom : c.plateforme.nom + ", en pause")
                            .font(Theme.Police.mini).foregroundStyle(Theme.secondaire).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    c.plateforme.logo(Theme.Taille.logo)
                }
                HStack(alignment: .bottom, spacing: Theme.Espace.m) {
                    VStack(alignment: .leading, spacing: 0) {
                        Chiffre(texte: c.abonnes.map { Format.compact(Double($0)) } ?? Format.vide)
                            .font(Theme.Police.grand)
                            .foregroundStyle(Theme.texte)
                        Text("abonnés, \(Format.entier(c.videos)) vidéos")
                            .font(Theme.Police.mini).foregroundStyle(Theme.secondaire).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: Theme.Espace.s) {
                        if let g = c.gain7j {
                            Pastille(texte: Format.delta(Double(g), compacte: true) + " en 7 j", couleur: Ton(Double(g)).couleur)
                        }
                        Sparkline(valeurs: c.serie, couleur: Ton(c.gain7j.map(Double.init)).trait)
                    }
                }
            }
            .padding(.vertical, Theme.Espace.xl)
            .padding(.horizontal, Theme.Espace.xxl)
            .frame(width: Mesure.carteCompte)
            .verre(rayon: Theme.Rayon.carte)
            .overlay {
                if choisi {
                    RoundedRectangle(cornerRadius: Theme.Rayon.carte, style: .continuous)
                        .strokeBorder(Theme.accent, lineWidth: Mesure.contour)
                }
            }
            .opacity(c.actif ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Rayon.carte, style: .continuous))
        }
        .buttonStyle(.appuiCarte)
        .survolable()
        .help(c.releveLe.map { "Relevé \(Format.ilYa($0, maintenant: app.maintenant))" } ?? "Pas encore relevé")
        .contextMenu {
            Button("Ouvrir le profil") { URL(string: c.plateforme.profil(c.handle)).map { ouvrir($0) } }
            Button("Relever maintenant") { app.collecteur.relancer(c.plateforme.rawValue) }
            Button(c.actif ? "Mettre en pause" : "Reprendre") {
                app.ecrire { try $0.activer(compte: c.id, !c.actif) }
                if !c.actif { app.collecteur.relancer(c.plateforme.rawValue) }
            }
            Divider()
            Button("Ne plus suivre", role: .destructive) { app.ecrire { try $0.retirer(compte: c.id) } }
        }
    }
}

/// La carte + : plateforme, nom du compte ou lien de profil, business ; la source le relève aussitôt.
private struct CarteAjout: View {
    @Environment(AppState.self) private var app
    @State private var ouvert = false
    @State private var plateforme = Plateforme.tiktok
    @State private var saisie = ""
    @State private var business: String?

    var body: some View {
        Button { ouvert = true } label: {
            VStack(spacing: Theme.Espace.s) {
                Image(systemName: "plus").font(Theme.Police.symboleGrand)
                Text("Suivre un compte").font(Theme.Police.label)
            }
            .foregroundStyle(Theme.secondaire)
            .frame(width: Mesure.carteCompte / 2)
            .frame(maxHeight: .infinity)
            .verre(rayon: Theme.Rayon.carte)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Rayon.carte, style: .continuous))
        }
        .buttonStyle(.appui)
        .popover(isPresented: $ouvert, arrowEdge: .bottom) { formulaire }
    }

    private var formulaire: some View {
        let tous = app.tousLesBusiness
        let pour = business ?? app.affiches.first?.id ?? tous.first?.id
        let handle = Compte.handle(saisie)
        let pret = handle != nil && pour != nil
        return VStack(alignment: .leading, spacing: Theme.Espace.l) {
            Text("Suivre un compte").font(Theme.Police.h2).foregroundStyle(Theme.texte)
            Picker("Plateforme", selection: $plateforme) {
                ForEach(Plateforme.allCases) { Text($0.nom).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("@compte ou lien du profil", text: $saisie)
                .textFieldStyle(.plain)
                .font(Theme.Police.corps)
                .foregroundStyle(Theme.texte)
                .padding(.horizontal, Theme.Espace.xl)
                .frame(width: Mesure.champ, height: Theme.Taille.bouton)
                .fondBlanc(Theme.Blanc.pilule, rayon: Theme.Rayon.ligne)
                .onSubmit { ajouter(handle, pour) }
            if tous.count > 1 {
                Picker("Business", selection: Binding(get: { pour }, set: { business = $0 })) {
                    ForEach(tous) { Text($0.nom).tag(Optional($0.id)) }
                }
                .font(Theme.Police.petit)
            }
            HStack {
                Text(saisie.isEmpty || handle != nil ? "Relevé dans la minute." : "Nom de compte illisible.")
                    .font(Theme.Police.mini)
                    .foregroundStyle(Theme.secondaire)
                Spacer(minLength: Theme.Espace.m)
                Button { ajouter(handle, pour) } label: {
                    Text("Suivre")
                        .font(Theme.Police.corpsGras)
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, Theme.Espace.xxl)
                        .padding(.vertical, Theme.Espace.s)
                        .background(Theme.doux(Theme.accent), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.appui)
                .disabled(!pret)
                .opacity(pret ? 1 : 0.5)
            }
        }
        .padding(Theme.Espace.panneau)
    }

    private func ajouter(_ handle: String?, _ business: String?) {
        guard let handle, let business else { return }
        app.ecrire { try $0.ajouter(Compte(business: business, plateforme: plateforme, handle: handle)) }
        app.collecteur.relancer(plateforme.rawValue)
        saisie = ""
        ouvert = false
    }
}

// MARK: vidéos

/// Les vidéos filtrées, en grille de miniatures ou en tableau, qui défilent dans la hauteur du détail.
private struct PanneauVideos: View {
    @Environment(AppState.self) private var app
    let videos: [LigneVideo]
    @Binding var tri: Videos.Tri
    @Binding var grille: Bool
    /// Vide quand une seule plateforme est suivie : pas de filtre.
    let plateformes: [Plateforme]
    @Binding var plateforme: Plateforme?

    var body: some View {
        let choisie = app.videoChoisie.flatMap { id in videos.contains { $0.id == id } ? id : nil } ?? videos.first?.id
        VStack(alignment: .leading, spacing: 0) {
            EnTetePanneau(titre: "Toutes les vidéos") {
                Segmente(options: Videos.Tri.allCases.map { ($0.rawValue, $0) }, choix: $tri)
            }
            .padding(.horizontal, Theme.Espace.panneau)
            .padding(.bottom, Theme.Espace.l)
            HStack(spacing: Theme.Espace.m) {
                if !plateformes.isEmpty {
                    Segmente(options: [("Toutes", nil)] + plateformes.map { ($0.nom, Optional($0)) }, choix: $plateforme)
                }
                Spacer(minLength: 0)
                PastilleSeuil()
                Segmente(options: [("Grille", true), ("Tableau", false)], choix: $grille)
            }
            .padding(.horizontal, Theme.Espace.panneau)
            .padding(.bottom, Theme.Espace.m)
            if videos.isEmpty {
                Vide(texte: "Aucune vidéo relevée pour ce filtre.")
            } else {
                ScrollView {
                    if grille {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: Mesure.caseMin, maximum: Mesure.caseMax), spacing: Theme.Espace.l)],
                                  spacing: Theme.Espace.xl) {
                            ForEach(videos) { v in
                                Button { app.videoChoisie = v.id } label: {
                                    CaseVideo(v: v, mesure: Videos.mesure(v, tri, maintenant: app.maintenant),
                                              choisie: v.id == choisie)
                                }
                                .buttonStyle(.appuiCarte)
                                .survolable()
                            }
                        }
                        .padding(.horizontal, Theme.Espace.panneau)
                        .padding(.vertical, Theme.Espace.s)
                    } else {
                        TableVideos(videos: videos, maintenant: app.maintenant, choisie: choisie) { app.videoChoisie = $0.id }
                            .padding(.horizontal, Theme.Espace.l)
                    }
                }
                .scrollIndicators(.never)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Espace.xxl)
        .padding(.bottom, Theme.Espace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }
}

/// Une vidéo de la grille : miniature 9:16, vues en bas, glyphe de la plateforme, mesure du tri en pastille.
private struct CaseVideo: View {
    let v: LigneVideo
    let mesure: String?
    let choisie: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            Color.clear
                .aspectRatio(9 / 16, contentMode: .fit)
                .overlay { Miniature(cles: Miniatures.cles(v.id, v.plateforme), plateforme: v.plateforme) }
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.voile], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: Theme.Espace.s) {
                        Image(systemName: "play.fill").font(Theme.Police.coche)
                        Text(Format.compact(Double(v.vues))).font(Theme.Police.miniGras).monospacedDigit()
                    }
                    .foregroundStyle(.white)
                    .padding(Theme.Espace.m)
                }
                .overlay(alignment: .topTrailing) {
                    v.plateforme.logo(Theme.Taille.logoMini)
                        .padding(Theme.Espace.s)
                        .background(Theme.voile, in: Circle())
                        .padding(Theme.Espace.s)
                }
                .overlay(alignment: .topLeading) {
                    if let mesure {
                        Pastille(texte: mesure, couleur: .white, police: Theme.Police.tag)
                            .background(Theme.voile, in: Capsule())
                            .padding(Theme.Espace.s)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous)
                        .strokeBorder(choisie ? Theme.accent : .white.opacity(Theme.Blanc.grille),
                                      lineWidth: choisie ? Mesure.contour : 1)
                }
            Text(v.titre.isEmpty ? v.id : v.titre)
                .font(Theme.Police.mini)
                .foregroundStyle(choisie ? Theme.texte : Theme.secondaire)
                .lineLimit(2, reservesSpace: true)
        }
        .contentShape(Rectangle())
        .help(v.titre)
    }
}

// MARK: détail

/// Le détail de la vidéo choisie, ou de la première. Seule vue à lire `videoChoisie` avec la grille : un clic ne
/// relance ni les requêtes ni le tri de l'écran.
private struct DetailChoisi: View {
    @Environment(AppState.self) private var app
    let videos: [LigneVideo]
    /// Toutes les vidéos, filtre ignoré : le levier se mesure contre tout le compte.
    let toutes: [LigneVideo]
    let lectures: Lectures
    let sansCompte: Bool

    var body: some View {
        if let v = videos.first(where: { $0.id == app.videoChoisie }) ?? videos.first {
            let accroches = lectures.accroches()
            DetailVideo(v: v, releves: lectures.releves(v.id), analyse: lectures.analyse(v.id),
                        levier: Percee.levier(v, parmi: toutes, accroches: accroches), accroche: accroches[v.id],
                        comparable: Percee.compte(v, parmi: toutes).count >= Percee.minimum, maintenant: app.maintenant)
        } else {
            Bloc(titre: "Détail") {
                Vide(texte: sansCompte ? "Suivre un compte avec la carte +." : "Aucune vidéo relevée pour ce filtre.")
            }
        }
    }
}

/// La vidéo choisie : ce qui l'a fait percer, watch time, engagement, courbe des relevés, stats privées de sa
/// plateforme, fiche et liens. Chaque donnée garde sa place d'une vidéo à l'autre : une valeur absente s'écrit
/// « … », un graphique ou une liste absente garde sa hauteur.
private struct DetailVideo: View {
    @Environment(\.openURL) private var ouvrir
    let v: LigneVideo
    let releves: [(at: Date, vues: Int)]
    /// Les stats privées de la page Analytics, si la source les a lues.
    let analyse: (Analyse, at: Date)?
    /// La mesure qui a fait percer la vidéo, contre les autres vidéos de son compte.
    let levier: Percee.Levier?
    /// La part encore là à `Percee.accrocheS` secondes.
    let accroche: Double?
    /// Le compte a assez de vidéos vues pour chercher un levier.
    let comparable: Bool
    let maintenant: Date

    private struct Compteur {
        var libelle: String
        var valeur: String?
        /// Une part au-dessus du seuil, en blanc.
        var passe = false
        /// La mesure de percée que la case montre, entourée quand c'est le levier.
        var mesure: Percee.Mesure?
    }

    /// Au-delà, une liste de parts s'arrête : la traîne ne dit rien.
    private static let partsMax = 6
    private static let absent = "Pas encore relevé pour cette vidéo."

    private var a: Analyse { analyse?.0 ?? Analyse() }

    var body: some View {
        // pas de ScrollView ici : la rangée prend la hauteur du détail et la page défile
        Bloc(titre: "Détail") {
            HStack(spacing: Theme.Espace.m) {
                verdict
                if v.partPartages != nil || v.partEnreg != nil {
                    Pastille(texte: v.seuilAtteint ? "seuil atteint" : "sous le seuil",
                             couleur: v.seuilAtteint ? Theme.succes : Theme.secondaire)
                }
            }
        } contenu: {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                entete
                percee
                section("Visionnage", visionnage, note: notePrivee)
                section("Engagement", engagement)
                if v.plateforme == .tiktok {
                    graphique("Rétention", absent: a.retention.count > 1 ? nil : Self.absent) {
                        CourbeRetention(retention: a.retention)
                    }
                }
                graphique("Vues relevées", absent: releves.count > 1 ? nil : "Un seul relevé : la courbe se dessine au suivant.") {
                    courbe
                }
                // les blocs que la plateforme remplit, toujours les mêmes pour elle
                switch v.plateforme {
                case .tiktok:
                    graphique("7 premiers jours", absent: a.vuesParJour.isEmpty ? Self.absent : nil) { septJours }
                    HStack(alignment: .top, spacing: Theme.Espace.xl) {
                        parts("Sources de trafic", a.sources)
                        parts("Recherches", a.recherches)
                    }
                    HStack(alignment: .top, spacing: Theme.Espace.xl) {
                        parts("Âges", a.ages)
                        parts("Pays", a.pays) { Locale.current.localizedString(forRegionCode: $0) ?? $0 }
                    }
                case .facebook:
                    parts("Jalons de visionnage", a.jalons)
                case .youtube, .instagram:
                    EmptyView()
                }
            }
        }
    }

    /// Sans image : la vidéo est déjà cernée dans la grille.
    private var entete: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.s) {
            HStack(alignment: .top, spacing: Theme.Espace.m) {
                Text(v.titre.isEmpty ? v.id : v.titre)
                    .font(Theme.Police.corpsGras)
                    .foregroundStyle(Theme.texte)
                    .lineLimit(2, reservesSpace: true)
                Spacer(minLength: 0)
                lien(v.plateforme.nom, v.url.flatMap(URL.init(string:)))
                lien("Fiche", v.fiche.map { URL(fileURLWithPath: $0) })
            }
            Text(meta)
                .font(Theme.Police.petit)
                .foregroundStyle(Theme.secondaire)
                .lineLimit(1)
            HStack(spacing: Theme.Espace.m) {
                HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.s) {
                    Chiffre(texte: Format.entier(v.vues)).font(Theme.Police.grand).foregroundStyle(Theme.texte)
                    Text("vues").font(Theme.Police.petit).foregroundStyle(Theme.secondaire)
                }
                if let g = v.gain24h {
                    Pastille(texte: Format.delta(Double(g), compacte: true) + " en 24 h",
                             couleur: g > 0 ? Theme.succes : Theme.secondaire)
                }
            }
        }
    }

    /// « TikTok · @holaestony · 12 nov., J+1 · 21 s · methode-secrete ».
    private var meta: String {
        let publiee = v.publieeLe.map { "\(Format.jourCourt($0)), \(Format.age($0, maintenant: maintenant))" }
        return [v.plateforme.nom, "@" + v.compte, publiee, v.dureeS.map(Format.duree), v.format]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// La mesure qui a fait percer la vidéo, ou son meilleur atout quand elle est sous la médiane de son compte.
    private var percee: some View {
        let teinte = couleurLevier
        return VStack(alignment: .leading, spacing: Theme.Espace.s) {
            titre(levier.map { $0.percee ? "Ce qui l'a fait percer" : "Sous la médiane des vues, son meilleur atout" }
                  ?? "Ce qui l'a fait percer")
            Text(levier.map { "\($0.mesure.nom) : \($0.mesure.texte($0.valeur))" } ?? Format.vide)
                .font(Theme.Police.corpsGras)
                .foregroundStyle(teinte == Theme.secondaire ? Theme.texte : teinte)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(explication)
                .font(Theme.Police.mini)
                .foregroundStyle(Theme.secondaire)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Espace.xl)
        .padding(.vertical, Theme.Espace.l)
        .background(Theme.doux(teinte), in: RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous))
    }

    /// Vert si la vidéo a percé, rouge si elle est sous la médiane ; gris sans levier.
    private var couleurLevier: Color {
        levier.map { $0.percee ? Theme.succes : Theme.danger } ?? Theme.secondaire
    }

    /// « Mieux que 95 % des vidéos de @holaestony (médiane 50 %) ; sur ce compte, cette mesure suit les vues à 0,67. »
    private var explication: String {
        guard let l = levier else {
            return comparable ? "Aucune mesure liée aux vues de @\(v.compte) n'est au-dessus de sa médiane."
                : "Moins de \(Percee.minimum) vidéos vues sur @\(v.compte) : rien à comparer."
        }
        return "Mieux que \(Format.pourcent(l.rang)) des vidéos de @\(v.compte) (médiane \(l.mesure.court(l.mediane))) ; "
            + "sur ce compte, cette mesure suit les vues à \(Format.decimal(l.poids, 2))."
    }

    /// Le watch time des stats privées : la plateforme ne le donne qu'au propriétaire du compte.
    private var visionnage: [Compteur] {
        [
            Compteur(libelle: "Visionnage moyen", valeur: v.watchMoyenS.map { s in
                Format.duree(s) + (v.dureeS.map { " sur " + Format.duree($0) } ?? "")
            }, mesure: .visionnage),
            Compteur(libelle: "Encore là à \(Percee.accrocheS) s", valeur: accroche.map { Format.pourcent($0) }, mesure: .accroche),
            Compteur(libelle: "Complétion", valeur: v.completion.map { Format.pourcent($0, decimales: 1) }, mesure: .completion),
            Compteur(libelle: "Temps total", valeur: a.watchTotalS.map(Format.cumul)),
            Compteur(libelle: "Spectateurs", valeur: a.spectateurs.map(Format.entier)),
            Compteur(libelle: "Nouveaux spectateurs", valeur: a.nouveaux.map { Format.pourcent($0) }),
            Compteur(libelle: "Vues d'abonnés", valeur: a.abonnesPart.map { Format.pourcent($0, decimales: 1) }),
            Compteur(libelle: "Abonnés gagnés", valeur: v.abonnes.map(Format.entier)),
            Compteur(libelle: "Pour 1 000 vues", valeur: v.conversion.map { Format.decimal($0, 1) + " abonnés" }, mesure: .abonnes),
        ]
    }

    /// D'où viennent les stats privées, ou pourquoi elles manquent.
    private var notePrivee: String {
        if let at = analyse?.at { return "Stats privées relevées \(Format.ilYa(at, maintenant: maintenant))." }
        if v.watchMoyenS != nil { return "Analyse détaillée pas encore relevée : elle arrive avec le relevé du jour." }
        return switch v.plateforme {
        case .tiktok: "Pas de watch time : seul le compte TikTok connecté dans Safari a ses stats privées."
        case .youtube: "Pas de watch time : il passe par l'API YouTube Analytics, pas encore branchée."
        case .facebook: "Pas de watch time : la Page n'est pas dans le Business Suite de la session Safari."
        case .instagram: "Pas de watch time : les stats privées d'Instagram ne sont pas encore branchées."
        }
    }

    /// Les compteurs publics avec leur part des vues ; `passe` met en blanc une part au-dessus du seuil.
    private var engagement: [Compteur] {
        func part(_ n: Int?, _ m: Percee.Mesure) -> String? {
            n.map { Format.entier($0) + (m.valeur(v, accroche: nil).map { " · " + m.court($0) } ?? "") }
        }
        return [
            Compteur(libelle: "Taux d'engagement", valeur: v.engagement.map { Format.pourcent($0, decimales: 1) }),
            Compteur(libelle: "Likes", valeur: part(v.likes, .likes), mesure: .likes),
            Compteur(libelle: "Commentaires", valeur: part(v.commentaires, .commentaires), mesure: .commentaires),
            Compteur(libelle: "Partages", valeur: part(v.partages, .partages),
                     passe: (v.partPartages ?? 0) >= Lectures.seuilVideo, mesure: .partages),
            Compteur(libelle: "Enregistrements", valeur: part(v.enregistrements, .enregistrements),
                     passe: (v.partEnreg ?? 0) >= Lectures.seuilVideo, mesure: .enregistrements),
        ]
    }

    private func titre(_ t: String) -> some View {
        Text(t).font(Theme.Police.miniGras).foregroundStyle(Theme.secondaire)
    }

    /// Toutes les cases, toujours : une valeur absente s'écrit « … » ; la case du levier est entourée.
    private func section(_ t: String, _ compteurs: [Compteur], note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            titre(t)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Mesure.compteur), spacing: Theme.Espace.m)],
                      spacing: Theme.Espace.m) {
                ForEach(compteurs, id: \.libelle) { c in
                    let levier = c.mesure != nil && c.mesure == levier?.mesure
                    let forme = RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous)
                    VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                        Text(c.libelle).font(Theme.Police.mini).foregroundStyle(Theme.secondaire).lineLimit(1)
                        Text(c.valeur ?? Format.vide)
                            .font(Theme.Police.ligne)
                            .monospacedDigit()
                            .foregroundStyle(levier ? couleurLevier : c.passe ? Theme.accent : c.valeur == nil ? Theme.secondaire : Theme.texte)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Espace.l)
                    .padding(.vertical, Theme.Espace.m)
                    .background(levier ? Theme.doux(couleurLevier) : .white.opacity(Theme.Blanc.ligne), in: forme)
                    .overlay { if levier { forme.strokeBorder(couleurLevier, lineWidth: Mesure.contour) } }
                }
            }
            if let note {
                Text(note)
                    .font(Theme.Police.mini)
                    .foregroundStyle(Theme.secondaire)
                    .lineLimit(2, reservesSpace: true)
            }
        }
    }

    /// Un graphique titré, à hauteur fixe ; sans sa donnée, `absent` prend sa place.
    private func graphique(_ t: String, absent: String?, @ViewBuilder _ contenu: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            titre(t)
            Group {
                if let absent { Vide(texte: absent) } else { contenu() }
            }
            .frame(height: Theme.Taille.graphique)
        }
    }

    /// Les vues de chacun des sept premiers jours.
    private var septJours: some View {
        Chart(a.vuesParJour.indices, id: \.self) { j in
            BarMark(x: .value("Jour", "J\(j + 1)"), y: .value("Vues", a.vuesParJour[j]))
                .foregroundStyle(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Rayon.barre, style: .continuous))
        }
        .chartXAxis {
            AxisMarks { _ in AxisValueLabel().font(Theme.Police.axe).foregroundStyle(Theme.secondaire) }
        }
        .chartYAxis { axeNombres(.automatic(desiredCount: 3), texte: Format.compact) }
        .revele()
    }

    /// Une liste de parts en barres : nom, barre, pourcentage. Toujours `partsMax` lignes, les manquantes vides.
    private func parts(_ t: String, _ liste: [Analyse.Part], nom: @escaping (String) -> String = { $0 }) -> some View {
        let tries = Array(liste.sorted { $0.part > $1.part }.prefix(Self.partsMax))
        return VStack(alignment: .leading, spacing: Theme.Espace.m) {
            titre(t)
            VStack(alignment: .leading, spacing: Theme.Espace.m) {
                ForEach(0..<Self.partsMax, id: \.self) { i in
                    let p = i < tries.count ? tries[i] : Analyse.Part(nom: "", part: 0)
                    HStack(spacing: Theme.Espace.m) {
                        Text(nom(p.nom))
                            .font(Theme.Police.mini)
                            .foregroundStyle(Theme.texte)
                            .lineLimit(1)
                            .frame(width: Mesure.nomPart, alignment: .leading)
                        GeometryReader { g in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(Theme.Blanc.pilule))
                                Capsule().fill(Theme.accent).frame(width: g.size.width * min(max(p.part, 0), 1))
                            }
                        }
                        .frame(height: Mesure.barrePart)
                        Text(Format.pourcent(p.part, decimales: p.part < 0.1 ? 1 : 0))
                            .font(Theme.Police.mini)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaire)
                            .frame(width: Mesure.valeurPart, alignment: .trailing)
                    }
                    .opacity(i < tries.count ? 1 : 0)
                    .accessibilityHidden(i >= tries.count)
                }
            }
            .overlay { if tries.isEmpty { Vide(texte: Self.absent) } }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Les vues à chaque relevé.
    private var courbe: some View {
        let duree = (releves.last?.at ?? maintenant).timeIntervalSince(releves.first?.at ?? maintenant)
        return Chart(releves.indices, id: \.self) { i in
            LineMark(x: .value("Relevé", releves[i].at), y: .value("Vues", Double(releves[i].vues)))
                .foregroundStyle(Theme.accent)
                .lineStyle(Theme.trait)
                .interpolationMethod(.monotone)
            PointMark(x: .value("Relevé", releves[i].at), y: .value("Vues", Double(releves[i].vues)))
                .foregroundStyle(Theme.accent)
                .symbolSize(Theme.Taille.pointCourbe)
        }
        .chartXAxis { axeDates(.automatic(desiredCount: 4), texte: duree < 36 * 3600 ? Format.heure : Format.jourCourt) }
        .chartYAxis { axeNombres(.automatic(desiredCount: 3), texte: Format.entier) }
        .chartYScale(domain: .automatic(includesZero: false))
        .revele()
    }

    @ViewBuilder
    private var verdict: some View {
        if v.fiche == nil {
            Text("Pas de fiche").font(Theme.Police.petit).foregroundStyle(Theme.secondaire)
        } else if v.verdict {
            Pastille(texte: "verdict écrit", couleur: Theme.accent)
        } else {
            // la source Contenu ouvre la tâche de verdict 7 jours après la sortie
            let enRetard = (v.publieeLe ?? maintenant) < maintenant.addingTimeInterval(-7 * 86_400)
            Pastille(texte: "verdict à écrire", couleur: enRetard ? Theme.ambre : Theme.secondaire)
        }
    }

    private func lien(_ texte: String, _ url: URL?) -> some View {
        Button { if let url { ouvrir(url) } } label: {
            HStack(spacing: Theme.Espace.s) {
                Text(texte).font(Theme.Police.label)
                Image(systemName: "arrow.up.right").font(Theme.Police.tag)
            }
            .foregroundStyle(url == nil ? Theme.secondaire : Theme.texte)
            .padding(.horizontal, Theme.Espace.xl)
            .frame(height: Theme.Taille.segment)
            .verre(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.appui)
        .disabled(url == nil)
    }
}

/// La part des spectateurs encore là, seconde par seconde ; au survol, un curseur dit la seconde et sa part.
private struct CourbeRetention: View {
    let retention: [Double]
    @State private var seconde: Int?

    var body: some View {
        Chart {
            ForEach(retention.indices, id: \.self) { s in
                AreaMark(x: .value("Seconde", s), y: .value("Encore là", retention[s]))
                    .foregroundStyle(Theme.accent.opacity(Theme.Blanc.serie))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Seconde", s), y: .value("Encore là", retention[s]))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(Theme.trait)
                    .interpolationMethod(.monotone)
            }
            // la courbe d'une autre vidéo peut être plus courte que la seconde survolée
            if let s = seconde, retention.indices.contains(s) {
                RuleMark(x: .value("Seconde", s))
                    .foregroundStyle(.white.opacity(Theme.Blanc.trait))
                PointMark(x: .value("Seconde", s), y: .value("Encore là", retention[s]))
                    .foregroundStyle(Theme.accent)
                    .symbolSize(Theme.Taille.pointCourbe)
                    .annotation(position: .top, spacing: Theme.Espace.m,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        bulle(s)
                    }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { x in
                AxisValueLabel { if let s = x.as(Int.self) { Text("\(s) s") } }
                    .font(Theme.Police.axe)
                    .foregroundStyle(Theme.secondaire)
            }
        }
        .chartYAxis { axeNombres(.automatic(desiredCount: 3)) { Format.pourcent($0) } }
        .chartYScale(domain: 0...1)
        .chartOverlay { proxy in
            GeometryReader { g in
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let p):
                            guard let cadre = proxy.plotFrame,
                                  let x = proxy.value(atX: p.x - g[cadre].origin.x, as: Double.self) else { return }
                            seconde = min(max(Int(x.rounded()), 0), retention.count - 1)
                        case .ended:
                            seconde = nil
                        }
                    }
            }
        }
        .revele()
    }

    /// Bulle opaque : posée sur l'aire blanche, un fond translucide noyait les chiffres.
    private func bulle(_ s: Int) -> some View {
        let forme = RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            Text(Format.pourcent(retention[s], decimales: 1))
                .font(Theme.Police.h2)
                .foregroundStyle(Theme.texte)
            Text("encore là à \(s) s")
                .font(Theme.Police.mini)
                .foregroundStyle(Theme.secondaire)
        }
        .monospacedDigit()
        .padding(.horizontal, Theme.Espace.l)
        .padding(.vertical, Theme.Espace.m)
        .background(Theme.fond, in: forme)
        .overlay { forme.strokeBorder(.white.opacity(Theme.Blanc.repere)) }
        .shadow(color: .black.opacity(Theme.Blanc.ombre), radius: Theme.Espace.m, y: Theme.Espace.s)
    }
}
