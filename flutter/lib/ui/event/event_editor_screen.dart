import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../core/date_utils.dart';
import '../../data/event_service.dart';
import '../../domain/models.dart';
import '../../domain/recurrence.dart';
import '../../domain/series_edit.dart';
import '../../domain/reminders.dart';
import '../../state/reminder_settings.dart';
import '../reminders/reminder_list_editor.dart';
import '../reminders/reminder_permissions.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'event_details_screen.dart' show describeRruleSafe;
import 'scope_dialog.dart';

/// Full screen editor to create an event or edit [occurrence].
class EventEditorScreen extends ConsumerStatefulWidget {
  const EventEditorScreen({
    super.key,
    this.occurrence,
    this.initialStart,
    this.initialAllDay = false,
  });

  final EventOccurrence? occurrence;
  final DateTime? initialStart;
  final bool initialAllDay;

  @override
  ConsumerState<EventEditorScreen> createState() => _EventEditorScreenState();
}

class _EventEditorScreenState extends ConsumerState<EventEditorScreen> {
  final _title = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();

  late bool _allDay;

  /// Start and end. For all-day events [_end] is the last day (inclusive).
  late DateTime _start;
  late DateTime _end;
  String? _rrule;
  String? _calendarId;
  Color? _color;
  List<Reminder> _reminders = const [];

  /// False until the user changes the reminders: new events then follow the
  /// default reminders of the all-day / timed mode.
  bool _remindersTouched = false;

  /// Reminders before the last all-day switch and what they became, so that
  /// switching back restores them.
  List<Reminder>? _remindersBeforeSwitch;
  List<Reminder>? _remindersAfterSwitch;

  /// Reminders of a Google instance that only this device keeps, as loaded:
  /// a change asks whether it applies to the whole series.
  List<Reminder>? _deviceOnlyAtLoad;

  bool _dirty = false;
  bool _saving = false;

  /// Id of a new event, chosen once so that saving twice cannot create two.
  late final String _newEventId = ref.read(eventServiceProvider).newEventId();

  bool get _isNew => widget.occurrence == null;
  CalendarEvent? get _original => widget.occurrence?.event;

  /// Google instances of a series and CalDAV modified occurrences can only be
  /// edited one at a time.
  bool get _isSeriesInstance =>
      _original?.recurringRemoteId != null || _original?.recurrenceId != null;

  @override
  void initState() {
    super.initState();
    final o = widget.occurrence;
    if (o != null) {
      final e = o.event;
      _title.text = e.title;
      _location.text = e.location ?? '';
      _description.text = e.description ?? '';
      _allDay = e.allDay;
      _start = o.start;
      _end = e.allDay ? addDays(o.end, -1) : o.end;
      if (_end.isBefore(_start)) _end = _start;
      _rrule = e.rrule;
      _calendarId = e.calendarId;
      _color = e.color;
      _reminders = e.reminders;
      _loadDeviceReminders(e);
    } else {
      final now = DateTime.now();
      _allDay = widget.initialAllDay;
      _start = widget.initialStart ?? DateTime(now.year, now.month, now.day, now.hour + 1);
      final minutes = ref.read(settingsProvider).defaultDurationMinutes;
      _end = _allDay ? _start : _start.add(Duration(minutes: minutes));
      _reminders = ref.read(reminderSettingsProvider).defaultsFor(allDay: _allDay);
    }
    _initialTexts = [_title.text, _location.text, _description.text];
    for (final c in [_title, _location, _description]) {
      c.addListener(_onTextChanged);
    }
  }

  /// Texts as opened, to tell edits from mere cursor moves.
  late final List<String> _initialTexts;

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  /// The first text edit rebuilds the screen, so that the back guard
  /// ([PopScope]) asks before discarding it.
  void _onTextChanged() {
    if (_dirty) return;
    final texts = [_title.text, _location.text, _description.text];
    for (var i = 0; i < texts.length; i++) {
      if (texts[i] != _initialTexts[i]) {
        setState(() => _dirty = true);
        return;
      }
    }
  }

