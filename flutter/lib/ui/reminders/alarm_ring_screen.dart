import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../domain/reminders.dart';
import '../format.dart';

/// Information shown on the ringing / full-screen reminder screen.
class RingingReminder {
  const RingingReminder({
    required this.notificationId,
    required this.type,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.eventId,
  });

  final int notificationId;
  final ReminderType type;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? eventId;
}

/// Full-screen page shown for alarm and full-screen reminders, over the lock
/// screen. Alarms keep ringing until "Stop" (or the auto-stop delay).
class AlarmRingScreen extends StatefulWidget {
  const AlarmRingScreen({
    super.key,
    required this.reminder,
    required this.snoozeMinutes,
    required this.autoStop,
    required this.onStop,
    required this.onSnooze,
    this.onOpenEvent,
    this.isStillRinging,
    this.onShown,
  });

  final RingingReminder reminder;
  final int snoozeMinutes;
  final Duration autoStop;
  final Future<void> Function() onStop;
  final Future<void> Function() onSnooze;
  final Future<void> Function()? onOpenEvent;

  /// Polled every second. Once it has returned true, a false means the alarm
  /// was stopped elsewhere (notification, watch, auto-stop) and the screen
  /// closes by itself. Null means "unknown".
  final Future<bool?> Function()? isStillRinging;

  /// Called once the screen is displayed.
  final VoidCallback? onShown;

  /// Route result when the user chose to open the event.
  static const openedEvent = 'open';

  @override
  State<AlarmRingScreen> createState() => _AlarmRingScreenState();
}

class _AlarmRingScreenState extends State<AlarmRingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  Timer? _clock;
  Timer? _autoStop;
  bool _closing = false;
  bool _seenRinging = false;

  bool get _isAlarm => widget.reminder.type == ReminderType.alarm;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;
      setState(() {});
      final check = widget.isStillRinging;
      if (check == null || _closing) return;
      // The system notification may be posted slightly after this screen
      // opens: only a ringing alarm that stopped closes the screen.
      final ringing = await check();
      if (ringing == true) {
        _seenRinging = true;
      } else if (ringing == false && _seenRinging && mounted) {
        _close(() async {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.onShown?.call());
    _autoStop = Timer(widget.autoStop, () => _close(widget.onStop));
    if (_isAlarm) HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _autoStop?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  /// Runs [action], closes this screen (returning [result] to the route),
  /// then runs [after] (which may push another route).
  Future<void> _close(Future<void> Function() action,
      {Future<void> Function()? after, String? result}) async {
    if (_closing) return;
    _closing = true;
    try {
      await action();
    } finally {
      if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop(result);
    }
    if (after != null) await after();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final r = widget.reminder;
    final now = DateTime.now();
    const fg = Colors.white;
    final time = r.allDay
        ? l10n.allDay
        : '${formatTime(context, r.start)} – ${formatTime(context, r.end)}';

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1F3A),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                Text(
                  formatTime(context, now),
                  style: const TextStyle(color: fg, fontSize: 64, fontWeight: FontWeight.w300),
                ),
                Text(
                  capitalize(DateFormat.MMMMEEEEd(context.localeName).format(now)),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                ScaleTransition(
                  scale: Tween(begin: 0.92, end: 1.08)
                      .animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    child: Icon(_isAlarm ? Icons.alarm : Icons.event, color: fg, size: 56),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  r.title.trim().isEmpty ? l10n.noTitle : r.title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: fg, fontSize: 28, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Text(time, style: const TextStyle(color: Colors.white70, fontSize: 18)),
                if (r.location?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 4),
                  Text(r.location!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 16)),
                ],
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: fg,
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: const Icon(Icons.snooze),
                        label: Text(l10n.alarmSnooze(widget.snoozeMinutes)),
                        onPressed: () => _close(widget.onSnooze),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: fg,
                          foregroundColor: const Color(0xFF0B1F3A),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        icon: Icon(_isAlarm ? Icons.alarm_off : Icons.close),
                        label: Text(_isAlarm ? l10n.alarmStop : l10n.alarmDismiss),
                        onPressed: () => _close(widget.onStop),
                      ),
                    ),
                  ],
                ),
                if (widget.onOpenEvent != null) ...[
                  const SizedBox(height: 12),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: () =>
                        _close(widget.onStop, after: widget.onOpenEvent, result: AlarmRingScreen.openedEvent),
                    child: Text(l10n.openEvent),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
