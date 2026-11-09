import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/models.dart';
import 'petsy_api.dart';

const _deviceIdKey = 'petsy_device_id';
const _pushEnabledKey = 'petsy_push_enabled';
const _registeredTokenKey = 'petsy_registered_push_token';
const _appointmentsChannelId = 'petsy_appointments';
const _appointmentsChannelName = 'Appointment reminders';
const _lostFoundChannelId = 'petsy_lost_found';
const _lostFoundChannelName = 'Lost & found nearby';
const _messagesChannelId = 'petsy_messages';
const _messagesChannelName = 'Chat messages';

enum NotificationChannel { appointments, lostFound, messages }

/// Local device notifications (appointment reminders, chat and nearby alerts)
/// plus registration of this device's push token with the API.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  void Function(String route)? onOpenRoute;

  bool get isReady => _ready;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Damascus'));
    }

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final route = _routeFromPayload(response.payload);
        if (route != null) onOpenRoute?.call(route);
      },
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      final route = _routeFromPayload(launch!.notificationResponse?.payload);
      if (route != null) {
        // Defer until the router is ready.
        Future<void>.delayed(const Duration(milliseconds: 600), () => onOpenRoute?.call(route));
      }
    }

    _ready = true;
  }

  Future<bool> areEnabled(SharedPreferences prefs) async => prefs.getBool(_pushEnabledKey) ?? true;

  Future<void> setEnabled(SharedPreferences prefs, bool enabled) async {
    await prefs.setBool(_pushEnabledKey, enabled);
    if (!enabled) await cancelAll();
  }

  Future<bool> requestPermission() async {
    if (kIsWeb) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      final granted = await android?.requestNotificationsPermission();
      await android?.requestExactAlarmsPermission();
      return granted ?? true;
    }
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      final granted = await ios?.requestPermissions(alert: true, badge: true, sound: true);
      return granted ?? false;
    }
    return true;
  }

  Future<String> deviceId(SharedPreferences prefs) async {
    var id = prefs.getString(_deviceIdKey);
    if (id == null || id.isEmpty) {
      id = 'local_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }

  /// Returns true when the server now holds an FCM token for this device.
  Future<bool> registerWithBackend(
    PetsyApi api,
    SharedPreferences prefs, {
    String? fcmToken,
    String language = 'en',
  }) async {
    if (!await areEnabled(prefs)) return false;
    try {
      final useFcm = fcmToken != null && fcmToken.isNotEmpty;
      final token = useFcm ? fcmToken : await deviceId(prefs);
      await api.registerDeviceToken(
        token: token,
        platform: Platform.isIOS ? 'ios' : 'android',
        provider: useFcm ? 'fcm' : 'local',
        language: language == 'ar' ? 'ar' : 'en',
      );
      await prefs.setString(_registeredTokenKey, token);
      return useFcm;
    } catch (e) {
      debugPrint('register device token failed: $e');
      return false;
    }
  }

  /// Detaches this device from the signed-in account so it stops receiving server pushes.
  Future<void> unregisterFromBackend(PetsyApi api, SharedPreferences prefs) async {
    final token = prefs.getString(_registeredTokenKey);
    if (token == null || token.isEmpty) return;
    try {
      await api.unregisterDeviceToken(token);
      await prefs.remove(_registeredTokenKey);
    } catch (e) {
      debugPrint('unregister device token failed: $e');
    }
  }

  Future<void> showNow({
    required String title,
    required String body,
    String payload = '/appointments',
    int id = 900001,
    NotificationChannel channel = NotificationChannel.appointments,
  }) async {
    if (!_ready) await init();
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(channel),
      payload: payload,
    );
  }

  Future<void> scheduleAppointmentReminder({
    required Appointment appointment,
    required String title,
    required String body,
  }) async {
    if (!_ready) await init();
    final when = _appointmentWhen(appointment);
    if (when == null) return;

    var remindAt = when.subtract(const Duration(hours: 24));
    final now = tz.TZDateTime.now(tz.local);
    if (!remindAt.isAfter(now)) {
      remindAt = when.subtract(const Duration(hours: 1));
    }
    if (!remindAt.isAfter(now)) {
      remindAt = now.add(const Duration(seconds: 15));
    }
    if (!when.isAfter(now)) return;

    final id = _notifId(appointment.id);
    await _plugin.cancel(id: id);
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: remindAt,
      title: title,
      body: body,
      notificationDetails: _details(NotificationChannel.appointments),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: jsonEncode({
        'route': '/appointments',
        'appointment_id': appointment.id,
        'type': 'appointment_reminder',
      }),
    );
  }

  Future<void> cancelAppointment(String appointmentId) => _plugin.cancel(id: _notifId(appointmentId));

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<void> syncAppointments({
    required List<Appointment> appointments,
    required String title,
    required String Function(Appointment a) bodyFor,
  }) async {
    for (final a in appointments) {
      if (a.status == 'cancelled' || a.status == 'completed') {
        await cancelAppointment(a.id);
        continue;
      }
      await scheduleAppointmentReminder(appointment: a, title: title, body: bodyFor(a));
    }
  }

  NotificationDetails _details(NotificationChannel channel) {
    final String id;
    final String name;
    final String description;
    switch (channel) {
      case NotificationChannel.lostFound:
        id = _lostFoundChannelId;
        name = _lostFoundChannelName;
        description = 'Alerts when a lost or found pet is reported near you';
      case NotificationChannel.messages:
        id = _messagesChannelId;
        name = _messagesChannelName;
        description = 'New chat message alerts';
      case NotificationChannel.appointments:
        id = _appointmentsChannelId;
        name = _appointmentsChannelName;
        description = 'Petsy appointment reminders';
    }
    return NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        name,
        channelDescription: description,
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  static int _notifId(String appointmentId) => appointmentId.hashCode & 0x7fffffff;

  static tz.TZDateTime? _appointmentWhen(Appointment a) {
    final raw = '${a.date} ${a.time}'.trim();
    DateTime? local;
    for (final fmt in [
      () => DateTime.tryParse('${a.date}T${a.time}:00'),
      () => DateTime.tryParse('${a.date}T${a.time}'),
      () {
        final parts = a.date.split('-');
        final t = a.time.split(':');
        if (parts.length != 3 || t.length < 2) return null;
        return DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
          int.parse(t[0]),
          int.parse(t[1]),
        );
      },
    ]) {
      local = fmt();
      if (local != null) break;
    }
    if (local == null) {
      debugPrint('Could not parse appointment time: $raw');
      return null;
    }
    return tz.TZDateTime.from(local, tz.local);
  }

  static String? _routeFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    if (payload.startsWith('/')) return payload;
    try {
      final map = jsonDecode(payload);
      if (map is Map && map['route'] is String) return map['route'] as String;
    } catch (_) {}
    return '/appointments';
  }
}
