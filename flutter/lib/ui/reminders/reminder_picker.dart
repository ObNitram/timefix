import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/reminders.dart';
import '../../state/reminder_settings.dart';
import '../format.dart';
import '../theme.dart';
import 'reminder_format.dart';

/// Bottom sheet to choose a reminder: alert type, built-in delays, the
/// user's presets or a custom delay.
Future<Reminder?> showReminderPicker(BuildContext context,
    {required bool allDay, Reminder? initial, bool showPresets = true}) {
  return showModalBottomSheet<Reminder>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, controller) => _ReminderPicker(
        controller: controller,
        allDay: allDay,
        initial: initial,
        showPresets: showPresets,
      ),
    ),
  );
}

class _ReminderPicker extends ConsumerStatefulWidget {
  const _ReminderPicker({
    required this.controller,
    required this.allDay,
    required this.initial,
    required this.showPresets,
  });

  final ScrollController controller;
  final bool allDay;
  final Reminder? initial;
  final bool showPresets;

  @override
  ConsumerState<_ReminderPicker> createState() => _ReminderPickerState();
}

class _ReminderPickerState extends ConsumerState<_ReminderPicker> {
  late ReminderType _type = widget.initial?.type ?? ReminderType.push;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isIos = Theme.of(context).platform == TargetPlatform.iOS;
    final delays = widget.allDay ? builtInAllDayDelays : builtInTimedDelays;
    final presets = widget.showPresets
        ? ref.watch(reminderSettingsProvider).presets.where((p) => p.allDay == widget.allDay).toList()
        : const <ReminderPreset>[];
    final note = !isIos
        ? null
        : switch (_type) {
            ReminderType.fullScreen => l10n.fullScreenIosNote,
            ReminderType.alarm => l10n.alarmIosNote,
            ReminderType.push => null,
          };

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: SegmentedButton<ReminderType>(
            showSelectedIcon: false,
            segments: [
              for (final t in ReminderType.values)
                // Labels only: with icons "Notification" does not fit on
                // phones (the list below shows the type's icon).
                ButtonSegment(
                  value: t,
                  label: Text(reminderTypeLabel(l10n, t),
                      maxLines: 1, softWrap: false, overflow: TextOverflow.fade),
                ),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.single),
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(note, style: TextStyle(fontSize: 12, color: scheme.mutedText)),
          ),
        for (final d in delays)
          ListTile(
            leading: Icon(reminderTypeIcon(_type)),
            title: Text(context.reminderDelay(d, allDay: widget.allDay)),
            trailing: widget.initial == Reminder(d, _type) ? const Icon(Icons.check) : null,
            onTap: () => Navigator.pop(context, Reminder(d, _type)),
          ),
        ListTile(
          leading: const Icon(Icons.tune),
          title: Text(l10n.reminderCustom),
          onTap: () async {
            final minutes = await showCustomDelayDialog(context,
                allDay: widget.allDay, initialMinutes: widget.initial?.minutesBefore);
            if (minutes != null && context.mounted) Navigator.pop(context, Reminder(minutes, _type));
          },
        ),
        if (presets.isNotEmpty) ...[
          const Divider(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(l10n.myPresets,
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w500)),
          ),
          for (final p in presets)
            ListTile(
              leading: Icon(reminderTypeIcon(p.reminder.type)),
              title: Text(context.presetLabel(p)),
              subtitle: (p.name?.trim().isNotEmpty ?? false)
                  ? Text(context.reminderSummary(p.reminder, allDay: p.allDay))
                  : null,
              onTap: () => Navigator.pop(context, p.reminder),
            ),
        ],
      ],
    );
  }
}

enum _Unit { minutes, hours, days, weeks }

/// Asks for a custom delay. Timed events: "N minutes/hours/days/weeks
/// before"; all-day events: "N days before at HH:MM".
Future<int?> showCustomDelayDialog(BuildContext context,
    {required bool allDay, int? initialMinutes}) {
  return showDialog<int>(
    context: context,
    builder: (_) => _CustomDelayDialog(allDay: allDay, initialMinutes: initialMinutes),
  );
}

class _CustomDelayDialog extends StatefulWidget {
  const _CustomDelayDialog({required this.allDay, this.initialMinutes});
  final bool allDay;
  final int? initialMinutes;

  @override
  State<_CustomDelayDialog> createState() => _CustomDelayDialogState();
}

class _CustomDelayDialogState extends State<_CustomDelayDialog> {
  final _amount = TextEditingController();
  var _unit = _Unit.minutes;
  var _time = const TimeOfDay(hour: 9, minute: 0);

  /// Timed reminder after the start (imported, e.g. a CalDAV "PT5M"
  /// trigger): kept as such, the preview below says so.
  var _afterStart = false;

  static const _unitMinutes = {
    _Unit.minutes: 1,
    _Unit.hours: 60,
    _Unit.days: 24 * 60,
    _Unit.weeks: 7 * 24 * 60,
  };

  @override
  void initState() {
    super.initState();
    final initial = widget.initialMinutes;
    if (widget.allDay) {
      final parts = allDayDelayParts(initial ?? 15 * 60);
      _amount.text = '${parts.daysBefore < 0 ? 0 : parts.daysBefore}';
      _time = TimeOfDay(hour: parts.hour, minute: parts.minute);
    } else {
      _afterStart = initial != null && initial < 0;
      final m = (initial ?? 30).abs();
      _unit = _Unit.values.reversed.firstWhere((u) => m > 0 && m % _unitMinutes[u]! == 0,
          orElse: () => _Unit.minutes);
      _amount.text = '${m ~/ _unitMinutes[_unit]!}';
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  int? get _value {
    final n = int.tryParse(_amount.text.trim());
    if (n == null || n < 0) return null;
    final minutes = widget.allDay
        ? allDayDelay(daysBefore: n, hour: _time.hour, minute: _time.minute)
        : n * _unitMinutes[_unit]! * (_afterStart ? -1 : 1);
    return minutes.abs() <= maxReminderMinutes ? minutes : null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unitLabels = {
      _Unit.minutes: l10n.unitMinutes,
      _Unit.hours: l10n.unitHours,
      _Unit.days: l10n.unitDays,
      _Unit.weeks: l10n.unitWeeks,
    };
    final value = _value;
    return AlertDialog(
      title: Text(l10n.reminderCustomTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 80,
                child: TextField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(labelText: widget.allDay ? l10n.daysBefore : null),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: widget.allDay
                    ? OutlinedButton.icon(
                        icon: const Icon(Icons.schedule),
                        label: Text(_time.format(context)),
                        onPressed: () async {
                          final t = await showTimePicker(context: context, initialTime: _time);
                          if (t != null) setState(() => _time = t);
                        },
                      )
                    : DropdownButton<_Unit>(
                        value: _unit,
                        isExpanded: true,
                        items: [
                          for (final u in _Unit.values)
                            DropdownMenuItem(value: u, child: Text(unitLabels[u]!)),
                        ],
                        onChanged: (u) => setState(() => _unit = u ?? _unit),
                      ),
              ),
            ],
          ),
          if (value != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(context.reminderDelay(value, allDay: widget.allDay),
                  style: TextStyle(color: Theme.of(context).colorScheme.mutedText)),
            ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(
          onPressed: value == null ? null : () => Navigator.pop(context, value),
          child: Text(l10n.ok),
        ),
      ],
    );
  }
}
