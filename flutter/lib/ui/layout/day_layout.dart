import '../../core/date_utils.dart';
import '../../domain/models.dart';

/// Position of a timed event inside a day column of the week grid.
class PositionedOccurrence {
  PositionedOccurrence({
    required this.occurrence,
    required this.startMinutes,
    required this.endMinutes,
    required this.column,
    required this.columnSpan,
    required this.columnCount,
  });

  final EventOccurrence occurrence;

  /// Minutes since midnight of the displayed day (clipped to 0..1440).
  final int startMinutes;
  final int endMinutes;
  final int column;
  final int columnSpan;
  final int columnCount;

  double get left => column / columnCount;
  double get width => columnSpan / columnCount;
}

/// Lays out the timed events of [day] side by side when they overlap, like
/// Google Calendar: events of a cluster of overlaps share the width, and an
/// event extends to the right while the next columns are free.
List<PositionedOccurrence> layoutDay(
  DateTime day,
  List<EventOccurrence> occurrences, {
  int minDurationMinutes = 20,
}) {
  final dayStart = dateOnly(day);
  final dayEnd = addDays(dayStart, 1);

  final items = <_Item>[];
  for (final o in occurrences) {
    if (!o.start.isBefore(dayEnd)) continue;
    if (!o.end.isAfter(dayStart) && !(o.start == o.end && !o.start.isBefore(dayStart))) {
      continue;
    }
    final s = o.start.isBefore(dayStart) ? dayStart : o.start;
    final e = o.end.isAfter(dayEnd) ? dayEnd : o.end;
    final sm = s.difference(dayStart).inMinutes.clamp(0, 1440);
    var em = e.difference(dayStart).inMinutes.clamp(0, 1440);
    // Visual end, so that very short events still get a readable height.
    final visualEnd = (em - sm < minDurationMinutes)
        ? (sm + minDurationMinutes).clamp(0, 1440)
        : em;
    if (em < sm) em = sm;
    items.add(_Item(o, sm, em, visualEnd));
  }
  items.sort((a, b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    return b.visualEnd.compareTo(a.visualEnd);
  });

  final result = <PositionedOccurrence>[];
  var cluster = <_Item>[];
  var clusterEnd = -1;

  void flush() {
    if (cluster.isEmpty) return;
    // Greedy column assignment.
    final columnsEnd = <int>[];
    for (final it in cluster) {
      var placed = false;
      for (var c = 0; c < columnsEnd.length; c++) {
        if (columnsEnd[c] <= it.start) {
          it.column = c;
          columnsEnd[c] = it.visualEnd;
          placed = true;
          break;
        }
      }
      if (!placed) {
        it.column = columnsEnd.length;
        columnsEnd.add(it.visualEnd);
      }
    }
    final count = columnsEnd.length;
    for (final it in cluster) {
      // Expand to the right while no event of the next column overlaps.
      var span = 1;
      for (var c = it.column + 1; c < count; c++) {
        final blocked = cluster.any((o) =>
            o.column == c && o.start < it.visualEnd && o.visualEnd > it.start);
        if (blocked) break;
        span++;
      }
      result.add(PositionedOccurrence(
        occurrence: it.occurrence,
        startMinutes: it.start,
        endMinutes: it.visualEnd,
        column: it.column,
        columnSpan: span,
        columnCount: count,
      ));
    }
    cluster = [];
    clusterEnd = -1;
  }

  for (final it in items) {
    if (cluster.isNotEmpty && it.start >= clusterEnd) flush();
    cluster.add(it);
    if (it.visualEnd > clusterEnd) clusterEnd = it.visualEnd;
  }
  flush();
  return result;
}

class _Item {
  _Item(this.occurrence, this.start, this.end, this.visualEnd);
  final EventOccurrence occurrence;
  final int start;
  final int end;
  final int visualEnd;
  int column = 0;
}
