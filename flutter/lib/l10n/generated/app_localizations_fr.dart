// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'TimeFix';

  @override
  String get viewSchedule => 'Planning';

  @override
  String get viewWeek => 'Semaine';

  @override
  String get viewMonth => 'Mois';

  @override
  String get today => 'Aujourd\'hui';

  @override
  String get search => 'Rechercher';

  @override
  String get searchHint => 'Rechercher des événements';

  @override
  String get noResults => 'Aucun résultat';

  @override
  String get settings => 'Paramètres';

  @override
  String get refresh => 'Actualiser';

  @override
  String get addCalendar => 'Ajouter un calendrier';

  @override
  String get calendars => 'Calendriers';

  @override
  String get myCalendar => 'Mon calendrier';

  @override
  String get noTitle => '(Sans titre)';

  @override
  String get allDay => 'Toute la journée';

  @override
  String get addTitle => 'Ajouter un titre';

  @override
  String get save => 'Enregistrer';

  @override
  String get cancel => 'Annuler';

  @override
  String get delete => 'Supprimer';

  @override
  String get edit => 'Modifier';

  @override
  String get close => 'Fermer';

  @override
  String get ok => 'OK';

  @override
  String get discardChangesTitle => 'Abandonner les modifications ?';

  @override
  String get discard => 'Abandonner';

  @override
  String get keepEditing => 'Continuer';

  @override
  String get deleteEventTitle => 'Supprimer cet événement ?';

  @override
  String get deleteRecurringTitle => 'Supprimer l\'événement périodique';

  @override
  String get editRecurringTitle => 'Modifier l\'événement périodique';

  @override
  String get scopeThis => 'Cet événement';

  @override
  String get scopeFollowing => 'Cet événement et les suivants';

  @override
  String get scopeAll => 'Tous les événements';

  @override
  String get addLocation => 'Ajouter un lieu';

  @override
  String get addDescription => 'Ajouter une description';

  @override
  String get calendar => 'Calendrier';

  @override
  String get defaultColor => 'Couleur par défaut';

  @override
  String get color => 'Couleur';

  @override
  String get repeatNone => 'Ne se répète pas';

  @override
  String get repeatDaily => 'Tous les jours';

  @override
  String repeatWeekly(String weekday) {
    return 'Toutes les semaines le $weekday';
  }

  @override
  String repeatMonthly(int day) {
    return 'Tous les mois le $day';
  }

  @override
  String repeatYearly(String date) {
    return 'Tous les ans le $date';
  }

  @override
  String get repeatWeekdays =>
      'Tous les jours de la semaine (du lundi au vendredi)';

  @override
  String get repeatCustom => 'Répétition personnalisée';

  @override
  String repeatEveryNDays(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tous les $countString jours',
      one: 'Tous les jours',
    );
    return '$_temp0';
  }

  @override
  String repeatEveryNWeeks(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Toutes les $countString semaines',
      one: 'Toutes les semaines',
    );
    return '$_temp0';
  }

  @override
  String repeatEveryNMonths(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tous les $countString mois',
      one: 'Tous les mois',
    );
    return '$_temp0';
  }

  @override
  String repeatEveryNYears(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tous les $countString ans',
      one: 'Tous les ans',
    );
    return '$_temp0';
  }

  @override
  String repeatOnDays(String base, String days) {
    return '$base, le $days';
  }

  @override
  String repeatUntil(String base, String date) {
    return '$base, jusqu\'au $date';
  }

  @override
  String repeatCount(String base, int count) {
    return '$base, $count fois';
  }

  @override
  String get nothingPlanned => 'Rien de prévu';

  @override
  String moreEvents(int count) {
    return '+$count';
  }

  @override
  String get readOnlyCalendar => 'Calendrier en lecture seule';

  @override
  String get sourceIcal => 'S\'abonner via une URL iCal';

  @override
  String get sourceIcalSubtitle =>
      'Lien .ics ou webcal:// (Google, Outlook, iCloud…)';

  @override
  String get sourceGoogle => 'Compte Google';

  @override
  String get sourceGoogleSubtitle =>
      'Synchroniser et modifier vos agendas Google';

  @override
  String get sourceLocal => 'Nouveau calendrier local';

  @override
  String get sourceLocalSubtitle => 'Stocké uniquement sur cet appareil';

  @override
  String get icalUrl => 'URL du calendrier';

  @override
  String get icalUrlHint => 'https://… ou webcal://…';

  @override
  String get nameOptional => 'Nom (facultatif)';

  @override
  String get name => 'Nom';

  @override
  String get subscribe => 'S\'abonner';

  @override
  String get create => 'Créer';

  @override
  String get invalidUrl => 'URL invalide';

  @override
  String get requiredField => 'Champ obligatoire';

  @override
  String icalError(String message) {
    return 'Impossible de charger le calendrier : $message';
  }

  @override
  String googleError(String message) {
    return 'Connexion à Google impossible : $message';
  }

  @override
  String get googleSingleAccountNote =>
      'Un seul compte Google peut être connecté à la fois sur cette version.';

  @override
  String get calendarAdded => 'Calendrier ajouté';

  @override
  String get manageCalendars => 'Gérer les calendriers';

  @override
  String lastSync(String date) {
    return 'Dernière synchro : $date';
  }

  @override
  String get neverSynced => 'Jamais synchronisé';

  @override
  String get syncNow => 'Synchroniser';

  @override
  String get removeSource => 'Supprimer la source';

  @override
  String removeSourceConfirm(String name) {
    return 'Supprimer « $name » et tous ses événements de cet appareil ?';
  }

  @override
  String get deleteCalendar => 'Supprimer le calendrier';

  @override
  String deleteCalendarConfirm(String name) {
    return 'Supprimer « $name » et tous ses événements ?';
  }

  @override
  String get rename => 'Renommer';

  @override
  String get general => 'Général';

  @override
  String get firstDayOfWeek => 'Premier jour de la semaine';

  @override
  String get localeDefault => 'Selon la langue';

  @override
  String get theme => 'Thème';

  @override
  String get themeSystem => 'Par défaut du système';

  @override
  String get themeLight => 'Clair';

  @override
  String get themeDark => 'Sombre';

  @override
  String get defaultDuration => 'Durée par défaut des événements';

  @override
  String minutes(int count) {
    return '$count minutes';
  }

  @override
  String get syncing => 'Synchronisation…';

  @override
  String syncFailed(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Échec de la synchronisation de $countString sources',
      one: 'Échec de la synchronisation d\'une source',
    );
    return '$_temp0';
  }

  @override
  String get eventDeleted => 'Événement supprimé';

  @override
  String errorMessage(String message) {
    return 'Erreur : $message';
  }

  @override
  String get sourceTypeLocal => 'Sur cet appareil';

  @override
  String get sourceTypeIcal => 'Abonnement iCal';

  @override
  String get sourceTypeGoogle => 'Google';

  @override
  String get noWritableCalendar =>
      'Aucun calendrier modifiable. Ajoutez un calendrier local ou un compte Google.';

  @override
  String get seriesInstanceNote =>
      'Seule cette occurrence de la série sera modifiée.';

  @override
  String get noEvents => 'Aucun événement';

  @override
  String get openMenu => 'Ouvrir le menu';

  @override
  String get goToToday => 'Aller à aujourd\'hui';

  @override
  String get newEvent => 'Nouvel événement';

  @override
  String get about => 'À propos';

  @override
  String get colorTomato => 'Tomate';

  @override
  String get colorFlamingo => 'Flamant';

  @override
  String get colorTangerine => 'Mandarine';

  @override
  String get colorBanana => 'Banane';

  @override
  String get colorSage => 'Sauge';

  @override
  String get colorBasil => 'Basilic';

  @override
  String get colorPeacock => 'Paon';

  @override
  String get colorBlueberry => 'Myrtille';

  @override
  String get colorLavender => 'Lavande';

  @override
  String get colorGrape => 'Raisin';

  @override
  String get colorGraphite => 'Graphite';

  @override
  String get repeat => 'Répétition';

  @override
  String get googleReconnect => 'Reconnexion à Google nécessaire';
}
