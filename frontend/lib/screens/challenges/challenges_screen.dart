import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart'; // Essential for global currency formatting
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
  List _discoveryChallenges = [];
  String _featuredTheme = "Loading Trends...";
  bool _loading = true;
  bool _discovering = false;

  @override
  void initState() {
    super.initState();
    _initScreen();
  }

  Future<void> _initScreen() async {
    await Future.wait([
      _loadActiveChallenges(),
      _discoverNewChallenges(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadActiveChallenges() async {
    try {
      final data = await api.get('/challenges/');
      if (mounted) {
        setState(() {
          _active = (data as Map?)?['active_challenges'] as List? ?? [];
          _completed = (data)?['challenges']?.where((c) => c['status'] == 'completed')?.toList() ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error loading active challenges: $e");
    }
  }

  Future<void> _discoverNewChallenges() async {
    if (mounted) setState(() => _discovering = true);
    try {
      // Calls the new dynamic discovery endpoint
      final data = await api.get('/challenges/discover');
      if (mounted) {
        setState(() {
          _discoveryChallenges = data['challenges'] as List? ?? [];
          _featuredTheme = data['featured_this_week'] ?? "Global Opportunities";
          _discovering = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _startChallenge(Map discoveryItem) async {
    try {
      final result = await api.post('/challenges/create', {
        'challenge_type': discoveryItem['type_id'],
        'discovery_data': discoveryItem,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🎯 Challenge started: ${discoveryItem['title']}'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadActiveChallenges(); // Refresh the active list
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _showCheckinDialog(Map challenge) async {
    final ctrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final currencyCode = challenge['currency_code'] ?? 'USD';
    final symbol = NumberFormat.simpleCurrency(name: currencyCode).currencySymbol;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Day ${challenge['current_day']} Check-In', 
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  Text(challenge['emoji'] ?? '🎯', style: const TextStyle(fontSize: 24)),
                ],
              ),
              const SizedBox(height: 8),
              const Text('Log your progress and earnings for today.', style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 20),
              TextField(
                controller: ctrl,
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  labelText: "What action did you take?",
                  hintText: "e.g., Sent 5 cold emails",
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: "Amount earned today",
                  prefixText: "$symbol ",
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.05),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    final amount = double.tryParse(amountCtrl.text) ?? 0;
                    final result = await api.post('/challenges/check-in', {
                      'challenge_id': challenge['id'],
                      'action_taken': ctrl.text,
                      'amount_earned': amount,
                      'currency': currencyCode,
                    });
                    if (mounted) {
                      _loadActiveChallenges();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(result?['message'] ?? '✅ Progress saved!'), backgroundColor: AppColors.success),
                      );
                    }
                  },
                  child: const Text('Confirm Check-In', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 20), onPressed: () => context.pop()),
        title: Text('Income Challenges', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: text)),
        actions: [
          IconButton(onPressed: _initScreen, icon: const Icon(Iconsax.refresh, size: 20, color: AppColors.primary)),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _initScreen,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                children: [
                  // ACTIVE SECTION
                  if (_active.isNotEmpty) ...[
                    _sectionHeader('CURRENT PROGRESS', sub),
                    ..._active.map((c) => _activeChallengeCard(c, isDark, text, sub)).toList(),
                    const SizedBox(height: 24),
                  ],

                  // DISCOVERY SECTION
                  Row(
                    children: [
                      _sectionHeader('DISCOVER: $_featuredTheme', sub),
                      const Spacer(),
                      if (_discovering) 
                        const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_discoveryChallenges.isEmpty && !_discovering)
                    _emptyState("No new challenges found for your region.")
                  else
                    ..._discoveryChallenges.asMap().entries.map((e) {
                      return _discoveryCard(e.value, isDark, text, sub)
                          .animate()
                          .fadeIn(delay: Duration(milliseconds: e.key * 100))
                          .slideX(begin: 0.1, curve: Curves.easeOutCubic);
                    }).toList(),

                  // COMPLETED SECTION
                  if (_completed.isNotEmpty) ...[
                    const SizedBox(height: 32),
                    _sectionHeader('HALL OF FAME ✅', sub),
                    ..._completed.take(3).map((c) => _completedCard(c, text)).toList(),
                  ],
                  const SizedBox(height: 60),
                ],
              ),
            ),
    );
  }

  Widget _activeChallengeCard(Map c, bool isDark, Color text, Color sub) {
    final target = (c['target_amount'] ?? 1.0).toDouble();
    final current = (c['current_amount'] ?? 0.0).toDouble();
    final progress = (current / target).clamp(0.0, 1.0);
    final currency = c['currency_code'] ?? 'USD';
    final fmt = NumberFormat.simpleCurrency(name: currency, decimalDigits: 0);

    final day = c['current_day'] ?? 1;
    final total = c['duration_days'] ?? 30;
    final isBehind = progress < (day / total) - 0.15;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: isBehind ? AppColors.warning.withOpacity(0.3) : AppColors.primary.withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: (isBehind ? AppColors.warning : AppColors.primary).withOpacity(0.1),
                child: Text(c['emoji'] ?? '🎯', style: const TextStyle(fontSize: 20)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['title'] ?? 'Challenge', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: text)),
                    Text('Day $day of $total · Streak: ${c['streak'] ?? 0} 🔥', style: TextStyle(fontSize: 12, color: sub)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(fmt.format(current), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.success)),
              Text('Goal: ${fmt.format(target)}', style: TextStyle(fontSize: 12, color: sub, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: isDark ? Colors.white10 : Colors.grey[200],
              valueColor: AlwaysStoppedAnimation(isBehind ? AppColors.warning : AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _showCheckinDialog(c),
                  icon: const Icon(Icons.add_task_rounded, size: 18, color: Colors.white),
                  label: const Text('Check In', style: TextStyle(fontWeight: FontWeight.w800, color: Colors.white)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              if (isBehind) ...[
                const SizedBox(width: 10),
                IconButton.filled(
                  onPressed: () async {
                    final res = await api.post('/challenges/${c['id']}/ai-intervention', {});
                    if (mounted) _showInterventionSheet(res['intervention']);
                  },
                  backgroundColor: AppColors.warning.withOpacity(0.1),
                  icon: const Icon(Iconsax.magicpen, color: AppColors.warning, size: 20),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _discoveryCard(Map t, bool isDark, Color text, Color sub) {
    final alreadyActive = _active.any((a) => a['challenge_type'] == t['type_id']);
    final currency = t['currency'] ?? 'USD';
    final fmt = NumberFormat.simpleCurrency(name: currency, decimalDigits: 0);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white05 : Colors.black.withOpacity(0.05)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: alreadyActive ? null : () => _startChallenge(t),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(child: Text(t['emoji'] ?? '🚀', style: const TextStyle(fontSize: 28))),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t['title'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: text)),
                      const SizedBox(height: 4),
                      Text(t['description'] ?? '', 
                        style: TextStyle(fontSize: 12, color: sub, height: 1.3), 
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _badge('${t['duration_days']} Days', AppColors.accent),
                          const SizedBox(width: 8),
                          _badge('Target: ${fmt.format(t['target_amount'])}', AppColors.gold),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showInterventionSheet(Map data) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('🧠 AI Intervention', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.warning)),
            const SizedBox(height: 12),
            Text(data['situation_assessment'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
            const SizedBox(height: 20),
            const Text('RECOVERY STEPS:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.grey)),
            const SizedBox(height: 8),
            ...(data['recovery_plan'] as List? ?? []).map((step) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.check_circle_outline, size: 16, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(child: Text(step.toString(), style: const TextStyle(fontSize: 13))),
              ]),
            )).toList(),
            const SizedBox(height: 24),
            Text(data['you_can_do_this'] ?? '', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.primary)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
    child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w800)),
  );

  Widget _sectionHeader(String title, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 12, left: 4),
    child: Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: color, letterSpacing: 1.2)),
  );

  Widget _completedCard(Map c, Color text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: AppColors.success.withOpacity(0.05), borderRadius: BorderRadius.circular(16)),
    child: Row(
      children: [
        const Text('🏆', style: TextStyle(fontSize: 20)),
        const SizedBox(width: 12),
        Expanded(child: Text(c['title'] ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text))),
        Text('Done', style: TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w800)),
      ],
    ),
  );

  Widget _emptyState(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Text(msg, style: const TextStyle(color: Colors.grey), textAlign: TextAlign.center),
    ),
  );
}
