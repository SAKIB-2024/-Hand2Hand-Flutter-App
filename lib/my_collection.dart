import 'package:flutter/material.dart';
import 'models.dart';
import 'supabase_service.dart';
import 'product_detail.dart';

class MyCollectionPage extends StatefulWidget {
  const MyCollectionPage({super.key});

  @override
  State<MyCollectionPage> createState() => _MyCollectionPageState();
}

class _MyCollectionPageState extends State<MyCollectionPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<Map<String, dynamic>> rentals = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) { setState(() => _loading = false); return; }
    try {
      final data = await SupabaseService.fetchMyRentals(uid);
      setState(() { rentals = data; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor, foregroundColor: Colors.white,
        title: const Text('My Rentals'), centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : rentals.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.favorite_border, size: 80, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text('No rentals yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text('Explore items and start renting!', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Explore Items'),
        ),
      ]))
          : RefreshIndicator(
        onRefresh: _load,
        color: primaryColor,
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: rentals.length,
          itemBuilder: (_, i) {
            final rental = rentals[i];
            final productMap = rental['products'] as Map<String, dynamic>? ?? {};
            final product = Product.fromMap(productMap);
            return _RentalCard(
              rental: rental,
              product: product,
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
            );
          },
        ),
      ),
    );
  }
}

class _RentalCard extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final Map<String, dynamic> rental;
  final Product product;
  final VoidCallback onTap;
  const _RentalCard({required this.rental, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = rental['status'] ?? 'active';
    final startDate = rental['start_date'] != null ? rental['start_date'].toString().substring(0, 10) : '';
    final endDate = rental['end_date'] != null ? rental['end_date'].toString().substring(0, 10) : '';
    Color statusColor = status == 'active' ? Colors.green : status == 'completed' ? Colors.blue : Colors.orange;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(product.imageUrl, width: 80, height: 80, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(width: 80, height: 80, color: Colors.grey.shade300, child: const Icon(Icons.broken_image))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(product.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text('৳${product.price.toStringAsFixed(0)} / day',
                style: TextStyle(fontSize: 14, color: primaryColor, fontWeight: FontWeight.bold)),
            if (startDate.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text('$startDate → $endDate', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
            ],
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
              child: Text(status.toUpperCase(), style: TextStyle(fontSize: 11, color: statusColor, fontWeight: FontWeight.bold)),
            ),
          ])),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}