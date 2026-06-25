// ─────────────────────────────────────────────────────────────────────────────
// Shared models for the Rental App
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math' as math;

/// Geo helper: great-circle distance + "nearest first" sorting used by the
/// homepage "Recommended for you" section and the search results page.
class GeoUtils {
  /// Distance in kilometres between two lat/lng points (Haversine formula).
  static double distanceKm(
      double lat1, double lng1, double lat2, double lng2) {
    const earthRadiusKm = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }

  static double _toRad(double deg) => deg * (math.pi / 180.0);

  /// Sorts [products] by distance from [fromLat]/[fromLng], nearest first.
  /// Products without coordinates are pushed to the end (in their original
  /// relative order). If [fromLat]/[fromLng] is null, the list is returned
  /// unchanged (no location to sort by).
  static List<Product> sortByDistance(
      List<Product> products, double? fromLat, double? fromLng) {
    if (fromLat == null || fromLng == null) return List<Product>.from(products);

    final withDistance = <MapEntry<Product, double?>>[];
    for (final p in products) {
      withDistance.add(MapEntry(p, p.distanceFrom(fromLat, fromLng)));
    }

    // Stable sort: items with a distance come first (ascending), items
    // without coordinates keep their relative order at the end.
    withDistance.sort((a, b) {
      final da = a.value;
      final db = b.value;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return withDistance.map((e) => e.key).toList();
  }
}

class Product {
  final String id;
  final String name;
  final String imageUrl;      // cover image (legacy / fallback)
  final List<String> images;  // all images; first is cover if not empty
  final double price;
  final double originalPrice;
  final bool freeDelivery;
  final double coinsSaved;
  final double coinsSave;
  final String location;
  final String? description;
  final String? category;
  final String? listingType; // 'rent' | 'buy'
  final String? ownerId;
  final String? ownerName;
  final String? ownerAvatar;
  final bool ownerIsAdmin; // true when the listing owner's profile has is_admin = true
  final double? latitude;
  final double? longitude;
  final String? status;
  final DateTime? rentalEndDate;

  Product({
    required this.id,
    required this.name,
    required this.imageUrl,
    this.images = const [],
    required this.price,
    required this.originalPrice,
    this.freeDelivery = false,
    this.coinsSaved = 0.0,
    this.coinsSave = 0.0,
    required this.location,
    this.description,
    this.category,
    this.listingType,
    this.ownerId,
    this.ownerName,
    this.ownerAvatar,
    this.ownerIsAdmin = false,
    this.latitude,
    this.longitude,
    this.status,
    this.rentalEndDate,
  });

  // ── Image URL helpers ──────────────────────────────────────────────────────

  /// Returns true only for non-empty strings that look like real URLs.
  static bool _isValidUrl(String? url) =>
      url != null && url.isNotEmpty && url.startsWith('http');

  /// The cover image to display in cards and as the first slideshow image.
  /// Prefers the first entry of [images] (product_images join), then falls back
  /// to [imageUrl] (products.image_url column). Returns empty string if neither
  /// is available so widgets can show their own placeholder.
  String get coverImage {
    // Try the first image from the product_images join (already sorted cover-first)
    for (final img in images) {
      if (_isValidUrl(img)) return img;
    }
    // Fall back to the denormalised image_url column on products
    if (_isValidUrl(imageUrl)) return imageUrl;
    return '';
  }

  /// All images to show in slideshow, filtering out any blank/invalid URLs.
  /// Falls back to [imageUrl] when the product_images join returned nothing.
  List<String> get allImages {
    final valid = images.where(_isValidUrl).toList();
    if (valid.isNotEmpty) return valid;
    if (_isValidUrl(imageUrl)) return [imageUrl];
    return [];
  }

  int get discountPercent =>
      originalPrice > 0
          ? ((originalPrice - price) / originalPrice * 100).round()
          : 0;

  /// Truncated location for compact card display (max 25 chars)
  String get shortLocation {
    const int maxLen = 25;
    if (location.length <= maxLen) return location;
    return '${location.substring(0, maxLen)}...';
  }

  /// Whether this product has usable coordinates for distance sorting.
  bool get hasCoords =>
      latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0;

  /// Distance in kilometres from the given coordinates, or null if this
  /// product (or the given coordinates) has no usable location.
  double? distanceFrom(double? fromLat, double? fromLng) {
    if (!hasCoords || fromLat == null || fromLng == null) return null;
    return GeoUtils.distanceKm(fromLat, fromLng, latitude!, longitude!);
  }

  factory Product.fromMap(Map<String, dynamic> map) {
    final profile = map['profiles'] as Map<String, dynamic>?;

    // Build image list from product_images join (if present)
    List<String> imgs = [];
    final rawImgs = map['product_images'];
    if (rawImgs is List) {
      // Sort by is_cover desc then sort_order asc so cover is always first
      final sorted = List<Map<String, dynamic>>.from(rawImgs)
        ..sort((a, b) {
          final aCover = (a['is_cover'] == true) ? 0 : 1;
          final bCover = (b['is_cover'] == true) ? 0 : 1;
          if (aCover != bCover) return aCover.compareTo(bCover);
          return ((a['sort_order'] as num?) ?? 0)
              .compareTo((b['sort_order'] as num?) ?? 0);
        });
      imgs = sorted
          .map((m) => (m['image_url'] as String?) ?? '')
          .where((u) => u.isNotEmpty)
          .toList();
    }

    return Product(
      id: map['id']?.toString() ?? '',
      name: map['name'] ?? '',
      imageUrl: map['image_url'] ?? '',
      images: imgs,
      price: (map['price'] as num?)?.toDouble() ?? 0.0,
      originalPrice: (map['original_price'] as num?)?.toDouble() ?? 0.0,
      freeDelivery: map['free_delivery'] ?? false,
      coinsSaved: (map['coins_saved'] as num?)?.toDouble() ?? 0.0,
      coinsSave: (map['coins_save'] as num?)?.toDouble() ?? 0.0,
      location: map['location'] ?? '',
      description: map['description'],
      category: map['category'],
      listingType: map['listing_type'],
      ownerId: map['owner_id'],
      ownerName: profile?['full_name'],
      ownerAvatar: profile?['avatar_url'],
      ownerIsAdmin: profile?['is_admin'] == true,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      status: map['status'],
      rentalEndDate: map['rental_end_date'] != null
          ? DateTime.parse(map['rental_end_date'])
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'image_url': imageUrl,
    'price': price,
    'original_price': originalPrice,
    'free_delivery': freeDelivery,
    'coins_saved': coinsSaved,
    'coins_save': coinsSave,
    'location': location,
    'description': description,
    'category': category,
    'listing_type': listingType,
    'owner_id': ownerId,
    'latitude': latitude,
    'longitude': longitude,
    'status': status,
    'rental_end_date': rentalEndDate?.toIso8601String(),
  };
}

class CartItem {
  final String id;
  final String productId;
  final String? ownerId;   // product owner (for notifications)
  final String name;
  final String imageUrl;
  final double price;
  final bool isRental;    // true = listing_type is 'rent'
  int rentalDays;         // used when isRental == true  (min 1)
  final bool freeDelivery;

  CartItem({
    required this.id,
    required this.productId,
    this.ownerId,
    required this.name,
    required this.imageUrl,
    required this.price,
    this.isRental = false,
    this.rentalDays = 1,
    this.freeDelivery = false,
  });

  /// Total price: for rentals = price * days; for sales = price (single unit)
  double get totalPrice => isRental ? price * rentalDays : price;

  factory CartItem.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map<String, dynamic>? ?? {};
    final listingType = product['listing_type'] as String?;
    final isRental = listingType == 'rent';
    return CartItem(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      ownerId: product['owner_id']?.toString(),
      name: product['name'] ?? '',
      imageUrl: product['image_url'] ?? '',
      price: (product['price'] as num?)?.toDouble() ?? 0.0,
      isRental: isRental,
      rentalDays: isRental
          ? ((map['rental_days'] as num?)?.toInt() ?? 1).clamp(1, 365)
          : 1,
      freeDelivery: product['free_delivery'] ?? false,
    );
  }
}

class AppUser {
  final String id;
  final String email;
  final String fullName;
  final String? avatarUrl;
  final double walletBalance;
  final int rewardPoints;
  final String? address;
  final double? latitude;
  final double? longitude;

  AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    this.avatarUrl,
    this.walletBalance = 0.0,
    this.rewardPoints = 0,
    this.address,
    this.latitude,
    this.longitude,
  });

