import 'dart:async';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reminders/reminder_platform.dart';
import '../../domain/reminders.dart';
import '../../state/reminder_providers.dart';
import '../../state/settings.dart';
import '../format.dart';

/// Asks for the permissions [reminders] need, right after the user created
/// them (the system dialogs then make sense). Each system dialog is shown at
/// most once: afterwards, a denied permission is only pointed out by a
/// snackbar whose "Grant" action opens the system settings.
Future<void> ensureReminderPermissions(
    BuildContext context, Iterable<Reminder> reminders) async {
  final types = reminders.map((r) => r.type).toSet();
  if (types.isEmpty) return;
  // The snackbar outlives the screen that called this (the editor closes).
  final container = ProviderScope.containerOf(context, listen: false);
  final platform = container.read(reminderPlatformProvider);
  final prefs = container.read(sharedPreferencesProvider);
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);

  final before = await platform.permissions();
  var perms = before;
  bool denied(ReminderPermission p) => perms[p] == PermissionState.denied;

  Future<void> askOnce(ReminderPermission p) async {
    final key = '$_askedKeyPrefix${p.name}';
    if (!denied(p) || (prefs.getBool(key) ?? false)) return;
    await prefs.setBool(key, true);
    await platform.request(p);
    perms = await platform.permissions();
  }

  await askOnce(ReminderPermission.notifications);
  // iOS 26: alarms go through AlarmKit when it is allowed.
  if (types.contains(ReminderType.alarm)) await askOnce(ReminderPermission.alarmKit);

  if (!mapEquals(before, perms)) {
    container.invalidate(reminderPermissionsProvider);
    // A permission change reschedules every alert (see ReminderService).
    unawaited(container.read(reminderServiceProvider).reschedule());
  }

  String? hint;
  ReminderPermission? fix;
  if (denied(ReminderPermission.notifications)) {
    hint = l10n.notificationPermissionHint;
    fix = ReminderPermission.notifications;
  } else if (types.any((t) => t != ReminderType.push) && denied(ReminderPermission.fullScreen)) {
    hint = l10n.fullScreenPermissionHint;
    fix = ReminderPermission.fullScreen;
  } else if (denied(ReminderPermission.exactAlarms)) {
    hint = l10n.permissionExactAlarms;
    fix = ReminderPermission.exactAlarms;
  }
  if (hint != null && fix != null && messenger != null) {
    final permission = fix;
    messenger.showSnackBar(SnackBar(
      content: Text(hint),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: l10n.grant,
        onPressed: () => grantReminderPermission(container, permission),
      ),
    ));
  }
}

const _askedKeyPrefix = 'reminderPermissionAsked.';

/// "Grant" tapped for [permission]: system dialog, or the system settings
/// once the dialog can no longer be shown. Alerts are rescheduled when the
/// app comes back with the new permission.
Future<void> grantReminderPermission(ProviderContainer container, ReminderPermission permission) async {
  await container.read(reminderPlatformProvider).request(permission, openSettingsIfDenied: true);
  container.invalidate(reminderPermissionsProvider);
  await container.read(reminderServiceProvider).reschedule();
}
