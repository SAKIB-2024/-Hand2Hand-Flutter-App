import 'package:flutter/material.dart';
import 'models.dart';
import 'supabase_service.dart';
import 'homepage.dart'; // ProductGridCard
import 'upload.dart';
import 'product_detail.dart';

class MyListPage extends StatefulWidget {
  const MyListPage({super.key});

  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<Product> myItems = [];
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
      final data = await SupabaseService.fetchMyListings(uid);
      setState(() {
        myItems = data.map((m) => Product.fromMap(m)).toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Listing'),
        content: const Text('Are you sure you want to delete this listing?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => myItems.removeWhere((p) => p.id == id));
    await SupabaseService.deleteProduct(id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Listing deleted')));
  }

  Future<void> _markAvailable(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Make Available'),
        content: const Text(
            'Mark this item as available now? Only do this if the renter has already returned it.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white),
            child: const Text('Make Available'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SupabaseService.markProductAvailable(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Item is now available for rent')));
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor, foregroundColor: Colors.white,
        title: const Text('My Listings'), centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadPage()));
              _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : myItems.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.inventory_2_outlined, size: 80, color: Colors.grey.shade400),
        const SizedBox(height: 16),
        Text('No listings yet', style: TextStyle(fontSize: 18, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        Text('Tap + to add your first item', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadPage()));
            _load();
          },
          icon: const Icon(Icons.add),
          label: const Text('Add Listing'),
          style: ElevatedButton.styleFrom(backgroundColor: primaryColor, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
      ]))
          : RefreshIndicator(
        onRefresh: _load,
        color: primaryColor,
        child: GridView.builder(
          padding: const EdgeInsets.all(12),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, childAspectRatio: 0.65, crossAxisSpacing: 12, mainAxisSpacing: 12),
          itemCount: myItems.length,
          itemBuilder: (_, i) => _MyListingCard(
            product: myItems[i],
            onDelete: () => _delete(myItems[i].id),
            onMakeAvailable: () => _markAvailable(myItems[i].id),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailPage(product: myItems[i]))),
          ),
        ),
      ),
    );
  }
}

class _MyListingCard extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final Product product;
  final VoidCallback onDelete, onTap, onMakeAvailable;
  const _MyListingCard({required this.product, required this.onDelete, required this.onTap, required this.onMakeAvailable});

  @override
  Widget build(BuildContext context) {
    final isRenting = product.status == 'renting';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isRenting ? Colors.orange.withOpacity(0.5) : Colors.grey.withOpacity(0.2)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Image now takes the remaining space in the card (Expanded)
              // instead of a fixed 100px height, so the photo is much larger.
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.network(
                        product.coverImage.isNotEmpty ? product.coverImage : product.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image, size: 36),
                        ),
                      ),
                      if (isRenting)
                        Positioned(
                          left: 0, right: 0, bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 3),
                            color: Colors.black54,
                            child: Center(
                              child: Text(
                                product.rentalEndDate != null
                                    ? 'Renting until ${product.rentalEndDate!.day}/${product.rentalEndDate!.month}/${product.rentalEndDate!.year}'
                                    : 'Currently Renting',
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(product.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Text('৳${product.price.toStringAsFixed(0)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              if (product.listingType != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(product.listingType == 'rent' ? 'For Rent' : 'For Sale',
                      style: const TextStyle(fontSize: 10, color: primaryColor, fontWeight: FontWeight.w500)),
                ),
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.location_on, size: 11, color: Colors.grey.shade600),
                const SizedBox(width: 2),
                Expanded(child: Text(product.shortLocation,   // <-- CHANGED to shortLocation
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
              ]),
              if (isRenting) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onMakeAvailable,
                    icon: const Icon(Icons.lock_open, size: 14),
                    label: const Text('Make Available', style: TextStyle(fontSize: 11)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.green.shade700,
                      side: BorderSide(color: Colors.green.shade300),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          Positioned(
            top: 4, right: 4,
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.9), shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4)]),
                child: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}