# Journal des changements

Fork de [Artzainnn/ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar). Format : une section par version, la plus récente en haut.

## 1.9.0 : 19 octobre 2026

### Ajouté
- **Budget du jour** : « Aujourd'hui : 9 % sur 24 % conseillés », en gris dans le budget, en jaune au-delà de 80 %, en rouge avec « dépassé de N % » et « les jours suivants auront d'autant moins ». Le budget est calculé à minuit : il ne rétrécit pas quand on consomme, donc le dépassement reste visible.
- **Planning de la semaine depuis minuit** : le bloc « auj. » est le budget complet de la journée, avec une jauge qui se remplit (« 9 / 22 % »), rouge quand il est dépassé. Le gris à gauche devient « avant auj. ».
- **Prévenir des nouvelles versions** : lecture de la dernière release GitHub toutes les 6 h (requête publique, aucune donnée envoyée), bandeau « Version X disponible · Voir » dans le popover et une notification par version. Désactivable, avec « Rechercher maintenant ».
- **Organisation suivie** : si le compte claude.ai a plusieurs organisations (personnel, équipe), un sélecteur dans Réglages > Connexions choisit laquelle suivre (par défaut, la dernière utilisée sur claude.ai).
- **CI GitHub** : tests et compilations (développement et release) à chaque push. **Release GitHub** avec l'application zippée et sa somme SHA-256 à chaque tag `vX.Y.Z` (non notarisée : clic droit > Ouvrir).
- **Régression visuelle** : `scripts/visual-check.sh` compare 15 écrans de démonstration (clair et sombre) à des références (`tests/visual/ref`), `--update` après un changement voulu.

### Modifié
- `scripts/test.sh` s'arrête si la compilation des tests échoue (avant, il pouvait exécuter un ancien binaire).
- Carte « Budget d'aujourd'hui » : le chiffre est le budget conseillé du jour, plus la moyenne par jour.
- Deux fichiers redécoupés pour rester sous 200 lignes (`SettingsGeneralTab`, `UsageManager+DisplaySettings`).

## 1.8.0 : 19 octobre 2026

### Modifié
- **Première version de déploiement : secrets dans le trousseau macOS.** Les deux cookies (claude.ai et Console) quittent le fichier de développement au premier lancement, puis le fichier est supprimé. macOS peut demander une fois l'autorisation du trousseau à chaque nouvelle version ; c'est le prix de la protection.
- **`ClaudeUsageBar.swift` (1 560 lignes) découpé en 13 fichiers de moins de 200 lignes** : `AppDelegate` (+ Shortcuts, Popover), `UsageManager` (+ Settings, Fetch, Credits, Parsing), `StatusManager`, `StatusModels`, `PasteableText`, `AppEntry`, `AppExtensions`. Aucun changement de comportement : mêmes fonctions, mêmes propriétés publiées, mêmes journaux.
- `app/build.sh` (héritage amont) et README alignés sur la nouvelle structure.

### Ajouté
- Options de développement `--import-browser` (import Zen/Firefox en ligne de commande, statuts seulement) et `--wait` (délai des captures).

## 1.7.0 : 19 octobre 2026

### Modifié
- **Mode clair lisible** : les couleurs d'état (vert, ambre, rouge) ont une version plus profonde sur fond clair (contraste d'au moins 4,5:1 pour le texte). Avant, le vert et le jaune étaient presque illisibles sur blanc, et le texte blanc du planning disparaissait sur fond pâle.
- **Cartes : le rythme est dit en toutes lettres** (« Trop rapide », « Sous le rythme ») sous chaque anneau, au lieu de la seule couleur. Les deux cartes ont la même hauteur.
- **Planning de la semaine** : bloc « utilisé » étiqueté, étiquettes des jours écartées quand elles se chevaucheraient (fin de semaine chargée), texte du bloc à encre normale.
- **Courbe** : la valeur finale est posée sur une pastille et ne se superpose plus au tracé ; textes d'axe à 11 pt.
- Session à 0 % sans fenêtre ouverte : « Aucune session en cours » au lieu d'un 0 % sans explication.

