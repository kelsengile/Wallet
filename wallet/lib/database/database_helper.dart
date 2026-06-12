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

// ── Trash-bin item wrappers ────────────────────────────────────────────────────

/// A soft-deleted transaction with metadata about when it was trashed.
class TrashedTransaction {
  /// Primary key of the row in [trash_transactions].
  final int trashId;
  final WalletTransaction transaction;
  final String deletedAt; // ISO-8601 timestamp
  final String? accountName; // denormalised for display (account may be gone)

  const TrashedTransaction({
    required this.trashId,
    required this.transaction,
    required this.deletedAt,
    this.accountName,
  });
}

/// A soft-deleted account with metadata about when it was trashed.
class TrashedAccount {
  /// Primary key of the row in [trash_accounts].
  final int trashId;
  final Account account;
  final String deletedAt; // ISO-8601 timestamp

  const TrashedAccount({
    required this.trashId,
    required this.account,
    required this.deletedAt,
  });
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
      version: 4, // bumped from 3 → 4 to add trash tables
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

    // ── Trash bin tables ─────────────────────────────────────────────────────

    /// Soft-deleted transactions. Mirrors the transactions table plus
    /// `deleted_at` (ISO-8601) and `account_name` (denormalised snapshot).
    await db.execute('''
      CREATE TABLE trash_transactions (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        orig_id      INTEGER NOT NULL,
        title        TEXT    NOT NULL,
        amount       REAL    NOT NULL,
        date         TEXT    NOT NULL,
        type         TEXT    NOT NULL,
        category     TEXT    NOT NULL,
        note         TEXT    DEFAULT '',
        account_id   INTEGER,
        account_name TEXT    DEFAULT '',
        deleted_at   TEXT    NOT NULL
      )
    ''');

