import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../utils/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifPosts     = true;
  bool _notifComments  = true;
  bool _notifFollows   = true;
  bool _notifAI        = true;
  bool _privateAccount = false;
  bool _showOnline     = true;
  String _userEmail    = '';
  bool _loadingEmail   = true;

  static const _kSupportEmail = 'riseup.customer.carez@gmail.com';

  @override
  void initState() {
    super.initState();
    unawaited(_loadData());
  }

  Future<void> _loadData() async {
    await Future.wait([_loadUserEmail(), _loadPreferences()]);
  }

  // ── Load user email ────────────────────────────────────────────────────────
  Future<void> _loadUserEmail() async {
    try {
      // Supabase auth session is most reliable
      final supaEmail =
          Supabase.instance.client.auth.currentUser?.email ?? '';
      if (supaEmail.isNotEmpty) {
        if (mounted) setState(() { _userEmail = supaEmail; _loadingEmail = false; });
        final prefs = await SharedPreferences.getInstance();
        unawaited(prefs.setString('user_email', supaEmail));
        return;
      }

      // Fallback: SharedPreferences cached value
      final prefs = await SharedPreferences.getInstance();
      var email =
          prefs.getString('user_email') ?? prefs.getString('email') ?? '';

      if (email.isEmpty) {
        try {
          final profile = await api.getMyProfile();
          email = profile?.email ?? '';
          if (email.isNotEmpty) unawaited(prefs.setString('user_email', email));
        } catch (_) {}
      }

      if (mounted) setState(() { _userEmail = email; _loadingEmail = false; });
    } catch (_) {
      if (mounted) setState(() => _loadingEmail = false);
    }
  }

  // ── Load persisted notification / privacy prefs ────────────────────────────
  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _notifPosts     = prefs.getBool('notif_posts')     ?? true;
          _notifComments  = prefs.getBool('notif_comments')  ?? true;
          _notifFollows   = prefs.getBool('notif_follows')   ?? true;
          _notifAI        = prefs.getBool('notif_ai')        ?? true;
          _privateAccount = prefs.getBool('privacy_private') ?? false;
          _showOnline     = prefs.getBool('privacy_online')  ?? true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveNotifPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      // TODO: sync to backend notification-prefs endpoint when available
    } catch (_) {}
  }

  Future<void> _savePrivacyPref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
      // TODO: sync to backend profile privacy endpoint when available
    } catch (_) {}
  }

  // ── Change Password (bottom sheet) ────────────────────────────────────────
  void _showChangePassword(
      BuildContext ctx, bool isDark, Color text, Color sub) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _ChangePasswordSheet(isDark: isDark, text: text, sub: sub),
    );
  }

  // ── Email Address dialog ───────────────────────────────────────────────────
  void _showEmailInfo(
      BuildContext ctx, bool isDark, Color text, Color sub) {
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Email Address',
            style: TextStyle(fontWeight: FontWeight.w700, color: text)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your account email:',
                style: TextStyle(fontSize: 12, color: sub)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Text(
                _loadingEmail
                    ? 'Loading…'
                    : (_userEmail.isNotEmpty ? _userEmail : '—'),
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: text, fontSize: 14),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'To change your email address, please contact our support team.',
              style: TextStyle(color: sub, fontSize: 12, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Help & Support bottom sheet ────────────────────────────────────────────
  void _showHelp(BuildContext ctx, bool isDark, Color text, Color sub) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 24),

            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16)),
              child: const Icon(Iconsax.message_question,
                  color: AppColors.primary, size: 28),
            ),
            const SizedBox(height: 16),

            Text('Customer Support',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: text)),
            const SizedBox(height: 8),
            Text(
              'Our dedicated support team is here to assist you with any questions, account issues, or feedback about RiseUp.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: sub, height: 1.6),
            ),
            const SizedBox(height: 20),

            // Email card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: AppColors.primary.withOpacity(0.18)),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Iconsax.sms,
                          color: AppColors.primary, size: 15),
                      const SizedBox(width: 6),
                      Text('Support Email',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary)),
                    ]),
                    const SizedBox(height: 6),
                    Text(_kSupportEmail,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: text)),
                    const SizedBox(height: 4),
                    Text('Response within 3 business days',
                        style: TextStyle(fontSize: 11, color: sub)),
                  ]),
            ),
            const SizedBox(height: 10),

            // Notice
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.withOpacity(0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: Colors.amber, size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Please include your registered email and a brief description of the issue for faster assistance.',
                    style: TextStyle(fontSize: 11, color: sub, height: 1.5),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // Buttons
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    Clipboard.setData(
                        const ClipboardData(text: _kSupportEmail));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                      content: Text('Email copied to clipboard'),
                      behavior: SnackBarBehavior.floating,
                    ));
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    side: BorderSide(
                        color: AppColors.primary.withOpacity(0.5)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Copy Email',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ElevatedButton(
                    onPressed: () async {
                      final uri = Uri(
                          scheme: 'mailto',
                          path: _kSupportEmail,
                          query: 'subject=RiseUp%20Support%20Request');
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri);
                      } else {
                        Clipboard.setData(
                            const ClipboardData(text: _kSupportEmail));
                        if (ctx.mounted) {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                            content: Text(
                                'Email copied — open your mail app to contact support'),
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Send Email',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  // ── Sign Out ───────────────────────────────────────────────────────────────
  Future<void> _logout() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Sign Out?',
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87)),
        content: Text(
          'You will need to sign back in to access your account.',
          style: TextStyle(
              color: isDark ? Colors.white60 : Colors.black54, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark ? Colors.white54 : Colors.black45)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Clear local storage — non-blocking, errors do not block navigation
    try { await storageService.deleteAll(); } catch (_) {}
    try { await api.signOut(); } catch (_) {}
    // Always redirect regardless of any upstream error
    if (mounted) context.go('/login');
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black : Colors.grey.shade50;
    final cardColor   = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white : Colors.black87;
    final subColor    = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: textColor, size: 18),
          onPressed: () => context.pop(),
        ),
        title: Text('Settings',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 16),

          // ── Account ─────────────────────────────────
          _Section('Account', textColor),
          _Tile(
            icon: Iconsax.user_edit,
            label: 'Edit Profile',
            sub: 'Name, bio, location, photo',
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onTap: () => context.push('/edit-profile'),
          ),
          _Tile(
            icon: Iconsax.lock,
            label: 'Change Password',
            sub: 'Update your password',
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onTap: () =>
                _showChangePassword(context, isDark, textColor, subColor),
          ),
          _Tile(
            icon: Iconsax.sms,
            label: 'Email Address',
            sub: _loadingEmail
                ? 'Loading…'
                : (_userEmail.isNotEmpty ? _userEmail : 'Manage your email'),
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onTap: () => _showEmailInfo(context, isDark, textColor, subColor),
          ),
          _Tile(
            icon: Iconsax.crown,
            label: 'Upgrade to Premium',
            sub: 'Unlock unlimited AI access',
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            // push preserves the back stack → back arrow returns to Settings
            onTap: () => context.push('/premium'),
            trailing: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('PRO',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
          ),

          const SizedBox(height: 16),

          // ── Notifications ────────────────────────────
          _Section('Notifications', textColor),
          _SwitchTile(
            icon: Iconsax.notification,
            label: 'New Posts',
            sub: 'From people you follow',
            value: _notifPosts,
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onChanged: (v) {
              setState(() => _notifPosts = v);
              _saveNotifPref('notif_posts', v);
            },
          ),
          _SwitchTile(
            icon: Iconsax.message,
            label: 'Comments',
            sub: 'On your posts',
            value: _notifComments,
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onChanged: (v) {
              setState(() => _notifComments = v);
              _saveNotifPref('notif_comments', v);
            },
          ),
          _SwitchTile(
            icon: Iconsax.user_add,
            label: 'New Followers',
            sub: 'When someone follows you',
            value: _notifFollows,
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onChanged: (v) {
              setState(() => _notifFollows = v);
              _saveNotifPref('notif_follows', v);
            },
          ),
          _SwitchTile(
            icon: Icons.auto_awesome,
            label: 'AI Responses',
            sub: 'RiseUp AI activity',
            value: _notifAI,
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onChanged: (v) {
              setState(() => _notifAI = v);
              _saveNotifPref('notif_ai', v);
            },
          ),

          const SizedBox(height: 16),

          // ── Privacy ──────────────────────────────────
          _Section('Privacy', textColor),
          _SwitchTile(
            icon: Iconsax.lock,
            label: 'Private Account',
            sub: 'Only followers see your posts',
            value: _privateAccount,
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onChanged: (v) {
              setState(() => _privateAccount = v);
              _savePrivacyPref('privacy_private', v);
            },
          ),
          _SwitchTile(
            icon: Iconsax.eye,
            label: 'Show Online Status',
            sub: "Let others see when you're active",
            value: _showOnline,
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onChanged: (v) {
              setState(() => _showOnline = v);
              _savePrivacyPref('privacy_online', v);
            },
          ),

          const SizedBox(height: 16),

          // ── Support ──────────────────────────────────
          _Section('Support', textColor),
          _Tile(
            icon: Iconsax.message_question,
            label: 'Help & Support',
            sub: 'Contact our customer care team',
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            onTap: () => _showHelp(context, isDark, textColor, subColor),
          ),
          _Tile(
            icon: Iconsax.shield_tick,
            label: 'Privacy Policy',
            sub: 'How we protect your data',
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            // push preserves the back stack → back arrow returns to Settings
            onTap: () => context.push('/privacy'),
          ),
          _Tile(
            icon: Iconsax.document_text,
            label: 'Terms of Service',
            sub: 'Our terms and conditions',
            textColor: textColor, subColor: subColor,
            cardColor: cardColor, borderColor: borderColor,
            // push preserves the back stack → back arrow returns to Settings
            onTap: () => context.push('/terms'),
          ),

          const SizedBox(height: 16),

          // ── Sign Out ─────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            child: GestureDetector(
              onTap: _logout,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: AppColors.error.withOpacity(0.3)),
                ),
                child: const Center(
                  child: Text('Sign Out',
                      style: TextStyle(
                          color: AppColors.error,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ).animate().fadeIn(),
        ],
      ),
    );
  }
}

