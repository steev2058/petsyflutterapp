import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'chat_prefs.dart';
import 'chat_session.dart';
import 'petsy_api.dart';
import 'push_notification_service.dart';

const _snapshotKey = 'petsy_chat_unread_snapshot';
const _seededKey = 'petsy_chat_alerts_seeded';

/// Local banners when unread chat counts rise (works without FCM).
class ChatMessageAlertService {
  ChatMessageAlertService._();
  static final ChatMessageAlertService instance = ChatMessageAlertService._();

  Future<void> check({
    required PetsyApi api,
    required SharedPreferences prefs,
    String hiddenBody = 'New message',
  }) async {
    if (!await PushNotificationService.instance.areEnabled(prefs)) return;

    late final List<Conversation> conversations;
    try {
      conversations = await api.conversations();
    } catch (e) {
      debugPrint('chat alert fetch failed: $e');
      return;
    }

    final prev = _loadSnapshot(prefs);
    final firstRun = prefs.getBool(_seededKey) != true;
    final next = <String, int>{};
    final openId = ChatSession.instance.openConversationId;

    for (final c in conversations) {
      next[c.id] = c.unreadCount;
      if (firstRun) continue;
      final before = prev[c.id] ?? 0;
      if (c.unreadCount <= before) continue;
      if (openId != null && openId == c.id) continue;
      if (ChatPrefs.isMuted(prefs, c.id)) continue;

      final previewOn = ChatPrefs.previewEnabled(prefs);
      final preview = (c.lastMessage ?? '').trim();
      final body = !previewOn ? hiddenBody : (preview.isEmpty ? '…' : preview);
      try {
        await PushNotificationService.instance.showNow(
          title: c.otherUser.name,
          body: body,
          payload: '/chat/${c.id}',
          id: ('chat_${c.id}'.hashCode) & 0x7fffffff,
          channel: NotificationChannel.messages,
        );
        await ChatPrefs.playIncomingSound(prefs);
      } catch (e) {
        debugPrint('chat alert notify failed: $e');
      }
    }

    if (firstRun) await prefs.setBool(_seededKey, true);
    await prefs.setString(_snapshotKey, jsonEncode(next));
  }

  Map<String, int> _loadSnapshot(SharedPreferences prefs) {
    final raw = prefs.getString(_snapshotKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return {};
      return {
        for (final e in map.entries) e.key.toString(): int.tryParse('${e.value}') ?? 0,
      };
    } catch (_) {
      return {};
    }
  }
}
