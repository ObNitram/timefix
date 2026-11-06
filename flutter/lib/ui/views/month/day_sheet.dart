import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/date_utils.dart';
import '../../../state/providers.dart';
import '../../format.dart';
import '../../navigation.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Bottom sheet listing the events of one day.
Future<void> showDaySheet(BuildContext context, DateTime day) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, controller) => _DaySheetContent(day: day, controller: controller),
    ),
  );
}

class _DaySheetContent extends ConsumerWidget {
  const _DaySheetContent({required this.day, required this.controller});

  final DateTime day;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final occurrences = ref.watch(occurrencesProvider(dayRange(day))).value;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                formatLongDate(context, day),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            IconButton.filledTonal(
              tooltip: context.l10n.newEvent,
              onPressed: () {
                Navigator.pop(context);
                openEventEditor(context, start: DateTime(day.year, day.month, day.day, 9));
              },
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (occurrences == null)
          const Center(child: CircularProgressIndicator())
        else if (occurrences.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(context.l10n.noEvents,
                textAlign: TextAlign.center, style: TextStyle(color: scheme.mutedText)),
          )
        else
          for (final o in occurrences)
            EventCard(
              occurrence: o,
              day: day,
              onTap: () => openEventDetails(context, o),
            ),
      ],
    );
  }
}