// ── Change Password Sheet ──────────────────────────────────────────────────────
class _ChangePasswordSheet extends StatefulWidget {
  final bool isDark;
  final Color text, sub;
  const _ChangePasswordSheet(
      {required this.isDark, required this.text, required this.sub});
  @override
  State<_ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<_ChangePasswordSheet> {
  final _formKey      = GlobalKey<FormState>();
  final _currentCtrl  = TextEditingController();
  final _newCtrl      = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _showCurrent = false;
  bool _showNew     = false;
  bool _showConfirm = false;
  bool _loading     = false;
  String? _errorMsg;

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _errorMsg = null; });

    try {
      final email =
          Supabase.instance.client.auth.currentUser?.email ?? '';
      if (email.isEmpty) {
        throw Exception(
            'Unable to verify your account. Please sign out and sign back in.');
      }

      // Re-authenticate to verify the current password
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: _currentCtrl.text.trim(),
      );

      // Apply the new password
      await Supabase.instance.client.auth
          .updateUser(UserAttributes(password: _newCtrl.text.trim()));

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Password updated successfully'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.primary,
        ));
      }
    } on AuthException catch (e) {
      setState(() {
        _errorMsg = e.message.toLowerCase().contains('invalid')
            ? 'Current password is incorrect.'
            : e.message;
      });
    } catch (e) {
      setState(() =>
          _errorMsg = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor   = widget.isDark ? AppColors.bgCard : Colors.white;
    final borderColor =
        widget.isDark ? AppColors.bgSurface : Colors.grey.shade200;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 20),

              Text('Change Password',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: widget.text)),
              const SizedBox(height: 4),
              Text('Enter your current password, then choose a new one.',
                  style: TextStyle(
                      fontSize: 12, color: widget.sub, height: 1.4)),
              const SizedBox(height: 20),

              // Current password
              _PasswordField(
                controller: _currentCtrl,
                label: 'Current Password',
                obscure: !_showCurrent,
                isDark: widget.isDark,
                textColor: widget.text,
                subColor: widget.sub,
                borderColor: borderColor,
                onToggle: () =>
                    setState(() => _showCurrent = !_showCurrent),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter your current password';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // New password
              _PasswordField(
                controller: _newCtrl,
                label: 'New Password',
                obscure: !_showNew,
                isDark: widget.isDark,
                textColor: widget.text,
                subColor: widget.sub,
                borderColor: borderColor,
                onToggle: () => setState(() => _showNew = !_showNew),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Enter a new password';
                  }
                  if (v.trim().length < 8) {
                    return 'Password must be at least 8 characters';
                  }
                  if (v.trim() == _currentCtrl.text.trim()) {
                    return 'New password must differ from your current one';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),

              // Confirm new password
              _PasswordField(
                controller: _confirmCtrl,
                label: 'Confirm New Password',
                obscure: !_showConfirm,
                isDark: widget.isDark,
                textColor: widget.text,
                subColor: widget.sub,
                borderColor: borderColor,
                onToggle: () =>
                    setState(() => _showConfirm = !_showConfirm),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please confirm your new password';
                  }
                  if (v.trim() != _newCtrl.text.trim()) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),

              // Inline error banner
              if (_errorMsg != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.error.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: AppColors.error.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline_rounded,
                        color: AppColors.error, size: 15),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_errorMsg!,
                          style: const TextStyle(
                              color: AppColors.error, fontSize: 12)),
                    ),
                  ]),
                ),
              ],

              const SizedBox(height: 20),

              // Submit
              SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.primary, AppColors.accent]),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Update Password',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Reusable password text field ───────────────────────────────────────────────
