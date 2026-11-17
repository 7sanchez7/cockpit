# Données

Une base SQLite locale, `~/Library/Application Support/Cockpit/cockpit.sqlite`. Les sources l'écrivent, les écrans la lisent, rien d'autre. Le schéma est dans `Cockpit/Store/Schema.swift` ; les écritures dans `Store.swift`, les lectures des écrans dans `Cockpit/Lecture/` (`Lectures` et ses extensions par écran).

Pas de migrations : une table ou une colonne nouvelle s'ajoute dans `Schema.swift` avec `create table if not exists` ou un `alter table … add column` gardé par `colonneExiste`. Une colonne nouvelle a une valeur par défaut. Effacer la base est sans risque : la collecte suivante la remplit, seul l'historique accumulé (MRR jour par jour, relevés de vidéos, rangs) est perdu.

## Conventions

| Quoi | Format |
|---|---|
| `jour` | `yyyy-MM-dd`, fuseau Europe/Paris (`Jour.cle(date)`) |
| `heure` | 0 à 23, heure de Paris ; `-1` = la journée entière |
| `at`, `maj`, `debut`, `fin`, `cree_le`, `fait_le` | ISO 8601 UTC, `2026-11-13T14:05:00Z` (`Date.iso`) |
| `business` | l'`id` d'une ligne de `business`, `roleo` |
| argent | `$` pour RevenueCat (sa devise), `€` pour les coûts ; jamais converti en douce, une conversion passe par `Metrique.eurParUSD` (0,92, taux fixe de Roleo) et l'écran le dit |

## Tables

### `business`

Un business suivi : Roleo, l'App 2. Créé par la graine ([`collecte.md`](collecte.md) § Graine) ou dans Réglages, modifiable dans Réglages.

| Colonne | Contenu |
|---|---|
| `id` | clé courte, `roleo` |
| `nom` | `Roleo` |
| `lettre` | l'initiale de l'avatar quand le business n'a pas d'icône d'app, `R` |
| `teinte` | clé de couleur, lue par `Theme.teinte` : `menthe` (aqua), `ciel` (bleu), `lilas` (violet), `ambre` (orange) |
| `ordre` | rang dans le menu des business de la barre du haut |
| `config` | JSON de `Business.Config` : `appStoreId`, `ascIssuer` (issuer de la clé App Store Connect), `ascVendor` (numéro de fournisseur App Store Connect), `playPackage`, `playBucket`, `firebaseProject`, `posthogHost`, `contenuDir`, `pays` (codes des storefronts), `genre` (catégorie App Store), `objectifMensuelEUR`, `evenements` (noms des événements PostHog lus) |

### `serie`

Toutes les séries chiffrées, une ligne par métrique, jour et heure. Une source réécrit la ligne du jour à chaque collecte (`Store.serie`), donc la valeur d'aujourd'hui est toujours « jusqu'à maintenant ».

| Colonne | Contenu |
|---|---|
| `business`, `metrique`, `jour`, `heure` | clé primaire |
| `valeur` | le chiffre |
| `maj` | dernier relevé |

Le catalogue des métriques est fermé : une métrique nouvelle s'ajoute ici et dans `Cockpit/Store/Metrique.swift`, et le code n'écrit jamais le nom en dur (`Metrique.actifs`).

**Par store.** Les métriques de PostHog et de RevenueCat s'écrivent trois fois : le total sous le nom nu (`actifs`), puis une ligne par store suffixée (`actifs.app_store`, `actifs.play_store`, `Boutique.metrique`). La liste est `Boutique.separees`. Côté PostHog, le store se lit dans `$os` : iOS et iPadOS pour l'App Store, Android pour le Play Store ; le total des actifs, essais et ronds garde tous les OS, celui des installs vaut iOS + iPadOS + Android. Côté RevenueCat, les graphiques sont demandés avec `segment=store`, sauf `customers_new` (`segment=first_platform`) ; l'overview (MRR, abonnés, essais en cours, revenu des 28 j) ne se découpe pas, chaque store en prend la part qu'il a dans les graphiques du jour, et les stores somment au total. `telechargements` vient des stores eux-mêmes : chaque store écrit sa ligne suffixée, le total en est la somme. Les autres métriques (coûts, vidéos, notes) n'ont que le total.

