import SwiftUI

/// Le logo, celui de l'icône : un horizon artificiel, un anneau autour d'un demi-disque incliné.
struct Marque: View {
    let taille: CGFloat

    var body: some View {
        ZStack {
            Circle().strokeBorder(lineWidth: taille * 42 / 680)
            Horizon().padding(taille * 90 / 680)
        }
        .frame(width: taille, height: taille)
    }
}

/// La moitié basse d'un disque, sous une ligne qui monte de 12 degrés vers la droite.
nonisolated struct Horizon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.addArc(center: CGPoint(x: rect.midX, y: rect.midY), radius: min(rect.width, rect.height) / 2,
                     startAngle: .degrees(-12), endAngle: .degrees(168), clockwise: false)
            p.closeSubpath()
        }
    }
}
