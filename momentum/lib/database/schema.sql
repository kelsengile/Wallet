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
    } catch (_) {
      _opening = null; // allow a retry next time
      rethrow;
    }
  }

  Future<Database> _open() async {
    final dir = await getDatabasesPath();
    final path = p.join(dir, AppConstants.databaseName);
    return openDatabase(
      path,
      version: AppConstants.databaseVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _runScript(db, await rootBundle.loadString(_schemaAsset));
        await _runScript(db, await rootBundle.loadString(_seedAsset));
      },
    );
  }

  /// Runs a .sql file one statement at a time (split on semicolons).
  Future<void> _runScript(Database db, String script) async {
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
    } catch (_) {
      throw const DatabaseFailure();
    }
  }

  // ---------- Categories ----------

  String _tableOf(CategoryGroup g) {
    switch (g) {
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

  /// The `kind` column value for transaction categories, null otherwise.
  String? _kindOf(CategoryGroup g) {
    switch (g) {
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

  /// Turns database errors into friendly [Failure]s.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on Failure {
      rethrow;
    } catch (e) {
      final text = e.toString();
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

  void _checkEditable(CategoryGroup g) {
    if (g == CategoryGroup.transfer) {
      throw const ValidationFailure('The Transfer category can\'t be changed.');
    }
  }

  String _cleanName(String name) {
    final text = name.trim();
    if (text.isEmpty) throw const ValidationFailure('Please enter a name.');
    return text;
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
        for (final r in rows)
          CategoryItem((r['id'] as num).toInt(), r['name'] as String),
      ];
    });
  }

  Future<void> addCategoryItem(CategoryGroup group, String name) {
    return _guard(() async {
      _checkEditable(group);
      final clean = _cleanName(name);
      final db = await database;
      final kind = _kindOf(group);
      await db.insert(_tableOf(group), {
        'name': clean,
        if (kind != null) 'kind': kind,
      });
      notifyChanged();
    });
  }

  Future<void> renameCategoryItem(CategoryGroup group, int id, String name) {
    return _guard(() async {
      _checkEditable(group);
      final clean = _cleanName(name);
      final db = await database;
      await db.update(
        _tableOf(group),
        {'name': clean},
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