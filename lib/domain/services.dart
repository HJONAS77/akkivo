import 'models.dart';

abstract interface class SpeechService {
  Future<void> speak(String text);
  Future<void> stop();
}

abstract interface class DeviceLockService {
  Future<void> keepScreenOn(bool enabled);
}

abstract interface class AudioService {
  Future<void> play(String path);
  Future<void> stop();
}

class BoardNavigator {
  BoardNavigator(this.current);
  String current;
  final List<String> _history = [];
  bool get canGoBack => _history.isNotEmpty;
  void open(String id) {
    if (id != current) {
      _history.add(current);
      current = id;
    }
  }

  void back() {
    if (canGoBack) current = _history.removeLast();
  }

  void home(String id) {
    _history.clear();
    current = id;
  }
}

class ActionDispatcher {
  ActionDispatcher({
    required this.speech,
    required this.audio,
    required this.message,
    required this.navigate,
    required this.audioPath,
  });
  final SpeechService speech;
  final AudioService audio;
  final MessageBuilder message;
  final void Function(String) navigate;
  final String Function(String) audioPath;
  Future<void> activate(Cell cell) async {
    switch (cell.action) {
      case CellAction.speak:
        await speech.speak(cell.spokenText);
      case CellAction.addToMessage:
        message.add(cell);
      case CellAction.navigateToBoard:
        if (cell.target == null) {
          throw StateError('Cellen saknar länk till en bräda.');
        }
        navigate(cell.target!);
      case CellAction.playAudio:
        if (cell.audio == null) throw StateError('Cellen saknar ljud.');
        await audio.play(audioPath(cell.audio!));
    }
  }
}
