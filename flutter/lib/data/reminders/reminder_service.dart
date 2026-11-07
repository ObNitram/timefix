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

/// "Open the app" notification placed after the last scheduled alert when
/// some reminders could not be scheduled yet.
const sentinelAlertId = 104;

/// Keeps the device's scheduled alerts in sync with the events.
///
/// * Only the next alerts are scheduled (the platform's horizon, at most
///   [ReminderPlatform.maxPending]); [reschedule] runs on every app start,
///   return to the foreground and data change.
/// * Alerts whose time has passed are never cancelled: they may be ringing
///   or waiting in the notification shade.
/// * The first run of a process schedules everything again (alarms are lost
///   on force-stop, restored backups contain stale state), as does any change
///   of permissions; later runs only touch changed alerts.
class ReminderService {
  ReminderService({
    required this.platform,
    required this.repository,
    required this.prefs,
    required this.settings,
    this.horizon,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final ReminderPlatform platform;
  final CalendarRepository repository;
  final SharedPreferences prefs;
  final ReminderSettings Function() settings;
  /// Overrides the platform's planning horizon (tests).
  final Duration? horizon;
  final DateTime Function() _clock;

  static const _stateKey = 'scheduledReminders.v2';
  static const _permissionsKey = 'reminderPermissions';
  static const _snoozesKey = 'snoozedReminders';

  Future<void>? _running;
  bool _again = false;
  bool _fullNext = true;

  Duration get planningHorizon => horizon ?? platform.planningHorizon;

  /// Full-screen and alarm alerts still to come (planned and snoozed), so
  /// the app can show the ringing screen itself while it is in the
  /// foreground (the system gives no callback when a notification fires).
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

  /// Recomputes and schedules the upcoming alerts. Calls are serialized:
  /// a call during a run makes the run start over once it is done.
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

  /// Schedules every alert again (after a permission change, for instance).
  Future<void> rescheduleAll() {
    _fullNext = true;
    return reschedule();
  }

  Future<void> _reschedule() async {
    final full = _fullNext;
    _fullNext = false;
    final l10n = localizations();
    // Alert texts are formatted outside of the widget tree.
    await initializeDateFormatting(l10n.localeName);
    final now = _clock();
    final nowMs = now.millisecondsSinceEpoch;

    // Permission changes (also made in the system settings) may move alerts
    // between delivery mechanisms (AlarmKit / notification): redo everything.
    final perms = await platform.permissions();
    final fingerprint = ReminderPermission.values.map((p) => '${p.name}=${perms[p]?.name}').join(',');
    final forceAll = full || prefs.getString(_permissionsKey) != fingerprint;

    final until = now.add(planningHorizon);
    final calendars = {
      for (final c in await repository.getCalendars())
        if (c.visible) c.id: c
    };
    // Alerts may fire up to 4 weeks before the event, or after its start
    // (all-day "the same day at 9:00").
    final range = DateRange(
      addDays(dateOnly(now), -2),
      until.add(const Duration(days: 7 * 4 + 1)),
    );
    final events = await repository.eventsForRange(range, calendars.keys.toSet());
    final occurrences = expandEvents(events, calendars, range);
    final local = await repository.localReminders();
    final snoozes = await _activeSnoozes(now);
    // One slot for the sentinel, and the pending snoozes.
    final cap = (platform.maxPending - 1 - snoozes.length).clamp(0, platform.maxPending);
    final planned = planReminders(
      occurrences: occurrences,
      localReminders: local,
      now: now,
      until: until,
      maxCount: cap,
    );
    final later = planReminders(
      occurrences: occurrences,
      localReminders: local,
      now: now,
      until: until.add(const Duration(days: 7 * 4)),
    );

    final options = alarmOptions;
    final ringSig = '${options.sound}|${options.vibrate}|${options.autoStop.inMinutes}|${options.snoozeLabel}';
    final alerts = <ReminderAlert>[for (final p in planned) alertFor(p)];
    final signatures = <int, String>{
      for (var i = 0; i < planned.length; i++)
        planned[i].notificationId:
            '${planned[i].signature}|${l10n.localeName}|${planned[i].type == ReminderType.push ? '' : ringSig}',
    };

    // Some reminders are left for later (cap or horizon): remind the user to
    // open the app before the last scheduled alert is over.
    if (later.length > planned.length) {
      final at = planned.length >= cap && planned.isNotEmpty
          ? planned.last.fireAt.add(const Duration(minutes: 1))
          : until;
      alerts.add(ReminderAlert(
        id: sentinelAlertId,
        type: ReminderType.push,
        fireAt: at,
        title: l10n.appTitle,
        body: l10n.remindersSentinel,
        eventId: 'sentinel',
        start: at,
        end: at,
      ));
      signatures[sentinelAlertId] = 'sentinel|${at.millisecondsSinceEpoch}|${l10n.localeName}';
    }

    final previous = _loadState();
    final next = <int, ({String sig, int fireAt})>{
      for (final a in alerts) a.id: (sig: signatures[a.id]!, fireAt: a.fireAt.millisecondsSinceEpoch),
    };

    // Cancel only alerts that are still pending; fired ones are left alone.
    final toCancel = [
      for (final e in previous.entries)
        if (e.value.fireAt > nowMs && next[e.key]?.sig != e.value.sig) e.key
    ];
    if (toCancel.isNotEmpty) await platform.cancel(toCancel);
    for (final a in alerts) {
      if (!forceAll && previous[a.id]?.sig == next[a.id]!.sig) continue;
      await platform.schedule(a, options);
    }
    if (forceAll) {
      for (final s in snoozes) {
        await platform.schedule(s, options);
      }
    }
    await _saveState(next);
    await prefs.setString(_permissionsKey, fingerprint);

    upcomingRinging = [
      ...alerts.where((a) => a.type != ReminderType.push),
      ...snoozes.where((a) => a.type != ReminderType.push),
    ]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
  }

  Map<int, ({String sig, int fireAt})> _loadState() {
    try {
      final raw = jsonDecode(prefs.getString(_stateKey) ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in raw.entries)
          int.parse(e.key): (
            sig: (e.value as Map<String, dynamic>)['s'] as String,
            fireAt: (e.value['f'] as num).toInt(),
          ),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveState(Map<int, ({String sig, int fireAt})> state) => prefs.setString(
      _stateKey,
      jsonEncode({
        for (final e in state.entries) '${e.key}': {'s': e.value.sig, 'f': e.value.fireAt},
      }));

  // ---------------------------------------------------------------------------
  // Snooze
  // ---------------------------------------------------------------------------

  Map<int, ReminderAlert> _loadSnoozes() {
    try {
      final raw = jsonDecode(prefs.getString(_snoozesKey) ?? '{}') as Map<String, dynamic>;
      return {
        for (final e in raw.entries)
          if (ReminderAlert.fromPayload(e.value['a'] as String) case final a?)
            int.parse(e.key): a.copyWith(fireAt: DateTime.fromMillisecondsSinceEpoch((e.value['f'] as num).toInt())),
      };
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveSnoozes(Map<int, ReminderAlert> snoozes) => prefs.setString(
      _snoozesKey,
      jsonEncode({
        for (final e in snoozes.entries)
          '${e.key}': {'a': e.value.toPayload(), 'f': e.value.fireAt.millisecondsSinceEpoch},
      }));

  /// Pending snoozes; those whose event was deleted are cancelled.
  Future<List<ReminderAlert>> _activeSnoozes(DateTime now) async {
    final snoozes = _loadSnoozes();
    final keep = <int, ReminderAlert>{};
    final gone = <int>[];
    for (final e in snoozes.entries) {
      if (!e.value.fireAt.isAfter(now)) continue; // fired: forget it
      final eventId = e.value.eventId;
      final exists = eventId == 'test' || await repository.getEvent(eventId) != null;
      if (exists) {
        keep[e.key] = e.value;
      } else {
        gone.add(e.key);
      }
    }
    if (gone.isNotEmpty) await platform.cancel(gone);
    if (keep.length != snoozes.length) await _saveSnoozes(keep);
    return keep.values.toList();
  }

  /// Stops [alert] and delivers it again after the snooze delay.
  Future<DateTime> snooze(ReminderAlert alert) async {
    await platform.stop(alert.id);
    final at = _clock().add(alarmOptions.snooze);
    // Distinct id, tracked separately from planned alerts.
    final snoozed = alert.copyWith(id: stableNotificationId('snooze:${alert.id}'), fireAt: at);
    await platform.schedule(snoozed, alarmOptions);
    final snoozes = _loadSnoozes()..[snoozed.id] = snoozed;
    await _saveSnoozes(snoozes);
    upcomingRinging = [...upcomingRinging, if (snoozed.type != ReminderType.push) snoozed]
      ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return at;
  }

  Future<void> stop(ReminderAlert alert) => platform.stop(alert.id);

  /// Whether [id] is an alert this app scheduled (responses carrying other
  /// ids are ignored: on Android anyone can send the launch intent).
  bool isKnownAlert(int id) =>
      testAlertIds.containsValue(id) ||
      id == sentinelAlertId ||
      _loadState().containsKey(id) ||
      _loadSnoozes().containsKey(id);

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
    if (type != ReminderType.push) {
      upcomingRinging = [...upcomingRinging, alert]..sort((a, b) => a.fireAt.compareTo(b.fireAt));
    }
  }
}
