import 'package:flutter/material.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const map = <String, Map<String, dynamic>>{
      'survival': {'emoji': '🌱', 'label': 'Survival Mode', 'color': Color(0xFFFF6B35)},
      'earning':  {'emoji': '💰', 'label': 'Earning',       'color': Color(0xFF43E97B)},
      'stability':{'emoji': '⚡', 'label': 'Stability',     'color': Color(0xFF4FACFE)},
      'growing':  {'emoji': '📈', 'label': 'Growing',       'color': Color(0xFF6C63FF)},
      'growth':   {'emoji': '📈', 'label': 'Growing',       'color': Color(0xFF6C63FF)},
      'wealth':   {'emoji': '👑', 'label': 'Wealth',        'color': Color(0xFFFFD700)},
      'legacy':   {'emoji': '🏛️', 'label': 'Legacy',       'color': Color(0xFF9B59B6)},
    };
    return map[stage.toLowerCase()] ?? map['survival']!;
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabCtrl;

  Map<String, dynamic> _profile = {};
  List _posts      = [];
  List _likedPosts = [];
  bool _loading    = true;
  bool _isRefreshing = false;

  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isPremium  = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
    _loadAd();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabCtrl.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadAd();
  }

  Future<void> _loadAd() async {
    if (_isPremium) return;
    try {
      final ad = BannerAd(
        adUnitId: Platform.isAndroid
            ? AppConstants.androidBannerAdUnitId
            : AppConstants.iosBannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() { _bannerAd = ad as BannerAd; _isAdLoaded = true; });
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted) setState(() => _isAdLoaded = false);
          },
        ),
      );
      await ad.load();
    } catch (_) {}
  }

  Future<void> _load() async {
    if (_isRefreshing) return;
    if (mounted) setState(() { if (!_isRefreshing) _loading = true; });

    try {
      final userId = await api.getUserId() ?? '';
      if (userId.isEmpty) throw Exception('Not authenticated');

      final results = await Future.wait([
        api.getProfile(),
        api.getUserPosts(userId),
        api.getLikedPosts(userId),
      ]);

      if (mounted) {
        setState(() {
          final profileRes = results[0] as Map? ?? {};
          final profileData = (profileRes['profile'] as Map?)?.cast<String, dynamic>() ?? {};
          // FIX: merge stats so followers/following counts are available
          final statsData   = (profileRes['stats'] as Map?)?.cast<String, dynamic>() ?? {};

          _profile = {
            ...profileData,
            // Only inject from stats if profile dict doesn't already carry them
            'followers_count': profileData['followers_count']
                ?? statsData['followers']
                ?? statsData['followers_count']
                ?? 0,
            'following_count': profileData['following_count']
                ?? statsData['following']
                ?? statsData['following_count']
                ?? 0,
          };

          _posts      = (results[1] as Map?)?['posts'] as List? ?? [];
          _likedPosts = (results[2] as Map?)?['posts'] as List? ?? [];

          _isPremium  = _profile['subscription_tier'] == 'premium'
                     || _profile['is_premium'] == true;
          _loading    = false;
          _isRefreshing = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _isRefreshing = false; });
    }
  }

  Future<void> _refresh() async {
    setState(() => _isRefreshing = true);
    await _load();
  }

  String _fmt(dynamic n) {
    final v = (n as num?)?.toInt() ?? 0;
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }

  String _timeAgo(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1)  return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    if (d.inDays < 7)     return '${d.inDays}d ago';
    if (d.inDays < 30)    return '${(d.inDays / 7).floor()}w ago';
    return '${(d.inDays / 30).floor()}mo ago';
  }

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      context.pop();
    } else {
      context.go('/home');
    }
  }

  void _shareProfile() {
    final id   = _profile['id']?.toString() ?? '';
    final link = 'riseup.app/u/$id';
    Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      HapticFeedback.lightImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Link copied: $link'),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  // ── Like toggle on profile posts ─────────────────────────────────────────
  Future<void> _toggleLike(Map post) async {
    final currentlyLiked = post['is_liked'] == true;
    final currentCount   = (post['likes_count'] as num?)?.toInt() ?? 0;

    // Optimistic update
    setState(() {
      post['is_liked']     = !currentlyLiked;
      post['likes_count']  = currentlyLiked
          ? (currentCount - 1).clamp(0, 999999)
          : currentCount + 1;
    });

    try {
      final res = await api.toggleLike(post['id'].toString());
      if (mounted) {
        setState(() {
          post['is_liked']    = res['liked'] == true;
          post['likes_count'] = res['likes_count'] ?? post['likes_count'];
        });
      }
    } catch (_) {
      // Revert on failure
      if (mounted) {
        setState(() {
          post['is_liked']    = currentlyLiked;
          post['likes_count'] = currentCount;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final bgColor      = isDark ? Colors.black : Colors.white;
    final cardColor    = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor    = isDark ? Colors.white : Colors.black87;
    final subColor     = isDark ? Colors.white54 : Colors.black45;

    final name      = _profile['full_name']?.toString() ?? 'Your Name';
    final stage     = _profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);

    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet    = screenWidth > 600;
    final isDesktop   = screenWidth > 1024;

    if (_loading) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Iconsax.arrow_left, color: textColor),
          onPressed: _goBack,
        ),
        title: Text(name,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.setting_2, color: textColor, size: 22),
            onPressed: () => context.push('/settings'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        color: AppColors.primary,
        child: Column(children: [
          if (!_isPremium && _isAdLoaded && _bannerAd != null)
            Container(
              color: cardColor,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: SizedBox(
                  width:  _bannerAd!.size.width.toDouble(),
                  height: _bannerAd!.size.height.toDouble(),
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),
            ),
          Expanded(
            child: _buildContent(
              isDark: isDark, isTablet: isTablet, isDesktop: isDesktop,
              bgColor: bgColor, cardColor: cardColor, surfaceColor: surfaceColor,
              borderColor: borderColor, textColor: textColor, subColor: subColor,
              name: name, stage: stage, stageInfo: stageInfo,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildContent({
    required bool isDark, required bool isTablet, required bool isDesktop,
    required Color bgColor, required Color cardColor, required Color surfaceColor,
    required Color borderColor, required Color textColor, required Color subColor,
    required String name, required String stage,
    required Map<String, dynamic> stageInfo,
  }) {
    if (isTablet || isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: isDesktop ? 380 : 320,
            decoration: BoxDecoration(
              color: cardColor,
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: _buildProfileHeader(
                isDark: isDark, cardColor: cardColor, surfaceColor: surfaceColor,
                borderColor: borderColor, textColor: textColor, subColor: subColor,
                name: name, stage: stage, stageInfo: stageInfo, isCompact: false,
              ),
            ),
          ),
          Expanded(
            child: _buildPostsSection(
              isDark: isDark, cardColor: cardColor, borderColor: borderColor,
              textColor: textColor, subColor: subColor,
            ),
          ),
        ],
      );
    }

    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _buildProfileHeader(
            isDark: isDark, cardColor: cardColor, surfaceColor: surfaceColor,
            borderColor: borderColor, textColor: textColor, subColor: subColor,
            name: name, stage: stage, stageInfo: stageInfo, isCompact: true,
          ),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(
            TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: subColor,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              tabs: const [
                Tab(icon: Icon(Iconsax.grid_1, size: 20)),
                Tab(icon: Icon(Iconsax.heart,  size: 20)),
              ],
            ),
            cardColor, borderColor,
          ),
        ),
        SliverFillRemaining(
          child: TabBarView(
            controller: _tabCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              _buildPostsList(
                posts: _posts, isDark: isDark, cardColor: cardColor,
                borderColor: borderColor, textColor: textColor, subColor: subColor,
                emptyMessage: 'No posts yet', isLikedTab: false,
              ),
              _buildPostsList(
                posts: _likedPosts, isDark: isDark, cardColor: cardColor,
                borderColor: borderColor, textColor: textColor, subColor: subColor,
                emptyMessage: 'No liked posts yet', isLikedTab: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileHeader({
    required bool isDark, required Color cardColor, required Color surfaceColor,
    required Color borderColor, required Color textColor, required Color subColor,
    required String name, required String stage,
    required Map<String, dynamic> stageInfo, required bool isCompact,
  }) {
    final isPremium = _profile['subscription_tier'] == 'premium'
                   || _profile['is_premium'] == true;

    // FIX: correctly read followers/following from merged profile dict
    final followersCount = _profile['followers_count'] ?? 0;
    final followingCount = _profile['following_count'] ?? 0;

    return Container(
      color: cardColor,
      padding: EdgeInsets.all(isCompact ? 20 : 24),
      child: Column(
        crossAxisAlignment: isCompact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          isCompact
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatar(name: name, avatarUrl: _profile['avatar_url']?.toString(),
                        cardColor: cardColor, isCompact: true),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _StatCol(_fmt(_posts.length), 'Posts', textColor, subColor),
                          _StatCol(_fmt(followersCount), 'Followers', textColor, subColor),
                          _StatCol(_fmt(followingCount), 'Following', textColor, subColor),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(children: [
                  _buildAvatar(name: name, avatarUrl: _profile['avatar_url']?.toString(),
                      cardColor: cardColor, isCompact: false),
                  const SizedBox(height: 16),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _StatCol(_fmt(_posts.length), 'Posts', textColor, subColor),
                    const SizedBox(width: 32),
                    _StatCol(_fmt(followersCount), 'Followers', textColor, subColor),
                    const SizedBox(width: 32),
                    _StatCol(_fmt(followingCount), 'Following', textColor, subColor),
                  ]),
                ]),

          const SizedBox(height: 16),

          if (isCompact)
            Row(children: [
              Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(width: 6),
              _buildStageBadge(stageInfo),
              if (isPremium) ...[const SizedBox(width: 6), _buildPremiumBadge()],
            ])
          else
            Column(children: [
              Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _buildStageBadge(stageInfo),
                if (isPremium) ...[const SizedBox(width: 8), _buildPremiumBadge()],
              ]),
            ]),

          const SizedBox(height: 8),

          Text(
            _profile['bio']?.toString().isNotEmpty == true
                ? _profile['bio'].toString()
                : 'Building wealth one step at a time 🚀',
            style: TextStyle(fontSize: 13, color: subColor),
            textAlign: isCompact ? TextAlign.left : TextAlign.center,
          ),

          if ((_profile['status']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: isCompact ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(_profile['status'].toString(),
                    style: const TextStyle(fontSize: 12, color: AppColors.success,
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ],

          if ((_profile['country']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: isCompact ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                Icon(Iconsax.location, size: 12, color: subColor),
                const SizedBox(width: 4),
                Text(_profile['country'].toString(), style: TextStyle(fontSize: 12, color: subColor)),
              ],
            ),
          ],

          const SizedBox(height: 16),

          if (isCompact)
            Row(children: [
              Expanded(child: _buildActionButton('Edit Profile',
                  onTap: () => context.push('/edit-profile').then((_) => _load()),
                  surfaceColor: surfaceColor, borderColor: borderColor, textColor: textColor)),
              const SizedBox(width: 8),
              Expanded(child: _buildActionButton('Share Profile',
                  onTap: _shareProfile,
                  surfaceColor: surfaceColor, borderColor: borderColor, textColor: textColor)),
              if (!isPremium) ...[const SizedBox(width: 8), _buildProButton()],
            ])
          else
            Column(children: [
              _buildActionButton('Edit Profile',
                  onTap: () => context.push('/edit-profile').then((_) => _load()),
                  surfaceColor: surfaceColor, borderColor: borderColor, textColor: textColor,
                  isFullWidth: true),
              const SizedBox(height: 8),
              _buildActionButton('Share Profile',
                  onTap: _shareProfile,
                  surfaceColor: surfaceColor, borderColor: borderColor, textColor: textColor,
                  isFullWidth: true),
              if (!isPremium) ...[const SizedBox(height: 8), _buildProButton(isFullWidth: true)],
            ]),

          const SizedBox(height: 16),

          Row(children: [
            _ProfileFeatureTile('🎨', 'Portfolio', () => context.push('/portfolio')),
            const SizedBox(width: 8),
            _ProfileFeatureTile('🏆', 'Challenges', () => context.push('/challenges')),
            const SizedBox(width: 8),
            _ProfileFeatureTile('🧠', 'Memory', () => context.push('/memory')),
            const SizedBox(width: 8),
            _ProfileFeatureTile('💼', 'CRM', () => context.push('/crm')),
          ]),
        ],
      ),
    );
  }

  Widget _buildAvatar({
    required String name, required String? avatarUrl,
    required Color cardColor, required bool isCompact,
  }) {
    final size     = isCompact ? 76.0 : 100.0;
    final initial  = name.isNotEmpty ? name[0].toUpperCase() : '👤';
    final fontSize = isCompact ? 32.0 : 40.0;

    return Stack(children: [
      Container(
        width: size, height: size,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [AppColors.primary, AppColors.accent]),
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: avatarUrl != null && avatarUrl.isNotEmpty
              ? Image.network(avatarUrl, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(initial, style: TextStyle(fontSize: fontSize,
                        color: Colors.white, fontWeight: FontWeight.w700))))
              : Center(child: Text(initial, style: TextStyle(fontSize: fontSize,
                  color: Colors.white, fontWeight: FontWeight.w700))),
        ),
      ),
      Positioned(
        bottom: 0, right: 0,
        child: GestureDetector(
          onTap: () => context.push('/edit-profile').then((_) => _load()),
          child: Container(
            width: isCompact ? 22 : 28, height: isCompact ? 22 : 28,
            decoration: BoxDecoration(
              color: AppColors.primary, shape: BoxShape.circle,
              border: Border.all(color: cardColor, width: 2),
            ),
            child: Icon(Icons.camera_alt_rounded, color: Colors.white,
                size: isCompact ? 11 : 14),
          ),
        ),
      ),
    ]);
  }

  Widget _buildStageBadge(Map<String, dynamic> stageInfo) {
    final color = stageInfo['color'] as Color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Text('${stageInfo['emoji']} ${stageInfo['label']}',
          style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildPremiumBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('⭐ PRO',
          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
    );
  }

  Widget _buildActionButton(String label, {
    required VoidCallback onTap, required Color surfaceColor,
    required Color borderColor, required Color textColor, bool isFullWidth = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: surfaceColor, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor),
        ),
        child: Center(child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: textColor))),
      ),
    );
  }

  Widget _buildProButton({bool isFullWidth = false}) {
    return GestureDetector(
      onTap: () => context.go('/premium'),
      child: Container(
        width: isFullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Text('⭐ Pro',
            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildPostsSection({
    required bool isDark, required Color cardColor,
    required Color borderColor, required Color textColor, required Color subColor,
  }) {
    return Column(children: [
      Container(
        color: cardColor,
        child: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: subColor,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2.5,
          tabs: const [
            Tab(icon: Icon(Iconsax.grid_1, size: 20)),
            Tab(icon: Icon(Iconsax.heart, size: 20)),
          ],
        ),
      ),
      Divider(height: 1, color: borderColor),
      Expanded(
        child: TabBarView(
          controller: _tabCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildPostsList(
              posts: _posts, isDark: isDark, cardColor: cardColor,
              borderColor: borderColor, textColor: textColor, subColor: subColor,
              emptyMessage: 'No posts yet', isLikedTab: false,
            ),
            _buildPostsList(
              posts: _likedPosts, isDark: isDark, cardColor: cardColor,
              borderColor: borderColor, textColor: textColor, subColor: subColor,
              emptyMessage: 'No liked posts yet', isLikedTab: true,
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _buildPostsList({
    required List posts,
    required bool isDark,
    required Color cardColor,
    required Color borderColor,
    required Color textColor,
    required Color subColor,
    required String emptyMessage,
    required bool isLikedTab,
  }) {
    if (posts.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(isLikedTab ? '❤️' : '📝', style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(emptyMessage, style: TextStyle(color: subColor, fontSize: 14)),
          if (!isLikedTab) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => context.go('/create'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                child: const Text('Create your first post',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ]),
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: posts.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
      itemBuilder: (_, i) {
        final p = posts[i] as Map;
        // FIX: check is_liked for both own posts tab and liked tab
        final isLiked = p['is_liked'] == true || isLikedTab;

        return GestureDetector(
          onTap: () => context.push(
              '/comments/${p['id']}?content=${Uri.encodeComponent(p['content']?.toString() ?? '')}'),
          child: Container(
            color: cardColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text(p['tag']?.toString() ?? '',
                      style: const TextStyle(fontSize: 11, color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                  const Spacer(),
                  Text(_timeAgo(p['created_at']?.toString()),
                      style: TextStyle(fontSize: 11, color: subColor)),
                ]),
                const SizedBox(height: 8),
                Text(p['content']?.toString() ?? '',
                    style: TextStyle(fontSize: 14, color: textColor, height: 1.5)),
                const SizedBox(height: 8),
                Row(children: [
                  // FIX: show filled heart when post is liked
                  GestureDetector(
                    onTap: isLikedTab ? null : () => _toggleLike(p),
                    child: Icon(
                      isLiked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      size: 16,
                      color: isLiked ? Colors.red : subColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('${p['likes_count'] ?? 0}', style: TextStyle(fontSize: 12, color: subColor)),
                  const SizedBox(width: 16),
                  Icon(Iconsax.message, size: 16, color: subColor),
                  const SizedBox(width: 4),
                  Text('${p['comments_count'] ?? 0}', style: TextStyle(fontSize: 12, color: subColor)),
                ]),
              ],
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40)),
        );
      },
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _StatCol extends StatelessWidget {
  final String value, label;
  final Color textColor, subColor;
  const _StatCol(this.value, this.label, this.textColor, this.subColor);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: textColor)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11, color: subColor)),
      ]);
}

class _ProfileFeatureTile extends StatelessWidget {
  final String emoji, label;
  final VoidCallback onTap;
  const _ProfileFeatureTile(this.emoji, this.label, this.onTap);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black54)),
          ]),
        ),
      ),
    );
  }
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  final Color bg, border;
  const _TabBarDelegate(this.tabBar, this.bg, this.border);

  @override double get minExtent => tabBar.preferredSize.height + 1;
  @override double get maxExtent => tabBar.preferredSize.height + 1;

  @override
  Widget build(BuildContext _, double __, bool ___) => Container(
        color: bg,
        child: Column(children: [tabBar, Divider(height: 1, color: border)]),
      );

  @override
  bool shouldRebuild(_TabBarDelegate o) => false;
}
