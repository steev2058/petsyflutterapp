import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petsy/core/api_client.dart';
import 'package:petsy/models/models.dart';
import 'package:petsy/state/app_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.body, this.status);

  final Object body;
  final int status;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream, Future<void>? cancelFuture) async =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      });

  @override
  void close({bool force = false}) {}
}

void main() {
  group('models', () {
    test('Vet parses vet_profiles keys', () {
      final vet = Vet.fromJson({
        'id': 'v1',
        'user_id': 'u1',
        'name': 'Dr. Lina',
        'experience_years': 7,
        'rating_avg': 4.6,
        'rating_count': 12,
        'location_text': 'Mezzeh',
        'image_url': 'https://x/y.png',
      });
      expect(vet.experienceYears, 7);
      expect(vet.rating, 4.6);
      expect(vet.ratingCount, 12);
      expect(vet.location, 'Mezzeh');
      expect(vet.image, 'https://x/y.png');
    });

    test('Vet parses legacy vets keys', () {
      final vet = Vet.fromJson({
        'id': 'v2',
        'name': 'Dr. Sami',
        'experience': '5',
        'rating': 4,
        'reviews_count': 3,
        'address': 'Aleppo',
      });
      expect(vet.experienceYears, 5);
      expect(vet.rating, 4.0);
      expect(vet.ratingCount, 3);
      expect(vet.location, 'Aleppo');
    });

    test('naive server datetimes are treated as UTC', () {
      final post = CommunityPost.fromJson({
        'id': 'p1',
        'user_id': 'u',
        'user_name': 'A',
        'type': 'tip',
        'title': 't',
        'content': 'c',
        'created_at': '2026-02-11T10:00:00',
      });
      expect(post.createdAt!.toUtc(), DateTime.utc(2026, 2, 11, 10));
    });

    test('Pet tolerates missing optional fields', () {
      final pet = Pet.fromJson({'id': 1, 'name': 'Mishmish', 'species': 'cat', 'gender': 'female', 'owner_id': 'o'});
      expect(pet.id, '1');
      expect(pet.status, 'owned');
      expect(pet.weight, isNull);
    });
  });

  group('ApiClient errors', () {
    Future<ApiException> run(Object body, int status) async {
      final client = ApiClient(baseUrl: 'http://test.local', adapter: _StubAdapter(body, status));
      try {
        await client.get('/x');
      } on ApiException catch (e) {
        return e;
      }
      fail('expected ApiException');
    }

    test('structured detail object', () async {
      final e = await run({
        'detail': {'code': 'AUTH_INVALID_CREDENTIALS', 'message': 'Invalid credentials'}
      }, 401);
      expect(e.message, 'Invalid credentials');
      expect(e.code, 'AUTH_INVALID_CREDENTIALS');
      expect(e.isUnauthorized, isTrue);
    });

    test('string detail', () async {
      final e = await run({'detail': 'Cannot message this user'}, 403);
      expect(e.message, 'Cannot message this user');
    });

    test('validation list detail', () async {
      final e = await run({
        'detail': [
          {'msg': 'field required'}
        ]
      }, 422);
      expect(e.message, 'field required');
    });

    test('401 with a token triggers onUnauthorized', () async {
      var called = false;
      final client = ApiClient(baseUrl: 'http://test.local', adapter: _StubAdapter({'detail': 'x'}, 401))
        ..token = 'abc'
        ..onUnauthorized = () => called = true;
      await expectLater(client.get('/x'), throwsA(isA<ApiException>()));
      expect(called, isTrue);
    });
  });

  test('CartState adds, merges, updates and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final cart = CartState(prefs);
    final food = Product(id: 'p1', name: 'Food', category: 'food', price: 10, petType: 'cat');
    cart.add(food);
    cart.add(food);
    cart.add(Product(id: 'p2', name: 'Toy', category: 'toys', price: 2.5, petType: 'dog'));
    expect(cart.count, 3);
    expect(cart.total, 22.5);

    cart.setQuantity('p2', 0);
    expect(cart.items.length, 1);

    final restored = CartState(prefs);
    expect(restored.count, 2);
    expect(restored.total, 20);
  });

  test('PetAge parses legacy and canonical ages', () {
    PetAge? age(String raw) => PetAge.parse(raw);
    expect(age('2 years')!.stored, '2 years');
    expect(age('1 Year')!.stored, '1 year');
    expect(age('6 months')!.months, isTrue);
    expect(age('3 mo')!.stored, '3 months');
    expect(age('5')!.stored, '5 years');
    expect(age('1,5 years')!.stored, '1.5 years');
    expect(age('3 سنوات')!.stored, '3 years');
    expect(age('4 أشهر')!.stored, '4 months');
    expect(age('1-2'), isNull);
    expect(age(''), isNull);
  });
}
