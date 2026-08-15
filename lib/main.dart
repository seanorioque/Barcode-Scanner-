import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'app_providers.dart';
import 'data/sqlite_scan_repository.dart';
import 'ui/entries/entries_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbPath = p.join(await getDatabasesPath(), 'scan_entries.db');
  final repository = SqliteScanRepository(databaseFactory: databaseFactory, path: dbPath);

  // Fire-and-forget backstop for photos left behind by an abandoned scan
  // (rescan/dispose deletes them immediately; this just catches whatever
  // slipped through, e.g. a process kill mid-capture). Never blocks first
  // paint.
  unawaited(_purgeOrphanedImages(repository));

  runApp(
    ProviderScope(
      overrides: [scanRepositoryProvider.overrideWithValue(repository)],
      child: const BarcodeCaptureApp(),
    ),
  );
}

Future<void> _purgeOrphanedImages(SqliteScanRepository repository) async {
  final documentsDir = await getApplicationDocumentsDirectory();
  final imagesDir = Directory(p.join(documentsDir.path, 'scan_images'));
  await repository.purgeOrphanedImages(imagesDir);
}

class BarcodeCaptureApp extends StatelessWidget {
  const BarcodeCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Barcode Capture',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple), useMaterial3: true),
      home: const EntriesScreen(),
    );
  }
}
