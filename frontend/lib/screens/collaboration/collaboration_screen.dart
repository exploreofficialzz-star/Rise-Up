import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────
// Collaboration Screen
// Users propose big income goals, invite others to tackle together.
// Each collab has: goal, roles needed, progress, revenue split, chat.
// ─────────────────────────────────────────────────────────────────

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});
  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _discover = [];
  Map _mine = {'owned': [], 'joined': [], 'pending': []};
  bool _loading = true;

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
        api.get('/collaborations/'),
        api.get('/collaborations/mine'),
      ]);
      if (mounted) {
        setState(() {
          _discover = (results[0] as Map?)?['collaborations'] as List? ?? [];
          _mine = Map<String, dynamic>.from((results[1] as Map?) ?? {});
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestJoin(String collabId) async {
    try {
      await api.post('/collaborations/$collabId/request', {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request sent! ✅'), backgroundColor: AppColors.success),
        );
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().contains('already') ? 'Already requested' : 'Failed to send request'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

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
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => context.pop(),
        ),
        title: Text('Collaboration', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.add_circle, color: AppColors.primary),
            onPressed: () => _showCreateSheet(context, isDark, border, text, sub),
            tooltip: 'Start a Collaboration',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: sub,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Discover'), Tab(text: 'My Collabs'), Tab(text: 'Requests')],
            ),
            Divider(height: 1, color: border),
          ]),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
            : TabBarView(
                controller: _tabs,
                children: [
                  _DiscoverTab(collabs: _discover, isDark: isDark, bg: bg, card: card, border: border, text: text, sub: sub, onJoin: _requestJoin),
                  _MyCollabsTab(mine: _mine, isDark: isDark, bg: bg, card: card, border: border, text: text, sub: sub),
                  _RequestsTab(pending: (_mine['pending'] as List?) ?? [], isDark: isDark, bg: bg, card: card, border: border, text: text, sub: sub),
                ],
              ),
      ),
    );
  }

  void _showCreateSheet(BuildContext context, bool isDark, Color border, Color text, Color sub) {
    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedType = 'youtube';

    const types = [
      ('▶️', 'youtube', 'YouTube Channel'),
      ('💻', 'freelance', 'Freelance Agency'),
      ('🛍️', 'ecommerce', 'eCommerce Store'),
      ('📝', 'content', 'Content Studio'),
      ('🔗', 'affiliate', 'Affiliate Network'),
      ('🏪', 'physical', 'Physical Business'),
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (ctx, setS) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(children: [
                  Text('Start a Collaboration', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close_rounded, color: sub), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(left: 20, right: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),
                    Text('Income Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: types.map((t) {
                        final sel = selectedType == t.$2;
                        return GestureDetector(
                          onTap: () => setS(() => selectedType = t.$2),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: sel ? AppColors.primary : (isDark ? Colors.white24 : Colors.grey.shade300)),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(t.$1, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Text(t.$3, style: TextStyle(fontSize: 12, color: sel ? Colors.white : sub, fontWeight: FontWeight.w500)),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 16),
                    Text('Project Title', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(fontSize: 14, color: text),
                      decoration: InputDecoration(
                        hintText: 'e.g. Build a personal finance YouTube channel',
                        hintStyle: TextStyle(color: sub, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text('What you need help with', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: sub)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      maxLines: 4,
                      style: TextStyle(fontSize: 14, color: text),
                      decoration: InputDecoration(
                        hintText: 'Describe the goal, the roles you need, and what each collaborator gets...',
                        hintStyle: TextStyle(color: sub, fontSize: 13),
                        filled: true,
                        fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: () async {
                          if (titleCtrl.text.trim().isEmpty) return;
                          Navigator.pop(ctx);
                          try {
                            await api.post('/collaborations/', {
                              'title': titleCtrl.text.trim(),
                              'description': descCtrl.text.trim(),
                              'income_type': selectedType,
                            });
                            _load();
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('✅ Collaboration posted!'), backgroundColor: AppColors.success),
                            );
                          } catch (e) {
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error),
                            );
                          }
                        },
                        child: const Text('Post Collaboration',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Discover Tab ──────────────────────────────────────
class _DiscoverTab extends StatelessWidget {
  final List collabs;
  final bool isDark;
  final Color bg, card, border, text, sub;
  final Function(String) onJoin;
  const _DiscoverTab({required this.collabs, required this.isDark, required this.bg, required this.card, required this.border, required this.text, required this.sub, required this.onJoin});

  static final _collabs = [
    _CollabModel(
      id: '1', emoji: '▶️', type: 'YouTube Channel',
      title: 'Personal Finance YouTube — Need Video Editor',
      owner: 'Marcus Wealth', ownerEmoji: '💎', verified: true,
      description: 'I script and record, need someone to edit 2-3 videos/week. Revenue split 70/30 once monetized. Channel already at 800 subs.',
      roles: ['Video Editor', 'Thumbnail Designer'],
      rolesNeeded: 2, rolesFilled: 0,
      potentialRevenue: 'NGN 150K-400K/mo',
      members: 1, maxMembers: 3,
      tag: '💻 Content',
    ),
    _CollabModel(
      id: '2', emoji: '💻', type: 'Freelance Agency',
      title: 'WhatsApp Business Automation Agency',
      owner: 'Sarah Builds', ownerEmoji: '🚀', verified: false,
      description: 'Building an agency that sets up WhatsApp automation for small businesses in Lagos. Need a sales person and one more developer.',
      roles: ['Sales Person', 'Backend Dev'],
      rolesNeeded: 2, rolesFilled: 1,
      potentialRevenue: 'NGN 500K-1M/mo',
      members: 2, maxMembers: 4,
      tag: '⚡ Agency',
    ),
    _CollabModel(
      id: '3', emoji: '🛍️', type: 'eCommerce',
      title: 'Thrift Fashion Store on Instagram + Jumia',
      owner: 'Priya Skills', ownerEmoji: '🎯', verified: true,
      description: 'I source quality thrift items. Need a social media manager to run content + someone to handle delivery logistics in Abuja.',
      roles: ['Social Media Manager', 'Logistics Handler'],
      rolesNeeded: 2, rolesFilled: 1,
      potentialRevenue: 'NGN 80K-250K/mo',
      members: 2, maxMembers: 3,
      tag: '🛍️ eCommerce',
    ),
    _CollabModel(
      id: '4', emoji: '📝', type: 'Content Studio',
      title: 'Newsletter + LinkedIn Content for Tech Founders',
      owner: 'Alex Johnson', ownerEmoji: '💼', verified: true,
      description: 'Looking for a writer/researcher to co-produce weekly newsletter. \$200/mo per subscriber target. Need 2 great writers.',
      roles: ['Writer', 'Researcher'],
      rolesNeeded: 2, rolesFilled: 0,
      potentialRevenue: '\$800-2,000/mo',
      members: 1, maxMembers: 3,
      tag: '✍️ Content',
    ),
    _CollabModel(
      id: '5', emoji: '🔗', type: 'Affiliate Network',
      title: 'Finance & Crypto Affiliate Team',
      owner: 'David Hustle', ownerEmoji: '🔥', verified: false,
      description: 'Building a 5-person affiliate team. I handle the tools and tracking. You bring traffic. Profit split monthly. All remote.',
      roles: ['Traffic Manager', 'SEO Specialist', 'Content Writer'],
      rolesNeeded: 3, rolesFilled: 1,
      potentialRevenue: '\$500-3,000/mo',
      members: 2, maxMembers: 5,
      tag: '🔗 Affiliate',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (collabs.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('🤝', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No open collaborations yet', style: TextStyle(color: sub, fontSize: 14)),
        const SizedBox(height: 8),
        Text('Be the first to start one!', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 13)),
      ]));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: collabs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final c = collabs[i] as Map;
        final profile = c['profiles'] as Map? ?? {};
        final rolesFilled = (c['roles_filled'] as num?)?.toInt() ?? 0;
        final rolesNeeded = (c['roles_needed'] as num?)?.toInt() ?? 1;
        final userStatus = c['user_status']?.toString();
        return GestureDetector(
          onTap: () { HapticFeedback.lightImpact(); },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(c['emoji']?.toString() ?? '🤝', style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c['title']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text('by ${profile['full_name'] ?? 'User'}  ·  ${c['income_type'] ?? ''}', style: TextStyle(fontSize: 11, color: sub)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                  child: Text(c['tag']?.toString() ?? '', style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              Text(c['description']?.toString() ?? '', style: TextStyle(fontSize: 13, color: sub, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 10),
              Row(children: [
                Text('${c['potential_revenue'] ?? ''}', style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12)),
                const Spacer(),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    if (userStatus == null) onJoin(c['id'].toString());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: userStatus != null ? Colors.transparent : AppColors.primary,
                      borderRadius: BorderRadius.circular(20),
                      border: userStatus != null ? Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300) : null,
                    ),
                    child: Text(
                      userStatus == 'pending' ? 'Requested' : userStatus == 'accepted' ? 'Joined ✓' : 'Request to Join',
                      style: TextStyle(color: userStatus != null ? sub : Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ]),
            ]),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 60)).slideY(begin: 0.1, end: 0);
      },
    );
  }
}

// ── My Collabs Tab ────────────────────────────────────
class _MyCollabsTab extends StatelessWidget {
  final Map mine;
  final bool isDark;
  final Color bg, card, border, text, sub;
  const _MyCollabsTab({required this.mine, required this.isDark, required this.bg, required this.card, required this.border, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Center(child: Text('🤝', style: TextStyle(fontSize: 40))),
          ).animate().scale(),
          const SizedBox(height: 20),
          Text('No Active Collaborations', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
          const SizedBox(height: 8),
          Text('Start or join a collaboration to build bigger income goals with others.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () => context.go('/collaboration'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
              child: const Text('Browse Collaborations', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── Requests Tab ──────────────────────────────────────
class _RequestsTab extends StatelessWidget {
  final List pending;
  final bool isDark;
  final Color bg, card, border, text, sub;
  const _RequestsTab({required this.pending, required this.isDark, required this.bg, required this.card, required this.border, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('📬', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('No pending requests', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: text)),
        const SizedBox(height: 6),
        Text('Your join requests will appear here.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pending.length,
      itemBuilder: (_, i) {
        final p = pending[i] as Map;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(children: [
            Text(p['emoji']?.toString() ?? '🤝', style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['title']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
              Text('Pending approval', style: TextStyle(fontSize: 11, color: AppColors.warning)),
            ])),
          ]),
        );
      },
    );
  }
}

// ── Collab Card ───────────────────────────────────────
class _CollabCard extends StatelessWidget {
  final _CollabModel collab;
  final bool isDark;
  final Color card, border, text, sub;
  final VoidCallback onTap;
  const _CollabCard({required this.collab, required this.isDark, required this.card, required this.border, required this.text, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = collab;
    final filled = c.rolesFilled;
    final needed = c.rolesNeeded;
    final progress = needed > 0 ? filled / needed : 0.0;

    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isDark ? AppColors.bgSurface : Colors.grey.shade200),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(c.emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c.type, style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
              Text(c.title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text), maxLines: 2, overflow: TextOverflow.ellipsis),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
              child: Text(c.potentialRevenue, style: const TextStyle(fontSize: 9, color: AppColors.success, fontWeight: FontWeight.w700)),
            ),
          ]),

          const SizedBox(height: 10),

          // Description
          Text(c.description, style: TextStyle(fontSize: 12.5, color: sub, height: 1.5), maxLines: 2, overflow: TextOverflow.ellipsis),

          const SizedBox(height: 12),

          // Roles needed
          Wrap(
            spacing: 6, runSpacing: 6,
            children: c.roles.map((r) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Iconsax.user_add, size: 10, color: AppColors.primary),
                const SizedBox(width: 4),
                Text(r, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ]),
            )).toList(),
          ),

          const SizedBox(height: 12),

          // Footer
          Row(children: [
            // Owner
            Container(
              width: 22, height: 22,
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
              child: Center(child: Text(c.ownerEmoji, style: const TextStyle(fontSize: 11))),
            ),
            const SizedBox(width: 6),
            Text(c.owner, style: TextStyle(fontSize: 11, color: sub)),
            if (c.verified) ...[const SizedBox(width: 3), const Icon(Icons.verified_rounded, color: AppColors.primary, size: 11)],
            const Spacer(),
            // Member slots
            Text('${c.members}/${c.maxMembers} members', style: TextStyle(fontSize: 11, color: sub)),
            const SizedBox(width: 10),
            // Progress
            SizedBox(
              width: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                  valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                  minHeight: 4,
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Collab Detail Sheet ───────────────────────────────
class _CollabDetailSheet extends StatelessWidget {
  final _CollabModel collab;
  final bool isDark;
  final Color border, text, sub;
  const _CollabDetailSheet({required this.collab, required this.isDark, required this.border, required this.text, required this.sub});

  @override
  Widget build(BuildContext context) {
    final c = collab;
    final bg = isDark ? AppColors.bgCard : Colors.white;
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Title block
                Row(children: [
                  Text(c.emoji, style: const TextStyle(fontSize: 32)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c.type, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
                    Text(c.title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
                  ])),
                ]),
                const SizedBox(height: 16),

                // Revenue potential
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.success.withOpacity(0.25))),
                  child: Row(children: [
                    const Text('💰', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Revenue Potential', style: TextStyle(fontSize: 11, color: AppColors.success)),
                      Text(c.potentialRevenue, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 16),

                // Full description
                Text('About this Collab', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                const SizedBox(height: 6),
                Text(c.description, style: TextStyle(fontSize: 13.5, color: sub, height: 1.6)),
                const SizedBox(height: 16),

                // Roles open
                Text('Roles Open', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                const SizedBox(height: 8),
                ...c.roles.map((r) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Container(width: 32, height: 32, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle), child: const Center(child: Icon(Iconsax.user_add, size: 15, color: AppColors.primary))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                      Text('Apply to fill this role', style: TextStyle(fontSize: 11, color: sub)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Text('Open', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
                    ),
                  ]),
                )),
                const SizedBox(height: 16),

                // Current team
                Text('Current Team (${c.members}/${c.maxMembers})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                const SizedBox(height: 8),
                Row(children: [
                  Container(width: 36, height: 36, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle), child: Center(child: Text(c.ownerEmoji, style: const TextStyle(fontSize: 18)))),
                  const SizedBox(width: 10),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(c.owner, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                      if (c.verified) ...[const SizedBox(width: 4), const Icon(Icons.verified_rounded, color: AppColors.primary, size: 12)],
                    ]),
                    Text('Owner', style: TextStyle(fontSize: 11, color: sub)),
                  ]),
                ]),
                const SizedBox(height: 24),
              ]),
            ),
          ),

          // CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Request sent to ${c.owner}!'), backgroundColor: AppColors.success),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Request to Join', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Data Model ────────────────────────────────────────
class _CollabModel {
  final String id, emoji, type, title, owner, ownerEmoji, description, potentialRevenue, tag;
  final List<String> roles;
  final int rolesNeeded, rolesFilled, members, maxMembers;
  final bool verified;

  const _CollabModel({
    required this.id, required this.emoji, required this.type, required this.title,
    required this.owner, required this.ownerEmoji, required this.description,
    required this.roles, required this.rolesNeeded, required this.rolesFilled,
    required this.potentialRevenue, required this.members, required this.maxMembers,
    required this.tag, this.verified = false,
  });
}
