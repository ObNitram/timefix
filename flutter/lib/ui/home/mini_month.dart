import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/date_utils.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../format.dart';
import '../theme.dart';

/// Compact month calendar shown under the app bar when the title is tapped.
class MiniMonthPicker extends ConsumerStatefulWidget {
  const MiniMonthPicker({super.key, required this.selected, required this.onSelected});

  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  ConsumerState<MiniMonthPicker> createState() => _MiniMonthPickerState();
}

class _MiniMonthPickerState extends ConsumerState<MiniMonthPicker> {
  static const _base = 1000;
  late final DateTime _anchor = startOfMonth(widget.selected);
  late final PageController _controller = PageController(initialPage: _base);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = resolveFirstWeekday(context, ref.watch(settingsProvider));
    return SizedBox(
      height: 252,
      child: PageView.builder(
        controller: _controller,
        itemBuilder: (context, page) {
          final month = DateTime(_anchor.year, _anchor.month + page - _base, 1);
          return _MiniMonth(
            month: month,
            firstWeekday: firstWeekday,
            selected: widget.selected,
            onSelected: widget.onSelected,
          );
        },
      ),
    );
  }
}

class _MiniMonth extends ConsumerWidget {
  const _MiniMonth({
    required this.month,
    required this.firstWeekday,
    required this.selected,
    required this.onSelected,
  });

  final DateTime month;
  final int firstWeekday;
  final DateTime selected;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final start = monthGridStart(month, firstWeekday);
    final rows = monthGridRows(month, firstWeekday);
    final today = dateOnly(DateTime.now());
    final occurrences =
        ref.watch(occurrencesProvider(DateRange(start, addDays(start, rows * 7)))).value ??
            const [];
    final busyDays = <DateTime>{};
    for (final o in occurrences) {
      var d = dateOnly(o.start);
      final last = o.end.isAfter(o.start)
          ? dateOnly(o.end.subtract(const Duration(microseconds: 1)))
          : d;
      while (!d.isAfter(last)) {
        busyDays.add(d);
        d = addDays(d, 1);
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              capitalize(DateFormat.yMMMM(context.localeName).format(month)),
              style: TextStyle(fontWeight: FontWeight.w500, color: scheme.onSurface),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat.EEEEE(context.localeName).format(addDays(start, i)),
                      style: TextStyle(fontSize: 11, color: scheme.mutedText),
                    ),
                  ),
                ),
            ],
          ),
          for (var r = 0; r < rows; r++)
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < 7; c++)
                    Expanded(child: _dayCell(context, addDays(start, r * 7 + c), today, busyDays)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _dayCell(BuildContext context, DateTime day, DateTime today, Set<DateTime> busy) {
    final scheme = Theme.of(context).colorScheme;
    final inMonth = isSameMonth(day, month);
    final isToday = day == today;
    final isSelected = day == dateOnly(selected);
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: () => onSelected(day),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isToday
                  ? scheme.primary
                  : (isSelected ? scheme.primaryContainer : null),
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 12,
                color: isToday
                    ? scheme.onPrimary
                    : inMonth
                        ? scheme.onSurface
                        : scheme.mutedText.withValues(alpha: 0.6),
              ),
            ),
          ),
          if (busy.contains(day) && !isToday)
            Positioned(
              bottom: 1,
              child: Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(color: scheme.mutedText, shape: BoxShape.circle),
              ),
            ),
        ],
      ),
    );
  }
}
