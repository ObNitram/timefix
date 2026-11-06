import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/colors.dart';
import '../../domain/models.dart';
import '../format.dart';

/// Day number, circled in blue when it is today.
class DayNumber extends StatelessWidget {
  const DayNumber({
    super.key,
    required this.day,
    required this.isToday,
    this.size = 32,
    this.fontSize = 18,
    this.muted = false,
  });

  final int day;
  final bool isToday;
  final double size;
  final double fontSize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: isToday
          ? BoxDecoration(color: scheme.primary, shape: BoxShape.circle)
          : null,
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: isToday ? FontWeight.w600 : FontWeight.w400,
          color: isToday
              ? scheme.onPrimary
              : (muted ? scheme.onSurfaceVariant.withValues(alpha: 0.6) : scheme.onSurface),
        ),
      ),
    );
  }
}

/// Rounded colored card used by the schedule view and day sheets.
class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.occurrence, this.day, this.onTap});

  final EventOccurrence occurrence;
  final DateTime? day;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = occurrence.color;
    final fg = onColor(color);
    final timeLabel = occurrence.allDay ? null : formatOccurrenceTime(context, occurrence, day: day);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  eventTitle(context, occurrence.event),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.w500),
                ),
                if (timeLabel != null)
                  Text(
                    timeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 12),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet listing the 11 palette colors, Google Calendar style.
/// Returns the chosen color, or `null` when [allowDefault] and "default"
/// is selected. The sheet result is wrapped so that "dismissed" can be told
/// apart from "default".
Future<({Color? color})?> showColorPickerSheet(
  BuildContext context, {
  Color? selected,
  bool allowDefault = false,
  Color? defaultColor,
}) {
  return showModalBottomSheet<({Color? color})>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      Widget tile(Color? c, String label) {
        final isSelected = c == null ? selected == null : selected == c;
        return ListTile(
          leading: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: c ?? defaultColor ?? googleBlue,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(label),
          trailing: isSelected ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, (color: c)),
        );
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              if (allowDefault) tile(null, context.l10n.defaultColor),
              for (final p in calendarPalette) tile(p.color, colorName(context, p)),
            ],
          ),
        ),
      );
    },
  );
}

/// Small horizontal swatch row (used in forms).
class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({super.key, required this.selected, required this.onSelected});

  final Color selected;
  final ValueChanged<Color> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final p in calendarPalette)
          Semantics(
            label: colorName(context, p),
            selected: p.color == selected,
            button: true,
            child: GestureDetector(
              onTap: () => onSelected(p.color),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: p.color, shape: BoxShape.circle),
                child: p.color == selected
                    ? Icon(Icons.check, color: onColor(p.color), size: 20)
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.cancel)),
        TextButton(
            onPressed: () => Navigator.pop(context, true), child: Text(confirmLabel)),
      ],
    ),
  );
  return result ?? false;
}

void showSnack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Calls [action] and shows errors in a snackbar.
Future<bool> runGuarded(BuildContext context, Future<void> Function() action) async {
  try {
    await action();
    return true;
  } catch (e) {
    if (context.mounted) showSnack(context, context.l10n.errorMessage('$e'));
    return false;
  }
}

/// Utility to keep a widget in sync with a periodic timer.
class Ticker extends StatefulWidget {
  const Ticker({super.key, required this.builder, this.period = const Duration(minutes: 1)});
  final WidgetBuilder builder;
  final Duration period;

  @override
  State<Ticker> createState() => _TickerState();
}

class _TickerState extends State<Ticker> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.period, (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
