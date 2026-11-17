import SwiftUI

/// L'écran SAV, le dashboard admin de Roleo dans le cockpit : les fils avec les users et la réponse qui part avec sa
/// notif, les retours à traiter ; dessous, les autres tâches, l'ajout à la main et les faites.
struct SAV: View {
    @Environment(AppState.self) private var app

    /// Le haut de l'écran, où remonter quand on répond à un retour.
    private static let haut = "fils"

    var body: some View {
        let l = app.lectures
        let aujourdhui = Jour.cle(app.maintenant)
        let fils = l.filsSAV()
        let cle = app.filChoisi ?? fils.first?.cle
        let groupes = Genre.ranger(l.taches(), aujourdhui: aujourdhui)
        ScrollViewReader { defilement in
            Page(titre: "SAV", sousTitre: sousTitre(l.nbSAV())) {
                OutilsSAV()
            } contenu: {
                Rangee(poids: [2, 3], hauteurDe: 1) {
                    PanneauFils(fils: fils, choisi: cle)
                    PanneauConversation(cle: cle).id(cle)
                }
                .id(Self.haut)
                Rangee(poids: [3, 2]) {
                    PanneauRetours { c in
                        app.filChoisi = c
                        withAnimation(Theme.Anim.navigation) { defilement.scrollTo(Self.haut, anchor: .top) }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    VStack(spacing: Theme.Espace.xl) {
                        if groupes.isEmpty {
                            PanneauRien()
                        } else {
                            ForEach(groupes, id: \.genre) { g in
                                PanneauGroupe(genre: g.genre, taches: g.taches, aujourdhui: aujourdhui)
                            }
                        }
                        PanneauAjout()
                        PanneauFaites(taches: l.tachesFaites(jours: 7).filter { Genre($0) != nil })
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
            }
        }
    }

    private func sousTitre(_ n: (fils: Int, retours: Int)) -> String {
        let morceaux = [
            n.fils > 0 ? "\(n.fils) " + (n.fils > 1 ? "fils à répondre" : "fil à répondre") : nil,
            n.retours > 0 ? "\(n.retours) " + (n.retours > 1 ? "retours à traiter" : "retour à traiter") : nil,
        ].compactMap { $0 }
        return morceaux.isEmpty ? "Rien à répondre" : morceaux.joined(separator: ", ")
    }
}

/// Quand Firebase a lu le SAV pour la dernière fois, et la relance.
private struct OutilsSAV: View {
    @Environment(AppState.self) private var app

    var body: some View {
        let p = app.lectures.derniersPassages()[Firebase.idSource]
        HStack(spacing: Theme.Espace.m) {
            Point(couleur: EtatSource(passage: p, enCours: app.collecteur.enCours.contains(Firebase.idSource)).couleur)
            Text(p.map { "lu " + Format.ilYa($0.fin, maintenant: app.maintenant) } ?? "jamais lu")
                .font(Theme.Police.petit)
                .foregroundStyle(Theme.secondaire)
                .help(p?.erreur ?? "")
            BoutonRelancer(id: Firebase.idSource)
        }
    }
}

// MARK: fils

/// Les fils, ceux à répondre d'abord ; un clic ouvre la conversation.
private struct PanneauFils: View {
    @Environment(AppState.self) private var app
    let fils: [FilSAV]
    let choisi: CleFil?

    var body: some View {
        Panneau(titre: "Fils") {
            Pastille(texte: Format.entier(fils.count))
        } contenu: {
            if fils.isEmpty {
                Vide(texte: "Aucun fil. Un message écrit depuis l'app arrive ici au passage suivant de Firebase.")
                    .frame(maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Theme.Espace.xs) {
                        ForEach(fils) { f in
                            LigneFilSAV(fil: f, choisi: f.cle == choisi) { app.filChoisi = f.cle }
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct LigneFilSAV: View {
    @Environment(AppState.self) private var app
    let fil: FilSAV
    let choisi: Bool
    let choisir: () -> Void

    var body: some View {
        Button(action: choisir) {
            VStack(alignment: .leading, spacing: Theme.Espace.s) {
                HStack(spacing: Theme.Espace.m) {
                    Text(nomCompte(fil.nom, fil.email))
                        .font(Theme.Police.ligne)
                        .foregroundStyle(Theme.texte)
                        .lineLimit(1)
                    Spacer(minLength: Theme.Espace.m)
                    Text(Format.ilYa(fil.dernierAt, maintenant: app.maintenant))
                        .font(Theme.Police.mini)
                        .foregroundStyle(Theme.tertiaire)
                }
                HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
                    Text((fil.dernierEquipe ? "Équipe : " : "") + fil.apercu)
                        .font(Theme.Police.petit)
                        .foregroundStyle(Theme.secondaire)
                        .lineLimit(2)
                    Spacer(minLength: Theme.Espace.m)
                    Pastille(texte: fil.etat.texte, couleur: fil.etat.couleur)
                }
            }
            .padding(.horizontal, Theme.Espace.l)
            .padding(.vertical, Theme.Espace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fondBlanc(choisi ? Theme.Blanc.selection : 0, rayon: Theme.Rayon.ligne)
            .contentShape(Rectangle())
        }
        .buttonStyle(.appui)
    }
}

// MARK: conversation

/// Le fil choisi en entier et la réponse, qui part dans l'app avec une notif.
private struct PanneauConversation: View {
    @Environment(AppState.self) private var app
    let cle: CleFil?
    @State private var texte = ""
    @State private var enCours = false
    @State private var resultat: Resultat?

    private struct Resultat {
        let texte: String
        let erreur: Bool
    }

    var body: some View {
        let fil = cle.flatMap(app.lectures.filSAV)
        Panneau(titre: "Conversation") {
            if let fil { Pastille(texte: fil.etat.texte, couleur: fil.etat.couleur) }
        } contenu: {
            if let cle {
                VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                    enTete(cle, fil)
                    Bulles(messages: app.lectures.messagesSAV(cle))
                    reponse(cle, ouvert: fil?.ouvert == true)
                }
            } else {
                Vide(texte: "Choisis un fil ou un retour pour lui répondre.")
                    .frame(height: Theme.Taille.conversation, alignment: .top)
            }
        }
    }

    private func enTete(_ cle: CleFil, _ fil: FilSAV?) -> some View {
        let email = fil?.email ?? app.lectures.emailSAV(cle)
        return VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(nomCompte(fil?.nom, email)).font(Theme.Police.h2).foregroundStyle(Theme.texte)
            Text([email, cle.uid].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "))
                .font(Theme.Police.mini)
                .foregroundStyle(Theme.tertiaire)
                .textSelection(.enabled)
        }
    }

    private func reponse(_ cle: CleFil, ouvert: Bool) -> some View {
        let n = texte.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count
        let pret = Firebase.reponse(texte) != nil && !enCours
        return VStack(alignment: .leading, spacing: Theme.Espace.m) {
            TextEditor(text: $texte)
                .font(Theme.Police.corps)
                .foregroundStyle(Theme.texte)
                .scrollContentBackground(.hidden)
                .padding(Theme.Espace.m)
                .frame(height: Theme.Taille.reponse)
                .fondBlanc(Theme.Blanc.pilule, rayon: Theme.Rayon.ligne)
                .overlay(alignment: .topLeading) {
                    if texte.isEmpty {
                        Text("Ta réponse, elle arrive dans l'app avec une notif")
                            .font(Theme.Police.corps)
                            .foregroundStyle(Theme.tertiaire)
                            .padding(.horizontal, Theme.Espace.m + Theme.Espace.s)
                            .padding(.vertical, Theme.Espace.m)
                            .allowsHitTesting(false)
                    }
                }
                .disabled(enCours)
            HStack(spacing: Theme.Espace.l) {
                Text("\(n) / \(Firebase.longueurReponse)")
                    .font(Theme.Police.mini)
                    .monospacedDigit()
                    .foregroundStyle(n > Firebase.longueurReponse ? Theme.danger : Theme.tertiaire)
                if let resultat {
                    Text(resultat.texte)
                        .font(Theme.Police.mini)
                        .foregroundStyle(resultat.erreur ? Theme.danger : Theme.secondaire)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .help(resultat.texte)
                }
                Spacer(minLength: 0)
                if ouvert {
                    BoutonPilule(texte: "Marquer traité sans répondre") {
                        agir { try await app.fermer(cle); return "Marqué traité" }
                    }
                    .disabled(enCours)
                }
                BoutonPrincipal(texte: enCours ? "Envoi…" : "Envoyer", actif: pret) {
                    agir {
                        let r = try await app.repondre(texte, a: cle)
                        texte = ""
                        return r
                    }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")
            }
        }
    }

    /// Lance une action réseau, son résultat ou son erreur sous le champ.
    private func agir(_ action: @escaping () async throws -> String) {
        enCours = true
        resultat = nil
        Task {
            do {
                resultat = Resultat(texte: try await action(), erreur: false)
            } catch {
                resultat = Resultat(texte: error.localizedDescription, erreur: true)
            }
            enCours = false
        }
    }
}

/// Les messages d'un fil, l'équipe à droite, le dernier en bas.
private struct Bulles: View {
    let messages: [MessageSAV]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Espace.l) {
                ForEach(messages) { m in Bulle(m: m) }
            }
        }
        .defaultScrollAnchor(.bottom)
        .scrollIndicators(.never)
        .frame(height: Theme.Taille.conversation)
        .overlay(alignment: .topLeading) {
            if messages.isEmpty { Vide(texte: "Le premier message part d'ici, avec une notif sur son téléphone.") }
        }
    }
}

private struct Bulle: View {
    let m: MessageSAV

    var body: some View {
        HStack(spacing: 0) {
            if m.equipe { Spacer(minLength: Theme.Espace.page) }
            VStack(alignment: m.equipe ? .trailing : .leading, spacing: Theme.Espace.xs) {
                Text(m.texte)
                    .font(Theme.Police.corps)
                    .foregroundStyle(Theme.texte)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.horizontal, Theme.Espace.xl)
                    .padding(.vertical, Theme.Espace.m)
                    .fondBlanc(m.equipe ? Theme.Blanc.selection : Theme.Blanc.pilule, rayon: Theme.Rayon.bloc)
                Text((m.equipe ? "Équipe · " : "") + Format.jourHeure(m.at))
                    .font(Theme.Police.mini)
                    .foregroundStyle(Theme.tertiaire)
            }
            if !m.equipe { Spacer(minLength: Theme.Espace.page) }
        }
    }
}

// MARK: retours

/// Les retours, à traiter d'abord ; « Répondre » ouvre le fil de son auteur.
private struct PanneauRetours: View {
    @Environment(AppState.self) private var app
    let repondre: (CleFil) -> Void
    @State private var traites: Bool? = false
    @State private var tout = false

    private static let limite = 10

    var body: some View {
        let retours = app.lectures.retoursSAV(traites: traites)
        Panneau(titre: "Retours") {
            Segmente(options: [("À traiter", false), ("Traités", true), ("Tous", nil)], choix: $traites)
        } contenu: {
            if retours.isEmpty {
                Vide(texte: traites == false ? "Aucun retour à traiter." : "Aucun retour.")
            } else {
                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    ForEach(tout ? retours : Array(retours.prefix(Self.limite))) { r in
                        CarteRetour(r: r, repondre: repondre)
                    }
                    if retours.count > Self.limite { BoutonVoir(n: retours.count, tout: $tout) }
                }
            }
        }
    }
}

private struct CarteRetour: View {
    @Environment(AppState.self) private var app
    let r: RetourSAV
    let repondre: (CleFil) -> Void
    @State private var enCours = false
    @State private var erreur: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            HStack(spacing: Theme.Espace.s) {
                Pastille(texte: r.libelleSource)
                if let c = r.libelleCategorie { Pastille(texte: c, couleur: r.souci ? Theme.ambre : Theme.secondaire) }
                if let e = r.etoiles { Pastille(texte: "\(e)/5", couleur: e <= 2 ? Theme.ambre : Theme.secondaire) }
                Spacer(minLength: Theme.Espace.m)
                Text(Format.ilYa(r.at, maintenant: app.maintenant)).font(Theme.Police.mini).foregroundStyle(Theme.tertiaire)
            }
            if let c = r.citation {
                Text("« \(c) »")
                    .font(Theme.Police.petit)
                    .italic()
                    .foregroundStyle(Theme.secondaire)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if !r.message.isEmpty {
                Text(r.message)
                    .font(Theme.Police.corps)
                    .foregroundStyle(Theme.texte)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack(spacing: Theme.Espace.m) {
                Text(pied)
                    .font(Theme.Police.mini)
                    .foregroundStyle(Theme.tertiaire)
                    .lineLimit(1)
                    .textSelection(.enabled)
                Spacer(minLength: Theme.Espace.m)
                if let erreur {
                    Text(erreur).font(Theme.Police.mini).foregroundStyle(Theme.danger).lineLimit(2).help(erreur)
                }
                if let uid = r.uid {
                    BoutonPilule(texte: "Répondre") { repondre(CleFil(business: r.business, uid: uid)) }
                }
                BoutonPilule(texte: r.traite ? "Rouvrir" : "Marquer traité") { basculer() }
                    .disabled(enCours)
            }
        }
        .padding(Theme.Espace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fondBlanc(Theme.Blanc.ligne, rayon: Theme.Rayon.bloc)
    }

    /// Le compte, l'appareil, quand il a été traité.
    private var pied: String {
        let compte = r.email?.isEmpty == false ? r.email : r.uid == nil ? "Anonyme" : "Invité"
        let appareil = [r.plateforme.map { $0 == "ios" ? "iOS" : $0 == "android" ? "Android" : $0 },
                        r.build.map { "build " + $0 }].compactMap { $0 }.joined(separator: " ")
        let traite = r.traite ? r.traiteLe.map { "traité le " + Format.jourHeure($0) } : nil
        return [compte, appareil.isEmpty ? nil : appareil, traite].compactMap { $0 }.joined(separator: " · ")
    }

    private func basculer() {
        enCours = true
        erreur = nil
        Task {
            do {
                try await app.traiter(r, !r.traite)
            } catch {
                self.erreur = error.localizedDescription
            }
            enCours = false
        }
    }
}

private extension RetourSAV {
    /// Les libellés du dashboard de Roleo.
    var libelleSource: String {
        switch source {
        case "profile": "Profil"
        case "rating": "Note"
        case "chat_report": "Signalement"
        default: "Retour"
        }
    }

    var libelleCategorie: String? {
        categorie.map {
            switch $0 {
            case "idea": "Idée"
            case "problem": "Souci"
            case "weird": "Réponse bizarre"
            case "language": "Faute ou mauvaise langue"
            case "off_topic": "Hors sujet"
            case "bug": "Bug de l'app"
            case "other": "Autre"
            default: $0
            }
        }
    }

    var souci: Bool { categorie == "problem" || categorie == "bug" }
}

private extension EtatFil {
    var texte: String {
        switch self {
        case .aRepondre: "À répondre"
        case .pasLu: "Pas encore lu"
        case .lu: "Lu"
        case .traite: "Traité"
        }
    }

    var couleur: Color {
        switch self {
        case .aRepondre: Theme.ambre
        case .pasLu: Theme.accent
        case .lu: Theme.succes
        case .traite: Theme.secondaire
        }
    }
}

/// Le nom affiché d'un compte : son prénom, sinon son email, sinon invité.
private func nomCompte(_ nom: String?, _ email: String?) -> String {
    nom ?? (email?.isEmpty == false ? email : nil) ?? "Invité"
}

// MARK: boutons

/// L'action principale d'un panneau.
private struct BoutonPrincipal: View {
    let texte: String
    var actif = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(texte)
                .font(Theme.Police.corpsGras)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, Theme.Espace.xxl)
                .padding(.vertical, Theme.Espace.s)
                .background(Theme.doux(Theme.accent), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.appui)
        .disabled(!actif)
        .opacity(actif ? 1 : 0.5)
    }
}

/// Une action secondaire, dans une pilule.
private struct BoutonPilule: View {
    let texte: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(texte)
                .font(Theme.Police.miniGras)
                .foregroundStyle(Theme.texte)
                .padding(.horizontal, Theme.Espace.l)
                .padding(.vertical, Theme.Espace.s)
                .fondBlanc(Theme.Blanc.pilule, rayon: Theme.Rayon.ligne)
                .contentShape(Rectangle())
        }
        .buttonStyle(.appui)
    }
}

/// « Voir les N », « Réduire ».
private struct BoutonVoir: View {
    let n: Int
    @Binding var tout: Bool

