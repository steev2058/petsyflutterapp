import 'package:flutter/foundation.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/config.dart';

enum SocialProvider { google, facebook, instagram }

extension SocialProviderX on SocialProvider {
  String get id => name;

  String get labelKey => switch (this) {
        SocialProvider.google => 'continue_google',
        SocialProvider.facebook => 'continue_facebook',
        SocialProvider.instagram => 'continue_instagram',
      };
}

class SocialAuthResult {
  const SocialAuthResult({
    required this.provider,
    required this.providerUserId,
    this.email,
    this.name,
    this.avatar,
    this.accessToken,
    this.demo = false,
  });

  final String provider;
  final String providerUserId;
  final String? email;
  final String? name;
  final String? avatar;
  final String? accessToken;
  final bool demo;
}

class SocialAuthException implements Exception {
  SocialAuthException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Real Google / Facebook sign-in with optional demo fallback for local builds.
class SocialAuthService {
  SocialAuthService._();
  static final SocialAuthService instance = SocialAuthService._();

  bool _googleReady = false;

  Future<void> _ensureGoogle() async {
    if (_googleReady) return;
    final serverClientId = AppConfig.googleServerClientId.trim();
    await GoogleSignIn.instance.initialize(
      serverClientId: serverClientId.isEmpty ? null : serverClientId,
    );
    _googleReady = true;
  }

  Future<SocialAuthResult> signIn(SocialProvider provider) async {
    return switch (provider) {
      SocialProvider.google => _google(),
      SocialProvider.facebook => _facebook(),
      // Consumer Instagram Login is provided by Meta through Facebook Login.
      SocialProvider.instagram => _facebook(asProvider: 'instagram'),
    };
  }

  Future<SocialAuthResult> _google() async {
    try {
      await _ensureGoogle();
      if (!GoogleSignIn.instance.supportsAuthenticate()) {
        throw SocialAuthException('google_unsupported');
      }
      final account = await GoogleSignIn.instance.authenticate(
        scopeHint: const ['email', 'profile'],
      );
      final auth = account.authentication;
      // The backend verifies a Google ID token (aud = Web/Android OAuth client).
      final idToken = auth.idToken;
      if (idToken == null || idToken.isEmpty) {
        throw SocialAuthException('google_token_missing');
      }

      return SocialAuthResult(
        provider: 'google',
        providerUserId: account.id,
        email: account.email,
        name: account.displayName,
        avatar: account.photoUrl,
        accessToken: idToken,
      );
    } catch (e) {
      if (AppConfig.allowDemoSocial) {
        debugPrint('Google Sign-In fell back to demo: $e');
        return _demo(SocialProvider.google);
      }
      if (e is SocialAuthException) rethrow;
      throw SocialAuthException('google_signin_failed');
    }
  }

  Future<SocialAuthResult> _facebook({String asProvider = 'facebook'}) async {
    final appId = AppConfig.facebookAppId.trim();
    final configured = appId.isNotEmpty && appId != '0';
    if (!configured) {
      if (AppConfig.allowDemoSocial) {
        return _demo(asProvider == 'instagram' ? SocialProvider.instagram : SocialProvider.facebook);
      }
      throw SocialAuthException('social_not_configured');
    }
    try {
      final login = await FacebookAuth.instance.login(
        permissions: const ['email', 'public_profile'],
      );
      if (login.status != LoginStatus.success || login.accessToken == null) {
        if (login.status == LoginStatus.cancelled) {
          throw SocialAuthException('social_cancelled');
        }
        throw SocialAuthException(
          asProvider == 'instagram' ? 'instagram_signin_failed' : 'facebook_signin_failed',
        );
      }
      final token = login.accessToken!.tokenString;
      final data = await FacebookAuth.instance.getUserData(fields: 'id,name,email,picture.width(200)');
      final picture = data['picture'];
      String? avatar;
      if (picture is Map && picture['data'] is Map) {
        avatar = picture['data']['url']?.toString();
      }
      final userId = data['id']?.toString() ?? '';
      if (userId.isEmpty) {
        throw SocialAuthException(
          asProvider == 'instagram' ? 'instagram_signin_failed' : 'facebook_signin_failed',
        );
      }
      return SocialAuthResult(
        provider: asProvider,
        providerUserId: userId,
        email: data['email']?.toString(),
        name: data['name']?.toString(),
        avatar: avatar,
        accessToken: token,
      );
    } catch (e) {
      if (e is SocialAuthException) {
        if (e.message == 'social_cancelled') rethrow;
        if (AppConfig.allowDemoSocial) {
          debugPrint('Meta Sign-In fell back to demo: $e');
          return _demo(asProvider == 'instagram' ? SocialProvider.instagram : SocialProvider.facebook);
        }
        rethrow;
      }
      if (AppConfig.allowDemoSocial) {
        debugPrint('Meta Sign-In fell back to demo: $e');
        return _demo(asProvider == 'instagram' ? SocialProvider.instagram : SocialProvider.facebook);
      }
      throw SocialAuthException(
        asProvider == 'instagram' ? 'instagram_signin_failed' : 'facebook_signin_failed',
      );
    }
  }

  Future<SocialAuthResult> _demo(SocialProvider provider) async {
    if (!AppConfig.allowDemoSocial) {
      throw SocialAuthException('social_not_configured');
    }
    final stamp = DateTime.now().millisecondsSinceEpoch;
    return SocialAuthResult(
      provider: provider.id,
      providerUserId: 'demo_${provider.id}_$stamp',
      email: 'demo.${provider.id}.$stamp@petsy.app',
      name: switch (provider) {
        SocialProvider.google => 'Google User',
        SocialProvider.facebook => 'Facebook User',
        SocialProvider.instagram => 'Instagram User',
      },
      demo: true,
    );
  }
}
