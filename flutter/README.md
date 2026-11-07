# TimeFix — application mobile (Flutter)

Clone de l'application mobile Google Calendar, pour Android et iOS.

## Fonctionnalités

| Domaine | Détail |
|---|---|
| **Vues** | **Planning** (liste infinie dans les deux sens, bannières de mois illustrées, ligne « maintenant »), **Semaine** (grille horaire, zone « toute la journée », événements qui se chevauchent côte à côte, swipe entre semaines, zoom à deux doigts), **Mois** (grille 5–6 semaines, barres multi-jours continues, « +N », feuille de détail du jour) |
| **Navigation** | Tiroir latéral (vues + calendriers à cocher), titre du mois cliquable avec mini-calendrier, bouton « aujourd'hui », recherche |
| **Événements** | Création / modification / suppression, journée entière, multi-jours, couleur par événement, lieu, description, déplacement entre calendriers |
| **Récurrence** | Tous les jours / semaines / mois / ans / jours ouvrables ; affichage des règles RRULE quelconques ; modification ou suppression de « cet événement », « cet événement et les suivants » ou « tous les événements » |
| **Sources** | Calendriers **locaux** · abonnements **iCal** (`https://`, `webcal://`) en lecture seule · compte **Google** (lecture + écriture) · comptes **CalDAV** (serveur TimeFix auto-hébergé, Nextcloud, Radicale…) en lecture + écriture, création de calendriers |
| **Synchro** | Au démarrage, au retour au premier plan, et via « Actualiser » |
| **Rappels** | Trois types : **notification**, **plein écran**, **alarme** (sonne comme un réveil, Arrêter / Répéter). Délais intégrés + **presets perso**, rappels par défaut (événements / journée entière), réglages de l'alarme (sonnerie, répétition, arrêt automatique, vibration) |
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
│   ├── caldav/      client CalDAV et écriture des événements (ETags, RECURRENCE-ID)
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

## CalDAV

**Ajouter un calendrier → Compte CalDAV**, avec l'adresse du serveur,
l'identifiant et le mot de passe. L'application trouve elle-même les
calendriers (`/.well-known/caldav`, principal, `calendar-home-set`).

* Le mot de passe est stocké dans le stockage sécurisé du téléphone (Keychain /
  Keystore), jamais dans la base de données.
* Seuls les calendriers dont le `getctag` a changé sont re-téléchargés.
* Chaque modification est envoyée immédiatement avec une précondition `If-Match` :
  si l'événement a été modifié ailleurs entre-temps, rien n'est écrasé, les
  données sont actualisées et un message invite à recommencer.
* Modifier une seule occurrence d'une série crée une exception `RECURRENCE-ID`
  dans la même ressource, comme le font les autres clients CalDAV.
* Depuis l'écran du compte (Paramètres → le compte), on peut créer un
  calendrier sur le serveur ou changer le mot de passe.

Limites : l'application fonctionne en ligne pour les écritures CalDAV ; les
propriétés qu'elle ne connaît pas (rappels, invités…) d'un événement créé par
un autre client sont perdues si on le modifie depuis TimeFix.

