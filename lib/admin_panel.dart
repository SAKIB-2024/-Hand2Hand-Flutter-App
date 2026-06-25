import 'package:flutter/material.dart';
import 'supabase_service.dart';
import 'merit_system.dart';

class AdminPanelPage extends StatefulWidget {
  const AdminPanelPage({super.key});

  @override
  State<AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<AdminPanelPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  int _selectedTab = 0;
  List<Map<String, dynamic>> _verificationRequests = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _adminLogs = [];
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final requests = await SupabaseService.getVerificationRequests();
      final users = await SupabaseService.getAllUsers();
      final logs = await SupabaseService.getAdminLogs();
      final reports = await SupabaseService.getReports();

      // Generate signed URLs for NID images (private bucket)
      final enrichedRequests = await Future.wait(requests.map((req) async {
        final Map<String, dynamic> enriched = Map.from(req);
        if (req['nid_front_url'] != null) {
          try {
            final signed = await SupabaseService.getSignedNIDUrl(req['nid_front_url'] as String);
            enriched['nid_front_signed'] = signed;
          } catch (_) {
            enriched['nid_front_signed'] = req['nid_front_url'];
          }
        }
        if (req['nid_back_url'] != null) {
          try {
            final signed = await SupabaseService.getSignedNIDUrl(req['nid_back_url'] as String);
            enriched['nid_back_signed'] = signed;
          } catch (_) {
            enriched['nid_back_signed'] = req['nid_back_url'];
          }
        }
        return enriched;
      }));