class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool obscure, isDark;
  final Color textColor, subColor, borderColor;
  final VoidCallback onToggle;
  final String? Function(String?) validator;

  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    required this.isDark,
    required this.textColor,
    required this.subColor,
    required this.borderColor,
    required this.onToggle,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: obscure,
    style: TextStyle(color: textColor, fontSize: 14),
    validator: validator,
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: subColor, fontSize: 13),
      filled: true,
      fillColor: isDark
          ? AppColors.bgSurface.withOpacity(0.5)
          : Colors.grey.shade50,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: borderColor, width: 0.8)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.primary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
              color: AppColors.error.withOpacity(0.7), width: 1)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.error, width: 1.5)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Iconsax.eye_slash : Iconsax.eye,
          color: subColor, size: 18,
        ),
        onPressed: onToggle,
      ),
    ),
  );
}

// ── Section header ─────────────────────────────────────────────────────────────
class _Section extends StatelessWidget {
  final String title;
  final Color textColor;
  const _Section(this.title, this.textColor);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
    child: Text(title,
        style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
            letterSpacing: 0.5)),
  );
}

// ── Standard tappable row ──────────────────────────────────────────────────────
class _Tile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final Color textColor, subColor, cardColor, borderColor;
  final VoidCallback onTap;
  final Widget? trailing;
  const _Tile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.textColor,
    required this.subColor,
    required this.cardColor,
    required this.borderColor,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 0.5)),
      child: Row(children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(icon, color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textColor)),
                Text(sub,
                    style: TextStyle(fontSize: 12, color: subColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ]),
        ),
        trailing ??
            Icon(Icons.chevron_right_rounded, color: subColor, size: 20),
      ]),
    ),
  );
}

// ── Toggle row ─────────────────────────────────────────────────────────────────
class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String label, sub;
  final bool value;
  final Color textColor, subColor, cardColor, borderColor;
  final Function(bool) onChanged;
  const _SwitchTile({
    required this.icon,
    required this.label,
    required this.sub,
    required this.value,
    required this.textColor,
    required this.subColor,
    required this.cardColor,
    required this.borderColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(16, 0, 16, 2),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 0.5)),
    child: Row(children: [
      Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: AppColors.primary, size: 18),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textColor)),
              Text(sub, style: TextStyle(fontSize: 12, color: subColor)),
            ]),
      ),
      Switch.adaptive(
          value: value, onChanged: onChanged, activeColor: AppColors.primary),
    ]),
  );
}