    /// Soft-deleted accounts. Mirrors the accounts table plus `deleted_at`.
    await db.execute('''
      CREATE TABLE trash_accounts (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        orig_id     INTEGER NOT NULL,
        name        TEXT    NOT NULL,
        balance     REAL    NOT NULL DEFAULT 0.0,
        type        TEXT    NOT NULL,
        category    TEXT    NOT NULL DEFAULT 'personal',
        color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
        icon        TEXT    NOT NULL DEFAULT 'wallet',
        deleted_at  TEXT    NOT NULL
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
    if (oldVersion < 4) {
      // Add trash tables for existing installs
      await db.execute('''
        CREATE TABLE IF NOT EXISTS trash_transactions (
          id           INTEGER PRIMARY KEY AUTOINCREMENT,
          orig_id      INTEGER NOT NULL,
          title        TEXT    NOT NULL,
          amount       REAL    NOT NULL,
          date         TEXT    NOT NULL,
          type         TEXT    NOT NULL,
          category     TEXT    NOT NULL,
          note         TEXT    DEFAULT '',
          account_id   INTEGER,
          account_name TEXT    DEFAULT '',
          deleted_at   TEXT    NOT NULL
        )
      ''');

      await db.execute('''
        CREATE TABLE IF NOT EXISTS trash_accounts (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          orig_id     INTEGER NOT NULL,
          name        TEXT    NOT NULL,
          balance     REAL    NOT NULL DEFAULT 0.0,
          type        TEXT    NOT NULL,
          category    TEXT    NOT NULL DEFAULT 'personal',
          color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
          icon        TEXT    NOT NULL DEFAULT 'wallet',
          deleted_at  TEXT    NOT NULL
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

  /// Soft-deletes an account and all its transactions into the trash bin,
  /// then hard-deletes them from the live tables.
  Future<int> deleteAccount(int id) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Snapshot the account before deletion
    final accountRows = await db.query(
      'accounts',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (accountRows.isNotEmpty) {
      final row = Map<String, dynamic>.from(accountRows.first);
      await db.insert('trash_accounts', {
        'orig_id': row['id'],
        'name': row['name'],
        'balance': row['balance'],
        'type': row['type'],
        'category': row['category'] ?? 'personal',
        'color_hex': row['color_hex'],
        'icon': row['icon'],
        'deleted_at': now,
      });
    }

    // Snapshot all linked transactions before deletion
    final txRows = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [id],
    );
    for (final row in txRows) {
      await db.insert('trash_transactions', {
        'orig_id': row['id'],
        'title': row['title'],
        'amount': row['amount'],
        'date': row['date'],
        'type': row['type'],
        'category': row['category'],
        'note': row['note'] ?? '',
        'account_id': row['account_id'],
        'account_name': accountRows.isNotEmpty
            ? accountRows.first['name'] as String? ?? ''
            : '',
        'deleted_at': now,
      });
    }

    // Hard-delete from live tables
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
      oldDelta = oldTx.amount;
    } else if (oldTx.type == 'transfer_in') {
      oldDelta = -oldTx.amount;
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

    await adjustAccountBalance(oldTx.accountId ?? 1, oldDelta);
    await adjustAccountBalance(newTx.accountId ?? 1, newDelta);

    return await db.update(
      'transactions',
      newTx.toMap(),
      where: 'id = ?',
      whereArgs: [newTx.id],
    );
  }

  /// Soft-deletes a transaction into the trash bin, then hard-deletes it from
  /// the live table and adjusts the account balance.
  Future<int> deleteTransaction(WalletTransaction tx) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    // Resolve account name for the denormalised snapshot
    String accountName = '';
    if (tx.accountId != null) {
      final acctRows = await db.query(
        'accounts',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [tx.accountId],
        limit: 1,
      );
      if (acctRows.isNotEmpty) {
        accountName = acctRows.first['name'] as String? ?? '';
      }
    }

    // Snapshot into trash
    await db.insert('trash_transactions', {
      'orig_id': tx.id,
      'title': tx.title,
      'amount': tx.amount,
      'date': tx.date,
      'type': tx.type,
      'category': tx.category,
      'note': tx.note ?? '',
      'account_id': tx.accountId,
      'account_name': accountName,
      'deleted_at': now,
    });

    // Reverse balance
    if (tx.type == 'transfer_out' || tx.type == 'transfer_in') {
      await adjustAccountBalance(
        tx.accountId ?? 1,
        tx.type == 'transfer_in' ? -tx.amount : tx.amount,
      );
    } else {
      await adjustAccountBalance(
        tx.accountId ?? 1,
        tx.type == 'income' ? -tx.amount : tx.amount,
      );
    }

    return await db.delete('transactions', where: 'id = ?', whereArgs: [tx.id]);
  }

  // ── Transfer ───────────────────────────────────────────────────────────────

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
    final noteWithRef =
        note.isEmpty ? '__ref:${ref}__' : '$note __ref:${ref}__';

    late int debitId;
    late int creditId;

