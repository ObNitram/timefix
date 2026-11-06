import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'l10n/generated/app_localizations.dart';
import 'state/providers.dart';
import 'state/settings.dart';
import 'ui/home/home_screen.dart';
import 'ui/theme.dart';

class TimefixApp extends ConsumerWidget {
  const TimefixApp({super.key, this.syncOnStart = true});

  /// Disabled in widget tests.
  final bool syncOnStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(settingsProvider.select((s) => s.themeMode));
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: _Bootstrap(syncOnStart: syncOnStart, child: const HomeScreen()),
    );
  }
}

/// Creates the default local calendar on first launch (with a localized name)
/// and starts a background synchronisation of remote sources.
class _Bootstrap extends ConsumerStatefulWidget {
  const _Bootstrap({required this.child, required this.syncOnStart});

  final Widget child;
  final bool syncOnStart;

  @override
  ConsumerState<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends ConsumerState<_Bootstrap> with WidgetsBindingObserver {
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final name = AppLocalizations.of(context).myCalendar;
    Future(() async {
      await ref.read(syncServiceProvider).ensureLocalCalendar(name);
      ref.read(dataRevisionProvider.notifier).bump();
      if (widget.syncOnStart) {
        await ref.read(syncControllerProvider.notifier).syncAll();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh remote calendars when the app comes back to the foreground.
    if (state == AppLifecycleState.resumed && widget.syncOnStart) {
      ref.read(syncControllerProvider.notifier).syncAll();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
