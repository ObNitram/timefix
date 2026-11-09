import 'package:flutter/material.dart';

import '../../domain/reminders.dart';
import '../format.dart';
import '../theme.dart';
import 'reminder_format.dart';
import 'reminder_picker.dart';

/// Editable list of reminders (event editor, event details, settings).
class ReminderListEditor extends StatelessWidget {
  const ReminderListEditor({
    super.key,
    required this.reminders,
    required this.allDay,
    required this.onChanged,
    this.readOnly = const [],
    this.leadingIcon = true,
    this.maxCount = 10,
  });

  final List<Reminder> reminders;

  /// Reminders shown but not removable (e.g. set on the server of a
  /// read-only calendar).
  final List<Reminder> readOnly;
  final bool allDay;
  final ValueChanged<List<Reminder>> onChanged;

  /// Show the bell icon in the left column (editor layout).
  final bool leadingIcon;
  final int maxCount;

  Future<void> _edit(BuildContext context, int? index) async {
    final r = await showReminderPicker(context,
        allDay: allDay, initial: index == null ? null : reminders[index]);
    if (r == null) return;
    final list = [...reminders];
    if (index == null) {
      list.add(r);
    } else {
      list[index] = r;
    }
    onChanged(Reminder.normalize(list));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final muted = Theme.of(context).colorScheme.mutedText;
    final rows = <Widget>[];

    Widget row({required Widget child, VoidCallback? onTap, Widget? trailing, bool first = false}) => InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 64,
                  child: first && leadingIcon ? Icon(Icons.notifications_outlined, color: muted) : null,
                ),
                Expanded(child: child),
                ?trailing,
                const SizedBox(width: 4),
              ],
            ),
          ),
        );

    Widget reminderText(Reminder r) => Row(
          children: [
            Icon(reminderTypeIcon(r.type), size: 20, color: muted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.reminderDelay(r.minutesBefore, allDay: allDay),
                      style: const TextStyle(fontSize: 16)),
                  Text(reminderTypeLabel(l10n, r.type), style: TextStyle(fontSize: 12, color: muted)),
                ],
              ),
            ),
          ],
        );

    for (final r in readOnly) {
      rows.add(row(first: rows.isEmpty, child: reminderText(r)));
    }
    for (var i = 0; i < reminders.length; i++) {
      final r = reminders[i];
      rows.add(row(
        first: rows.isEmpty,
        onTap: () => _edit(context, i),
        child: reminderText(r),
        trailing: IconButton(
          tooltip: l10n.delete,
          icon: const Icon(Icons.close),
          onPressed: () => onChanged([...reminders]..removeAt(i)),
        ),
      ));
    }
    if (reminders.length + readOnly.length < maxCount) {
      rows.add(row(
        first: rows.isEmpty,
        onTap: () => _edit(context, null),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(l10n.addReminder, style: TextStyle(fontSize: 16, color: muted)),
        ),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}
