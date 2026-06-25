import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'models.dart';
import 'supabase_service.dart';
import 'chat.dart';
import 'merit_system.dart';
import 'merit_history.dart';
import 'nid_verification.dart';
import 'report_dialog.dart';
import 'verification_popup.dart';
import 'cart.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen image viewer (swipeable gallery)
// ─────────────────────────────────────────────────────────────────────────────
class FullScreenImageViewer extends StatefulWidget {
  final List<String> images;
  final int initialIndex;
  final String title;

  const FullScreenImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
    required this.title,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: _current);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('${_current + 1} / ${widget.images.length}  •  ${widget.title}'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.network(
                  widget.images[i],
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: CircularProgressIndicator(
                        value: progress.expectedTotalBytes != null
                            ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                            : null,
                        color: Colors.white,
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 80),
                      SizedBox(height: 16),
                      Text('Could not load image',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Dot indicators
          if (widget.images.length > 1)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.images.length, (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: _current == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _current == i ? Colors.white : Colors.white38,
                    borderRadius: BorderRadius.circular(4),
                  ),
                )),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product Detail Page
// ─────────────────────────────────────────────────────────────────────────────
class ProductDetailPage extends StatefulWidget {
  final Product product;
  const ProductDetailPage({super.key, required this.product});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  bool _isSaved = false;
  bool _isLoading = false;

  // Slideshow
  late List<String> _images;
  int _currentImageIndex = 0;
  Timer? _slideshowTimer;
  late PageController _imagePageCtrl;

  @override
  void initState() {
    super.initState();
    _images = widget.product.allImages;
    _imagePageCtrl = PageController();
    _checkSaved();
    if (_images.length > 1) _startSlideshow();
  }

  @override
  void dispose() {
    _slideshowTimer?.cancel();
    _imagePageCtrl.dispose();
    super.dispose();
  }

  void _startSlideshow() {
    _slideshowTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      final next = (_currentImageIndex + 1) % _images.length;
      _imagePageCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  Future<void> _checkSaved() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) return;
    final saved = await SupabaseService.isSaved(uid, widget.product.id);
    if (mounted) setState(() => _isSaved = saved);
  }

  Future<void> _toggleSave() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please log in first')));
      return;
    }
    setState(() => _isSaved = !_isSaved);
    if (_isSaved) {
      await SupabaseService.saveProduct(uid, widget.product.id);
    } else {
      await SupabaseService.unsaveProduct(uid, widget.product.id);
    }
  }

  /// Add this product to the user's cart instead of directly requesting
  /// the owner. The actual rent/buy request is created later from the
  /// cart's checkout flow.
  Future<void> _addToCart() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please log in first')));
      return;
    }

    // Owners cannot add their own product to cart
    if (widget.product.ownerId == uid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You cannot add your own product to cart')),
      );
      return;
    }

    final canPerform = await SupabaseService.canPerformActions();
    if (!canPerform) {
      VerificationRequiredPopup.show(context, onVerify: () {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NIDVerificationPage()));
      });
      return;
    }

    final isRental = widget.product.listingType == 'rent';
    if (isRental) {
      final merit = await MeritService.getUserMerit(uid);
      if (!merit.canRent) {
        _showMeritBlockDialog(merit);
        return;
      }
    }

    setState(() => _isLoading = true);
    try {
      await SupabaseService.addToCart(
        uid,
        widget.product.id,
        rentalDays: 1, // Default; user can adjust in cart for rentals
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: const Text('Added to cart!'),
              backgroundColor: const Color(0xFF381932),
              action: SnackBarAction(
                label: 'VIEW CART',
                textColor: Colors.white,
                onPressed: () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const CartPage()));
                },
              )),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _openGallery([int startIndex = 0]) {
    if (_images.isEmpty) return;
    _slideshowTimer?.cancel(); // pause while viewing
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImageViewer(
          images: _images,
          initialIndex: startIndex,
          title: widget.product.name,
        ),
      ),
    ).then((_) {
      // Resume slideshow after returning
      if (_images.length > 1) _startSlideshow();
    });
  }

  void _showMeritBlockDialog(UserMerit merit) {
    final tier = merit.tier;
    final tierColor = Color(tier.color as int);

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                  color: tierColor.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(Icons.block, color: tierColor, size: 36),
            ),
            const SizedBox(height: 16),
            const Text('Cannot Rent',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Your current merit score is ${merit.points}/100.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            const Text('You need at least 40 merit points to rent items.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: merit.points / 100,
                minHeight: 10,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(tierColor),
              ),
            ),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${merit.points} pts',
                  style: TextStyle(
                      fontSize: 12,
                      color: tierColor,
                      fontWeight: FontWeight.bold)),
              Text('Need: 40 pts',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade600)),
            ]),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('How to improve your merit:',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: Colors.blue)),
                    const SizedBox(height: 8),
                    ..._meritTips().map((tip) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        const Icon(Icons.add_circle,
                            color: Colors.green, size: 14),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(tip,
                                style: const TextStyle(fontSize: 12))),
                      ]),
                    )),
                  ]),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: const BorderSide(color: primaryColor),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('Close'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const MeritHistoryPage()));
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  child: const Text('View Merit'),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  List<String> _meritTips() => [
    'Complete your profile (+5 pts)',
    'List quality products (+3 pts each)',
    'Leave reviews for sellers (+2 pts)',
    'Respond to messages quickly (+1 pt)',
    'Refer friends to the app (+10 pts)',
  ];

  Future<void> _chatWithSeller() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Please log in first')));
      return;
    }
    final sellerId = widget.product.ownerId;
    if (sellerId == null || sellerId == uid) return;
    try {
      final convId = await SupabaseService.getOrCreateConversation(
          uid, sellerId, widget.product.id);
      if (mounted) {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ChatDetailPage(
                  conversationId: convId,
                  otherUserId: sellerId,
                  otherUserName: widget.product.ownerName ?? 'Seller',
                  otherUserAvatar: widget.product.ownerAvatar ?? '',
                  productName: widget.product.name,
                )));
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final isRental = p.listingType == 'rent';

    return Scaffold(
      backgroundColor: backgroundColor,
      body: CustomScrollView(
        slivers: [
          // ── Hero image slideshow ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            flexibleSpace: FlexibleSpaceBar(
              background: GestureDetector(
                onTap: () => _openGallery(_currentImageIndex),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Slideshow
                    _images.isEmpty
                        ? Container(
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.image, size: 80),
                    )
                        : PageView.builder(
                      controller: _imagePageCtrl,
                      itemCount: _images.length,
                      onPageChanged: (i) =>
                          setState(() => _currentImageIndex = i),
                      itemBuilder: (_, i) => Image.network(
                        _images[i],
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image, size: 60),
                        ),
                      ),
                    ),

                    // Dot indicators (only if multiple images)
                    if (_images.length > 1)
                      Positioned(
                        bottom: 40,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            _images.length,
                                (i) => AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              width: _currentImageIndex == i ? 20 : 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _currentImageIndex == i
                                    ? Colors.white
                                    : Colors.white54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // Tap-to-view hint + image counter
                    Positioned(
                      bottom: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.zoom_in,
                                color: Colors.white, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              _images.length > 1
                                  ? '${_currentImageIndex + 1}/${_images.length} · Tap to view'
                                  : 'Tap to zoom',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: Icon(_isSaved ? Icons.bookmark : Icons.bookmark_border),
                onPressed: _toggleSave,
              ),
              // Only show report option for other users' listings
              if (widget.product.ownerId != null &&
                  widget.product.ownerId != SupabaseService.currentUserId)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'report') {
                      showReportDialog(
                        context: context,
                        reportedUserId: widget.product.ownerId!,
                        reportedUserName:
                        widget.product.ownerName ?? 'this user',
                        productId: widget.product.id,
                      );
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'report',
                      child: Row(
                        children: [
                          Icon(Icons.flag_outlined, color: Colors.red, size: 20),
                          SizedBox(width: 10),
                          Text('Report User',
                              style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),

          // ── Thumbnail strip (if multiple images) ─────────────────────────
          if (_images.length > 1)
            SliverToBoxAdapter(
              child: Container(
                height: 64,
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _images.length,
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () {
                      _imagePageCtrl.animateToPage(i,
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOut);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _currentImageIndex == i
                              ? primaryColor
                              : Colors.grey.shade300,
                          width: _currentImageIndex == i ? 2.5 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.network(_images[i], fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                            const Icon(Icons.broken_image, size: 20)),
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── Product details ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.name,
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Text('৳${p.price.toStringAsFixed(0)}',
                        style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: primaryColor)),
                    if (isRental) ...[
                      const SizedBox(width: 4),
                      Text('/day',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600)),
                    ],
                    const SizedBox(width: 12),
                    if (p.originalPrice > p.price)
                      Text('৳${p.originalPrice.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                              decoration: TextDecoration.lineThrough)),
                    const Spacer(),
                    if (p.discountPercent > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(8)),
                        child: Text('${p.discountPercent}% OFF',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.red.shade700)),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, children: [
                    if (p.freeDelivery)
                      _tag(Icons.local_shipping, 'Free Delivery', Colors.green),
                    if (p.listingType != null)
                      _tag(
                        p.listingType == 'rent' ? Icons.loop : Icons.sell,
                        p.listingType == 'rent' ? 'For Rent' : 'For Sale',
                        primaryColor,
                      ),
                    _locationTag(p),
                    if (p.category != null)
                      _tag(Icons.category, p.category!, Colors.purple),
                  ]),
                  const SizedBox(height: 16),
                  if (p.status != null &&
                      p.status != 'available' &&
                      p.ownerId != SupabaseService.currentUserId)
                    _availabilityBanner(p),
                  if (p.coinsSaved > 0)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber.shade200)),
                      child: Row(children: [
                        const Icon(Icons.monetization_on,
                            color: Colors.amber, size: 20),
                        const SizedBox(width: 8),
                        Text(
                            'Save ${p.coinsSaved.toStringAsFixed(0)} coins  •  Earn ${p.coinsSave.toStringAsFixed(1)} coins',
                            style: const TextStyle(fontWeight: FontWeight.w500)),
                      ]),
                    ),
                  const SizedBox(height: 20),
                  if (p.ownerName != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 8)
                          ]),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundImage: p.ownerAvatar != null
                              ? NetworkImage(p.ownerAvatar!)
                              : null,
                          backgroundColor: primaryColor.withOpacity(0.2),
                          child: p.ownerAvatar == null
                              ? const Icon(Icons.person, color: Colors.white)
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Listed by',
                                      style: TextStyle(
                                          color: Colors.grey, fontSize: 12)),
                                  Text(p.ownerName!,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16)),
                                ])),
                        if (p.ownerId != null &&
                            p.ownerId != SupabaseService.currentUserId)
                          TextButton.icon(
                            onPressed: _chatWithSeller,
                            icon: const Icon(Icons.chat_bubble_outline,
                                size: 16),
                            label: const Text('Chat'),
                            style: TextButton.styleFrom(
                                foregroundColor: primaryColor),
                          ),
                      ]),
                    ),
                  const SizedBox(height: 20),
                  if (p.description != null && p.description!.isNotEmpty) ...[
                    const Text('Description',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(p.description!,
                        style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade800,
                            height: 1.6)),
                    const SizedBox(height: 20),
                  ],
                  // Note for rental items about days selection in cart
                  if (isRental)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: primaryColor.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: primaryColor.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        Icon(Icons.info_outline, color: primaryColor, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Add this item to your cart, then adjust the rental days and send your request to the owner from there.',
                            style: TextStyle(
                                fontSize: 13, color: primaryColor.withOpacity(0.9)),
                          ),
                        ),
                      ]),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            if (widget.product.ownerId != SupabaseService.currentUserId) ...[
              Expanded(
                child: OutlinedButton(
                  onPressed: _chatWithSeller,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: const BorderSide(color: primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Chat Seller',
                      style: TextStyle(fontSize: 16)),
                ),
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: _isLoading ||
                    widget.product.status != 'available' ||
                    widget.product.ownerId == SupabaseService.currentUserId
                    ? null
                    : _addToCart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: widget.product.ownerId == SupabaseService.currentUserId
                      ? Colors.grey.shade400
                      : primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isLoading
                    ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                    : Text(
                    widget.product.ownerId == SupabaseService.currentUserId
                        ? 'Your Product'
                        : widget.product.status != 'available'
                        ? (widget.product.listingType == 'buy'
                        ? (widget.product.status == 'sold'
                        ? 'Sold Out'
                        : 'Reserved')
                        : 'Currently Renting')
                        : 'Add to Cart',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _availabilityBanner(Product p) {
    final isBuyItem = p.listingType == 'buy';
    final isSold = p.status == 'sold';
    final isReserved = p.status == 'reserved';

    // Colors: buy items use grey/blue-grey tones; rent items use red
    final Color bgColor = isBuyItem ? const Color(0xFFF5F5F5) : Colors.red.shade50;
    final Color borderColor = isBuyItem ? const Color(0xFFBDBDBD) : Colors.red.shade200;
    final Color iconColor = isBuyItem ? const Color(0xFF757575) : Colors.red.shade400;
    final Color textColor = isBuyItem ? const Color(0xFF424242) : Colors.red.shade700;

    final IconData icon = isBuyItem
        ? (isSold ? Icons.sell_outlined : Icons.hourglass_top_outlined)
        : Icons.lock_clock_outlined;

    final String message = isBuyItem
        ? (isSold
        ? 'This item has been sold and is no longer available.'
        : isReserved
        ? 'This item is reserved and pending delivery to another buyer.'
        : 'This item is currently unavailable.')
        : (p.rentalEndDate != null
        ? 'This item is currently being rented by another user and will be '
        'available again after ${p.rentalEndDate!.day}/${p.rentalEndDate!.month}/${p.rentalEndDate!.year}.'
        : 'This item is currently being rented by another user and is temporarily unavailable.');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: textColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(IconData icon, String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }

  /// Tappable location chip — opens embedded map if lat/lng stored,
  /// otherwise falls back to opening Google Maps search in browser.
  Widget _locationTag(Product p) {
    final hasCoords = p.latitude != null && p.longitude != null &&
        p.latitude != 0.0 && p.longitude != 0.0;
    return GestureDetector(
      onTap: () {
        if (hasCoords) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductLocationMapPage(
                productName: p.name,
                address: p.location,
                latitude: p.latitude!,
                longitude: p.longitude!,
              ),
            ),
          );
        } else {
          // No stored coords — open Google Maps search
          final query = Uri.encodeComponent(p.location);
          final url = 'https://www.google.com/maps/search/?api=1&query=$query';
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.blue.withOpacity(0.3))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.location_on, size: 14, color: Colors.blue),
          const SizedBox(width: 4),
          Text(p.shortLocation,   // <-- FIXED: uses p.shortLocation instead of a non-existent function
              style: const TextStyle(
                  fontSize: 12,
                  color: Colors.blue,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          const Icon(Icons.open_in_new, size: 11, color: Colors.blue),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductLocationMapPage — full-screen map showing product location
// ─────────────────────────────────────────────────────────────────────────────
class ProductLocationMapPage extends StatefulWidget {
  final String productName;
  final String address;
  final double latitude;
  final double longitude;

  const ProductLocationMapPage({
    super.key,
    required this.productName,
    required this.address,
    required this.latitude,
    required this.longitude,
  });

  @override
  State<ProductLocationMapPage> createState() => _ProductLocationMapPageState();
}

class _ProductLocationMapPageState extends State<ProductLocationMapPage> {
  static const Color primaryColor = Color(0xFF381932);
  GoogleMapController? _mapController;

  late final LatLng _position;

  @override
  void initState() {
    super.initState();
    _position = LatLng(widget.latitude, widget.longitude);
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _openInGoogleMaps() async {
    final url =
        'https://www.google.com/maps/search/?api=1&query=${widget.latitude},${widget.longitude}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.productName,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
          Text('Location', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
        centerTitle: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new),
            tooltip: 'Open in Google Maps',
            onPressed: _openInGoogleMaps,
          ),
        ],
      ),
      body: Stack(children: [
        GoogleMap(
          onMapCreated: (c) => _mapController = c,
          initialCameraPosition: CameraPosition(target: _position, zoom: 15),
          markers: {
            Marker(
              markerId: const MarkerId('product_location'),
              position: _position,
              infoWindow: InfoWindow(
                title: widget.productName,
                snippet: widget.address,
              ),
            ),
          },
          myLocationButtonEnabled: false,
          zoomControlsEnabled: true,
          mapToolbarEnabled: true,
        ),
        // Address card at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: primaryColor.withOpacity(0.1),
                      shape: BoxShape.circle),
                  child: const Icon(Icons.location_on, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.productName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(widget.address,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
              ]),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openInGoogleMaps,
                  icon: const Icon(Icons.directions),
                  label: const Text('Get Directions'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}