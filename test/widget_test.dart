import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petsy/core/api_client.dart';
import 'package:petsy/main.dart';
import 'package:petsy/services/petsy_api.dart';
import 'package:petsy/state/app_state.dart';
import 'package:petsy/state/badge_counts.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) =>
      throw DioException.connectionError(requestOptions: options, reason: 'offline');

  @override
  void close({bool force = false}) {}
}

Future<void> _pumpApp(WidgetTester tester, Map<String, Object> prefsValues) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefsValues);
  final prefs = await SharedPreferences.getInstance();
  final api = PetsyApi(ApiClient(baseUrl: 'http://test.local', adapter: _OfflineAdapter()));
  final auth = AuthState(api, prefs);
  await auth.restore();
  await tester.pumpWidget(PetsyApp(
    api: api,
    auth: auth,
    locale: LocaleState(prefs),
    cart: CartState(prefs),
    badges: BadgeCountsState(api),
    prefs: prefs,
  ));
  await _settle(tester);
}

/// The auth screens loop background animations forever, so `pumpAndSettle` never returns.
Future<void> _settle(WidgetTester tester, [Duration total = const Duration(seconds: 3)]) async {
  for (var t = Duration.zero; t < total; t += const Duration(milliseconds: 100)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('logged-out user lands on the Arabic RTL login screen', (tester) async {
    await _pumpApp(tester, {});

    expect(find.text('تسجيل الدخول'), findsWidgets);
    expect(find.text('المتابعة كضيف'), findsOneWidget);
    final direction = Directionality.of(tester.element(find.text('المتابعة كضيف')));
    expect(direction, TextDirection.rtl);
  });

  testWidgets('guest can open home and switch to English', (tester) async {
    await _pumpApp(tester, {});

    await tester.tap(find.text('المتابعة كضيف'));
    await _settle(tester);
    expect(find.text('الرئيسية'), findsOneWidget);
    expect(find.text('تعذّر الاتصال بالخادم'), findsOneWidget);

    await tester.tap(find.text('ع'));
    await _settle(tester);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Could not reach the server'), findsOneWidget);
  });

  testWidgets('messages tab asks guests to log in', (tester) async {
    await _pumpApp(tester, {'language': 'en'});

    await tester.tap(find.text('Continue as guest'));
    await _settle(tester);
    await tester.tap(find.text('Messages'));
    await _settle(tester);
    expect(find.text('Log in to access your pets, messages and orders'), findsOneWidget);
  });
}