### Ajouté
- **VoiceOver et aide** sur les jauges et anneaux ; info-bulle de la jauge qui explique le trait (rythme régulier) et la zone claire (prévision).
- Option de capture `--light` pour vérifier le rendu en mode clair.

## 1.6.6 : 19 octobre 2026

### Modifié
- **Courbe d'historique refaite selon les bonnes pratiques de visualisation** : ligne de 2 pt, lavis léger (10 %) sous la courbe, grille pleine et discrète (plus de pointillés), point final de 8 pt avec anneau, étiquettes ciblées (valeur finale, pic), texte en encre discrète.
- **Axe vertical adaptatif et toujours étiqueté** (20, 50 ou 100 %) : une session basse n'est plus écrasée en bas, et l'axe repasse à 100 % dès que l'usage monte.
- **Survol** : repère vertical et info-bulle « heure · valeur » sur le relevé le plus proche.
- Description pour VoiceOver (durée, valeur de départ, valeur finale, pic).

## 1.6.5 : 19 octobre 2026

### Modifié
- **Courbe d'historique** : l'axe colle exactement à la durée des relevés (de 10 minutes à 24 h) au lieu de paliers ronds, donc la courbe remplit toute la largeur dès les premières minutes. Le titre et le libellé gauche donnent la durée réelle (« Historique · 19 min », « il y a 19 min »).
- Repères **100 %** et **50 %**, point sur la valeur actuelle, et valeur de la session affichée à droite.

## 1.6.4 : 19 octobre 2026

### Corrigé
- **Courbe d'historique écrasée dans un coin** quand l'historique est jeune : l'échelle s'adapte maintenant à la durée disponible (1, 3, 6, 12 ou 24 h) et le titre l'indique (« Historique · 3 h »).
- Le tracé est **interrompu à chaque trou de plus de 30 minutes** (app fermée, veille) : plus de longue pente entre deux relevés distants.

## 1.6.3 : 19 octobre 2026

### Corrigé
- **Fausse alerte « limite de la semaine »** : le rythme hebdomadaire se calculait sur les 3 dernières heures, donc une rafale de travail était extrapolée à toute la semaine, nuits comprises (4,7 %/h tenus 35 h, alors que la projection sur la semaine donnait 71 %). Il se calcule maintenant sur **24 h avec au moins 12 h d'observation** ; en dessous, l'app utilise la moyenne de la semaine.
- Les messages disent qu'il s'agit d'une hypothèse (« si ça continue ») et donnent la **période de blocage** (« de mardi à 2 h 26 à mercredi à 14 h 00, soit environ 35 h »).

## 1.6.2 : 19 octobre 2026

### Modifié
- **Alertes de limite plus explicites** : le titre dit de quelle limite il s'agit (« Limite de la semaine atteinte mercredi à 2 h 15 »), le texte donne ton rythme, la **durée pendant laquelle tu serais bloqué** et, pour la semaine, le **budget par jour à tenir**.
- Heures sans zéro initial (« 0 h 03 » au lieu de « 00 h 03 »), durées courtes (« 1 h 20 », « 38 h », « 3 j 4 h »).

### Nouveau
- Bouton **« Voir des exemples d'alertes »** dans Réglages > Alertes, pour lire les textes avant qu'une vraie alerte arrive.

## 1.6.1 : 19 octobre 2026

### Nouveau
- Quand macOS bloque la lecture du navigateur (Firefox, Chrome), trois boutons guident l'autorisation : **ouvrir l'Accès complet au disque**, **afficher l'app dans le Finder** (pour la glisser dans la liste), **relancer l'app**. macOS ne permet pas à une app de s'accorder cet accès elle-même : seul l'interrupteur reste à activer.

