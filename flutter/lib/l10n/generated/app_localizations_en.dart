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

  @override
  String get sourceCalDav => 'CalDAV account';

  @override
  String get sourceCalDavSubtitle =>
      'Self-hosted TimeFix server, Nextcloud, Radicale, iCloud…';

  @override
  String get sourceTypeCalDav => 'CalDAV';

  @override
  String get serverUrl => 'Server address';

  @override
  String get serverUrlHint => 'https://cal.example.com';

  @override
  String get username => 'Username';

  @override
  String get password => 'Password';

  @override
  String get connect => 'Connect';

  @override
  String caldavError(String message) {
    return 'Could not connect to CalDAV: $message';
  }

  @override
  String get caldavAuthError => 'Wrong username or password';

  @override
  String get newCalendar => 'New calendar';

  @override
  String get changePassword => 'Change password';

  @override
  String get passwordUpdated => 'Password updated';

  @override
  String get conflictError =>
      'This event was changed elsewhere. Data has been refreshed: please try again.';

  @override
  String get caldavHelp =>
      'For a TimeFix server, use the server address (e.g. https://cal.example.com) and the account created by the administrator.';

  @override
  String get account => 'Account';

  @override
  String get reminders => 'Reminders';

  @override
  String get addReminder => 'Add reminder';

  @override
  String get reminderTypePush => 'Notification';

  @override
  String get reminderTypeFullScreen => 'Full screen';

  @override
  String get reminderTypeAlarm => 'Alarm';

  @override
  String get reminderAtStart => 'At time of event';

  @override
  String reminderMinutesBefore(num count) {
    final intl.NumberFormat countNumberFormat = intl.NumberFormat.compact(
      locale: localeName,
    );
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString minutes before',
      one: '1 minute before',
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
      other: '$countString hours before',
      one: '1 hour before',
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
      other: '$countString days before',
      one: '1 day before',
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
      other: '$countString weeks before',
      one: '1 week before',
    );
    return '$_temp0';
  }

  @override
  String reminderHoursMinutesBefore(int hours, int minutes) {
    return '$hours h $minutes min before';
  }

  @override
  String reminderMinutesAfter(int count) {
    return '$count min after the start';
  }

  @override
  String reminderSameDayAt(String time) {
    return 'On the day at $time';
  }

  @override
  String reminderDayBeforeAt(String time) {
    return 'The day before at $time';
  }

  @override
  String reminderDaysBeforeAt(int count, String time) {
    return '$count days before at $time';
  }

  @override
  String get reminderCustom => 'Custom…';

  @override
  String get reminderCustomTitle => 'Custom reminder';

  @override
  String get myPresets => 'My presets';

  @override
  String get unitMinutes => 'minutes';

  @override
  String get unitHours => 'hours';

  @override
  String get unitDays => 'days';

  @override
  String get unitWeeks => 'weeks';

  @override
  String get daysBefore => 'Days before';

  @override
  String get atTime => 'Time';

  @override
  String get fullScreenIosNote =>
      'On iPhone: time-sensitive notification, no full screen.';

  @override
  String get alarmIosNote =>
      'On iPhone: system alarm on iOS 26 and later, time-sensitive notification before.';

  @override
  String get defaultReminders => 'Default reminders';

  @override
  String get defaultRemindersTimed => 'Events';

  @override
  String get defaultRemindersAllDay => 'All-day events';

  @override
  String get noReminders => 'No reminders';

  @override
  String get newPreset => 'New preset';

  @override
  String get editPreset => 'Edit preset';

  @override
  String get deletePreset => 'Delete preset';

  @override
  String get presetForAllDay => 'For all-day events';

  @override
  String get presetsHint =>
      'Your presets are offered when you add a reminder to an event.';

  @override
  String get alarmSection => 'Alarm';

  @override
  String get alarmSound => 'Sound';

  @override
  String get soundSystem => 'Phone alarm sound';

  @override
  String get soundClassic => 'Classic';

  @override
  String get soundDigital => 'Digital';

  @override
  String get soundGentle => 'Gentle';

  @override
  String get snoozeDuration => 'Snooze length';

  @override
  String get autoStop => 'Stop automatically after';

  @override
  String get vibration => 'Vibration';

  @override
  String get permissions => 'Permissions';

  @override
  String get permissionNotifications => 'Notifications';

  @override
  String get permissionExactAlarms => 'Exact alarms and reminders';

  @override
  String get permissionFullScreen => 'Full-screen notifications';

  @override
  String get permissionAlarmKit => 'Alarms (iOS 26 and later)';

  @override
  String get permissionGranted => 'Allowed';

  @override
  String get permissionDenied => 'Not allowed';

  @override
  String get permissionUnsupported => 'Not available on this device';

  @override
  String get grant => 'Allow';

  @override
  String get testSection => 'Test';

  @override
  String get testPush => 'Test a notification';

  @override
  String get testFullScreen => 'Test full screen';

  @override
  String get testAlarm => 'Test the alarm';

  @override
  String get testScheduled =>
      'Firing in 5 seconds. Lock the screen to see the real behaviour.';

  @override
  String get testEventTitle => 'TimeFix test';

  @override
  String get alarmStop => 'Stop';

  @override
  String alarmSnooze(int minutes) {
    return 'Snooze ($minutes min)';
  }

  @override
  String get alarmDismiss => 'Dismiss';

  @override
  String get openEvent => 'Open event';

  @override
  String get channelPush => 'Reminders';

  @override
  String get channelPushDescription => 'Event reminder notifications';

  @override
  String get channelFullScreen => 'Full-screen reminders';

  @override
  String get channelFullScreenDescription => 'Reminders shown full screen';

  @override
  String get channelAlarm => 'Alarms';

  @override
  String get channelAlarmDescription =>
      'Reminders that ring like an alarm clock';

  @override
  String get notificationStartsNow => 'Starting now';

  @override
  String get remindersDeviceOnly => 'Reminders saved on this device only.';

  @override
  String snoozedUntil(String time) {
    return 'Snoozed until $time';
  }

  @override
  String get alarmSnoozeShort => 'Snooze';

  @override
  String get notificationPermissionHint =>
      'Allow notifications to receive your reminders.';

  @override
  String get fullScreenPermissionHint =>
      'Full-screen reminders and alarms need a permission to show over the lock screen.';
}
