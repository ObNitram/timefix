import 'dart:convert';

import '../../domain/reminders.dart';

/// Permissions that affect reminders.
enum ReminderPermission {
  /// Show notifications (Android 13+, iOS).
  notifications,

  /// Fire at the exact minute (Android 12+ "Alarms & reminders").
  exactAlarms,

  /// Full-screen notifications over the lock screen (Android 14+).
  fullScreen,

  /// Apple AlarmKit (iOS 26+).
  alarmKit,
}

enum PermissionState { granted, denied, unsupported }

/// Behaviour of alarms, from the settings.
class AlarmOptions {
  const AlarmOptions({
    required this.sound,
    required this.vibrate,
    required this.autoStop,
    required this.snooze,
    this.stopLabel = 'Stop',
    this.snoozeLabel = 'Snooze',
    this.dismissLabel = 'Dismiss',
    this.soundLabel = '',
    this.channelPushName = 'Reminders',
    this.channelPushDescription = '',
    this.channelFullScreenName = 'Full-screen reminders',
    this.channelFullScreenDescription = '',
    this.channelAlarmName = 'Alarms',
    this.channelAlarmDescription = '',
  });

  final String sound;
  final bool vibrate;
  final Duration autoStop;
  final Duration snooze;

  /// Localized action buttons.
  final String stopLabel;
  final String snoozeLabel;
  final String dismissLabel;

  /// Name of the sound (Android channel name).
  final String soundLabel;

  /// Localized Android notification channels.
  final String channelPushName;
  final String channelPushDescription;
  final String channelFullScreenName;
  final String channelFullScreenDescription;
  final String channelAlarmName;
  final String channelAlarmDescription;

  Map<String, Object> toJson() => {
        'sound': sound,
        'vib': vibrate,
        'auto': autoStop.inMinutes,
        'snooze': snooze.inMinutes,
        'stopL': stopLabel,
        'snoozeL': snoozeLabel,
        'dismissL': dismissLabel,
        'soundL': soundLabel,
        'ch': [
          channelPushName,
          channelPushDescription,
          channelFullScreenName,
          channelFullScreenDescription,
          channelAlarmName,
          channelAlarmDescription,
        ],
      };

  static AlarmOptions fromJson(Map<String, dynamic> m) {
    final ch = (m['ch'] as List?)?.cast<String>() ?? const [];
    String c(int i, String fallback) => i < ch.length ? ch[i] : fallback;
    return AlarmOptions(
        sound: m['sound'] as String? ?? 'system',
        vibrate: m['vib'] as bool? ?? true,
        autoStop: Duration(minutes: (m['auto'] as num?)?.toInt() ?? 5),
        snooze: Duration(minutes: (m['snooze'] as num?)?.toInt() ?? 10),
        stopLabel: m['stopL'] as String? ?? 'Stop',
        snoozeLabel: m['snoozeL'] as String? ?? 'Snooze',
        dismissLabel: m['dismissL'] as String? ?? 'Dismiss',
        soundLabel: m['soundL'] as String? ?? '',
        channelPushName: c(0, 'Reminders'),
        channelPushDescription: c(1, ''),
        channelFullScreenName: c(2, 'Full-screen reminders'),
        channelFullScreenDescription: c(3, ''),
        channelAlarmName: c(4, 'Alarms'),
        channelAlarmDescription: c(5, ''),
      );
  }
}

/// Localized texts registered once at initialization (iOS notification
/// action buttons). Per-alert texts travel in [AlarmOptions].
class ReminderTexts {
  const ReminderTexts({required this.stop, required this.snooze});

  final String stop;
  final String snooze;
}

/// One alert to deliver at [fireAt].
class ReminderAlert {
  const ReminderAlert({
    required this.id,
    required this.type,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.eventId,
    required this.start,
    required this.end,
    this.allDay = false,
    this.location,
  });

  /// Positive 31-bit id (notification id, AlarmKit id derived from it).
  final int id;
  final ReminderType type;
  final DateTime fireAt;
  final String title;
  final String body;
  final String eventId;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;

  ReminderAlert copyWith({int? id, DateTime? fireAt, String? body}) => ReminderAlert(
        id: id ?? this.id,
        type: type,
        fireAt: fireAt ?? this.fireAt,
        title: title,
        body: body ?? this.body,
        eventId: eventId,
        start: start,
        end: end,
        allDay: allDay,
        location: location,
      );

  String toPayload() => jsonEncode({
        'id': id,
        't': type.name,
        'title': title,
        'body': body,
        'event': eventId,
        's': start.millisecondsSinceEpoch,
        'e': end.millisecondsSinceEpoch,
        'a': allDay,
        if (location != null) 'loc': location,
      });

