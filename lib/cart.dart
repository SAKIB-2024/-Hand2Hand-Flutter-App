import 'package:flutter/material.dart';
import 'models.dart';
import 'supabase_service.dart';

class CartPage extends StatefulWidget {
  const CartPage({super.key});

  @override
  State<CartPage> createState() => _CartPageState();
}

class _CartPageState extends State<CartPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<CartItem> cartItems = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCart();
  }

  Future<void> _loadCart() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await SupabaseService.fetchCart(uid);
      setState(() {
        cartItems = data.map((m) => CartItem.fromMap(m)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  /// For rental items: change rental days.
  /// For buy items: delta +1 / -1 has no effect (quantity is fixed at 1).
  Future<void> _changeDays(CartItem item, int delta) async {
    if (!item.isRental) return;
    final newDays = item.rentalDays + delta;
    if (newDays <= 0) {
      await _removeItem(item);
      return;
    }
    setState(() => item.rentalDays = newDays);
    await SupabaseService.updateCartRentalDays(item.id, newDays);
  }

  Future<void> _removeItem(CartItem item) async {
    setState(() => cartItems.removeWhere((i) => i.id == item.id));
    await SupabaseService.removeFromCart(item.id);
  }

  /// Confirm purchase / rental for all items in cart.
  /// Notifies each product owner that someone wants their item.
  Future<void> _checkout() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;

    // Guard: at least one item
    if (cartItems.isEmpty) return;

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Order'),
        content: Text(
            'Send a request to the owner(s) for ${cartItems.length} item(s), total ৳${total.toStringAsFixed(2)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              onPressed: () => Navigator.pop(context, true),
              child:
              const Text('Confirm', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _loading = true);

    try {
      // Create the actual request (rent_requests / buy_requests) for each
      // item, notify the owner, and open a chat with them.
      for (final item in cartItems) {
        final ownerId = item.ownerId;
        if (ownerId == null || ownerId == uid) continue; // skip own products

        if (item.isRental) {
          await SupabaseService.createRentRequest(
            productId: item.productId,
            ownerId: ownerId,
            rentalDays: item.rentalDays,
          );
        } else {
          await SupabaseService.createBuyRequest(
            productId: item.productId,
            ownerId: ownerId,
          );
        }

        // Open/ensure a chat with the owner for this product
        await SupabaseService.getOrCreateConversation(uid, ownerId, item.productId);
      }

      // Clear cart
      for (final item in cartItems) {
        await SupabaseService.removeFromCart(item.id);
      }

      if (mounted) {
        setState(() {
          cartItems.clear();
          _loading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              '✅ Request sent! Product owners have been notified.'),
          backgroundColor: Color(0xFF381932),
        ));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  double get subtotal =>
      cartItems.fold(0.0, (s, i) => s + i.totalPrice);
  double get deliveryFee =>
      cartItems.any((i) => !i.freeDelivery) ? 100 : 0.0;
  double get total => subtotal + deliveryFee;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('My Cart'),
        centerTitle: true,
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
            const Text('Please log in to view your cart',
                style: TextStyle(fontSize: 16)),
          ],
        ),
      )
          : cartItems.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shopping_cart_outlined,
                size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text('Your cart is empty',
                style: TextStyle(
                    fontSize: 18, color: Colors.grey.shade600)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 32, vertical: 12)),
              child: const Text('Start Shopping'),
            ),
          ],
        ),
      )
          : Column(children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: cartItems.length,
            itemBuilder: (_, i) => _CartItemCard(
              item: cartItems[i],
              onIncrease: () => _changeDays(cartItems[i], 1),
              onDecrease: () => _changeDays(cartItems[i], -1),
              onRemove: () => _removeItem(cartItems[i]),
            ),
          ),
        ),
        // Order summary
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -4))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Order Summary',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _summaryRow('Subtotal',
                  '৳${subtotal.toStringAsFixed(2)}'),
              const SizedBox(height: 6),
              _summaryRow(
                  'Delivery Fee',
                  deliveryFee == 0
                      ? 'FREE'
                      : '৳${deliveryFee.toStringAsFixed(2)}'),
              const Divider(height: 20),
              Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold)),
                    Text('৳${total.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: primaryColor)),
                  ]),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _checkout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(12)),
                  ),
                  child: const Text('Send Request to Owner(s)',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _summaryRow(String label, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(label, style: TextStyle(color: Colors.grey.shade700)),
      Text(value),
    ],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Cart item card — compact, image takes ~50% card width
// ─────────────────────────────────────────────────────────────────────────────
class _CartItemCard extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final CartItem item;
  final VoidCallback onIncrease, onDecrease, onRemove;

  const _CartItemCard({
    required this.item,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image (~50% card width) ────────────────────────────────────
            ClipRRect(
              borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(13)),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.42,
                child: Image.network(
                  item.imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, size: 32),
                  ),
                ),
              ),
            ),

            // ── Details ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(item.name,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),

                    // Price (per day or fixed)
                    Row(children: [
                      Text('৳${item.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold)),
                      if (item.isRental)
                        Text('/day',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600)),
                    ]),

                    // Free delivery badge
                    if (item.freeDelivery) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.local_shipping_outlined,
                            size: 12, color: Colors.green.shade700),
                        const SizedBox(width: 3),
                        Text('Free Delivery',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.green.shade700)),
                      ]),
                    ],

                    const Spacer(),

                    // ── Days / unit stepper ──────────────────────────────
                    Row(children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: onDecrease,
                                child: const Icon(Icons.remove,
                                    size: 16, color: primaryColor),
                              ),
                              Expanded(
                                child: Column(children: [
                                  Text(
                                    item.isRental
                                        ? '${item.rentalDays}'
                                        : '1',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14),
                                  ),
                                  Text(
                                    item.isRental ? 'day(s)' : 'unit',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.grey.shade600),
                                  ),
                                ]),
                              ),
                              GestureDetector(
                                onTap: item.isRental ? onIncrease : null,
                                child: Icon(Icons.add,
                                    size: 16,
                                    color: item.isRental
                                        ? primaryColor
                                        : Colors.grey.shade300),
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Delete
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.red, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: onRemove,
                      ),
                    ]),

                    const SizedBox(height: 4),

                    // Total for this item
                    Text(
                      item.isRental
                          ? 'Total: ৳${item.totalPrice.toStringAsFixed(0)} (${item.rentalDays} day${item.rentalDays > 1 ? 's' : ''})'
                          : 'Total: ৳${item.totalPrice.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 11,
                          color: primaryColor,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