  /// Whether the user has set a saved address/location.
  bool get hasAddress => address != null && address!.trim().isNotEmpty;

  /// Whether the user has usable saved coordinates for distance sorting.
  bool get hasCoords =>
      latitude != null && longitude != null && latitude != 0.0 && longitude != 0.0;

  factory AppUser.fromMap(String id, String email, Map<String, dynamic> profile) {
    return AppUser(
      id: id,
      email: email,
      fullName: profile['full_name'] ?? 'User',
      avatarUrl: profile['avatar_url'],
      walletBalance: (profile['wallet_balance'] as num?)?.toDouble() ?? 0.0,
      rewardPoints: (profile['reward_points'] as num?)?.toInt() ?? 0,
      address: profile['address'],
      latitude: (profile['latitude'] as num?)?.toDouble(),
      longitude: (profile['longitude'] as num?)?.toDouble(),
    );
  }
}

class RentRequest {
  final String id;
  final String productId;
  final String productName;
  final String productImageUrl;
  final String requesterId;
  final String requesterName;
  final String requesterAvatar;
  final String ownerId;
  final String status;
  final int rentalDays;
  final double productPrice; // price per day, from products.price
  final DateTime createdAt;
  final DateTime? rentalEndDate; // Set by owner upon acceptance

  double get totalPrice => productPrice * rentalDays;

