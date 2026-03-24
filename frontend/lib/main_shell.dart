import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'config/app_constants.dart';
import 'services/api_service.dart';

// Global key so any screen can call MainShell.refresh() after
// reading notifications or messages.
final mainShellKey = GlobalKey<_MainShellState>();

class MainShell extends StatefulWidget {
  final Widget child;
  MainShell({Key? key, required this.child}) : super(key: mainShellKey);

  /// Call this from any screen to refresh nav-bar badge counts.
  static void refresh() {
    mainShellKey.currentState?._fetchCounts();
  }

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _unreadMessages = 0;
  int _unreadNotifs   = 0;

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
          _unreadNotifs   = unreadNotifs;
          _unreadMessages = unreadMsgs;
        });
      }
    } catch (_) {
      // Silent fail — badges stay at 0
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
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final idx     = _currentIndex(context);
    final bgColor = isDark ? AppColors.bgCard : Colors.white;
    final border  = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    // Icons: white on dark, near-black on light
    final iconOff = isDark ? Colors.white60 : Colors.black45;

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: bgColor,
          border: Border(top: BorderSide(color: border, width: 0.8)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.25 : 0.07),
              blurRadius: 12,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              children: List.generate(_tabs.length, (i) {
                final tab      = _tabs[i];
                final selected = i == idx;
                final isCreate = tab.path == '/create';

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      if (tab.path == '/messages' || tab.path == '/profile') {
                        _fetchCounts();
                      }
                      context.go(tab.path);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: isCreate
                        ? _CreateButton()
                        : _NavItem(
                            tab: tab,
                            selected: selected,
                            iconOff: iconOff,
                            badge: tab.path == '/messages'
                                ? _unreadMessages
                                : tab.path == '/profile'
                                    ? _unreadNotifs
                                    : 0,
                            badgeColor: tab.path == '/messages'
                                ? AppColors.error
                                : AppColors.primary,
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

// ── Create FAB ────────────────────────────────────────────────────────
class _CreateButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Iconsax.add, color: Colors.white, size: 22),
    );
  }
}

// ── Nav item ──────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final _Tab tab;
  final bool selected;
  final Color iconOff;
  final int badge;
  final Color badgeColor;

  const _NavItem({
    required this.tab,
    required this.selected,
    required this.iconOff,
    required this.badge,
    required this.badgeColor,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = selected ? AppColors.primary : iconOff;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              selected ? tab.activeIcon : tab.icon,
              color: iconColor,
              size: 24,
            ),
            if (badge > 0)
              Positioned(
                right: -5,
                top: -4,
                child: Container(
                  width: 15,
                  height: 15,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      badge > 9 ? '9+' : '$badge',
                      style: const TextStyle(
                        fontSize: 7,
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          tab.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: iconColor,
          ),
        ),
      ],
    );
  }
}

class _Tab {
  final String path, label;
  final IconData icon, activeIcon;
  const _Tab(this.path, this.icon, this.activeIcon, this.label);
}
