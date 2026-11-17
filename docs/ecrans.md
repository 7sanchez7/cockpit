# Écrans

Chaque écran répond à une question et ne lit que la base, par `app.lectures` (`Cockpit/Lecture/`). On passe d'un écran à l'autre par la barre du haut ou ⌘1 à ⌘6 (voir [design.md](design.md) § La barre du haut). Le business affiché (Tous ou un seul), choisi dans le menu en haut à gauche ou le segmenté de l'en-tête, restreint toutes les lectures ; `app.maintenant` avance toutes les 30 s et après chaque passage du collecteur, ce qui fait relire l'écran.

Le store affiché, segmenté en tête de l'Accueil et de Data (`ChoixBoutique` : Total, App Store, Play Store ; `app.boutique`, gardé dans `reglage`), remplace chaque métrique découpée par store (`Boutique.separees` : actifs, installs, essais, ronds, MRR, abonnés, essais en cours, achats, revenu, nouveaux clients, téléchargements) par sa version du store (`Lectures.serie`). Les coûts, les vidéos et les notes restent le total. Les sections tirées des tables `install` et `porte` (Conversion, portes du paywall, arbre des installs, cohortes) ne sont pas découpées : elles restent App Store. La barre de menus et le widget montrent toujours le total.

| Écran | ⌘ | Question | Fichier |
|---|---|---|---|
| Accueil | 1 | Combien on gagne, comment va l'app, où en sont mes comptes et qu'est-ce que j'ai à faire ? | `Ecrans/EcranAccueil.swift`, `Ecrans/PanneauxAccueil.swift` |
| Data | 2 | Combien on gagne, qui convertit et qui revient, découpé jusqu'au segment ? | `Ecrans/EcranData.swift` |
| Vidéos | 3 | Quelle vidéo marche, et est-ce qu'elle amène des installs ? | `Ecrans/Videos.swift` |
| Santé | 4 | Quelle source est en panne, depuis quand, et la prod va-t-elle bien ? | `Ecrans/Sante.swift` |
| SAV | 5 | Qui m'a écrit, qu'est-ce que je lui réponds, et qu'est-ce que je dois faire d'autre aujourd'hui ? | `Ecrans/SAV.swift` |
| Apps de potes | 6 | Où sont nos apps et celles des potes dans le top 200 ? | `Ecrans/AppsDePotes.swift` |

## Accueil

Trois colonnes : les réseaux à gauche, les chiffres au centre, le plan à droite. Les deux panneaux se replient en rail par leur bouton (`app.reseauOuvert`, `app.planOuvert`, gardés dans `reglage`). Le centre suit la période choisie dans le héros (`Periode`, partagée avec Data) : Aujourd'hui (par défaut, remis à chaque lancement), 7 j, 30 j, 90 j. Aujourd'hui se compare à la même heure une semaine avant ; 7, 30 et 90 j sont des jours complets jusqu'à hier, comparés à autant de jours juste avant (`Lecture/Fenetre.swift`). Une période d'avant qui a un jour non relevé ne donne pas de comparaison. Une somme ou une moyenne dont la période elle-même n'est relevée qu'en partie dit « sur N j » à la place de l'écart (`Chiffres.couverture`) : 90 j de vues TikTok quand la source n'en a que 8.

Sous-titre : la date et « comparé à <jour> dernier à la même heure », ou « Du <premier jour> au <dernier>, comparé aux N jours d'avant ».

**Réseaux**, à gauche (`PanneauReseau`, `l.reseau()`) : les comptes suivis, les actifs d'abord. En tête, les vidéos publiées aujourd'hui sur tous les comptes actifs contre l'objectif (`LigneReseau.videosParJour` = 3 par compte actif), avec sa jauge. Par compte : avatar et logo de la plateforme, `@handle`, « 2 / 3 · il y a 3 h » (vidéos du jour depuis minuit à Paris, puis la dernière publiée) ou « en pause », abonnés et leur gain sur 7 jours. Au survol : le dernier relevé et les vues prises sur 24 h. Un clic ouvre le profil ; clic droit : ouvrir, relever maintenant, mettre en pause ou reprendre. « Gérer les comptes » ouvre l'écran Vidéos. Replié : les avatars des comptes actifs, un point vert sur ceux qui ont fait leurs 3 vidéos du jour.

Au centre :

