import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'app.dart';
import 'data/db/sqlite_calendar_repository.dart';
import 'data/reminders/notifications_reminder_platform.dart';
import 'state/reminder_providers.dart';
import 'state/providers.dart';
import 'state/settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  tzdata.initializeTimeZones();
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    // Unknown zone: tz.local stays UTC, recurrences fall back to UTC.
  }

  final prefs = await SharedPreferences.getInstance();
  final repository = await SqliteCalendarRepository.open();

  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      repositoryProvider.overrideWithValue(repository),
      reminderPlatformProvider.overrideWithValue(NotificationsReminderPlatform()),
    ],
    child: const TimefixApp(),
  ));
}
