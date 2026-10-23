import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/media.dart';
import '../data/obf.dart';
import '../data/store.dart';
import '../domain/models.dart';
import '../domain/services.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this.store,
    required this.media,
    required this.speech,
    required this.audio,
    required this.device,
  });
  final Store store;
  final MediaStore media;
  final SpeechService speech;
  final AudioService audio;
  final DeviceLockService device;
  final message = MessageBuilder();
  List<Board> boards = [];
  List<Cell> cells = [];
  AppSettings settings = const AppSettings(userMode: false, homeBoard: '');
  BoardNavigator? navigator;
  bool visible = true;
  Board get board => boards.firstWhere((b) => b.id == navigator!.current);
  List<Cell> get boardCells =>
      cells.where((c) => c.boardId == board.id).toList();
  Future<void> load() async {
    settings = await store.settings();
    boards = await store.boards();
    cells = await store.cells();
    navigator ??= BoardNavigator(settings.homeBoard);
    if (!boards.any((b) => b.id == navigator!.current)) {
      navigator!.home(settings.homeBoard);
    }
    notifyListeners();
    await updateScreen();
  }

  Future<void> updateScreen() =>
      device.keepScreenOn(settings.userMode && visible);
  Future<void> visibility(bool value) async {
    visible = value;
    await updateScreen();
    if (!value) {
      await speech.stop();
      await audio.stop();
    }
  }

  Future<void> activate(Cell cell) async {
    final dispatcher = ActionDispatcher(
      speech: speech,
      audio: audio,
      message: message,
      navigate: open,
      audioPath: media.path,
    );
    await dispatcher.activate(cell);
    notifyListeners();
  }

  void open(String id) {
    if (!boards.any((b) => b.id == id)) {
      throw StateError('Den länkade brädan saknas.');
    }
    navigator!.open(id);
    notifyListeners();
  }

  void home() {
    navigator!.home(settings.homeBoard);
    notifyListeners();
  }

  void back() {
    navigator!.back();
    notifyListeners();
  }

  void undo() {
    message.undo();
    notifyListeners();
  }

  void clear() {
    message.clear();
    notifyListeners();
  }

  Future<void> lock() async {
    await store.lock();
    await load();
    home();
  }

  Future<bool> unlock(String pin) async {
    final ok = await store.unlock(pin);
    if (ok) await load();
    return ok;
  }

  Future<List<String>> importFile(Uint8List bytes, bool zipped) async {
    await store.requireAdmin();
    final bundle = await compute(_parseImport, (bytes, zipped));
    // Validated resources are content-addressed, never overwrite existing media.
    final mapped = <String, String>{};
    for (final entry in bundle.media.entries) {
      mapped[entry.key] = await media.save(
        entry.value,
        MediaStore.typeForName(entry.key),
      );
    }
    final updated = [
      for (final c in bundle.cells)
        Cell(
          id: c.id,
          boardId: c.boardId,
          row: c.row,
          column: c.column,
          text: c.text,
          action: c.action,
          image: mapped[c.image],
          audio: mapped[c.audio],
          target: c.target,
          color: c.color,
          vocalization: c.vocalization,
          metadata: c.metadata,
        ),
    ];
    await store.importBundle(BoardBundle(bundle.boards, updated, bundle.root));
    await load();
    open(bundle.root);
    return bundle.warnings;
  }

  Future<Uint8List> export({bool single = false}) async {
    await store.requireAdmin();
    final bytes = await ObfCodec.encode(
      BoardBundle(boards, cells, settings.homeBoard),
      media,
      singleBoard: single ? board.id : null,
    );
    // A backup must also fit our importer, including expanded-media limits.
    await compute(_parseImport, (bytes, !single));
    return bytes;
  }

  Future<String> importImage(String path) async {
    await store.requireAdmin();
    final file = File(path);
    if (await file.length() > MediaStore.maxFile) {
      throw const FormatException('Bilden är större än 10 MB.');
    }
    final bytes = await file.readAsBytes();
    final type = MediaStore.imageType(bytes);
    if (type == null) throw const FormatException('Välj PNG, JPEG eller WebP.');
    return media.save(bytes, type);
  }
}

BoardBundle _parseImport((Uint8List, bool) input) =>
    ObfCodec.decode(input.$1, zipped: input.$2);
