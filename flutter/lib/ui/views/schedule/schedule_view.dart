import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/date_utils.dart';
import '../../../domain/models.dart';
import '../../../state/providers.dart';
import '../../../state/settings.dart';
import '../../format.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'month_banner.dart';

/// "Planning" view: an infinite list of days with events, in both directions.
class ScheduleView extends ConsumerStatefulWidget {
  const ScheduleView({super.key});

  @override
  ConsumerState<ScheduleView> createState() => _ScheduleViewState();
}

class _ScheduleViewState extends ConsumerState<ScheduleView> {
  final _centerKey = UniqueKey();
  final _scrollViewKey = GlobalKey();
  final _marks = _MarkRegistry();
  late DateTime _anchorDay;
  DateTime? _anchorWeek;
  int _generation = 0;
  ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _anchorDay = ref.read(focusedDateProvider);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealAnchorDay());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpTo(DateTime date) {
    final old = _controller;
    setState(() {
      _anchorDay = dateOnly(date);
      _anchorWeek = null;
      _generation++;
      _controller = ScrollController();
    });
    // Dispose once the scroll view has switched to the new controller.
    WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
    ref.read(focusedDateProvider.notifier).set(date);
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealAnchorDay());
  }

  /// Scrolls so that the anchor day (or the next displayed day) is at the top.
  void _revealAnchorDay([int attempt = 0]) {
    if (!mounted) return;
    final ctx = _marks.firstDayFrom(_anchorDay, addDays(_anchorWeek ?? _anchorDay, 7));
    if (ctx == null) {
      // Data not loaded yet: try again on the next frames.
      if (attempt < 60) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _revealAnchorDay(attempt + 1));
      }
      return;
    }
    Scrollable.ensureVisible(ctx, alignment: 0);
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0) return false;
    final viewBox = _scrollViewKey.currentContext?.findRenderObject() as RenderBox?;
    if (viewBox == null || !viewBox.attached) return false;
    final top = viewBox.localToGlobal(Offset.zero).dy;
    final date = _marks.dateAt(top + 4);
    if (date != null) ref.read(focusedDateProvider.notifier).set(date);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final firstWeekday = resolveFirstWeekday(context, settings);
    _anchorWeek ??= startOfWeek(_anchorDay, firstWeekday);
    final anchorWeek = _anchorWeek!;

    ref.listen(jumpProvider, (_, next) {
      if (next != null) _jumpTo(next.date);
    });

    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: CustomScrollView(
          key: _scrollViewKey,
          controller: _controller,
          center: _centerKey,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ScheduleWeek(
                  key: ValueKey('w$_generation-${-i - 1}'),
                  weekStart: addDays(anchorWeek, -7 * (i + 1)),
                  marks: _marks,
                ),
              ),
            ),
            SliverList(
              key: _centerKey,
              delegate: SliverChildBuilderDelegate(
                (context, i) => _ScheduleWeek(
                  key: ValueKey('w$_generation-$i'),
                  weekStart: addDays(anchorWeek, 7 * i),
                  marks: _marks,
                ),
              ),
            ),
          ],
        ),
    );
  }
}

/// Keeps track of the widgets that carry a date, to update the app bar title
/// while scrolling and to scroll to a given day.
class _MarkRegistry {
  final Map<_MarkState, ({DateTime date, bool isDay})> _items = {};

  void add(_MarkState s, DateTime date, bool isDay) => _items[s] = (date: date, isDay: isDay);
  void remove(_MarkState s) => _items.remove(s);

  BuildContext? firstDayFrom(DateTime from, DateTime before) {
    _MarkState? best;
    DateTime? bestDate;
    for (final e in _items.entries) {
      final v = e.value;
      if (!v.isDay || v.date.isBefore(from) || !v.date.isBefore(before)) continue;
      if (bestDate == null || v.date.isBefore(bestDate)) {
        best = e.key;
        bestDate = v.date;
      }
    }
    return best?.context;
  }

  /// Date of the last mark whose top is above [y] (global coordinates).
  DateTime? dateAt(double y) {
    DateTime? best;
    double bestTop = double.negativeInfinity;
    DateTime? firstBelow;
    double firstBelowTop = double.infinity;
    for (final e in _items.entries) {
      final box = e.key.context.findRenderObject() as RenderBox?;
      if (box == null || !box.attached || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top <= y && top > bestTop) {
        bestTop = top;
        best = e.value.date;
      } else if (top > y && top < firstBelowTop) {
        firstBelowTop = top;
        firstBelow = e.value.date;
      }
    }
    return best ?? firstBelow;
  }
}

