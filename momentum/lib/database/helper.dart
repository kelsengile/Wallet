import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../core/constants.dart';
import '../core/failures.dart';

/// Numbers shown on the total balance card (in pesos).
class AccountsSummary {
  final double totalBalance;
  final int accountCount;
  final double income;
  final double expense;

  const AccountsSummary({
    required this.totalBalance,
    required this.accountCount,
    required this.income,
    required this.expense,
  });

  static const empty = AccountsSummary(
    totalBalance: 0,
    accountCount: 0,
    income: 0,
    expense: 0,
  );
}

/// Row counts shown on the Database screen.
class DatabaseStats {
  final int accounts;
  final int transactions;
  final int categories;
  final int trashed;

  const DatabaseStats({
    required this.accounts,
    required this.transactions,
    required this.categories,
    required this.trashed,
  });

  static const empty = DatabaseStats(
    accounts: 0,
    transactions: 0,
    categories: 0,
    trashed: 0,
  );
}

/// What kind of row is sitting in the trash.
enum TrashKind { account, transaction }

/// One row of the Trash screen.
class TrashItem {
  final TrashKind kind;
  final int id;
  final String title;
  final String subtitle;
  final DateTime? deletedAt;

  const TrashItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.deletedAt,
  });
}

/// The lists managed on the Categories screen.
enum CategoryGroup { accountType, accountCategory, income, expense, transfer }

/// One row of a category list.
/// [icon] is the saved icon key. null = the screen picks a default.
class CategoryItem {
  final int id;
  final String name;
  final String? icon;
  const CategoryItem(this.id, this.name, [this.icon]);
}

