/// Helpers for calendar date arithmetic.
///
/// All "day" helpers work on local wall-clock dates and are DST-safe: they
/// build new [DateTime]s from year/month/day instead of adding Durations.
library;

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

DateTime addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days, d.hour, d.minute, d.second);

DateTime addMonths(DateTime d, int months) {
  final target = DateTime(d.year, d.month + months, 1);
  final lastDay = daysInMonth(target.year, target.month);
  return DateTime(target.year, target.month, d.day > lastDay ? lastDay : d.day);
}

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

bool isSameMonth(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month;

/// Number of calendar days between two dates (ignores the time of day).
int daysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

/// Start of the week containing [d]. [firstWeekday] uses [DateTime.monday]..
/// [DateTime.sunday] (1..7).
DateTime startOfWeek(DateTime d, int firstWeekday) {
  final day = dateOnly(d);
  final diff = (day.weekday - firstWeekday) % 7;
  return addDays(day, -diff);
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month, 1);

/// The first day displayed in a month grid (start of the week containing the
/// 1st of the month).
DateTime monthGridStart(DateTime month, int firstWeekday) =>
    startOfWeek(startOfMonth(month), firstWeekday);

/// Number of week rows needed to display [month] (4 to 6).
int monthGridRows(DateTime month, int firstWeekday) {
  final start = monthGridStart(month, firstWeekday);
  final last = DateTime(month.year, month.month, daysInMonth(month.year, month.month));
  return daysBetween(start, last) ~/ 7 + 1;
}

/// A half-open range of time `[start, end)`.
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool overlaps(DateTime s, DateTime e) =>
      s.isBefore(end) && (e.isAfter(start) || (s == e && !s.isBefore(start)));

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start, $end)';
}

/// Day range `[day 00:00, next day 00:00)`.
DateRange dayRange(DateTime day) {
  final d = dateOnly(day);
  return DateRange(d, addDays(d, 1));
}
