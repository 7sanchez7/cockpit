import SwiftUI

/// Le ton d'un écart : vert s'il monte, rouge s'il baisse, gris s'il est nul ou sans référence.
enum Ton {
    case positif, negatif, neutre

    init(_ ecart: Double?, inverse: Bool = false) {
        guard let ecart, ecart != 0 else { self = .neutre; return }
        self = (ecart > 0) != inverse ? .positif : .negatif
    }

    var couleur: Color {
        switch self {
        case .positif: Theme.succes
        case .negatif: Theme.danger
        case .neutre: Theme.secondaire
        }
    }

    /// Le trait d'une sparkline : la couleur du ton, blanc à .5 si neutre.
    var trait: Color { self == .neutre ? .white.opacity(Theme.Blanc.trait) : couleur }
}
