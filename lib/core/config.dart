class AppConfig {
  /// Override at build time: `flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000/api`
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://petsy.company/api',
  );

  /// Google OAuth Web client ID (serverClientId) for ID token audience.
  static const googleServerClientId = String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID');

  /// Facebook App ID / client token — also set Android string resources for native SDK.
  static const facebookAppId = String.fromEnvironment('FACEBOOK_APP_ID');
  static const facebookClientToken = String.fromEnvironment('FACEBOOK_CLIENT_TOKEN');

  /// When true, Google/Facebook fall back to a local demo identity if native OAuth isn't configured.
  static const allowDemoSocial = bool.fromEnvironment('ALLOW_DEMO_SOCIAL', defaultValue: true);

  static const requestTimeout = Duration(seconds: 12);

  /// API origin without the `/api` suffix — used for uploaded media URLs.
  static String get mediaBaseUrl {
    final base = apiBaseUrl.trim();
    if (base.endsWith('/api')) return base.substring(0, base.length - 4);
    if (base.endsWith('/api/')) return base.substring(0, base.length - 5);
    return base;
  }

  static String resolveMediaUrl(String? url) {
    final src = url?.trim() ?? '';
    if (src.isEmpty) return '';
    if (src.startsWith('http://') ||
        src.startsWith('https://') ||
        src.startsWith('file://') ||
        src.startsWith('data:')) {
      return src;
    }
    if (src.startsWith('/')) return '$mediaBaseUrl$src';
    return src;
  }

  static String get _publicShareBase =>
      mediaBaseUrl.contains('petsy.company') ? mediaBaseUrl : 'https://petsy.company';

  /// Public share URL for a lost/found report (falls back to production host in local/dev).
  static String lostFoundShareUrl(String id) => '$_publicShareBase/lost-found/$id';

  static String communityShareUrl(String id) => '$_publicShareBase/community/$id';

  /// Chat realtime WebSocket (`/ws/chat?token=…`).
  static String chatWsUrl(String accessToken) {
    final httpBase = mediaBaseUrl;
    final wsBase = httpBase.startsWith('https://')
        ? 'wss://${httpBase.substring(8)}'
        : httpBase.startsWith('http://')
            ? 'ws://${httpBase.substring(7)}'
            : httpBase;
    return '$wsBase/ws/chat?token=${Uri.encodeQueryComponent(accessToken)}';
  }
}
