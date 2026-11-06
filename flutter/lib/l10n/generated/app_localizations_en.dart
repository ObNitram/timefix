// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'TimeFix';

  @override
  String get viewSchedule => 'Schedule';

  @override
  String get viewWeek => 'Week';

  @override
  String get viewMonth => 'Month';

  @override
  String get today => 'Today';

  @override
  String get search => 'Search';

  @override
  String get searchHint => 'Search events';

  @override
  String get noResults => 'No results';

  @override
  String get settings => 'Settings';

  @override
  String get refresh => 'Refresh';

  @override
  String get addCalendar => 'Add calendar';

  @override
  String get calendars => 'Calendars';

  @override
  String get myCalendar => 'My calendar';

  @override
  String get noTitle => '(No title)';

  @override
  String get allDay => 'All day';

  @override
  String get addTitle => 'Add title';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get ok => 'OK';

  @override
  String get discardChangesTitle => 'Discard changes?';

  @override
  String get discard => 'Discard';

  @override
  String get keepEditing => 'Keep editing';

  @override
  String get deleteEventTitle => 'Delete this event?';

  @override
  String get deleteRecurringTitle => 'Delete recurring event';

  @override
  String get editRecurringTitle => 'Edit recurring event';

  @override
  String get scopeThis => 'This event';

  @override
  String get scopeFollowing => 'This and following events';

  @override
  String get scopeAll => 'All events';

  @override
  String get addLocation => 'Add location';

  @override
  String get addDescription => 'Add description';

  @override
  String get calendar => 'Calendar';

  @override
  String get defaultColor => 'Default color';

  @override
  String get color => 'Color';

  @override
  String get repeatNone => 'Does not repeat';

  @override
  String get repeatDaily => 'Every day';

  @override
  String repeatWeekly(String weekday) {
    return 'Every week on $weekday';
  }

  @override
  String repeatMonthly(int day) {
    return 'Every month on day $day';
  }

  @override
  String repeatYearly(String date) {
    return 'Every year on $date';
  }

  @override
  String get repeatWeekdays => 'Every weekday (Monday to Friday)';

  @override
  String get repeatCustom => 'Custom recurrence';

  @override
  String repeatEveryNDays(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Every $countString days',
      one: 'Every day',
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
      other: 'Every $countString weeks',
      one: 'Every week',
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
      other: 'Every $countString months',
      one: 'Every month',
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
      other: 'Every $countString years',
      one: 'Every year',
    );
    return '$_temp0';
  }

  @override
  String repeatOnDays(String base, String days) {
    return '$base on $days';
  }

  @override
  String repeatUntil(String base, String date) {
    return '$base, until $date';
  }

  @override
  String repeatCount(String base, int count) {
    return '$base, $count times';
  }

  @override
  String get nothingPlanned => 'Nothing planned';

  @override
  String moreEvents(int count) {
    return '+$count';
  }

  @override
  String get readOnlyCalendar => 'Read-only calendar';

  @override
  String get sourceIcal => 'Subscribe with an iCal URL';

  @override
  String get sourceIcalSubtitle =>
      'An .ics or webcal:// link (Google, Outlook, iCloud…)';

  @override
  String get sourceGoogle => 'Google account';

  @override
  String get sourceGoogleSubtitle => 'Sync and edit your Google calendars';

  @override
  String get sourceLocal => 'New local calendar';

  @override
  String get sourceLocalSubtitle => 'Stored only on this device';

  @override
  String get icalUrl => 'Calendar URL';

  @override
  String get icalUrlHint => 'https://… or webcal://…';

  @override
  String get nameOptional => 'Name (optional)';

  @override
  String get name => 'Name';

  @override
  String get subscribe => 'Subscribe';

  @override
  String get create => 'Create';

  @override
  String get invalidUrl => 'Invalid URL';

  @override
  String get requiredField => 'Required';

  @override
  String icalError(String message) {
    return 'Could not load the calendar: $message';
  }

  @override
  String googleError(String message) {
    return 'Could not connect to Google: $message';
  }

  @override
  String get googleSingleAccountNote =>
      'Only one Google account can be connected at a time in this version.';

  @override
  String get calendarAdded => 'Calendar added';

  @override
  String get manageCalendars => 'Manage calendars';

  @override
  String lastSync(String date) {
    return 'Last synced: $date';
  }

  @override
  String get neverSynced => 'Never synced';

  @override
  String get syncNow => 'Sync now';

  @override
  String get removeSource => 'Remove source';

  @override
  String removeSourceConfirm(String name) {
    return 'Remove \"$name\" and all its events from this device?';
  }

  @override
  String get deleteCalendar => 'Delete calendar';

  @override
  String deleteCalendarConfirm(String name) {
    return 'Delete \"$name\" and all its events?';
  }

  @override
  String get rename => 'Rename';

  @override
  String get general => 'General';

  @override
  String get firstDayOfWeek => 'Start of the week';

  @override
  String get localeDefault => 'Locale default';

  @override
  String get theme => 'Theme';

  @override
  String get themeSystem => 'System default';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get defaultDuration => 'Default event duration';

  @override
  String minutes(int count) {
    return '$count minutes';
  }

  @override
  String get syncing => 'Syncing…';

  @override
  String syncFailed(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Sync failed for $countString sources',
      one: 'Sync failed for one source',
    );
    return '$_temp0';
  }

  @override
  String get eventDeleted => 'Event deleted';

  @override
  String errorMessage(String message) {
    return 'Error: $message';
  }

  @override
  String get sourceTypeLocal => 'On this device';

  @override
  String get sourceTypeIcal => 'iCal subscription';

  @override
  String get sourceTypeGoogle => 'Google';

  @override
  String get noWritableCalendar =>
      'No editable calendar. Add a local calendar or a Google account.';

  @override
  String get seriesInstanceNote =>
      'Only this occurrence of the series will be changed.';

  @override
  String get noEvents => 'No events';

  @override
  String get openMenu => 'Open menu';

  @override
  String get goToToday => 'Jump to today';

  @override
  String get newEvent => 'New event';

  @override
  String get about => 'About';

  @override
  String get colorTomato => 'Tomato';

  @override
  String get colorFlamingo => 'Flamingo';

  @override
  String get colorTangerine => 'Tangerine';

  @override
  String get colorBanana => 'Banana';

  @override
  String get colorSage => 'Sage';

  @override
  String get colorBasil => 'Basil';

  @override
  String get colorPeacock => 'Peacock';

  @override
  String get colorBlueberry => 'Blueberry';

  @override
  String get colorLavender => 'Lavender';

  @override
  String get colorGrape => 'Grape';

  @override
  String get colorGraphite => 'Graphite';

  @override
  String get repeat => 'Repeat';

  @override
  String get googleReconnect => 'Google sign-in required';
}
