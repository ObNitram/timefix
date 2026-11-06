import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/event_service.dart';
import '../../domain/reminders.dart';
import '../reminders/reminder_format.dart';
import '../reminders/reminder_list_editor.dart';
import '../reminders/reminder_permissions.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'scope_dialog.dart';

class EventDetailsScreen extends ConsumerWidget {
  const EventDetailsScreen({super.key, required this.occurrence});

  final EventOccurrence occurrence;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final event = occurrence.event;
    final calendar = ref.watch(calendarsByIdProvider)[event.calendarId];
    final source = calendar == null ? null : ref.watch(sourcesByIdProvider)[calendar.sourceId];
    final editable = calendar != null && !calendar.readOnly;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (editable)
            IconButton(
              tooltip: l10n.edit,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await openEventEditor(context, occurrence: occurrence);
                if (context.mounted) Navigator.of(context).pop();
              },
            ),
          if (editable)
            IconButton(
              tooltip: l10n.delete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(context, ref),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 8, 16, 32),
        children: [
          _Row(
            leading: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: occurrence.color,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(eventTitle(context, event), style: textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text(formatOccurrenceDetails(context, occurrence), style: textTheme.bodyMedium),
                if (event.isRecurring) ...[
                  const SizedBox(height: 2),
                  Text(describeRruleSafe(context, event),
                      style: textTheme.bodyMedium?.copyWith(color: scheme.mutedText)),
                ],
              ],
            ),
          ),
          _RemindersSection(event: event, editable: editable),
          if (event.location?.isNotEmpty ?? false)
            _Row(
              leading: const Icon(Icons.place_outlined),
              child: SelectableText(event.location!, style: textTheme.bodyLarge),
            ),
          if (event.description?.isNotEmpty ?? false)
            _Row(
              leading: const Icon(Icons.notes),
              child: SelectableText(event.description!, style: textTheme.bodyLarge),
            ),
          if (calendar != null)
            _Row(
              leading: const Icon(Icons.calendar_today_outlined),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(calendar.name, style: textTheme.bodyLarge),
                  if (source != null)
                    Text(
                      switch (source.type) {
                        SourceType.google => source.accountEmail ?? source.name,
                        SourceType.caldav => source.name,
                        _ => _sourceLabel(context, source.type),
                      },
                      style: textTheme.bodySmall?.copyWith(color: scheme.mutedText),
                    ),
                  if (calendar.readOnly)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(l10n.readOnlyCalendar,
                          style: textTheme.bodySmall?.copyWith(color: scheme.mutedText)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _sourceLabel(BuildContext context, SourceType type) => switch (type) {
        SourceType.local => context.l10n.sourceTypeLocal,
        SourceType.ical => context.l10n.sourceTypeIcal,
        SourceType.google => context.l10n.sourceTypeGoogle,
        SourceType.caldav => context.l10n.sourceTypeCalDav,
      };

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final l10n = context.l10n;
    final event = occurrence.event;
    RecurrenceScope scope = RecurrenceScope.all;
    if (event.isRecurring) {
      final s = await askRecurrenceScope(context,
          title: l10n.deleteRecurringTitle, confirmLabel: l10n.delete);
      if (s == null) return;
      scope = s;
    } else if (event.recurringRemoteId != null) {
      final s = await askRecurrenceScope(context,
          title: l10n.deleteRecurringTitle,
          confirmLabel: l10n.delete,
          options: const [RecurrenceScope.thisEvent, RecurrenceScope.all]);
      if (s == null) return;
      scope = s;
    } else {
      if (!await confirmDialog(context,
          title: l10n.deleteEventTitle, confirmLabel: l10n.delete)) {
        return;
      }
    }
    if (!context.mounted) return;
    final ok = await runGuarded(context, () async {
      await ref.read(eventServiceProvider).delete(occurrence, scope: scope);
      ref.read(dataRevisionProvider.notifier).bump();
    });
    if (ok && context.mounted) {
      showSnack(context, l10n.eventDeleted);
      Navigator.of(context).pop();
    }
  }
}

String describeRruleSafe(BuildContext context, CalendarEvent e) {
  try {
    return describeRrule(context, e.rrule!, e.start);
  } catch (_) {
    return context.l10n.repeatCustom;
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.child});
  final Widget leading;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Center(child: leading)),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Reminders of the event. Events of read-only calendars can get reminders
/// kept on this device; other events are changed in the editor.
class _RemindersSection extends ConsumerWidget {
  const _RemindersSection({required this.event, required this.editable});

  final CalendarEvent event;
  final bool editable;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = localReminderKey(event);
    final local = ref.watch(localRemindersProvider(key)).value ?? const <Reminder>[];
    final all = Reminder.normalize([...event.reminders, ...local]);
    final muted = Theme.of(context).colorScheme.mutedText;

    if (editable) {
      if (all.isEmpty) return const SizedBox.shrink();
      return _Row(
        leading: const Icon(Icons.notifications_outlined),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final r in all)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(reminderTypeIcon(r.type), size: 18, color: muted),
                    const SizedBox(width: 8),
                    Expanded(child: Text(context.reminderSummary(r, allDay: event.allDay))),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ReminderListEditor(
            reminders: local,
            readOnly: event.reminders,
            allDay: event.allDay,
            onChanged: (list) async {
              await ref.read(repositoryProvider).setLocalReminders(key, list);
              ref.read(dataRevisionProvider.notifier).bump();
              if (context.mounted) await ensureReminderPermissions(context, ref, list);
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 64, top: 2),
            child: Text(context.l10n.remindersDeviceOnly, style: TextStyle(fontSize: 12, color: muted)),
          ),
        ],
      ),
    );
  }
}
