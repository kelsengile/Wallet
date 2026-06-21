import 'package:flutter/foundation.dart';
import 'database/database_helper.dart';

/// Supported currencies: code -> display symbol.
/// Keep keys in sync with the dropdown in SettingsPage.
const Map<String, String> kCurrencySymbols = {
  'PHP': '₱',
  'USD': '\$',
  'EUR': '€',
  'JPY': '¥',
};

const kCurrencySettingKey = 'currency_code';
const kDefaultCurrencyCode = 'PHP';

/// Global, app-wide currency symbol. Every page that displays money should
/// wrap the relevant part of its build method in a
/// `ValueListenableBuilder<String>(valueListenable: currencySymbolNotifier, ...)`
/// so it updates immediately when the user changes currency in Settings.
final ValueNotifier<String> currencySymbolNotifier =
    ValueNotifier(kCurrencySymbols[kDefaultCurrencyCode]!);

/// The currency code backing the current symbol (e.g. 'PHP'). Kept in sync
/// with [currencySymbolNotifier].
final ValueNotifier<String> currencyCodeNotifier =
    ValueNotifier(kDefaultCurrencyCode);

Future<void> loadSavedCurrency() async {
  final saved = await DatabaseHelper.instance.getSetting(kCurrencySettingKey);
  final code = (saved != null && kCurrencySymbols.containsKey(saved))
      ? saved
      : kDefaultCurrencyCode;
  currencyCodeNotifier.value = code;
  currencySymbolNotifier.value = kCurrencySymbols[code]!;
}

/// Call this whenever the user picks a new currency in Settings.
Future<void> setCurrency(String code) async {
  if (!kCurrencySymbols.containsKey(code)) return;
  currencyCodeNotifier.value = code;
  currencySymbolNotifier.value = kCurrencySymbols[code]!;
  await DatabaseHelper.instance.saveSetting(kCurrencySettingKey, code);
}
