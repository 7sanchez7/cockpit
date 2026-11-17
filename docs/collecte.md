# Collecte

Comment les chiffres arrivent dans la base. Le code est dans `Cockpit/Collecte/` (le moteur) et `Cockpit/Sources/` (une source par service). Ce que chaque source lit et écrit est dans [`sources/`](sources/README.md) ; les tables et métriques dans [`donnees.md`](donnees.md).

## Le collecteur

`Collecteur` tourne tant que l'app est ouverte. Toutes les 60 secondes il lance chaque source arrivée à échéance, en parallèle :

- échéance = début du dernier passage + `cadence` de la source ;
- après un passage en **erreur** ou **non configuré** (session Safari expirée, clé absente), la source est retentée au plus tard 10 minutes après (`repriseApresEchec`, sauf si sa `reprise` dit autrement : Instagram attend sa cadence de 3 heures) : elle repasse au vert dès que la session revient, sans attendre sa cadence ;
- une source déjà en cours n'est pas relancée ;
- le réglage `collecte.pause = 1` (`Collecteur.reglagePause`, Réglages ou palette ⌘K) suspend tout ;
- ⌘R ou le bouton de l'écran Santé relance tout de suite (`relancer`).

Chaque passage écrit une ligne dans `collecte` : `ok`, `erreur` (message lisible) ou `non_configure` (clé absente, business sans réglage pour cette source : gris dans la bande des sources de la barre du haut, pas une panne). Une erreur n'est jamais avalée : elle remonte au collecteur, qui l'écrit et la montre dans Santé. Les messages passent aussi dans le journal système (`log stream --predicate 'subsystem == "com.tonysanchez.cockpit"'`).

| Source | Fichier | Cadence | Fiche |
|---|---|---|---|
| PostHog | `PostHog.swift` | 15 min | [posthog](sources/posthog.md) |
| RevenueCat | `RevenueCat.swift` | 30 min | [revenuecat](sources/revenuecat.md) |
| App Store Connect | `AppStoreConnect.swift` | 1 h | [app-store-connect](sources/app-store-connect.md) |
| Play Console | `PlayConsole.swift` | 3 h | [play-console](sources/play-console.md) |
| TikTok | `TikTok.swift` | 30 min | [tiktok](sources/tiktok.md) |
| Instagram | `Instagram.swift` | 3 h | [instagram](sources/instagram.md) |
| YouTube | `YouTube.swift` | 1 h | [youtube](sources/youtube.md) |
| Facebook | `Facebook.swift` | 3 h | [facebook](sources/facebook.md) |
| Contenu | `Contenu.swift` | 15 min | [contenu](sources/contenu.md) |
| Firebase | `Firebase.swift` | 15 min | [firebase](sources/firebase.md), [couts](sources/couts.md) |
| Classements | `Classements.swift` | 3 h | [classements-itunes](sources/classements-itunes.md) |
| Notes | `Notes.swift` | 1 min | [notes](sources/notes.md) |

Le registre (l'ordre affiché) est `Cockpit/App/Registre.swift`.

Aides partagées par les sources vidéo, dans `Cockpit/Collecte/` :

- `Safari.swift` : les cookies d'un domaine dans Safari (`Safari.cookies(domaine, requis:)`, `Safari.entete`), lus dans `Cookies.binarycookies` avec l'accès complet au disque. Voir [sources/tiktok.md](sources/tiktok.md) § La session.
- `YtDlp.swift` : la liste et le détail des vidéos publiques par `yt-dlp` (TikTok, YouTube).
- `Miniatures.swift` : télécharge les images absentes de `~/Library/Caches/Cockpit/miniatures`, un fichier par clé (`:` et `/` remplacés par `_`) : id de vidéo pour sa miniature, `avatar:<compte>`, `icone:<id App Store>` (Classements), `premiere:<id de vidéo>` pour la première image extraite du flux (`extrairePremieres` : `yt-dlp -g` en 960 px au plus, puis `ffmpeg -frames:v 1`, toutes celles qui manquent, 4 à la fois, 2 à 3 s chacune ; YouTube et Facebook, dont la miniature n'est pas la première image ou est trop petite). L'interface lit ce dossier sans réseau ; le vider fait tout revenir au passage suivant.

## Notifications

Après chaque passage, le collecteur prend les lignes du fil que la source vient d'insérer (`Store.prendreNouveaux`, par le préfixe `<source>:` de l'id) et envoie une notification macOS par ligne, titre `<Business> · <Type>`, corps = le texte du fil. Garde-fous :

- rien au **premier passage** réussi d'une source (sinon l'historique entier notifierait) ;
- rien pour une ligne de plus de 2 heures (retour de veille) ;
- un type coupé dans Réglages (`notifs.<type> = 0`, `TypeFil.reglageNotif`) ne notifie pas ;
- au-delà de 3 lignes d'un coup, un résumé « N autres nouveautés ».

