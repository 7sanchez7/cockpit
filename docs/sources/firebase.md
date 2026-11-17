# Firebase (Firestore de Roleo)

Fichier : `Cockpit/Sources/Firebase.swift`, avec `Firebase+Firestore.swift` (client REST), `Firebase+Cout.swift` (coût) et `Firebase+SAV.swift` (l'écran SAV). Cadence : 15 min. Aucune clé : le jeton du compte Google de gcloud. Tests : `CockpitTests/FirebaseTests.swift`, `CockpitTests/SAVTests.swift`.

Ce que le backend de Roleo compte lui-même dans Firestore : la charge IA heure par heure, les fils de messagerie sans réponse, les retours pas encore lus, et tout ce que montre l'écran SAV (fils, messages, retours, emails). Lecture seule pendant un passage, sur le `firebaseProject` de chaque business ; les seules écritures du cockpit chez un service sont les trois actions du SAV, sur un clic (§ SAV). Branchée et vérifiée le 13 nov. 2026, SAV ajouté le 15 nov.

## Lire Firestore en REST

```
POST https://firestore.googleapis.com/v1/projects/roleo-73820/databases/(default)/documents:batchGet
POST https://firestore.googleapis.com/v1/projects/roleo-73820/databases/(default)/documents:runQuery
Authorization: Bearer <gcloud.jeton()>
x-goog-user-project: roleo-73820
```

Les deux POST sont des lectures ; `documents:commit`, l'écriture du SAV, est décrit plus bas. `x-goog-user-project` est obligatoire avec les identifiants d'un user (ADC) : sans lui, Google refuse faute de projet de quota.

- **batchGet** : `{"documents": [noms complets], "mask": {"fieldPaths": ["m"]}}`, 100 noms par appel. La réponse est un tableau, un élément par nom : `found` (le document) ou `missing`.
- **runQuery** : `structuredQuery` avec un `fieldFilter` `EQUAL` et un `select`. Une égalité simple n'a pas besoin d'index. La réponse est un tableau ; sans résultat, un seul élément qui n'a que `readTime`.

Les valeurs sont typées : `{"integerValue": "22"}` (int64 en chaîne), `doubleValue`, `stringValue`, `booleanValue`, `timestampValue` (ISO, microsecondes), `mapValue.fields`, `arrayValue.values`, `nullValue`. `Firestore.Valeur` les décode ; un type inconnu, un entier ou un instant illisible lève.

## Charge IA : `aiLoad`

Un document par heure UTC, `aiLoad/2026-11-12T23`, écrit par `src/ai/load.ts` de Roleo par lots de 10 minutes (l'heure en cours a donc jusqu'à 10 min de retard) :

```
m.<minute "05">.<fournisseur>.n    requêtes HTTP, reprises comprises
                             .q    réponses 429
                             .e    autres échecs : 5xx, 4xx, réseau, délai
                             .ms   latence cumulée
                             .p    pic de requêtes en vol (pas lu)
m.<minute>.tk                      tokens facturables : entrée hors lecture de cache + sortie
m.<minute>.f                       appels qui ont échoué jusqu'à l'user
m.<minute>.w                       pic de la file d'attente (pas lu)
m.<minute>.v.<moteur>              caractères de voix synthétisés, par moteur (depuis le 17 nov. 2026)
expireAt                           TTL : dernière écriture + 30 jours
```

Un fournisseur est une clé dont la valeur est une carte : `anthropic`, `mistral`, `deepinfra`, `gemini`, et `fireworks` jusqu'au 12 nov. 2026. La source n'a pas de liste fermée, un nouveau fournisseur s'écrit tout seul. Seule exception, `v` : la carte des caractères de voix (`Charge.voix`), dont chaque moteur doit avoir un prix dans `CoutIA.voixUSD`, sinon le passage lève.

**Pourquoi pas `aiDays`.** Roleo tient aussi `aiDays/{jour}`, les mêmes compteurs agrégés à plat, mais en **jours UTC** : le jour serait décalé d'une heure (deux en été), aujourd'hui vaudrait 0 de minuit à 1 h, et le journalier ne serait pas la somme des heures. La source lit donc les heures dans `aiLoad` et les range à l'heure de Paris. Vérifié le 13 nov. : la somme des 24 heures UTC du 12 nov. écrite par la source égale `aiDays/2026-11-12` au compteur près (`req_ia` : anthropic 85, deepinfra 17, fireworks 3 770, mistral 2 894). 

**Fenêtre.** Quand `cout_texte` d'hier ou de J-29 manque (premier passage, trou d'un jour ou plus), 30 jours de Paris (`Firebase.joursHistorique`), aujourd'hui compris : environ 720 documents en 8 appels, 2 s. Ensuite hier et aujourd'hui : 25 à 48 documents, un appel. Les ids sont calculés (`Firebase.heures`, `Firebase.idHeure`) : lister `aiLoad` triée par nom demande un index composite. Un document absent est une heure sans appel, donc des zéros. Les 30 jours tiennent dans la rétention d'`aiLoad` : au-delà, rien à relire. Le coût IA sur 90 j s'affiche donc « sur N j » tant que le Cockpit n'a pas accumulé lui-même ses 90 jours.

