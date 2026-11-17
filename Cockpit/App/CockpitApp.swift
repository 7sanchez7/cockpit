import SwiftUI

@main
struct CockpitApp: App {
    static let fenetre = "cockpit"
    @State private var app = AppState.lancer()

    var body: some Scene {
        Window("Cockpit", id: Self.fenetre) {
            Racine()
                .environment(app)
                .frame(minWidth: Theme.Taille.fenetreMin.width, minHeight: Theme.Taille.fenetreMin.height)
        }
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .defaultSize(Theme.Taille.fenetre)
        .commands { Commandes(app: app) }

        MenuBarExtra {
            BarreMenus().environment(app).sobre()
        } label: {
            EtiquetteBarreMenus(app: app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            Reglages().environment(app)
        }
    }
}

/// La fenêtre : barre du haut, écran choisi, lueur blanche qui tombe du haut. Tout ce qui change ici s'anime :
/// écran, business, palette, données ; changer d'écran, de business ou de période tape dans le trackpad.
struct Racine: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(spacing: 0) {
            BarreHaut().zIndex(1)
            ZStack {
                ecran
                    .id(app.ecran)
                    .transition(Bascule(sens: app.avance ? 1 : -1))
            }
            .padding(.horizontal, Theme.Espace.page)
            .padding(.top, Theme.Espace.m)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background {
            Theme.fond
                .overlay(alignment: .top) {
                    Theme.lueur
                        .frame(height: Theme.Taille.lueur)
                        .offset(y: -Theme.Taille.lueur / 2)
                }
                .ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if app.palette {
                Theme.voile
                    .ignoresSafeArea()
                    .onTapGesture { app.palette = false }
                    .transition(.opacity)
                Palette().transition(Surgit())
            }
        }
        .animation(Theme.Anim.navigation, value: app.ecran)
        .animation(Theme.Anim.navigation, value: app.selection)
        .animation(Theme.Anim.navigation, value: app.palette)
        .animation(Theme.Anim.navigation, value: app.store.version)
        .sensoryFeedback(.alignment, trigger: app.ecran)
        .sensoryFeedback(.alignment, trigger: app.selection)
        .sensoryFeedback(.levelChange, trigger: app.periode)
        // les images de tous les business en mémoire avant qu'un écran les demande
        .task(id: app.store.version, priority: .utility) {
            let l = Lectures(db: app.store.db, businesses: app.tousLesBusiness, maintenant: app.maintenant)
            await Images.precharger(l.images(limite: Images.videosEnMemoire))
        }
        .sobre()
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var ecran: some View {
        switch app.ecran {
        case .app: EcranAccueil()
        case .data: EcranData()
        case .videos: Videos()
        case .sante: Sante()
        case .aTraiter: SAV()
        case .apps: AppsDePotes()
        }
    }
}

/// ⌘1 à ⌘6 pour les écrans, ⌘R pour tout relancer, ⌘K pour la palette.
struct Commandes: Commands {
    let app: AppState

    var body: some Commands {
        CommandMenu("Aller") {
            ForEach(Ecran.allCases) { e in
                Button(e.titre) { app.ecran = e }
                    .keyboardShortcut(KeyEquivalent(e.raccourci), modifiers: .command)
            }
            Divider()
            Button("Rechercher…") { app.palette = true }
                .keyboardShortcut("k", modifiers: .command)
        }
        CommandGroup(after: .newItem) {
            Button("Tout relancer") { app.collecteur.relancer() }
                .keyboardShortcut("r", modifiers: .command)
        }
    }
}
