import 'package:flutter/material.dart';
import 'models.dart';
import 'supabase_service.dart';
import 'chat.dart';

class RequestsTabsPage extends StatelessWidget {
  final bool isRent;
  const RequestsTabsPage({super.key, required this.isRent});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: const Color(0xFF381932),
          foregroundColor: Colors.white,
          title: Text(isRent ? 'Rent Requests' : 'Buy Requests'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'MY REQUESTS'),
              Tab(text: 'INCOMING'),
            ],
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: TabBarView(
          children: [
            RequestsList(isRent: isRent, isIncoming: false),
            RequestsList(isRent: isRent, isIncoming: true),
          ],
        ),
      ),
    );
  }
}

class RequestsList extends StatefulWidget {
  final bool isRent;
  final bool isIncoming;
  const RequestsList({super.key, required this.isRent, required this.isIncoming});

  @override
  State<RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends State<RequestsList> {
  List<dynamic> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    try {
      List<Map<String, dynamic>> data;
      if (widget.isRent) {
        data = widget.isIncoming
            ? await SupabaseService.fetchOwnerRentRequests(uid)
            : await SupabaseService.fetchMyRentRequests(uid);
        _requests = data.map((m) => RentRequest.fromMap(m)).toList();
      } else {
        data = widget.isIncoming
            ? await SupabaseService.fetchOwnerBuyRequests(uid)
            : await SupabaseService.fetchMyBuyRequests(uid);
        _requests = data.map((m) => BuyRequest.fromMap(m)).toList();
      }
    } catch (e) {
      print('Error loading requests: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(dynamic request, String status) async {
    try {
      if (widget.isRent) {
        DateTime? deadline;
        if (status == 'accepted') {
          deadline = await showDatePicker(
            context: context,
            initialDate: DateTime.now().add(const Duration(days: 7)),
            firstDate: DateTime.now(),
            lastDate: DateTime.now().add(const Duration(days: 365)),
            helpText: 'SET RENTAL DEADLINE',
          );
          if (deadline == null) return;
        }
        await SupabaseService.updateRentRequestStatus(request.id, status, rentalEndDate: deadline);
      } else {
        await SupabaseService.updateBuyRequestStatus(request.id, status);
      }
      _load();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_requests.isEmpty) return Center(child: Text('No ${widget.isRent ? 'rent' : 'buy'} requests yet.'));

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _requests.length,
        itemBuilder: (_, i) {
          final r = _requests[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(r.productImageUrl, width: 60, height: 60, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey.shade200, width: 60, height: 60, child: const Icon(Icons.broken_image))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            Text(widget.isIncoming ? 'From: ${r.requesterName}' : 'Status: ${r.status.toUpperCase()}',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                          ],
                        ),
                      ),
                      _statusBadge(r.status),
                    ],
                  ),
                  if (widget.isIncoming && r.status == 'pending') ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => _updateStatus(r, 'rejected'),
                          child: const Text('REJECT', style: TextStyle(color: Colors.red)),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => _updateStatus(r, 'accepted'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                          child: const Text('ACCEPT'),
                        ),
                      ],
                    ),
                  ],
                  // "Mark as Delivered" button for accepted buy requests (owner side only)
                  if (!widget.isRent && widget.isIncoming && r.status == 'accepted') ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: const Text('Mark as Sold'),
                              content: const Text(
                                  'Confirm that the item has been delivered and the sale is complete. The listing will be marked as sold and hidden after 24 hours.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF381932),
                                      foregroundColor: Colors.white),
                                  child: const Text('Confirm'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) _updateStatus(r, 'completed');
                        },
                        icon: const Icon(Icons.sell_outlined, size: 16),
                        label: const Text('Mark as Delivered / Sold'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF381932),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (widget.isRent)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF381932).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: Color(0xFF381932)),
                              const SizedBox(width: 6),
                              Text('${r.rentalDays} day${r.rentalDays == 1 ? '' : 's'}',
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF381932))),
                              const SizedBox(width: 4),
                              Text('(${r.productPrice.toStringAsFixed(0)}/day)',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            ],
                          ),
                          Text('Total: ${r.totalPrice.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF381932))),
                        ],
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF381932).withOpacity(0.06),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Price', style: TextStyle(fontSize: 13, color: Colors.grey)),
                          Text(r.productPrice.toStringAsFixed(0),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF381932))),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        final convId = await SupabaseService.getOrCreateConversation(
                            SupabaseService.currentUserId!,
                            widget.isIncoming ? r.requesterId : r.ownerId,
                            r.productId
                        );
                        if (mounted) {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => ChatDetailPage(
                            conversationId: convId,
                            otherUserId: widget.isIncoming ? r.requesterId : r.ownerId,
                            otherUserName: widget.isIncoming ? r.requesterName : 'Owner',
                            otherUserAvatar: widget.isIncoming ? r.requesterAvatar : '',
                            productName: r.productName,
                          )));
                        }
                      },
                      icon: const Icon(Icons.chat_bubble_outline, size: 16),
                      label: const Text('Chat'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _statusBadge(String status) {
    Color color = Colors.grey;
    if (status == 'accepted') color = Colors.green;
    if (status == 'rejected') color = Colors.red;
    if (status == 'pending') color = Colors.orange;
    if (status == 'completed') color = const Color(0xFF381932);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}