import 'package:flutter/material.dart';

import '../domain/models.dart';
import 'event/event_details_screen.dart';
import 'event/event_editor_screen.dart';

Future<void> openEventDetails(BuildContext context, EventOccurrence occurrence) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EventDetailsScreen(occurrence: occurrence),
    ));

Future<void> openEventEditor(
  BuildContext context, {
  EventOccurrence? occurrence,
  DateTime? start,
  bool allDay = false,
}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => EventEditorScreen(
        occurrence: occurrence,
        initialStart: start,
        initialAllDay: allDay,
      ),
    ));
