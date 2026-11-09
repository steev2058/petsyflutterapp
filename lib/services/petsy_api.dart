import '../core/api_client.dart';
import '../models/models.dart';

List<T> _list<T>(dynamic data, T Function(Json) parse) =>
    (data as List? ?? const []).map((e) => parse(e as Json)).toList();

class AuthResult {
  AuthResult(this.token, this.user);
  final String token;
  final User user;
}

class SignupResult {
  SignupResult({required this.userId, this.devCode});
  final String userId;
  final String? devCode;
}

class PetsyApi {
  PetsyApi(this.client);

  final ApiClient client;

  // ---------- auth ----------
  AuthResult _auth(dynamic data) =>
      AuthResult(data['access_token'] as String, User.fromJson(data['user'] as Json));

  Future<AuthResult> login(String email, String password) async =>
      _auth(await client.post('/auth/login', body: {'email': email, 'password': password}));

  Future<AuthResult> socialLogin({
    required String provider,
    required String providerUserId,
    String? email,
    String? name,
    String? avatar,
    String? accessToken,
  }) async =>
      _auth(await client.post('/auth/social', body: {
        'provider': provider,
        'provider_user_id': providerUserId,
        if (email != null && email.isNotEmpty) 'email': email,
        if (name != null && name.isNotEmpty) 'name': name,
        if (avatar != null && avatar.isNotEmpty) 'avatar': avatar,
        if (accessToken != null && accessToken.isNotEmpty) 'access_token': accessToken,
      }));

  Future<SignupResult> signup({required String name, required String email, required String password, String? phone}) async {
    final data = await client.post('/auth/signup', body: {
      'name': name,
      'email': email,
      'password': password,
      if (phone != null && phone.isNotEmpty) 'phone': phone,
    });
    return SignupResult(userId: data['user_id'].toString(), devCode: data['verification_code']?.toString());
  }

  Future<AuthResult> verify(String userId, String code) async =>
      _auth(await client.post('/auth/verify', query: {'user_id': userId, 'code': code}));

  Future<void> resendVerification(String email) =>
      client.post('/auth/resend-verification', body: {'email': email});

  Future<void> forgotPassword(String email) => client.post('/auth/forgot-password', body: {'email': email});

  Future<void> resetPassword(String email, String code, String newPassword) => client.post(
        '/auth/reset-password',
        body: {'email': email, 'code': code, 'new_password': newPassword},
      );

  Future<User> me() async => User.fromJson(await client.get('/auth/me') as Json);

  Future<User> updateProfile(Json data) async => User.fromJson(await client.put('/auth/update', body: data) as Json);

  // ---------- pets ----------
  Future<List<Pet>> pets({
    String? status,
    String? species,
    String? city,
    String? purpose,
    String? guardRole,
    String? country,
    String? sellerType,
  }) async =>
      _list(
        await client.get('/pets', query: {
          'status': status,
          'species': species,
          'city': city,
          'purpose': purpose,
          'guard_role': guardRole,
          'country': country,
          'seller_type': sellerType,
        }),
        Pet.fromJson,
      );

  Future<List<Pet>> myPets() async => _list(await client.get('/pets/my'), Pet.fromJson);

  Future<Pet> pet(String id) async => Pet.fromJson(await client.get('/pets/$id') as Json);

  Future<AdoptionRequest> requestAdoption(String petId, String message) async => AdoptionRequest.fromJson(
      await client.post('/pets/$petId/adoption-requests', body: {'message': message}) as Json);

  Future<AdoptionRequest?> myAdoptionRequest(String petId) async {
    final data = await client.get('/pets/$petId/my-adoption-request');
    return data is Json ? AdoptionRequest.fromJson(data) : null;
  }

  /// [role] is `incoming` (requests for my pets) or `sent` (my own requests).
  Future<List<AdoptionRequest>> adoptionRequests(String role) async =>
      _list(await client.get('/adoption-requests', query: {'role': role}), AdoptionRequest.fromJson);

  /// [action] is accept or decline (pet owner) or withdraw (requester).
  Future<AdoptionRequest> updateAdoptionRequest(String id, String action) async =>
      AdoptionRequest.fromJson(await client.put('/adoption-requests/$id', body: {'action': action}) as Json);

  Future<Pet> createPet(Json data) async => Pet.fromJson(await client.post('/pets', body: data) as Json);

  Future<Pet> updatePet(String id, Json data) async =>
      Pet.fromJson(await client.put('/pets/$id', body: data) as Json);

