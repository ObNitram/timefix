import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In fr, this message translates to:
  /// **'TimeFix'**
  String get appTitle;

  /// No description provided for @viewSchedule.
  ///
  /// In fr, this message translates to:
  /// **'Planning'**
  String get viewSchedule;

  /// No description provided for @viewWeek.
  ///
  /// In fr, this message translates to:
  /// **'Semaine'**
  String get viewWeek;

  /// No description provided for @viewMonth.
  ///
  /// In fr, this message translates to:
  /// **'Mois'**
  String get viewMonth;

  /// No description provided for @today.
  ///
  /// In fr, this message translates to:
  /// **'Aujourd\'hui'**
  String get today;

  /// No description provided for @search.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In fr, this message translates to:
  /// **'Rechercher des événements'**
  String get searchHint;

  /// No description provided for @noResults.
  ///
  /// In fr, this message translates to:
  /// **'Aucun résultat'**
  String get noResults;

  /// No description provided for @settings.
  ///
  /// In fr, this message translates to:
  /// **'Paramètres'**
  String get settings;

  /// No description provided for @refresh.
  ///
  /// In fr, this message translates to:
  /// **'Actualiser'**
  String get refresh;

  /// No description provided for @addCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un calendrier'**
  String get addCalendar;

  /// No description provided for @calendars.
  ///
  /// In fr, this message translates to:
  /// **'Calendriers'**
  String get calendars;

  /// No description provided for @myCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Mon calendrier'**
  String get myCalendar;

  /// No description provided for @noTitle.
  ///
  /// In fr, this message translates to:
  /// **'(Sans titre)'**
  String get noTitle;

  /// No description provided for @allDay.
  ///
  /// In fr, this message translates to:
  /// **'Toute la journée'**
  String get allDay;

  /// No description provided for @addTitle.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un titre'**
  String get addTitle;

  /// No description provided for @save.
  ///
  /// In fr, this message translates to:
  /// **'Enregistrer'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In fr, this message translates to:
  /// **'Annuler'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer'**
  String get delete;

  /// No description provided for @edit.
  ///
  /// In fr, this message translates to:
  /// **'Modifier'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get close;

  /// No description provided for @ok.
  ///
  /// In fr, this message translates to:
  /// **'OK'**
  String get ok;

  /// No description provided for @discardChangesTitle.
  ///
  /// In fr, this message translates to:
  /// **'Abandonner les modifications ?'**
  String get discardChangesTitle;

  /// No description provided for @discard.
  ///
  /// In fr, this message translates to:
  /// **'Abandonner'**
  String get discard;

  /// No description provided for @keepEditing.
  ///
  /// In fr, this message translates to:
  /// **'Continuer'**
  String get keepEditing;

  /// No description provided for @deleteEventTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer cet événement ?'**
  String get deleteEventTitle;

  /// No description provided for @deleteRecurringTitle.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer l\'événement périodique'**
  String get deleteRecurringTitle;

  /// No description provided for @editRecurringTitle.
  ///
  /// In fr, this message translates to:
  /// **'Modifier l\'événement périodique'**
  String get editRecurringTitle;

  /// No description provided for @scopeThis.
  ///
  /// In fr, this message translates to:
  /// **'Cet événement'**
  String get scopeThis;

  /// No description provided for @scopeFollowing.
  ///
  /// In fr, this message translates to:
  /// **'Cet événement et les suivants'**
  String get scopeFollowing;

  /// No description provided for @scopeAll.
  ///
  /// In fr, this message translates to:
  /// **'Tous les événements'**
  String get scopeAll;

  /// No description provided for @addLocation.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un lieu'**
  String get addLocation;

  /// No description provided for @addDescription.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter une description'**
  String get addDescription;

  /// No description provided for @calendar.
  ///
  /// In fr, this message translates to:
  /// **'Calendrier'**
  String get calendar;

  /// No description provided for @defaultColor.
  ///
  /// In fr, this message translates to:
  /// **'Couleur par défaut'**
  String get defaultColor;

  /// No description provided for @color.
  ///
  /// In fr, this message translates to:
  /// **'Couleur'**
  String get color;

  /// No description provided for @repeatNone.
  ///
  /// In fr, this message translates to:
  /// **'Ne se répète pas'**
  String get repeatNone;

  /// No description provided for @repeatDaily.
  ///
  /// In fr, this message translates to:
  /// **'Tous les jours'**
  String get repeatDaily;

  /// No description provided for @repeatWeekly.
  ///
  /// In fr, this message translates to:
  /// **'Toutes les semaines le {weekday}'**
  String repeatWeekly(String weekday);

  /// No description provided for @repeatMonthly.
  ///
  /// In fr, this message translates to:
  /// **'Tous les mois le {day}'**
  String repeatMonthly(int day);

  /// No description provided for @repeatYearly.
  ///
  /// In fr, this message translates to:
  /// **'Tous les ans le {date}'**
  String repeatYearly(String date);

  /// No description provided for @repeatWeekdays.
  ///
  /// In fr, this message translates to:
  /// **'Tous les jours de la semaine (du lundi au vendredi)'**
  String get repeatWeekdays;

  /// No description provided for @repeatCustom.
  ///
  /// In fr, this message translates to:
  /// **'Répétition personnalisée'**
  String get repeatCustom;

  /// No description provided for @repeatEveryNDays.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{Tous les jours} other{Tous les {count} jours}}'**
  String repeatEveryNDays(num count);

  /// No description provided for @repeatEveryNWeeks.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{Toutes les semaines} other{Toutes les {count} semaines}}'**
  String repeatEveryNWeeks(num count);

  /// No description provided for @repeatEveryNMonths.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{Tous les mois} other{Tous les {count} mois}}'**
  String repeatEveryNMonths(num count);

  /// No description provided for @repeatEveryNYears.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{Tous les ans} other{Tous les {count} ans}}'**
  String repeatEveryNYears(num count);

  /// No description provided for @repeatOnDays.
  ///
  /// In fr, this message translates to:
  /// **'{base}, le {days}'**
  String repeatOnDays(String base, String days);

  /// No description provided for @repeatUntil.
  ///
  /// In fr, this message translates to:
  /// **'{base}, jusqu\'au {date}'**
  String repeatUntil(String base, String date);

  /// No description provided for @repeatCount.
  ///
  /// In fr, this message translates to:
  /// **'{base}, {count} fois'**
  String repeatCount(String base, int count);

  /// No description provided for @nothingPlanned.
  ///
  /// In fr, this message translates to:
  /// **'Rien de prévu'**
  String get nothingPlanned;

  /// No description provided for @moreEvents.
  ///
  /// In fr, this message translates to:
  /// **'+{count}'**
  String moreEvents(int count);

  /// No description provided for @readOnlyCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Calendrier en lecture seule'**
  String get readOnlyCalendar;

  /// No description provided for @sourceIcal.
  ///
  /// In fr, this message translates to:
  /// **'S\'abonner via une URL iCal'**
  String get sourceIcal;

  /// No description provided for @sourceIcalSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Lien .ics ou webcal:// (Google, Outlook, iCloud…)'**
  String get sourceIcalSubtitle;

  /// No description provided for @sourceGoogle.
  ///
  /// In fr, this message translates to:
  /// **'Compte Google'**
  String get sourceGoogle;

  /// No description provided for @sourceGoogleSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Synchroniser et modifier vos agendas Google'**
  String get sourceGoogleSubtitle;

  /// No description provided for @sourceLocal.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau calendrier local'**
  String get sourceLocal;

  /// No description provided for @sourceLocalSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Stocké uniquement sur cet appareil'**
  String get sourceLocalSubtitle;

  /// No description provided for @icalUrl.
  ///
  /// In fr, this message translates to:
  /// **'URL du calendrier'**
  String get icalUrl;

  /// No description provided for @icalUrlHint.
  ///
  /// In fr, this message translates to:
  /// **'https://… ou webcal://…'**
  String get icalUrlHint;

  /// No description provided for @nameOptional.
  ///
  /// In fr, this message translates to:
  /// **'Nom (facultatif)'**
  String get nameOptional;

  /// No description provided for @name.
  ///
  /// In fr, this message translates to:
  /// **'Nom'**
  String get name;

  /// No description provided for @subscribe.
  ///
  /// In fr, this message translates to:
  /// **'S\'abonner'**
  String get subscribe;

  /// No description provided for @create.
  ///
  /// In fr, this message translates to:
  /// **'Créer'**
  String get create;

  /// No description provided for @invalidUrl.
  ///
  /// In fr, this message translates to:
  /// **'URL invalide'**
  String get invalidUrl;

  /// No description provided for @requiredField.
  ///
  /// In fr, this message translates to:
  /// **'Champ obligatoire'**
  String get requiredField;

  /// No description provided for @icalError.
  ///
  /// In fr, this message translates to:
  /// **'Impossible de charger le calendrier : {message}'**
  String icalError(String message);

  /// No description provided for @googleError.
  ///
  /// In fr, this message translates to:
  /// **'Connexion à Google impossible : {message}'**
  String googleError(String message);

  /// No description provided for @googleSingleAccountNote.
  ///
  /// In fr, this message translates to:
  /// **'Un seul compte Google peut être connecté à la fois sur cette version.'**
  String get googleSingleAccountNote;

  /// No description provided for @calendarAdded.
  ///
  /// In fr, this message translates to:
  /// **'Calendrier ajouté'**
  String get calendarAdded;

  /// No description provided for @manageCalendars.
  ///
  /// In fr, this message translates to:
  /// **'Gérer les calendriers'**
  String get manageCalendars;

  /// No description provided for @lastSync.
  ///
  /// In fr, this message translates to:
  /// **'Dernière synchro : {date}'**
  String lastSync(String date);

  /// No description provided for @neverSynced.
  ///
  /// In fr, this message translates to:
  /// **'Jamais synchronisé'**
  String get neverSynced;

  /// No description provided for @syncNow.
  ///
  /// In fr, this message translates to:
  /// **'Synchroniser'**
  String get syncNow;

  /// No description provided for @removeSource.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer la source'**
  String get removeSource;

  /// No description provided for @removeSourceConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer « {name} » et tous ses événements de cet appareil ?'**
  String removeSourceConfirm(String name);

  /// No description provided for @deleteCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le calendrier'**
  String get deleteCalendar;

  /// No description provided for @deleteCalendarConfirm.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer « {name} » et tous ses événements ?'**
  String deleteCalendarConfirm(String name);

  /// No description provided for @rename.
  ///
  /// In fr, this message translates to:
  /// **'Renommer'**
  String get rename;

  /// No description provided for @general.
  ///
  /// In fr, this message translates to:
  /// **'Général'**
  String get general;

  /// No description provided for @firstDayOfWeek.
  ///
  /// In fr, this message translates to:
  /// **'Premier jour de la semaine'**
  String get firstDayOfWeek;

  /// No description provided for @localeDefault.
  ///
  /// In fr, this message translates to:
  /// **'Selon la langue'**
  String get localeDefault;

  /// No description provided for @theme.
  ///
  /// In fr, this message translates to:
  /// **'Thème'**
  String get theme;

  /// No description provided for @themeSystem.
  ///
  /// In fr, this message translates to:
  /// **'Par défaut du système'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In fr, this message translates to:
  /// **'Clair'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In fr, this message translates to:
  /// **'Sombre'**
  String get themeDark;

  /// No description provided for @defaultDuration.
  ///
  /// In fr, this message translates to:
  /// **'Durée par défaut des événements'**
  String get defaultDuration;

  /// No description provided for @minutes.
  ///
  /// In fr, this message translates to:
  /// **'{count} minutes'**
  String minutes(int count);

  /// No description provided for @syncing.
  ///
  /// In fr, this message translates to:
  /// **'Synchronisation…'**
  String get syncing;

  /// No description provided for @syncFailed.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{Échec de la synchronisation d\'une source} other{Échec de la synchronisation de {count} sources}}'**
  String syncFailed(num count);

  /// No description provided for @eventDeleted.
  ///
  /// In fr, this message translates to:
  /// **'Événement supprimé'**
  String get eventDeleted;

  /// No description provided for @errorMessage.
  ///
  /// In fr, this message translates to:
  /// **'Erreur : {message}'**
  String errorMessage(String message);

  /// No description provided for @sourceTypeLocal.
  ///
  /// In fr, this message translates to:
  /// **'Sur cet appareil'**
  String get sourceTypeLocal;

  /// No description provided for @sourceTypeIcal.
  ///
  /// In fr, this message translates to:
  /// **'Abonnement iCal'**
  String get sourceTypeIcal;

  /// No description provided for @sourceTypeGoogle.
  ///
  /// In fr, this message translates to:
  /// **'Google'**
  String get sourceTypeGoogle;

  /// No description provided for @noWritableCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Aucun calendrier modifiable. Ajoutez un calendrier local ou un compte Google.'**
  String get noWritableCalendar;

  /// No description provided for @seriesInstanceNote.
  ///
  /// In fr, this message translates to:
  /// **'Seule cette occurrence de la série sera modifiée.'**
  String get seriesInstanceNote;

  /// No description provided for @noEvents.
  ///
  /// In fr, this message translates to:
  /// **'Aucun événement'**
  String get noEvents;

  /// No description provided for @openMenu.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir le menu'**
  String get openMenu;

  /// No description provided for @goToToday.
  ///
  /// In fr, this message translates to:
  /// **'Aller à aujourd\'hui'**
  String get goToToday;

  /// No description provided for @newEvent.
  ///
  /// In fr, this message translates to:
  /// **'Nouvel événement'**
  String get newEvent;

  /// No description provided for @about.
  ///
  /// In fr, this message translates to:
  /// **'À propos'**
  String get about;

  /// No description provided for @colorTomato.
  ///
  /// In fr, this message translates to:
  /// **'Tomate'**
  String get colorTomato;

  /// No description provided for @colorFlamingo.
  ///
  /// In fr, this message translates to:
  /// **'Flamant'**
  String get colorFlamingo;

  /// No description provided for @colorTangerine.
  ///
  /// In fr, this message translates to:
  /// **'Mandarine'**
  String get colorTangerine;

  /// No description provided for @colorBanana.
  ///
  /// In fr, this message translates to:
  /// **'Banane'**
  String get colorBanana;

  /// No description provided for @colorSage.
  ///
  /// In fr, this message translates to:
  /// **'Sauge'**
  String get colorSage;

  /// No description provided for @colorBasil.
  ///
  /// In fr, this message translates to:
  /// **'Basilic'**
  String get colorBasil;

  /// No description provided for @colorPeacock.
  ///
  /// In fr, this message translates to:
  /// **'Paon'**
  String get colorPeacock;

  /// No description provided for @colorBlueberry.
  ///
  /// In fr, this message translates to:
  /// **'Myrtille'**
  String get colorBlueberry;

  /// No description provided for @colorLavender.
  ///
  /// In fr, this message translates to:
  /// **'Lavande'**
  String get colorLavender;

  /// No description provided for @colorGrape.
  ///
  /// In fr, this message translates to:
  /// **'Raisin'**
  String get colorGrape;

  /// No description provided for @colorGraphite.
  ///
  /// In fr, this message translates to:
  /// **'Graphite'**
  String get colorGraphite;

  /// No description provided for @repeat.
  ///
  /// In fr, this message translates to:
  /// **'Répétition'**
  String get repeat;

  /// No description provided for @googleReconnect.
  ///
  /// In fr, this message translates to:
  /// **'Reconnexion à Google nécessaire'**
  String get googleReconnect;

  /// No description provided for @sourceCalDav.
  ///
  /// In fr, this message translates to:
  /// **'Compte CalDAV'**
  String get sourceCalDav;

  /// No description provided for @sourceCalDavSubtitle.
  ///
  /// In fr, this message translates to:
  /// **'Serveur TimeFix auto-hébergé, Nextcloud, Radicale, iCloud…'**
  String get sourceCalDavSubtitle;

  /// No description provided for @sourceTypeCalDav.
  ///
  /// In fr, this message translates to:
  /// **'CalDAV'**
  String get sourceTypeCalDav;

  /// No description provided for @serverUrl.
  ///
  /// In fr, this message translates to:
  /// **'Adresse du serveur'**
  String get serverUrl;

  /// No description provided for @serverUrlHint.
  ///
  /// In fr, this message translates to:
  /// **'https://cal.exemple.fr'**
  String get serverUrlHint;

  /// No description provided for @username.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant'**
  String get username;

  /// No description provided for @password.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe'**
  String get password;

  /// No description provided for @connect.
  ///
  /// In fr, this message translates to:
  /// **'Se connecter'**
  String get connect;

  /// No description provided for @caldavError.
  ///
  /// In fr, this message translates to:
  /// **'Connexion CalDAV impossible : {message}'**
  String caldavError(String message);

  /// No description provided for @caldavAuthError.
  ///
  /// In fr, this message translates to:
  /// **'Identifiant ou mot de passe incorrect'**
  String get caldavAuthError;

  /// No description provided for @newCalendar.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau calendrier'**
  String get newCalendar;

  /// No description provided for @changePassword.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le mot de passe'**
  String get changePassword;

  /// No description provided for @passwordUpdated.
  ///
  /// In fr, this message translates to:
  /// **'Mot de passe mis à jour'**
  String get passwordUpdated;

  /// No description provided for @conflictError.
  ///
  /// In fr, this message translates to:
  /// **'Cet événement a été modifié ailleurs. Les données ont été actualisées : réessayez.'**
  String get conflictError;

  /// No description provided for @caldavHelp.
  ///
  /// In fr, this message translates to:
  /// **'Pour un serveur TimeFix, utilisez l\'adresse du serveur (ex. https://cal.exemple.fr) et le compte créé par l\'administrateur.'**
  String get caldavHelp;

  /// No description provided for @account.
  ///
  /// In fr, this message translates to:
  /// **'Compte'**
  String get account;

  /// No description provided for @reminders.
  ///
  /// In fr, this message translates to:
  /// **'Rappels'**
  String get reminders;

  /// No description provided for @addReminder.
  ///
  /// In fr, this message translates to:
  /// **'Ajouter un rappel'**
  String get addReminder;

  /// No description provided for @reminderTypePush.
  ///
  /// In fr, this message translates to:
  /// **'Notification'**
  String get reminderTypePush;

  /// No description provided for @reminderTypeFullScreen.
  ///
  /// In fr, this message translates to:
  /// **'Plein écran'**
  String get reminderTypeFullScreen;

  /// No description provided for @reminderTypeAlarm.
  ///
  /// In fr, this message translates to:
  /// **'Alarme'**
  String get reminderTypeAlarm;

  /// No description provided for @reminderAtStart.
  ///
  /// In fr, this message translates to:
  /// **'Au moment de l\'événement'**
  String get reminderAtStart;

  /// No description provided for @reminderMinutesBefore.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 minute avant} other{{count} minutes avant}}'**
  String reminderMinutesBefore(num count);

  /// No description provided for @reminderHoursBefore.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 heure avant} other{{count} heures avant}}'**
  String reminderHoursBefore(num count);

  /// No description provided for @reminderDaysBefore.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 jour avant} other{{count} jours avant}}'**
  String reminderDaysBefore(num count);

  /// No description provided for @reminderWeeksBefore.
  ///
  /// In fr, this message translates to:
  /// **'{count, plural, =1{1 semaine avant} other{{count} semaines avant}}'**
  String reminderWeeksBefore(num count);

  /// No description provided for @reminderHoursMinutesBefore.
  ///
  /// In fr, this message translates to:
  /// **'{hours} h {minutes} min avant'**
  String reminderHoursMinutesBefore(int hours, int minutes);

  /// No description provided for @reminderMinutesAfter.
  ///
  /// In fr, this message translates to:
  /// **'{count} min après le début'**
  String reminderMinutesAfter(int count);

  /// No description provided for @reminderSameDayAt.
  ///
  /// In fr, this message translates to:
  /// **'Le jour même à {time}'**
  String reminderSameDayAt(String time);

  /// No description provided for @reminderDayBeforeAt.
  ///
  /// In fr, this message translates to:
  /// **'La veille à {time}'**
  String reminderDayBeforeAt(String time);

  /// No description provided for @reminderDaysBeforeAt.
  ///
  /// In fr, this message translates to:
  /// **'{count} jours avant à {time}'**
  String reminderDaysBeforeAt(int count, String time);

  /// No description provided for @reminderCustom.
  ///
  /// In fr, this message translates to:
  /// **'Personnalisé…'**
  String get reminderCustom;

  /// No description provided for @reminderCustomTitle.
  ///
  /// In fr, this message translates to:
  /// **'Rappel personnalisé'**
  String get reminderCustomTitle;

  /// No description provided for @myPresets.
  ///
  /// In fr, this message translates to:
  /// **'Mes presets'**
  String get myPresets;

  /// No description provided for @unitMinutes.
  ///
  /// In fr, this message translates to:
  /// **'minutes'**
  String get unitMinutes;

  /// No description provided for @unitHours.
  ///
  /// In fr, this message translates to:
  /// **'heures'**
  String get unitHours;

  /// No description provided for @unitDays.
  ///
  /// In fr, this message translates to:
  /// **'jours'**
  String get unitDays;

  /// No description provided for @unitWeeks.
  ///
  /// In fr, this message translates to:
  /// **'semaines'**
  String get unitWeeks;

  /// No description provided for @daysBefore.
  ///
  /// In fr, this message translates to:
  /// **'Jours avant'**
  String get daysBefore;

  /// No description provided for @atTime.
  ///
  /// In fr, this message translates to:
  /// **'Heure'**
  String get atTime;

  /// No description provided for @fullScreenIosNote.
  ///
  /// In fr, this message translates to:
  /// **'Sur iPhone : notification urgente, sans plein écran.'**
  String get fullScreenIosNote;

  /// No description provided for @alarmIosNote.
  ///
  /// In fr, this message translates to:
  /// **'Sur iPhone : alarme système à partir d\'iOS 26, notification urgente avant.'**
  String get alarmIosNote;

  /// No description provided for @defaultReminders.
  ///
  /// In fr, this message translates to:
  /// **'Rappels par défaut'**
  String get defaultReminders;

  /// No description provided for @defaultRemindersTimed.
  ///
  /// In fr, this message translates to:
  /// **'Événements'**
  String get defaultRemindersTimed;

  /// No description provided for @defaultRemindersAllDay.
  ///
  /// In fr, this message translates to:
  /// **'Événements sur la journée'**
  String get defaultRemindersAllDay;

  /// No description provided for @noReminders.
  ///
  /// In fr, this message translates to:
  /// **'Aucun rappel'**
  String get noReminders;

  /// No description provided for @newPreset.
  ///
  /// In fr, this message translates to:
  /// **'Nouveau preset'**
  String get newPreset;

  /// No description provided for @editPreset.
  ///
  /// In fr, this message translates to:
  /// **'Modifier le preset'**
  String get editPreset;

  /// No description provided for @deletePreset.
  ///
  /// In fr, this message translates to:
  /// **'Supprimer le preset'**
  String get deletePreset;

  /// No description provided for @presetForAllDay.
  ///
  /// In fr, this message translates to:
  /// **'Pour les événements sur la journée'**
  String get presetForAllDay;

  /// No description provided for @presetsHint.
  ///
  /// In fr, this message translates to:
  /// **'Vos presets apparaissent quand vous ajoutez un rappel à un événement.'**
  String get presetsHint;

  /// No description provided for @alarmSection.
  ///
  /// In fr, this message translates to:
  /// **'Alarme'**
  String get alarmSection;

  /// No description provided for @alarmSound.
  ///
  /// In fr, this message translates to:
  /// **'Sonnerie'**
  String get alarmSound;

  /// No description provided for @soundSystem.
  ///
  /// In fr, this message translates to:
  /// **'Sonnerie d\'alarme du téléphone'**
  String get soundSystem;

  /// No description provided for @soundClassic.
  ///
  /// In fr, this message translates to:
  /// **'Classique'**
  String get soundClassic;

  /// No description provided for @soundDigital.
  ///
  /// In fr, this message translates to:
  /// **'Numérique'**
  String get soundDigital;

  /// No description provided for @soundGentle.
  ///
  /// In fr, this message translates to:
  /// **'Douce'**
  String get soundGentle;

  /// No description provided for @snoozeDuration.
  ///
  /// In fr, this message translates to:
  /// **'Répétition (snooze)'**
  String get snoozeDuration;

  /// No description provided for @autoStop.
  ///
  /// In fr, this message translates to:
  /// **'Arrêt automatique après'**
  String get autoStop;

  /// No description provided for @vibration.
  ///
  /// In fr, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @permissions.
  ///
  /// In fr, this message translates to:
  /// **'Autorisations'**
  String get permissions;

  /// No description provided for @permissionNotifications.
  ///
  /// In fr, this message translates to:
  /// **'Notifications'**
  String get permissionNotifications;

  /// No description provided for @permissionExactAlarms.
  ///
  /// In fr, this message translates to:
  /// **'Alarmes et rappels à l\'heure exacte'**
  String get permissionExactAlarms;

  /// No description provided for @permissionFullScreen.
  ///
  /// In fr, this message translates to:
  /// **'Notifications plein écran'**
  String get permissionFullScreen;

  /// No description provided for @permissionAlarmKit.
  ///
  /// In fr, this message translates to:
  /// **'Alarmes (iOS 26 et plus)'**
  String get permissionAlarmKit;

  /// No description provided for @permissionGranted.
  ///
  /// In fr, this message translates to:
  /// **'Autorisé'**
  String get permissionGranted;

  /// No description provided for @permissionDenied.
  ///
  /// In fr, this message translates to:
  /// **'Non autorisé'**
  String get permissionDenied;

  /// No description provided for @permissionUnsupported.
  ///
  /// In fr, this message translates to:
  /// **'Non disponible sur cet appareil'**
  String get permissionUnsupported;

  /// No description provided for @grant.
  ///
  /// In fr, this message translates to:
  /// **'Autoriser'**
  String get grant;

  /// No description provided for @testSection.
  ///
  /// In fr, this message translates to:
  /// **'Tester'**
  String get testSection;

  /// No description provided for @testPush.
  ///
  /// In fr, this message translates to:
  /// **'Tester une notification'**
  String get testPush;

  /// No description provided for @testFullScreen.
  ///
  /// In fr, this message translates to:
  /// **'Tester le plein écran'**
  String get testFullScreen;

  /// No description provided for @testAlarm.
  ///
  /// In fr, this message translates to:
  /// **'Tester l\'alarme'**
  String get testAlarm;

  /// No description provided for @testScheduled.
  ///
  /// In fr, this message translates to:
  /// **'Déclenchement dans 5 secondes. Verrouillez l\'écran pour voir le rendu réel.'**
  String get testScheduled;

  /// No description provided for @testEventTitle.
  ///
  /// In fr, this message translates to:
  /// **'Test TimeFix'**
  String get testEventTitle;

  /// No description provided for @alarmStop.
  ///
  /// In fr, this message translates to:
  /// **'Arrêter'**
  String get alarmStop;

  /// No description provided for @alarmSnooze.
  ///
  /// In fr, this message translates to:
  /// **'Répéter ({minutes} min)'**
  String alarmSnooze(int minutes);

  /// No description provided for @alarmDismiss.
  ///
  /// In fr, this message translates to:
  /// **'Fermer'**
  String get alarmDismiss;

  /// No description provided for @openEvent.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrir l\'événement'**
  String get openEvent;

  /// No description provided for @channelPush.
  ///
  /// In fr, this message translates to:
  /// **'Rappels'**
  String get channelPush;

  /// No description provided for @channelPushDescription.
  ///
  /// In fr, this message translates to:
  /// **'Notifications de rappel des événements'**
  String get channelPushDescription;

  /// No description provided for @channelFullScreen.
  ///
  /// In fr, this message translates to:
  /// **'Rappels plein écran'**
  String get channelFullScreen;

  /// No description provided for @channelFullScreenDescription.
  ///
  /// In fr, this message translates to:
  /// **'Rappels affichés en plein écran'**
  String get channelFullScreenDescription;

  /// No description provided for @channelAlarm.
  ///
  /// In fr, this message translates to:
  /// **'Alarmes'**
  String get channelAlarm;

  /// No description provided for @channelAlarmDescription.
  ///
  /// In fr, this message translates to:
  /// **'Rappels qui sonnent comme un réveil'**
  String get channelAlarmDescription;

  /// No description provided for @notificationStartsNow.
  ///
  /// In fr, this message translates to:
  /// **'Commence maintenant'**
  String get notificationStartsNow;

  /// No description provided for @remindersDeviceOnly.
  ///
  /// In fr, this message translates to:
  /// **'Rappels enregistrés sur cet appareil uniquement.'**
  String get remindersDeviceOnly;

  /// No description provided for @snoozedUntil.
  ///
  /// In fr, this message translates to:
  /// **'Répété à {time}'**
  String snoozedUntil(String time);

  /// No description provided for @alarmSnoozeShort.
  ///
  /// In fr, this message translates to:
  /// **'Répéter'**
  String get alarmSnoozeShort;

  /// No description provided for @notificationPermissionHint.
  ///
  /// In fr, this message translates to:
  /// **'Autorisez les notifications pour recevoir vos rappels.'**
  String get notificationPermissionHint;

  /// No description provided for @fullScreenPermissionHint.
  ///
  /// In fr, this message translates to:
  /// **'Les rappels plein écran et les alarmes ont besoin d\'une autorisation pour s\'afficher sur l\'écran verrouillé.'**
  String get fullScreenPermissionHint;

  /// No description provided for @remindersSentinel.
  ///
  /// In fr, this message translates to:
  /// **'Ouvrez TimeFix pour programmer vos prochains rappels.'**
  String get remindersSentinel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
