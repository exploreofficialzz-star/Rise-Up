import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../utils/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifPosts = true;
  bool _notifComments = true;
  bool _notifFollows = true;
  bool _notifAI = true;
  bool _privateAccount = false;
  bool _showOnline = true;

  Future<void> _logout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign out?', style: TextStyle(fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
        content: Text('You can sign back in anytime.', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await storageService.deleteAll();
      await api.signOut();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.grey.shade50;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // ── Account ───────────────────────────────────
          _Section('Account', textColor),
          _Tile(icon: Iconsax.user_edit, label: 'Edit Profile', sub: 'Name, bio, location', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () {}),
          _Tile(icon: Iconsax.lock, label: 'Change Password', sub: 'Update your password', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () {}),
          _Tile(icon: Iconsax.sms, label: 'Email Address', sub: 'Manage your email', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () {}),
          _Tile(icon: Iconsax.crown, label: 'Upgrade to Premium', sub: 'Unlock unlimited AI access', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () => context.go('/premium'),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(10)),
                child: const Text('PRO', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
              )),

          const SizedBox(height: 16),

          // ── Notifications ─────────────────────────────
          _Section('Notifications', textColor),
          _SwitchTile(icon: Iconsax.notification, label: 'New Posts', sub: 'From people you follow', value: _notifPosts, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onChanged: (v) => setState(() => _notifPosts = v)),
          _SwitchTile(icon: Iconsax.message, label: 'Comments', sub: 'On your posts', value: _notifComments, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onChanged: (v) => setState(() => _notifComments = v)),
          _SwitchTile(icon: Iconsax.user_add, label: 'New Followers', sub: 'When someone follows you', value: _notifFollows, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onChanged: (v) => setState(() => _notifFollows = v)),
          _SwitchTile(icon: Icons.auto_awesome, label: 'AI Responses', sub: 'RiseUp AI activity', value: _notifAI, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onChanged: (v) => setState(() => _notifAI = v)),

          const SizedBox(height: 16),

          // ── Privacy ───────────────────────────────────
          _Section('Privacy', textColor),
          _SwitchTile(icon: Iconsax.lock, label: 'Private Account', sub: 'Only followers see your posts', value: _privateAccount, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onChanged: (v) => setState(() => _privateAccount = v)),
          _SwitchTile(icon: Iconsax.eye, label: 'Show Online Status', sub: 'Let others see when you\'re active', value: _showOnline, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onChanged: (v) => setState(() => _showOnline = v)),

          const SizedBox(height: 16),

          // ── Support ───────────────────────────────────
          _Section('Support', textColor),
          _Tile(icon: Iconsax.message_question, label: 'Help & FAQ', sub: 'Get answers', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () {}),
          _Tile(icon: Iconsax.shield_tick, label: 'Privacy Policy', sub: 'How we protect your data', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () => context.go('/privacy')),
          _Tile(icon: Iconsax.document_text, label: 'Terms of Service', sub: 'Our terms', textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, onTap: () => context.go('/terms')),

          const SizedBox(height: 16),

          // ── Sign out ──────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: GestureDetector(
              onTap: _logout,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: const Center(
                  child: Text('Sign Out', style: TextStyle(color: AppColors.error, fontSize: 15, fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ).animate().fadeIn(),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Color textColor;
  const _Section(this.title, this.textColor);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary, letterSpacing: 0.5)),
  );
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color textColor, subColor, cardColor, borderColor;
  final VoidCallback onTap;
  final Widget? trailing;
  const _Tile({required this.icon, required this.label, required this.sub, required this.textColor, required this.subColor, required this.cardColor, required this.borderColor, required this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor, width: 0.5)),
      child: Row(children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primary, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
          Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
        ])),
        trailing ?? Icon(Icons.chevron_right_rounded, color: subColor, size: 20),
      ]),
    ),
  );
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final bool value;
  final Color textColor, subColor, cardColor, borderColor;
  final Function(bool) onChanged;
  const _SwitchTile({required this.icon, required this.label, required this.sub, required this.value, required this.textColor, required this.subColor, required this.cardColor, required this.borderColor, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: borderColor, width: 0.5)),
    child: Row(children: [
      Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primary, size: 18)),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textColor)),
        Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
      ])),
      Switch.adaptive(value: value, onChanged: onChanged, activeColor: AppColors.primary),
    ]),
  );
}
