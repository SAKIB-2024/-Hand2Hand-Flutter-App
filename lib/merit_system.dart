import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Merit Models
// ─────────────────────────────────────────────────────────────────────────────

class MeritTransaction {
  final String id;
  final String userId;
  final int pointsChange;
  final String reason;
  final String? rentalId;
  final DateTime createdAt;

  MeritTransaction({
    required this.id,
    required this.userId,
    required this.pointsChange,
    required this.reason,
    this.rentalId,
    required this.createdAt,
  });

  factory MeritTransaction.fromMap(Map<String, dynamic> m) {
    return MeritTransaction(
      id: m['id']?.toString() ?? '',
      userId: m['user_id']?.toString() ?? '',
      pointsChange: (m['points_change'] as num?)?.toInt() ?? 0,
      reason: m['reason'] ?? '',
      rentalId: m['rental_id']?.toString(),
      createdAt: m['created_at'] != null
          ? DateTime.parse(m['created_at'])
          : DateTime.now(),
    );
  }
}

class UserMerit {
  final int points;
  final int totalEarned;
  final int totalLost;
  final int dailyGain;
  final DateTime? probationUntil;
  final bool isBanned;

  UserMerit({
    required this.points,
    this.totalEarned = 0,
    this.totalLost = 0,
    this.dailyGain = 0,
    this.probationUntil,
    this.isBanned = false,
  });

  factory UserMerit.fromMap(Map<String, dynamic> m) {
    return UserMerit(
      points: (m['merit_points'] as num?)?.toInt() ?? 70,
      totalEarned: (m['total_merit_earned'] as num?)?.toInt() ?? 0,
      totalLost: (m['total_merit_lost'] as num?)?.toInt() ?? 0,
      dailyGain: (m['daily_merit_gain'] as num?)?.toInt() ?? 0,
      probationUntil: m['probation_until'] != null
          ? DateTime.tryParse(m['probation_until'])
          : null,
      isBanned: m['is_banned'] ?? false,
    );
  }

  factory UserMerit.defaultMerit() => UserMerit(points: 70);

  bool get canRent => points >= 40 && !isBanned;
  bool get isOnProbation =>
      probationUntil != null && probationUntil!.isAfter(DateTime.now());
  int get remainingDailyGain => 15 - dailyGain;

  MeritTier get tier {
    if (points >= 90) return MeritTier.trustedElite;
    if (points >= 70) return MeritTier.goodStanding;
    if (points >= 50) return MeritTier.needsImprovement;
    if (points >= 40) return MeritTier.warningZone;
    if (points >= 20) return MeritTier.cannotRent;
    return MeritTier.blocked;
  }
}

enum MeritTier {
  trustedElite,
  goodStanding,
  needsImprovement,
  warningZone,
  cannotRent,
  blocked,
}

extension MeritTierExtension on MeritTier {
  String get label {
    switch (this) {
      case MeritTier.trustedElite:    return 'Trusted Elite';
      case MeritTier.goodStanding:    return 'Good Standing';
      case MeritTier.needsImprovement:return 'Needs Improvement';
      case MeritTier.warningZone:     return 'Warning Zone';
      case MeritTier.cannotRent:      return 'Cannot Rent';
      case MeritTier.blocked:         return 'Blocked';
    }
  }

  String get description {
    switch (this) {
      case MeritTier.trustedElite:    return 'Lower deposit • Priority access';
      case MeritTier.goodStanding:    return 'Full access to all features';
      case MeritTier.needsImprovement:return 'Higher deposit required';
      case MeritTier.warningZone:     return 'Co-signer or upfront payment';
      case MeritTier.cannotRent:      return 'Can only list & sell items';
      case MeritTier.blocked:         return 'View only access';
    }
  }

  int get minPoints {
    switch (this) {
      case MeritTier.trustedElite:    return 90;
      case MeritTier.goodStanding:    return 70;
      case MeritTier.needsImprovement:return 50;
      case MeritTier.warningZone:     return 40;
      case MeritTier.cannotRent:      return 20;
      case MeritTier.blocked:         return 0;
    }
  }

