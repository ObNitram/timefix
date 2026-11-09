import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../domain/models.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../calendars/add_calendar_screen.dart';
import '../format.dart';
import '../settings/settings_screen.dart';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final sources = ref.watch(sourcesProvider).value ?? const [];
    final calendars = ref.watch(calendarsProvider).value ?? const [];
    final syncing = ref.watch(syncControllerProvider).running;
    final scheme = Theme.of(context).colorScheme;

    return NavigationDrawer(
      selectedIndex: settings.viewMode.index,
      onDestinationSelected: (i) {
        ref.read(settingsProvider.notifier).setViewMode(CalendarViewMode.values[i]);
        Navigator.pop(context);
      },
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 16, 12),
          child: Row(
            children: [
              const _Logo(),
              const SizedBox(width: 12),
              Text(l10n.appTitle,
                  style: TextStyle(fontSize: 22, color: scheme.onSurface)),
            ],
          ),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.view_agenda_outlined),
          selectedIcon: const Icon(Icons.view_agenda),
          label: Text(l10n.viewSchedule),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.view_week_outlined),
          selectedIcon: const Icon(Icons.view_week),
          label: Text(l10n.viewWeek),
        ),
        NavigationDrawerDestination(
          icon: const Icon(Icons.calendar_view_month_outlined),
          selectedIcon: const Icon(Icons.calendar_view_month),
          label: Text(l10n.viewMonth),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Divider(),
        ),
        _DrawerTile(
          icon: Icons.refresh,
          label: l10n.refresh,
          trailing: syncing
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : null,
          onTap: () {
            Navigator.pop(context);
            ref.read(syncControllerProvider.notifier).syncAll(interactive: true);
          },
        ),
        for (final source in sources) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    source.type == SourceType.local ? l10n.sourceTypeLocal : source.name,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant),
                  ),
                ),
                if (source.lastError != null)
                  Tooltip(
                    message: source.lastError!,
                    child: Icon(Icons.sync_problem, size: 18, color: scheme.error),
                  ),
              ],
            ),
          ),
          for (final cal in calendars.where((c) => c.sourceId == source.id))
            _CalendarToggle(calendar: cal),
        ],
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          child: Divider(),
        ),
        _DrawerTile(
          icon: Icons.add,
          label: l10n.addCalendar,
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AddCalendarScreen()));
          },
        ),
        _DrawerTile(
          icon: Icons.settings_outlined,
          label: l10n.settings,
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context)
                .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
          },
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({required this.icon, required this.label, required this.onTap, this.trailing});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        shape: const StadiumBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        leading: Icon(icon),
        title: Text(label),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}

class _CalendarToggle extends ConsumerWidget {
  const _CalendarToggle({required this.calendar});
  final CalendarInfo calendar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> toggle() async {
      await ref
          .read(repositoryProvider)
          .upsertCalendar(calendar.copyWith(visible: !calendar.visible));
      ref.read(dataRevisionProvider.notifier).bump();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListTile(
        dense: true,
        shape: const StadiumBorder(),
        contentPadding: const EdgeInsets.only(left: 4, right: 16),
        horizontalTitleGap: 8,
        minLeadingWidth: 0,
        leading: Checkbox(
          value: calendar.visible,
          activeColor: calendar.color,
          side: BorderSide(color: calendar.color, width: 2),
          onChanged: (_) => toggle(),
        ),
        title: Text(calendar.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
        onTap: toggle,
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final day = DateTime.now().day;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: googleBlue, width: 2),
      ),
      alignment: Alignment.center,
      child: Text('$day',
          style: const TextStyle(color: googleBlue, fontWeight: FontWeight.w700, fontSize: 14)),
    );
  }
}
