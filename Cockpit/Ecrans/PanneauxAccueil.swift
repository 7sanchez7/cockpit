import AppKit
import SwiftUI

private enum Mesure {
    /// Un compte en pause, comme sa carte dans Vidéos.
    static let enPause = 0.6
}

/// Le panneau gauche de l'Accueil : chaque compte suivi, ses vidéos du jour contre le rythme visé. Replié, un rail
/// d'avatars dont le point passe au vert quand le compte a tenu son rythme.
struct PanneauReseau: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var ouvrir
    @Binding var ouvert: Bool
    let comptes: [LigneReseau]

    private var actifs: [LigneReseau] { comptes.filter(\.compte.actif) }
    private var faites: Int { actifs.map(\.aujourdhui).reduce(0, +) }
    private var visees: Int { actifs.count * LigneReseau.videosParJour }

    var body: some View {
        Group {
            if ouvert { panneau } else { rail }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .verre(rayon: Theme.Rayon.panneau)
        .padding(.top, Theme.Espace.xl)
        .padding(.bottom, Theme.Espace.page)
    }

    private var panneau: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xl) {
            EnTetePanneau(titre: "Réseaux") {
                BoutonPanneau(symbole: "sidebar.left", aide: "Replier les réseaux") { basculer() }
            }
            .padding(.horizontal, Theme.Espace.m)
            if visees > 0 {
                VStack(alignment: .leading, spacing: Theme.Espace.m) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Aujourd'hui").surtitre()
                        Spacer(minLength: Theme.Espace.m)
                        Text("\(faites) / \(visees) vidéos")
                            .font(Theme.Police.label)
                            .monospacedDigit()
                            .foregroundStyle(faites >= visees ? Theme.succes : Theme.texte)
                            .contentTransition(.numericText())
                    }
                    Jauge(part: Double(faites) / Double(visees), couleur: faites >= visees ? Theme.succes : Theme.accent)
                }
                .padding(.horizontal, Theme.Espace.m)
            }
            if comptes.isEmpty {
                Vide(texte: "Aucun compte suivi.")
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Espace.xs) {
                        ForEach(actifs + comptes.filter { !$0.compte.actif }) { LigneReseauVue(r: $0) }
                    }
                }
                .scrollIndicators(.never)
            }
            Button { app.ecran = .videos } label: {
                HStack(spacing: Theme.Espace.s) {
                    Text("Gérer les comptes")
                    Image(systemName: "arrow.right").font(Theme.Police.fleche)
                }
                .font(Theme.Police.petit)
                .foregroundStyle(Theme.secondaire)
            }
            .buttonStyle(.appui)
            .padding(.horizontal, Theme.Espace.m)
        }
        .padding(.vertical, Theme.Espace.xxl)
        .padding(.horizontal, Theme.Espace.l)
        .frame(width: Theme.Taille.panneauReseau)
    }

    private var rail: some View {
        VStack(spacing: Theme.Espace.xl) {
            BoutonPanneau(symbole: "sidebar.left", aide: "Déplier les réseaux") { basculer() }
            ForEach(actifs) { r in
                Button { URL(string: r.compte.plateforme.profil(r.compte.handle)).map { ouvrir($0) } } label: {
                    AvatarCompte(c: r.compte, taille: Theme.Taille.avatarMini)
                        .overlay(alignment: .topTrailing) {
                            Point(couleur: r.aujourdhui >= LigneReseau.videosParJour ? Theme.succes : .white.opacity(Theme.Blanc.repere),
                                  taille: Theme.Taille.pointMini)
                        }
                }
                .buttonStyle(.appui)
                .help("@\(r.compte.handle), \(r.aujourdhui) / \(LigneReseau.videosParJour) aujourd'hui")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Espace.xxl)
        .frame(width: Theme.Taille.rail)
    }

    private func basculer() { withAnimation(Theme.Anim.navigation) { ouvert.toggle() } }
}

