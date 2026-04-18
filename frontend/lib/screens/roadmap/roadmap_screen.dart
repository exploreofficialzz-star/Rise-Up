// frontend/lib/screens/roadmap/roadmap_screen.dart
// v2.0 — Theme-aware (light/dark), cache-first, proper ad wiring, fast reload
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/ad_widgets.dart';
import '../../widgets/gradient_button.dart';

// ── Theme helper — every widget in this file calls _T.of(context) ─────────
class _T {
  final bool   dark;
  final Color  bg, card, surface, border, text, sub;
  const _T({
    required this.dark,   required this.bg,
    required this.card,   required this.surface,
    required this.border, required this.text,
    required this.sub,
  });
  factory _T.of(BuildContext ctx) {
    final dark = Theme.of(ctx).brightness == Brightness.dark;
    return _T(
      dark:    dark,
      bg:      dark ? Colors.black        : Colors.white,
      card:    dark ? AppColors.bgCard    : Colors.white,
      surface: dark ? AppColors.bgSurface : Colors.grey.shade100,
      border:  dark ? AppColors.bgSurface : Colors.grey.shade200,
      text:    dark ? Colors.white        : Colors.black87,
      sub:     dark ? Colors.white54      : Colors.black54,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});
  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen>
    with WidgetsBindingObserver {
  // ── Cache keys ─────────────────────────────────────────────────────────
  static const _kRoadmap  = 'riseup_roadmap_v1';
  static const _kProfile  = 'riseup_roadmap_profile_v1';
  static const _kAccess   = 'riseup_roadmap_access_v1';

  // ── State ───────────────────────────────────────────────────────────────
  Map?  _roadmap;
  Map   _profile   = {};
  bool  _loading    = true;
  bool  _generating = false;
  bool  _refreshing = false;
  bool  _hasAccess  = false;
  bool  _isPremium  = false;

  // ── Banner ad (same pattern as ProfileScreen) ───────────────────────────
  BannerAd? _bannerAd;
  bool      _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreCache();
    // Fire check immediately after first frame so cache renders first
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndLoad());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) _silentRefresh();
  }

  // ── Step 1: instant cache paint ─────────────────────────────────────────
  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Profile / premium
      final pStr = prefs.getString(_kProfile);
      if (pStr != null) {
        final p = Map<String, dynamic>.from(jsonDecode(pStr) as Map);
        if (mounted) setState(() {
          _profile   = p;
          _isPremium = p['subscription_tier'] == 'premium' ||
                       p['is_premium'] == true;
        });
      }

      // Access flag
      final access = prefs.getBool(_kAccess) ?? false;
      if (mounted) setState(() => _hasAccess = access);

      // Roadmap
      final rStr = prefs.getString(_kRoadmap);
      if (rStr != null) {
        final r = Map<String, dynamic>.from(jsonDecode(rStr) as Map);
        if (mounted) setState(() {
          _roadmap = r;
          _loading = false;
        });
      } else if (mounted) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Step 2: silent background fetch ─────────────────────────────────────
  Future<void> _silentRefresh() async {
    if (_refreshing || !mounted) return;
    setState(() => _refreshing = true);
    await _checkAndLoad(silent: true);
  }

  // ── Core load orchestrator ───────────────────────────────────────────────
  Future<void> _checkAndLoad({bool silent = false}) async {
    if (!silent) setState(() { _loading = true; _refreshing = true; });

    try {
      // Fetch profile + feature access in parallel
      final results = await Future.wait([
        api.getProfile(),
        api.checkFeatureAccess(FeatureKeys.aiRoadmap),
      ]);

      final profileRes = results[0] as Map;
      final profile    = (profileRes['profile'] as Map?)
                             ?.cast<String, dynamic>() ?? {};
      final accessRes  = results[1] as Map;
      final hasAccess  = accessRes['has_access'] == true;
      final isPremium  = profile['subscription_tier'] == 'premium' ||
                         profile['is_premium'] == true;

      if (mounted) setState(() {
        _profile    = profile;
        _hasAccess  = hasAccess;
        _isPremium  = isPremium;
        _loading    = false;
        _refreshing = false;
      });

      // Persist
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setString(_kProfile, jsonEncode(profile)),
        prefs.setBool(_kAccess,    hasAccess),
      ]);

      // Manage ad — load for free users, dispose for premium
      if (!isPremium) {
        _loadAd();
      } else {
        _bannerAd?.dispose();
        _bannerAd    = null;
        _isAdLoaded  = false;
      }

      // Load roadmap content if granted access
      if (hasAccess && _roadmap == null) {
        await _loadRoadmap();
      }
    } catch (_) {
      if (mounted) setState(() { _loading = false; _refreshing = false; });
    }
  }

  // ── Fetch roadmap data ───────────────────────────────────────────────────
  Future<void> _loadRoadmap() async {
    if (!mounted) return;
    try {
      final data = await api.getRoadmap();
      final roadmap = data['roadmap'] as Map?;
      if (roadmap != null && mounted) {
        setState(() => _roadmap = roadmap);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kRoadmap, jsonEncode(roadmap));
      }
    } catch (_) {}
  }

  // ── Generate (or regenerate) roadmap ────────────────────────────────────
  Future<void> _generate() async {
    if (!mounted || _generating) return;
    setState(() => _generating = true);
    try {
      final data    = await api.generateRoadmap();
      final roadmap = data['roadmap'] as Map?;
      if (roadmap != null && mounted) {
        setState(() { _roadmap = roadmap; _generating = false; });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kRoadmap, jsonEncode(roadmap));
      } else {
        if (mounted) setState(() => _generating = false);
      }
    } catch (_) {
      if (mounted) setState(() => _generating = false);
    }
  }

  // ── Banner ad loader (mirrors ProfileScreen exactly) ─────────────────────
  Future<void> _loadAd() async {
    if (_isPremium || kIsWeb || _bannerAd != null) return;
    try {
      final ad = BannerAd(
        adUnitId: Platform.isAndroid
            ? AppConstants.androidBannerAdUnitId
            : AppConstants.iosBannerAdUnitId,
        size:    AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (mounted) setState(() {
              _bannerAd    = ad as BannerAd;
              _isAdLoaded  = true;
            });
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (mounted) setState(() {
              _bannerAd   = null;
              _isAdLoaded = false;
            });
          },
        ),
      );
      await ad.load();
    } catch (_) {}
  }

  // ── Called after rewarded ad or returning from premium screen ────────────
  Future<void> _onAccessMaybeGranted() async {
    setState(() { _loading = true; _roadmap = null; });
    // Clear cached access so it re-fetches cleanly
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kAccess);
    await prefs.remove(_kRoadmap);
    await _checkAndLoad();
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Wealth Roadmap', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: t.border),
        ),
        actions: [
          if (_refreshing)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(child: SizedBox(width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5,
                    color: AppColors.primary.withOpacity(0.5)))),
            ),
          if (_hasAccess && _roadmap != null)
            IconButton(
              icon: Icon(Iconsax.refresh, color: t.sub, size: 22),
              onPressed: _generating ? null : _generate,
              tooltip: 'Regenerate',
            ),
        ],
      ),
      body: Column(children: [
        // ── Banner ad (free users only, mirrors ProfileScreen) ────────────
        if (!_isPremium && _isAdLoaded && _bannerAd != null && !kIsWeb)
          Container(
            color: t.card,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(child: SizedBox(
              width:  _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child:  AdWidget(ad: _bannerAd!),
            )),
          ),

        // ── Main content ──────────────────────────────────────────────────
        Expanded(child: _buildBody(t)),

        // ── Sticky bottom banner (free users) ─────────────────────────────
        if (!_isPremium && !kIsWeb)
          ScreenBannerAd(isDark: t.dark),
      ]),
    );
  }

  Widget _buildBody(_T t) {
    if (_loading && _roadmap == null) {
      return Center(child: Column(
        mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(
              color: AppColors.primary,
              strokeWidth: 2.5),
          const SizedBox(height: 16),
          Text('Loading your roadmap…',
              style: TextStyle(fontSize: 13, color: t.sub)),
        ],
      ));
    }

    if (!_hasAccess) {
      return _AccessGate(
        onSubscribe: () async {
          // push so user can navigate back — re-check on return
          await context.push('/payment');
          if (mounted) _onAccessMaybeGranted();
        },
        onUnlocked: _onAccessMaybeGranted,
      );
    }

    if (_roadmap == null) {
      return _EmptyRoadmap(
          onGenerate: _generate,
          generating: _generating);
    }

    return _RoadmapView(
      roadmap:      _roadmap!,
      onRegenerate: _generate,
      generating:   _generating,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Access Gate — resolves own theme
// ─────────────────────────────────────────────────────────────────────────────
class _AccessGate extends StatelessWidget {
  final VoidCallback onSubscribe;
  final VoidCallback onUnlocked;   // called after rewarded ad rewards user
  const _AccessGate({
    required this.onSubscribe, required this.onUnlocked,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 48, 28, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🗺️',
                style: TextStyle(fontSize: 52))),
          ),
          const SizedBox(height: 24),

          Text('Your Personalized Wealth Roadmap',
              style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800, color: t.text),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'A 3-stage plan from where you are to where\n'
            'you want to be — tailored by AI to your exact situation.',
            style: TextStyle(fontSize: 13, color: t.sub, height: 1.5),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Feature bullets
          ...[
            (Iconsax.map, '3-stage personalised wealth plan'),
            (Iconsax.star, 'Weekly action steps for your stage'),
            (Iconsax.book, 'Skill & income recommendations'),
            (Iconsax.refresh, 'Regenerate as your situation changes'),
          ].map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(item.$1, color: AppColors.primary, size: 16),
              ),
              const SizedBox(width: 12),
              Text(item.$2,
                  style: TextStyle(fontSize: 13, color: t.text,
                      fontWeight: FontWeight.w500)),
            ]),
          )),

          const SizedBox(height: 28),

          // Premium button
          GradientButton(
            text: '👑 Unlock with Premium · \$15.99/mo',
            onTap: onSubscribe,
          ),

          const SizedBox(height: 16),

          // Divider
          Row(children: [
            Expanded(child: Divider(color: t.border)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text('or', style: TextStyle(
                  fontSize: 12, color: t.sub)),
            ),
            Expanded(child: Divider(color: t.border)),
          ]),

          const SizedBox(height: 16),

          // Watch ad button — uses RewardedAdButton from ad_widgets.dart
          SizedBox(
            width: double.infinity,
            child: RewardedAdButton(
              featureKey:  FeatureKeys.aiRoadmap,
              featureName: 'Roadmap',
              isDark:      Theme.of(context).brightness == Brightness.dark,
              onRewarded:  onUnlocked,
            ),
          ),

          const SizedBox(height: 10),
          Text(
            'Watching an ad unlocks the roadmap for 1 hour.',
            style: TextStyle(fontSize: 11, color: t.sub),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty Roadmap — resolves own theme
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyRoadmap extends StatelessWidget {
  final VoidCallback onGenerate;
  final bool         generating;
  const _EmptyRoadmap({required this.onGenerate, required this.generating});

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 100, height: 100,
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Center(child: Text('🚀',
                style: TextStyle(fontSize: 52))),
          ),
          const SizedBox(height: 24),
          Text('Ready for your roadmap?',
              style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800, color: t.text),
              textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Text(
            'AI will create a personalised 3-stage wealth plan\n'
            'based on your profile, stage, and goals.',
            style: TextStyle(fontSize: 13, color: t.sub, height: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          // What you'll get
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.card, borderRadius: AppRadius.lg,
              border: Border.all(color: t.border),
            ),
            child: Column(children: [
              ...[
                '🎯  Stage-by-stage income targets',
                '📋  Concrete weekly action steps',
                '💡  Personalised skill recommendations',
                '📈  Progress milestones to celebrate',
              ].map((line) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.substring(0, 2),
                        style: const TextStyle(fontSize: 15)),
                    const SizedBox(width: 10),
                    Expanded(child: Text(line.substring(3),
                        style: TextStyle(
                            fontSize: 13, color: t.text))),
                  ],
                ),
              )),
            ]),
          ),

          const SizedBox(height: 28),

          GradientButton(
            text: generating ? 'Generating…' : 'Generate My Roadmap ✨',
            onTap: generating ? null : onGenerate,
            isLoading: generating,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Roadmap View — resolves own theme
// ─────────────────────────────────────────────────────────────────────────────
class _RoadmapView extends StatelessWidget {
  final Map          roadmap;
  final VoidCallback onRegenerate;
  final bool         generating;
  const _RoadmapView({
    required this.roadmap,
    required this.onRegenerate,
    required this.generating,
  });

  @override
  Widget build(BuildContext context) {
    final t = _T.of(context);

    final stages = [
      ('stage_1', '🎯', 'Stage 1', AppColors.survival),
      ('stage_2', '📈', 'Stage 2', AppColors.earning),
      ('stage_3', '💎', 'Stage 3', AppColors.wealth),
    ];

    return RefreshIndicator(
      onRefresh: () async => onRegenerate(),
      color: AppColors.primary,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── AI summary card ─────────────────────────────────────────
            if ((roadmap['summary'] as String?)?.isNotEmpty == true)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: t.card,
                  gradient: LinearGradient(colors: [
                    AppColors.primary.withOpacity(0.08), t.card,
                  ]),
                  borderRadius: AppRadius.lg,
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome,
                          color: AppColors.primary, size: 15),
                      const SizedBox(width: 8),
                      Text('AI Analysis', style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                    ]),
                    const SizedBox(height: 8),
                    Text(roadmap['summary'] as String,
                        style: TextStyle(
                            fontSize: 13, color: t.text,
                            height: 1.5)),
                  ],
                ),
              ).animate().fadeIn(),

            // ── Do this TODAY ────────────────────────────────────────────
            if ((roadmap['first_step_today'] as String?)?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.07),
                  borderRadius: AppRadius.md,
                  border: Border.all(
                      color: AppColors.success.withOpacity(0.25)),
                ),
                child: Row(children: [
                  const Text('⚡', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Do this TODAY:', style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w700,
                          color: AppColors.success)),
                      const SizedBox(height: 3),
                      Text(roadmap['first_step_today'] as String,
                          style: TextStyle(
                              fontSize: 13, color: t.text,
                              height: 1.4)),
                    ],
                  )),
                ]),
              ).animate().fadeIn(delay: 80.ms),
            ],

            const SizedBox(height: 24),

            // Section header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Your 3-Stage Journey', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700,
                    color: t.text)),
                if (generating)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    SizedBox(width: 12, height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          color: AppColors.primary.withOpacity(0.6))),
                    const SizedBox(width: 6),
                    Text('Updating…',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.primary)),
                  ]),
              ],
            ),
            const SizedBox(height: 16),

            // ── Stage cards ──────────────────────────────────────────────
            ...stages.asMap().entries.map((entry) {
              final i = entry.key;
              final (key, emoji, label, color) = entry.value;
              final stage = roadmap[key] as Map? ?? {};
              if (stage.isEmpty) return const SizedBox.shrink();
              return _StageCard(
                emoji:    emoji,
                label:    label,
                stage:    stage,
                color:    color,
                isActive: roadmap['current_stage'] == _stageKey(i + 1),
              )
                  .animate()
                  .fadeIn(delay: Duration(milliseconds: (i + 1) * 120))
                  .slideY(begin: 0.08);
            }),

            // ── Recommended skills ───────────────────────────────────────
            if ((roadmap['recommended_skills'] as List?)?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text('Recommended Skills', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: t.text)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: (roadmap['recommended_skills'] as List)
                    .map((s) => GestureDetector(
                  onTap: () => context.go('/skills'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: AppRadius.pill,
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.25)),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Iconsax.book, size: 12,
                          color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(s.toString(), style: TextStyle(
                          fontSize: 12, color: t.dark
                              ? AppColors.primaryLight
                              : AppColors.primary,
                          fontWeight: FontWeight.w500)),
                    ]),
                  ),
                )).toList(),
              ).animate().fadeIn(delay: 500.ms),
            ],

            // ── Regenerate footer ────────────────────────────────────────
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.card, borderRadius: AppRadius.lg,
                border: Border.all(color: t.border),
              ),
              child: Row(children: [
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Life changed?', style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: t.text)),
                    Text('Regenerate your roadmap for a fresh plan.',
                        style: TextStyle(fontSize: 12, color: t.sub)),
                  ],
                )),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: generating ? null : onRegenerate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: generating
                      ? const SizedBox(width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Iconsax.refresh,
                          size: 15, color: Colors.white),
                  label: Text(generating ? 'Updating…' : 'Refresh',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.white,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ).animate().fadeIn(delay: 600.ms),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  String _stageKey(int i) {
    switch (i) {
      case 1:  return 'immediate_income';
      case 2:  return 'skill_growth';
      case 3:  return 'long_term_wealth';
      default: return '';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stage Card — resolves own theme
// ─────────────────────────────────────────────────────────────────────────────
class _StageCard extends StatelessWidget {
  final String emoji, label;
  final Map    stage;
  final Color  color;
  final bool   isActive;
  const _StageCard({
    required this.emoji,    required this.label,
    required this.stage,    required this.color,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    final t          = _T.of(context);
    final milestones = (stage['milestones'] as List?) ?? [];
    final actions    = (stage['weekly_actions'] as List?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: AppRadius.lg,
        border: Border.all(
          color: isActive ? color.withOpacity(0.5) : t.border,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: isActive
                  ? color.withOpacity(0.06) : Colors.transparent,
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12.0)),
            ),
            child: Row(children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stage['title']?.toString() ?? label,
                      style: TextStyle(fontSize: 14,
                          fontWeight: FontWeight.w700, color: color)),
                  if ((stage['duration'] as String?)?.isNotEmpty == true)
                    Text(stage['duration'] as String,
                        style: TextStyle(fontSize: 11, color: t.sub)),
                ],
              )),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.15),
                      borderRadius: AppRadius.pill),
                  child: Text('Current', style: TextStyle(
                      fontSize: 10, color: color,
                      fontWeight: FontWeight.w700)),
                ),
            ]),
          ),

          // ── Body ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (t.dark || true) Divider(height: 1, color: t.border),
                const SizedBox(height: 12),

                // Income target
                if ((stage['target_income'] as String?)?.isNotEmpty == true)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Iconsax.money, size: 13, color: color),
                      const SizedBox(width: 6),
                      Text('Target: ${stage['target_income']}',
                          style: TextStyle(fontSize: 12,
                              color: color, fontWeight: FontWeight.w600)),
                    ]),
                  ),

                // Milestones
                if (milestones.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('Milestones', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: t.sub)),
                  const SizedBox(height: 8),
                  ...milestones.take(3).map((m) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            margin: const EdgeInsets.only(top: 5),
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle)),
                        const SizedBox(width: 10),
                        Expanded(child: Text(
                          m['title']?.toString() ?? m.toString(),
                          style: TextStyle(
                              fontSize: 12, color: t.text, height: 1.4),
                        )),
                      ],
                    ),
                  )),
                ],

                // Weekly actions
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('This week', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700,
                      color: t.sub)),
                  const SizedBox(height: 8),
                  ...actions.take(2).map((a) => Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20, height: 20,
                          decoration: BoxDecoration(
                            color: AppColors.success.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Icon(Iconsax.tick_circle,
                              size: 12, color: AppColors.success),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: Text(
                          a.toString(),
                          style: TextStyle(
                              fontSize: 12, color: t.text, height: 1.4),
                        )),
                      ],
                    ),
                  )),
                ],

                // Description fallback
                if (milestones.isEmpty && actions.isEmpty &&
                    (stage['description'] as String?)?.isNotEmpty == true)
                  Text(stage['description'] as String,
                      style: TextStyle(
                          fontSize: 13, color: t.sub, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

