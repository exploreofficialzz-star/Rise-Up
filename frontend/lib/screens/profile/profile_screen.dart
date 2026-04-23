// frontend/lib/screens/profile/profile_screen.dart
// RiseUp v3.0 — Income Profile
// No posts. No followers. No social.
// Shows: avatar, stage, total earned, missions, skills, goals, settings.
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

// ─────────────────────────────────────────────────────────────────────────────
// Stage helper
// ─────────────────────────────────────────────────────────────────────────────
class StageInfo {
  static Map<String, dynamic> get(String stage) {
    const map = <String, Map<String, dynamic>>{
      'survival':  {'emoji': '🆘', 'label': 'Survival',  'color': Color(0xFFE17055)},
      'earning':   {'emoji': '💪', 'label': 'Earning',   'color': Color(0xFF0984E3)},
      'growing':   {'emoji': '🚀', 'label': 'Growing',   'color': Color(0xFF00B894)},
      'wealth':    {'emoji': '💎', 'label': 'Wealth',    'color': Color(0xFF6C5CE7)},
      'legacy':    {'emoji': '🏛️', 'label': 'Legacy',   'color': Color(0xFF9B59B6)},
    };
    return map[stage.toLowerCase()] ?? map['survival']!;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ProfileScreen
// ─────────────────────────────────────────────────────────────────────────────
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with WidgetsBindingObserver {

  Map<String, dynamic> _profile      = {};
  List<dynamic>        _missions     = [];
  List<dynamic>        _goals        = [];
  bool                 _loading      = true;
  bool                 _uploading    = false;
  int                  _totalEarned  = 0;
  int                  _activeMissions = 0;
  int                  _tokensToday  = 0;
  bool                 _isPremium    = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/auth/me'),
        api.get('/mentor/sessions'),
        api.get('/goals'),
        api.get('/agent/tokens'),
        api.get('/income_memory/summary'),
      ], eagerError: false);

      final profile  = results[0] as Map<String, dynamic>? ?? {};
      final sessions = (results[1] as Map?)?['sessions'] as List? ?? [];
      final goals    = (results[2] as Map?)?['goals']    as List? ?? [];
      final tokens   = results[3] as Map<String, dynamic>? ?? {};
      final income   = results[4] as Map<String, dynamic>? ?? {};

