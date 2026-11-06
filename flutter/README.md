# TimeFix — application mobile (Flutter)

Clone de l'application mobile Google Calendar, pour Android et iOS.

## Fonctionnalités

| Domaine | Détail |
|---|---|
| **Vues** | **Planning** (liste infinie dans les deux sens, bannières de mois illustrées, ligne « maintenant »), **Semaine** (grille horaire, zone « toute la journée », événements qui se chevauchent côte à côte, swipe entre semaines, zoom à deux doigts), **Mois** (grille 5–6 semaines, barres multi-jours continues, « +N », feuille de détail du jour) |
| **Navigation** | Tiroir latéral (vues + calendriers à cocher), titre du mois cliquable avec mini-calendrier, bouton « aujourd'hui », recherche |
| **Événements** | Création / modification / suppression, journée entière, multi-jours, couleur par événement, lieu, description, déplacement entre calendriers |
| **Récurrence** | Tous les jours / semaines / mois / ans / jours ouvrables ; affichage des règles RRULE quelconques ; modification ou suppression de « cet événement », « cet événement et les suivants » ou « tous les événements » |
| **Sources** | Calendriers **locaux** · abonnements **iCal** (`https://`, `webcal://`) en lecture seule · compte **Google** (lecture + écriture) |
| **Synchro** | Au démarrage, au retour au premier plan, et via « Actualiser » |
| **Divers** | Français + anglais (selon la langue du téléphone), thème clair / sombre, premier jour de la semaine, durée par défaut |

## Démarrage

```bash
cd flutter
flutter pub get
flutter run
```

Sans configuration Google, tout fonctionne sauf l'ajout d'un compte Google
(calendriers locaux et abonnements iCal inclus).

## Architecture

```
lib/
├── core/            utilitaires de dates, palette de couleurs, fuseau horaire
├── domain/          modèles (source, calendrier, événement, occurrence) et calcul des récurrences
├── data/
│   ├── db/          stockage SQLite (sqflite)
│   ├── ical/        parseur .ics et téléchargement des abonnements
│   ├── google/      API Google Calendar (google_sign_in + googleapis)
│   ├── sync/        import / synchronisation des sources
│   └── event_service.dart   création / modification / suppression (locale ou Google)
├── state/           providers Riverpod (données, paramètres, navigation, synchro)
├── ui/
│   ├── views/       planning, semaine, mois
│   ├── layout/      algorithmes de placement (chevauchements, couloirs multi-jours)
│   ├── event/       détail et éditeur d'événement
│   ├── home/        écran principal, tiroir, mini-calendrier
│   ├── calendars/   ajout de calendriers
│   └── settings/    paramètres et gestion des sources
└── l10n/            traductions (app_fr.arb, app_en.arb) + code généré
```

Principes :

* **Une source** (local, iCal, compte Google) contient **des calendriers**, qui
  contiennent **des événements**. Les événements récurrents sont stockés une
  seule fois (règle RRULE + exceptions EXDATE) et développés à l'affichage.
* Les récurrences sont calculées **dans le fuseau horaire de l'événement**
  (une réunion hebdomadaire à 9 h reste à 9 h après le changement d'heure).
* Les événements Google sont récupérés « dépliés » (`singleEvents=true`) sur
  une fenêtre de 6 mois dans le passé à 2 ans dans le futur.
* L'accès aux données passe par l'interface `CalendarRepository` : le futur
  backend C# pourra la remplacer sans toucher à l'interface utilisateur.

## Configurer Google Calendar

1. Dans la [Google Cloud Console](https://console.cloud.google.com/), créer un projet et
   activer l'**API Google Calendar**.
2. Configurer l'**écran de consentement OAuth** avec le scope
   `https://www.googleapis.com/auth/calendar` (ajouter vos comptes de test tant que
   l'app n'est pas validée).
3. Créer les identifiants OAuth :
   * client **Application Web** → son ID sert de `GOOGLE_SERVER_CLIENT_ID` ;
   * client **Android** : package `com.obnitram.timefix` + empreinte SHA-1 du keystore
     (`keytool -list -v -keystore ~/.android/debug.keystore -storepass android`) ;
   * client **iOS** : bundle ID `com.obnitram.timefix` → son ID sert de `GOOGLE_IOS_CLIENT_ID`.
4. iOS uniquement : ajouter dans `ios/Runner/Info.plist` le schéma d'URL
   correspondant à l'« iOS URL scheme » du client iOS (`com.googleusercontent.apps.…`)
   dans `CFBundleURLTypes`.
5. Lancer l'app avec les identifiants :

```bash
flutter run --dart-define=GOOGLE_SERVER_CLIENT_ID=xxx.apps.googleusercontent.com --dart-define=GOOGLE_IOS_CLIENT_ID=yyy.apps.googleusercontent.com
```

> Limite de cette version : `google_sign_in` ne garde qu'un seul compte connecté
> sur l'appareil, donc un seul compte Google à la fois. Le multi-compte passera
> par le backend (stockage des refresh tokens côté serveur).

## Tests

```bash
flutter analyze
flutter test
```

Les tests couvrent le calcul des récurrences (y compris changement d'heure),
le parseur iCal, les algorithmes de placement, le stockage SQLite, la
synchronisation iCal / Google (API simulée) et les principaux parcours de
l'interface (navigation entre vues, création, suppression, masquage d'un
calendrier).

Captures d'écran des écrans principaux (générées dans `build/screenshots/`) :

```bash
flutter test test/screenshot_test.dart --update-goldens --dart-define=SCREENSHOTS=true
```

## Prochaines étapes

* Backend C# (ASP.NET Core) déployé avec Docker : comptes utilisateurs,
  synchronisation multi-appareils, multi-comptes Google, rafraîchissement
  des abonnements iCal côté serveur.
* Vues Jour et 3 jours (la grille de la vue Semaine accepte déjà un nombre de jours).
* Rappels / notifications, invités, fuseau horaire par événement dans l'éditeur.
