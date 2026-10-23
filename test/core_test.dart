import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:akkivo/application/app_controller.dart';
import 'package:akkivo/data/media.dart';
import 'package:akkivo/data/obf.dart';
import 'package:akkivo/data/pin.dart';
import 'package:akkivo/data/store.dart';
import 'package:akkivo/domain/models.dart';
import 'package:akkivo/domain/services.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeDevice implements SpeechService, AudioService, DeviceLockService {
  String? spoken, played;
  bool awake = false;
  @override
  Future<void> speak(String text) async {
    spoken = text;
  }

  @override
  Future<void> play(String path) async {
    played = path;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> keepScreenOn(bool enabled) async {
    awake = enabled;
  }
}

Cell cell(CellAction action, {String? target, String? audio}) => Cell(
  id: 'c',
  boardId: 'home',
  row: 0,
  column: 0,
  text: 'Hej',
  action: action,
  target: target,
  audio: audio,
);
final png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
);
Uint8List zip(Map<String, List<int>> files) {
  // Build raw stored ZIP records: ZipEncoder sanitizes malicious filenames.
  final local = BytesBuilder(), central = BytesBuilder();
  void field(BytesBuilder b, int value, int size) {
    final d = ByteData(size);
    if (size == 2) {
      d.setUint16(0, value, Endian.little);
    } else {
      d.setUint32(0, value, Endian.little);
    }
    b.add(d.buffer.asUint8List());
  }

  for (final e in files.entries) {
    final name = utf8.encode(e.key),
        offset = local.length,
        crc = getCrc32(e.value);
    for (final v in [0x04034b50]) {
      field(local, v, 4);
    }
    for (final v in [20, 0, 0, 0, 0]) {
      field(local, v, 2);
    }
    for (final v in [crc, e.value.length, e.value.length]) {
      field(local, v, 4);
    }
    field(local, name.length, 2);
    field(local, 0, 2);
    local.add(name);
    local.add(e.value);
    field(central, 0x02014b50, 4);
    for (final v in [20, 20, 0, 0, 0, 0]) {
      field(central, v, 2);
    }
    for (final v in [crc, e.value.length, e.value.length]) {
      field(central, v, 4);
    }
    for (final v in [name.length, 0, 0, 0, 0]) {
      field(central, v, 2);
    }
    field(central, 0, 4);
    field(central, offset, 4);
    central.add(name);
  }
  final offset = local.length, length = central.length;
  local.add(central.takeBytes());
  field(local, 0x06054b50, 4);
  for (final v in [0, 0, files.length, files.length]) {
    field(local, v, 2);
  }
  field(local, length, 4);
  field(local, offset, 4);
  field(local, 0, 2);
  return local.takeBytes();
}

