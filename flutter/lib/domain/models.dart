import 'package:flutter/painting.dart';

import 'reminders.dart';

/// Where a group of calendars comes from.
enum SourceType {
  /// Stored only on the device. Fully editable.
  local,

  /// iCalendar (.ics) subscription by URL. Read only.
  ical,

  /// Google account, synced through the Google Calendar API.
  google,

  /// CalDAV account (TimeFix server, Nextcloud, Radicale, iCloud…). Read and
  /// write, the password lives in secure storage.
  caldav;

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
    this.username,
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

  /// Login for [SourceType.caldav] ([url] is then the calendar home URL).
  final String? username;
  final DateTime? lastSyncedAt;
  final String? lastError;

  bool get isRemote => type != SourceType.local;

  CalendarSource copyWith({
    String? name,
    String? url,
    String? accountEmail,
    String? username,
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
        username: username ?? this.username,
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
    this.syncToken,
  });

  final String id;
  final String sourceId;

  /// Identifier on the remote service (Google calendar id, CalDAV collection
  /// URL).
  final String? remoteId;
  final String name;
  final Color color;
  final bool visible;
  final bool readOnly;
  final int sortOrder;

  /// Last seen change marker (CalDAV getctag), to skip unchanged calendars.
  final String? syncToken;

  CalendarInfo copyWith({
    String? name,
    Color? color,
    bool? visible,
    bool? readOnly,
    int? sortOrder,
    String? syncToken,
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
        syncToken: syncToken ?? this.syncToken,
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
      other.sortOrder == sortOrder &&
      other.syncToken == syncToken;

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
    this.href,
    this.etag,
    this.recurrenceId,
    this.reminders = const [],
    this.extraAlarms = const [],
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

  /// CalDAV resource URL and its ETag. A resource holds a recurring event and
  /// its modified occurrences, which all share the same [href].
  final String? href;
  final String? etag;

  /// Set when this event replaces one occurrence of a series (iCalendar
  /// RECURRENCE-ID): original start of the replaced occurrence.
  final DateTime? recurrenceId;

  /// Reminders stored with the event (synced for CalDAV, local otherwise).
  /// Reminders on read-only events live in the repository's local reminders.
  final List<Reminder> reminders;

  /// VALARM blocks TimeFix cannot represent (e-mail alarms, absolute triggers
  /// on a series, more than 4 weeks…), kept verbatim so that rewriting a
  /// CalDAV resource does not delete them.
  final List<String> extraAlarms;
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
    String? href,
    String? etag,
    DateTime? recurrenceId,
    bool clearRecurrenceId = false,
    List<Reminder>? reminders,
    List<String>? extraAlarms,
    DateTime? updatedAt,
    /// Drops the link to the remote copy (remote ids, href, ETag,
    /// RECURRENCE-ID): the event is copied to another calendar.
    bool clearRemote = false,
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
        remoteId: remoteId ?? (clearRemote ? null : this.remoteId),
        recurringRemoteId: clearRecurringRemoteId || clearRemote
            ? null
            : (recurringRemoteId ?? this.recurringRemoteId),
        href: href ?? (clearRemote ? null : this.href),
        etag: etag ?? (clearRemote ? null : this.etag),
        recurrenceId:
            clearRecurrenceId || clearRemote ? null : (recurrenceId ?? this.recurrenceId),
        reminders: reminders ?? this.reminders,
        extraAlarms: extraAlarms ?? this.extraAlarms,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Key of the device-only reminders of an event. All instances of a Google
/// recurring series share the key of the series.
String localReminderKey(CalendarEvent e) => e.recurringRemoteId != null
    ? '${e.calendarId}|series|${e.recurringRemoteId}'
    : e.id;

/// Keys that may hold the device-only reminders of [e], most specific first:
/// the event itself (a Google instance edited alone, an iCal / CalDAV
/// modified occurrence), then its series.
List<String> deviceReminderKeys(CalendarEvent e) => [
      e.id,
      if (e.recurringRemoteId != null) '${e.calendarId}|series|${e.recurringRemoteId}',
      if (e.recurrenceId != null && e.remoteId != null) '${e.calendarId}|${e.remoteId}',
    ];

/// Device-only reminders of [e]: the first key that has an entry wins (an
/// empty entry means "none for this occurrence").
List<Reminder> deviceReminders(CalendarEvent e, Map<String, List<Reminder>> local) {
  for (final key in deviceReminderKeys(e)) {
    final list = local[key];
    if (list != null) return list;
  }
  return const [];
}

/// Reminders of an event: those stored with it plus the device-only ones.
List<Reminder> effectiveReminders(CalendarEvent e, Map<String, List<Reminder>> local) =>
    Reminder.normalize([...e.reminders, ...deviceReminders(e, local)]);

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
