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

/// The lists managed on the Categories screen.
enum CategoryGroup { accountType, accountCategory, income, expense, transfer }

/// One row of a category list.
class CategoryItem {
  final int id;
  final String name;
  const CategoryItem(this.id, this.name);
}

/// Opens the local SQLite database and holds every database function.
/// Money is stored as whole centavos, so values are divided by 100 here.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  static const _schemaAsset = 'lib/database/schema.sql';
  static const _seedAsset = 'lib/database/seed.sql';

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

  // CHANGED: no onCreate. A brand new file has no tables, so the check in
  // onOpen builds everything. One code path for new, broken and old files.
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

  /// Columns every table must have for the app's queries to work.
  static const _requiredColumns = <String, Set<String>>{
    'account_types': {'id', 'name'},
    'account_categories': {'id', 'name', 'sort_order'},
    'accounts': {
      'id',
      'name',
      'type_id',
      'category_id',
      'initial_balance',
      'deleted_at',
    },
    'categories': {'id', 'name', 'kind'},
    'transactions': {'id', 'type', 'amount', 'deleted_at'},
  };

  /// Runs every time the database opens. Rebuilds it when the tables are
  /// missing or different from schema.sql, or when the default data
  /// (seed.sql) was never fully inserted.
  Future<void> _ensureReady(Database db) async {
    final ready = await _schemaIsValid(db) && await _isSeeded(db);
    if (ready) return;
    debugPrint('Database is missing tables or default data. Rebuilding.');
    await _rebuild(db);
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

  /// Drops the finance tables and recreates them from the .sql assets.
  /// All in one transaction: it either fully works or changes nothing.
  Future<void> _rebuild(Database db) async {
    final schema = await rootBundle.loadString(_schemaAsset);
    final seed = await rootBundle.loadString(_seedAsset);
    await db.transaction((txn) async {
      // Children first, so foreign keys don't block the drops.
      await txn.execute('DROP VIEW IF EXISTS account_balances');
      await txn.execute('DROP TABLE IF EXISTS transactions');
      await txn.execute('DROP TABLE IF EXISTS accounts');
      await txn.execute('DROP TABLE IF EXISTS categories');
      await txn.execute('DROP TABLE IF EXISTS account_categories');
      await txn.execute('DROP TABLE IF EXISTS account_types');
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
        totalBalance: (balanceRow['total'] as num).toInt() / 100,
        accountCount: (balanceRow['count'] as num).toInt(),
        income: (incomeRow['total'] as num).toInt() / 100,
        expense: (expenseRow['total'] as num).toInt() / 100,
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
        columns: ['id', 'name'],
        where: kind == null ? null : 'kind = ?',
        whereArgs: kind == null ? null : [kind],
        orderBy: 'id',
      );
      return [
        for (final row in rows)
          CategoryItem((row['id'] as num).toInt(), row['name'] as String),
      ];
    });
  }

  Future<void> addCategoryItem(CategoryGroup group, String name) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      final kind = _kindOf(group);
      await db.insert(_tableOf(group), {
        'name': _cleanName(name),
        // ignore: use_null_aware_elements
        if (kind != null) 'kind': kind,
      });
      notifyChanged();
    });
  }

  Future<void> renameCategoryItem(CategoryGroup group, int id, String name) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      await db.update(
        _tableOf(group),
        {'name': _cleanName(name)},
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
}