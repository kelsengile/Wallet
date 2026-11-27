import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/constants.dart';
import '../core/screens/settings.dart';
import '../core/utils.dart';
import '../database/helper.dart';

class NotificationService with WidgetsBindingObserver {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _reminderBase = 1000000;
  static const int _summaryBase = 2000000;
  static const int _budgetBase = 3000000;
  static const int _testId = 3999999;
  static const int _summaryDays = 7;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;
  bool _started = false;
  bool _syncing = false;
  bool _again = false;
  Timer? _debounce;

  void start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    DatabaseHelper.instance.changes.addListener(scheduleSync);
    scheduleSync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) scheduleSync();
  }

  Future<void> init() async {
    if (_ready) return;
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  Future<bool> requestPermission() async {
    try {
      await init();
      final android = _android;
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final ios = _ios;
      if (ios != null) {
        return await ios.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (e) {
      debugPrint('Notification permission failed: $e');
    }
    return false;
  }

  Future<bool> areEnabled() async {
    try {
      await init();
      final android = _android;
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      final ios = _ios;
      if (ios != null) {
        final p = await ios.checkPermissions();
        return p?.isEnabled ?? false;
      }
    } catch (_) {}
    return false;
  }

  Future<bool> _canExact() async {
    try {
      return await _android?.canScheduleExactNotifications() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestExactAlarms() async {
    try {
      await init();
      final android = _android;
      if (android == null) return;
      if (!(await android.canScheduleExactNotifications() ?? false)) {
        await android.requestExactAlarmsPermission();
      }
    } catch (_) {}
  }

  NotificationDetails _details() {
    final s = AppSettings.instance;
    final sound = s.notif(NotificationOption.sound);
    final vibrate = s.notif(NotificationOption.vibration);
    final id = 'wallet_alerts_${sound ? 's' : 'q'}${vibrate ? 'v' : 'n'}';
    final name =
        'Wallet alerts (${sound ? 'sound' : 'silent'}'
        '${vibrate ? ' + vibration' : ''})';
    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        name,
        channelDescription: 'Reminders, budget warnings and daily summaries',
        importance: Importance.high,
        priority: Priority.high,
        playSound: sound,
        enableVibration: vibrate,
      ),
      iOS: DarwinNotificationDetails(presentSound: sound),
    );
  }

  Future<void> showTest() async {
    await init();
    await _plugin.show(
      id: _testId,
      title: AppConstants.appName,
      body: 'Notifications are working.',
      notificationDetails: _details(),
    );
  }

  Future<void> _zoned(
    int id,
    String title,
    String body,
    tz.TZDateTime when,
    bool exact,
  ) async {
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: mode,
    );
    try {
      await schedule(
        exact
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (e) {
      if (!exact) {
        debugPrint('Could not schedule notification $id: $e');
        return;
      }
      try {
        await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (e2) {
        debugPrint('Could not schedule notification $id: $e2');
      }
    }
  }

  tz.TZDateTime _instant(DateTime appTime) {
    final utc = DateTime.utc(
      appTime.year,
      appTime.month,
      appTime.day,
      appTime.hour,
      appTime.minute,
    ).subtract(Duration(minutes: AppConstants.locationOffsetMinutes));
    return tz.TZDateTime.utc(utc.year, utc.month, utc.day, utc.hour, utc.minute);
  }

  bool _isFuture(tz.TZDateTime t) =>
      t.isAfter(tz.TZDateTime.now(tz.UTC).add(const Duration(seconds: 5)));

  String _money(double v) =>
      Utils.formatCurrency(v, symbol: AppConstants.currencySymbol);

  void scheduleSync() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), sync);
  }

  Future<void> sync() async {
    if (_syncing) {
      _again = true;
      return;
    }
    _syncing = true;
    try {
      do {
        _again = false;
        await _syncOnce();
      } while (_again);
    } catch (e) {
      debugPrint('Notification sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  Future<void> _syncOnce() async {
    await init();
    for (final p in await _plugin.pendingNotificationRequests()) {
      await _plugin.cancel(id: p.id);
    }

    final s = AppSettings.instance;
    if (!s.notif(NotificationOption.push)) return;
    if (!await areEnabled()) return;

    final exact = await _canExact();
    if (s.notif(NotificationOption.reminders)) await _scheduleReminders(exact);
    if (s.notif(NotificationOption.summary)) await _scheduleSummary(exact);
    if (s.notif(NotificationOption.budget)) await _checkBudgets();
  }

  Future<void> _scheduleReminders(bool exact) async {
    final reminders = await DatabaseHelper.instance.getReminders();
    for (final r in reminders) {
      final when = _instant(r.dueDate);
      if (!_isFuture(when)) continue;
      final sign = r.type == 'income' ? '+' : '−';
      final body = [
        '$sign${_money(r.amount)}',
        if (r.categoryName != null) r.categoryName!,
        if (r.accountName != null) r.accountName!,
      ].join(' · ');
      await _zoned(
        _reminderBase + r.id,
        'Reminder: ${r.title}',
        body,
        when,
        exact,
      );
    }
  }

  Future<void> _scheduleSummary(bool exact) async {
    final now = Utils.now();
    final today = DateTime(now.year, now.month, now.day);
    final entries = await DatabaseHelper.instance.getHistory(
      from: today,
      until: DateTime(today.year, today.month, today.day + 1),
    );
    var income = 0.0;
    var expense = 0.0;
    var count = 0;
    for (final e in entries) {
      count++;
      if (e.type == 'income') income += e.amount;
      if (e.type == 'expense') expense += e.amount;
    }

    for (var i = 0; i < _summaryDays; i++) {
      final at = DateTime(
        today.year,
        today.month,
        today.day + i,
        AppConstants.notifySummaryHour,
      );
      final when = _instant(at);
      if (!_isFuture(when)) continue;
      final body = i > 0
          ? 'See how your day went. Open Wallet for your daily recap.'
          : (count == 0
                ? 'No transactions today. Tap to add any you missed.'
                : 'Income +${_money(income)} · Expense −${_money(expense)} · '
                      '$count transaction${count == 1 ? '' : 's'} today');
      await _zoned(_summaryBase + i, 'Daily summary', body, when, exact);
    }
  }

  Future<void> _checkBudgets() async {
    final db = DatabaseHelper.instance;
    final prefs = await SharedPreferences.getInstance();
    final now = Utils.now();
    final month = '${now.year}-${now.month}';

    final categories = await db.getCategoryItems(CategoryGroup.expense);
    final history = await db.getHistory(
      from: DateTime(now.year, now.month),
      until: DateTime(now.year, now.month + 1),
    );
    final spent = <int, double>{};
    for (final e in history) {
      final id = e.categoryId;
      if (e.type == 'expense' && id != null) {
        spent[id] = (spent[id] ?? 0) + e.amount;
      }
    }

    for (final c in categories) {
      final budget = c.budget;
      if (budget == null || budget <= 0) continue;
      final used = spent[c.id] ?? 0;
      final ratio = used / budget;
      final level = ratio >= 1
          ? 2
          : (ratio >= AppConstants.budgetWarnRatio ? 1 : 0);

      final key = 'notif.budget.${c.id}';
      final saved = prefs.getString(key);
      final savedLevel = (saved != null && saved.startsWith('$month:'))
          ? int.tryParse(saved.split(':').last) ?? 0
          : 0;

      if (level > savedLevel) {
        final title = level == 2
            ? '${c.name} budget exceeded'
            : '${c.name} budget almost used';
        final body = level == 2
            ? 'You have spent ${_money(used)} of your ${_money(budget)} budget.'
            : '${(ratio * 100).floor()}% used · '
                  '${_money(budget - used)} left of ${_money(budget)}';
        await _plugin.show(
          id: _budgetBase + c.id,
          title: title,
          body: body,
          notificationDetails: _details(),
        );
      }
      if (level != savedLevel) await prefs.setString(key, '$month:$level');
    }
  }
}