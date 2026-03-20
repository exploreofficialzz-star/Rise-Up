import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List _notifications = [];
  bool _loading = true;

  static const _typeIcons = {
    'streak_reminder': '🔥',
    'task_reminder':   '💰',
    'achievement':     '🏆',
    'payment':         '💳',
    'referral':        '🤝',
    'goal_milestone':  '🎯',
    'weekly_report':   '📊',
    'system':          '📢',
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final data = await api.getNotifications();
      setState(() { _notifications = data['notifications'] as List? ?? []; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _markAllRead() async {
    await api.markNotificationsRead();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final unread = _notifications.where((n) => n['is_read'] != true).length;
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Notifications', style: AppTextStyles.h3),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
                child: Text('$unread', style: AppTextStyles.caption.copyWith(color: Colors.white)),
              ),
            ],
          ],
        ),
        backgroundColor: AppColors.bgDark,
        actions: [
          if (unread > 0)
            TextButton(
              onPressed: _markAllRead,
              child: Text('Mark all read',
                  style: AppTextStyles.label.copyWith(color: AppColors.primary)),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: _notifications.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('🔔', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 16),
                      Text('No notifications yet',
                          style: AppTextStyles.h4.copyWith(color: AppColors.textSecondary)),
                      const SizedBox(height: 8),
                      Text('Check in daily to earn streak bonuses!',
                          style: AppTextStyles.body.copyWith(color: AppColors.textMuted)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _notifications.length,
                      itemBuilder: (_, i) {
                        final n   = _notifications[i];
                        final read = n['is_read'] == true;
                        final icon = _typeIcons[n['type']] ?? '📢';
                        final sentAt = DateTime.tryParse(n['sent_at'] ?? '');

                        return GestureDetector(
                          onTap: () async {
                            if (!read) {
                              await api.markNotificationsRead(ids: [n['id']]);
                              _load();
                            }
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: read ? AppColors.bgCard : AppColors.bgSurface,
                              borderRadius: AppRadius.lg,
                              border: Border.all(
                                color: read
                                    ? Colors.transparent
                                    : AppColors.primary.withOpacity(0.3),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44, height: 44,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              n['title'] ?? '',
                                              style: AppTextStyles.h4.copyWith(
                                                fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          if (!read)
                                            Container(
                                              width: 8, height: 8,
                                              decoration: const BoxDecoration(
                                                  color: AppColors.primary, shape: BoxShape.circle),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        n['body'] ?? '',
                                        style: AppTextStyles.body.copyWith(
                                            color: AppColors.textSecondary),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (sentAt != null) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          timeago.format(sentAt),
                                          style: AppTextStyles.caption,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ).animate(delay: Duration(milliseconds: i * 40)).fadeIn(duration: 300.ms),
                        );
                      },
                    ),
            ),
    );
  }
}
