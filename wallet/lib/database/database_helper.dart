import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';

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
      version: 1,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Called once when the database is first created on the device.
  Future<void> _onCreate(Database db, int version) async {
    // Accounts table
    await db.execute('''
      CREATE TABLE accounts (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        name        TEXT    NOT NULL,
        balance     REAL    NOT NULL DEFAULT 0.0,
        type        TEXT    NOT NULL,
        color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
        icon        TEXT    NOT NULL DEFAULT 'wallet'
      )
    ''');

    // Transactions table
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

    // Seed one default account so the app isn't empty on first launch
    await db.insert('accounts', {
      'name': 'Cash',
      'balance': 0.0,
      'type': 'cash',
      'color_hex': '#6366F1',
      'icon': 'wallet',
    });
  }

  /// Called when you bump the version number in the future.
  /// Add ALTER TABLE statements here instead of changing _onCreate.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Example for a future version 2:
    // if (oldVersion < 2) {
    //   await db.execute('ALTER TABLE transactions ADD COLUMN receipt_url TEXT');
    // }
  }

  // ── Account CRUD ───────────────────────────────────────────────────────────

  Future<int> insertAccount(Account account) async {
    final db = await database;
    return await db.insert('accounts', account.toMap());
  }

  Future<List<Account>> getAllAccounts() async {
    final db = await database;
    final rows = await db.query('accounts', orderBy: 'name ASC');
    return rows.map(Account.fromMap).toList();
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
    return await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  /// Adjust balance by a delta (positive = add, negative = subtract)
  Future<void> adjustAccountBalance(int accountId, double delta) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE accounts SET balance = balance + ? WHERE id = ?',
      [delta, accountId],
    );
  }

  // ── Transaction CRUD ───────────────────────────────────────────────────────

  Future<int> insertTransaction(WalletTransaction tx) async {
    final db = await database;
    final id = await db.insert('transactions', tx.toMap());
    // Keep account balance in sync
    if (tx.type == 'income') {
      await adjustAccountBalance(
        tx.toMap()['account_id'] as int? ?? 1,
        tx.amount,
      );
    } else {
      await adjustAccountBalance(
        tx.toMap()['account_id'] as int? ?? 1,
        -tx.amount,
      );
    }
    return id;
  }

  Future<List<WalletTransaction>> getAllTransactions() async {
    final db = await database;
    final rows = await db.query('transactions', orderBy: 'date DESC');
    return rows.map(WalletTransaction.fromMap).toList();
  }

  Future<List<WalletTransaction>> getTransactionsByAccount(
    int accountId,
  ) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
      orderBy: 'date DESC',
    );
    return rows.map(WalletTransaction.fromMap).toList();
  }

  Future<List<WalletTransaction>> getTransactionsByType(String type) async {
    final db = await database;
    final rows = await db.query(
      'transactions',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'date DESC',
    );
    return rows.map(WalletTransaction.fromMap).toList();
  }

  Future<int> updateTransaction(WalletTransaction tx) async {
    final db = await database;
    return await db.update(
      'transactions',
      tx.toMap(),
      where: 'id = ?',
      whereArgs: [tx.id],
    );
  }

  Future<int> deleteTransaction(WalletTransaction tx) async {
    final db = await database;
    // Reverse the balance effect before deleting
    if (tx.type == 'income') {
      await adjustAccountBalance(
        tx.toMap()['account_id'] as int? ?? 1,
        -tx.amount,
      );
    } else {
      await adjustAccountBalance(
        tx.toMap()['account_id'] as int? ?? 1,
        tx.amount,
      );
    }
    return await db.delete('transactions', where: 'id = ?', whereArgs: [tx.id]);
  }

  // ── Analytics helpers ──────────────────────────────────────────────────────

  /// Total income across all transactions
  Future<double> getTotalIncome() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transactions WHERE type = 'income'",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Total expenses across all transactions
  Future<double> getTotalExpenses() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT SUM(amount) as total FROM transactions WHERE type = 'expense'",
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Spending per category
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

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Wipe everything — useful for a "reset app" feature
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
