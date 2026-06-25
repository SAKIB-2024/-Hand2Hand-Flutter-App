import 'dart:async';
import 'package:flutter/material.dart';
import 'supabase_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Notification model
// ─────────────────────────────────────────────────────────────────────────────
class AppNotification {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? extra;
  bool isRead;
  final DateTime createdAt;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.extra,
    required this.isRead,
    required this.createdAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> m) => AppNotification(
    id: m['id'] as String,
    type: m['type'] as String,
    title: m['title'] as String,
    body: m['body'] as String,
    extra: m['extra'] as Map<String, dynamic>?,
    isRead: m['is_read'] as bool,
    createdAt: DateTime.parse(m['created_at'] as String),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Notification icon / colour helpers
// ─────────────────────────────────────────────────────────────────────────────
IconData _iconFor(String type) {
  switch (type) {
    case 'nid_verified':
      return Icons.verified_user;
    case 'nid_rejected':
      return Icons.gpp_bad;
    case 'merit_increased':
      return Icons.trending_up;
    case 'merit_decreased':
      return Icons.trending_down;
    case 'low_merit':
      return Icons.warning_amber_rounded;
    case 'cart_interest':
      return Icons.shopping_bag_outlined;
    case 'id_reported':
      return Icons.flag_outlined;
    case 'nid_reminder':
      return Icons.badge_outlined;
    case 'phone_reminder':
      return Icons.phone_iphone;
    case 'ban_warning':
      return Icons.block;
    case 'rent_request':
    case 'buy_request':
      return Icons.shopping_bag_outlined;
    case 'rent_accepted':
    case 'buy_accepted':
      return Icons.check_circle_outline;
    case 'rent_rejected':
    case 'buy_rejected':
      return Icons.cancel_outlined;
    case 'rental_ending':
      return Icons.timer_outlined;
    default:
      return Icons.notifications_outlined;
  }
}

Color _colorFor(String type) {
  switch (type) {
    case 'nid_verified':
    case 'rent_accepted':
    case 'buy_accepted':
      return const Color(0xFF22C55E);
    case 'nid_rejected':
    case 'id_reported':
    case 'ban_warning':
    case 'rent_rejected':
    case 'buy_rejected':
      return const Color(0xFFEF4444);
    case 'rent_request':
    case 'buy_request':
      return const Color(0xFF8B5CF6);
    case 'rental_ending':
      return const Color(0xFFF59E0B);
    case 'merit_increased':
      return const Color(0xFF3B82F6);
    case 'merit_decreased':
    case 'low_merit':
      return const Color(0xFFF97316);
    case 'cart_interest':
      return const Color(0xFF8B5CF6);
    case 'nid_reminder':
    case 'phone_reminder':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF6B7280);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationPage  (full screen)
// ─────────────────────────────────────────────────────────────────────────────
class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<AppNotification> _notifications = [];
  bool _loading = true;
  StreamSubscription? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final data = await SupabaseService.fetchNotifications();
    if (mounted) {
      setState(() {
        _notifications = data.map(AppNotification.fromMap).toList();
        _loading = false;
      });
      // Mark all as read once the page opens
      await SupabaseService.markAllNotificationsRead();
    }
  }

  void _subscribeRealtime() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    _realtimeSub = SupabaseService.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .listen((rows) {
      if (mounted) {
        setState(() {
          _notifications = rows.map(AppNotification.fromMap).toList();
        });
      }
    });
  }

  Future<void> _deleteNotification(String id) async {
    setState(() => _notifications.removeWhere((n) => n.id == id));
    await SupabaseService.deleteNotification(id);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear all notifications?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear all',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await SupabaseService.clearAllNotifications();
      if (mounted) setState(() => _notifications.clear());
    }
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => !n.isRead).length;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifications',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (unread > 0)
              Text('$unread unread',
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          if (_notifications.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: const Text('Clear all',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
          ? _EmptyState()
          : RefreshIndicator(
        onRefresh: _load,
        color: primaryColor,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(
              vertical: 12, horizontal: 14),
          itemCount: _notifications.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final n = _notifications[i];
            return _NotificationTile(
              notification: n,
              timeAgo: _timeAgo(n.createdAt),
              onDelete: () => _deleteNotification(n.id),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Single notification tile
// ─────────────────────────────────────────────────────────────────────────────
class _NotificationTile extends StatelessWidget {
  final AppNotification notification;
  final String timeAgo;
  final VoidCallback onDelete;

  const _NotificationTile({
    required this.notification,
    required this.timeAgo,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = _colorFor(notification.type);
    final icon = _iconFor(notification.type);
    final isUnread = !notification.isRead;

    return Dismissible(
      key: ValueKey(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.shade400,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isUnread
              ? Colors.white
              : Colors.white.withOpacity(0.65),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isUnread ? color.withOpacity(0.35) : Colors.grey.shade200,
            width: isUnread ? 1.5 : 1,
          ),
          boxShadow: isUnread
              ? [
            BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ]
              : [],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          style: TextStyle(
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    notification.body,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeAgo,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_outlined,
              size: 72, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text('No notifications yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade500)),
          const SizedBox(height: 8),
          Text('You\'re all caught up!',
              style:
              TextStyle(fontSize: 14, color: Colors.grey.shade400)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NotificationBell widget — drop it in any AppBar actions list
// ─────────────────────────────────────────────────────────────────────────────
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => NotificationBellState();
}

class NotificationBellState extends State<NotificationBell> {
  int _unreadCount = 0;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _loadCount();
    _subscribeRealtime();
    // Also check & send daily reminders each time the bell is built
    _checkDailyReminders();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _loadCount() async {
    final count = await SupabaseService.getUnreadNotificationCount();
    if (mounted) setState(() => _unreadCount = count);
  }

  void _subscribeRealtime() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    _sub = SupabaseService.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .listen((_) => _loadCount());
  }

  Future<void> _checkDailyReminders() async {
    await SupabaseService.sendDailyRemindersIfNeeded();
  }

  /// Call this after returning from the notification page to clear the badge.
  void refresh() => _loadCount();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined, color: Colors.white),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationPage()),
            );
            // Re-fetch count after returning (all read on open)
            _loadCount();
          },
        ),
        if (_unreadCount > 0)
          Positioned(
            top: 8,
            right: 8,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                constraints:
                const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  _unreadCount > 99 ? '99+' : '$_unreadCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
      ],
    );
  }
}