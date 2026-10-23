import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_controller.dart';
import '../data/obf.dart';
import '../domain/models.dart';
import 'editors.dart';

class BoardHome extends StatefulWidget {
  const BoardHome({super.key, required this.controller});
  final AppController controller;
  @override
  State<BoardHome> createState() => _BoardHomeState();
}

class _BoardHomeState extends State<BoardHome> with WidgetsBindingObserver {
  AppController get c => widget.controller;
  bool editing = false, busy = false;
  String? active;
  Timer? feedback;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    feedback?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(c.device.keepScreenOn(false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    unawaited(run(() => c.visibility(state == AppLifecycleState.resumed)));
  }

  void notice(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException catch (e) {
      notice(e.message ?? 'Android-funktionen kunde inte utföras.');
    } catch (e) {
      notice(
        e.toString().replaceFirst(
          RegExp(r'^(Bad state: |FormatException: )'),
          '',
        ),
      );
    }
  }

  Future<void> task(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await run(action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> pin({required bool unlock}) async {
    final first = TextEditingController(), second = TextEditingController();
    String? error;
    var checking = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) => AlertDialog(
          title: Text(unlock ? 'Öppna administration' : 'Välj PIN-kod'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  unlock ? 'Ange vuxens PIN-kod.' : '4–12 siffror. Spara koden på en säker plats. En glömd kod kräver återställning av appdata.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(12),
                  ],
                  decoration: const InputDecoration(labelText: 'PIN-kod'),
                ),
                if (!unlock)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextField(
                      controller: second,
                      obscureText: true,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(12),
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Upprepa PIN-koden',
                      ),
                    ),
                  ),
                if (checking)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: checking ? null : () => Navigator.pop(dialogContext),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: checking
                  ? null
                  : () async {
                      refresh(() {
                        checking = true;
                        error = null;
                      });
                      try {
                        if (unlock) {
                          if (!await c.unlock(first.text)) {
                            throw StateError('Fel PIN-kod. Försök igen.');
                          }
                        } else {
                          if (first.text != second.text) {
                            throw StateError('Koderna stämmer inte överens.');
                          }
                          await c.store.setPin(first.text);
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        if (dialogContext.mounted) {
                          refresh(
                            () => error = e.toString().replaceFirst(
                              'Bad state: ',
                              '',
                            ),
                          );
                        }
                      } finally {
                        if (dialogContext.mounted) {
                          refresh(() => checking = false);
                        }
                      }
                    },
              child: Text(unlock ? 'Öppna' : 'Spara'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog route's exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    first.dispose();
    second.dispose();
  }

  Future<bool> confirm(String title, String text) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Avbryt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Fortsätt'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> import() => task(() async {
    await c.store.requireAdmin();
    final file = await FilePicker.pickFile(type: FileType.any);
    if (file == null) return;
    final name = file.name.toLowerCase();
    if (!name.endsWith('.obf') && !name.endsWith('.obz')) {
      throw const FormatException('Välj en .obf- eller .obz-fil.');
    }
    final size = await file.length();
    if (size == null || size > ObfCodec.maxPackage) {
      throw const FormatException('Filen får vara högst 30 MB.');
    }
    if (!mounted ||
        !await confirm(
          'Importera brädor?',
          'Brädor med samma ID ersätts. Övriga brädor behålls. Exportera gärna en säkerhetskopia först.',
        )) {
      return;
    }
    final warnings = await c.importFile(
      await file.readAsBytes(),
      name.endsWith('.obz'),
    );
    notice(
      warnings.isEmpty
          ? 'Brädorna är importerade.'
          : 'Importerad. ${warnings.join(' ')}',
    );
  });
  Future<void> export(bool single) => task(() async {
    final bytes = await c.export(single: single);
    final saved = await FilePicker.saveFile(
      fileName: single ? 'akkivo.obf' : 'akkivo.obz',
      bytes: bytes,
    );
    if (saved != null) notice('Exporten är sparad.');
  });
  Future<void> boardEditor([Board? board]) async {
    await c.store.requireAdmin();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => BoardEditor(controller: c, board: board),
    );
  }

  Future<void> boards() async {
    await c.store.requireAdmin();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AnimatedBuilder(
        animation: c,
        builder: (context, _) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .75,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text(
                        'Mina brädor',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Skapa bräda',
                        onPressed: () => run(() => boardEditor()),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final b in c.boards)
                        ListTile(
                          title: Text(b.name),
                          subtitle: Text(
                            '${b.rows} × ${b.columns}${c.settings.homeBoard == b.id ? ' · Startbräda' : ''}',
                          ),
                          onTap: () {
                            c.open(b.id);
                            Navigator.pop(context);
                          },
                          trailing: PopupMenuButton<String>(
                            tooltip: 'Brädinställningar',
                            onSelected: (value) => run(() async {
                              switch (value) {
                                case 'edit':
                                  await boardEditor(b);
                                case 'home':
                                  await c.store.setHome(b.id);
                                  await c.load();
                                case 'delete':
                                  if (await confirm(
                                    'Ta bort ${b.name}?',
                                    'Brädan och dess celler tas bort.',
                                  )) {
                                    await c.store.deleteBoard(b.id);
                                    await c.load();
                                  }
                              }
                            }),
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Namn och rutnät'),
                              ),
                              PopupMenuItem(
                                value: 'home',
                                child: Text('Använd som startbräda'),
                              ),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text('Ta bort bräda'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> activateCell(Cell? cell, int row, int col) async {
    if (editing && !c.settings.userMode) {
      await c.store.requireAdmin();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => CellEditor(
          controller: c,
          board: c.board,
          row: row,
          column: col,
          cell: cell,
        ),
      );
    } else if (cell != null) {
      setState(() => active = cell.id);
      feedback?.cancel();
      feedback = Timer(const Duration(milliseconds: 450), () {
        if (mounted) setState(() => active = null);
      });
      await c.activate(cell);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final locked = c.settings.userMode;
      final isEditing = editing && !locked;
      return PopScope(
        canPop: !c.navigator!.canGoBack,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) c.back();
        },
        child: Scaffold(
          appBar: AppBar(
            toolbarHeight: 20 + MediaQuery.textScalerOf(context).scale(36),
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.board.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  locked
                      ? 'Akkivo'
                      : 'Akkivo · ${isEditing ? 'Redigering' : 'Förhandsvisning'}',
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            leading: IconButton(
              tooltip: c.navigator!.canGoBack ? 'Tillbaka' : 'Startbräda',
              onPressed: c.navigator!.canGoBack ? c.back : c.home,
              icon: Icon(
                c.navigator!.canGoBack ? Icons.arrow_back : Icons.home_outlined,
              ),
            ),
            actions: [
              if (locked)
                IconButton(
                  tooltip: 'Öppna administration med PIN',
                  onPressed: busy ? null : () => run(() => pin(unlock: true)),
                  icon: const Icon(Icons.lock_outline),
                ),
              if (!locked)
                PopupMenuButton<String>(
                  enabled: !busy,
                  tooltip: 'Administration',
                  onSelected: (value) => run(() async {
                    switch (value) {
                      case 'boards':
                        await boards();
                      case 'edit':
                        setState(() => editing = !editing);
                      case 'pin':
                        await pin(unlock: false);
                      case 'lock':
                        if (!await c.store.hasPin()) await pin(unlock: false);
                        if (await c.store.hasPin()) {
                          await c.lock();
                          if (mounted) setState(() => editing = false);
                        }
                      case 'import':
                        await import();
                      case 'obz':
                        await export(false);
                      case 'obf':
                        await export(true);
                    }
                  }),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'boards',
                      child: Text('Mina brädor'),
                    ),
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(
                        isEditing ? 'Förhandsgranska' : 'Redigera celler',
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'lock',
                      child: Text('Starta skyddat användarläge'),
                    ),
                    const PopupMenuItem(
                      value: 'pin',
                      child: Text('Välj / ändra PIN-kod'),
                    ),
                    const PopupMenuItem(
                      value: 'import',
                      child: Text('Importera OBF / OBZ'),
                    ),
                    const PopupMenuItem(
                      value: 'obz',
                      child: Text('Exportera alla brädor (OBZ)'),
                    ),
                    const PopupMenuItem(
                      value: 'obf',
                      child: Text('Exportera denna bräda (OBF)'),
                    ),
                  ],
                ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, viewport) => Column(
                children: [
                  if (busy) const LinearProgressIndicator(),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: viewport.maxHeight * .55,
                    ),
                    child: SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                        child: Material(
                          color: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: const BorderSide(color: Color(0xffcbd9d2)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Text(
                                  'Mitt meddelande',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xff496058),
                                  ),
                                ),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minHeight: 42,
                                    maxHeight: 120,
                                  ),
                                  child: SingleChildScrollView(
                                    reverse: true,
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        c.message.text.isEmpty
                                            ? 'Tryck på ord för att bygga en mening'
                                            : c.message.text,
                                        style: TextStyle(
                                          fontSize: 22,
                                          color: c.message.text.isEmpty
                                              ? const Color(0xff64716b)
                                              : const Color(0xff172d24),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    FilledButton.icon(
                                      onPressed: c.message.text.isEmpty
                                          ? null
                                          : () => run(
                                              () => c.speech.speak(
                                                c.message.text,
                                              ),
                                            ),
                                      icon: const Icon(
                                        Icons.volume_up_outlined,
                                      ),
                                      label: const Text('Läs upp'),
                                    ),
                                    IconButton(
                                      tooltip: 'Ta bort senaste ordet',
                                      onPressed: c.message.text.isEmpty
                                          ? null
                                          : c.undo,
                                      icon: const Icon(
                                        Icons.backspace_outlined,
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: c.message.text.isEmpty
                                          ? null
                                          : c.clear,
                                      child: const Text('Rensa'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (isEditing)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Tryck på en cell för att redigera eller lägga till.',
                      ),
                    ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        const gap = 8.0, padding = 12.0;
                        final width =
                            ((box.maxWidth -
                                        padding * 2 -
                                        gap * (c.board.columns - 1)) /
                                    c.board.columns)
                                .clamp(96.0, 1000.0);
                        final height =
                            ((box.maxHeight -
                                        padding * 2 -
                                        gap * (c.board.rows - 1)) /
                                    c.board.rows)
                                .clamp(108.0, 500.0);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width:
                                (width + gap) * c.board.columns -
                                gap +
                                padding * 2,
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(padding),
                                child: Column(
                                  children: [
                                    for (var r = 0; r < c.board.rows; r++)
                                      Padding(
                                        padding: EdgeInsets.only(
                                          bottom: r == c.board.rows - 1
                                              ? 0
                                              : gap,
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            for (
                                              var col = 0;
                                              col < c.board.columns;
                                              col++
                                            )
                                              Padding(
                                                padding: EdgeInsets.only(
                                                  right:
                                                      col == c.board.columns - 1
                                                      ? 0
                                                      : gap,
                                                ),
                                                child: SizedBox(
                                                  width: width,
                                                  height: height,
                                                  child: _tile(
                                                    c.boardCells
                                                        .where(
                                                          (cell) =>
                                                              cell.row == r &&
                                                              cell.column ==
                                                                  col,
                                                        )
                                                        .firstOrNull,
                                                    r,
                                                    col,
                                                    isEditing,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (!locked)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_outlined, size: 16),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Sparas på den här enheten',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
  Widget _tile(Cell? cell, int row, int col, bool isEditing) {
    if (cell == null && !isEditing) {
      return const DecoratedBox(
        decoration: BoxDecoration(
          color: Color(0xffeef1eb),
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      );
    }
    final color = Color(cell?.color ?? 0xffeef1eb);
    return Semantics(
      button: true,
      label: cell?.text ?? 'Tom cell, rad ${row + 1}, kolumn ${col + 1}',
      child: Material(
        color: active == cell?.id && cell != null
            ? Color.alphaBlend(const Color(0x332d6255), color)
            : color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: active == cell?.id && cell != null
                ? const Color(0xff2d6255)
                : const Color(0xffbacbc2),
            width: active == cell?.id && cell != null ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : () => run(() => activateCell(cell, row, col)),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (cell?.image != null)
                  Expanded(
                    child: Image.file(
                      File(c.media.path(cell!.image!)),
                      fit: BoxFit.contain,
                      cacheWidth: 512,
                      errorBuilder: (_, error, stack) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 32,
                      ),
                    ),
                  ),
                if (cell == null)
                  const Icon(Icons.add, size: 32, color: Color(0xff496058)),
                if (cell != null)
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(
                        cell.text,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: color.computeLuminance() < .4
                              ? Colors.white
                              : const Color(0xff182c25),
                        ),
                      ),
                    ),
                  ),
                if (cell?.action == CellAction.navigateToBoard)
                  const Icon(Icons.arrow_forward_rounded, size: 20),
                if (cell?.action == CellAction.playAudio)
                  const Icon(Icons.music_note_outlined, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