Pour tester contre un serveur local en HTTP : les builds Android de debug
autorisent le HTTP en clair (depuis l'émulateur, le PC est `http://10.0.2.2:8080`),
iOS l'autorise vers les adresses locales. En production, utiliser HTTPS.

## Rappels et alarmes

Chaque événement peut avoir plusieurs rappels. Un rappel = un délai + un type.

| Type | Android | iOS |
|---|---|---|
| Notification | Notification (canal « Rappels ») | Notification |
| Plein écran | Notification plein écran par-dessus l'écran verrouillé, écran TimeFix avec Fermer / Répéter | Notification **urgente** (Time Sensitive, passe les modes Concentration) : Apple n'autorise pas le plein écran |
| Alarme | Alarme système (`setAlarmClock`) : sonnerie d'alarme en boucle + vibration jusqu'à **Arrêter**, **Répéter** (snooze), arrêt automatique ; écran de sonnerie plein écran | iOS 26+ : vraie alarme **AlarmKit** (comme l'app Horloge) ; avant iOS 26 : notification urgente avec une sonnerie de 28 s |

* **Presets** : délais intégrés (comme Google Agenda) + presets perso créés dans
  Paramètres → Rappels (nom facultatif, délai, type, journée entière ou non).
  Les **rappels par défaut** sont ajoutés aux nouveaux événements.
* **Synchronisation** : calendriers locaux et CalDAV → stockés avec l'événement
  (CalDAV : `VALARM` standard + `X-TIMEFIX-REMINDER-TYPE`, donc les autres
  appareils TimeFix sonnent aussi) ; Google → les notifications deviennent des
  rappels Google, plein écran et alarme restent sur l'appareil ; calendriers en
  lecture seule (iCal…) → rappels ajoutés depuis la fiche de l'événement,
  gardés sur l'appareil.
* **Planification** : les rappels des 3 prochaines semaines sont programmés
  dans le système (au plus 60 sur iOS, qui n'en garde que 64), et recalculés à
  chaque ouverture de l'app, retour au premier plan, modification ou synchro.
* **Autorisations** : demandées à la création du premier rappel ; leur état et
  des boutons de test sont dans Paramètres → Rappels.

Limites connues :

* iOS : le bouton « Répéter » des alarmes AlarmKit demande une extension
  Widget (Live Activity) à créer dans Xcode (`dart run alarm_kit:setup`), puis
  `alarmKitSnoozeEnabled = true` dans `notifications_reminder_platform.dart`.
  Sans elle, l'alarme iOS 26 propose seulement « Arrêter ».
* Android 14+ : l'autorisation « notifications plein écran » n'est accordée
  d'office qu'aux applications d'alarme ou d'appel ; sinon l'utilisateur
  l'active depuis Paramètres → Rappels (sans elle : notification normale qui
  sonne quand même en boucle). Publication Play Store : déclarer
  `USE_EXACT_ALARM` (autorisé pour les agendas) et `USE_FULL_SCREEN_INTENT`.
* Les rappels sont programmés sur 5 semaines (Android) / 3 semaines et 60
  alertes (iOS), et recalculés à chaque ouverture de l'app. S'il reste des
  rappels non programmés, une notification « Ouvrez TimeFix pour programmer vos
  prochains rappels » est placée après la dernière alerte.
* Android : après un redémarrage, les alarmes sont reprogrammées au premier
  déverrouillage (pas de démarrage direct) ; une alarme due avant ce
  déverrouillage sonne à ce moment-là.
* Android 8.0 minimum (canaux de notification).
* iOS : le texte de la demande d'autorisation AlarmKit est bilingue FR / EN
  (pas encore de fichiers `InfoPlist.strings`).

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
le parseur et le générateur iCal, le client CalDAV, les algorithmes de
placement, le stockage SQLite (dont la migration de schéma), la synchronisation
iCal / Google (API simulée) et les principaux parcours de l'interface.

Tests de bout en bout contre un vrai serveur TimeFix (ignorés sans serveur) :

```bash
cd ../backend && dotnet run --project src/TimeFix.Server --urls http://127.0.0.1:5080
```

```bash
TIMEFIX_CALDAV_URL=http://127.0.0.1:5080 TIMEFIX_CALDAV_ADMIN=admin:admin-dev-password flutter test test/integration/caldav_server_test.dart
```

Captures d'écran des écrans principaux (générées dans `build/screenshots/`) :

```bash
flutter test test/screenshot_test.dart --update-goldens --dart-define=SCREENSHOTS=true
```

## Prochaines étapes

* Synchronisation Google et iCal côté serveur (multi-comptes Google).
* Mode hors ligne pour CalDAV (file d'attente des modifications).
* Vues Jour et 3 jours (la grille de la vue Semaine accepte déjà un nombre de jours).
* Invités, fuseau horaire par événement dans l'éditeur.
* Rappels : rafraîchissement en arrière-plan (WorkManager / BGTaskScheduler) pour ne
  plus dépendre de l'ouverture de l'app, et snooze AlarmKit (extension Widget).
