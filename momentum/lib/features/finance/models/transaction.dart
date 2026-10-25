enum TransactionType {
  income('income', 'Income'),
  expense('expense', 'Expense'),
  transfer('transfer', 'Transfer'),
  reminder('reminder', 'Reminder');

  final String dbValue;
  final String label;
  const TransactionType(this.dbValue, this.label);

  static TransactionType fromDb(String? value) =>
      TransactionType.values.firstWhere(
        (t) => t.dbValue == value,
        orElse: () => TransactionType.expense,
      );
}

/// A row of the `transactions` table.
/// [amount] is always positive and kept in centavos (₱12.50 = 1250).
/// The [type] decides whether it adds to or takes from the balance.
class MomentumTransaction {
  final int? id;
  final TransactionType type;
  final String title;
  final int amount;
  final DateTime date;
  final int? categoryId;

  /// Account the money comes from (or goes into, for income).
  final int accountId;

  /// Destination account. Only used when [type] is [TransactionType.transfer].
  final int? toAccountId;
  final String? note;

  /// Path of the attached image on the device.
  final String? imagePath;

  const MomentumTransaction({
    this.id,
    required this.type,
    required this.title,
    required this.amount,
    required this.date,
    this.categoryId,
    required this.accountId,
    this.toAccountId,
    this.note,
    this.imagePath,
  });

  /// Amount in pesos, ready for `Utils.formatCurrency`.
  double get amountInPesos => amount / 100;

  factory MomentumTransaction.fromMap(Map<String, Object?> m) =>
      MomentumTransaction(
        id: m['id'] as int?,
        type: TransactionType.fromDb(m['type'] as String?),
        title: m['title'] as String,
        amount: m['amount'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        categoryId: m['category_id'] as int?,
        accountId: m['account_id'] as int,
        toAccountId: m['to_account_id'] as int?,
        note: m['note'] as String?,
        imagePath: m['image_path'] as String?,
      );

  Map<String, Object?> toMap() => {
        if (id != null) 'id': id,
        'type': type.dbValue,
        'title': title,
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'category_id': categoryId,
        'account_id': accountId,
        'to_account_id': type == TransactionType.transfer ? toAccountId : null,
        'note': note,
        'image_path': imagePath,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
}