import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../models/models.dart';
import '../services/petsy_api.dart';

const _tokenKey = 'auth_token';
const _userKey = 'auth_user';
const _languageKey = 'language';
const _cartKey = 'cart';
const _onboardingPrefix = 'onboarding_done_';

class AuthState extends ChangeNotifier {
  AuthState(this._api, this._prefs) {
    _api.client.onUnauthorized = () => logout(sessionValid: false);
  }

  final PetsyApi _api;
  final SharedPreferences _prefs;

  /// Runs before the token is cleared on a user-initiated logout, while API calls still authenticate.
  Future<void> Function()? beforeLogout;

  User? _user;
  bool _ready = false;

  User? get user => _user;
  bool get isLoggedIn => _user != null;
  bool get isReady => _ready;

  /// Restores the cached session immediately, then refreshes it from `/auth/me`.
  Future<void> restore() async {
    final token = _prefs.getString(_tokenKey);
    final cachedUser = _prefs.getString(_userKey);
    if (token != null && cachedUser != null) {
      _api.client.token = token;
      _user = User.fromJson(jsonDecode(cachedUser) as Json);
    }
    _ready = true;
    notifyListeners();

    if (token != null) {
      try {
        await _setUser(await _api.me());
      } on ApiException catch (e) {
        if (e.isUnauthorized) await logout(sessionValid: false);
      }
    }
  }

  Future<void> login(String email, String password) => _apply(_api.login(email, password));

  Future<void> loginSocial({
    required String provider,
    required String providerUserId,
    String? email,
    String? name,
    String? avatar,
    String? accessToken,
  }) =>
      _apply(_api.socialLogin(
        provider: provider,
        providerUserId: providerUserId,
        email: email,
        name: name,
        avatar: avatar,
        accessToken: accessToken,
      ));

  Future<void> verify(String userId, String code) => _apply(_api.verify(userId, code));

  Future<void> updateProfile(Json data) async => _setUser(await _api.updateProfile(data));

  bool get needsOnboarding {
    final id = _user?.id;
    if (id == null) return false;
    return !(_prefs.getBool('$_onboardingPrefix$id') ?? false);
  }

  Future<void> completeOnboarding() async {
    final id = _user?.id;
    if (id == null) return;
    await _prefs.setBool('$_onboardingPrefix$id', true);
    notifyListeners();
  }

  Future<void> logout({bool sessionValid = true}) async {
    if (sessionValid && _user != null) {
      try {
        await beforeLogout?.call().timeout(const Duration(seconds: 5));
      } catch (_) {}
    }
    _api.client.token = null;
    _user = null;
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_userKey);
    notifyListeners();
  }

  Future<void> _apply(Future<AuthResult> request) async {
    final result = await request;
    _api.client.token = result.token;
    await _prefs.setString(_tokenKey, result.token);
    await _setUser(result.user);
  }

  Future<void> _setUser(User user) async {
    _user = user;
    await _prefs.setString(_userKey, jsonEncode(user.toJson()));
    notifyListeners();
  }
}

class LocaleState extends ChangeNotifier {
  LocaleState(this._prefs) : _locale = Locale(_prefs.getString(_languageKey) ?? 'ar');

  final SharedPreferences _prefs;
  Locale _locale;

  Locale get locale => _locale;

  Future<void> setLanguage(String code) async {
    _locale = Locale(code);
    await _prefs.setString(_languageKey, code);
    notifyListeners();
  }

  Future<void> toggle() => setLanguage(_locale.languageCode == 'ar' ? 'en' : 'ar');
}

class CartState extends ChangeNotifier {
  CartState(this._prefs) {
    final raw = _prefs.getString(_cartKey);
    if (raw != null) {
      _items.addAll((jsonDecode(raw) as List).map((e) => CartItem.fromJson(e as Json)));
    }
  }

  final SharedPreferences _prefs;
  final List<CartItem> _items = [];

  List<CartItem> get items => List.unmodifiable(_items);
  int get count => _items.fold(0, (sum, i) => sum + i.quantity);
  double get total => _items.fold(0, (sum, i) => sum + i.price * i.quantity);

  void add(Product product) {
    final existing = _items.where((i) => i.productId == product.id).firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      _items.add(CartItem(productId: product.id, name: product.name, price: product.price, image: product.image));
    }
    _persist();
  }

  /// Merge a cart line (used by reorder). Adds quantity if the product already exists.
  void addCartItem(CartItem item, {bool notify = true}) {
    if (item.quantity <= 0) return;
    final existing = _items.where((i) => i.productId == item.productId).firstOrNull;
    if (existing != null) {
      existing.quantity += item.quantity;
    } else {
      _items.add(CartItem(
        productId: item.productId,
        name: item.name,
        price: item.price,
        image: item.image,
        quantity: item.quantity,
      ));
    }
    if (notify) _persist();
  }

  void addCartItems(Iterable<CartItem> items) {
    for (final item in items) {
      addCartItem(item, notify: false);
    }
    _persist();
  }

  void setQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      _items.removeWhere((i) => i.productId == productId);
    } else {
      _items.firstWhere((i) => i.productId == productId).quantity = quantity;
    }
    _persist();
  }

  void clear() {
    _items.clear();
    _persist();
  }

  void _persist() {
    _prefs.setString(_cartKey, jsonEncode(_items.map((e) => e.toJson()).toList()));
    notifyListeners();
  }
}
