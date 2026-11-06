import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reminders/reminder_platform.dart';
import '../../domain/reminders.dart';
import '../../state/reminder_providers.dart';
import '../format.dart';

/// Asks for the permissions [reminders] need, right after the user created
/// them (the system dialogs then make sense). Denied permissions that can
/// only be granted in the system settings are offered through a snackbar.
Future<void> ensureReminderPermissions(
    BuildContext context, WidgetRef ref, Iterable<Reminder> reminders) async {
  final types = reminders.map((r) => r.type).toSet();
  if (types.isEmpty) return;
  final platform = ref.read(reminderPlatformProvider);
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.maybeOf(context);
  var changed = false;

  try {
    var perms = await platform.permissions();
    bool denied(ReminderPermission p) => perms[p] == PermissionState.denied;

    if (denied(ReminderPermission.notifications)) {
      await platform.request(ReminderPermission.notifications);
      changed = true;
      perms = await platform.permissions();
    }
    if (types.contains(ReminderType.alarm) && denied(ReminderPermission.alarmKit)) {
      // iOS 26: the system prompt only appears the first time.
      await platform.request(ReminderPermission.alarmKit);
      changed = true;
      perms = await platform.permissions();
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
          onPressed: () async {
            await platform.request(permission);
            ref.invalidate(reminderPermissionsProvider);
            await ref.read(reminderServiceProvider).rescheduleAll();
          },
        ),
      ));
    }
  } finally {
    if (changed) {
      ref.invalidate(reminderPermissionsProvider);
      await ref.read(reminderServiceProvider).rescheduleAll();
    }
  }
}
