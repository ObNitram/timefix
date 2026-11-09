import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../navigation.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Searches events by title, location or description.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<EventOccurrence>? _results;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _search(query));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _results = null);
      return;
    }
    final calendars = await ref.read(calendarsProvider.future);
    final visible = {for (final c in calendars) if (c.visible) c.id: c};
    final events =
        await ref.read(repositoryProvider).searchEvents(query, visible.keys.toSet());
    final now = DateTime.now();
    final results = <EventOccurrence>[];
    for (final e in events) {
      final cal = visible[e.calendarId];
      if (cal == null) continue;
      var start = e.start, end = e.end;
      if (e.isRecurring) {
        // Show the next occurrence (or the first one if the series is over).
        final next = expandEvents(
            [e], visible, DateRange(dateOnly(now), addDays(dateOnly(now), 366)));
        if (next.isNotEmpty) {
          start = next.first.start;
          end = next.first.end;
        }
      }
      results.add(EventOccurrence(event: e, start: start, end: end, color: e.color ?? cal.color));
    }
    results.sort(compareOccurrences);
    if (mounted && _controller.text == query) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: _search,
          decoration: InputDecoration(hintText: l10n.searchHint, border: InputBorder.none),
        ),
      ),
      body: results == null
          ? const SizedBox.shrink()
          : results.isEmpty
              ? Center(
                  child: Text(l10n.noResults,
                      style: TextStyle(color: Theme.of(context).colorScheme.mutedText)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: results.length,
                  itemBuilder: (context, i) {
                    final o = results[i];
                    final showDate = i == 0 || !isSameDay(results[i - 1].start, o.start);
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (showDate)
                          Padding(
                            padding: const EdgeInsets.only(top: 12, bottom: 6),
                            child: Text(formatLongDate(context, o.start),
                                style: Theme.of(context).textTheme.titleSmall),
                          ),
                        EventCard(occurrence: o, onTap: () => openEventDetails(context, o)),
                      ],
                    );
                  },
                ),
    );
  }
}
