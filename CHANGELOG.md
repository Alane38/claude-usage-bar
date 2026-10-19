# Journal des changements

Fork de [Artzainnn/ClaudeUsageBar](https://github.com/Artzainnn/ClaudeUsageBar). Format : une section par version, la plus récente en haut.

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
