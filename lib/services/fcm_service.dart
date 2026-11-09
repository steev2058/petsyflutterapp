import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'push_notification_service.dart';

/// Background isolate handler for FCM data/notification messages.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // System tray may already show notification payload from FCM.
  debugPrint('FCM background: ${message.messageId} ${message.data}');
}

/// Real FCM token registration + foreground message → local notification bridge.
class FcmService {
  FcmService._();
  static final FcmService instance = FcmService._();

  bool _ready = false;
  bool get isReady => _ready;

  Future<bool> init({
    void Function(String route)? onOpenRoute,
    void Function(String token)? onTokenRefresh,
  }) async {
    if (kIsWeb) return false;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);
      // Foreground messages are re-posted locally below, so suppress the iOS duplicate.
      await messaging.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );

      FirebaseMessaging.onMessage.listen((message) async {
        // In the foreground chat alerts arrive over the realtime socket.
        if (message.data['type'] == 'chat_message') return;
        final title = message.notification?.title ?? message.data['title']?.toString() ?? 'Petsy';
        final body = message.notification?.body ?? message.data['body']?.toString() ?? '';
        final route = _routeOf(message) ?? '/notifications';
        await PushNotificationService.instance.showNow(
          title: title,
          body: body.isEmpty ? '…' : body,
          payload: route,
          id: (message.messageId ?? route).hashCode & 0x7fffffff,
          channel: message.data['type'] == 'appointment'
              ? NotificationChannel.appointments
              : NotificationChannel.messages,
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        final route = _routeOf(message);
        if (route != null) onOpenRoute?.call(route);
      });

      // The server targets registration tokens (FCM HTTP v1), not installation IDs from onRegistered.
      // ignore: deprecated_member_use
      if (onTokenRefresh != null) messaging.onTokenRefresh.listen(onTokenRefresh);

      final initial = await messaging.getInitialMessage();
      if (initial != null) {
        final route = _routeOf(initial);
        if (route != null) {
          Future<void>.delayed(const Duration(milliseconds: 700), () => onOpenRoute?.call(route));
        }
      }

      _ready = true;
      return true;
    } catch (e) {
      debugPrint('FCM init skipped/failed: $e');
      _ready = false;
      return false;
    }
  }

  static String? _routeOf(RemoteMessage message) {
    final route = message.data['route']?.toString();
    if (route != null && route.startsWith('/')) return route;
    final conversationId = message.data['conversation_id']?.toString();
    return conversationId != null && conversationId.isNotEmpty ? '/chat/$conversationId' : null;
  }

  Future<String?> token() async {
    if (!_ready) return null;
    try {
      if (Platform.isIOS) {
        final apns = await FirebaseMessaging.instance.getAPNSToken();
        if (apns == null) {
          // Wait briefly for APNs on first launch.
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      }
      // ignore: deprecated_member_use
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('FCM getToken failed: $e');
      return null;
    }
  }
}
