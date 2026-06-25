import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'models.dart';
import 'supabase_service.dart';
import 'product_detail.dart';
import 'profile.dart';
import 'cart.dart';
import 'saves.dart';
import 'chat.dart';
import 'upload.dart';
import 'search.dart';
import 'all_products.dart';
import 'notifications.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const Color primaryColor = Color(0xFF381932);
  static const Color backgroundColor = Color(0xFFF0EDE9);

  List<Product> allProducts = [];
  List<Product> products = [];
  bool _loading = true;
  UserCoords? _userCoords;
  Set<String> _savedProductIds = {};

  final List<String> filters = [
    'Best Match', 'Mall', 'Free Delivery', 'Buy More Save',
  ];
  int _selectedFilterIndex = 0;
  int _selectedNavIndex = 0;
  String _selectedExploreMode = 'Rent';

  final GlobalKey<_ChatNavItemState> _chatNavKey = GlobalKey<_ChatNavItemState>();

  late PageController _carouselController;
  late Timer _carouselTimer;
  int _currentCarouselPage = 0;

  final List<Map<String, dynamic>> _categories = [
    {'name': 'Electronics', 'image': 'https://images.unsplash.com/photo-1498049794561-7780e7231661?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&q=80'},
    {'name': 'Furniture',   'image': 'https://images.unsplash.com/photo-1555041469-a586c61ea9bc?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&q=80'},
    {'name': 'Vehicles',    'image': 'https://images.unsplash.com/photo-1580273916550-e323be2ae537?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&q=80'},
    {'name': 'Accessories', 'image': 'https://images.unsplash.com/photo-1523275335684-37898b6baf30?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&q=80'},
    {'name': 'Other',       'image': 'https://images.unsplash.com/photo-1543163521-1bf539c55dd2?ixlib=rb-4.0.3&auto=format&fit=crop&w=1200&q=80'},
  ];

  @override
  void initState() {
    super.initState();
    _carouselController = PageController();
    _startCarouselTimer();
    _loadProducts();
  }

  Future<void> _loadProducts({String? listingType, bool refreshLocation = false}) async {
    setState(() => _loading = true);
    try {
      // Fetch the user's saved location once per session (cheap to cache);
      // pull-to-refresh re-fetches it in case the address was just updated.
      if (refreshLocation || _userCoords == null) {
        _userCoords = await SupabaseService.fetchUserCoords();
      }

      final data = await SupabaseService.fetchProducts(listingType: listingType);
      var loaded = data.map((m) => Product.fromMap(m)).toList();

      // Nearest-first: "Recommended for you" shows closest items first when
      // we know the user's location, falling back to original order otherwise.
      loaded = GeoUtils.sortByDistance(loaded, _userCoords?.lat, _userCoords?.lng);

      // Refresh which products the user has saved too, so the "Buy More
      // Save" filter (and a pull-to-refresh while it's active) stays accurate.
      final uid = SupabaseService.currentUserId;
      if (uid != null) {
        try {
          _savedProductIds = await SupabaseService.fetchSavedProductIds(uid);
        } catch (_) {
          // Keep whatever saved-ids we already had if this fetch fails.
        }
      }

      setState(() {
        allProducts = loaded;
        products = _filteredProducts(loaded);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error loading products: $e')));
      }
    }
  }

  void _startCarouselTimer() {
    _carouselTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_carouselController.hasClients) {
        final next = (_currentCarouselPage + 1) % _categories.length;
        _carouselController.animateToPage(next,
            duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _carouselTimer.cancel();
    _carouselController.dispose();
    super.dispose();
  }

  /// Applies the currently-selected filter chip to [source].
  List<Product> _filteredProducts(List<Product> source) {
    switch (_selectedFilterIndex) {
      case 1: // Mall — only items added/listed by admin accounts
        return source.where((p) => p.ownerIsAdmin).toList();
      case 2: // Free Delivery
        return source.where((p) => p.freeDelivery).toList();
      case 3: // Buy More Save — only items the user has saved
        return source.where((p) => _savedProductIds.contains(p.id)).toList();
      case 0: // Best Match
      default:
        return List.from(source);
    }
  }

  Future<void> _applyFilter(int index) async {
    setState(() => _selectedFilterIndex = index);

    // "Buy More Save" reflects the saves table, so refresh it first in case
    // the user saved/unsaved something since products were last loaded.
    if (index == 3) {
      final uid = SupabaseService.currentUserId;
      if (uid == null) {
        _savedProductIds = {};
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sign in to see your saved items')),
          );
        }
      } else {
        try {
          _savedProductIds = await SupabaseService.fetchSavedProductIds(uid);
        } catch (_) {
          // Fall back to whatever saved-ids are already cached.
        }
      }
    }

    if (!mounted) return;
    setState(() {
      products = _filteredProducts(allProducts);
    });
  }

  void _onNavItemTapped(int index) {
    if (index == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SavesPage()));
      return;
    }
    if (index == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatListPage()))
          .then((_) {
        _chatNavKey.currentState?._loadUnreadCount();
      });
      return;
    }
    if (index == 4) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen()));
      return;
    }
    setState(() => _selectedNavIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        title: const Text('Hand2Hand'),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SearchPage())),
          ),
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.shopping_cart_outlined, color: Colors.white),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CartPage())),
          ),
        ],
      ),
      body: Column(
        children: [
          // Filter chips
          SizedBox(
            height: 48,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              itemCount: filters.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedFilterIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filters[index],
                        style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black87,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
                    selected: isSelected,
                    onSelected: (_) => _applyFilter(index),
                    backgroundColor: Colors.grey.shade100,
                    selectedColor: primaryColor,
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(color: isSelected ? primaryColor : Colors.grey.shade300),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _loadProducts(refreshLocation: true),
              color: primaryColor,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ========== FIXED CAROUSEL: FULL WIDTH, NO WHITE GAP ==========
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 260,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _carouselController,
                            onPageChanged: (i) => setState(() => _currentCarouselPage = i),
                            itemCount: _categories.length,
                            itemBuilder: (context, index) {
                              final cat = _categories[index];
                              return GestureDetector(
                                onTap: () => Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => SearchPage(query: cat['name']))),
                                child: Container(
                                  width: double.infinity,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(0), // no rounded corners to avoid edge gaps
                                    boxShadow: [
                                      BoxShadow(
                                          color: Colors.black.withOpacity(0.1),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2))
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(0),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        // Image - covers whole container
                                        Image.network(
                                          cat['image'],
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: double.infinity,
                                          loadingBuilder: (context, child, progress) {
                                            if (progress == null) return child;
                                            return Container(
                                              color: Colors.grey.shade200,
                                              child: const Center(child: CircularProgressIndicator()),
                                            );
                                          },
                                          errorBuilder: (_, __, ___) => Container(
                                            color: Colors.grey.shade300,
                                            child: const Icon(Icons.broken_image, size: 50),
                                          ),
                                        ),
                                        // Dark overlay for text readability
                                        Container(
                                          color: Colors.black.withOpacity(0.35),
                                        ),
                                        // Category name centered
                                        Center(
                                          child: Text(
                                            cat['name'],
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 34,
                                              fontWeight: FontWeight.bold,
                                              letterSpacing: 1.2,
                                              shadows: [
                                                Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(2, 2))
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                          // Dot indicators
                          Positioned(
                            bottom: 16,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(_categories.length, (i) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(horizontal: 5),
                                width: _currentCarouselPage == i ? 28 : 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: _currentCarouselPage == i ? primaryColor : Colors.white.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              )),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ========== END OF CAROUSEL ==========

                    const SizedBox(height: 16),

                    // Explore + Rent/Buy toggle
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Explore', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          TextButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => AllProductsPage(products: products, userCoords: _userCoords))),
                            style: TextButton.styleFrom(foregroundColor: primaryColor),
                            child: const Text('See All'),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(child: _ExploreToggleButton(
                            label: 'Rent', isSelected: _selectedExploreMode == 'Rent',
                            onTap: () { setState(() => _selectedExploreMode = 'Rent'); _loadProducts(listingType: 'rent'); },
                            selectedColor: primaryColor,
                          )),
                          const SizedBox(width: 12),
                          Expanded(child: _ExploreToggleButton(
                            label: 'Buy', isSelected: _selectedExploreMode == 'Buy',
                            onTap: () { setState(() => _selectedExploreMode = 'Buy'); _loadProducts(listingType: 'buy'); },
                            selectedColor: primaryColor,
                          )),
                        ],
                      ),
                    ),

                    // Promo banner carousel
                    const SizedBox(height: 20),
                    _PromoBannerCarousel(
                      products: products,
                      primaryColor: primaryColor,
                    ),

                    // Recommended header
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Recommended for you', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                          TextButton(
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => AllProductsPage(products: products, userCoords: _userCoords))),
                            style: TextButton.styleFrom(foregroundColor: primaryColor),
                            child: const Text('See All'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // Product grid (image fill fix applied in ProductGridCard)
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (products.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(40),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 60, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text('No products yet', style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                              const SizedBox(height: 8),
                              const Text('Be the first to list an item!', style: TextStyle(color: Colors.grey)),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 0.68,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemCount: products.length,
                          itemBuilder: (context, index) => ProductGridCard(product: products[index], userCoords: _userCoords),
                        ),
                      ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        color: primaryColor,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8.0,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(icon: Icons.home_outlined, activeIcon: Icons.home, label: 'Home', index: 0),
              _buildNavItem(icon: Icons.bookmark_border, activeIcon: Icons.bookmark, label: 'Save', index: 1),
              const SizedBox(width: 48),
              _buildNavItem(icon: Icons.chat_bubble_outline, activeIcon: Icons.chat_bubble, label: 'Chat', index: 3),
              _buildNavItem(icon: Icons.person_outline, activeIcon: Icons.person, label: 'Profile', index: 4),
            ],
          ),
        ),
      ),
      floatingActionButton: SizedBox(
        width: 65, height: 65,
        child: FloatingActionButton(
          onPressed: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const UploadPage()));
            _loadProducts();
          },
          backgroundColor: primaryColor,
          elevation: 8,
          child: const Icon(Icons.add, size: 32, color: Colors.white),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
    );
  }

  Widget _buildNavItem({required IconData icon, required IconData activeIcon, required String label, required int index}) {
    final isSelected = _selectedNavIndex == index;

    if (index == 3) {
      return _ChatNavItem(
        key: _chatNavKey,
        isSelected: isSelected,
        onTap: () => _onNavItemTapped(index),
        label: label,
        icon: icon,
        activeIcon: activeIcon,
      );
    }

    return InkWell(
      onTap: () => _onNavItemTapped(index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isSelected ? activeIcon : icon, color: isSelected ? Colors.white : Colors.white70),
          Text(label, style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : Colors.white70)),
        ],
      ),
    );
  }
}

