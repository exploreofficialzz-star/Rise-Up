import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});
  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _clients = [];
  Map _stats = {};
  List _dueFollowups = [];
  bool _loading = true;

  static const _statusColors = {
    'prospect': 0xFF74B9FF,
    'contacted': 0xFFFFD700,
    'proposal_sent': 0xFFFF6B35,
    'negotiating': 0xFFFF3CAC,
    'won': 0xFF00B894,
    'lost': 0xFFD63031,
    'recurring': 0xFF6C5CE7,
  };

  @override
  void initState() { super.initState(); _tabs = TabController(length: 3, vsync: this); _load(); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/crm/clients'),
        api.get('/crm/follow-ups/due'),
      ]);
      if (mounted) setState(() {
        final data = results[0] as Map? ?? {};
        _clients = data['clients'] as List? ?? [];
        _stats = data['stats'] as Map? ?? {};
        _dueFollowups = (results[1] as Map?)?['overdue_followups'] as List? ?? [];
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  void _showAddClientSheet() {
    final nameCtrl = TextEditingController();
    final platformCtrl = TextEditingController();
    final serviceCtrl = TextEditingController();
    final budgetCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add Client', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 16),
            _field(nameCtrl, 'Client name *', isDark),
            const SizedBox(height: 10),
            _field(platformCtrl, 'Where you met them (Upwork, Instagram...)', isDark),
            const SizedBox(height: 10),
            _field(serviceCtrl, 'Service they need', isDark),
            const SizedBox(height: 10),
            _field(budgetCtrl, 'Budget (\$USD)', isDark, type: TextInputType.number),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  if (nameCtrl.text.isEmpty) return;
                  Navigator.pop(context);
                  await api.post('/crm/clients', {
                    'name': nameCtrl.text,
                    'platform': platformCtrl.text,
                    'service_interest': serviceCtrl.text,
                    'budget_usd': double.tryParse(budgetCtrl.text) ?? 0,
                  });
                  _load();
                },
                child: const Text('Add to CRM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, bool isDark, {TextInputType? type}) => TextField(
    controller: c, keyboardType: type,
    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
      filled: true,
      fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );

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
          const Text('💼', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('Client CRM', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_rounded, color: AppColors.primary), onPressed: _showAddClientSheet),
        ],
        bottom: TabBar(
          controller: _tabs, labelColor: AppColors.primary, unselectedLabelColor: sub,
          indicatorColor: AppColors.primary, indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(text: 'Pipeline'),
            Tab(text: _dueFollowups.isEmpty ? 'Follow-ups' : '⚡ Follow-ups (${_dueFollowups.length})'),
            Tab(text: 'Analytics'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load, color: AppColors.primary,
              child: TabBarView(controller: _tabs, children: [
                _buildPipeline(isDark, text, sub, card),
                _buildFollowUps(isDark, text, sub, card),
                _buildAnalytics(isDark, text, sub, card),
              ]),
            ),
    );
  }

  Widget _buildPipeline(bool isDark, Color text, Color sub, Color card) {
    if (_clients.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('💼', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 12),
      Text('No clients yet', style: TextStyle(color: sub, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text('Add your first prospect to start tracking', style: TextStyle(color: sub, fontSize: 13)),
      const SizedBox(height: 20),
      GestureDetector(
        onTap: _showAddClientSheet,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
          child: const Text('Add First Client', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ),
    ]));

    // Stats row
    return Column(children: [
      Container(
        color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          _statPill('Pipeline', '\$${_stats['pipeline_value_usd'] ?? 0}', AppColors.primary),
          const SizedBox(width: 8),
          _statPill('Won', '${_stats['won'] ?? 0}', AppColors.success),
          const SizedBox(width: 8),
          _statPill('Close Rate', '${_stats['close_rate_pct'] ?? 0}%', AppColors.gold),
        ]),
      ),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _clients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c = _clients[i];
          final color = Color(_statusColors[c['status']] ?? 0xFF74B9FF);
          return GestureDetector(
            onTap: () => _showClientDetail(c, isDark, text, sub),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.white,
                borderRadius: AppRadius.lg,
                border: Border.all(color: color.withOpacity(0.25)),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
                  child: Center(child: Text(c['name'][0].toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                  Text('${c['service_interest'] ?? 'No service yet'} · ${c['platform'] ?? 'Unknown platform'}', style: TextStyle(fontSize: 12, color: sub)),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: AppRadius.pill),
                    child: Text(c['status']?.toString().replaceAll('_', ' ').toUpperCase() ?? '', style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
                  ),
                  if (c['budget_usd'] != null && c['budget_usd'] > 0) ...[
                    const SizedBox(height: 4),
                    Text('\$${c['budget_usd']}', style: const TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700)),
                  ],
                ]),
              ]),
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
        },
      )),
    ]);
  }

  void _showClientDetail(Map c, bool isDark, Color text, Color sub) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(c['name']?.toString() ?? '', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text)),
          Text(c['service_interest']?.toString() ?? '', style: TextStyle(color: sub, fontSize: 14)),
          const SizedBox(height: 20),
          Expanded(child: ListView(children: [
            if (c['email'] != null) _detailRow('Email', c['email'], text, sub),
            _detailRow('Platform', c['platform'] ?? 'N/A', text, sub),
            _detailRow('Budget', '\$${c['budget_usd'] ?? 0}', text, sub),
            _detailRow('Status', c['status']?.toString().replaceAll('_', ' ') ?? '', text, sub),
            if (c['notes'] != null) _detailRow('Notes', c['notes'], text, sub),
          ])),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
              label: const Text('Generate Follow-up Message', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: () async {
                Navigator.pop(context);
                final r = await api.post('/crm/clients/${c['id']}/ai-followup', {});
                if (mounted) {
                  final msg = (r as Map?)?['follow_up']?['message']?.toString() ?? '';
                  if (msg.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: msg));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Follow-up message copied!'), backgroundColor: AppColors.success));
                  }
                }
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value, Color text, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(children: [
      Text(label, style: TextStyle(fontSize: 12, color: sub, fontWeight: FontWeight.w600)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 13, color: text, fontWeight: FontWeight.w600)),
    ]),
  );

  Widget _buildFollowUps(bool isDark, Color text, Color sub, Color card) {
    if (_dueFollowups.isEmpty) return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('✅', style: TextStyle(fontSize: 48)),
      const SizedBox(height: 12),
      Text('All follow-ups on track!', style: TextStyle(color: sub, fontSize: 15, fontWeight: FontWeight.w600)),
    ]));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _dueFollowups.length,
      itemBuilder: (_, i) {
        final c = _dueFollowups[i];
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.07),
            borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.warning.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Text('⏰', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
              Text('Due: ${c['next_follow_up'] ?? 'overdue'}', style: const TextStyle(fontSize: 12, color: AppColors.warning)),
            ])),
            GestureDetector(
              onTap: () async {
                final r = await api.post('/crm/clients/${c['id']}/ai-followup', {});
                if (mounted) {
                  final msg = (r as Map?)?['follow_up']?['message']?.toString() ?? '';
                  if (msg.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: msg));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Message copied!'), backgroundColor: AppColors.success));
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
                child: const Text('Get Message', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _buildAnalytics(bool isDark, Color text, Color sub, Color card) {
    return FutureBuilder(
      future: api.get('/crm/analytics'),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        final data = snap.data as Map? ?? {};
        if (data['has_data'] != true) return Center(child: Text('Add clients to unlock analytics', style: TextStyle(color: sub)));
        return ListView(padding: const EdgeInsets.all(16), children: [
          _analyticsCard('Total Clients', data['total_clients']?.toString() ?? '0', '👥', AppColors.primary, isDark, text),
          _analyticsCard('Total Earned', '\$${data['total_earned_usd'] ?? 0}', '💰', AppColors.success, isDark, text),
          _analyticsCard('Avg Deal Size', '\$${data['avg_deal_size_usd'] ?? 0}', '📊', AppColors.gold, isDark, text),
          _analyticsCard('Best Platform', data['best_platform']?.toString() ?? 'N/A', '⭐', AppColors.accent, isDark, text),
          if (data['insight'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: AppRadius.lg, border: Border.all(color: AppColors.primary.withOpacity(0.3))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🧠 KEY INSIGHT', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 11, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(data['insight'].toString(), style: TextStyle(color: text, fontSize: 13, height: 1.5)),
              ]),
            ),
          ],
        ]);
      },
    );
  }

  Widget _analyticsCard(String label, String value, String emoji, Color color, bool isDark, Color text) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: isDark ? AppColors.bgCard : Colors.white,
      borderRadius: AppRadius.lg,
      border: Border.all(color: color.withOpacity(0.2)),
    ),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 24)),
      const SizedBox(width: 14),
      Text(label, style: TextStyle(fontSize: 14, color: text)),
      const Spacer(),
      Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: color)),
    ]),
  );

  Widget _statPill(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: AppRadius.md),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
      ]),
    ),
  );
}
