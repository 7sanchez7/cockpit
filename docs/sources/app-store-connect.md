# App Store Connect

Fichier : `Cockpit/Sources/AppStoreConnect.swift`. Cadence : 1 h. Clé : `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8`. Tests : `CockpitTests/AppStoreConnectTests.swift`.

Les avis App Store de nos apps, les tâches « répondre à l'avis », les changements d'état des versions et les téléchargements par jour, par l'API officielle (`https://api.appstoreconnect.apple.com/v1`), en lecture. La note et le nombre de notes ne viennent pas d'ici mais de [Classements](classements-itunes.md). Testé et branché le 13 nov. 2026.

Un business est lu s'il a `appStoreId` et `ascIssuer` (config). Aucun : `nonConfigure`.

## Le jeton

Un JWT ES256 signé avec CryptoKit, refait à chaque passage :

```
en-tête  {"alg":"ES256","kid":"<KEYID>","typ":"JWT"}
charge   {"aud":"appstoreconnect-v1","exp":<iat + 19 min>,"iat":<maintenant>,"iss":"<ascIssuer>"}
signature  P256 sur "<en-tête>.<charge>" (base64url sans =), au format brut r‖s de 64 octets
```

- La clé est le premier fichier `AuthKey_*.p8` du dossier (ordre alphabétique). `KEYID` vient du nom du fichier. Elle ne sort jamais du dossier : ni dans le dépôt, ni dans la base, ni dans un journal.
- `ascIssuer` est l'issuer de la clé (App Store Connect, Utilisateurs et accès, Intégrations). Ce n'est pas un secret, il vit dans la config du business.
- Apple refuse un `exp` à plus de 20 min de `iat`.
- Pas de clé : `nonConfigure`. Clé illisible : `nonConfigure` aussi, sans rien en citer.

## Les avis : `customerReviews`

```
GET /v1/apps/{appStoreId}/customerReviews?sort=-createdDate&limit=200&include=response
→ {"data":[{"id":"…","attributes":{"rating":5,"title":"Top","body":"…","reviewerNickname":"…",
            "createdDate":"2026-11-11T00:18:14-08:00","territory":"FRA"},
           "relationships":{"response":{"data":null}}}],
   "included":[…], "meta":{"paging":{"total":5,"limit":200}}}
```

- `createdDate` porte un décalage (`-08:00`), pas un `Z`.
- `territory` est le code pays à 3 lettres, gardé tel quel dans `avis.pays`.
- `include=response` remplit `relationships.response.data` : nul = pas de réponse. Sans `include`, la relation n'a que des liens et tout semblerait sans réponse.
- 200 avis tiennent sur une page ; au-delà, les plus anciens ne sont plus relus (ils restent dans la base).

Tous les avis s'écrivent dans `avis` (une réponse ajoutée depuis met `repondu` à 1).

### Les tâches

Une par avis de **3 étoiles ou moins sans réponse**, via `synchroniserTaches(source: "asc")` : un avis répondu sort de la liste, sa tâche passe à fait.

| Champ | Valeur |
|---|---|
| clé | `avis:<id>` (id de tâche `asc:avis:<id>`) |
| texte | `Répondre à Tom, « Nul »` (titre coupé à 60 caractères, sans titre : `Répondre à Tom`) |
| étiquette | la note, `1 ★` |
| ton | `alerte` pour 1 ou 2 étoiles, `neutre` pour 3 |
| lien | `https://appstoreconnect.apple.com/apps/{appStoreId}/distribution/activity/ios/ratingsResponses` |

### Le fil `AVIS`

Les avis de moins de 7 jours : id `asc:avis:<id>`, `at` = `createdDate`, texte `★★★★★ Top` (étoiles pleines et vides, puis le titre), même lien que les tâches.

## Les versions : `appStoreVersions`

```
GET /v1/apps/{appStoreId}/appStoreVersions?limit=5
→ {"data":[{"id":"…","attributes":{"platform":"IOS","versionString":"2.0.3","appStoreState":"READY_FOR_SALE",
            "appVersionState":"READY_FOR_DISTRIBUTION","createdDate":"2026-11-01T14:25:38-08:00"}}]}
```

On ne suit que la version iOS la plus récente (`createdDate`) : c'est elle qui change d'état. Une ligne `VERSION` par état, id `asc:version:<id>:<appStoreState>`, donc une nouvelle ligne à chaque changement. Texte : `2.0.4 en examen`, `2.0.3 en vente`. Lien : `https://appstoreconnect.apple.com/apps/{appStoreId}/distribution`. `at` : `createdDate` au premier passage, l'heure du passage ensuite (le changement a eu lieu dans l'heure).