/// Un compte du panneau Réseaux : un clic ouvre le profil, le clic droit le relève ou le met en pause.
private struct LigneReseauVue: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var ouvrir
    let r: LigneReseau
    @State private var survol = false

    var body: some View {
        let c = r.compte
        Button { URL(string: c.plateforme.profil(c.handle)).map { ouvrir($0) } } label: {
            HStack(spacing: Theme.Espace.l) {
                AvatarCompte(c: c, taille: Theme.Taille.avatar)
                VStack(alignment: .leading, spacing: 0) {
                    Text("@" + c.handle).font(Theme.Police.label).foregroundStyle(Theme.texte).lineLimit(1)
                    Text(detail)
                        .font(Theme.Police.mini)
                        .foregroundStyle(c.actif && r.aujourdhui >= LigneReseau.videosParJour ? Theme.succes : Theme.secondaire)
                        .lineLimit(1)
                }
                Spacer(minLength: Theme.Espace.s)
                VStack(alignment: .trailing, spacing: 0) {
                    Text(c.abonnes.map { Format.compact(Double($0)) } ?? Format.vide)
                        .font(Theme.Police.label)
                        .monospacedDigit()
                        .foregroundStyle(Theme.texte)
                    if let g = c.gain7j {
                        Text(Format.delta(Double(g), compacte: true))
                            .font(Theme.Police.mini)
                            .monospacedDigit()
                            .foregroundStyle(Ton(Double(g)).couleur)
                    }
                }
            }
            .padding(Theme.Espace.m)
            .background(.white.opacity(survol ? Theme.Blanc.survol : 0),
                        in: RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous))
            .opacity(c.actif ? 1 : Mesure.enPause)
            .contentShape(RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous))
        }
        .buttonStyle(.appui)
        .onHover { survol = $0 }
        .animation(Theme.Anim.survol, value: survol)
        .help(aide)
        .contextMenu {
            Button("Ouvrir le profil") { URL(string: c.plateforme.profil(c.handle)).map { ouvrir($0) } }
            Button("Relever maintenant") { app.collecteur.relancer(c.plateforme.rawValue) }
            Button(c.actif ? "Mettre en pause" : "Reprendre") {
                app.ecrire { try $0.activer(compte: c.id, !c.actif) }
                if !c.actif { app.collecteur.relancer(c.plateforme.rawValue) }
            }
        }
    }

    /// `2 / 3 · il y a 3 h` : les vidéos du jour, puis la dernière publiée ; ou `en pause`.
    private var detail: String {
        guard r.compte.actif else { return "en pause" }
        return "\(r.aujourdhui) / \(LigneReseau.videosParJour)"
            + (r.derniere.map { " · " + Format.ilYa($0, maintenant: app.maintenant) } ?? " aujourd'hui")
    }

    private var aide: String {
        let releve = r.compte.releveLe.map { "Relevé " + Format.ilYa($0, maintenant: app.maintenant) } ?? "Pas encore relevé"
        return releve + (r.vues24h.map { ", " + Format.entier($0) + " vues sur 24 h" } ?? "")
    }
}

/// L'avatar rond d'un compte, le logo de sa plateforme en bas à droite.
private struct AvatarCompte: View {
    let c: LigneCompte
    let taille: CGFloat

    var body: some View {
        Miniature(cle: Miniatures.avatar(c.id), plateforme: c.plateforme)
            .frame(width: taille, height: taille)
            .clipShape(Circle())
            .overlay(alignment: .bottomTrailing) {
                c.plateforme.logo(Theme.Taille.logoMini)
                    .padding(Theme.Espace.xs)
                    .background(Theme.fond, in: Circle())
                    .offset(x: Theme.Espace.s, y: Theme.Espace.s)
            }
    }
}

/// Une jauge en capsule, remplie de `part` (0 à 1).
private struct Jauge: View {
    let part: Double
    let couleur: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(Theme.Blanc.fantome))
                Capsule().fill(couleur).frame(width: g.size.width * min(max(part, 0), 1))
            }
        }
        .frame(height: Theme.Taille.jauge)
        .animation(Theme.Anim.chiffre, value: part)
    }
}

/// Le panneau droit de l'Accueil : le plan de la note « Cockpit » de Notes, section par section, puis les tâches à
/// traiter. Replié, un rail avec les cases restantes et le nombre de tâches.
struct PanneauPlan: View {
    @Environment(AppState.self) private var app
    @Binding var ouvert: Bool
    let plan: [LignePlan]
    let taches: [LigneTache]
    /// L'erreur du dernier passage de Notes : accès au disque refusé, note introuvable.
    let erreur: String?

    private var restantes: Int { plan.filter { $0.coche && !$0.fait }.count }

    /// Les sections dans l'ordre de la note ; deux intertitres identiques restent deux sections.
    private var sections: [(nom: String, lignes: [LignePlan])] {
        var r: [(nom: String, lignes: [LignePlan])] = []
        for l in plan {
            if r.last?.nom == l.section { r[r.count - 1].lignes.append(l) } else { r.append((l.section, [l])) }
        }
        return r
    }

    var body: some View {
        Group {
            if ouvert { panneau } else { rail }
        }
        .padding(.top, Theme.Espace.xl)
        .padding(.bottom, Theme.Espace.page)
    }