    var body: some View {
        Button { withAnimation(Theme.Anim.navigation) { tout.toggle() } } label: {
            Text(tout ? "Réduire" : "Voir les \(n)").font(Theme.Police.petit).foregroundStyle(Theme.accent)
        }
        .buttonStyle(.appui)
        .padding(.horizontal, Theme.Espace.m)
        .padding(.top, Theme.Espace.s)
    }
}

// MARK: autres tâches

/// En alerte, ou échéance passée.
private func urgente(_ t: LigneTache, _ aujourdhui: String) -> Bool {
    t.ton == .alerte || t.echeance.map { $0 < aujourdhui } == true
}

/// Le genre d'une tâche, lu dans son id (`asc:avis:…`, docs/donnees.md) ; nil pour un message ou un retour, que
/// les panneaux du SAV montrent déjà.
private enum Genre: Int {
    case avis, manuel, verdict, autre

    init?(_ t: LigneTache) {
        if t.source == "manuel" { self = .manuel; return }
        switch t.id.split(separator: ":").dropFirst().first {
        case "msg"?, "retour"?: return nil
        case "avis"?: self = .avis
        case "verdict"?: self = .verdict
        default: self = .autre
        }
    }

    var titre: String {
        switch self {
        case .avis: "Avis App Store"
        case .manuel: "À la main"
        case .verdict: "Verdicts de vidéos"
        case .autre: "Autres"
        }
    }