class _Mark extends StatefulWidget {
  const _Mark({required this.registry, required this.date, required this.isDay, required this.child});
  final _MarkRegistry registry;
  final DateTime date;
  final bool isDay;
  final Widget child;

  @override
  State<_Mark> createState() => _MarkState();
}

class _MarkState extends State<_Mark> {
  @override
  void initState() {
    super.initState();
    widget.registry.add(this, widget.date, widget.isDay);
  }

  @override
  void didUpdateWidget(_Mark old) {
    super.didUpdateWidget(old);
    widget.registry.add(this, widget.date, widget.isDay);
  }

  @override
  void dispose() {
    widget.registry.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _ScheduleWeek extends ConsumerWidget {
  const _ScheduleWeek({super.key, required this.weekStart, required this.marks});

  final DateTime weekStart;
  final _MarkRegistry marks;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weekEnd = addDays(weekStart, 7);
    final async = ref.watch(occurrencesProvider(DateRange(weekStart, weekEnd)));
    final occurrences = async.value;
    final today = dateOnly(DateTime.now());
    final children = <Widget>[];

    Widget weekLabel(DateTime from) => _Mark(
          registry: marks,
          date: from,
          isDay: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(72, 12, 16, 8),
            child: Text(
              formatWeekRange(context, from, addDays(weekEnd, -1)),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.mutedText,
              ),
            ),
          ),
        );

    for (var i = 0; i < 7; i++) {
      final day = addDays(weekStart, i);
      if (day.day == 1) {
        children.add(_Mark(
          registry: marks,
          date: day,
          isDay: false,
          child: MonthBanner(month: day),
        ));
        children.add(weekLabel(day));
      } else if (i == 0) {
        children.add(weekLabel(day));
      }
      if (occurrences == null) continue;
      final dayEnd = addDays(day, 1);
      final dayOccurrences = occurrences
          .where((o) => o.start.isBefore(dayEnd) &&
              (o.end.isAfter(day) || (o.start == o.end && !o.start.isBefore(day))))
          .toList();
      final isToday = day == today;
      if (dayOccurrences.isEmpty && !isToday) continue;
      children.add(_Mark(
        registry: marks,
        date: day,
        isDay: true,
        child: _DayRow(day: day, occurrences: dayOccurrences, isToday: isToday),
      ));
    }
    if (occurrences == null) {
      children.add(const SizedBox(height: 120));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day, required this.occurrences, required this.isToday});

  final DateTime day;
  final List<EventOccurrence> occurrences;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final weekday = DateFormat.E(context.localeName).format(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 56,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => openEventEditor(context, start: _defaultStart(day)),
              child: Column(
                children: [
                  Text(
                    weekday,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isToday ? scheme.primary : scheme.mutedText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  DayNumber(day: day.day, isToday: isToday, size: 36, fontSize: 20),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isToday
                ? Ticker(builder: (context) => _events(context, DateTime.now()))
                : _events(context, null),
          ),
        ],
      ),
    );
  }

  Widget _events(BuildContext context, DateTime? now) {
    final children = <Widget>[];
    var nowPlaced = now == null;
    for (final o in occurrences) {
      if (!nowPlaced && !o.allDay && o.start.isAfter(now!)) {
        children.add(const _NowLine());
        nowPlaced = true;
      }
      children.add(EventCard(
        occurrence: o,
        day: day,
        onTap: () => openEventDetails(context, o),
      ));
    }
    if (occurrences.isEmpty) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(
          context.l10n.nothingPlanned,
          style: TextStyle(color: Theme.of(context).colorScheme.mutedText),
        ),
      ));
    }
    if (!nowPlaced) children.add(const _NowLine());
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
    );
  }

  static DateTime _defaultStart(DateTime day) {
    final now = DateTime.now();
    if (isSameDay(day, now)) return DateTime(day.year, day.month, day.day, now.hour + 1);
    return DateTime(day.year, day.month, day.day, 9);
  }
}

class _NowLine extends StatelessWidget {
  const _NowLine();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.nowIndicator;
    return SizedBox(
      height: 12,
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          Expanded(child: Container(height: 2, color: color)),
        ],
      ),
    );
  }
}