| Métrique | Heure | Unité | Source | Définition |
|---|---|---|---|---|
| `actifs` | -1 | personnes | PostHog | personnes distinctes avec un événement de l'app ce jour-là, hors bruit (`$identify`, `$set`, `$feature_flag_called`, `$opt_in`, `$screen_view_exit`) |
| `actifs_j7` | -1 | personnes | PostHog | la même mesure, le même jour de la semaine précédente, jusqu'à la même heure et minute |
| `actifs_h` | 0-23 | personnes | PostHog | personnes distinctes dans l'heure |
| `installs` | -1 | installs | PostHog | premier `onboarding_started` d'une personne, iOS, iPadOS ou Android |
| `installs_j7` | -1 | installs | PostHog | idem, J-7 jusqu'à la même heure |
| `essais` | -1 | essais | PostHog | `trial_started` |
| `essais_j7` | -1 | essais | PostHog | idem, J-7 jusqu'à la même heure |
| `ronds` | -1 | ronds | PostHog | `path_round_done` |
| `ronds_j7` | -1 | ronds | PostHog | idem, J-7 jusqu'à la même heure |
| `achats` | -1 | achats | RevenueCat | premières transactions payantes du jour (nouvel abonnement payé, fin d'essai payée) |
| `mrr_brut` | -1 | $ | RevenueCat | MRR de l'overview RevenueCat, dernier relevé du jour |
| `mrr_net` | -1 | $ | RevenueCat | `mrr_brut × 0,72` (TVA puis 15 % du store) ; écrit, aucun écran ne l'affiche |
| `abonnes` | -1 | abonnés | RevenueCat | abonnements payants actifs |
| `essais_actifs` | -1 | essais | RevenueCat | essais en cours |
| `revenu_28j` | -1 | $ | RevenueCat | revenu encaissé des 28 derniers jours |
| `revenu` | -1 | $ | RevenueCat | revenu brut encaissé du jour UTC, aujourd'hui compris et encore partiel ; l'Accueil et Data l'affichent brut en euros (`Metrique.enEuros` : × 0,92) |
| `nouveaux_clients` | -1 | clients | RevenueCat | clients vus pour la première fois par RevenueCat ce jour-là (premier lancement avec le SDK), aujourd'hui compris ; par store selon `first_platform`, les clients de plateforme inconnue ne comptent qu'au total |
| `telechargements` | -1 | téléchargements | App Store Connect, Play Console | premiers téléchargements comptés par le store, que l'app ait été ouverte ou non : `telechargements.app_store` (rapport de ventes Apple, `Units` des types de premier téléchargement), `telechargements.play_store` (« Daily User Installs » du rapport groupé Play) ; le total, nu, est la somme des deux, réécrite à chaque jour écrit (`Boutique.telechargements`) ; un à trois jours de retard |
| `cout_ia` | -1 | € | Firebase | `cout_texte + cout_voix` |
| `cout_texte` | -1 | € | Firebase | tokens texte facturables du jour × prix Claude Haiku 5.5 (formule `textCostEUR` de Roleo) |
| `cout_voix` | -1 | € | Firebase | caractères de voix du jour de Paris (`aiLoad`, `v`) × prix de chaque moteur ; jour UTC avant le 17 nov. 2026 |
| `tokens_ia` | -1 | tokens | Firebase | tokens facturables du jour, somme des heures d'`aiLoad` (compteur `tk`) |
| `echecs_ia` | -1 | appels | Firebase | appels IA qui ont échoué jusqu'à l'user, somme des heures d'`aiLoad` (compteur `f`) |
| `req_ia.<fournisseur>` | -1, 0-23 | requêtes | Firebase | requêtes HTTP vers le fournisseur (`anthropic`, `mistral`, `deepinfra`, `gemini`, `fireworks` jusqu'au 12 nov. 2026 ; liste ouverte) |
| `q429_ia.<fournisseur>` | -1, 0-23 | réponses | Firebase | 429 du fournisseur |
| `err_ia.<fournisseur>` | -1, 0-23 | réponses | Firebase | autres échecs (5xx, 4xx, réseau, délai) |
| `ms_ia.<fournisseur>` | -1, 0-23 | ms | Firebase | latence moyenne |
| `messages_ouverts` | -1 | fils | Firebase | fils de messagerie où l'équipe n'a pas répondu |
| `retours_nouveaux` | -1 | retours | Firebase | retours au statut `new` |
| `vues_tiktok` | -1 | vues | TikTok | vues gagnées dans la journée, toutes vidéos des comptes du business |
| `vues_tiktok_j7` | -1 | vues | TikTok | idem, J-7 jusqu'à la même heure, quand les relevés existent |
| `note` | -1 | étoiles | Classements | note moyenne de l'app dans le premier pays de `config.pays` |
| `nb_notes` | -1 | notes | Classements | nombre de notes dans ce pays |

### `fil`

Le fil « En direct » : ce qui vient de se passer. Une source ajoute une ligne par `Store.fil` ; l'`id` est stable et commence toujours par l'id de la source (`<source>:<id chez la source>`), donc une ligne déjà vue n'est jamais réinsérée et ne renotifie pas. Le collecteur notifie les lignes nouvelles d'une source par ce préfixe.

| Colonne | Contenu |
|---|---|
| `id` | clé stable, `posthog:essai:<uuid>` |
| `business`, `at` | qui, quand (l'heure de l'événement, pas celle de la collecte) |
| `type` | `ESSAI`, `ACHAT`, `AVIS`, `MSG`, `RETOUR`, `VIDEO`, `RANG`, `IA`, `VERSION` |
| `texte` | une ligne lisible, `Essai annuel, Belgique` |
| `lien` | URL à ouvrir au clic, facultative |

### `compte` et `compte_releve`

Les comptes vidéo suivis, toutes plateformes, et leurs compteurs dans le temps. Ajoutés dans l'écran Vidéos ou par un agent ([`runbook.md`](runbook.md)). À la création de la table, le Store sème `Business.comptes` : TikTok `holaestony` et `tonyolingo`, Instagram, YouTube et Facebook `holaestony`, tous pour `roleo`.

| `compte` | Contenu |
|---|---|
| `id` | `<plateforme>:<handle>`, `tiktok:holaestony` |
| `business` | `roleo` |
| `plateforme` | `tiktok`, `instagram`, `youtube`, `facebook` |
| `handle` | le nom du compte, minuscules, `[a-z0-9._-]`, sans `@` (`Compte.handle` normalise une saisie `@x` ou un lien de profil) ; pour Facebook, le nom ou l'id de la Page |
| `actif` | 0 = en pause : la source ne le relève plus, ses vidéos restent affichées |
| `ajoute_le` | ISO UTC |

Retirer un compte (`Store.retirer`) supprime sa ligne seulement : ses relevés et ses vidéos restent en base.

| `compte_releve` | Contenu |
|---|---|
| `compte`, `at` | clé primaire, un relevé par collecte |
| `abonnes`, `videos`, `likes` | compteurs du profil, nuls si la plateforme ne les donne pas |

La pastille « +N en 7 j » d'une carte de compte est `abonnes(dernier relevé) − abonnes(dernier relevé d'il y a 7 jours ou plus)`.

### `video`, `video_releve` et `video_analyse`

Une ligne par vidéo publiée, et ses relevés de stats dans le temps. Deux sources remplissent la même ligne sans s'écraser : la source de la plateforme par `Store.video` (compte, légende, date, durée, lien), Contenu par `Store.ficheVideo` (titre, format, fiche, verdict).

| `video` | Contenu |
|---|---|
| `id` | brut pour TikTok (`7706850746066554145`, les fiches s'en servent), `<plateforme>:<id>` sinon (`instagram:DQx…`, `youtube:abc`, `facebook:123`) |
| `plateforme` | `tiktok` (défaut des lignes d'avant le 13 nov. 2026), `instagram`, `youtube`, `facebook` |
| `business`, `compte` | `roleo`, `holaestony` (le handle) |
| `legende` | légende ou titre chez la plateforme |
| `titre` | titre de la fiche `contenu/bank/…`, écrit par la source Contenu ; l'écran affiche `coalesce(titre, legende)` |
| `format` | dossier du format dans `contenu/bank` (`comment-dire`), sinon nul |
| `fiche` | chemin de la fiche, sinon nul |
| `publiee_le` | ISO UTC |
| `duree_s`, `url` | durée, lien public |
| `verdict` | 1 si la fiche a déjà une section `## Verdict` |

| `video_releve` | Contenu |
|---|---|
| `video`, `at` | clé primaire, un relevé par collecte |
| `vues`, `likes`, `commentaires`, `partages`, `enregistrements` | compteurs cumulés |
| `watch_moyen_s`, `completion` | durée moyenne regardée, taux de complétion (0 à 1), nuls si la source ne les a pas |
| `abonnes` | abonnés gagnés par la vidéo, nul si inconnu |

| `video_analyse` | Contenu |
|---|---|
| `video` | clé primaire |
| `at` | dernier passage qui l'a écrite ; remplacée à chaque passage |
| `donnees` | JSON d'`Analyse` : `watchTotalS` (temps total regardé, s), `spectateurs`, `nouveaux` et `abonnesPart` (parts de 0 à 1), `retention` (part encore là, un point par pas de la courbe), `sources`, `recherches`, `ages`, `pays`, `jalons` (listes de `{nom, part}`), `vuesParJour` (7 premiers jours) |

Seules les vidéos du compte TikTok connecté dans Safari et des Pages Facebook en ont une. Une analyse vide n'est pas écrite.

La colonne « 24 h » de l'écran Vidéos est `vues(dernier relevé) − vues(relevé le plus proche d'il y a 24 h)`.

### `app` et `rang`

Toutes les apps dont on suit le classement : les nôtres (`business` non nul) et celles des potes.

| `app` | Contenu |
|---|---|
| `id` | id App Store, `6770304361` |
| `nom`, `editeur`, `icone` | lus par `lookup` |
| `genre` | catégorie principale (`primaryGenreId`), sert à choisir les classements à lire |
| `note`, `nb_notes`, `version` | `lookup` dans le premier pays suivi |
| `business` | nul pour une app de pote |
| `suivie` | 0 pour la retirer du panneau sans perdre son historique |

| `rang` | Contenu |
|---|---|
| `app`, `pays`, `genre`, `liste`, `at` | clé primaire ; `pays` en code ISO (`fr`), `genre` (`6017` Éducation, `36` toutes catégories), `liste` (`gratuit`, `payant`, `recettes`) |
| `position` | 1 à 200 |

Chaque passage de la source Classements a un seul `at` pour toutes ses lignes ; l'index `rang_at` sert à retrouver le dernier passage et ses positions. Une app absente d'une liste au dernier passage réussi n'a pas de ligne à cet `at` : elle est « hors top 200 ». Le classement entier n'est pas gardé, seulement les apps de la table `app`.

### `avis`

Avis App Store de nos apps, lus par App Store Connect.

| Colonne | Contenu |
|---|---|
| `id` | id App Store Connect de l'avis |
| `business`, `pays` | pays en code ISO à 3 lettres comme ASC (`FRA`) |
| `note`, `titre`, `texte`, `auteur`, `at` | l'avis |
| `repondu` | 1 si une réponse développeur existe |

### `a_traiter`

L'écran SAV et le compteur ambre de la barre du haut.

| Colonne | Contenu |
|---|---|
| `id` | `manuel:<uuid>` pour une tâche à la main ; `<source>:<clé>` pour une tâche posée par une source (`asc:avis:<id>`, `firebase:msg:<uid>:<supportLastAt>` pour qu'un nouveau message rouvre une tâche, `firebase:retour:<id>`, `contenu:verdict:<id vidéo>`) |
| `business`, `texte` | à quoi ça sert, en une ligne |
| `etiquette`, `ton` | la pastille (`retard`, `FR`, `17 nov.`) et sa couleur : `alerte` (ambre) ou `neutre` |
| `echeance` | jour `yyyy-MM-dd`, facultatif ; dépassé, le ton passe à `alerte` |
| `source` | `manuel`, `asc`, `firebase`, `contenu` |
| `cree_le`, `fait_le` | `fait_le` nul tant que c'est à faire |
| `lien` | où agir : l'avis dans App Store Connect, le fil dans le dashboard admin |

Une source synchronise ses tâches avec `Store.synchroniserTaches(source:business:taches:)` : les nouvelles entrent, celles qui ont disparu de la source (avis répondu, message traité) passent à fait. Cocher une tâche automatique la marque faite ; si la source la renvoie encore, elle reste faite.

### `sav_fil`, `sav_message`, `sav_retour` et `sav_compte`

L'écran SAV, recopié de Firestore par Firebase à chaque passage ([sources/firebase.md](sources/firebase.md) § SAV). Réécrites par `Store.synchroniserSAV`, et par les trois actions de l'écran (`repondreSAV`, `fermerFilSAV`, `traiterRetourSAV`) pour que l'écran change sans attendre le passage suivant.

| `sav_fil` | Contenu |
|---|---|
| `business`, `uid` | clé primaire, un fil par compte |
| `nom` | le prénom du compte (`displayName`), nul s'il n'en a pas |
| `dernier_at`, `dernier_equipe`, `apercu` | le dernier message : ISO à la seconde (`supportLastAt`), 1 s'il vient de l'équipe, son début (`supportPreview`) |
| `ouvert` | 1 tant que l'équipe n'a ni répondu ni fermé le fil (`supportOpen`) ; un fil ouvert absent du relevé suivant passe à 0 |
| `non_vu` | 1 si la dernière réponse de l'équipe n'a pas encore été ouverte dans l'app (`supportUnread`) |

L'état affiché (`FilSAV.etat`) : ouvert, à répondre ; sinon `non_vu`, pas encore lu ; sinon dernier message de l'équipe, lu ; sinon traité (fermé sans réponse).

| `sav_message` | Contenu |
|---|---|
| `business`, `uid`, `id` | clé primaire ; `id` du document `users/{uid}/support/{id}` |
| `equipe`, `texte`, `at` | 1 si l'équipe l'a écrit, le texte, ISO |

Les 100 derniers messages d'un fil, relus seulement quand son `dernier_at` a bougé ; un fil relu remplace tous ses messages.

| `sav_retour` | Contenu |
|---|---|
| `business`, `id` | clé primaire ; `id` du document `feedback/{id}` |
| `uid` | l'auteur, nul pour un ancien retour anonyme |
| `source`, `categorie`, `etoiles` | `profile`, `rating`, `chat_report` ; `idea`, `problem`, `weird`, `language`, `off_topic`, `bug`, `other` ; la note sur 5 si le retour en porte une |
| `message`, `citation`, `conversation` | le texte de l'user, la bulle du tuteur signalée, l'id de la conversation |
| `traite`, `traite_le` | 1 au statut `done`, et quand ; un retour à traiter absent du relevé suivant passe à 1 |
| `plateforme`, `build` | `ios` ou `android`, le numéro de build de l'app |
| `at` | ISO (`createdAt`) |

| `sav_compte` | Contenu |
|---|---|
| `business`, `uid`, `email` | l'email du compte Firebase Auth, vide pour un invité ou un compte supprimé. Un uid connu avec un email n'est plus relu ; un vide l'est à chaque passage (un invité qui crée son compte) |

### `install`, `paiement` et `porte`

L'arbre des installs de l'écran Data. PostHog réécrit `install` et `porte` une fois par heure sur les 97 derniers jours (90 jours, plus de quoi comparer une semaine) ; RevenueCat remplit `paiement` pour les installs qui ont converti.

| `install` | Contenu |
|---|---|
| `business`, `jour` | jour d'install à Paris (premier `onboarding_started`) |
| `loin` | rang de l'écran du tunnel le plus loin atteint, 0 à 17 (`PostHog.ecrans`, `paywall_viewed` compris) |
| `paywall`, `essai`, `direct` | 0 ou 1 : a vu le paywall, a pris l'essai (`trial_started`), a acheté sans essai |
| `rond` | 0 ou 1 : a fini au moins un rond (`path_round_done`) |
| `j1`, `j7`, `j14`, `j30` | 0 ou 1 : a fini un rond entre N et N+1 jours après l'install ; ne compte qu'une fois le jour d'install complet (`Lectures.completJusqua`) |
| `client` | l'id RevenueCat (`distinct_id` de l'essai ou de l'achat) s'il a converti, nul sinon |
| `valeurs` | objet JSON, une liste de valeurs par `Dimension` répondue : `{"age":["18_24"],"interet":["music","series"],"pays":["FR"],"version":["2.0.3"],"build":["49"],"zone":["europe"]}`. Une dimension absente = pas répondu. `zone` est déduite du pays au décodage (`Dimension.zone(de:)`) |

| `paiement` | Contenu |
|---|---|
| `business`, `client` | un converti de `install` |
| `etat` | `paye` (un abonnement de production a rapporté), `essai` (l'un court encore), `non`, `inconnu` (pas d'abonnement de production, ou 404) |
| `lu` | ISO, dernière lecture ; `essai` et `non` se relisent toutes les 6 h sur les installs des 40 derniers jours |

| `porte` | Contenu |
|---|---|
| `business`, `jour`, `porte` | jour à Paris et porte du paywall (`properties.source` : `onboarding`, une porte de l'app, vide pour les anciennes versions) |
| `vues`, `essais`, `directs` | paywalls vus, essais gratuits, achats sans essai |

Définitions et cibles reprises du suivi hebdo de Roleo (`docs/croissance/suivi/README.md` du dépôt Roleo) : J7 en rond fini 7,5 %.

### `collecte`

Le journal du collecteur, une ligne par passage d'une source. La bande des sources de la barre du haut et l'écran Santé lisent la dernière ligne de chaque source. Les lignes de plus de 30 jours sont effacées au lancement.

| Colonne | Contenu |
|---|---|
| `source` | `posthog`, un passage couvre tous les business |
| `debut`, `fin` | ISO UTC |
| `etat` | `ok`, `erreur`, `non_configure` (clé absente, business sans config : gris, pas une panne) |
| `erreur` | message lisible, jamais une clé ni une URL avec jeton |
| `lignes` | lignes écrites |

### `plan`

Le plan de l'Accueil, la note « Cockpit » de l'app Notes ([sources/notes.md](sources/notes.md)). Vidée et réécrite à chaque passage de Notes ; aucun business.

| Colonne | Contenu |
|---|---|
| `ordre` | rang de la ligne dans la note, à partir de 0 |
| `section` | dernier titre, intertitre ou sous-titre au-dessus, `Plan` avant le premier |
| `texte` | la ligne, sans pièce jointe |
| `coche` | `1` pour une case à cocher |
| `fait` | `1` pour une case cochée |

### `reglage`

Clé, valeur texte : `ecran` (dernier écran ouvert), `business` (filtre choisi), `boutique` (store affiché sur l'Accueil et Data : `app_store`, `play_store`, absent = total), `notifs.<type>` (`essai`, `achat`… ; `0` coupe, absent = activé), `collecte.pause` (`1` met le collecteur en pause), `accueil.reseau` et `accueil.plan` (`0` = panneau replié, absent = ouvert), `posthog.horaire.<business>` (instant ISO du dernier calcul de `install` et `porte`, refaits au plus une fois par heure), `graine` (date ISO de modification de la graine déjà appliquée).
