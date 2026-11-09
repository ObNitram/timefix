import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timefix/state/settings.dart';
import 'package:timefix/ui/views/month/month_view.dart';
import 'package:timefix/ui/views/week/week_view.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:timefix/core/date_utils.dart';
import 'package:timefix/state/providers.dart';
import 'package:timefix/ui/home/home_screen.dart';
import 'package:timefix/domain/models.dart';
import 'package:timefix/ui/home/mini_month.dart';

import '../helpers.dart';

String formatMonthTitleFr(DateTime d) {
  final pattern = d.year == DateTime.now().year ? DateFormat.MMMM('fr') : DateFormat.yMMMM('fr');
  final s = pattern.format(d);
  return s[0].toUpperCase() + s.substring(1);
}

void main() {
  setUp(() {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.platformDispatcher.localesTestValue = const [Locale('fr', 'FR')];
  });

  Future<void> setPhoneSize(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
  }

  testWidgets('schedule view shows today events', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    expect(find.text('Réunion d\'équipe'), findsOneWidget);
    expect(find.text('Déjeuner avec Paul'), findsOneWidget);
    expect(find.text('Course à pied'), findsWidgets);

    // The schedule scrolled to today, and the focused date follows it (it
    // used to be computed from stale positions, giving the week's Monday).
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    expect(container.read(focusedDateProvider), dateOnly(DateTime.now()));
  });

  testWidgets('drawer switches between the three views', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semaine'));
    await tester.pumpAndSettle();
    expect(find.byType(WeekView), findsOneWidget);
    expect(find.text('Réunion d\'équipe'), findsOneWidget);

    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mois'));
    await tester.pumpAndSettle();
    expect(find.byType(MonthView), findsOneWidget);
    expect(find.text('Vacances'), findsWidgets);
  });

  testWidgets('week view: zooming out on a tall screen keeps working', (tester) async {
    tester.view.physicalSize = const Size(1024, 1800); // tablet, the whole day fits
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Semaine'));
    await tester.pumpAndSettle();

    final grid = tester.getCenter(find.descendant(
        of: find.byType(WeekView), matching: find.byType(SingleChildScrollView)).first);
    final a = await tester.startGesture(grid - const Offset(0, 150));
    final b = await tester.startGesture(grid + const Offset(0, 150));
    for (var i = 0; i < 5; i++) {
      await a.moveBy(const Offset(0, 25));
      await b.moveBy(const Offset(0, -25));
      await tester.pump();
    }
    await a.up();
    await b.up();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(WeekView), findsOneWidget);
  });

  testWidgets('editor: a text-only change asks before closing', (tester) async {
    await setPhoneSize(tester);
    await tester.pumpWidget(await buildTestApp(repository: await seededRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Réunion d\'équipe'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Modifier'));
    await tester.pumpAndSettle();
    // Moving the cursor alone is not a change.
    await tester.tap(find.byType(TextField).first);
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, 'Réunion renommée');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Abandonner les modifications ?'), findsOneWidget);
  });

  testWidgets('month view: tapping a day opens the day sheet', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(
      repository: repo,
      prefs: {'viewMode': CalendarViewMode.month.index},
    ));
    await tester.pumpAndSettle();

    final today = DateTime.now();
    await tester.tap(find.text('${today.day}').first);
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(sheet, findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Réunion d\'équipe')), findsOneWidget);
    expect(find.descendant(of: sheet, matching: find.text('Déjeuner avec Paul')), findsOneWidget);
  });

  testWidgets('create an event with the editor', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Nouvel événement'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Dentiste');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing,
        reason: find.byType(SnackBar).evaluate().isEmpty
            ? null
            : (tester.widget<SnackBar>(find.byType(SnackBar)).content as Text).data);

    final events = await repo.searchEvents('Dentiste', {'local:default', 'local:sport'});
    expect(events, hasLength(1));
    expect(find.text('Dentiste'), findsOneWidget);
  });

  testWidgets('event details then delete', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Réunion d\'équipe'));
    await tester.pumpAndSettle();
    expect(find.text('Salle A'), findsOneWidget);
    expect(find.text('Mon calendrier'), findsOneWidget);

    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    expect(await repo.getEvent('1'), isNull);
    expect(find.text('Réunion d\'équipe'), findsNothing);
  });

  testWidgets('deleting one occurrence of a recurring event', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Course à pied').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Supprimer'));
    await tester.pumpAndSettle();
    expect(find.text('Supprimer l\'événement périodique'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Supprimer'));
    await tester.pumpAndSettle();

    final master = await repo.getEvent('3');
    expect(master, isNotNull);
    expect(master!.exdates, hasLength(1));
  });

  testWidgets('hiding a calendar from the drawer hides its events', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('Course à pied'), findsWidgets);

    await tester.tap(find.byTooltip('Ouvrir le menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sport'));
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('Sport'))).pop();
    await tester.pumpAndSettle();

    expect(find.text('Course à pied'), findsNothing);
  });

  testWidgets('mini calendar jumps to a date and today button comes back', (tester) async {
    await setPhoneSize(tester);
    final repo = await seededRepository();
    final now = DateTime.now();
    final target = DateTime(now.year, now.month + 2, 15);
    await repo.upsertEvent(CalendarEvent(
      id: 'far',
      calendarId: 'local:default',
      title: 'Événement lointain',
      start: DateTime(target.year, target.month, target.day, 10),
      end: DateTime(target.year, target.month, target.day, 11),
    ));
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('Événement lointain'), findsNothing);

    // Open the mini calendar and swipe two months ahead.
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await tester.pumpAndSettle();
    final picker = find.byType(MiniMonthPicker);
    for (var i = 0; i < 2; i++) {
      await tester.drag(picker, const Offset(-500, 0));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.descendant(of: picker, matching: find.text('15')).first);
    await tester.pumpAndSettle();
    expect(find.text('Événement lointain'), findsOneWidget);
    expect(find.text(formatMonthTitleFr(target)), findsOneWidget);

    await tester.tap(find.byTooltip('Aller à aujourd\'hui'));
    await tester.pumpAndSettle();
    expect(find.text('Réunion d\'équipe'), findsOneWidget);
  });

  testWidgets('english locale', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    await setPhoneSize(tester);
    final repo = await seededRepository();
    await tester.pumpWidget(await buildTestApp(repository: repo));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Open menu'));
    await tester.pumpAndSettle();
    expect(find.text('Schedule'), findsOneWidget);
    expect(find.text('Add calendar'), findsOneWidget);
  });
}
