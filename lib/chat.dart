import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';
import 'profile.dart';

// ─────────────────────────────────────────────────────────────
// ChatListPage
// ─────────────────────────────────────────────────────────────
class ChatListPage extends StatefulWidget {
  const ChatListPage({super.key});

  @override
  State<ChatListPage> createState() => _ChatListPageState();
}

class _ChatListPageState extends State<ChatListPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<Map<String, dynamic>> conversations = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _setupRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _setupRealtime() {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    // Listen for any new messages so the last-message preview updates instantly
    _channel = SupabaseService.client
        .channel('conv_list_$uid')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (_, [__]) => _load(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'conversations',
      callback: (_, [__]) => _load(),
    )
        .subscribe();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final data = await SupabaseService.fetchConversations(uid);
      if (mounted) {
        setState(() {
          conversations = data;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _otherName(Map<String, dynamic> conv) {
    final uid = SupabaseService.currentUserId;
    final buyer = conv['buyer'] as Map<String, dynamic>?;
    final seller = conv['seller'] as Map<String, dynamic>?;
    if (conv['buyer_id'] == uid) return seller?['full_name'] ?? 'Seller';
    return buyer?['full_name'] ?? 'Buyer';
  }

  String _otherAvatar(Map<String, dynamic> conv) {
    final uid = SupabaseService.currentUserId;
    final buyer = conv['buyer'] as Map<String, dynamic>?;
    final seller = conv['seller'] as Map<String, dynamic>?;
    if (conv['buyer_id'] == uid) return seller?['avatar_url'] ?? '';
    return buyer?['avatar_url'] ?? '';
  }

  String _otherUserId(Map<String, dynamic> conv) {
    final uid = SupabaseService.currentUserId;
    if (conv['buyer_id'] == uid) return conv['seller_id'] as String? ?? '';
    return conv['buyer_id'] as String? ?? '';
  }

  String _lastMessage(Map<String, dynamic> conv) {
    final msgs = conv['messages'];
    if (msgs == null || (msgs as List).isEmpty) return 'No messages yet';
    final last = msgs.first as Map<String, dynamic>;
    final imageUrl = last['image_url'] as String?;
    if (imageUrl != null && imageUrl.isNotEmpty) return '📷 Image';
    final text = last['text'] as String? ?? '';
    return text.isEmpty ? 'No messages yet' : text;
  }

  // Raw created_at of the most recent message, used for the relative time label.
  String? _lastMessageTime(Map<String, dynamic> conv) {
    final msgs = conv['messages'];
    if (msgs == null || (msgs as List).isEmpty) return null;
    final last = msgs.first as Map<String, dynamic>;
    return last['created_at'] as String?;
  }

  // WhatsApp-style relative timestamp: "Now", "5m", "3h", "Yesterday",
  // weekday name for the last week, or a short date further back.
  String _relativeTime(String? iso) {
    if (iso == null) return '';
    DateTime dt;
    try {
      dt = DateTime.parse(iso).toLocal();
    } catch (_) {
      return '';
    }
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inSeconds < 60) return 'Now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24 && dt.day == now.day) return '${diff.inHours}h';

    final yesterday = now.subtract(const Duration(days: 1));
    if (dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day) {
      return 'Yesterday';
    }

    if (diff.inDays < 7) {
      const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return weekdays[dt.weekday - 1];
    }

    if (dt.year == now.year) {
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day} ${months[dt.month - 1]}';
    }
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  // True if the most recent message is unread AND it wasn't sent by me
  // (no need to bold my own outgoing message just because the other
  // person hasn't read it yet).
  bool _hasUnread(Map<String, dynamic> conv) {
    final msgs = conv['messages'];
    if (msgs == null || (msgs as List).isEmpty) return false;
    final last = msgs.first as Map<String, dynamic>;
    final uid = SupabaseService.currentUserId;
    final senderId = last['sender_id'] as String?;
    final readAt = last['read_at'];
    return readAt == null && senderId != uid;
  }

  Future<void> _deleteConversation(String convId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Delete Chat', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('This will permanently delete the conversation and all messages. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.deleteConversation(convId);
      if (mounted) {
        setState(() => conversations.removeWhere((c) => c['id'] == convId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conversation deleted'), backgroundColor: Color(0xFF381932)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Messages'),
        centerTitle: true,
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SupabaseService.currentUserId == null
          ? Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline,
                  size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text('Please log in to view messages'),
            ]),
      )
          : conversations.isEmpty
          ? Center(
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.chat_bubble_outline,
                  size: 80, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text('No messages yet',
                  style: TextStyle(
                      fontSize: 18, color: Colors.grey.shade600)),
              const SizedBox(height: 8),
              Text('Start a conversation from a product page',
                  style: TextStyle(
                      fontSize: 14, color: Colors.grey.shade500)),
            ]),
      )
          : RefreshIndicator(
        onRefresh: _load,
        color: primaryColor,
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: conversations.length,
          itemBuilder: (_, i) {
            final conv = conversations[i];
            return Dismissible(
              key: Key(conv['id'] as String),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async {
                await _deleteConversation(conv['id'] as String);
                return false; // we handle removal ourselves
              },
              background: Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 20),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline, color: Colors.white, size: 28),
                    SizedBox(height: 4),
                    Text('Delete', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              child: _ConvCard(
                name: _otherName(conv),
                avatar: _otherAvatar(conv),
                lastMessage: _lastMessage(conv),
                hasUnread: _hasUnread(conv),
                timeLabel: _relativeTime(_lastMessageTime(conv)),
                productName: (conv['products']
                as Map<String, dynamic>?)?['name'],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ChatDetailPage(
                      conversationId: conv['id'],
                      otherUserId: _otherUserId(conv),
                      otherUserName: _otherName(conv),
                      otherUserAvatar: _otherAvatar(conv),
                      productName: (conv['products']
                      as Map<String, dynamic>?)?['name'],
                    ),
                  ),
                ).then((_) => _load()),
                onLongPress: () => _deleteConversation(conv['id'] as String),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConvCard extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final String name, avatar, lastMessage;
  final bool hasUnread;
  final String? timeLabel;
  final String? productName;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ConvCard({
    required this.name,
    required this.avatar,
    required this.lastMessage,
    this.hasUnread = false,
    this.timeLabel,
    this.productName,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: hasUnread
            ? primaryColor.withOpacity(0.05)
            : Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasUnread
              ? primaryColor.withOpacity(0.35)
              : Colors.grey.withOpacity(0.2),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: ListTile(
        onTap: onTap,
        onLongPress: onLongPress,
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          radius: 28,
          backgroundImage:
          avatar.isNotEmpty ? NetworkImage(avatar) : null,
          backgroundColor: primaryColor.withOpacity(0.2),
          child: avatar.isEmpty
              ? const Icon(Icons.person, color: Colors.white)
              : null,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: hasUnread ? primaryColor : Colors.black)),
            ),
            if (timeLabel != null && timeLabel!.isNotEmpty)
              Text(timeLabel!,
                  style: TextStyle(
                      fontSize: 12,
                      color: hasUnread ? primaryColor : Colors.grey.shade500,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
        subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 4),
              Text(lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: hasUnread ? Colors.black87 : Colors.grey.shade700,
                      fontWeight: hasUnread ? FontWeight.bold : FontWeight.normal)),
              if (productName != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: Text('Re: $productName',
                      style: TextStyle(
                          fontSize: 11,
                          color: primaryColor,
                          fontWeight: FontWeight.w500)),
                ),
              ],
            ]),
        trailing: hasUnread
            ? Container(
          width: 12,
          height: 12,
          decoration: const BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
          ),
        )
            : const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// ChatDetailPage  —  optimistic send + real-time updates