  /// Uploads an image and returns a media URL (absolute or `/uploads/...`).
  Future<String> uploadImage(String filePath) async {
    final data = await client.uploadFile('/uploads', filePath) as Json;
    final url = data['url']?.toString();
    if (url == null || url.isEmpty) {
      throw ApiException('upload_failed');
    }
    return url;
  }

  Future<void> deletePet(String id) => client.delete('/pets/$id');

  /// Toggles the like; returns whether the pet is now liked.
  Future<bool> likePet(String id) async => ((await client.post('/pets/$id/like')) as Json)['liked'] == true;

  Future<bool> isPetLiked(String id) async => ((await client.get('/pets/$id/like')) as Json)['liked'] == true;

  Future<List<Pet>> favoritePets() async => _list(await client.get('/favorites/pets'), Pet.fromJson);

  Future<bool> isProductFavorite(String id) async =>
      ((await client.get('/favorites/product/$id')) as Json)['is_favorite'] == true;

  Future<void> setProductFavorite(String id, bool favorite) =>
      favorite ? client.post('/favorites/product/$id') : client.delete('/favorites/product/$id');

  Future<List<Product>> favoriteProducts() async {
    final rows = await client.get('/favorites', query: {'item_type': 'product'}) as List;
    return [for (final row in rows) Product.fromJson((row as Json)['item'] as Json)];
  }

  Future<List<HealthRecord>> healthRecords(String petId) async =>
      _list(await client.get('/health-records/$petId'), HealthRecord.fromJson);

  Future<HealthRecord> createHealthRecord(Json data) async =>
      HealthRecord.fromJson(await client.post('/health-records', body: data) as Json);

  Future<void> deleteHealthRecord(String id) => client.delete('/health-records/$id');

  // ---------- lost & found ----------
  Future<List<LostFoundPost>> lostFound({String? type, String? city, String? q, String status = 'active'}) async =>
      _list(
        await client.get('/lost-found', query: {
          'type': type,
          'city': city,
          'q': q,
          'status': status,
        }),
        LostFoundPost.fromJson,
      );

  Future<LostFoundPost> lostFoundPost(String id) async =>
      LostFoundPost.fromJson(await client.get('/lost-found/$id') as Json);

  Future<LostFoundPost> createLostFound(Json data) async =>
      LostFoundPost.fromJson(await client.post('/lost-found', body: data) as Json);

  Future<void> resolveLostFound(String id) => client.put('/lost-found/$id/resolve');

  // ---------- shop ----------
  Future<List<Product>> products({String? category, String? petType}) async =>
      _list(await client.get('/products', query: {'category': category, 'pet_type': petType}), Product.fromJson);

  Future<Product> product(String id) async => Product.fromJson(await client.get('/products/$id') as Json);

  Future<Order> createOrder({
    required List<CartItem> items,
    required double total,
    required String address,
    required String city,
    required String phone,
    String paymentMethod = 'cash_on_delivery',
    String? notes,
  }) async =>
      Order.fromJson(await client.post('/orders', body: {
        'items': items.map((e) => e.toJson()).toList(),
        'total': total,
        'shipping_address': address,
        'shipping_city': city,
        'shipping_phone': phone,
        'payment_method': paymentMethod,
        if (notes != null && notes.isNotEmpty) 'notes': notes,
      }) as Json);

  Future<List<Order>> orders() async => _list(await client.get('/orders'), Order.fromJson);

  // ---------- vets & appointments ----------
  Future<List<Vet>> vets({String? q, String? city, String sort = 'top_rated'}) async =>
      _list(await client.get('/vets', query: {'q': q, 'city': city, 'sort': sort}), Vet.fromJson);

  Future<Vet> vet(String id) async => Vet.fromJson(await client.get('/vets/$id') as Json);

  // ---------- trainers ----------
  Future<List<Trainer>> trainers({
    String? q,
    String? city,
    String? country,
    String? category,
    String? petType,
    bool? international,
  }) async =>
      _list(
        await client.get('/trainers', query: {
          'q': q,
          'city': city,
          'country': country,
          'category': category,
          'pet_type': petType,
          if (international != null) 'international': international,
        }),
        Trainer.fromJson,
      );

  Future<Trainer> trainer(String id) async => Trainer.fromJson(await client.get('/trainers/$id') as Json);

  Future<Trainer> applyAsTrainer(Json data) async =>
      Trainer.fromJson(await client.post('/trainers', body: data) as Json);