    private var panneau: some View {
        VStack(spacing: Theme.Espace.xl) {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                EnTetePanneau(titre: "Plan") {
                    BoutonPanneau(symbole: "sidebar.right", aide: "Replier le plan") { basculer() }
                }
                Text(Format.dateLongue(app.maintenant)).font(Theme.Police.grand).foregroundStyle(Theme.texte)
                if plan.isEmpty {
                    Vide(texte: erreur
                        ?? "Crée une note « Cockpit » dans Notes : intertitres pour les sections, cases à cocher pour les tâches.")
                    Spacer(minLength: 0)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Espace.panneau) {
                            ForEach(Array(sections.enumerated()), id: \.offset) { _, s in section(s.nom, s.lignes) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .scrollIndicators(.never)
                }
                Button(action: ouvrirNotes) {
                    HStack(spacing: Theme.Espace.s) {
                        Text("Ouvrir Notes")
                        Image(systemName: "arrow.up.right").font(Theme.Police.fleche)
                    }
                    .font(Theme.Police.petit)
                    .foregroundStyle(Theme.secondaire)
                }
                .buttonStyle(.appui)
            }
            .padding(Theme.Espace.panneau)
            .frame(maxHeight: .infinity, alignment: .top)
            .verre(rayon: Theme.Rayon.panneau)
            PanneauTaches(taches: taches, limite: 5) { app.ecran = .aTraiter }
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: Theme.Taille.panneauPlan)
    }

    private func section(_ nom: String, _ lignes: [LignePlan]) -> some View {
        let cases = lignes.filter(\.coche)
        return VStack(alignment: .leading, spacing: Theme.Espace.m) {
            HStack(alignment: .firstTextBaseline) {
                Text(nom).surtitre()
                Spacer(minLength: Theme.Espace.m)
                if !cases.isEmpty {
                    Text("\(cases.filter(\.fait).count) / \(cases.count)")
                        .font(Theme.Police.tag)
                        .monospacedDigit()
                        .foregroundStyle(Theme.tertiaire)
                }
            }
            ForEach(Array(lignes.enumerated()), id: \.offset) { _, l in LignePlanVue(l: l) }
        }
    }

    private var rail: some View {
        VStack(spacing: Theme.Espace.xl) {
            BoutonPanneau(symbole: "sidebar.right", aide: "Déplier le plan") { basculer() }
            if restantes > 0 {
                VStack(spacing: Theme.Espace.xs) {
                    Image(systemName: "checklist").font(Theme.Police.symbole).foregroundStyle(Theme.secondaire)
                    Text("\(restantes)").font(Theme.Police.label).monospacedDigit().foregroundStyle(Theme.texte)
                }
                .help("\(restantes) cases à cocher dans Notes")
            }
            if !taches.isEmpty {
                Button { app.ecran = .aTraiter } label: { Pastille(texte: "\(taches.count)", couleur: Theme.ambre) }
                    .buttonStyle(.appui)
                    .help("À traiter")
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Espace.xxl)
        .frame(width: Theme.Taille.rail)
        .frame(maxHeight: .infinity, alignment: .top)
        .verre(rayon: Theme.Rayon.panneau)
    }

    private func basculer() { withAnimation(Theme.Anim.navigation) { ouvert.toggle() } }

    private func ouvrirNotes() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Une ligne du plan : une case de Notes, cochée ou non, ou une ligne simple en puce.
private struct LignePlanVue: View {
    let l: LignePlan

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.m) {
            Group {
                if l.coche {
                    Image(systemName: l.fait ? "checkmark.circle.fill" : "circle")
                        .font(Theme.Police.symbole)
                        .foregroundStyle(l.fait ? Theme.succes : Theme.tertiaire)
                        .help("Se coche dans Notes")
                } else {
                    Image(systemName: "circle.fill").font(Theme.Police.coche).foregroundStyle(Theme.tertiaire)
                }
            }
            .frame(width: Theme.Taille.icone)
            Text(l.texte)
                .font(Theme.Police.petit)
                .foregroundStyle(l.fait ? Theme.tertiaire : Theme.texte)
                .strikethrough(l.fait, color: Theme.tertiaire)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Le bouton qui replie ou déplie un panneau latéral.
private struct BoutonPanneau: View {
    let symbole: String
    let aide: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbole)
                .font(Theme.Police.symbole)
                .foregroundStyle(Theme.secondaire)
                .frame(width: Theme.Taille.segment, height: Theme.Taille.segment)
                .contentShape(Rectangle())
        }
        .buttonStyle(.appui)
        .survolable()
        .help(aide)
    }
}
