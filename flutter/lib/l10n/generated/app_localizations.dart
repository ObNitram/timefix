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
