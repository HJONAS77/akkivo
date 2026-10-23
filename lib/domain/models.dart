import 'dart:math';

String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

enum CellAction { speak, addToMessage, navigateToBoard, playAudio }

class Board {
  const Board({
    required this.id,
    required this.name,
    required this.rows,
    required this.columns,
    this.metadata = const {},
  });
  final String id, name;
  final int rows, columns;
  final Map<String, dynamic> metadata;
  void validate() {
    if (id.isEmpty ||
        name.trim().isEmpty ||
        name.length > 200 ||
        rows < 1 ||
        rows > 10 ||
        columns < 1 ||
        columns > 10) {
      throw const FormatException(
        'Brädan behöver ett namn och 1–10 rader och kolumner.',
      );
    }
  }
}

class Cell {
  const Cell({
    required this.id,
    required this.boardId,
    required this.row,
    required this.column,
    required this.text,
    required this.action,
    this.image,
    this.audio,
    this.target,
    this.color = 0xffe7f0ec,
    this.vocalization,
    this.metadata = const {},
  });
  final String id, boardId, text;
  final int row, column, color;
  final CellAction action;
  final String? image, audio, target, vocalization;
  final Map<String, dynamic> metadata;
  String get spokenText => vocalization ?? text;
  Cell moved(int r, int c) => Cell(
    id: id,
    boardId: boardId,
    row: r,
    column: c,
    text: text,
    action: action,
    image: image,
    audio: audio,
    target: target,
    color: color,
    vocalization: vocalization,
    metadata: metadata,
  );
}

class MessageSegment {
  const MessageSegment(this.text, this.cellId);
  final String text;
  final String? cellId;
}

class MessageBuilder {
  final List<MessageSegment> _segments = [];
  List<MessageSegment> get segments => List.unmodifiable(_segments);
  String get text => _segments.map((s) => s.text).join(' ');
  void add(Cell cell) {
    if (cell.spokenText.trim().isNotEmpty) {
      _segments.add(MessageSegment(cell.spokenText, cell.id));
    }
  }

  void undo() {
    if (_segments.isNotEmpty) _segments.removeLast();
  }

  void clear() => _segments.clear();
}

class AppSettings {
  const AppSettings({required this.userMode, required this.homeBoard});
  final bool userMode;
  final String homeBoard;
}

class BoardBundle {
  const BoardBundle(
    this.boards,
    this.cells,
    this.root, {
    this.media = const {},
    this.warnings = const [],
  });
  final List<Board> boards;
  final List<Cell> cells;
  final String root;
  final Map<String, List<int>> media;
  final List<String> warnings;
}
