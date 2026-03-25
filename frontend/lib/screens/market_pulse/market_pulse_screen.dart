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
  Map<String, dynamic> _pulse = {};
  Map<String, dynamic> _arbitrage = {};
  Map<String, dynamic> _scan = {};
  bool _loading = true;
  bool _scanning = false;
  String _selectedSkill = '';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/pulse/today'),
        api.get('/pulse/arbitrage'),
      ]);
      if (mounted) setState(() {
        _pulse = Map<String, dynamic>.from(results[0] ?? {});
        _arbitrage = Map<String, dynamic>.from(results[1] ?? {});
        _loading = false;
      });
    } catch (e) {
      debugPrint("Market Pulse Load Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanSkill(String skill) async {
    setState(() { _scanning = true; _selectedSkill = skill; });
    try {
      final data = await api.get('/pulse/opportunity-scan', queryParams: {'skill': skill});
      if (mounted) setState(() { 
        _scan = Map<String, dynamic>.from(data ?? {}); 
        _scanning = false; 
      });
    } catch (e) {
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
        elevation: 0,
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
          tabs: const [Tab(text: "Live Trends"), Tab(text: 'Arbitrage'), Tab(text: 'Scan Skill')],
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
    final trending = _pulse['trending_now'] as List? ?? [];
    final emerging = _pulse['emerging_opportunities'] as List? ?? [];
    final avoid = _pulse['overbooked_avoid'] as List? ?? [];
    final briefing = _pulse['morning_briefing']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (briefing.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]),
              borderRadius: AppRadius.lg,
              boxShadow: [BoxShadow(color: const Color(0xFFFF6B35).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('☀️ MORNING BRIEFING', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(briefing, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Text(_pulse['date']?.toString() ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ).animate().slideY(begin: 0.1, curve: Curves.easeOutQuad).fadeIn(),

        _sectionHeader('🔥 EXPLODING DEMAND', sub),
        ...trending.asMap().entries.map((e) => _trendCard(
          e.value.toString(), 'High Volume', 
          [AppColors.primary, AppColors.accent, AppColors.gold][e.key % 3], 
          isDark, text, sub
        ).animate().fadeIn(delay: Duration(milliseconds: e.key * 100))),

        const SizedBox(height: 20),
        _sectionHeader('🚀 EARLY OPPORTUNITIES', sub),
        ...emerging.map((e) => _trendCard(e.toString(), 'Low Competition', AppColors.success, isDark, text, sub)),

        const SizedBox(height: 20),
        _sectionHeader('⚠️ SATURATED MARKETS', sub),
        ...avoid.map((e) => _avoidCard(e.toString(), text)),

        const SizedBox(height: 24),
        _infoSection('📊 Platform Intelligence', _pulse['platform_intelligence'], isDark, text),
        _infoSection('📈 Rate Trends', _pulse['rate_trends'], isDark, text),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildArbitrageTab(bool isDark, Color text, Color sub, Color card) {
    final opps = _arbitrage['opportunities'] as List? ?? [];
    final multiplier = _arbitrage['rate_multiplier']?.toString() ?? '1.0';
    final localCurrency = _arbitrage['local_currency']?.toString() ?? 'USD';
    final totalGain = _arbitrage['total_monthly_gain_usd']?.toString() ?? '0';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF2E3192), Color(0xFF1BFFFF)]),
            borderRadius: AppRadius.lg,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('💱 GLOBAL RATE ARBITRAGE', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Text('International clients pay ${multiplier}x more than local markets.',
                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 1.2)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: AppRadius.sm),
              child: Text('Potential Extra: \$$totalGain/mo', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
            )
          ]),
        ),
        const SizedBox(height: 24),
        _sectionHeader('LIVE ARBITRAGE GAPS', sub),
        ...opps.map((o) {
          final opp = o as Map;
          return _arbitrageCard(opp, localCurrency, isDark, text, sub);
        }),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildScanTab(bool isDark, Color text, Color sub, Color card) {
    final scanData = _scan['scan'] as Map? ?? {};
    // Dynamically use trending items as suggestions
    final suggestions = (_pulse['trending_now'] as List?)?.take(6).toList() ?? 
                       ['AI Automation', 'Video Editing', 'SaaS Dev', 'UI/UX Design'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionHeader('QUICK SCAN TRENDS', sub),
        Wrap(spacing: 8, runSpacing: 8, children: suggestions.map((s) => ChoiceChip(
          label: Text(s.toString(), style: TextStyle(fontSize: 11, color: _selectedSkill == s ? Colors.white : text)),
          selected: _selectedSkill == s,
          onSelected: (val) => _scanSkill(s.toString()),
          selectedColor: AppColors.primary,
          backgroundColor: isDark ? AppColors.bgCard : Colors.grey.shade100,
        )).toList()),
        
        const SizedBox(height: 24),
        if (_scanning)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (scanData.isNotEmpty) ...[
          _buildScanResult(scanData, isDark, text, sub),
        ] else
          _buildEmptyScanState(sub),
        const SizedBox(height: 40),
      ]),
    );
  }

  // --- UI COMPONENTS ---

  Widget _infoSection(String title, dynamic content, bool isDark, Color text) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _sectionHeader(title.toUpperCase(), text.withOpacity(0.5)),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: isDark ? AppColors.bgCard : const Color(0xFFF8F9FA), borderRadius: AppRadius.lg),
        child: Text(content?.toString() ?? 'Loading...', style: TextStyle(fontSize: 13, color: text, height: 1.6)),
      ),
      const SizedBox(height: 20),
    ],
  );

  Widget _arbitrageCard(Map opp, String currency, bool isDark, Color text, Color sub) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: isDark ? AppColors.bgCard : Colors.white,
      borderRadius: AppRadius.lg,
      border: Border.all(color: AppColors.success.withOpacity(0.2)),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(opp['skill']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
        Text('+$currency ${opp['monthly_gain_local_currency']?.toString().split(' ').last}', 
             style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 13)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        _miniRate('Local', '\$${opp['local_rate_usd']}', isDark),
        const Icon(Icons.chevron_right, size: 16, color: Colors.grey),
        _miniRate('Intl', '\$${opp['international_rate_usd']}', isDark, isPrimary: true),
      ]),
      const SizedBox(height: 12),
      Text(opp['how_to_access_international'] ?? '', style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
    ]),
  );

  Widget _miniRate(String label, String val, bool isDark, {bool isPrimary = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    margin: const EdgeInsets.only(right: 8),
    decoration: BoxDecoration(
      color: isPrimary ? AppColors.success.withOpacity(0.1) : (isDark ? Colors.white10 : Colors.grey.shade100),
      borderRadius: AppRadius.sm
    ),
    child: Row(children: [
      Text('$label: ', style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54)),
      Text(val, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isPrimary ? AppColors.success : null)),
    ]),
  );

  Widget _buildScanResult(Map data, bool isDark, Color text, Color sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('LIVE MARKET REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primary)),
      const SizedBox(height: 4),
      Text(_selectedSkill.toUpperCase(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: text)),
      const SizedBox(height: 16),
      _gridStat('Demand', data['demand_level'], Iconsax.flash),
      _gridStat('Platform', data['best_platform_now'], Iconsax.global),
      _gridStat('Avg Rate', '\$${data['average_rate_usd']}/hr', Iconsax.money),
      _gridStat('Momentum', data['momentum'], Iconsax.graph),
      const SizedBox(height: 20),
      _actionBox('NEXT STEP', data['action_today'], AppColors.success),
    ],
  ).animate().fadeIn();

  Widget _gridStat(String label, dynamic val, IconData icon) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.black.withOpacity(0.03), borderRadius: AppRadius.md),
    child: Row(children: [
      Icon(icon, size: 18, color: AppColors.primary),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const Spacer(),
      Text(val?.toString() ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _actionBox(String title, dynamic content, Color color) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: AppRadius.lg, border: Border.all(color: color.withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
      const SizedBox(height: 8),
      Text(content?.toString() ?? '', style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500)),
    ]),
  );

  Widget _avoidCard(String title, Color text) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: AppColors.error.withOpacity(0.05), borderRadius: AppRadius.md),
    child: Row(children: [
      const Icon(Icons.block, color: AppColors.error, size: 16),
      const SizedBox(width: 12),
      Text(title, style: TextStyle(fontSize: 13, color: text, fontWeight: FontWeight.w500)),
      const Spacer(),
      const Text('Saturated', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _trendCard(String title, String sub2, Color color, bool isDark, Color text, Color sub) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? AppColors.bgCard : Colors.white,
      borderRadius: AppRadius.lg,
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]
    ),
    child: Row(children: [
      Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
        Text(sub2, style: TextStyle(fontSize: 11, color: sub)),
      ])),
      Icon(Icons.trending_up_rounded, size: 16, color: color.withOpacity(0.5)),
    ]),
  );

  Widget _sectionHeader(String title, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 12, top: 4),
    child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: sub, letterSpacing: 1.5)),
  );

  Widget _buildEmptyScanState(Color sub) => Center(child: Padding(
    padding: const EdgeInsets.all(40),
    child: Column(children: [
      Icon(Iconsax.search_status, size: 64, color: sub.withOpacity(0.2)),
      const SizedBox(height: 16),
      Text('Select a skill above to perform a live AI market scan', textAlign: TextAlign.center, style: TextStyle(color: sub, fontSize: 13)),
    ]),
  ));
}
