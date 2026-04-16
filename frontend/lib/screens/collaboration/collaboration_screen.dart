import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Collaboration Screen — Production Ready v2.0
//  Fixes: API join query failure, type-casting, empty state bug,
//         create form missing fields, no detail sheet on tap,
//         no ad integration.
// ─────────────────────────────────────────────────────────────────────────────

class CollaborationScreen extends StatefulWidget {
  const CollaborationScreen({super.key});

  @override
  State<CollaborationScreen> createState() => _CollaborationScreenState();
}

class _CollaborationScreenState extends State<CollaborationScreen>
    with SingleTickerProviderStateMixin {
  // ── tabs ───────────────────────────────────────────────────────────────────
  late TabController _tabs;

  // ── data ───────────────────────────────────────────────────────────────────
  List _discover = [];
  Map  _mine     = {'owned': [], 'joined': [], 'pending': []};

  // ── ui state ───────────────────────────────────────────────────────────────
  bool    _loading  = true;
  String? _error;
  bool    _creating = false;

  // ── income type metadata ───────────────────────────────────────────────────
  static const _types = [
    {'emoji': '▶️',  'value': 'youtube',   'label': 'YouTube Channel',   'tag': '▶️ YouTube'},
    {'emoji': '💻',  'value': 'freelance', 'label': 'Freelance Agency',  'tag': '💻 Agency'},
    {'emoji': '🛍️', 'value': 'ecommerce', 'label': 'eCommerce Store',   'tag': '🛍️ eCommerce'},
    {'emoji': '📝',  'value': 'content',   'label': 'Content Studio',    'tag': '✍️ Content'},
    {'emoji': '🔗',  'value': 'affiliate', 'label': 'Affiliate Network', 'tag': '🔗 Affiliate'},
    {'emoji': '🏪',  'value': 'physical',  'label': 'Physical Business', 'tag': '🏪 Physical'},
    {'emoji': '📱',  'value': 'app',       'label': 'App / SaaS',        'tag': '📱 SaaS'},
    {'emoji': '📚',  'value': 'education', 'label': 'Course / Education','tag': '📚 Edu'},
    {'emoji': '🎵',  'value': 'music',     'label': 'Music / Audio',     'tag': '🎵 Music'},
    {'emoji': '🎨',  'value': 'creative',  'label': 'Creative Studio',   'tag': '🎨 Creative'},
  ];

  static String _emojiFor(String type) =>
      (_types.firstWhere((t) => t['value'] == type, orElse: () => {'emoji': '🤝'})['emoji'] as String?) ?? '🤝';

  static String _tagFor(String type) =>
      (_types.firstWhere((t) => t['value'] == type, orElse: () => {'tag': '🤝 Other'})['tag'] as String?) ?? '🤝 Other';

  // ── lifecycle ──────────────────────────────────────────────────────────────

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

  // ── data helpers ───────────────────────────────────────────────────────────

  /// Wraps a single API call; returns null on any error instead of throwing.
  Future<dynamic> _safeGet(String path) async {
    try {
      return await api.get(path);
    } catch (e) {
      debugPrint('[CollabScreen] GET $path failed: $e');
      return null;
    }
  }

  List _asList(dynamic data, String key) {
    if (data == null) return [];
    if (data is Map) {
      final v = data[key];
      return v is List ? v : [];
    }
    return [];
  }

  Map _parseMine(dynamic data) {
    if (data == null || data is! Map) {
      return {'owned': [], 'joined': [], 'pending': []};
    }
    return {
      'owned':   data['owned']   is List ? data['owned']   as List : [],
      'joined':  data['joined']  is List ? data['joined']  as List : [],
      'pending': data['pending'] is List ? data['pending'] as List : [],
    };
  }

  // ── load ───────────────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });

    final results = await Future.wait([
      _safeGet('/collaborations/'),
      _safeGet('/collaborations/mine'),
    ]);

    if (!mounted) return;

    final discoverRaw = results[0];
    final mineRaw     = results[1];

    // If both calls returned null the device is likely offline
    if (discoverRaw == null && mineRaw == null) {
      setState(() {
        _loading = false;
        _error   = 'Could not connect to the server.\nCheck your internet and tap Retry.';
      });
      return;
    }

    setState(() {
      _discover = _asList(discoverRaw, 'collaborations');
      _mine     = _parseMine(mineRaw);
      _loading  = false;
    });
  }

  // ── actions ────────────────────────────────────────────────────────────────

  Future<void> _requestJoin(String collabId) async {
    HapticFeedback.mediumImpact();
    try {
      await api.post('/collaborations/$collabId/request', {});
      if (!mounted) return;
      _showSnack('✅ Join request sent! The owner will review it.', AppColors.success);
      _load();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().toLowerCase();
      if (msg.contains('already') || msg.contains('pending')) {
        _showSnack('⚠️ You already requested to join this.', AppColors.warning);
      } else if (msg.contains('member')) {
        _showSnack('✅ You are already a member.', AppColors.success);
      } else {
        _showSnack('Failed to send request. Please try again.', AppColors.error);
      }
    }
  }

  void _showSnack(String message, Color color) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ));
  }

  void _openDetail(Map collab) {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CollabDetailSheet(
        collab: collab,
        isDark: isDark,
        onJoin: () => _requestJoin(collab['id'].toString()),
      ),
    );
  }

  // ── create sheet ───────────────────────────────────────────────────────────

  void _showCreateSheet() {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bgCard  = isDark ? AppColors.bgCard    : Colors.white;
    final bgField = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final textClr = isDark ? Colors.white        : Colors.black87;
    final subClr  = isDark ? Colors.white54      : Colors.black45;

    final titleCtrl   = TextEditingController();
    final descCtrl    = TextEditingController();
    final revenueCtrl = TextEditingController();
    final roleCtrl    = TextEditingController();

    String         selectedType = 'youtube';
    List<String>   roles        = [];
    bool           submitting   = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          InputDecoration _field(String hint, {IconData? prefix}) => InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: subClr, fontSize: 13),
            filled: true,
            fillColor: bgField,
            prefixIcon: prefix != null ? Icon(prefix, color: subClr, size: 18) : null,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          );

          return Container(
            height: MediaQuery.of(context).size.height * 0.92,
            decoration: BoxDecoration(
              color: bgCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(children: [
              // ── handle ─────────────────────────────────────────────────────
              const SizedBox(height: 8),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // ── header ─────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 8, 0),
                child: Row(children: [
                  Text('Start a Collaboration',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: textClr)),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: subClr),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ]),
              ),
              // ── form ───────────────────────────────────────────────────────
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(
                    left: 20, right: 20,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 28,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SizedBox(height: 4),

                    // Income type chips
                    _SectionLabel('Income Type', subClr),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8, runSpacing: 8,
                      children: _types.map((t) {
                        final sel = selectedType == t['value'];
                        return GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setS(() => selectedType = t['value'] as String);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: sel ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: sel
                                    ? AppColors.primary
                                    : (isDark ? Colors.white24 : Colors.grey.shade300),
                              ),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Text(t['emoji'] as String, style: const TextStyle(fontSize: 14)),
                              const SizedBox(width: 6),
                              Text(
                                t['label'] as String,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: sel ? Colors.white : subClr,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ]),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 18),

                    // Title
                    _SectionLabel('Project Title *', subClr),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleCtrl,
                      style: TextStyle(fontSize: 14, color: textClr),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field('e.g. Build a personal finance YouTube channel'),
                    ),
                    const SizedBox(height: 14),

                    // Description
                    _SectionLabel('What you need help with', subClr),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descCtrl,
                      maxLines: 4,
                      style: TextStyle(fontSize: 14, color: textClr),
                      textCapitalization: TextCapitalization.sentences,
                      decoration: _field(
                          'Describe the goal, roles you need, and what each collaborator gets...'),
                    ),
                    const SizedBox(height: 14),

                    // Revenue potential
                    _SectionLabel('Revenue Potential (optional)', subClr),
                    const SizedBox(height: 8),
                    TextField(
                      controller: revenueCtrl,
                      style: TextStyle(fontSize: 14, color: textClr),
                      decoration: _field(
                        'e.g. ₦100K–500K/month or \$500–2,000/month',
                        prefix: Iconsax.dollar_circle,
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Roles needed
                    _SectionLabel('Roles Needed (optional)', subClr),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: roleCtrl,
                          style: TextStyle(fontSize: 14, color: textClr),
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (v) {
                            if (v.trim().isNotEmpty) {
                              setS(() { roles.add(v.trim()); roleCtrl.clear(); });
                            }
                          },
                          decoration: _field('e.g. Video Editor, Copywriter...'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          if (roleCtrl.text.trim().isNotEmpty) {
                            HapticFeedback.selectionClick();
                            setS(() { roles.add(roleCtrl.text.trim()); roleCtrl.clear(); });
                          }
                        },
                        child: Container(
                          width: 46, height: 46,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ]),
                    if (roles.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6, runSpacing: 6,
                        children: roles.map((r) => Chip(
                          label: Text(r),
                          labelStyle: const TextStyle(
                            fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w500,
                          ),
                          deleteIcon: const Icon(Icons.close_rounded, size: 14),
                          onDeleted: () => setS(() => roles.remove(r)),
                          backgroundColor: AppColors.primary.withOpacity(0.1),
                          deleteIconColor: AppColors.primary,
                          side: BorderSide(color: AppColors.primary.withOpacity(0.25)),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        )).toList(),
                      ),
                    ],
                    const SizedBox(height: 28),

                    // Submit button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        onPressed: submitting ? null : () async {
                          final title = titleCtrl.text.trim();
                          if (title.isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(
                              const SnackBar(
                                content: Text('Please enter a project title.'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          setS(() => submitting = true);

                          try {
                            await api.post('/collaborations/', {
                              'title':             title,
                              'description':       descCtrl.text.trim(),
                              'income_type':       selectedType,
                              'emoji':             _emojiFor(selectedType),
                              'tag':               _tagFor(selectedType),
                              'potential_revenue': revenueCtrl.text.trim(),
                              'roles':             roles,
                            });

                            if (ctx.mounted) Navigator.pop(ctx);

                            await _load();

                            if (mounted) {
                              _showSnack('✅ Collaboration posted!', AppColors.success);
                              // Interstitial for free users after posting
                              await adManager.forceInterstitial();
                            }
                          } catch (e) {
                            if (mounted) {
                              _showSnack(
                                'Failed: ${e.toString().replaceAll('Exception: ', '')}',
                                AppColors.error,
                              );
                            }
                          } finally {
                            if (ctx.mounted) setS(() => submitting = false);
                          }
                        },
                        child: submitting
                            ? const SizedBox(
                                height: 18, width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white,
                                ),
                              )
                            : const Text(
                                'Post Collaboration',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                ),
                              ),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? Colors.black    : Colors.white;
    final card   = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text   = isDark ? Colors.white    : Colors.black87;
    final sub    = isDark ? Colors.white54  : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      // Sticky banner ad for free users — premium users get null (no bar)
      bottomNavigationBar: adManager.getStickyBanner(context),
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Collaboration',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text),
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.add_circle, color: AppColors.primary),
            onPressed: _showCreateSheet,
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
              tabs: const [
                Tab(text: 'Discover'),
                Tab(text: 'My Collabs'),
                Tab(text: 'Requests'),
              ],
            ),
            Divider(height: 1, color: border),
          ]),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        color: AppColors.primary,
        child: _buildBody(isDark, bg, card, border, text, sub),
      ),
    );
  }

  Widget _buildBody(
      bool isDark, Color bg, Color card, Color border, Color text, Color sub) {
    // ── loading ──────────────────────────────────────────────────────────────
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
      );
    }

    // ── error state ──────────────────────────────────────────────────────────
    if (_error != null) {
      return LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: c.maxHeight,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('😕', style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 16),
                  Text(
                    'Something went wrong',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(fontSize: 13, color: sub, height: 1.5),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Retry'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    // ── tabs ─────────────────────────────────────────────────────────────────
    return TabBarView(
      controller: _tabs,
      children: [
        _DiscoverTab(
          collabs: _discover,
          isDark: isDark, card: card, border: border, text: text, sub: sub,
          onJoin: _requestJoin,
          onTap:  _openDetail,
        ),
        _MyCollabsTab(
          mine: _mine,
          isDark: isDark, card: card, border: border, text: text, sub: sub,
          onTap: _openDetail,
        ),
        _RequestsTab(
          pending: (_mine['pending'] as List?) ?? [],
          isDark: isDark, card: card, border: border, text: text, sub: sub,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Small shared helper
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel(this.label, this.color);

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
  );
}

Widget _emptyPage({
  required double height,
  required String emoji,
  required String title,
  required String subtitle,
}) {
  return LayoutBuilder(
    builder: (_, c) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: SizedBox(
        height: height > 0 ? height : c.maxHeight,
        child: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(subtitle,
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500, height: 1.5),
                  textAlign: TextAlign.center),
            ),
          ]),
        ),
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
//  Discover Tab
// ─────────────────────────────────────────────────────────────────────────────

class _DiscoverTab extends StatelessWidget {
  final List           collabs;
  final bool           isDark;
  final Color          card, border, text, sub;
  final Function(String) onJoin;
  final Function(Map)    onTap;

  const _DiscoverTab({
    required this.collabs,
    required this.isDark,
    required this.card,
    required this.border,
    required this.text,
    required this.sub,
    required this.onJoin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (collabs.isEmpty) {
      return _emptyPage(
        height: 0,
        emoji: '🤝',
        title: 'No open collaborations yet',
        subtitle: 'Be the first to post one! Tap the + button above.',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: collabs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final c          = collabs[i] as Map;
        final profile    = (c['profiles'] as Map?) ?? {};
        final userStatus = c['user_status']?.toString();
        final revenue    = c['potential_revenue']?.toString() ?? '';
        final emoji      = c['emoji']?.toString().isNotEmpty == true
            ? c['emoji'].toString()
            : '🤝';
        final tag        = c['tag']?.toString() ?? '';

        return GestureDetector(
          onTap: () => onTap(c),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? AppColors.bgSurface : Colors.grey.shade200,
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── header ────────────────────────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 46, height: 46,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    c['title']?.toString() ?? 'Untitled Collaboration',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'by ${profile['full_name'] ?? 'Anonymous'}',
                    style: TextStyle(fontSize: 11, color: sub),
                  ),
                ])),
                if (tag.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(tag,
                        style: const TextStyle(
                          fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w700,
                        )),
                  ),
                ],
              ]),

              // ── description ───────────────────────────────────────────────
              if ((c['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  c['description'].toString(),
                  style: TextStyle(fontSize: 13, color: sub, height: 1.45),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 12),

              // ── footer ────────────────────────────────────────────────────
              Row(children: [
                if (revenue.isNotEmpty) ...[
                  const Icon(Icons.attach_money_rounded, color: AppColors.success, size: 14),
                  Expanded(
                    child: Text(
                      revenue,
                      style: const TextStyle(
                        color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ] else
                  const Spacer(),

                const SizedBox(width: 8),

                // Status / join button
                _JoinButton(
                  status: userStatus,
                  sub: sub,
                  onTap: () => onJoin(c['id'].toString()),
                ),
              ]),
            ]),
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 45)).slideY(begin: 0.06, end: 0);
      },
    );
  }
}