// Chat Navigation Item with Unread Badge (unchanged)
class _ChatNavItem extends StatefulWidget {
  final bool isSelected;
  final VoidCallback onTap;
  final String label;
  final IconData icon;
  final IconData activeIcon;

  const _ChatNavItem({
    super.key,
    required this.isSelected,
    required this.onTap,
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  @override
  State<_ChatNavItem> createState() => _ChatNavItemState();
}

class _ChatNavItemState extends State<_ChatNavItem> {
  int _unreadCount = 0;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _setupRealtimeListener();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    final count = await SupabaseService.getUnreadMessageCount();
    if (mounted) setState(() => _unreadCount = count);
  }

  void _setupRealtimeListener() {
    final userId = SupabaseService.currentUserId;
    if (userId == null) return;

    _channel = SupabaseService.client
        .channel('messages_unread_${userId.substring(0, 8)}')
        .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'messages',
      callback: (_, [__]) => _loadUnreadCount(),
    )
        .onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'messages',
      callback: (_, [__]) => _loadUnreadCount(),
    )
        .subscribe((status, [_]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _loadUnreadCount();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        InkWell(
          onTap: widget.onTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.isSelected ? widget.activeIcon : widget.icon,
                  color: widget.isSelected ? Colors.white : Colors.white70),
              Text(widget.label,
                  style: TextStyle(fontSize: 12,
                      color: widget.isSelected ? Colors.white : Colors.white70)),
            ],
          ),
        ),
        if (_unreadCount > 0)
          Positioned(
            top: -6,
            right: -10,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                _unreadCount > 99 ? '99+' : '$_unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}

class _ExploreToggleButton extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color selectedColor;
  const _ExploreToggleButton({required this.label, required this.isSelected, required this.onTap, required this.selectedColor});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? selectedColor : Colors.transparent,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: isSelected ? selectedColor : Colors.grey.shade300, width: 1.5),
        ),
        child: Center(child: Text(label,
            style: TextStyle(color: isSelected ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 16))),
      ),
    );
  }
}

