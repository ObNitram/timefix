import '../../core/date_utils.dart';
import '../../domain/models.dart';

/// An event bar inside a row of days (month view week row, all-day area of
/// the week view).
class LaneItem {
  LaneItem({
    required this.occurrence,
    required this.firstDay,
    required this.lastDay,
    required this.lane,
    required this.continuesBefore,
    required this.continuesAfter,
  });

  final EventOccurrence occurrence;

  /// Index of the first / last covered day within the row (inclusive).
  final int firstDay;
  final int lastDay;
  final int lane;

  /// The event started before the row / ends after it.
  final bool continuesBefore;
  final bool continuesAfter;

  int get span => lastDay - firstDay + 1;
}

class LaneLayout {
  LaneLayout(this.items, this.dayCount);

  final List<LaneItem> items;
  final int dayCount;

  int get laneCount =>
      items.fold(0, (m, i) => i.lane + 1 > m ? i.lane + 1 : m);

  /// Number of lanes used on [day].
  int lanesOnDay(int day) => items
      .where((i) => i.firstDay <= day && i.lastDay >= day)
      .fold(0, (m, i) => i.lane + 1 > m ? i.lane + 1 : m);

  /// Splits items between visible ones and per-day "+N" counters when at most
  /// [maxLanes] lanes fit.
  ({List<LaneItem> visible, List<int> hiddenPerDay}) clip(int maxLanes) {
    final hidden = List<int>.filled(dayCount, 0);
    if (maxLanes <= 0) {
      for (final i in items) {
        for (var d = i.firstDay; d <= i.lastDay; d++) {
          hidden[d]++;
        }
      }
      return (visible: const <LaneItem>[], hiddenPerDay: hidden);
    }
    final overflow = [for (var d = 0; d < dayCount; d++) lanesOnDay(d) > maxLanes];
    final visible = <LaneItem>[];
    for (final i in items) {
      var show = i.lane < maxLanes - 1;
      if (i.lane == maxLanes - 1) {
        show = true;
        for (var d = i.firstDay; d <= i.lastDay; d++) {
          if (overflow[d]) show = false;
        }
      }
      if (show) {
        visible.add(i);
      } else {
        for (var d = i.firstDay; d <= i.lastDay; d++) {
          hidden[d]++;
        }
      }
    }
    return (visible: visible, hiddenPerDay: hidden);
  }
}

/// Assigns lanes to [occurrences] displayed in a row of [dayCount] days
/// starting at [rowStart]. Longer events get the upper lanes.
LaneLayout layoutLanes(
    DateTime rowStart, int dayCount, List<EventOccurrence> occurrences) {
  final start = dateOnly(rowStart);
  final end = addDays(start, dayCount);
  final candidates = <(EventOccurrence, int, int, bool, bool)>[];
  for (final o in occurrences) {
    // Last day covered (end is exclusive, except for zero-length events).
    final lastInstant =
        o.end.isAfter(o.start) ? o.end.subtract(const Duration(microseconds: 1)) : o.start;
    final first = dateOnly(o.start);
    final last = dateOnly(lastInstant);
    if (!first.isBefore(end) || last.isBefore(start)) continue;
    final fi = first.isBefore(start) ? 0 : daysBetween(start, first);
    final li = last.isAfter(addDays(end, -1)) ? dayCount - 1 : daysBetween(start, last);
    candidates.add((o, fi, li, first.isBefore(start), last.isAfter(addDays(end, -1))));
  }
  candidates.sort((a, b) {
    final c = a.$2.compareTo(b.$2);
    if (c != 0) return c;
    final spanA = a.$3 - a.$2, spanB = b.$3 - b.$2;
    if (spanA != spanB) return spanB.compareTo(spanA);
    if (a.$1.allDay != b.$1.allDay) return a.$1.allDay ? -1 : 1;
    return a.$1.start.compareTo(b.$1.start);
  });

  final occupied = <List<bool>>[]; // lane → day → used
  final items = <LaneItem>[];
  for (final (o, fi, li, before, after) in candidates) {
    var lane = 0;
    while (true) {
      if (lane == occupied.length) occupied.add(List<bool>.filled(dayCount, false));
      var free = true;
      for (var d = fi; d <= li; d++) {
        if (occupied[lane][d]) {
          free = false;
          break;
        }
      }
      if (free) break;
      lane++;
    }
    for (var d = fi; d <= li; d++) {
      occupied[lane][d] = true;
    }
    items.add(LaneItem(
      occurrence: o,
      firstDay: fi,
      lastDay: li,
      lane: lane,
      continuesBefore: before,
      continuesAfter: after,
    ));
  }
  return LaneLayout(items, dayCount);
}
