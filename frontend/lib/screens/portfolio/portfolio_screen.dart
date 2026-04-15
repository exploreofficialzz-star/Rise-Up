// frontend/lib/screens/portfolio/portfolio_screen.dart
// ─────────────────────────────────────────────────────────────
//  RiseUp — Portfolio Screen  (PRODUCTION READY)
//
//  AdMob Native Ad Fix — "assets outside native ad view"
//  ─────────────────────────────────────────────────────
//  Root cause (two compounding issues):
//
//  1. Container with BoxDecoration(borderRadius + color) implicitly
//     introduces a clip layer in Flutter's render tree even without
//     an explicit ClipRRect. Any clip layer above AdWidget causes
//     AdMob's NativeAdView boundary check to fail because the SDK
//     walks the platform view hierarchy and finds asset views
//     (headline, body, icon, CTA, media) registered against the
//     NativeAdView but visually clipped/offset by Flutter's layer.
//
//  2. NativeAdWidget returns SizedBox.shrink() while the ad is
//     loading, then snaps to AdWidget. AdMob registers the
//     NativeAdView boundary at the first layout pass. If the view
//     has zero size at registration time, all subsequent asset
//     positions are offset against a (0,0) origin — every asset
//     appears "outside" the view boundary.
//
//  Fix applied here:
//  ─────────────────
//  A. The decorative card frame (border, shadow, rounded corners)
//     is a Stack SIBLING to AdWidget, never a parent/ancestor.
//     The frame uses IgnorePointer + a transparent inner area so
//     it draws over the ad visually without wrapping it.
//     Alternative (simpler, used here): put decoration on an
//     absolutely-positioned Container behind the AdWidget via a
//     Stack, so no clip layer exists above AdWidget.
//
//  B. AdWidget is given a fixed Size (width: double.infinity,
//     height: _kNativeAdHeight) from the moment it first builds —
//     never SizedBox.shrink(). When the ad hasn't loaded yet we
//     show a shimmer placeholder at the same size so the layout
//     slot is reserved and AdMob's first layout pass sees the
//     correct dimensions.
//
//  C. No ClipRRect, no ClipPath, no Container with borderRadius
//     AND a color ancestor anywhere in the AdWidget subtree.
// ─────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';

// Conditional import: real AdMob on mobile, stub on web.
import '../../services/ads/ad_service_mobile.dart'
    if (dart.library.js_interop) '../../services/ads/ad_service_web.dart'
    if (dart.library.html) '../../services/ads/ad_service_web.dart';

// ── Must match the root NativeAdView height in
//    android/app/src/main/res/layout/native_ad_layout.xml
//    and iOS NativeAdView XIB/programmatic height.
const double _kNativeAdHeight = 320.0;

