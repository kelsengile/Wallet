class WalletTransaction {
  final int? id;
  final String title;
  final double amount;
  final String date;
  final String type; // 'income' or 'expense'
  final String category;
  final String? note;

  WalletTransaction({
    this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
    this.note,
  });

  /// Convert to a Map for inserting into SQLite
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'amount': amount,
      'date': date,
      'type': type,
      'category': category,
      'note': note ?? '',
    };
  }

  /// Create a WalletTransaction from a SQLite row Map
  factory WalletTransaction.fromMap(Map<String, dynamic> map) {
    return WalletTransaction(
      id: map['id'] as int?,
      title: map['title'] as String,
      amount: (map['amount'] as num).toDouble(),
      date: map['date'] as String,
      type: map['type'] as String,
      category: map['category'] as String,
      note: map['note'] as String?,
    );
  }
}
