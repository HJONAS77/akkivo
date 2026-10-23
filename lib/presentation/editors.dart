import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../application/app_controller.dart';
import '../data/media.dart';
import '../domain/models.dart';

class BoardEditor extends StatefulWidget {
  const BoardEditor({super.key, required this.controller, this.board});
  final AppController controller;
  final Board? board;
  @override
  State<BoardEditor> createState() => _BoardEditorState();
}

class _BoardEditorState extends State<BoardEditor> {
  late final name = TextEditingController(text: widget.board?.name ?? '');
  late int rows = widget.board?.rows ?? 3, columns = widget.board?.columns ?? 3;
  String? error;
  bool busy = false;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.board == null ? 'Ny bräda' : 'Namn och rutnät'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Brädans namn'),
          ),
          _number('Rader', rows, (value) => setState(() => rows = value)),
          const SizedBox(height: 12),
          _number(
            'Kolumner',
            columns,
            (value) => setState(() => columns = value),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Avbryt'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () async {
                setState(() => busy = true);
                try {
                  final b = Board(
                    id: widget.board?.id ?? newId(),
                    name: name.text.trim(),
                    rows: rows,
                    columns: columns,
                    metadata: widget.board?.metadata ?? {},
                  );
                  await widget.controller.store.saveBoard(b);
                  await widget.controller.load();
                  widget.controller.open(b.id);
                  if (context.mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                } finally {
                  if (mounted) setState(() => busy = false);
                }
              },
        child: const Text('Spara'),
      ),
    ],
  );
}

Widget _number(
  String label,
  int value,
  void Function(int) changed, {
  int max = 10,
}) => DropdownButtonFormField<int>(
  initialValue: value,
  decoration: InputDecoration(labelText: label),
  items: [
    for (var i = 1; i <= max; i++)
      DropdownMenuItem(value: i, child: Text('$i')),
  ],
  onChanged: (v) {
    if (v != null) changed(v);
  },
);

class CellEditor extends StatefulWidget {
  const CellEditor({
    super.key,
    required this.controller,
    required this.board,
    required this.row,
    required this.column,
    this.cell,
  });
  final AppController controller;
  final Board board;
  final int row, column;
  final Cell? cell;
  @override
  State<CellEditor> createState() => _CellEditorState();
}