  RentRequest({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productImageUrl,
    required this.requesterId,
    required this.requesterName,
    required this.requesterAvatar,
    required this.ownerId,
    required this.status,
    required this.rentalDays,
    required this.productPrice,
    required this.createdAt,
    this.rentalEndDate,
  });

  factory RentRequest.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map<String, dynamic>?;
    final requesterProfile = map['requester_profile'] as Map<String, dynamic>?;

    return RentRequest(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      productName: product?['name'] as String? ?? 'Unknown Product',
      productImageUrl: product?['image_url'] as String? ?? '',
      requesterId: map['requester_id']?.toString() ?? '',
      requesterName: requesterProfile?['full_name'] as String? ?? 'Unknown User',
      requesterAvatar: requesterProfile?['avatar_url'] as String? ?? '',
      ownerId: map['owner_id']?.toString() ?? '',
      status: map['status'] as String? ?? 'pending',
      rentalDays: (map['rental_days'] as num?)?.toInt() ?? 1,
      productPrice: (product?['price'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      rentalEndDate: map['rental_end_date'] != null
          ? DateTime.parse(map['rental_end_date'] as String)
          : null,
    );
  }
}

class BuyRequest {
  final String id;
  final String productId;
  final String productName;
  final String productImageUrl;
  final String requesterId;
  final String requesterName;
  final String requesterAvatar;
  final String ownerId;
  final String status;
  final double productPrice;
  final DateTime createdAt;

  BuyRequest({
    required this.id,
    required this.productId,
    required this.productName,
    required this.productImageUrl,
    required this.requesterId,
    required this.requesterName,
    required this.requesterAvatar,
    required this.ownerId,
    required this.status,
    required this.productPrice,
    required this.createdAt,
  });

  factory BuyRequest.fromMap(Map<String, dynamic> map) {
    final product = map['products'] as Map<String, dynamic>?;
    final requesterProfile = map['requester_profile'] as Map<String, dynamic>?;

    return BuyRequest(
      id: map['id']?.toString() ?? '',
      productId: map['product_id']?.toString() ?? '',
      productName: product?['name'] as String? ?? 'Unknown Product',
      productImageUrl: product?['image_url'] as String? ?? '',
      requesterId: map['requester_id']?.toString() ?? '',
      requesterName: requesterProfile?['full_name'] as String? ?? 'Unknown User',
      requesterAvatar: requesterProfile?['avatar_url'] as String? ?? '',
      ownerId: map['owner_id']?.toString() ?? '',
      status: map['status'] as String? ?? 'pending',
      productPrice: (product?['price'] as num?)?.toDouble() ?? 0.0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }
}