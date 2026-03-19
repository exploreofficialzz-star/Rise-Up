import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _version = '';
  Map _profile = {};
  bool _notificationsEnabled = true;
  bool _dailyReminder = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final info = await PackageInfo.fromPlatform();
    final p = await api.getProfile();
    setState(() {
      _version = '${info.version} (${info.buildNumber})';
      _profile = p['profile'] as Map? ?? {};
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Settings', style: AppTextStyles.h3),
        leading: IconButton(
          icon: const Icon(Iconsax.arrow_left),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Account ──────────────────────────────────
            _SectionHeader('Account'),
            _SettingGroup(tiles: [
              _SettingTile(
                icon: Iconsax.user_edit,
                label: 'Edit Profile',
                subtitle: _profile['full_name']?.toString() ?? '',
                onTap: () => context.go('/profile'),
              ),
              _SettingTile(
                icon: Iconsax.location,
                label: 'Country & Currency',
                subtitle:
                    '${_profile['country'] ?? 'Not set'} · ${_profile['currency'] ?? 'NGN'}',
                onTap: _editCurrency,
              ),
              _SettingTile(
                icon: Iconsax.crown,
                label: 'Subscription',
                subtitle: _profile['subscription_tier'] == 'premium'
                    ? '👑 Premium Active'
                    : 'Free Tier',
                trailingColor: _profile['subscription_tier'] == 'premium'
                    ? AppColors.gold
                    : AppColors.primary,
                onTap: () => context.go('/payment'),
              ),
            ]).animate().fadeIn(delay: 50.ms),

            // ── Notifications ─────────────────────────────
            _SectionHeader('Notifications'),
            _SettingGroup(tiles: [
              _ToggleTile(
                icon: Iconsax.notification,
                label: 'Push Notifications',
                subtitle: 'Task reminders and milestone alerts',
                value: _notificationsEnabled,
                onChanged: (v) => setState(() => _notificationsEnabled = v),
              ),
              _ToggleTile(
                icon: Iconsax.clock,
                label: 'Daily Reminder',
                subtitle: 'Morning nudge to check your tasks',
                value: _dailyReminder,
                onChanged: (v) => setState(() => _dailyReminder = v),
              ),
            ]).animate().fadeIn(delay: 100.ms),

            // ── AI Settings ───────────────────────────────
            _SectionHeader('AI Mentor'),
            _SettingGroup(tiles: [
              _SettingTile(
                icon: Iconsax.cpu,
                label: 'AI Model',
                subtitle: 'Auto (uses best free model available)',
                onTap: _showModelPicker,
              ),
              _SettingTile(
                icon: Iconsax.message_text,
                label: 'Chat History',
                subtitle: 'View all past conversations',
                onTap: () => context.go('/chat'),
              ),
            ]).animate().fadeIn(delay: 150.ms),

            // ── Privacy ───────────────────────────────────
            _SectionHeader('Privacy & Legal'),
            _SettingGroup(tiles: [
              _SettingTile(
                icon: Iconsax.shield_tick,
                label: 'Privacy Policy',
                onTap: () => _openUrl('https://riseupapp.com/privacy'),
              ),
              _SettingTile(
                icon: Iconsax.document,
                label: 'Terms of Service',
                onTap: () => _openUrl('https://riseupapp.com/terms'),
              ),
              _SettingTile(
                icon: Iconsax.security_safe,
                label: 'Data & Security',
                subtitle: 'Your data is encrypted and private',
                onTap: () {},
              ),
            ]).animate().fadeIn(delay: 200.ms),

            // ── About ─────────────────────────────────────
            _SectionHeader('About'),
            _SettingGroup(tiles: [
              _SettingTile(
                icon: Iconsax.info_circle,
                label: 'App Version',
                subtitle: _version,
                onTap: () {},
              ),
              _SettingTile(
                icon: Iconsax.star,
                label: 'Rate RiseUp',
                subtitle: 'Help others find this app',
                onTap: () => _openUrl('market://details?id=com.chastech.riseup'),
              ),
              _SettingTile(
                icon: Iconsax.message_question,
                label: 'Support',
                subtitle: 'Get help from our team',
                onTap: () => _openUrl('mailto:support@riseupapp.com'),
              ),
              _SettingTile(
                icon: Iconsax.buildings,
                label: 'ChAs Tech Group',
                subtitle: 'The company behind RiseUp',
                onTap: () => _openUrl('https://chastech.com'),
              ),
            ]).animate().fadeIn(delay: 250.ms),

            // ── Danger zone ───────────────────────────────
            const SizedBox(height: 8),
            _SettingGroup(tiles: [
              _SettingTile(
                icon: Iconsax.logout,
                label: 'Sign Out',
                labelColor: AppColors.error,
                onTap: () => context.go('/privacy'),
              ),
              _SettingsTile(
                icon: Icons.article_outlined,
                iconColor: AppColors.accent,
                title: 'Terms of Service',
                onTap: () => context.go('/terms'),
              ),
              _SettingsTile(
                icon: Icons.share_rounded,
                iconColor: AppColors.success,
                title: 'Share RiseUp with Friends',
                subtitle: 'Help someone else rise up!',
                onTap: () => Share.share(
                  '🚀 I'm using RiseUp — an AI wealth mentor that helps you earn more, build skills, and reach financial freedom! Check it out: https://chastech.ng/riseup',
                  subject: 'Check out RiseUp!',
                ),
              ),
              const Divider(height: 1, color: Color(0xFF1F1F3A)),
              _SettingsTile(
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.error,
                title: 'Delete Account',
                subtitle: 'Permanently remove all your data',
                onTap: () => _confirmDeleteAccount(context),
              ),
              const Divider(height: 1, color: Color(0xFF1F1F3A)),
              _SettingsTile(
                icon: Icons.logout_rounded,
                iconColor: AppColors.error,
                title: 'Sign Out',
                onTap: _signOut,
              ),
            ]).animate().fadeIn(delay: 300.ms),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _editCurrency() {
    final currencies = [
      'NGN', 'USD', 'GBP', 'EUR', 'GHS', 'KES', 'ZAR', 'CAD', 'AUD',
    ];
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select Currency', style: AppTextStyles.h4),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: currencies
                  .map((c) => GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await api.updateProfile({'currency': c});
                          await _load();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: _profile['currency'] == c
                                ? AppColors.primary.withOpacity(0.2)
                                : AppColors.bgSurface,
                            borderRadius: AppRadius.pill,
                            border: Border.all(
                              color: _profile['currency'] == c
                                  ? AppColors.primary
                                  : Colors.transparent,
                            ),
                          ),
                          child: Text(c,
                              style: AppTextStyles.body.copyWith(
                                  color: _profile['currency'] == c
                                      ? AppColors.primary
                                      : AppColors.textPrimary)),
                        ),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showModelPicker() async {
    final models = await api.getAvailableModels();
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Available AI Models', style: AppTextStyles.h4),
            const SizedBox(height: 6),
            Text('Models are tried in order — free models first',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: 16),
            ...models.asMap().entries.map((e) {
              final name = e.value.toString();
              final isFree = ['groq', 'gemini', 'cohere'].contains(name);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: AppRadius.md,
                ),
                child: Row(children: [
                  Text('${e.key + 1}.',
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.primary)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(
                          _modelLabel(name), style: AppTextStyles.body)),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isFree
                          ? AppColors.success.withOpacity(0.15)
                          : AppColors.gold.withOpacity(0.15),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      isFree ? 'FREE' : 'PAID',
                      style: AppTextStyles.caption.copyWith(
                        color: isFree ? AppColors.success : AppColors.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  String _modelLabel(String m) {
    switch (m) {
      case 'groq':
        return '⚡ Groq — Llama 3.1 70B';
      case 'gemini':
        return '✨ Google Gemini Flash';
      case 'cohere':
        return '🤖 Cohere Command R';
      case 'openai':
        return '🧠 OpenAI GPT-4o Mini';
      case 'anthropic':
        return '🎭 Anthropic Claude Haiku';
      default:
        return m;
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Delete Account?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete your account and all data. This cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE17055)),
            child: const Text('Delete Forever'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await api.signOut();
      if (mounted) context.go('/login');
    }
  }

  Future<void> _signOut() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: Text('Sign Out?', style: AppTextStyles.h4),
        content: Text('You can sign back in anytime.',
            style: AppTextStyles.body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('Sign Out',
                  style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (confirm == true) {
      await api.signOut();
      if (mounted) context.go('/login');
    }
  }
}

// ── Helpers ───────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 10),
        child: Text(title.toUpperCase(),
            style: AppTextStyles.caption.copyWith(
                letterSpacing: 1.2,
                fontWeight: FontWeight.w700,
                color: AppColors.textMuted)),
      );
}

class _SettingGroup extends StatelessWidget {
  final List<Widget> tiles;
  const _SettingGroup({required this.tiles});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
          color: AppColors.bgCard, borderRadius: AppRadius.lg),
      child: Column(
        children: tiles.asMap().entries.map((e) {
          return Column(children: [
            e.value,
            if (e.key < tiles.length - 1)
              Divider(height: 1, color: AppColors.bgSurface,
                  indent: 52, endIndent: 16),
          ]);
        }).toList(),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color? labelColor;
  final Color? trailingColor;
  final VoidCallback? onTap;

  const _SettingTile({
    required this.icon,
    required this.label,
    this.subtitle,
    this.labelColor,
    this.trailingColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.md,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Icon(icon,
              size: 20,
              color: labelColor ?? AppColors.textSecondary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppTextStyles.body.copyWith(
                        color: labelColor ?? AppColors.textPrimary)),
                if (subtitle != null)
                  Text(subtitle!,
                      style: AppTextStyles.caption, maxLines: 1,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded,
              size: 18,
              color: trailingColor ?? AppColors.textMuted),
        ]),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.label,
    this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(children: [
        Icon(icon, size: 20, color: AppColors.textSecondary),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.body),
              if (subtitle != null)
                Text(subtitle!, style: AppTextStyles.caption),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
          activeTrackColor: AppColors.primary.withOpacity(0.3),
          inactiveTrackColor: AppColors.bgSurface,
          inactiveThumbColor: AppColors.textMuted,
        ),
      ]),
    );
  }
}
