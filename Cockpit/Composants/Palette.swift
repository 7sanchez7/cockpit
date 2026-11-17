import AppKit
import SwiftUI

/// La palette ⌘K : aller à un écran, une vidéo, une app ou une tâche, lancer une action.
/// Flèches pour choisir, Entrée pour valider, Échap ou un clic à côté pour fermer.
struct Palette: View {
    @Environment(AppState.self) private var app
    @Environment(\.openSettings) private var ouvrirReglages
    @State private var texte = ""
    @State private var choix = 0
    @State private var moniteur: Any?
    @FocusState private var focus: Bool
    @Namespace private var pilule

    private struct Resultat: Identifiable {
        let id: String
        let icone: String
        let titre: String
        let detail: String
        let agir: () -> Void
    }

    var body: some View {
        let resultats = self.resultats
        VStack(spacing: 0) {
            HStack(spacing: Theme.Espace.l) {
                Image(systemName: "magnifyingglass")
                    .font(Theme.Police.symboleGrand)
                    .foregroundStyle(Theme.secondaire)
                TextField("Écran, vidéo, app, tâche, action", text: $texte)
                    .textFieldStyle(.plain)
                    .font(Theme.Police.h2)
                    .foregroundStyle(Theme.texte)
                    .focused($focus)
                    .onSubmit { valider() }
            }
            .padding(.horizontal, Theme.Espace.panneau)
            .frame(height: Theme.Taille.champPalette)
            Rectangle().fill(.white.opacity(Theme.Blanc.grille)).frame(height: 1)
            if resultats.isEmpty {
                Vide(texte: "Rien ne correspond.")
            } else {
                ScrollViewReader { defilement in
                    ScrollView {
                        VStack(spacing: Theme.Espace.xs) {
                            ForEach(Array(resultats.enumerated()), id: \.element.id) { i, r in
                                Button { executer(r) } label: { ligne(r, active: i == choix) }
                                    .buttonStyle(.appui)
                                    .id(r.id)
                                    .onHover { if $0 { choix = i } }
                            }
                        }
                        .padding(Theme.Espace.m)
                        .animation(Theme.Anim.survol, value: choix)
                    }
                    .scrollIndicators(.never)
                    .frame(maxHeight: Theme.Taille.listePalette)
                    .fixedSize(horizontal: false, vertical: true)
                    .onChange(of: choix) {
                        if resultats.indices.contains(choix) { defilement.scrollTo(resultats[choix].id) }
                    }
                }
            }
        }
        .frame(width: Theme.Taille.palette)
        .verre(rayon: Theme.Rayon.panneau)
        .padding(.top, 110)
        .onChange(of: texte) { choix = 0 }
        .onAppear {
            focus = true
            moniteur = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                switch e.keyCode {
                case 125: deplacer(1); return nil
                case 126: deplacer(-1); return nil
                case 53: fermer(); return nil
                default: return e
                }
            }
        }
        .onDisappear {
            if let moniteur { NSEvent.removeMonitor(moniteur) }
        }
    }

    private func ligne(_ r: Resultat, active: Bool) -> some View {
        HStack(spacing: Theme.Espace.l) {
            Image(systemName: r.icone)
                .font(Theme.Police.symbole)
                .foregroundStyle(active ? Theme.accent : Theme.secondaire)
                .frame(width: Theme.Taille.icone)
            Text(r.titre)
                .font(Theme.Police.ligne)
                .foregroundStyle(Theme.texte)
                .lineLimit(1)
            Spacer(minLength: Theme.Espace.m)
            Text(r.detail)
                .font(Theme.Police.mini)
                .foregroundStyle(Theme.secondaire)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Espace.l)
        .frame(height: Theme.Taille.itemNav)
        .background {
            if active {
                RoundedRectangle(cornerRadius: Theme.Rayon.ligne, style: .continuous)
                    .fill(.white.opacity(Theme.Blanc.actif))
                    .matchedGeometryEffect(id: "choix", in: pilule)
            }
        }
        .contentShape(Rectangle())
    }

    /// Écrans, business et actions toujours ; vidéos, apps et tâches dès qu'on tape.
    private var resultats: [Resultat] {
        let q = texte.trimmingCharacters(in: .whitespaces)
        var r = Ecran.allCases.map { e in
            Resultat(id: "ecran:\(e.id)", icone: e.icone, titre: e.titre, detail: "⌘\(e.raccourci)") { app.ecran = e }
        }
        r.append(Resultat(id: "action:relancer", icone: "arrow.clockwise", titre: "Tout relancer", detail: "⌘R") {
            app.collecteur.relancer()
        })
        let pause = app.enPause
        r.append(Resultat(id: "action:pause", icone: pause ? "play" : "pause",
                          titre: pause ? "Reprendre la collecte" : "Mettre la collecte en pause", detail: "Collecte") {
            app.enPause = !pause
        })
        r.append(Resultat(id: "action:reglages", icone: "gearshape", titre: "Réglages", detail: "⌘,") { ouvrirReglages() })
        let tous = app.tousLesBusiness
        if tous.count > 1 {
            r.append(Resultat(id: "business:tous", icone: "square.stack", titre: "Afficher tous les business", detail: "Business") {
                app.selection = nil
            })
        }
        r += tous.map { b in
            Resultat(id: "business:\(b.id)", icone: "square", titre: "Afficher \(b.nom)", detail: "Business") { app.selection = b.id }
        }
        guard !q.isEmpty else { return r }

        let l = app.lectures
        r += l.videos().map { v in
            Resultat(id: "video:\(v.id)", icone: Ecran.videos.icone, titre: v.titre.isEmpty ? v.id : v.titre,
                     detail: "@\(v.compte), \(Format.entier(v.vues)) vues") {
                app.videoChoisie = v.id
                app.ecran = .videos
            }
        }
        r += l.apps().map { a in
            Resultat(id: "app:\(a.id)", icone: Ecran.apps.icone, titre: a.app.nom, detail: a.app.editeur ?? "App Store") {
                app.ecran = .apps
            }
        }
        r += l.taches().map { t in
            Resultat(id: "tache:\(t.id)", icone: Ecran.aTraiter.icone, titre: t.texte, detail: "SAV") { app.ecran = .aTraiter }
        }
        return Array(r.filter { $0.titre.localizedStandardContains(q) || $0.detail.localizedStandardContains(q) }.prefix(40))
    }

    private func deplacer(_ pas: Int) {
        let n = resultats.count
        guard n > 0 else { return }
        choix = (choix + pas + n) % n
    }

    private func valider() {
        let r = resultats
        if r.indices.contains(choix) { executer(r[choix]) }
    }

    private func executer(_ r: Resultat) {
        fermer()
        r.agir()
    }

    private func fermer() { app.palette = false }
}
