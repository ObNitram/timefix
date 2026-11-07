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

  @override
  String get sourceCalDav => 'Compte CalDAV';

  @override
  String get sourceCalDavSubtitle =>
      'Serveur TimeFix auto-hébergé, Nextcloud, Radicale, iCloud…';

  @override
  String get sourceTypeCalDav => 'CalDAV';

  @override
  String get serverUrl => 'Adresse du serveur';

  @override
  String get serverUrlHint => 'https://cal.exemple.fr';

  @override
  String get username => 'Identifiant';

  @override
  String get password => 'Mot de passe';

  @override
  String get connect => 'Se connecter';

  @override
  String caldavError(String message) {
    return 'Connexion CalDAV impossible : $message';
  }

  @override
  String get caldavAuthError => 'Identifiant ou mot de passe incorrect';

  @override
  String get newCalendar => 'Nouveau calendrier';

  @override
  String get changePassword => 'Modifier le mot de passe';

  @override
  String get passwordUpdated => 'Mot de passe mis à jour';

  @override
  String get conflictError =>
      'Cet événement a été modifié ailleurs. Les données ont été actualisées : réessayez.';

  @override
  String get caldavHelp =>
      'Pour un serveur TimeFix, utilisez l\'adresse du serveur (ex. https://cal.exemple.fr) et le compte créé par l\'administrateur.';

  @override
  String get account => 'Compte';

  @override
  String get reminders => 'Rappels';

  @override
  String get addReminder => 'Ajouter un rappel';

  @override
  String get reminderTypePush => 'Notification';

  @override
  String get reminderTypeFullScreen => 'Plein écran';

  @override
  String get reminderTypeAlarm => 'Alarme';

  @override
  String get reminderAtStart => 'Au moment de l\'événement';

  @override
  String reminderMinutesBefore(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString minutes avant',
      one: '1 minute avant',
    );
    return '$_temp0';
  }

  @override
  String reminderHoursBefore(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString heures avant',
      one: '1 heure avant',
    );
    return '$_temp0';
  }

  @override
  String reminderDaysBefore(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString jours avant',
      one: '1 jour avant',
    );
    return '$_temp0';
  }

  @override
  String reminderWeeksBefore(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString semaines avant',
      one: '1 semaine avant',
    );
    return '$_temp0';
  }

  @override
  String reminderHoursMinutesBefore(int hours, int minutes) {
    return '$hours h $minutes min avant';
  }

  @override
  String reminderMinutesAfter(int count) {
    return '$count min après le début';
  }

  @override
  String reminderSameDayAt(String time) {
    return 'Le jour même à $time';
  }

  @override
  String reminderDayBeforeAt(String time) {
    return 'La veille à $time';
  }

  @override
  String reminderDaysBeforeAt(int count, String time) {
    return '$count jours avant à $time';
  }

  @override
  String get reminderCustom => 'Personnalisé…';

  @override
  String get reminderCustomTitle => 'Rappel personnalisé';

  @override
  String get myPresets => 'Mes presets';

  @override
  String get unitMinutes => 'minutes';

  @override
  String get unitHours => 'heures';

  @override
  String get unitDays => 'jours';

  @override
  String get unitWeeks => 'semaines';

  @override
  String get daysBefore => 'Jours avant';

  @override
  String get atTime => 'Heure';

  @override
  String get fullScreenIosNote =>
      'Sur iPhone : notification urgente, sans plein écran.';

  @override
  String get alarmIosNote =>
      'Sur iPhone : alarme système à partir d\'iOS 26, notification urgente avant.';

  @override
  String get defaultReminders => 'Rappels par défaut';

  @override
  String get defaultRemindersTimed => 'Événements';

  @override
  String get defaultRemindersAllDay => 'Événements sur la journée';

  @override
  String get noReminders => 'Aucun rappel';

  @override
  String get newPreset => 'Nouveau preset';

  @override
  String get editPreset => 'Modifier le preset';

  @override
  String get deletePreset => 'Supprimer le preset';

  @override
  String get presetForAllDay => 'Pour les événements sur la journée';

  @override
  String get presetsHint =>
      'Vos presets apparaissent quand vous ajoutez un rappel à un événement.';

  @override
  String get alarmSection => 'Alarme';

  @override
  String get alarmSound => 'Sonnerie';

  @override
  String get soundSystem => 'Sonnerie d\'alarme du téléphone';

  @override
  String get soundClassic => 'Classique';

  @override
  String get soundDigital => 'Numérique';

  @override
  String get soundGentle => 'Douce';

  @override
  String get snoozeDuration => 'Répétition (snooze)';

  @override
  String get autoStop => 'Arrêt automatique après';

  @override
  String get vibration => 'Vibration';

  @override
  String get permissions => 'Autorisations';

  @override
  String get permissionNotifications => 'Notifications';

  @override
  String get permissionExactAlarms => 'Alarmes et rappels à l\'heure exacte';

  @override
  String get permissionFullScreen => 'Notifications plein écran';

  @override
  String get permissionAlarmKit => 'Alarmes (iOS 26 et plus)';

  @override
  String get permissionGranted => 'Autorisé';

  @override
  String get permissionDenied => 'Non autorisé';

  @override
  String get permissionUnsupported => 'Non disponible sur cet appareil';

  @override
  String get grant => 'Autoriser';

  @override
  String get testSection => 'Tester';

  @override
  String get testPush => 'Tester une notification';

  @override
  String get testFullScreen => 'Tester le plein écran';

  @override
  String get testAlarm => 'Tester l\'alarme';

  @override
  String get testScheduled =>
      'Déclenchement dans 5 secondes. Verrouillez l\'écran pour voir le rendu réel.';

  @override
  String get testEventTitle => 'Test TimeFix';

  @override
  String get alarmStop => 'Arrêter';

  @override
  String alarmSnooze(int minutes) {
    return 'Répéter ($minutes min)';
  }

  @override
  String get alarmDismiss => 'Fermer';

  @override
  String get openEvent => 'Ouvrir l\'événement';

  @override
  String get channelPush => 'Rappels';

  @override
  String get channelPushDescription => 'Notifications de rappel des événements';

  @override
  String get channelFullScreen => 'Rappels plein écran';

  @override
  String get channelFullScreenDescription => 'Rappels affichés en plein écran';

  @override
  String get channelAlarm => 'Alarmes';

  @override
  String get channelAlarmDescription => 'Rappels qui sonnent comme un réveil';

  @override
  String get notificationStartsNow => 'Commence maintenant';

  @override
  String get remindersDeviceOnly =>
      'Rappels enregistrés sur cet appareil uniquement.';

  @override
  String get deviceRemindersScopeTitle =>
      'Appliquer les rappels de cet appareil à';

  @override
  String snoozedUntil(String time) {
    return 'Répété à $time';
  }

  @override
  String get alarmSnoozeShort => 'Répéter';

  @override
  String get notificationPermissionHint =>
      'Autorisez les notifications pour recevoir vos rappels.';

  @override
  String get fullScreenPermissionHint =>
      'Les rappels plein écran et les alarmes ont besoin d\'une autorisation pour s\'afficher sur l\'écran verrouillé.';

  @override
  String get remindersSentinel =>
      'Ouvrez TimeFix pour programmer vos prochains rappels.';
}
