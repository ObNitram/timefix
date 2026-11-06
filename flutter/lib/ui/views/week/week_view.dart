import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/colors.dart';
import '../../../core/date_utils.dart';
import '../../../domain/models.dart';
import '../../../state/providers.dart';
import '../../../state/settings.dart';
import '../../format.dart';
import '../../layout/day_layout.dart';
import '../../layout/lane_layout.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

const double _gutterWidth = 52;
const double _minHourHeight = 28;
const double _maxHourHeight = 160;

/// Week view: 7 day columns on an hourly grid. Swipe horizontally to change
/// week, pinch to zoom.
class WeekView extends ConsumerStatefulWidget {
  const WeekView({super.key, this.dayCount = 7});

  final int dayCount;

  @override
  ConsumerState<WeekView> createState() => _WeekViewState();
}

class _WeekViewState extends ConsumerState<WeekView> {
  static const _basePage = 10000;

  late final PageController _pageController = PageController(initialPage: _basePage);
  DateTime? _anchorWeek;
  int? _firstWeekday;
  double? _scrollOffset;
  late double _hourHeight = ref.read(settingsProvider).hourHeight;

  DateTime _weekForPage(int page) => addDays(_anchorWeek!, 7 * (page - _basePage));

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int page) {
    final week = _weekForPage(page);
    final today = dateOnly(DateTime.now());
    final focus = !today.isBefore(week) && today.isBefore(addDays(week, 7)) ? today : week;
    ref.read(focusedDateProvider.notifier).set(focus);
  }

  void _jumpTo(DateTime date) {
    final target = startOfWeek(date, _firstWeekday!);
    final page = _basePage + daysBetween(_anchorWeek!, target) ~/ 7;
    final current = _pageController.page?.round() ?? _basePage;
    if ((page - current).abs() <= 2) {
      _pageController.animateToPage(page,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
    } else {
      _pageController.jumpToPage(page);
    }
    ref.read(focusedDateProvider.notifier).set(date);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final firstWeekday = resolveFirstWeekday(context, settings);
    if (_firstWeekday != firstWeekday) {
      final focused = ref.read(focusedDateProvider);
      _firstWeekday = firstWeekday;
      final current = _pageController.hasClients ? _pageController.page?.round() : null;
      _anchorWeek = startOfWeek(focused, firstWeekday);
      if (current != null && current != _basePage) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _pageController.jumpToPage(_basePage));
      }
    }
    ref.listen(jumpProvider, (_, next) {
      if (next != null) _jumpTo(next.date);
    });

    return PageView.builder(
      controller: _pageController,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, page) => _WeekPage(
        weekStart: _weekForPage(page),
        dayCount: widget.dayCount,
        hourHeight: _hourHeight,
        initialScrollOffset: _scrollOffset ?? _defaultOffset(),
        onScrollOffsetChanged: (o) => _scrollOffset = o,
        onHourHeightChanged: (h, {bool end = false}) {
          setState(() => _hourHeight = h);
          if (end) ref.read(settingsProvider.notifier).setHourHeight(h);
        },
      ),
    );
  }

  double _defaultOffset() {
    final now = DateTime.now();
    final hour = (now.hour - 1).clamp(0, 18);
    return hour * _hourHeight;
  }
}

class _WeekPage extends ConsumerStatefulWidget {
  const _WeekPage({
    required this.weekStart,
    required this.dayCount,
    required this.hourHeight,
    required this.initialScrollOffset,
    required this.onScrollOffsetChanged,
    required this.onHourHeightChanged,
  });

  final DateTime weekStart;
  final int dayCount;
  final double hourHeight;
  final double initialScrollOffset;
  final ValueChanged<double> onScrollOffsetChanged;
  final void Function(double height, {bool end}) onHourHeightChanged;

  @override
  ConsumerState<_WeekPage> createState() => _WeekPageState();
}

class _WeekPageState extends ConsumerState<_WeekPage> {
  late final ScrollController _scroll =
      ScrollController(initialScrollOffset: widget.initialScrollOffset)
        ..addListener(() => widget.onScrollOffsetChanged(_scroll.offset));

  // Pinch-to-zoom state (handled with raw pointers so that one-finger
  // scrolling keeps working normally).
  final Map<int, Offset> _pointers = {};
  double? _pinchStartDistance;
  double? _pinchStartHourHeight;
  double? _pinchFocalContentHours;
  double? _pinchFocalViewportY;
  bool _allDayExpanded = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _pinching => _pointers.length >= 2;

  void _onPointerDown(PointerDownEvent e) {
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 2) {
      final pts = _pointers.values.toList();
      _pinchStartDistance = (pts[0] - pts[1]).distance;
      _pinchStartHourHeight = widget.hourHeight;
      final focalY = (pts[0].dy + pts[1].dy) / 2;
      _pinchFocalViewportY = focalY;
      _pinchFocalContentHours = (_scroll.offset + focalY) / widget.hourHeight;
      setState(() {});
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    if (!_pinching || _pinchStartDistance == null || _pinchStartDistance! < 10) return;
    final pts = _pointers.values.toList();
    final distance = (pts[0] - pts[1]).distance;
    final h = (_pinchStartHourHeight! * distance / _pinchStartDistance!)
        .clamp(_minHourHeight, _maxHourHeight);
    widget.onHourHeightChanged(h);
    final offset = _pinchFocalContentHours! * h - _pinchFocalViewportY!;
    if (_scroll.hasClients) {
      _scroll.jumpTo(offset.clamp(0, _scroll.position.maxScrollExtent + 24 * (h - widget.hourHeight)));
    }
  }