| Métrique | Heure | Calcul |
|---|---|---|
| `tokens_ia` | -1 | Σ `tk` du jour de Paris |
| `echecs_ia` | -1 | Σ `f` |
| `cout_texte` | -1 | `CoutIA.euros(tokens_ia)`, voir [couts.md](couts.md) |
| `cout_voix` | -1 | `CoutIA.euros(voix:)` sur Σ `v` du jour de Paris. Pas écrit un jour sans `v` : la valeur déjà en base reste (§ Voix) |
| `cout_ia` | -1 | `cout_texte + cout_voix` (`Store.somme`) |
| `req_ia.<f>`, `q429_ia.<f>`, `err_ia.<f>` | -1, 0-23 | Σ `n`, `q`, `e`. Pour chaque fournisseur vu ce jour-là, 0 aux heures sans appel |
| `ms_ia.<f>` | -1, 0-23 | Σ `ms` / Σ `n`, seulement si `n` > 0 |

Le journalier est toujours la somme des heures. Au passage à l'heure d'hiver, les deux heures UTC qui tombent sur 2 h de Paris s'additionnent.

### Le fil `IA`

Une ligne par heure et par fournisseur quand :

- les échecs de l'heure, 429 compris, atteignent **20** (`Firebase.seuilEchecs`) : « Mistral, 25 erreurs 429 et 4 échecs cette heure » ;
- ou au moins **5** requêtes (`Firebase.minimumPanne`) ont toutes échoué : « DeepInfra ne répond plus, 6 requêtes en échec cette heure ».

Id `firebase:ia:<fournisseur>:<id du document aiLoad>` (heure UTC), `at` = début de l'heure, lien `<dashboard>/ia/`. Le texte garde le compte de la première détection ; s'il monte ensuite dans l'heure, la ligne ne change pas.

Calibrage : sur les 30 jours au 13 nov., le seuil de 20 donne 18 lignes (Fireworks 11, DeepInfra 5, Mistral 2 ; la pire, 66 échecs Fireworks en une heure), environ une tous les deux jours. « Ne répond plus » n'est jamais arrivé.

## Messages : `users`, `supportOpen == true`

```json
{"structuredQuery": {"from": [{"collectionId": "users"}],
  "where": {"fieldFilter": {"field": {"fieldPath": "supportOpen"}, "op": "EQUAL", "value": {"booleanValue": true}}},
  "select": {"fields": [{"fieldPath": "supportLastAt"}, {"fieldPath": "supportPreview"}, …]}}}
```

