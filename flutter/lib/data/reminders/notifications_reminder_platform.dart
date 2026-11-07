import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alarm_kit/alarm_kit.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:uuid/uuid.dart';

import '../../domain/reminder_planner.dart' show stableNotificationId;
import '../../domain/reminders.dart';
import 'reminder_platform.dart';

/// Android `Notification.FLAG_INSISTENT`: the sound repeats until the
/// notification is cancelled.
const _flagInsistent = 4;
const _ringPrefix = 'ring:';
const _plainPrefix = 'rem:';
const _actionStop = 'stop';
const _actionSnooze = 'snooze';
const _iosAlarmCategory = 'timefix_alarm';

/// AlarmKit snooze needs a widget extension (countdown presentation) that
/// must be created in Xcode. Set to true once it exists (see README).
const alarmKitSnoozeEnabled = false;

/// Reminders through the system notification service
/// (flutter_local_notifications), and Apple AlarmKit for alarms on iOS 26+.
///
/// * push: standard notification;
/// * full screen: Android full-screen intent, iOS Time Sensitive notification;
/// * alarm: Android exact alarm with a looping alarm sound (FLAG_INSISTENT)
///   on a dedicated channel, auto-stopped by `timeoutAfter`; iOS 26+ AlarmKit
///   alarm, older iOS a Time Sensitive notification.
///
/// Times are sent in UTC: a local wall time is ambiguous during the hour
/// repeated when DST ends.
class NotificationsReminderPlatform implements ReminderPlatform {
  NotificationsReminderPlatform();

  final _fln = FlutterLocalNotificationsPlugin();
  static const _channel = MethodChannel('timefix/reminders');
  bool? _alarmKitUsable;

  bool get _isIos => Platform.isIOS;
  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _fln.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  IOSFlutterLocalNotificationsPlugin? get _ios =>
      _fln.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

  @override
  int get maxPending => _isIos ? 60 : 400;

  @override
  Duration get planningHorizon => _isIos ? const Duration(days: 21) : const Duration(days: 35);

