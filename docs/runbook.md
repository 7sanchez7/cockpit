# Runbook

Tout se lance depuis la racine du dépôt.

## Prérequis

- macOS 26, Xcode 26 (`xcode-select -p` pointe sur Xcode, pas sur les CommandLineTools).
- `brew install xcodegen`.
- `Local.xcconfig` à la racine, non versionné : `DEVELOPMENT_TEAM = <Team ID>`, l'équipe d'un certificat « Apple Development » du trousseau (voir § Installer). Sans lui, `make` s'arrête et le dit.
- Pour un business avec `firebaseProject` seulement, identifiants Google par défaut pour Secret Manager et Firestore : `gcloud auth application-default login` (une fois ; crée `~/.config/gcloud/application_default_credentials.json`).
- La clé App Store Connect `AuthKey_<KEYID>.p8` dans `~/.appstoreconnect/private_keys/`, et l'issuer dans Réglages, onglet Business.
- `yt-dlp` pour TikTok et YouTube ([`sources/tiktok.md`](sources/tiktok.md), [`sources/youtube.md`](sources/youtube.md)), et `ffmpeg` (`brew install ffmpeg`) pour la première image des vidéos YouTube et Facebook ([`collecte.md`](collecte.md)).
- Une session ouverte dans Safari sur tiktok.com, instagram.com et business.facebook.com : les sources TikTok (stats privées), Instagram et Facebook en lisent les cookies. La source Notes lit la base de l'app Notes pour le plan de l'Accueil : une note dont la première ligne est « Cockpit », intertitres pour les sections, cases à cocher pour les tâches ([`sources/notes.md`](sources/notes.md)). Les deux demandent l'accès complet au disque pour Cockpit (Réglages Système, Confidentialité et sécurité, Accès complet au disque, ajouter `Cockpit.app`, puis la relancer), une fois. Session expirée : la source passe en gris dans Santé, se reconnecter dans Safari.

## Installer

Sur un autre Mac, pour un autre business : cloner, puis `claude "/installer"` à la racine. Le skill ([`.claude/skills/installer/SKILL.md`](../.claude/skills/installer/SKILL.md)) fait les étapes ci-dessous en posant les questions, sans jamais voir une clé. À la main :

1. Le Team ID, l'`OU` du certificat :

   ```bash
   security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
   ```

   Aucun certificat : Xcode, Réglages, Comptes, ajouter son identifiant Apple, « Manage Certificates », « + », « Apple Development ». Puis `echo "DEVELOPMENT_TEAM = <TEAMID>" > Local.xcconfig`.
2. La graine `~/Library/Application Support/Cockpit/graine.json`, sur le modèle de [`outils/graine.exemple.json`](../outils/graine.exemple.json) ([`collecte.md`](collecte.md) § Graine).
3. `make run`, puis les clés dans Réglages, onglet Clés, les fichiers de clés App Store Connect et Play à leur place (§ Prérequis, [`collecte.md`](collecte.md) § Secrets) et l'accès complet au disque.

Les bundle ids restent `com.tonysanchez.cockpit` : ils n'ont pas besoin d'être uniques entre équipes pour un build de développement.

## Commandes

```bash
make run                        # xcodegen, compile, relance l'app
make build                      # compile seulement
make test                       # tests du cœur (SwiftPM, sans interface)
make test SCRATCH=.cache/spm-ui # idem dans un autre dossier de build, si un autre build tourne
make essai SOURCE=RevenueCat    # une source contre les vraies API, sur .cache/essai.sqlite
```

L'app se signe avec l'équipe de `Local.xcconfig` et vit dans `build/Build/Products/Debug/Cockpit.app`. Sa base est `~/Library/Application Support/Cockpit/cockpit.sqlite` (Réglages, Collecte, « Montrer dans le Finder »).

## Déboguer

- **Une source en panne** : son message est dans Santé et dans la table `collecte`. Le rejouer seule : `make essai SOURCE=<Nom>`.
- **Journal** : `log stream --predicate 'subsystem == "com.tonysanchez.cockpit"'`.
- **La base** : `sqlite3 ~/Library/Application\ Support/Cockpit/cockpit.sqlite`. L'effacer est sans risque, seul l'historique accumulé est perdu.
- **Les images** : `~/Library/Caches/Cockpit/miniatures`, miniatures, premières images, avatars et icônes d'apps. Le vider fait tout retélécharger au prochain passage de chaque source.
- **Une clé** : env `NOM=… make essai SOURCE=…` pour tester ; dans l'app, Réglages, onglet Clés, la range dans le Trousseau. Ne jamais l'afficher.
- **Les diagnostics de l'éditeur** (« Cannot find type … in scope ») sont des faux positifs de SourceKit sans projet ouvert : seul `make build` fait foi.

## Le widget

Il est embarqué dans `Cockpit.app` et s'enregistre au premier lancement. L'ajouter : clic droit sur le bureau, Modifier les widgets, chercher Cockpit, glisser la taille voulue. Vérifier qu'il est connu du système :

```bash
pluginkit -mv -p com.apple.widgetkit-extension | grep cockpit
```

