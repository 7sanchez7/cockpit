# Play Console

Fichier : `Cockpit/Sources/PlayConsole.swift`, signature dans `Cockpit/Collecte/JWT.swift`. Cadence : 3 h. Tests : `CockpitTests/PlayConsoleTests.swift`.

Les installs Play par jour, comptés par le store (que l'app ait été ouverte ou non), lus dans les rapports groupés que la Play Console dépose chaque jour dans Cloud Storage. En lecture seule.

## Ce qu'il faut

- Dans les réglages du business : **Play Store, paquet** (`app.roleo.roleo`) et **Play Console, bucket des rapports**. Le bucket se copie dans la Play Console, Télécharger des rapports, Statistiques, « Copier l'URI Cloud Storage » ; l'URI entière (`gs://pubsite_prod_rev_…/stats/installs`) se colle telle quelle, la source n'en garde que le nom du bucket (`PlayConsole.bucket`).
- La clé JSON du compte de service dans `~/.googleplay/<business>-play-publisher.json`, hors du dépôt (pour Roleo : `play-publisher@roleo-73820`, la clé de `tools/playstore/publish.py`).
- Dans la Play Console, Utilisateurs et autorisations : ce compte de service a la permission « Afficher les informations de l'application et télécharger les rapports groupés ».

Sans paquet ou sans bucket, le business est sauté ; aucun business suivi : `nonConfigure`.

## Le jeton

Un JWT RS256 signé avec la clé du compte de service (`iss` l'e-mail du compte, `scope` `https://www.googleapis.com/auth/devstorage.read_only`, `aud` le `token_uri` de la clé, une heure), échangé contre un jeton d'accès (`grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer`). La clé PKCS#8 du JSON est ramenée en PKCS#1 pour le Trousseau (`PlayConsole.pkcs1`).

## Les rapports

```
GET https://storage.googleapis.com/storage/v1/b/{bucket}/o?prefix=stats/installs/installs_{paquet}_
GET https://storage.googleapis.com/storage/v1/b/{bucket}/o/{nom encodé}?alt=media
```

On lit les rapports `installs_{paquet}_AAAAMM_overview.csv` des 4 derniers mois (`PlayConsole.mois`, de quoi couvrir 91 jours), du plus ancien au plus récent. Les autres découpes (`_country`, `_device`…) sont ignorées. Chaque fichier est en UTF-16 avec BOM, une ligne par jour ; on lit la colonne « Daily User Installs » (comptes Google qui installent l'app pour la première fois). Sans colonnes `Date` et `Daily User Installs` : erreur `.format`.

## Ce qui est écrit

**`serie(telechargements.play_store)`**, `heure = -1`, un jour par ligne de rapport, réécrit à chaque passage, puis le total `telechargements` (somme des deux stores, `Boutique.telechargements`). La carte Téléchargements de la section Acquisition de Data l'affiche ; les cartes Installs restent `installs.play_store` de PostHog (premier lancement vu par l'app), pour rester comparables à l'App Store.

## Ce qui peut casser

- **403** : la permission des rapports groupés manque au compte de service, ou elle vient d'être donnée (Google met jusqu'à 24 h à la propager).
- **Aucun fichier** : le bucket est juste mais le premier rapport n'est pas encore déposé (un jour ou deux après la mise en ligne).
- Les rapports ont un à deux jours de retard : le jour en cours manque toujours.
