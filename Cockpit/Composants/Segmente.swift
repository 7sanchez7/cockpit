import SwiftUI

/// Une pilule de verre à choix unique, la pilule blanche glisse d'un choix à l'autre : le filtre des business de l'en-tête, les bascules des panneaux.
struct Segmente<Valeur: Hashable>: View {
    let options: [(texte: String, valeur: Valeur)]
    @Binding var choix: Valeur
    @Namespace private var pilule

    var body: some View {
        HStack(spacing: Theme.Espace.xs) {
            ForEach(options, id: \.valeur) { o in
                let actif = o.valeur == choix
                Button { choix = o.valeur } label: {
                    Text(o.texte)
                        .font(Theme.Police.ligne)
                        .foregroundStyle(actif ? Theme.fond : Theme.secondaire)
                        .lineLimit(1)
                        .padding(.horizontal, Theme.Espace.xl)
                        .frame(height: Theme.Taille.segment)
                        .background {
                            if actif {
                                Capsule()
                                    .fill(Theme.texte)
                                    .shadow(color: .white.opacity(Theme.Blanc.halo), radius: Theme.Espace.m)
                                    .matchedGeometryEffect(id: "pilule", in: pilule)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.appui)
            }
        }
        .animation(Theme.Anim.navigation, value: choix)
        .padding(Theme.Espace.xs + 1)
        .verre(Capsule())
    }
}