Il doit pointer sur `build/Build/Products/Debug/Cockpit.app/Contents/PlugIns/CockpitWidget.appex`. Un autre build de l'app (worktree, `.cache/build-*`) peut y imposer une vieille version : même remède que pour l'icône ([`design.md`](design.md) § Icône de l'app). Le widget reste vide tant que l'app n'a pas écrit `widget.json` ; il se met à jour au plus toutes les 15 min. Le fichier est dans le conteneur du groupe, que le Terminal n'a pas le droit de lire : « Operation not permitted » y est normal. Journal : `log stream --predicate 'category == "widget"'` (l'app écrit sous `com.tonysanchez.cockpit`, l'extension sous `com.tonysanchez.cockpit.widget`).

## Comptes vidéo

La graine les ajoute ([`collecte.md`](collecte.md) § Graine) ; l'écran Vidéos les ajoute, les met en pause et les retire ; un agent fait la même chose dans la base, puis relance la source (⌘R ou Santé). L'id est `<plateforme>:<compte>`, le compte sans `@`, en minuscules ; pour Facebook, le nom de la Page ou son id.

```bash
B=~/Library/Application\ Support/Cockpit/cockpit.sqlite
sqlite3 "$B" "select id, business, actif from compte"
sqlite3 "$B" "insert into compte (id, business, plateforme, handle, ajoute_le) values ('instagram:x', 'roleo', 'instagram', 'x', strftime('%Y-%m-%dT%H:%M:%SZ', 'now'))"
sqlite3 "$B" "update compte set actif = 0 where id = 'instagram:x'"   # pause, 1 pour reprendre
sqlite3 "$B" "delete from compte where id = 'instagram:x'"           # ne plus suivre : vidéos et relevés restent
```

Plateformes : `tiktok`, `instagram`, `youtube`, `facebook`. Le business doit exister (`select id from business`).

## Voir l'app depuis un agent

Sans voler le focus : lancer en arrière-plan, capturer la fenêtre seule, rendre la main à l'app qui était devant.

```bash
open -g build/Build/Products/Debug/Cockpit.app
screencapture -x -o -l <id de la fenêtre> ecran.png
```

L'id de la fenêtre se lit par `CGWindowListCopyWindowInfo` (propriétaire « Cockpit », couche 0).

Avec la permission d'accessibilité (Réglages Système, Confidentialité et sécurité, Accessibilité, accordée à l'app qui lance `osascript`), System Events pilote l'app sans clavier ni souris :

- **Changer d'écran** : `perform action "AXPress" of menu item "Vidéos" of menu 1 of menu bar item "Aller" of menu bar 1`. Pas de `keystroke "2" using command down` : un sélecteur d'apps tiers intercepte ⌘chiffre.
- **L'arbre** part de `UI element 1 of window "Cockpit"`, la page est `scroll area 1` dessous. `entire contents of window 1` rend une liste vide.
- **Un bouton** se clique par son rang, `perform action "AXPress" of button 3 of …` : SwiftUI range le libellé dans `AXAttributedDescription`, que System Events ne lit pas (`name` et `title` sont vides).
- **Réglages** : `menu item "Réglages…" of menu 1 of menu bar item "Cockpit"` ; fermer par le bouton de sous-rôle `AXCloseButton`.
- **Le panneau de la barre de menus** ne s'ouvre pas par AX : il faut un vrai clic.

Après chaque action, remettre au premier plan l'app qui l'était (`set frontmost of process "<nom>" to true`).

Sans la permission, changer d'écran passe par le réglage et une relance, `sqlite3 <base> "insert or replace into reglage values ('ecran', 'data')" && make run` (valeurs : `app`, `data`, `videos`, `sante`, `aTraiter` (SAV), `apps`).

## Réparer l'environnement

**gcloud ou yt-dlp plantent au démarrage** (`Library not loaded: /opt/homebrew/opt/openssl@4/…`) : Homebrew a installé `openssl@4` sans son lien. Réparé le 13 nov. 2026 par :

```bash
ln -s ../Cellar/openssl@4/4.0.3 /opt/homebrew/opt/openssl@4
```

Si la version change : `brew reinstall openssl@4 python@3.14`. Le cockpit n'a pas besoin de la CLI gcloud (il lit l'ADC en HTTP), mais la source TikTok a besoin de yt-dlp.

**ADC expirés** (Santé : « invalid_grant ») : `gcloud auth application-default login`.

**Notifications muettes** : Réglages Système, Notifications, Cockpit. Elles ne partent que depuis l'app signée (pas depuis `make essai`).

**Notifications sans l'icône de l'app** : macOS garde l'enregistrement de vieilles copies de Cockpit (même identifiant `com.tonysanchez.cockpit`) dont le dossier n'existe plus. Les lister : `lsregister -dump | grep -E "^path:|identifier:" | grep -B1 "com.tonysanchez.cockpit$"` ; retirer chaque copie morte par `lsregister -u <chemin de l'app>`, puis `lsregister -f build/Build/Products/Debug/Cockpit.app` (`lsregister` est dans `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/`). Fait le 13 nov. 2026 pour trois builds de `.cache/`.
