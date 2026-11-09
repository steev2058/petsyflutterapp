import 'package:intl/intl.dart';

typedef Json = Map<String, dynamic>;

String? _str(dynamic v) => v?.toString();
double _double(dynamic v, {double fallback = 0}) =>
    v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? fallback;
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
bool _bool(dynamic v) => v == true;
DateTime? _date(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  // FastAPI serializes naive UTC datetimes without an offset.
  final hasZone = s.endsWith('Z') || RegExp(r'[+-]\d\d:\d\d$').hasMatch(s);
  return DateTime.tryParse(hasZone ? s : '${s}Z')?.toLocal();
}

class User {
  User({
    required this.id,
    required this.email,
    required this.name,
    this.username,
    this.userCode,
    this.phone,
    this.city,
    this.bio,
    this.avatar,
    this.language = 'ar',
    this.isVerified = false,
    this.isAdmin = false,
    this.role = 'user',
  });

  factory User.fromJson(Json j) => User(
        id: j['id'].toString(),
        email: _str(j['email']) ?? '',
        name: _str(j['name']) ?? '',
        username: _str(j['username']),
        userCode: _str(j['user_code']),
        phone: _str(j['phone']),
        city: _str(j['city']),
        bio: _str(j['bio']),
        avatar: _str(j['avatar']),
        language: _str(j['language']) ?? 'ar',
        isVerified: _bool(j['is_verified']),
        isAdmin: _bool(j['is_admin']),
        role: _str(j['role']) ?? 'user',
      );

  final String id;
  final String email;
  final String name;
  final String? username;
  final String? userCode;
  final String? phone;
  final String? city;
  final String? bio;
  final String? avatar;
  final String language;
  final bool isVerified;
  final bool isAdmin;
  final String role;

  Json toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'username': username,
        'user_code': userCode,
        'phone': phone,
        'city': city,
        'bio': bio,
        'avatar': avatar,
        'language': language,
        'is_verified': isVerified,
        'is_admin': isAdmin,
        'role': role,
      };
}

class Pet {
  Pet({
    required this.id,
    required this.name,
    required this.species,
    required this.gender,
    required this.ownerId,
    this.breed,
    this.age,
    this.color,
    this.weight,
    this.description,
    this.image,
    this.status = 'owned',
    this.purpose,
    this.guardRole,
    this.country,
    this.sellerType,
    this.price,
    this.currency,
    this.location,
    this.vaccinated = false,
    this.neutered = false,
    this.likes = 0,
  });

  factory Pet.fromJson(Json j) => Pet(
        id: j['id'].toString(),
        name: _str(j['name']) ?? '',
        species: _str(j['species']) ?? 'other',
        gender: _str(j['gender']) ?? 'male',
        ownerId: _str(j['owner_id']) ?? '',
        breed: _str(j['breed']),
        age: _str(j['age']),
        color: _str(j['color']),
        weight: j['weight'] == null ? null : _double(j['weight']),
        description: _str(j['description']),
        image: _str(j['image']),
        status: _str(j['status']) ?? 'owned',
        purpose: _str(j['purpose']),
        guardRole: _str(j['guard_role']),
        country: _str(j['country']),
        sellerType: _str(j['seller_type']),
        price: j['price'] == null ? null : _double(j['price']),
        currency: _str(j['currency']),
        location: _str(j['location']),
        vaccinated: _bool(j['vaccinated']),
        neutered: _bool(j['neutered']),
        likes: _int(j['likes']),
      );

  final String id;
  final String name;
  final String species;
  final String gender;
  final String ownerId;
  final String? breed;
  final String? age;
  final String? color;
  final double? weight;
  final String? description;
  final String? image;
  final String status;
  final String? purpose;
  final String? guardRole;
  final String? country;
  final String? sellerType;
  final double? price;
  final String? currency;
  final String? location;
  final bool vaccinated;
  final bool neutered;
  final int likes;

  bool get isGuardDog => purpose == 'guard';
}

