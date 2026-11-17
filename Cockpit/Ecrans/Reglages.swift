import AppKit
import SwiftUI

/// La fenêtre Réglages (⌘,) : business, clés, notifications, collecte.
struct Reglages: View {
    var body: some View {
        TabView {
            Tab("Business", systemImage: "square.stack") { ReglagesBusiness() }
            Tab("Clés", systemImage: "key") { ReglagesCles() }
            Tab("Notifications", systemImage: "bell") { ReglagesNotifs() }
            Tab("Collecte", systemImage: "arrow.triangle.2.circlepath") { ReglagesCollecte() }
        }
        .frame(width: Theme.Taille.reglages.width, height: Theme.Taille.reglages.height)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

/// Le choix du business dont on règle la config ou les clés.
private struct ChoixReglage: View {
    @Environment(AppState.self) private var app
    @Binding var id: String?

    var body: some View {
        Picker("Business", selection: $id) {
            ForEach(app.tousLesBusiness) { b in Text(b.nom).tag(Optional(b.id)) }
            if id == nil { Text("Nouveau").tag(String?.none) }
        }
        .onAppear { if id == nil { id = app.selection ?? app.tousLesBusiness.first?.id } }
    }
}

// MARK: business

/// La config d'un business en texte, le temps de l'éditer.
private struct Brouillon {
    var id = ""
    var nom = ""
    var lettre = ""
    var teinte = "menthe"
    var appStoreId = ""
    var ascIssuer = ""
    var ascVendor = ""
    var playPackage = ""
    var playBucket = ""
    var firebaseProject = ""
    var posthogHost = ""
    var contenuDir = ""
    var pays = ""
    var genre = "6017"
    var objectif = "10000"

    init() {}

    init(_ b: Business) {
        id = b.id
        nom = b.nom
        lettre = b.lettre
        teinte = b.teinte
        appStoreId = b.config.appStoreId ?? ""
        ascIssuer = b.config.ascIssuer ?? ""
        ascVendor = b.config.ascVendor ?? ""
        playPackage = b.config.playPackage ?? ""
        playBucket = b.config.playBucket ?? ""
        firebaseProject = b.config.firebaseProject ?? ""
        posthogHost = b.config.posthogHost ?? ""
        contenuDir = b.config.contenuDir ?? ""
        pays = b.config.pays.joined(separator: ", ")
        genre = String(b.config.genre)
        objectif = String(Int(b.config.objectifMensuelEUR))
    }

    /// Le business à enregistrer ; un nouveau prend pour id son nom en minuscules sans accents.
    func business() throws -> Business {
        let nom = nom.trimmingCharacters(in: .whitespaces)
        let id = id.isEmpty ? Self.identifiant(nom) : id
        guard !nom.isEmpty, !id.isEmpty else { throw ErreurReglage("Il faut un nom.") }
        guard let genre = Int(genre) else { throw ErreurReglage("La catégorie App Store est un nombre (6017 = Éducation).") }
        guard let objectif = Double(objectif.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: ".")) else {
            throw ErreurReglage("L'objectif mensuel est un nombre d'euros.")
        }
        let config = Business.Config(
            appStoreId: Self.texte(appStoreId), ascIssuer: Self.texte(ascIssuer), ascVendor: Self.texte(ascVendor),
            playPackage: Self.texte(playPackage), playBucket: Self.texte(playBucket), firebaseProject: Self.texte(firebaseProject),
            posthogHost: Self.texte(posthogHost),
            contenuDir: Self.texte(contenuDir), pays: Self.liste(pays).map { $0.lowercased() }, genre: genre,
            objectifMensuelEUR: objectif)
        let lettre = lettre.trimmingCharacters(in: .whitespaces)
        return Business(id: id, nom: nom, lettre: lettre.isEmpty ? String(nom.prefix(1)).uppercased() : String(lettre.prefix(2)),
                        teinte: teinte, config: config)
    }

    static func identifiant(_ nom: String) -> String {
        nom.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Format.locale)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    private static func texte(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private static func liste(_ s: String) -> [String] {
        s.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

private struct ErreurReglage: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private struct ReglagesBusiness: View {
    @Environment(AppState.self) private var app
    @State private var id: String?
    @State private var b = Brouillon()
    @State private var erreur: String?
    @State private var enregistre = false
    @State private var aSupprimer = false

    var body: some View {
        Form {
            Section {
                ChoixReglage(id: $id)
                Button("Nouveau business") { id = nil }
            }
            Section("Identité") {
                TextField("Nom", text: $b.nom)
                TextField("Lettre", text: $b.lettre)
                Picker("Teinte", selection: $b.teinte) {
                    ForEach(Theme.teintes, id: \.cle) { t in Text(t.nom).foregroundStyle(Theme.teinte(t.cle)).tag(t.cle) }
                }
            }
            Section {
                TextField("App Store, id de l'app", text: $b.appStoreId)
                TextField("App Store Connect, issuer", text: $b.ascIssuer)
                TextField("App Store Connect, numéro de fournisseur", text: $b.ascVendor, prompt: Text("8…"))
                TextField("Play Store, paquet", text: $b.playPackage, prompt: Text("com.exemple.app"))
                TextField("Play Console, bucket des rapports", text: $b.playBucket, prompt: Text("pubsite_prod_rev_…"))
                TextField("Firebase, projet", text: $b.firebaseProject)
                TextField("PostHog, hôte", text: $b.posthogHost, prompt: Text("https://eu.posthog.com"))
                TextField("Fiches de contenu, dossier", text: $b.contenuDir)
            } header: {
                Text("Sources")
            } footer: {
                Text("Un champ vide coupe la source pour ce business.").foregroundStyle(Theme.secondaire)
            }
            Section("Classements et objectif") {
                TextField("Pays suivis", text: $b.pays, prompt: Text("fr, es, us"))
                TextField("Catégorie App Store", text: $b.genre)
                TextField("Objectif mensuel (€)", text: $b.objectif)
            }
            Section {
                HStack {
                    if id != nil {
                        Button("Supprimer", role: .destructive) { aSupprimer = true }
                            .disabled(app.tousLesBusiness.count < 2)
                    }
                    if let erreur {
                        Text(erreur).foregroundStyle(Theme.danger).lineLimit(2)
                    } else if enregistre {
                        Text("Enregistré").foregroundStyle(Theme.succes)
                    }
                    Spacer()
                    Button("Enregistrer", action: enregistrer).keyboardShortcut(.defaultAction)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: charger)
        .onChange(of: id) { charger() }
        .onChange(of: b.nom) { enregistre = false }
        .confirmationDialog("Supprimer \(b.nom) ?", isPresented: $aSupprimer) {
            Button("Supprimer", role: .destructive, action: supprimer)
        } message: {
            Text("Le business disparaît du cockpit. Ses chiffres déjà collectés restent dans la base.")
        }
    }

    private func charger() {
        erreur = nil
        enregistre = false
        b = app.tousLesBusiness.first { $0.id == id }.map(Brouillon.init) ?? Brouillon()
    }

    private func enregistrer() {
        do {
            let nouveau = try b.business()
            if id == nil, app.tousLesBusiness.contains(where: { $0.id == nouveau.id }) {
                throw ErreurReglage("Un business porte déjà l'id \(nouveau.id).")
            }
            try app.store.enregistrer(nouveau)
            app.store.aChange()
            id = nouveau.id
            b = Brouillon(nouveau)
            erreur = nil
            enregistre = true
        } catch {
            erreur = error.localizedDescription
        }
    }

    private func supprimer() {
        guard let id else { return }
        do {
            try app.store.supprimerBusiness(id)
            if app.selection == id { app.selection = nil }
            app.store.aChange()
            self.id = app.tousLesBusiness.first?.id
        } catch {
            erreur = error.localizedDescription
        }
    }
}

// MARK: clés

private struct ReglagesCles: View {
    @Environment(AppState.self) private var app
    @State private var id: String?
    @State private var saisies: [String: String] = [:]
    @State private var erreur: String?
    /// Incrémenté après chaque écriture du Trousseau, pour relire l'état des clés.
    @State private var tour = 0

    private static let cles = [
        (PostHog.cleProjet, "PostHog, id du projet"),
        (PostHog.cleAPI, "PostHog, clé personnelle scopée au projet"),
        (RevenueCat.nomCle, "RevenueCat, clé secrète v2 en lecture"),
    ]

    var body: some View {
        let b = app.tousLesBusiness.first { $0.id == id }
        Form {
            Section { ChoixReglage(id: $id) }
            if let b {
                Section {
                    ForEach(Self.cles, id: \.0) { nom, libelle in ligne(nom, libelle, b) }
                } header: {
                    Text("Trousseau")
                } footer: {
                    Text("Sans clé dans le Trousseau, le cockpit lit la variable d'environnement du même nom, puis Secret Manager"
                         + (b.config.firebaseProject.map { " du projet \($0)" } ?? "") + ".")
                        .foregroundStyle(Theme.secondaire)
                }
            }
            Section("Fichiers") {
                LabeledContent("App Store Connect") {
                    Text((try? AppStoreConnect.cle()) != nil ? "clé AuthKey trouvée" : "aucune clé dans ~/.appstoreconnect/private_keys")
                }
                LabeledContent("Google, ADC") {
                    Text(FileManager.default.fileExists(atPath: GCloud.identifiants.path)
                         ? "identifiants présents" : "gcloud auth application-default login")
                }
            }
            if let erreur {
                Text(erreur).foregroundStyle(Theme.danger)
            }
        }
        .formStyle(.grouped)
        .id(tour)
    }

    private func ligne(_ nom: String, _ libelle: String, _ b: Business) -> some View {
        LabeledContent {
            if app.collecteur.secrets.dansTrousseau(nom, b) {
                HStack {
                    Text("dans le Trousseau").foregroundStyle(Theme.succes)
                    Button("Effacer") { agir { try app.collecteur.secrets.effacer(nom, b) } }
                }
            } else {
                HStack {
                    SecureField(nom, text: Binding(get: { saisies[nom] ?? "" }, set: { saisies[nom] = $0 }))
                        .labelsHidden()
                    Button("Ranger") {
                        let v = (saisies[nom] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !v.isEmpty else { return }
                        agir { try app.collecteur.secrets.enregistrer(nom, b, v) }
                        saisies[nom] = nil
                    }
                }
            }
        } label: {
            Text(libelle)
        }
    }

    private func agir(_ f: () throws -> Void) {
        do {
            try f()
            erreur = nil
        } catch {
            erreur = error.localizedDescription
        }
        tour += 1
    }
}

// MARK: notifications

private struct ReglagesNotifs: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Form {
            Section {
                ForEach(TypeFil.allCases, id: \.self) { t in
                    Toggle(t.libelle, isOn: Binding(
                        get: { app.reglage(t.reglageNotif) != "0" },
                        set: { oui in app.ecrire { try $0.regler(t.reglageNotif, oui ? nil : "0") } }))
                }
            } header: {
                Text("Me notifier pour")
            } footer: {
                Text("Une notification par nouveauté de moins de 2 h ; au-delà de trois d'un coup, un résumé. "
                     + "Une source qui tombe en panne notifie toujours.")
                    .foregroundStyle(Theme.secondaire)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: collecte

private struct ReglagesCollecte: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle("Collecte en pause", isOn: $app.enPause)
                Button("Tout relancer") { app.collecteur.relancer() }
            }
            Section("Sources") {
                ForEach(app.collecteur.sources, id: \.id) { s in
                    LabeledContent(s.nom, value: "toutes les " + Format.cadence(s.cadence))
                }
            }
            Section("Base") {
                LabeledContent("Fichier", value: Store.fichier.path(percentEncoded: false))
                Button("Montrer dans le Finder") { NSWorkspace.shared.activateFileViewerSelecting([Store.fichier]) }
            }
        }
        .formStyle(.grouped)
    }
}
