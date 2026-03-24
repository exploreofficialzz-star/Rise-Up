import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List _sessions = [];
  bool _loading = true;
  bool _isPremium = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getLiveSessions();
      if (mounted) {
        setState(() {
          _sessions = data['sessions'] ?? [];
          _isPremium = data['is_premium'] == true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _viewers(dynamic v) {
    final n = v as int? ?? 0;
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

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
          GestureDetector(
            onTap: () => _showGoLiveSheet(context, isDark),
            child: Container(
              margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.red, Color(0xFFFF6B00)]), borderRadius: BorderRadius.circular(20)),
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
              labelColor: AppColors.primary, unselectedLabelColor: subColor,
              indicatorColor: AppColors.primary, indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Live Now'), Tab(text: 'Scheduled'), Tab(text: 'Replays')],
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                // Live Now
                _sessions.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('📺', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 12),
                        Text('No live sessions right now', style: TextStyle(color: subColor, fontSize: 14)),
                        const SizedBox(height: 8),
                        Text('Be the first to go live!', style: TextStyle(color: subColor, fontSize: 12)),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _sessions.length,
                          itemBuilder: (_, i) {
                            final s = _sessions[i];
                            final host = s['profiles'] as Map? ?? {};
                            final isPremiumLive = s['is_premium'] == true;
                            final canJoin = s['can_join'] == true;

                            return GestureDetector(
                              onTap: canJoin
                                  ? () async {
                                      await api.joinLive(s['id'].toString());
                                      context.go('/live-viewer/${s['id']}?host=${Uri.encodeComponent(host['full_name'] ?? '')}&title=${Uri.encodeComponent(s['title'] ?? '')}');
                                    }
                                  : () => _showPremiumPrompt(context, isDark),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  // Thumbnail
                                  Container(
                                    height: 160,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.8), AppColors.accent.withOpacity(0.6)]),
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                                    ),
                                    child: Stack(children: [
                                      Center(child: Text(
                                        _stageEmoji(host['stage']?.toString()),
                                        style: const TextStyle(fontSize: 64),
                                      )),
                                      Positioned(top: 12, left: 12, child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.circle, color: Colors.white, size: 6), SizedBox(width: 4), Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800))]),
                                      )),
                                      if (isPremiumLive)
                                        Positioned(top: 12, right: 12, child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.gold, AppColors.goldDark]), borderRadius: BorderRadius.circular(6)),
                                          child: const Text('⭐ Premium', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                                        )),
                                      Positioned(bottom: 12, right: 12, child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const Icon(Icons.remove_red_eye_outlined, color: Colors.white, size: 13),
                                          const SizedBox(width: 4),
                                          Text(_viewers(s['viewers_count']), style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                        ]),
                                      )),
                                      Positioned(bottom: 12, left: 12, child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          const Text('🪙', style: TextStyle(fontSize: 11)),
                                          const SizedBox(width: 4),
                                          Text('${s['coins_earned'] ?? 0}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
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
                                        child: Center(child: Text(_stageEmoji(host['stage']?.toString()), style: const TextStyle(fontSize: 18))),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text(s['title']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor), maxLines: 2, overflow: TextOverflow.ellipsis),
                                        const SizedBox(height: 2),
                                        Row(children: [
                                          Text(host['full_name']?.toString() ?? '', style: TextStyle(fontSize: 11, color: subColor)),
                                          const SizedBox(width: 8),
                                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(s['topic']?.toString() ?? '', style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600))),
                                        ]),
                                      ])),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: canJoin ? (isPremiumLive ? AppColors.gold.withOpacity(0.15) : AppColors.primary.withOpacity(0.1)) : Colors.grey.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: canJoin ? (isPremiumLive ? AppColors.gold.withOpacity(0.3) : AppColors.primary.withOpacity(0.2)) : Colors.grey.withOpacity(0.3)),
                                        ),
                                        child: Text(
                                          canJoin ? (isPremiumLive ? '⭐ Join' : 'Join') : '🔒 Premium',
                                          style: TextStyle(color: canJoin ? (isPremiumLive ? AppColors.gold : AppColors.primary) : subColor, fontSize: 12, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ]),
                              ),
                            ).animate().fadeIn(delay: Duration(milliseconds: i * 80));
                          },
                        ),
                      ),

                Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('📅', style: TextStyle(fontSize: 56)), const SizedBox(height: 12), Text('No scheduled lives yet', style: TextStyle(color: subColor, fontSize: 14))])),
                Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [const Text('🎬', style: TextStyle(fontSize: 56)), const SizedBox(height: 12), Text('No replays yet', style: TextStyle(color: subColor, fontSize: 14))])),
              ],
            ),
    );
  }

  String _stageEmoji(String? stage) {
    return {'survival': '🆘', 'earning': '💪', 'growing': '🚀', 'wealth': '💎'}[stage] ?? '⭐';
  }

  void _showPremiumPrompt(BuildContext context, bool isDark) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: isDark ? AppColors.bgCard : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Premium Required ⭐', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('This live session is exclusive to Premium members.\n\nUpgrade to join unlimited live sessions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () { Navigator.pop(context); context.go('/premium'); },
            child: const Text('Upgrade', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showGoLiveSheet(BuildContext context, bool isDark) {
    final titleCtrl = TextEditingController();
    String topic = '💰 Wealth';
    bool isPremium = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (_, setSt) {
          final bgColor = isDark ? AppColors.bgCard : Colors.white;
          final textColor = isDark ? Colors.white : Colors.black87;
          final subColor = isDark ? Colors.white54 : Colors.black45;
          final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
          final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;

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
              TextField(controller: titleCtrl, style: TextStyle(fontSize: 14, color: textColor), decoration: InputDecoration(hintText: 'What will you teach today?', hintStyle: TextStyle(color: subColor, fontSize: 13), filled: true, fillColor: surfaceColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
              const SizedBox(height: 20),
              Text('Topic', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: ['💰 Wealth', '📈 Investing', '💼 Business', '🧠 Mindset', '⚡ Hustle', '🎯 Skills'].map((t) {
                final sel = t == topic;
                return GestureDetector(onTap: () => setSt(() => topic = t), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: sel ? AppColors.primary : surfaceColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppColors.primary : borderColor)), child: Text(t, style: TextStyle(fontSize: 12, color: sel ? Colors.white : subColor, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
              }).toList()),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.gold.withOpacity(isDark ? 0.1 : 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.gold.withOpacity(0.3))),
                child: Row(children: [
                  const Text('⭐', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Premium Live', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                    Text('Only premium members join. You earn coins 🪙', style: TextStyle(fontSize: 12, color: subColor)),
                  ])),
                  Switch.adaptive(value: isPremium, onChanged: (v) => setSt(() => isPremium = v), activeColor: AppColors.gold),
                ]),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () async {
                  if (titleCtrl.text.trim().isEmpty) return;
                  Navigator.pop(context);
                  try {
                    await api.startLive(title: titleCtrl.text.trim(), topic: topic, isPremium: isPremium);
                    _load();
                  } catch (_) {}
                },
                child: Container(
                  width: double.infinity, height: 54,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.red, Color(0xFFFF6B00)]), borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [Icon(Icons.circle, color: Colors.white, size: 8), SizedBox(width: 8), Text('Start Live', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700))]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
