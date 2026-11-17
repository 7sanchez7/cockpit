# YouTube

Fichier : `Cockpit/Sources/YouTube.swift`, la lecture dans `Collecte/YtDlp.swift`. Cadence : 1 h. Aucune clé, aucun cookie. Tests : `CockpitTests/ReseauxTests.swift`.

Les Shorts des chaînes YouTube suivies (table `compte`), leurs compteurs publics et les abonnés de la chaîne. Branchée le 13 nov. 2026.

## La liste

```
yt-dlp --flat-playlist -J https://www.youtube.com/@holaestony/shorts
```

Lu : `channel_follower_count` (abonnés), `thumbnails[]` d'id `avatar_uncropped` (l'avatar), puis dans `entries[]` : `id` (id `youtube:<id>`), `title`, `view_count`, `url`, et la plus grande des `thumbnails[]`. La liste à plat n'a ni date ni likes.

## Le détail

```
yt-dlp -j --skip-download <url> <url> …
```

Une ligne JSON complète par vidéo : `timestamp`, `duration`, `like_count`, `comment_count`. Ouvert seulement pour les vidéos inconnues ou publiées il y a moins de 7 jours, au plus 20 par passage (`YouTube.ouvertesMax`) : une vieille vidéo garde la date de son premier passage. Lancé après la liste, ses champs remplacent ceux de la liste à plat.

## Ce que la source fait

Pour chaque chaîne active des business suivis : liste, détail, miniatures et avatar absents du cache, la première image des vidéos qui ne l'ont pas encore (`Miniatures.extrairePremieres`, jusqu'à 960 px de haut au lieu de 405 pour la miniature, avec le titre incrusté), puis un seul `lot` : `video` et sa ligne du fil `youtube:pub:<id>`, `video_releve`, `compte_releve` (abonnés, nombre de Shorts listés).

## Ce qui n'y est pas

Le watch time, la rétention et les abonnés gagnés par vidéo ne sont que dans YouTube Studio ou l'API YouTube Analytics, qui demande un projet Google Cloud et un OAuth du propriétaire de la chaîne. Pas branché.

## Ce qui peut casser

- yt-dlp suit mal un changement de YouTube : `brew upgrade yt-dlp`.
- YouTube limite les requêtes anonymes (« Sign in to confirm you're not a bot ») : erreur au détail, la liste reste écrite.
