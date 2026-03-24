import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ChallengesScreen extends StatefulWidget {
  const ChallengesScreen({super.key});
  @override
  State<ChallengesScreen> createState() => _ChallengesScreenState();
}

class _ChallengesScreenState extends State<ChallengesScreen> {
  List _active = [];
  List _completed = [];
  bool _loading = true;

  static const _templates = [
    {'type': 'first_client', 'emoji': '🎯', 'title': 'Land Your First Client', 'duration': '7 Days', 'target': '\$50', 'desc': 'Go from zero to paid. Your first client is the hardest — and the most important.', 'color': 0xFF6C5CE7},
    {'type': 'first_100', 'emoji': '💯', 'title': 'Earn Your First \$100', 'duration': '14 Days', 'target': '\$100', 'desc': 'Prove to yourself that you can make real money online. 14 days is all you need.', 'color': 0xFF00B894},
    {'type': 'first_500_month', 'emoji': '🚀', 'title': '\$500/Month Challenge', 'duration': '30 Days', 'target': '\$500', 'desc': 'Build a repeatable income system that puts \$500 in your account every month.', 'color': 0xFFFF6B35},
    {'type': 'skill_30day', 'emoji': '🎓', 'title': 'Learn → Earn in 30 Days', 'duration': '30 Days', 'target': '\$200', 'desc': 'Pick a skill. Learn it. Get paid for it. All within a single month.', 'color': 0xFF74B9FF},
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.get('/challenges/');
      if (mounted) setState(() {
        _active = (data as Map?)?['active_challenges'] as List? ?? [];
        _completed = (data)?['challenges']?.where((c) => c['status'] == 'completed')?.toList() ?? [];
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _startChallenge(String type) async {
    try {
      final result = await api.post('/challenges/create', {'challenge_type': type});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('🎯 Challenge started! ${result?['message'] ?? ''}'), backgroundColor: AppColors.success),
        );
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _showCheckinDialog(Map challenge) async {
    final ctrl = TextEditingController();
    final amountCtrl = TextEditingController();
    await showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Day ${challenge['current_day']} Check-In', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(hintText: "What action did you take today?", filled: true, border: InputBorder.none),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(hintText: "Amount earned today (\$0 if none)", filled: true, border: InputBorder.none),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  Navigator.pop(context);
                  final amount = double.tryParse(amountCtrl.text) ?? 0;
                  final result = await api.post('/challenges/check-in', {
                    'challenge_id': challenge['id'],
                    'action_taken': ctrl.text,
                    'amount_earned_usd': amount,
                  });
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(result?['message'] ?? '✅ Checked in!'), backgroundColor: AppColors.success),
                  );
                  _load();
                },
                child: const Text('Check In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: text), onPressed: () => context.pop()),
        title: Row(children: [
          const Text('🏆', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('Income Challenges', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load, color: AppColors.primary,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Active challenges
                if (_active.isNotEmpty) ...[
                  _header('ACTIVE CHALLENGES', sub),
                  ..._active.map((c) => _activeChallengeCard(c, isDark, text, sub, card)).toList(),
                  const SizedBox(height: 20),
                ],

                // Start a challenge
                _header('START A CHALLENGE', sub),
                ..._templates.asMap().entries.map((e) {
                  final t = e.value;
                  final alreadyActive = _active.any((a) => a['challenge_type'] == t['type']);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.bgCard : Colors.white,
                      borderRadius: AppRadius.lg,
                      border: Border.all(color: Color(t['color'] as int).withOpacity(0.25)),
                    ),
                    child: Material(color: Colors.transparent, borderRadius: AppRadius.lg,
                      child: InkWell(
                        borderRadius: AppRadius.lg,
                        onTap: alreadyActive ? null : () => _startChallenge(t['type'] as String),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            Container(
                              width: 52, height: 52,
                              decoration: BoxDecoration(
                                color: Color(t['color'] as int).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(child: Text(t['emoji'] as String, style: const TextStyle(fontSize: 26))),
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(t['title'] as String, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                              const SizedBox(height: 3),
                              Text(t['desc'] as String, style: TextStyle(fontSize: 12, color: sub, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 6),
                              Row(children: [
                                _tag(t['duration'] as String, Color(t['color'] as int)),
                                const SizedBox(width: 8),
                                _tag('Target: ${t['target']}', AppColors.gold),
                              ]),
                            ])),
                            const SizedBox(width: 8),
                            if (alreadyActive)
                              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: AppRadius.pill),
                                child: const Text('Active', style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.w700)))
                            else
                              Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(color: Color(t['color'] as int), shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18),
                              ),
                          ]),
                        ),
                      ),
                    ),
                  ).animate().fadeIn(delay: Duration(milliseconds: e.key * 80));
                }),

                if (_completed.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _header('COMPLETED ✅', sub),
                  ..._completed.take(5).map((c) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.06),
                      borderRadius: AppRadius.md,
                      border: Border.all(color: AppColors.success.withOpacity(0.2)),
                    ),
                    child: Row(children: [
                      const Text('🏆', style: TextStyle(fontSize: 20)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['title']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                        Text('Earned: \$${c['current_usd'] ?? 0}', style: const TextStyle(fontSize: 12, color: AppColors.success)),
                      ])),
                    ]),
                  )),
                ],
                const SizedBox(height: 40),
              ]),
            ),
    );
  }

  Widget _activeChallengeCard(Map c, bool isDark, Color text, Color sub, Color card) {
    final progress = (c['current_usd'] ?? 0) / (c['target_usd'] ?? 1);
    final day = c['current_day'] ?? 1;
    final total = c['duration_days'] ?? 30;
    final pct = (progress * 100).clamp(0, 100).round();
    final behindPace = pct < ((day / total) * 100 - 20);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: AppRadius.lg,
        border: Border.all(color: behindPace ? AppColors.warning.withOpacity(0.4) : AppColors.primary.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: AppColors.primary.withOpacity(0.06), blurRadius: 10, spreadRadius: -2)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(c['emoji']?.toString() ?? '🎯', style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Expanded(child: Text(c['title']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text))),
          if (behindPace)
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.12), borderRadius: AppRadius.pill),
              child: const Text('⚠️ Behind pace', style: TextStyle(fontSize: 10, color: AppColors.warning, fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Text('Day $day/$total', style: TextStyle(fontSize: 12, color: sub)),
          const Spacer(),
          Text('\$${c['current_usd'] ?? 0} / \$${c['target_usd'] ?? 0}', style: const TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0).toDouble(),
            backgroundColor: isDark ? Colors.white12 : Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(behindPace ? AppColors.warning : AppColors.success),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 4),
        Text('$pct% complete · ${c['streak'] ?? 0} day streak 🔥', style: TextStyle(fontSize: 11, color: sub)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showCheckinDialog(c),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: AppRadius.pill),
                child: const Center(child: Text('✅ Check In Today', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13))),
              ),
            ),
          ),
          if (behindPace) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () async {
                final r = await api.post('/challenges/${c['id']}/ai-intervention', {});
                if (mounted && r != null) {
                  final inv = r['intervention'] as Map? ?? {};
                  showDialog(context: context, builder: (_) => AlertDialog(
                    title: const Text('🚨 Recovery Plan'),
                    content: Text(inv['recovery_plan']?.toString() ?? ''),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
                  ));
                }
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.1), borderRadius: AppRadius.pill, border: Border.all(color: AppColors.warning.withOpacity(0.4))),
                child: const Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
              ),
            ),
          ],
        ]),
      ]),
    ).animate().fadeIn();
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: AppRadius.pill),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
  );

  Widget _header(String t, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1)),
  );
}
