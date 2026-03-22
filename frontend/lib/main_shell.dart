import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _unreadMessages = 0;
  int _unreadNotifs = 0;

  static const _tabs = [
    _Tab('/home',     Iconsax.home,          Iconsax.home_2,          'Home'),
    _Tab('/explore',  Iconsax.search_normal, Iconsax.search_normal_1, 'Explore'),
    _Tab('/create',   Iconsax.add_square,    Iconsax.add_square,      'Post'),
    _Tab('/messages', Iconsax.message,       Iconsax.message_2,       'Messages'),
    _Tab('/profile',  Iconsax.user,          Iconsax.user_octagon,    'Profile'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _fetchCounts();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Refresh counts when app comes back to foreground
    if (state == AppLifecycleState.resumed) _fetchCounts();
  }

  Future<void> _fetchCounts() async {
    try {
      final results = await Future.wait([
        api.getNotifications(limit: 50),
        api.get('/messages/conversations'),
      ]);

      final notifs = results[0] as Map;
      final convos = results[1] as Map? ?? {};

      final unreadNotifs = (notifs['notifications'] as List? ?? [])
          .where((n) => n['is_read'] == false)
          .length;

      final unreadMsgs = (convos['conversations'] as List? ?? [])
          .where((c) => (c['unread_count'] as int? ?? 0) > 0)
          .fold<int>(0, (sum, c) => sum + ((c['unread_count'] as int?) ?? 0));

      if (mounted) {
        setState(() {
          _unreadNotifs = unreadNotifs;
          _unreadMessages = unreadMsgs;
        });
      }
    } catch (_) {
      // Silent fail — badges just stay at 0
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final idx = _currentIndex(context);
    final bgColor = isDark ? AppColors.bgCard : Colors.white;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final iconColor = isDark ? Colors.white60 : Colors.black45;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: borderColor, width: 0.8)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(isDark ? 0.2 : 0.06), blurRadius: 10, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab = _tabs[i];
                final selected = i == idx;
                final isCreate = tab.path == '/create';

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      // Refresh counts when tapping messages or profile
                      if (tab.path == '/messages' || tab.path == '/profile') {
                        _fetchCounts();
                      }
                      context.go(tab.path);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: isCreate
                        ? Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            padding: const EdgeInsets.symmetric(vertical: 9),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(Iconsax.add, color: Colors.white, size: 22),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Icon(
                                    selected ? tab.activeIcon : tab.icon,
                                    color: selected ? AppColors.primary : iconColor,
                                    size: 24,
                                  ),
                                  // Messages badge
                                  if (tab.path == '/messages' && _unreadMessages > 0)
                                    Positioned(right: -4, top: -4, child: Container(
                                      width: 14, height: 14,
                                      decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                                      child: Center(child: Text(
                                        _unreadMessages > 9 ? '9+' : '$_unreadMessages',
                                        style: const TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.w700),
                                      )),
                                    )),
                                  // Notifications badge (on Profile icon)
                                  if (tab.path == '/profile' && _unreadNotifs > 0)
                                    Positioned(right: -4, top: -4, child: Container(
                                      width: 14, height: 14,
                                      decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                      child: Center(child: Text(
                                        _unreadNotifs > 9 ? '9+' : '$_unreadNotifs',
                                        style: const TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.w700),
                                      )),
                                    )),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                tab.label,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                                  color: selected ? AppColors.primary : iconColor,
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab {
  final String path, label;
  final IconData icon, activeIcon;
  const _Tab(this.path, this.icon, this.activeIcon, this.label);
}
