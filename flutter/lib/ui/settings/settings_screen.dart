import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/date_utils.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../calendars/add_calendar_screen.dart';
import '../format.dart';
import 'source_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final sources = ref.watch(sourcesProvider).value ?? const [];
    final calendars = ref.watch(calendarsProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;

    String weekdayLabel(int? wd) {
      if (wd == null) return l10n.localeDefault;
      // 2023-01-02 is a Monday.
      return capitalize(DateFormat.EEEE(context.localeName).format(DateTime(2023, 1, 1 + wd)));
    }

    String themeLabel(ThemeMode m) => switch (m) {
          ThemeMode.system => l10n.themeSystem,
          ThemeMode.light => l10n.themeLight,
          ThemeMode.dark => l10n.themeDark,
        };

    Future<T?> choose<T>(String title, List<T> values, T current, String Function(T) label) {
      return showDialog<T>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title),
          children: [
            for (final v in values)
              ListTile(
                leading: Icon(v == current ? Icons.radio_button_checked : Icons.radio_button_off,
                    color: v == current ? scheme.primary : null),
                title: Text(label(v)),
                onTap: () => Navigator.pop(context, v),
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        children: [
          _Header(l10n.general),
          ListTile(
            leading: const Icon(Icons.today_outlined),
            title: Text(l10n.firstDayOfWeek),
            subtitle: Text(weekdayLabel(settings.firstWeekday)),
            onTap: () async {
              // 0 stands for "locale default" in the dialog.
              final v = await choose<int>(
                l10n.firstDayOfWeek,
                const [0, DateTime.monday, DateTime.saturday, DateTime.sunday],
                settings.firstWeekday ?? 0,
                (v) => weekdayLabel(v == 0 ? null : v),
              );
              if (v != null) notifier.setFirstWeekday(v == 0 ? null : v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_outlined),
            title: Text(l10n.theme),
            subtitle: Text(themeLabel(settings.themeMode)),
            onTap: () async {
              final v = await choose(l10n.theme, ThemeMode.values, settings.themeMode, themeLabel);
              if (v != null) notifier.setThemeMode(v);
            },
          ),
          ListTile(
            leading: const Icon(Icons.timelapse),
            title: Text(l10n.defaultDuration),
            subtitle: Text(l10n.minutes(settings.defaultDurationMinutes)),
            onTap: () async {
              final v = await choose(l10n.defaultDuration, const [15, 30, 45, 60, 90, 120],
                  settings.defaultDurationMinutes, l10n.minutes);
              if (v != null) notifier.setDefaultDuration(v);
            },
          ),
          const Divider(),
          _Header(l10n.manageCalendars),
          for (final s in sources)
            ListTile(
              leading: Icon(switch (s.type) {
                SourceType.local => Icons.phone_android,
                SourceType.ical => Icons.link,
                SourceType.google => Icons.account_circle_outlined,
              }),
              title: Text(s.type == SourceType.local ? l10n.sourceTypeLocal : s.name),
              subtitle: Text(
                s.lastError != null
                    ? s.lastError!
                    : s.type == SourceType.local
                        ? '${calendars.where((c) => c.sourceId == s.id).length} × ${l10n.calendar.toLowerCase()}'
                        : s.lastSyncedAt == null
                            ? l10n.neverSynced
                            : l10n.lastSync(_formatSync(context, s.lastSyncedAt!)),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: s.lastError != null ? TextStyle(color: scheme.error) : null,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => SourceScreen(sourceId: s.id))),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: Text(l10n.addCalendar),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const AddCalendarScreen())),
          ),
          const Divider(),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: l10n.appTitle,
            applicationVersion: '1.0.0',
            child: Text(l10n.about),
          ),
        ],
      ),
    );
  }

  static String _formatSync(BuildContext context, DateTime d) {
    final time = formatTime(context, d);
    if (isSameDay(d, DateTime.now())) return time;
    return '${DateFormat.MMMd(context.localeName).format(d)} $time';
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: TextStyle(
              color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500)),
    );
  }
}
