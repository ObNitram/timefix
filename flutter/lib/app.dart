import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/reminders/reminder_platform.dart';
import 'data/reminders/reminder_service.dart';
import 'domain/models.dart';
import 'domain/reminders.dart';
import 'l10n/generated/app_localizations.dart';
import 'state/providers.dart';
import 'state/reminder_providers.dart';
import 'state/reminder_settings.dart';
import 'state/settings.dart';
import 'ui/event/event_details_screen.dart';
import 'ui/home/home_screen.dart';
import 'ui/reminders/alarm_ring_screen.dart';
import 'ui/theme.dart';

/// Used to open screens from notification callbacks.
final appNavigatorKey = GlobalKey<NavigatorState>();

class TimefixApp extends ConsumerWidget {
  const TimefixApp({super.key, this.syncOnStart = true});

  /// Disabled in widget tests.
  final bool syncOnStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      navigatorKey: appNavigatorKey,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Bootstrap(syncOnStart: syncOnStart, child: const HomeScreen()),
    );
  }
}

/// Creates the default local calendar on first launch (with a localized name),
/// starts a background synchronisation of remote sources and keeps the
/// device's reminders scheduled.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap({required this.child, required this.syncOnStart});

  final Widget child;
  final bool syncOnStart;

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> with WidgetsBindingObserver {
  bool _started = false;
  Timer? _rescheduleDebounce;
  Timer? _foregroundRing;
  int? _ringingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rescheduleDebounce?.cancel();
    _foregroundRing?.cancel();
    super.dispose();
  }

  /// While the app is open, shows the ringing screen when the next
  /// full-screen / alarm reminder fires.
  void _armForegroundRing() {
    _foregroundRing?.cancel();
    final next = ref.read(reminderServiceProvider).upcomingRinging.firstOrNull;
    if (next == null) return;
    final delay = next.fireAt.difference(DateTime.now());
    if (delay.isNegative || delay > const Duration(hours: 12)) return;
    _foregroundRing = Timer(delay, () {
      if (!mounted) return;
      _showRingScreen(next, launchedByAlert: false);
      // Let the system notification appear first, then look further.
      Timer(const Duration(seconds: 2), () {
        if (mounted) _scheduleReminders();
      });
    });
  }

  void _scheduleReminders() {
    _rescheduleDebounce?.cancel();
    _rescheduleDebounce = Timer(const Duration(milliseconds: 800), () async {
      if (!mounted) return;
      await ref.read(reminderServiceProvider).reschedule();
      if (mounted && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _armForegroundRing();
      }
    });
  }

  Future<void> _startReminders() async {
    final platform = ref.read(reminderPlatformProvider);
    await platform.initialize(texts: ReminderService.texts(), onResponse: _onReminderResponse);
    final launch = await platform.takeLaunchResponse();
    if (launch != null) _onReminderResponse(launch, launchedByAlert: true);
    await ref.read(reminderServiceProvider).reschedule();
    _armForegroundRing();
  }

  Future<void> _onReminderResponse(ReminderResponse response, {bool? launchedByAlert}) async {
    // Opened from the lock screen / another app: go back there afterwards.
    final background = launchedByAlert ??
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed;
    final service = ref.read(reminderServiceProvider);
    final alert = response.alert;
    // On Android any app can send the launch intent with a made-up payload:
    // act only on alerts this app scheduled or that are really displayed.
    if (!service.isKnownAlert(alert.id) &&
        await ref.read(reminderPlatformProvider).isRinging(alert.id) != true) {
      return;
    }
    switch (response.action) {
      case ReminderAction.stop:
        await service.stop(alert);
      case ReminderAction.snooze:
        await service.snooze(alert);
      case ReminderAction.open:
        if (alert.type == ReminderType.push) {
          await service.stop(alert);
          await _openEvent(alert);
        } else {
          _showRingScreen(alert, launchedByAlert: background);
        }
    }
  }

  void _showRingScreen(ReminderAlert alert, {required bool launchedByAlert}) {
    final navigator = appNavigatorKey.currentState;
    if (navigator == null || _ringingId == alert.id) return;
    _ringingId = alert.id;
    final settings = ref.read(reminderSettingsProvider);
    final service = ref.read(reminderServiceProvider);
    final platform = ref.read(reminderPlatformProvider);
    navigator
        .push(MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => AlarmRingScreen(
            reminder: RingingReminder(
              notificationId: alert.id,
              type: alert.type,
              title: alert.title,
              start: alert.start,
              end: alert.end,
              allDay: alert.allDay,
              location: alert.location,
              eventId: alert.eventId,
            ),
            snoozeMinutes: settings.snoozeMinutes,
            autoStop: Duration(minutes: settings.autoStopMinutes),
            onStop: () => service.stop(alert),
            onSnooze: () => service.snooze(alert),
            onOpenEvent: alert.eventId == 'test' ? null : () => _openEvent(alert),
            isStillRinging:
                alert.type == ReminderType.alarm ? () => platform.isRinging(alert.id) : null,
            onShown: platform.enterRing,
          ),
        ))
        .then((result) {
      _ringingId = null;
      // Back to the lock screen / previous app, unless the user went on to
      // the event.
      platform.leaveRing(background: launchedByAlert && result != AlarmRingScreen.openedEvent);
    });
  }

  Future<void> _openEvent(ReminderAlert alert) async {
    final event = await ref.read(repositoryProvider).getEvent(alert.eventId);
    final navigator = appNavigatorKey.currentState;
    if (event == null || navigator == null) return;
    final calendar = (await ref.read(calendarsProvider.future)).where((c) => c.id == event.calendarId).firstOrNull;
    final occurrence = EventOccurrence(
      event: event,
      start: alert.start,
      end: alert.end,
      color: event.color ?? calendar?.color ?? Colors.blue,
    );
    navigator.push(MaterialPageRoute<void>(builder: (_) => EventDetailsScreen(occurrence: occurrence)));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final name = AppLocalizations.of(context).myCalendar;
    // Any change to events, calendars or reminder settings reschedules alerts.
    ref.listenManual(dataRevisionProvider, (_, _) => _scheduleReminders());
    ref.listenManual(reminderSettingsProvider, (_, _) => _scheduleReminders());
    Future(() async {
      await ref.read(syncServiceProvider).ensureLocalCalendar(name);
      ref.read(dataRevisionProvider.notifier).bump();
      await _startReminders();
      if (widget.syncOnStart) {
        await ref.read(syncControllerProvider.notifier).syncAll();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh remote calendars when the app comes back to the foreground.
    if (state == AppLifecycleState.paused) _foregroundRing?.cancel();
    if (state == AppLifecycleState.resumed) {
      _scheduleReminders();
      if (widget.syncOnStart) ref.read(syncControllerProvider.notifier).syncAll();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
