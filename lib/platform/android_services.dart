import 'package:flutter/services.dart';

import '../domain/services.dart';

class AndroidServices
    implements SpeechService, AudioService, DeviceLockService {
  static const channel = MethodChannel('se.akkivo/device');
  @override
  Future<void> speak(String text) async {
    if (text.trim().isNotEmpty) await channel.invokeMethod<void>('speak', text);
  }

  @override
  Future<void> play(String path) =>
      channel.invokeMethod<void>('playAudio', path);
  @override
  Future<void> stop() => channel.invokeMethod<void>('stop');
  @override
  Future<void> keepScreenOn(bool enabled) =>
      channel.invokeMethod<void>('keepScreenOn', enabled);
}