class _CellEditorState extends State<CellEditor> {
  late final text = TextEditingController(text: widget.cell?.text ?? '');
  late final vocal = TextEditingController(
    text: widget.cell?.vocalization ?? '',
  );
  late CellAction action = widget.cell?.action ?? CellAction.addToMessage;
  late String? image = widget.cell?.image,
      audio = widget.cell?.audio,
      target = widget.cell?.target;
  late int row = widget.row + 1,
      column = widget.column + 1,
      color = widget.cell?.color ?? 0xffe7f0ec;
  String? error;
  bool busy = false;
  static const labels = {
    CellAction.speak: 'Läs upp direkt',
    CellAction.addToMessage: 'Lägg till i meddelandet',
    CellAction.navigateToBoard: 'Öppna en bräda',
    CellAction.playAudio: 'Spela ljudfil',
  };
  Future<void> run(Future<void> Function() operation) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.controller.store.requireAdmin();
      await operation();
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Bad state: ', ''));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    text.dispose();
    vocal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.cell == null ? 'Lägg till cell' : 'Redigera cell'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: text,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'Text på cellen'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: vocal,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Taltext (valfri)',
                helperText: 'Används i tal och meddelanden.',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<CellAction>(
              initialValue: action,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Åtgärd'),
              items: [
                for (final a in CellAction.values)
                  DropdownMenuItem(value: a, child: Text(labels[a]!)),
              ],
              onChanged: busy ? null : (v) => setState(() => action = v!),
            ),
            const SizedBox(height: 12),
            if (action == CellAction.navigateToBoard)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  initialValue: target,
                  decoration: const InputDecoration(labelText: 'Målbräda'),
                  items: [
                    for (final b in widget.controller.boards)
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: busy ? null : (v) => setState(() => target = v),
                ),
              ),
            if (image != null)
              SizedBox(
                height: 100,
                child: Image.file(
                  File(widget.controller.media.path(image!)),
                  errorBuilder: (_, error, stack) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final picked = await ImagePicker().pickImage(
                            source: ImageSource.gallery,
                            maxWidth: 2048,
                            maxHeight: 2048,
                          );
                          if (picked == null) return;
                          final saved = await widget.controller.importImage(
                            picked.path,
                          );
                          if (mounted) setState(() => image = saved);
                        }),
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Välj bild'),
                ),
                if (image != null)
                  TextButton(
                    onPressed: busy ? null : () => setState(() => image = null),
                    child: const Text('Ta bort bild'),
                  ),
              ],
            ),
            if (action == CellAction.playAudio)
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => run(() async {
                            final picked = await FilePicker.pickFile(
                              type: FileType.audio,
                            );
                            if (picked == null) return;
                            final length = await picked.length();
                            if (length == null || length > MediaStore.maxFile) {
                              throw const FormatException(
                                'Ljudfilen får vara högst 10 MB.',
                              );
                            }
                            final saved = await widget.controller.media.save(
                              await picked.readAsBytes(),
                              MediaStore.typeForName(picked.name),
                            );
                            if (mounted) setState(() => audio = saved);
                          }),
                    icon: const Icon(Icons.audio_file_outlined),
                    label: Text(audio == null ? 'Välj ljud' : 'Byt ljud'),
                  ),
                  if (audio != null) const Icon(Icons.check_circle_outline),
                ],
              ),
            const SizedBox(height: 12),
            const Text('Bakgrundsfärg'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in [
                  0xffe7f0ec,
                  0xffdcefd9,
                  0xffffe1dc,
                  0xffffeed0,
                  0xffe8e1f3,
                  0xffdcebf7,
                  0xffffffff,
                ])
                  Semantics(
                    selected: color == value,
                    child: IconButton.filledTonal(
                      tooltip: 'Färg ${value.toRadixString(16)}',
                      style: IconButton.styleFrom(
                        backgroundColor: Color(value),
                        side: BorderSide(
                          color: color == value
                              ? const Color(0xff2d6255)
                              : Colors.grey,
                          width: color == value ? 3 : 1,
                        ),
                      ),
                      onPressed: busy
                          ? null
                          : () => setState(() => color = value),
                      icon: Icon(
                        color == value ? Icons.check : Icons.circle_outlined,
                        color: const Color(0xff233d30),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _number(
                    'Rad',
                    row,
                    (v) => setState(() => row = v),
                    max: widget.board.rows,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _number(
                    'Kolumn',
                    column,
                    (v) => setState(() => column = v),
                    max: widget.board.columns,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Flytta genom att välja en tom position.',
              style: TextStyle(fontSize: 12),
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      if (widget.cell != null)
        TextButton(
          onPressed: busy
              ? null
              : () => run(() async {
                  await widget.controller.store.deleteCell(widget.cell!);
                  await widget.controller.load();
                  if (context.mounted) Navigator.pop(context);
                }),
          child: const Text('Ta bort cell'),
        ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: const Text('Avbryt'),
      ),
      FilledButton(
        onPressed: busy
            ? null
            : () => run(() async {
                final cell = Cell(
                  id: widget.cell?.id ?? newId(),
                  boardId: widget.board.id,
                  row: row - 1,
                  column: column - 1,
                  text: text.text.trim(),
                  action: action,
                  image: image,
                  audio: action == CellAction.playAudio ? audio : null,
                  target: action == CellAction.navigateToBoard ? target : null,
                  color: color,
                  vocalization: vocal.text.trim().isEmpty
                      ? null
                      : vocal.text.trim(),
                  metadata: widget.cell?.metadata ?? {},
                );
                await widget.controller.store.saveCell(cell);
                await widget.controller.load();
                if (context.mounted) Navigator.pop(context);
              }),
        child: const Text('Spara'),
      ),
    ],
  );
}
