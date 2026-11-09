import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The three main views (same as Google Calendar).
enum CalendarViewMode { schedule, week, month }

class AppSettings {
  const AppSettings({
    this.firstWeekday,
    this.themeMode = ThemeMode.system,
    this.defaultDurationMinutes = 60,
    this.viewMode = CalendarViewMode.schedule,
    this.hourHeight = 52,
  });

  /// [DateTime.monday]..[DateTime.sunday], or null to follow the locale.
  final int? firstWeekday;
  final ThemeMode themeMode;
  final int defaultDurationMinutes;
  final CalendarViewMode viewMode;

  /// Height of one hour in the week view (pinch to zoom).
  final double hourHeight;

  AppSettings copyWith({
    int? firstWeekday,
    bool clearFirstWeekday = false,
    ThemeMode? themeMode,
    int? defaultDurationMinutes,
    CalendarViewMode? viewMode,
    double? hourHeight,
  }) =>
      AppSettings(
        firstWeekday: clearFirstWeekday ? null : (firstWeekday ?? this.firstWeekday),
        themeMode: themeMode ?? this.themeMode,
        defaultDurationMinutes: defaultDurationMinutes ?? this.defaultDurationMinutes,
        viewMode: viewMode ?? this.viewMode,
        hourHeight: hourHeight ?? this.hourHeight,
      );
}

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden in main()'),
);

class SettingsNotifier extends Notifier<AppSettings> {
  static const _kFirstWeekday = 'firstWeekday';
  static const _kTheme = 'themeMode';
  static const _kDuration = 'defaultDuration';
  static const _kView = 'viewMode';
  static const _kHourHeight = 'hourHeight';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  AppSettings build() {
    final p = ref.watch(sharedPreferencesProvider);
    return AppSettings(
      firstWeekday: p.getInt(_kFirstWeekday),
      themeMode: ThemeMode.values.elementAtOrNull(p.getInt(_kTheme) ?? 0) ??
          ThemeMode.system,
      defaultDurationMinutes: p.getInt(_kDuration) ?? 60,
      viewMode: CalendarViewMode.values.elementAtOrNull(p.getInt(_kView) ?? 0) ??
          CalendarViewMode.schedule,
      hourHeight: p.getDouble(_kHourHeight) ?? 52,
    );
  }

  void setFirstWeekday(int? weekday) {
    if (weekday == null) {
      _prefs.remove(_kFirstWeekday);
      state = state.copyWith(clearFirstWeekday: true);
    } else {
      _prefs.setInt(_kFirstWeekday, weekday);
      state = state.copyWith(firstWeekday: weekday);
    }
  }

  void setThemeMode(ThemeMode mode) {
    _prefs.setInt(_kTheme, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  void setDefaultDuration(int minutes) {
    _prefs.setInt(_kDuration, minutes);
    state = state.copyWith(defaultDurationMinutes: minutes);
  }

  void setViewMode(CalendarViewMode mode) {
    _prefs.setInt(_kView, mode.index);
    state = state.copyWith(viewMode: mode);
  }

  void setHourHeight(double height) {
    _prefs.setDouble(_kHourHeight, height);
    state = state.copyWith(hourHeight: height);
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

/// Effective first day of the week ([DateTime.monday]..[DateTime.sunday]).
int resolveFirstWeekday(BuildContext context, AppSettings settings) {
  if (settings.firstWeekday != null) return settings.firstWeekday!;
  final idx = MaterialLocalizations.of(context).firstDayOfWeekIndex; // 0 = Sunday
  return idx == 0 ? DateTime.sunday : idx;
}