// ─────────────────────────────────────────────────────────────
class ChatDetailPage extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String otherUserAvatar;
  final String? productName;

  const ChatDetailPage({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    required this.otherUserAvatar,
    this.productName,
  });

  @override
  State<ChatDetailPage> createState() => _ChatDetailPageState();
}

class _ChatDetailPageState extends State<ChatDetailPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  final TextEditingController _msgCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  final ImagePicker _picker = ImagePicker();

  List<Map<String, dynamic>> _messages = [];
  bool _loading = true;
  bool _sending = false;
  bool _sendingImage = false;

  // Optimistic message IDs to avoid duplicates when realtime fires
  final Set<String> _optimisticIds = {};

  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadMessages(scrollToBottom: true);
    _setupRealtime();
    SupabaseService.markConversationRead(widget.conversationId);
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _setupRealtime() {
    try {
      // We do NOT use a server-side filter because filtered Postgres realtime
      // requires REPLICA IDENTITY FULL on the table (not set by default).
      // Instead we subscribe to ALL inserts and filter by conversation_id
      // in the callback — this is the most reliable approach.
      _channel = SupabaseService.client
          .channel('chat_detail_${widget.conversationId}')
          .onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'messages',
        callback: (payload, [event]) {
          final myId = SupabaseService.currentUserId;
          final newRecord = payload.newRecord;

          // newRecord may be empty {} if REPLICA IDENTITY FULL is not set.
          // Fall back to a full reload in that case.
          final convId = newRecord['conversation_id'] as String?;
          if (convId == null || convId.isEmpty) {
            _loadMessages(scrollToBottom: true);
            SupabaseService.markConversationRead(widget.conversationId);
            return;
          }

          // Ignore messages belonging to other conversations
          if (convId != widget.conversationId) return;

          final senderId = newRecord['sender_id'] as String?;
          if (senderId != myId) {
            _addIncomingMessage(newRecord);
          } else {
            _replaceOptimisticMessage(newRecord);
          }

          SupabaseService.markConversationRead(widget.conversationId);
        },
      )
          .subscribe((status, [err]) {
        debugPrint('Chat realtime: $status err=$err');
        if (status == RealtimeSubscribeStatus.subscribed) {
          // Catch any messages that arrived while we were subscribing
          _loadMessages(scrollToBottom: true);
        }
      });
    } catch (e) {
      debugPrint('Error setting up realtime: $e');
    }
  }

  /// Add an incoming (other person's) message directly from the realtime payload.
  void _addIncomingMessage(Map<String, dynamic> record) {
    if (!mounted) return;
    final id = record['id'] as String?;
    // Avoid duplicates
    if (id != null && _messages.any((m) => m['id'] == id)) return;
    setState(() {
      _messages.add(Map<String, dynamic>.from(record));
    });
    _scrollToBottom();
  }

  /// Replace an optimistic message (temp id) with the real DB record.
  void _replaceOptimisticMessage(Map<String, dynamic> record) {
    if (!mounted) return;
    final realId = record['id'] as String?;
    if (realId == null) return;

    setState(() {
      // Remove any optimistic placeholder that was inserted for this send
      _messages.removeWhere((m) => _optimisticIds.contains(m['id']));
      _optimisticIds.clear();
      // Add the real record if not already present
      if (!_messages.any((m) => m['id'] == realId)) {
        _messages.add(Map<String, dynamic>.from(record));
      }
    });
  }

  Future<void> _loadMessages({bool scrollToBottom = false}) async {
    try {
      final data = await SupabaseService.fetchMessages(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _messages = data.reversed.toList(); // oldest first
        _loading = false;
      });
      if (scrollToBottom) _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Send text message ─────────────────────────────────────────────────────
  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    _msgCtrl.clear();
    setState(() => _sending = true);

    // ── Optimistic insert: show the message immediately ──────────────────
    final tempId = 'temp_${DateTime.now().microsecondsSinceEpoch}';
    final optimisticMsg = {
      'id': tempId,
      'conversation_id': widget.conversationId,
      'sender_id': uid,
      'text': text,
      'image_url': null,
      'read_at': null,
      'created_at': DateTime.now().toIso8601String(),
    };
    setState(() {
      _optimisticIds.add(tempId);
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    try {
      await SupabaseService.sendMessage(widget.conversationId, uid, text);
      // Realtime will fire and call _replaceOptimisticMessage
    } catch (e) {
      // Roll back optimistic message on failure
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
          _optimisticIds.remove(tempId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Pick & send image ─────────────────────────────────────────────────────
  Future<void> _pickAndSendImage() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    try {
      final XFile? picked = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 80,
      );
      if (picked == null) return;

      final bytes = await picked.readAsBytes();
      setState(() => _sendingImage = true);

      // ── Optimistic insert with local bytes preview ───────────────────
      final tempId = 'temp_img_${DateTime.now().microsecondsSinceEpoch}';
      final optimisticMsg = {
        'id': tempId,
        'conversation_id': widget.conversationId,
        'sender_id': uid,
        'text': '',
        'image_url': '__local__', // placeholder; bubble handles this
        'image_bytes': bytes,     // for local preview
        'read_at': null,
        'created_at': DateTime.now().toIso8601String(),
      };
      setState(() {
        _optimisticIds.add(tempId);
        _messages.add(optimisticMsg);
      });
      _scrollToBottom();

      final imageUrl = await SupabaseService.uploadChatImage(
          uid, widget.conversationId, bytes);

      await SupabaseService.sendMessage(
        widget.conversationId,
        uid,
        '',
        imageUrl: imageUrl,
      );
      // Realtime will replace the optimistic entry
    } catch (e) {
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => _optimisticIds.contains(m['id']));
          _optimisticIds.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to send image: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.currentUserId;
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UserProfilePage(
                userId: widget.otherUserId,
                initialName: widget.otherUserName,
                initialAvatar: widget.otherUserAvatar,
              ),
            ),
          ),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundImage: widget.otherUserAvatar.isNotEmpty
                  ? NetworkImage(widget.otherUserAvatar)
                  : null,
              backgroundColor: Colors.white24,
              child: widget.otherUserAvatar.isEmpty
                  ? const Icon(Icons.person, size: 16)
                  : null,
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(widget.otherUserName,
                    style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 14, color: Colors.white70),
              ]),
              if (widget.productName != null)
                Text('Re: ${widget.productName}',
                    style: const TextStyle(fontSize: 12, color: Colors.white70))
              else
                const Text('Tap to view profile',
                    style: TextStyle(fontSize: 11, color: Colors.white54)),
            ]),
          ]),
        ),
        leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context)),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
              child: Text('No messages yet. Say hello!',
                  style:
                  TextStyle(color: Colors.grey.shade600)),
            )
                : ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (_, i) {
                final msg = _messages[i];
                final isMe = msg['sender_id'] == myId;
                final imageUrl = msg['image_url'] as String?;
                final imageBytes = msg['image_bytes'] as Uint8List?;
                final text = msg['text'] as String? ?? '';
                final isOptimistic = _optimisticIds.contains(msg['id']);
                return _MessageBubble(
                  text: text,
                  imageUrl: imageUrl == '__local__' ? null : imageUrl,
                  imageBytes: imageBytes,
                  isMe: isMe,
                  time: _formatTime(msg['created_at']),
                  isOptimistic: isOptimistic,
                );
              },
            ),
          ),

          // ── Input bar ───────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(children: [
              // Image picker button
              _sendingImage
                  ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(primaryColor)),
                ),
              )
                  : IconButton(
                icon: const Icon(Icons.image_outlined,
                    color: primaryColor),
                onPressed: _pickAndSendImage,
                tooltip: 'Send image',
              ),

              // Text field
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: TextField(
                    controller: _msgCtrl,
                    decoration: const InputDecoration(
                        hintText: 'Type a message…',
                        border: InputBorder.none),
                    maxLines: null,
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Send button
              Container(
                decoration: const BoxDecoration(
                    color: primaryColor, shape: BoxShape.circle),
                child: IconButton(
                  icon: _sending
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(
                            Colors.white)),
                  )
                      : const Icon(Icons.send,
                      color: Colors.white),
                  onPressed: _sending ? null : _send,
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = dt.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $period';
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Message bubble — handles text, image URL, and local bytes preview
// ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final String text;
  final String? imageUrl;
  final Uint8List? imageBytes; // for optimistic local preview
  final String time;
  final bool isMe;
  final bool isOptimistic;

  const _MessageBubble({
    required this.text,
    required this.isMe,
    required this.time,
    this.imageUrl,
    this.imageBytes,
    this.isOptimistic = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasImage = (imageUrl != null && imageUrl!.isNotEmpty) || imageBytes != null;
    final hasText = text.isNotEmpty;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe
              ? primaryColor.withOpacity(isOptimistic ? 0.7 : 1.0)
              : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft:
            isMe ? const Radius.circular(20) : Radius.zero,
            bottomRight:
            isMe ? Radius.zero : const Radius.circular(20),
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2))
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // ── Image ──────────────────────────────────────────────
            if (hasImage)
              GestureDetector(
                onTap: imageUrl != null && imageUrl!.isNotEmpty
                    ? () => _showFullImage(context, imageUrl!)
                    : null,
                child: Stack(
                  children: [
                    // Show local bytes while uploading, then switch to network
                    imageBytes != null && (imageUrl == null || imageUrl!.isEmpty)
                        ? Image.memory(
                      imageBytes!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    )
                        : Image.network(
                      imageUrl!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      loadingBuilder: (_, child, progress) {
                        if (progress == null) return child;
                        return Container(
                          height: 160,
                          alignment: Alignment.center,
                          child: CircularProgressIndicator(
                            value: progress.expectedTotalBytes != null
                                ? progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!
                                : null,
                            strokeWidth: 2,
                            color: isMe ? Colors.white70 : primaryColor,
                          ),
                        );
                      },
                      errorBuilder: (_, __, ___) => Container(
                        height: 120,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image,
                            color: Colors.grey),
                      ),
                    ),
                    if (isOptimistic)
                      Positioned(
                        bottom: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    else if (imageUrl != null && imageUrl!.isNotEmpty)
                      Positioned(
                        bottom: 6, right: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.fullscreen,
                              color: Colors.white, size: 14),
                        ),
                      ),
                  ],
                ),
              ),

            // ── Text + timestamp ────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(14, hasImage ? 6 : 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (hasText)
                    Text(text,
                        style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87,
                            fontSize: 15)),
                  if (hasText) const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time,
                          style: TextStyle(
                              fontSize: 10,
                              color: isMe
                                  ? Colors.white70
                                  : Colors.grey.shade600)),
                      if (isOptimistic) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.access_time,
                            size: 10,
                            color: isMe ? Colors.white54 : Colors.grey.shade400),
                      ] else if (isMe) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.done_all,
                            size: 12,
                            color: Colors.white70),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FullImagePage(imageUrl: url)),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Full-screen image viewer
// ─────────────────────────────────────────────────────────────
class _FullImagePage extends StatelessWidget {
  final String imageUrl;
  const _FullImagePage({required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.broken_image,
              color: Colors.white,
              size: 64,
            ),
          ),
        ),
      ),
    );
  }
}