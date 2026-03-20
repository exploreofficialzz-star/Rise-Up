import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'config/app_constants.dart';
import 'services/api_service.dart';

class MainShell extends StatefulWidget {
  final Widget child;
  const MainShell({super.key, required this.child});
  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _unreadCount = 0;
  bool _checkedInToday = false;

  static const _tabs = [
    _Tab('/home',    Iconsax.home,    Iconsax.home_2,    'Home'),
    _Tab('/chat',    Iconsax.message, Iconsax.message_2, 'AI Chat'),
    _Tab('/tasks',   Iconsax.task,    Iconsax.task_square,'Tasks'),
    _Tab('/skills',  Iconsax.book,    Iconsax.book_1,    'Skills'),
    _Tab('/roadmap', Iconsax.map,     Iconsax.map_1,     'Roadmap'),
  ];

  @override
  void initState() {
    super.initState();
    _loadBadges();
  }

  Future<void> _loadBadges() async {
    try {
      final notifs = await api.getNotifications(limit: 50);
      final streak = await api.getStreak();
      if (mounted) {
        setState(() {
          _unreadCount = (notifs['unread_count'] ?? 0) as int;
          _checkedInToday = streak['checked_in_today'] == true;
        });
      }
    } catch (_) {}
  }

  int _currentIndex(BuildContext ctx) {
    final path = GoRouterState.of(ctx).uri.path;
    for (int i = 0; i < _tabs.length; i++) {
      if (path.startsWith(_tabs[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final idx = _currentIndex(context);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          border: Border(top: BorderSide(color: AppColors.bgSurface, width: 1)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 20, offset: const Offset(0, -4)),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab      = _tabs[i];
                final selected = i == idx;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      context.go(tab.path);
                      // Refresh badge counts when switching tabs
                      _loadBadges();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            selected ? tab.activeIcon : tab.icon,
                            color: selected ? AppColors.primary : AppColors.textMuted,
                            size: 22,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            tab.label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                              color: selected ? AppColors.primary : AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
      // ── Floating action buttons for quick access ──────────
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Streak check-in quick button
          if (!_checkedInToday)
            FloatingActionButton.small(
              heroTag: 'streak',
              backgroundColor: AppColors.warning,
              onPressed: () => context.go('/streak'),
              child: const Text('🔥', style: TextStyle(fontSize: 18)),
            ),
          const SizedBox(height: 8),
          // Notification bell with badge
          Stack(
            children: [
              FloatingActionButton.small(
                heroTag: 'notif',
                backgroundColor: AppColors.bgCard,
                onPressed: () => context.go('/notifications'),
                child: const Icon(Iconsax.notification, color: AppColors.textPrimary, size: 20),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 0, top: 0,
                  child: Container(
                    width: 16, height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.error, shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        _unreadCount > 9 ? '9+' : '$_unreadCount',
                        style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }
}

class _Tab {
  final String path, label;
  final IconData icon, activeIcon;
  const _Tab(this.path, this.icon, this.activeIcon, this.label);
}
