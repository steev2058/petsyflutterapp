import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api_client.dart';
import 'core/i18n.dart';
import 'core/theme.dart';
import 'router.dart';
import 'services/chat_message_alert_service.dart';
import 'services/chat_prefs.dart';
import 'services/chat_realtime_service.dart';
import 'services/chat_session.dart';
import 'services/fcm_service.dart';
import 'services/geo_service.dart';
import 'services/lost_found_proximity_service.dart';
import 'services/petsy_api.dart';
import 'services/push_notification_service.dart';
import 'state/app_state.dart';
import 'state/badge_counts.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final api = PetsyApi(ApiClient());
  final auth = AuthState(api, prefs);
  final badges = BadgeCountsState(api);
  await PushNotificationService.instance.init();
  await auth.restore();
  badges.start(loggedIn: auth.isLoggedIn);

  runApp(PetsyApp(
    api: api,
    auth: auth,
    locale: LocaleState(prefs),
    cart: CartState(prefs),
    badges: badges,
    prefs: prefs,
  ));
}

class PetsyApp extends StatefulWidget {
  const PetsyApp({
    super.key,
    required this.api,
    required this.auth,
    required this.locale,
    required this.cart,
    required this.badges,
    required this.prefs,
  });

  final PetsyApi api;
  final AuthState auth;
  final LocaleState locale;
  final CartState cart;
  final BadgeCountsState badges;
  final SharedPreferences prefs;

  @override
  State<PetsyApp> createState() => _PetsyAppState();
}

