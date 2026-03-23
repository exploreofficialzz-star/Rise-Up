import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class MarketPulseScreen extends StatefulWidget {
  const MarketPulseScreen({super.key});
  @override
  State<MarketPulseScreen> createState() => _MarketPulseScreenState();
}

class _MarketPulseScreenState extends State<MarketPulseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map _pulse = {};
  Map _arbitrage = {};
  Map _scan = {};
  bool _loading = true;
  bool _scanning = false;
  String _scanSkill = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/pulse/today'),
        api.get('/pulse/arbitrage'),
      ]);
      if (mounted) setState(() {
        _pulse = (results[0] as Map?) ?? {};
        _arbitrage = (results[1] as Map?) ?? {};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanSkill(String skill) async {
    setState(() { _scanning = true; _scanSkill = skill; });
    try {
      final data = await api.get('/pulse/opportunity-scan', queryParams: {'skill': skill});
      if (mounted) setState(() { _scan = (data as Map?) ?? {}; _scanning = false; });
    } catch (_) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: text), onPressed: () => context.pop()),
        title: Row(children: [
          Container(width: 28, height: 28,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 16)),
          const SizedBox(width: 10),
          Text('Market Pulse', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          IconButton(icon: Icon(Iconsax.refresh, color: AppColors.primary, size: 20), onPressed: _load),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary, unselectedLabelColor: sub,
          indicatorColor: AppColors.primary, indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: "Today's Pulse"), Tab(text: 'Arbitrage'), Tab(text: 'Scan Skill')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(controller: _tabs, children: [
              _buildPulseTab(isDark, text, sub, card, border),
              _buildArbitrageTab(isDark, text, sub, card),
              _buildScanTab(isDark, text, sub, card),
            ]),
    );
  }

  Widget _buildPulseTab(bool isDark, Color text, Color sub, Color card, Color border) {
    final trending = (_pulse['trending_now'] as List?) ?? [];
    final emerging = (_pulse['emerging_opportunities'] as List?) ?? [];
    final avoid = (_pulse['overbooked_avoid'] as List?) ?? [];
    final matched = (_pulse['matched_to_your_skills'] as List?) ?? [];
    final briefing = _pulse['morning_briefing']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Morning briefing banner
        if (briefing.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]),
              borderRadius: AppRadius.lg,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('☀️ TODAY\'S BRIEFING', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(briefing, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.5)),
              const SizedBox(height: 4),
              Text(_pulse['date']?.toString() ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ).animate().fadeIn(),

        // Matched to YOUR skills
        if (matched.isNotEmpty) ...[
          _sectionHeader('🎯 MATCHED TO YOUR SKILLS', sub),
          ...matched.map((m) => _trendCard((m as Map)['opportunity']?.toString() ?? '',
              'Your skill: ${m['your_skill']}', AppColors.success, isDark, text, sub)),
          const SizedBox(height: 16),
        ],

        // Trending now
        _sectionHeader('🔥 TRENDING RIGHT NOW', sub),
        ...trending.asMap().entries.map((e) => _trendCard(
          e.value.toString(), 'High demand now',
          [AppColors.primary, AppColors.accent, AppColors.gold][e.key % 3],
          isDark, text, sub,
        ).animate().fadeIn(delay: Duration(milliseconds: e.key * 60))),
        const SizedBox(height: 16),

        // Emerging
        _sectionHeader('🚀 EMERGING OPPORTUNITIES', sub),
        ...emerging.map((e) => _trendCard(e.toString(), 'Early mover advantage', AppColors.accent, isDark, text, sub)),
        const SizedBox(height: 16),

        // Avoid
        _sectionHeader('⚠️ OVERSATURATED — AVOID', sub),
        ...avoid.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.error.withOpacity(0.07),
            borderRadius: AppRadius.md,
            border: Border.all(color: AppColors.error.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Text('🚫', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 10),
            Expanded(child: Text(e.toString(), style: TextStyle(fontSize: 13, color: text))),
            Text('Oversaturated', style: TextStyle(fontSize: 10, color: AppColors.error)),
          ]),
        )),

        const SizedBox(height: 16),
        _sectionHeader('📊 PLATFORM INTELLIGENCE', sub),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8), borderRadius: AppRadius.lg),
          child: Text(_pulse['platform_intelligence']?.toString() ?? '', style: TextStyle(fontSize: 13, color: text, height: 1.5)),
        ),
        const SizedBox(height: 16),
        _sectionHeader('📈 RATE TRENDS', sub),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8), borderRadius: AppRadius.lg),
          child: Text(_pulse['rate_trends']?.toString() ?? '', style: TextStyle(fontSize: 13, color: text, height: 1.5)),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildArbitrageTab(bool isDark, Color text, Color sub, Color card) {
    final opps = (_arbitrage['opportunities'] as List?) ?? [];
    final multiplier = _arbitrage['rate_multiplier']?.toString() ?? '';
    final totalGain = _arbitrage['total_monthly_gain_if_international'];
    final firstStep = _arbitrage['first_step']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF4776E6), Color(0xFF8E54E9)]),
            borderRadius: AppRadius.lg,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💱 CURRENCY ARBITRAGE', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
            const SizedBox(height: 8),
            Text('International clients pay ${multiplier}x MORE for the same work.',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            if (totalGain != null)
              Text('Your potential monthly gain: \$${(totalGain as num).toStringAsFixed(0)}/mo extra',
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ]),
        ).animate().fadeIn(),
        const SizedBox(height: 20),
        _sectionHeader('YOUR SKILLS — RATE GAPS', sub),
        ...opps.asMap().entries.map((e) {
          final opp = e.value as Map;
          final gap = (opp['gap_usd_per_hour'] as num?)?.toDouble() ?? 0;
          final monthly = (opp['monthly_gain_if_international'] as num?)?.toDouble() ?? 0;
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(opp['skill']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
              const SizedBox(height: 10),
              Row(children: [
                _rateBox('Local', '\$${opp['local_rate_usd']}/hr', AppColors.textMuted, isDark),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_rounded, color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                _rateBox('International', '\$${opp['international_rate_usd']}/hr', AppColors.success, isDark),
                const SizedBox(width: 8),
                _rateBox('+/hr', '+\$${gap.toStringAsFixed(0)}', AppColors.gold, isDark),
              ]),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: AppRadius.md),
                child: Text('Monthly gain if international: \$${monthly.toStringAsFixed(0)}',
                    style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Text(opp['how_to_access_international']?.toString() ?? '',
                  style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
            ]),
          ).animate().fadeIn(delay: Duration(milliseconds: e.key * 80));
        }),
        if (firstStep.isNotEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: AppRadius.lg,
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚡ DO THIS NOW', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Text(firstStep, style: TextStyle(color: text, fontSize: 13, height: 1.5)),
            ]),
          ),
        ],
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildScanTab(bool isDark, Color text, Color sub, Color card) {
    final scanData = _scan['scan'] as Map? ?? {};
    final skills = ['Video editing', 'Graphic design', 'Copywriting', 'Web development', 'Social media', 'VA services', 'Animation', 'AI automation'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Scan demand for any skill — RIGHT NOW', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: skills.map((s) => GestureDetector(
          onTap: () => _scanSkill(s),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _scanSkill == s ? AppColors.primary : (isDark ? AppColors.bgCard : const Color(0xFFF5F5F5)),
              borderRadius: AppRadius.pill,
            ),
            child: Text(s, style: TextStyle(fontSize: 12, color: _scanSkill == s ? Colors.white : text, fontWeight: FontWeight.w600)),
          ),
        )).toList()),
        const SizedBox(height: 16),
        if (_scanning)
          const Center(child: CircularProgressIndicator(color: AppColors.primary))
        else if (scanData.isNotEmpty) ...[
          Text('📊 ${_scan['skill']} — Market Scan', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 12),
          _scanStat('Demand Level', scanData['demand_level']?.toString() ?? '', isDark, text),
          _scanStat('Best Platform Now', scanData['best_platform_now']?.toString() ?? '', isDark, text),
          _scanStat('Average Rate', '\$${scanData['average_rate_usd'] ?? 0}/hr', isDark, text),
          _scanStat('Top Rate', '\$${scanData['top_rate_usd'] ?? 0}/hr', isDark, text),
          _scanStat('Competition', scanData['competition_level']?.toString() ?? '', isDark, text),
          _scanStat('Momentum', scanData['momentum']?.toString() ?? '', isDark, text),
          if (scanData['niche_down_suggestion'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.08), borderRadius: AppRadius.lg, border: Border.all(color: AppColors.accent.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('💡 NICHE DOWN SUGGESTION', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 11)),
                const SizedBox(height: 6),
                Text(scanData['niche_down_suggestion'].toString(), style: TextStyle(fontSize: 13, color: text, height: 1.4)),
              ]),
            ),
          ],
          if (scanData['action_today'] != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.08), borderRadius: AppRadius.lg, border: Border.all(color: AppColors.success.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('⚡ ACTION TODAY', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700, fontSize: 11)),
                const SizedBox(height: 6),
                Text(scanData['action_today'].toString(), style: TextStyle(fontSize: 13, color: text, height: 1.4)),
              ]),
            ),
          ],
        ] else
          Center(child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(children: [
              const Text('🔍', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 12),
              Text('Tap a skill above to scan its market demand', style: TextStyle(color: sub, fontSize: 14), textAlign: TextAlign.center),
            ]),
          )),
        const SizedBox(height: 40),
      ]),
    );
  }

  Widget _trendCard(String title, String sub2, Color color, bool isDark, Color text, Color sub) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: AppRadius.md,
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(children: [
      Container(width: 4, height: 36, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
        Text(sub2, style: TextStyle(fontSize: 11, color: sub)),
      ])),
      Icon(Icons.arrow_forward_ios_rounded, size: 12, color: sub),
    ]),
  );

  Widget _rateBox(String label, String value, Color color, bool isDark) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: AppRadius.md),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 9, color: color.withOpacity(0.7))),
      ]),
    ),
  );

  Widget _scanStat(String label, String value, bool isDark, Color text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8), borderRadius: AppRadius.md),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 13, color: text.withOpacity(0.6))),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
    ]),
  );

  Widget _sectionHeader(String title, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1)),
  );
}
