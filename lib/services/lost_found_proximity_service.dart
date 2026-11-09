import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'geo_service.dart';
import 'petsy_api.dart';
import 'push_notification_service.dart';

const lostFoundAlertsEnabledKey = 'petsy_lost_found_alerts';
const lostFoundAlertKmKey = 'petsy_lost_found_alert_km';
const _seenIdsKey = 'petsy_seen_lost_found_ids';
const _seededKey = 'petsy_lf_alerts_seeded';

/// Local proximity alerts for new nearby lost/found posts (no FCM required).
class LostFoundProximityService {
  LostFoundProximityService._();
  static final LostFoundProximityService instance = LostFoundProximityService._();

  Future<bool> areEnabled(SharedPreferences prefs) async =>
      prefs.getBool(lostFoundAlertsEnabledKey) ?? true;

  Future<void> setEnabled(SharedPreferences prefs, bool enabled) async {
    await prefs.setBool(lostFoundAlertsEnabledKey, enabled);
  }

  double alertKm(SharedPreferences prefs) => prefs.getDouble(lostFoundAlertKmKey) ?? 10;

  Future<void> setAlertKm(SharedPreferences prefs, double km) async {
    await prefs.setDouble(lostFoundAlertKmKey, km);
  }

  /// Checks active posts near the device and shows a local notification for new ones.
  Future<void> check({
    required PetsyApi api,
    required SharedPreferences prefs,
    String? myUserId,
    required String Function(LostFoundPost post, double km) titleFor,
    required String Function(LostFoundPost post, double km) bodyFor,
  }) async {
    if (!await PushNotificationService.instance.areEnabled(prefs)) return;
    if (!await areEnabled(prefs)) return;

    final loc = await GeoService.instance.currentLocation();
    // Avoid Damascus-fallback spam when GPS is unavailable.
    if (!loc.fromDevice) return;

    final radius = alertKm(prefs);
    List<LostFoundPost> posts;
    try {
      posts = await api.lostFound(status: 'active');
    } catch (e) {
      debugPrint('lost-found proximity fetch failed: $e');
      return;
    }

    final seen = prefs.getStringList(_seenIdsKey)?.toSet() ?? <String>{};
    final firstRun = prefs.getBool(_seededKey) != true;
    final nextSeen = <String>{...seen};
    final geo = GeoService.instance;

    for (final post in posts) {
      if (myUserId != null && myUserId.isNotEmpty && post.userId == myUserId) {
        nextSeen.add(post.id);
        continue;
      }
      if (!post.hasCoords) continue;

      final point = LatLng(post.lat!, post.lng!);
      final km = geo.kmBetween(loc.point, point);

      if (firstRun) {
        nextSeen.add(post.id);
        continue;
      }

      if (km > radius) continue;
      if (seen.contains(post.id)) continue;

      try {
        await PushNotificationService.instance.showNow(
          title: titleFor(post, km),
          body: bodyFor(post, km),
          payload: '/lost-found/${post.id}',
          id: post.id.hashCode & 0x7fffffff,
          channel: NotificationChannel.lostFound,
        );
      } catch (e) {
        debugPrint('lost-found proximity notify failed: $e');
      }
      nextSeen.add(post.id);
    }

    if (firstRun) {
      for (final post in posts) {
        nextSeen.add(post.id);
      }
      await prefs.setBool(_seededKey, true);
    }

    // Cap stored ids to avoid unbounded prefs growth.
    final capped = nextSeen.toList();
    if (capped.length > 400) {
      capped.removeRange(0, capped.length - 400);
    }
    await prefs.setStringList(_seenIdsKey, capped);
  }
}
