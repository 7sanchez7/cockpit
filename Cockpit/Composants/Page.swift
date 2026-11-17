import SwiftUI

/// Le cadre d'un écran : l'en-tête fixe et ses outils propres à l'écran, le contenu qui défile dessous, ses blocs
/// entrant l'un après l'autre.
struct Page<Outils: View, Contenu: View>: View {
    let titre: String
    let sousTitre: String
    @ViewBuilder var outils: Outils
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(spacing: Theme.Espace.xl) {
            EnTete(titre: titre, sousTitre: sousTitre) { outils }
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                    Group(subviews: contenu) { blocs in
                        ForEach(Array(blocs.enumerated()), id: \.element.id) { i, bloc in bloc.entree(rang: i) }
                    }
                }
                    .padding(.bottom, Theme.Espace.page)
            }
            .scrollIndicators(.never)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension Page where Outils == EmptyView {
    init(titre: String, sousTitre: String, @ViewBuilder contenu: () -> Contenu) {
        self.init(titre: titre, sousTitre: sousTitre, outils: { EmptyView() }, contenu: contenu)
    }
}

/// Le panneau de verre d'un graphique ou d'une liste, au padding de la maquette (18 20 14).
struct Bloc<Droite: View, Contenu: View>: View {
    let titre: String
    @ViewBuilder var droite: Droite
    @ViewBuilder var contenu: Contenu

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            EnTetePanneau(titre: titre) { droite }
            contenu
        }
        .padding(.top, 18)
        .padding(.horizontal, Theme.Espace.panneau)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.panneau)
    }
}

extension Bloc where Droite == EmptyView {
    init(titre: String, @ViewBuilder contenu: () -> Contenu) {
        self.init(titre: titre, droite: { EmptyView() }, contenu: contenu)
    }
}
