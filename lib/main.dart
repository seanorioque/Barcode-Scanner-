import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'app_providers.dart';
import 'data/sqlite_scan_repository.dart';
import 'ui/entries/entries_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbPath = p.join(await getDatabasesPath(), 'scan_entries.db');
  final repository = SqliteScanRepository(databaseFactory: databaseFactory, path: dbPath);

  runApp(
    ProviderScope(
      overrides: [scanRepositoryProvider.overrideWithValue(repository)],
      child: const BarcodeCaptureApp(),
    ),
  );
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