    /// Les groupes, ceux qui ont de l'urgent d'abord ; dans un groupe, l'urgent d'abord, l'ordre de `taches()` ensuite.
    static func ranger(_ taches: [LigneTache], aujourdhui: String) -> [(genre: Genre, taches: [LigneTache])] {
        Dictionary(grouping: taches.compactMap { t in Genre(t).map { (genre: $0, tache: t) } }, by: \.genre)
            .map { g, paires in
                let ts = paires.map(\.tache)
                return (genre: g, taches: ts.filter { urgente($0, aujourdhui) } + ts.filter { !urgente($0, aujourdhui) })
            }
            .sorted { a, b in
                let ua = a.taches.contains { urgente($0, aujourdhui) }, ub = b.taches.contains { urgente($0, aujourdhui) }
                return ua != ub ? ua : a.genre.rawValue < b.genre.rawValue
            }
    }
}

/// Les tâches ouvertes d'un genre, huit d'abord, le reste au clic.
private struct PanneauGroupe: View {
    let genre: Genre
    let taches: [LigneTache]
    let aujourdhui: String
    @State private var tout = false

    private static let limite = 8

    var body: some View {
        Panneau(titre: genre.titre) {
            Pastille(texte: Format.entier(taches.count),
                     couleur: taches.contains { urgente($0, aujourdhui) } ? Theme.ambre : Theme.secondaire)
        } contenu: {
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                ForEach(tout ? taches : Array(taches.prefix(Self.limite))) { t in
                    LigneTacheVue(t: t, supprimable: t.source == "manuel")
                }
                if taches.count > Self.limite { BoutonVoir(n: taches.count, tout: $tout) }
            }
        }
    }
}