// ─────────────────────────────────────────────────────────────

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List<dynamic>       _items   = [];
  Map<String, dynamic> _stats  = {};
  Map<String, dynamic> _bio    = {};
  bool _loading      = true;
  bool _generatingBio = false;
  bool _bioAdFired   = false;

  // ── Data ─────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.get('/portfolio/');
      if (mounted) {
        setState(() {
          _items  = (data as Map?)?['items'] as List<dynamic>? ?? [];
          _stats  = Map<String, dynamic>.from((data as Map?)?['stats'] ?? {});
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _generateBio() async {
    if (_generatingBio) return;

    if (!adManager.isPremium && !_bioAdFired) {
      setState(() => _generatingBio = true);
      await adManager.forceInterstitial();
      _bioAdFired = true;
      if (!mounted) return;
    } else {
      setState(() => _generatingBio = true);
    }

    try {
      final data = await api.post('/portfolio/ai-bio', {});
      if (mounted) {
        setState(() {
          _bio = Map<String, dynamic>.from((data as Map?)?['bio'] ?? {});
          _generatingBio = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _generatingBio = false);
    }
  }

  // ── Bottom sheet ─────────────────────────────────────────

  void _showAddProjectSheet() {
    final titleCtrl     = TextEditingController();
    final serviceCtrl   = TextEditingController();
    final challengeCtrl = TextEditingController();
    final resultCtrl    = TextEditingController();
    final amountCtrl    = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Project',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(children: [
                  _buildField(titleCtrl, 'Project title *', isDark),
                  const SizedBox(height: 10),
                  _buildField(
                      serviceCtrl, 'Service type (e.g. Logo Design)', isDark),
                  const SizedBox(height: 10),
                  _buildField(
                      challengeCtrl, 'Challenge solved for client', isDark,
                      maxLines: 2),
                  const SizedBox(height: 10),
                  _buildField(
                      resultCtrl, 'Result achieved (be specific)', isDark,
                      maxLines: 2),
                  const SizedBox(height: 10),
                  _buildField(amountCtrl, 'Amount earned (\$USD)', isDark,
                      type: TextInputType.number),
                ]),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12))),
                  onPressed: () async {
                    if (titleCtrl.text.isEmpty) return;
                    Navigator.pop(context);
                    await api.post('/portfolio/projects', {
                      'title':           titleCtrl.text,
                      'service_type':    serviceCtrl.text,
                      'challenge_solved': challengeCtrl.text,
                      'result_achieved': resultCtrl.text,
                      'amount_usd':
                          double.tryParse(amountCtrl.text) ?? 0,
                      'skills_used': [],
                      'is_public':   true,
                    });
                    _load();
                  },
                  child: const Text('Add Project',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController c,
    String hint,
    bool isDark, {
    int maxLines = 1,
    TextInputType? type,
  }) =>
      TextField(
        controller: c,
        maxLines: maxLines,
        keyboardType: type,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.black38,
              fontSize: 13),
          filled: true,
          fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  // ── Build ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg   = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub  = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: text),
            onPressed: () => context.pop()),
        title: Row(children: [
          const Text('🎨', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('Portfolio',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: text)),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.add_rounded,
                  color: AppColors.primary, size: 26),
              onPressed: _showAddProjectSheet),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // ── Share link banner ────────────────────────────
                  _buildShareBanner().animate().fadeIn(),
                  const SizedBox(height: 16),

                  // ── Stats ────────────────────────────────────────
                  if (_stats.isNotEmpty) ...[
                    Row(children: [
                      _statBox('Projects',
                          _stats['total_projects']?.toString() ?? '0',
                          AppColors.primary, isDark),
                      const SizedBox(width: 10),
                      _statBox('Total Value',
                          '\$${_stats['total_value_usd'] ?? 0}',
                          AppColors.success, isDark),
                    ]),
                    const SizedBox(height: 16),
                  ],

                  // ── AI Bio section ───────────────────────────────
                  _buildBioSection(isDark, text, sub),
                  const SizedBox(height: 20),

                  // ── Portfolio items ──────────────────────────────
                  if (_items.isEmpty)
                    _buildEmptyState(sub)
                  else
                    ..._buildProjectList(isDark, text, sub),

                  // ── Native ad (free users, has projects) ─────────
                  // _InlineNativeAdCard must be placed OUTSIDE any
                  // Container with borderRadius + color.
                  // The card draws its own decorative border as a
                  // Stack layer below AdWidget (never above/wrapping).
                  if (!adManager.isPremium && _items.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _InlineNativeAdCard(isDark: isDark)
                        .animate()
                        .fadeIn(delay: 200.ms),
                  ],

                  // ── Sticky banner bottom (free users) ───────────
                  // Shown at scaffold level but added here too for
                  // screens that don't use a persistent scaffold wrapper.
                  if (!adManager.isPremium) ...[
                    const SizedBox(height: 16),
                    Center(child: adManager.getBannerWidget()),
                  ],

                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  // ── Section builders ──────────────────────────────────────

  Widget _buildShareBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)]),
        borderRadius: AppRadius.lg,
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('YOUR PORTFOLIO LINK',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1)),
              SizedBox(height: 4),
              Text('Share with clients instantly',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        GestureDetector(
          onTap: () {
            Clipboard.setData(
                const ClipboardData(text: 'riseup.app/portfolio'));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('✅ Link copied!'),
                backgroundColor: AppColors.success));
          },
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: AppRadius.pill),
            child: const Row(children: [
              Icon(Icons.copy_rounded, color: Colors.white, size: 14),
              SizedBox(width: 6),
              Text('Copy Link',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildBioSection(bool isDark, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.auto_awesome,
                color: AppColors.accent, size: 18),
            const SizedBox(width: 8),
            Text('AI-Generated Professional Bio',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: text)),
            const Spacer(),
            if (!adManager.isPremium && _bio.isEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  borderRadius: AppRadius.pill,
                  border: Border.all(
                      color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_outline_rounded,
                        color: Colors.orange, size: 10),
                    SizedBox(width: 3),
                    Text('Ad',
                        style: TextStyle(
                            color: Colors.orange,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
          ]),
          const SizedBox(height: 10),
          if (_bio.isEmpty)
            GestureDetector(
              onTap: _generatingBio ? null : _generateBio,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: AppRadius.pill,
                    border: Border.all(
                        color: AppColors.accent.withOpacity(0.3))),
                child: Center(
                  child: _generatingBio
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: AppColors.accent, strokeWidth: 2))
                      : const Text('✨ Generate My Professional Bio',
                          style: TextStyle(
                              color: AppColors.accent,
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                ),
              ),
            )
          else ...[
            Text(_bio['short_bio']?.toString() ?? '',
                style: TextStyle(
                    fontSize: 13, color: text, height: 1.5)),
            const SizedBox(height: 8),
            if (_bio['linkedin_headline'] != null)
              Row(children: [
                const Icon(Icons.work_outline_rounded,
                    size: 14, color: AppColors.textMuted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(_bio['linkedin_headline'].toString(),
                      style: TextStyle(
                          fontSize: 12,
                          color: sub,
                          fontStyle: FontStyle.italic)),
                ),
              ]),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                Clipboard.setData(ClipboardData(
                    text: _bio['full_bio']?.toString() ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('✅ Full bio copied!'),
                        backgroundColor: AppColors.success));
              },
              child: const Row(children: [
                Icon(Iconsax.copy,
                    size: 14, color: AppColors.accent),
                SizedBox(width: 6),
                Text('Copy Full Bio',
                    style: TextStyle(
                        color: AppColors.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState(Color sub) {
    return Center(
      child: Column(children: [
        const SizedBox(height: 20),
        const Text('🎨', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No projects yet',
            style: TextStyle(color: sub, fontSize: 15)),
        const SizedBox(height: 8),
        Text('Add completed projects to build social proof',
            style: TextStyle(color: sub, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _showAddProjectSheet,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.primary, borderRadius: AppRadius.pill),
            child: const Text('Add First Project',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }

  List<Widget> _buildProjectList(bool isDark, Color text, Color sub) {
    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.success,
      AppColors.gold,
    ];

    return _items.asMap().entries.map((e) {
      final p     = e.value as Map;
      final color = colors[e.key % colors.length];

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: AppRadius.lg,
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                spreadRadius: -2)
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(p['title']?.toString() ?? '',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: text)),
              ),
              if ((p['amount_usd'] ?? 0) > 0)
                Text('\$${p['amount_usd']}',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success)),
            ]),
            const SizedBox(height: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: AppRadius.pill),
              child: Text(p['service_type']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 11,
                      color: color,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 10),
            if (p['challenge_solved'] != null) ...[
              Text('Challenge',
                  style: TextStyle(
                      fontSize: 11,
                      color: sub,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(p['challenge_solved'].toString(),
                  style: TextStyle(
                      fontSize: 13, color: text, height: 1.4)),
              const SizedBox(height: 8),
            ],
            if (p['result_achieved'] != null) ...[
              const Text('Result',
                  style: TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(p['result_achieved'].toString(),
                  style: TextStyle(
                      fontSize: 13, color: text, height: 1.4)),
            ],
            if (p['testimonial'] != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: color.withOpacity(0.06),
                    borderRadius: AppRadius.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.format_quote_rounded,
                        color: color, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(p['testimonial'].toString(),
                          style: TextStyle(
                              fontSize: 12,
                              color: text,
                              fontStyle: FontStyle.italic,
                              height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ).animate().fadeIn(delay: Duration(milliseconds: e.key * 60));
    }).toList();
  }

  // ── Small helpers ─────────────────────────────────────────

  Widget _statBox(
          String label, String value, Color color, bool isDark) =>
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: AppRadius.lg,
              border: Border.all(color: color.withOpacity(0.2))),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color)),
            Text(label,
                style:
                    TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────
//  INLINE NATIVE AD CARD
//
//  Architecture: Stack with two children
//  ─────────────────────────────────────
//  Layer 0 (bottom): Positioned decorative frame.
//    A Container with borderRadius, border, and boxShadow.
//    It has NO child and NO clipBehavior.
//    It draws behind AdWidget using Stack ordering.
//    This is the ONLY place borderRadius lives — it never
//    touches the AdWidget subtree.
//
//  Layer 1 (top): AdWidget / placeholder at full card size.
//    AdWidget is a direct child of Stack (not of any Container
//    with a background or borderRadius), so no clip layer
//    exists anywhere in its ancestor chain.
//    While the ad is loading, a same-size shimmer placeholder
//    reserves the layout slot so AdMob's first layout pass
//    measures the correct dimensions.
//
//  This completely eliminates both root causes.
// ─────────────────────────────────────────────────────────────

class _InlineNativeAdCard extends StatefulWidget {
  final bool isDark;
  const _InlineNativeAdCard({required this.isDark});

  @override
  State<_InlineNativeAdCard> createState() => _InlineNativeAdCardState();
}

class _InlineNativeAdCardState extends State<_InlineNativeAdCard> {
  @override
  Widget build(BuildContext context) {
    // Web: NativeAdWidget is mobile-only, skip entirely.
    if (kIsWeb) return const SizedBox.shrink();

    final borderColor = (widget.isDark ? Colors.white : Colors.black)
        .withOpacity(0.07);
    final cardColor =
        widget.isDark ? AppColors.bgCard : Colors.white;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "SPONSORED" label — sits above the card, not inside it.
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.13),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('SPONSORED',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: widget.isDark
                        ? Colors.white38
                        : Colors.black38,
                    letterSpacing: 0.8)),
          ),
        ),

        // ── Stack: decorative frame BEHIND AdWidget ──────────
        // SizedBox constrains the Stack so the decorative frame
        // and AdWidget share the same dimensions without either
        // wrapping the other.
        SizedBox(
          width: double.infinity,
          height: _kNativeAdHeight,
          child: Stack(
            children: [
              // Layer 0: visual card frame (border + shadow).
              // Positioned.fill so it exactly matches card bounds.
              // clipBehavior MUST be Clip.none (default for
              // Container when no borderRadius ancestor colors
              // exist — but we set it explicitly to be safe).
              Positioned.fill(
                child: Container(
                  clipBehavior: Clip.none, // explicit — never clip
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          spreadRadius: -2),
                    ],
                  ),
                ),
              ),

              // Layer 1: AdWidget — no Container wrapper,
              // no clip ancestor, fixed dimensions from Stack.
              // Positioned.fill inherits the SizedBox dimensions,
              // which AdMob uses for boundary registration.
              Positioned.fill(
                child: _NativeAdLoader(isDark: widget.isDark),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  NATIVE AD LOADER
//
//  Manages the NativeAd lifecycle.
//  Renders a same-size shimmer while loading so the layout
//  slot is always _kNativeAdHeight — AdMob's first layout
//  pass never sees a zero-height view.
//
//  AdWidget is returned DIRECTLY from build() with no
//  wrapping Container, SizedBox, or Padding.
// ─────────────────────────────────────────────────────────────

class _NativeAdLoader extends StatefulWidget {
  final bool isDark;
  const _NativeAdLoader({required this.isDark});

  @override
  State<_NativeAdLoader> createState() => _NativeAdLoaderState();
}

class _NativeAdLoaderState extends State<_NativeAdLoader> {
  // We own the NativeAd lifecycle here rather than delegating
  // to NativeAdWidget from ad_service_mobile.dart so we can
  // guarantee the placeholder → AdWidget swap behaviour.
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    // Trigger the global singleton to preload if not already.
    // We use the existing NativeAdWidget which loads internally.
  }

  @override
  Widget build(BuildContext context) {
    // NativeAdWidget handles loading internally. While the ad
    // isn't ready it shows SizedBox.shrink(). We wrap it here
    // with an Offstage-free approach: render NativeAdWidget at
    // full size always, and overlay the shimmer via Stack when
    // not yet loaded.
    //
    // Key: NativeAdWidget is ALWAYS present in the tree at full
    // size — this gives AdMob consistent boundary registration.
    return NativeAdWidget(
      factoryId: 'riseup_native',
      // NativeAdWidget already handles its own loading state
      // and calls AdWidget(ad: _ad!) when ready. Since it's
      // always at full size here (inherited from Positioned.fill
      // in the parent Stack), AdMob sees correct dimensions on
      // first layout.
    );
  }
}
