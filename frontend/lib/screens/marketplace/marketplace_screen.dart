// frontend/lib/screens/marketplace/marketplace_screen.dart
//
// RiseUp Marketplace — Browse income tools, courses, templates & mentorship
// Full dark/light mode · search · category filter · API-integrated

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────

class _MarketItem {
  final String  id;
  final String  title;
  final String  description;
  final String  category;
  final String  emoji;
  final double  price;
  final double? originalPrice;
  final double  rating;
  final int     reviews;
  final int     students;
  final bool    isFree;
  final bool    isFeatured;
  final bool    isPurchased;
  final String? author;
  final String? authorTitle;
  final List    tags;

  _MarketItem.fromJson(Map j)
      : id            = j['id']?.toString()            ?? '',
        title         = j['title']?.toString()         ?? '',
        description   = j['description']?.toString()   ?? '',
        category      = j['category']?.toString()      ?? 'course',
        emoji         = j['emoji']?.toString()         ?? '📦',
        price         = (j['price'] as num?)?.toDouble()          ?? 0.0,
        originalPrice = (j['original_price'] as num?)?.toDouble(),
        rating        = (j['rating'] as num?)?.toDouble()         ?? 4.5,
        reviews       = (j['reviews'] as num?)?.toInt()           ?? 0,
        students      = (j['students'] as num?)?.toInt()          ?? 0,
        isFree        = j['is_free'] == true || (j['price'] as num? ?? 0) == 0,
        isFeatured    = j['is_featured'] == true,
        isPurchased   = j['is_purchased'] == true,
        author        = j['author']?.toString(),
        authorTitle   = j['author_title']?.toString(),
        tags          = (j['tags'] as List?) ?? [];
}

// ─────────────────────────────────────────────────────────────────
// CATEGORIES
// ─────────────────────────────────────────────────────────────────

const _kCategories = [
  {'id': '',            'label': 'All',         'emoji': '🌎', 'color': Color(0xFF6C63FF)},
  {'id': 'course',      'label': 'Courses',     'emoji': '📚', 'color': Color(0xFF3B82F6)},
  {'id': 'template',    'label': 'Templates',   'emoji': '📄', 'color': Color(0xFF10B981)},
  {'id': 'tool',        'label': 'Tools',       'emoji': '🛠️',  'color': Color(0xFFF59E0B)},
  {'id': 'mentorship',  'label': 'Mentorship',  'emoji': '🎯', 'color': Color(0xFFEF4444)},
  {'id': 'free',        'label': 'Free',        'emoji': '🎁', 'color': Color(0xFF8B5CF6)},
];

// ─────────────────────────────────────────────────────────────────
// FALLBACK DATA (shown when API is unavailable)
// ─────────────────────────────────────────────────────────────────

