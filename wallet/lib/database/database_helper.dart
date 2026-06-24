import 'package:sqflite/sqflite.dart';
import 'package:sqflite/sqlite_api.dart' show ConflictAlgorithm;
import 'package:path/path.dart';
import '../models/transaction_model.dart';
import '../models/account_model.dart';
import '../models/category_model.dart';

/// Result returned by [DatabaseHelper.insertTransfer].
/// Named with a leading underscore to avoid colliding with the
/// [TransferResult] form-result class in transaction_model.dart.
class _DbTransferResult {
  final int debitId;
  final int creditId;
  const _DbTransferResult({required this.debitId, required this.creditId});
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

/// A soft-deleted category with metadata about when it was trashed.
class TrashedCategory {
  /// Primary key of the row in [trash_categories].
  final int trashId;
  final WalletCategory category;
  final String deletedAt; // ISO-8601 timestamp

  const TrashedCategory({
    required this.trashId,
    required this.category,
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
      version:
          13, // bumped to 13 to re-apply cash corner_style = sharp (idempotent)
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

    /// Soft-deleted categories. Mirrors the categories table (minus the
    /// is_default/is_system flags, which never apply to a trashed category)
    /// plus `deleted_at`.
    await db.execute('''
      CREATE TABLE trash_categories (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        orig_id     INTEGER,
        name        TEXT    NOT NULL,
        group_type  TEXT    NOT NULL,
        icon        TEXT    NOT NULL DEFAULT 'label',
        color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
        sort_order  INTEGER NOT NULL DEFAULT 0,
        sub_type    TEXT    NOT NULL DEFAULT '',
        deleted_at  TEXT    NOT NULL
      )
    ''');

    // ── Categories table ─────────────────────────────────────────────────────
    //
    // Single source of truth for account types, account categories, and
    // transaction categories. `group_type` partitions the three groups so
    // they never collide. `is_default` marks the fallback category that
    // existing accounts/transactions are reassigned to when their category
    // is deleted. `is_system` marks categories the user can't edit/delete
    // (currently only the "Transfer" transaction category).
    await db.execute('''
      CREATE TABLE categories (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        name         TEXT    NOT NULL,
        group_type   TEXT    NOT NULL,
        icon         TEXT    NOT NULL DEFAULT 'label',
        color_hex    TEXT    NOT NULL DEFAULT '#6366F1',
        sort_order   INTEGER NOT NULL DEFAULT 0,
        is_default   INTEGER NOT NULL DEFAULT 0,
        is_system    INTEGER NOT NULL DEFAULT 0,
        sub_type     TEXT    NOT NULL DEFAULT '',
        corner_style TEXT    NOT NULL DEFAULT 'rounded',
        UNIQUE(group_type, sub_type, name)
      )
    ''');

    await _seedDefaultCategories(db);

    // Seed default Cash account — color must match the 'cash' account-type
    // category color so the card gradient is correct on first run.
    await db.insert('accounts', {
      'name': 'Cash',
      'balance': 0.0,
      'type': 'cash',
      'category': 'personal',
      'color_hex': '#22C55E',
      'icon': 'wallet',
    });
  }

  /// Seeds the categories table with the app's original built-in
  /// categories. Safe to call on a fresh DB (onCreate) or when upgrading an
  /// older install that never had this table.
  Future<void> _seedDefaultCategories(Database db) async {
    Future<void> insertAll(
      String groupType,
      List<Map<String, Object>> items,
    ) async {
      for (int i = 0; i < items.length; i++) {
        final item = items[i];
        await db.insert(
          'categories',
          {
            'name': item['name'],
            'group_type': groupType,
            'icon': item['icon'],
            'color_hex': item['color_hex'],
            'sort_order': i,
            'is_default': item['is_default'] == true ? 1 : 0,
            'is_system': item['is_system'] == true ? 1 : 0,
            'sub_type': item['sub_type'] ?? '',
            'corner_style': item['corner_style'] ?? kCornerStyleRounded,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    // ── Account types ─────────────────────────────────────────────────────
    await insertAll(kCategoryGroupAccountType, [
      {
        'name': 'cash',
        'icon': 'cash',
        'color_hex': '#22C55E',
        'is_default': true,
        'corner_style': kCornerStyleSharp,
      },
      {
        'name': 'bank',
        'icon': 'bank',
        'color_hex': '#3B82F6',
        'is_default': false,
      },
      {
        'name': 'credit',
        'icon': 'credit_card',
        'color_hex': '#EF4444',
        'is_default': false,
      },
      {
        'name': 'ewallet',
        'icon': 'ewallet',
        'color_hex': '#A855F7',
        'is_default': false,
      },
      {
        'name': 'investment',
        'icon': 'trending_up',
        'color_hex': '#F59E0B',
        'is_default': false,
      },
      {
        'name': 'assets',
        'icon': 'home',
        'color_hex': '#14B8A6',
        'is_default': false,
      },
      {
        'name': 'debt',
        'icon': 'handshake',
        'color_hex': '#F97316',
        'is_default': false,
      },
      {
        'name': 'business',
        'icon': 'business',
        'color_hex': '#6366F1',
        'is_default': false,
      },
    ]);

    // ── Account categories ────────────────────────────────────────────────
    await insertAll(kCategoryGroupAccountCategory, [
      {
        'name': 'personal',
        'icon': 'label',
        'color_hex': '#6366F1',
        'is_default': true,
      },
      {
        'name': 'family',
        'icon': 'family',
        'color_hex': '#EC4899',
        'is_default': false,
      },
      {
        'name': 'savings',
        'icon': 'savings',
        'color_hex': '#22C55E',
        'is_default': false,
      },
      {
        'name': 'future',
        'icon': 'goal',
        'color_hex': '#F59E0B',
        'is_default': false,
      },
      {
        'name': 'work',
        'icon': 'work',
        'color_hex': '#3B82F6',
        'is_default': false,
      },
      {
        'name': 'travel',
        'icon': 'travel',
        'color_hex': '#0EA5E9',
        'is_default': false,
      },
      {
        'name': 'health',
        'icon': 'health',
        'color_hex': '#EF4444',
        'is_default': false,
      },
      {
        'name': 'investment',
        'icon': 'trending_up',
        'color_hex': '#10B981',
        'is_default': false,
      },
      {
        'name': 'debt',
        'icon': 'handshake',
        'color_hex': '#F97316',
        'is_default': false,
      },
    ]);

    // ── Transaction categories ────────────────────────────────────────────
    // Income and Expense each have a built-in system "Miscellaneous" category
    // that serves as the fallback for their sub-type. The "Transfer" category
    // is the group-level default used internally for transfer legs.
    await insertAll(kCategoryGroupTransactionCategory, [
      // ── Income categories ───────────────────────────────────────────────
      {
        'name': 'Salary',
        'icon': 'cash',
        'color_hex': '#22C55E',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Bonus',
        'icon': 'star',
        'color_hex': '#F59E0B',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Commission',
        'icon': 'handshake',
        'color_hex': '#10B981',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Allowance',
        'icon': 'wallet',
        'color_hex': '#3B82F6',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Freelance',
        'icon': 'work',
        'color_hex': '#A855F7',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Business',
        'icon': 'business',
        'color_hex': '#6366F1',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Investment',
        'icon': 'trending_up',
        'color_hex': '#0EA5E9',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Online',
        'icon': 'ewallet',
        'color_hex': '#14B8A6',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Gift',
        'icon': 'gift',
        'color_hex': '#EC4899',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Scholarship',
        'icon': 'school',
        'color_hex': '#8B5CF6',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Refund',
        'icon': 'savings',
        'color_hex': '#F97316',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      {
        'name': 'Loan',
        'icon': 'bank',
        'color_hex': '#64748B',
        'is_default': false,
        'sub_type': kSubTypeIncome,
      },
      // System fallback for income — non-deletable, non-editable, default.
      {
        'name': kMiscellaneousCategoryName,
        'icon': 'label',
        'color_hex': '#6366F1',
        'is_system': true,
        'is_default': true,
        'sub_type': kSubTypeIncome,
      },
      // ── Expense categories ──────────────────────────────────────────────
      {
        'name': 'Food',
        'icon': 'restaurant',
        'color_hex': '#F97316',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Transportation',
        'icon': 'transport',
        'color_hex': '#3B82F6',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Shopping',
        'icon': 'shopping',
        'color_hex': '#EC4899',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Bills',
        'icon': 'bills',
        'color_hex': '#EF4444',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Health',
        'icon': 'health',
        'color_hex': '#10B981',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Education',
        'icon': 'school',
        'color_hex': '#8B5CF6',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Entertainment',
        'icon': 'entertainment',
        'color_hex': '#A855F7',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Tax',
        'icon': 'bills',
        'color_hex': '#64748B',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Debt',
        'icon': 'handshake',
        'color_hex': '#F59E0B',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Gift',
        'icon': 'gift',
        'color_hex': '#22C55E',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      {
        'name': 'Travel',
        'icon': 'travel',
        'color_hex': '#0EA5E9',
        'is_default': false,
        'sub_type': kSubTypeExpense,
      },
      // System fallback for expense — non-deletable, non-editable, default.
      {
        'name': kMiscellaneousCategoryName,
        'icon': 'label',
        'color_hex': '#6366F1',
        'is_system': true,
        'is_default': true,
        'sub_type': kSubTypeExpense,
      },
      // Non-deletable, non-editable — used for transfer-in/transfer-out legs.
      {
        'name': kTransferCategoryName,
        'icon': 'swap',
        'color_hex': '#0D9488',
        'is_system': true,
        'is_default': true,
        'sub_type': '',
      },
    ]);
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
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          name        TEXT    NOT NULL,
          group_type  TEXT    NOT NULL,
          icon        TEXT    NOT NULL DEFAULT 'label',
          color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
          sort_order  INTEGER NOT NULL DEFAULT 0,
          is_default  INTEGER NOT NULL DEFAULT 0,
          is_system   INTEGER NOT NULL DEFAULT 0,
          sub_type    TEXT    NOT NULL DEFAULT '',
          UNIQUE(group_type, sub_type, name)
        )
      ''');
      await _seedDefaultCategories(db);

      // Existing installs may have account types/categories or transaction
      // categories that pre-date this table (e.g. custom data). Make sure
      // every distinct value already in use has a matching category row so
      // nothing disappears from the Category Manager.
      await _backfillCategoriesFromExistingData(db);
    }
    if (oldVersion < 7) {
      // Add trash table for soft-deleted categories
      await db.execute('''
        CREATE TABLE IF NOT EXISTS trash_categories (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          orig_id     INTEGER,
          name        TEXT    NOT NULL,
          group_type  TEXT    NOT NULL,
          icon        TEXT    NOT NULL DEFAULT 'label',
          color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
          sort_order  INTEGER NOT NULL DEFAULT 0,
          sub_type    TEXT    NOT NULL DEFAULT '',
          deleted_at  TEXT    NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      // Widen the UNIQUE constraint from (group_type, name) to
      // (group_type, sub_type, name) so Income and Expense can each have
      // identically-named categories (e.g. both can have "Food").
      // SQLite doesn't support ALTER CONSTRAINT, so we recreate the table.
      await db.execute('''
        CREATE TABLE categories_new (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          name        TEXT    NOT NULL,
          group_type  TEXT    NOT NULL,
          icon        TEXT    NOT NULL DEFAULT 'label',
          color_hex   TEXT    NOT NULL DEFAULT '#6366F1',
          sort_order  INTEGER NOT NULL DEFAULT 0,
          is_default  INTEGER NOT NULL DEFAULT 0,
          is_system   INTEGER NOT NULL DEFAULT 0,
          sub_type    TEXT    NOT NULL DEFAULT '',
          UNIQUE(group_type, sub_type, name)
        )
      ''');
      await db.execute('''
        INSERT OR IGNORE INTO categories_new
          (id, name, group_type, icon, color_hex, sort_order, is_default, is_system, sub_type)
        SELECT id, name, group_type, icon, color_hex, sort_order, is_default, is_system,
               COALESCE(sub_type, '')
        FROM categories
      ''');
      await db.execute('DROP TABLE categories');
      await db.execute('ALTER TABLE categories_new RENAME TO categories');

      // Ensure both Miscellaneous system rows exist after the migration.
      for (final subType in [kSubTypeIncome, kSubTypeExpense]) {
        final maxRow = await db.rawQuery(
          'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ?',
          [kCategoryGroupTransactionCategory],
        );
        final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
        await db.insert(
          'categories',
          {
            'name': kMiscellaneousCategoryName,
            'group_type': kCategoryGroupTransactionCategory,
            'icon': 'label',
            'color_hex': '#6366F1',
            'sort_order': nextOrder,
            'is_default': 0,
            'is_system': 1,
            'sub_type': subType,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    if (oldVersion < 8) {
      // Add system Miscellaneous categories for income and expense subtypes.
      // ConflictAlgorithm.ignore means this is safe to run even if the rows
      // already exist (e.g. a fresh install that went straight to v8).
      for (final subType in [kSubTypeIncome, kSubTypeExpense]) {
        final maxRow = await db.rawQuery(
          'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ?',
          [kCategoryGroupTransactionCategory],
        );
        final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
        await db.insert(
          'categories',
          {
            'name': kMiscellaneousCategoryName,
            'group_type': kCategoryGroupTransactionCategory,
            'icon': 'label',
            'color_hex': '#6366F1',
            'sort_order': nextOrder,
            'is_default': 0,
            'is_system': 1,
            'sub_type': subType,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    if (oldVersion < 10) {
      // Seed all expanded built-in categories for existing installs.
      // ConflictAlgorithm.ignore keeps user data safe — any category the user
      // already created with the same name is left untouched.

      // ── Account types ─────────────────────────────────────────────────
      final newAccountTypes = [
        {'name': 'bank', 'icon': 'bank', 'color_hex': '#3B82F6'},
        {'name': 'credit', 'icon': 'credit_card', 'color_hex': '#EF4444'},
        {'name': 'ewallet', 'icon': 'ewallet', 'color_hex': '#A855F7'},
        {'name': 'investment', 'icon': 'trending_up', 'color_hex': '#F59E0B'},
        {'name': 'assets', 'icon': 'home', 'color_hex': '#14B8A6'},
        {'name': 'debt', 'icon': 'handshake', 'color_hex': '#F97316'},
        {'name': 'business', 'icon': 'business', 'color_hex': '#6366F1'},
      ];
      for (final item in newAccountTypes) {
        final maxRow = await db.rawQuery(
          'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ?',
          [kCategoryGroupAccountType],
        );
        final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
        await db.insert(
          'categories',
          {
            'name': item['name'],
            'group_type': kCategoryGroupAccountType,
            'icon': item['icon'],
            'color_hex': item['color_hex'],
            'sort_order': nextOrder,
            'is_default': 0,
            'is_system': 0,
            'sub_type': '',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // ── Account categories ─────────────────────────────────────────────
      final newAccountCategories = [
        {'name': 'family', 'icon': 'family', 'color_hex': '#EC4899'},
        {'name': 'savings', 'icon': 'savings', 'color_hex': '#22C55E'},
        {'name': 'future', 'icon': 'goal', 'color_hex': '#F59E0B'},
        {'name': 'work', 'icon': 'work', 'color_hex': '#3B82F6'},
        {'name': 'travel', 'icon': 'travel', 'color_hex': '#0EA5E9'},
        {'name': 'health', 'icon': 'health', 'color_hex': '#EF4444'},
        {'name': 'investment', 'icon': 'trending_up', 'color_hex': '#10B981'},
        {'name': 'debt', 'icon': 'handshake', 'color_hex': '#F97316'},
      ];
      for (final item in newAccountCategories) {
        final maxRow = await db.rawQuery(
          'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ?',
          [kCategoryGroupAccountCategory],
        );
        final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
        await db.insert(
          'categories',
          {
            'name': item['name'],
            'group_type': kCategoryGroupAccountCategory,
            'icon': item['icon'],
            'color_hex': item['color_hex'],
            'sort_order': nextOrder,
            'is_default': 0,
            'is_system': 0,
            'sub_type': '',
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // ── Income categories ──────────────────────────────────────────────
      final newIncomeCategories = [
        {'name': 'Salary', 'icon': 'cash', 'color_hex': '#22C55E'},
        {'name': 'Bonus', 'icon': 'star', 'color_hex': '#F59E0B'},
        {'name': 'Commission', 'icon': 'handshake', 'color_hex': '#10B981'},
        {'name': 'Allowance', 'icon': 'wallet', 'color_hex': '#3B82F6'},
        {'name': 'Freelance', 'icon': 'work', 'color_hex': '#A855F7'},
        {'name': 'Business', 'icon': 'business', 'color_hex': '#6366F1'},
        {'name': 'Investment', 'icon': 'trending_up', 'color_hex': '#0EA5E9'},
        {'name': 'Online', 'icon': 'ewallet', 'color_hex': '#14B8A6'},
        {'name': 'Gift', 'icon': 'gift', 'color_hex': '#EC4899'},
        {'name': 'Scholarship', 'icon': 'school', 'color_hex': '#8B5CF6'},
        {'name': 'Refund', 'icon': 'savings', 'color_hex': '#F97316'},
        {'name': 'Loan', 'icon': 'bank', 'color_hex': '#64748B'},
      ];
      for (final item in newIncomeCategories) {
        final maxRow = await db.rawQuery(
          'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ? AND sub_type = ?',
          [kCategoryGroupTransactionCategory, kSubTypeIncome],
        );
        final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
        await db.insert(
          'categories',
          {
            'name': item['name'],
            'group_type': kCategoryGroupTransactionCategory,
            'icon': item['icon'],
            'color_hex': item['color_hex'],
            'sort_order': nextOrder,
            'is_default': 0,
            'is_system': 0,
            'sub_type': kSubTypeIncome,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      // ── Expense categories ─────────────────────────────────────────────
      final newExpenseCategories = [
        {'name': 'Food', 'icon': 'restaurant', 'color_hex': '#F97316'},
        {'name': 'Transportation', 'icon': 'transport', 'color_hex': '#3B82F6'},
        {'name': 'Shopping', 'icon': 'shopping', 'color_hex': '#EC4899'},
        {'name': 'Bills', 'icon': 'bills', 'color_hex': '#EF4444'},
        {'name': 'Health', 'icon': 'health', 'color_hex': '#10B981'},
        {'name': 'Education', 'icon': 'school', 'color_hex': '#8B5CF6'},
        {
          'name': 'Entertainment',
          'icon': 'entertainment',
          'color_hex': '#A855F7'
        },
        {'name': 'Tax', 'icon': 'bills', 'color_hex': '#64748B'},
        {'name': 'Debt', 'icon': 'handshake', 'color_hex': '#F59E0B'},
        {'name': 'Gift', 'icon': 'gift', 'color_hex': '#22C55E'},
        {'name': 'Travel', 'icon': 'travel', 'color_hex': '#0EA5E9'},
      ];
      for (final item in newExpenseCategories) {
        final maxRow = await db.rawQuery(
          'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ? AND sub_type = ?',
          [kCategoryGroupTransactionCategory, kSubTypeExpense],
        );
        final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
        await db.insert(
          'categories',
          {
            'name': item['name'],
            'group_type': kCategoryGroupTransactionCategory,
            'icon': item['icon'],
            'color_hex': item['color_hex'],
            'sort_order': nextOrder,
            'is_default': 0,
            'is_system': 0,
            'sub_type': kSubTypeExpense,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
    }

    if (oldVersion < 11) {
      // Add corner_style column to categories. Default 'rounded' keeps
      // existing account types looking exactly as before; the user can
      // customise each type in the Category Manager.
      await db.execute(
        "ALTER TABLE categories ADD COLUMN corner_style TEXT NOT NULL DEFAULT 'rounded'",
      );
    }

    if (oldVersion < 13) {
      // Set the cash account type to use sharp corners by default, matching
      // the intended card design for cash accounts.
      await db.execute(
        "UPDATE categories SET corner_style = 'sharp' "
        "WHERE group_type = '$kCategoryGroupAccountType' AND name = 'cash'",
      );
    }
  }

  /// Ensures any account type/category or transaction category already
  /// referenced by existing rows has a corresponding entry in [categories],
  /// so older installs don't lose access to categories they were using.
  Future<void> _backfillCategoriesFromExistingData(Database db) async {
    Future<void> ensure(String groupType, String name,
        {String icon = 'label', String colorHex = '#6366F1'}) async {
      if (name.trim().isEmpty) return;
      final existing = await db.query(
        'categories',
        where: 'group_type = ? AND name = ?',
        whereArgs: [groupType, name],
        limit: 1,
      );
      if (existing.isNotEmpty) return;
      final maxRow = await db.rawQuery(
        'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ?',
        [groupType],
      );
      final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
      await db.insert(
        'categories',
        {
          'name': name,
          'group_type': groupType,
          'icon': icon,
          'color_hex': colorHex,
          'sort_order': nextOrder,
          'is_default': 0,
          'is_system': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final accountRows =
        await db.query('accounts', columns: ['type', 'category', 'color_hex']);
    for (final row in accountRows) {
      await ensure(kCategoryGroupAccountType, row['type'] as String,
          colorHex: row['color_hex'] as String? ?? '#6366F1');
      await ensure(kCategoryGroupAccountCategory,
          (row['category'] as String?) ?? 'personal');
    }

    final txRows = await db.query('transactions', columns: ['category']);
    for (final row in txRows) {
      await ensure(
          kCategoryGroupTransactionCategory, row['category'] as String);
    }
  }

  // ── Category CRUD ────────────────────────────────────────────────────────

  /// Returns every category in [groupType], ordered for display.
  Future<List<WalletCategory>> getCategories(String groupType) async {
    final db = await database;
    final rows = await db.query(
      'categories',
      where: 'group_type = ?',
      whereArgs: [groupType],
      orderBy: 'sort_order ASC, id ASC',
    );
    return rows.map(WalletCategory.fromMap).toList();
  }

  /// Loads all three category groups at once.
  Future<CategoryRegistry> getCategoryRegistry() async {
    final accountTypes = await getCategories(kCategoryGroupAccountType);
    final accountCategories =
        await getCategories(kCategoryGroupAccountCategory);
    final transactionCategories =
        await getCategories(kCategoryGroupTransactionCategory);
    return CategoryRegistry(
      accountTypes: accountTypes,
      accountCategories: accountCategories,
      transactionCategories: transactionCategories,
    );
  }

  /// Adds a new category to the end of its group. Throws if a category with
  /// the same name already exists in that group+sub_type combination
  /// (enforced by a UNIQUE index on group_type, sub_type, name).
  Future<int> addCategory(WalletCategory category) async {
    final db = await database;
    // Scope sort_order within the same sub_type bucket for transaction
    // categories so Income and Expense are ordered independently.
    final List<dynamic> args = category.subType.isNotEmpty
        ? [category.groupType, category.subType]
        : [category.groupType];
    final whereClause = category.subType.isNotEmpty
        ? 'group_type = ? AND sub_type = ?'
        : 'group_type = ?';
    final maxRow = await db.rawQuery(
      'SELECT MAX(sort_order) as m FROM categories WHERE $whereClause',
      args,
    );
    final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;
    final map = category.toMap()
      ..remove('id')
      ..['sort_order'] = nextOrder;
    return await db.insert('categories', map);
  }

  /// Updates a category's name/icon/color. If the name changed, every
  /// account or transaction referencing the old name is migrated to the new
  /// one so existing data keeps showing the right label.
  Future<void> updateCategory(
      WalletCategory oldCategory, WalletCategory newCategory) async {
    if (oldCategory.isSystem) return; // system categories are immutable
    final db = await database;
    final map = newCategory.toMap()..remove('id');
    await db.update('categories', map,
        where: 'id = ?', whereArgs: [oldCategory.id]);

    // Always sync account color when the account-type color changes, even when
    // the name is unchanged, so card gradients update without a manual edit.
    if (oldCategory.groupType == kCategoryGroupAccountType &&
        oldCategory.colorHex != newCategory.colorHex) {
      await db.update(
        'accounts',
        {'color_hex': newCategory.colorHex},
        where: 'type = ?',
        whereArgs: [oldCategory.name],
      );
    }

    if (oldCategory.name == newCategory.name) return;

    switch (oldCategory.groupType) {
      case kCategoryGroupAccountType:
        await db.update(
          'accounts',
          {'type': newCategory.name, 'color_hex': newCategory.colorHex},
          where: 'type = ?',
          whereArgs: [oldCategory.name],
        );
        break;
      case kCategoryGroupAccountCategory:
        await db.update('accounts', {'category': newCategory.name},
            where: 'category = ?', whereArgs: [oldCategory.name]);
        break;
      case kCategoryGroupTransactionCategory:
        // Scope the rename to transactions of the matching income/expense
        // type so a rename of an Income "Food" never touches an Expense "Food".
        final txType =
            oldCategory.subType == kSubTypeIncome ? 'income' : 'expense';
        await db.update(
          'transactions',
          {'category': newCategory.name},
          where: 'category = ? AND type = ?',
          whereArgs: [oldCategory.name, txType],
        );
        break;
    }
  }

  /// Marks [categoryId] as the default for its group (and unmarks any
  /// previous default). The default category is the one new
  /// accounts/transactions fall back to and that other categories in the
  /// group get reassigned to when deleted, so it can never be deleted
  /// itself.
  Future<void> setDefaultCategory(String groupType, int categoryId) async {
    final db = await database;
    await db.batch()
      ..update('categories', {'is_default': 0},
          where: 'group_type = ?', whereArgs: [groupType])
      ..update('categories', {'is_default': 1},
          where: 'id = ?', whereArgs: [categoryId])
      ..commit(noResult: true);
  }

  /// Persists a new display order for a category group.
  Future<void> reorderCategories(String groupType, List<int> orderedIds) async {
    final db = await database;
    final batch = db.batch();
    for (int i = 0; i < orderedIds.length; i++) {
      batch.update('categories', {'sort_order': i},
          where: 'id = ?', whereArgs: [orderedIds[i]]);
    }
    await batch.commit(noResult: true);
  }

  /// Deletes [category] and reassigns any accounts/transactions that were
  /// using it to the group's default category. System categories and the
  /// current default category cannot be deleted (callers should prevent
  /// this in the UI; this is a final safety check).
  ///
  /// Returns the name of the category everything was reassigned to, or
  /// `null` if nothing was deleted.
  Future<String?> deleteCategory(WalletCategory category) async {
    if (category.id == null || category.isSystem || category.isDefault) {
      return null;
    }
    final db = await database;

    // For transaction categories, find the fallback within the same sub_type
    // (income or expense) so we never cross-contaminate the two groups.
    final bool scopeBySubType =
        category.groupType == kCategoryGroupTransactionCategory &&
            category.subType.isNotEmpty;
    final defaultRows = await db.query(
      'categories',
      where: scopeBySubType
          ? 'group_type = ? AND sub_type = ? AND is_default = 1'
          : 'group_type = ? AND is_default = 1',
      whereArgs: scopeBySubType
          ? [category.groupType, category.subType]
          : [category.groupType],
      limit: 1,
    );
    // If no explicit default in this sub_type, fall back to the system
    // Miscellaneous for the same sub_type.
    WalletCategory? fallback;
    if (defaultRows.isNotEmpty) {
      fallback = WalletCategory.fromMap(defaultRows.first);
    } else if (scopeBySubType) {
      final miscRows = await db.query(
        'categories',
        where: 'group_type = ? AND sub_type = ? AND name = ? AND is_system = 1',
        whereArgs: [
          category.groupType,
          category.subType,
          kMiscellaneousCategoryName
        ],
        limit: 1,
      );
      if (miscRows.isNotEmpty)
        fallback = WalletCategory.fromMap(miscRows.first);
    }
    if (fallback == null) return null; // no fallback configured — abort

    switch (category.groupType) {
      case kCategoryGroupAccountType:
        await db.update(
          'accounts',
          {'type': fallback.name, 'color_hex': fallback.colorHex},
          where: 'type = ?',
          whereArgs: [category.name],
        );
        break;
      case kCategoryGroupAccountCategory:
        await db.update(
          'accounts',
          {'category': fallback.name},
          where: 'category = ?',
          whereArgs: [category.name],
        );
        break;
      case kCategoryGroupTransactionCategory:
        // Only reassign transactions of the matching income/expense type.
        final txType =
            category.subType == kSubTypeIncome ? 'income' : 'expense';
        await db.update(
          'transactions',
          {'category': fallback.name},
          where: 'category = ? AND type = ?',
          whereArgs: [category.name, txType],
        );
        break;
    }

    final catMap = category.toMap();
    await db.insert('trash_categories', {
      'orig_id': category.id,
      'name': catMap['name'],
      'group_type': catMap['group_type'],
      'icon': catMap['icon'],
      'color_hex': catMap['color_hex'],
      'sort_order': catMap['sort_order'] ?? 0,
      'sub_type': catMap['sub_type'] ?? '',
      'deleted_at': DateTime.now().toIso8601String(),
    });

    await db.delete('categories', where: 'id = ?', whereArgs: [category.id]);
    return fallback.name;
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

  /// Soft-deletes BOTH legs of a transfer together, so they land in the trash
  /// bin as a matched pair (sharing the same `__ref:…__` tag) and can be
  /// restored or purged as a single unit.
  ///
  /// Use this instead of calling [deleteTransaction] separately on each leg —
  /// doing that leaves the other leg live in the `transactions` table and
  /// breaks pairing in the trash bin (the deleted leg shows up as an orphaned
  /// single card instead of a unified transfer card).
  Future<void> deleteTransfer(
      WalletTransaction outLeg, WalletTransaction inLeg) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();

    Future<String> resolveAccountName(int? accountId) async {
      if (accountId == null) return '';
      final rows = await db.query(
        'accounts',
        columns: ['name'],
        where: 'id = ?',
        whereArgs: [accountId],
        limit: 1,
      );
      return rows.isNotEmpty ? (rows.first['name'] as String? ?? '') : '';
    }

    final outAccountName = await resolveAccountName(outLeg.accountId);
    final inAccountName = await resolveAccountName(inLeg.accountId);

    await db.transaction((txn) async {
      await txn.insert('trash_transactions', {
        'orig_id': outLeg.id,
        'title': outLeg.title,
        'amount': outLeg.amount,
        'date': outLeg.date,
        'type': outLeg.type,
        'category': outLeg.category,
        'note': outLeg.note ?? '',
        'account_id': outLeg.accountId,
        'account_name': outAccountName,
        'deleted_at': now,
      });
      await txn.insert('trash_transactions', {
        'orig_id': inLeg.id,
        'title': inLeg.title,
        'amount': inLeg.amount,
        'date': inLeg.date,
        'type': inLeg.type,
        'category': inLeg.category,
        'note': inLeg.note ?? '',
        'account_id': inLeg.accountId,
        'account_name': inAccountName,
        'deleted_at': now,
      });

      // Reverse balance effects for both legs.
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        [outLeg.amount, outLeg.accountId ?? 1],
      );
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance - ? WHERE id = ?',
        [inLeg.amount, inLeg.accountId ?? 1],
      );

      await txn.delete('transactions', where: 'id = ?', whereArgs: [outLeg.id]);
      await txn.delete('transactions', where: 'id = ?', whereArgs: [inLeg.id]);
    });
  }

  // ── Transfer ───────────────────────────────────────────────────────────────

  Future<_DbTransferResult> insertTransfer({
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
        'category': kTransferCategoryName,
        'note': noteWithRef,
        'account_id': fromAccountId,
      });

      creditId = await txn.insert('transactions', {
        'title': 'Transfer In',
        'amount': amount,
        'date': date,
        'type': 'transfer_in',
        'category': kTransferCategoryName,
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

    return _DbTransferResult(debitId: debitId, creditId: creditId);
  }

  /// Updates both legs of an existing transfer atomically.
  ///
  /// Reverses the old balance effects on both accounts, then applies the new
  /// ones. The `__ref:…__` tag and original date are preserved (passed in via
  /// [refId] and [date]). If [fromAccountId] or [toAccountId] changed the
  /// balance adjustment targets the correct accounts for both old and new.
  Future<void> updateTransfer({
    required int outLegId,
    required int inLegId,
    required int oldFromAccountId,
    required int oldToAccountId,
    required double oldAmount,
    required int newFromAccountId,
    required int newToAccountId,
    required double newAmount,
    required String date,
    required String refId,
    String note = '',
  }) async {
    final db = await database;
    final noteWithRef =
        note.isEmpty ? '__ref:${refId}__' : '$note __ref:${refId}__';

    await db.transaction((txn) async {
      // ── Reverse old balance effects ──────────────────────────────────────
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        [oldAmount, oldFromAccountId],
      );
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance - ? WHERE id = ?',
        [oldAmount, oldToAccountId],
      );

      // ── Update both legs ─────────────────────────────────────────────────
      await txn.update(
        'transactions',
        {
          'title': 'Transfer Out',
          'amount': newAmount,
          'date': date,
          'type': 'transfer_out',
          'category': kTransferCategoryName,
          'note': noteWithRef,
          'account_id': newFromAccountId,
        },
        where: 'id = ?',
        whereArgs: [outLegId],
      );

      await txn.update(
        'transactions',
        {
          'title': 'Transfer In',
          'amount': newAmount,
          'date': date,
          'type': 'transfer_in',
          'category': kTransferCategoryName,
          'note': noteWithRef,
          'account_id': newToAccountId,
        },
        where: 'id = ?',
        whereArgs: [inLegId],
      );

      // ── Apply new balance effects ─────────────────────────────────────────
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance - ? WHERE id = ?',
        [newAmount, newFromAccountId],
      );
      await txn.rawUpdate(
        'UPDATE accounts SET balance = balance + ? WHERE id = ?',
        [newAmount, newToAccountId],
      );
    });
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

  /// Returns all trashed categories, most recently deleted first.
  Future<List<TrashedCategory>> getTrashedCategories() async {
    final db = await database;
    final rows = await db.query(
      'trash_categories',
      orderBy: 'deleted_at DESC',
    );
    return rows.map((row) {
      final category = WalletCategory.fromMap({
        'id': row['orig_id'],
        'name': row['name'],
        'group_type': row['group_type'],
        'icon': row['icon'],
        'color_hex': row['color_hex'],
        'sort_order': row['sort_order'],
        'is_default': 0,
        'is_system': 0,
        'sub_type': row['sub_type'] ?? '',
      });
      return TrashedCategory(
        trashId: row['id'] as int,
        category: category,
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

  /// Restores a trashed category back to the live categories table. If a
  /// category with the same name already exists in that group (e.g. it was
  /// re-created after deletion), the restored name is suffixed to avoid the
  /// UNIQUE(group_type, name) constraint.
  Future<void> restoreCategory(int trashId) async {
    final db = await database;

    final rows = await db.query(
      'trash_categories',
      where: 'id = ?',
      whereArgs: [trashId],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final row = rows.first;
    final groupType = row['group_type'] as String;
    final subType = row['sub_type'] as String? ?? '';
    var name = row['name'] as String;

    final clash = await db.query(
      'categories',
      where: 'group_type = ? AND sub_type = ? AND name = ?',
      whereArgs: [groupType, subType, name],
      limit: 1,
    );
    if (clash.isNotEmpty) {
      name = '$name (restored)';
    }

    final bool scopeBySubType = subType.isNotEmpty;
    final maxRow = await db.rawQuery(
      scopeBySubType
          ? 'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ? AND sub_type = ?'
          : 'SELECT MAX(sort_order) as m FROM categories WHERE group_type = ?',
      scopeBySubType ? [groupType, subType] : [groupType],
    );
    final nextOrder = ((maxRow.first['m'] as int?) ?? -1) + 1;

    await db.insert('categories', {
      'name': name,
      'group_type': groupType,
      'icon': row['icon'],
      'color_hex': row['color_hex'],
      'sort_order': nextOrder,
      'is_default': 0,
      'is_system': 0,
      'sub_type': subType,
    });

    await db.delete('trash_categories', where: 'id = ?', whereArgs: [trashId]);
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

  /// Permanently deletes a single trashed category row.
  Future<void> permanentlyDeleteCategory(int trashId) async {
    final db = await database;
    await db.delete(
      'trash_categories',
      where: 'id = ?',
      whereArgs: [trashId],
    );
  }

  /// Permanently deletes ALL items from all trash tables.
  Future<void> emptyTrash() async {
    final db = await database;
    await db.delete('trash_transactions');
    await db.delete('trash_accounts');
    await db.delete('trash_categories');
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
    final catCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM trash_categories'),
        ) ??
        0;
    return txCount + acctCount + catCount;
  }

  // ── Utility ────────────────────────────────────────────────────────────────

  /// Clears all live data AND the trash bin, then restores all default
  /// categories (both built-in defaults and system categories) to their
  /// original state.
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('transactions');
    await db.delete('accounts');
    await db.delete('trash_transactions');
    await db.delete('trash_accounts');
    await db.delete('trash_categories');

    // Remove ALL categories so we can re-seed them cleanly from scratch.
    await db.delete('categories');
    await _seedDefaultCategories(db);

    // Re-seed the default Cash account, since it was just deleted above.
    await db.insert('accounts', {
      'name': 'Cash',
      'balance': 0.0,
      'type': 'cash',
      'category': 'personal',
      'color_hex': '#22C55E',
      'icon': 'wallet',
    });
  }

  Future<void> closeDatabase() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
