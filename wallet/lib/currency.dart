import 'package:flutter/foundation.dart';
import 'database/database_helper.dart';

/// Supported currencies: code -> display symbol.
/// Keep keys in sync with the picker in SettingsPage.
const Map<String, String> kCurrencySymbols = {
  'PHP': '₱',
  'USD': '\$',
  'EUR': '€',
  'JPY': '¥',
  'GBP': '£',
  'AUD': '\$',
  'CAD': '\$',
  'CHF': 'Fr',
  'CNY': '¥',
  'HKD': '\$',
  'SGD': '\$',
  'NZD': '\$',
  'KRW': '₩',
  'INR': '₹',
  'IDR': 'Rp',
  'MYR': 'RM',
  'THB': '฿',
  'VND': '₫',
  'AED': 'د.إ',
  'SAR': '﷼',
  'ZAR': 'R',
  'BRL': 'R\$',
  'MXN': '\$',
  'RUB': '₽',
  'TRY': '₺',
  'SEK': 'kr',
  'NOK': 'kr',
  'DKK': 'kr',
  'PLN': 'zł',
  'TWD': 'NT\$',
  'PKR': '₨',
};

/// Friendly display names, used alongside the code/symbol in the picker.
const Map<String, String> kCurrencyNames = {
  'PHP': 'Philippine Peso',
  'USD': 'US Dollar',
  'EUR': 'Euro',
  'JPY': 'Japanese Yen',
  'GBP': 'British Pound',
  'AUD': 'Australian Dollar',
  'CAD': 'Canadian Dollar',
  'CHF': 'Swiss Franc',
  'CNY': 'Chinese Yuan',
  'HKD': 'Hong Kong Dollar',
  'SGD': 'Singapore Dollar',
  'NZD': 'New Zealand Dollar',
  'KRW': 'South Korean Won',
  'INR': 'Indian Rupee',
  'IDR': 'Indonesian Rupiah',
  'MYR': 'Malaysian Ringgit',
  'THB': 'Thai Baht',
  'VND': 'Vietnamese Dong',
  'AED': 'UAE Dirham',
  'SAR': 'Saudi Riyal',
  'ZAR': 'South African Rand',
  'BRL': 'Brazilian Real',
  'MXN': 'Mexican Peso',
  'RUB': 'Russian Ruble',
  'TRY': 'Turkish Lira',
  'SEK': 'Swedish Krona',
  'NOK': 'Norwegian Krone',
  'DKK': 'Danish Krone',
  'PLN': 'Polish Zloty',
  'TWD': 'Taiwan Dollar',
  'PKR': 'Pakistani Rupee',
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