  void _onPointerUp(PointerEvent e) {
    final wasPinching = _pinching;
    _pointers.remove(e.pointer);
    if (wasPinching && !_pinching) {
      _pinchStartDistance = null;
      widget.onHourHeightChanged(widget.hourHeight, end: true);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = DateRange(widget.weekStart, addDays(widget.weekStart, widget.dayCount));
    final occurrences = ref.watch(occurrencesProvider(range)).value ?? const [];
    final allDay = <EventOccurrence>[];
    final timed = <EventOccurrence>[];
    for (final o in occurrences) {
      if (o.allDay || o.end.difference(o.start) >= const Duration(hours: 24)) {
        allDay.add(o);
      } else {
        timed.add(o);
      }
    }
    final days = [for (var i = 0; i < widget.dayCount; i++) addDays(widget.weekStart, i)];

    return Column(
      children: [
        _DayHeaders(days: days),
        if (allDay.isNotEmpty)
          _AllDayArea(
            weekStart: widget.weekStart,
            dayCount: widget.dayCount,
            occurrences: allDay,
            expanded: _allDayExpanded,
            onToggle: () => setState(() => _allDayExpanded = !_allDayExpanded),
          ),
        const Divider(),
        Expanded(
          child: Listener(
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: SingleChildScrollView(
              controller: _scroll,
              physics: _pinching ? const NeverScrollableScrollPhysics() : null,
              child: _TimeGrid(days: days, timed: timed, hourHeight: widget.hourHeight),
            ),
          ),
        ),
      ],
    );
  }
}

class _DayHeaders extends StatelessWidget {
  const _DayHeaders({required this.days});
  final List<DateTime> days;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final today = dateOnly(DateTime.now());
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 6),
      child: Row(
        children: [
          const SizedBox(width: _gutterWidth),
          for (final d in days)
            Expanded(
              child: Column(
                children: [
                  Text(
                    DateFormat.E(context.localeName).format(d).replaceAll('.', '').toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: d == today ? scheme.primary : scheme.mutedText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  DayNumber(day: d.day, isToday: d == today, size: 30, fontSize: 16),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _AllDayArea extends StatelessWidget {
  const _AllDayArea({
    required this.weekStart,
    required this.dayCount,
    required this.occurrences,
    required this.expanded,
    required this.onToggle,
  });

  final DateTime weekStart;
  final int dayCount;
  final List<EventOccurrence> occurrences;
  final bool expanded;
  final VoidCallback onToggle;

  static const _laneHeight = 20.0;
  static const _laneGap = 2.0;
  static const _collapsedLanes = 3;

  @override
  Widget build(BuildContext context) {
    final layout = layoutLanes(weekStart, dayCount, occurrences);
    final collapsible = layout.laneCount > _collapsedLanes;
    final maxLanes = expanded || !collapsible ? layout.laneCount : _collapsedLanes;
    final clip = layout.clip(maxLanes);
    final shownLanes = maxLanes.clamp(1, 1000);
    final height = shownLanes * (_laneHeight + _laneGap) + 4;
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _gutterWidth,
            child: collapsible
                ? IconButton(
                    visualDensity: VisualDensity.compact,
                    iconSize: 20,
                    onPressed: onToggle,
                    icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                  )
                : null,
          ),
          Expanded(
            child: LayoutBuilder(builder: (context, constraints) {
              final colW = constraints.maxWidth / dayCount;
              return Stack(
                children: [
                  for (final item in clip.visible)
                    Positioned(
                      top: item.lane * (_laneHeight + _laneGap),
                      left: item.firstDay * colW + 1,
                      width: item.span * colW - 2,
                      height: _laneHeight,
                      child: _AllDayChip(item: item),
                    ),
                  for (var d = 0; d < dayCount; d++)
                    if (clip.hiddenPerDay[d] > 0)
                      Positioned(
                        top: (maxLanes - 1) * (_laneHeight + _laneGap),
                        left: d * colW + 1,
                        width: colW - 2,
                        height: _laneHeight,
                        child: InkWell(
                          onTap: onToggle,
                          child: Center(
                            child: Text(
                              context.l10n.moreEvents(clip.hiddenPerDay[d]),
                              style: TextStyle(fontSize: 11, color: scheme.mutedText),
                            ),
                          ),
                        ),
                      ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip({required this.item});
  final LaneItem item;

  @override
  Widget build(BuildContext context) {
    final o = item.occurrence;
    return Material(
      color: o.color,
      borderRadius: BorderRadius.horizontal(
        left: Radius.circular(item.continuesBefore ? 0 : 4),
        right: Radius.circular(item.continuesAfter ? 0 : 4),
      ),
      child: InkWell(
        onTap: () => openEventDetails(context, o),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              eventTitle(context, o.event),
              maxLines: 1,
              overflow: TextOverflow.clip,
              softWrap: false,
              style: TextStyle(fontSize: 12, color: onColor(o.color), fontWeight: FontWeight.w500),
            ),
          ),
        ),
      ),
    );
  }
}

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({required this.days, required this.timed, required this.hourHeight});

  final List<DateTime> days;
  final List<EventOccurrence> timed;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalHeight = hourHeight * 24;
    return SizedBox(
      height: totalHeight + 12,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _gutterWidth,
            height: totalHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var h = 1; h < 24; h++)
                  Positioned(
                    top: h * hourHeight - 7,
                    right: 8,
                    child: Text(
                      formatHourLabel(context, h),
                      style: TextStyle(fontSize: 11, color: scheme.mutedText),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: SizedBox(
              height: totalHeight,
              child: LayoutBuilder(builder: (context, constraints) {
                final colW = constraints.maxWidth / days.length;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _GridPainter(
                          hourHeight: hourHeight,
                          columns: days.length,
                          color: scheme.gridLine,
                        ),
                      ),
                    ),
                    for (var i = 0; i < days.length; i++)
                      Positioned(
                        left: i * colW,
                        width: colW,
                        top: 0,
                        bottom: 0,
                        child: _DayColumn(
                          day: days[i],
                          occurrences: timed,
                          hourHeight: hourHeight,
                        ),
                      ),
                    for (var i = 0; i < days.length; i++)
                      if (isSameDay(days[i], DateTime.now()))
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Ticker(
                              builder: (context) => _NowIndicator(
                                dayIndex: i,
                                columnWidth: colW,
                                hourHeight: hourHeight,
                              ),
                            ),
                          ),
                        ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayColumn extends ConsumerWidget {
  const _DayColumn({required this.day, required this.occurrences, required this.hourHeight});

  final DateTime day;
  final List<EventOccurrence> occurrences;
  final double hourHeight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positioned = layoutDay(day, occurrences);
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (details) {
          final hour = (details.localPosition.dy / hourHeight).floor().clamp(0, 23);
          openEventEditor(context, start: DateTime(day.year, day.month, day.day, hour));
        },
        child: Stack(
          children: [
            for (final p in positioned)
              Positioned(
                top: p.startMinutes / 60 * hourHeight + 1,
                height: ((p.endMinutes - p.startMinutes) / 60 * hourHeight - 2).clamp(12, 24 * hourHeight),
                left: p.left * width + 1,
                width: p.width * width - 2,
                child: _GridEventTile(positioned: p, day: day),
              ),
          ],
        ),
      );
    });
  }
}

class _GridEventTile extends StatelessWidget {
  const _GridEventTile({required this.positioned, required this.day});
  final PositionedOccurrence positioned;
  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final o = positioned.occurrence;
    final fg = onColor(o.color);
    final surface = Theme.of(context).colorScheme.surface;
    return Material(
      color: o.color,
      // A thin border separates overlapping events.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: positioned.column > 0 ? BorderSide(color: surface, width: 1) : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openEventDetails(context, o),
        child: LayoutBuilder(builder: (context, c) {
          final showTime = c.maxHeight >= 30;
          // Narrow tiles: one clipped line instead of words broken mid-way.
          final narrow = c.maxWidth < 64;
          final titleLines = narrow ? 1 : (c.maxHeight >= 44 ? 3 : 1);
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 2, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Text(
                    eventTitle(context, o.event),
                    maxLines: titleLines,
                    softWrap: titleLines > 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ),
                if (showTime)
                  Text(
                    formatTime(context, o.start),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(color: fg.withValues(alpha: 0.9), fontSize: 10, height: 1.2),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _NowIndicator extends StatelessWidget {
  const _NowIndicator({required this.dayIndex, required this.columnWidth, required this.hourHeight});

  final int dayIndex;
  final double columnWidth;
  final double hourHeight;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final top = (now.hour * 60 + now.minute) / 60 * hourHeight;
    final color = Theme.of(context).colorScheme.nowIndicator;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: top - 1,
          left: dayIndex * columnWidth,
          width: columnWidth,
          height: 2,
          child: ColoredBox(color: color),
        ),
        Positioned(
          top: top - 6,
          left: dayIndex * columnWidth - 6,
          width: 12,
          height: 12,
          child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({required this.hourHeight, required this.columns, required this.color});

  final double hourHeight;
  final int columns;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (var h = 1; h < 24; h++) {
      final y = h * hourHeight;
      // Small tick into the gutter, like Google Calendar.
      canvas.drawLine(Offset(-8, y), Offset(size.width, y), paint);
    }
    final colW = size.width / columns;
    for (var i = 0; i < columns; i++) {
      final x = i * colW;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.hourHeight != hourHeight || old.columns != columns || old.color != color;
}
