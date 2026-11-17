import SwiftUI

/// L'avatar d'un business : l'icône de son app, sinon sa lettre ; pour « Tous », le logo rond du cockpit.
struct Avatar: View {
    let business: Business?
    var taille = Theme.Taille.avatar

    var body: some View {
        if let app = business?.config.appStoreId {
            IconeApp(id: app, taille: taille)
        } else if let business {
            let teinte = Theme.teinte(business.teinte)
            Text(business.lettre)
                .font(taille < Theme.Taille.avatar ? Theme.Police.miniGras : Theme.Police.corpsGras.weight(.heavy))
                .foregroundStyle(teinte)
                .frame(width: taille, height: taille)
                .background(Theme.doux(teinte), in: RoundedRectangle(cornerRadius: Theme.Rayon.avatar * taille / Theme.Taille.avatar, style: .continuous))
        } else {
            Marque(taille: taille).foregroundStyle(Theme.texte)
        }
    }
}

/// L'icône d'une app, mise en cache par Classements, cernée d'un filet pour se détacher du noir ; un fond neutre
/// tant qu'elle n'est pas téléchargée.
struct IconeApp: View {
    let id: String
    var taille = Theme.Taille.avatar

    var body: some View {
        let forme = RoundedRectangle(cornerRadius: Theme.Rayon.avatar * taille / Theme.Taille.avatar, style: .continuous)
        Miniature(cle: Miniatures.icone(id))
            .frame(width: taille, height: taille)
            .clipShape(forme)
            .overlay { forme.strokeBorder(.white.opacity(Theme.Blanc.bordFort), lineWidth: 1) }
    }
}
