import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/reminder_settings.dart';
import '../domain/reminders.dart';
import 'settings.dart';

export '../domain/reminder_settings.dart';

class ReminderSettingsNotifier extends Notifier<ReminderSettings> {
  static const _key = 'reminderSettings';

  @override
  ReminderSettings build() =>
      ReminderSettings.fromJson(ref.watch(sharedPreferencesProvider).getString(_key));

  void _save(ReminderSettings s) {
    ref.read(sharedPreferencesProvider).setString(_key, jsonEncode(s.toJson()));
    state = s;
  }

  void savePreset(ReminderPreset preset) {
    final list = [...state.presets];
    final i = list.indexWhere((p) => p.id == preset.id);
    if (i >= 0) {
      list[i] = preset;
    } else {
      list.add(preset);
    }
    _save(state.copyWith(presets: list));
  }

  void deletePreset(String id) =>
      _save(state.copyWith(presets: state.presets.where((p) => p.id != id).toList()));

  void setDefaults({required bool allDay, required List<Reminder> reminders}) => _save(allDay
      ? state.copyWith(defaultAllDay: Reminder.normalize(reminders))
      : state.copyWith(defaultTimed: Reminder.normalize(reminders)));

  void setSnoozeMinutes(int v) => _save(state.copyWith(snoozeMinutes: v));
  void setAutoStopMinutes(int v) => _save(state.copyWith(autoStopMinutes: v));
  void setVibrate(bool v) => _save(state.copyWith(vibrate: v));
  void setAlarmSound(String v) => _save(state.copyWith(alarmSound: v));
}

final reminderSettingsProvider =
    NotifierProvider<ReminderSettingsNotifier, ReminderSettings>(ReminderSettingsNotifier.new);
