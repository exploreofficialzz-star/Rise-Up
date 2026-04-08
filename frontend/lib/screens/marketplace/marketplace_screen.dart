// frontend/lib/screens/marketplace/marketplace_screen.dart
// v1.0 — RiseUp Marketplace — Buy · Sell · Services
//
// Features:
//  • Browse listings with filter chips (All / Selling / Wanted / Services)
//  • Search with live query (uses brain internal search)
//  • Create new listing with type, title, description, price, tags
//  • Contact seller via inquiry bottom sheet → api.inquireMarketplaceListing
//  • My Listings tab — view and delete own listings
//  • Brain AI suggestions — complementary users from adaptive profile
//  • "Can't find it? Let AI search the web" → escalates to agent/workflow
//  • Pull-to-refresh, pagination at 80% scroll

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────

class MarketplaceScreen extends StatefulWidget {
  const MarketplaceScreen({super.key});

  @override
  State<MarketplaceScreen> createState() => _MarketplaceScreenState();
}

class _MarketplaceScreenState extends State<MarketplaceScreen>
    with SingleTickerProviderStateMixin {

  late TabController _tab;
  final _searchCtrl  = TextEditingController();
  final _scrollCtrl  = ScrollController();

  // Browse
  List   _listings        = [];
  bool   _loadingListings = true;
  bool   _hasMore         = true;
  int    _offset          = 0;
  bool   _paginating      = false;
  String _filter          = 'all';
  String _query           = '';

  // My listings
  List _myListings  = [];
  bool _loadingMine = true;

  // Brain AI suggestions
  List _complementary = [];

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _tab.addListener(() {
      if (!_tab.indexIsChanging) return;
      if (_tab.index == 1 && _myListings.isEmpty) _loadMyListings();
    });
    _scrollCtrl.addListener(_onScroll);
    _loadListings(refresh: true);
    _loadComplementary();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent * 0.8 &&
        !_paginating &&
        _hasMore) {
      _loadListings();
    }
  }

  // ── Data loaders ─────────────────────────────────────────────

  Future<void> _loadListings({bool refresh = false}) async {
    if (_paginating && !refresh) return;
    if (refresh) {
      setState(() {
        _offset          = 0;
        _hasMore         = true;
        _loadingListings = true;
      });
    }
    setState(() => _paginating = true);
    try {
      final d = await api.getMarketplaceListings(
        listingType: _filter == 'all' ? null : _filter,
        search:      _query.isNotEmpty ? _query : null,
        limit:       20,
        offset:      _offset,
      );
      final items = (d['listings'] as List?) ?? [];
      if (mounted) {
        setState(() {
          if (refresh) _listings = items;
          else         _listings = [..._listings, ...items];
          _offset          += items.length;
          _hasMore          = items.length == 20;
          _loadingListings  = false;
          _paginating       = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loadingListings = false; _paginating = false; });
    }
  }

  Future<void> _loadMyListings() async {
    setState(() => _loadingMine = true);
    try {
      final d = await api.getMyMarketplaceListings();
      if (mounted) setState(() {
        _myListings  = (d['listings'] as List?) ?? [];
        _loadingMine = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMine = false);
    }
  }

  Future<void> _loadComplementary() async {
    try {
      final list = await api.getComplementaryUsers(limit: 3);
      if (mounted) setState(() => _complementary = list);
    } catch (_) {}
  }

  // ── Filter / Search ───────────────────────────────────────────

  void _applyFilter(String f) {
    if (_filter == f) return;
    setState(() => _filter = f);
    _loadListings(refresh: true);
  }

  void _applySearch(String q) {
    setState(() => _query = q);
    _loadListings(refresh: true);
  }

  // ── Inquiry ───────────────────────────────────────────────────

  Future<void> _inquire(Map listing) async {
    final ctrl   = TextEditingController();
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final sent = await showModalBottomSheet<bool>(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sh) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(sh).viewInsets.bottom,
            left: 20, right: 20, top: 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),
          Row(children: [
            _TypeBadge(type: listing['listing_type']?.toString() ?? 'sell'),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                listing['title']?.toString() ?? 'Listing',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: isDark ? Colors.white : Colors.black87),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            maxLines:   4,
            autofocus:  true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText:  'Write your message or offer…',
              hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.black38),
              filled:    true,
              fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border:    OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: () => Navigator.pop(sh, true),
              child: const Text('Send Message',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );

    if (sent == true && ctrl.text.trim().isNotEmpty && mounted) {
      try {
        await api.inquireMarketplaceListing(
            listing['id']?.toString() ?? '', ctrl.text.trim());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:         Text('Message sent! 🎉'),
              backgroundColor: AppColors.success,
              duration:        Duration(seconds: 2)));
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:         Text('Failed to send. Try again.'),
              backgroundColor: AppColors.error,
              duration:        Duration(seconds: 2)));
        }
      }
    }
  }

  // ── Delete my listing ─────────────────────────────────────────

  Future<void> _delete(String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title:   const Text('Remove listing?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove',
                  style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (ok == true) {
      try {
        await api.deleteMarketplaceListing(id);
        if (mounted) {
          setState(() {
            _myListings.removeWhere((l) => l['id']?.toString() == id);
            _listings.removeWhere((l) => l['id']?.toString() == id);
          });
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Listing removed'),
              duration: Duration(seconds: 2)));
        }
      } catch (_) {}
    }
  }

  // ── Create listing ────────────────────────────────────────────

  void _showCreate() {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Theme.of(context).brightness == Brightness.dark
          ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => _CreateSheet(
        onCreated: (listing) {
          if (mounted) setState(() {
            _listings.insert(0, listing);
            _myListings.insert(0, listing);
          });
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? Colors.black : Colors.white;
    final card    = isDark ? AppColors.bgCard : Colors.white;
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final border  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text    = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor:  card,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Iconsax.arrow_left, color: sub),
          onPressed: () => context.pop(),
        ),
        title: const Text('Marketplace',
            style: TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.w800,
                color:      AppColors.primary)),
        actions: [
          IconButton(
            icon:    const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.primary, size: 24),
            onPressed: _showCreate,
            tooltip: 'Post a listing',
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller:          _tab,
              labelColor:          AppColors.primary,
              unselectedLabelColor: sub,
              indicatorColor:      AppColors.primary,
              indicatorWeight:     2.5,
              labelStyle: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Browse'), Tab(text: 'My Listings')],
            ),
          ]),
        ),
      ),
      body: TabBarView(controller: _tab, children: [

        // ── 0: BROWSE ───────────────────────────────────────────
        Column(children: [
          // Search + filter
          Container(
            color: card,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(children: [
              // Search field
              TextField(
                controller: _searchCtrl,
                style:      TextStyle(fontSize: 14, color: text),
                onSubmitted: _applySearch,
                onChanged:   (v) { if (v.isEmpty) _applySearch(''); },
                decoration: InputDecoration(
                  hintText:  'Search listings…',
                  hintStyle: TextStyle(color: sub, fontSize: 13),
                  filled:    true,
                  fillColor: surface,
                  border:    OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:  BorderSide.none),
                  prefixIcon: Icon(Iconsax.search_normal, color: sub, size: 18),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close, color: sub, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            _applySearch('');
                          })
                      : null,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
              const SizedBox(height: 10),
              // Filter chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _FilterChip(label: '🏪 All',      active: _filter == 'all',     onTap: () => _applyFilter('all')),
                  const SizedBox(width: 8),
                  _FilterChip(label: '💰 Selling',  active: _filter == 'sell',    onTap: () => _applyFilter('sell')),
                  const SizedBox(width: 8),
                  _FilterChip(label: '🛒 Wanted',   active: _filter == 'buy',     onTap: () => _applyFilter('buy')),
                  const SizedBox(width: 8),
                  _FilterChip(label: '🔧 Services', active: _filter == 'service', onTap: () => _applyFilter('service')),
                ]),
              ),
            ]),
          ),
          Divider(height: 1, color: border),

          // Brain AI suggestions
          if (_complementary.isNotEmpty) _BrainSuggestions(
            users:  _complementary,
            isDark: isDark,
            text:   text,
            sub:    sub,
            card:   card,
            border: border,
          ),

          // Listing content
          Expanded(
            child: _loadingListings
                ? const Center(child: CircularProgressIndicator(
                    color: AppColors.primary, strokeWidth: 2))
                : _listings.isEmpty
                    ? _EmptyBrowse(isDark: isDark, sub: sub, text: text,
                        onPost:         _showCreate,
                        onAiSearch:     () => context.push('/agent'),
                        onWorkflow:     () => context.push('/workflow/new'),
                        query:          _query)
                    : RefreshIndicator(
                        onRefresh: () => _loadListings(refresh: true),
                        color: AppColors.primary,
                        child: ListView.separated(
                          controller:  _scrollCtrl,
                          padding:     const EdgeInsets.all(16),
                          itemCount:   _listings.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (ctx, i) {
                            if (i == _listings.length) {
                              return const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: CircularProgressIndicator(
                                      color: AppColors.primary, strokeWidth: 2),
                                ),
                              );
                            }
                            final item = _listings[i] as Map;
                            return _ListingCard(
                              listing:   item,
                              isDark:    isDark,
                              text:      text,
                              sub:       sub,
                              index:     i,
                              onInquire: () => _inquire(item),
                            );
                          },
                        ),
                      ),
          ),

          // Can't find it banner
          if (!_loadingListings && _query.isNotEmpty && _listings.isEmpty)
            const SizedBox.shrink()
          else if (!_loadingListings && !_hasMore && _listings.isNotEmpty)
            _CantFindBanner(
              isDark:     isDark,
              sub:        sub,
              onWorkflow: () => context.push('/workflow/new'),
              onAgent:    () => context.push('/agent'),
            ),
        ]),

        // ── 1: MY LISTINGS ──────────────────────────────────────
        _loadingMine
            ? const Center(child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2))
            : _myListings.isEmpty
                ? _EmptyMine(isDark: isDark, sub: sub, text: text,
                    onPost: _showCreate)
                : RefreshIndicator(
                    onRefresh: _loadMyListings,
                    color: AppColors.primary,
                    child: ListView.separated(
                      padding:      const EdgeInsets.all(16),
                      itemCount:    _myListings.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        final item = _myListings[i] as Map;
                        return _ListingCard(
                          listing:  item,
                          isDark:   isDark,
                          text:     text,
                          sub:      sub,
                          index:    i,
                          isOwner:  true,
                          onDelete: () => _delete(item['id']?.toString() ?? ''),
                        );
                      },
                    ),
                  ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// LISTING CARD