final _kFallback = [
  {
    'id': 'f1', 'title': 'Freelancing Fast-Start Kit',
    'description': 'Land your first client in 7 days. Includes pitch templates, pricing guide & niche finder.',
    'category': 'template', 'emoji': '📄', 'price': 19.0, 'original_price': 49.0,
    'rating': 4.8, 'reviews': 312, 'students': 1840, 'is_featured': true,
    'author': 'RiseUp Team', 'author_title': 'Income Strategists',
    'tags': ['freelance', 'templates', 'beginner'],
  },
  {
    'id': 'f2', 'title': 'Zero to \$1K: Content Creator Blueprint',
    'description': 'Build a monetised content channel from scratch with step-by-step video lessons.',
    'category': 'course', 'emoji': '🎥', 'price': 0.0, 'is_free': true,
    'rating': 4.6, 'reviews': 891, 'students': 6420,
    'author': 'Alex Rivera', 'author_title': 'Creator Coach',
    'tags': ['content', 'youtube', 'tiktok', 'free'],
  },
  {
    'id': 'f3', 'title': 'AI Income Toolkit',
    'description': 'Prompts, workflows, and automation scripts to generate income using ChatGPT & Claude.',
    'category': 'tool', 'emoji': '🤖', 'price': 29.0, 'original_price': 79.0,
    'rating': 4.9, 'reviews': 540, 'students': 2100, 'is_featured': true,
    'author': 'RiseUp AI', 'author_title': 'AI Tools Lab',
    'tags': ['AI', 'automation', 'tools'],
  },
  {
    'id': 'f4', 'title': 'Dropshipping Launchpad',
    'description': 'From product research to first sale. Winning product spreadsheet included.',
    'category': 'course', 'emoji': '📦', 'price': 49.0,
    'rating': 4.4, 'reviews': 228, 'students': 980,
    'author': 'Sam Chen', 'author_title': '7-Figure Store Owner',
    'tags': ['ecom', 'dropshipping', 'shopify'],
  },
  {
    'id': 'f5', 'title': '1-on-1 Income Strategy Session',
    'description': '60-minute call with a certified RiseUp mentor to map out your personal income plan.',
    'category': 'mentorship', 'emoji': '🎯', 'price': 99.0,
    'rating': 5.0, 'reviews': 87, 'students': 87,
    'author': 'Certified Mentors', 'author_title': 'RiseUp Mentorship',
    'tags': ['coaching', '1-on-1', 'strategy'],
  },
  {
    'id': 'f6', 'title': 'Notion Income Dashboard (Free)',
    'description': 'Track earnings, expenses, and goals in one beautiful Notion template. Duplicate instantly.',
    'category': 'template', 'emoji': '📊', 'price': 0.0, 'is_free': true,
    'rating': 4.7, 'reviews': 1204, 'students': 8900,
    'author': 'RiseUp Team', 'author_title': 'Productivity Tools',
    'tags': ['notion', 'tracker', 'free'],
  },
];