Une source qui marchait et tombe en `erreur` envoie « Cockpit · <Source> en panne ».

## Contrat d'une source

```swift
protocol Source {
    var id: String { get }              // "posthog" : clé du journal, préfixe des ids du fil et des tâches
    var nom: String { get }             // "PostHog"
    var cadence: TimeInterval { get }
    func collecte(_ ctx: Contexte) async throws -> Int   // lignes écrites
}
```

`Contexte` donne `store`, `secrets`, `http`, `gcloud` et `businesses`. Les règles :

1. **Boucler sur `ctx.businesses`** et ne traiter que ceux configurés pour la source (un `appStoreId`, des comptes de la table `compte`…). Si aucun ne l'est, lever `SourceErreur.nonConfigure`. Une erreur sur un business nomme le business (`"Roleo : HTTP 401 …"`).
2. **Écrire seulement par `Store`** (`serie`, `fil`, `video`, `releve` d'une vidéo ou d'un compte, `analyse`, `app`, `rang`, `avis`, `synchroniserTaches`, `installs`, `portes`, `paiement`). Lire par `ctx.store.db.query` est permis. Grouper les écritures dans `ctx.store.lot { … }`.
3. **Métriques** : seulement celles de `Metrique` et de `donnees.md`. Une nouvelle s'ajoute aux deux.
4. **Fil** : id `<source>:<id stable chez le service>`, `at` = l'heure de l'événement, pas de la collecte. Texte court en français, sans tiret cadratin.
5. **Tâches** : `synchroniserTaches(source:business:_:)` avec la liste complète des tâches encore ouvertes chez le service ; les absentes passent à faites.
6. **Lecture seule** chez le service. Aucun POST qui modifie quoi que ce soit (les POST de requête, comme HogQL ou le graphql de Business Suite, sont permis). Seule exception, hors passage : les actions de l'écran SAV dans `Firebase+SAV` ([sources/firebase.md](sources/firebase.md) § SAV).
7. **Aucun secret** dans une erreur, un log, la base ni une sortie : ni clé, ni cookie, ni jeton de session, ni URL ou page HTML qui en contient.
8. **Erreurs** : `SourceErreur.nonConfigure` (manque un réglage), `.http` (levée par `HTTP`), `.format` (réponse qui ne ressemble pas à ce qu'on attend), `.commande` (programme local). Ne jamais renvoyer 0 ligne en silence quand le service a répondu n'importe quoi.

`HTTP` fournit `requete(url, methode:, jeton:, corps:, entetes:)`, `donnees`, `json(Type.self, req)` et `objet(req)` ; il rejoue seul sur 429 et 5xx. Ses requêtes ne portent aucun cookie automatique. `Commande.lancer(chemin, args)` et `Commande.shell("…")` lancent un programme local hors du thread principal.

## Secrets

`ctx.secrets.valeur("NOM", business)` cherche, dans l'ordre :

1. la variable d'environnement `NOM` (débogage, `NOM=… make essai`) ;
2. le Trousseau de session, service `cockpit`, compte `<business>.<NOM>` (saisi dans Réglages) ;
3. Secret Manager du `firebaseProject` du business, en REST, s'il en a un.

Le jeton Google (`GCloud`) vient des identifiants par défaut `~/.config/gcloud/application_default_credentials.json` (créés par `gcloud auth application-default login`), rafraîchis en HTTP ; sinon de `gcloud auth print-access-token`. Pas besoin que la CLI gcloud marche.

| Secret | Source | Où il est pour Roleo |
|---|---|---|
| `POSTHOG_PERSONAL_API_KEY`, `POSTHOG_PROJECT_ID` | PostHog | Secret Manager `roleo-73820` |
| `REVENUECAT_SECRET_KEY_V2` | RevenueCat | Secret Manager `roleo-73820` |
| clé `.p8` App Store Connect | App Store Connect | `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`, voir sa fiche |
| clé JSON du compte de service Play | Play Console | `~/.googleplay/<business>-play-publisher.json`, voir sa fiche |
| cookies `tiktok.com`, `instagram.com`, `facebook.com` | TikTok, Instagram, Facebook | Safari (se connecter au site dans Safari, accès complet au disque pour Cockpit), voir leurs fiches |
| note « Cockpit » de l'app Notes | Notes | accès complet au disque pour Cockpit, voir sa fiche |
| aucun | Contenu, Classements, YouTube et Firebase (jeton Google) | |

## Business

Un business = une ligne de `business` avec sa `Business.Config` (`Cockpit/Store/Business.swift`). Il vient de la graine (ci-dessous) ou de Réglages, onglet Business, « Nouveau business » ; remplir ce dont ses sources ont besoin.

| Champ | Utilisé par |
|---|---|
| `firebaseProject` | Firebase, Secret Manager |
| `posthogHost` | PostHog (avec les deux secrets PostHog) |
| `appStoreId` | App Store Connect, Classements |
| `ascIssuer` | App Store Connect : issuer de la clé API (pas un secret ; la clé `.p8` reste hors du dépôt) |
| `ascVendor` | App Store Connect : numéro de fournisseur, pour les téléchargements (rapports de ventes) ; vide, cette étape seule est sautée |
| `playPackage`, `playBucket` | Play Console : paquet Android et bucket des rapports groupés (`pubsite_prod_rev_…`, ou l'URI `gs://` copiée telle quelle) |
| `pays`, `genre` | Classements (storefronts et catégorie) |
| `contenuDir` | Contenu (dossier `bank` des fiches) |
| `objectifMensuelEUR` | écran Data |
| `evenements` | PostHog : le nom des six événements lus, `installation`, `etape` (avec sa propriété `step`), `paywall`, `essai`, `achat`, `usage` ; ceux de Roleo par défaut ([`sources/posthog.md`](sources/posthog.md)). Graine seulement, pas dans Réglages |

Un champ vide coupe la source pour ce business, sans erreur.

Les comptes vidéo (TikTok, Instagram, YouTube, Facebook) ne sont pas dans la config : ils vivent dans la table `compte` ([`donnees.md`](donnees.md)), ajoutés par la graine, dans l'écran Vidéos ou par un agent ([`runbook.md`](runbook.md)).

## Graine

Ce qui est propre à un utilisateur n'est pas dans le dépôt : son business et ses comptes sont dans `~/Library/Application Support/Cockpit/graine.json` (`Store.graine`), écrit par `/installer` sur le modèle de [`outils/graine.exemple.json`](../outils/graine.exemple.json).

- `businesses` : `id` et `nom` obligatoires ; `lettre` (l'initiale du nom par défaut), `teinte` (`menthe` par défaut) et `config`, dont chaque champ est facultatif.
- `comptes` : `business`, `plateforme`, `handle` (normalisé comme une saisie de l'écran Vidéos, `@MonApp` → `monapp`) et `actif` (vrai par défaut).

`Store.ouvrir` l'applique quand sa date de modification diffère de celle retenue dans le réglage `graine` : au premier lancement, puis après chaque modification du fichier. Un business est créé ou remplacé tel quel. Un compte n'est ajouté que s'il n'est pas déjà suivi : une pause faite dans l'app tient. Un business ou un compte supprimé dans l'app revient à la modification suivante de la graine : le retirer aussi du fichier. Pas de fichier : rien ne se passe, le cockpit démarre vide. Un fichier illisible arrête l'app au lancement avec son chemin et l'erreur de décodage.

## Essayer une source

```bash
make essai SOURCE=PostHog
```

Compile le cœur et la seule source demandée, la lance contre les vraies API sur `.cache/essai.sqlite` (pas la base de l'app) et affiche ce qu'elle a écrit : séries du passage, fil, tâches, compteurs des tables. Le gabarit est `outils/essai.swift`. Les fichiers d'aide d'une source se nomment `<Source>+Quoi.swift` pour être compilés avec elle.

## Ajouter une source

1. `Cockpit/Sources/<Nom>.swift` qui respecte le contrat, et ses tests dans `CockpitTests/` (le décodage des réponses, sur des exemples figés).
2. L'ajouter à `Registre.sources`.
3. Ses tables et métriques dans `donnees.md` (et `Metrique.swift`), sa fiche dans `sources/`, sa ligne dans le tableau plus haut.
4. `make essai SOURCE=<Nom>`, `make test`, `make build`.