// ─────────────────────────────────────────────────────────────────

class _ListingCard extends StatelessWidget {
  final Map          listing;
  final bool         isDark;
  final Color        text, sub;
  final int          index;
  final bool         isOwner;
  final VoidCallback? onInquire;
  final VoidCallback? onDelete;

  const _ListingCard({
    required this.listing,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.index,
    this.isOwner  = false,
    this.onInquire,
    this.onDelete,
  });

  Color get _typeColor {
    switch (listing['listing_type']?.toString()) {
      case 'sell':    return AppColors.success;
      case 'buy':     return AppColors.primary;
      case 'service': return const Color(0xFF9B59B6);
      default:        return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title    = listing['title']?.toString() ?? '';
    final desc     = listing['description']?.toString() ?? '';
    final price    = listing['price']?.toString();
    final currency = listing['currency']?.toString() ?? 'USD';
    final country  = listing['country']?.toString() ?? '';
    final tags     = (listing['tags'] as List?)?.cast<String>() ?? [];
    final profile  = (listing['profiles'] as Map?)?.cast<String, dynamic>() ?? {};
    final seller   = profile['full_name']?.toString()
                  ?? listing['seller_name']?.toString()
                  ?? 'RiseUp Member';

    return Container(
      decoration: BoxDecoration(
        color:  isDark ? AppColors.bgCard : const Color(0xFFF9F9F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _typeColor.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
          child: Row(children: [
            _TypeBadge(type: listing['listing_type']?.toString() ?? 'sell'),
            const Spacer(),
            if (country.isNotEmpty)
              Text(country, style: TextStyle(fontSize: 11, color: sub)),
            if (isOwner) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: Icon(Iconsax.trash, size: 16, color: AppColors.error),
              ),
            ],
          ]),
        ),

        // ── Title + description ──────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700, color: text),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(desc,
                  style: TextStyle(fontSize: 12, color: sub, height: 1.4),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ]),
        ),

        // ── Tags ─────────────────────────────────────────────────
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Wrap(spacing: 6, runSpacing: 4, children: [
              for (final tag in tags.take(4))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(tag,
                      style: TextStyle(fontSize: 10, color: sub)),
                ),
            ]),
          ),
        ],

        // ── Price + seller + CTA ─────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(children: [
            // Price
            if (price != null && price.isNotEmpty)
              Text('$currency $price',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800,
                      color: _typeColor))
            else
              Text('Price on request',
                  style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(width: 8),

            // Seller avatar + name
            CircleAvatar(
              radius: 10,
              backgroundColor: _typeColor.withOpacity(0.15),
              child: Text(
                seller.isNotEmpty ? seller[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                    color: _typeColor),
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(seller,
                  style: TextStyle(fontSize: 11, color: sub),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),

            // CTA
            if (!isOwner && onInquire != null)
              GestureDetector(
                onTap: () { HapticFeedback.mediumImpact(); onInquire!(); },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                        colors: [_typeColor, _typeColor.withOpacity(0.7)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Contact',
                      style: TextStyle(color: Colors.white, fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
              ),

            if (isOwner)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: _typeColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text('Active',
                    style: TextStyle(
                        fontSize: 11, color: _typeColor,
                        fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ]),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 50));
  }
}

// ─────────────────────────────────────────────────────────────────
// TYPE BADGE
// ─────────────────────────────────────────────────────────────────

class _TypeBadge extends StatelessWidget {
  final String type;
  const _TypeBadge({required this.type});

  Color get _color {
    switch (type) {
      case 'sell':    return AppColors.success;
      case 'buy':     return AppColors.primary;
      case 'service': return const Color(0xFF9B59B6);
      default:        return AppColors.textMuted;
    }
  }

  String get _label {
    switch (type) {
      case 'sell':    return '💰 FOR SALE';
      case 'buy':     return '🛒 WANTED';
      case 'service': return '🔧 SERVICE';
      default:        return '📦 LISTING';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: _color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(_label,
          style: TextStyle(
              fontSize: 9, color: _color, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FILTER CHIP
// ─────────────────────────────────────────────────────────────────

class _FilterChip extends StatelessWidget {
  final String       label;
  final bool         active;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? AppColors.primary
              : AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active
                  ? AppColors.primary
                  : AppColors.primary.withOpacity(0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: active ? Colors.white : AppColors.primary)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// BRAIN SUGGESTIONS BANNER
// ─────────────────────────────────────────────────────────────────

class _BrainSuggestions extends StatelessWidget {
  final List  users;
  final bool  isDark;
  final Color text, sub, card, border;

  const _BrainSuggestions({
    required this.users,
    required this.isDark,
    required this.text,
    required this.sub,
    required this.card,
    required this.border,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: card,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 13),
          const SizedBox(width: 6),
          Text('AI matched for you',
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: AppColors.primary)),
        ]),
        const SizedBox(height: 8),
        SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection:  Axis.horizontal,
            itemCount:        users.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final u    = users[i] as Map;
              final name = u['full_name']?.toString() ?? 'User';
              final type = u['match_type']?.toString() ?? 'match';
              final typeLabel = type == 'buyer' ? 'BUYER'
                             : type == 'service_provider' ? 'SERVICE'
                             : 'MATCH';
              final typeColor = type == 'buyer' ? AppColors.success
                              : type == 'service_provider' ? const Color(0xFF9B59B6)
                              : AppColors.primary;
              return GestureDetector(
                onTap: () {
                  if (u['user_id'] != null) {
                    ctx.push('/user-profile/${u['user_id']}');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color:  typeColor.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: typeColor.withOpacity(0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: typeColor.withOpacity(0.15),
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 13,
                            fontWeight: FontWeight.w800, color: typeColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.split(' ').first,
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600,
                                color: text)),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: typeColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(4)),
                          child: Text(typeLabel,
                              style: TextStyle(
                                  fontSize: 8, fontWeight: FontWeight.w700,
                                  color: typeColor)),
                        ),
                      ],
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
        Divider(height: 12, color: border),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// EMPTY STATES
// ─────────────────────────────────────────────────────────────────

class _EmptyBrowse extends StatelessWidget {
  final bool         isDark;
  final Color        sub, text;
  final String       query;
  final VoidCallback onPost, onAiSearch, onWorkflow;

  const _EmptyBrowse({
    required this.isDark,
    required this.sub,
    required this.text,
    required this.query,
    required this.onPost,
    required this.onAiSearch,
    required this.onWorkflow,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🏪', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 14),
          Text(
            query.isNotEmpty
                ? 'No listings match "$query"'
                : 'No listings yet',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: text),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            query.isNotEmpty
                ? 'Try a different search or let AI find it for you'
                : 'Be the first to post something in the community',
            style: TextStyle(fontSize: 13, color: sub, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Post listing
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              icon: const Icon(Icons.add, color: Colors.white, size: 18),
              label: const Text('Post a Listing',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700)),
              onPressed: onPost,
            ),
          ),
          const SizedBox(height: 10),

          // AI search the web
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              icon: const Icon(Icons.travel_explore_rounded,
                  color: AppColors.primary, size: 18),
              label: const Text('Search the Web with AI',
                  style: TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700)),
              onPressed: onAiSearch,
            ),
          ),
          const SizedBox(height: 10),

          // Workflow engine
          GestureDetector(
            onTap: onWorkflow,
            child: Text('Or use the Workflow Engine →',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _EmptyMine extends StatelessWidget {
  final bool         isDark;
  final Color        sub, text;
  final VoidCallback onPost;

  const _EmptyMine({
    required this.isDark,
    required this.sub,
    required this.text,
    required this.onPost,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('📋', style: TextStyle(fontSize: 52)),
          const SizedBox(height: 14),
          Text('No listings yet',
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 8),
          Text('Post something to sell, find a buyer, or offer a service',
              style: TextStyle(fontSize: 13, color: sub, height: 1.5),
              textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 13),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Post Your First Listing',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
            onPressed: onPost,
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// CAN'T FIND BANNER
// ─────────────────────────────────────────────────────────────────

class _CantFindBanner extends StatelessWidget {
  final bool         isDark;
  final Color        sub;
  final VoidCallback onWorkflow, onAgent;

  const _CantFindBanner({
    required this.isDark,
    required this.sub,
    required this.onWorkflow,
    required this.onAgent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF6C5CE7), Color(0xFF0984E3)]),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(children: [
        const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Can't find what you need?",
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700,
                    fontSize: 13)),
            Text('Let AI search the web or run a full workflow',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.8), fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 8),
        Column(children: [
          GestureDetector(
            onTap: onWorkflow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('Workflow',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onAgent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10)),
              child: const Text('AI Agent',
                  style: TextStyle(
                      color: Colors.white, fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// CREATE LISTING BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────

class _CreateSheet extends StatefulWidget {
  final Function(Map) onCreated;
  const _CreateSheet({required this.onCreated});

  @override
  State<_CreateSheet> createState() => _CreateSheetState();
}

class _CreateSheetState extends State<_CreateSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl  = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _tagsCtrl  = TextEditingController();

  String _type     = 'sell';
  String _currency = 'USD';
  bool   _loading  = false;
  String _error    = '';

  static const _currencies = ['USD','NGN','GHS','KES','ZAR','GBP','EUR','INR'];
  static const _types = [
    ('sell',    '💰 I am selling something'),
    ('buy',     '🛒 I am looking to buy'),
    ('service', '🔧 I offer a service'),
  ];

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    final desc  = _descCtrl.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Title is required');
      return;
    }
    setState(() { _loading = true; _error = ''; });
    try {
      final tags = _tagsCtrl.text
          .split(',')
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      final result = await api.createMarketplaceListing({
        'listing_type': _type,
        'title':        title,
        'description':  desc,
        'price':        _priceCtrl.text.trim().isEmpty ? null : _priceCtrl.text.trim(),
        'currency':     _currency,
        'tags':         tags,
      });

      final listing = (result['listing'] as Map?) ?? result;
      if (mounted) {
        widget.onCreated(listing);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Listing posted! 🎉'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error   = 'Failed to post. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _tagsCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text   = isDark ? Colors.white : Colors.black87;
    final sub    = isDark ? Colors.white54 : Colors.black45;
    final fill   = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 20, right: 20, top: 20),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),
          Text('Post a Listing',
              style: TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: text)),
          const SizedBox(height: 18),

          // Listing type
          ...List.generate(_types.length, (i) {
            final (val, label) = _types[i];
            return GestureDetector(
              onTap: () => setState(() => _type = val),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _type == val
                      ? AppColors.primary.withOpacity(0.1)
                      : fill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _type == val
                          ? AppColors.primary
                          : Colors.transparent,
                      width: 1.5),
                ),
                child: Row(children: [
                  Text(label,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: _type == val ? AppColors.primary : text)),
                  const Spacer(),
                  if (_type == val)
                    const Icon(Icons.check_circle_rounded,
                        color: AppColors.primary, size: 18),
                ]),
              ),
            );
          }),

          const SizedBox(height: 6),

          // Title
          _Field(
              ctrl: _titleCtrl, hint: 'Title (e.g. "Used MacBook M1 for sale")',
              isDark: isDark, fill: fill, text: text),
          const SizedBox(height: 10),

          // Description
          _Field(
              ctrl: _descCtrl, hint: 'Description (condition, specs, details…)',
              isDark: isDark, fill: fill, text: text, maxLines: 3),
          const SizedBox(height: 10),

          // Price + currency
          Row(children: [
            Expanded(
              child: _Field(
                  ctrl: _priceCtrl, hint: 'Price (optional)',
                  isDark: isDark, fill: fill, text: text,
                  keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              height: 50,
              decoration: BoxDecoration(
                  color: fill, borderRadius: BorderRadius.circular(12)),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _currency,
                  dropdownColor: isDark ? AppColors.bgCard : Colors.white,
                  style: TextStyle(color: text, fontSize: 13),
                  items: _currencies.map((c) => DropdownMenuItem(
                      value: c,
                      child: Text(c))).toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _currency = v);
                  },
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),

          // Tags
          _Field(
              ctrl: _tagsCtrl,
              hint: 'Tags (comma-separated: laptop, electronics, tech)',
              isDark: isDark, fill: fill, text: text),
          const SizedBox(height: 6),

          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error,
                  style: const TextStyle(
                      color: AppColors.error, fontSize: 12)),
            ),

          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: _loading ? null : _submit,
              child: _loading
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Post Listing',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700,
                          fontSize: 15)),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String               hint;
  final bool                 isDark;
  final Color                fill, text;
  final int                  maxLines;
  final TextInputType        keyboardType;

  const _Field({
    required this.ctrl,
    required this.hint,
    required this.isDark,
    required this.fill,
    required this.text,
    this.maxLines    = 1,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller:   ctrl,
      maxLines:     maxLines,
      keyboardType: keyboardType,
      style:        TextStyle(fontSize: 14, color: text),
      decoration: InputDecoration(
        hintText:  hint,
        hintStyle: TextStyle(
            color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
        filled:    true,
        fillColor: fill,
        border:    OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:  BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
      ),
    );
  }
}
