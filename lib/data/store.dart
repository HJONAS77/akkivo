import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import 'demo.dart';
import 'pin.dart';

class Store {
  Store(this.db, {this.hasher = const PinHasher(), DateTime Function()? now})
    : now = now ?? DateTime.now;
  final Database db;
  final PinHasher hasher;
  final DateTime Function() now;
  bool _unlocking = false;

  static Future<Store> open(String path, {DatabaseFactory? factory}) async {
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await db.execute(
            'CREATE TABLE boards(id TEXT PRIMARY KEY, name TEXT NOT NULL, rows INTEGER NOT NULL, columns INTEGER NOT NULL, metadata TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE cells(board_id TEXT NOT NULL REFERENCES boards(id) ON DELETE CASCADE, id TEXT NOT NULL, row INTEGER NOT NULL, col INTEGER NOT NULL, text TEXT NOT NULL, action TEXT NOT NULL, image TEXT, audio TEXT, target TEXT, color INTEGER NOT NULL, vocalization TEXT, metadata TEXT NOT NULL, PRIMARY KEY(board_id,id), UNIQUE(board_id,row,col))',
          );
          await db.execute(
            'CREATE TABLE settings(id INTEGER PRIMARY KEY CHECK(id=1), user_mode INTEGER NOT NULL, home TEXT NOT NULL REFERENCES boards(id))',
          );
          await db.execute(
            'CREATE TABLE secrets(id INTEGER PRIMARY KEY CHECK(id=1), verifier TEXT NOT NULL, failures INTEGER NOT NULL DEFAULT 0, blocked_until INTEGER NOT NULL DEFAULT 0)',
          );
          final demo = demoBoards();
          for (final b in demo.boards) {
            await db.insert('boards', boardRow(b));
          }
          for (final c in demo.cells) {
            await db.insert('cells', cellRow(c));
          }
          await db.insert('settings', {
            'id': 1,
            'user_mode': 0,
            'home': demo.root,
          });
        },
      ),
    );
    return Store(db);
  }

  static Map<String, Object?> boardRow(Board b) => {
    'id': b.id,
    'name': b.name,
    'rows': b.rows,
    'columns': b.columns,
    'metadata': jsonEncode(b.metadata),
  };
  static Map<String, Object?> cellRow(Cell c) => {
    'id': c.id,
    'board_id': c.boardId,
    'row': c.row,
    'col': c.column,
    'text': c.text,
    'action': c.action.name,
    'image': c.image,
    'audio': c.audio,
    'target': c.target,
    'color': c.color,
    'vocalization': c.vocalization,
    'metadata': jsonEncode(c.metadata),
  };
  Future<AppSettings> settings() async {
    final r = (await db.query('settings')).single;
    return AppSettings(
      userMode: r['user_mode'] == 1,
      homeBoard: r['home'] as String,
    );
  }

  Future<List<Board>> boards() async =>
      (await db.query('boards', orderBy: 'rowid'))
          .map(
            (r) => Board(
              id: r['id'] as String,
              name: r['name'] as String,
              rows: r['rows'] as int,
              columns: r['columns'] as int,
              metadata:
                  jsonDecode(r['metadata'] as String) as Map<String, dynamic>,
            ),
          )
          .toList();
  Future<List<Cell>> cells() async => (await db.query('cells'))
      .map(
        (r) => Cell(
          id: r['id'] as String,
          boardId: r['board_id'] as String,
          row: r['row'] as int,
          column: r['col'] as int,
          text: r['text'] as String,
          action: CellAction.values.byName(r['action'] as String),
          image: r['image'] as String?,
          audio: r['audio'] as String?,
          target: r['target'] as String?,
          color: r['color'] as int,
          vocalization: r['vocalization'] as String?,
          metadata: jsonDecode(r['metadata'] as String) as Map<String, dynamic>,
        ),
      )
      .toList();
  Future<void> _guard(DatabaseExecutor tx) async {
    if ((await tx.query('settings')).single['user_mode'] == 1) {
      throw StateError('Administration är låst i användarläget.');
    }
  }

  Future<void> requireAdmin() => _guard(db);
  Future<void> saveBoard(Board board) => db.transaction((tx) async {
    await _guard(tx);
    board.validate();
    final outside = await tx.query(
      'cells',
      where: 'board_id=? AND (row>=? OR col>=?)',
      whereArgs: [board.id, board.rows, board.columns],
    );
    if (outside.isNotEmpty) {
      throw StateError(
        'Flytta eller ta bort cellerna utanför det nya rutnätet först.',
      );
    }
    await tx.insert(
      'boards',
      boardRow(board),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    await tx.update(
      'boards',
      boardRow(board),
      where: 'id=?',
      whereArgs: [board.id],
    );
  });
  Future<void> saveCell(Cell c) => db.transaction((tx) async {
    await _guard(tx);
    final b = (await tx.query(
      'boards',
      where: 'id=?',
      whereArgs: [c.boardId],
    )).single;
    if (c.row < 0 ||
        c.column < 0 ||
        c.row >= (b['rows'] as int) ||
        c.column >= (b['columns'] as int) ||
        c.text.length > 2000) {
      throw const FormatException('Ogiltig cellposition eller för lång text.');
    }
    if (c.action == CellAction.navigateToBoard &&
        (await tx.query(
          'boards',
          where: 'id=?',
          whereArgs: [c.target],
        )).isEmpty) {
      throw StateError('Välj en befintlig målbräda.');
    }
    if (c.action == CellAction.playAudio && c.audio == null) {
      throw StateError('Välj en ljudfil.');
    }
    final occupied = await tx.query(
      'cells',
      where: 'board_id=? AND row=? AND col=? AND id<>?',
      whereArgs: [c.boardId, c.row, c.column, c.id],
    );
    if (occupied.isNotEmpty) {
      throw StateError('Positionen är upptagen. Välj en tom cell.');
    }
    await tx.delete(
      'cells',
      where: 'board_id=? AND id=?',
      whereArgs: [c.boardId, c.id],
    );
    await tx.insert('cells', cellRow(c));
  });
  Future<void> deleteCell(Cell c) => db.transaction((tx) async {
    await _guard(tx);
    await tx.delete(
      'cells',
      where: 'board_id=? AND id=?',
      whereArgs: [c.boardId, c.id],
    );
  });
  Future<void> deleteBoard(String id) => db.transaction((tx) async {
    await _guard(tx);
    if ((await tx.query('settings')).single['home'] == id) {
      throw StateError('Välj en annan startbräda innan du tar bort den här.');
    }
    if ((await tx.query(
      'cells',
      where: 'target=? AND board_id<>?',
      whereArgs: [id, id],
    )).isNotEmpty) {
      throw StateError('Ta bort länkarna till brädan först.');
    }
    await tx.delete('boards', where: 'id=?', whereArgs: [id]);
  });
  Future<void> setHome(String id) => db.transaction((tx) async {
    await _guard(tx);
    await tx.update('settings', {'home': id}, where: 'id=1');
  });
  Future<bool> hasPin() async => (await db.query('secrets')).isNotEmpty;
  Future<void> setPin(String pin) async {
    await requireAdmin();
    final verifier = await hasher.hash(pin);
    await db.transaction((tx) async {
      await _guard(tx);
      await tx.insert('secrets', {
        'id': 1,
        'verifier': verifier,
        'failures': 0,
        'blocked_until': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> lock() => db.transaction((tx) async {
    await _guard(tx);
    if ((await tx.query('secrets')).isEmpty) {
      throw StateError('Skapa en PIN-kod först.');
    }
    await tx.update('settings', {'user_mode': 1}, where: 'id=1');
  });
  Future<bool> unlock(String pin) async {
    if (_unlocking) throw StateError('Vänta medan PIN-koden kontrolleras.');
    _unlocking = true;
    try {
      final r = (await db.query('secrets')).single;
      final until = r['blocked_until'] as int;
      if (until > now().millisecondsSinceEpoch) {
        throw StateError(
          'För många försök. Försök igen om ${((until - now().millisecondsSinceEpoch) / 1000).ceil()} sekunder.',
        );
      }
      final ok = await hasher.verify(pin, r['verifier'] as String);
      await db.transaction((tx) async {
        final failures = ok ? 0 : (r['failures'] as int) + 1;
        final delay = failures < 3
            ? 0
            : (5 * (1 << (failures - 3).clamp(0, 6))).clamp(0, 300);
        await tx.update('secrets', {
          'failures': failures,
          'blocked_until': ok ? 0 : now().millisecondsSinceEpoch + delay * 1000,
        }, where: 'id=1');
        if (ok) await tx.update('settings', {'user_mode': 0}, where: 'id=1');
      });
      return ok;
    } finally {
      _unlocking = false;
    }
  }

  Future<void> importBundle(BoardBundle bundle) => db.transaction((tx) async {
    await _guard(tx);
    for (final b in bundle.boards) {
      b.validate();
      await tx.insert(
        'boards',
        boardRow(b),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await tx.update('boards', boardRow(b), where: 'id=?', whereArgs: [b.id]);
      await tx.delete('cells', where: 'board_id=?', whereArgs: [b.id]);
    }
    for (final c in bundle.cells) {
      await tx.insert('cells', cellRow(c));
    }
  });
}
