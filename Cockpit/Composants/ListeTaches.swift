import SwiftUI

/// La case ronde d'une tâche : bord ambre si alerte, coche verte une fois faite.
struct CaseRonde: View {
    let faite: Bool
    var alerte = false
    let basculer: () -> Void

    var body: some View {
        Button(action: basculer) {
            ZStack {
                Circle()
                    .strokeBorder(faite ? Theme.succes : alerte ? Theme.ambre.opacity(0.7) : .white.opacity(Theme.Blanc.serie), lineWidth: 1.5)
                    .background(Circle().fill(faite ? Theme.doux(Theme.succes) : .clear))
                if faite {
                    Image(systemName: "checkmark")
                        .font(Theme.Police.coche)
                        .foregroundStyle(Theme.succes)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(Theme.Anim.survol, value: faite)
            .frame(width: Theme.Taille.caseTache, height: Theme.Taille.caseTache)
            .contentShape(Circle())
        }
        .buttonStyle(.appui)
        .help(faite ? "Remettre à faire" : "Marquer comme fait")
    }
}

/// Une ligne de tâche : case, texte, pastille d'échéance ou d'étiquette ; le business quand « Tous » en montre plusieurs.
struct LigneTacheVue: View {
    @Environment(AppState.self) private var app
    @Environment(\.openURL) private var ouvrir
    let t: LigneTache
    var supprimable = false

    private var nomBusiness: String? {
        guard app.selection == nil, app.tousLesBusiness.count > 1 else { return nil }
        return app.tousLesBusiness.first { $0.id == t.business }?.nom
    }

    var body: some View {
        let faite = t.faitLe != nil
        HStack(spacing: Theme.Espace.l) {
            CaseRonde(faite: faite, alerte: t.ton == .alerte) {
                app.ecrire { try $0.cocher(t.id, fait: !faite) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(t.texte)
                    .font(Theme.Police.petit)
                    .foregroundStyle(faite ? Theme.secondaire : Theme.texte)
                    .strikethrough(faite, color: Theme.secondaire)
                    .lineLimit(2)
                let detail = [nomBusiness, t.faitLe.map { "fait " + Format.ilYa($0, maintenant: app.maintenant) }]
                    .compactMap { $0 }.joined(separator: ", ")
                if !detail.isEmpty {
                    Text(detail).font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
                }
            }
            Spacer(minLength: 0)
            if !faite, let p = t.pastille(aujourdhui: Jour.cle(app.maintenant)) {
                Pastille(texte: p, couleur: t.ton == .alerte || p == "retard" ? Theme.ambre : Theme.secondaire,
                         police: Theme.Police.miniGras)
            }
            if let lien = t.lien, let url = URL(string: lien) {
                Button { ouvrir(url) } label: {
                    Image(systemName: "arrow.up.right").font(Theme.Police.fleche).foregroundStyle(Theme.secondaire)
                }
                .buttonStyle(.appui)
                .help(lien)
            }
            if supprimable {
                Button { app.ecrire { try $0.supprimerTache(t.id) } } label: {
                    Image(systemName: "xmark").font(Theme.Police.fleche).foregroundStyle(Theme.secondaire)
                }
                .buttonStyle(.appui)
                .help("Supprimer")
            }
        }
        .padding(.vertical, Theme.Espace.s)
        .padding(.horizontal, Theme.Espace.m)
        .frame(minHeight: Theme.Taille.ligneTache)
        .contentShape(Rectangle())
    }
}

/// Le panneau « À traiter » de l'Accueil : les tâches ouvertes, compteur ambre.
struct PanneauTaches: View {
    let taches: [LigneTache]
    var limite = 8
    var voirTout: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            EnTetePanneau(titre: "À traiter") {
                if !taches.isEmpty { Pastille(texte: "\(taches.count)", couleur: Theme.ambre) }
            }
            .padding(.horizontal, Theme.Espace.m)
            .padding(.bottom, Theme.Espace.m)
            if taches.isEmpty {
                Vide(texte: "Rien à traiter.")
            } else {
                ForEach(taches.prefix(limite)) { t in LigneTacheVue(t: t) }
                if taches.count > limite {
                    Button(action: voirTout) {
                        Text("Voir les \(taches.count)").font(Theme.Police.petit).foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.appui)
                    .padding(.horizontal, Theme.Espace.m)
                    .padding(.top, Theme.Espace.s)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, Theme.Espace.xxl)
        .padding(.horizontal, Theme.Espace.xl)
        .padding(.bottom, Theme.Espace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }
}