class Trainer {
  Trainer({
    required this.id,
    required this.name,
    this.userId,
    this.title,
    this.categories = const [],
    this.petTypes = const [],
    this.experienceYears = 0,
    this.phone,
    this.city,
    this.country,
    this.location,
    this.bio,
    this.image,
    this.languages = const [],
    this.priceFrom,
    this.currency,
    this.servesInternational = false,
    this.rating = 0,
    this.ratingCount = 0,
    this.status = 'active',
    this.verified = true,
    this.isPublic = true,
    this.verificationNotes,
  });

  factory Trainer.fromJson(Json j) => Trainer(
        id: j['id'].toString(),
        userId: _str(j['user_id']),
        name: _str(j['name']) ?? '',
        title: _str(j['title']),
        categories: ((j['categories'] as List?) ?? const []).map((e) => e.toString()).toList(),
        petTypes: ((j['pet_types'] as List?) ?? const []).map((e) => e.toString()).toList(),
        experienceYears: _int(j['experience_years']),
        phone: _str(j['phone']),
        city: _str(j['city']),
        country: _str(j['country']),
        location: _str(j['location_text']),
        bio: _str(j['bio']),
        image: _str(j['image_url'] ?? j['image']),
        languages: ((j['languages'] as List?) ?? const []).map((e) => e.toString()).toList(),
        priceFrom: j['price_from'] == null ? null : _double(j['price_from']),
        currency: _str(j['currency']),
        servesInternational: _bool(j['serves_international']),
        rating: _double(j['rating_avg'] ?? j['rating']),
        ratingCount: _int(j['rating_count']),
        status: _str(j['status']) ?? 'active',
        verified: j['verified'] != false,
        isPublic: j['is_public'] != false,
        verificationNotes: _str(j['verification_notes']),
      );

  final String id;
  final String? userId;
  final String name;
  final String? title;
  final List<String> categories;
  final List<String> petTypes;
  final int experienceYears;
  final String? phone;
  final String? city;
  final String? country;
  final String? location;
  final String? bio;
  final String? image;
  final List<String> languages;
  final double? priceFrom;
  final String? currency;
  final bool servesInternational;
  final double rating;
  final int ratingCount;
  final String status;
  final bool verified;
  final bool isPublic;
  final String? verificationNotes;

  bool get isPending => status == 'pending_verification';
  bool get isRejected => status == 'rejected';
  bool get isApproved => status == 'active' && verified;
}

class Product {
  Product({
    required this.id,
    required this.name,
    required this.category,
    required this.price,
    required this.petType,
    this.description,
    this.originalPrice,
    this.image,
    this.brand,
    this.inStock = true,
    this.rating = 0,
  });

  factory Product.fromJson(Json j) => Product(
        id: j['id'].toString(),
        name: _str(j['name']) ?? '',
        category: _str(j['category']) ?? '',
        price: _double(j['price']),
        petType: _str(j['pet_type']) ?? 'all',
        description: _str(j['description']),
        originalPrice: j['original_price'] == null ? null : _double(j['original_price']),
        image: _str(j['image']),
        brand: _str(j['brand']),
        inStock: j['in_stock'] != false,
        rating: _double(j['rating']),
      );

  final String id;
  final String name;
  final String category;
  final double price;
  final String petType;
  final String? description;
  final double? originalPrice;
  final String? image;
  final String? brand;
  final bool inStock;
  final double rating;
}

/// Backs both `vet_profiles` rows and the legacy `vets` collection, which use different keys.
class Vet {
  Vet({
    required this.id,
    required this.name,
    this.userId,
    this.specialty = '',
    this.experienceYears = 0,
    this.phone,
    this.city,
    this.location,
    this.clinicName,
    this.bio,
    this.image,
    this.rating = 0,
    this.ratingCount = 0,
    this.services = const [],
  });

