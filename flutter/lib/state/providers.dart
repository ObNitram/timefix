import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/date_utils.dart';
import '../data/caldav/caldav_client.dart';
import '../data/calendar_repository.dart';
import '../data/credentials.dart';
import '../data/event_service.dart';
import '../data/google/google_calendar_service.dart';
import '../data/ical/ical_service.dart';
import '../data/sync/sync_service.dart';
import '../domain/models.dart';
import '../domain/occurrences.dart';

export '../domain/occurrences.dart';
import '../domain/reminders.dart';

// -----------------------------------------------------------------------------
// Services
// -----------------------------------------------------------------------------

final repositoryProvider = Provider<CalendarRepository>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

final googleGatewayProvider =
    Provider<GoogleCalendarGateway>((ref) => GoogleCalendarService());

final icalServiceProvider = Provider<IcalService>((ref) => IcalService());

final credentialStoreProvider =
    Provider<CredentialStore>((ref) => const SecureCredentialStore());

/// Creates CalDAV clients (overridden in tests).
final calDavClientFactoryProvider = Provider<CalDavClientFactory>(
    (ref) => (username, password) => CalDavClient(username: username, password: password));

final syncServiceProvider = Provider<SyncService>((ref) => SyncService(
      repository: ref.watch(repositoryProvider),
      ical: ref.watch(icalServiceProvider),
      google: ref.watch(googleGatewayProvider),
      credentials: ref.watch(credentialStoreProvider),
      caldavClientFactory: ref.watch(calDavClientFactoryProvider),
    ));

final eventServiceProvider = Provider<EventService>((ref) => EventService(
      repository: ref.watch(repositoryProvider),
      google: ref.watch(googleGatewayProvider),
      sync: ref.watch(syncServiceProvider),
    ));

// -----------------------------------------------------------------------------
// Data
// -----------------------------------------------------------------------------

/// Incremented after every write so that data providers reload.
class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

final sourcesProvider = FutureProvider<List<CalendarSource>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).getSources();
});

final calendarsProvider = FutureProvider<List<CalendarInfo>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(repositoryProvider).getCalendars();
});

/// Device-only reminders of one event (by [localReminderKey]).
final localRemindersProvider =
    FutureProvider.family<List<Reminder>, String>((ref, key) async {
  ref.watch(dataRevisionProvider);
  final map = await ref.watch(repositoryProvider).localReminders({key});
  return map[key] ?? const [];
}, isAutoDispose: true);

final calendarsByIdProvider = Provider<Map<String, CalendarInfo>>((ref) {
  final cals = ref.watch(calendarsProvider).value ?? const [];
  return {for (final c in cals) c.id: c};
});

final sourcesByIdProvider = Provider<Map<String, CalendarSource>>((ref) {
  final sources = ref.watch(sourcesProvider).value ?? const [];
  return {for (final s in sources) s.id: s};
});

/// Calendars the user can create events in.
final writableCalendarsProvider = Provider<List<CalendarInfo>>((ref) {
  final cals = ref.watch(calendarsProvider).value ?? const [];
  return cals.where((c) => !c.readOnly).toList();
});

/// Occurrences of visible calendars overlapping a range, sorted by start.
final occurrencesProvider =
    FutureProvider.family<List<EventOccurrence>, DateRange>((ref, range) async {
  ref.watch(dataRevisionProvider);
  final calendars = await ref.watch(calendarsProvider.future);
  final visible = {
    for (final c in calendars)
      if (c.visible) c.id: c
  };
  if (visible.isEmpty) return const [];
  final events =
      await ref.watch(repositoryProvider).eventsForRange(range, visible.keys.toSet());
  return expandEvents(events, visible, range);
}, isAutoDispose: true);

// -----------------------------------------------------------------------------
// Navigation state
// -----------------------------------------------------------------------------

/// Date currently shown by the active view (drives the app bar title).
class FocusedDate extends Notifier<DateTime> {
  @override
  DateTime build() => dateOnly(DateTime.now());

  void set(DateTime date) {
    final d = dateOnly(date);
    if (d != state) state = d;
  }
}

final focusedDateProvider = NotifierProvider<FocusedDate, DateTime>(FocusedDate.new);

/// A request for the active view to scroll to a date. The [id] makes every
/// request distinct, so jumping twice to the same date works.
class JumpRequest {
  JumpRequest(this.date, this.id);
  final DateTime date;
  final int id;
}

class JumpController extends Notifier<JumpRequest?> {
  int _counter = 0;

  @override
  JumpRequest? build() => null;

  void jumpTo(DateTime date) => state = JumpRequest(dateOnly(date), ++_counter);
}

final jumpProvider = NotifierProvider<JumpController, JumpRequest?>(JumpController.new);

// -----------------------------------------------------------------------------
// Synchronisation status
// -----------------------------------------------------------------------------

class SyncState {
  const SyncState({this.running = false, this.lastReport});
  final bool running;
  final SyncReport? lastReport;
}

class SyncController extends Notifier<SyncState> {
  @override
  SyncState build() => const SyncState();

  Future<SyncReport?> syncAll({bool interactive = false}) async {
    if (state.running) return null;
    state = SyncState(running: true, lastReport: state.lastReport);
    SyncReport? report;
    try {
      report = await ref.read(syncServiceProvider).syncAll(interactive: interactive);
    } finally {
      if (ref.mounted) {
        state = SyncState(running: false, lastReport: report);
        ref.read(dataRevisionProvider.notifier).bump();
      }
    }
    return report;
  }

  Future<void> syncSource(CalendarSource source) async {
    state = SyncState(running: true, lastReport: state.lastReport);
    try {
      await ref.read(syncServiceProvider).syncSource(source, interactive: true);
    } finally {
      if (ref.mounted) {
        state = SyncState(running: false, lastReport: state.lastReport);
        ref.read(dataRevisionProvider.notifier).bump();
      }
    }
  }
}

final syncControllerProvider =
    NotifierProvider<SyncController, SyncState>(SyncController.new);
