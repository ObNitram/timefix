import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../widgets/common.dart';

/// Manage one source: sync, remove, and edit its calendars (name, color).
class SourceScreen extends ConsumerWidget {
  const SourceScreen({super.key, required this.sourceId});

  final String sourceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final source = ref.watch(sourcesByIdProvider)[sourceId];
    final calendars = (ref.watch(calendarsProvider).value ?? const [])
        .where((c) => c.sourceId == sourceId)
        .toList();
    final syncing = ref.watch(syncControllerProvider).running;
    if (source == null) {
      return Scaffold(appBar: AppBar());
    }
    final isLocal = source.type == SourceType.local;

    Future<void> bump() async => ref.read(dataRevisionProvider.notifier).bump();

    return Scaffold(
      appBar: AppBar(
        title: Text(isLocal ? l10n.sourceTypeLocal : source.name),
        bottom: syncing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
        actions: [
          if (source.isRemote)
            IconButton(
              tooltip: l10n.syncNow,
              icon: const Icon(Icons.sync),
              onPressed: syncing
                  ? null
                  : () => runGuarded(context,
                      () => ref.read(syncControllerProvider.notifier).syncSource(source)),
            ),
        ],
      ),
      body: ListView(
        children: [
          if (source.url != null)
            ListTile(
              leading: const Icon(Icons.link),
              title: SelectableText(source.url!),
            ),
          if (source.lastError != null)
            ListTile(
              leading: Icon(Icons.sync_problem, color: Theme.of(context).colorScheme.error),
              title: Text(source.lastError!),
            ),
          for (final cal in calendars)
            ListTile(
              leading: GestureDetector(
                onTap: () async {
                  final r = await showColorPickerSheet(context, selected: cal.color);
                  if (r?.color == null) return;
                  await ref.read(repositoryProvider).upsertCalendar(cal.copyWith(color: r!.color));
                  await bump();
                },
                child: CircleAvatar(radius: 12, backgroundColor: cal.color),
              ),
              title: Text(cal.name),
              subtitle: cal.readOnly ? Text(l10n.readOnlyCalendar) : null,
              trailing: PopupMenuButton<String>(
                onSelected: (action) async {
                  switch (action) {
                    case 'rename':
                      final name = await _askName(context, cal.name);
                      if (name == null || name.isEmpty) return;
                      await ref.read(repositoryProvider).upsertCalendar(cal.copyWith(name: name));
                      await bump();
                    case 'color':
                      if (!context.mounted) return;
                      final r = await showColorPickerSheet(context, selected: cal.color);
                      if (r?.color == null) return;
                      await ref
                          .read(repositoryProvider)
                          .upsertCalendar(cal.copyWith(color: r!.color));
                      await bump();
                    case 'delete':
                      if (!context.mounted) return;
                      final ok = await confirmDialog(context,
                          title: l10n.deleteCalendar,
                          message: l10n.deleteCalendarConfirm(cal.name),
                          confirmLabel: l10n.delete);
                      if (!ok) return;
                      await ref.read(repositoryProvider).deleteCalendar(cal.id);
                      await bump();
                  }
                },
                itemBuilder: (context) => [
                  if (source.type != SourceType.google)
                    PopupMenuItem(value: 'rename', child: Text(l10n.rename)),
                  PopupMenuItem(value: 'color', child: Text(l10n.color)),
                  if (isLocal && calendars.length > 1)
                    PopupMenuItem(value: 'delete', child: Text(l10n.deleteCalendar)),
                ],
              ),
            ),
          if (!isLocal) ...[
            const Divider(),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(l10n.removeSource,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () async {
                final ok = await confirmDialog(context,
                    title: l10n.removeSource,
                    message: l10n.removeSourceConfirm(source.name),
                    confirmLabel: l10n.delete);
                if (!ok) return;
                await ref.read(syncServiceProvider).removeSource(source);
                await bump();
                if (context.mounted) Navigator.pop(context);
              },
            ),
          ],
        ],
      ),
    );
  }

  static Future<String?> _askName(BuildContext context, String current) {
    final controller = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.rename),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(context.l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: Text(context.l10n.ok)),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
