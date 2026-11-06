import 'dart:async';
import 'dart:convert';
import 'dart:ui' show Color, Locale, PlatformDispatcher;

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/date_utils.dart';
import '../../domain/models.dart';
import '../../domain/occurrences.dart';
import '../../domain/reminder_planner.dart';
import '../../domain/reminder_settings.dart';
import '../../domain/reminders.dart';
import '../../l10n/generated/app_localizations.dart';
import '../calendar_repository.dart';
import 'reminder_platform.dart';

/// Ids reserved for alerts that are not tied to a planned reminder.
const testAlertIds = {
  ReminderType.push: 101,
  ReminderType.fullScreen: 102,
  ReminderType.alarm: 103,
};

/// Keeps the device's scheduled alerts in sync with the events.
///
/// Only the next alerts are scheduled (a horizon of a few weeks, and at most
/// [ReminderPlatform.maxPending]); [reschedule] runs again on every app start,
/// return to the foreground and data change, so later alerts are added in
/// time. Only changed alerts are cancelled / scheduled again.
class ReminderService {
  ReminderService({
    required this.platform,
    required this.repository,
    required this.prefs,
    required this.settings,
    this.horizon = const Duration(days: 21),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReminderPlatform platform;
  final CalendarRepository repository;
  final SharedPreferences prefs;
  final ReminderSettings Function() settings;
  final Duration horizon;
  final DateTime Function() _clock;

  static const _stateKey = 'scheduledReminders';

  Future<void>? _running;
  bool _again = false;

  /// Full-screen and alarm alerts scheduled by the last [reschedule], so the
  /// app can show the ringing screen itself while it is in the foreground
  /// (the system gives no callback when a notification fires).
  List<ReminderAlert> upcomingRinging = const [];

  AlarmOptions get alarmOptions {
    final s = settings();
    final l10n = localizations();
    return AlarmOptions(
      sound: s.alarmSound,
      vibrate: s.vibrate,
      autoStop: Duration(minutes: s.autoStopMinutes),
      snooze: Duration(minutes: s.snoozeMinutes),
      stopLabel: l10n.alarmStop,
      snoozeLabel: l10n.alarmSnooze(s.snoozeMinutes),
      dismissLabel: l10n.alarmDismiss,
      channelPushName: l10n.channelPush,
      channelPushDescription: l10n.channelPushDescription,
      channelFullScreenName: l10n.channelFullScreen,
      channelFullScreenDescription: l10n.channelFullScreenDescription,
      channelAlarmName: l10n.channelAlarm,
      channelAlarmDescription: l10n.channelAlarmDescription,
      soundLabel: switch (s.alarmSound) {
        'classic' => l10n.soundClassic,
        'digital' => l10n.soundDigital,
        'gentle' => l10n.soundGentle,
        _ => l10n.soundSystem,
      },
    );
  }

  static AppLocalizations localizations([Locale? locale]) {
    final l = locale ?? PlatformDispatcher.instance.locale;
    return lookupAppLocalizations(Locale(l.languageCode == 'fr' ? 'fr' : 'en'));
  }

  static ReminderTexts texts([Locale? locale]) {
    final l = localizations(locale);
    return ReminderTexts(stop: l.alarmStop, snooze: l.alarmSnoozeShort);
  }

  /// Text of an alert: time of the event and location.
  static ReminderAlert alertFor(PlannedReminder p, {Locale? locale}) {
    final l10n = localizations(locale);
    final lang = l10n.localeName;
    final o = p.occurrence;
    final time = o.allDay
        ? l10n.allDay
        : '${DateFormat.jm(lang).format(o.start)} – ${DateFormat.jm(lang).format(o.end)}';
    final parts = [
      if (p.reminder.minutesBefore == 0 && !o.allDay) l10n.notificationStartsNow,
      if (!isSameDay(o.start, p.fireAt)) DateFormat.MMMEd(lang).format(o.start),
      time,
      if (o.event.location?.isNotEmpty ?? false) o.event.location!,
    ];
    return ReminderAlert(
      id: p.notificationId,
      type: p.type,
      fireAt: p.fireAt,
      title: o.event.title.trim().isEmpty ? l10n.noTitle : o.event.title,
      body: parts.join(' · '),
      eventId: o.event.id,
      start: o.start,
      end: o.end,
      allDay: o.allDay,
      location: o.event.location,
    );
  }

  /// Recomputes and schedules the upcoming alerts. Concurrent calls are
  /// coalesced.
  Future<void> reschedule() {
    if (_running != null) {
      _again = true;
      return _running!;
    }
    final run = () async {
      try {
        do {
          _again = false;
          await _reschedule();
        } while (_again);
      } finally {
        _running = null;
      }
    }();
    _running = run;
    return run;
  }

  Future<void> _reschedule() async {
    // Alert texts are formatted outside of the widget tree.
    await initializeDateFormatting(localizations().localeName);
    final now = _clock();
    final until = now.add(horizon);
    final calendars = {
      for (final c in await repository.getCalendars())
        if (c.visible) c.id: c
    };
    // Alerts may fire up to 4 weeks before the event, or after its start
    // (all-day "the same day at 9:00").
    final range = DateRange(
      addDays(dateOnly(now), -2),
      until.add(const Duration(minutes: maxReminderMinutes)),
    );
    final events = await repository.eventsForRange(range, calendars.keys.toSet());
    final occurrences = expandEvents(events, calendars, range);
    final planned = planReminders(
      occurrences: occurrences,
      localReminders: await repository.localReminders(),
      now: now,
      until: until,
      maxCount: platform.maxPending,
    );

    final options = alarmOptions;
    final optionsSig = '${options.sound}|${options.vibrate}|${options.autoStop.inMinutes}|'
        '${options.snoozeLabel}';
    final previous = _loadState();
    final next = <int, String>{};
    for (final p in planned) {
      next[p.notificationId] = '${p.signature}|${p.type == ReminderType.alarm ? optionsSig : ''}';
    }

    final toCancel = [
      for (final e in previous.entries)
        if (next[e.key] != e.value) e.key
    ];
    if (toCancel.isNotEmpty) await platform.cancel(toCancel);
    for (final p in planned) {
      if (previous[p.notificationId] == next[p.notificationId]) continue;
      await platform.schedule(alertFor(p), options);
    }
    await prefs.setString(_stateKey, jsonEncode({for (final e in next.entries) '${e.key}': e.value}));
    upcomingRinging = [
      for (final p in planned)
        if (p.type != ReminderType.push) alertFor(p),
    ];
  }

  Map<int, String> _loadState() {
    try {
      final raw = jsonDecode(prefs.getString(_stateKey) ?? '{}') as Map<String, dynamic>;
      return {for (final e in raw.entries) int.parse(e.key): e.value as String};
    } catch (_) {
      return {};
    }
  }

  /// Forgets everything that was scheduled (e.g. after a permission change).
  Future<void> rescheduleAll() async {
    final previous = _loadState();
    if (previous.isNotEmpty) await platform.cancel(previous.keys);
    await prefs.remove(_stateKey);
    await reschedule();
  }

  /// Stops [alert] and delivers it again after the snooze delay.
  Future<DateTime> snooze(ReminderAlert alert) async {
    await platform.stop(alert.id);
    final at = _clock().add(alarmOptions.snooze);
    // Distinct id so that the next rescheduling does not cancel it.
    final snoozeId = stableNotificationId('snooze:${alert.id}');
    await platform.schedule(alert.copyWith(id: snoozeId, fireAt: at), alarmOptions);
    return at;
  }

  Future<void> stop(ReminderAlert alert) => platform.stop(alert.id);

  /// Delivers a sample alert of [type] in 5 seconds.
  Future<void> scheduleTest(ReminderType type, {Locale? locale}) async {
    final l10n = localizations(locale);
    await initializeDateFormatting(l10n.localeName);
    final now = _clock();
    final start = DateTime(now.year, now.month, now.day, now.hour + 1);
    final event = CalendarEvent(
      id: 'test',
      calendarId: 'test',
      title: l10n.testEventTitle,
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
    final occurrence = EventOccurrence(
        event: event, start: event.start, end: event.end, color: const Color(0x00000000));
    final alert = alertFor(PlannedReminder(occurrence: occurrence, reminder: Reminder(0, type)), locale: locale)
        .copyWith(id: testAlertIds[type], fireAt: now.add(const Duration(seconds: 5)));
    await platform.cancel([alert.id]);
    await platform.schedule(alert, alarmOptions);
  }
}

