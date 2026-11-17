import SwiftUI

/// Une rangée de panneaux aux largeurs proportionnelles (2 | 1, 3 | 1), tous à la même hauteur.
/// `hauteurDe` prend la hauteur d'un seul enfant (les autres défilent dedans) ; nil prend la plus haute.
struct Rangee: Layout {
    var poids: [CGFloat]
    var hauteurDe: Int?
    var ecart = Theme.Espace.xl

    private func largeurs(_ total: CGFloat, _ n: Int) -> [CGFloat] {
        let p = (0..<n).map { $0 < poids.count ? poids[$0] : 1 }
        let utile = max(total - ecart * CGFloat(n - 1), 0)
        return p.map { utile * $0 / p.reduce(0, +) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let total = proposal.width ?? 1000
        let l = largeurs(total, subviews.count)
        let hauteurs = zip(subviews, l).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
        let h = hauteurDe.flatMap { hauteurs.indices.contains($0) ? hauteurs[$0] : nil } ?? hauteurs.max() ?? 0
        return CGSize(width: total, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (s, w) in zip(subviews, largeurs(bounds.width, subviews.count)) {
            s.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: w, height: bounds.height))
            x += w + ecart
        }
    }
}
