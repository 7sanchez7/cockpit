import SwiftUI

/// Le tableau des vidéos : #, titre, âge, vues, gain 24 h, part de partages et d'enregistrements, seuil.
struct TableVideos: View {
    let videos: [LigneVideo]
    var maintenant: Date = .now
    /// La vidéo du détail, surlignée.
    var choisie: String?
    var choisir: (LigneVideo) -> Void = { _ in }

    private static let colonnes: [(String, CGFloat?)] = [
        ("#", 26), ("Titre", nil), ("Âge", 44), ("Vues", 80), ("24 h", 70), ("Part.", 62), ("Enreg.", 62), ("Seuil", 52),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Espace.l) {
                ForEach(Self.colonnes, id: \.0) { titre, largeur in
                    cellule(largeur, aligne: largeur == nil ? .leading : .trailing) {
                        Text(titre).foregroundStyle(titre == "Vues" ? Theme.texte : Theme.secondaire)
                    }
                }
            }
            .font(Theme.Police.miniGras.weight(.bold))
            .padding(.horizontal, Theme.Espace.l)
            .padding(.top, Theme.Espace.s)
            .padding(.bottom, 6)
            ForEach(Array(videos.enumerated()), id: \.element.id) { i, v in
                Button { choisir(v) } label: { ligne(i, v) }.buttonStyle(.appuiCarte)
            }
        }
    }

    private func ligne(_ i: Int, _ v: LigneVideo) -> some View {
        HStack(spacing: Theme.Espace.l) {
            cellule(26, aligne: .leading) { Text("\(i + 1)").foregroundStyle(Theme.secondaire) }
            cellule(nil, aligne: .leading) {
                Text(v.titre.isEmpty ? v.id : v.titre).foregroundStyle(Theme.texte).lineLimit(1).truncationMode(.tail)
            }
            cellule(44) { Text(v.publieeLe.map { Format.age($0, maintenant: maintenant) } ?? Format.vide).foregroundStyle(Theme.secondaire) }
            cellule(80) { Text(Format.entier(v.vues)).font(Theme.Police.corpsGras).foregroundStyle(Theme.texte) }
            cellule(70) {
                let g = v.gain24h ?? 0
                Text(v.gain24h.map { Format.delta(Double($0), compacte: true) } ?? Format.vide)
                    .foregroundStyle(g > 0 ? Theme.succes : Theme.secondaire)
            }
            cellule(62) { Text(v.partPartages.map { Format.pourcent($0, decimales: 1) } ?? Format.vide).foregroundStyle(Theme.secondaire) }
            cellule(62) { Text(v.partEnreg.map { Format.pourcent($0, decimales: 1) } ?? Format.vide).foregroundStyle(Theme.secondaire) }
            cellule(52) {
                if v.partPartages == nil && v.partEnreg == nil {
                    Text(Format.vide).foregroundStyle(Theme.secondaire)
                } else if v.seuilAtteint {
                    Pastille(texte: "oui", couleur: Theme.accent)
                } else {
                    Pastille(texte: "non", couleur: Theme.secondaire)
                }
            }
        }
        .font(Theme.Police.petit)
        .monospacedDigit()
        .padding(.horizontal, Theme.Espace.l)
        .frame(height: Theme.Taille.ligneVideo)
        .fondBlanc(v.id == choisie ? Theme.Blanc.actif : i % 2 == 0 ? Theme.Blanc.ligne : 0, rayon: Theme.Rayon.ligne)
        .contentShape(Rectangle())
        .help("@\(v.compte) · relevé \(Format.ilYa(v.releveLe, maintenant: maintenant))")
    }

    private func cellule<C: View>(_ largeur: CGFloat?, aligne: Alignment = .trailing, @ViewBuilder _ c: () -> C) -> some View {
        Group {
            if let largeur {
                c().frame(width: largeur, alignment: aligne)
            } else {
                c().frame(maxWidth: .infinity, alignment: aligne)
            }
        }
    }
}

/// La pastille « seuil partages et enreg. 1,5 % » des en-têtes de panneau vidéo.
struct PastilleSeuil: View {
    var body: some View {
        Pastille(texte: "seuil partages et enreg. " + Format.pourcent(Lectures.seuilVideo, decimales: 1), couleur: Theme.secondaire)
    }
}