- **Revenu en héros** (`HerosRevenu`) : le revenu de la période tel que RevenueCat le donne (`revenu`), brut (TVA et commission Apple comprises) en euros (`Metrique.enEuros`), son écart contre la période d'avant, ou « hier X € » en mode Aujourd'hui ; les essais et achats de la période ; l'aire du revenu cumulé jour par jour (30 jours en mode Aujourd'hui, la période sinon), un repère et le cumul du jour au survol. « Tous les chiffres » ouvre Data.
- **6 KPI** en grandes cartes 3 × 2 (`GrilleKPI`), la courbe sous le chiffre (14 jours en mode Aujourd'hui, la période sinon) et une note dessous :
  - Abonnés : le dernier relevé, écart brut ; note : le MRR brut en euros.
  - Essais : la somme, écart brut ; note : les essais en cours.
  - Installs : la somme, variation en % ; note : la part passée en essai. Aujourd'hui se compare à `installs_j7`, comme Essais, Actifs et Vues TikTok à leur `*_j7`.
  - Actifs : la valeur du jour ou la moyenne par jour (« Actifs / jour ») ; note : les ronds.
  - Vues TikTok : la somme, variation en % ; note : les vidéos publiées sur la période, tous comptes.
  - Rang : le rang du business principal dans son genre et son premier pays (`l.rangPrincipal()`), « hors top » au-delà de 200, delta inversé ; note : la note moyenne et le nombre d'avis.
- **Cette semaine** : le revenu brut en euros jour par jour du lundi au dimanche, en fantôme la semaine d'avant, le jour en cours mis en avant ; au-dessus, le revenu, les essais et les achats depuis lundi. Ne suit pas la période.
- **Score** (`l.score(jusqua: hier)`) : les sept jours complets jusqu'à hier contre les sept d'avant, sur cinq axes : vidéos publiées, vues TikTok, installs, conversion install → essai, revenu. Chaque axe vaut `100 × courant / avant`, plafonné à 100 ; un axe sans semaine d'avant n'est pas noté et reste au centre du radar. En dessous, la moyenne des axes notés sur 100 et le point faible (l'axe le plus bas sous 100).
- **Actifs par heure** (Aujourd'hui) : barres heure par heure contre le même jour la semaine dernière (`actifs_h`), l'heure en cours mise en avant. **Actifs par jour** (N jours) : un jour par barre, en fantôme le jour correspondant de la période d'avant.
- **En direct** : le fil de la période (`l.fil(du:au:)`, 40 au plus), achats, essais, résiliations, avis, ruptures de seuil.
- **Vidéos** : Aujourd'hui, celles qui ont pris des vues sur 24 h, les plus fortes d'abord ; sur N jours, celles publiées dans la période, les plus vues d'abord (8 au plus). Un clic ouvre la vidéo dans l'écran Vidéos (`app.videoChoisie`).

**Plan**, à droite (`PanneauPlan`, `l.plan()`) : la date du jour, puis la note « Cockpit » de l'app Notes ([sources/notes.md](sources/notes.md)), section par section dans l'ordre de la note, avec « cases faites / cases » par section. Une case cochée est barrée ; une ligne sans case a une puce. Sans note, le panneau dit pourquoi (l'erreur de la source) ou comment l'écrire. « Ouvrir Notes » ouvre l'app. Dessous, les 5 premières tâches ouvertes de la base ; leur en-tête ouvre l'écran SAV. Replié : le nombre de cases à faire et celui des tâches.

## Palette ⌘K

`Composants/Palette.swift`, au-dessus de la fenêtre. Sans saisie : les 6 écrans, « Tout relancer », pause ou reprise de la collecte, Réglages, et le choix du business. Dès qu'on tape : aussi les vidéos, les apps et les tâches qui contiennent le texte (titre ou détail, 40 au plus). Flèches pour choisir, Entrée pour ouvrir, Échap ou un clic à côté pour fermer. Une vidéo ouvre l'écran Vidéos sur elle.

## Barre de menus

`Composants/BarreMenus.swift`. L'icône porte le nombre de tâches ouvertes. Le panneau, aux couleurs du cockpit, montre l'heure du dernier passage, 4 chiffres du jour (MRR brut en euros, Actifs, Installs, Essais), le bouton « SAV » et les 5 derniers événements du fil, puis Ouvrir, Actualiser et Quitter. Fermer la fenêtre laisse la collecte tourner tant que l'app est dans la barre.

## Widget du bureau

`CockpitWidget/`, à poser sur le bureau ou dans le centre de notifications. Toujours tous les business, sur la journée. Trois tailles :

- **petit** : le revenu brut du jour en euros, celui d'hier, la courbe du revenu cumulé sur 30 jours ;
- **moyen** : le petit, plus Abonnés, Essais, Installs et Actifs avec leur écart ;
- **grand** : l'heure de la dernière collecte, le revenu du jour avec hier en pastille, les essais et achats du jour, la courbe, puis six tuiles avec sparkline : Abonnés (écart, MRR), Essais (écart, essais en cours), Installs (évolution, part en essai), Actifs (évolution, ronds), Vues TikTok (évolution, vidéos publiées), À traiter (les tâches ouvertes de l'écran SAV).

Les chiffres sont ceux de l'Accueil (`Lectures.resumeWidget()`, mêmes fonctions de `Format`). Rafraîchi au plus toutes les 15 min, voir [`architecture.md`](architecture.md) § Le widget du bureau.

## Réglages (⌘,)

`Ecrans/Reglages.swift`, quatre onglets :

- **Business** : ajouter, modifier, supprimer un business. Identité (nom, lettre et teinte de l'avatar) ; sources (id App Store, issuer et numéro de fournisseur ASC, paquet Play et bucket des rapports, projet Firebase, hôte PostHog, dossier des fiches de contenu, un champ vide coupe la source ; les noms des événements PostHog ne se changent que dans la graine) ; pays suivis, catégorie App Store et objectif mensuel en €. On ne peut pas supprimer le dernier.
- **Clés** : pour chaque secret (`PostHog.cleProjet`, `PostHog.cleAPI`, `RevenueCat.nomCle`), dit s'il est dans le Trousseau, permet de l'y ranger ou de l'effacer. Jamais la valeur. Dit aussi si la clé `.p8` ASC et les identifiants Google (ADC) sont trouvés.
- **Notifications** : un interrupteur par type d'événement du fil (`notifs.<type>`).
- **Collecte** : pause, « Tout relancer », la cadence de chaque source, l'emplacement de la base.

## Vidéos

Toutes les vidéos des comptes suivis, sur TikTok, Instagram, YouTube et Facebook : laquelle marche, laquelle convertit, et son vrai watch time.

Sous-titre : « N vidéos sur N comptes, N publiées en 7 j, dernier relevé il y a … ».

- **Comptes** (`RangeeComptes`), une rangée qui défile à l'horizontale, une carte par compte (`l.comptes()`) : avatar, @compte, plateforme (ou « en pause »), abonnés, nombre de vidéos, gain d'abonnés sur 7 jours en pastille, courbe des abonnés sur 14 jours. Un clic filtre la grille sur ce compte, un second l'enlève. Clic droit : Ouvrir le profil, Relever maintenant, Mettre en pause ou Reprendre, Ne plus suivre.
- **Suivre un compte** : la dernière carte, « + ». Plateforme, « @compte ou lien du profil » (`Compte.handle` le normalise), business s'il y en a plusieurs ; Suivre écrit la ligne de `compte` et relance la source de la plateforme.
- **Toutes les vidéos** : tri Récentes, Vues, 24 h (gain de vues), Engagement ((likes + commentaires + partages + enregistrements) / vues), Conversion (abonnés gagnés pour 1 000 vues). Filtre par plateforme quand plusieurs sont suivies. `PastilleSeuil` rappelle le seuil de 1,5 % (partages ou enregistrements rapportés aux vues). Deux vues :
  - Grille (par défaut) : une `CaseVideo` par vidéo, cases de 150 à 190 pt de large, image 9:16 (la première image de la vidéo pour YouTube et Facebook, où le titre se lit), vues, logo de la plateforme, la mesure du tri en pastille. La vidéo choisie est cernée.
  - Tableau : `TableVideos` (#, titre, âge, vues, gain 24 h, parts de partages et d'enregistrements, seuil).
  Une vidéo sans la mesure du tri passe après les autres. Le titre est celui de la fiche de contenu (son en-tête sans la date, ou sa ligne `Titre :` quand l'en-tête est un slug), sinon la légende sans hashtags, sinon « @compte, date » (`TikTok.titre`). Une vidéo n'a de fiche que si la fiche porte son lien dans `tiktok:`.
- **Détail** de la vidéo choisie (`app.videoChoisie`, sinon la première de la liste), dans `DetailChoisi` : un clic ne relance ni les requêtes ni le tri de l'écran. **Disposition fixe** : d'une vidéo à l'autre de la même plateforme, chaque bloc et chaque case restent à la même place ; une valeur absente s'écrit « — » en gris, un graphique absent garde sa hauteur avec une phrase, une liste de parts garde ses 6 lignes. Le détail n'a pas de défilement à lui : la rangée prend sa hauteur, la page défile, la grille défile dans cette hauteur. En haut à droite, l'état du verdict de la fiche (ambre s'il manque après 7 jours) et le seuil. Dans l'ordre :
  - en-tête sans image (la vidéo est cernée dans la grille) : titre sur deux lignes avec, sur la même ligne à droite, les liens vers la vidéo et la fiche ; plateforme, compte, date et âge, durée, format ; vues et gain sur 24 h ;
  - **Ce qui l'a fait percer** : le levier de la vidéo (voir plus bas), « Accroche : 58 % encore là à 3 s », en vert sur fond vert si la vidéo a plus de vues que la médiane de son compte (elle a percé), sinon en rouge sur fond rouge et titré « Sous la médiane des vues, son meilleur atout » ; gris sans levier ; dessous, mieux que quelle part des vidéos du compte, la médiane, et la corrélation de la mesure avec les vues ;
  - **Visionnage**, 9 cases : visionnage moyen sur la durée, encore là à 3 s, complétion, temps total, spectateurs, nouveaux spectateurs, vues d'abonnés, abonnés gagnés, abonnés pour 1 000 vues. Note dessous : « Stats privées relevées il y a … », ou pourquoi elles manquent pour la plateforme (compte TikTok pas connecté dans Safari, API YouTube Analytics pas branchée, Page absente du Business Suite, Instagram pas branché) ;
  - **Engagement** : taux d'engagement, likes, commentaires, partages, enregistrements, chacun avec sa part des vues (partages et enregistrements en blanc au-dessus du seuil) ;
  - TikTok : courbe de rétention. Son survol pose un curseur : trait vertical, point et une bulle opaque, « 41,3 % » en gros et « encore là à 12 s » dessous ;
  - vues relevées (`l.releves(id)`) ;
  - TikTok : vues des 7 premiers jours, puis les parts sur deux colonnes : sources de trafic et recherches, âges et pays. Facebook : jalons de visionnage.

  La case du levier est cernée dans Visionnage ou Engagement, de la même couleur que le panneau (vert ou rouge).

**Levier d'une vidéo** (`Lecture/Percee.swift`, calculé à l'affichage, rien en base). La base de comparaison est son compte : même plateforme, même @, vidéos vues. Mesures, chacune rapportée aux vues : accroche (part encore là à 3 s, `retention[3]` de `video_analyse`, `l.accroches()`), visionnage (watch moyen / durée), complétion, likes, commentaires, partages, enregistrements, abonnés pour 1 000 vues. Pour chaque mesure présente sur au moins 8 vidéos du compte : la corrélation de rang de Spearman entre la mesure et les vues (le poids), et le rang de la vidéo (part des autres vidéos du compte sous elle, ex aequo comptés à moitié). Le levier est la mesure qui maximise (rang − 0,5) × poids, parmi celles de poids positif où la vidéo dépasse la médiane ; aucune sinon. « Nouveaux spectateurs » n'est pas une mesure : il suit les vues parce que la vidéo perce (0,83 sur holaestony), il ne l'explique pas. Sur holaestony le 13 nov. 2026, 105 vidéos dont 22 avec rétention : accroche 0,67, visionnage 0,43, watch moyen en secondes 0,23, abonnés pour 1 000 vues 0,18, likes 0,16, complétion 0,16, enregistrements 0,14, commentaires −0,01, partages −0,06, durée −0,21. Un agent qui cherche pourquoi une vidéo a percé part de ce levier, puis lit la vidéo elle-même (ses 3 premières secondes quand c'est l'accroche).

Lit `compte`, `compte_releve`, `video`, `video_releve`, `video_analyse`, la fiche de contenu (`Lectures+Videos.swift`) et les images en mémoire ou dans le cache disque (`Composants/Miniature.swift`, voir [design.md](design.md)), sans réseau. Suivre, mettre en pause et ne plus suivre un compte sont des écritures de l'écran ; un agent fait la même chose dans la base (voir [runbook.md](runbook.md) § Comptes vidéo).

## Apps de potes

Où sont nos apps et celles des potes dans le top 200 de l'App Store, pays par pays.

- **Top 200** : une ligne par app suivie, les nôtres d'abord (pastille « à nous ») : icône, éditeur, catégorie, note. Une colonne par pays des business affichés : le rang au dernier passage de Classements et les places gagnées depuis la veille (vert si elle monte, rouge si elle descend), « hors top » si l'app a été lue et n'y est pas. Bascules Gratuit, Payant ou Recettes, et sa catégorie ou toutes (36).
- **Détail** de l'app choisie : son rang sur 30 jours, un pays à la fois, axe inversé (1er en haut), un jour hors top coupe la ligne ; la grille pays par liste. « Ne plus suivre » pour une app de pote seulement.
- **Ajouter** : un id ou un lien App Store. La fiche est lue sur iTunes tout de suite (`Classements.ajouterApp`), les rangs arrivent au prochain passage ou avec ⌘R.

Lit `app` et `rang` (`l.apps()`, `l.rangJours`) et les icônes du cache. L'ajout d'une app est le seul accès réseau d'un écran (sa fiche et son icône) : suivre un compte vidéo ne fait que relancer la source.

## Data

Toute la data de l'app sur la période de l'en-tête, la même que l'Accueil (`app.periode`, `Fenetre`), en cinq sections.

**Par build** : le menu « Tous les builds » de l'en-tête liste les builds des installs, le plus récent d'abord, avec leur version et leurs installs (`l.builds()`). Un build choisi (`app.build`, pas gardé au relancement) remplace la période, qui perd sa pilule ; recliquer une période en sort. La fenêtre devient la vie du build, de son premier à son dernier jour d'install, et ne restent que trois sections, filtrées sur lui (`Build.filtre`) : Conversion (sans les portes du paywall), l'arbre (le build en racine du fil d'Ariane) et Rétention (le taux sur toutes ses cohortes complètes, toutes en table). Chaque taux se compare en points au build d'avant qui a au moins `Segment.minimum` installs, sur toute sa vie à lui ; le sous-titre dit lequel. Argent, Acquisition et Usage ne se découpent pas par build. Pour voir tous les builds côte à côte, l'arbre se découpe par Build.

- **Argent** : 8 KPI, MRR, Revenu de la période, Abonnés et Essais actifs (le dernier relevé), Achats, Revenu 28 j, Coût IA (texte et voix) et Coût voix (une hausse en rouge). Puis l'objectif (le MRR du jour face à la somme des objectifs mensuels, jauge, reste à gagner, rythme des 30 derniers jours, date d'arrivée si elle tombe dans les 5 ans), la courbe du MRR, les achats par jour et les achats et essais du fil. Tout montant est en euros : RevenueCat brut (TVA et commission Apple comprises, comme son tableau de bord) converti à `Metrique.eurParUSD` (`Metrique.enEuros`), les coûts déjà en euros. Le net n'est affiché nulle part.
- **Acquisition** : 3 KPI qui suivent le store choisi. Téléchargements (`telechargements` : comptés par le store, app ouverte ou non, un à trois jours de retard ; vide tant que le numéro de fournisseur App Store et le bucket Play ne sont pas saisis), Installs (`installs` : premier lancement vu par PostHog) et Nouveaux clients (`nouveaux_clients` : premier lancement vu par RevenueCat).
- **Conversion** : les installs de la période et ce qu'ils ont fait depuis (table `install`). 8 KPI : Installs, Paywall vu, Essais gratuits, Payants, Install → essai, Install → payant, Essai → payant, Retour J1, les taux comparés en points à la période d'avant quand les installs la couvrent entière. Payant veut dire que RevenueCat les a vus payer (`paiement`), après un essai ou sans. **Portes du paywall** : d'où il s'ouvre (fin du tunnel ou porte de l'app), vues, essais, achats directs et conversion (`porte`).
- **Arbre des installs** (`Ecrans/ArbreInstalls.swift`) : un nœud est l'ensemble des installs de la période qui passent tous les filtres du chemin (`app.chemin`, des `Filtre`). On descend en cliquant :
  - une marche de l'**entonnoir du nœud** (Paywall vu, Essai gratuit, Payant) : garde ceux qui l'ont franchie ;
  - un écran du **tunnel d'onboarding** du nœud (`l.tunnel`) : garde ceux qui l'ont passé, un seul écran à la fois ;
  - une valeur de **Comparer par** : le nœud découpé par une des 16 dimensions (âge, source, motivation, blocage, niveau, offre, zone, pays, build…, le build le plus récent d'abord), une ligne par valeur avec installs, paywall, essai, payant, essai payé, rond fini, J1 et J7, chaque taux sur sa base. Un clic sur la valeur garde ses seuls installs, puis la découpe passe à la dimension suivante pas encore posée ; l'œil barré l'écarte (`Filtre.sauf`) et garde tous les autres, sur la même dimension : écarter « Afrique » dans Zone retire tous les pays d'Afrique. Un en-tête trie ; un taux sur moins de `Segment.minimum` (30) installs est grisé et trié en dernier, le meilleur taux fiable de chaque colonne est en blanc vif, jamais un taux à 0. Les installs d'avant qu'une question soit posée (`Dimension.mesureeDepuis`) forment la ligne « Pas mesuré (avant le …) », toujours en dernier et jamais mise en avant ; une réponse vide dit « Sans réponse », sauf compte (« Pas lié »), offre (« Ni essai ni achat »), pays et zone (« Inconnu »). Intérêt et blocage acceptent plusieurs réponses : leurs parts se recoupent.

  Le **fil d'Ariane** en haut dit le chemin, du plus large au plus fin, avec les installs de chaque nœud : un clic remonte, la croix retire ce seul filtre, « Tout effacer » revient à la racine. L'entonnoir donne chaque marche en compte et en part des installs du nœud, l'écart en points avec le nœud du dessus (vert s'il gagne, rouge s'il perd, gris sous 30 installs), ce que perd chaque passage, puis 8 tuiles : achats sans essai (des tentatives, cartes refusées comprises : Payant dit lesquels ont été encaissés), essais en cours, convertis à vérifier (pas encore lus par RevenueCat), rond fini, retours J1 et J7, part des installs de la période et du nœud au-dessus. Rond fini et retours ne comptent que les installs depuis le 15 oct. 2026 (`PostHog.rondsDepuis`), et un retour JN que les jours d'install qui ont eu tout leur temps (`completJusqua`).
- **Rétention** : retour J1, J7, J14 et J30 (un rond fini N jours après l'install, pas une app ouverte : plus bas que la rétention des notes de Roleo), pondérés par les installs sur les dernières cohortes complètes (7 en mode Aujourd'hui, la période sinon), écart en points contre autant d'avant. **Cohortes** : une ligne par jour d'install depuis le 15 oct. 2026, la plus récente en haut, l'opacité blanche d'une case suit son taux dans sa colonne ; une case reste vide tant que le jour n'est pas atteint.
- **Usage et coûts** : Actifs (par jour sur N jours), Ronds finis, Ronds par actif, Coût IA pour 100 actifs. Sur une période relevée en partie, les deux ratios ne comptent que les jours relevés des deux séries.

Lit `install`, `paiement` et `porte` (`Lectures+Data.swift`), les séries et le fil (`Lectures+Argent.swift`).

## Santé

Les sources répondent-elles, l'IA tient-elle, combien coûte la journée.

- **4 KPI** : sources en panne (pastille « n ok »), coût IA du jour et sa part de voix, échecs IA du jour et le total sur 7 jours, messages ouverts et retours nouveaux.
- **Sources** : état, cadence, dernier passage, durée (« < 1 s » sous la seconde), lignes écrites, dernier succès (`l.derniersSucces()`), l'erreur en clair en ambre sous la ligne. Un bouton relance une source, même en pause ; l'interrupteur « Collecte en pause » est en tête du panneau.
- **IA par fournisseur**, aujourd'hui ou hier : requêtes, part du total, part de 429, part d'erreurs, latence moyenne (`req_ia.*`, `q429_ia.*`, `err_ia.*`, `ms_ia.*`), et les requêtes par heure empilées par fournisseur.
- **Coût IA sur 14 jours** : une barre par jour, texte et voix, coût et part de voix au survol, total du mois. La voix suit le jour UTC.
- **Journal** : les 30 derniers passages, filtrables par source.

Lit `collecte` (`derniersPassages`, `derniersSucces`, `journal`), `l.fournisseursIA` et les séries `cout_ia`, `cout_voix`, `echecs_ia`, `messages_ouverts`, `retours_nouveaux` (`Lectures+Sante.swift`).

## SAV

Le dashboard admin de Roleo (pages Messages et Retours) dans le cockpit : lire un fil, répondre, marquer traité, puis le reste de ce qu'il faut faire aujourd'hui. Sous-titre : « 2 fils à répondre, 5 retours à traiter », ou « Rien à répondre » (`l.nbSAV()`). En tête, à droite : le point d'état de Firebase, « lu il y a 4 min » (l'erreur au survol) et le bouton qui relance la source.

En haut, deux panneaux de même hauteur :

- **Fils** (`l.filsSAV()`, 100 au plus) : les ouverts d'abord, puis du plus récent au plus ancien. Par fil : le prénom, sinon l'email, sinon « Invité » ; l'âge du dernier message ; son début, précédé de « Équipe : » s'il vient de nous ; l'état en pastille, « À répondre » (ambre), « Pas encore lu » (accent, notre réponse n'a pas été ouverte), « Lu » (vert), « Traité » (fermé sans réponse). Un clic ouvre le fil (`app.filChoisi`, le premier par défaut).
- **Conversation** : le nom, l'email et l'uid (sélectionnables), les messages du fil (`l.messagesSAV`, l'user à gauche, l'équipe à droite, le dernier en bas, `Taille.conversation` de haut), puis la réponse : un champ de `Taille.reponse`, le compteur « n / 2000 » (rouge au-delà), « Marquer traité sans répondre » tant que le fil est ouvert, et « Envoyer » (⌘↩). Sous le champ, ce qui s'est passé : « Envoyé et notifié », « Envoyé, aucun appareil à notifier », « Envoyé, la notif a échoué : … » ou l'erreur. Un compte qui n'a jamais écrit peut recevoir un premier message.

En bas, deux colonnes :

- **Retours** (`l.retoursSAV(traites:)`), segmenté À traiter, Traités, Tous ; dix cartes, puis « Voir les N ». Par carte : la provenance (Profil, Note, Signalement), la catégorie (Idée, Souci, Réponse bizarre, Faute ou mauvaise langue, Hors sujet, Bug de l'app, Autre ; ambre pour Souci et Bug), la note sur 5 (ambre à 2 ou moins), l'âge ; la bulle du tuteur signalée entre guillemets, le message ; en pied, l'email (ou Invité, Anonyme), l'appareil et le build, « traité le … ». « Répondre » ouvre le fil de son auteur et remonte en haut de l'écran ; « Marquer traité » ou « Rouvrir ».
- **Le reste** : les tâches ouvertes qui ne sont ni un message ni un retour, rangées par genre (Avis App Store, À la main, Verdicts de vidéos, Autres), chacune avec son compteur, ambre si le groupe contient une alerte ou un retard. Les groupes urgents d'abord, l'urgent d'abord dans un groupe ; huit lignes, puis « Voir les N ». Sans tâche : « Rien d'autre à traiter. » et l'heure du dernier passage d'App Store Connect et de Contenu. Puis **Ajouter** à la main (un texte, une échéance facultative, rattaché au business affiché, à aucun si « Tous » en montre plusieurs ; Entrée valide) et **Faites, 7 jours**, repliées (`l.tachesFaites(jours: 7)`, sans les messages ni les retours).

Les tâches des messages et des retours restent dans `a_traiter` : elles font le compteur ambre de la barre du haut, de la barre de menus et du widget, et l'Accueil les montre. Répondre à un fil ou le fermer coche ses tâches ; traiter un retour coche la sienne, le rouvrir la décoche.

Écritures : les trois actions du SAV, seules écritures chez un service, passent par `AppState` (`repondre`, `fermer`, `traiter`) vers `Firebase+SAV`, écrivent dans Firestore puis dans la base ([sources/firebase.md](sources/firebase.md) § SAV) ; une erreur s'affiche sous le champ ou la carte. Dans la base seulement : cocher ou décocher une tâche, ajouter ou supprimer une tâche manuelle (les seules supprimables). Une tâche cochée l'est par sa clé : la source qui la repose ne la rouvre pas.