// Separate widget so it can rebuild independently
class _JoinButton extends StatelessWidget {
  final String? status;
  final Color   sub;
  final VoidCallback onTap;
  const _JoinButton({required this.status, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final joined  = status == 'accepted';
    final pending = status == 'pending';
    final label   = pending ? '⏳ Requested' : joined ? '✓ Joined' : 'Request to Join';
    final clr     = status != null ? Colors.transparent : AppColors.primary;

    return GestureDetector(
      onTap: status == null ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: clr,
          borderRadius: BorderRadius.circular(20),
          border: status != null
              ? Border.all(color: Colors.grey.withOpacity(0.4))
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: status != null ? sub : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  My Collabs Tab
// ─────────────────────────────────────────────────────────────────────────────

class _MyCollabsTab extends StatelessWidget {
  final Map         mine;
  final bool        isDark;
  final Color       card, border, text, sub;
  final Function(Map) onTap;

  const _MyCollabsTab({
    required this.mine,
    required this.isDark,
    required this.card, required this.border, required this.text, required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final owned  = (mine['owned']  as List?) ?? [];
    final joined = (mine['joined'] as List?) ?? [];
    final all    = [...owned, ...joined];

    if (all.isEmpty) {
      return _emptyPage(
        height: 0,
        emoji: '🤝',
        title: 'No active collaborations',
        subtitle: 'Start or join a collaboration to build bigger income goals with others.',
      );
    }

    // Build item list with a section header between owned and joined
    final items = <dynamic>[];
    if (owned.isNotEmpty) {
      items.add(_SectionHeader('My Collaborations (${owned.length})'));
      items.addAll(owned);
    }
    if (joined.isNotEmpty) {
      items.add(_SectionHeader('Joined Collaborations (${joined.length})'));
      items.addAll(joined);
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, i) =>
          items[i] is _SectionHeader ? const SizedBox.shrink() : const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final item = items[i];
        if (item is _SectionHeader) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(item.title,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: sub)),
          );
        }

        final c       = item as Map;
        final isOwned = owned.contains(c);
        final emoji   = c['emoji']?.toString().isNotEmpty == true
            ? c['emoji'].toString()
            : '🤝';

        return GestureDetector(
          onTap: () => onTap(c),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isOwned
                    ? AppColors.primary.withOpacity(0.3)
                    : (isDark ? AppColors.bgSurface : Colors.grey.shade200),
              ),
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  c['title']?.toString() ?? 'Untitled',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(children: [
                  if (isOwned) ...[
                    const Icon(Icons.star_rounded, color: AppColors.primary, size: 12),
                    const SizedBox(width: 3),
                    Text('Owner',
                        style: const TextStyle(
                          fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(width: 8),
                    const Text('·', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (c['status'] == 'open'
                          ? AppColors.success
                          : Colors.grey).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      c['status']?.toString() ?? 'open',
                      style: TextStyle(
                        fontSize: 10,
                        color: c['status'] == 'open' ? AppColors.success : Colors.grey,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ]),
              ])),
              const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey),
            ]),
          ),
        );
      },
    );
  }
}

