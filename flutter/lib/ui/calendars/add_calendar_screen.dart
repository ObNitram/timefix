import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/colors.dart';
import '../../data/ical/ical_service.dart';
import '../../state/providers.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Lets the user pick which kind of calendar source to add.
class AddCalendarScreen extends ConsumerStatefulWidget {
  const AddCalendarScreen({super.key});

  @override
  ConsumerState<AddCalendarScreen> createState() => _AddCalendarScreenState();
}

class _AddCalendarScreenState extends ConsumerState<AddCalendarScreen> {
  bool _busy = false;

  Future<void> _addGoogle() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await ref.read(syncServiceProvider).addGoogleAccount();
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      showSnack(context, l10n.calendarAdded);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) showSnack(context, l10n.googleError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addLocal() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _LocalCalendarDialog(),
    );
    if (created == true && mounted) {
      showSnack(context, context.l10n.calendarAdded);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.addCalendar),
        bottom: _busy
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
            : null,
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.link)),
              title: Text(l10n.sourceIcal),
              subtitle: Text(l10n.sourceIcalSubtitle),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const IcalSubscriptionScreen(),
              )),
            ),
            ListTile(
              leading: const CircleAvatar(child: Text('G', style: TextStyle(fontWeight: FontWeight.bold))),
              title: Text(l10n.sourceGoogle),
              subtitle: Text(l10n.sourceGoogleSubtitle),
              onTap: _addGoogle,
            ),
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.phone_android)),
              title: Text(l10n.sourceLocal),
              subtitle: Text(l10n.sourceLocalSubtitle),
              onTap: _addLocal,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(72, 16, 16, 16),
              child: Text(l10n.googleSingleAccountNote,
                  style: TextStyle(fontSize: 12, color: scheme.mutedText)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocalCalendarDialog extends ConsumerStatefulWidget {
  const _LocalCalendarDialog();

  @override
  ConsumerState<_LocalCalendarDialog> createState() => _LocalCalendarDialogState();
}

class _LocalCalendarDialogState extends ConsumerState<_LocalCalendarDialog> {
  final _name = TextEditingController();
  Color _color = calendarPalette[4].color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.sourceLocal),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: l10n.name),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            ColorSwatchRow(selected: _color, onSelected: (c) => setState(() => _color = c)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        TextButton(
          onPressed: _name.text.trim().isEmpty
              ? null
              : () async {
                  await ref.read(syncServiceProvider).addLocalCalendar(_name.text.trim(), _color);
                  ref.read(dataRevisionProvider.notifier).bump();
                  if (context.mounted) Navigator.pop(context, true);
                },
          child: Text(l10n.create),
        ),
      ],
    );
  }
}

/// Form to subscribe to an iCal (.ics / webcal) URL.
class IcalSubscriptionScreen extends ConsumerStatefulWidget {
  const IcalSubscriptionScreen({super.key});

  @override
  ConsumerState<IcalSubscriptionScreen> createState() => _IcalSubscriptionScreenState();
}

class _IcalSubscriptionScreenState extends ConsumerState<IcalSubscriptionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _name = TextEditingController();
  Color _color = calendarPalette[7].color;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = context.l10n;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(syncServiceProvider).addIcalSubscription(
            url: _url.text,
            name: _name.text,
            color: _color,
          );
      ref.read(dataRevisionProvider.notifier).bump();
      if (!mounted) return;
      showSnack(context, l10n.calendarAdded);
      Navigator.of(context)
        ..pop()
        ..pop();
    } on IcalFetchException catch (e) {
      setState(() => _error = l10n.icalError(e.message));
    } catch (e) {
      setState(() => _error = l10n.icalError('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.sourceIcal)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.icalUrl,
                hintText: l10n.icalUrlHint,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.link),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return l10n.requiredField;
                try {
                  IcalService.normalizeUrl(v);
                  return null;
                } catch (_) {
                  return l10n.invalidUrl;
                }
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                labelText: l10n.nameOptional,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.label_outline),
              ),
            ),
            const SizedBox(height: 24),
            Text(l10n.color, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            ColorSwatchRow(selected: _color, onSelected: (c) => setState(() => _color = c)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.add),
              label: Text(l10n.subscribe),
            ),
            const SizedBox(height: 12),
            Text(l10n.sourceIcalSubtitle,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.mutedText)),
          ],
        ),
      ),
    );
  }
}
