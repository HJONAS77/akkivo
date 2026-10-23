import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../domain/models.dart';
import 'media.dart';

// Parse everything before writing any boards. Archive paths are never extracted.
class ObfCodec {
  static const maxPackage = 30 * 1024 * 1024;
  static const maxExpanded = 60 * 1024 * 1024;
  static Map<String, dynamic> object(dynamic value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Förväntade ett JSON-objekt.');
    }
    return value;
  }

  static String string(dynamic value, {int max = 2000}) {
    if (value is! String || value.isEmpty || value.length > max) {
      throw const FormatException('Ogiltig eller för lång text i filen.');
    }
    return value;
  }

  static List<dynamic> list(dynamic value) {
    if (value is! List || value.length > 1000) {
      throw const FormatException('Ogiltig lista i filen.');
    }
    return value;
  }

  static void safePath(String value) {
    if (value.length > 240 ||
        value.contains('\\') ||
        value.contains(':') ||
        value.contains('%') ||
        value.startsWith('/') ||
        value.contains(RegExp(r'[\x00-\x1f]')) ||
        value.split('/').any((s) => s == '..' || s == '.' || s.isEmpty)) {
      throw const FormatException('Osäker sökväg i paketet.');
    }
  }

  static Map<String, dynamic> jsonObject(List<int> bytes) {
    if (bytes.length > 2 * 1024 * 1024) {
      throw const FormatException('JSON-filen är för stor.');
    }
    return object(jsonDecode(utf8.decode(bytes)));
  }

  static BoardBundle decode(Uint8List bytes, {required bool zipped}) {
    if (bytes.isEmpty || bytes.length > maxPackage) {
      throw const FormatException('Importen måste vara mindre än 30 MB.');
    }
    try {
      return _decode(bytes, zipped);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Filen är skadad eller har en struktur som inte stöds.',
      );
    }
  }

  static BoardBundle _decode(Uint8List bytes, bool zipped) {
    final files = <String, List<int>>{};
    final sources = <String, Map<String, dynamic>>{};
    String? rootPath;
    Map<String, dynamic>? boardPaths;
    if (zipped) {
      final directory = ZipDirectory()..read(InputMemoryStream(bytes));
      if (directory.fileHeaders.isEmpty || directory.fileHeaders.length > 500) {
        throw const FormatException(
          'Paketet är tomt eller innehåller för många filer.',
        );
      }
      var total = 0;
      final names = <String>{};
      for (final h in directory.fileHeaders) {
        final name = h.filename.endsWith('/')
            ? h.filename.substring(0, h.filename.length - 1)
            : h.filename;
        safePath(name);
        if (!names.add(name.toLowerCase()) ||
            h.generalPurposeBitFlag & 1 != 0 ||
            ((h.externalFileAttributes >> 16) & 0xf000) == 0xa000 ||
            h.uncompressedSize > MediaStore.maxFile ||
            h.uncompressedSize < 0 ||
            h.uncompressedSize > 200 * (h.compressedSize + 1)) {
          throw const FormatException(
            'Paketet innehåller dubbletter, kryptering, länkar eller för stora filer.',
          );
        }
        total += h.uncompressedSize;
        if (total > maxExpanded) {
          throw const FormatException('Det uppackade paketet är för stort.');
        }
      }
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive.files.where((f) => f.isFile)) {
        final data = f.readBytes()!;
        if (data.length != f.size || getCrc32(data) != f.crc32) {
          throw const FormatException('Paketets kontrollsumma är felaktig.');
        }
        files[f.name] = data;
      }
      if (files.containsKey('manifest.json')) {
        final manifest = jsonObject(files['manifest.json']!);
        if (manifest['format'] != 'open-board-0.1') {
          throw const FormatException('Okänd manifestversion.');
        }
        rootPath = string(manifest['root']);
        safePath(rootPath);
        final paths = object(manifest['paths']);
        boardPaths = object(paths['boards']);
        for (final category in paths.values) {
          for (final path in object(category).values) {
            safePath(string(path));
            if (!files.containsKey(path)) {
              throw const FormatException('En fil i manifestet saknas.');
            }
          }
        }
      }
      for (final f in files.entries.where((e) => e.key.endsWith('.obf'))) {
        sources[f.key] = jsonObject(f.value);
      }
      if (sources.length != 1 && rootPath == null) {
        throw const FormatException(
          'Manifest saknas för paket med flera brädor.',
        );
      }
      rootPath ??= sources.keys.first;
    } else {
      sources['board.obf'] = jsonObject(bytes);
      rootPath = 'board.obf';
    }
    if (sources.isEmpty ||
        sources.length > 100 ||
        !sources.containsKey(rootPath)) {
      throw const FormatException('Startbrädan saknas.');
    }
    final pathIds = <String, String>{};
    for (final entry in sources.entries) {
      final id = string(entry.value['id'], max: 200);
      if (pathIds.containsValue(id)) {
        throw const FormatException('Dubbla bräd-ID:n.');
      }
      pathIds[entry.key] = id;
    }
    if (boardPaths != null) {
      for (final entry in boardPaths.entries) {
        if (pathIds[entry.value] != entry.key) {
          throw const FormatException('Manifestets bräd-ID stämmer inte.');
        }
      }
      if (boardPaths.length != sources.length) {
        throw const FormatException('Manifestet saknar brädor.');
      }
    }
    final boards = <Board>[];
    final cells = <Cell>[];
    final media = <String, List<int>>{};
    final warnings = <String>{};
    var mediaTotal = 0;
    for (final source in sources.values) {
      if (source['format'] != 'open-board-0.1') {
        throw const FormatException('Endast open-board-0.1 stöds.');
      }
      final id = string(source['id'], max: 200);
      final grid = object(source['grid']);
      if (grid['rows'] is! int || grid['columns'] is! int) {
        throw const FormatException('Rutnätets storlek måste vara heltal.');
      }
      final board = Board(
        id: id,
        name: string(source['name'], max: 200),
        rows: grid['rows'] as int,
        columns: grid['columns'] as int,
        metadata: {
          if (source['license'] != null) 'license': object(source['license']),
          if (source['locale'] != null) 'locale': string(source['locale']),
        },
      );
      board.validate();
      boards.add(board);
      final resources = <String, String>{};
      final resourceMeta = <String, dynamic>{};
      final declaredResources = <String>{};
      for (final category in ['images', 'sounds']) {
        final seen = <String>{};
        for (final value in list(source[category] ?? [])) {
          final resource = object(value);
          final rid = string(resource['id'], max: 200);
          if (!seen.add(rid)) throw const FormatException('Dubbla media-ID:n.');
          declaredResources.add('$category/$rid');
          List<int>? data;
          String? type = resource['content_type'] as String?;
          if (resource['path'] != null) {
            final path = string(resource['path']);
            safePath(path);
            data = files[path];
            if (data == null) {
              throw const FormatException('Mediafil saknas i paketet.');
            }
            type ??= MediaStore.typeForName(path);
          } else if (resource['data'] != null) {
            final uri = UriData.parse(
              string(resource['data'], max: 15 * 1024 * 1024),
            );
            type ??= uri.mimeType;
            data = uri.contentAsBytes();
          } else {
            warnings.add(
              'Externa bilder, ljud och symbolbibliotek hämtas inte. Tomma platshållare används.',
            );
          }
          if (data != null) {
            if (data.isEmpty ||
                data.length > MediaStore.maxFile ||
                (category == 'images'
                    ? MediaStore.imageType(data) != type
                    : !MediaStore.audioTypes.containsKey(type))) {
              throw const FormatException(
                'Mediaformatet stöds inte eller är skadat.',
              );
            }
            mediaTotal += data.length;
            if (mediaTotal > maxExpanded) {
              throw const FormatException('För mycket inbäddad media.');
            }
            final ext = {
              ...MediaStore.imageTypes,
              ...MediaStore.audioTypes,
            }[type]!;
            final key = '${media.length}.$ext';
            media[key] = data;
            resources['$category/$rid'] = key;
            resourceMeta['$category/$rid'] = {
              if (resource['license'] != null)
                'license': object(resource['license']),
            };
          }
        }
      }
      final buttons = <String, Map<String, dynamic>>{};
      for (final raw in list(source['buttons'])) {
        final button = object(raw);
        final bid = string(button['id'], max: 200);
        if (buttons.containsKey(bid)) {
          throw const FormatException('Dubbla knapp-ID:n.');
        }
        buttons[bid] = button;
      }
      final order = list(grid['order']);
      if (order.length != board.rows) {
        throw const FormatException('Fel antal rader i rutnätet.');
      }
      final used = <String>{};
      for (var r = 0; r < board.rows; r++) {
        final row = list(order[r]);
        if (row.length != board.columns) {
          throw const FormatException('Fel antal kolumner i rutnätet.');
        }
        for (var c = 0; c < board.columns; c++) {
          if (row[c] == null) continue;
          final bid = string(row[c], max: 200);
          final button = buttons[bid];
          if (button == null || !used.add(bid)) {
            throw const FormatException(
              'Rutnätet har okända eller upprepade knapp-ID:n.',
            );
          }
          final text = button['label'] == null ? '' : button['label'] as String;
          if (text.length > 2000) {
            throw const FormatException('För lång celltext.');
          }
          for (final entry in {
            'image_id': 'images',
            'sound_id': 'sounds',
          }.entries) {
            if (button[entry.key] != null &&
                !declaredResources.contains(
                  '${entry.value}/${string(button[entry.key], max: 200)}',
                )) {
              throw const FormatException(
                'Cellen hänvisar till ett okänt media-ID.',
              );
            }
          }
          if (button['action'] != null || button['actions'] != null) {
            throw const FormatException(
              'Paketet innehåller specialåtgärder som denna MVP inte stöder.',
            );
          }
          final image = resources['images/${button['image_id']}'];
          final sound = resources['sounds/${button['sound_id']}'];
          var action = sound != null ? CellAction.playAudio : CellAction.speak;
          String? target;
          if (button['load_board'] != null) {
            final link = object(button['load_board']);
            if (link['path'] != null) {
              safePath(string(link['path']));
              target = pathIds[link['path']];
              if (target == null ||
                  (link['id'] != null && link['id'] != target)) {
                throw const FormatException(
                  'Brädlänkens sökväg och ID stämmer inte.',
                );
              }
            }
            target ??= link['id'] as String?;
            if (target == null || !pathIds.containsValue(target)) {
              throw const FormatException(
                'Länk till en bräda utanför importen stöds inte. Använd OBZ.',
              );
            }
            action = CellAction.navigateToBoard;
          } else if (button['ext_akkivo_action'] == 'addToMessage') {
            action = CellAction.addToMessage;
          } else if (button['action'] != null || button['actions'] != null) {
            throw const FormatException(
              'Paketet innehåller specialåtgärder som denna MVP inte stöder.',
            );
          }
          cells.add(
            Cell(
              id: bid,
              boardId: id,
              row: r,
              column: c,
              text: text,
              action: action,
              target: target,
              image: image,
              audio: sound,
              color: _color(button['background_color']),
              vocalization: button['vocalization'] == null
                  ? null
                  : string(button['vocalization']),
              metadata: {
                'image': resourceMeta['images/${button['image_id']}'],
                'audio': resourceMeta['sounds/${button['sound_id']}'],
              },
            ),
          );
        }
      }
    }
    return BoardBundle(
      boards,
      cells,
      pathIds[rootPath]!,
      media: media,
      warnings: warnings.toList(),
    );
  }

  static int _color(dynamic value) {
    if (value == null) return 0xffe7f0ec;
    final match = RegExp(
      r'^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)(?:\s*,\s*([\d.]+))?\s*\)$',
    ).firstMatch(value as String);
    if (match == null) return 0xffe7f0ec;
    final rgb = [for (var i = 1; i <= 3; i++) int.parse(match.group(i)!)];
    if (rgb.any((v) => v > 255)) throw const FormatException('Ogiltig färg.');
    final alpha = double.parse(match.group(4) ?? '1');
    if (alpha < 0 || alpha > 1) throw const FormatException('Ogiltig färg.');
    final blended = rgb
        .map((v) => (v * alpha + 255 * (1 - alpha)).round())
        .toList();
    return 0xff000000 | blended[0] << 16 | blended[1] << 8 | blended[2];
  }

  static Future<Uint8List> encode(
    BoardBundle bundle,
    MediaStore media, {
    String? singleBoard,
  }) async {
    final archive = Archive();
    final paths = <String, String>{
      for (final b in bundle.boards)
        b.id: 'boards/${bundle.boards.indexOf(b)}.obf',
    };
    final imagePaths = <String, String>{}, soundPaths = <String, String>{};
    void add(String name, List<int> bytes) =>
        archive.add(ArchiveFile(name, bytes.length, bytes));
    for (final b in bundle.boards.where(
      (b) => singleBoard == null || b.id == singleBoard,
    )) {
      final cells = bundle.cells.where((c) => c.boardId == b.id).toList();
      if (singleBoard != null &&
          cells.any((c) => c.action == CellAction.navigateToBoard)) {
        throw StateError(
          'Den här brädan har länkar. Exportera OBZ för att bevara dem.',
        );
      }
      final images = <Map<String, dynamic>>[],
          sounds = <Map<String, dynamic>>[];
      for (final c in cells) {
        for (final isImage in [true, false]) {
          final name = isImage ? c.image : c.audio;
          if (name == null) continue;
          final bytes = await File(media.path(name)).readAsBytes();
          final type = MediaStore.typeForName(name);
          final path = '${isImage ? 'images' : 'sounds'}/$name';
          final meta = c.metadata[isImage ? 'image' : 'audio'];
          final resource = <String, dynamic>{
            'id': name,
            'content_type': type,
            if (meta is Map && meta['license'] != null)
              'license': meta['license'],
          };
          if (singleBoard != null) {
            resource['data'] = 'data:$type;base64,${base64Encode(bytes)}';
          } else {
            resource['path'] = path;
            if (!imagePaths.containsKey(name) &&
                !soundPaths.containsKey(name)) {
              add(path, bytes);
            }
            (isImage ? imagePaths : soundPaths)[name] = path;
          }
          final list = isImage ? images : sounds;
          if (!list.any((r) => r['id'] == name)) list.add(resource);
        }
      }
      final data = <String, dynamic>{
        'format': 'open-board-0.1',
        'id': b.id,
        'name': b.name,
        'locale': b.metadata['locale'] ?? 'sv',
        if (b.metadata['license'] != null) 'license': b.metadata['license'],
        'grid': {
          'rows': b.rows,
          'columns': b.columns,
          'order': List.generate(
            b.rows,
            (r) => List.generate(
              b.columns,
              (col) => cells
                  .where((c) => c.row == r && c.column == col)
                  .firstOrNull
                  ?.id,
            ),
          ),
        },
        'buttons': [
          for (final c in cells)
            {
              'id': c.id,
              'label': c.text,
              if (c.vocalization != null) 'vocalization': c.vocalization,
              'background_color':
                  'rgb(${c.color >> 16 & 255}, ${c.color >> 8 & 255}, ${c.color & 255})',
              if (c.image != null) 'image_id': c.image,
              if (c.audio != null) 'sound_id': c.audio,
              if (c.action == CellAction.addToMessage)
                'ext_akkivo_action': 'addToMessage',
              if (c.action == CellAction.navigateToBoard)
                'load_board': {'id': c.target, 'path': paths[c.target]},
            },
        ],
        'images': images,
        'sounds': sounds,
      };
      final bytes = utf8.encode(jsonEncode(data));
      if (singleBoard != null) return Uint8List.fromList(bytes);
      add(paths[b.id]!, bytes);
    }
    add(
      'manifest.json',
      utf8.encode(
        jsonEncode({
          'format': 'open-board-0.1',
          'root': paths[bundle.root],
          'paths': {
            'boards': paths,
            'images': imagePaths,
            'sounds': soundPaths,
          },
        }),
      ),
    );
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}
