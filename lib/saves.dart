import 'package:flutter/material.dart';
import 'models.dart';
import 'supabase_service.dart';
import 'product_detail.dart';

class SavesPage extends StatefulWidget {
  const SavesPage({super.key});

  @override
  State<SavesPage> createState() => _SavesPageState();
}

class _SavesPageState extends State<SavesPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<Product> savedProducts = [];
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
      final data = await SupabaseService.fetchSaves(uid);
      setState(() {
        savedProducts = data.map((m) {
          final productMap = m['products'] as Map<String, dynamic>? ?? m;
          return Product.fromMap(productMap);
        }).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _unsave(String productId) async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    setState(() => savedProducts.removeWhere((p) => p.id == productId));
    await SupabaseService.unsaveProduct(uid, productId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor, foregroundColor: Colors.white,
        title: const Text('Saved Items'), centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SupabaseService.currentUserId == null
          ? Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text('Please log in to view saved items'),
        ]),
      )
          : savedProducts.isEmpty
          ? Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.bookmark_border, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text('No saved items yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          Text('Tap the bookmark icon on any item to save it',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Explore Items'),
          ),
        ]),
      )
          : RefreshIndicator(
        onRefresh: _load,
        color: primaryColor,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 0.72, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: savedProducts.length,
          itemBuilder: (_, i) => _SavedCard(
            product: savedProducts[i],
            onUnsave: () => _unsave(savedProducts[i].id),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ProductDetailPage(product: savedProducts[i]))),
          ),
        ),
      ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final Product product;
  final VoidCallback onUnsave, onTap;

  const _SavedCard({required this.product, required this.onUnsave, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Image now takes the remaining space in the card (Expanded)
                // instead of a fixed 120px height, so the photo is much larger.
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(
                      product.coverImage.isNotEmpty ? product.coverImage : product.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade300,
                        child: const Icon(Icons.broken_image, size: 30),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(product.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(children: [
                  Text('৳${product.price.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('৳${product.originalPrice.toStringAsFixed(0)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600, decoration: TextDecoration.lineThrough)),
                ]),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(4)),
                  child: Text('${product.discountPercent}% OFF',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.location_on, size: 12, color: Colors.grey.shade600),
                  const SizedBox(width: 2),
                  Expanded(child: Text(product.shortLocation,   // <-- CHANGED to shortLocation
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                ]),
              ]),
            ),
            Positioned(
              top: 8, right: 8,
              child: GestureDetector(
                onTap: onUnsave,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9), shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)],
                  ),
                  child: const Icon(Icons.bookmark, color: primaryColor, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}