  dynamic get color {
    // Returns hex-like int for use with Color()
    switch (this) {
      case MeritTier.trustedElite:    return 0xFFFFD700; // Gold
      case MeritTier.goodStanding:    return 0xFF2E7D32; // Green
      case MeritTier.needsImprovement:return 0xFFE65100; // Orange
      case MeritTier.warningZone:     return 0xFFFF6F00; // Amber
      case MeritTier.cannotRent:      return 0xFFB71C1C; // Red
      case MeritTier.blocked:         return 0xFF424242; // Dark grey
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Merit Service
// ─────────────────────────────────────────────────────────────────────────────

class MeritService {
  static final _client = Supabase.instance.client;

  // Fetch merit info for a user
  static Future<UserMerit> getUserMerit(String userId) async {
    try {
      final data = await _client
          .from('profiles')
          .select(
          'merit_points, total_merit_earned, total_merit_lost, daily_merit_gain, probation_until, is_banned')
          .eq('id', userId)
          .maybeSingle();
      if (data == null) return UserMerit.defaultMerit();
      return UserMerit.fromMap(data);
    } catch (_) {
      return UserMerit.defaultMerit();
    }
  }

  // Check if user can rent
  static Future<bool> canUserRent(String userId) async {
    final merit = await getUserMerit(userId);
    return merit.canRent;
  }

  // Update merit points (positive = gain, negative = loss)
  static Future<int> updateMerit(
      String userId,
      int pointsChange,
      String reason, {
        String? rentalId,
      }) async {
    try {
      // Fetch current state
      final profile = await _client
          .from('profiles')
          .select('merit_points, daily_merit_gain, last_merit_update, total_merit_earned, total_merit_lost')
          .eq('id', userId)
          .maybeSingle();

      int current = (profile?['merit_points'] as num?)?.toInt() ?? 70;
      int dailyGain = (profile?['daily_merit_gain'] as num?)?.toInt() ?? 0;
      String? lastUpdate = profile?['last_merit_update'];
      int totalEarned = (profile?['total_merit_earned'] as num?)?.toInt() ?? 0;
      int totalLost = (profile?['total_merit_lost'] as num?)?.toInt() ?? 0;

      // Reset daily gain if it's a new day
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (lastUpdate != today) {
        dailyGain = 0;
      }

      // Below 40: gain points 50% faster
      int effectiveChange = pointsChange;
      if (pointsChange > 0 && current < 40) {
        effectiveChange = (pointsChange * 1.5).round();
      }

      // Cap daily gain at 15
      if (effectiveChange > 0) {
        final allowed = 15 - dailyGain;
        if (allowed <= 0) return current; // Daily limit reached
        effectiveChange = effectiveChange.clamp(0, allowed);
      }

      final newPoints = (current + effectiveChange).clamp(0, 100);

      // Update profile
      final updateData = <String, dynamic>{
        'merit_points': newPoints,
        'last_merit_update': today,
        'daily_merit_gain': effectiveChange > 0 ? dailyGain + effectiveChange : dailyGain,
      };
      if (effectiveChange > 0) {
        updateData['total_merit_earned'] = totalEarned + effectiveChange;
      } else if (effectiveChange < 0) {
        updateData['total_merit_lost'] = totalLost + (-effectiveChange);
      }

      await _client.from('profiles').update(updateData).eq('id', userId);

      // Record transaction
      await _client.from('merit_transactions').insert({
        'user_id': userId,
        'points_change': effectiveChange,
        'reason': reason,
        if (rentalId != null) 'rental_id': rentalId,
      });

      // ── Notify the user about their merit change ──────────────────────────
      if (effectiveChange > 0) {
        await SupabaseService.notifyMeritIncreased(userId, effectiveChange, reason);
      } else if (effectiveChange < 0) {
        await SupabaseService.notifyMeritDecreased(userId, effectiveChange, reason);
        // Warn if they've dropped into the low-merit zone
        if (newPoints < 30 && current >= 30) {
          await SupabaseService.notifyLowMerit(userId, newPoints);
        }
      }

      return newPoints;
    } catch (_) {
      return 70;
    }
  }

  // Fetch merit transaction history
  static Future<List<MeritTransaction>> getMeritHistory(
      String userId, {
        int limit = 50,
      }) async {
    try {
      final data = await _client
          .from('merit_transactions')
          .select('*')
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).map((m) => MeritTransaction.fromMap(m)).toList();
    } catch (_) {
      return [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Business Logic Helpers - Merit Gain Actions (Positive Points)
  // ─────────────────────────────────────────────────────────────────────────────

  // Complete profile bonus (+5 points)
  static Future<void> processCompleteProfile(String userId) async {
    await updateMerit(userId, 5, 'Completed profile');
  }

  // List quality product (+3 points)
  static Future<void> processListQualityProduct(String userId) async {
    await updateMerit(userId, 3, 'Listed quality product');
  }

  // Leave a review (+2 points)
  static Future<void> processLeaveReview(String userId) async {
    await updateMerit(userId, 2, 'Left a review');
  }

  // Refer a new user (+10 points)
  static Future<void> processReferral(String userId) async {
    await updateMerit(userId, 10, 'Referred a new user');
  }

  // Quick response to message (+1 point)
  static Future<void> processQuickResponse(String userId) async {
    await updateMerit(userId, 1, 'Quick response to message');
  }

  // Successful rental completion (+5 points)
  static Future<void> processRentalCompletion(String userId, String rentalId) async {
    await updateMerit(userId, 5, 'Successful rental completion', rentalId: rentalId);
  }

  // On-time return (+3 points)
  static Future<void> processOnTimeReturn(String userId, String rentalId) async {
    await updateMerit(userId, 3, 'On-time return', rentalId: rentalId);
  }

  // Good condition return (+4 points)
  static Future<void> processGoodConditionReturn(String userId, String rentalId) async {
    await updateMerit(userId, 4, 'Item returned in good condition', rentalId: rentalId);
  }

  // Combined rental completion with conditions
  static Future<void> processSuccessfulRental(
      String userId,
      String rentalId, {
        bool onTime = true,
        bool goodCondition = true,
      }) async {
    await processRentalCompletion(userId, rentalId);
    if (onTime) await processOnTimeReturn(userId, rentalId);
    if (goodCondition) await processGoodConditionReturn(userId, rentalId);
  }

  // Positive feedback from seller/buyer (+2 points)
  static Future<void> processPositiveFeedback(String userId, String rentalId) async {
    await updateMerit(userId, 2, 'Received positive feedback', rentalId: rentalId);
  }

  // Verified email/phone (+3 points)
  static Future<void> processVerificationBonus(String userId) async {
    await updateMerit(userId, 3, 'Verified contact information');
  }

  // First successful transaction bonus (+10 points)
  static Future<void> processFirstTransactionBonus(String userId, String rentalId) async {
    await updateMerit(userId, 10, 'First successful transaction bonus', rentalId: rentalId);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Business Logic Helpers - Merit Loss Actions (Negative Points)
  // ─────────────────────────────────────────────────────────────────────────────

  // Cancel rental due to buyer fault (-8 points)
  static Future<void> processRentalCancellationBuyerFault(String userId, String rentalId) async {
    await updateMerit(userId, -8, 'Cancelled rental - buyer fault', rentalId: rentalId);
  }

  // Cancel after confirmation (-10 points)
  static Future<void> processCancellationAfterConfirmation(String userId, String rentalId) async {
    await updateMerit(userId, -10, 'Cancelled after confirmation', rentalId: rentalId);
  }

  // General cancellation (use this with a parameter)
  static Future<void> processRentalCancellation(
      String userId,
      String rentalId, {
        bool buyerFault = false,
      }) async {
    if (buyerFault) {
      await processRentalCancellationBuyerFault(userId, rentalId);
    } else {
      await processCancellationAfterConfirmation(userId, rentalId);
    }
  }

  // Damaged return (-15 points)
  static Future<void> processReturnDamage(String userId, String rentalId) async {
    await updateMerit(userId, -15, 'Returned item damaged', rentalId: rentalId);
  }

  // No-show (-20 points)
  static Future<void> processNoShow(String userId, String rentalId) async {
    await updateMerit(userId, -20, 'No-show for rental', rentalId: rentalId);
  }

  // Received valid report (-10 points)
  static Future<void> processValidReport(String targetUserId, String reason) async {
    await updateMerit(targetUserId, -10, 'Received valid report: $reason');
  }

  // Late return (-5 points per day, max -20)
  static Future<void> processLateReturn(String userId, String rentalId, int daysLate) async {
    int penalty = (daysLate * 5).clamp(0, 20);
    if (penalty > 0) {
      await updateMerit(userId, -penalty, 'Late return ($daysLate days)', rentalId: rentalId);
    }
  }

  // Negative feedback from user (-3 points)
  static Future<void> processNegativeFeedback(String userId, String rentalId) async {
    await updateMerit(userId, -3, 'Received negative feedback', rentalId: rentalId);
  }

  // Dispute lost (-15 points)
  static Future<void> processDisputeLost(String userId, String rentalId) async {
    await updateMerit(userId, -15, 'Lost dispute resolution', rentalId: rentalId);
  }

  // Multiple cancellations warning (-5 points)
  static Future<void> processMultipleCancellations(String userId) async {
    await updateMerit(userId, -5, 'Multiple cancellations warning');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Admin Actions
  // ─────────────────────────────────────────────────────────────────────────────

  // Admin: Adjust user merit
  static Future<void> adminAdjustMerit(String userId, int points, String reason) async {
    await updateMerit(userId, points, 'Admin adjustment: $reason');
  }

  // Admin: Put user on probation
  static Future<void> adminSetProbation(String userId, int days) async {
    final probationUntil = DateTime.now().add(Duration(days: days));
    await _client.from('profiles').update({
      'probation_until': probationUntil.toIso8601String(),
    }).eq('id', userId);
  }

  // Admin: Remove probation
  static Future<void> adminRemoveProbation(String userId) async {
    await _client.from('profiles').update({
      'probation_until': null,
    }).eq('id', userId);
  }

  // Check if user can perform certain actions based on merit
  static Future<bool> canUserPerformAction(String userId, String action) async {
    final merit = await getUserMerit(userId);

    // Banned users cannot do anything
    if (merit.isBanned) return false;

    switch (action) {
      case 'rent':
        return merit.canRent;
      case 'list':
        return merit.points >= 20; // Can list items even with low merit
      case 'chat':
        return merit.points >= 10; // Can chat with low merit
      default:
        return true;
    }
  }

  // Get merit statistics for a user
  static Future<Map<String, dynamic>> getMeritStats(String userId) async {
    final merit = await getUserMerit(userId);
    final history = await getMeritHistory(userId, limit: 100);

    final gains = history.where((t) => t.pointsChange > 0).fold(0, (sum, t) => sum + t.pointsChange);
    final losses = history.where((t) => t.pointsChange < 0).fold(0, (sum, t) => sum + t.pointsChange.abs());

    return {
      'currentPoints': merit.points,
      'totalGained': gains,
      'totalLost': losses,
      'netPoints': gains - losses,
      'dailyGainRemaining': merit.remainingDailyGain,
      'tier': merit.tier.label,
      'canRent': merit.canRent,
      'isOnProbation': merit.isOnProbation,
      'isBanned': merit.isBanned,
    };
  }

  // Reset daily merit gain (can be called via cron job)
  static Future<void> resetDailyMeritGain() async {
    try {
      await _client.from('profiles').update({
        'daily_merit_gain': 0,
      }).neq('id', '');
    } catch (_) {
      // Handle error silently
    }
  }
}