import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/reminders/reminder_platform.dart';
import '../data/reminders/reminder_service.dart';
import 'providers.dart';
import 'reminder_settings.dart';
import 'settings.dart';

/// Device notification system (overridden in main() with the real one).
final reminderPlatformProvider = Provider<ReminderPlatform>((ref) => FakeReminderPlatform());

final reminderServiceProvider = Provider<ReminderService>((ref) => ReminderService(
      platform: ref.watch(reminderPlatformProvider),
      repository: ref.watch(repositoryProvider),
      prefs: ref.watch(sharedPreferencesProvider),
      settings: () => ref.read(reminderSettingsProvider),
    ));

/// Permission states, refreshed with `ref.invalidate`.
final reminderPermissionsProvider =
    FutureProvider<Map<ReminderPermission, PermissionState>>((ref) {
  return ref.watch(reminderPlatformProvider).permissions();
}, isAutoDispose: true);