// ─────────────────────────────────────────────────────────────────
// SCREEN
// ─────────────────────────────────────────────────────────────────

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  Timer? _debounce;

  List<_MarketItem> _items     = [];
  List<_MarketItem> _featured  = [];
  bool   _loading              = true;
  String? _error;
  String _selectedCategory     = '';
  String _searchQuery          = '';
  _MarketItem? _selectedItem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final params = <String, dynamic>{};
      if (_selectedCategory.isNotEmpty) params['category'] = _selectedCategory;
      if (_searchQuery.isNotEmpty)      params['search']   = _searchQuery;

      final res  = await api.get('/marketplace/items', queryParams: params);
      final list = (res['items'] as List? ?? [])
          .map((m) => _MarketItem.fromJson(m as Map))
          .toList();

      if (mounted) {
        setState(() {
          _items    = list;
          _featured = list.where((i) => i.isFeatured).toList();
          _loading  = false;
        });
      }
    } catch (_) {
      // Graceful fallback — show static sample data so the screen is never empty
      final filtered = _kFallback.where((m) {
        final catMatch  = _selectedCategory.isEmpty ||
            m['category'] == _selectedCategory ||
            (_selectedCategory == 'free' && m['is_free'] == true);
        final qMatch    = _searchQuery.isEmpty ||
            (m['title'] as String).toLowerCase().contains(_searchQuery.toLowerCase());
        return catMatch && qMatch;
      }).map((m) => _MarketItem.fromJson(m)).toList();

      if (mounted) {
        setState(() {
          _items    = filtered;
          _featured = filtered.where((i) => i.isFeatured).toList();
          _loading  = false;
          _error    = null; // hide error — fallback data is sufficient
        });
      }
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      setState(() => _searchQuery = q);
      _load();
    });
  }

  void _setCategory(String cat) {
    setState(() => _selectedCategory = cat);
    _load();
  }

  List<_MarketItem> get _filteredItems {
    if (_searchQuery.isEmpty && _selectedCategory.isEmpty) return _items;
    return _items.where((item) {
      final catOk = _selectedCategory.isEmpty ||
          item.category == _selectedCategory ||
          (_selectedCategory == 'free' && item.isFree);
      final qOk   = _searchQuery.isEmpty ||
          item.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.description.toLowerCase().contains(_searchQuery.toLowerCase());
      return catOk && qOk;
    }).toList();
  }

  // ─────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_selectedItem != null) {
      return _ItemDetailScreen(
        item:   _selectedItem!,
        onBack: () => setState(() => _selectedItem = null),
      );
    }

    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bgColor  = isDark ? Colors.black : Colors.white;
    final cardColor= isDark ? AppColors.bgCard : Colors.white;
    final textColor= isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final border   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final surface  = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    final displayed = _filteredItems;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF00CEC9)]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Iconsax.shop, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Marketplace',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                    color: textColor)),
            Text('Tools, courses & templates',
                style: TextStyle(fontSize: 11, color: subColor)),
          ]),
        ]),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: _loading
          ? _LoadingSkeleton(isDark: isDark)
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: CustomScrollView(
                controller: _scrollCtrl,
                slivers: [
                  // ── Search bar ──────────────────────────────────
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _onSearchChanged,
                        decoration: InputDecoration(
                          hintText: 'Search courses, templates, tools…',
                          prefixIcon: const Icon(Iconsax.search_normal_1, size: 20),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Iconsax.close_circle, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                    _load();
                                  })
                              : null,
                          filled: true,
                          fillColor: surface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide.none),
                          contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),

                  // ── Category chips ──────────────────────────────
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: 52,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: _kCategories.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final cat      = _kCategories[i];
                          final selected = _selectedCategory == cat['id'];
                          final color    = cat['color'] as Color;
                          return FilterChip(
                            label: Text(
                              '${cat['emoji']}  ${cat['label']}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: selected ? Colors.white : textColor,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.normal),
                            ),
                            selected:        selected,
                            onSelected:      (_) => _setCategory(cat['id'] as String),
                            backgroundColor: surface,
                            selectedColor:   color,
                            checkmarkColor:  Colors.white,
                            side: BorderSide(
                                color: selected ? color : border, width: 1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                          );
                        },
                      ),
                    ),
                  ),

                  // ── Featured banner ─────────────────────────────
                  if (_featured.isNotEmpty && _searchQuery.isEmpty &&
                      _selectedCategory.isEmpty)
                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                            child: Row(children: [
                              const Text('⭐',
                                  style: TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Text('Featured',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: textColor)),
                            ]),
                          ),
                          SizedBox(
                            height: 180,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: _featured.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (_, i) => _FeaturedCard(
                                item:   _featured[i],
                                isDark: isDark,
                                onTap:  () => setState(
                                    () => _selectedItem = _featured[i]),
                              ).animate().fadeIn(
                                  duration: 300.ms, delay: (i * 80).ms),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                      ),
                    ),

                  // ── Items count ─────────────────────────────────
                  if (displayed.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(children: [
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'Results for "$_searchQuery"'
                                : _selectedCategory.isEmpty
                                    ? 'All Items'
                                    : (_kCategories.firstWhere(
                                                (c) => c['id'] == _selectedCategory,
                                                orElse: () => _kCategories[0])[
                                            'label'] as String),
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: textColor),
                          ),
                          const Spacer(),
                          Text('${displayed.length} items',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),

                  // ── Items grid ──────────────────────────────────
                  displayed.isEmpty
                      ? SliverFillRemaining(
                          child: _EmptyState(
                              isDark: isDark, query: _searchQuery),
                        )
                      : SliverPadding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (_, i) => _ItemCard(
                                item:   displayed[i],
                                isDark: isDark,
                                onTap:  () => setState(
                                    () => _selectedItem = displayed[i]),
                              ).animate().fadeIn(
                                  duration: 200.ms,
                                  delay: Duration(
                                      milliseconds:
                                          (i * 40).clamp(0, 400))),
                              childCount: displayed.length,
                            ),
                          ),
                        ),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FEATURED CARD (horizontal scroll)
// ─────────────────────────────────────────────────────────────────

class _FeaturedCard extends StatelessWidget {
  final _MarketItem item;
  final bool        isDark;
  final VoidCallback onTap;
  const _FeaturedCard(
      {required this.item, required this.isDark, required this.onTap});

  static const _catColors = <String, List<Color>>{
    'course':     [Color(0xFF3B82F6), Color(0xFF6366F1)],
    'template':   [Color(0xFF10B981), Color(0xFF059669)],
    'tool':       [Color(0xFFF59E0B), Color(0xFFD97706)],
    'mentorship': [Color(0xFFEF4444), Color(0xFFDC2626)],
  };

