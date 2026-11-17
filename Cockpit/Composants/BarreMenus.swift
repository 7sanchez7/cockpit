import AppKit
import SwiftUI

/// L'icône de la barre de menus, avec le nombre de choses à traiter.
struct EtiquetteBarreMenus: View {
    let app: AppState

    var body: some View {
        let n = app.lectures.nbATraiter()
        HStack(spacing: Theme.Espace.s) {
            Image(systemName: "gauge.with.dots.needle.67percent")
            if n > 0 { Text("\(n)") }
        }
    }
}

/// La fenêtre de la barre de menus : les chiffres du jour, ce qu'il reste à traiter, les 5 derniers événements.
struct BarreMenus: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var ouvrirFenetre

    var body: some View {
        let l = app.lectures
        let jour = Jour.cle(app.maintenant)
        let aTraiter = l.nbATraiter()
        VStack(alignment: .leading, spacing: Theme.Espace.xl) {
            HStack {
                Text("Cockpit").font(Theme.Police.h2).foregroundStyle(Theme.texte)
                Spacer()
                Text(derniereCollecte(l)).font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
            }
            Grid(alignment: .leading, horizontalSpacing: Theme.Espace.xl, verticalSpacing: Theme.Espace.l) {
                GridRow {
                    chiffre("MRR", l.valeur(Metrique.mrrBrut, jour: jour).map { Format.euros(Metrique.enEuros($0)) })
                    chiffre("Actifs", l.valeur(Metrique.actifs, jour: jour).map(Format.entier))
                }
                GridRow {
                    chiffre("Installs", l.valeur(Metrique.installs, jour: jour).map(Format.entier))
                    chiffre("Essais", l.valeur(Metrique.essais, jour: jour).map(Format.entier))
                }
            }
            Button { ouvrir(.aTraiter) } label: {
                HStack {
                    Text("SAV").font(Theme.Police.ligne).foregroundStyle(Theme.texte)
                    Spacer()
                    Pastille(texte: "\(aTraiter)", couleur: aTraiter > 0 ? Theme.ambre : Theme.secondaire)
                }
                .padding(.horizontal, Theme.Espace.l)
                .frame(height: Theme.Taille.itemNav)
                .fondBlanc(Theme.Blanc.ligne, rayon: Theme.Rayon.ligne)
                .contentShape(Rectangle())
            }
            .buttonStyle(.appuiCarte)
            VStack(spacing: 0) {
                let fil = l.fil(limite: 5)
                if fil.isEmpty {
                    Vide(texte: "Rien de nouveau.")
                } else {
                    ForEach(fil, id: \.id) { LigneFil(e: $0) }
                }
            }
            HStack(spacing: Theme.Espace.m) {
                Button("Ouvrir") { ouvrir(nil) }
                    .keyboardShortcut(.defaultAction)
                Button("Actualiser") { app.collecteur.relancer() }
                Spacer()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
            }
            .font(Theme.Police.ligne)
        }
        .padding(Theme.Espace.xxl)
        .frame(width: Theme.Taille.barreMenus)
        .preferredColorScheme(.dark)
    }

    private func chiffre(_ libelle: String, _ valeur: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            Text(libelle).font(Theme.Police.label).foregroundStyle(Theme.secondaire)
            Chiffre(texte: valeur ?? Format.vide)
                .font(Theme.Police.grand)
                .foregroundStyle(Theme.texte)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func derniereCollecte(_ l: Lectures) -> String {
        guard let fin = l.derniersPassages().values.map(\.fin).max() else { return "aucune collecte" }
        return "collecte " + Format.ilYa(fin, maintenant: app.maintenant)
    }

    /// Ramène la fenêtre principale devant, sur l'écran demandé.
    private func ouvrir(_ ecran: Ecran?) {
        if let ecran { app.ecran = ecran }
        ouvrirFenetre(id: CockpitApp.fenetre)
        NSApplication.shared.activate()
    }
}