class _PetsyAppState extends State<PetsyApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(widget.auth);
  Timer? _chatAlertPoll;
  StreamSubscription<ChatRealtimeEvent>? _wsAlerts;
  bool _fcmReady = false;
  bool _serverPushActive = false;
  bool _foreground = true;

  /// While backgrounded, chat alerts come from server pushes instead of local polling.
  bool get _deferChatAlertsToServer => !_foreground && _serverPushActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.instance.onOpenRoute = (route) {
      try {
        _router.go(route);
      } catch (_) {}
    };
    widget.auth.addListener(_onAuthChanged);
    widget.auth.beforeLogout = () async {
      await PushNotificationService.instance.unregisterFromBackend(widget.api, widget.prefs);
      _serverPushActive = false;
    };
    widget.locale.addListener(_registerPushToken);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _fcmReady = await FcmService.instance.init(
        onOpenRoute: (route) {
          try {
            _router.go(route);
          } catch (_) {}
        },
        onTokenRefresh: (_) => _registerPushToken(),
      );
      await _bootstrapPush();
    });
    _chatAlertPoll = Timer.periodic(const Duration(seconds: 15), (_) => _checkChatAlerts());
    _wsAlerts = ChatRealtimeService.instance.events.listen(_onRealtimeAlert);
  }

  @override
  void dispose() {
    _chatAlertPoll?.cancel();
    _wsAlerts?.cancel();
    widget.badges.dispose();
    ChatRealtimeService.instance.disconnect(reconnect: false);
    widget.auth.removeListener(_onAuthChanged);
    widget.auth.beforeLogout = null;
    widget.locale.removeListener(_registerPushToken);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onAuthChanged() {
    if (widget.auth.isLoggedIn) {
      widget.badges.start(loggedIn: true);
      _bootstrapPush();
    } else {
      widget.badges.stop();
      ChatRealtimeService.instance.disconnect(reconnect: false);
    }
  }

  Future<void> _onRealtimeAlert(ChatRealtimeEvent event) async {
    if (!widget.auth.isLoggedIn) return;
    if (event.type != 'new_message') return;
    if (_deferChatAlertsToServer) return;
    final conversationId = event.conversationId;
    if (conversationId == null || conversationId.isEmpty) return;
    if (ChatSession.instance.openConversationId == conversationId) return;
    if (ChatPrefs.isMuted(widget.prefs, conversationId)) return;
    if (!await PushNotificationService.instance.areEnabled(widget.prefs)) return;

    final raw = event.payload['message'];
    final myId = widget.auth.user?.id;
    String title = translate(widget.locale.locale.languageCode, 'new_chat_message');
    var body = translate(widget.locale.locale.languageCode, 'new_chat_message');
    if (raw is Map) {
      final senderId = raw['sender_id']?.toString();
      if (myId != null && senderId == myId) return;
      final content = (raw['content']?.toString() ?? '').trim();
      final hasImage = (raw['image_url']?.toString() ?? '').trim().isNotEmpty;
      if (ChatPrefs.previewEnabled(widget.prefs)) {
        body = content.isNotEmpty ? content : (hasImage ? '📷' : body);
      }
    }
    try {
      await PushNotificationService.instance.showNow(
        title: title,
        body: body,
        payload: '/chat/$conversationId',
        id: ('chat_$conversationId'.hashCode) & 0x7fffffff,
        channel: NotificationChannel.messages,
      );
      await ChatPrefs.playIncomingSound(widget.prefs);
    } catch (_) {}
  }

  Future<void> _connectChatRealtime() async {
    final token = widget.api.client.token;
    if (token == null || token.isEmpty) return;
    await ChatRealtimeService.instance.connect(token);
  }

  Future<void> _syncChatSettings() async {
    try {
      final settings = await widget.api.userSettings();
      await ChatPrefs.applyFromSettings(widget.prefs, settings);
    } catch (_) {}
  }

  Future<void> _checkChatAlerts() async {
    if (!widget.auth.isLoggedIn) return;
    if (_deferChatAlertsToServer) return;
    try {
      final lang = widget.locale.locale.languageCode;
      await ChatMessageAlertService.instance.check(
        api: widget.api,
        prefs: widget.prefs,
        hiddenBody: translate(lang, 'new_chat_message'),
      );
    } catch (_) {}
  }

  Future<void> _bootstrapPush() async {
    if (!widget.auth.isLoggedIn) return;
    await _connectChatRealtime();
    await _syncChatSettings();
    final push = PushNotificationService.instance;
    if (!await push.areEnabled(widget.prefs)) {
      await push.unregisterFromBackend(widget.api, widget.prefs);
      _serverPushActive = false;
      await _checkChatAlerts();
      return;
    }
    await push.requestPermission();
    await _registerPushToken();
    try {
      final appointments = await widget.api.appointments();
      await push.syncAppointments(
        appointments: appointments,
        title: 'Petsy',
        bodyFor: (a) => '${a.reason} · ${a.when(widget.locale.locale.languageCode)}',
      );
    } catch (_) {}
    try {
      final lang = widget.locale.locale.languageCode;
      await LostFoundProximityService.instance.check(
        api: widget.api,
        prefs: widget.prefs,
        myUserId: widget.auth.user?.id,
        titleFor: (post, km) => translate(lang, 'nearby_alert_title')
            .replaceAll('{type}', translate(lang, post.type)),
        bodyFor: (post, km) => translate(lang, 'nearby_alert_body')
            .replaceAll('{species}', translate(lang, post.petSpecies))
            .replaceAll('{location}', post.lastSeenLocation)
            .replaceAll('{km}', GeoService.instance.formatKm(km, lang)),
      );
    } catch (_) {}
    await _checkChatAlerts();
  }

  Future<void> _registerPushToken() async {
    if (!widget.auth.isLoggedIn) return;
    final fcmToken = _fcmReady ? await FcmService.instance.token() : null;
    _serverPushActive = await PushNotificationService.instance.registerWithBackend(
      widget.api,
      widget.prefs,
      fcmToken: fcmToken,
      language: widget.locale.locale.languageCode,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` still runs the foreground FCM handler, which leaves chat to the socket.
    _foreground = state == AppLifecycleState.resumed || state == AppLifecycleState.inactive;
    if (state == AppLifecycleState.resumed) {
      _bootstrapPush();
      if (widget.auth.isLoggedIn) widget.badges.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: widget.api),
        Provider.value(value: widget.prefs),
        ChangeNotifierProvider.value(value: widget.auth),
        ChangeNotifierProvider.value(value: widget.locale),
        ChangeNotifierProvider.value(value: widget.cart),
        ChangeNotifierProvider.value(value: widget.badges),
      ],
      child: Consumer<LocaleState>(
        builder: (context, localeState, _) => MaterialApp.router(
          title: 'Petsy',
          debugShowCheckedModeBanner: false,
          theme: buildPetsyTheme(),
          locale: localeState.locale,
          supportedLocales: supportedLocales,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          routerConfig: _router,
          // Pushed routes sit above the shell; without a solid root fill, Android
          // shows the window's black background through transparent scaffolds.
          builder: (context, child) => ColoredBox(
            color: PetsyColors.backgroundAlt,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}
