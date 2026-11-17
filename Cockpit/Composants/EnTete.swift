import SwiftUI

/// L'en-tête d'un écran : titre et sous-titre, outils de l'écran, segmenté des business.
struct EnTete<Outils: View>: View {
    @Environment(AppState.self) private var app
    let titre: String
    let sousTitre: String
    @ViewBuilder var outils: Outils

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Espace.xl) {
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                Text(titre)
                    .font(Theme.Police.titre)
                    .tracking(-0.9)
                    .foregroundStyle(Theme.texte)
                Text(sousTitre)
                    .font(Theme.Police.corps)
                    .foregroundStyle(Theme.secondaire)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Espace.xl)
            HStack(spacing: Theme.Espace.l) {
                outils
                Segmente(options: [("Tous", nil)] + app.tousLesBusiness.map { ($0.nom, Optional($0.id)) },
                         choix: Binding(get: { app.selection }, set: { app.selection = $0 }))
            }
        }
        .padding(.top, Theme.Espace.xl)
        .padding(.bottom, Theme.Espace.m)
    }
}