Un fil est ouvert tant que l'équipe n'a pas répondu (`src/support/store.ts`). Le `select` prend les champs du SAV (`Firebase.champsFil` : `supportLastAt`, `supportLastFrom`, `supportPreview`, `supportOpen`, `supportUnread`, `displayName`), relus pour l'écran.

- `messages_ouverts` (aujourd'hui, -1) : le nombre de fils ouverts.
- Une tâche par fil, clé `msg:<uid>:<supportLastAt>` (ISO à la seconde) : un nouveau message de l'user ouvre une nouvelle tâche, l'ancienne passe à faite. Texte : le début de `supportPreview` sur une ligne, 80 caractères au plus, ou « Nouveau message ». Étiquette : l'âge du dernier message (« 12 min », « 2 h », « 3 j »). Ton `alerte` après 24 h sans réponse (`Firebase.delaiMessage`). Lien `<dashboard>/messages/`.
- Fil `MSG`, id `firebase:msg:<uid>:<supportLastAt>`, `at` = `supportLastAt`, même texte.

## Retours : `feedback`, `status == "new"`

Même requête sur `feedback`, filtre `status` = `"new"`, tous les champs (le SAV les affiche).

- `retours_nouveaux` (aujourd'hui, -1) : le nombre de retours non traités.
- Une tâche par retour, clé `retour:<id>`. Texte selon la provenance, puis le début du message :

  | `source`, `category` | Texte |
  |---|---|
  | `profile`, `idea` | « Idée : … » |
  | `profile`, `problem` | « Problème : … » |
  | `rating` | « Après le bilan : … » (« Pas vraiment » à la question posée au bout d'un bilan) |
  | `chat_report` | « Signalement : … » (drapeau sous une bulle du chat) |
  | autre | « Retour : … » |

  Sans message, le mot seul. Étiquette : l'âge du retour. Ton neutre. Lien `<dashboard>/feedback/`. Passer le retour à `done` dans le dashboard ferme la tâche au passage suivant.
- Fil `RETOUR`, id `firebase:retour:<id>`, `at` = `createdAt`.

Messages et retours partent dans **un seul** `synchroniserTaches(source: "firebase", business:)`, avec la liste complète.

Le dashboard est `https://<projet>.web.app` (`Firebase.dashboard`, le site Hosting par défaut). Il n'a pas de lien vers un fil ou un retour précis : les liens mènent à la page.

## SAV

Ce que l'écran SAV montre et ce qu'il écrit, calqué sur le dashboard admin de Roleo (`src/support/` et `src/feedback/`, pages `/messages/` et `/feedback/`).

### Lire, à chaque passage

`Firebase.lireSAV`, après les fils ouverts et les retours `new` déjà lus :

- **Fils récents** : `users` triés par `supportLastAt` décroissant, 50 (`Firebase.recentsSAV`), champs `champsFil`. Un compte qui n'a jamais écrit a `supportLastAt` à null : il est écarté. Avec les ouverts, sans doublon, ça fait les fils de l'écran.
- **Retours récents** : `feedback` triés par `createdAt` décroissant, 50, tous les champs. Avec les `new`.
- **Messages** : pour chaque fil dont `supportLastAt` diffère de celui en base (`Store.filsLus`), les 100 derniers de `users/{uid}/support` (`Firebase.messagesParFil`, le `threadLimit` de Roleo), triés par `createdAt`. Un fil qui n'a pas bougé n'est pas relu.
- **Emails** : pour les uids des fils et des retours sans email connu, `POST https://identitytoolkit.googleapis.com/v1/projects/<projet>/accounts:lookup` `{"localId": [100 uids au plus]}`, même jeton et même `x-goog-user-project`. Un uid absent de la réponse (compte supprimé) ou sans email (invité) est gardé vide et relu au passage suivant.

`runQuery` avec `orderBy` sur un seul champ et `limit` : l'index simple suffit. Pour une sous-collection, le chemin est `documents/users/<uid>:runQuery`.

Champs lus :

| Document | Champ | Pour |
|---|---|---|
| `users/{uid}` | `supportLastAt`, `supportLastFrom` (`user`, `team`), `supportPreview` | le dernier message ; un fil sans `supportLastAt` lève `.format` |
| | `supportOpen` | à répondre |
| | `supportUnread` `{id, text, at}` | la dernière réponse pas encore ouverte dans l'app (`readUnread` de Roleo : les trois champs présents) |
| | `displayName` | le prénom |
| `users/{uid}/support/{id}` | `from`, `text`, `createdAt` | un message ; sans `createdAt`, `.format` |
| `feedback/{id}` | `uid`, `source`, `category`, `stars`, `message`, `quote`, `conversationId`, `status`, `handledAt`, `platform`, `appBuild`, `createdAt` | un retour ; sans `createdAt`, `.format`. Un ancien retour n'a que `message`, `status` et `createdAt` |

Tout part dans `Store.synchroniserSAV` avec le reste du passage, dans le même lot : un fil ouvert en base mais absent des ouverts lus passe à fermé, un retour à traiter absent des `new` passe à traité (traités ailleurs, dans le dashboard). Tables : [donnees.md](../donnees.md) § `sav_fil`.

### Écrire, sur un clic

`POST https://firestore.googleapis.com/v1/projects/<projet>/databases/(default)/documents:commit`, `{"writes": [...]}`, atomique. Chaque écriture est un `update` avec `updateMask` (seuls les champs nommés changent) et `currentDocument.exists` (`Firestore.ecriture`). Les valeurs typées sortent de `Firestore.valeur` : nil, Bool, Int, String, Date (`timestampValue` aux millisecondes), carte ; un autre type lève.

- **Répondre** (`Firebase.repondre`, le `sendTeamMessage` de Roleo). Le texte sans les blancs autour, 1 à 2 000 caractères Unicode (`Firebase.reponse`, le `parseText` de Roleo), sinon rien ne part. Un commit de deux écritures :
  - `users/{uid}/support/{id}`, `exists: false`, id de 20 caractères alphanumériques tiré par le cockpit : `from: "team"`, `text`, `sentBy: "cockpit"`, `feedbackId: null`, `createdAt`.
  - `users/{uid}`, `exists: true` : `supportLastAt`, `supportLastFrom: "team"`, `supportPreview` (blancs réduits à une espace, 140 caractères au plus, `…` au bout), `supportOpen: false`, `supportUnread: {id, text, at}`.

  Puis la notif, comme `notifyUser` : les appareils sont les documents `pushTokens` où `uid` vaut l'uid (champ `token`), un `POST https://fcm.googleapis.com/v1/projects/<projet>/messages:send` par appareil :

  ```json
  {"message": {"token": "…",
    "data": {"kind": "support", "message_id": "<id>", "title": "Roleo", "body": "<aperçu>"},
    "android": {"priority": "HIGH"},
    "apns": {"payload": {"aps": {"alert": {"title": "Roleo", "body": "<aperçu>"}, "sound": "default"}}}}}
  ```

  Le titre est le nom du business. Un 400 ou 404 de FCM (app désinstallée, jeton tourné) efface le document `pushTokens`, dans un commit. Le message est écrit même si la notif échoue : l'écran dit « Envoyé, la notif a échoué : … ». L'app le montre à la prochaine ouverture du fil.
- **Marquer traité sans répondre** (`Firebase.fermer`, `closeThread`) : `users/{uid}` `supportOpen: false`.
- **Marquer traité, rouvrir un retour** (`Firebase.traiter`) : `feedback/{id}` `status: "done"` et `handledAt`, ou `status: "new"` et `handledAt: null`.

Après Firestore, la même chose dans la base (`repondreSAV`, `fermerFilSAV`, `traiterRetourSAV`) : l'écran change tout de suite, les tâches `firebase:msg:<uid>:…` du fil sont cochées, celle du retour cochée ou décochée. `sav_fil.dernier_at` prend l'instant écrit dans Firestore à la seconde : le passage suivant ne relit pas le fil.

Droits : le compte Google de gcloud doit pouvoir écrire dans Firestore et envoyer par FCM (propriétaire ou éditeur du projet). Un refus remonte en 403 sous le champ.

## Ce que ça coûte en lectures

Firestore compte une lecture par document rendu, et une par requête sans résultat. Par passage : 25 à 48 `aiLoad`, plus les fils ouverts, plus les retours `new` (34 au 13 nov.), plus 100 pour les fils et retours récents du SAV, plus les messages des fils qui ont bougé (100 au plus chacun, rarement plus de quelques-uns), soit environ 190 lectures et 18 000 par jour à 96 passages. Mesuré le 16 nov. 2026 dans les journaux d'audit : environ 21 000 par jour. Le premier passage relit tous les fils : environ 760 plus quelques milliers de messages. Une réponse coûte une lecture par appareil du compte. Trier les retours dans le dashboard fait baisser la note.

**Le piège évité.** Jusqu'au 17 nov. 2026, une source Voix relisait chaque heure tous les `usage/*/days` des 30 derniers jours (un document par user actif et par jour) : environ 7 700 lectures par passage, 184 000 par jour, plus de la moitié des lectures du projet. Roleo écrit désormais ces caractères dans `aiLoad` (`v`), que ce passage lit déjà : zéro lecture de plus. Ne jamais remettre une requête de groupe (`allDescendants`) ni une lecture qui grossit avec le nombre d'users.

## Voix

Le coût de la voix des tuteurs, 75 à 90 % du coût IA depuis le passage à Voxtral 3 (28 oct. 2026). Roleo ajoute les caractères de chaque synthèse au compteur de la minute (`aiLoad.voice` dans `src/ai/speak.ts`), juste avant `settleTTS` : ce sont les mêmes caractères que le quota de l'user, rangés par heure au lieu de par user. Le prix de chaque moteur est dans [couts.md](couts.md#voix).

**Transition.** Avant le 17 nov. 2026, `cout_voix` venait de la source Voix, au jour UTC. Les heures écrites par un Roleo plus ancien n'ont pas de `v` : un jour entièrement sans `v` garde la valeur déjà en base, au lieu d'être réécrit à 0 par la relecture de 30 jours. Le jour du déploiement est partiel : sa voix ne compte que les heures qui suivent. Après le 17 déc. 2026, plus aucun jour n'est concerné.

## Ce qui peut casser

- Pas de compte Google dans gcloud, ou ADC expiré : `.nonConfigure`, ou 401. `gcloud auth application-default login`.
- Roleo change la forme d'`aiLoad` : un document sans `m`, une minute qui n'est pas une carte ou un compteur non numérique lèvent `.format`. Un compteur renommé (`tk`, `n`) passerait en zéros sans erreur : comparer à la page `/ia/` du dashboard.
- Le TTL d'`aiLoad` raccourci sous 30 jours : un passage historique écrit des zéros pour les jours perdus.
- Un filtre de plus (inégalité, tri) demande un index composite : 400 `FAILED_PRECONDITION`.
- Un fil ouvert sans `supportLastAt` ou un retour sans `createdAt` : `.format`, le passage échoue plutôt que de poser une tâche sans date.
- Le dashboard quitte le site Hosting par défaut : les liens cassent, changer `Firebase.dashboard`.
- Roleo change la forme du support (`supportUnread`, `from`, le `pushMessage` de la notif, `threadLimit`) : changer `Firebase+SAV` en même temps que `src/support/` de Roleo, sinon le cockpit écrit des fils que l'app lit mal.
- L'ADC sans droit d'écriture ou sans FCM : 403 sous le champ, rien n'est écrit dans la base.