/// Ajoute une tâche à la main, pour le business affiché, sans business si « Tous » en montre plusieurs.
private struct PanneauAjout: View {
    @Environment(AppState.self) private var app
    @State private var texte = ""
    @State private var avecEcheance = false
    @State private var echeance = Date.now

    var body: some View {
        let business = app.affiches.count == 1 ? app.affiches.first : nil
        let vide = texte.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        Panneau(titre: "Ajouter") {
            VStack(alignment: .leading, spacing: Theme.Espace.l) {
                TextField("Une chose à faire", text: $texte)
                    .textFieldStyle(.plain)
                    .font(Theme.Police.corps)
                    .foregroundStyle(Theme.texte)
                    .padding(.horizontal, Theme.Espace.xl)
                    .frame(height: Theme.Taille.bouton)
                    .fondBlanc(Theme.Blanc.pilule, rayon: Theme.Rayon.ligne)
                    .onSubmit { ajouter(business) }
                HStack(spacing: Theme.Espace.m) {
                    Toggle("Échéance", isOn: $avecEcheance)
                        .toggleStyle(.checkbox)
                        .font(Theme.Police.petit)
                        .foregroundStyle(Theme.secondaire)
                    if avecEcheance {
                        DatePicker("Échéance", selection: $echeance, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .labelsHidden()
                            .controlSize(.small)
                            .environment(\.locale, Format.locale)
                            .environment(\.timeZone, Jour.fuseau)
                            .environment(\.calendar, Jour.calendrier)
                    }
                }
                HStack(spacing: Theme.Espace.m) {
                    Text(business.map { "Pour " + $0.nom } ?? "Sans business")
                        .font(Theme.Police.mini)
                        .foregroundStyle(Theme.secondaire)
                    Spacer(minLength: 0)
                    BoutonPrincipal(texte: "Ajouter", actif: !vide) { ajouter(business) }
                }
            }
        }
    }

    private func ajouter(_ business: Business?) {
        let t = texte.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        let cle = avecEcheance ? Jour.cle(echeance) : nil
        app.ecrire { try $0.ajouterTache(texte: t, business: business?.id, echeance: cle) }
        texte = ""
        avecEcheance = false
    }
}

/// Les tâches cochées ces 7 jours, repliées par défaut ; décocher les remet à faire.
private struct PanneauFaites: View {
    let taches: [LigneTache]
    @State private var ouvert = false

