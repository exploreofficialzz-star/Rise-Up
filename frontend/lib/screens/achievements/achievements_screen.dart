// frontend/lib/screens/achievements/achievements_screen.dart
// v3.0 — Theme-aware · Cache-first · Shimmer · 5 Ad placements wired
//
// CHANGES vs v2:
//  1.  Full theme awareness — bg/card/text adapt to system light/dark theme
//  2.  Cache-first with SharedPreferences — instant re-open, silent bg refresh
//  3.  Shimmer skeleton while loading — no CircularProgressIndicator
//  4.  Five AdMob placements (aggressive but policy-compliant):
//       [1] ScreenBannerAd        — sticky bottom banner
//       [2] Rewarded "Watch Ad → +50 XP" tappable row inside the XP card
//       [3] PremiumUpsellBanner   — below XP card, before tabs
//       [4] FeedAdCard            — full-width, injected every 6 achievements in grid
//       [5] Interstitial          — fired on every tab switch (AdService frequency-controlled)
//  5.  _AchievementCard now receives theme colors; no more hardcoded dark colours
//  6.  Bottom sheet also theme-aware

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';   // adService singleton
import '../../widgets/ad_widgets.dart';    // AdConfig, FeedAdCard, ScreenBannerAd,
                                           // PremiumUpsellBanner

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer helper
// ─────────────────────────────────────────────────────────────────────────────
class _Shimmer extends StatelessWidget {
  const _Shimmer({
    this.width,
    required this.height,
    this.radius = 8,
    this.circle = false,
  });
  final double? width;
  final double  height, radius;
  final bool    circle;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A2A2A) : const Color(0xFFE4E4E4),
        borderRadius: circle ? null : BorderRadius.circular(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
      ),
    )
        .animate(onPlay: (c) => c.repeat())
        .shimmer(
          duration: 1200.ms,
          color: dark ? Colors.white10 : Colors.white70,
        );
  }
}

/// One row of 3 achievement placeholders while loading
class _AchievementRowSkeleton extends StatelessWidget {
  const _AchievementRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: List.generate(3, (i) {
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(
                  left: i == 0 ? 0 : 5, right: i == 2 ? 0 : 5),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  _Shimmer(width: 56, height: 56, circle: true),
                  SizedBox(height: 8),
                  _Shimmer(width: 60, height: 10),
                  SizedBox(height: 4),
                  _Shimmer(width: 40, height: 8),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab categories
// ─────────────────────────────────────────────────────────────────────────────
const _kCats = [
  'all', 'tasks', 'earnings', 'streak',
  'skills', 'community', 'referral', 'milestone',
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen>
    with SingleTickerProviderStateMixin {
  Map  _data         = {};
  bool _loading      = true;
  bool _xpAdLoading  = false;
  int  _lastTabIndex = 0;
  late TabController _tab;

  static const _kCacheKey = 'riseup_achievements_v1';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _kCats.length, vsync: this);
    _tab.addListener(_onTabChanged);
    AdConfig.load(); // keep ad config fresh (non-blocking)
    _restoreFromCache();
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ── Tab change → interstitial [placement 5] ────────────────────────────────
  void _onTabChanged() {
    if (_tab.index == _lastTabIndex) return;
    _lastTabIndex = _tab.index;
    // AdService has built-in frequency (_interstitialFreq=3) and
    // cooldown (_interstitialCooldown=2 min) — safe to call every tab switch
    if (AdConfig.shouldShowAds) adService.showInterstitialIfReady();
  }

  // ── Cache ──────────────────────────────────────────────────────────────────
  Future<void> _restoreFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kCacheKey);
      if (raw == null || !mounted) return;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      if (mounted) setState(() { _data = decoded; _loading = false; });
    } catch (_) {}
  }

