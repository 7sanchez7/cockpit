import SwiftUI

/// Une carte de la grille KPI : libellé en surtitre et pastille, valeur, sa note et sparkline ; `grande` pose la
/// sparkline dessous, sur toute la place que la carte reçoit.
struct CarteKPI: View {
    let libelle: String
    let valeur: String
    var delta: String?
    var ton: Ton = .neutre
    var serie: [Double?] = []
    var inverse = false
    var grande = false
    /// Une ligne de contexte sous la valeur : `MRR 608 €`, `2 en cours`.
    var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.m) {
            HStack(spacing: Theme.Espace.m) {
                Text(libelle).surtitre()
                Spacer(minLength: 0)
                // la pastille porte une donnée : le libellé se coupe avant elle
                if let delta { Pastille(texte: delta, couleur: ton.couleur).layoutPriority(1) }
            }
            if grande {
                valeurEtNote
                Sparkline(valeurs: serie, couleur: ton.trait, inverse: inverse, libre: true)
                    .padding(.top, Theme.Espace.m)
            } else {
                HStack(alignment: .bottom, spacing: Theme.Espace.m) {
                    valeurEtNote
                    Spacer(minLength: 0)
                    Sparkline(valeurs: serie, couleur: ton.trait, inverse: inverse)
                }
            }
        }
        .padding(.vertical, Theme.Espace.xxl)
        .padding(.horizontal, Theme.Espace.xxl + Theme.Espace.s)
        .frame(maxWidth: .infinity, maxHeight: grande ? .infinity : nil, alignment: .topLeading)
        .verre(rayon: Theme.Rayon.carte)
        .survolable()
    }

    private var valeurEtNote: some View {
        VStack(alignment: .leading, spacing: Theme.Espace.xs) {
            chiffre
            if let note {
                Text(note).font(Theme.Police.petit).foregroundStyle(Theme.tertiaire).lineLimit(1)
            }
        }
    }

    private var chiffre: some View {
        Chiffre(texte: valeur)
            .font(Theme.Police.kpi)
            .tracking(-0.9)
            .foregroundStyle(Theme.texte)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }
}

/// La grille de cartes KPI, quatre colonnes par défaut ; les rangées se partagent la hauteur reçue et les cartes
/// entrent l'une après l'autre.
struct GrilleKPI<Contenu: View>: View {
    var colonnes = 4
    @ViewBuilder var contenu: Contenu

    var body: some View {
        Group(subviews: contenu) { cartes in
            VStack(spacing: Theme.Espace.xl) {
                ForEach(Array(stride(from: 0, to: cartes.count, by: colonnes)), id: \.self) { debut in
                    HStack(spacing: Theme.Espace.xl) {
                        ForEach(debut..<debut + colonnes, id: \.self) { i in
                            if i < cartes.count {
                                cartes[i].entree(rang: i + 1)
                            } else {
                                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                            }
                        }
                    }
                }
            }
        }
    }
}