    var body: some View {
        Panneau(titre: "Faites, 7 jours") {
            Button { withAnimation(Theme.Anim.navigation) { ouvert.toggle() } } label: {
                HStack(spacing: Theme.Espace.s) {
                    Pastille(texte: Format.entier(taches.count))
                    Image(systemName: "chevron.down")
                        .font(Theme.Police.miniGras)
                        .foregroundStyle(Theme.secondaire)
                        .rotationEffect(.degrees(ouvert ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.appui)
            .help(ouvert ? "Replier" : "Déplier")
        } contenu: {
            if ouvert {
                if taches.isEmpty {
                    Vide(texte: "Rien de fait ces 7 jours.")
                } else {
                    VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                        ForEach(taches) { t in LigneTacheVue(t: t, supprimable: t.source == "manuel") }
                    }
                }
            }
        }
    }
}

/// Aucune autre tâche : quand les sources qui en posent ont lu pour la dernière fois.
private struct PanneauRien: View {
    @Environment(AppState.self) private var app

    /// Les sources qui écrivent dans `a_traiter` autre chose que le SAV (docs/donnees.md).
    private static let poseuses = ["asc", "contenu"]

    var body: some View {
        let passages = app.lectures.derniersPassages()
        let sources = app.collecteur.sources.filter { Self.poseuses.contains($0.id) }
        Panneau(titre: "Rien d'autre à traiter.") {
            VStack(alignment: .leading, spacing: Theme.Espace.m) {
                Text("Les avis App Store et les verdicts de vidéos arrivent ici à chaque passage de leur source.")
                    .font(Theme.Police.petit)
                    .foregroundStyle(Theme.secondaire)
                ForEach(sources, id: \.id) { s in
                    let p = passages[s.id]
                    HStack(spacing: Theme.Espace.m) {
                        Point(couleur: EtatSource(passage: p, enCours: app.collecteur.enCours.contains(s.id)).couleur)
                        Text(s.nom).font(Theme.Police.ligne).foregroundStyle(Theme.texte)
                        Spacer(minLength: 0)
                        Text(p.map { "lu " + Format.ilYa($0.fin, maintenant: app.maintenant) } ?? "jamais lue")
                            .font(Theme.Police.petit)
                            .foregroundStyle(Theme.secondaire)
                    }
                }
            }
        }
    }
}
