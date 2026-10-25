/// Kinds of account. [dbValue] is what is stored in the database.
enum AccountType {
  cash('cash', 'Cash'),
  bank('bank', 'Bank'),
  eWallet('e_wallet', 'E-Wallet'),
  creditCard('credit_card', 'Credit Card'),
  investment('investment', 'Investment'),
  other('other', 'Other');

  final String dbValue;
  final String label;
  const AccountType(this.dbValue, this.label);

  static AccountType fromDb(String? value) => AccountType.values.firstWhere(
        (t) => t.dbValue == value,
        orElse: () => AccountType.other,
      );
}

/// A row of the `account_categories` table (Everyday, Savings, ...).
class AccountCategory {
  final int? id;
  final String name;
  final int sortOrder;

  const AccountCategory({this.id, required this.name, this.sortOrder = 0});

  factory AccountCategory.fromMap(Map<String, Object?> m) => AccountCategory(
        id: m['id'] as int?,
        name: m['name'] as String,
        sortOrder: (m['sort_order'] as int?) ?? 0,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'sort_order': sortOrder,
      };
}

/// A row of the `accounts` table.
/// Money is kept in centavos (₱12.50 = 1250).
class Account {
  final int? id;
  final String name;
  final AccountType type;
  final int? categoryId;

  /// Balance the account started with.
  final int initialBalance;

  /// Current balance from the `account_balances` view.
  /// Equals [initialBalance] when the account was not loaded with it.
  final int balance;

  /// Name of the card theme used to draw the account card.
  final String? cardTheme;
  final String? note;

  const Account({
    this.id,
    required this.name,
    required this.type,
    this.categoryId,
    this.initialBalance = 0,
    int? balance,
    this.cardTheme,
    this.note,
  }) : balance = balance ?? initialBalance;

  /// Current balance in pesos, ready for `Utils.formatCurrency`.
  double get balanceAmount => balance / 100;

  /// SQL that loads accounts together with their current balance.
  static const selectWithBalance = '''
    SELECT a.*, b.balance AS balance
    FROM accounts a
    JOIN account_balances b ON b.account_id = a.id
    WHERE a.deleted_at IS NULL
    ORDER BY a.name
  ''';

  factory Account.fromMap(Map<String, Object?> m) => Account(
        id: m['id'] as int?,
        name: m['name'] as String,
        type: AccountType.fromDb(m['type'] as String?),
        categoryId: m['category_id'] as int?,
        initialBalance: (m['initial_balance'] as int?) ?? 0,
        balance: m['balance'] as int?,
        cardTheme: m['card_theme'] as String?,
        note: m['note'] as String?,
      );

  /// Columns to insert or update. The current balance is never stored.
  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'name': name,
        'type': type.dbValue,
        'category_id': categoryId,
        'initial_balance': initialBalance,
        'card_theme': cardTheme,
        'note': note,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
}