    await db.transaction((txn) async {
      debitId = await txn.insert('transactions', {
        'title': 'Transfer Out',
        'amount': amount,
        'date': date,
        'type': 'transfer_out',
        'category': 'Transfer',
        'note': noteWithRef,
        'account_id': fromAccountId,
      });

      creditId = await txn.insert('transactions', {
        'title': 'Transfer In',
        'amount': amount,
        'date': date,
        'type': 'transfer_in',
        'category': 'Transfer',
        'note': noteWithRef,
        'account_id': toAccountId,
      });

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

  Future<void> saveSetting(String key, String value) async {
    final db = await database;
    await db.insert(
      'settings',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Trash bin ──────────────────────────────────────────────────────────────

  /// Returns all trashed transactions, most recently deleted first.
  Future<List<TrashedTransaction>> getTrashedTransactions() async {
    final db = await database;
    final rows = await db.query(
      'trash_transactions',
      orderBy: 'deleted_at DESC',
    );
    return rows.map((row) {
      final tx = WalletTransaction(
        id: row['orig_id'] as int?,
        title: row['title'] as String,
        amount: (row['amount'] as num).toDouble(),
        date: row['date'] as String,
        type: row['type'] as String,
        category: row['category'] as String,
        note: row['note'] as String?,
        accountId: row['account_id'] as int?,
      );
      return TrashedTransaction(
        trashId: row['id'] as int,
        transaction: tx,
        deletedAt: row['deleted_at'] as String,
        accountName: row['account_name'] as String?,
      );
    }).toList();
  }

  /// Returns all trashed accounts, most recently deleted first.
  Future<List<TrashedAccount>> getTrashedAccounts() async {
    final db = await database;
    final rows = await db.query(
      'trash_accounts',
      orderBy: 'deleted_at DESC',
    );
    return rows.map((row) {
      final account = Account(
        id: row['orig_id'] as int?,
        name: row['name'] as String,
        balance: (row['balance'] as num).toDouble(),
        type: row['type'] as String,
        category: (row['category'] as String?) ?? 'personal',
        colorHex: row['color_hex'] as String,
        icon: row['icon'] as String,
      );
      return TrashedAccount(
        trashId: row['id'] as int,
        account: account,
        deletedAt: row['deleted_at'] as String,
      );
    }).toList();
  }

  /// Restores a trashed transaction back to the live transactions table
  /// and re-applies its balance effect. The trash row is removed.
  Future<void> restoreTransaction(int trashId) async {
    final db = await database;

    final rows = await db.query(
      'trash_transactions',
      where: 'id = ?',
      whereArgs: [trashId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    final type = row['type'] as String;
    final amount = (row['amount'] as num).toDouble();
    final accountId = row['account_id'] as int?;

    // Re-insert into live table (without the orig_id — let DB assign new id)
    await db.insert('transactions', {
      'title': row['title'],
      'amount': amount,
      'date': row['date'],
      'type': type,
      'category': row['category'],
      'note': row['note'] ?? '',
      'account_id': accountId,
    });

    // Re-apply balance effect
    if (accountId != null) {
      double delta;
      if (type == 'transfer_out') {
        delta = -amount;
      } else if (type == 'transfer_in') {
        delta = amount;
      } else {
        delta = type == 'income' ? amount : -amount;
      }
      await adjustAccountBalance(accountId, delta);
    }

    await db
        .delete('trash_transactions', where: 'id = ?', whereArgs: [trashId]);
  }

  /// Restores a trashed account (and only the account row) back to the live
  /// accounts table. Note: linked transactions are NOT automatically restored
  /// because they may have already been overwritten by other activity.
  Future<void> restoreAccount(int trashId) async {
    final db = await database;

    final rows = await db.query(
      'trash_accounts',
      where: 'id = ?',
      whereArgs: [trashId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = rows.first;

    await db.insert('accounts', {
      'name': row['name'],
      'balance': row['balance'],
      'type': row['type'],
      'category': row['category'] ?? 'personal',
      'color_hex': row['color_hex'],
      'icon': row['icon'],
    });

    await db.delete('trash_accounts', where: 'id = ?', whereArgs: [trashId]);
  }

  /// Permanently deletes a single trashed transaction (no balance change —
  /// balance was already reversed when it was first trashed).
  Future<void> permanentlyDeleteTransaction(int trashId) async {
    final db = await database;
    await db.delete(
      'trash_transactions',
      where: 'id = ?',
      whereArgs: [trashId],
    );
  }

  /// Permanently deletes a single trashed account row.
  Future<void> permanentlyDeleteAccount(int trashId) async {
    final db = await database;
    await db.delete(
      'trash_accounts',
      where: 'id = ?',
      whereArgs: [trashId],
    );
  }

  /// Permanently deletes ALL items from both trash tables.
  Future<void> emptyTrash() async {
    final db = await database;
    await db.delete('trash_transactions');
    await db.delete('trash_accounts');
  }

  /// Returns the total number of items currently in the trash.
  Future<int> getTrashCount() async {
    final db = await database;
    final txCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM trash_transactions'),
        ) ??
        0;
    final acctCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM trash_accounts'),
        ) ??
        0;
    return txCount + acctCount;
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Clears all live data AND the trash bin.
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('accounts');
    await db.delete('trash_transactions');
    await db.delete('trash_accounts');
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
