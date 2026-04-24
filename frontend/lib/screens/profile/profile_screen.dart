// frontend/lib/screens/profile/profile_screen.dart
// RiseUp — Professional Profile v4.0
//
// Design:
//   • No "RiseUp" title in app bar — just back + settings
//   • Collapsing gradient header with centered avatar + gradient ring
//   • Glassmorphic stats banner
//   • Clean section cards with subtle separators
//   • Account actions at bottom
// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/storage_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const map = <String, Map<String, dynamic>>{
      'survival': {'emoji': '🆘', 'label': 'Survival', 'color': Color(0xFFE17055)},
      'earning':  {'emoji': '💪', 'label': 'Earning',  'color': Color(0xFF0984E3)},
      'growing':  {'emoji': '🚀', 'label': 'Growing',  'color': Color(0xFF00B894)},
      'wealth':   {'emoji': '💎', 'label': 'Wealth',   'color': Color(0xFF6C5CE7)},
      'legacy':   {'emoji': '🏛️', 'label': 'Legacy',  'color': Color(0xFF9B59B6)},
    };
    return map[stage.toLowerCase()] ?? map['survival']!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {

  Map<String, dynamic> _profile       = {};
  List<dynamic>        _missions      = [];
  List<dynamic>        _goals         = [];
  bool                 _loading       = true;
  bool                 _uploading     = false;
  int                  _totalEarned   = 0;
  int                  _activeMissions = 0;
  int                  _tokensLeft    = 0;
  bool                 _isPremium     = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed) _load();
  }

  Future<void> _loadFromCache() async {
    final cached = await storageService.getCachedProfile();
    if (cached != null && mounted) {
      setState(() { _profile = cached; _loading = false; });
    }
  }

  Future<void> _load() async {
    try {
      final futures = await Future.wait([
        api.get('/auth/me').timeout(const Duration(seconds: 12)),
        api.get('/mentor/sessions').timeout(const Duration(seconds: 12)),
        api.get('/goals').timeout(const Duration(seconds: 12)),
        api.get('/agent/tokens').timeout(const Duration(seconds: 12)),
        api.get('/income_memory/summary').timeout(const Duration(seconds: 12)),
      ], eagerError: false).catchError((_) =>
          <dynamic>[null, null, null, null, null]);

      if (!mounted) return;
      final profile  = futures[0] as Map<String, dynamic>? ?? {};
      final sessions = (futures[1] as Map?)?['sessions'] as List? ?? [];
      final goals    = (futures[2] as Map?)?['goals']    as List? ?? [];
      final tokens   = futures[3] as Map<String, dynamic>? ?? {};
      final income   = futures[4] as Map<String, dynamic>? ?? {};

      if (profile.isNotEmpty) storageService.cacheProfile(profile);

      setState(() {
        _profile        = profile.isNotEmpty ? profile : _profile;
        _missions       = sessions;
        _goals          = goals.take(3).toList();
        _isPremium      = profile['is_premium'] == true ||
                          profile['subscription_tier'] == 'premium';
        _totalEarned    = (income['total_earned'] as num?)?.toInt() ?? 0;
        _activeMissions = sessions.where((s) => s['status'] == 'active').length;
        _tokensLeft     = tokens['tokens_remaining'] as int? ?? 0;
        _loading        = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickAvatar() async {
    HapticFeedback.mediumImpact();
    try {
      final picker = ImagePicker();
      final img    = await picker.pickImage(
          source: ImageSource.gallery, imageQuality: 80, maxWidth: 800);
      if (img == null || !mounted) return;
      setState(() => _uploading = true);
      if (!kIsWeb) {
        final bytes = await File(img.path).readAsBytes();
        await api.uploadAvatarBytes(bytes: bytes, filename: img.name);
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Upload failed: $e'), backgroundColor: AppColors.error));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _signOut() async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1C1C1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Sign out?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: const Text('You can sign back in anytime.',
            style: TextStyle(color: Colors.white54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await authService.onLogout();
      if (mounted) context.go('/login');
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '\$${(n / 1000).toStringAsFixed(1)}K';
    return '\$$n';
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark ? Colors.black : const Color(0xFFF2F2F7);
    final cardBg    = isDark ? const Color(0xFF111111) : Colors.white;
    final borderClr = isDark
        ? Colors.white.withOpacity(0.06)
        : Colors.black.withOpacity(0.07);

    final name      = _profile['full_name']?.toString()
                   ?? _profile['username']?.toString() ?? 'Hustler';
    final stage     = _profile['stage']?.toString()    ?? 'survival';
    final bio       = _profile['bio']?.toString()      ?? '';
    final avatarUrl = _profile['avatar_url']?.toString();
    final country   = _profile['country']?.toString()  ?? '';
    final stageInfo = StageInfo.get(stage);
    final stageColor = stageInfo['color'] as Color;

    return Scaffold(
      backgroundColor: scaffoldBg,
      body: _loading && _profile.isEmpty
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // ── Collapsing header ──────────────────────────────────
                  SliverAppBar(
                    expandedHeight: 300,
                    pinned: true,
                    backgroundColor: isDark
                        ? const Color(0xFF0D0D0D)
                        : const Color(0xFFF2F2F7),
                    elevation: 0,
                    leading: IconButton(
                      icon: Icon(Icons.arrow_back_ios_new_rounded,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 20),
                      onPressed: () => context.pop(),
                    ),
                    actions: [
                      IconButton(
                        icon: Icon(Icons.settings_rounded,
                            color: isDark ? Colors.white70 : Colors.black54,
                            size: 22),
                        onPressed: () => context.push('/settings'),
                      ),
                      const SizedBox(width: 4),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      collapseMode: CollapseMode.pin,
                      background: _buildHeroHeader(isDark,
                          name, bio, country, avatarUrl, stageColor, stageInfo),
                    ),
                  ),

                  SliverToBoxAdapter(child: _buildStatsBanner(isDark, cardBg, borderClr)
                      .animate().fadeIn(duration: 300.ms, delay: 50.ms)),

                  if (!_isPremium)
                    SliverToBoxAdapter(child: _buildPremiumBanner(cardBg, borderClr)
                        .animate().fadeIn(duration: 300.ms, delay: 100.ms)),

                  SliverToBoxAdapter(child: _buildMissionsSection(isDark, cardBg, borderClr)
                      .animate().fadeIn(duration: 300.ms, delay: 150.ms)),

                  if (_goals.isNotEmpty)
                    SliverToBoxAdapter(child: _buildGoalsSection(isDark, cardBg, borderClr)
                        .animate().fadeIn(duration: 300.ms, delay: 200.ms)),

                  SliverToBoxAdapter(child: _buildQuickAccess(isDark, cardBg, borderClr)
                      .animate().fadeIn(duration: 300.ms, delay: 250.ms)),

                  SliverToBoxAdapter(child: _buildAccountSection(isDark, cardBg, borderClr)
                      .animate().fadeIn(duration: 300.ms, delay: 300.ms)),

                  const SliverToBoxAdapter(child: SizedBox(height: 48)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeroHeader(bool isDark, String name, String bio, String country,
      String? avatarUrl, Color stageColor, Map<String, dynamic> stageInfo) {
    final heroBg1 = isDark ? const Color(0xFF0D0D0D) : const Color(0xFFEEEEF4);
    final heroBg2 = isDark ? const Color(0xFF16101E) : const Color(0xFFE8E4F4);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [heroBg1, heroBg2, heroBg1],
        ),
      ),
      child: Stack(children: [
        // Glow behind avatar
        Positioned(top: 60, left: 0, right: 0,
          child: Center(child: Container(width: 160, height: 160,
            decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
              BoxShadow(color: AppColors.primary.withOpacity(0.15),
                  blurRadius: 80, spreadRadius: 14),
            ])))),

        // Content
        Positioned.fill(
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 52),

              // ── Avatar — 108px, gradient ring ─────────────────────────
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(alignment: Alignment.center, children: [
                  // Gradient ring
                  Container(
                    width: 116, height: 116,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                    ),
                  ),
                  // White gap ring
                  Container(
                    width: 110, height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF111111) : Colors.white,
                    ),
                  ),
                  // Avatar inner
                  Container(
                    width: 104, height: 104,
                    decoration: const BoxDecoration(shape: BoxShape.circle,
                        color: Color(0xFF2C2C2E)),
                    child: ClipOval(
                      child: avatarUrl != null && avatarUrl.isNotEmpty
                          ? CachedNetworkImage(imageUrl: avatarUrl,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => _fallback(name, isDark),
                              errorWidget: (_, __, ___) => _fallback(name, isDark))
                          : _fallback(name, isDark),
                    ),
                  ),
                  if (_uploading)
                    Container(width: 104, height: 104,
                      decoration: const BoxDecoration(
                          shape: BoxShape.circle, color: Colors.black54),
                      child: const Center(child: CircularProgressIndicator(
                          strokeWidth: 2.5, color: Colors.white))),

                  // Camera badge — bottom right, clear icon
                  Positioned(bottom: 4, right: 4,
                    child: Container(
                      width: 30, height: 30,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: isDark ? Colors.black : Colors.white,
                            width: 2.5),
                      ),
                      child: const Icon(Icons.camera_alt_rounded,
                          size: 14, color: Colors.white),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 14),
              Text(name, style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 23, fontWeight: FontWeight.w800,
                  letterSpacing: -0.3)),
              const SizedBox(height: 7),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _StagePill(stageInfo: stageInfo, color: stageColor),
                if (_isPremium) ...[const SizedBox(width: 8), _PremiumPill()],
              ]),
              if (country.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(country, style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.black38,
                    fontSize: 12)),
              ],
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 8),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Text(bio, textAlign: TextAlign.center,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.black45,
                        fontSize: 13, height: 1.4))),
              ],
            ]),
        ),
      ]),
    );
  }

  Widget _fallback(String name, bool isDark) => Container(
    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFDDDDEE),
    child: Center(child: Text(name.isNotEmpty ? name[0].toUpperCase() : 'R',
        style: TextStyle(
            color: isDark ? Colors.white : const Color(0xFF6C5CE7),
            fontSize: 38, fontWeight: FontWeight.bold))),
  );

  Widget _buildStatsBanner(bool isDark, Color cardBg, Color borderClr) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderClr),
      ),
      child: IntrinsicHeight(child: Row(children: [
        _StatCell(icon: Iconsax.money_recive, color: AppColors.success,
            value: _fmt(_totalEarned), label: 'Total Earned',
            onTap: () => context.push('/earnings')),
        _vDivider(isDark),
        _StatCell(icon: Iconsax.flash, color: AppColors.primary,
            value: '$_activeMissions', label: 'Missions',
            onTap: () => context.go('/home')),
        _vDivider(isDark),
        _StatCell(icon: Iconsax.flash_1, color: AppColors.gold,
            value: '$_tokensLeft', label: 'Tokens',
            onTap: _isPremium ? null : () => context.push('/premium')),
      ])),
    );
  }

  Widget _vDivider(bool isDark) => Container(width: 1,
      margin: const EdgeInsets.symmetric(vertical: 16),
      color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.07));

  Widget _buildPremiumBanner(Color cardBg, Color borderClr) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); context.push('/premium'); },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF1A1200), Color(0xFF1A0D00)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.22)),
        ),
        child: Row(children: [
          Container(width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Iconsax.crown_1, color: Colors.white, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Upgrade to Premium', style: TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 14)),
            SizedBox(height: 2),
            Text('Unlimited tokens · All features · No ads',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ])),
          const Icon(Iconsax.arrow_right_2, color: Color(0xFFFFD700), size: 18),
        ]),
      ),
    );
  }

  Widget _buildMissionsSection(bool isDark, Color cardBg, Color borderClr) {
    final active = _missions.where((m) => m['status'] != 'completed').take(3).toList();
    return _Section(
      isDark: isDark, cardBg: cardBg, borderClr: borderClr,
      title: 'My Missions',
      trailing: GestureDetector(onTap: () => context.go('/home'),
        child: const Text('See All', style: TextStyle(
            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600))),
      child: active.isEmpty
          ? _EmptyMissions(onTap: () => context.go('/home'), isDark: isDark)
          : Column(children: active.map<Widget>((m) => _MissionRow(
              emoji:  m['emoji']?.toString()  ?? '🎯',
              title:  m['title']?.toString()  ?? 'Mission',
              status: m['status']?.toString() ?? 'active',
              isDark: isDark,
              earned: ((m['income_earned'] as num?)?.toInt() ?? 0) > 0
                  ? _fmt((m['income_earned'] as num).toInt()) : null,
              onTap: () => context.go('/home?missionId=${m['id']}'),
            )).toList()),
    );
  }

  Widget _buildGoalsSection(bool isDark, Color cardBg, Color borderClr) {
    return _Section(
      isDark: isDark, cardBg: cardBg, borderClr: borderClr,
      title: 'Goals',
      trailing: GestureDetector(onTap: () => context.push('/goals'),
        child: const Text('All Goals', style: TextStyle(
            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600))),
      child: Column(children: _goals.map<Widget>((g) {
        final title  = g['title']?.toString()        ?? 'Goal';
        final target = (g['target_amount']  as num?) ?? 0;
        final curr   = (g['current_amount'] as num?)?.toDouble() ?? 0;
        final pct    = target > 0 ? (curr / target.toDouble()).clamp(0.0, 1.0) : 0.0;
        return Padding(padding: const EdgeInsets.only(bottom: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.w600, fontSize: 13))),
              Text('${(pct * 100).toInt()}%', style: TextStyle(
                  color: isDark ? AppColors.textSecondary : Colors.black45, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: pct.toDouble(), minHeight: 5,
                backgroundColor: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE0E0E0),
                color: pct >= 1.0 ? AppColors.success : AppColors.primary)),
          ]));
      }).toList()),
    );
  }

  Widget _buildQuickAccess(bool isDark, Color cardBg, Color borderClr) {
    final items = [
      (Iconsax.chart_2,     'Earnings',   '/earnings', AppColors.success),
      (Iconsax.book_1,      'Skills',     '/skills',   AppColors.primary),
      (Iconsax.task_square, 'Tasks',      '/tasks',    AppColors.info),
      (Iconsax.receipt_2,   'Income Log', '/memory',   AppColors.gold),
    ];
    return _Section(
      isDark: isDark, cardBg: cardBg, borderClr: borderClr,
      title: 'Quick Access',
      child: GridView.count(
        crossAxisCount: 4, shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10, crossAxisSpacing: 10,
        children: items.map((item) => GestureDetector(
          onTap: () { HapticFeedback.selectionClick(); context.push(item.$3); },
          child: Container(
            decoration: BoxDecoration(
              color: (item.$4).withOpacity(isDark ? 0.08 : 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: (item.$4).withOpacity(0.20)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(item.$1, color: item.$4, size: 22),
              const SizedBox(height: 5),
              Text(item.$2, style: TextStyle(color: item.$4,
                  fontSize: 10, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            ]),
          ),
        )).toList()),
    );
  }

  Widget _buildAccountSection(bool isDark, Color cardBg, Color borderClr) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderClr),
      ),
      child: Column(children: [
        _ActionRow(icon: Iconsax.edit_2, label: 'Edit Profile', isDark: isDark,
            onTap: () async { await context.push('/edit-profile'); _load(); }),
        _rowDiv(isDark),
        _ActionRow(icon: Iconsax.shield_tick, label: 'Privacy Policy',
            isDark: isDark, onTap: () => context.push('/privacy')),
        _rowDiv(isDark),
        _ActionRow(icon: Iconsax.document, label: 'Terms of Service',
            isDark: isDark, onTap: () => context.push('/terms')),
        _rowDiv(isDark),
        _ActionRow(icon: Iconsax.logout, label: 'Sign Out',
            isDark: isDark, color: AppColors.error, showArrow: false, onTap: _signOut),
      ]),
    );
  }

  Widget _rowDiv(bool isDark) => Container(height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.06));
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StagePill extends StatelessWidget {
  final Map<String, dynamic> stageInfo;
  final Color color;
  const _StagePill({required this.stageInfo, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(stageInfo['emoji'] as String, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(stageInfo['label'] as String,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _PremiumPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      gradient: const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
      borderRadius: BorderRadius.circular(20),
    ),
    child: const Text('⭐ Premium', style: TextStyle(
        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
  );
}

class _StatCell extends StatelessWidget {
  final IconData icon; final Color color;
  final String value, label; final VoidCallback? onTap;
  const _StatCell({required this.icon, required this.color,
      required this.value, required this.label, this.onTap});
  @override
  Widget build(BuildContext context) => Expanded(
    child: GestureDetector(
      onTap: onTap != null ? () { HapticFeedback.selectionClick(); onTap!(); } : null,
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 18),
        child: Column(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 16,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(
              color: AppColors.textMuted, fontSize: 10),
              textAlign: TextAlign.center),
        ])),
    ),
  );
}