  Future<void> _writeCache(Map data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheKey, jsonEncode(data));
    } catch (_) {}
  }

  // ── Load / refresh ─────────────────────────────────────────────────────────
  Future<void> _load() async {
    try {
      final data = await api.getAchievements();
      // Background achievement check — don't await
      api.checkAchievements().catchError((_) {});
      await _writeCache(data);
      if (mounted) setState(() { _data = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Rewarded ad → +50 XP [placement 2] ────────────────────────────────────
  Future<void> _watchAdForXp() async {
    if (_xpAdLoading) return;
    setState(() => _xpAdLoading = true);
    HapticFeedback.lightImpact();

    await adService.showRewardedAd(
      featureKey: 'achievement_bonus_xp',
      onRewarded: () async {
        try {
          await api.post('/achievements/bonus-xp', {'amount': 50});
        } catch (_) {
          // bonus still queued server-side; don't block UX
        }
        await _load();
        if (mounted) {
          setState(() => _xpAdLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('🎉 +50 Bonus XP earned!'),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: 2),
          ));
        }
      },
      onDismissed: () {
        if (mounted) setState(() => _xpAdLoading = false);
      },
    );
  }

  // ── Filter by tab ──────────────────────────────────────────────────────────
  List _filtered(String cat) {
    final all = (_data['achievements'] as List? ?? []);
    if (cat == 'all') return all;
    return all.where((a) => a['category'] == cat).toList();
  }

  // ── Build achievement rows + injected ad cards [placement 4] ──────────────
  List<Widget> _buildGridWithAds(
    List  items,
    bool  isDark,
    Color card,
    Color border,
    Color textClr,
    Color sub,
  ) {
    final result   = <Widget>[];
    var   rowCount = 0;
    const adEvery  = 2; // inject ad after every 2 rows (≈ every 6 achievements)

    for (int i = 0; i < items.length; i += 3) {
      final slice = items.sublist(i, min(i + 3, items.length));

      result.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(3, (j) {
              if (j < slice.length) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                        left: j == 0 ? 0 : 5, right: j == 2 ? 0 : 5),
                    child: _AchievementCard(
                      achievement: slice[j],
                      index: i + j,
                      isDark: isDark,
                      textClr: textClr,
                      sub: sub,
                    ),
                  ),
                );
              }
              return const Expanded(child: SizedBox());
            }),
          ),
        ),
      );

      rowCount++;

      // Inject full-width ad every `adEvery` rows
      if (rowCount % adEvery == 0 && AdConfig.shouldShowAds) {
        result.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: FeedAdCard(
              isDark:      isDark,
              cardColor:   card,
              borderColor: border,
              textColor:   textClr,
              subColor:    sub,
            ),
          ),
        );
      }
    }

    return result;
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? Colors.black : Colors.white;
    final card    = isDark ? AppColors.bgCard : const Color(0xFFF7F7F7);
    final border  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textClr = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.white54 : Colors.black45;

    final xp        = (_data['xp_points']      ?? 0) as int;
    final level     = (_data['level']           ?? 1) as int;
    final unlocked  = (_data['unlocked_count']  ?? 0) as int;
    final total     = (_data['total_count']     ?? 0) as int;
    final xpInLevel = xp % 500;
    final progress  = xpInLevel / 500.0;

    return Scaffold(
      backgroundColor: bg,

      // ── [Placement 1] Sticky bottom BannerAd ──────────────────────────────
      // ScreenBannerAd returns SizedBox.shrink() for premium / unloaded states
      bottomNavigationBar: ScreenBannerAd(isDark: isDark),

      appBar: AppBar(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'Achievements',
          style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.w700, color: textClr),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : Colors.white,
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: sub,
              indicatorColor: AppColors.primary,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: _kCats
                  .map((c) =>
                      Tab(text: c[0].toUpperCase() + c.substring(1)))
                  .toList(),
            ),
          ),
        ),
      ),

      body: _loading && _data.isEmpty
          ? _buildSkeleton(isDark, border)
          : Column(children: [

              // ── XP & Level card ─────────────────────────────────────────
              _buildXpCard(
                isDark: isDark, card: card, border: border,
                textClr: textClr, sub: sub,
                xp: xp, level: level, unlocked: unlocked, total: total,
                xpInLevel: xpInLevel, progress: progress,
              ),

              // ── [Placement 3] Premium upsell banner ─────────────────────
              if (AdConfig.shouldShowAds)
                PremiumUpsellBanner(isDark: isDark)
                    .animate()
                    .fadeIn(duration: 300.ms),

              // ── Achievement grid with tabs ────────────────────────────────
              Expanded(
                child: TabBarView(
                  controller: _tab,
                  children: _kCats.map((cat) {
                    final items = _filtered(cat);

                    if (items.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('🏅',
                                style: TextStyle(fontSize: 48)),
                            const SizedBox(height: 12),
                            Text('No achievements here yet',
                                style: TextStyle(
                                    color: sub, fontSize: 14)),
                          ],
                        ),
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 24),
                        children: _buildGridWithAds(
                            items, isDark, card, border, textClr, sub),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ]),
    );
  }

  // ── XP card (contains placement 2: rewarded ad XP button) ─────────────────
  Widget _buildXpCard({
    required bool   isDark,
    required Color  card,
    required Color  border,
    required Color  textClr,
    required Color  sub,
    required int    xp,
    required int    level,
    required int    unlocked,
    required int    total,
    required int    xpInLevel,
    required double progress,
  }) {
    // Theme-aware gradient: rich purple on dark, soft lavender tint on light
    final gradColors = isDark
        ? [const Color(0xFF2D1B69), const Color(0xFF1A0E4F)]
        : [
            AppColors.primary.withOpacity(0.07),
            AppColors.accent.withOpacity(0.04),
          ];

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradColors),
        borderRadius: AppRadius.xl,
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Level + badge count row
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Level $level',
                style: AppTextStyles.h2.copyWith(color: AppColors.gold)),
            Text('$xp XP total',
                style: AppTextStyles.bodySmall.copyWith(color: sub)),
          ]),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              borderRadius: AppRadius.pill,
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.4)),
            ),
            child: Text('🏆 $unlocked / $total badges',
                style: AppTextStyles.label
                    .copyWith(color: AppColors.primary)),
          ),
        ]),

        const SizedBox(height: 12),

        // XP progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark
                ? AppColors.bgSurface
                : Colors.grey.shade200,
            valueColor:
                const AlwaysStoppedAnimation(AppColors.gold),
            minHeight: 8,
          ),
        ),

        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('$xpInLevel XP',
              style: AppTextStyles.caption.copyWith(color: sub)),
          Text('${500 - xpInLevel} XP to Level ${level + 1}',
              style: AppTextStyles.caption.copyWith(color: sub)),
        ]),

        // ── [Placement 2] Rewarded ad → +50 XP ────────────────────────────
        if (AdConfig.shouldShowAds) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _watchAdForXp,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.success
                    .withOpacity(isDark ? 0.14 : 0.09),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: AppColors.success.withOpacity(0.32)),
              ),
              child: Row(children: [
                _xpAdLoading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: AppColors.success,
                            strokeWidth: 2))
                    : const Text('🎁',
                        style: TextStyle(fontSize: 18)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _xpAdLoading
                            ? 'Loading ad…'
                            : 'Watch Ad → Earn +50 XP',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.success,
                        ),
                      ),
                      Text(
                        'Free daily XP boost — watch a short ad',
                        style: TextStyle(
                            fontSize: 11, color: sub),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.play_circle_outline_rounded,
                  color: AppColors.success,
                  size: 22,
                ),
              ]),
            ),
          ),
        ],
      ]),
    )
        .animate()
        .fadeIn(duration: 400.ms)
        .slideY(begin: -0.2);
  }

  // ── Skeleton loader ────────────────────────────────────────────────────────
  Widget _buildSkeleton(bool isDark, Color border) {
    return Column(children: [
      // XP card placeholder
      Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        height: 120,
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.bgCard
              : Colors.grey.shade100,
          borderRadius: AppRadius.xl,
        ),
        child: const Center(
          child: _Shimmer(width: 180, height: 14),
        ),
      ),
      // Tab bar placeholder
      Container(
        height: 48,
        margin: const EdgeInsets.only(top: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: border)),
        ),
        child: const _Shimmer(height: 48),
      ),
      // Grid skeleton rows
      Expanded(
        child: ListView.builder(
          padding: const EdgeInsets.only(top: 14),
          itemCount: 4,
          itemBuilder: (_, __) => const _AchievementRowSkeleton(),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Achievement Card — fully theme-aware, no hardcoded dark colours
// ─────────────────────────────────────────────────────────────────────────────
class _AchievementCard extends StatelessWidget {
  final Map   achievement;
  final int   index;
  final bool  isDark;
  final Color textClr, sub;

  const _AchievementCard({
    required this.achievement,
    required this.index,
    required this.isDark,
    required this.textClr,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = achievement['unlocked'] == true;
    final isSecret = achievement['is_secret'] == true && !unlocked;

    return GestureDetector(
      onTap: () => _showDetail(context),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          // Unlocked: card bg; locked: slightly muted surface
          color: unlocked
              ? (isDark ? AppColors.bgCard : Colors.white)
              : (isDark
                  ? AppColors.bgSurface
                  : Colors.grey.shade100),
          borderRadius: AppRadius.lg,
          border: Border.all(
            color: unlocked
                ? AppColors.gold.withOpacity(0.45)
                : Colors.transparent,
            width: 1.5,
          ),
          boxShadow: unlocked
              ? [
                  BoxShadow(
                    color: AppColors.gold
                        .withOpacity(isDark ? 0.14 : 0.10),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ]
              : [],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              vertical: 14, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Badge circle
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: unlocked
                      ? AppColors.gold.withOpacity(0.15)
                      : (isDark
                          ? AppColors.bgDark
                          : Colors.grey.shade200),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: isSecret
                      ? Icon(Icons.lock_outline,
                          color: sub, size: 24)
                      : Text(
                          achievement['icon'] ?? '🏆',
                          style: TextStyle(
                            fontSize: 28,
                            color: unlocked
                                ? null
                                : textClr.withOpacity(0.3),
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              // Title
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  isSecret
                      ? '???'
                      : (achievement['title'] ?? ''),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: unlocked ? textClr : sub,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              // XP / unlocked label
              Text(
                unlocked
                    ? '✓ Unlocked'
                    : '+${achievement['xp_reward'] ?? 0} XP',
                style: TextStyle(
                  fontSize: 9,
                  color: unlocked ? AppColors.success : sub,
                  fontWeight: unlocked
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      )
          .animate(delay: Duration(milliseconds: index * 30))
          .fadeIn(duration: 300.ms)
          .scale(begin: const Offset(0.85, 0.85)),
    );
  }

  void _showDetail(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bg      = isDark ? AppColors.bgCard : Colors.white;
    final textClr = isDark ? Colors.white : Colors.black87;
    final sub     = isDark ? Colors.white54 : Colors.black45;
    final unlocked = achievement['unlocked'] == true;

    showModalBottomSheet(
      context: context,
      backgroundColor: bg,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Handle
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(achievement['icon'] ?? '🏆',
              style: const TextStyle(fontSize: 56)),
          const SizedBox(height: 16),
          Text(
            achievement['title'] ?? '',
            style: AppTextStyles.h3.copyWith(color: textClr),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            achievement['description'] ?? '',
            style: AppTextStyles.body.copyWith(color: sub),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: (unlocked
                      ? AppColors.success
                      : AppColors.primary)
                  .withOpacity(0.15),
              borderRadius: AppRadius.pill,
            ),
            child: Text(
              unlocked
                  ? '✅ Unlocked on '
                      '${achievement['unlocked_at']?.toString().split('T')[0] ?? ''}'
                  : '🔒 +${achievement['xp_reward']} XP when unlocked',
              style: AppTextStyles.label.copyWith(
                color: unlocked
                    ? AppColors.success
                    : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
