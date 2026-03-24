import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ContractsScreen extends StatefulWidget {
  const ContractsScreen({super.key});
  @override
  State<ContractsScreen> createState() => _ContractsScreenState();
}

class _ContractsScreenState extends State<ContractsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _contracts = [];
  List _invoices = [];
  double _totalInvoiced = 0;
  double _totalPaid = 0;
  double _outstanding = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await api.get('/contracts/');
      if (mounted) setState(() {
        final d = data as Map? ?? {};
        _contracts = d['contracts'] as List? ?? [];
        _invoices  = d['invoices']  as List? ?? [];
        _totalInvoiced = (d['total_invoiced_usd'] as num?)?.toDouble() ?? 0;
        _totalPaid     = (d['total_paid_usd']     as num?)?.toDouble() ?? 0;
        _outstanding   = (d['outstanding_usd']    as num?)?.toDouble() ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Generate Contract Sheet ──────────────────────────────────
  void _showGenerateContract() {
    final clientCtrl    = TextEditingController();
    final serviceCtrl   = TextEditingController();
    final amountCtrl    = TextEditingController();
    final del1Ctrl      = TextEditingController();
    final del2Ctrl      = TextEditingController();
    bool _generating    = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) =>
        Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Container(
            height: MediaQuery.of(context).size.height * 0.80,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(4)))),
              const SizedBox(height: 16),
              Text('Generate Contract', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87)),
              const SizedBox(height: 4),
              Text('AI writes a professional contract instantly', style: TextStyle(fontSize: 12,
                  color: isDark ? Colors.white54 : Colors.black45)),
              const SizedBox(height: 20),
              Expanded(child: ListView(children: [
                _field(clientCtrl,  'Client name *', isDark),
                const SizedBox(height: 10),
                _field(serviceCtrl, 'Service type (e.g. Logo Design Package)', isDark),
                const SizedBox(height: 10),
                _field(amountCtrl,  'Contract value (\$USD) *', isDark, type: TextInputType.number),
                const SizedBox(height: 10),
                _field(del1Ctrl, 'Deliverable 1 (e.g. 3 logo concepts)', isDark),
                const SizedBox(height: 10),
                _field(del2Ctrl, 'Deliverable 2 (e.g. Final files in AI, PNG, PDF)', isDark),
              ])),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: _generating
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.auto_awesome, color: Colors.white, size: 16),
                  label: Text(_generating ? 'Writing contract...' : 'Generate Contract',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _generating ? null : () async {
                    if (clientCtrl.text.isEmpty || amountCtrl.text.isEmpty) return;
                    setS(() => _generating = true);
                    try {
                      final result = await api.post('/contracts/generate', {
                        'client_name': clientCtrl.text,
                        'service_type': serviceCtrl.text,
                        'amount_usd': double.tryParse(amountCtrl.text) ?? 0,
                        'deliverables': [del1Ctrl.text, del2Ctrl.text]
                            .where((s) => s.isNotEmpty).toList(),
                        'payment_terms': '50% upfront, 50% on delivery',
                        'duration_days': 14,
                        'revision_rounds': 2,
                      });
                      if (mounted) {
                        Navigator.pop(context);
                        _showContractPreview(result as Map, isDark);
                        _load();
                      }
                    } catch (e) {
                      setS(() => _generating = false);
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error));
                    }
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  void _showContractPreview(Map result, bool isDark) {
    final contractText = result['contract_text']?.toString() ?? '';
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(children: [
          Row(children: [
            const Text('📄', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(child: Text('Contract Ready', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87))),
            TextButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 14, color: AppColors.primary),
              label: const Text('Copy', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: contractText));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Contract copied!'), backgroundColor: AppColors.success));
              },
            ),
          ]),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: AppRadius.pill),
            child: Text('Contract #${result['contract_number'] ?? ''} · \$${result['amount_usd'] ?? 0}',
                style: const TextStyle(color: AppColors.success, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 14),
          Expanded(child: SingleChildScrollView(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurface : Colors.grey.shade50,
                borderRadius: AppRadius.lg,
                border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade200),
              ),
              child: SelectableText(contractText,
                style: TextStyle(fontSize: 12, color: isDark ? Colors.white : Colors.black87,
                    height: 1.7, fontFamily: 'monospace')),
            ),
          )),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 13)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: contractText));
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('✅ Contract copied — send to client!'), backgroundColor: AppColors.success));
              },
              child: const Text('Copy & Close', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Generate Invoice Sheet ───────────────────────────────────
  void _showGenerateInvoice() {
    final clientCtrl = TextEditingController();
    final descCtrl   = TextEditingController();
    final rateCtrl   = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Generate Invoice', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 16),
            _field(clientCtrl, 'Client name *', isDark),
            const SizedBox(height: 10),
            _field(descCtrl, 'Service description *', isDark),
            const SizedBox(height: 10),
            _field(rateCtrl, 'Amount (\$USD) *', isDark, type: TextInputType.number),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: () async {
                  if (clientCtrl.text.isEmpty || rateCtrl.text.isEmpty) return;
                  Navigator.pop(context);
                  final amount = double.tryParse(rateCtrl.text) ?? 0;
                  await api.post('/contracts/invoice/generate', {
                    'client_name': clientCtrl.text,
                    'items': [{'description': descCtrl.text, 'quantity': 1, 'rate_usd': amount}],
                    'due_days': 7,
                  });
                  _load();
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Invoice generated!'), backgroundColor: AppColors.success));
                },
                child: const Text('Generate Invoice', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, bool isDark,
      {int maxLines = 1, TextInputType? type}) =>
    TextField(
      controller: c, maxLines: maxLines, keyboardType: type,
      style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
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
    final bg   = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub  = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: Icon(Icons.arrow_back_rounded, color: text), onPressed: () => context.pop()),
        title: Row(children: [
          const Text('📄', style: TextStyle(fontSize: 22)),
          const SizedBox(width: 10),
          Text('Contracts & Invoices', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        bottom: TabBar(
          controller: _tabs, labelColor: AppColors.primary, unselectedLabelColor: sub,
          indicatorColor: AppColors.primary, indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [Tab(text: 'Contracts'), Tab(text: 'Invoices')],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _load, color: AppColors.primary,
              child: TabBarView(controller: _tabs, children: [
                _buildContracts(isDark, text, sub),
                _buildInvoices(isDark, text, sub),
              ]),
            ),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'invoice',
          onPressed: _showGenerateInvoice,
          backgroundColor: AppColors.accent,
          child: const Icon(Icons.receipt_long_rounded, color: Colors.white),
        ),
        const SizedBox(height: 8),
        FloatingActionButton.extended(
          heroTag: 'contract',
          onPressed: _showGenerateContract,
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          label: const Text('Contract', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _buildContracts(bool isDark, Color text, Color sub) {
    // Summary strip
    return Column(children: [
      _summaryStrip(isDark, text, sub),
      Expanded(child: _contracts.isEmpty
          ? _emptyState('No contracts yet', 'Generate your first professional contract', isDark, sub)
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: _contracts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final c = _contracts[i] as Map;
                final statusColor = _statusColor(c['status']?.toString() ?? '');
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgCard : Colors.white,
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: statusColor.withOpacity(0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(c['client_name']?.toString() ?? '',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text))),
                      _statusPill(c['status']?.toString() ?? '', statusColor),
                    ]),
                    const SizedBox(height: 4),
                    Text(c['service_type']?.toString() ?? '',
                        style: TextStyle(fontSize: 12, color: sub)),
                    const SizedBox(height: 8),
                    Row(children: [
                      Text('\$${c['amount_usd'] ?? 0}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success)),
                      const Spacer(),
                      Text(c['contract_number']?.toString() ?? '',
                          style: TextStyle(fontSize: 11, color: sub)),
                    ]),
                    if (c['contract_text'] != null) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: c['contract_text'].toString()));
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Contract copied!'), backgroundColor: AppColors.success));
                        },
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.copy_rounded, size: 13, color: AppColors.primary),
                          const SizedBox(width: 5),
                          const Text('Copy contract text',
                              style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                  ]),
                ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
              },
            )),
    ]);
  }

  Widget _buildInvoices(bool isDark, Color text, Color sub) {
    return Column(children: [
      _summaryStrip(isDark, text, sub),
      Expanded(child: _invoices.isEmpty
          ? _emptyState('No invoices yet', 'Generate your first invoice in seconds', isDark, sub)
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: _invoices.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final inv = _invoices[i] as Map;
                final isPaid = inv['status'] == 'paid';
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgCard : Colors.white,
                    borderRadius: AppRadius.lg,
                    border: Border.all(color: (isPaid ? AppColors.success : AppColors.warning).withOpacity(0.25)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(inv['client_name']?.toString() ?? '',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text))),
                      _statusPill(isPaid ? 'paid' : 'pending', isPaid ? AppColors.success : AppColors.warning),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      Text('\$${inv['amount_usd'] ?? 0}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.success)),
                      const Spacer(),
                      Text(inv['invoice_number']?.toString() ?? '',
                          style: TextStyle(fontSize: 11, color: sub)),
                    ]),
                    if (inv['due_date'] != null) Text(
                      'Due: ${inv['due_date'].toString().split('T')[0]}',
                      style: TextStyle(fontSize: 11, color: sub),
                    ),
                    if (!isPaid) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () async {
                          await api.patch('/contracts/invoice/${inv['id']}/paid', {});
                          _load();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Marked paid! Earnings logged.'), backgroundColor: AppColors.success));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(color: AppColors.success, borderRadius: AppRadius.pill),
                          child: const Text('Mark as Paid ✓',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ]),
                ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
              },
            )),
    ]);
  }

  Widget _summaryStrip(bool isDark, Color text, Color sub) => Container(
    color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    child: Row(children: [
      _miniStat('Invoiced', '\$${_totalInvoiced.toStringAsFixed(0)}', AppColors.primary),
      _divider(),
      _miniStat('Paid', '\$${_totalPaid.toStringAsFixed(0)}', AppColors.success),
      _divider(),
      _miniStat('Outstanding', '\$${_outstanding.toStringAsFixed(0)}',
          _outstanding > 0 ? AppColors.warning : sub),
    ]),
  );

  Widget _miniStat(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted)),
    ]),
  );

  Widget _divider() => Container(width: 1, height: 32, color: Colors.grey.withOpacity(0.2));

  Widget _statusPill(String status, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: AppRadius.pill),
    child: Text(status.toUpperCase(), style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700)),
  );

  Color _statusColor(String status) {
    switch (status) {
      case 'signed': return AppColors.success;
      case 'completed': return AppColors.primary;
      case 'sent': return AppColors.warning;
      case 'cancelled': return AppColors.error;
      default: return AppColors.textMuted;
    }
  }

  Widget _emptyState(String title, String sub2, bool isDark, Color sub) => Center(
    child: Padding(padding: const EdgeInsets.all(32),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📄', style: TextStyle(fontSize: 52)),
        const SizedBox(height: 14),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: isDark ? Colors.white : Colors.black87)),
        const SizedBox(height: 6),
        Text(sub2, style: TextStyle(color: sub, fontSize: 13), textAlign: TextAlign.center),
      ]),
    ),
  );
}
