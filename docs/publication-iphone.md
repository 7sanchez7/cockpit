# Publier depuis l'iPhone

Plan du 13 nov. 2026, rien n'est codé. Ce fichier se suffit à lui-même : une session qui reprend le chantier lit ce fichier, puis [`../AGENTS.md`](../AGENTS.md).

## Le but

Tony ne va plus sur les réseaux. Il met une vidéo et une description dans le cockpit sur son iPhone, coche les réseaux voulus parmi TikTok, Instagram, YouTube et Facebook, appuie sur Envoyer, et la vidéo part partout.

## Décisions de Tony

- **Aucune API**, agrégateurs compris (Upload-Post, Blotato, TikTok Share Kit, Meta Sharing to Reels) : Tony pense qu'un post par API est bridé en vues. Le post part des **apps officielles** de l'iPhone, comme s'il le faisait à la main.
- **L'iPhone seul** : pas de Mac branché pendant la publication.
- Pas d'IA dans la boucle : un script déterministe, pas un agent qui regarde l'écran.

## Le moyen : iCTRL

[iCTRL](https://github.com/OpenMinis/iCTRL) (Apache-2.0) est un runner XCUITest installé sur l'iPhone. On le lance d'un tap, il continue de tourner après, et il expose une API JSON-RPC 2.0 sur `127.0.0.1:8200`. Il touche, tape et lit l'écran par l'arbre d'accessibilité de n'importe quelle app. Le cockpit iOS l'appelle en local, sur le téléphone même.

### Ce que voit Tony

1. Écran Publier du cockpit : vidéo, description, cases des réseaux, bouton Envoyer.
2. Après Envoyer, le téléphone travaille seul sous ses yeux, environ une minute par réseau. Une Live Activity affiche « Publication 2/4 ».
3. À la fin, un résumé par réseau : publié, ou bloqué avec l'étape et une capture.

### Ce que fait le cockpit

1. Il range la vidéo dans Photos (`PHAssetCreationRequest`), où elle devient l'élément le plus récent et donc le premier de chaque galerie. La copie reste dans Photos, car la supprimer déclenche une confirmation iOS.
2. Il lance une tâche longue `BGContinuedProcessingTask` (iOS 26), depuis le tap sur Envoyer, puisqu'elle doit partir d'une action au premier plan. Il publie sa progression à chaque étape, sinon iOS la tue.
3. Pour chaque réseau coché, il exécute la séquence suivante :
   1. `launch_app` sur l'app.
   2. `find_element` sur le bouton de création, puis `tap`.
   3. Il choisit la première vidéo de la galerie.
   4. Il touche le champ légende, puis `type`.
   5. Il touche Publier.
   6. Il vérifie le résultat avec `screen_text`.
4. Il revient au cockpit et écrit le résultat.

**Repli** si iOS coupe la tâche longue : on forke iCTRL et on ajoute une méthode `publish` dans le runner, qui n'est jamais suspendu. Le cockpit envoie un seul ordre (fichier, légende, réseaux) et peut même être fermé.

## Installation, faite par Tony

Une fois :

1. Réglages, Confidentialité et sécurité, **Mode développeur** activé.
2. Installer iCTRL signé avec son compte développeur Apple, de l'une de ces deux façons :
   - `make build` après avoir rempli `Config/Local.xcconfig`, puis Product, Test dans Xcode ;
   - `Scripts/sign-ipa.sh -i iCTRLUITests-Runner.ipa`.
3. Ouvrir iCTRL, puis approuver l'appairage sur le téléphone.

Après chaque redémarrage du téléphone, il faut remonter l'image développeur (DDI). On touche « Mount without a Mac » dans l'app iCTRL, ce qui demande LocalDevVPN et un fichier RemotePairing. À défaut, on passe par Xcode. Ensuite, on relance le runner.

## Le protocole iCTRL

Spécification relevée dans `Scripts/ictrl_rpc.py` (environ 800 lignes, stdlib Python). Avant de porter en Swift, la revérifier contre le fichier.

### Appairage

On envoie `POST /pair` avec `{"client_name":"cockpit","plain":true}`. Le mode `plain` n'est accepté que depuis localhost, ce qui est le cas du cockpit sur le téléphone. Tony approuve sur l'écran, et la réponse renvoie une clé `K` de 32 octets.

- `K` va au Trousseau, jamais dans un log.
- `tok` vaut `sha256(K)[:4]`, soit 8 caractères hex.
- La clé expire après 30 jours sans appel.
- Depuis le Mac, en réseau local, l'appairage passe par un échange X25519, que `ictrl_rpc.py` sait faire.

### Une requête `/rpc`

Le corps est chiffré puis signé. Il n'existe pas de `/rpc` en clair.

On part de ces valeurs :

- `nonce` : 16 octets aléatoires.
- `ts` : un entier en secondes. Le serveur rejette au-delà de ±120 s ou en cas de rejeu.

On dérive deux clés et un chiffré :

- `k_enc = HMAC-SHA256(K, "ictrl-v1|enc-req" || nonce)`
- `k_mac = HMAC-SHA256(K, "ictrl-v1|mac" || nonce)`
- `ct` : le JSON `{"jsonrpc":"2.0","method":…,"params":…,"id":…}`, XOR avec le flux. Le bloc `i` du flux vaut `HMAC(k_enc, nonce || be32(i))`.

Le `tag` vaut `HMAC(k_mac, "v1" || tok_octets || ts_be64 || nonce || ct)`.

On envoie `POST /rpc`, `Content-Type: application/json`, avec ce corps : `{"v":1,"tok":"<hex>","ts":<int>,"nonce":"<hex>","ct":"<base64>","tag":"<hex>"}`.

Pour lire la réponse `{ct, tag}` :

1. Vérifier `HMAC(k_mac, "resp" || nonce || ct)` en temps constant.
2. Déchiffrer avec `HMAC(K, "ictrl-v1|enc-resp" || nonce)` comme clé de flux.

Tout se fait en CryptoKit (`HMAC<SHA256>`), sans dépendance.

### Méthodes utiles

| Méthode | Paramètres |
|---|---|
| `resolve_app` | `text` (nom de l'app), renvoie le bundle id |
| `launch_app` | `bundle_id`, lie les appels suivants à cette app |
| `find_element` | `element_id` (label ou accessibility id), `element_type`, `match:"contains"`, `bundle_id`. Renvoie `ref`, `visibility`, `is_text_input` |
| `tap` | `ref` ou coordonnées |
| `type` | `text`, `submit`, `clear`. Pas de cible : toucher le champ avant |
| `page_source` | `visible_only`, `filter`, `max_elements`. Sert à relever les labels |
| `screen_text`, `screenshot` | vérifier, garder une preuve en cas d'échec |
| `logs`, `reset` | après un timeout |

Les paramètres de `tap_element` et `find_and_tap` sont dans `GET /schema`. Le mode d'emploi complet est le `SKILL.md` du dépôt iCTRL.

Bundle ids attendus, à confirmer avec `resolve_app` :

| App | Bundle id |
|---|---|
| TikTok | `com.zhiliaoapp.musically` |
| Instagram | `com.burbn.instagram` |
| YouTube | `com.google.ios.youtube` |
| Facebook | `com.facebook.Facebook` |

### Règles de fiabilité, tirées du SKILL.md

- Jamais de `sleep`. Chaque action renvoie `settle:{stable, screen_changed, waited_ms}`. Si `stable:false`, on boucle sur `screen_text` avec une limite.
- Ne jamais répéter une action « pour être sûr » : un double tap sur Publier fait deux posts. Après un timeout, on lit `logs`. Deux timeouts d'affilée bloquent l'UI, on fait alors `reset`.
- Une erreur sur une action par `ref` veut dire que rien n'a été touché. On peut retrouver l'élément et réessayer.
- Une alerte système (`system_alert:true`) se ferme par `find_element` avec `bundle_id:"com.apple.springboard"`, puis `tap`.
- Le clavier décale l'écran. On relit `page_source.keyboard` avant de toucher sous le champ.
- `type` sur un champ maison peut taper touche par touche, à environ 1 s par caractère. Les emojis ne sont pas documentés, il faut les tester.
- Face à `blocked_by:"captcha"` ou `"rate_limit"`, on s'arrête et on remonte le blocage. On ne contourne jamais.
- Client : timeout d'au moins 30 s.

## Séquences par réseau

Les labels exacts se relèvent au premier test avec `page_source`, puis s'écrivent ici. On ne les devine pas.

| Réseau | Parcours attendu | À noter |
|---|---|---|
| TikTok | + → Importer → 1re vidéo → Suivant → légende → Publier | |
| Instagram | + → Reel → 1re vidéo → Suivant → légende → Partager | |
| YouTube | + → Short → 1re vidéo → Suivant → titre → Mettre en ligne | Titre : les 100 premiers caractères de la description |
| Facebook | + → Reel → 1re vidéo → Suivant → description → Partager | |

## Côté code

Le cockpit est aujourd'hui une app macOS. Il faut :

- **Une cible iOS** dans `project.yml`, qui partage `Cockpit/Design/Theme.swift` et les composants, avec le même design (verre `.verre`, menthe, ambre, sans halos).
- **`IctrlClient`** : appairage, sceau des requêtes, appels typés. La clé vient de `Secrets`, donc du Trousseau.
- **`Publication`** : la séquence de chaque réseau, les étapes, les preuves d'échec.
- **Écran Publier** : sélecteur de vidéo (Photos ou Fichiers), description, quatre cases, Envoyer, puis la progression et le résultat.
- **Info.plist** :
  - `BGTaskSchedulerPermittedIdentifiers` pour la tâche longue ;
  - `NSAllowsLocalNetworking` pour le HTTP vers 127.0.0.1 ;
  - `NSPhotoLibraryAddUsageDescription`.
- **Une table de journal des publications**, à documenter dans [`donnees.md`](donnees.md).
- **[`../AGENTS.md`](../AGENTS.md)** : la règle « Lecture seule partout » gagne sa première exception, la publication. Cette exception est à écrire le jour où le code arrive.

## Étapes

| # | Étape | Qui |
|---|---|---|
| 1 | Mode développeur, installation d'iCTRL, DDI montée, runner lancé | Tony |
| 2 | Appairage depuis le Mac, puis script `outils/ictrl/` qui pousse une vidéo **en brouillon** TikTok, de préférence sur un compte secondaire. Relever les labels | Claude |
| 3 | Même chose en brouillon sur Instagram, YouTube et Facebook | Claude |
| 4 | Cible iOS du cockpit, `IctrlClient` en Swift, appairage localhost | Claude |
| 5 | Écran Publier et tâche longue | Claude |
| 6 | Premier vrai post sur un seul réseau, avec l'accord de Tony, puis les quatre | Tony donne le go |
| 7 | Si iOS coupe la tâche : fork du runner avec `publish` | Claude |

Rien ne se publie en vrai sans l'accord explicite de Tony.

## Limites connues

- Pendant l'envoi, le téléphone doit être déverrouillé et occupé. `unlock` réveille l'écran mais ne tape pas le code.
- Le Mode développeur reste activé. Il faut remonter la DDI après chaque redémarrage. Une mise à jour d'iOS peut casser iCTRL.
- Une app qui change son interface casse sa séquence. On la répare avec `page_source`.
- Détection des robots : le README d'iCTRL prévient que « Apps with anti-bot checks may still challenge synthesized input. » Aucun ban documenté trouvé, d'où le test en brouillon d'abord.
- iCTRL utilise des API privées. C'est sans conséquence pour un outil perso, mais il ne passera jamais l'App Store.

## Écartés

| Option | Pourquoi |
|---|---|
| API et agrégateurs | Refus de Tony (portée des posts) |
| Raccourcis | Ne savent pas toucher l'écran. Aucune des 4 apps n'a d'action « publier » |
| Siri IA (iOS 27.3) | Agit seulement par les App Intents des apps |
| Commande vocale (iOS 27) | Pilotée à la voix, une touche à la fois. Les gestes perso font environ 5 taps |
| Contrôle de sélection | Recettes à coordonnées fixes |
| Recopie de l'iPhone sur Mac | Absente en UE |
| Mac branché en USB | Tony veut l'iPhone seul |
| phoness | Trop jeune, 0 étoile |
| Open Minis + iCTRL | Agent IA avec une clé payante, lent et imprévisible. Bon pour un essai de 10 minutes, pas au quotidien |
| Boîtier ESP32 Handsy | Souris USB et AssistiveTouch, sans Mode développeur, mais lent, perd les emojis et prend le Wi-Fi. Repli si le Mode développeur devient impossible |
| Android + MacroDroid | Plus simple, mais c'est un autre téléphone |

## Sources

- iCTRL : https://github.com/OpenMinis/iCTRL (`SKILL.md`, `Scripts/ictrl_rpc.py`)
- BGContinuedProcessingTask : https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
- Open Minis : https://apps.apple.com/app/id6759188481, https://www.macstories.net/reviews/open-minis-is-the-ios-agent-i-wish-siri-ai-could-be/
- Siri IA d'iOS 27.3 : https://www.switchingtomac.com/ios-27-3-siri-ai-third-party-apps-on-screen-awareness/
- Commande vocale d'iOS 27 : https://www.apfelpatient.com/news/ios-27-voice-control-preview-of-new-siri-agentic
- Handsy : https://github.com/onehumanbeing/esp32-iphone-agent
- phoness : https://github.com/medsel06/phoness
- MacroDroid : https://www.macrodroidforum.com/wiki/index.php/Action:_UI_Interaction
