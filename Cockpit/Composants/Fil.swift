import SwiftUI

extension TypeFil {
    /// Le tag affiché : `VIDÉO` avec son accent, les autres tels quels.
    var tag: String { self == .video ? "VIDÉO" : rawValue }

    var couleur: Color {
        switch self {
        case .essai, .achat, .rang: Theme.succes
        case .ia: Theme.ambre
        default: Theme.secondaire
        }
    }
}

/// Une ligne du fil : heure, tag, texte. Un clic ouvre le lien s'il y en a un.
struct LigneFil: View {
    let e: Evenement
    var premiere = false
    var avecJour = false
    @Environment(\.openURL) private var ouvrir

    var body: some View {
        HStack(spacing: Theme.Espace.m) {
            Text(avecJour ? Format.jourHeure(e.at) : Format.heure(e.at))
                .font(Theme.Police.mini)
                .monospacedDigit()
                .foregroundStyle(Theme.secondaire)
                .frame(minWidth: avecJour ? 92 : 36, alignment: .leading)
            Pastille(texte: e.type.tag, couleur: e.type.couleur, police: Theme.Police.tag, largeurMin: 50)
            Text(e.texte)
                .font(Theme.Police.petit)
                .foregroundStyle(Theme.texte)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if e.lien != nil {
                Image(systemName: "arrow.up.right").font(Theme.Police.fleche).foregroundStyle(Theme.secondaire)
            }
        }
        .padding(.horizontal, Theme.Espace.m)
        .frame(height: Theme.Taille.ligneFil)
        .fondBlanc(premiere ? Theme.Blanc.survol : 0, rayon: Theme.Rayon.ligne)
        .contentShape(Rectangle())
        .help(e.texte)
        .onTapGesture {
            if let lien = e.lien, let url = URL(string: lien) { ouvrir(url) }
        }
    }
}

/// Le panneau « En direct » : les derniers événements, qui défilent dans la hauteur de la rangée.
struct PanneauFil: View {
    let evenements: [Evenement]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            HStack(spacing: Theme.Espace.m) {
                Point(couleur: Theme.succes, taille: Theme.Taille.point)
                Text("En direct").font(Theme.Police.h2).foregroundStyle(Theme.texte)
                Spacer(minLength: 0)
                Text("\(evenements.count) récents").font(Theme.Police.mini).foregroundStyle(Theme.secondaire)
            }
            .padding(.horizontal, Theme.Espace.m)
            .padding(.bottom, Theme.Espace.m)
            if evenements.isEmpty {
                Vide(texte: "Rien sur la période : le fil se remplit à chaque collecte.")
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Espace.xs) {
                        ForEach(Array(evenements.enumerated()), id: \.element.id) { i, e in
                            LigneFil(e: e, premiere: i == 0)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, Theme.Espace.xl)
        .padding(.bottom, Theme.Espace.l)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }
}
