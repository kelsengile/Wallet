class WalletTransaction {
  final int? id;
  final String title;
  final double amount;
  final String date;
  final String type; // 'income' or 'expense'
  final String category;
  final String? note;
  final int? accountId;

  WalletTransaction({
    this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
    this.note,
    this.accountId,
  });

  WalletTransaction copyWith({
    int? id,
    String? title,
    double? amount,
    String? date,
    String? type,
    String? category,
    String? note,
    int? accountId,
  }) {
    return WalletTransaction(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      type: type ?? this.type,
      category: category ?? this.category,
      note: note ?? this.note,
      accountId: accountId ?? this.accountId,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'amount': amount,
      'date': date,
      'type': type,
      'category': category,
      'note': note ?? '',
      if (accountId != null) 'account_id': accountId,
    };
  }

  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      type: map['type'] as String,
      category: map['category'] as String,
      note: map['note'] as String?,
      accountId: map['account_id'] as int?,
    );
  }
}
