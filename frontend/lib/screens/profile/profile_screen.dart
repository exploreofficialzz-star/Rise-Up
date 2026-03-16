import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map _profile = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getProfile();
      setState(() { _profile = data['profile'] ?? {}; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _signOut() async {
    await api.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    final name = _profile['full_name']?.toString() ?? 'User';
    final stage = _profile['stage']?.toString() ?? 'survival';
    final stageInfo = StageInfo.get(stage);
    final isPremium = _profile['subscription_tier'] == 'premium';
    final totalEarned = (_profile['total_earned'] ?? 0.0) as num;
    final currency = _profile['currency']?.toString() ?? 'NGN';

    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Profile', style: AppTextStyles.h3),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.setting_2),
            onPressed: () {},
            tooltip: 'Settings',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Avatar & Name
                  Column(
                    children: [
                      CircleAvatar(
                        radius: 44,
                        backgroundColor: AppColors.primary.withOpacity(0.2),
                        child: Text(
                          name.isNotEmpty ? name[0].toUpperCase() : 'U',
                          style: AppTextStyles.h1.copyWith(color: AppColors.primary),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(name, style: AppTextStyles.h3),
                      const SizedBox(height: 4),
                      Text(_profile['email']?.toString() ?? '', style: AppTextStyles.bodySmall),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: (stageInfo['color'] as Color).withOpacity(0.15),
                              borderRadius: AppRadius.pill,
                            ),
                            child: Text('${stageInfo['emoji']} ${stageInfo['label']}', style: AppTextStyles.label.copyWith(color: stageInfo['color'] as Color)),
                          ),
                          if (isPremium) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
                                borderRadius: AppRadius.pill,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.workspace_premium, color: Colors.white, size: 12),
                                  const SizedBox(width: 4),
                                  Text('Premium', style: AppTextStyles.caption.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ).animate().fadeIn(),

                  const SizedBox(height: 28),

                  // Earnings
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.bgCard,
                      borderRadius: AppRadius.lg,
                      border: Border.all(color: AppColors.success.withOpacity(0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _StatItem('$currency\n${_formatAmount(totalEarned.toDouble())}', 'Total Earned', AppColors.success),
                        _Divider(),
                        _StatItem(_profile['stage']?.toString().toUpperCase() ?? 'START', 'Stage', AppColors.primary),
                        _Divider(),
                        _StatItem(_profile['wealth_type']?.toString().split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' ') ?? 'N/A', 'Type', AppColors.accent),
                      ],
                    ),
                  ).animate().fadeIn(delay: 100.ms),

                  const SizedBox(height: 20),

                  // Info tiles
                  _InfoSection(title: 'My Journey', tiles: [
                    _InfoTile(Iconsax.location, 'Location', _profile['country']?.toString() ?? 'Not set'),
                    _InfoTile(Iconsax.wallet, 'Monthly Income', '$currency ${_profile['monthly_income'] ?? 0}'),
                    _InfoTile(Iconsax.star, 'Skills', (_profile['current_skills'] as List?)?.join(', ') ?? 'Not set'),
                    _InfoTile(Iconsax.flag, 'Goal', _profile['short_term_goal']?.toString() ?? 'Not set'),
                  ]).animate().fadeIn(delay: 150.ms),

                  const SizedBox(height: 16),

                  // Actions
                  _ActionList(tiles: [
                    _ActionTile(Iconsax.edit, 'Edit Profile', AppColors.primary, () {}),
                    _ActionTile(Iconsax.message, 'Chat with AI', AppColors.accent, () => context.go('/chat')),
                    if (!isPremium) _ActionTile(Icons.workspace_premium, 'Upgrade to Premium', AppColors.gold, () => context.go('/payment')),
                    _ActionTile(Iconsax.logout, 'Sign Out', AppColors.error, _signOut),
                  ]).animate().fadeIn(delay: 200.ms),

                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  String _formatAmount(double a) {
    if (a >= 1000000) return '${(a / 1000000).toStringAsFixed(1)}M';
    if (a >= 1000) return '${(a / 1000).toStringAsFixed(1)}K';
    return a.toStringAsFixed(0);
  }
}

class _StatItem extends StatelessWidget {
  final String value, label;
  final Color color;
  const _StatItem(this.value, this.label, this.color);
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(value, style: AppTextStyles.h4.copyWith(color: color, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(label, style: AppTextStyles.caption),
    ],
  );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 40, color: AppColors.bgSurface);
}

class _InfoSection extends StatelessWidget {
  final String title;
  final List<_InfoTile> tiles;
  const _InfoSection({required this.title, required this.tiles});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: AppTextStyles.h4),
      const SizedBox(height: 12),
      Container(
        decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.lg),
        child: Column(
          children: tiles.asMap().entries.map((e) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(e.value.icon, size: 18, color: AppColors.textMuted),
                    const SizedBox(width: 12),
                    Text(e.value.label, style: AppTextStyles.label),
                    const Spacer(),
                    Flexible(child: Text(e.value.value, style: AppTextStyles.bodySmall, textAlign: TextAlign.right, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ],
                ),
              ),
              if (e.key < tiles.length - 1) Divider(height: 1, color: AppColors.bgSurface),
            ],
          )).toList(),
        ),
      ),
    ],
  );
}

class _InfoTile {
  final IconData icon; final String label, value;
  const _InfoTile(this.icon, this.label, this.value);
}

class _ActionList extends StatelessWidget {
  final List<_ActionTile> tiles;
  const _ActionList({required this.tiles});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.lg),
    child: Column(
      children: tiles.asMap().entries.map((e) => Column(
        children: [
          InkWell(
            onTap: e.value.onTap,
            borderRadius: AppRadius.md,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Icon(e.value.icon, size: 20, color: e.value.color),
                  const SizedBox(width: 12),
                  Text(e.value.label, style: AppTextStyles.body.copyWith(color: e.value.color == AppColors.error ? AppColors.error : AppColors.textPrimary)),
                  const Spacer(),
                  Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                ],
              ),
            ),
          ),
          if (e.key < tiles.length - 1) Divider(height: 1, color: AppColors.bgSurface),
        ],
      )).toList(),
    ),
  );
}

class _ActionTile {
  final IconData icon; final String label; final Color color; final VoidCallback onTap;
  const _ActionTile(this.icon, this.label, this.color, this.onTap);
}