  /// Adds the reminders kept on this device (e.g. Google alarms).
  Future<void> _loadDeviceReminders(CalendarEvent e) async {
    final local = await ref.read(repositoryProvider).localReminders(deviceReminderKeys(e).toSet());
    if (!mounted || _remindersTouched) return;
    final effective = effectiveReminders(e, local);
    _deviceOnlyAtLoad = EventService.splitGoogleReminders(effective).local;
    if (local.isNotEmpty) setState(() => _reminders = effective);
  }

  void _update(VoidCallback fn) => setState(() {
        final start = _start;
        fn();
        _dirty = true;
        // A rule chosen here follows the date ("every Monday" moved to a
        // Tuesday). An event's own rule follows on save, for the occurrences
        // the change applies to.
        if (_rrule != null && _rrule != _original?.rrule) _rrule = rruleMovedBy(_rrule!, start, _start);
      });

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(1970),
      lastDate: DateTime(2200),
    );
    if (picked == null) return;
    _update(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
        _end = _start.add(duration);
      } else {
        _end = DateTime(picked.year, picked.month, picked.day, _end.hour, _end.minute);
        if (_end.isBefore(_start)) {
          _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
          if (_end.isBefore(_start)) _end = _start;
        }
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    _update(() {
      if (isStart) {
        final duration = _end.difference(_start);
        _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
        _end = _start.add(duration);
      } else {
        _end = DateTime(_end.year, _end.month, _end.day, picked.hour, picked.minute);
        if (_end.isBefore(_start)) {
          final minutes = ref.read(settingsProvider).defaultDurationMinutes;
          _end = _start.add(Duration(minutes: minutes));
        }
      }
    });
  }

  void _toggleAllDay(bool value) {
    _update(() {
      if (value == _allDay) return;
      _allDay = value;
      if (_isNew && !_remindersTouched) {
        _reminders = ref.read(reminderSettingsProvider).defaultsFor(allDay: value);
      } else if (_remindersBeforeSwitch != null && listEquals(_reminders, _remindersAfterSwitch)) {
        _reminders = _remindersBeforeSwitch!;
        _remindersBeforeSwitch = _remindersAfterSwitch = null;
      } else {
        // The same delay means something else for all-day events (counted
        // from midnight): convert it.
        _remindersBeforeSwitch = _reminders;
        _reminders = _remindersAfterSwitch = convertRemindersForAllDay(_reminders, toAllDay: value);
      }
      if (!value) {
        final now = DateTime.now();
        _start = DateTime(_start.year, _start.month, _start.day,
            isSameDay(_start, now) ? (now.hour + 1).clamp(0, 23) : 9);
        final minutes = ref.read(settingsProvider).defaultDurationMinutes;
        final end = _start.add(Duration(minutes: minutes));
        _end = isSameDay(_end, _start)
            ? end
            : DateTime(_end.year, _end.month, _end.day, end.hour, end.minute);
      }
    });
  }

  Future<void> _pickRecurrence() async {
    final current = presetForRrule(_rrule);
    final presets = [
      RecurrencePreset.none,
      RecurrencePreset.daily,
      RecurrencePreset.weekly,
      RecurrencePreset.monthly,
      RecurrencePreset.yearly,
      RecurrencePreset.weekdays,
      if (current == RecurrencePreset.custom) RecurrencePreset.custom,
    ];
    final picked = await showDialog<RecurrencePreset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(context.l10n.repeat),
        children: [
          for (final p in presets)
            ListTile(
              leading: Icon(p == current ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: p == current ? Theme.of(context).colorScheme.primary : null),
              title: Text(p == RecurrencePreset.custom
                  ? describeRrule(context, _rrule!, _start)
                  : recurrencePresetLabel(context, p, _start)),
              onTap: () => Navigator.pop(context, p),
            ),
        ],
      ),
    );
    if (picked == null || picked == RecurrencePreset.custom || picked == current) return;
    _update(() => _rrule = rruleForPreset(picked, _start));
  }

  Future<void> _pickCalendar(List<CalendarInfo> calendars) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final c in calendars)
              ListTile(
                leading: CircleAvatar(radius: 8, backgroundColor: c.color),
                title: Text(c.name),
                trailing: c.id == _calendarId ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(context, c.id),
              ),
          ],
        ),
      ),
    );
    if (picked != null) _update(() => _calendarId = picked);
  }

  Future<void> _pickColor(Color calendarColor) async {
    final result = await showColorPickerSheet(context,
        selected: _color, allowDefault: true, defaultColor: calendarColor);
    if (result != null) _update(() => _color = result.color);
  }

  CalendarEvent _buildEvent(String calendarId) {
    final start = _allDay ? dateOnly(_start) : _start;
    final end = _allDay ? addDays(dateOnly(_end), 1) : _end;
    final base = _original ??
        CalendarEvent(
          id: _newEventId,
          calendarId: calendarId,
          title: '',
          start: start,
          end: end,
        );
    return CalendarEvent(
      id: base.id,
      calendarId: calendarId,
      title: _title.text.trim(),
      start: start,
      end: end,
      allDay: _allDay,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      location: _location.text.trim().isEmpty ? null : _location.text.trim(),
      timeZone: base.timeZone,
      rrule: _isSeriesInstance ? null : _rrule,
      exdates: base.exdates,
      color: _color,
      remoteId: base.remoteId,
      recurringRemoteId: base.recurringRemoteId,
      reminders: _reminders,
      extraAlarms: base.extraAlarms,
    );
  }

  Future<void> _save(String calendarId) async {
    final l10n = context.l10n;
    final edited = _buildEvent(calendarId);
    final service = ref.read(eventServiceProvider);
    var scope = RecurrenceScope.all;
    final original = _original;
    if (original != null && original.isRecurring) {
      final ruleChanged = edited.rrule != original.rrule;
      final s = await askRecurrenceScope(
        context,
        title: l10n.editRecurringTitle,
        confirmLabel: l10n.ok,
        options: ruleChanged
            ? const [RecurrenceScope.thisAndFollowing, RecurrenceScope.all]
            : RecurrenceScope.values,
      );
      if (s == null) return;
      scope = s;
    }
    RecurrenceScope? deviceScope;
    final deviceOnlyAtLoad = _deviceOnlyAtLoad;
    if (original?.recurringRemoteId != null &&
        deviceOnlyAtLoad != null &&
        edited.calendarId == original!.calendarId &&
        !listEquals(EventService.splitGoogleReminders(edited.reminders).local, deviceOnlyAtLoad)) {
      if (!mounted) return;
      deviceScope = await askRecurrenceScope(
        context,
        title: l10n.deviceRemindersScopeTitle,
        confirmLabel: l10n.ok,
        options: const [RecurrenceScope.thisEvent, RecurrenceScope.all],
      );
      if (deviceScope == null) return;
    }
    if (!mounted) return;
    setState(() => _saving = true);
    final ok = await runGuarded(context, () async {
      if (original == null) {
        await service.create(edited);
      } else {
        await service.update(
            original: widget.occurrence!, edited: edited, scope: scope, deviceScope: deviceScope);
      }
      ref.read(dataRevisionProvider.notifier).bump();
    });
    if (!mounted) return;
    if (!ok) {
      setState(() => _saving = false);
      return;
    }
    // Saving stays disabled until the editor is closed.
    _dirty = false;
    await ensureReminderPermissions(context, edited.reminders);
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await confirmDialog(context,
        title: l10n.discardChangesTitle, confirmLabel: l10n.discard);
    if (discard && mounted) {
      _dirty = false;
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final writable = ref.watch(writableCalendarsProvider);
    final calendarsById = ref.watch(calendarsByIdProvider);
    _calendarId ??= writable.isEmpty ? null : writable.first.id;
    final calendar = _calendarId == null ? null : calendarsById[_calendarId];

    // Google series instances can only move inside their own calendar.
    final calendarChoices = _isSeriesInstance
        ? writable.where((c) => c.id == _original!.calendarId).toList()
        : writable;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: l10n.close,
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.maybePop(context),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton(
                onPressed: calendar == null || _saving ? null : () => _save(calendar.id),
                child: _saving
                    ? const SizedBox(
                        width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(l10n.save),
              ),
            ),
          ],
        ),
        body: calendar == null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(l10n.noWritableCalendar, textAlign: TextAlign.center),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(64, 8, 16, 8),
                    child: TextField(
                      controller: _title,
                      autofocus: _isNew,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(fontSize: 24),
                      decoration: InputDecoration(
                        hintText: l10n.addTitle,
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const Divider(),
                  _EditorRow(
                    icon: Icons.schedule,
                    child: Row(
                      children: [
                        Expanded(child: Text(l10n.allDay, style: const TextStyle(fontSize: 16))),
                        Switch(value: _allDay, onChanged: _toggleAllDay),
                      ],
                    ),
                  ),
                  _DateTimeRow(
                    date: formatShortDate(context, _start),
                    time: _allDay ? null : formatTime(context, _start),
                    onDate: () => _pickDate(isStart: true),
                    onTime: () => _pickTime(isStart: true),
                  ),
                  _DateTimeRow(
                    date: formatShortDate(context, _end),
                    time: _allDay ? null : formatTime(context, _end),
                    onDate: () => _pickDate(isStart: false),
                    onTime: () => _pickTime(isStart: false),
                  ),
                  _EditorRow(
                    icon: Icons.repeat,
                    onTap: _isSeriesInstance ? null : _pickRecurrence,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _rrule == null
                              ? l10n.repeatNone
                              : describeRruleSafe(
                                  context, _buildEvent(calendar.id).copyWith(start: _start)),
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (_isSeriesInstance)
                          Text(l10n.seriesInstanceNote,
                              style: TextStyle(fontSize: 12, color: scheme.mutedText)),
                      ],
                    ),
                  ),
                  const Divider(),
                  ReminderListEditor(
                    reminders: _reminders,
                    allDay: _allDay,
                    onChanged: (list) => _update(() {
                      _reminders = list;
                      _remindersTouched = true;
                    }),
                  ),
                  const Divider(),
                  _EditorRow(
                    icon: Icons.calendar_today_outlined,
                    onTap: calendarChoices.length > 1 ? () => _pickCalendar(calendarChoices) : null,
                    child: Row(
                      children: [
                        CircleAvatar(radius: 6, backgroundColor: calendar.color),
                        const SizedBox(width: 12),
                        Expanded(child: Text(calendar.name, style: const TextStyle(fontSize: 16))),
                      ],
                    ),
                  ),
                  _EditorRow(
                    icon: Icons.palette_outlined,
                    onTap: () => _pickColor(calendar.color),
                    child: Row(
                      children: [
                        CircleAvatar(radius: 6, backgroundColor: _color ?? calendar.color),
                        const SizedBox(width: 12),
                        Text(
                          _color == null
                              ? l10n.defaultColor
                              : colorName(context,
                                  calendarPalette.firstWhere((p) => p.color == _color,
                                      orElse: () => calendarPalette.last)),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  _EditorRow(
                    icon: Icons.place_outlined,
                    child: TextField(
                      controller: _location,
                      decoration: InputDecoration(
                          hintText: l10n.addLocation, border: InputBorder.none),
                    ),
                  ),
                  const Divider(),
                  _EditorRow(
                    icon: Icons.notes,
                    child: TextField(
                      controller: _description,
                      minLines: 1,
                      maxLines: 8,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                          hintText: l10n.addDescription, border: InputBorder.none),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _EditorRow extends StatelessWidget {
  const _EditorRow({required this.icon, required this.child, this.onTap});

  final IconData icon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            SizedBox(
              width: 64,
              child: Icon(icon, color: Theme.of(context).colorScheme.mutedText),
            ),
            Expanded(child: child),
            const SizedBox(width: 16),
          ],
        ),
      ),
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({required this.date, required this.time, required this.onDate, required this.onTime});

  final String date;
  final String? time;
  final VoidCallback onDate;
  final VoidCallback onTime;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 16);
    return Padding(
      padding: const EdgeInsets.only(left: 52, right: 4),
      child: Row(
        children: [
          Expanded(
            child: TextButton(
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                foregroundColor: Theme.of(context).colorScheme.onSurface,
              ),
              onPressed: onDate,
              child: Text(date, style: style),
            ),
          ),
          if (time != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
              onPressed: onTime,
              child: Text(time!, style: style),
            ),
        ],
      ),
    );
  }
}
