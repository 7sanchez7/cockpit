---
name: installer
description: Installe le cockpit sur le Mac d'un nouvel utilisateur et le branche sur son business à lui (son app, ses comptes, ses clés). À lancer une fois après le clone, par `/installer`.
---

# Installer le cockpit

Tu installes le cockpit pour la personne devant toi, sur son Mac, avec son business. Le dépôt vient du cockpit de Tony : tout ce qui est propre à un utilisateur (équipe de signature, business, comptes, clés) est hors du code. Lis `AGENTS.md` et `docs/collecte.md` avant de commencer.

**Règle absolue : aucune clé ne passe dans le chat.** Tu ne demandes jamais une clé, tu ne l'affiches jamais, même tronquée, tu ne l'écris ni dans le dépôt ni dans un fichier que tu lis ensuite. La personne la colle elle-même dans l'app (Réglages, onglet Clés) ou dépose le fichier au bon endroit.

Avance étape par étape, vérifie chacune avant la suivante, et parle français.

## 1. Le Mac

- macOS 26 et Xcode 26 : `sw_vers -productVersion`, `xcodebuild -version`. `xcode-select -p` doit pointer dans `Xcode.app`, pas sur les CommandLineTools (sinon `sudo xcode-select -s /Applications/Xcode.app`, que la personne lance elle-même).
- `brew install xcodegen yt-dlp ffmpeg` (yt-dlp pour TikTok et YouTube, ffmpeg pour les premières images).
- Un certificat « Apple Development » : `security find-identity -v -p codesigning`. Aucun : la personne ouvre Xcode, Réglages, Comptes, ajoute son identifiant Apple (un compte gratuit suffit), puis « Manage Certificates », « + », « Apple Development ».

## 2. La signature

Le Team ID est l'`OU` du certificat :

```bash
security find-certificate -c "Apple Development" -p | openssl x509 -noout -subject
```

Écris `Local.xcconfig` à la racine (non versionné) :

```
// L'équipe Apple qui signe le cockpit sur ce Mac, écrite par /installer. Non versionné.
DEVELOPMENT_TEAM = <TEAMID>
```

Plusieurs certificats : demande lequel. Vérifie avec `make build` (aucun profil à télécharger : le groupe d'app est préfixé par l'équipe).

## 3. Le business

Pose les questions une par une, en disant à quoi sert chaque réponse ; tout champ est facultatif, un champ vide coupe seulement la source qui en a besoin (`docs/collecte.md` § Business) :

- nom de l'app et un id court en minuscules (`monapp`) ;
- App Store : l'id numérique de l'app (dans l'URL de sa page), l'issuer de la clé API App Store Connect et le numéro de fournisseur (Ventes et tendances) ;
- Play Store : le nom du paquet Android, et le bucket des rapports (`pubsite_prod_rev_…`) s'il l'a ;
- PostHog : l'hôte (`https://eu.posthog.com` ou `https://us.posthog.com`) ;
- les pays à suivre dans les classements (codes de `Classements.storefronts` dans `Cockpit/Sources/Classements.swift` ; un autre pays s'y ajoute avec son storefront) et la catégorie App Store (`genre`, 6017 = Éducation, liste dans `docs/sources/classements-itunes.md`) ;
- l'objectif de revenu mensuel en euros ;
- ses comptes TikTok, Instagram, YouTube et Facebook (le handle sans `@` ; pour Facebook, le nom ou l'id de la Page).

## 4. Les événements PostHog

Le cockpit lit six événements : `installation` (début du tunnel), `etape` (étape du tunnel franchie, avec une propriété `step`), `paywall`, `essai`, `achat`, `usage` (l'action qui prouve qu'on utilise l'app). Leurs noms par défaut sont ceux de Roleo (`Business.Evenements` dans `Cockpit/Store/Business.swift`). Demande à la personne les siens. Si elle ne sait pas, une fois la clé PostHog collée (étape 6), elle lance dans PostHog, onglet SQL :

```sql
select event, count() from events where timestamp > now() - interval 30 day group by event order by 2 desc limit 50
```

et te lit la liste ; propose la correspondance et fais-la valider. Un événement qu'elle n'a pas garde le nom par défaut (la série reste vide).

## 5. La graine

Écris `~/Library/Application Support/Cockpit/graine.json` sur le modèle de `outils/graine.exemple.json`, avec les réponses des étapes 3 et 4. L'app l'applique au lancement, puis à chaque fois que le fichier change : le business est créé ou mis à jour, les comptes ajoutés s'ils ne sont pas déjà suivis. Vérifie qu'il se lit :

```bash
python3 -m json.tool ~/Library/Application\ Support/Cockpit/graine.json > /dev/null
```

## 6. Lancer et brancher les clés

`make run`. Puis guide la personne, sans jamais voir les valeurs :

- **Réglages, onglet Clés**, son business : l'id du projet PostHog, une clé personnelle PostHog scopée au seul projet en lecture, la clé secrète v2 RevenueCat en lecture.
- **App Store Connect** : une clé API (Utilisateurs et accès, Intégrations, rôle Ventes ou Finance), le fichier `AuthKey_<KEYID>.p8` déposé dans `~/.appstoreconnect/private_keys/`. Tu peux créer le dossier ; elle y glisse le fichier.
- **Play Console** : la clé JSON d'un compte de service invité dans la Play Console en lecture, déposée sous `~/.googleplay/<business>-play-publisher.json` (`docs/sources/play-console.md`).
- **Accès complet au disque** pour `Cockpit.app` (Réglages Système, Confidentialité et sécurité), puis relancer l'app : sans lui, ni TikTok privé, ni Instagram, ni Facebook, ni Notes. Ensuite une session ouverte dans Safari sur tiktok.com, instagram.com et business.facebook.com.
- **Plan de l'Accueil** (facultatif) : une note de l'app Notes dont la première ligne est « Cockpit » (`docs/sources/notes.md`).

Le chemin de l'app pour l'accès au disque : `build/Build/Products/Debug/Cockpit.app` (« Montrer dans le Finder » depuis le Terminal : `open -R build/Build/Products/Debug/Cockpit.app`).

## 7. Vérifier

Santé, dans l'app, liste chaque source : verte, grise (non configurée, normal si la personne n'a pas ce service) ou rouge. Une source rouge se rejoue seule, son message s'affiche :

```bash
make essai SOURCE=PostHog
```

Corrige jusqu'à ce que tout ce qui est configuré soit vert. Puis le widget : clic droit sur le bureau, Modifier les widgets, Cockpit.

## 8. Ce qui reste propre à Roleo

Ces parties marchent d'elles-mêmes si la personne n'a rien d'équivalent (la source passe en gris), mais se lisent comme Roleo. Dis-le, et propose de les adapter sur sa copie :

- le tunnel de l'écran Data : les étapes et leurs noms dans `PostHog.ecrans`, les découpages (`Dimension`, `Cockpit/Lecture/Decoupage.swift`) ;
- `PostHog.rondsDepuis`, la date depuis laquelle l'événement `usage` est fiable ;
- les sources Firebase (charge IA, retours, SAV) et Contenu, qui lisent le Firestore et le dossier de fiches de Roleo : sans `firebaseProject` ni `contenuDir`, elles sont coupées.

## 9. Les mises à jour

`git pull` à la racine. Un conflit sur ses propres adaptations se règle comme d'habitude ; sa graine et sa signature ne sont jamais dans le dépôt, donc jamais en conflit.
