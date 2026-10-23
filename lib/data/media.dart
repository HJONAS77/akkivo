import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;

class MediaStore {
  MediaStore(this.directory);
  final Directory directory;
  static const maxFile = 10 * 1024 * 1024;
  static const imageTypes = {
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
  };
  static const audioTypes = {
    'audio/mpeg': 'mp3',
    'audio/mp4': 'm4a',
    'audio/wav': 'wav',
    'audio/ogg': 'ogg',
  };
  static String? imageType(List<int> b) {
    if (b.length >= 8 && b.take(8).join(',') == '137,80,78,71,13,10,26,10') {
      return 'image/png';
    }
    if (b.length >= 3 && b[0] == 255 && b[1] == 216 && b[2] == 255) {
      return 'image/jpeg';
    }
    if (b.length >= 12 &&
        String.fromCharCodes(b.take(4)) == 'RIFF' &&
        String.fromCharCodes(b.skip(8).take(4)) == 'WEBP') {
      return 'image/webp';
    }
    return null;
  }

  static String typeForName(String name) {
    final ext = p.extension(name).replaceFirst('.', '').toLowerCase();
    return {
          ...imageTypes,
          ...audioTypes,
        }.entries.where((e) => e.value == ext).map((e) => e.key).firstOrNull ??
        'application/octet-stream';
  }

  String path(String name) {
    if (!RegExp(r'^[a-f0-9]{64}\.(png|jpg|webp|mp3|m4a|wav|ogg)$')
        .hasMatch(name)) {
      throw const FormatException('Ogiltig mediareferens.');
    }
    return p.join(directory.path, name);
  }

  Future<String> save(List<int> bytes, String type) async {
    if (bytes.isEmpty || bytes.length > maxFile) {
      throw const FormatException('Mediafilen måste vara mindre än 10 MB.');
    }
    final ext = {...imageTypes, ...audioTypes}[type];
    if (ext == null ||
        (type.startsWith('image/') && imageType(bytes) != type)) {
      throw const FormatException(
        'Bilden måste vara en giltig PNG, JPEG eller WebP.',
      );
    }
    final digest = await Sha256().hash(bytes);
    final name =
        '${digest.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}.$ext';
    await directory.create(recursive: true);
    final file = File(path(name));
    if (!await file.exists()) {
      final temporary = File('${file.path}.part');
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
    }
    return name;
  }
}
