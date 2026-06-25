import 'package:flutter/material.dart';
import 'merit_system.dart';
import 'supabase_service.dart';

class MeritHistoryPage extends StatefulWidget {
  const MeritHistoryPage({super.key});

  @override
  State<MeritHistoryPage> createState() => _MeritHistoryPageState();
}

class _MeritHistoryPageState extends State<MeritHistoryPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<MeritTransaction> _all = [];
  String _filter = 'all'; // all | gains | losses
  bool _loading = true;
  UserMerit? _merit;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final history = await MeritService.getMeritHistory(uid, limit: 100);
      final merit = await MeritService.getUserMerit(uid);
      setState(() { _all = history; _merit = merit; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  List<MeritTransaction> get _filtered {
    if (_filter == 'gains') return _all.where((t) => t.pointsChange > 0).toList();
    if (_filter == 'losses') return _all.where((t) => t.pointsChange < 0).toList();
    return _all;
  }

  @override
  Widget build(BuildContext context) {
    final merit = _merit;
    final tier = merit?.tier ?? MeritTier.goodStanding;
    final tierColor = Color(tier.color as int);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Merit History'),
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Summary header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Current Merit', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      Text('${merit?.points ?? 70}', style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: tierColor)),
                    ]),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: tierColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: tierColor.withOpacity(0.3)),
                      ),
                      child: Text(tier.label, style: TextStyle(color: tierColor, fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: (merit?.points ?? 70) / 100,
                    minHeight: 10,
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(tierColor),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _statItem('Total Earned', '+${merit?.totalEarned ?? 0}', Colors.green),
                    Container(width: 1, height: 32, color: Colors.grey.shade200),
                    _statItem('Total Lost', '-${merit?.totalLost ?? 0}', Colors.red),
                    Container(width: 1, height: 32, color: Colors.grey.shade200),
                    _statItem('Daily Left', '+${merit?.remainingDailyGain ?? 15}', Colors.blue),
                  ],
                ),
              ],
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _filterChip('All', 'all'),
                const SizedBox(width: 8),
                _filterChip('Gains ▲', 'gains'),
                const SizedBox(width: 8),
                _filterChip('Losses ▼', 'losses'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Transaction list
          Expanded(
            child: _filtered.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.history, size: 64, color: Colors.grey.shade300),
              const SizedBox(height: 12),
              Text('No transactions yet', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
            ]))
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filtered.length,
              itemBuilder: (_, i) => _TransactionRow(transaction: _filtered[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = _filter == value;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? primaryColor : Colors.grey.shade300),
        ),
        child: Text(label, style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : Colors.grey.shade700,
        )),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final MeritTransaction transaction;
  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isGain = transaction.pointsChange > 0;
    final color = isGain ? Colors.green : Colors.red;
    final sign = isGain ? '+' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isGain ? Icons.arrow_upward : Icons.arrow_downward,
              color: color,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(transaction.reason, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                _formatDate(transaction.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
          ),
          Text(
            '$sign${transaction.pointsChange} pts',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  $h:$m $period';
  }
}