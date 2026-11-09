import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timefix/app.dart';
import 'package:timefix/core/colors.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/data/calendar_repository.dart';
import 'package:timefix/data/reminders/reminder_platform.dart';
import 'package:timefix/data/google/google_calendar_service.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/state/providers.dart';
import 'package:timefix/state/reminder_providers.dart';
import 'package:timefix/state/settings.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;

/// In-memory fake of the Google Calendar API.
class FakeGoogleGateway implements GoogleCalendarGateway {
  final calendars = <gcal.CalendarListEntry>[];
  final events = <String, List<gcal.Event>>{};
  int _ids = 0;
  String email = 'user@example.com';

  @override
  Future<String> signIn() async => email;
  @override
  Future<void> signOut() async {}
  @override
  Future<String?> currentAccount() async => email;

  @override
  Future<List<gcal.CalendarListEntry>> listCalendars({bool interactive = false}) async =>
      calendars;

  @override
  Future<List<gcal.Event>> listEvents(String calendarId, DateTime timeMin, DateTime timeMax,
          {bool interactive = false}) async =>
      events[calendarId] ?? [];

  @override
  Future<gcal.Event> insertEvent(String calendarId, gcal.Event event) async {
    event.id = 'g${_ids++}';
    events.putIfAbsent(calendarId, () => []).add(event);
    return event;
  }

  /// Body of the last PATCH request.
  gcal.Event? lastPatch;

  @override
  Future<gcal.Event> patchEvent(String calendarId, String eventId, gcal.Event event) async {
    lastPatch = event;
    final list = events[calendarId]!;
    final i = list.indexWhere((e) => e.id == eventId);
    // PATCH: the fields sent replace the stored ones, the others are kept.
    final merged = gcal.Event.fromJson({
      ...jsonDecode(jsonEncode(list[i].toJson())) as Map<String, dynamic>,
      ...jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>,
      'id': eventId,
    });
    list[i] = merged;
    return merged;
  }

  @override
  Future<void> deleteEvent(String calendarId, String eventId) async {
    events[calendarId]?.removeWhere((e) => e.id == eventId);
  }
}

/// Repository with a local source, two calendars and a few events around
/// today.
Future<InMemoryCalendarRepository> seededRepository({DateTime? today}) async {
  final repo = InMemoryCalendarRepository();
  final t = dateOnly(today ?? DateTime.now());
  await repo.upsertSource(
      const CalendarSource(id: 'local', type: SourceType.local, name: 'Local'));
  await repo.upsertCalendar(CalendarInfo(
      id: 'local:default', sourceId: 'local', name: 'Mon calendrier', color: calendarPalette[6].color));
  await repo.upsertCalendar(CalendarInfo(
      id: 'local:sport', sourceId: 'local', name: 'Sport', color: calendarPalette[4].color, sortOrder: 1));

  CalendarEvent ev(String id, String cal, String title, DateTime s, DateTime e,
          {bool allDay = false, String? rrule, String? location}) =>
      CalendarEvent(
          id: id,
          calendarId: cal,
          title: title,
          start: s,
          end: e,
          allDay: allDay,
          rrule: rrule,
          location: location);

  final events = [
    ev('1', 'local:default', 'Réunion d\'équipe', t.add(const Duration(hours: 9)),
        t.add(const Duration(hours: 10)), location: 'Salle A'),
    ev('2', 'local:default', 'Déjeuner avec Paul', t.add(const Duration(hours: 12, minutes: 30)),
        t.add(const Duration(hours: 13, minutes: 30))),
    ev('3', 'local:sport', 'Course à pied', addDays(t, 1).add(const Duration(hours: 7)),
        addDays(t, 1).add(const Duration(hours: 8)), rrule: 'FREQ=WEEKLY'),
    ev('4', 'local:default', 'Vacances', addDays(t, 3), addDays(t, 6), allDay: true),
    ev('5', 'local:default', 'Revue de code', addDays(t, 2).add(const Duration(hours: 14)),
        addDays(t, 2).add(const Duration(hours: 15, minutes: 30))),
    ev('6', 'local:sport', 'Yoga', addDays(t, 2).add(const Duration(hours: 14, minutes: 30)),
        addDays(t, 2).add(const Duration(hours: 15, minutes: 30))),
    ev('7', 'local:default', 'Anniversaire', addDays(t, -2), addDays(t, -1),
        allDay: true, rrule: 'FREQ=YEARLY'),
  ];
  for (final e in events) {
    await repo.upsertEvent(e);
  }
  return repo;
}

Future<Widget> buildTestApp({
  required CalendarRepository repository,
  GoogleCalendarGateway? google,
  ReminderPlatform? reminders,
  Map<String, Object> prefs = const {},
}) async {
  tzdata.initializeTimeZones();
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sp),
      repositoryProvider.overrideWithValue(repository),
      googleGatewayProvider.overrideWithValue(google ?? FakeGoogleGateway()),
      reminderPlatformProvider.overrideWithValue(reminders ?? FakeReminderPlatform()),
    ],
    child: const TimefixApp(syncOnStart: false),
  );
}
