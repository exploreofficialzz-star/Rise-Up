import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  List _items = [];
  Map _stats = {};
  Map _bio = {};
  bool _loading = true;
  bool _generatingBio = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.get('/portfolio/');
      if (mounted) setState(() {
        _items = (data as Map?)?['items'] as List? ?? [];
        _stats = data?['stats'] as Map? ?? {};
        _loading = false;
      });
    } catch (_) { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _generateBio() async {
    setState(() => _generatingBio = true);
    try {
      final data = await api.post('/portfolio/ai-bio', {});
      if (mounted) setState(() {
        _bio = (data as Map?)?['bio'] as Map? ?? {};
        _generatingBio = false;
      });
    } catch (_) { if (mounted) setState(() => _generatingBio = false); }
  }

  void _showAddProjectSheet() {
    final titleCtrl = TextEditingController();
    final serviceCtrl = TextEditingController();
    final challengeCtrl = TextEditingController();
    final resultCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.75,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add Project', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 16),
            Expanded(child: ListView(children: [
              _buildField(titleCtrl, 'Project title *', isDark),
              const SizedBox(height: 10),
              _buildField(serviceCtrl, 'Service type (e.g. Logo Design)', isDark),
              const SizedBox(height: 10),
              _buildField(challengeCtrl, 'Challenge solved for client', isDark, maxLines: 2),
              const SizedBox(height: 10),
              _buildField(resultCtrl, 'Result achieved (be specific)', isDark, maxLines: 2),
              const SizedBox(height: 10),
              _buildField(amountCtrl, 'Amount earned (\$USD)', isDark, type: TextInputType.number),
            ])),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () async {
                  Navigator.pop(context);
                  await api.post('/portfolio/projects', {
                    'title': titleCtrl.text,
                    'service_type': serviceCtrl.text,
                    'challenge_solved': challengeCtrl.text,
                    'result_achieved': resultCtrl.text,
                    'amount_usd': double.tryParse(amountCtrl.text) ?? 0,
                    'skills_used': [],
                    'is_public': true,
                  });
                  _load();
                },
                child: const Text('Add Project', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController c, String hint, bool isDark, {int maxLines = 1, TextInputType? type}) => TextField(
    controller: c, maxLines: maxLines, keyboardType: type,
    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
      filled: true, fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
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
          const Text('🎨', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('Portfolio', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          IconButton(icon: const Icon(Icons.add_rounded, color: AppColors.primary, size: 26), onPressed: _showAddProjectSheet),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load, color: AppColors.primary,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                // Share link banner
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF6C5CE7), Color(0xFFFF3CAC)]),
                    borderRadius: AppRadius.lg,
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('YOUR PORTFOLIO LINK', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
                      const SizedBox(height: 4),
                      const Text('Share with clients instantly', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                    ])),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(const ClipboardData(text: 'riseup.app/portfolio'));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Link copied!'), backgroundColor: AppColors.success));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: AppRadius.pill),
                        child: const Row(children: [
                          Icon(Icons.copy_rounded, color: Colors.white, size: 14),
                          SizedBox(width: 6),
                          Text('Copy Link', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ]),
                      ),
                    ),
                  ]),
                ).animate().fadeIn(),
                const SizedBox(height: 16),

                // Stats
                if (_stats.isNotEmpty) Row(children: [
                  _statBox('Projects', _stats['total_projects']?.toString() ?? '0', AppColors.primary, isDark),
                  const SizedBox(width: 10),
                  _statBox('Total Value', '\$${_stats['total_value_usd'] ?? 0}', AppColors.success, isDark),
                ]),
                const SizedBox(height: 16),

                // AI Bio section
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: AppColors.accent.withOpacity(0.2)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.auto_awesome, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      Text('AI-Generated Professional Bio', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
                    ]),
                    const SizedBox(height: 10),
                    if (_bio.isEmpty)
                      GestureDetector(
                        onTap: _generateBio,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1), borderRadius: AppRadius.pill, border: Border.all(color: AppColors.accent.withOpacity(0.3))),
                          child: Center(child: _generatingBio
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accent, strokeWidth: 2))
                              : const Text('✨ Generate My Professional Bio', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 13))),
                        ),
                      )
                    else ...[
                      Text(_bio['short_bio']?.toString() ?? '', style: TextStyle(fontSize: 13, color: text, height: 1.5)),
                      const SizedBox(height: 8),
                      if (_bio['linkedin_headline'] != null) Row(children: [
                        const Icon(Icons.work_outline_rounded, size: 14, color: AppColors.textMuted),
                        const SizedBox(width: 6),
                        Expanded(child: Text(_bio['linkedin_headline'].toString(), style: TextStyle(fontSize: 12, color: sub, fontStyle: FontStyle.italic))),
                      ]),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: () { Clipboard.setData(ClipboardData(text: _bio['full_bio']?.toString() ?? '')); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Full bio copied!'), backgroundColor: AppColors.success)); },
                        child: Row(children: [const Icon(Iconsax.copy, size: 14, color: AppColors.accent), const SizedBox(width: 6), const Text('Copy Full Bio', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.w600))]),
                      ),
                    ],
                  ]),
                ),
                const SizedBox(height: 20),

                // Portfolio items
                if (_items.isEmpty)
                  Center(child: Column(children: [
                    const SizedBox(height: 20),
                    const Text('🎨', style: TextStyle(fontSize: 48)),
                    const SizedBox(height: 12),
                    Text('No projects yet', style: TextStyle(color: sub, fontSize: 15)),
                    const SizedBox(height: 8),
                    Text('Add completed projects to build social proof', style: TextStyle(color: sub, fontSize: 13), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _showAddProjectSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
                        child: const Text('Add First Project', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]))
                else
                  ..._items.asMap().entries.map((e) {
                    final p = e.value as Map;
                    final colors = [AppColors.primary, AppColors.accent, AppColors.success, AppColors.gold];
                    final color = colors[e.key % colors.length];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.bgCard : Colors.white,
                        borderRadius: AppRadius.lg,
                        border: Border.all(color: color.withOpacity(0.2)),
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, spreadRadius: -2)],
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Expanded(child: Text(p['title']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text))),
                          if (p['amount_usd'] != null && p['amount_usd'] > 0)
                            Text('\$${p['amount_usd']}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.success)),
                        ]),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: AppRadius.pill),
                          child: Text(p['service_type']?.toString() ?? '', style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(height: 10),
                        if (p['challenge_solved'] != null) ...[
                          Text('Challenge', style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(p['challenge_solved'].toString(), style: TextStyle(fontSize: 13, color: text, height: 1.4)),
                          const SizedBox(height: 8),
                        ],
                        if (p['result_achieved'] != null) ...[
                          Text('Result', style: TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text(p['result_achieved'].toString(), style: TextStyle(fontSize: 13, color: text, height: 1.4)),
                        ],
                        if (p['testimonial'] != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: color.withOpacity(0.06), borderRadius: AppRadius.md),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.format_quote_rounded, color: color, size: 16),
                              const SizedBox(width: 6),
                              Expanded(child: Text(p['testimonial'].toString(), style: TextStyle(fontSize: 12, color: text, fontStyle: FontStyle.italic, height: 1.4))),
                            ]),
                          ),
                        ],
                      ]),
                    ).animate().fadeIn(delay: Duration(milliseconds: e.key * 60));
                  }),
                const SizedBox(height: 40),
              ]),
            ),
    );
  }

  Widget _statBox(String label, String value, Color color, bool isDark) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: AppRadius.lg, border: Border.all(color: color.withOpacity(0.2))),
      child: Column(children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.7))),
      ]),
    ),
  );
}