| `appStoreState` | Texte |
|---|---|
| `PREPARE_FOR_SUBMISSION` | en préparation |
| `READY_FOR_REVIEW` | prête pour l'examen |
| `WAITING_FOR_REVIEW` | en attente d'examen |
| `IN_REVIEW` | en examen |
| `ACCEPTED` | acceptée |
| `PENDING_DEVELOPER_RELEASE` | validée, à publier |
| `PENDING_APPLE_RELEASE` | validée, publication par Apple |
| `PROCESSING_FOR_APP_STORE` | en traitement |
| `READY_FOR_SALE` | en vente |
| `REJECTED`, `METADATA_REJECTED`, `INVALID_BINARY` | refusée, métadonnées refusées, binaire invalide |
| `DEVELOPER_REJECTED` | retirée de l'examen |
| `WAITING_FOR_EXPORT_COMPLIANCE` | en attente de conformité export |
| `REMOVED_FROM_SALE`, `DEVELOPER_REMOVED_FROM_SALE` | retirée de la vente |
| `REPLACED_WITH_NEW_VERSION` | remplacée |
| autre | le code en minuscules |

## Les téléchargements : `salesReports`

```
GET /v1/salesReports?filter[frequency]=DAILY&filter[reportType]=SALES&filter[reportSubType]=SUMMARY
    &filter[vendorNumber]={ascVendor}&filter[reportDate]=AAAA-MM-JJ&filter[version]=1_1
Accept: application/a-gzip
```

- Il faut `ascVendor`, le numéro de fournisseur (App Store Connect, Paiements et rapports financiers, en haut à gauche ; ou Ventes et tendances, Rapports). Il ne se lit pas par l'API, ce n'est pas un secret : il se saisit dans Réglages. Sans lui, l'étape est sautée, avis et versions continuent.
- La réponse est un TSV compressé en gzip, une ligne par produit, pays et type. On garde les lignes dont `Apple Identifier` est l'`appStoreId` du business et dont `Product Type Identifier` est un premier téléchargement (`1`, `1F`, `1T`, `F1`, `1E`, `1EP`, `1EU` : `AppStoreConnect.premiersTelechargements`), et on somme `Units`. Retéléchargements (`3F`…) et mises à jour (`7F`…) sont exclus. Sans ces trois colonnes : erreur `.format`.
- Un jour sans aucune vente rend 404. Le rapport arrive le lendemain, parfois plus tard : un 404 de moins de 3 jours (`retardVentes`) est laissé pour le passage suivant, plus vieux il vaut 0.
- Fenêtre : les 90 jours finissant hier (`historiqueVentes`), seulement ceux que la base n'a pas encore (`AppStoreConnect.aRelire`) : un rapport publié ne change plus. Premier passage : jusqu'à 90 appels, ensuite un par jour.

Écrit **`serie(telechargements.app_store)`**, `heure = -1`, puis le total `telechargements`, somme des deux stores (`Boutique.telechargements`).

## Ce que la source fait

Pour chaque business : le jeton, `customerReviews`, `appStoreVersions`, puis un `lot` (avis, fil) et la synchro des tâches ; enfin, si `ascVendor` est saisi, un `salesReports` par jour manquant. 2 appels, plus les jours de ventes.

Relevé du 13 nov. 2026 à 1 h : 5 avis, tous à 5 étoiles, tous en France, aucun répondu, donc 0 tâche. Fil : `★★★★★ Top` (11 nov.) et `2.0.3 en vente`. 7 lignes au premier passage, 5 au suivant (les deux lignes du fil existent déjà).

## Ce qui peut casser

- Clé révoquée ou issuer faux : HTTP 401, Santé le montre. Une nouvelle clé : déposer `AuthKey_<KEYID>.p8` dans le dossier ; s'il y en a plusieurs, la première par ordre alphabétique sert.
- Apple marque `appStoreState` comme déprécié au profit de `appVersionState`. S'il disparaît, le décodage échoue (`.format`) : passer à `appVersionState` (`READY_FOR_DISTRIBUTION`, `PROCESSING_FOR_DISTRIBUTION` sont déjà traduits).
- Plus de 200 avis : les anciens ne sont plus relus, une réponse tardive à l'un d'eux ne ferme pas sa tâche.
- Une base créée avant `ascIssuer` n'a pas ce champ : le saisir dans Réglages, sinon la source reste « non configurée ».
- Numéro de fournisseur faux : `salesReports` rend une erreur et le passage échoue, Santé le montre. La clé doit avoir un rôle qui voit les ventes (Finances, Ventes ou Admin).
