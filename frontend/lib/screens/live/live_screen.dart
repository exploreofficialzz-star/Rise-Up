import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveSession {
  final String id, host, avatar, title, topic, viewers;
  final bool isPremium, isEarner;
  final int coins;
  const _LiveSession({
    required this.id, required this.host, required this.avatar,
    required this.title, required this.topic, required this.viewers,
    this.isPremium = false, this.isEarner = true, this.coins = 0,
  });
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  static const _sessions = [
    _LiveSession(id: '1', host: 'Marcus Wealth', avatar: '💎', title: 'How I make \$10K/month with 3 income streams', topic: '💰 Wealth', viewers: '1.2K', isEarner: true, coins: 500),
    _LiveSession(id: '2', host: 'Priya Skills', avatar: '🎯', title: 'Freelancing masterclass — getting your first client', topic: '💼 Business', viewers: '847', isEarner: true, isPremium: true, coins: 200),
    _LiveSession(id: '3', host: 'Alex Johnson', avatar: '💼', title: 'Stock market basics for beginners', topic: '📈 Investing', viewers: '2.1K', isEarner: true, coins: 800),
    _LiveSession(id: '4', host: 'Sarah Builds', avatar: '🚀', title: 'Building passive income from scratch', topic: '⚡ Hustle', viewers: '634', isPremium: true, coins: 350),
    _LiveSession(id: '5', host: 'David Hustle', avatar: '🔥', title: 'Graphic design to agency: my full journey', topic: '🎯 Skills', viewers: '421', isEarner: true, coins: 150),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _goLive(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GoLiveSheet(isDark: isDark),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
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
        title: Text('Live', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          // Go Live button
          GestureDetector(
            onTap: () => _goLive(context),
            child: Container(
              margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Colors.red, Color(0xFFFF6B00)]),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.circle, color: Colors.white, size: 8),
                SizedBox(width: 6),
                Text('Go Live', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: subColor,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Live Now'), Tab(text: 'Scheduled'), Tab(text: 'Replays')],
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Live Now
          ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _sessions.length,
            itemBuilder: (_, i) {
              final s = _sessions[i];
              return GestureDetector(
                onTap: () => context.go('/live-viewer/${s.id}?host=${Uri.encodeComponent(s.host)}&title=${Uri.encodeComponent(s.title)}'),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Thumbnail
                      Container(
                        height: 160,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary.withOpacity(0.8),
                              AppColors.accent.withOpacity(0.6),
                            ],
                          ),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Stack(children: [
                          Center(child: Text(s.avatar, style: const TextStyle(fontSize: 64))),
                          // LIVE badge
                          Positioned(top: 12, left: 12, child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: const [
                              Icon(Icons.circle, color: Colors.white, size: 6),
                              SizedBox(width: 4),
                              Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                            ]),
                          )),
                          // Premium badge
                          if (s.isPremium)
                            Positioned(top: 12, right: 12, child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('⭐ Premium', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                            )),
                          // Viewers
                          Positioned(bottom: 12, right: 12, child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 13),
                              const SizedBox(width: 4),
                              Text(s.viewers, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          )),
                          // Coins
                          Positioned(bottom: 12, left: 12, child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              const Text('🪙', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 4),
                              Text('${s.coins}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          )),
                        ]),
                      ),

                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                            child: Center(child: Text(s.avatar, style: const TextStyle(fontSize: 18))),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(s.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Row(children: [
                              Text(s.host, style: TextStyle(fontSize: 11, color: subColor)),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                                child: Text(s.topic, style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600)),
                              ),
                            ]),
                          ])),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: s.isPremium ? AppColors.gold.withOpacity(0.15) : AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: s.isPremium ? AppColors.gold.withOpacity(0.3) : AppColors.primary.withOpacity(0.2)),
                            ),
                            child: Text(
                              s.isPremium ? '⭐ Join' : 'Join',
                              style: TextStyle(
                                color: s.isPremium ? AppColors.gold : AppColors.primary,
                                fontSize: 12, fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ).animate().fadeIn(delay: Duration(milliseconds: i * 80));
            },
          ),

          // Scheduled
          Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('📅', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('No scheduled lives yet', style: TextStyle(color: subColor, fontSize: 14)),
          ])),

          // Replays
          Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('🎬', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 12),
            Text('No replays yet', style: TextStyle(color: subColor, fontSize: 14)),
          ])),
        ],
      ),
    );
  }
}

// ── Go Live Bottom Sheet ──────────────────────────────
class _GoLiveSheet extends StatefulWidget {
  final bool isDark;
  const _GoLiveSheet({required this.isDark});
  @override
  State<_GoLiveSheet> createState() => _GoLiveSheetState();
}

class _GoLiveSheetState extends State<_GoLiveSheet> {
  final _titleCtrl = TextEditingController();
  String _topic = '💰 Wealth';
  bool _isPremium = false;

  static const _topics = ['💰 Wealth', '📈 Investing', '💼 Business', '🧠 Mindset', '⚡ Hustle', '🎯 Skills'];

  @override
  void dispose() { _titleCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? AppColors.bgCard : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;
    final surfaceColor = widget.isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = widget.isDark ? AppColors.bgSurface : Colors.grey.shade200;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: subColor.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Text('Go Live 🔴', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
        const SizedBox(height: 4),
        Text('Share your wealth knowledge with the world', style: TextStyle(fontSize: 13, color: subColor)),
        const SizedBox(height: 24),

        Text('Session title', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          style: TextStyle(fontSize: 14, color: textColor),
          decoration: InputDecoration(
            hintText: 'What will you teach today?',
            hintStyle: TextStyle(color: subColor, fontSize: 13),
            filled: true, fillColor: surfaceColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 20),

        Text('Topic', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: _topics.map((t) {
          final sel = t == _topic;
          return GestureDetector(
            onTap: () => setState(() => _topic = t),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: sel ? AppColors.primary : surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sel ? AppColors.primary : borderColor),
              ),
              child: Text(t, style: TextStyle(fontSize: 12, color: sel ? Colors.white : subColor, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
            ),
          );
        }).toList()),
        const SizedBox(height: 20),

        // Premium toggle
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.gold.withOpacity(widget.isDark ? 0.1 : 0.05),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Text('⭐', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Premium Live', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
              Text('Only premium members join. You earn coins 🪙', style: TextStyle(fontSize: 12, color: subColor)),
            ])),
            Switch.adaptive(value: _isPremium, onChanged: (v) => setState(() => _isPremium = v), activeColor: AppColors.gold),
          ]),
        ),

        const Spacer(),

        GestureDetector(
          onTap: () { Navigator.pop(context); },
          child: Container(
            width: double.infinity, height: 54,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Colors.red, Color(0xFFFF6B00)]),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
              Icon(Icons.circle, color: Colors.white, size: 8),
              SizedBox(width: 8),
              Text('Start Live', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ]),
    );
  }
}
