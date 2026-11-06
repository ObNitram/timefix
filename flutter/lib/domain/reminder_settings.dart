import 'dart:convert';

import 'reminders.dart';

/// Alarm sounds bundled with the app (`assets/sounds/<id>.mp3` on Android,
/// `<id>.caf` in the iOS bundle). "system" uses the device alarm sound.
const alarmSoundIds = ['system', 'classic', 'digital', 'gentle'];

class ReminderSettings {
  const ReminderSettings({
    required this.presets,
    required this.defaultTimed,
    required this.defaultAllDay,
    this.snoozeMinutes = 10,
    this.autoStopMinutes = 5,
    this.vibrate = true,
    this.alarmSound = 'system',
  });

  /// User presets offered in the editor (in addition to the built-in delays).
  final List<ReminderPreset> presets;

  /// Reminders added to new events.
  final List<Reminder> defaultTimed;
  final List<Reminder> defaultAllDay;

  /// Alarm behaviour.
  final int snoozeMinutes;
  final int autoStopMinutes;
  final bool vibrate;
  final String alarmSound;

  static const defaults = ReminderSettings(
    presets: [
      ReminderPreset(id: 'preset-alarm-1h', reminder: Reminder(60, ReminderType.alarm)),
      ReminderPreset(id: 'preset-fullscreen-15', reminder: Reminder(15, ReminderType.fullScreen)),
      ReminderPreset(
        id: 'preset-allday-eve',
        allDay: true,
        reminder: Reminder((24 - 18) * 60, ReminderType.push), // the day before at 18:00
      ),
    ],
    defaultTimed: [Reminder(10, ReminderType.push)],
    defaultAllDay: [],
  );

  List<Reminder> defaultsFor({required bool allDay}) => allDay ? defaultAllDay : defaultTimed;

  ReminderSettings copyWith({
    List<ReminderPreset>? presets,
    List<Reminder>? defaultTimed,
    List<Reminder>? defaultAllDay,
    int? snoozeMinutes,
    int? autoStopMinutes,
    bool? vibrate,
    String? alarmSound,
  }) =>
      ReminderSettings(
        presets: presets ?? this.presets,
        defaultTimed: defaultTimed ?? this.defaultTimed,
        defaultAllDay: defaultAllDay ?? this.defaultAllDay,
        snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
        autoStopMinutes: autoStopMinutes ?? this.autoStopMinutes,
        vibrate: vibrate ?? this.vibrate,
        alarmSound: alarmSound ?? this.alarmSound,
      );

  Map<String, Object> toJson() => {
        'presets': jsonDecode(ReminderPreset.encodeList(presets)) as Object,
        'defaultTimed': jsonDecode(Reminder.encodeList(defaultTimed)) as Object,
        'defaultAllDay': jsonDecode(Reminder.encodeList(defaultAllDay)) as Object,
        'snoozeMinutes': snoozeMinutes,
        'autoStopMinutes': autoStopMinutes,
        'vibrate': vibrate,
        'alarmSound': alarmSound,
      };

  static ReminderSettings fromJson(String? json) {
    if (json == null) return defaults;
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return ReminderSettings(
        presets: ReminderPreset.decodeList(jsonEncode(m['presets'])) ?? defaults.presets,
        defaultTimed: Reminder.decodeList(jsonEncode(m['defaultTimed'])),
        defaultAllDay: Reminder.decodeList(jsonEncode(m['defaultAllDay'])),
        snoozeMinutes: (m['snoozeMinutes'] as num?)?.toInt() ?? 10,
        autoStopMinutes: (m['autoStopMinutes'] as num?)?.toInt() ?? 5,
        vibrate: m['vibrate'] as bool? ?? true,
        alarmSound: alarmSoundIds.contains(m['alarmSound']) ? m['alarmSound'] as String : 'system',
      );
    } catch (_) {
      return defaults;
    }
  }
}

