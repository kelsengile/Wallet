import 'dart:math' as math;
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  final int reminders;
  final int trashed;

  const DatabaseStats({
    required this.accounts,
    required this.transactions,
    required this.categories,
    required this.reminders,
    required this.trashed,
  });

  static const empty = DatabaseStats(
    accounts: 0,
    transactions: 0,
    categories: 0,
    reminders: 0,
    trashed: 0,
  );
}

/// What kind of row is sitting in the trash.
enum TrashKind { account, transaction }

/// One row of the Trash screen.
/// One row of the Trash screen.
class TrashItem {
  final TrashKind kind;
  final int id;
  final String title;
  final String subtitle;
  final DateTime? deletedAt;

  /// Transactions: income | expense | transfer. Accounts: null.
  final String? txType;

  /// Accounts: the account type name (used for its icon).
  final String? typeName;

  /// Transactions: category name. Accounts: account category name.
  final String? categoryName;

  /// Saved icon key (category icon, or account type icon for accounts).
  final String? iconKey;

  /// Transactions: amount. Accounts: balance. In pesos.
  final double? amount;
  final String? accountName;
  final String? toAccountName;
  final String? note;

  const TrashItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.deletedAt,
    this.txType,
    this.typeName,
    this.categoryName,
    this.iconKey,
    this.amount,
    this.accountName,
    this.toAccountName,
    this.note,
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

  /// Saved color (ARGB int). null = automatic. Only income / expense
  /// categories use it.
  final int? color;

  /// Budget in pesos. null = no budget. Only expense categories use it.
  final double? budget;
  const CategoryItem(this.id, this.name, [this.icon, this.color, this.budget]);
}

/// An active account in a picker (Transfer From/To, Account fields).
class AccountOption {
  final int id;
  final String name;
  final int typeId;
  final String typeName;
  final String? typeIcon;
  const AccountOption(
    this.id,
    this.name,
    this.typeId,
    this.typeName,
    this.typeIcon,
  );
}

/// One saved reminder.
class ReminderItem {
  final int id;
  final String type; // 'income' | 'expense'
  final String title;
  final double amount; // pesos
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final int? accountId;
  final String? accountName;
  final DateTime dueDate;
  final String repeat; // none | daily | weekly | monthly | yearly
  final String? note;
  final String? imagePath;
  final bool done;

  const ReminderItem({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.categoryId,
    required this.categoryName,
    required this.categoryIcon,
    required this.accountId,
    required this.accountName,
    required this.dueDate,
    required this.repeat,
    required this.note,
    required this.imagePath,
    required this.done,
  });
}

/// One transaction row of the Transaction History list.
class HistoryEntry {
  final int id;
  final String type; // income | expense | transfer
  final String title;
  final double amount; // pesos
  final DateTime date;
  final int accountId;
  final int? toAccountId;
  final int? categoryId;
  final String accountName;
  final String? toAccountName;
  final String? categoryName;
  final String? categoryIcon;
  final int? categoryColor;
  final String? note;
  final String? imagePath;

  const HistoryEntry({
    required this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.date,
    required this.accountId,
    required this.toAccountId,
    required this.categoryId,
    required this.accountName,
    required this.toAccountName,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.note,
    required this.imagePath,
  });
}

