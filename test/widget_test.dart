import 'dart:io';

import 'package:akkivo/application/app_controller.dart';
import 'package:akkivo/data/media.dart';
import 'package:akkivo/data/pin.dart';
import 'package:akkivo/data/store.dart';
import 'package:akkivo/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core_test.dart' show FakeDevice;

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late Store store;
  late AppController c;
  late FakeDevice device;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('akkivo-ui-');
    final s = await Store.open(
      '${dir.path}/test.db',
      factory: databaseFactoryFfi,
    );
    store = Store(s.db, hasher: const PinHasher(iterations: 1000));
    device = FakeDevice();
    c = AppController(
      store: store,
      media: MediaStore(Directory('${dir.path}/media')),
      speech: device,
      audio: device,
      device: device,
    );
    await c.load();
  });
  tearDown(() async {
    c.dispose();
    await store.db.close();
    await dir.delete(recursive: true);
  });
  testWidgets('Build message, undo, clear, speech and board navigation', (
    tester,
  ) async {
    await tester.pumpWidget(AkkivoApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Jag vill'));
    await tester.pump();
    await tester.tap(find.text('vatten'));
    await tester.pump();
    expect(c.message.text, 'Jag vill vatten');
    await tester.tap(find.text('Läs upp'));
    await tester.pump();
    expect(device.spoken, 'Jag vill vatten');
    await tester.tap(find.byTooltip('Ta bort senaste ordet'));
    await tester.pump();
    expect(c.message.text, 'Jag vill');
    await tester.tap(find.text('Rensa'));
    await tester.pump();
    expect(c.message.text, '');
    await tester.tap(find.text('Känslor'));
    await tester.pumpAndSettle();
    expect(c.board.id, 'feelings');
    await tester.tap(find.byTooltip('Tillbaka'));
    await tester.pumpAndSettle();
    expect(c.board.id, 'home');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
  testWidgets(
    'Phone, tablet, landscape and large text retain positions without layout errors',
    (tester) async {
      for (final size in [
        const Size(360, 640),
        const Size(1024, 768),
        const Size(640, 360),
      ]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(size: size, textScaler: TextScaler.linear(2)),
            child: AkkivoApp(controller: c),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getTopLeft(find.text('Jag vill')).dx,
          lessThan(tester.getTopLeft(find.text('ha')).dx),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    },
  );
  testWidgets(
    'Protected mode hides administration and wrong PIN cannot unlock',
    (tester) async {
      await tester.runAsync(() async {
        await store.setPin('1234');
        await c.lock();
      });
      await tester.pumpWidget(AkkivoApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Administration'), findsNothing);
      await tester.tap(find.byTooltip('Öppna administration med PIN'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '0000');
      await tester.runAsync(() async {
        await tester.tap(find.text('Öppna'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(c.settings.userMode, true);
      await tester.enterText(find.byType(TextField), '1234');
      await tester.runAsync(() async {
        await tester.tap(find.text('Öppna'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();
      expect(c.settings.userMode, false);
      expect(find.byTooltip('Administration'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
