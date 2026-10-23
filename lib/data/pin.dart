import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

// Work runs off the UI isolate. The persisted parameters allow future upgrades.
class PinHasher {
  const PinHasher({this.iterations = 600000});
  final int iterations;
  Future<String> hash(String pin) async {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) {
      throw const FormatException('Välj en PIN-kod med 4–12 siffror.');
    }
    final salt = List.generate(16, (_) => Random.secure().nextInt(256));
    final key = await compute(_derive, [pin, salt, iterations]);
    return jsonEncode({
      'salt': base64Encode(salt),
      'hash': base64Encode(key),
      'iterations': iterations,
    });
  }

  Future<bool> verify(String pin, String encoded) async {
    final record = jsonDecode(encoded) as Map<String, dynamic>;
    final expected = base64Decode(record['hash'] as String);
    final actual = await compute(_derive, [
      pin,
      base64Decode(record['salt'] as String),
      record['iterations'] as int,
    ]);
    if (actual.length != expected.length) return false;
    var difference = 0;
    for (var i = 0; i < actual.length; i++) {
      difference |= actual[i] ^ expected[i];
    }
    return difference == 0;
  }
}

Future<List<int>> _derive(List<Object> args) async {
  final algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: args[2] as int,
    bits: 256,
  );
  final key = await algorithm.deriveKey(
    secretKey: SecretKey(utf8.encode(args[0] as String)),
    nonce: args[1] as List<int>,
  );
  return key.extractBytes();
}
