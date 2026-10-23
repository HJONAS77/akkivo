import 'dart:io';

import 'package:akkivo/application/app_controller.dart';
import 'package:akkivo/data/media.dart';
import 'package:akkivo/data/pin.dart';
import 'package:akkivo/data/store.dart';
import 'package:akkivo/main.dart';
import 'package:akkivo/platform/android_services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Android SQLite, board actions, persisted lock and native wake lifecycle',
    (tester) async {
      Future<void> waitFor(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            fail('Android-flödet blev inte klart inom 20 sekunder.');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
      }

      final support = await getApplicationSupportDirectory();
      final directory = await Directory(
        p.join(
          support.path,
          'integration-${DateTime.now().microsecondsSinceEpoch}',
        ),
      ).create();
      final path = p.join(directory.path, 'integration.db');
      final opened = await Store.open(path);
      var store = Store(opened.db, hasher: const PinHasher(iterations: 1000));
      final platform = AndroidServices();
      AppController controller() => AppController(
        store: store,
        media: MediaStore(Directory(p.join(support.path, 'media'))),
        speech: platform,
        audio: platform,
        device: platform,
      );
      var c = controller();
      await c.load();
      await tester.pumpWidget(AkkivoApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Jag vill'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('vatten'));
      await tester.pumpAndSettle();
      expect(c.message.text, 'Jag vill vatten');
      await tester.tap(find.text('Känslor'));
      await tester.pumpAndSettle();
      expect(c.board.id, 'feelings');
      await tester.tap(find.byTooltip('Tillbaka'));
      await tester.pumpAndSettle();
      expect(c.board.id, 'home');
      await tester.tap(find.byTooltip('Administration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mina brädor'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Skapa bräda'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Min testbräda');
      await tester.tap(find.text('Spara'));
      await waitFor(
        () =>
            c.board.name == 'Min testbräda' &&
            find.byType(AlertDialog).evaluate().isEmpty,
      );
      final createdId = c.board.id;
      await tester.tap(find.widgetWithText(ListTile, 'Min testbräda'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Administration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Redigera celler'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'Testord');
      await tester.tap(find.text('Spara'));
      await waitFor(
        () =>
            c.cells.any((cell) => cell.text == 'Testord') &&
            find.byType(AlertDialog).evaluate().isEmpty,
      );
      await tester.tap(find.byTooltip('Administration'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Förhandsgranska'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Testord'));
      await tester.pumpAndSettle();
      expect(c.message.text, 'Jag vill vatten Testord');
      final exported = await c.export();
      await c.importFile(exported, true);
      expect(c.board.name, 'Min vardag');
      await store.setPin('1234');
      await c.lock();
      await tester.pumpAndSettle();
      expect(find.byTooltip('Administration'), findsNothing);
      await expectLater(store.deleteBoard(createdId), throwsStateError);
      expect(await c.unlock('9999'), false);
      await c.visibility(false);
      await c.visibility(true);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c.dispose();
      await store.db.close();
      final reopened = await Store.open(path);
      store = Store(reopened.db, hasher: const PinHasher(iterations: 1000));
      c = controller();
      await c.load();
      expect(c.settings.userMode, true);
      expect(c.board.id, 'home');
      await tester.pumpWidget(AkkivoApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Administration'), findsNothing);
      expect(await c.unlock('1234'), true);
      await tester.pumpAndSettle();
      expect(find.byTooltip('Administration'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      c.dispose();
      await store.db.close();
      await directory.delete(recursive: true);
    },
  );
}
