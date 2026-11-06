import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/date_utils.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../format.dart';
import '../navigation.dart';
import '../search/search_screen.dart';
import '../views/month/month_view.dart';
import '../views/schedule/schedule_view.dart';
import '../views/week/week_view.dart';
import 'app_drawer.dart';
import 'mini_month.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _miniCalendarOpen = false;

  void _jumpTo(DateTime date) {
    setState(() => _miniCalendarOpen = false);
    ref.read(jumpProvider.notifier).jumpTo(date);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final viewMode = ref.watch(settingsProvider.select((s) => s.viewMode));
    final focused = ref.watch(focusedDateProvider);
    final syncing = ref.watch(syncControllerProvider.select((s) => s.running));
    final scheme = Theme.of(context).colorScheme;

    ref.listen(syncControllerProvider, (prev, next) {
      final report = next.lastReport;
      if (prev?.running == true && !next.running && report != null && report.hasErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.syncFailed(report.errors.length))),
        );
      }
    });

    final Widget view = switch (viewMode) {
      CalendarViewMode.schedule => const ScheduleView(key: ValueKey('schedule')),
      CalendarViewMode.week => const WeekView(key: ValueKey('week')),
      CalendarViewMode.month => const MonthView(key: ValueKey('month')),
    };

    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        titleSpacing: 0,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: l10n.openMenu,
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _miniCalendarOpen = !_miniCalendarOpen),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    formatMonthTitle(context, focused),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AnimatedRotation(
                  turns: _miniCalendarOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.arrow_drop_down),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.search,
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SearchScreen())),
          ),
          IconButton(
            tooltip: l10n.goToToday,
            onPressed: () => _jumpTo(DateTime.now()),
            icon: _TodayIcon(day: DateTime.now().day),
          ),
          const SizedBox(width: 4),
        ],
        bottom: syncing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(minHeight: 2),
              )
            : null,
      ),
      body: Column(
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _miniCalendarOpen
                ? Material(
                    color: scheme.surface,
                    child: Column(
                      children: [
                        MiniMonthPicker(selected: focused, onSelected: _jumpTo),
                        const Divider(),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Expanded(child: view),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.newEvent,
        onPressed: () {
          final now = DateTime.now();
          final base = isSameDay(focused, now) ? now : DateTime(focused.year, focused.month, focused.day, 8);
          openEventEditor(context,
              start: DateTime(base.year, base.month, base.day, (base.hour + 1).clamp(0, 23)));
        },
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }
}

/// Calendar-shaped icon showing today's day number.
class _TodayIcon extends StatelessWidget {
  const _TodayIcon({required this.day});
  final int day;

  @override
  Widget build(BuildContext context) {
    final color = IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.calendar_today_outlined, color: color),
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Text(
              '$day',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    );
  }
}