class _Section extends StatelessWidget {
  final String title;
  final Widget? trailing;
  final Widget child;
  final bool isDark;
  final Color cardBg, borderClr;
  const _Section({required this.title, this.trailing, required this.child,
      required this.isDark, required this.cardBg, required this.borderClr});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: borderClr),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(title, style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14, fontWeight: FontWeight.w700)),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 14),
      child,
    ]),
  );
}

class _MissionRow extends StatelessWidget {
  final String emoji, title, status; final String? earned;
  final VoidCallback onTap; final bool isDark;
  const _MissionRow({required this.emoji, required this.title,
      required this.status, this.earned, required this.onTap,
      required this.isDark});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () { HapticFeedback.selectionClick(); onTap(); },
    child: Padding(padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 38, height: 38,
          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18)))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            Text(status == 'active' ? '⚡ Active' : '⏸ Paused',
                style: TextStyle(fontSize: 11,
                  color: status == 'active' ? AppColors.success : AppColors.warning)),
          ])),
        if (earned != null)
          Text(earned!, style: const TextStyle(color: AppColors.success,
              fontWeight: FontWeight.w700, fontSize: 13))
        else
          const Icon(Iconsax.arrow_right_2, color: AppColors.textMuted, size: 16),
      ])),
  );
}

class _EmptyMissions extends StatelessWidget {
  final VoidCallback onTap; final bool isDark;
  const _EmptyMissions({required this.onTap, required this.isDark});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(Iconsax.flash, color: isDark ? AppColors.textMuted : Colors.black26, size: 32),
    const SizedBox(height: 8),
    Text('No active missions yet',
        style: TextStyle(color: isDark ? AppColors.textMuted : Colors.black45, fontSize: 13)),
    const SizedBox(height: 12),
    GestureDetector(
      onTap: () { HapticFeedback.mediumImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: const Text('Start a Mission', style: TextStyle(
            color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    ),
    const SizedBox(height: 4),
  ]);
}

class _ActionRow extends StatelessWidget {
  final IconData icon; final String label;
  final VoidCallback onTap; final Color? color;
  final bool showArrow; final bool isDark;
  const _ActionRow({required this.icon, required this.label,
      required this.onTap, this.color, this.showArrow = true,
      required this.isDark});
  @override
  Widget build(BuildContext context) {
    final c = color ?? (isDark ? Colors.white70 : Colors.black87);
    final arrowClr = isDark ? AppColors.textMuted : Colors.black26;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      behavior: HitTestBehavior.opaque,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Icon(icon, color: c, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(color: c,
              fontSize: 14, fontWeight: FontWeight.w500))),
          if (showArrow) Icon(Iconsax.arrow_right_2, color: arrowClr, size: 16),
        ])),
    );
  }
}
