import SwiftUI

/// Le store affiché sur l'Accueil et Data : le total, l'App Store ou le Play Store. Les chiffres écrits par store
/// (`Boutique.separees`) suivent ; les autres, coûts et vidéos, restent le total.
struct ChoixBoutique: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Segmente(options: [("Total", nil)] + Boutique.allCases.map { ($0.nom, Optional($0)) },
                 choix: Binding(get: { app.boutique }, set: { app.boutique = $0 }))
    }
}
