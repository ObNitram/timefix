import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/reminders/reminder_platform.dart';
import '../../domain/reminders.dart';
import '../../state/reminder_providers.dart';
import '../format.dart';
import '../reminders/reminder_format.dart';
import '../reminders/reminder_permissions.dart';
import '../widgets/common.dart';

/// Permission status (with buttons to grant them) and test alerts.
class ReminderPermissionsSection extends ConsumerStatefulWidget {
  const ReminderPermissionsSection({super.key});

  @override
  ConsumerState<ReminderPermissionsSection> createState() => _ReminderPermissionsSectionState();
}

class _ReminderPermissionsSectionState extends ConsumerState<ReminderPermissionsSection>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may come back from the system settings.
    if (state == AppLifecycleState.resumed) ref.invalidate(reminderPermissionsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final permissions = ref.watch(reminderPermissionsProvider).value ?? const {};

    String label(ReminderPermission p) => switch (p) {
          ReminderPermission.notifications => l10n.permissionNotifications,
          ReminderPermission.exactAlarms => l10n.permissionExactAlarms,
          ReminderPermission.fullScreen => l10n.permissionFullScreen,
          ReminderPermission.alarmKit => l10n.permissionAlarmKit,
        };

    final rows = [
      for (final p in ReminderPermission.values)
        if (permissions[p] case final state? when state != PermissionState.unsupported)
          ListTile(
            leading: Icon(
              state == PermissionState.granted ? Icons.check_circle : Icons.error_outline,
              color: state == PermissionState.granted ? Colors.green : scheme.error,
            ),
            title: Text(label(p)),
            subtitle: Text(state == PermissionState.granted ? l10n.permissionGranted : l10n.permissionDenied),
            trailing: state == PermissionState.granted
                ? null
                : TextButton(
                    onPressed: () async {
                      await ref.read(reminderPlatformProvider).request(p);
                      ref.invalidate(reminderPermissionsProvider);
                      await ref.read(reminderServiceProvider).rescheduleAll();
                    },
                    child: Text(l10n.grant),
                  ),
          ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (rows.isNotEmpty) ...[
          _header(context, l10n.permissions),
          ...rows,
          const Divider(),
        ],
        _header(context, l10n.testSection),
        for (final type in ReminderType.values)
          ListTile(
            leading: Icon(reminderTypeIcon(type)),
            title: Text(switch (type) {
              ReminderType.push => l10n.testPush,
              ReminderType.fullScreen => l10n.testFullScreen,
              ReminderType.alarm => l10n.testAlarm,
            }),
            onTap: () => runGuarded(context, () async {
              await ensureReminderPermissions(context, ref, [Reminder(0, type)]);
              await ref.read(reminderServiceProvider).scheduleTest(type);
              if (context.mounted) showSnack(context, l10n.testScheduled);
            }),
          ),
      ],
    );
  }

  Widget _header(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
      );
}