Map<String, dynamic> obf({String id = 'b'}) => {
  'format': 'open-board-0.1',
  'id': id,
  'name': 'Test',
  'grid': {
    'rows': 1,
    'columns': 2,
    'order': [
      ['c', null],
    ],
  },
  'buttons': [
    {'id': 'c', 'label': 'Hej'},
  ],
  'images': [],
};
Uint8List jsonBytes(Object o) => Uint8List.fromList(utf8.encode(jsonEncode(o)));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  test('Typed actions and ordered message segments', () async {
    final platform = FakeDevice(), message = MessageBuilder();
    String? target;
    final dispatcher = ActionDispatcher(
      speech: platform,
      audio: platform,
      message: message,
      navigate: (v) => target = v,
      audioPath: (v) => '/media/$v',
    );
    await dispatcher.activate(cell(CellAction.speak));
    expect(platform.spoken, 'Hej');
    await dispatcher.activate(cell(CellAction.addToMessage));
    await dispatcher.activate(cell(CellAction.addToMessage));
    expect(message.text, 'Hej Hej');
    expect(message.segments.first.cellId, 'c');
    message.undo();
    expect(message.text, 'Hej');
    message.clear();
    message.undo();
    expect(message.text, '');
    await dispatcher.activate(
      cell(CellAction.navigateToBoard, target: 'other'),
    );
    expect(target, 'other');
    await dispatcher.activate(cell(CellAction.playAudio, audio: 'sound.mp3'));
    expect(platform.played, '/media/sound.mp3');
    await expectLater(
      dispatcher.activate(cell(CellAction.playAudio)),
      throwsStateError,
    );
  });
  test('Navigation preserves history and resets at home', () {
    final n = BoardNavigator('home');
    n.open('b');
    n.open('c');
    n.back();
    expect(n.current, 'b');
    n.home('home');
    expect(n.canGoBack, false);
    n.back();
    expect(n.current, 'home');
  });
  test('PBKDF2 uses independent salts and verifies PINs', () async {
    const h = PinHasher(iterations: 1000);
    final a = await h.hash('1234'), b = await h.hash('1234');
    expect(a, isNot(b));
    expect(a, isNot(contains('1234')));
    expect(await h.verify('1234', a), true);
    expect(await h.verify('4321', a), false);
    await expectLater(h.hash('12'), throwsFormatException);
  });
  group('SQLite and protected mode', () {
    late Directory dir;
    late Store store;
    setUp(() async {
      dir = await Directory.systemTemp.createTemp('akkivo-test-');
      final opened = await Store.open(
        '${dir.path}/test.db',
        factory: databaseFactoryFfi,
      );
      store = Store(opened.db, hasher: const PinHasher(iterations: 1000));
    });
    tearDown(() async {
      await store.db.close();
      await dir.delete(recursive: true);
    });
    test(
      'Seed, cell move, occupied position and shrinking protection',
      () async {
        expect((await store.boards()).length, 2);
        await store.saveBoard(
          const Board(id: 'b', name: 'Board', rows: 2, columns: 2),
        );
        final c = Cell(
          id: 'x',
          boardId: 'b',
          row: 0,
          column: 0,
          text: 'Text',
          action: CellAction.speak,
        );
        await store.saveCell(c);
        await store.saveCell(c.moved(1, 1));
        expect(
          (await store.cells()).singleWhere((c) => c.boardId == 'b').row,
          1,
        );
        await expectLater(
          store.saveBoard(
            const Board(id: 'b', name: 'Board', rows: 1, columns: 1),
          ),
          throwsStateError,
        );
        await expectLater(
          store.saveCell(
            Cell(
              id: 'y',
              boardId: 'b',
              row: 1,
              column: 1,
              text: 'Y',
              action: CellAction.speak,
            ),
          ),
          throwsStateError,
        );
        await store.setHome('b');
        await expectLater(store.deleteBoard('b'), throwsStateError);
      },
    );
    test('Every administrative mutation is rejected while locked, including after reopen', () async {
      await store.setPin('1234');
      await store.lock();
      await expectLater(
        store.saveBoard(
          const Board(id: 'new', name: 'New', rows: 1, columns: 1),
        ),
        throwsStateError,
      );
      await expectLater(
        store.saveCell(cell(CellAction.speak)),
        throwsStateError,
      );
      await expectLater(
        store.deleteCell(cell(CellAction.speak)),
        throwsStateError,
      );
      await expectLater(store.deleteBoard('feelings'), throwsStateError);
      await expectLater(store.setHome('feelings'), throwsStateError);
      await expectLater(store.setPin('9999'), throwsStateError);
      await expectLater(
        store.importBundle(BoardBundle([], [], 'home')),
        throwsStateError,
      );
      expect(await store.unlock('0000'), false);
      expect((await store.settings()).userMode, true);
      await store.db.close();
      final reopened = await Store.open(
        '${dir.path}/test.db',
        factory: databaseFactoryFfi,
      );
      store = Store(reopened.db, hasher: const PinHasher(iterations: 1000));
      expect((await store.settings()).userMode, true);
      expect(await store.unlock('1234'), true);
      expect((await store.settings()).userMode, false);
    });
    test('Wrong PIN throttle persists across process restart', () async {
      await store.setPin('1234');
      await store.lock();
      for (var i = 0; i < 3; i++) {
        expect(await store.unlock('9999'), false);
      }
      await store.db.close();
      final reopened = await Store.open(
        '${dir.path}/test.db',
        factory: databaseFactoryFfi,
      );
      store = Store(reopened.db, hasher: const PinHasher(iterations: 1000));
      await expectLater(store.unlock('1234'), throwsStateError);
      final later = Store(
        store.db,
        hasher: const PinHasher(iterations: 1000),
        now: () => DateTime.now().add(const Duration(seconds: 10)),
      );
      expect(await later.unlock('1234'), true);
    });
    test(
      'Failed import transaction rolls back board and cell changes',
      () async {
        final old = (await store.boards()).first;
        await expectLater(
          store.importBundle(
            BoardBundle(
              [Board(id: old.id, name: 'Changed', rows: 1, columns: 1)],
              [cell(CellAction.speak), cell(CellAction.speak)],
              old.id,
            ),
          ),
          throwsA(anything),
        );
        expect((await store.boards()).first.name, old.name);
        expect((await store.cells()).length, 15);
      },
    );
    test('Screen awake follows protected mode and visibility; restart restores mode', () async {
      final platform = FakeDevice();
      final c = AppController(
        store: store,
        media: MediaStore(Directory('${dir.path}/media')),
        speech: platform,
        audio: platform,
        device: platform,
      );
      await c.load();
      expect(platform.awake, false);
      await store.setPin('1234');
      await c.lock();
      expect(platform.awake, true);
      await c.visibility(false);
      expect(platform.awake, false);
      await c.visibility(true);
      expect(platform.awake, true);
      expect(await c.unlock('1234'), true);
      expect(platform.awake, false);
      c.dispose();
    });
    test(
      'OBZ roundtrip preserves IDs, coordinates, images, audio and links',
      () async {
        final media = MediaStore(Directory('${dir.path}/media'));
        final name = await media.save(png, 'image/png');
        final audio = await media.save([
          82,
          73,
          70,
          70,
          0,
          0,
          0,
          0,
          87,
          65,
          86,
          69,
        ], 'audio/wav');
        final bundle = BoardBundle(
          const [
            Board(id: 'first', name: 'First', rows: 1, columns: 2),
            Board(id: 'second', name: 'Second', rows: 1, columns: 1),
          ],
          [
            Cell(
              id: 'photo',
              boardId: 'first',
              row: 0,
              column: 1,
              text: 'Hej',
              image: name,
              action: CellAction.addToMessage,
            ),
            const Cell(
              id: 'link',
              boardId: 'second',
              row: 0,
              column: 0,
              text: 'Hem',
              action: CellAction.navigateToBoard,
              target: 'first',
            ),
            Cell(
              id: 'sound',
              boardId: 'first',
              row: 0,
              column: 0,
              text: 'Ljud',
              action: CellAction.playAudio,
              audio: audio,
            ),
          ],
          'second',
        );
        final bytes = await ObfCodec.encode(bundle, media);
        final parsed = ObfCodec.decode(bytes, zipped: true);
        expect(parsed.root, 'second');
        expect(parsed.cells.singleWhere((c) => c.id == 'photo').column, 1);
        expect(
          parsed.cells.singleWhere((c) => c.id == 'photo').action,
          CellAction.addToMessage,
        );
        expect(parsed.cells.singleWhere((c) => c.id == 'link').target, 'first');
        expect(parsed.media.length, 2);
        final platform = FakeDevice();
        final c = AppController(
          store: store,
          media: media,
          speech: platform,
          audio: platform,
          device: platform,
        );
        await c.load();
        await c.importFile(bytes, true);
        await c.importFile(bytes, true);
        expect((await store.boards()).where((b) => b.id == 'first').length, 1);
        final photo = (await store.cells()).singleWhere((c) => c.id == 'photo');
        expect(await File(media.path(photo.image!)).readAsBytes(), png);
        c.dispose();
      },
    );
  });
  group('OBF validation', () {
    test('Independent standard OBF with null position and RGB color', () {
      final data = obf();
      (data['buttons'] as List).first['background_color'] =
          'rgba(0, 0, 0, 0.5)';
      final b = ObfCodec.decode(jsonBytes(data), zipped: false);
      expect(b.cells.single.column, 0);
      expect(b.cells.single.color, 0xff808080);
      expect(b.cells.single.action, CellAction.speak);
    });
    test(
      'Reject malformed JSON, bad dimensions, unknown grid IDs and actions',
      () {
        expect(
          () => ObfCodec.decode(Uint8List.fromList([123]), zipped: false),
          throwsFormatException,
        );
        for (final field in ['rows', 'columns']) {
          final d = obf();
          (d['grid'] as Map)[field] = 100;
          expect(
            () => ObfCodec.decode(jsonBytes(d), zipped: false),
            throwsFormatException,
          );
        }
        final d = obf();
        (d['buttons'] as List).first['action'] = ':clear';
        expect(
          () => ObfCodec.decode(jsonBytes(d), zipped: false),
          throwsFormatException,
        );
        final unknown = obf();
        (unknown['grid'] as Map)['order'] = [
          ['unknown', null],
        ];
        expect(
          () => ObfCodec.decode(jsonBytes(unknown), zipped: false),
          throwsFormatException,
        );
      },
    );
    test(
      'Reject traversal, absolute paths, backslashes and malformed manifests',
      () {
        for (final path in [
          '../bad.obf',
          '/bad.obf',
          'C:/bad.obf',
          'boards\\bad.obf',
          'boards/../bad.obf',
          'boards/%2e%2e/bad.obf',
        ]) {
          expect(
            () => ObfCodec.decode(zip({path: jsonBytes(obf())}), zipped: true),
            throwsFormatException,
          );
        }
        expect(
          () => ObfCodec.decode(
            zip({
              'a.obf': jsonBytes(obf()),
              'b.obf': jsonBytes(obf(id: 'other')),
            }),
            zipped: true,
          ),
          throwsFormatException,
        );
        expect(
          () => ObfCodec.decode(
            zip({
              'board.obf': jsonBytes(obf()),
              'manifest.json': jsonBytes({
                'format': 'open-board-0.1',
                'root': 'missing.obf',
                'paths': {
                  'boards': {'b': 'board.obf'},
                },
              }),
            }),
            zipped: true,
          ),
          throwsFormatException,
        );
      },
    );
    test('Reject ZIP bomb and missing media before writing boards', () {
      expect(
        () => ObfCodec.decode(
          zip({'large.bin': List.filled(11 * 1024 * 1024, 0)}),
          zipped: true,
        ),
        throwsFormatException,
      );
      final d = obf();
      d['images'] = [
        {'id': 'i', 'path': 'missing.png', 'content_type': 'image/png'},
      ];
      expect(
        () => ObfCodec.decode(jsonBytes(d), zipped: false),
        throwsFormatException,
      );
    });
    test('Reject duplicate paths and corrupted ZIP', () {
      expect(
        () => ObfCodec.decode(
          zip({'a.obf': jsonBytes(obf()), 'A.obf': jsonBytes(obf(id: 'a2'))}),
          zipped: true,
        ),
        throwsFormatException,
      );
      final data = zip({'board.obf': jsonBytes(obf())});
      data[35] ^= 255;
      expect(() => ObfCodec.decode(data, zipped: true), throwsFormatException);
    });
    test('Remote media becomes a warning and placeholder without a network request', () {
      final d = obf();
      d['images'] = [
        {'id': 'remote', 'url': 'https://example.com/photo.png'},
      ];
      (d['buttons'] as List).first['image_id'] = 'remote';
      final parsed = ObfCodec.decode(jsonBytes(d), zipped: false);
      expect(parsed.cells.single.image, isNull);
      expect(parsed.warnings, isNotEmpty);
    });
  });
}