class _SectionHeader {
  final String title;
  const _SectionHeader(this.title);
}

// ─────────────────────────────────────────────────────────────────────────────
//  Requests Tab
// ─────────────────────────────────────────────────────────────────────────────

class _RequestsTab extends StatelessWidget {
  final List  pending;
  final bool  isDark;
  final Color card, border, text, sub;

  const _RequestsTab({
    required this.pending,
    required this.isDark,
    required this.card, required this.border, required this.text, required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) {
      return _emptyPage(
        height: 0,
        emoji: '📬',
        title: 'No pending requests',
        subtitle: 'Your collaboration join requests will appear here.',
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: pending.length,
      itemBuilder: (_, i) {
        final p     = pending[i] as Map;
        final emoji = p['emoji']?.toString().isNotEmpty == true
            ? p['emoji'].toString()
            : '🤝';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.warning.withOpacity(0.3),
            ),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                p['title']?.toString() ?? 'Untitled',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.schedule_rounded, size: 11, color: AppColors.warning),
                const SizedBox(width: 3),
                Text(
                  'Pending approval',
                  style: const TextStyle(
                    fontSize: 11, color: AppColors.warning, fontWeight: FontWeight.w500,
                  ),
                ),
              ]),
            ])),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Collab Detail Bottom Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _CollabDetailSheet extends StatelessWidget {
  final Map         collab;
  final bool        isDark;
  final VoidCallback? onJoin;

  const _CollabDetailSheet({
    required this.collab,
    required this.isDark,
    this.onJoin,
  });

  @override
  Widget build(BuildContext context) {
    final c       = collab;
    final bg      = isDark ? AppColors.bgCard    : Colors.white;
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final text    = isDark ? Colors.white        : Colors.black87;
    final sub     = isDark ? Colors.white54      : Colors.black45;

    final profile    = (c['profiles'] as Map?) ?? {};
    final roles      = (c['roles']   as List?) ?? [];
    final userStatus = c['user_status']?.toString();
    final isOwner    = c['is_owner'] == true;
    final emoji      = c['emoji']?.toString().isNotEmpty == true
        ? c['emoji'].toString()
        : '🤝';
    final revenue    = c['potential_revenue']?.toString() ?? '';

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(children: [
        // handle
        const SizedBox(height: 8),
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: Colors.grey.shade400,
            borderRadius: BorderRadius.circular(2),
          ),
        ),

        // scrollable content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ── title block ────────────────────────────────────────────────
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(child: Text(emoji, style: const TextStyle(fontSize: 28))),
                ),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if ((c['tag'] ?? '').toString().isNotEmpty)
                    Text(c['tag'].toString(),
                        style: const TextStyle(
                          fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700,
                        )),
                  const SizedBox(height: 2),
                  Text(
                    c['title']?.toString() ?? 'Untitled',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: Text(
                        (profile['full_name']?.toString() ?? 'U').isNotEmpty
                            ? (profile['full_name'] as String).characters.first.toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(profile['full_name']?.toString() ?? 'Anonymous',
                        style: TextStyle(fontSize: 12, color: sub)),
                    if (profile['is_verified'] == true) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.verified_rounded, color: AppColors.primary, size: 13),
                    ],
                  ]),
                ])),
              ]),
              const SizedBox(height: 16),

              // ── revenue ────────────────────────────────────────────────────
              if (revenue.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.success.withOpacity(0.25)),
                  ),
                  child: Row(children: [
                    const Text('💰', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Revenue Potential',
                          style: TextStyle(fontSize: 11, color: AppColors.success.withOpacity(0.8))),
                      Text(revenue,
                          style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.success,
                          )),
                    ]),
                  ]),
                ),

              // ── description ────────────────────────────────────────────────
              if ((c['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('About',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                const SizedBox(height: 6),
                Text(c['description'].toString(),
                    style: TextStyle(fontSize: 13.5, color: sub, height: 1.6)),
              ],

              // ── roles ──────────────────────────────────────────────────────
              if (roles.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Roles Open',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                const SizedBox(height: 10),
                ...roles.map((r) {
                  final name     = r is Map
                      ? (r['role_name'] ?? r['name'] ?? r.toString())
                      : r.toString();
                  final filled   = r is Map ? r['is_filled'] == true : false;
                  final roleClr  = filled ? AppColors.success : AppColors.primary;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(children: [
                      Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: roleClr.withOpacity(0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Icon(
                          filled ? Iconsax.user_tick : Iconsax.user_add,
                          size: 15, color: roleClr,
                        )),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name.toString(),
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600, color: text)),
                        Text(filled ? 'Position filled' : 'Open — apply to fill this role',
                            style: TextStyle(fontSize: 11, color: sub)),
                      ])),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: roleClr.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          filled ? 'Filled' : 'Open',
                          style: TextStyle(
                            fontSize: 10, color: roleClr, fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ]),
                  );
                }),
              ],

              const SizedBox(height: 20),
            ]),
          ),
        ),

        // ── CTA ─────────────────────────────────────────────────────────────
        if (!isOwner)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: userStatus != null
                      ? null
                      : () {
                          Navigator.pop(context);
                          onJoin?.call();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: userStatus != null
                        ? Colors.grey.withOpacity(0.4)
                        : AppColors.primary,
                    disabledBackgroundColor: Colors.grey.withOpacity(0.35),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Text(
                    userStatus == 'pending'
                        ? '⏳ Request Pending'
                        : userStatus == 'accepted'
                            ? '✓ You are a Member'
                            : 'Request to Join',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
