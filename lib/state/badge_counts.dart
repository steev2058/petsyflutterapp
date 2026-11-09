import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/petsy_api.dart';

class BadgeCountsState extends ChangeNotifier {
  BadgeCountsState(this._api);

  final PetsyApi _api;
  Timer? _timer;
  int notifications = 0;
  int friendRequests = 0;
  int messages = 0;
  bool _loggedIn = false;

  int get profileBadge => notifications + friendRequests;

  void start({bool loggedIn = false}) {
    _loggedIn = loggedIn;
    _timer?.cancel();
    if (!_loggedIn) {
      notifications = 0;
      friendRequests = 0;
      messages = 0;
      notifyListeners();
      return;
    }
    refresh();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => refresh());
  }

  void stop() {
    _loggedIn = false;
    _timer?.cancel();
    _timer = null;
    notifications = 0;
    friendRequests = 0;
    messages = 0;
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!_loggedIn) return;
    try {
      final data = await _api.inboxBadges();
      final nextNotif = data.$1;
      final nextFriends = data.$2;
      final nextMessages = data.$3;
      if (nextNotif == notifications && nextFriends == friendRequests && nextMessages == messages) {
        return;
      }
      notifications = nextNotif;
      friendRequests = nextFriends;
      messages = nextMessages;
      notifyListeners();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