### Modifié
- Onglet Connexions réorganisé : l'import depuis le navigateur passe en premier, chaque rapport n'apparaît qu'à sa place.

## 1.6.0 : 19 octobre 2026

### Nouveau
- **Alertes anticipées** (réglables une par une) : « tu atteindras 100 % vers 18 h 40 » avant que ça arrive, part de session ou de semaine **inutilisée** avant un reset, **session libérée** après la limite, **session claude.ai expirée**, **crédits API qui expirent** (à 5, 2 et 1 jour). Chaque alerte n'est envoyée qu'une fois.
- **Historique local** (un relevé par minute, 8 jours, fichier réservé à l'utilisateur) : courbe de la session sur 24 h, consommation du jour (« +9 % de la semaine »), **rythme récent** (par heure) et heure d'atteinte de 100 % à ce rythme.
- **Planning de la semaine** : part de la limite utilisable chaque jour jusqu'au reset, au prorata des heures.
- **Export de la prévision** (`forecast.json`) pour le statusline de Claude Code, avec une ligne prête à afficher (réglable dans l'onglet Général).

### Modifié
- Notifications via UserNotifications (l'API dépréciée de l'original disparaît) : zéro avertissement de compilation.

## 1.5.0 : 19 octobre 2026

### Nouveau
- Design réglable : popover en **jauges** (barre avec repère de rythme et prévision) ou en **cartes** (budget du jour, anneaux).
- Trois styles de barre de menu : étincelle, **double anneau** (semaine à l'extérieur, session à l'intérieur), **deux valeurs**.
- Valeur affichée réglable pour chaque style : session, hebdo, la plus haute, les deux. Option « icône seule » et décompte avant reset.
- Vraie **fenêtre de réglages** à cinq onglets (Affichage, Connexions, Crédits, Alertes, Général), tout en français.
- Rafraîchissement **toutes les minutes** (5 min dans l'original), ralenti à 5 min tant que l'API refuse, retour à 60 s au premier succès.
- Popover ancré en haut à droite si l'icône est masquée par une barre de menu pleine.

### Sécurité et stockage
- **Développement** : cookies dans un fichier protégé (0600), aucune fenêtre du trousseau.
- **Release** (`scripts/release.sh`) : cookies dans le trousseau macOS. Voir `docs/adr/001-stockage-des-secrets.md`.
- Bouton d'import de l'ancien trousseau (une demande de mot de passe, à l'initiative de l'utilisateur).

### Corrigé
- Barres : bouts arrondis seulement sur la piste, remplissage et voile à plat.
- Libellé de rythme sans pastille et cohérent avec la couleur (« Usage élevé », « Limite proche »…).
- Au Refresh, un statusline ancien n'écrase plus les valeurs fraîches.
- Retrait de l'ancienne vue de 800 lignes et du code mort.

## 1.4.0 : 18 octobre 2026

### Nouveau
- Source **statusline de Claude Code** (`rate_limits`) : données sans cookie ni appel réseau.
- **Prévisions** : fin de semaine estimée, budget par jour, rythme de la session de 5 h avec heure d'atteinte de 100 %.
- **Crédits API de la Console** (Max/Team) : solde, dépense, échéance, budget par jour, avec saisie manuelle en repli.
- Import des sessions depuis Zen/Firefox, âge des données affiché, diagnostic du trousseau (`--diagnose`).
- Icône de l'application (jauge et étincelle, générée par `scripts/make_icon.py`).
- Build local **sans Xcode** (`scripts/build.sh`, SDK 26, signature par certificat local stable) et tests (`scripts/test.sh`).

### Sécurité
- Cookie dans le Keychain avec migration depuis l'ancien stockage en clair.
- Plus de réponse brute de l'API ni d'identifiants dans les journaux ; flux distant de bannières et lien de don de l'amont retirés.

### Corrigé
- Le popover suit la hauteur de son contenu (en-tête rogné dans l'original, voir sa PR 36).
