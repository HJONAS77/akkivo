import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'application/app_controller.dart';
import 'data/media.dart';
import 'data/store.dart';
import 'platform/android_services.dart';
import 'presentation/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AkkivoApp());
}

class AkkivoApp extends StatefulWidget {
  const AkkivoApp({super.key, this.controller});
  final AppController? controller;
  @override
  State<AkkivoApp> createState() => _AkkivoAppState();
}

class _AkkivoAppState extends State<AkkivoApp> {
  late final Future<AppController> startup = _start();
  Future<AppController> _start() async {
    if (widget.controller != null) return widget.controller!;
    final directory = await getApplicationSupportDirectory();
    final platform = AndroidServices();
    final c = AppController(
      store: await Store.open(p.join(directory.path, 'akkivo.db')),
      media: MediaStore(Directory(p.join(directory.path, 'media'))),
      speech: platform,
      audio: platform,
      device: platform,
    );
    await c.load();
    return c;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Akkivo',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2d6255)),
      scaffoldBackgroundColor: const Color(0xfff7f8f4),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
    ),
    home: FutureBuilder<AppController>(
      future: startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: SafeArea(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: SelectableText(
                    'Akkivo kunde inte öppna lokal lagring. Starta om appen. Rensa inte appdata om du saknar säkerhetskopia.\n${snapshot.error}',
                  ),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return BoardHome(controller: snapshot.data!);
      },
    ),
  );
}
