import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Live exchange rates. Cached in memory and refreshed when the cached
/// copy is more than an hour old.
class ExchangeRates {
  ExchangeRates._();
  static final ExchangeRates instance = ExchangeRates._();

  // Free, no key. Swap this URL for a keyed provider if you need
  // rates that update every hour.
  static const _url = 'https://open.er-api.com/v6/latest/USD';
  static const _maxAge = Duration(hours: 1);

  Map<String, double> _perUsd = {};
  DateTime? _fetchedAt;
  DateTime? _providerUpdate;

  /// When the rates were published (or fetched, if unknown).
  DateTime? get updatedAt => _providerUpdate ?? _fetchedAt;

  /// Returns true when usable rates are available (fresh or cached).
  Future<bool> refresh({bool force = false}) async {
    final at = _fetchedAt;
    if (!force && at != null && DateTime.now().difference(at) < _maxAge) {
      return true;
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(_url));
      final res = await req.close().timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return _perUsd.isNotEmpty;
      final body = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final json = jsonDecode(body);
      if (json is! Map || json['result'] != 'success') {
        return _perUsd.isNotEmpty;
      }
      final raw = json['rates'];
      if (raw is! Map) return _perUsd.isNotEmpty;
      final next = <String, double>{
        for (final e in raw.entries)
          if (e.key is String && e.value is num && (e.value as num) > 0)
            e.key as String: (e.value as num).toDouble(),
      };
      if (next.isEmpty) return _perUsd.isNotEmpty;
      _perUsd = next;
      _fetchedAt = DateTime.now();
      final unix = json['time_last_update_unix'];
      _providerUpdate = unix is num
          ? DateTime.fromMillisecondsSinceEpoch(unix.toInt() * 1000)
          : null;
      return true;
    } catch (_) {
      return _perUsd.isNotEmpty; // offline: keep the last good rates
    } finally {
      client.close(force: true);
    }
  }

  /// How many [to] you get for 1 [from] (null if unknown).
  double? rate(String from, String to) {
    final a = _perUsd[from];
    final b = _perUsd[to];
    if (a == null || b == null) return null;
    return b / a;
  }
}