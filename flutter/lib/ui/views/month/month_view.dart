import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/colors.dart';
import '../../../core/date_utils.dart';
import '../../../domain/models.dart';
import '../../../state/providers.dart';
import '../../../state/settings.dart';
import '../../format.dart';
import '../../layout/lane_layout.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'day_sheet.dart';

/// Month view: a 5–6 week grid with event bars. Swipe to change month.
class MonthView extends ConsumerStatefulWidget {
  const MonthView({super.key});

  @override
  ConsumerState<MonthView> createState() => _MonthViewState();
}

class _MonthViewState extends ConsumerState<MonthView> {
  static const _basePage = 10000;
  late final PageController _controller = PageController(initialPage: _basePage);
  late final DateTime _anchorMonth = startOfMonth(ref.read(focusedDateProvider));

  DateTime _monthForPage(int page) =>
      DateTime(_anchorMonth.year, _anchorMonth.month + page - _basePage, 1);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    final month = _monthForPage(page);
    final today = DateTime.now();
    ref.read(focusedDateProvider.notifier).set(isSameMonth(month, today) ? today : month);
  }

  void _jumpTo(DateTime date) {
    final page = _basePage +
        (date.year - _anchorMonth.year) * 12 +
        (date.month - _anchorMonth.month);
    final current = _controller.page?.round() ?? _basePage;
    if ((page - current).abs() <= 2) {
      _controller.animateToPage(page,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    } else {
      _controller.jumpToPage(page);
    }
    ref.read(focusedDateProvider.notifier).set(date);
  }

  @override
  Widget build(BuildContext context) {
    final firstWeekday = resolveFirstWeekday(context, ref.watch(settingsProvider));
    ref.listen(jumpProvider, (_, next) {
      if (next != null) _jumpTo(next.date);
    });
    return Column(
      children: [
        _WeekdayHeader(firstWeekday: firstWeekday),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, page) =>
                _MonthPage(month: _monthForPage(page), firstWeekday: firstWeekday),
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.firstWeekday});
  final int firstWeekday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = DateTime.now();
    final start = startOfWeek(today, firstWeekday);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Center(
                child: Text(
                  DateFormat.EEEEE(context.localeName).format(addDays(start, i)).toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: scheme.mutedText,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MonthPage extends ConsumerWidget {
  const _MonthPage({required this.month, required this.firstWeekday});

  final DateTime month;
  final int firstWeekday;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = monthGridRows(month, firstWeekday);
    final gridStart = monthGridStart(month, firstWeekday);
    final range = DateRange(gridStart, addDays(gridStart, rows * 7));
    final occurrences = ref.watch(occurrencesProvider(range)).value ?? const [];
    return Column(
      children: [
        for (var r = 0; r < rows; r++)
          Expanded(
            child: _MonthWeekRow(
              weekStart: addDays(gridStart, r * 7),
              month: month,
              occurrences: occurrences,
            ),
          ),
      ],
    );
  }
}

class _MonthWeekRow extends StatelessWidget {
  const _MonthWeekRow({
    required this.weekStart,
    required this.month,
    required this.occurrences,
  });

  final DateTime weekStart;
  final DateTime month;
  final List<EventOccurrence> occurrences;

  static const _dayHeaderHeight = 26.0;
  static const _laneHeight = 16.0;
  static const _laneGap = 2.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());
    final layout = layoutLanes(weekStart, 7, occurrences);

    return LayoutBuilder(builder: (context, constraints) {
      final colW = constraints.maxWidth / 7;
      final available = constraints.maxHeight - _dayHeaderHeight - 2;
      final maxLanes = (available / (_laneHeight + _laneGap)).floor();
      final clip = layout.clip(maxLanes);

      return Stack(
        children: [
          // Day cells (tap → day sheet).
          Row(
            children: [
              for (var d = 0; d < 7; d++)
                Expanded(
                  child: _DayCell(
                    day: addDays(weekStart, d),
                    inMonth: isSameMonth(addDays(weekStart, d), month),
                    isToday: addDays(weekStart, d) == today,
                    leftBorder: d > 0,
                  ),
                ),
            ],
          ),
          for (final item in clip.visible)
            Positioned(
              top: _dayHeaderHeight + item.lane * (_laneHeight + _laneGap),
              left: item.firstDay * colW + 2,
              width: item.span * colW - 4,
              height: _laneHeight,
              child: IgnorePointer(child: _MonthChip(item: item)),
            ),
          for (var d = 0; d < 7; d++)
            if (clip.hiddenPerDay[d] > 0 && maxLanes > 0)
              Positioned(
                top: _dayHeaderHeight + (maxLanes - 1) * (_laneHeight + _laneGap),
                left: d * colW + 2,
                width: colW - 4,
                height: _laneHeight,
                child: IgnorePointer(
                  child: Text(
                    context.l10n.moreEvents(clip.hiddenPerDay[d]),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: scheme.mutedText, fontWeight: FontWeight.w500),
                  ),
                ),
              ),
        ],
      );
    });
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.leftBorder,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool leftBorder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => showDaySheet(context, day),
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: scheme.gridLine),
            left: leftBorder ? BorderSide(color: scheme.gridLine) : BorderSide.none,
          ),
        ),
        alignment: Alignment.topCenter,
        padding: const EdgeInsets.only(top: 3),
        child: DayNumber(
          day: day.day,
          isToday: isToday,
          size: 22,
          fontSize: 12,
          muted: !inMonth,
        ),
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  const _MonthChip({required this.item});
  final LaneItem item;

  @override
  Widget build(BuildContext context) {
    final o = item.occurrence;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: o.color,
        borderRadius: BorderRadius.horizontal(
          left: Radius.circular(item.continuesBefore ? 0 : 4),
          right: Radius.circular(item.continuesAfter ? 0 : 4),
        ),
      ),
      child: Text(
        eventTitle(context, o.event),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          color: onColor(o.color),
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
