import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../main_shell.dart';
import '../../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notifs = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getNotifications(limit: 50);
      if (mounted) setState(() { _notifs = data['notifications'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    try {
      await api.markNotificationsRead();
      setState(() {
        for (final n in _notifs) n['is_read'] = true;
      });
      MainShell.refresh(); // update badge count in nav bar
    } catch (_) {}
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  Color _notifColor(String? type) {
    switch (type) {
      case 'like': return Colors.red;
      case 'comment': return AppColors.primary;
      case 'follow': return AppColors.success;
      case 'mention': return AppColors.accent;
      case 'coins': return AppColors.gold;
      case 'ai': return AppColors.primary;
      case 'message': return AppColors.accent;
      default: return AppColors.primary;
    }
  }

  IconData _notifIcon(String? type) {
    switch (type) {
      case 'like': return Icons.favorite_rounded;
      case 'comment': return Iconsax.message;
      case 'follow': return Iconsax.user_add;
      case 'mention': return Icons.alternate_email;
      case 'coins': return Icons.monetization_on;
      case 'ai': return Icons.auto_awesome;
      case 'message': return Iconsax.message_2;
      default: return Iconsax.notification;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final unreadBg = isDark ? AppColors.primary.withOpacity(0.07) : AppColors.primary.withOpacity(0.04);
    final unread = _notifs.where((n) => n['is_read'] != true).length;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
          if (unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(10)),
              child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: const Text('Mark all read', style: TextStyle(color: AppColors.primary, fontSize: 13)),
            ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: borderColor)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _notifs.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('🔔', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text('No notifications yet', style: TextStyle(color: subColor, fontSize: 14)),
                  const SizedBox(height: 8),
                  Text('Start engaging with the community!', style: TextStyle(color: subColor, fontSize: 12)),
                ]))
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: _notifs.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
                    itemBuilder: (_, i) {
                      final n = _notifs[i];
                      final isRead = n['is_read'] == true;
                      final type = n['type']?.toString();

                      return GestureDetector(
                        onTap: () async {
                          if (!isRead) {
                            await api.markNotificationsRead(ids: [n['id'].toString()]);
                            MainShell.refresh();
                            setState(() => n['is_read'] = true);
                          }
                          // Navigate based on type
                          final data = n['data'] as Map? ?? {};
                          if (data['post_id'] != null) context.go('/comments/${data['post_id']}');
                          else if (data['conversation_id'] != null) context.go('/conversation/${data['conversation_id']}');
                        },
                        child: Container(
                          color: isRead ? cardColor : unreadBg,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Stack(children: [
                              Container(
                                width: 46, height: 46,
                                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                                child: Center(child: Text(
                                  n['sender_avatar']?.toString() ?? '👤',
                                  style: const TextStyle(fontSize: 22),
                                )),
                              ),
                              Positioned(bottom: 0, right: 0, child: Container(
                                width: 18, height: 18,
                                decoration: BoxDecoration(color: _notifColor(type), shape: BoxShape.circle, border: Border.all(color: cardColor, width: 1.5)),
                                child: Center(child: Icon(_notifIcon(type), color: Colors.white, size: 10)),
                              )),
                            ]),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              RichText(
                                text: TextSpan(children: [
                                  TextSpan(text: n['message']?.toString() ?? '', style: TextStyle(fontSize: 14, color: textColor, height: 1.4)),
                                ]),
                              ),
                              const SizedBox(height: 4),
                              Text(_timeAgo(n['created_at']?.toString()), style: TextStyle(fontSize: 11, color: subColor)),
                            ])),
                            if (!isRead)
                              Container(width: 8, height: 8, margin: const EdgeInsets.only(top: 6), decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)),
                          ]),
                        ),
                      ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
                    },
                  ),
                ),
    );
  }
}