/// Auto-playing promo banner carousel shown on the homepage.
/// Surfaces real listings that have a discount or free delivery as
/// "featured" banners; falls back to a generic welcome banner when
/// no products qualify (e.g. on a fresh/empty marketplace).
class _PromoBannerCarousel extends StatefulWidget {
  final List<Product> products;
  final Color primaryColor;
  const _PromoBannerCarousel({required this.products, required this.primaryColor});

  @override
  State<_PromoBannerCarousel> createState() => _PromoBannerCarouselState();
}

class _PromoBannerCarouselState extends State<_PromoBannerCarousel> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _currentPage = 0;

  List<Product> get _featured {
    final discounted = widget.products
        .where((p) => p.originalPrice > p.price && p.imageUrl.isNotEmpty)
        .toList()
      ..sort((a, b) =>
          (b.originalPrice - b.price).compareTo(a.originalPrice - a.price));
    if (discounted.isNotEmpty) return discounted.take(5).toList();

    final withImages =
    widget.products.where((p) => p.imageUrl.isNotEmpty).toList();
    return withImages.take(5).toList();
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      final count = _featured.isEmpty ? 1 : _featured.length;
      if (!mounted || count <= 1) return;
      _currentPage = (_currentPage + 1) % count;
      _controller.animateToPage(_currentPage,
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = _featured;
    final pageCount = items.isEmpty ? 1 : items.length;

    return Column(
      children: [
        SizedBox(
          height: 150,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemCount: pageCount,
            itemBuilder: (context, index) {
              if (items.isEmpty) {
                return _WelcomeBanner(primaryColor: widget.primaryColor);
              }
              return _ProductPromoBanner(
                  product: items[index], primaryColor: widget.primaryColor);
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pageCount, (i) {
            final isActive = i == _currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: isActive ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: isActive
                    ? widget.primaryColor
                    : widget.primaryColor.withOpacity(0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ProductPromoBanner extends StatelessWidget {
  final Product product;
  final Color primaryColor;
  const _ProductPromoBanner({required this.product, required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.originalPrice > product.price;
    final discountPct = hasDiscount
        ? (((product.originalPrice - product.price) / product.originalPrice) * 100).round()
        : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(product.imageUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(color: primaryColor)),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withOpacity(0.65),
                      Colors.black.withOpacity(0.05),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (hasDiscount)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text('$discountPct% OFF',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      )
                    else if (product.freeDelivery)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('FREE DELIVERY',
                            style: TextStyle(
                                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(height: 8),
                    Text(product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text('৳${product.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                        if (hasDiscount) ...[
                          const SizedBox(width: 8),
                          Text('৳${product.originalPrice.toStringAsFixed(0)}',
                              style: TextStyle(
                                  color: Colors.white.withOpacity(0.7),
                                  fontSize: 13,
                                  decoration: TextDecoration.lineThrough)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fallback banner shown when there are no products to feature yet.
class _WelcomeBanner extends StatelessWidget {
  final Color primaryColor;
  const _WelcomeBanner({required this.primaryColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryColor, primaryColor.withOpacity(0.7)],
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Welcome to Hand2Hand',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Rent or buy what you need from people nearby.',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class ProductGridCard extends StatelessWidget {
  static const Color primaryColor = Color(0xFF381932);
  final Product product;
  final UserCoords? userCoords;
  const ProductGridCard({super.key, required this.product, this.userCoords});

  /// Compact distance label, e.g. "350 m" or "4.2 km", or null if unknown.
  String? get _distanceLabel {
    final km = product.distanceFrom(userCoords?.lat, userCoords?.lng);
    if (km == null) return null;
    if (km < 1) return '${(km * 1000).round()} m';
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'renting': return Colors.blue;
      case 'reserved': return Colors.orange;
      case 'sold': return Colors.red;
      default: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => ProductDetailPage(product: product))),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.withOpacity(0.18), width: 1),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2))
          ],
        ),
        // Use Stack so the status badge can be positioned over the image
        // without being a child of the Column (which caused overflow).
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image section – uses Expanded so it takes remaining space
                // after the fixed-height text section, adapting to all screens.
                Expanded(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
                    child: product.coverImage.isEmpty
                        ? Container(
                      color: Colors.grey.shade300,
                      width: double.infinity,
                      child: const Icon(Icons.image_not_supported, size: 40, color: Colors.grey),
                    )
                        : Image.network(
                      product.coverImage,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      height: double.infinity,
                      loadingBuilder: (ctx, child, prog) {
                        if (prog == null) return child;
                        return Container(
                            color: Colors.grey.shade200,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)));
                      },
                      errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.broken_image, size: 40)),
                    ),
                  ),
                ),
                // Details – fixed height content, no overflow possible
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(product.name,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Row(children: [
                        Flexible(
                          child: Text('৳${product.price.toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (product.originalPrice > product.price) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text('৳${product.originalPrice.toStringAsFixed(0)}',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade600,
                                    decoration: TextDecoration.lineThrough),
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 3),
                      Row(children: [
                        if (product.discountPercent > 0)
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4)),
                              child: Text('${product.discountPercent}% OFF',
                                  style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.red.shade700),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        if (product.discountPercent > 0 && product.listingType != null)
                          const SizedBox(width: 4),
                        if (product.listingType != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4)),
                            child: Text(
                                product.listingType == 'rent' ? 'Rent' : 'Buy',
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: primaryColor)),
                          ),
                      ]),
                      if (product.status == 'renting' && product.rentalEndDate != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Until: ${product.rentalEndDate!.day}/${product.rentalEndDate!.month}/${product.rentalEndDate!.year}',
                            style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Row(children: [
                        if (product.freeDelivery) ...[
                          Icon(Icons.local_shipping, size: 11, color: Colors.green.shade700),
                          const SizedBox(width: 2),
                          Text('FREE', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                          const SizedBox(width: 4),
                        ],
                        Icon(Icons.location_on, size: 11, color: Colors.grey.shade500),
                        const SizedBox(width: 2),
                        Expanded(
                            child: Text(product.shortLocation,
                                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                                overflow: TextOverflow.ellipsis)),
                        if (_distanceLabel != null) ...[
                          const SizedBox(width: 3),
                          Text(_distanceLabel!,
                              style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: primaryColor)),
                        ],
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            // Status badge – overlaid on top of the image via Stack
            if (product.status != null && product.status != 'available')
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _getStatusColor(product.status!).withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    product.status!.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}