/// Opens the local SQLite database and holds every database function.
/// Money is stored as whole centavos, so values are divided by
/// [AppConstants.centavosPerPeso] here.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  /// Screens listen to this and reload when it changes.
  /// Call [notifyChanged] after any insert, update or delete.
  final ValueNotifier<int> changes = ValueNotifier<int>(0);
  void notifyChanged() => changes.value++;

  Future<Database>? _opening;

  Future<Database> get database async {
    final opening = _opening ??= _open();
    try {
      return await opening;
    } catch (error) {
      debugPrint('Database open failed: $error');
      _opening = null; // allow a retry next time
      rethrow;
    }
  }

  // No onCreate. A brand new file has no tables, so the check in onOpen
  // builds everything. One code path for new, broken and old files.
  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, AppConstants.databaseName);
    return openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onOpen: _ensureReady,
    );
  }

  // ---------- Self-repair ----------

  /// Tables that have an `icon` column.
  static const _iconTables = [
    'account_types',
    'account_categories',
    'categories',
  ];

  /// Columns every table must have for the app's queries to work.
  static const _requiredColumns = <String, Set<String>>{
    'account_types': {'id', 'name', 'icon'},
    'account_categories': {'id', 'name', 'sort_order', 'icon'},
    'accounts': {
      'id',
      'name',
      'type_id',
      'category_id',
      'initial_balance',
      'deleted_at',
    },
    'categories': {'id', 'name', 'kind', 'icon'},
    'transactions': {'id', 'type', 'amount', 'deleted_at'},
  };

  /// Runs every time the database opens. Adds the icon columns to older
  /// files, then rebuilds the database only when the tables are missing or
  /// different from schema.sql, or when the default data was never inserted.
  Future<void> _ensureReady(Database db) async {
    await _addMissingIconColumns(db);
    final ready = await _schemaIsValid(db) && await _isSeeded(db);
    if (ready) return;
    debugPrint('Database is missing tables or default data. Rebuilding.');
    await _rebuild(db);
  }

  /// Older databases get the `icon` column without losing any data.
  Future<void> _addMissingIconColumns(Database db) async {
    for (final table in _iconTables) {
      final columns = await _columnsOf(db, table);
      if (columns.isNotEmpty && !columns.contains('icon')) {
        await db.execute('ALTER TABLE $table ADD COLUMN icon TEXT');
      }
    }
  }

  Future<Set<String>> _columnsOf(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final row in rows) row['name'] as String};
  }

  Future<bool> _schemaIsValid(Database db) async {
    for (final entry in _requiredColumns.entries) {
      final columns = await _columnsOf(db, entry.key);
      if (columns.isEmpty || !columns.containsAll(entry.value)) return false;
    }
    final view = await db.rawQuery(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'view' AND name = 'account_balances'",
    );
    return view.isNotEmpty;
  }

  /// The locked Transfer category is the last seed row, so if it is there
  /// the whole seed finished.
  Future<bool> _isSeeded(Database db) async {
    final transfer = Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM categories WHERE kind = 'transfer'",
          ),
        ) ??
        0;
    final types = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM account_types'),
        ) ??
        0;
    return transfer > 0 && types > 0;
  }

  /// Drops every finance table. Children first, so foreign keys don't
  /// block the drops.
  Future<void> _dropAll(DatabaseExecutor db) async {
    await db.execute('DROP VIEW IF EXISTS account_balances');
    await db.execute('DROP TABLE IF EXISTS transactions');
    await db.execute('DROP TABLE IF EXISTS accounts');
    await db.execute('DROP TABLE IF EXISTS categories');
    await db.execute('DROP TABLE IF EXISTS account_categories');
    await db.execute('DROP TABLE IF EXISTS account_types');
  }

  /// Drops the finance tables and recreates them from the .sql assets.
  /// All in one transaction: it either fully works or changes nothing.
  Future<void> _rebuild(Database db) async {
    final schema = await rootBundle.loadString(AppConstants.schemaAsset);
    final seed = await rootBundle.loadString(AppConstants.seedAsset);
    await db.transaction((txn) async {
      await _dropAll(txn);
      await _runScript(txn, schema);
      await _runScript(txn, seed);
    });
  }

  /// Runs a .sql file one statement at a time (split on semicolons).
  Future<void> _runScript(DatabaseExecutor db, String script) async {
    final withoutComments = script
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('--'))
        .join('\n');
    for (final statement in withoutComments.split(';')) {
      final sql = statement.trim();
      if (sql.isNotEmpty) await db.execute(sql);
    }
  }

  // ---------- Finance ----------

  /// Current total balance of all active accounts, the number of accounts,
  /// and the income / expense totals of all non-trashed transactions.
  Future<AccountsSummary> getAccountsSummary() async {
    try {
      final db = await database;

      final balanceRow = (await db.rawQuery('''
        SELECT COALESCE(SUM(b.balance), 0) AS total, COUNT(*) AS count
        FROM account_balances b
        JOIN accounts a ON a.id = b.account_id
        WHERE a.deleted_at IS NULL
      ''')).first;

      final incomeRow = (await db.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM transactions
        WHERE type = 'income' AND deleted_at IS NULL
      ''')).first;

      final expenseRow = (await db.rawQuery('''
        SELECT COALESCE(SUM(amount), 0) AS total
        FROM transactions
        WHERE type = 'expense' AND deleted_at IS NULL
      ''')).first;

      return AccountsSummary(
        totalBalance: (balanceRow['total'] as num).toInt() /
            AppConstants.centavosPerPeso,
        accountCount: (balanceRow['count'] as num).toInt(),
        income: (incomeRow['total'] as num).toInt() /
            AppConstants.centavosPerPeso,
        expense: (expenseRow['total'] as num).toInt() /
            AppConstants.centavosPerPeso,
      );
    } catch (error) {
      debugPrint('getAccountsSummary failed: $error');
      throw const DatabaseFailure();
    }
  }

  // ---------- Categories ----------

  String _tableOf(CategoryGroup group) {
    switch (group) {
      case CategoryGroup.accountType:
        return 'account_types';
      case CategoryGroup.accountCategory:
        return 'account_categories';
      case CategoryGroup.income:
      case CategoryGroup.expense:
      case CategoryGroup.transfer:
        return 'categories';
    }
  }

  String? _kindOf(CategoryGroup group) {
    switch (group) {
      case CategoryGroup.income:
        return 'income';
      case CategoryGroup.expense:
        return 'expense';
      case CategoryGroup.transfer:
        return 'transfer';
      case CategoryGroup.accountType:
      case CategoryGroup.accountCategory:
        return null;
    }
  }

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Failure {
      rethrow;
    } catch (error) {
      debugPrint('Database error: $error');
      final text = error.toString();
      if (text.contains('UNIQUE')) {
        throw const ValidationFailure('That name already exists.');
      }
      if (text.contains('FOREIGN KEY')) {
        throw const ValidationFailure(
          'This is still used by an account, so it can\'t be deleted.',
        );
      }
      throw const DatabaseFailure();
    }
  }

  void _checkEditable(CategoryGroup group) {
    if (group == CategoryGroup.transfer) {
      throw const ValidationFailure('The Transfer category can\'t be changed.');
    }
  }

  String _cleanName(String name) {
    final clean = name.trim();
    if (clean.isEmpty) throw const ValidationFailure('Please enter a name.');
    return clean;
  }

  Future<List<CategoryItem>> getCategoryItems(CategoryGroup group) {
    return _guard(() async {
      final db = await database;
      final kind = _kindOf(group);
      final rows = await db.query(
        _tableOf(group),
        columns: ['id', 'name', 'icon'],
        where: kind == null ? null : 'kind = ?',
        whereArgs: kind == null ? null : [kind],
        orderBy: 'id',
      );
      return [
        for (final row in rows)
          CategoryItem(
            (row['id'] as num).toInt(),
            row['name'] as String,
            row['icon'] as String?,
          ),
      ];
    });
  }

  Future<void> addCategoryItem(
    CategoryGroup group,
    String name, {
    String? icon,
  }) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      final kind = _kindOf(group);
      await db.insert(_tableOf(group), {
        'name': _cleanName(name),
        'icon': icon,
        // ignore: use_null_aware_elements
        if (kind != null) 'kind': kind,
      });
      notifyChanged();
    });
  }

  Future<void> renameCategoryItem(
    CategoryGroup group,
    int id,
    String name, {
    String? icon,
  }) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      await db.update(
        _tableOf(group),
        {'name': _cleanName(name), 'icon': icon},
        where: 'id = ?',
        whereArgs: [id],
      );
      notifyChanged();
    });
  }

  Future<void> deleteCategoryItem(CategoryGroup group, int id) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      await db.delete(_tableOf(group), where: 'id = ?', whereArgs: [id]);
      notifyChanged();
    });
  }

  // ---------- Soft delete (moves a row to the trash) ----------

  Future<void> softDeleteAccount(int id) {
    return _guard(() async {
      final db = await database;
      await db.update(
        'accounts',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      notifyChanged();
    });
  }

  Future<void> softDeleteTransaction(int id) {
    return _guard(() async {
      final db = await database;
      await db.update(
        'transactions',
        {'deleted_at': DateTime.now().toIso8601String()},
        where: 'id = ?',
        whereArgs: [id],
      );
      notifyChanged();
    });
  }

  // ---------- Trash ----------

  /// Everything currently in the trash, newest first.
  Future<List<TrashItem>> getTrashItems() {
    return _guard(() async {
      final db = await database;

      final accountRows = await db.query(
        'accounts',
        columns: ['id', 'name', 'deleted_at'],
        where: 'deleted_at IS NOT NULL',
      );
      final transactionRows = await db.rawQuery('''
        SELECT t.id, t.type, t.amount, t.note, t.deleted_at,
               c.name AS category_name
        FROM transactions t
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE t.deleted_at IS NOT NULL
      ''');

      final items = <TrashItem>[
        for (final row in accountRows)
          TrashItem(
            kind: TrashKind.account,
            id: (row['id'] as num).toInt(),
            title: row['name'] as String,
            subtitle: 'Account',
            deletedAt: DateTime.tryParse('${row['deleted_at']}'),
          ),
        for (final row in transactionRows)
          TrashItem(
            kind: TrashKind.transaction,
            id: (row['id'] as num).toInt(),
            title: (row['category_name'] as String?) ??
                _capitalize(row['type'] as String),
            subtitle: _transactionSubtitle(row),
            deletedAt: DateTime.tryParse('${row['deleted_at']}'),
          ),
      ];

      items.sort((a, b) {
        final left = a.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final right = b.deletedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        return right.compareTo(left);
      });
      return items;
    });
  }

  String _capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);

  String _transactionSubtitle(Map<String, Object?> row) {
    final amount =
        ((row['amount'] as num).toInt() / AppConstants.centavosPerPeso)
            .toStringAsFixed(2);
    final note = (row['note'] as String?)?.trim();
    final base =
        '${_capitalize(row['type'] as String)} | ${AppConstants.currencySymbol}$amount';
    return (note == null || note.isEmpty) ? base : '$base | $note';
  }

  Future<int> getTrashCount() {
    return _guard(() async {
      final db = await database;
      return _countTrash(db);
    });
  }

  Future<int> _countTrash(DatabaseExecutor db) async {
    final accounts = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM accounts WHERE deleted_at IS NOT NULL',
          ),
        ) ??
        0;
    final transactions = Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NOT NULL',
          ),
        ) ??
        0;
    return accounts + transactions;
  }

  /// Puts a trashed row back. Restoring a transaction also restores the
  /// account(s) it belongs to, so it never points at a hidden account.
  Future<void> restoreTrashItem(TrashItem item) {
    return _guard(() async {
      final db = await database;
      await db.transaction((txn) async {
        if (item.kind == TrashKind.account) {
          await txn.update(
            'accounts',
            {'deleted_at': null},
            where: 'id = ?',
            whereArgs: [item.id],
          );
        } else {
          final rows = await txn.query(
            'transactions',
            columns: ['account_id', 'to_account_id'],
            where: 'id = ?',
            whereArgs: [item.id],
          );
          if (rows.isNotEmpty) {
            final ids = <int>[
              (rows.first['account_id'] as num).toInt(),
              if (rows.first['to_account_id'] != null)
                (rows.first['to_account_id'] as num).toInt(),
            ];
            for (final accountId in ids) {
              await txn.update(
                'accounts',
                {'deleted_at': null},
                where: 'id = ?',
                whereArgs: [accountId],
              );
            }
          }
          await txn.update(
            'transactions',
            {'deleted_at': null},
            where: 'id = ?',
            whereArgs: [item.id],
          );
        }
      });
      notifyChanged();
    });
  }

  /// Permanently removes one trashed row. Deleting an account also removes
  /// the transactions that use it.
  Future<void> deleteTrashItemForever(TrashItem item) {
    return _guard(() async {
      final db = await database;
      await db.transaction((txn) async {
        if (item.kind == TrashKind.account) {
          await txn.delete(
            'transactions',
            where: 'account_id = ? OR to_account_id = ?',
            whereArgs: [item.id, item.id],
          );
          await txn.delete(
            'accounts',
            where: 'id = ?',
            whereArgs: [item.id],
          );
        } else {
          await txn.delete(
            'transactions',
            where: 'id = ?',
            whereArgs: [item.id],
          );
        }
      });
      notifyChanged();
    });
  }

  /// Permanently removes everything in the trash.
  Future<void> emptyTrash() {
    return _guard(() async {
      final db = await database;
      await db.transaction((txn) async {
        await txn.rawDelete('''
          DELETE FROM transactions
          WHERE deleted_at IS NOT NULL
             OR account_id IN (SELECT id FROM accounts WHERE deleted_at IS NOT NULL)
             OR to_account_id IN (SELECT id FROM accounts WHERE deleted_at IS NOT NULL)
        ''');
        await txn.delete('accounts', where: 'deleted_at IS NOT NULL');
      });
      notifyChanged();
    });
  }

  // ---------- Database screen ----------

  Future<DatabaseStats> getStats() {
    return _guard(() async {
      final db = await database;

      Future<int> count(String sql) async =>
          Sqflite.firstIntValue(await db.rawQuery(sql)) ?? 0;

      return DatabaseStats(
        accounts: await count(
          'SELECT COUNT(*) FROM accounts WHERE deleted_at IS NULL',
        ),
        transactions: await count(
          'SELECT COUNT(*) FROM transactions WHERE deleted_at IS NULL',
        ),
        categories: await count('SELECT COUNT(*) FROM categories'),
        trashed: await _countTrash(db),
      );
    });
  }

  /// Deletes everything and puts the database back to its original
  /// configuration (same tables and default data as a fresh install).
  Future<void> resetDatabase() {
    return _guard(() async {
      final db = await database;
      await _rebuild(db);
      notifyChanged();
    });
  }

  // ---------- Export / Import ----------

  /// Columns saved to / read from a backup file, in the order the tables
  /// must be filled (parents first).
  static const _exportColumns = <String, List<String>>{
    'account_types': ['id', 'name', 'icon'],
    'account_categories': ['id', 'name', 'sort_order', 'icon'],
    'accounts': [
      'id',
      'name',
      'type_id',
      'category_id',
      'initial_balance',
      'created_at',
      'deleted_at',
    ],
    'categories': ['id', 'name', 'kind', 'icon'],
    'transactions': [
      'id',
      'type',
      'amount',
      'account_id',
      'to_account_id',
      'category_id',
      'note',
      'date',
      'created_at',
      'deleted_at',
    ],
  };

  /// Every table (trash included) as one JSON text, ready to save as a file.
  Future<String> exportToJson() {
    return _guard(() async {
      final db = await database;
      final tables = <String, Object?>{};
      for (final table in _exportColumns.keys) {
        tables[table] = await db.query(table, orderBy: 'id');
      }
      return const JsonEncoder.withIndent('  ').convert({
        'app': AppConstants.exportApp,
        'format': AppConstants.exportFormat,
        'appVersion': AppConstants.appVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'tables': tables,
      });
    });
  }

  ValidationFailure get _badBackup => const ValidationFailure(
        'That file is not a valid Momentum backup.',
      );

  /// Replaces ALL current data with the data in a backup file.
  /// Everything happens in one transaction, so a bad file changes nothing.
  Future<void> importFromJson(String text) {
    return _guard(() async {
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        throw _badBackup;
      }
      if (decoded is! Map ||
          decoded['app'] != AppConstants.exportApp ||
          decoded['tables'] is! Map) {
        throw _badBackup;
      }
      final tables = decoded['tables'] as Map;

      // Keep only known columns of every row.
      final data = <String, List<Map<String, Object?>>>{};
      for (final entry in _exportColumns.entries) {
        final raw = tables[entry.key];
        if (raw is! List) throw _badBackup;
        final rows = <Map<String, Object?>>[];
        for (final row in raw) {
          if (row is! Map) throw _badBackup;
          rows.add({
            for (final column in entry.value)
              if (row.containsKey(column)) column: row[column] as Object?,
          });
        }
        data[entry.key] = rows;
      }

      // The app needs account types and the locked Transfer category.
      final hasTransfer =
          data['categories']!.any((row) => row['kind'] == 'transfer');
      if (data['account_types']!.isEmpty || !hasTransfer) throw _badBackup;

      final schema = await rootBundle.loadString(AppConstants.schemaAsset);
      final db = await database;
      try {
        await db.transaction((txn) async {
          await _dropAll(txn);
          await _runScript(txn, schema);
          for (final table in _exportColumns.keys) {
            for (final row in data[table]!) {
              await txn.insert(table, row);
            }
          }
        });
      } catch (error) {
        debugPrint('Import failed: $error');
        throw const ValidationFailure(
          'The backup file is damaged or doesn\'t match this app.',
        );
      }
      notifyChanged();
    });
  }
}