  factory Vet.fromJson(Json j) => Vet(
        id: j['id'].toString(),
        userId: _str(j['user_id']),
        name: _str(j['name']) ?? '',
        specialty: _str(j['specialty']) ?? '',
        experienceYears: _int(j['experience_years'] ?? j['experience']),
        phone: _str(j['phone']),
        city: _str(j['city']),
        location: _str(j['location_text'] ?? j['address']),
        clinicName: _str(j['clinic_name']),
        bio: _str(j['bio']),
        image: _str(j['image_url'] ?? j['image']),
        rating: _double(j['rating_avg'] ?? j['rating']),
        ratingCount: _int(j['rating_count'] ?? j['reviews_count']),
        services: ((j['services'] ?? j['specialties']) as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  final String id;
  final String? userId;
  final String name;
  final String specialty;
  final int experienceYears;
  final String? phone;
  final String? city;
  final String? location;
  final String? clinicName;
  final String? bio;
  final String? image;
  final double rating;
  final int ratingCount;
  final List<String> services;
}

class LostFoundPost {
  LostFoundPost({
    required this.id,
    required this.userId,
    required this.type,
    required this.petSpecies,
    required this.description,
    required this.lastSeenLocation,
    required this.lastSeenDate,
    required this.contactPhone,
    required this.status,
    this.breed,
    this.color,
    this.image,
    this.lat,
    this.lng,
    this.createdAt,
  });

  factory LostFoundPost.fromJson(Json j) => LostFoundPost(
        id: j['id'].toString(),
        userId: _str(j['user_id']) ?? '',
        type: _str(j['type']) ?? 'lost',
        petSpecies: _str(j['pet_species']) ?? 'other',
        breed: _str(j['breed']),
        color: _str(j['color']),
        description: _str(j['description']) ?? '',
        lastSeenLocation: _str(j['last_seen_location']) ?? '',
        lastSeenDate: _str(j['last_seen_date']) ?? '',
        contactPhone: _str(j['contact_phone']) ?? '',
        image: _str(j['image']),
        lat: j['lat'] == null ? null : _double(j['lat']),
        lng: j['lng'] == null ? null : _double(j['lng']),
        status: _str(j['status']) ?? 'active',
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String userId;
  final String type;
  final String petSpecies;
  final String? breed;
  final String? color;
  final String description;
  final String lastSeenLocation;
  final String lastSeenDate;
  final String contactPhone;
  final String? image;
  final double? lat;
  final double? lng;
  final String status;
  final DateTime? createdAt;

  bool get isLost => type == 'lost';
  bool get hasCoords => lat != null && lng != null;
}

class HealthRecord {
  HealthRecord({
    required this.id,
    required this.petId,
    required this.recordType,
    required this.title,
    required this.date,
    this.description,
    this.vetName,
    this.notes,
    this.appointmentId,
  });

  factory HealthRecord.fromJson(Json j) => HealthRecord(
        id: j['id'].toString(),
        petId: _str(j['pet_id']) ?? '',
        recordType: _str(j['record_type']) ?? 'other',
        title: _str(j['title']) ?? '',
        date: _str(j['date']) ?? '',
        description: _str(j['description']),
        vetName: _str(j['vet_name']),
        notes: _str(j['notes']),
        appointmentId: _str(j['appointment_id']),
      );

  final String id;
  final String petId;
  final String recordType;
  final String title;
  final String date;
  final String? description;
  final String? vetName;
  final String? notes;
  final String? appointmentId;
}

class Appointment {
  Appointment({
    required this.id,
    required this.vetId,
    required this.date,
    required this.time,
    required this.reason,
    required this.status,
    this.petId,
    this.notes,
    this.fee = 0,
    this.paymentMethod,
    this.paymentStatus = 'unpaid',
    this.paymentId,
    this.ownerName,
    this.petName,
    this.petSpecies,
  });

  factory Appointment.fromJson(Json j) => Appointment(
        id: j['id'].toString(),
        vetId: _str(j['vet_id']) ?? '',
        petId: _str(j['pet_id']),
        date: _str(j['date']) ?? '',
        time: _str(j['time']) ?? '',
        reason: _str(j['reason']) ?? '',
        status: _str(j['status']) ?? 'pending',
        notes: _str(j['notes']),
        fee: _double(j['fee']),
        paymentMethod: _str(j['payment_method']),
        paymentStatus: _str(j['payment_status']) ?? 'unpaid',
        paymentId: _str(j['payment_id']),
        ownerName: _str(j['owner_name']),
        petName: _str(j['pet_name']),
        petSpecies: _str(j['pet_species']),
      );

  final String id;
  final String vetId;
  final String? petId;
  final String date;
  final String time;
  final String reason;
  final String status;
  final String? notes;
  final double fee;
  final String? paymentMethod;
  final String paymentStatus;
  final String? paymentId;

  /// Only set on the vet's clinic list.
  final String? ownerName;
  final String? petName;
  final String? petSpecies;

  bool get needsPaymentConfirm => (status == 'pending' || status == 'confirmed') && paymentStatus == 'unpaid';

  /// "Nov 9, 2026 · 09:00" in [languageCode]; the raw ISO date reads backwards in RTL text.
  String when(String languageCode) => appointmentWhen(date, time, languageCode);
}

/// Pet ages are stored as `"N years"` / `"N months"`. Older free-text values
/// ("2 years", "6 mo", "5", "3 سنوات") are parsed when they follow that shape.
class PetAge {
  const PetAge(this.value, {required this.months});

  final num value;
  final bool months;

  static final _pattern = RegExp(
    r'^(\d+(?:[.,]\d+)?)\s*(years?|yrs?|y|months?|mos?|m|سنة|سنه|سنوات|سنين|عام|أعوام|شهر|شهور|أشهر|اشهر)?$',
  );

  static PetAge? parse(String? raw) {
    final match = _pattern.firstMatch(raw?.trim().toLowerCase() ?? '');
    if (match == null) return null;
    final value = num.parse(match.group(1)!.replaceAll(',', '.'));
    final unit = match.group(2) ?? '';
    return PetAge(value, months: unit.startsWith('m') || unit.contains('شهر') || unit == 'شهور');
  }

  /// The canonical text saved to the backend.
  String get number => value == value.roundToDouble() ? '${value.toInt()}' : '$value';

  String get stored {
    final unit = months ? 'month' : 'year';
    return value == 1 ? '$number $unit' : '$number ${unit}s';
  }
}

class AdoptionRequest {
  AdoptionRequest({
    required this.id,
    required this.petId,
    required this.ownerId,
    required this.requesterId,
    required this.message,
    required this.status,
    this.closedReason,
    this.createdAt,
    this.petName,
    this.petSpecies,
    this.petImage,
    this.petStatus,
    this.ownerName,
    this.requesterName,
    this.requesterCity,
  });

  factory AdoptionRequest.fromJson(Json j) => AdoptionRequest(
        id: j['id'].toString(),
        petId: _str(j['pet_id']) ?? '',
        ownerId: _str(j['owner_id']) ?? '',
        requesterId: _str(j['requester_id']) ?? '',
        message: _str(j['message']) ?? '',
        status: _str(j['status']) ?? 'pending',
        closedReason: _str(j['closed_reason']),
        createdAt: _date(j['created_at']),
        petName: _str(j['pet_name']),
        petSpecies: _str(j['pet_species']),
        petImage: _str(j['pet_image']),
        petStatus: _str(j['pet_status']),
        ownerName: _str(j['owner_name']),
        requesterName: _str(j['requester_name']),
        requesterCity: _str(j['requester_city']),
      );

  final String id;
  final String petId;
  final String ownerId;
  final String requesterId;
  final String message;

  /// pending, accepted, declined or withdrawn.
  final String status;

  /// `adopted` when the request was closed because another request was accepted.
  final String? closedReason;
  final DateTime? createdAt;
  final String? petName;
  final String? petSpecies;
  final String? petImage;
  final String? petStatus;
  final String? ownerName;
  final String? requesterName;
  final String? requesterCity;

  bool get isPending => status == 'pending';
}

String appointmentWhen(String date, String time, String languageCode) {
  final day = DateTime.tryParse(date);
  final dateText = day == null ? date : DateFormat.yMMMd(languageCode).format(day);
  return '$dateText · \u2066$time\u2069'.replaceAll(' ', '\u00A0');
}

class PublicUserProfile {
  PublicUserProfile({
    required this.id,
    required this.name,
    this.username,
    this.userCode,
    this.city,
    this.bio,
    this.avatar,
    this.role = 'user',
    this.isVerified = false,
    this.postsCount = 0,
    this.friendsCount = 0,
    this.mutualCount = 0,
    this.isBlocked = false,
    this.isSelf = false,
    this.friendshipStatus = 'none',
    this.incomingRequestId,
    this.createdAt,
  });

  factory PublicUserProfile.fromJson(Json j) => PublicUserProfile(
        id: j['id'].toString(),
        name: _str(j['name']) ?? '',
        username: _str(j['username']),
        userCode: _str(j['user_code']),
        city: _str(j['city']),
        bio: _str(j['bio']),
        avatar: _str(j['avatar']),
        role: _str(j['role']) ?? 'user',
        isVerified: _bool(j['is_verified']),
        postsCount: _int(j['posts_count']),
        friendsCount: _int(j['friends_count']),
        mutualCount: _int(j['mutual_count']),
        isBlocked: _bool(j['is_blocked']),
        isSelf: _bool(j['is_self']),
        friendshipStatus: _str(j['friendship_status']) ?? 'none',
        incomingRequestId: _str(j['incoming_request_id']),
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String name;
  final String? username;
  final String? userCode;
  final String? city;
  final String? bio;
  final String? avatar;
  final String role;
  final bool isVerified;
  final int postsCount;
  final int friendsCount;
  final int mutualCount;
  final bool isBlocked;
  final bool isSelf;
  final String friendshipStatus;
  final String? incomingRequestId;
  final DateTime? createdAt;
}

class FriendUser {
  FriendUser({
    required this.id,
    required this.name,
    this.avatar,
    this.username,
    this.userCode,
    this.city,
    this.isOnline = false,
    this.mutualCount = 0,
    this.friendshipStatus = 'none',
    this.suggestionReason,
  });

  factory FriendUser.fromJson(Json j) => FriendUser(
        id: j['id'].toString(),
        name: _str(j['name']) ?? '',
        avatar: _str(j['avatar']),
        username: _str(j['username']),
        userCode: _str(j['user_code']),
        city: _str(j['city']),
        isOnline: _bool(j['is_online']),
        mutualCount: _int(j['mutual_count']),
        friendshipStatus: _str(j['friendship_status']) ?? 'none',
        suggestionReason: _str(j['suggestion_reason']),
      );

  final String id;
  final String name;
  final String? avatar;
  final String? username;
  final String? userCode;
  final String? city;
  final bool isOnline;
  final int mutualCount;
  final String friendshipStatus;
  final String? suggestionReason;
}

class FriendRequestItem {
  FriendRequestItem({
    required this.id,
    required this.user,
    this.message,
    this.createdAt,
  });

  factory FriendRequestItem.fromJson(Json j) => FriendRequestItem(
        id: j['id'].toString(),
        user: FriendUser.fromJson((j['user'] as Json?) ?? const {}),
        message: _str(j['message']),
        createdAt: _date(j['created_at']),
      );

  final String id;
  final FriendUser user;
  final String? message;
  final DateTime? createdAt;
}

class FriendRequestsBundle {
  FriendRequestsBundle({required this.incoming, required this.outgoing});

  factory FriendRequestsBundle.fromJson(Json j) => FriendRequestsBundle(
        incoming: (j['incoming'] as List? ?? const [])
            .map((e) => FriendRequestItem.fromJson(e as Json))
            .toList(),
        outgoing: (j['outgoing'] as List? ?? const [])
            .map((e) => FriendRequestItem.fromJson(e as Json))
            .toList(),
      );

  final List<FriendRequestItem> incoming;
  final List<FriendRequestItem> outgoing;
}

class FriendActivityItem {
  FriendActivityItem({
    required this.kind,
    required this.user,
    this.createdAt,
    this.nearbyKm,
    this.isNearby = false,
    this.community,
    this.lostFound,
  });

  factory FriendActivityItem.fromJson(Json j) => FriendActivityItem(
        kind: _str(j['kind']) ?? 'community',
        user: FriendUser.fromJson((j['user'] as Json?) ?? const {}),
        createdAt: _date(j['created_at']),
        nearbyKm: j['nearby_km'] == null ? null : _double(j['nearby_km']),
        isNearby: _bool(j['is_nearby']),
        community: j['community'] is Map ? CommunityPost.fromJson(j['community'] as Json) : null,
        lostFound: j['lost_found'] is Map ? LostFoundPost.fromJson(j['lost_found'] as Json) : null,
      );

  final String kind;
  final FriendUser user;
  final DateTime? createdAt;
  final double? nearbyKm;
  final bool isNearby;
  final CommunityPost? community;
  final LostFoundPost? lostFound;

  bool get isCommunity => kind == 'community';
  bool get isLostFound => kind == 'lost_found';
}

class CommunityPost {
  CommunityPost({
    required this.id,
    required this.userId,
    required this.userName,
    required this.type,
    required this.title,
    required this.content,
    this.userAvatar,
    this.image,
    this.likes = 0,
    this.commentsCount = 0,
    this.createdAt,
  });

  factory CommunityPost.fromJson(Json j) => CommunityPost(
        id: j['id'].toString(),
        userId: _str(j['user_id']) ?? '',
        userName: _str(j['user_name']) ?? '',
        userAvatar: _str(j['user_avatar']),
        type: _str(j['type']) ?? 'story',
        title: _str(j['title']) ?? '',
        content: _str(j['content']) ?? '',
        image: _str(j['image']),
        likes: _int(j['likes']),
        commentsCount: _int(j['comments_count']),
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String userId;
  final String userName;
  final String? userAvatar;
  final String type;
  final String title;
  final String content;
  final String? image;
  final int likes;
  final int commentsCount;
  final DateTime? createdAt;
}

class Comment {
  Comment({
    required this.id,
    required this.userName,
    required this.content,
    this.userId,
    this.userAvatar,
    this.likes = 0,
    this.parentCommentId,
    this.createdAt,
  });

  factory Comment.fromJson(Json j) => Comment(
        id: j['id'].toString(),
        userId: _str(j['user_id']),
        userName: _str(j['user_name']) ?? '',
        userAvatar: _str(j['user_avatar']),
        content: _str(j['content']) ?? '',
        likes: _int(j['likes']),
        parentCommentId: _str(j['parent_comment_id']),
        createdAt: _date(j['created_at']),
      );

  final String id;
  final String? userId;
  final String userName;
  final String? userAvatar;
  final String content;
  final int likes;
  final String? parentCommentId;
  final DateTime? createdAt;
}

class ChatUser {
  ChatUser({this.id, required this.name, this.avatar, this.isOnline = false});

  factory ChatUser.fromJson(Json? j) => ChatUser(
        id: _str(j?['id']),
        name: _str(j?['name']) ?? '',
        avatar: _str(j?['avatar']),
        isOnline: _bool(j?['is_online']),
      );

  final String? id;
  final String name;
  final String? avatar;
  final bool isOnline;

  ChatUser copyWith({String? id, String? name, String? avatar, bool? isOnline}) => ChatUser(
        id: id ?? this.id,
        name: name ?? this.name,
        avatar: avatar ?? this.avatar,
        isOnline: isOnline ?? this.isOnline,
      );
}

class UserSettings {
  UserSettings({
    this.pushNotifications = true,
    this.chatSound = true,
    this.chatPreview = true,
    this.allowDirectMessages = 'everyone',
    this.allowFriendRequests = 'everyone',
    this.mutedConversationIds = const [],
  });

  factory UserSettings.fromJson(Json j) {
    final mutedRaw = j['muted_conversation_ids'];
    final muted = mutedRaw is List
        ? mutedRaw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
        : <String>[];
    return UserSettings(
      pushNotifications: j['push_notifications'] == false ? false : true,
      chatSound: j['chat_sound'] == false ? false : true,
      chatPreview: j['chat_preview'] == false ? false : true,
      allowDirectMessages: _str(j['allow_direct_messages']) ?? 'everyone',
      allowFriendRequests: _str(j['allow_friend_requests']) ?? 'everyone',
      mutedConversationIds: muted,
    );
  }

  final bool pushNotifications;
  final bool chatSound;
  final bool chatPreview;
  final String allowDirectMessages;
  final String allowFriendRequests;
  final List<String> mutedConversationIds;
}

class Conversation {
  Conversation({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.lastMessageSenderId,
    this.lastMessageRead = false,
  });

  factory Conversation.fromJson(Json j) => Conversation(
        id: j['id'].toString(),
        otherUser: ChatUser.fromJson(j['other_user'] as Json?),
        lastMessage: _str(j['last_message']),
        lastMessageTime: _date(j['last_message_time']),
        unreadCount: _int(j['unread_count']),
        lastMessageSenderId: _str(j['last_message_sender_id']),
        lastMessageRead: _bool(j['last_message_is_read']),
      );

  final String id;
  final ChatUser otherUser;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final String? lastMessageSenderId;
  final bool lastMessageRead;
}

class ChatMessage {
  ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    this.imageUrl,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderId,
    this.createdAt,
    this.isRead = false,
  });

  factory ChatMessage.fromJson(Json j) => ChatMessage(
        id: j['id'].toString(),
        senderId: _str(j['sender_id']) ?? '',
        content: _str(j['content']) ?? '',
        imageUrl: _str(j['image_url']),
        replyToMessageId: _str(j['reply_to_message_id']),
        replyToContent: _str(j['reply_to_content']),
        replyToSenderId: _str(j['reply_to_sender_id']),
        createdAt: _date(j['created_at']),
        isRead: _bool(j['is_read']),
      );

  final String id;
  final String senderId;
  final String content;
  final String? imageUrl;
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToSenderId;
  final DateTime? createdAt;
  final bool isRead;

  bool get hasImage => imageUrl != null && imageUrl!.trim().isNotEmpty;
  bool get isReply => replyToMessageId != null && replyToMessageId!.isNotEmpty;
}

class AppNotification {
  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    this.createdAt,
    this.data = const {},
  });

  factory AppNotification.fromJson(Json j) {
    final rawData = j['data'];
    return AppNotification(
      id: j['id'].toString(),
      title: _str(j['title']) ?? '',
      body: _str(j['body'] ?? j['message']) ?? '',
      type: _str(j['type']) ?? '',
      isRead: _bool(j['is_read']),
      createdAt: _date(j['created_at']),
      data: rawData is Map ? Map<String, dynamic>.from(rawData) : const {},
    );
  }

  final String id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime? createdAt;
  final Map<String, dynamic> data;

  String? get conversationId => _str(data['conversation_id']);
  String? get postId => _str(data['post_id']);
  String? get route => _str(data['route']);
  String? get requestId => _str(data['request_id']);
  String? get status => _str(data['status']);
  String? get fromUserName => _str(data['from_user_name']);
  String? get fromUserId => _str(data['from_user_id']);
  String? get action => _str(data['action']);
}

class CartItem {
  CartItem({required this.productId, required this.name, required this.price, this.image, this.quantity = 1});

  factory CartItem.fromJson(Json j) => CartItem(
        productId: j['product_id'].toString(),
        name: _str(j['name']) ?? '',
        price: _double(j['price']),
        image: _str(j['image']),
        quantity: _int(j['quantity']),
      );

  final String productId;
  final String name;
  final double price;
  final String? image;
  int quantity;

  Json toJson() => {
        'product_id': productId,
        'name': name,
        'price': price,
        'image': image,
        'quantity': quantity,
      };
}

class Order {
  Order({
    required this.id,
    required this.items,
    required this.total,
    required this.status,
    required this.shippingCity,
    this.createdAt,
  });

  factory Order.fromJson(Json j) => Order(
        id: j['id'].toString(),
        items: (j['items'] as List? ?? []).map((e) => CartItem.fromJson(e as Json)).toList(),
        total: _double(j['total']),
        status: _str(j['status']) ?? 'pending',
        shippingCity: _str(j['shipping_city']) ?? '',
        createdAt: _date(j['created_at']),
      );

  final String id;
  final List<CartItem> items;
  final double total;
  final String status;
  final String shippingCity;
  final DateTime? createdAt;
}