  @override
  Future<void> initialize({
    required ReminderTexts texts,
    required void Function(ReminderResponse response) onResponse,
  }) async {
    await _fln.initialize(
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_reminder'),
        iOS: DarwinInitializationSettings(
          // Permissions are asked when the first reminder is created.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          notificationCategories: [
            DarwinNotificationCategory(_iosAlarmCategory, actions: [
              DarwinNotificationAction.plain(_actionStop, texts.stop,
                  options: {DarwinNotificationActionOption.destructive}),
              DarwinNotificationAction.plain(_actionSnooze, texts.snooze),
            ]),
          ],
        ),
      ),
      onDidReceiveNotificationResponse: (r) {
        final response = _toResponse(r);
        if (response != null) onResponse(response);
      },
      onDidReceiveBackgroundNotificationResponse: reminderNotificationBackgroundHandler,
    );
    if (_isIos) await _installIosSounds();
  }

  @override
  Future<ReminderResponse?> takeLaunchResponse() async {
    final details = await _fln.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    final r = details.notificationResponse;
    return r == null ? null : _toResponse(r);
  }

  static ReminderResponse? _toResponse(NotificationResponse r) {
    final decoded = _decodePayload(r.payload);
    if (decoded == null) return null;
    final action = switch (r.actionId) {
      _actionStop => ReminderAction.stop,
      _actionSnooze => ReminderAction.snooze,
      _ => ReminderAction.open,
    };
    return ReminderResponse(decoded.alert, action);
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  @override
  Future<void> schedule(ReminderAlert alert, AlarmOptions options) async {
    if (!alert.fireAt.isAfter(DateTime.now())) return;
    if (_isIos && alert.type == ReminderType.alarm) {
      if (await _scheduleAlarmKit(alert, options)) {
        await _fln.cancel(id: alert.id); // no leftover notification fallback
        return;
      }
      await _cancelAlarmKit(alert.id);
    }
    await _zonedSchedule(_fln, alert, options, tz.TZDateTime.from(alert.fireAt, tz.UTC));
  }

  /// Shared with the background isolate (snooze from the notification).
  static Future<void> _zonedSchedule(FlutterLocalNotificationsPlugin fln, ReminderAlert alert,
      AlarmOptions options, tz.TZDateTime when) async {
    Future<void> run(AndroidScheduleMode mode) => fln.zonedSchedule(
          id: alert.id,
          scheduledDate: when,
          title: alert.title,
          body: alert.body,
          payload: _encodePayload(alert, options),
          notificationDetails: _details(alert.type, options),
          androidScheduleMode: mode,
        );
    try {
      // Not `alarmClock`: the plugin registers its delivery broadcast as the
      // alarm's "show" intent, so tapping the next-alarm chip of the system
      // UI would ring it at once (and drop it from the reboot cache).
      await run(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      // Exact alarms not allowed: deliver anyway, possibly a few minutes late.
      if (e.code != 'exact_alarms_not_permitted') rethrow;
      await run(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  static NotificationDetails _details(ReminderType type, AlarmOptions o) {
    switch (type) {
      case ReminderType.push:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            'timefix_reminders_v1',
            o.channelPushName,
            channelDescription: o.channelPushDescription,
            icon: 'ic_stat_reminder',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.active,
          ),
        );
      case ReminderType.fullScreen:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            'timefix_ring_fullscreen_v1',
            o.channelFullScreenName,
            channelDescription: o.channelFullScreenDescription,
            icon: 'ic_stat_reminder',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.event,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            timeoutAfter: o.autoStop.inMilliseconds,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        );
      case ReminderType.alarm:
        return NotificationDetails(
          android: AndroidNotificationDetails(
            // Sound, usage and vibration are frozen when a channel is created:
            // one channel per sound / vibration setting.
            'timefix_ring_alarm_${o.sound}_${o.vibrate ? 'vib' : 'novib'}_v1',
            o.soundLabel.isEmpty ? o.channelAlarmName : '${o.channelAlarmName} – ${o.soundLabel}',
            channelDescription: o.channelAlarmDescription,
            icon: 'ic_stat_reminder',
            importance: Importance.max,
            priority: Priority.max,
            category: AndroidNotificationCategory.alarm,
            fullScreenIntent: true,
            visibility: NotificationVisibility.public,
            playSound: true,
            sound: o.sound == 'system'
                // Settings.System.DEFAULT_ALARM_ALERT_URI (null would be the
                // notification sound).
                ? const UriAndroidNotificationSound('content://settings/system/alarm_alert')
                : RawResourceAndroidNotificationSound('timefix_alarm_${o.sound}'),
            audioAttributesUsage: AudioAttributesUsage.alarm,
            enableVibration: o.vibrate,
            vibrationPattern: o.vibrate ? Int64List.fromList([0, 1000, 800, 1000]) : null,
            additionalFlags: Int32List.fromList([_flagInsistent]),
            ongoing: true,
            autoCancel: false,
            timeoutAfter: o.autoStop.inMilliseconds,
            actions: [
              AndroidNotificationAction(_actionStop, o.stopLabel, cancelNotification: true),
              AndroidNotificationAction(_actionSnooze, o.snoozeLabel, cancelNotification: true),
            ],
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBanner: true,
            presentList: true,
            presentSound: true,
            // Notifications cannot use the iOS alarm tone: "system" gets the
            // classic bundled ringtone (28 s) instead of the short ding.
            sound: 'timefix_alarm_${o.sound == 'system' ? 'classic' : o.sound}.caf',
            interruptionLevel: InterruptionLevel.timeSensitive,
            categoryIdentifier: _iosAlarmCategory,
          ),
        );
    }
  }

  // ---------------------------------------------------------------------------
  // AlarmKit (iOS 26+)
  // ---------------------------------------------------------------------------

  static String _alarmKitId(int id) => const Uuid().v5(Namespace.url.value, 'timefix:alarm:$id');

  /// Cached for a run of scheduling; refreshed by [permissions], which the
  /// reminder service calls at the start of every run.
  Future<bool> _alarmKitReady() async {
    if (_alarmKitUsable != null) return _alarmKitUsable!;
    try {
      _alarmKitUsable = await AlarmKit.instance.isSupported() &&
          await AlarmKit.instance.authorizationState() == AlarmAuthorization.authorized;
    } catch (_) {
      _alarmKitUsable = false;
    }
    return _alarmKitUsable!;
  }

  /// Returns false when AlarmKit cannot be used (the caller falls back to a
  /// Time Sensitive notification).
  Future<bool> _scheduleAlarmKit(ReminderAlert alert, AlarmOptions o) async {
    if (!await _alarmKitReady()) return false;
    final id = _alarmKitId(alert.id);
    try {
      await _cancelAlarmKit(alert.id);
      await AlarmKit.instance.scheduleAlarm(
        id: id,
        schedule: AlarmSchedule.fixed(alert.fireAt),
        tint: const Color(0xFF1A73E8),
        sound: o.sound == 'system' ? null : 'timefix_alarm_${o.sound}.caf',
        postAlert: alarmKitSnoozeEnabled ? o.snooze : null,
        presentation: AlarmPresentation(
          alert: AlarmAlert(
            title: alert.title,
            stopButton: AlarmButton(text: o.stopLabel, systemImageName: 'stop.fill'),
            secondaryButton:
                alarmKitSnoozeEnabled ? AlarmButton(text: o.snoozeLabel, systemImageName: 'zzz') : null,
            secondaryBehavior: alarmKitSnoozeEnabled ? AlarmSecondaryBehavior.countdown : null,
          ),
          countdown: alarmKitSnoozeEnabled ? AlarmCountdown(title: alert.title) : null,
        ),
      );
      return true;
    } on AlarmKitException {
      return false; // limit reached, not authorized…: use a notification
    }
  }

  Future<void> _cancelAlarmKit(int id) async {
    try {
      // Also when authorization was revoked: alarms already handed to
      // AlarmKit must not ring for deleted events.
      await AlarmKit.instance.cancel(_alarmKitId(id));
    } catch (_) {
      // Unknown id or unsupported.
    }
  }

  // ---------------------------------------------------------------------------
  // Cancel / stop
  // ---------------------------------------------------------------------------

  Future<bool> _alarmKitSupported() async {
    try {
      return await AlarmKit.instance.isSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    final alarmKit = _isIos && await _alarmKitSupported();
    for (final id in ids) {
      await _fln.cancel(id: id);
      if (alarmKit) await _cancelAlarmKit(id);
    }
  }

  @override
  Future<void> stop(int id) async {
    // Cancelling the notification stops the looping sound on Android.
    await _fln.cancel(id: id);
    if (_isIos && await _alarmKitSupported()) {
      try {
        await AlarmKit.instance.stop(_alarmKitId(id));
      } catch (_) {}
    }
  }

  @override
  Future<bool?> isRinging(int id) async {
    try {
      if (_isIos && await _alarmKitReady()) {
        final alarm = (await AlarmKit.instance.alarms())
            .where((a) => a.id.toLowerCase() == _alarmKitId(id))
            .firstOrNull;
        if (alarm != null) return alarm.state == AlarmState.alerting;
      }
      final active = await _fln.getActiveNotifications();
      return active.any((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> enterRing() => _invoke('enterRing');

  @override
  Future<void> leaveRing({required bool background}) => _invoke('leaveRing', {'background': background});

  Future<void> _invoke(String method, [Object? args]) async {
    if (_isIos) return;
    try {
      await _channel.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // Not running in the app's activity.
    }
  }

  // ---------------------------------------------------------------------------
  // Permissions
  // ---------------------------------------------------------------------------

  @override
  Future<Map<ReminderPermission, PermissionState>> permissions() async {
    PermissionState of(bool? granted) =>
        granted == true ? PermissionState.granted : PermissionState.denied;
    final result = {for (final p in ReminderPermission.values) p: PermissionState.unsupported};
    if (_isIos) {
      final perms = await _ios?.checkPermissions();
      result[ReminderPermission.notifications] = of(perms?.isEnabled);
      _alarmKitUsable = false;
      try {
        if (await AlarmKit.instance.isSupported()) {
          final state = await AlarmKit.instance.authorizationState();
          _alarmKitUsable = state == AlarmAuthorization.authorized;
          result[ReminderPermission.alarmKit] = of(_alarmKitUsable);
        }
      } catch (_) {}
      return result;
    }
    final android = _android;
    if (android == null) return result;
    result[ReminderPermission.notifications] = of(await android.areNotificationsEnabled());
    result[ReminderPermission.exactAlarms] = of(await android.canScheduleExactNotifications());
    try {
      result[ReminderPermission.fullScreen] =
          of(await _channel.invokeMethod<bool>('canUseFullScreenIntent'));
    } on MissingPluginException {
      // Leave unsupported.
    }
    return result;
  }

  @override
  Future<void> request(ReminderPermission permission) async {
    switch (permission) {
      case ReminderPermission.notifications:
        final granted = _isIos
            ? await _ios?.requestPermissions(alert: true, badge: true, sound: true)
            : await _android?.requestNotificationsPermission();
        // Already refused: the system shows no dialog any more.
        if (granted != true) await _fln.openAppNotificationSettings();
      case ReminderPermission.exactAlarms:
        await _android?.requestExactAlarmsPermission();
      case ReminderPermission.fullScreen:
        await _android?.requestFullScreenIntentPermission();
      case ReminderPermission.alarmKit:
        try {
          final state = await AlarmKit.instance.authorizationState();
          if (state == AlarmAuthorization.notDetermined) {
            await AlarmKit.instance.requestAuthorization();
          } else if (state == AlarmAuthorization.denied) {
            // The "Alarms" switch is in the app's page of the Settings app.
            await _fln.openAppNotificationSettings();
          }
        } catch (_) {}
        _alarmKitUsable = null;
    }
  }

  // ---------------------------------------------------------------------------
  // iOS sounds: notification sounds are looked up in Library/Sounds.
  // ---------------------------------------------------------------------------

  static Future<void> _installIosSounds() async {
    try {
      final dir = Directory('${(await getLibraryDirectory()).path}/Sounds');
      await dir.create(recursive: true);
      for (final name in const ['classic', 'digital', 'gentle']) {
        final data = await rootBundle.load('assets/sounds/timefix_alarm_$name.caf');
        final file = File('${dir.path}/timefix_alarm_$name.caf');
        if (await file.exists() && await file.length() == data.lengthInBytes) continue;
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
    } catch (_) {
      // The default sound is used instead.
    }
  }
}

// -----------------------------------------------------------------------------
// Payload: the alert and its options, so that a notification can reschedule
// itself (snooze) from the background isolate without the app's database.
// -----------------------------------------------------------------------------

@visibleForTesting
String encodeReminderPayload(ReminderAlert alert, AlarmOptions options) =>
    _encodePayload(alert, options);

@visibleForTesting
({ReminderAlert alert, AlarmOptions options})? decodeReminderPayload(String? payload) =>
    _decodePayload(payload);

String _encodePayload(ReminderAlert alert, AlarmOptions options) {
  final prefix = alert.type == ReminderType.push ? _plainPrefix : _ringPrefix;
  return '$prefix${jsonEncode({'a': jsonDecode(alert.toPayload()), 'o': options.toJson()})}';
}

({ReminderAlert alert, AlarmOptions options})? _decodePayload(String? payload) {
  if (payload == null) return null;
  String json;
  if (payload.startsWith(_ringPrefix)) {
    json = payload.substring(_ringPrefix.length);
  } else if (payload.startsWith(_plainPrefix)) {
    json = payload.substring(_plainPrefix.length);
  } else {
    return null;
  }
  try {
    final m = jsonDecode(json) as Map<String, dynamic>;
    final alert = ReminderAlert.fromPayload(jsonEncode(m['a']));
    if (alert == null) return null;
    return (alert: alert, options: AlarmOptions.fromJson(m['o'] as Map<String, dynamic>));
  } catch (_) {
    return null;
  }
}

/// "Snooze" / "Stop" tapped on a notification while the app is not running.
/// Runs in a separate isolate: no database, no time zone database (UTC is
/// enough to compute "now + snooze").
@pragma('vm:entry-point')
Future<void> reminderNotificationBackgroundHandler(NotificationResponse response) async {
  if (response.actionId != _actionSnooze) return; // Stop: already cancelled natively
  final decoded = _decodePayload(response.payload);
  if (decoded == null) return;
  final at = tz.TZDateTime.now(tz.UTC).add(decoded.options.snooze);
  final snoozed = decoded.alert.copyWith(
    id: stableNotificationId('snooze:${decoded.alert.id}'),
    fireAt: at,
  );
  await NotificationsReminderPlatform._zonedSchedule(
      FlutterLocalNotificationsPlugin(), snoozed, decoded.options, at);
}
