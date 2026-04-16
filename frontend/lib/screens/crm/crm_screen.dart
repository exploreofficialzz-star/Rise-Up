// frontend/lib/screens/crm/crm_screen.dart
//
// v2.0 — Production-ready CRM screen
//
// FIXES:
//  BUG 1 (clients not saving):
//    Navigator.pop() was called BEFORE await api.post() — the sheet
//    dismissed optimistically and if the API call failed, the user saw
//    nothing. The button now shows a loading spinner, awaits the API call,
//    shows a success snackbar on completion, and shows an error snackbar
//    on failure — all before dismissing.
//
//  BUG 2 (no ads):
//    No ad placements existed on this screen. Now wired:
//      • ScreenBannerAd  — sticky bottom banner (Pipeline + Follow-ups tabs)
//      • adManager.showInterstitial() — fires after a client is added
//      • PremiumUpsellBanner — shown in Analytics when data exists
//      • UsageLimitBanner — shown in Pipeline header when pipeline is populated

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/ad_manager.dart';
import '../../services/api_service.dart';
import '../../widgets/ad_widgets.dart';

class CrmScreen extends StatefulWidget {
  const CrmScreen({super.key});
  @override
  State<CrmScreen> createState() => _CrmScreenState();
}

class _CrmScreenState extends State<CrmScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _clients      = [];
  Map  _stats        = {};
  List _dueFollowups = [];
  bool _loading      = true;

  static const _statusColors = {
    'prospect':      0xFF74B9FF,
    'contacted':     0xFFFFD700,
    'proposal_sent': 0xFFFF6B35,
    'negotiating':   0xFFFF3CAC,
    'won':           0xFF00B894,
    'lost':          0xFFD63031,
    'recurring':     0xFF6C5CE7,
  };

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/crm/clients'),
        api.get('/crm/follow-ups/due'),
      ]);
      if (!mounted) return;
      setState(() {
        final data = results[0] as Map? ?? {};
        _clients       = data['clients']  as List? ?? [];
        _stats         = data['stats']    as Map?  ?? {};
        _dueFollowups  = (results[1] as Map?)?['overdue_followups'] as List? ?? [];
        _loading       = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Add-client sheet ───────────────────────────────────────────────────────
  void _showAddClientSheet() {
    final nameCtrl     = TextEditingController();
    final platformCtrl = TextEditingController();
    final serviceCtrl  = TextEditingController();
    final budgetCtrl   = TextEditingController();
    final isDark       = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _AddClientSheet(
        isDark:      isDark,
        nameCtrl:    nameCtrl,
        platformCtrl: platformCtrl,
        serviceCtrl: serviceCtrl,
        budgetCtrl:  budgetCtrl,
        onSaved: (name) async {
          // BUG 1 FIX: The sheet widget handles loading state internally and
          // only dismisses after the API call succeeds (or fails with feedback).
          // _load() and the interstitial fire AFTER dismiss, from here.
          await _load();

          // Wire ads: show interstitial after adding a client
          await adManager.showInterstitial();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('✅ $name added to your CRM'),
              backgroundColor: AppColors.success,
              duration: const Duration(seconds: 2),
            ));
          }
        },
      ),
    );
  }

  // ── Client detail sheet ────────────────────────────────────────────────────
  void _showClientDetail(Map c, bool isDark, Color text, Color sub) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.65,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            c['name']?.toString() ?? '',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: text),
          ),
          Text(
            c['service_interest']?.toString() ?? '',
            style: TextStyle(color: sub, fontSize: 14),
          ),
          const SizedBox(height: 20),
          Expanded(child: ListView(children: [
            if (c['email'] != null) _detailRow('Email',    c['email'],    text, sub),
            _detailRow('Platform', c['platform'] ?? 'N/A', text, sub),
            _detailRow('Budget',   '\$${c['budget_usd'] ?? 0}', text, sub),
            _detailRow('Status',   c['status']?.toString().replaceAll('_', ' ') ?? '', text, sub),
            if (c['notes'] != null) _detailRow('Notes', c['notes'], text, sub),
          ])),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon:  const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
              label: const Text(
                'Generate Follow-up Message',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              onPressed: () async {
                Navigator.pop(context);
                try {
                  final r = await api.post('/crm/clients/${c['id']}/ai-followup', {});
                  if (!mounted) return;
                  final msg = (r as Map?)?['follow_up']?['message']?.toString() ?? '';
                  if (msg.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: msg));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ Follow-up message copied!'),
                      backgroundColor: AppColors.success,
                    ));
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Failed to generate message. Try again.'),
                      backgroundColor: AppColors.error,
                    ));
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

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? Colors.black : Colors.white;
    final card   = isDark ? AppColors.bgCard : Colors.white;
    final text   = isDark ? Colors.white : Colors.black87;
    final sub    = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () => context.pop(),
        ),
        title: Row(children: [
          const Text('💼', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('Client CRM', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: AppColors.primary),
            onPressed: _showAddClientSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppColors.primary,
          unselectedLabelColor: sub,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            const Tab(text: 'Pipeline'),
            Tab(text: _dueFollowups.isEmpty ? 'Follow-ups' : '⚡ Follow-ups (${_dueFollowups.length})'),
            const Tab(text: 'Analytics'),
          ],
        ),
      ),
      // ── Ads: sticky banner below scaffold body (Pipeline + Follow-ups) ──────
      bottomNavigationBar: AnimatedBuilder(
        animation: _tabs,
        builder: (_, __) {
          // No banner on Analytics tab — premium upsell lives inside it
          if (_tabs.index == 2) return const SizedBox.shrink();
          return ScreenBannerAd(isDark: isDark);
        },
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.primary,
              child: TabBarView(
                controller: _tabs,
                children: [
                  _buildPipeline(isDark, text, sub, card),
                  _buildFollowUps(isDark, text, sub, card),
                  _buildAnalytics(isDark, text, sub, card),
                ],
              ),
            ),
    );
  }

  // ── Pipeline tab ───────────────────────────────────────────────────────────
  Widget _buildPipeline(bool isDark, Color text, Color sub, Color card) {
    if (_clients.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('💼', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 12),
        Text('No clients yet',
            style: TextStyle(color: sub, fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Add your first prospect to start tracking',
            style: TextStyle(color: sub, fontSize: 13)),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: _showAddClientSheet,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
            child: const Text('Add First Client',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ),
      ]));
    }

    return Column(children: [
      // Stats row
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
      // Ads: usage limit nudge when pipeline has clients
      UsageLimitBanner(
        remaining: adManager.premiumUsesRemaining,
        total:     3,
        featureName: 'AI follow-ups',
        isDark:    isDark,
      ),
      Expanded(child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _clients.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final c     = _clients[i];
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
                  decoration: BoxDecoration(
                      color: color.withOpacity(0.12), shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      c['name'][0].toUpperCase(),
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['name']?.toString() ?? '',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                  Text(
                    '${c['service_interest'] ?? 'No service yet'} · ${c['platform'] ?? 'Unknown platform'}',
                    style: TextStyle(fontSize: 12, color: sub),
                  ),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12), borderRadius: AppRadius.pill),
                    child: Text(
                      c['status']?.toString().replaceAll('_', ' ').toUpperCase() ?? '',
                      style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (c['budget_usd'] != null && c['budget_usd'] > 0) ...[
                    const SizedBox(height: 4),
                    Text('\$${c['budget_usd']}',
                        style: const TextStyle(fontSize: 12, color: AppColors.success, fontWeight: FontWeight.w700)),
                  ],
                ]),
              ]),
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
        },
      )),
    ]);
  }

  // ── Follow-ups tab ─────────────────────────────────────────────────────────
  Widget _buildFollowUps(bool isDark, Color text, Color sub, Color card) {
    if (_dueFollowups.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('✅', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('All follow-ups on track!',
            style: TextStyle(color: sub, fontSize: 15, fontWeight: FontWeight.w600)),
      ]));
    }

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
              Text(c['name']?.toString() ?? '',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
              Text('Due: ${c['next_follow_up'] ?? 'overdue'}',
                  style: const TextStyle(fontSize: 12, color: AppColors.warning)),
            ])),
            GestureDetector(
              onTap: () async {
                try {
                  final r = await api.post('/crm/clients/${c['id']}/ai-followup', {});
                  if (!mounted) return;
                  final msg = (r as Map?)?['follow_up']?['message']?.toString() ?? '';
                  if (msg.isNotEmpty) {
                    await Clipboard.setData(ClipboardData(text: msg));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('✅ Message copied!'),
                      backgroundColor: AppColors.success,
                    ));
                  }
                } catch (_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Failed to generate message. Try again.'),
                      backgroundColor: AppColors.error,
                    ));
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
                child: const Text('Get Message',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        );
      },
    );
  }

  // ── Analytics tab ──────────────────────────────────────────────────────────
  Widget _buildAnalytics(bool isDark, Color text, Color sub, Color card) {
    return FutureBuilder(
      future: api.get('/crm/analytics'),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        final data = snap.data as Map? ?? {};
        if (data['has_data'] != true) {
          return Center(child: Text('Add clients to unlock analytics',
              style: TextStyle(color: sub)));
        }
        return ListView(padding: const EdgeInsets.all(16), children: [
          _analyticsCard('Total Clients', data['total_clients']?.toString() ?? '0',   '👥', AppColors.primary, isDark, text),
          _analyticsCard('Total Earned',  '\$${data['total_earned_usd'] ?? 0}',       '💰', AppColors.success, isDark, text),
          _analyticsCard('Avg Deal Size', '\$${data['avg_deal_size_usd'] ?? 0}',      '📊', AppColors.gold,    isDark, text),
          _analyticsCard('Best Platform', data['best_platform']?.toString() ?? 'N/A', '⭐', AppColors.accent,  isDark, text),
          if (data['insight'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                borderRadius: AppRadius.lg,
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🧠 KEY INSIGHT',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700,
                        fontSize: 11, letterSpacing: 0.5)),
                const SizedBox(height: 6),
                Text(data['insight'].toString(),
                    style: TextStyle(color: text, fontSize: 13, height: 1.5)),
              ]),
            ),
          ],
          // Ads: premium upsell inside analytics — contextually relevant
          // (they're seeing data value, ideal moment to upsell)
          const SizedBox(height: 8),
          PremiumUpsellBanner(isDark: isDark),
        ]);
      },
    );
  }

  Widget _analyticsCard(String label, String value, String emoji,
      Color color, bool isDark, Color text) =>
      Container(
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

// ── Add-client sheet (extracted widget so it owns its own loading state) ──────
//
// The key fix: the Save button now owns a _saving bool. It awaits api.post()
// BEFORE calling Navigator.pop(). If the call fails, the sheet stays open
// and shows an error — the user can retry without re-entering data.

class _AddClientSheet extends StatefulWidget {
  final bool                  isDark;
  final TextEditingController nameCtrl, platformCtrl, serviceCtrl, budgetCtrl;
  final Future<void> Function(String name) onSaved;

  const _AddClientSheet({
    required this.isDark,
    required this.nameCtrl,
    required this.platformCtrl,
    required this.serviceCtrl,
    required this.budgetCtrl,
    required this.onSaved,
  });

  @override
  State<_AddClientSheet> createState() => _AddClientSheetState();
}

class _AddClientSheetState extends State<_AddClientSheet> {
  bool _saving = false;

  Future<void> _save() async {
    final name = widget.nameCtrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _saving = true);
    try {
      await api.post('/crm/clients', {
        'name':             name,
        'platform':         widget.platformCtrl.text.trim(),
        'service_interest': widget.serviceCtrl.text.trim(),
        'budget_usd':       double.tryParse(widget.budgetCtrl.text) ?? 0,
      });

      if (!mounted) return;
      // Dismiss AFTER success
      Navigator.pop(context);
      // Notify parent to reload + show interstitial
      await widget.onSaved(name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Failed to save client. Please try again.'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Widget _field(TextEditingController c, String hint,
      {TextInputType? type}) =>
      TextField(
        controller: c,
        keyboardType: type,
        style: TextStyle(color: widget.isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
              color: widget.isDark ? Colors.white38 : Colors.black38,
              fontSize: 13),
          filled: true,
          fillColor: widget.isDark ? AppColors.bgSurface : Colors.grey.shade100,
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
      EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: widget.isDark ? AppColors.bgCard : Colors.white,
          borderRadius:
          const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add Client',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: widget.isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 16),
              _field(widget.nameCtrl, 'Client name *'),
              const SizedBox(height: 10),
              _field(widget.platformCtrl,
                  'Where you met them (Upwork, Instagram...)'),
              const SizedBox(height: 10),
              _field(widget.serviceCtrl, 'Service they need'),
              const SizedBox(height: 10),
              _field(widget.budgetCtrl, 'Budget (\$USD)',
                  type: TextInputType.number),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding:
                      const EdgeInsets.symmetric(vertical: 14)),
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                      : const Text('Add to CRM',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
      ),
    );
  }
}
