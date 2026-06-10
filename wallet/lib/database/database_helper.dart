import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqlite_api.dart' show ConflictAlgorithm;
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';

/// Result returned by [DatabaseHelper.insertTransfer].
class TransferResult {
  final int debitId;
  final int creditId;
  const TransferResult({required this.debitId, required this.creditId});
}

class DatabaseHelper {
  // ── Singleton ──────────────────────────────────────────────────────────────
  static final DatabaseHelper instance = DatabaseHelper._internal();
  static Database? _database;

  DatabaseHelper._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // ── Init ───────────────────────────────────────────────────────────────────
  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'wallet.db');

    return await openDatabase(
      path,
      version: 3, // bumped from 2 → 3 to add settings table
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE accounts (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        balance     REAL    NOT NULL DEFAULT 0.0,
        type        TEXT    NOT NULL,
        category    TEXT    NOT NULL DEFAULT 'personal',
        color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
        icon        TEXT    NOT NULL DEFAULT 'wallet'
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        title       TEXT    NOT NULL,
        amount      REAL    NOT NULL,
        date        TEXT    NOT NULL,
        type        TEXT    NOT NULL,
        category    TEXT    NOT NULL,
        note        TEXT    DEFAULT '',
        account_id  INTEGER,
        FOREIGN KEY (account_id) REFERENCES accounts (id)
      )
    ''');

    await db.execute('''
      CREATE TABLE settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');

    // Seed default Cash account
    await db.insert('accounts', {
      'name': 'Cash',
      'balance': 0.0,
      'type': 'cash',
      'category': 'personal',
      'color_hex': '#6366F1',
      'icon': 'wallet',
    });
  }

  /// Migrate existing installs from v1 → v2:
  /// adds the `category` column to the accounts table if it doesn't exist.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE accounts ADD COLUMN category TEXT NOT NULL DEFAULT 'personal'",
      );
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS settings (
          key   TEXT PRIMARY KEY,
          value TEXT NOT NULL
        )
      ''');
    }
  }

  // ── Account CRUD ───────────────────────────────────────────────────────────

  Future<int> insertAccount(Account account) async {
    final db = await database;
    return await db.insert('accounts', account.toMap());
  }

  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'id DESC');
    return rows.map(Account.fromMap).toList();
  }

  /// Returns accounts ordered by the date of their most recent transaction
  /// (most recent first). Accounts with no transactions come last, ordered by id DESC.
  Future<List<Account>> getAccountsSortedByLatestTransaction() async {
    final db = await database;
    final rows = await db.rawQuery('''
      SELECT a.*
      FROM accounts a
      LEFT JOIN (
        SELECT account_id, MAX(date) as latest_date
        FROM transactions
        GROUP BY account_id
      ) t ON a.id = t.account_id
      ORDER BY t.latest_date DESC NULLS LAST, a.id DESC
    ''');
    return rows.map(Account.fromMap).toList();
  }

  /// Retrieves the persisted account-type section order (null if never saved).
  Future<List<String>?> getTypeOrder() async {
    final db = await database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['type_order'],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final value = rows.first['value'] as String;
    return value.split(',').where((s) => s.isNotEmpty).toList();
  }

  /// Persists the account-type section order so it survives app restarts.
  Future<void> saveTypeOrder(List<String> order) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': 'type_order', 'value': order.join(',')},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<Account?> getAccountById(int id) async {
    final db = await database;
    final rows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Account.fromMap(rows.first);
  }

  Future<int> updateAccount(Account account) async {
    final db = await database;
    return await db.update(
      'accounts',
      account.toMap(),
      where: 'id = ?',
      whereArgs: [account.id],
    );
  }

  Future<int> deleteAccount(int id) async {
    final db = await database;
    await db.delete('transactions', where: 'account_id = ?', whereArgs: [id]);
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> adjustAccountBalance(int accountId, double delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [delta, accountId],
    );
  }

  // ── Transaction CRUD ───────────────────────────────────────────────────────

  /// Insert a transaction and update account balance atomically.
  Future<int> insertTransaction(WalletTransaction tx) async {
    final db = await database;
    final map = tx.toMap();
    final id = await db.insert('transactions', map);
    final accountId = tx.accountId ?? 1;
    await adjustAccountBalance(
      accountId,
      tx.type == 'income' ? tx.amount : -tx.amount,
    );
    return id;
  }

  Future<List<WalletTransaction>> getAllTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC');
    return rows.map(WalletTransaction.fromMap).toList();
  }

  Future<List<WalletTransaction>> getTransactionsByAccount(
      int accountId) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
    );
    return rows.map(WalletTransaction.fromMap).toList();
  }

  Future<List<WalletTransaction>> getTransactionsByMonth(
    int year,
    int month,
  ) async {
    final db = await database;
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final rows = await db.query(
      'transactions',
      where: "date LIKE ?",
      whereArgs: ['$prefix%'],
      orderBy: 'date DESC',
    );
    return rows.map(WalletTransaction.fromMap).toList();
  }

  /// Update a transaction, reversing old balance effect and applying new one.
  Future<int> updateTransaction(
    WalletTransaction oldTx,
    WalletTransaction newTx,
  ) async {
    final db = await database;

    double oldDelta;
    double newDelta;

    if (oldTx.type == 'transfer_out') {
      oldDelta = oldTx.amount; // reversal: add back
    } else if (oldTx.type == 'transfer_in') {
      oldDelta = -oldTx.amount; // reversal: subtract
    } else {
      oldDelta = oldTx.type == 'income' ? -oldTx.amount : oldTx.amount;
    }

    if (newTx.type == 'transfer_out') {
      newDelta = -newTx.amount;
    } else if (newTx.type == 'transfer_in') {
      newDelta = newTx.amount;
    } else {
      newDelta = newTx.type == 'income' ? newTx.amount : -newTx.amount;
    }

    // Reverse old
    await adjustAccountBalance(oldTx.accountId ?? 1, oldDelta);
    // Apply new
    await adjustAccountBalance(newTx.accountId ?? 1, newDelta);

    return await db.update(
      'transactions',
      newTx.toMap(),
      where: 'id = ?',
      whereArgs: [newTx.id],
    );
  }

  Future<int> deleteTransaction(WalletTransaction tx) async {
    final db = await database;

    if (tx.type == 'transfer_out' || tx.type == 'transfer_in') {
      // Reverse the balance effect for this leg only
      await adjustAccountBalance(
        tx.accountId ?? 1,
        tx.type == 'transfer_in' ? -tx.amount : tx.amount,
      );
      return await db
          .delete('transactions', where: 'id = ?', whereArgs: [tx.id]);
    }

    await adjustAccountBalance(
      tx.accountId ?? 1,
      tx.type == 'income' ? -tx.amount : tx.amount,
    );
    return await db.delete('transactions', where: 'id = ?', whereArgs: [tx.id]);
  }

  // ── Transfer ───────────────────────────────────────────────────────────────

  /// Inserts two linked transfer transactions atomically inside a DB transaction.
  ///
  /// * The **debit** leg is stored as `type = 'transfer_out'` on [fromAccountId].
  /// * The **credit** leg is stored as `type = 'transfer_in'`  on [toAccountId].
  ///
  /// Both rows share the same [refId] so they can be identified as a pair.
  /// The [refId] is embedded in the `note` field as `__ref:<refId>__` and
  /// appended after any user-supplied note.
  Future<TransferResult> insertTransfer({
    required int fromAccountId,
    required int toAccountId,
    required double amount,
    required String date,
    String note = '',
    String? refId,
  }) async {
    final db = await database;
    final ref = refId ?? '${DateTime.now().millisecondsSinceEpoch}';

    // Build the note suffix that links the two legs.
    final noteWithRef = note.isEmpty ? '__ref:$ref' : '$note __ref:$ref';

    late int debitId;
    late int creditId;

    await db.transaction((txn) async {
      // Debit leg — expense-like, deducted from source account
      debitId = await txn.insert('transactions', {
        'title': 'Transfer Out',
        'amount': amount,
        'date': date,
        'type': 'transfer_out',
        'category': 'Transfer',
        'note': noteWithRef,
        'account_id': fromAccountId,
      });

      // Credit leg — income-like, added to destination account
      creditId = await txn.insert('transactions', {
        'title': 'Transfer In',
        'amount': amount,
        'date': date,
        'type': 'transfer_in',
        'category': 'Transfer',
        'note': noteWithRef,
        'account_id': toAccountId,
      });

      // Adjust balances
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance - ? WHERE id = ?',
        [amount, fromAccountId],
      );
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        [amount, toAccountId],
      );
    });

    return TransferResult(debitId: debitId, creditId: creditId);
  }

  // ── Analytics ──────────────────────────────────────────────────────────────

  Future<double> getTotalIncome() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transactions WHERE type = 'income'",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getTotalExpenses() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transactions WHERE type = 'expense'",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getMonthlyIncome(int year, int month) async {
    final db = await database;
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transactions WHERE type = 'income' AND date LIKE ?",
      ['$prefix%'],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<double> getMonthlyExpenses(int year, int month) async {
    final db = await database;
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transactions WHERE type = 'expense' AND date LIKE ?",
      ['$prefix%'],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategory() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT category, SUM(amount) as total
      FROM transactions
      WHERE type = 'expense'
      GROUP BY category
      ORDER BY total DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getExpensesByCategoryForMonth(
    int year,
    int month,
  ) async {
    final db = await database;
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    return await db.rawQuery('''
      SELECT category, SUM(amount) as total
      FROM transactions
      WHERE type = 'expense' AND date LIKE ?
      GROUP BY category
      ORDER BY total DESC
    ''', ['$prefix%']);
  }

  /// Returns last 6 months of [{ month, income, expenses }]
  Future<List<Map<String, dynamic>>> getLast6MonthsSummary() async {
    final db = await database;
    return await db.rawQuery('''
      SELECT
        strftime('%Y-%m', date) as month,
        SUM(CASE WHEN type = 'income'  THEN amount ELSE 0 END) as income,
        SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as expenses
      FROM transactions
      WHERE type IN ('income', 'expense')
      GROUP BY month
      ORDER BY month DESC
      LIMIT 6
    ''');
  }

  // ── Generic settings ──────────────────────────────────────────────────────

  /// Reads a single value from the settings table. Returns null if not set.
  Future<String?> getSetting(String key) async {
    final db = await database;
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  /// Writes (or overwrites) a value in the settings table.
  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('accounts');
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