      setState(() {
        _verificationRequests = enrichedRequests;
        _users = users;
        _adminLogs = logs;
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _approveVerification(String userId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Approve Verification'),
        content: const Text('Are you sure you want to approve this user\'s NID verification?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseService.approveVerification(userId);
      await SupabaseService.notifyNidVerified(userId);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification approved'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _rejectVerification(String userId) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Verification'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Please provide a reason for rejection:'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g., Image unclear, Invalid NID',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final reason = reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please provide a reason'), backgroundColor: Colors.orange),
      );
      return;
    }

    try {
      await SupabaseService.rejectVerification(userId, reason);
      await SupabaseService.notifyNidRejected(userId, reason);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Verification rejected'), backgroundColor: Colors.orange),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleBan(String userId, bool isCurrentlyBanned, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isCurrentlyBanned ? 'Unban User' : 'Ban User'),
        content: Text('Are you sure you want to ${isCurrentlyBanned ? 'unban' : 'ban'} $userName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isCurrentlyBanned ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(isCurrentlyBanned ? 'Unban' : 'Ban'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseService.banUser(userId, !isCurrentlyBanned);
      await SupabaseService.notifyBanStatus(userId, !isCurrentlyBanned);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('User ${isCurrentlyBanned ? 'unbanned' : 'banned'} successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleAdmin(String userId, bool isCurrentlyAdmin, String userName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isCurrentlyAdmin ? 'Remove Admin' : 'Make Admin'),
        content: Text(
            'Are you sure you want to ${isCurrentlyAdmin ? 'remove admin privileges from' : 'make'} $userName ${isCurrentlyAdmin ? '' : 'an admin'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
            ),
            child: Text(isCurrentlyAdmin ? 'Remove' : 'Make Admin'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await SupabaseService.setAdminStatus(userId, !isCurrentlyAdmin);
      await _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Admin status updated for $userName'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
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
        title: const Text('Admin Panel'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Tabs
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _tabButton('Verification', 0, Icons.verified_user),
                const SizedBox(width: 12),
                _tabButton('Users', 1, Icons.people),
                const SizedBox(width: 12),
                _tabButton('Logs', 2, Icons.history),
                const SizedBox(width: 12),
                _tabButton('Reports', 3, Icons.flag_outlined),
              ],
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _selectedTab,
              children: [
                _VerificationTab(
                  requests: _verificationRequests,
                  onApprove: _approveVerification,
                  onReject: _rejectVerification,
                ),
                _UsersTab(
                  users: _users,
                  currentUserId: SupabaseService.currentUserId,
                  onToggleBan: _toggleBan,
                  onToggleAdmin: _toggleAdmin,
                ),
                _LogsTab(logs: _adminLogs),
                _ReportsTab(
                  reports: _reports,
                  onStatusChange: (id, status, note, meritPoints, reportedUserId) async {
                    await SupabaseService.updateReport(id,
                        status: status, adminNote: note);
                    if (meritPoints != null && meritPoints < 0) {
                      // Deduct merit from the reported user
                      final reasonLabel = note?.isNotEmpty == true
                          ? note!
                          : 'Report validated by admin';
                      await MeritService.updateMerit(
                          reportedUserId, meritPoints, reasonLabel);
                    }
                    // Notify the reported user their account was reported
                    await SupabaseService.notifyIdReported(reportedUserId);
                    await _loadData();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index, IconData icon) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? primaryColor : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? primaryColor : Colors.grey.shade300),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen image viewer
// ─────────────────────────────────────────────────────────────────────────────
class _FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;
  final String title;

  const _FullScreenImageViewer({required this.imageUrl, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(title),
        centerTitle: true,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (_, child, progress) {
              if (progress == null) return child;
              return Center(
                child: CircularProgressIndicator(
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                      : null,
                  color: Colors.white,
                ),
              );
            },
            errorBuilder: (_, __, ___) => Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.broken_image, color: Colors.white54, size: 80),
                const SizedBox(height: 16),
                Text('Could not load image', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification Tab
// ─────────────────────────────────────────────────────────────────────────────
class _VerificationTab extends StatelessWidget {
  final List<Map<String, dynamic>> requests;
  final Function(String) onApprove;
  final Function(String) onReject;

  const _VerificationTab({
    required this.requests,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    if (requests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No pending verifications', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: requests.length,
      itemBuilder: (_, i) {
        final req = requests[i];
        // Use signed URLs if available, fallback to original URLs
        final frontUrl = req['nid_front_signed'] as String? ?? req['nid_front_url'] as String?;
        final backUrl = req['nid_back_signed'] as String? ?? req['nid_back_url'] as String?;

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8)],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User info row
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF381932).withOpacity(0.1),
                    child: Text(
                      (req['full_name'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(color: Color(0xFF381932)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          req['full_name'] ?? 'Unknown',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          req['email'] ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        if (req['verification_requested_at'] != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            'Requested: ${_formatDate(req['verification_requested_at'])}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // NID Images label
              Row(
                children: [
                  const Icon(Icons.badge, size: 16, color: Color(0xFF381932)),
                  const SizedBox(width: 6),
                  const Text(
                    'NID Card Images',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const Spacer(),
                  Text(
                    'Tap to enlarge',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.zoom_in, size: 14, color: Colors.grey.shade500),
                ],
              ),
              const SizedBox(height: 10),

              // NID image previews — side by side
              Row(
                children: [
                  Expanded(
                    child: _imagePreview(
                      context: context,
                      url: frontUrl,
                      label: 'Front Side',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _imagePreview(
                      context: context,
                      url: backUrl,
                      label: 'Back Side',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => onReject(req['id']),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('Reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => onApprove(req['id']),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('Approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _imagePreview({
    required BuildContext context,
    required String? url,
    required String label,
  }) {
    if (url == null || url.isEmpty) {
      return Container(
        height: 130,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, color: Colors.grey.shade400, size: 32),
            const SizedBox(height: 6),
            Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            Text('Not uploaded', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _FullScreenImageViewer(
              imageUrl: url,
              title: 'NID $label',
            ),
          ),
        );
      },
      child: Container(
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.shade100,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                url,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(
                          value: progress.expectedTotalBytes != null
                              ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                              : null,
                          strokeWidth: 2,
                          color: const Color(0xFF381932),
                        ),
                        const SizedBox(height: 6),
                        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.grey.shade400, size: 32),
                    const SizedBox(height: 4),
                    Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    Text('Load failed', style: TextStyle(fontSize: 10, color: Colors.red.shade300)),
                  ],
                ),
              ),
              // Label badge at bottom
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.zoom_in, color: Colors.white, size: 12),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}, ${date.year}';
    } catch (_) {
      return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Users Tab
// ─────────────────────────────────────────────────────────────────────────────
class _UsersTab extends StatelessWidget {
  final List<Map<String, dynamic>> users;
  final String? currentUserId;
  final Function(String, bool, String) onToggleBan;
  final Function(String, bool, String) onToggleAdmin;

  const _UsersTab({
    required this.users,
    required this.currentUserId,
    required this.onToggleBan,
    required this.onToggleAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (_, i) {
        final user = users[i];
        final userId = user['id'];
        final isCurrentUser = userId == currentUserId;
        final isBanned = user['is_banned'] == true;
        final isAdmin = user['is_admin'] == true;
        final isVerified = user['nid_verified'] == true;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isBanned ? Colors.red.shade200 : Colors.grey.shade200,
              width: isBanned ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF381932).withOpacity(0.1),
                    child: Text(
                      (user['full_name'] ?? 'U')[0].toUpperCase(),
                      style: const TextStyle(color: Color(0xFF381932)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              user['full_name'] ?? 'Unknown',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (isAdmin) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Admin',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                                ),
                              ),
                            ],
                            if (isVerified) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.verified, color: Colors.green, size: 16),
                            ],
                          ],
                        ),
                        Text(
                          user['email'] ?? '',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Joined: ${_formatDate(user['created_at'])}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  if (!isCurrentUser) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => onToggleBan(userId, isBanned, user['full_name'] ?? 'User'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isBanned ? Colors.green : Colors.red,
                          side: BorderSide(color: isBanned ? Colors.green : Colors.red),
                        ),
                        child: Text(isBanned ? 'Unban' : 'Ban'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => onToggleAdmin(userId, isAdmin, user['full_name'] ?? 'User'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF381932),
                          side: const BorderSide(color: Color(0xFF381932)),
                        ),
                        child: Text(isAdmin ? 'Remove Admin' : 'Make Admin'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return 'Unknown';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logs Tab
// ─────────────────────────────────────────────────────────────────────────────
class _LogsTab extends StatelessWidget {
  final List<Map<String, dynamic>> logs;

  const _LogsTab({required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('No admin logs yet', style: TextStyle(color: Colors.grey.shade600)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (_, i) {
        final log = logs[i];
        final action = log['action'] ?? 'unknown';
        final admin = log['admin'] as Map<String, dynamic>?;
        final target = log['target'] as Map<String, dynamic>?;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(_getActionIcon(action), size: 24, color: _getActionColor(action)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getActionText(action, admin, target),
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatDateTime(log['created_at']),
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getActionIcon(String action) {
    switch (action) {
      case 'approve_verification':
        return Icons.verified;
      case 'reject_verification':
        return Icons.cancel;
      case 'ban_user':
        return Icons.block;
      case 'unban_user':
        return Icons.check_circle;
      case 'make_admin':
        return Icons.admin_panel_settings;
      case 'remove_admin':
        return Icons.person_remove;
      default:
        return Icons.info;
    }
  }

  Color _getActionColor(String action) {
    switch (action) {
      case 'approve_verification':
        return Colors.green;
      case 'reject_verification':
        return Colors.red;
      case 'ban_user':
        return Colors.red;
      case 'unban_user':
        return Colors.green;
      case 'make_admin':
        return Colors.amber;
      case 'remove_admin':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getActionText(String action, Map<String, dynamic>? admin, Map<String, dynamic>? target) {
    final adminName = admin?['full_name'] ?? 'Admin';
    final targetName = target?['full_name'] ?? 'User';

    switch (action) {
      case 'approve_verification':
        return '$adminName approved NID verification for $targetName';
      case 'reject_verification':
        return '$adminName rejected NID verification for $targetName';
      case 'ban_user':
        return '$adminName banned $targetName';
      case 'unban_user':
        return '$adminName unbanned $targetName';
      case 'make_admin':
        return '$adminName made $targetName an admin';
      case 'remove_admin':
        return '$adminName removed admin privileges from $targetName';
      default:
        return '$adminName performed $action';
    }
  }

  String _formatDateTime(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes} minutes ago';
      if (diff.inDays < 1) return '${diff.inHours} hours ago';
      return '${diff.inDays} days ago';
    } catch (_) {
      return '';
    }
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// _ReportsTab — Admin view of all user reports
// ─────────────────────────────────────────────────────────────────────────────

class _ReportsTab extends StatefulWidget {
  final List<Map<String, dynamic>> reports;
  // meritPoints: null = no action, negative int = deduct that many points
  final Future<void> Function(
      String id, String status, String? note, int? meritPoints, String reportedUserId)
  onStatusChange;

  const _ReportsTab({required this.reports, required this.onStatusChange});

  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> {
  String _filter = 'pending'; // pending | reviewed | resolved | dismissed | all

  static const _reasonLabels = {
    'scam': 'Scam / Fraud',
    'fake_listing': 'Fake Listing',
    'harassment': 'Harassment',
    'inappropriate_content': 'Inappropriate Content',
    'no_show': "No-Show / Didn't deliver",
    'damaged_item': 'Returned Damaged Item',
    'other': 'Other',
  };

  static const _statusColors = {
    'pending': Colors.orange,
    'reviewed': Colors.blue,
    'resolved': Colors.green,
    'dismissed': Colors.grey,
  };

  List<Map<String, dynamic>> get _filtered {
    if (_filter == 'all') return widget.reports;
    return widget.reports.where((r) => r['status'] == _filter).toList();
  }

  // ── Merit penalty options shown when admin resolves a report ──────────────
  static const _penaltyOptions = [
    (0,   'No merit deduction',          Icons.remove_circle_outline, Colors.grey),
    (-10, 'Warning  (−10 pts)',          Icons.warning_amber_outlined, Colors.orange),
    (-20, 'Serious violation  (−20 pts)',Icons.gpp_bad_outlined,       Colors.deepOrange),
    (-35, 'Scam / Fraud  (−35 pts)',     Icons.dangerous_outlined,     Colors.red),
    (-50, 'Severe abuse  (−50 pts)',     Icons.block,                  Colors.red),
  ];

  void _showActionSheet(Map<String, dynamic> report) {
    final noteCtrl = TextEditingController(
        text: report['admin_note'] as String? ?? '');
    String newStatus = report['status'] as String;
    int selectedPenalty = 0; // default: no deduction

    final reportedUser = report['reported'] as Map<String, dynamic>? ?? {};
    final reportedName  = reportedUser['full_name'] as String? ?? 'User';
    final reportedId    = reportedUser['id'] as String? ?? '';
    final reason        = report['reason'] as String? ?? '';
    final reasonLabel   = _reasonLabels[reason] ?? reason;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isResolving = newStatus == 'resolved';
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 20 + MediaQuery.of(ctx).viewInsets.bottom),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Header
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF381932).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.gavel,
                          color: Color(0xFF381932), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Review Report',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('Report against $reportedName · $reasonLabel',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ]),
                  ]),
                  const SizedBox(height: 20),

                  // ── Status ───────────────────────────────────────────────
                  const Text('Set Status',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['pending', 'reviewed', 'resolved', 'dismissed']
                        .map((s) {
                      final color = _statusColors[s] ?? Colors.grey;
                      final selected = newStatus == s;
                      return ChoiceChip(
                        label: Text(s[0].toUpperCase() + s.substring(1)),
                        selected: selected,
                        selectedColor: color,
                        labelStyle: TextStyle(
                            color: selected ? Colors.white : Colors.black87),
                        onSelected: (_) {
                          setLocal(() {
                            newStatus = s;
                            // Reset penalty if not resolving
                            if (s != 'resolved') selectedPenalty = 0;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),

                  // ── Merit Penalty (only when Resolved) ───────────────────
                  if (isResolving) ...[
                    Row(children: [
                      const Icon(Icons.stars, size: 16, color: Color(0xFF381932)),
                      const SizedBox(width: 6),
                      const Text('Merit Penalty for Reported User',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      'Select how many merit points to deduct from $reportedName.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 10),
                    ..._penaltyOptions.map((opt) {
                      final (pts, label, icon, color) = opt;
                      final sel = selectedPenalty == pts;
                      return GestureDetector(
                        onTap: () => setLocal(() => selectedPenalty = pts),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: sel
                                ? color.withOpacity(0.08)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: sel
                                  ? color
                                  : Colors.grey.shade200,
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Icon(icon,
                                size: 20,
                                color: sel ? color : Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(label,
                                  style: TextStyle(
                                    fontWeight: sel
                                        ? FontWeight.w700
                                        : FontWeight.normal,
                                    color: sel ? color : Colors.black87,
                                    fontSize: 14,
                                  )),
                            ),
                            if (sel)
                              Icon(Icons.check_circle,
                                  size: 18, color: color),
                          ]),
                        ),
                      );
                    }),

                    // Summary banner when a penalty is chosen
                    if (selectedPenalty < 0) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border:
                          Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(children: [
                          Icon(Icons.info_outline,
                              size: 15, color: Colors.red.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$reportedName will lose ${selectedPenalty.abs()} merit points. '
                                  'This will be logged in their merit history.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade800),
                            ),
                          ),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 16),
                  ],

                  // ── Admin Note ───────────────────────────────────────────
                  const Text('Admin Note (optional)',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      hintText: 'Reason for your decision...',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: Color(0xFF381932), width: 1.5)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Buttons ───────────────────────────────────────────────
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey.shade400),
                          padding:
                          const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF381932),
                          foregroundColor: Colors.white,
                          padding:
                          const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await widget.onStatusChange(
                            report['id'] as String,
                            newStatus,
                            noteCtrl.text.trim().isEmpty
                                ? null
                                : noteCtrl.text.trim(),
                            isResolving && selectedPenalty < 0
                                ? selectedPenalty
                                : null,
                            reportedId,
                          );
                        },
                        child: Text(
                          isResolving && selectedPenalty < 0
                              ? 'Resolve & Deduct ${selectedPenalty.abs()} pts'
                              : 'Save Decision',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          );
        },
      ),
    );
  }



  @override
  Widget build(BuildContext context) {
    final items = _filtered;

    return Column(
      children: [
        // Filter bar
        Container(
          height: 44,
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: ['pending', 'reviewed', 'resolved', 'dismissed', 'all']
                .map((f) {
              final selected = _filter == f;
              final count = f == 'all'
                  ? widget.reports.length
                  : widget.reports.where((r) => r['status'] == f).length;
              return GestureDetector(
                onTap: () => setState(() => _filter = f),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected
                        ? const Color(0xFF381932)
                        : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(children: [
                    Text(
                      f[0].toUpperCase() + f.substring(1),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected
                            ? Colors.white24
                            : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 11,
                          color: selected ? Colors.white : Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),

        // List
        Expanded(
          child: items.isEmpty
              ? Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_outlined,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  _filter == 'pending'
                      ? 'No pending reports'
                      : 'No reports in this category',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ],
            ),
          )
              : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final r = items[i];
              final reporter =
                  r['reporter'] as Map<String, dynamic>? ?? {};
              final reported =
                  r['reported'] as Map<String, dynamic>? ?? {};
              final product =
              r['product'] as Map<String, dynamic>?;
              final status = r['status'] as String? ?? 'pending';
              final statusColor =
                  _statusColors[status] ?? Colors.grey;
              final reason = r['reason'] as String? ?? '';
              final notes = r['notes'] as String?;
              final adminNote = r['admin_note'] as String?;
              final createdAt = r['created_at'] as String?;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row: status badge + time
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border:
                              Border.all(color: statusColor.withOpacity(0.4)),
                            ),
                            child: Text(
                              status[0].toUpperCase() +
                                  status.substring(1),
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Spacer(),
                          if (createdAt != null)
                            Text(
                              _timeAgo(createdAt),
                              style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 12),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Reporter → Reported
                      Row(children: [
                        _userChip(
                            reporter['full_name'] ?? 'Unknown',
                            reporter['avatar_url'],
                            'Reporter'),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.arrow_forward,
                              size: 16, color: Colors.grey),
                        ),
                        _userChip(
                            reported['full_name'] ?? 'Unknown',
                            reported['avatar_url'],
                            'Reported',
                            isBanned: reported['is_banned'] == true),
                      ]),
                      const SizedBox(height: 10),

                      // Reason
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.flag,
                              size: 14, color: Colors.red.shade600),
                          const SizedBox(width: 6),
                          Text(
                            _reasonLabels[reason] ?? reason,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ]),
                      ),

                      // User notes
                      if (notes != null && notes.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Details: $notes',
                          style: TextStyle(
                              color: Colors.grey.shade700, fontSize: 13),
                        ),
                      ],

                      // Product reference
                      if (product != null) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          const Icon(Icons.inventory_2_outlined,
                              size: 14, color: Colors.grey),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Listing: ${product['name'] ?? '—'}',
                              style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ]),
                      ],

                      // Admin note
                      if (adminNote != null && adminNote.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.blue.shade100),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  size: 14,
                                  color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  adminNote,
                                  style: TextStyle(
                                      color: Colors.blue.shade800,
                                      fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      // Action button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => _showActionSheet(r),
                          icon: const Icon(Icons.edit_note, size: 18),
                          label: const Text('Review & Update Status'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF381932),
                            side: const BorderSide(
                                color: Color(0xFF381932)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _userChip(String name, String? avatarUrl, String role,
      {bool isBanned = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(role,
            style: TextStyle(
                fontSize: 10,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 3),
        Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: Colors.grey.shade300,
            backgroundImage:
            avatarUrl != null ? NetworkImage(avatarUrl) : null,
            child: avatarUrl == null
                ? Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 12))
                : null,
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              if (isBanned)
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Banned',
                      style: TextStyle(
                          fontSize: 10, color: Colors.red.shade700)),
                ),
            ],
          ),
        ]),
      ],
    );
  }

  String _timeAgo(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inHours < 1) return '${diff.inMinutes}m ago';
      if (diff.inDays < 1) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return '';
    }
  }
}