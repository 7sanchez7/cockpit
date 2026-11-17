# Contenu (fiches vidéo)

Fichier : `Cockpit/Sources/Contenu.swift`. Cadence : 15 min. Aucune clé, aucun réseau. Tests : `CockpitTests/ContenuTests.swift`.

Lit les fiches de `contenu/bank` du dépôt du business (`config.contenuDir`, `~` accepté) : relie chaque vidéo TikTok à sa fiche et rappelle les verdicts à écrire. Branchée le 13 nov. 2026.

## Les fiches lues

`<famille>/<format>/*.md` et `<famille>/<format>/fait/*.md` sous `contenuDir`. Le reste est ignoré : les fichiers à la racine (`_fiche.md`), un niveau plus haut ou plus bas, un sous-dossier autre que `fait/`.

D'une fiche on lit :

- **Le frontmatter**, entre deux lignes `---` : `format`, `statut`, `groupe`, `export`, `tiktok`, `variable`. Le commentaire de fin de ligne (`statut: publiée   # écrite → …`) est retiré, un champ vide est ignoré.
- **Le titre** : la première ligne `# ` après le frontmatter, sans la date de tête (`# 2026-09-16 — 4-astuces-bonjour-natif` → `4-astuces-bonjour-natif`).
- **Le verdict** : une ligne qui commence par `## Verdict`.
- **La date** : le `yyyy-MM-dd` en tête du nom de fichier, sinon la création du fichier.
- **La vidéo** : le champ `tiktok`, un lien `https://www.tiktok.com/@<compte>/video/<id>`. Sans lien, la fiche ne fait rien.

## Ce que la source fait

1. Pour chaque fiche liée à une vidéo, `Store.ficheVideo` : titre (l'id à défaut), format, chemin absolu de la fiche, verdict. Ne touche pas à ce que la source TikTok écrit. Format = le `format` du frontmatter, sinon le dossier : les fiches de `format-app` disent `format: mia-oral` alors que leur dossier s'appelle autrement, le frontmatter fait foi.
2. Une tâche de verdict pour chaque vidéo sans `## Verdict` sortie depuis plus de 7 jours. Sortie = `video.publiee_le` si la source TikTok l'a écrite, sinon la date de la fiche. Échéance = sortie + 7 jours (jours de Paris).

   | Champ | Valeur |
   |---|---|
   | id | `contenu:verdict:<id vidéo>` |
   | texte | `Verdict : 3 apps pour apprendre l'espagnol` |
   | étiquette | l'échéance courte, `20 oct.` |
   | ton | `alerte` passé 3 jours de retard, sinon `neutre` |
   | échéance | `2026-10-20` |
   | lien | `file:///…/fait/2026-10-13-3-apps.md` |

3. `synchroniserTaches(source: "contenu")` : un verdict écrit ferme la tâche au passage suivant. Le passage rend le nombre de vidéos plus le nombre de tâches.

Relevé du 13 nov. 2026 : 103 fiches, 19 liées à une vidéo (toutes `holaestony`), 20 lignes. Une tâche : « Verdict : 3 apps pour apprendre l'espagnol » (`7696188146974739745`, publiée le 13 oct.), échéance 20 oct., en alerte.

## Ce qui peut casser

- `contenuDir` absent ou dossier déplacé : source en gris.
- Une fiche pas en UTF-8 : le passage échoue en la nommant.
- Une fiche rangée plus profond, ou un `fait/` renommé : ignorée.
- Le titre de section `## Verdict` renommé : la tâche reste ouverte.
- Deux fiches avec le même lien : la dernière dans l'ordre des chemins gagne.
- Sans date dans le nom de fichier ni `publiee_le`, la date est la création du fichier, qu'un `git clone` remet à zéro.