  Future<Trainer?> myTrainerApplication() async {
    try {
      return Trainer.fromJson(await client.get('/trainers/me') as Json);
    } on ApiException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<List<Trainer>> adminTrainers({String? status}) async => _list(
        await client.get('/admin/trainers', query: {'status': status}),
        Trainer.fromJson,
      );

  Future<Trainer> reviewTrainer(String id, {required String action, String? notes}) async =>
      Trainer.fromJson(await client.put('/admin/trainers/$id', body: {
        'action': action,
        if (notes != null && notes.trim().isNotEmpty) 'verification_notes': notes.trim(),
      }) as Json);

  /// Taken slots as "yyyy-MM-dd HH:mm" keys.
  Future<Set<String>> bookedSlots(String vetId, {required String start, int days = 90}) async {
    final rows = await client.get('/vets/$vetId/booked-slots', query: {'start': start, 'days': days}) as List;
    return {for (final r in rows.cast<Json>()) '${r['date']} ${r['time']}'};
  }

  Future<Appointment> createAppointment(Json data) async =>
      Appointment.fromJson(await client.post('/appointments', body: data) as Json);

  Future<List<Appointment>> appointments() async => _list(await client.get('/appointments'), Appointment.fromJson);

  Future<Appointment> confirmAppointment(String id, {required String paymentMethod}) async =>
      Appointment.fromJson(await client.post('/appointments/$id/confirm', body: {
        'payment_method': paymentMethod,
      }) as Json);

  Future<void> cancelAppointment(String id) => client.put('/appointments/$id/cancel');

  Future<List<Appointment>> vetAppointments() async => _list(await client.get('/vet/appointments'), Appointment.fromJson);

  /// [action] is accept, decline or complete.
  Future<Appointment> updateVetAppointment(String id, String action) async =>
      Appointment.fromJson(await client.put('/vet/appointments/$id', body: {'action': action}) as Json);

  // ---------- users / community ----------
  Future<PublicUserProfile> publicUserProfile(String userId) async =>
      PublicUserProfile.fromJson(await client.get('/users/$userId/public') as Json);

  Future<List<CommunityPost>> communityPosts({String? type, String? userId}) async =>
      _list(
        await client.get('/community', query: {'type': type, 'user_id': userId}),
        CommunityPost.fromJson,
      );

  Future<CommunityPost> communityPost(String id) async =>
      CommunityPost.fromJson(await client.get('/community/post/$id') as Json);

  Future<void> createPost({required String type, required String title, required String content, String? image}) =>
      client.post('/community', body: {
        'type': type,
        'title': title,
        'content': content,
        if (image != null && image.isNotEmpty) 'image': image,
      });

  Future<void> likePost(String id) => client.post('/community/$id/like');

  Future<void> reportPost(String id, {String reason = 'inappropriate'}) =>
      client.post('/community/$id/report', body: {'reason': reason});

  Future<void> blockCommunityUser(String userId) =>
      client.post('/community/users/$userId/block');

  Future<void> unblockCommunityUser(String userId) =>
      client.delete('/community/users/$userId/block');

  Future<void> likeComment(String commentId) =>
      client.post('/community/comments/$commentId/like');

  Future<void> enablePostNotify(String postId) => client.post('/community/$postId/notify');

  Future<void> disablePostNotify(String postId) => client.delete('/community/$postId/notify');

  Future<List<String>> communityNotifySubscriptions() async {
    final data = await client.get('/community/notifications/subscriptions');
    if (data is! List) return const [];
    return data.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }

  // ---------- friends ----------
  Future<List<FriendUser>> friends() async => _list(await client.get('/friends'), FriendUser.fromJson);

  Future<FriendRequestsBundle> friendRequests() async =>
      FriendRequestsBundle.fromJson(await client.get('/friends/requests') as Json);

  Future<List<FriendUser>> searchFriends(String query) async =>
      _list(await client.get('/friends/search', query: {'q': query}), FriendUser.fromJson);

  Future<List<FriendUser>> friendSuggestions({int limit = 20}) async =>
      _list(await client.get('/friends/suggestions', query: {'limit': limit}), FriendUser.fromJson);

  Future<FriendUser> lookupFriendByCode(String code) async =>
      FriendUser.fromJson(await client.get('/friends/lookup', query: {'code': code}) as Json);

  Future<List<FriendActivityItem>> friendsActivity({double? lat, double? lng, double radiusKm = 25}) async =>
      _list(
        await client.get('/friends/activity', query: {
          'lat': lat,
          'lng': lng,
          'radius_km': radiusKm,
        }),
        FriendActivityItem.fromJson,
      );

  Future<String> sendFriendRequest(String userId, {String? message}) async {
    final data = await client.post('/friends/requests', body: {
      'target_user_id': userId,
      if (message != null && message.isNotEmpty) 'message': message,
    }) as Json;
    return data['status']?.toString() ?? 'pending';
  }

  Future<String> reviewFriendRequest(String requestId, {required String action}) async {
    final data = await client.put('/friends/requests/$requestId', body: {'action': action}) as Json;
    return data['status']?.toString() ?? action;
  }

  Future<void> cancelFriendRequest(String requestId) => client.delete('/friends/requests/$requestId');

  Future<void> unfriend(String userId) => client.delete('/friends/$userId');

  Future<void> blockFriend(String userId) => client.post('/friends/$userId/block');

  Future<void> unblockFriend(String userId) => client.delete('/friends/$userId/block');

  Future<List<FriendUser>> blockedFriends() async =>
      _list(await client.get('/friends/blocked'), FriendUser.fromJson);

  Future<List<Comment>> comments(String postId) async =>
      _list(await client.get('/community/$postId/comments'), Comment.fromJson);

  Future<void> addComment(String postId, String content, {String? parentCommentId}) =>
      client.post('/community/$postId/comments', body: {
        'content': content,
        if (parentCommentId != null && parentCommentId.isNotEmpty) 'parent_comment_id': parentCommentId,
      });

  // ---------- messaging ----------
  Future<List<Conversation>> conversations() async =>
      _list(await client.get('/conversations'), Conversation.fromJson);

  Future<String> startConversation({required String otherUserId, required String message, String? petId}) async {
    final data = await client.post('/conversations', body: {
      'other_user_id': otherUserId,
      'initial_message': message,
      'pet_id': ?petId,
    });
    return data['conversation_id'].toString();
  }

  /// The server returns either `{conversation, messages}` or a bare list.
  Future<(ChatUser?, List<ChatMessage>)> messages(String conversationId) async {
    final data = await client.get('/conversations/$conversationId/messages');
    if (data is List) return (null, _list(data, ChatMessage.fromJson));
    final other = (data['conversation'] as Json?)?['other_user'] as Json?;
    return (other == null ? null : ChatUser.fromJson(other), _list(data['messages'], ChatMessage.fromJson));
  }

  Future<ChatMessage> sendMessage(
    String conversationId, {
    String content = '',
    String? imageUrl,
    String? replyToMessageId,
  }) async =>
      ChatMessage.fromJson(
        await client.post(
          '/conversations/$conversationId/messages',
          query: {
            'content': content,
            if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
            if (replyToMessageId != null && replyToMessageId.isNotEmpty)
              'reply_to_message_id': replyToMessageId,
          },
        ) as Json,
      );

  Future<void> deleteMessage(String conversationId, String messageId) =>
      client.delete('/conversations/$conversationId/messages/$messageId');

  Future<void> deleteConversation(String conversationId) =>
      client.delete('/conversations/$conversationId');

  Future<void> registerDeviceToken({
    required String token,
    required String platform,
    String provider = 'local',
    String language = 'en',
  }) =>
      client.post('/devices/register', body: {
        'token': token,
        'platform': platform,
        'provider': provider,
        'language': language,
      });

  Future<void> unregisterDeviceToken(String token) =>
      client.post('/devices/unregister', body: {'token': token});

  Future<void> pushTest() => client.post('/notifications/push-test');

  // ---------- notifications ----------
  Future<List<AppNotification>> notifications({int limit = 50}) async {
    final data = await client.get('/notifications', query: {'limit': limit});
    return _list(data['items'], AppNotification.fromJson);
  }

  Future<int> unreadNotifications() async {
    final data = await client.get('/notifications/unread-count');
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  Future<(int, int, int)> inboxBadges() async {
    final data = await client.get('/inbox/badges') as Json;
    return (
      (data['notifications'] as num?)?.toInt() ?? 0,
      (data['friend_requests'] as num?)?.toInt() ?? 0,
      (data['messages'] as num?)?.toInt() ?? 0,
    );
  }

  Future<void> markNotificationRead(String id) => client.put('/notifications/$id/read');

  Future<void> markAllNotificationsRead() => client.put('/notifications/read-all');

  Future<void> clearNotifications() => client.delete('/notifications/clear-all');

  // ---------- user settings ----------
  Future<UserSettings> userSettings() async =>
      UserSettings.fromJson(await client.get('/user-settings') as Json);

  Future<UserSettings> updateUserSettings(Map<String, dynamic> patch) async =>
      UserSettings.fromJson(await client.put('/user-settings', body: patch) as Json);
}
