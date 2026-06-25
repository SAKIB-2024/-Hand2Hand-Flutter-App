import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Simple lat/lng pair returned by [SupabaseService.fetchUserCoords].
class UserCoords {
  final double lat;
  final double lng;
  const UserCoords(this.lat, this.lng);
}

class SupabaseService {
  static final SupabaseClient client = Supabase.instance.client;

  static User? get currentUser => client.auth.currentUser;
  static String? get currentUserId => client.auth.currentUser?.id;

  static Future<bool> isAdmin() async {
    final uid = currentUserId;
    if (uid == null) return false;
    try {
      final profile = await fetchProfile(uid);
      return profile?['is_admin'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isUserVerified(String userId) async {
    try {
      final profile = await fetchProfile(userId);
      return profile?['nid_verified'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> canPerformActions() async {
    final uid = currentUserId;
    if (uid == null) return false;
    if (await isAdmin()) return true;
    final verified = await isUserVerified(uid);
    return verified;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UNREAD MESSAGES - NEW METHODS
  // ─────────────────────────────────────────────────────────────────────────

  // Get unread message count for current user
  static Future<int> getUnreadMessageCount() async {
    final userId = currentUserId;
    if (userId == null) return 0;
    try {
      final result = await client.rpc('get_unread_message_count');
      return result as int? ?? 0;
    } catch (e) {
      print('Error getting unread count: $e');
      return 0;
    }
  }

  // Mark all messages in a conversation as read
  static Future<void> markConversationRead(String conversationId) async {
    try {
      await client.rpc('mark_conversation_read', params: {'conv_id': conversationId});
    } catch (e) {
      print('Error marking conversation read: $e');
    }
  }

  // Stream unread message count for real-time updates
  static Stream<int> streamUnreadMessageCount() {
    return client
        .from('messages')
        .stream(primaryKey: ['id'])
        .map((_) => 0)
        .asyncMap((_) => getUnreadMessageCount());
  }

  // Auth
  static Future<AuthResponse> signUp(String email, String password,
      {String? fullName}) async {
    final res = await client.auth.signUp(
      email: email,
      password: password,
      data: fullName != null ? {'full_name': fullName} : null,
    );
    return res;
  }

  static Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth
        .signInWithPassword(email: email, password: password);
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  /// Sends a password reset email. The link uses the custom app scheme
  /// (com.rentalhub.app://reset-callback) so Flutter can intercept it
  /// via the PASSWORD_RECOVERY auth event and show ResetPasswordScreen.
  /// No error is thrown even if the email doesn't exist (security best practice).
  static Future<void> resetPassword(String email) async {
    await client.auth.resetPasswordForEmail(
      email,
      // Must match the redirect URL added in Supabase Dashboard →
      // Authentication → URL Configuration → Redirect URLs.
      redirectTo: 'com.rentalhub.app://reset-callback',
    );
  }

  /// Called from ResetPasswordScreen after PASSWORD_RECOVERY event fires.
  static Future<void> updatePassword(String newPassword) async {
    await client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }

  // Profile
  static Future<Map<String, dynamic>?> fetchProfile(String userId) async {
    final data = await client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return data;
  }

  static Future<void> upsertProfile(Map<String, dynamic> data) async {
    await client.from('profiles').upsert(data);
  }

  /// Returns the current user's saved (lat, lng) from their profile, or
  /// null if not signed in or no location has been saved yet.
  static Future<UserCoords?> fetchUserCoords() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final profile = await fetchProfile(uid);
      final lat = (profile?['latitude'] as num?)?.toDouble();
      final lng = (profile?['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) return null;
      return UserCoords(lat, lng);
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NID Verification
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> uploadNIDImages(
      String userId, Uint8List frontBytes, Uint8List backBytes) async {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    final frontFileName = '$userId/front_$timestamp.jpg';
    final frontUrl = await _uploadNIDImageBytes(frontBytes, frontFileName);

    final backFileName = '$userId/back_$timestamp.jpg';
    final backUrl = await _uploadNIDImageBytes(backBytes, backFileName);

    await upsertProfile({
      'id': userId,
      'nid_front_url': frontUrl,
      'nid_back_url': backUrl,
      'verification_requested_at': DateTime.now().toIso8601String(),
      'nid_verified': false,
    });
  }

  static Future<String> _uploadNIDImageBytes(
      Uint8List bytes, String filePath) async {
    await client.storage.from('verification').uploadBinary(
      filePath,
      bytes,
      fileOptions:
      const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    return filePath;
  }

  static Future<String> getSignedNIDUrl(String storedValue,
      {int expiresInSeconds = 3600}) async {
    final path = _extractNIDPath(storedValue);
    final signedUrl = await client.storage
        .from('verification')
        .createSignedUrl(path, expiresInSeconds);
    return signedUrl;
  }

  static String _extractNIDPath(String storedValue) {
    if (!storedValue.startsWith('http')) return storedValue;
    final uri = Uri.parse(storedValue);
    final segments = uri.pathSegments;
    final bucketIndex = segments.indexOf('verification');
    if (bucketIndex != -1 && bucketIndex < segments.length - 1) {
      return segments.sublist(bucketIndex + 1).join('/');
    }
    return storedValue;
  }

  static Future<List<Map<String, dynamic>>> getVerificationRequests() async {
    final data = await client
        .from('profiles')
        .select()
        .not('nid_front_url', 'is', null)
        .eq('nid_verified', false)
        .order('verification_requested_at', ascending: true);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> approveVerification(String userId) async {
    await upsertProfile({
      'id': userId,
      'nid_verified': true,
      'verification_verified_at': DateTime.now().toIso8601String(),
      'verification_rejected_reason': null,
    });
    await _logAdminAction('approve_verification', targetUserId: userId);
  }

  static Future<void> rejectVerification(String userId, String reason) async {
    await upsertProfile({
      'id': userId,
      'nid_verified': false,
      'verification_rejected_reason': reason,
      'nid_front_url': null,
      'nid_back_url': null,
    });
    await _logAdminAction('reject_verification',
        targetUserId: userId, details: {'reason': reason});
  }

  // Admin User Management
  static Future<List<Map<String, dynamic>>> getAllUsers() async {
    final data = await client
        .from('profiles')
        .select()
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> banUser(String userId, bool ban,
      {String? reason}) async {
    await upsertProfile({'id': userId, 'is_banned': ban});
    await _logAdminAction(ban ? 'ban_user' : 'unban_user',
        targetUserId: userId,
        details: reason != null ? {'reason': reason} : null);
  }

  static Future<void> setAdminStatus(String userId, bool isAdmin) async {
    await upsertProfile({'id': userId, 'is_admin': isAdmin});
    await _logAdminAction(
        isAdmin ? 'make_admin' : 'remove_admin',
        targetUserId: userId);
  }

  static Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final data = await client
        .from('profiles')
        .select()
        .eq('email', email)
        .maybeSingle();
    return data;
  }

  static Future<void> _logAdminAction(String action,
      {String? targetUserId, Map<String, dynamic>? details}) async {
    final adminId = currentUserId;
    if (adminId == null) return;
    await client.from('admin_logs').insert({
      'admin_id': adminId,
      'action': action,
      'target_user_id': targetUserId,
      'details': details,
    });
  }

  static Future<List<Map<String, dynamic>>> getAdminLogs(
      {int limit = 50}) async {
    final data = await client
        .from('admin_logs')
        .select(
        '*, admin:profiles!admin_logs_admin_id_fkey(full_name), target:profiles!admin_logs_target_user_id_fkey(full_name, email)')
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rental availability
  // ─────────────────────────────────────────────────────────────────────────

  /// Owner manually marks a 'renting' product as 'available' again
  /// (e.g. item was returned early). Clears rental_end_date and, if there's
  /// a still-'accepted' rent request for this product, marks it 'completed'
  /// so it stops appearing as an active rental.
  static Future<void> markProductAvailable(String productId) async {
    await updateProduct(productId, {
      'status': 'available',
      'rental_end_date': null,
    });

    try {
      await client
          .from('rent_requests')
          .update({'status': 'canceled'})
          .eq('product_id', productId)
          .eq('status', 'accepted');
    } catch (e) {
      print('Failed to update rent_requests status: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Products  (now also fetches product_images)
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchProducts(
      {String? category, String? listingType}) async {
    var query = client.from('products').select(
        '*, profiles(full_name, avatar_url, nid_verified, is_banned, is_admin), product_images(image_url, is_cover, sort_order)');
    if (category != null) query = query.eq('category', category);
    if (listingType != null) query = query.eq('listing_type', listingType);
    // Hide sold items that have been sold for more than 24 hours
    final cutoff = DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
    query = query.or('status.neq.sold,sold_at.gt.$cutoff');
    final data = await query
        .order('created_at', ascending: false)
        .order('sort_order', referencedTable: 'product_images');
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<Map<String, dynamic>?> fetchProduct(String id) async {
    final data = await client
        .from('products')
        .select(
        '*, profiles(full_name, avatar_url, nid_verified, is_banned, is_admin), product_images(image_url, is_cover, sort_order)')
        .eq('id', id)
        .order('sort_order', referencedTable: 'product_images')
        .maybeSingle();
    return data;
  }

  static Future<void> insertProduct(Map<String, dynamic> data) async {
    await client.from('products').insert(data);
  }

  static Future<void> updateProduct(
      String id, Map<String, dynamic> data) async {
    await client.from('products').update(data).eq('id', id);
  }

  static Future<void> deleteProduct(String id) async {
    await client.from('products').delete().eq('id', id);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Product Images
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String> uploadProductImage(
      String userId, String productId, Uint8List bytes,
      {bool isCover = false, int sortOrder = 0}) async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final fileName = '$userId/${ts}_$sortOrder.jpg';
    await client.storage.from('products').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    final url = client.storage.from('products').getPublicUrl(fileName);

    await client.from('product_images').insert({
      'product_id': productId,
      'image_url': url,
      'is_cover': isCover,
      'sort_order': sortOrder,
    });

    if (isCover) {
      await client
          .from('products')
          .update({'image_url': url}).eq('id', productId);
    }
    return url;
  }

  static Future<void> setProductCoverImage(
      String productId, String imageId) async {
    await client
        .from('product_images')
        .update({'is_cover': false}).eq('product_id', productId);
    final row = await client
        .from('product_images')
        .update({'is_cover': true})
        .eq('id', imageId)
        .select('image_url')
        .single();
    await client
        .from('products')
        .update({'image_url': row['image_url']}).eq('id', productId);
  }

  static Future<void> deleteProductImage(
      String imageId, String imageUrl, String userId) async {
    await client.from('product_images').delete().eq('id', imageId);
    try {
      final uri = Uri.parse(imageUrl);
      final idx = uri.pathSegments.indexOf('products');
      if (idx != -1) {
        final path = uri.pathSegments.sublist(idx + 1).join('/');
        await client.storage.from('products').remove([path]);
      }
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Saves
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchSaves(
      String userId) async {
    final data = await client
        .from('saves')
        .select(
        '*, products(*, profiles(full_name), product_images(image_url, is_cover, sort_order))')
        .eq('user_id', userId);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Lightweight fetch of just the saved product IDs for the current user —
  /// used by the homepage "Buy More Save" filter, which only needs to know
  /// which products to keep rather than the full saves+product join.
  static Future<Set<String>> fetchSavedProductIds(String userId) async {
    final data = await client
        .from('saves')
        .select('product_id')
        .eq('user_id', userId);
    return List<Map<String, dynamic>>.from(data as List)
        .map((m) => m['product_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static Future<void> saveProduct(String userId, String productId) async {
    await client
        .from('saves')
        .upsert({'user_id': userId, 'product_id': productId});
  }

  static Future<void> unsaveProduct(
      String userId, String productId) async {
    await client
        .from('saves')
        .delete()
        .eq('user_id', userId)
        .eq('product_id', productId);
  }

  static Future<bool> isSaved(String userId, String productId) async {
    final data = await client
        .from('saves')
        .select('id')
        .eq('user_id', userId)
        .eq('product_id', productId)
        .maybeSingle();
    return data != null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Cart
  // ─────────────────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> fetchCart(
      String userId) async {
    final data = await client
        .from('cart_items')
        .select('*, products(*)')
        .eq('user_id', userId);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> addToCart(
      String userId, String productId, {int rentalDays = 1}) async {
    try {
      await client.from('cart_items').insert({
        'user_id': userId,
        'product_id': productId,
        'quantity': 1,
        'rental_days': rentalDays,
      });
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        // Row already exists for this (user_id, product_id) — update it instead.
        await client
            .from('cart_items')
            .update({'rental_days': rentalDays, 'quantity': 1})
            .eq('user_id', userId)
            .eq('product_id', productId);
      } else {
        rethrow;
      }
    }
  }

  static Future<void> updateCartRentalDays(
      String cartItemId, int days) async {
    if (days <= 0) {
      await client.from('cart_items').delete().eq('id', cartItemId);
    } else {
      await client
          .from('cart_items')
          .update({'rental_days': days})
          .eq('id', cartItemId);
    }
  }

  static Future<void> removeFromCart(String cartItemId) async {
    await client.from('cart_items').delete().eq('id', cartItemId);
  }

  // Chat
  static Future<List<Map<String, dynamic>>> fetchConversations(
      String userId) async {
    final data = await client
        .from('conversations')
        .select(
        '*, messages(text, image_url, created_at, sender_id, read_at), buyer:profiles!conversations_buyer_id_fkey(full_name, avatar_url), seller:profiles!conversations_seller_id_fkey(full_name, avatar_url), products(name)')
        .or('buyer_id.eq.$userId,seller_id.eq.$userId');

    final list = List<Map<String, dynamic>>.from(data as List);

    // Sort the embedded messages so the most recent is first
    for (final conv in list) {
      final msgs = conv['messages'];
      if (msgs is List && msgs.length > 1) {
        msgs.sort((a, b) {
          final ta = DateTime.tryParse(a['created_at'] ?? '') ?? DateTime(0);
          final tb = DateTime.tryParse(b['created_at'] ?? '') ?? DateTime(0);
          return tb.compareTo(ta);
        });
      }
    }

    // Order the conversation list itself by the timestamp of the latest
    // message (like WhatsApp/Messenger), NOT by conversations.updated_at.
    // updated_at also gets bumped just by opening/reading a chat (via the
    // last_read_at update + the set_conv_updated_at trigger), which would
    // otherwise incorrectly move a conversation to the top just because
    // you opened it.
    DateTime sortKey(Map<String, dynamic> conv) {
      final msgs = conv['messages'];
      if (msgs is List && msgs.isNotEmpty) {
        final latest = msgs.first as Map<String, dynamic>;
        final ts = DateTime.tryParse(latest['created_at'] ?? '');
        if (ts != null) return ts;
      }
      // No messages yet — fall back to when the conversation was created.
      return DateTime.tryParse(conv['created_at'] ?? '') ?? DateTime(0);
    }

    list.sort((a, b) => sortKey(b).compareTo(sortKey(a)));

    return list;
  }

  static Future<String> getOrCreateConversation(
      String buyerId, String sellerId, String productId) async {
    final existing = await client
        .from('conversations')
        .select('id')
        .eq('buyer_id', buyerId)
        .eq('seller_id', sellerId)
        .eq('product_id', productId)
        .maybeSingle();
    if (existing != null) return existing['id'] as String;
    final res = await client
        .from('conversations')
        .insert({
      'buyer_id': buyerId,
      'seller_id': sellerId,
      'product_id': productId
    })
        .select('id')
        .single();
    return res['id'] as String;
  }

  // Chat delete feature
  static Future<void> deleteConversation(String conversationId) async {
    try {
      await client.from('conversations').delete().eq('id', conversationId);
    } catch (e) {
      throw Exception('Failed to delete conversation: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMessages(String conversationId) async {
    final data = await client
        .from('messages')
        .select()
        .eq('conversation_id', conversationId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> sendMessage(String conversationId, String senderId, String text, {String? imageUrl}) async {
    await client.from('messages').insert({
      'conversation_id': conversationId,
      'sender_id': senderId,
      'text': text,
      'image_url': imageUrl,
    });
    // Update the conversation's updated_at timestamp to bump it to the top of the list
    await client
        .from('conversations')
        .update({'updated_at': DateTime.now().toIso8601String()})
        .eq('id', conversationId);
  }

  static Future<String> uploadChatImage(String userId, String conversationId, Uint8List bytes) async {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final fileName = '$userId/$conversationId/$ts.jpg';
    await client.storage.from('chat').uploadBinary(
      fileName,
      bytes,
      fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
    );
    return client.storage.from('chat').getPublicUrl(fileName);
  }

  static Future<bool> canDeleteConversation(String conversationId) async {
    try {
      final result = await client.rpc('can_delete_conversation', params: {
        'conv_id': conversationId,
      });
      return result == true;
    } catch (_) {
      return false;
    }
  }

  // Rentals / Orders
  static Future<List<Map<String, dynamic>>> fetchMyRentals(
      String userId) async {
    final data = await client
        .from('rentals')
        .select('*, products(*, profiles(full_name))')
        .eq('renter_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<List<Map<String, dynamic>>> fetchMyListings(
      String userId) async {
    final data = await client
        .from('products')
        .select('*, product_images(image_url, is_cover, sort_order)')
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  // Bills / Top-Up / Rewards / Vouchers
  static Future<List<Map<String, dynamic>>> fetchVouchers(
      String userId) async {
    final data = await client
        .from('vouchers')
        .select('*')
        .or('user_id.eq.$userId,user_id.is.null');
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<List<Map<String, dynamic>>> fetchRewards(
      String userId) async {
    final data = await client
        .from('rewards')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<List<Map<String, dynamic>>> fetchBillHistory(
      String userId) async {
    final data = await client
        .from('bill_payments')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> payBill(Map<String, dynamic> billData) async {
    await client.from('bill_payments').insert(billData);
  }

  static Future<Map<String, dynamic>?> fetchWallet(String userId) async {
    return await client
        .from('wallets')
        .select()
        .eq('user_id', userId)
        .maybeSingle();
  }

  static Future<void> topUpWallet(String userId, double amount) async {
    final wallet = await fetchWallet(userId);
    if (wallet == null) {
      await client
          .from('wallets')
          .insert({'user_id': userId, 'balance': amount});
    } else {
      final newBalance = (wallet['balance'] as num).toDouble() + amount;
      await client
          .from('wallets')
          .update({'balance': newBalance}).eq('user_id', userId);
    }
    await client
        .from('topup_history')
        .insert({'user_id': userId, 'amount': amount});
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Rent Requests
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> createRentRequest({
    required String productId,
    required String ownerId,
    required int rentalDays,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not logged in');

    // Guard: refuse if the product is currently being rented by someone else
    final productCheck = await client
        .from('products')
        .select('status')
        .eq('id', productId)
        .maybeSingle();
    if (productCheck != null && productCheck['status'] != 'available') {
      throw Exception('This item is currently being rented by another user and is unavailable.');
    }

    // 1. Create the request record
    await client.from('rent_requests').insert({
      'product_id': productId,
      'requester_id': uid,
      'owner_id': ownerId,
      'rental_days': rentalDays,
    });

    // 2. Notify the owner
    try {
      final buyerProfile = await fetchProfile(uid);
      final buyerName = buyerProfile?['full_name'] ?? 'A user';
      final product = await fetchProduct(productId);
      final productName = product?['name'] ?? 'your product';

      await notifyNewRentRequest(
        ownerId: ownerId,
        buyerName: buyerName,
        productName: productName,
        productId: productId,
      );
    } catch (e) {
      print('Notification failed but request was created: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMyRentRequests(String userId) async {
    final data = await client
        .from('rent_requests')
        .select('*, products(*), requester_profile:profiles!requester_id(*)')
        .eq('requester_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<List<Map<String, dynamic>>> fetchOwnerRentRequests(String userId) async {
    final data = await client
        .from('rent_requests')
        .select('*, products(*), requester_profile:profiles!requester_id(*)')
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> updateRentRequestStatus(String requestId, String status, {DateTime? rentalEndDate}) async {
    final data = {'status': status};
    await client.from('rent_requests').update(data).eq('id', requestId);

    // Fetch the full request (with product) so we can update product status
    // and notify the requester of the owner's decision.
    final request = await client
        .from('rent_requests')
        .select('product_id, requester_id, products(name)')
        .eq('id', requestId)
        .single();

    if (status == 'accepted' && rentalEndDate != null) {
      // Also update product status
      await updateProduct(request['product_id'], {
        'status': 'renting',
        'rental_end_date': rentalEndDate.toIso8601String(),
      });
    }

    if (status == 'accepted' || status == 'rejected') {
      try {
        final productName =
            (request['products'] as Map<String, dynamic>?)?['name'] as String? ??
                'your product';
        await notifyRentRequestStatus(
          requesterId: request['requester_id'] as String,
          productName: productName,
          productId: request['product_id'] as String,
          accepted: status == 'accepted',
        );
      } catch (e) {
        print('Notification failed but status was updated: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Buy Requests
  // ─────────────────────────────────────────────────────────────────────────

  static Future<void> createBuyRequest({
    required String productId,
    required String ownerId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not logged in');

    // 1. Create the request record
    await client.from('buy_requests').insert({
      'product_id': productId,
      'requester_id': uid,
      'owner_id': ownerId,
    });

    // 2. Notify the owner
    try {
      final buyerProfile = await fetchProfile(uid);
      final buyerName = buyerProfile?['full_name'] ?? 'A user';
      final product = await fetchProduct(productId);
      final productName = product?['name'] ?? 'your product';

      await notifyNewBuyRequest(
        ownerId: ownerId,
        buyerName: buyerName,
        productName: productName,
        productId: productId,
      );
    } catch (e) {
      print('Notification failed but request was created: $e');
    }
  }

  static Future<List<Map<String, dynamic>>> fetchMyBuyRequests(String userId) async {
    final data = await client
        .from('buy_requests')
        .select('*, products(*), requester_profile:profiles!requester_id(*)')
        .eq('requester_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<List<Map<String, dynamic>>> fetchOwnerBuyRequests(String userId) async {
    final data = await client
        .from('buy_requests')
        .select('*, products(*), requester_profile:profiles!requester_id(*)')
        .eq('owner_id', userId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }

  static Future<void> updateBuyRequestStatus(String requestId, String status) async {
    await client.from('buy_requests').update({'status': status}).eq('id', requestId);

    final request = await client
        .from('buy_requests')
        .select('product_id, requester_id, products(name)')
        .eq('id', requestId)
        .single();

    if (status == 'accepted') {
      await updateProduct(request['product_id'], {'status': 'reserved'});
    }

    if (status == 'completed') {
      // Mark product as sold with a timestamp so it auto-hides after 24 hours
      await updateProduct(request['product_id'], {
        'status': 'sold',
        'sold_at': DateTime.now().toUtc().toIso8601String(),
      });
    }

    if (status == 'accepted' || status == 'rejected') {
      try {
        final productName =
            (request['products'] as Map<String, dynamic>?)?['name'] as String? ??
                'your product';
        await notifyBuyRequestStatus(
          requesterId: request['requester_id'] as String,
          productName: productName,
          productId: request['product_id'] as String,
          accepted: status == 'accepted',
        );
      } catch (e) {
        print('Notification failed but status was updated: $e');
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Reports
  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a report. Returns true if this is a duplicate (already reported).
  static Future<bool> submitReport({
    required String reportedUserId,
    required String reason,
    String? notes,
    String? productId,
  }) async {
    final uid = currentUserId;
    if (uid == null) throw Exception('Not logged in');
    try {
      await client.from('reports').insert({
        'reporter_id': uid,
        'reported_user_id': reportedUserId,
        'reason': reason,
        if (notes != null) 'notes': notes,
        if (productId != null) 'product_id': productId,
      });
      return false; // new report
    } on PostgrestException catch (e) {
      // Unique constraint violation = duplicate report
      if (e.code == '23505') return true;
      rethrow;
    }
  }

  /// Admin: fetch all reports, newest first, with reporter/reported profiles.
  static Future<List<Map<String, dynamic>>> getReports({
    String? status,
    int limit = 100,
  }) async {
    var query = client.from('reports').select(
      '*,'
          'reporter:profiles!reports_reporter_id_fkey(id, full_name, avatar_url, email),'
          'reported:profiles!reports_reported_user_id_fkey(id, full_name, avatar_url, email, is_banned),'
          'product:products(id, name, image_url),'
          'reviewer:profiles!reports_reviewed_by_fkey(full_name)',
    );
    if (status != null) query = query.eq('status', status);
    final data = await query
        .order('created_at', ascending: false)
        .limit(limit);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// Admin: update a report's status and optionally add an admin note.
  static Future<void> updateReport(
      String reportId, {
        required String status,
        String? adminNote,
      }) async {
    await client.from('reports').update({
      'status': status,
      if (adminNote != null) 'admin_note': adminNote,
      'reviewed_by': currentUserId,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', reportId);

    await _logAdminAction('review_report', details: {
      'report_id': reportId,
      'new_status': status,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // NOTIFICATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Fetch all notifications for the current user, newest first.
  static Future<List<Map<String, dynamic>>> fetchNotifications() async {
    final uid = currentUserId;
    if (uid == null) return [];
    try {
      final data = await client
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(data as List);
    } catch (e) {
      print('fetchNotifications error: $e');
      return [];
    }
  }

  /// Unread count for badge display.
  static Future<int> getUnreadNotificationCount() async {
    if (currentUserId == null) return 0;
    try {
      final result = await client.rpc('get_unread_notification_count');
      return result as int? ?? 0;
    } catch (e) {
      print('getUnreadNotificationCount error: $e');
      return 0;
    }
  }

  /// Mark all notifications for current user as read.
  static Future<void> markAllNotificationsRead() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await client
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', uid)
          .eq('is_read', false);
    } catch (e) {
      print('markAllNotificationsRead error: $e');
    }
  }

  /// Delete a single notification.
  static Future<void> deleteNotification(String notificationId) async {
    try {
      await client.from('notifications').delete().eq('id', notificationId);
    } catch (_) {}
  }

  /// Delete all notifications for current user.
  static Future<void> clearAllNotifications() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      await client.from('notifications').delete().eq('user_id', uid);
    } catch (_) {}
  }

  /// Core: insert a notification for any user.
  /// [targetUserId] is the recipient; can be any user (not just current).
  static Future<void> sendNotification({
    required String targetUserId,
    required String type,
    required String title,
    required String body,
    Map<String, dynamic>? extra,
  }) async {
    try {
      await client.rpc('send_notification', params: {
        'p_user_id': targetUserId,
        'p_type': type,
        'p_title': title,
        'p_body': body,
        'p_extra': extra,
      });
    } catch (e) {
      print('sendNotification error: $e');
      // Fallback: direct insert if RPC fails
      try {
        await client.from('notifications').insert({
          'user_id': targetUserId,
          'type': type,
          'title': title,
          'body': body,
          'extra': extra,
        });
      } catch (e2) {
        print('Direct notification insert also failed: $e2');
      }
    }
  }

  // ── Specific notification senders ─────────────────────────────────────────

  /// Admin approved NID.
  static Future<void> notifyNidVerified(String userId) async {
    await sendNotification(
      targetUserId: userId,
      type: 'nid_verified',
      title: '✅ NID Verified',
      body:
      'Your National ID has been verified. You now have full access to all features.',
    );
  }

  /// Admin rejected NID.
  static Future<void> notifyNidRejected(String userId, String reason) async {
    await sendNotification(
      targetUserId: userId,
      type: 'nid_rejected',
      title: '❌ NID Verification Rejected',
      body:
      'Your NID verification was rejected. Reason: $reason. Please resubmit with clear photos.',
    );
  }

  /// Merit increased by admin or system.
  static Future<void> notifyMeritIncreased(
      String userId, int points, String reason) async {
    await sendNotification(
      targetUserId: userId,
      type: 'merit_increased',
      title: '📈 Merit Points Added (+$points)',
      body: 'You earned $points merit points. Reason: $reason.',
      extra: {'points': points, 'reason': reason},
    );
  }

  /// Merit decreased by admin or system.
  static Future<void> notifyMeritDecreased(
      String userId, int points, String reason) async {
    await sendNotification(
      targetUserId: userId,
      type: 'merit_decreased',
      title: '📉 Merit Points Reduced (-${points.abs()})',
      body:
      'Your merit was reduced by ${points.abs()} points. Reason: $reason.',
      extra: {'points': points, 'reason': reason},
    );
  }

  /// Merit dropped below 30 — warn user.
  static Future<void> notifyLowMerit(String userId, int current) async {
    await sendNotification(
      targetUserId: userId,
      type: 'low_merit',
      title: '⚠️ Low Merit Warning',
      body:
      'Your merit score is $current/100. Falling below 20 may restrict your account. Complete transactions honestly to rebuild.',
      extra: {'current': current},
    );
  }

  /// Someone placed a cart order that includes your product.
  static Future<void> notifyCartInterest({
    required String productOwnerId,
    required String buyerName,
    required String productName,
    required String productId,
    required bool isRent,
  }) async {
    final action = isRent ? 'rent' : 'buy';
    await sendNotification(
      targetUserId: productOwnerId,
      type: 'cart_interest',
      title: isRent ? '🛍️ Rental Request' : '🛒 Purchase Request',
      body:
      '$buyerName wants to $action your product "$productName". Check your messages to discuss.',
      extra: {
        'buyer_name': buyerName,
        'product_id': productId,
        'product_name': productName,
        'action': action,
      },
    );
  }

  static Future<void> notifyNewRentRequest({
    required String ownerId,
    required String buyerName,
    required String productName,
    required String productId,
  }) async {
    await sendNotification(
      targetUserId: ownerId,
      type: 'rent_request',
      title: '🛍️ New Rental Request',
      body: '$buyerName wants to rent your product "$productName".',
      extra: {
        'buyer_name': buyerName,
        'product_id': productId,
        'product_name': productName,
      },
    );
  }

  static Future<void> notifyNewBuyRequest({
    required String ownerId,
    required String buyerName,
    required String productName,
    required String productId,
  }) async {
    await sendNotification(
      targetUserId: ownerId,
      type: 'buy_request',
      title: '🛒 New Purchase Request',
      body: '$buyerName wants to buy your product "$productName".',
      extra: {
        'buyer_name': buyerName,
        'product_id': productId,
        'product_name': productName,
      },
    );
  }

  /// Notify the requester that their rent request was accepted or rejected.
  static Future<void> notifyRentRequestStatus({
    required String requesterId,
    required String productName,
    required String productId,
    required bool accepted,
  }) async {
    await sendNotification(
      targetUserId: requesterId,
      type: accepted ? 'rent_accepted' : 'rent_rejected',
      title: accepted ? '✅ Rental Request Accepted' : '❌ Rental Request Rejected',
      body: accepted
          ? 'Your "$productName" request accepted by owner'
          : 'Your "$productName" request rejected by owner',
      extra: {
        'product_id': productId,
        'product_name': productName,
      },
    );
  }

  /// Notify the requester that their buy request was accepted or rejected.
  static Future<void> notifyBuyRequestStatus({
    required String requesterId,
    required String productName,
    required String productId,
    required bool accepted,
  }) async {
    await sendNotification(
      targetUserId: requesterId,
      type: accepted ? 'buy_accepted' : 'buy_rejected',
      title: accepted ? '✅ Purchase Request Accepted' : '❌ Purchase Request Rejected',
      body: accepted
          ? 'Your "$productName" request accepted by owner'
          : 'Your "$productName" request rejected by owner',
      extra: {
        'product_id': productId,
        'product_name': productName,
      },
    );
  }

  /// User's account was reported.
  static Future<void> notifyIdReported(String reportedUserId) async {
    await sendNotification(
      targetUserId: reportedUserId,
      type: 'id_reported',
      title: '🚩 Account Reported',
      body:
      'Your account has been reported by another user. Our team will review it. Maintain honest behaviour to avoid penalties.',
    );
  }

  /// Admin banned or unbanned a user.
  static Future<void> notifyBanStatus(
      String userId, bool banned, {String? reason}) async {
    await sendNotification(
      targetUserId: userId,
      type: 'ban_warning',
      title: banned ? '🚫 Account Suspended' : '✅ Account Reinstated',
      body: banned
          ? 'Your account has been suspended${reason != null ? '. Reason: $reason' : '.'}. Contact support if you believe this is an error.'
          : 'Your account suspension has been lifted. You may use the app normally.',
    );
  }

  // ── Daily reminder checks ─────────────────────────────────────────────────

  /// Called on app start / bell init — sends daily reminders if needed.
  static Future<void> sendDailyRemindersIfNeeded() async {
    final uid = currentUserId;
    if (uid == null) return;
    try {
      final profile = await fetchProfile(uid);
      if (profile == null) return;

      final nidVerified = profile['nid_verified'] as bool? ?? false;
      final nidFront = profile['nid_front_url'];
      final phone = profile['phone'] as String?;

      // NID reminder: not verified AND hasn't even uploaded yet
      if (!nidVerified && (nidFront == null || (nidFront as String).isEmpty)) {
        await sendNotification(
          targetUserId: uid,
          type: 'nid_reminder',
          title: '📋 Verify Your Identity',
          body:
          'Upload your NID card to unlock full features like renting and buying. It only takes a minute.',
        );
      }

      // Phone reminder: no phone number added
      if (phone == null || phone.trim().isEmpty) {
        await sendNotification(
          targetUserId: uid,
          type: 'phone_reminder',
          title: '📱 Add Your Phone Number',
          body:
          'Add a phone number to your profile so buyers and sellers can reach you easily.',
        );
      }
    } catch (e) {
      print('sendDailyRemindersIfNeeded error: $e');
    }
  }
}