      setState(() {
        _profile        = profile;
        _missions       = sessions;
        _goals          = goals.take(3).toList();
        _isPremium      = profile['is_premium'] == true ||
                          profile['subscription_tier'] == 'premium';
        _totalEarned    = (income['total_earned'] as num?)?.toInt() ?? 0;
        _activeMissions = sessions.where((s) =>
            s['status'] == 'active').length;
        _tokensToday    = tokens['tokens_remaining'] as int? ?? 0;
        _loading        = false;
      });
    } catch (_) {
      setState(() => _loading = false);
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
      final file  = File(img.path);
      final bytes = await file.readAsBytes();
      await api.uploadAvatar(bytes, img.name);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _signOut() async {
    HapticFeedback.heavyImpact();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Sign out?', style: TextStyle(color: Colors.white)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await authService.signOut();
      if (mounted) context.go('/login');
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) return '\$${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '\$${(n / 1000).toStringAsFixed(1)}K';
    return '\$$n';
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final name      = _profile['full_name']?.toString()       ??
                      _profile['username']?.toString()        ?? 'Hustler';
    final stage     = _profile['stage']?.toString()           ?? 'survival';
    final bio       = _profile['bio']?.toString()             ?? '';
    final avatarUrl = _profile['avatar_url']?.toString();
    final stageInfo = StageInfo.get(stage);
    final stageColor= stageInfo['color'] as Color;

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        backgroundColor: AppColors.bgCard,
        elevation: 0,
        title: RichText(text: const TextSpan(children: [
          TextSpan(text: 'Rise', style: TextStyle(fontSize: 20,
              fontWeight: FontWeight.w800, color: Color(0xFFFF6B00))),
          TextSpan(text: 'Up', style: TextStyle(fontSize: 20,
              fontWeight: FontWeight.w800, color: AppColors.primary)),
        ])),
        centerTitle: false,
        actions: [
          IconButton(icon: const Icon(Iconsax.edit_2, color: Colors.white70),
              tooltip: 'Edit profile',
              onPressed: () async {
                await context.push('/edit-profile');
                _load();
              }),
          IconButton(icon: const Icon(Iconsax.setting_2, color: Colors.white70),
              onPressed: () => context.push('/settings')),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(children: [

                  // ── Header card ──────────────────────────────────────────
                  _buildHeader(name, stage, bio, avatarUrl, stageColor, stageInfo),

                  const SizedBox(height: 8),

                  // ── Income stats ─────────────────────────────────────────
                  _buildIncomeStats(),

                  const SizedBox(height: 8),

                  // ── Active missions ───────────────────────────────────────
                  _buildMissionsCard(),

                  const SizedBox(height: 8),

                  // ── Goals snapshot ────────────────────────────────────────
                  if (_goals.isNotEmpty) _buildGoalsCard(),

                  const SizedBox(height: 8),

                  // ── Quick links ───────────────────────────────────────────
                  _buildQuickLinks(),

                  const SizedBox(height: 8),

                  // ── Account ───────────────────────────────────────────────
                  _buildAccountCard(),

                  const SizedBox(height: 32),
                ]),
              ),
            ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader(String name, String stage, String bio,
      String? avatarUrl, Color stageColor, Map stageInfo) {
    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.bgCard,
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Avatar
        GestureDetector(
          onTap: _pickAvatar,
          child: Stack(children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: AppColors.primary,
              backgroundImage: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImageProvider(avatarUrl) : null,
              child: avatarUrl == null || avatarUrl.isEmpty
                  ? Text(name.isNotEmpty ? name[0].toUpperCase() : 'R',
                      style: const TextStyle(fontSize: 28, color: Colors.white,
                          fontWeight: FontWeight.bold))
                  : null,
            ),
            if (_uploading)
              Positioned.fill(child: Container(
                decoration: BoxDecoration(
                    color: Colors.black45, shape: BoxShape.circle),
                child: const Center(child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white)),
              )),
            Positioned(bottom: 0, right: 0,
              child: Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bgCard, width: 2)),
                child: const Icon(Iconsax.camera, size: 12, color: Colors.white),
              )),
          ]),
        ),

        const SizedBox(width: 16),

        // Name + stage + bio
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
              color: Colors.white)),
          const SizedBox(height: 4),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: stageColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: stageColor.withOpacity(0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(stageInfo['emoji'] as String,
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 4),
                Text(stageInfo['label'] as String,
                    style: TextStyle(color: stageColor, fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
            if (_isPremium) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('⭐ Premium', style: TextStyle(
                    color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ]),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(bio, style: const TextStyle(color: AppColors.textSecondary,
                fontSize: 13, height: 1.4), maxLines: 3, overflow: TextOverflow.ellipsis),
          ],
        ])),
      ]),
    ).animate().fadeIn(duration: 300.ms);
  }

  // ── Income stats ──────────────────────────────────────────────────────────
  Widget _buildIncomeStats() {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        _StatTile(label: 'Total Earned', value: _fmt(_totalEarned),
            icon: Iconsax.money_recive, color: AppColors.success,
            onTap: () => context.push('/earnings')),
        _vDivider(),
        _StatTile(label: 'Active Missions', value: '$_activeMissions',
            icon: Iconsax.flash, color: AppColors.primary,
            onTap: () => context.go('/home')),
        _vDivider(),
        _StatTile(label: 'Tokens Left', value: '$_tokensToday',
            icon: Iconsax.flash_1, color: AppColors.gold,
            onTap: _isPremium ? null : () => context.push('/premium')),
      ]),
    ).animate().fadeIn(duration: 350.ms, delay: 50.ms);
  }

  Widget _vDivider() => Container(width: 1, height: 48, color: AppColors.bgSurface);

  // ── Missions card ─────────────────────────────────────────────────────────
  Widget _buildMissionsCard() {
    final active = _missions
        .where((m) => m['status'] != 'completed')
        .take(3)
        .toList();

    return _Card(
      title: 'My Missions',
      action: 'See All',
      onAction: () => context.go('/home'),
      child: active.isEmpty
          ? _EmptyState(icon: Iconsax.flash, message: 'No active missions yet.\nTap below to start one.',
              actionLabel: 'Start a Mission', onAction: () => context.go('/home'))
          : Column(children: active.map<Widget>((m) {
              final emoji   = m['emoji']?.toString()    ?? '🎯';
              final title   = m['title']?.toString()    ?? 'Mission';
              final status  = m['status']?.toString()   ?? 'active';
              final earned  = (m['income_earned'] as num?)?.toInt() ?? 0;
              return ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                leading: Container(width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8)),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 18)))),
                title: Text(title, style: const TextStyle(color: Colors.white,
                    fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: Text(status == 'active' ? '⚡ Active' : '⏸ Paused',
                    style: TextStyle(color: status == 'active'
                        ? AppColors.success : AppColors.warning, fontSize: 12)),
                trailing: earned > 0
                    ? Text(_fmt(earned), style: const TextStyle(color: AppColors.success,
                        fontWeight: FontWeight.w700))
                    : const Icon(Iconsax.arrow_right_2, color: AppColors.textMuted, size: 16),
                onTap: () => context.go('/home?missionId=${m['id']}'),
              );
            }).toList()),
    ).animate().fadeIn(duration: 350.ms, delay: 100.ms);
  }

  // ── Goals card ────────────────────────────────────────────────────────────
  Widget _buildGoalsCard() {
    return _Card(
      title: 'Goals',
      action: 'All Goals',
      onAction: () => context.push('/goals'),
      child: Column(children: _goals.map<Widget>((g) {
        final title    = g['title']?.toString()       ?? 'Goal';
        final target   = (g['target_amount'] as num?) ?? 0;
        final current  = (g['current_amount'] as num?)?.toDouble() ?? 0;
        final progress = target > 0 ? (current / target.toDouble()).clamp(0.0, 1.0) : 0.0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13))),
              Text('${(progress * 100).toInt()}%',
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress.toDouble(),
                minHeight: 6,
                backgroundColor: AppColors.bgSurface,
                color: progress >= 1.0 ? AppColors.success : AppColors.primary,
              ),
            ),
          ]),
        );
      }).toList()),
    ).animate().fadeIn(duration: 350.ms, delay: 150.ms);
  }

  // ── Quick links ───────────────────────────────────────────────────────────
  Widget _buildQuickLinks() {
    final items = [
      (Iconsax.chart_2,   'Earnings',      '/earnings',   AppColors.success),
      (Iconsax.book_1,    'Skills',        '/skills',     AppColors.primary),
      (Iconsax.task_square,'Tasks',        '/tasks',      AppColors.info),
      (Iconsax.receipt_2, 'Income Log',    '/memory',     AppColors.gold),
    ];
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Quick Access', style: TextStyle(color: AppColors.textSecondary,
            fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: items.map((item) => GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); context.push(item.$3); },
            child: Container(
              decoration: BoxDecoration(
                color: (item.$4).withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: (item.$4).withOpacity(0.2)),
              ),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(item.$1, color: item.$4, size: 22),
                const SizedBox(height: 4),
                Text(item.$2, style: TextStyle(color: item.$4,
                    fontSize: 10, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center),
              ]),
            ),
          )).toList(),
        ),
      ]),
    ).animate().fadeIn(duration: 350.ms, delay: 200.ms);
  }

  // ── Account card ──────────────────────────────────────────────────────────
  Widget _buildAccountCard() {
    return Container(
      color: AppColors.bgCard,
      child: Column(children: [
        if (!_isPremium)
          ListTile(
            leading: Container(width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFFD700), Color(0xFFFF8C00)]),
                borderRadius: BorderRadius.circular(8)),
              child: const Icon(Iconsax.crown_1, color: Colors.white, size: 18)),
            title: const Text('Upgrade to Premium',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            subtitle: const Text('Unlimited tokens · All features · No ads',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
            trailing: const Icon(Iconsax.arrow_right_2, color: AppColors.gold, size: 16),
            onTap: () => context.push('/premium'),
          ),
        _NavTile(icon: Iconsax.edit_2,      label: 'Edit Profile',
            onTap: () async { await context.push('/edit-profile'); _load(); }),
        _NavTile(icon: Iconsax.setting_2,   label: 'Settings',
            onTap: () => context.push('/settings')),
        _NavTile(icon: Iconsax.shield_tick, label: 'Privacy Policy',
            onTap: () => context.push('/privacy')),
        _NavTile(icon: Iconsax.document,    label: 'Terms of Service',
            onTap: () => context.push('/terms')),
        Divider(color: AppColors.bgSurface, height: 1),
        _NavTile(
          icon: Iconsax.logout,
          label: 'Sign Out',
          color: AppColors.error,
          onTap: _signOut,
        ),
        const SizedBox(height: 8),
      ]),
    ).animate().fadeIn(duration: 350.ms, delay: 250.ms);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Reusable widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String title, action;
  final VoidCallback onAction;
  final Widget child;
  const _Card({required this.title, required this.action,
      required this.onAction, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(title, style: const TextStyle(color: Colors.white,
              fontSize: 15, fontWeight: FontWeight.w700)),
          const Spacer(),
          GestureDetector(
            onTap: () { HapticFeedback.selectionClick(); onAction(); },
            child: Text(action, style: const TextStyle(
                color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: 12),
        child,
        const SizedBox(height: 8),
      ]),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  const _StatTile({required this.label, required this.value,
      required this.icon, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(child: GestureDetector(
      onTap: onTap != null ? () { HapticFeedback.selectionClick(); onTap!(); } : null,
      child: Column(children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(value, style: TextStyle(color: color,
            fontSize: 17, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 10),
            textAlign: TextAlign.center),
      ]),
    ));
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String   label;
  final VoidCallback onTap;
  final Color?   color;
  const _NavTile({required this.icon, required this.label,
      required this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white70;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: c, size: 20),
      title: Text(label, style: TextStyle(color: c, fontSize: 14)),
      trailing: color == null
          ? const Icon(Iconsax.arrow_right_2, color: AppColors.textMuted, size: 16)
          : null,
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String   message, actionLabel;
  final VoidCallback onAction;
  const _EmptyState({required this.icon, required this.message,
      required this.actionLabel, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(children: [
        Icon(icon, color: AppColors.textMuted, size: 36),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13, height: 1.5)),
        const SizedBox(height: 14),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          onPressed: () { HapticFeedback.mediumImpact(); onAction(); },
          child: Text(actionLabel),
        ),
      ]),
    );
  }
}
