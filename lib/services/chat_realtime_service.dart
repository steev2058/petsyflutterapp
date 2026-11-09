import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';

class ChatRealtimeEvent {
  ChatRealtimeEvent({
    required this.type,
    this.conversationId,
    this.payload = const {},
  });

  final String type;
  final String? conversationId;
  final Map<String, dynamic> payload;
}

/// Live chat channel for typing, presence, and message fan-out.
class ChatRealtimeService {
  ChatRealtimeService._();
  static final ChatRealtimeService instance = ChatRealtimeService._();

  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _ping;
  Timer? _reconnect;
  String? _token;
  final _events = StreamController<ChatRealtimeEvent>.broadcast();
  bool _intentionalClose = false;

  Stream<ChatRealtimeEvent> get events => _events.stream;
  bool get isConnected => _channel != null;

  Future<void> connect(String accessToken) async {
    if (accessToken.isEmpty) return;
    if (_token == accessToken && _channel != null) return;
    _intentionalClose = false;
    _token = accessToken;
    await disconnect(reconnect: false);
    try {
      final uri = Uri.parse(AppConfig.chatWsUrl(accessToken));
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _sub = channel.stream.listen(
        _onData,
        onError: (e) {
          debugPrint('chat ws error: $e');
          _scheduleReconnect();
        },
        onDone: _scheduleReconnect,
        cancelOnError: false,
      );
      _ping?.cancel();
      _ping = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'type': 'ping'});
      });
    } catch (e) {
      debugPrint('chat ws connect failed: $e');
      _scheduleReconnect();
    }
  }

  Future<void> disconnect({bool reconnect = true}) async {
    if (!reconnect) _intentionalClose = true;
    _reconnect?.cancel();
    _ping?.cancel();
    _ping = null;
    await _sub?.cancel();
    _sub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  void setTyping({required String conversationId, required bool isTyping}) {
    _send({
      'type': 'typing',
      'conversation_id': conversationId,
      'is_typing': isTyping,
    });
  }

  void markRead(String conversationId) {
    _send({
      'type': 'read',
      'conversation_id': conversationId,
    });
  }

  void _send(Map<String, dynamic> payload) {
    final channel = _channel;
    if (channel == null) return;
    try {
      channel.sink.add(jsonEncode(payload));
    } catch (e) {
      debugPrint('chat ws send failed: $e');
    }
  }

  void _onData(dynamic raw) {
    try {
      final map = raw is String
          ? jsonDecode(raw)
          : raw is Map
              ? raw
              : null;
      if (map is! Map) return;
      final type = '${map['type'] ?? ''}';
      if (type.isEmpty || type == 'pong' || type == 'connected') return;
      final payloadRaw = map['payload'];
      final payload = payloadRaw is Map ? Map<String, dynamic>.from(payloadRaw) : <String, dynamic>{};
      _events.add(ChatRealtimeEvent(
        type: type,
        conversationId: map['conversation_id']?.toString(),
        payload: payload,
      ));
    } catch (e) {
      debugPrint('chat ws parse failed: $e');
    }
  }

  void _scheduleReconnect() {
    _channel = null;
    _ping?.cancel();
    if (_intentionalClose) return;
    final token = _token;
    if (token == null || token.isEmpty) return;
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), () {
      if (!_intentionalClose) connect(token);
    });
  }
}