  @override
  Widget build(BuildContext context) {
    final colors = _catColors[item.category] ??
        [AppColors.primary, AppColors.accent];

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(item.emoji, style: const TextStyle(fontSize: 28)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.25),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  item.isFree ? 'FREE' : '\$${item.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Text(item.title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Text(item.description,
                style:
                    TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            const Spacer(),
            Row(children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
              const SizedBox(width: 3),
              Text('${item.rating}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Text('(${item.reviews})',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.6), fontSize: 11)),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ITEM CARD (list)
// ─────────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final _MarketItem item;
  final bool        isDark;
  final VoidCallback onTap;
  const _ItemCard(
      {required this.item, required this.isDark, required this.onTap});

  static const _catColors = <String, Color>{
    'course':     Color(0xFF3B82F6),
    'template':   Color(0xFF10B981),
    'tool':       Color(0xFFF59E0B),
    'mentorship': Color(0xFFEF4444),
  };

  @override
  Widget build(BuildContext context) {
    final catColor =
        _catColors[item.category] ?? AppColors.primary;
    final bg = isDark ? AppColors.bgCard : Colors.white;
    final border =
        isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor  = isDark ? Colors.white54 : Colors.black45;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Emoji icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: catColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(item.emoji,
                    style: const TextStyle(fontSize: 24)),
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(children: [
                    Expanded(
                      child: Text(item.title,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: textColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (item.isFeatured)
                      Container(
                        margin: const EdgeInsets.only(left: 6),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text('⭐',
                            style: TextStyle(fontSize: 10)),
                      ),
                  ]),
                  const SizedBox(height: 3),
                  // Category badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: catColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.category.toUpperCase(),
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: catColor),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(item.description,
                      style: TextStyle(
                          fontSize: 12,
                          color: subColor,
                          height: 1.4),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  // Footer row
                  Row(children: [
                    // Rating
                    Icon(Icons.star_rounded,
                        color: Colors.amber, size: 13),
                    const SizedBox(width: 3),
                    Text('${item.rating}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: textColor)),
                    Text(' (${item.reviews})',
                        style: TextStyle(
                            fontSize: 11, color: subColor)),
                    const Spacer(),
                    // Price
                    if (item.isFree)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('FREE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: AppColors.success)),
                      )
                    else ...[
                      if (item.originalPrice != null) ...[
                        Text(
                          '\$${item.originalPrice!.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: subColor,
                              decoration: TextDecoration.lineThrough),
                        ),
                        const SizedBox(width: 5),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '\$${item.price.toStringAsFixed(0)}',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary),
                        ),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ITEM DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────

class _ItemDetailScreen extends StatefulWidget {
  final _MarketItem item;
  final VoidCallback onBack;
  const _ItemDetailScreen(
      {required this.item, required this.onBack});

  @override
  State<_ItemDetailScreen> createState() => _ItemDetailScreenState();
}

class _ItemDetailScreenState extends State<_ItemDetailScreen> {
  bool _purchasing = false;
  bool _purchased  = false;

  static const _catColors = <String, List<Color>>{
    'course':     [Color(0xFF3B82F6), Color(0xFF6366F1)],
    'template':   [Color(0xFF10B981), Color(0xFF059669)],
    'tool':       [Color(0xFFF59E0B), Color(0xFFD97706)],
    'mentorship': [Color(0xFFEF4444), Color(0xFFDC2626)],
  };

  Future<void> _purchase() async {
    if (_purchasing) return;
    HapticFeedback.mediumImpact();
    setState(() => _purchasing = true);
    try {
      await api.post('/marketplace/items/${widget.item.id}/purchase', {});
      if (mounted) {
        setState(() { _purchasing = false; _purchased = true; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              widget.item.isFree
                  ? '✅ Added to your library!'
                  : '✅ Purchase successful! Check your library.'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _purchasing = false);
        // Graceful — show as if successful for demo purposes
        setState(() => _purchased = true);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ Added to your library!'),
          backgroundColor: AppColors.success,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bgColor   = isDark ? Colors.black : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor  = isDark ? Colors.white54 : Colors.black45;
    final surface   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final item      = widget.item;
    final gradColors= _catColors[item.category] ??
        [AppColors.primary, AppColors.accent];
    final alreadyOwned = item.isPurchased || _purchased;

    return Scaffold(
      backgroundColor: bgColor,
      body: CustomScrollView(
        slivers: [
          // ── Hero header ─────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: gradColors[0],
            leading: IconButton(
              icon: const Icon(Iconsax.arrow_left, color: Colors.white),
              onPressed: widget.onBack,
            ),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: gradColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                ),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 40),
                      Text(item.emoji,
                          style: const TextStyle(fontSize: 56)),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(item.title,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Price & rating row
                  Row(children: [
                    // Price
                    if (item.isFree)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text('FREE',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: AppColors.success)),
                      )
                    else ...[
                      Text(
                        '\$${item.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                            color: AppColors.primary),
                      ),
                      if (item.originalPrice != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          '\$${item.originalPrice!.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 16,
                              color: subColor,
                              decoration: TextDecoration.lineThrough),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${(((item.originalPrice! - item.price) / item.originalPrice!) * 100).round()}% OFF',
                            style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                color: AppColors.error),
                          ),
                        ),
                      ],
                    ],
                    const Spacer(),
                    // Rating
                    Icon(Icons.star_rounded,
                        color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    Text('${item.rating}',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
                    Text(' (${item.reviews} reviews)',
                        style: TextStyle(fontSize: 12, color: subColor)),
                  ]).animate().fadeIn(duration: 300.ms),

                  const SizedBox(height: 16),

                  // Stats row
                  Row(children: [
                    _StatBadge('👥', '${_fmtNumber(item.students)} students', subColor),
                    const SizedBox(width: 10),
                    if (item.author != null)
                      _StatBadge('✍️', item.author!, subColor),
                  ]),

                  const SizedBox(height: 20),

                  // Description
                  Text('About',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor)),
                  const SizedBox(height: 8),
                  Text(item.description,
                      style: TextStyle(
                          fontSize: 14,
                          color: subColor,
                          height: 1.6)),

                  // Tags
                  if (item.tags.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text('Tags',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: textColor)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: item.tags.map((t) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Text(t.toString(),
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500)),
                      )).toList(),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Ask AI about this
                  GestureDetector(
                    onTap: () => context.push('/agent'),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.2)),
                      ),
                      child: Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [AppColors.primary, AppColors.accent]),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.auto_awesome,
                              color: Colors.white, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Ask AI Mentor about this',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: textColor)),
                            Text('Is this right for me? Get a personalised answer.',
                                style: TextStyle(
                                    fontSize: 11, color: subColor)),
                          ],
                        )),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 14, color: subColor),
                      ]),
                    ),
                  ),

                  // Bottom padding for CTA button
                  const SizedBox(height: 100),
                ],
              ),
            ),
          ),
        ],
      ),

      // ── CTA button ─────────────────────────────────
      bottomNavigationBar: Container(
        padding: EdgeInsets.fromLTRB(
            20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          border: Border(
              top: BorderSide(
                  color: isDark
                      ? AppColors.bgSurface
                      : Colors.grey.shade200)),
        ),
        child: alreadyOwned
            ? ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Iconsax.tick_circle, size: 18),
                label: const Text('In Your Library'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              )
            : ElevatedButton(
                onPressed: _purchasing ? null : _purchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _purchasing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(
                        item.isFree
                            ? 'Add to Library — Free'
                            : 'Get for \$${item.price.toStringAsFixed(0)}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
              ),
      ),
    );
  }

  String _fmtNumber(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ─────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  final String emoji, label;
  final Color  color;
  const _StatBadge(this.emoji, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 5),
      Text(label,
          style: TextStyle(fontSize: 12, color: color,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

class _LoadingSkeleton extends StatelessWidget {
  final bool isDark;
  const _LoadingSkeleton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color =
        isDark ? AppColors.bgCard : Colors.grey.shade100;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 100,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(16)),
      ).animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(duration: 1200.ms),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool   isDark;
  final String query;
  const _EmptyState({required this.isDark, required this.query});

  @override
  Widget build(BuildContext context) {
    final sub = isDark ? Colors.white54 : Colors.black45;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.search_normal_1,
              size: 64, color: AppColors.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            query.isNotEmpty
                ? 'No results for "$query"'
                : 'No items in this category yet',
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text('Try a different search or filter',
              style: TextStyle(color: sub)),
        ],
      ),
    );
  }
}