/// Opens the local SQLite database and holds every database function.
/// Money is stored as whole centavos, so values are divided by
/// [AppConstants.centavosPerPeso] here.
class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  /// Appearance values kept in SharedPreferences that go in a backup.
  /// Add a key here to back up more.
  static const _appearancePrefs = <String>[
    AppConstants.prefTheme,
    AppConstants.prefColor,
    AppConstants.prefAccent,
    AppConstants.prefText,
    AppConstants.prefIncomeColor,
    AppConstants.prefExpenseColor,
    AppConstants.prefTransferColor,
    AppConstants.prefReminderColor,
    AppConstants.prefDeleteColor,
    AppConstants.prefDoneColor,
  ];

  /// Settings > Appearance / Theme values that Clear all data resets.
  static const _designPrefs = <String>[
    ..._appearancePrefs,
    AppConstants.prefTextSize,
    AppConstants.prefFontStyle,
    AppConstants.prefBoldText,
    AppConstants.prefAnimEnabled,
    AppConstants.prefAnimSpeed,
    AppConstants.prefCurrency,
    AppConstants.prefLocation,
    AppConstants.prefLanguage,
  ];

  Future<void> _clearDesignPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in _designPrefs) {
      await prefs.remove(key);
    }
  }

  Future<Map<String, Object?>> _readAppearance() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      for (final key in _appearancePrefs)
        if (prefs.containsKey(key)) key: prefs.get(key),
    };
  }

  /// Puts the backed-up values back. A key missing from the backup means it
  /// was at its default, so it is cleared. Old backups without an
  /// "appearance" section leave the current colors alone.
  Future<void> _writeAppearance(Object? raw) async {
    if (raw is! Map) return;
    final prefs = await SharedPreferences.getInstance();
    for (final key in _appearancePrefs) {
      if (!raw.containsKey(key)) {
        await prefs.remove(key);
        continue;
      }
      final value = raw[key];
      if (value is bool) {
        await prefs.setBool(key, value);
      } else if (value is int) {
        await prefs.setInt(key, value);
      } else if (value is double) {
        await prefs.setDouble(key, value);
      } else if (value is String) {
        await prefs.setString(key, value);
      } else if (value is List) {
        await prefs.setStringList(key, [for (final item in value) '$item']);
      }
    }
  }

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

  /// Default icon key of each seed item. Same keys as the Categories screen.
  /// Written into the `icon` column so every screen reads it from the database.
  static const _defaultIcons = <String, Map<String, String>>{
    'account_types': {
      'Cash': 'cash',
      'Bank': 'bank',
      'Digital Bank': 'phone',
      'Credit': 'card',
      'E-Wallet': 'wallet',
      'Investment': 'trending',
      'Assets': 'home',
      'Debt': 'handshake',
      'Business': 'business',
    },
    'account_categories': {
      'Personal': 'star',
      'Family': 'family',
      'Savings': 'savings',
      'Future': 'flag',
      'Work': 'work',
      'Travel': 'flight',
      'Health': 'medical',
      'Investment': 'trending',
      'Debt': 'card',
      'Emergency': 'heart',
      'Spending': 'shopping',
    },
    'categories': {
      'Salary': 'cash',
      'Bonus': 'gift',
      'Commission': 'handshake',
      'Allowance': 'wallet',
      'Freelance': 'work',
      'Business': 'business',
      'Investment': 'trending',
      'Gift': 'gift',
      'Scholarship': 'school',
      'Refund': 'receipt',
      'Loan': 'bank',
      'Miscellaneous': 'shapes',
      'Food': 'food',
      'Transportation': 'car',
      'Shopping': 'shopping',
      'Bills': 'receipt',
      'Health': 'medical',
      'Education': 'school',
      'Entertainment': 'movie',
      'Tax': 'bank',
      'Debt': 'card',
      'Travel': 'flight',
      'Sports': 'fitness',
      'Transfer': 'swap',
    },
  };

  /// Fills empty icons with the defaults above. Icons that were already
  /// saved (chosen by the user) are never touched.
  Future<void> _fillDefaultIcons(DatabaseExecutor db) async {
    for (final table in _defaultIcons.entries) {
      for (final item in table.value.entries) {
        await db.rawUpdate(
          'UPDATE ${table.key} SET icon = ? WHERE name = ? AND icon IS NULL',
          [item.value, item.key],
        );
      }
    }
  }

  /// Runs every time the database opens. Adds missing columns and tables to
  /// older files, then rebuilds the database only when the tables are missing
  /// or different from schema.sql, or when the default data was never
  /// inserted.
  Future<void> _ensureReady(Database db) async {
    await _addMissingIconColumns(db);
    await _addMissingColorColumn(db);
    await _addMissingNoteColumns(db);
    await _addMissingTransactionColumns(db);
    await _addMissingTables(db);
    await _addMissingBudgetColumn(db);
    final ready = await _schemaIsValid(db) && await _isSeeded(db);
    if (ready) {
      await _fillDefaultIcons(db);
      return;
    }
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

  /// Older databases get the `color` column without losing data.
  Future<void> _addMissingColorColumn(Database db) async {
    for (final table in _iconTables) {
      final columns = await _columnsOf(db, table);
      if (columns.isNotEmpty && !columns.contains('color')) {
        await db.execute('ALTER TABLE $table ADD COLUMN color INTEGER');
      }
    }
  }

  /// Older databases get the account note columns without losing any data.
  Future<void> _addMissingNoteColumns(Database db) async {
    final columns = await _columnsOf(db, 'accounts');
    if (columns.isEmpty) return;
    for (final column in const ['note_title', 'note_body']) {
      if (!columns.contains(column)) {
        await db.execute('ALTER TABLE accounts ADD COLUMN $column TEXT');
      }
    }
  }

  /// Older databases get the transaction title / image columns.
  Future<void> _addMissingTransactionColumns(Database db) async {
    final columns = await _columnsOf(db, 'transactions');
    if (columns.isEmpty) return;
    for (final column in const ['title', 'image_path']) {
      if (!columns.contains(column)) {
        await db.execute('ALTER TABLE transactions ADD COLUMN $column TEXT');
      }
    }
  }

  /// schema.sql is all "IF NOT EXISTS", so running it only adds what is
  /// missing (for example the reminders table) and never touches data.
  Future<void> _addMissingTables(Database db) async {
    final schema = await rootBundle.loadString(AppConstants.schemaAsset);
    await _runScript(db, schema);
  }

  /// Older databases get the expense-category budget column without losing
  /// any data.
  Future<void> _addMissingBudgetColumn(DatabaseExecutor db) async {
    final rows = await db.rawQuery('PRAGMA table_info(categories)');
    final columns = {for (final row in rows) row['name'] as String};
    if (columns.isNotEmpty && !columns.contains('budget')) {
      await db.execute('ALTER TABLE categories ADD COLUMN budget INTEGER');
    }
  }

  Future<Set<String>> _columnsOf(Database db, String table) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    return {for (final row in rows) row['name'] as String};
  }

  Future<bool> _schemaIsValid(Database db) async {
    for (final entry in _exportColumns.entries) {
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
    final transfer =
        Sqflite.firstIntValue(
          await db.rawQuery(
            "SELECT COUNT(*) FROM categories WHERE kind = 'transfer'",
          ),
        ) ??
        0;
    final types =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM account_types'),
        ) ??
        0;
    return transfer > 0 && types > 0;
  }

  /// Drops every finance table. Children first, so foreign keys don't
  /// block the drops.
  Future<void> _dropAll(DatabaseExecutor db) async {
    await db.execute('DROP VIEW IF EXISTS account_balances');
    await db.execute('DROP TABLE IF EXISTS reminders');
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
      await _addMissingBudgetColumn(txn);
      await _runScript(txn, seed);
      await _fillDefaultIcons(txn);
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
        totalBalance:
            (balanceRow['total'] as num).toInt() / AppConstants.centavosPerPeso,
        accountCount: (balanceRow['count'] as num).toInt(),
        income:
            (incomeRow['total'] as num).toInt() / AppConstants.centavosPerPeso,
        expense:
            (expenseRow['total'] as num).toInt() / AppConstants.centavosPerPeso,
      );
    } catch (error) {
      debugPrint('getAccountsSummary failed: $error');
      throw const DatabaseFailure();
    }
  }

  int _imageCounter = 0;

  // ---------- Settings (name / value) ----------

  Future<Map<String, String>> getAllSettings() {
    return _guard(() async {
      final db = await database;
      final rows = await db.query('settings');
      return {for (final r in rows) r['name'] as String: r['value'] as String};
    });
  }

  /// No notifyChanged here: settings must not reload the finance screens.
  Future<void> setSetting(String name, String value) {
    return _guard(() async {
      final db = await database;
      await db.insert('settings', {
        'name': name,
        'value': value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> removeSetting(String name) {
    return _guard(() async {
      final db = await database;
      await db.delete('settings', where: 'name = ?', whereArgs: [name]);
    });
  }

  /// Reads a comma-separated list of ids saved in the settings table.
  Future<List<int>> _readIdList(DatabaseExecutor db, String name) async {
    final rows = await db.query(
      'settings',
      columns: ['value'],
      where: 'name = ?',
      whereArgs: [name],
    );
    if (rows.isEmpty) return <int>[];
    return [
      for (final s in (rows.first['value'] as String).split(','))
        if (int.tryParse(s) != null) int.parse(s),
    ];
  }

  /// Saved order of the account type ids on the Finance screen.
  Future<List<int>> getTypeOrder() {
    return _guard(
      () async => _readIdList(await database, AppConstants.prefTypeOrder),
    );
  }

  Future<void> saveTypeOrder(List<int> ids) =>
      setSetting(AppConstants.prefTypeOrder, ids.join(','));

  // ---------- Category order (Categories screen) ----------

  String _categoryOrderKey(CategoryGroup group) =>
      '${AppConstants.prefCategoryOrder}${group.name}';

  /// Saves the drag order of one list. No notifyChanged, so the screen
  /// doesn't reload while the user is dragging.
  Future<void> saveCategoryOrder(CategoryGroup group, List<int> ids) =>
      setSetting(_categoryOrderKey(group), ids.join(','));

  /// Sorts by the saved order. Items not in the saved order yet (new ones)
  /// go to the end, in id order.
  List<CategoryItem> _applyOrder(List<CategoryItem> items, List<int> saved) {
    if (saved.isEmpty) return items;
    final rank = {for (var i = 0; i < saved.length; i++) saved[i]: i};
    const last = 1 << 30;
    final sorted = [...items];
    sorted.sort((a, b) {
      final ra = rank[a.id] ?? last;
      final rb = rank[b.id] ?? last;
      return ra != rb ? ra.compareTo(rb) : a.id.compareTo(b.id);
    });
    return sorted;
  }

  /// Pesos -> whole centavos. Refuses numbers too big for the database
  /// instead of crashing.
  int _toCentavos(double pesos) {
    final centavos = pesos * AppConstants.centavosPerPeso;
    if (!centavos.isFinite) {
      throw const ValidationFailure('That balance is too big.');
    }
    return centavos.clamp(-9.0e18, 9.0e18).round();
  }

  /// Adds a new account and returns its id. [initialBalance] is in pesos.
  Future<int> addAccount({
    required String name,
    required int typeId,
    required int categoryId,
    double initialBalance = 0,
    String? noteTitle,
    String? noteBody,
  }) {
    return _guard(() async {
      final db = await database;
      final title = noteTitle?.trim();
      final body = noteBody?.trim();
      final id = await db.insert('accounts', {
        'name': _cleanName(name),
        'type_id': typeId,
        'category_id': categoryId,
        'initial_balance': _toCentavos(initialBalance),
        'note_title': (title == null || title.isEmpty) ? null : title,
        'note_body': (body == null || body.isEmpty) ? null : body,
      });
      notifyChanged();
      return id;
    });
  }

  /// Saves changes to an existing account (the balance is not changed here).
  Future<void> updateAccount({
    required int id,
    required String name,
    required int typeId,
    required int categoryId,
    String? noteTitle,
    String? noteBody,
  }) {
    return _guard(() async {
      final db = await database;
      await db.update(
        'accounts',
        {
          'name': _cleanName(name),
          'type_id': typeId,
          'category_id': categoryId,
          'note_title': _nonEmpty(noteTitle),
          'note_body': _nonEmpty(noteBody),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      notifyChanged();
    });
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

  /// Items of one list, in the order set on the Categories screen.
  Future<List<CategoryItem>> getCategoryItems(CategoryGroup group) {
    return _guard(() async {
      final db = await database;
      final kind = _kindOf(group);
      final isCategories = _tableOf(group) == 'categories';
      final rows = await db.query(
        _tableOf(group),
        columns: [
          'id',
          'name',
          'icon',
          'color',
          if (isCategories) 'budget',
        ],
        where: kind == null ? null : 'kind = ?',
        whereArgs: kind == null ? null : [kind],
        orderBy: 'id',
      );
      final items = [
        for (final row in rows)
          CategoryItem(
            (row['id'] as num).toInt(),
            row['name'] as String,
            row['icon'] as String?,
            (row['color'] as num?)?.toInt(),
            (row['budget'] as num?) == null
                ? null
                : (row['budget'] as num).toInt() /
                      AppConstants.centavosPerPeso,
          ),
      ];
      return _applyOrder(
        items,
        await _readIdList(db, _categoryOrderKey(group)),
      );
    });
  }

  Future<void> addCategoryItem(
    CategoryGroup group,
    String name, {
    String? icon,
    int? color,
    double? budget,
  }) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      final kind = _kindOf(group);
      await db.insert(_tableOf(group), {
        'name': _cleanName(name),
        'icon': icon,
        'color': color,
        if (_tableOf(group) == 'categories')
          'budget': budget == null ? null : _positiveCentavos(budget),
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
    int? color,
    double? budget,
  }) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      final oldIcon = await _iconOf(db, group, id);
      await db.update(
        _tableOf(group),
        {
          'name': _cleanName(name),
          'icon': icon,
          if (_tableOf(group) == 'categories') 'color': color,
          if (_tableOf(group) == 'categories')
            'budget': budget == null ? null : _positiveCentavos(budget),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      if (oldIcon != icon) await _deleteImageFiles([_iconImageOf(oldIcon)]);
      notifyChanged();
    });
  }

  Future<void> deleteCategoryItem(CategoryGroup group, int id) {
    return _guard(() async {
      _checkEditable(group);
      final db = await database;
      final oldIcon = await _iconOf(db, group, id);
      await db.delete(_tableOf(group), where: 'id = ?', whereArgs: [id]);
      await _deleteImageFiles([_iconImageOf(oldIcon)]);
      notifyChanged();
    });
  }

  // ---------- Transactions ----------
  // Account balances come from the account_balances view, so every
  // insert below updates the balance of the account(s) automatically.

  String? _nonEmpty(String? text) {
    final t = text?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  /// Removes picture files that no row points to anymore.
  /// Never throws: a missing file is simply ignored.
  Future<void> _deleteImageFiles(Iterable<Object?> paths) async {
    for (final path in paths) {
      if (path is! String || path.isEmpty) continue;
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }

  int _positiveCentavos(double pesos) {
    final centavos = _toCentavos(pesos);
    if (centavos <= 0) {
      throw const ValidationFailure('Enter an amount greater than zero.');
    }
    return centavos;
  }

  Future<void> _requireActiveAccount(DatabaseExecutor db, int id) async {
    final found =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM accounts WHERE id = ? AND deleted_at IS NULL',
            [id],
          ),
        ) ??
        0;
    if (found == 0) {
      throw const ValidationFailure('That account no longer exists.');
    }
  }

  /// Active accounts for the pickers, grouped by type order.
  Future<List<AccountOption>> getAccountOptions() {
    return _guard(() async {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT a.id, a.name, t.id AS type_id, t.name AS type_name,
               t.icon AS type_icon
        FROM accounts a
        JOIN account_types t ON t.id = a.type_id
        WHERE a.deleted_at IS NULL
        ORDER BY t.id, a.id
      ''');
      return [
        for (final row in rows)
          AccountOption(
            (row['id'] as num).toInt(),
            row['name'] as String,
            (row['type_id'] as num).toInt(),
            row['type_name'] as String,
            row['type_icon'] as String?,
          ),
      ];
    });
  }

  /// Adds an income or expense. [amount] is in pesos.
  Future<void> addTransaction({
    required String type,
    required String title,
    required double amount,
    required DateTime date,
    required int accountId,
    required int categoryId,
    String? note,
    String? imagePath,
  }) {
    return _guard(() async {
      if (type != 'income' && type != 'expense') {
        throw const ValidationFailure('Unknown transaction type.');
      }
      final centavos = _positiveCentavos(amount);
      final db = await database;
      await db.transaction((txn) async {
        await _requireActiveAccount(txn, accountId);
        await txn.insert('transactions', {
          'type': type,
          'amount': centavos,
          'account_id': accountId,
          'category_id': categoryId,
          'title': _cleanName(title),
          'note': _nonEmpty(note),
          'image_path': imagePath,
          'date': date.toIso8601String(),
        });
      });
      notifyChanged();
    });
  }

  /// Moves money between two accounts: takes it from [fromAccountId] and
  /// adds it to [toAccountId] (both balances change).
  Future<void> addTransfer({
    required String title,
    required double amount,
    required DateTime date,
    required int fromAccountId,
    required int toAccountId,
    String? note,
    String? imagePath,
  }) {
    return _guard(() async {
      if (fromAccountId == toAccountId) {
        throw const ValidationFailure('Pick two different accounts.');
      }
      final centavos = _positiveCentavos(amount);
      final db = await database;
      await db.transaction((txn) async {
        await _requireActiveAccount(txn, fromAccountId);
        await _requireActiveAccount(txn, toAccountId);
        final categoryId = Sqflite.firstIntValue(
          await txn.rawQuery(
            "SELECT id FROM categories WHERE kind = 'transfer' LIMIT 1",
          ),
        );
        await txn.insert('transactions', {
          'type': 'transfer',
          'amount': centavos,
          'account_id': fromAccountId,
          'to_account_id': toAccountId,
          'category_id': categoryId,
          'title': _cleanName(title),
          'note': _nonEmpty(note),
          'image_path': imagePath,
          'date': date.toIso8601String(),
        });
      });
      notifyChanged();
    });
  }

  // ---------- Reminders ----------

  static const _repeatRules = ['none', 'daily', 'weekly', 'monthly', 'yearly'];

  Future<void> addReminder({
    required String type,
    required String title,
    required double amount,
    required DateTime dueDate,
    int? categoryId,
    int? accountId,
    String repeat = 'none',
    String? note,
    String? imagePath,
  }) {
    return _guard(() async {
      if (type != 'income' && type != 'expense') {
        throw const ValidationFailure('Unknown reminder type.');
      }
      if (!_repeatRules.contains(repeat)) {
        throw const ValidationFailure('Unknown repeat option.');
      }
      final centavos = _positiveCentavos(amount);
      final db = await database;
      await db.transaction((txn) async {
        if (accountId != null) await _requireActiveAccount(txn, accountId);
        await txn.insert('reminders', {
          'type': type,
          'title': _cleanName(title),
          'amount': centavos,
          'category_id': categoryId,
          'account_id': accountId,
          'due_date': dueDate.toIso8601String(),
          'repeat_rule': repeat,
          'note': _nonEmpty(note),
          'image_path': imagePath,
        });
      });
      notifyChanged();
    });
  }

  /// Reminders that are not done, soonest first.
  Future<List<ReminderItem>> getReminders() {
    return _guard(() async {
      final db = await database;
      final rows = await db.rawQuery('''
        SELECT r.*, c.name AS category_name, c.icon AS category_icon,
               a.name AS account_name
        FROM reminders r
        LEFT JOIN categories c ON c.id = r.category_id
        LEFT JOIN accounts a ON a.id = r.account_id
        WHERE r.done = 0
        ORDER BY r.due_date
      ''');
      return [
        for (final row in rows)
          ReminderItem(
            id: (row['id'] as num).toInt(),
            type: row['type'] as String,
            title: row['title'] as String,
            amount:
                (row['amount'] as num).toInt() / AppConstants.centavosPerPeso,
            categoryId: (row['category_id'] as num?)?.toInt(),
            categoryName: row['category_name'] as String?,
            categoryIcon: row['category_icon'] as String?,
            accountId: (row['account_id'] as num?)?.toInt(),
            accountName: row['account_name'] as String?,
            dueDate: DateTime.tryParse('${row['due_date']}') ?? DateTime.now(),
            repeat: row['repeat_rule'] as String,
            note: row['note'] as String?,
            imagePath: row['image_path'] as String?,
            done: (row['done'] as num).toInt() == 1,
          ),
      ];
    });
  }

  /// Transactions (not trashed) between [from] (inclusive) and [until]
  /// (exclusive), newest first. Both null = everything.
  Future<List<HistoryEntry>> getHistory({DateTime? from, DateTime? until}) {
    return _guard(() async {
      final db = await database;
      final where = <String>['t.deleted_at IS NULL', 'a.deleted_at IS NULL'];
      final args = <Object?>[];
      if (from != null) {
        where.add('t.date >= ?');
        args.add(from.toIso8601String());
      }
      if (until != null) {
        where.add('t.date < ?');
        args.add(until.toIso8601String());
      }
      final rows = await db.rawQuery('''
        SELECT t.*, c.name AS category_name, c.icon AS category_icon,
               c.color AS category_color,
               a.name AS account_name, b.name AS to_account_name
        FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        LEFT JOIN accounts b ON b.id = t.to_account_id
        LEFT JOIN categories c ON c.id = t.category_id
        WHERE ${where.join(' AND ')}
        ORDER BY t.date DESC, t.id DESC
      ''', args);
      return [
        for (final row in rows)
          HistoryEntry(
            id: (row['id'] as num).toInt(),
            type: row['type'] as String,
            title:
                _nonEmpty(row['title'] as String?) ??
                _nonEmpty(row['category_name'] as String?) ??
                _capitalize(row['type'] as String),
            amount:
                (row['amount'] as num).toInt() / AppConstants.centavosPerPeso,
            date: DateTime.tryParse('${row['date']}') ?? DateTime.now(),
            accountId: (row['account_id'] as num).toInt(),
            toAccountId: (row['to_account_id'] as num?)?.toInt(),
            categoryId: (row['category_id'] as num?)?.toInt(),
            accountName: row['account_name'] as String,
            toAccountName: row['to_account_name'] as String?,
            categoryName: row['category_name'] as String?,
            categoryIcon: row['category_icon'] as String?,
            categoryColor: (row['category_color'] as num?)?.toInt(),
            note: row['note'] as String?,
            imagePath: row['image_path'] as String?,
          ),
      ];
    });
  }

  /// Saves the changes of an existing transaction (the type never changes).
  Future<void> updateTransaction({
    required int id,
    required String type,
    required String title,
    required double amount,
    required DateTime date,
    required int accountId,
    int? toAccountId,
    int? categoryId,
    String? note,
    String? imagePath,
  }) {
    return _guard(() async {
      final centavos = _positiveCentavos(amount);
      final db = await database;
      String? oldImage;
      await db.transaction((txn) async {
        await _requireActiveAccount(txn, accountId);
        if (type == 'transfer') {
          if (toAccountId == null || toAccountId == accountId) {
            throw const ValidationFailure('Pick two different accounts.');
          }
          await _requireActiveAccount(txn, toAccountId);
        }
        final old = await txn.query(
          'transactions',
          columns: ['image_path'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (old.isNotEmpty) oldImage = old.first['image_path'] as String?;
        await txn.update(
          'transactions',
          {
            'amount': centavos,
            'account_id': accountId,
            'to_account_id': type == 'transfer' ? toAccountId : null,
            if (type != 'transfer') 'category_id': categoryId,
            'title': _cleanName(title),
            'note': _nonEmpty(note),
            'image_path': imagePath,
            'date': date.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });
      if (oldImage != null && oldImage != imagePath) {
        await _deleteImageFiles([oldImage]);
      }
      notifyChanged();
    });
  }

  /// Saves the changes of an existing (not done) reminder.
  Future<void> updateReminder({
    required int id,
    required String type,
    required String title,
    required double amount,
    required DateTime dueDate,
    int? categoryId,
    int? accountId,
    String repeat = 'none',
    String? note,
    String? imagePath,
  }) {
    return _guard(() async {
      if (type != 'income' && type != 'expense') {
        throw const ValidationFailure('Unknown reminder type.');
      }
      if (!_repeatRules.contains(repeat)) {
        throw const ValidationFailure('Unknown repeat option.');
      }
      final centavos = _positiveCentavos(amount);
      final db = await database;
      String? oldImage;
      await db.transaction((txn) async {
        if (accountId != null) await _requireActiveAccount(txn, accountId);
        final old = await txn.query(
          'reminders',
          columns: ['image_path'],
          where: 'id = ?',
          whereArgs: [id],
        );
        if (old.isNotEmpty) oldImage = old.first['image_path'] as String?;
        await txn.update(
          'reminders',
          {
            'type': type,
            'title': _cleanName(title),
            'amount': centavos,
            'category_id': categoryId,
            'account_id': accountId,
            'due_date': dueDate.toIso8601String(),
            'repeat_rule': repeat,
            'note': _nonEmpty(note),
            'image_path': imagePath,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      });
      if (oldImage != null && oldImage != imagePath) {
        await _deleteImageFiles([oldImage]);
      }
      notifyChanged();
    });
  }

  DateTime? _nextDue(DateTime d, String repeat) {
    switch (repeat) {
      case 'daily':
        return DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
      case 'weekly':
        return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute);
      case 'monthly':
        final lastDay = DateTime(d.year, d.month + 2, 0).day;
        return DateTime(
          d.year,
          d.month + 1,
          math.min(d.day, lastDay),
          d.hour,
          d.minute,
        );
      case 'yearly':
        final day = (d.month == 2 && d.day == 29) ? 28 : d.day;
        return DateTime(d.year + 1, d.month, day, d.hour, d.minute);
      default:
        return null;
    }
  }

  /// Marks a reminder as done and turns it into a regular transaction
  /// (dated now). A repeating reminder also schedules its next one.
  Future<void> completeReminder(ReminderItem r, {required int accountId}) {
    return _guard(() async {
      final db = await database;
      await db.transaction((txn) async {
        await _requireActiveAccount(txn, accountId);
        await txn.insert('transactions', {
          'type': r.type,
          'amount': _positiveCentavos(r.amount),
          'account_id': accountId,
          'category_id': r.categoryId,
          'title': r.title,
          'note': _nonEmpty(r.note),
          'image_path': r.imagePath,
          'date': DateTime.now().toIso8601String(),
        });
        await txn.update(
          'reminders',
          {'done': 1, 'account_id': accountId},
          where: 'id = ?',
          whereArgs: [r.id],
        );
        final next = _nextDue(r.dueDate, r.repeat);
        if (next != null) {
          await txn.insert('reminders', {
            'type': r.type,
            'title': r.title,
            'amount': _positiveCentavos(r.amount),
            'category_id': r.categoryId,
            'account_id': accountId,
            'due_date': next.toIso8601String(),
            'repeat_rule': r.repeat,
            'note': _nonEmpty(r.note),
            'image_path': null,
          });
        }
      });
      notifyChanged();
    });
  }

  Future<void> deleteReminder(int id) {
    return _guard(() async {
      final db = await database;
      final rows = await db.query(
        'reminders',
        columns: ['image_path'],
        where: 'id = ?',
        whereArgs: [id],
      );
      await db.delete('reminders', where: 'id = ?', whereArgs: [id]);
      await _deleteImageFiles(rows.map((r) => r['image_path']));
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

      final accountRows = await db.rawQuery('''
        SELECT a.id, a.name, a.deleted_at,
               t.name AS type_name, t.icon AS type_icon,
               c.name AS category_name,
               b.balance AS balance
        FROM accounts a
        JOIN account_types t ON t.id = a.type_id
        JOIN account_categories c ON c.id = a.category_id
        LEFT JOIN account_balances b ON b.account_id = a.id
        WHERE a.deleted_at IS NOT NULL
      ''');
      final transactionRows = await db.rawQuery('''
        SELECT t.id, t.type, t.amount, t.note, t.title, t.deleted_at,
               c.name AS category_name, c.icon AS category_icon,
               a.name AS account_name, b.name AS to_account_name
        FROM transactions t
        JOIN accounts a ON a.id = t.account_id
        LEFT JOIN accounts b ON b.id = t.to_account_id
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
            typeName: row['type_name'] as String?,
            categoryName: row['category_name'] as String?,
            iconKey: row['type_icon'] as String?,
            amount:
                ((row['balance'] as num?) ?? 0).toInt() /
                AppConstants.centavosPerPeso,
          ),
        for (final row in transactionRows)
          TrashItem(
            kind: TrashKind.transaction,
            id: (row['id'] as num).toInt(),
            title:
                _nonEmpty(row['title'] as String?) ??
                _nonEmpty(row['category_name'] as String?) ??
                _capitalize(row['type'] as String),
            subtitle: _transactionSubtitle(row),
            deletedAt: DateTime.tryParse('${row['deleted_at']}'),
            txType: row['type'] as String,
            categoryName: row['category_name'] as String?,
            iconKey: row['category_icon'] as String?,
            amount:
                (row['amount'] as num).toInt() / AppConstants.centavosPerPeso,
            accountName: row['account_name'] as String?,
            toAccountName: row['to_account_name'] as String?,
            note: row['note'] as String?,
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
    final accounts =
        Sqflite.firstIntValue(
          await db.rawQuery(
            'SELECT COUNT(*) FROM accounts WHERE deleted_at IS NOT NULL',
          ),
        ) ??
        0;
    final transactions =
        Sqflite.firstIntValue(
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
  /// the transactions that use it (and their pictures).
  Future<void> deleteTrashItemForever(TrashItem item) {
    return _guard(() async {
      final db = await database;
      final images = <Object?>[];
      await db.transaction((txn) async {
        if (item.kind == TrashKind.account) {
          final rows = await txn.query(
            'transactions',
            columns: ['image_path'],
            where: 'account_id = ? OR to_account_id = ?',
            whereArgs: [item.id, item.id],
          );
          images.addAll(rows.map((r) => r['image_path']));
          await txn.delete(
            'transactions',
            where: 'account_id = ? OR to_account_id = ?',
            whereArgs: [item.id, item.id],
          );
          await txn.delete('accounts', where: 'id = ?', whereArgs: [item.id]);
        } else {
          final rows = await txn.query(
            'transactions',
            columns: ['image_path'],
            where: 'id = ?',
            whereArgs: [item.id],
          );
          images.addAll(rows.map((r) => r['image_path']));
          await txn.delete(
            'transactions',
            where: 'id = ?',
            whereArgs: [item.id],
          );
        }
      });
      await _deleteImageFiles(images);
      notifyChanged();
    });
  }

  /// Permanently removes everything in the trash (and the pictures).
  Future<void> emptyTrash() {
    return _guard(() async {
      final db = await database;
      final images = <Object?>[];
      await db.transaction((txn) async {
        const doomed = '''
          deleted_at IS NOT NULL
          OR account_id IN (SELECT id FROM accounts WHERE deleted_at IS NOT NULL)
          OR to_account_id IN (SELECT id FROM accounts WHERE deleted_at IS NOT NULL)
        ''';
        final rows = await txn.rawQuery(
          'SELECT image_path FROM transactions WHERE $doomed',
        );
        images.addAll(rows.map((r) => r['image_path']));
        await txn.rawDelete('DELETE FROM transactions WHERE $doomed');
        await txn.delete('accounts', where: 'deleted_at IS NOT NULL');
      });
      await _deleteImageFiles(images);
      notifyChanged();
    });
  }

    /// Permanently removes everything that was deleted in an EARLIER month
  /// (so the trash is cleaned at the end of every month). Returns how many
  /// rows were removed. Called when the app starts and when Trash opens.
  Future<int> purgeExpiredTrash() {
    return _guard(() async {
      final db = await database;
      final now = DateTime.now();
      final cutoff = DateTime(now.year, now.month).toIso8601String();
      final images = <Object?>[];
      var removed = 0;

      await db.transaction((txn) async {
        // Old trashed accounts go with all of their transactions.
        final accounts = await txn.query(
          'accounts',
          columns: ['id'],
          where: 'deleted_at IS NOT NULL AND deleted_at < ?',
          whereArgs: [cutoff],
        );
        for (final row in accounts) {
          final id = (row['id'] as num).toInt();
          final rows = await txn.query(
            'transactions',
            columns: ['image_path'],
            where: 'account_id = ? OR to_account_id = ?',
            whereArgs: [id, id],
          );
          images.addAll(rows.map((r) => r['image_path']));
          await txn.delete(
            'transactions',
            where: 'account_id = ? OR to_account_id = ?',
            whereArgs: [id, id],
          );
          await txn.delete('accounts', where: 'id = ?', whereArgs: [id]);
          removed++;
        }

        // Old trashed transactions.
        final txRows = await txn.query(
          'transactions',
          columns: ['image_path'],
          where: 'deleted_at IS NOT NULL AND deleted_at < ?',
          whereArgs: [cutoff],
        );
        images.addAll(txRows.map((r) => r['image_path']));
        removed += await txn.delete(
          'transactions',
          where: 'deleted_at IS NOT NULL AND deleted_at < ?',
          whereArgs: [cutoff],
        );
      });

      await _deleteImageFiles(images);
      if (removed > 0) notifyChanged();
      return removed;
    });
  }

  /// Multiplies every saved amount by [rate] (old currency -> new currency):
  /// account starting balances, transactions, reminders and budgets.
  Future<void> convertAmounts(double rate) {
    return _guard(() async {
      if (!rate.isFinite || rate <= 0 || rate > 1e7) {
        throw const ValidationFailure('Enter a valid exchange rate.');
      }
      final db = await database;
      await db.transaction((txn) async {
        await txn.rawUpdate(
          'UPDATE accounts SET initial_balance = '
          'CAST(ROUND(initial_balance * ?) AS INTEGER)',
          [rate],
        );
        await txn.rawUpdate(
          'UPDATE transactions SET amount = '
          'MAX(1, CAST(ROUND(amount * ?) AS INTEGER))',
          [rate],
        );
        await txn.rawUpdate(
          'UPDATE reminders SET amount = '
          'MAX(1, CAST(ROUND(amount * ?) AS INTEGER))',
          [rate],
        );
        await txn.rawUpdate(
          'UPDATE categories SET budget = '
          'MAX(1, CAST(ROUND(budget * ?) AS INTEGER)) '
          'WHERE budget IS NOT NULL',
          [rate],
        );
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
        reminders: await count('SELECT COUNT(*) FROM reminders WHERE done = 0'),
        trashed: await _countTrash(db),
      );
    });
  }

  /// Deletes everything and puts the database back to its original
  /// configuration (same tables and default data as a fresh install).
  /// Saved pictures are removed too.
  Future<void> resetDatabase() {
    return _guard(() async {
      final db = await database;
      final images = <Object?>[
        ...(await db.rawQuery('SELECT image_path FROM transactions'))
            .map((r) => r['image_path']),
        ...(await db.rawQuery('SELECT image_path FROM reminders'))
            .map((r) => r['image_path']),
        for (final t in _iconTables)
          ...(await db.query(
            t,
            columns: ['icon'],
          )).map((r) => _iconImageOf(r['icon'])),
        for (final r in await db.query(
          'settings',
          columns: ['value'],
          where: 'name = ?',
          whereArgs: [AppConstants.prefIconLibrary],
        ))
          ..._libraryPaths(r['value']),
        for (final r in await db.query(
          'settings',
          columns: ['value'],
          where: 'name LIKE ?',
          whereArgs: ['$_themePrefix%'],
        ))
          _themeImageOf(r['value']),
      ];
      await _rebuild(db);
      await db.delete(
        'settings',
        where: 'name LIKE ? OR name = ? OR name LIKE ? OR name LIKE ?',
        whereArgs: [
          '${AppConstants.prefCategoryOrder}%',
          AppConstants.prefTypeOrder,
          'categoryIcons.%',
          '$_themePrefix%',
        ],
      );
      for (final key in _designPrefs) {
        await db.delete('settings', where: 'name = ?', whereArgs: [key]);
      }
      await _clearDesignPrefs();
      await _deleteImageFiles(images);
      notifyChanged();
    });
  }

  // ---------- Export / Import ----------

  /// Columns saved to / read from a backup file, in the order the tables
  /// must be filled (parents first).
  static const _exportColumns = <String, List<String>>{
    'account_types': ['id', 'name', 'icon', 'color'],
    'account_categories': ['id', 'name', 'sort_order', 'icon', 'color'],
    'accounts': [
      'id',
      'name',
      'type_id',
      'category_id',
      'initial_balance',
      'note_title',
      'note_body',
      'created_at',
      'deleted_at',
    ],
    'categories': ['id', 'name', 'kind', 'icon', 'color', 'budget'],
    'transactions': [
      'id',
      'type',
      'amount',
      'account_id',
      'to_account_id',
      'category_id',
      'title',
      'note',
      'image_path',
      'date',
      'created_at',
      'deleted_at',
    ],
    'reminders': [
      'id',
      'type',
      'title',
      'amount',
      'category_id',
      'account_id',
      'due_date',
      'repeat_rule',
      'note',
      'image_path',
      'done',
      'created_at',
    ],
    'settings': ['name', 'value'],
  };

  /// Every table (trash included) as one JSON text, ready to save as a file.
  Future<String> exportToJson() {
    return _guard(() async {
      final db = await database;
      final tables = <String, Object?>{};
      for (final table in _exportColumns.keys) {
        final rows = await db.query(table, orderBy: 'rowid');
        tables[table] = switch (table) {
          'account_types' ||
          'account_categories' ||
          'categories' => [for (final row in rows) await _withIconImage(row)],
          'transactions' ||
          'reminders' => [for (final row in rows) await _withImage(row)],
          'settings' => [for (final row in rows) await _withThemeImage(row)],
          _ => rows,
        };
      }
      final appearance = await _readAppearance();
      return JsonEncoder.withIndent('  ').convert({
        'app': AppConstants.exportApp,
        'format': AppConstants.exportFormat,
        'appVersion': AppConstants.appVersion,
        'exportedAt': DateTime.now().toIso8601String(),
        'appearance': appearance,
        'tables': tables,
      });
    });
  }

  ValidationFailure get _badBackup =>
      const ValidationFailure('That file is not a valid Momentum backup.');

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

      // Pictures written from this backup (removed again if import fails).
      final written = <String>[];

      // Keep only known columns of every row. Backups made before
      // reminders / settings existed simply have no such list.
      final data = <String, List<Map<String, Object?>>>{};
      final iconPaths = <String, String>{};
      for (final entry in _exportColumns.entries) {
        final raw =
            tables[entry.key] ??
            ((entry.key == 'reminders' || entry.key == 'settings')
                ? <Object?>[]
                : null);
        if (raw is! List) throw _badBackup;
        final rows = <Map<String, Object?>>[];
        for (final row in raw) {
          if (row is! Map) throw _badBackup;
          final map = <String, Object?>{
            for (final column in entry.value)
              if (row.containsKey(column)) column: row[column] as Object?,
          };
          final b64 = row['image_base64'];
          if ((entry.key == 'transactions' || entry.key == 'reminders') &&
              b64 is String &&
              b64.isNotEmpty) {
            try {
              final path = await _writeImage(
                base64Decode(b64),
                map['image_path'] as String?,
              );
              written.add(path);
              map['image_path'] = path;
            } catch (_) {
              map['image_path'] = null;
            }
          }
          if (_iconTables.contains(entry.key) &&
              _iconImageOf(map['icon']) != null) {
            final oldPath = _iconImageOf(map['icon'])!;
            final iconB64 = row['icon_base64'];
            if (iconPaths.containsKey(oldPath)) {
              map['icon'] =
                  '${AppConstants.iconImagePrefix}${iconPaths[oldPath]}';
            } else if (iconB64 is String && iconB64.isNotEmpty) {
              try {
                final path = await _writeImage(
                  base64Decode(iconB64),
                  oldPath,
                  folder: AppConstants.iconImageFolder,
                );
                written.add(path);
                iconPaths[oldPath] = path;
                map['icon'] = '${AppConstants.iconImagePrefix}$path';
              } catch (_) {
                map['icon'] = null;
              }
            } else {
              map['icon'] = null; // picture wasn't in the backup
            }
          }
          if (entry.key == 'settings' && b64 is String && b64.isNotEmpty) {
            map['value'] = await _restoreThemeImage(map['value'], b64, written);
          }
          if (entry.key == 'settings' &&
              map['name'] == AppConstants.prefIconLibrary) {
            map['value'] = await _restoreIconLibrary(
              row['icons_base64'],
              iconPaths,
              written,
            );
          }
          rows.add(map);
        }
        data[entry.key] = rows;
      }

      // The app needs account types and the locked Transfer category.
      final hasTransfer = data['categories']!.any(
        (row) => row['kind'] == 'transfer',
      );
      if (data['account_types']!.isEmpty || !hasTransfer) {
        await _deleteImageFiles(written);
        throw _badBackup;
      }

      final schema = await rootBundle.loadString(AppConstants.schemaAsset);
      final db = await database;

      // Pictures of the data that is about to be replaced.
      final oldThemes = await db.query(
        'settings',
        columns: ['value'],
        where: 'name LIKE ?',
        whereArgs: ['$_themePrefix%'],
      );
      final oldImages = <Object?>[
        ...(await db.rawQuery('SELECT image_path FROM transactions'))
            .map((r) => r['image_path']),
        ...(await db.rawQuery('SELECT image_path FROM reminders'))
            .map((r) => r['image_path']),
        ...oldThemes.map((r) => _themeImageOf(r['value'])),
        for (final row in await db.query(
          'settings',
          columns: ['value'],
          where: 'name = ?',
          whereArgs: [AppConstants.prefIconLibrary],
        ))
          ..._libraryPaths(row['value']),
        for (final t in _iconTables)
          ...(await db.query(
            t,
            columns: ['icon'],
          )).map((r) => _iconImageOf(r['icon'])),
      ];
      final keep = <Object?>{
        for (final t in ['transactions', 'reminders'])
          for (final row in data[t]!) row['image_path'],
        for (final row in data['settings']!) _themeImageOf(row['value']),
        for (final row in data['settings']!)
          if (row['name'] == AppConstants.prefIconLibrary)
            ..._libraryPaths(row['value']),
        for (final t in _iconTables)
          for (final row in data[t]!) _iconImageOf(row['icon']),
      };

      final hasSettings = tables['settings'] is List;
      try {
        await db.transaction((txn) async {
          await _dropAll(txn);
          await _runScript(txn, schema);
          await _addMissingBudgetColumn(txn);
          if (hasSettings) await txn.delete('settings');
          for (final table in _exportColumns.keys) {
            for (final row in data[table]!) {
              await txn.insert(table, row);
            }
          }
          await _fillDefaultIcons(txn);
        });
      } catch (error) {
        debugPrint('Import failed: $error');
        await _deleteImageFiles(written);
        throw const ValidationFailure(
          'The backup file is damaged or doesn\'t match this app.',
        );
      }
      await _writeAppearance(decoded['appearance']);
      await _deleteImageFiles(oldImages.where((p) => !keep.contains(p)));
      notifyChanged();
    });
  }

  /// Copy of [row] with the picture bytes added (base64), if the file exists.
  Future<Map<String, Object?>> _withImage(Map<String, Object?> row) async {
    final copy = Map<String, Object?>.from(row);
    final path = row['image_path'];
    if (path is String && path.isNotEmpty) {
      try {
        final file = File(path);
        if (await file.exists()) {
          copy['image_base64'] = base64Encode(await file.readAsBytes());
        }
      } catch (_) {}
    }
    return copy;
  }

  /// Points every row that uses [oldKey] to [newKey].
  Future<void> replaceIcon(String oldKey, String newKey) {
    return _guard(() async {
      final db = await database;
      for (final table in _iconTables) {
        await db.update(
          table,
          {'icon': newKey},
          where: 'icon = ?',
          whereArgs: [oldKey],
        );
      }
      notifyChanged();
    });
  }

  /// The picture path of an imported icon (null = a normal icon).
  String? _iconImageOf(Object? icon) {
    if (icon is String && icon.startsWith(AppConstants.iconImagePrefix)) {
      final path = icon.substring(AppConstants.iconImagePrefix.length);
      return path.isEmpty ? null : path;
    }
    return null;
  }

  List<String> _libraryPaths(Object? value) {
    try {
      final list = jsonDecode('$value');
      if (list is List) {
        return [
          for (final entry in list)
            if (entry is String &&
                entry.startsWith(AppConstants.iconImagePrefix))
              entry.substring(AppConstants.iconImagePrefix.length),
        ];
      }
    } on FormatException {
      return [];
    }
    return [];
  }

  Future<Object?> _restoreIconLibrary(
    Object? icons,
    Map<String, String> known,
    List<String> written,
  ) async {
    final keys = <String>[];
    if (icons is List) {
      for (final entry in icons) {
        if (entry is! Map) continue;
        final oldPath = entry['path'] as String?;
        final b64 = entry['b64'];
        if (b64 is! String) continue;
        try {
          var path = oldPath == null ? null : known[oldPath];
          if (path == null) {
            path = await _writeImage(
              base64Decode(b64),
              oldPath,
              folder: AppConstants.iconImageFolder,
            );
            written.add(path);
            if (oldPath != null) known[oldPath] = path;
          }
          keys.add('${AppConstants.iconImagePrefix}$path');
        } catch (_) {}
      }
    }
    return jsonEncode(keys);
  }

  /// Copy of [row] with the icon picture bytes added (base64).
  Future<Map<String, Object?>> _withIconImage(Map<String, Object?> row) async {
    final copy = Map<String, Object?>.from(row);
    final path = _iconImageOf(row['icon']);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) {
          copy['icon_base64'] = base64Encode(await file.readAsBytes());
        }
      } catch (_) {}
    }
    return copy;
  }

  Future<String?> _iconOf(
    DatabaseExecutor db,
    CategoryGroup group,
    int id,
  ) async {
    final rows = await db.query(
      _tableOf(group),
      columns: ['icon'],
      where: 'id = ?',
      whereArgs: [id],
    );
    return rows.isEmpty ? null : rows.first['icon'] as String?;
  }

  /// Writes picture bytes into the app's attachments folder.
  Future<String> _writeImage(
    List<int> bytes,
    String? oldPath, {
    String folder = 'attachments',
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final target = Directory(p.join(dir.path, folder));
    if (!await target.exists()) await target.create(recursive: true);
    final ext = (oldPath == null || p.extension(oldPath).isEmpty)
        ? '.jpg'
        : p.extension(oldPath);
    final file = p.join(
      target.path,
      '${DateTime.now().microsecondsSinceEpoch}_${_imageCounter++}$ext',
    );
    await File(file).writeAsBytes(bytes);
    return file;
  }

  static const _themePrefix = 'accountTheme.';

  /// The picture path inside an account theme's JSON value (null = none).
  String? _themeImageOf(Object? value) {
    try {
      final m = jsonDecode('$value');
      if (m is Map) {
        final image = m['image'];
        if (image is String && image.isNotEmpty) return image;
      }
    } catch (_) {}
    return null;
  }

  /// Copy of a settings row. For an account theme with a picture, the
  /// picture bytes are added (base64), if the file exists.
  Future<Map<String, Object?>> _withThemeImage(Map<String, Object?> row) async {
    final copy = Map<String, Object?>.from(row);
    final name = row['name'];
    if (name is String && name.startsWith(_themePrefix)) {
      final path = _themeImageOf(row['value']);
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) {
            copy['image_base64'] = base64Encode(await file.readAsBytes());
          }
        } catch (_) {}
      }
    }
    if (name == AppConstants.prefIconLibrary) {
      final out = <Map<String, String>>[];
      for (final path in _libraryPaths(row['value'])) {
        try {
          final file = File(path);
          if (await file.exists()) {
            out.add({
              'path': path,
              'b64': base64Encode(await file.readAsBytes()),
            });
          }
        } catch (_) {}
      }
      copy['icons_base64'] = out;
    }
    return copy;
  }

  /// Writes the backed-up picture into the app's account_themes folder and
  /// returns the theme JSON pointing at the new file. If the picture can't
  /// be written, the theme keeps its color / pattern but loses the picture.
  Future<Object?> _restoreThemeImage(
    Object? value,
    String b64,
    List<String> written,
  ) async {
    try {
      final m = Map<String, Object?>.from(jsonDecode('$value') as Map);
      try {
        final path = await _writeImage(
          base64Decode(b64),
          m['image'] as String?,
          folder: 'account_themes',
        );
        written.add(path);
        m['image'] = path;
      } catch (_) {
        m['image'] = null;
      }
      return jsonEncode(m);
    } catch (_) {
      return value;
    }
  }
}