  static ReminderAlert? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      return ReminderAlert(
        id: (m['id'] as num).toInt(),
        type: ReminderType.fromName(m['t'] as String?),
        fireAt: DateTime.now(),
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        eventId: m['event'] as String? ?? '',
        start: DateTime.fromMillisecondsSinceEpoch((m['s'] as num).toInt()),
        end: DateTime.fromMillisecondsSinceEpoch((m['e'] as num).toInt()),
        allDay: m['a'] as bool? ?? false,
        location: m['loc'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}

/// What the user did with a delivered alert.
enum ReminderAction { open, stop, snooze }

class ReminderResponse {
  const ReminderResponse(this.alert, this.action);
  final ReminderAlert alert;
  final ReminderAction action;
}

/// Device notification / alarm system.
abstract class ReminderPlatform {
  /// How many alerts may be pending at once (iOS keeps only 64).
  int get maxPending;

  /// How far ahead alerts are scheduled.
  Duration get planningHorizon;

  Future<void> initialize({
    required ReminderTexts texts,
    required void Function(ReminderResponse response) onResponse,
  });

  /// The alert that launched the app (notification tap / full-screen intent).
  Future<ReminderResponse?> takeLaunchResponse();

  Future<void> schedule(ReminderAlert alert, AlarmOptions options);

  Future<void> cancel(Iterable<int> ids);

  /// Stops a ringing alarm / removes a delivered alert.
  Future<void> stop(int id);

  /// Whether the alarm [id] is ringing / its notification is displayed.
  /// Null when the platform cannot tell.
  Future<bool?> isRinging(int id);

  /// Whether the pending alerts [ids] are still scheduled on the device
  /// (alarms are dropped when the app is force-stopped). Null when the
  /// platform cannot tell.
  Future<bool?> areScheduled(List<int> ids);

  /// Snoozes made from a notification while the app was not running; each
  /// is returned once.
  Future<List<ReminderAlert>> takeBackgroundSnoozes();

  /// Called once the ringing screen is displayed: the app may then show over
  /// the lock screen (and only then).
  Future<void> enterRing();

  /// Called when the ringing screen closes: stop showing the app over the
  /// lock screen, and go back to the background if the alert opened the app.
  Future<void> leaveRing({required bool background});

  Future<Map<ReminderPermission, PermissionState>> permissions();

  /// Asks for a permission. Permissions without a system dialog open their
  /// system settings page; a refused one opens the app's settings only when
  /// [openSettingsIfDenied] (an explicit "Grant" tap).
  Future<void> request(ReminderPermission permission, {bool openSettingsIfDenied = false});
}

/// In-memory implementation (tests, unsupported platforms).
class FakeReminderPlatform implements ReminderPlatform {
  final Map<int, ReminderAlert> scheduled = {};
  final List<int> stopped = [];
  Map<ReminderPermission, PermissionState> granted = {
    for (final p in ReminderPermission.values) p: PermissionState.granted,
  };
  void Function(ReminderResponse)? _onResponse;
  ReminderResponse? launchResponse;

  @override
  int maxPending = 500;

  @override
  Duration planningHorizon = const Duration(days: 21);

  int enteredRing = 0;

  @override
  Future<void> enterRing() async => enteredRing++;

  @override
  Future<void> initialize({
    required ReminderTexts texts,
    required void Function(ReminderResponse response) onResponse,
  }) async =>
      _onResponse = onResponse;

  /// Simulates the user acting on a delivered alert.
  void respond(ReminderResponse response) => _onResponse?.call(response);

  @override
  Future<ReminderResponse?> takeLaunchResponse() async {
    final r = launchResponse;
    launchResponse = null;
    return r;
  }

  @override
  Future<void> schedule(ReminderAlert alert, AlarmOptions options) async => scheduled[alert.id] = alert;

  @override
  Future<void> cancel(Iterable<int> ids) async {
    for (final id in ids) {
      scheduled.remove(id);
    }
  }

  @override
  Future<void> stop(int id) async => stopped.add(id);

  @override
  Future<bool?> areScheduled(List<int> ids) async => ids.every(scheduled.containsKey);

  /// Snoozes "made from a notification".
  final List<ReminderAlert> backgroundSnoozes = [];

  @override
  Future<List<ReminderAlert>> takeBackgroundSnoozes() async {
    final taken = [...backgroundSnoozes];
    backgroundSnoozes.clear();
    return taken;
  }

  /// Ids currently "displayed" (null: the fake cannot tell).
  Set<int>? displayed;

  @override
  Future<bool?> isRinging(int id) async => displayed?.contains(id);

  int leftRing = 0;

  /// `background` of each [leaveRing] call.
  final List<bool> leftRingBackground = [];

  @override
  Future<void> leaveRing({required bool background}) async {
    leftRing++;
    leftRingBackground.add(background);
  }

  @override
  Future<Map<ReminderPermission, PermissionState>> permissions() async => Map.of(granted);

  /// Requests made, with their `openSettingsIfDenied` flag.
  final List<(ReminderPermission, bool)> requests = [];

  /// Whether a request grants the permission (the user taps "Allow").
  bool grantOnRequest = true;

  @override
  Future<void> request(ReminderPermission permission, {bool openSettingsIfDenied = false}) async {
    requests.add((permission, openSettingsIfDenied));
    if (grantOnRequest) granted[permission] = PermissionState.granted;
  }
}
