import 'package:flutter/material.dart';

import '../../data/event_service.dart';
import '../format.dart';

/// Asks which occurrences of a recurring event an action applies to.
Future<RecurrenceScope?> askRecurrenceScope(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  List<RecurrenceScope> options = RecurrenceScope.values,
}) {
  var selected = options.first;
  return showDialog<RecurrenceScope>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final l10n = context.l10n;
        String label(RecurrenceScope s) => switch (s) {
              RecurrenceScope.thisEvent => l10n.scopeThis,
              RecurrenceScope.thisAndFollowing => l10n.scopeFollowing,
              RecurrenceScope.all => l10n.scopeAll,
            };
        return AlertDialog(
          title: Text(title),
          contentPadding: const EdgeInsets.only(top: 12, bottom: 8),
          content: RadioGroup<RecurrenceScope>(
            groupValue: selected,
            onChanged: (v) => setState(() => selected = v!),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final o in options)
                  RadioListTile<RecurrenceScope>(value: o, title: Text(label(o))),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
            TextButton(
                onPressed: () => Navigator.pop(context, selected),
                child: Text(confirmLabel)),
          ],
        );
      },
    ),
  );
}
