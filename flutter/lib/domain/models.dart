import 'package:flutter/painting.dart';

/// Where a group of calendars comes from.
enum SourceType {
  /// Stored only on the device. Fully editable.
  local,

  /// iCalendar (.ics) subscription by URL. Read only.
  ical,

  /// Google account, synced through the Google Calendar API.
  google;

  static SourceType fromName(String name) =>
      SourceType.values.firstWhere((t) => t.name == name, orElse: () => local);
}

/// An account or subscription that provides one or more calendars.
class CalendarSource {
  const CalendarSource({
    required this.id,
    required this.type,
    required this.name,
    this.url,
    this.accountEmail,
    this.lastSyncedAt,
    this.lastError,
  });

  final String id;
  final SourceType type;
  final String name;

  /// Subscription URL for [SourceType.ical].
  final String? url;

  /// Account e-mail for [SourceType.google].
  final String? accountEmail;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get isRemote => type != SourceType.local;

  CalendarSource copyWith({
    String? name,
    String? url,
    String? accountEmail,
    DateTime? lastSyncedAt,
    String? lastError,
    bool clearError = false,
  }) =>
      CalendarSource(
        id: id,
        type: type,
        name: name ?? this.name,
        url: url ?? this.url,
        accountEmail: accountEmail ?? this.accountEmail,
        lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
      );
}

/// A calendar displayed in the drawer with its own color and visibility.
class CalendarInfo {
  const CalendarInfo({
    required this.id,
    required this.sourceId,
    required this.name,
    required this.color,
    this.remoteId,
    this.visible = true,
    this.readOnly = false,
    this.sortOrder = 0,
  });

  final String id;
  final String sourceId;

  /// Identifier on the remote service (Google calendar id).
  final String? remoteId;
  final String name;
  final Color color;
  final bool visible;
  final bool readOnly;
  final int sortOrder;

  CalendarInfo copyWith({
    String? name,
    Color? color,
    bool? visible,
    bool? readOnly,
    int? sortOrder,
  }) =>
      CalendarInfo(
        id: id,
        sourceId: sourceId,
        remoteId: remoteId,
        name: name ?? this.name,
        color: color ?? this.color,
        visible: visible ?? this.visible,
        readOnly: readOnly ?? this.readOnly,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  @override
  bool operator ==(Object other) =>
      other is CalendarInfo &&
      other.id == id &&
      other.sourceId == sourceId &&
      other.remoteId == remoteId &&
      other.name == name &&
      other.color == color &&
      other.visible == visible &&
      other.readOnly == readOnly &&
      other.sortOrder == sortOrder;

  @override
  int get hashCode => Object.hash(
      id, sourceId, remoteId, name, color, visible, readOnly, sortOrder);
}

/// A stored event. For recurring events this is the "master" event; the
/// occurrences are computed with the recurrence expander.
///
/// Time conventions:
/// * timed events: [start]/[end] are absolute instants (local DateTime).
/// * all-day events: [start]/[end] are local midnights, [end] exclusive
///   (an event on the 6th has start=6th 00:00 and end=7th 00:00).
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.calendarId,
    required this.title,
    required this.start,
    required this.end,
    this.allDay = false,
    this.description,
    this.location,
    this.timeZone,
    this.rrule,
    this.exdates = const [],
    this.color,
    this.remoteId,
    this.recurringRemoteId,
    this.updatedAt,
  });

  final String id;
  final String calendarId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? description;
  final String? location;

  /// IANA time zone the recurrence is computed in (e.g. "Europe/Paris").
  final String? timeZone;

  /// RFC 5545 recurrence rule without the "RRULE:" prefix,
  /// e.g. `FREQ=WEEKLY;BYDAY=MO,WE`.
  final String? rrule;

  /// Start of the occurrences removed from the recurrence.
  final List<DateTime> exdates;

  /// Event-specific color overriding the calendar color.
  final Color? color;

  /// Id on the remote service (Google event id or iCal UID).
  final String? remoteId;

  /// For an instance of a Google recurring event: the id of the series.
  final String? recurringRemoteId;
  final DateTime? updatedAt;

  bool get isRecurring => rrule != null && rrule!.isNotEmpty;

  /// True when the event is part of a series (local rule or Google series).
  bool get isPartOfSeries => isRecurring || recurringRemoteId != null;

  Duration get duration => end.difference(start);

  CalendarEvent copyWith({
    String? id,
    String? calendarId,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? description,
    String? location,
    String? timeZone,
    String? rrule,
    bool clearRrule = false,
    List<DateTime>? exdates,
    Color? color,
    bool clearColor = false,
    String? remoteId,
    String? recurringRemoteId,
    bool clearRecurringRemoteId = false,
    DateTime? updatedAt,
  }) =>
      CalendarEvent(
        id: id ?? this.id,
        calendarId: calendarId ?? this.calendarId,
        title: title ?? this.title,
        start: start ?? this.start,
        end: end ?? this.end,
        allDay: allDay ?? this.allDay,
        description: description ?? this.description,
        location: location ?? this.location,
        timeZone: timeZone ?? this.timeZone,
        rrule: clearRrule ? null : (rrule ?? this.rrule),
        exdates: exdates ?? this.exdates,
        color: clearColor ? null : (color ?? this.color),
        remoteId: remoteId ?? this.remoteId,
        recurringRemoteId: clearRecurringRemoteId
            ? null
            : (recurringRemoteId ?? this.recurringRemoteId),
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// One concrete occurrence of an event, ready to be displayed.
class EventOccurrence {
  const EventOccurrence({
    required this.event,
    required this.start,
    required this.end,
    required this.color,
  });

  final CalendarEvent event;
  final DateTime start;
  final DateTime end;

  /// Resolved display color (event color or calendar color).
  final Color color;

  bool get allDay => event.allDay;
  String get title => event.title;

  /// True when the occurrence spans several days (or is all-day). Such events
  /// are shown as bars in the all-day area / month view.
  bool get isMultiDayOrAllDay {
    if (allDay) return true;
    final s = DateTime(start.year, start.month, start.day);
    final lastInstant = end.subtract(const Duration(microseconds: 1));
    final e = DateTime(lastInstant.year, lastInstant.month, lastInstant.day);
    return end.isAfter(start) && e.isAfter(s);
  }

  /// Stable key identifying this occurrence (event id + start).
  String get key => '${event.id}@${start.millisecondsSinceEpoch}';

  @override
  bool operator ==(Object other) =>
      other is EventOccurrence &&
      other.event.id == event.id &&
      other.start == start &&
      other.end == end &&
      other.color == color &&
      other.event.title == event.title &&
      other.event.updatedAt == event.updatedAt;

  @override
  int get hashCode => Object.hash(event.id, start, end, color);
}
