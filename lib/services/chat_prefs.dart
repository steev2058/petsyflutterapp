import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

const chatSoundKey = 'petsy_chat_sound';
const chatPreviewKey = 'petsy_chat_preview';
const mutedConversationsKey = 'petsy_muted_conversations';

class ChatPrefs {
  ChatPrefs._();

  static bool soundEnabled(SharedPreferences prefs) => prefs.getBool(chatSoundKey) ?? true;

  static bool previewEnabled(SharedPreferences prefs) => prefs.getBool(chatPreviewKey) ?? true;

  static Future<void> setSound(SharedPreferences prefs, bool value) => prefs.setBool(chatSoundKey, value);

  static Future<void> setPreview(SharedPreferences prefs, bool value) => prefs.setBool(chatPreviewKey, value);

  static Set<String> mutedIds(SharedPreferences prefs) =>
      (prefs.getStringList(mutedConversationsKey) ?? const <String>[]).toSet();

  static bool isMuted(SharedPreferences prefs, String conversationId) =>
      mutedIds(prefs).contains(conversationId);

  static Future<void> setMutedIds(SharedPreferences prefs, Iterable<String> ids) =>
      prefs.setStringList(mutedConversationsKey, ids.toSet().toList());

  static Future<void> applyFromSettings(SharedPreferences prefs, UserSettings settings) async {
    await setSound(prefs, settings.chatSound);
    await setPreview(prefs, settings.chatPreview);
    await setMutedIds(prefs, settings.mutedConversationIds);
  }

  static Future<void> playIncomingSound(SharedPreferences prefs) async {
    if (!soundEnabled(prefs)) return;
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {
      try {
        await SystemSound.play(SystemSoundType.click);
      } catch (_) {}
    }
  }
}
