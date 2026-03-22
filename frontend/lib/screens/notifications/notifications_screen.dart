import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotifItem {
  final String avatar, name, action, time, type;
  bool read;
  _NotifItem({required this.avatar, required this.name, required this.action, required this.time, required this.type, this.read = false});
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _notifs = [
    _NotifItem(avatar: '💎', name: 'Marcus Wealth', action: 'liked your post about freelancing', time: '2m ago', type: 'like'),
    _NotifItem(avatar: '🚀', name: 'Sarah Builds', action: 'commented: "This is gold! 🔥"', time: '10m ago', type: 'comment'),
    _NotifItem(avatar: '🎯', name: 'Priya Skills', action: 'started following you', time: '1h ago', type: 'follow'),
    _NotifItem(avatar: '💼', name: 'Alex Johnson', action: 'mentioned you in a post', time: '2h ago', type: 'mention'),
    _NotifItem(avatar: '🔥', name: 'David Hustle', action: 'liked your comment', time: '3h ago', type: 'like', read: true),
    _NotifItem(avatar: '🌱', name: 'Linda Growth', action: 'started following you', time: '5h ago', type: 'follow', read: true),
    _NotifItem(avatar: '💰', name: 'James Money', action: 'replied to your comment', time: '1d ago', type: 'comment', read: true),
    _NotifItem(avatar: '🤖', name: 'RiseUp AI', action: 'Your wealth roadmap is ready! Tap to view.', time: '1d ago', type: 'ai', read: true),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final unreadBg = isDark ? AppColors.primary.withOpacity(0.08) : AppColors.primary.withOpacity(0.04);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Notifications',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          TextButton(
            onPressed: () => setState(() { for (final n in _notifs) n.read = true; }),
            child: const Text('Mark all read',
                style: TextStyle(color: AppColors.primary, fontSize: 13)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _notifs.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
        itemBuilder: (_, i) {
          final n = _notifs[i];
          return GestureDetector(
            onTap: () => setState(() => n.read = true),
            child: Container(
              color: n.read ? cardColor : unreadBg,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Avatar
                  Stack(children: [
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(child: Text(n.avatar, style: const TextStyle(fontSize: 22))),
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          color: _notifColor(n.type),
                          shape: BoxShape.circle,
                          border: Border.all(color: cardColor, width: 1.5),
                        ),
                        child: Center(child: Icon(_notifIcon(n.type), color: Colors.white, size: 10)),
                      ),
                    ),
                  ]),

                  const SizedBox(width: 12),

                  // Content
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(text: n.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                              TextSpan(text: ' ${n.action}', style: TextStyle(fontSize: 14, color: textColor, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(n.time, style: TextStyle(fontSize: 11, color: subColor)),
                      ],
                    ),
                  ),

                  // Unread dot
                  if (!n.read)
                    Container(
                      width: 8, height: 8, margin: const EdgeInsets.only(top: 6),
                      decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                    ),
                ],
              ),
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
        },
      ),
    );
  }

  Color _notifColor(String type) {
    switch (type) {
      case 'like': return Colors.red;
      case 'comment': return AppColors.primary;
      case 'follow': return AppColors.success;
      case 'mention': return AppColors.accent;
      case 'ai': return AppColors.gold;
      default: return AppColors.primary;
    }
  }

  IconData _notifIcon(String type) {
    switch (type) {
      case 'like': return Icons.favorite_rounded;
      case 'comment': return Iconsax.message;
      case 'follow': return Iconsax.user_add;
      case 'mention': return Icons.alternate_email;
      case 'ai': return Icons.auto_awesome;
      default: return Iconsax.notification;
    }
  }
}
