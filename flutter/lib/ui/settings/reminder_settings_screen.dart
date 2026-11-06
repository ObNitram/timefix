import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../domain/reminders.dart';
import '../../state/reminder_settings.dart';
import '../format.dart';
import '../reminders/reminder_format.dart';
import '../reminders/reminder_list_editor.dart';
import '../reminders/reminder_picker.dart';
import '../theme.dart';
import 'reminder_permissions_section.dart';

/// Settings → Reminders: default reminders, presets, alarm behaviour,
/// permissions and test alerts.
class ReminderSettingsScreen extends ConsumerWidget {
  const ReminderSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(reminderSettingsProvider);
    final notifier = ref.read(reminderSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    String defaultsSummary(List<Reminder> list, bool allDay) => list.isEmpty
        ? l10n.noReminders
        : list.map((r) => context.reminderSummary(r, allDay: allDay)).join('\n');

    Future<T?> choose<T>(String title, List<T> values, T current, String Function(T) label) =>
        showDialog<T>(
          context: context,
          builder: (context) => SimpleDialog(
            title: Text(title),
            children: [
              for (final v in values)
                ListTile(
                  leading: Icon(v == current ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: v == current ? scheme.primary : null),
                  title: Text(label(v)),
                  onTap: () => Navigator.pop(context, v),
                ),
            ],
          ),
        );

    String soundLabel(String id) => switch (id) {
          'classic' => l10n.soundClassic,
          'digital' => l10n.soundDigital,
          'gentle' => l10n.soundGentle,
          _ => l10n.soundSystem,
        };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.reminders)),
      body: ListView(
        children: [
          _Header(l10n.defaultReminders),
          for (final allDay in [false, true])
            ListTile(
              leading: Icon(allDay ? Icons.today_outlined : Icons.schedule),
              title: Text(allDay ? l10n.defaultRemindersAllDay : l10n.defaultRemindersTimed),
              subtitle: Text(defaultsSummary(settings.defaultsFor(allDay: allDay), allDay)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => _DefaultRemindersScreen(allDay: allDay),
              )),
            ),
          const Divider(),
          _Header(l10n.myPresets),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(l10n.presetsHint, style: TextStyle(fontSize: 12, color: scheme.mutedText)),
          ),
          for (final p in settings.presets)
            ListTile(
              leading: Icon(reminderTypeIcon(p.reminder.type)),
              title: Text(context.presetLabel(p)),
              subtitle: Text([
                if (p.name?.trim().isNotEmpty ?? false) context.reminderSummary(p.reminder, allDay: p.allDay),
                if (p.allDay) l10n.defaultRemindersAllDay,
              ].join(' · ')),
              trailing: IconButton(
                tooltip: l10n.deletePreset,
                icon: const Icon(Icons.delete_outline),
                onPressed: () => notifier.deletePreset(p.id),
              ),
              onTap: () async {
                final edited = await showPresetDialog(context, preset: p);
                if (edited != null) notifier.savePreset(edited);
              },
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l10n.newPreset),
            onTap: () async {
              final created = await showPresetDialog(context);
              if (created != null) notifier.savePreset(created);
            },
          ),
          const Divider(),
          _Header(l10n.alarmSection),
          ListTile(
            leading: const Icon(Icons.music_note_outlined),
            title: Text(l10n.alarmSound),
            subtitle: Text(soundLabel(settings.alarmSound)),
            onTap: () async {
              final v = await choose(l10n.alarmSound, alarmSoundIds, settings.alarmSound, soundLabel);
              if (v != null) notifier.setAlarmSound(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.snooze),
            title: Text(l10n.snoozeDuration),
            subtitle: Text(l10n.minutes(settings.snoozeMinutes)),
            onTap: () async {
              final v = await choose(l10n.snoozeDuration, const [1, 5, 10, 15, 20, 30],
                  settings.snoozeMinutes, l10n.minutes);
              if (v != null) notifier.setSnoozeMinutes(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.timer_off_outlined),
            title: Text(l10n.autoStop),
            subtitle: Text(l10n.minutes(settings.autoStopMinutes)),
            onTap: () async {
              final v = await choose(l10n.autoStop, const [1, 2, 5, 10, 15, 30],
                  settings.autoStopMinutes, l10n.minutes);
              if (v != null) notifier.setAutoStopMinutes(v);
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.vibration),
            title: Text(l10n.vibration),
            value: settings.vibrate,
            onChanged: notifier.setVibrate,
          ),
          const Divider(),
          const ReminderPermissionsSection(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _DefaultRemindersScreen extends ConsumerWidget {
  const _DefaultRemindersScreen({required this.allDay});
  final bool allDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final reminders = ref.watch(reminderSettingsProvider).defaultsFor(allDay: allDay);
    return Scaffold(
      appBar: AppBar(title: Text(allDay ? l10n.defaultRemindersAllDay : l10n.defaultRemindersTimed)),
      body: ListView(
        padding: const EdgeInsets.only(top: 8),
        children: [
          ReminderListEditor(
            reminders: reminders,
            allDay: allDay,
            onChanged: (list) =>
                ref.read(reminderSettingsProvider.notifier).setDefaults(allDay: allDay, reminders: list),
          ),
        ],
      ),
    );
  }
}

/// Creates or edits a preset: optional name, timed / all-day, delay + type.
Future<ReminderPreset?> showPresetDialog(BuildContext context, {ReminderPreset? preset}) =>
    showDialog<ReminderPreset>(context: context, builder: (_) => _PresetDialog(preset: preset));

class _PresetDialog extends StatefulWidget {
  const _PresetDialog({this.preset});
  final ReminderPreset? preset;

  @override
  State<_PresetDialog> createState() => _PresetDialogState();
}

class _PresetDialogState extends State<_PresetDialog> {
  late final _name = TextEditingController(text: widget.preset?.name ?? '');
  late bool _allDay = widget.preset?.allDay ?? false;
  late Reminder _reminder = widget.preset?.reminder ?? const Reminder(30, ReminderType.alarm);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(widget.preset == null ? l10n.newPreset : l10n.editPreset),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.nameOptional),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.presetForAllDay),
              value: _allDay,
              onChanged: (v) => setState(() {
                _allDay = v;
                _reminder = Reminder(v ? 15 * 60 : 30, _reminder.type);
              }),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(reminderTypeIcon(_reminder.type)),
              title: Text(context.reminderDelay(_reminder.minutesBefore, allDay: _allDay)),
              subtitle: Text(reminderTypeLabel(l10n, _reminder.type)),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () async {
                final r = await showReminderPicker(context,
                    allDay: _allDay, initial: _reminder, showPresets: false);
                if (r != null) setState(() => _reminder = r);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(
          onPressed: () {
            final name = _name.text.trim();
            Navigator.pop(
              context,
              ReminderPreset(
                id: widget.preset?.id ?? 'preset-${const Uuid().v4()}',
                name: name.isEmpty ? null : name,
                reminder: _reminder,
                allDay: _allDay,
              ),
            );
          },
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text,
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
      );
}
