import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../core/failures.dart';

/// Opens (and on first launch creates) the local SQLite database.
///
/// The tables come from `lib/database/schema.sql` and the default rows from
/// `lib/database/seed.sql`. Both files are bundled as assets (see pubspec.yaml).
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  static const _schemaAsset = 'lib/database/schema.sql';
  static const _seedAsset = 'lib/database/seed.sql';

  Future<Database>? _opening;

  /// The shared database. Opened on first use, then reused.
  Future<Database> get database => _opening ??= _open();

  Future<Database> _open() async {
    try {
      final dir = await getDatabasesPath();
      return await openDatabase(
        p.join(dir, AppConstants.databaseName),
        version: AppConstants.databaseVersion,
        // Needed so ON DELETE rules and foreign keys are enforced.
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await _runScript(db, _schemaAsset);
          await _runScript(db, _seedAsset);
        },
        // When databaseVersion goes up, add the migration steps here.
        onUpgrade: (db, oldVersion, newVersion) async {},
      );
    } catch (_) {
      _opening = null; // allow a retry on the next call
      throw const DatabaseFailure();
    }
  }

  /// Runs every statement in a bundled .sql file.
  Future<void> _runScript(Database db, String asset) async {
    final raw = await rootBundle.loadString(asset);
    final sql = raw
        .split('\n')
        .where((line) => !line.trim().startsWith('--'))
        .join('\n');
    for (final statement in sql.split(';')) {
      final s = statement.trim();
      if (s.isNotEmpty) await db.execute(s);
    }
  }

  Future<void> close() async {
    final opening = _opening;
    _opening = null;
    if (opening != null) await (await opening).close();
  }
}