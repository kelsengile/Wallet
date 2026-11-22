import 'constants.dart';

/// Small formatting and date helpers (no external packages needed).
class Utils {
  Utils._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// 1234.5 -> "$1,234.50" (uses the currency chosen in Settings).
  static String formatCurrency(double amount, {String? symbol}) {
    final sym = symbol ?? AppConstants.currencySymbol;
    final negative = amount < 0;
    final parts = amount.abs().toStringAsFixed(2).split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${negative ? '-' : ''}$sym$whole.${parts[1]}';
  }

  /// The app's current date and time, following Settings > Location.
  /// Use this instead of DateTime.now() for anything the user sees or saves.
  static DateTime now() {
    final t = DateTime.now().toUtc().add(
      Duration(minutes: AppConstants.locationOffsetMinutes),
    );
    return DateTime(t.year, t.month, t.day, t.hour, t.minute, t.second);
  }

  /// DateTime -> "Oct 11, 2026"
  static String formatDate(DateTime date) =>
      '${_months[date.month - 1]} ${date.day}, ${date.year}';

  /// DateTime -> "14:05"
  static String formatTime(DateTime date) =>
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String capitalize(String text) =>
      text.isEmpty ? text : text[0].toUpperCase() + text.substring(1);
}