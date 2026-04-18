// frontend/lib/screens/groups/groups_screen.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_manager.dart';
import '../../widgets/ad_widgets.dart';

// ── Topic list ────────────────────────────────────────────────────────────────
const _kAllTopics = <String>[
  '💰 Wealth',          '📈 Investing',        '💼 Business',
  '🧠 Mindset',         '⚡ Hustle',            '🎯 Skills',
  '🏠 Real Estate',     '💻 Tech',              '📊 Budgeting',
  '🌱 Personal Growth', '💪 Finance',           '🚀 Startups',
  '🛒 Selling',         '🛍️ Buying',            '🔧 Services Offered',
  '🙋 Services Wanted', '🎓 Mentoring',         '🤝 Networking',
  '📚 Learning',        '💡 Ideas',             '🎨 Creativity',
  '🏛️ Education',       '📖 Reading',           '🧪 Research',
  '🏋️ Health & Fitness','🌍 Travel',            '🍕 Food & Lifestyle',
  '🎮 Gaming',          '🎵 Music',             '📱 Social Media',
  '📸 Photography',     '🎭 Entertainment',     '⚽ Sports',
  '💄 Beauty & Fashion','❤️ Relationships',     '👨‍👩‍👧 Family',
  '🤖 AI & Tech',       '🌐 Crypto & Web3',     '🖥️ Coding',
  '🔬 Science',         '🌿 Sustainability',    '🏦 Banking',
  '⚖️ Legal',           '🏥 Healthcare',        '🚗 Automotive',
  '🍳 Food Business',   '🏗️ Construction',      '🎪 Events & Marketing',
];

(String emoji, String label) _splitTopic(String topic) {
  final parts = topic.split(' ');
  if (parts.length < 2) return ('💬', topic);
  return (parts.first, parts.sublist(1).join(' '));
}

// ── GroupsScreen ──────────────────────────────────────────────────────────────
class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {

  static const _kGroupsCache = 'riseup_groups_v1';

  late TabController _tabCtrl;

  List   _groups   = [];
  bool   _loading  = true;
  bool   _hasError = false;

  final _searchCtrl  = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _restoreCache();
    WidgetsBinding.instance.addPostFrameCallback((_) => _silentRefresh());
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<void> _restoreCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_kGroupsCache);
      if (raw != null && mounted) {
        final list = (jsonDecode(raw) as List).cast<Map>();
        setState(() { _groups = list; _loading = false; });
      }
    } catch (_) {}
  }

  Future<void> _silentRefresh() async {
    if (!mounted) return;
    try {
      final data   = await api.getGroups();
      final groups = (data['groups'] as List? ?? []);
      if (mounted) setState(() { _groups = groups; _loading = false; _hasError = false; });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGroupsCache, jsonEncode(groups));
    } catch (_) {
      if (mounted && _groups.isEmpty) setState(() { _loading = false; _hasError = true; });
    }
  }

  Future<void> _load() => _silentRefresh();

  // ── Derived ───────────────────────────────────────────────────────────────

  List get _myGroups =>
      _groups.where((g) => g['is_joined'] == true).toList();

  List get _filteredGroups {
    if (_searchQuery.trim().isEmpty) return _groups;
    final q = _searchQuery.toLowerCase();
    return _groups.where((g) =>
        (g['name']?.toString().toLowerCase().contains(q) ?? false) ||
        (g['description']?.toString().toLowerCase().contains(q) ?? false) ||
        (g['category']?.toString().toLowerCase().contains(q) ?? false) ||
        (g['topic']?.toString().toLowerCase().contains(q) ?? false)).toList();
  }

  List _withAdSlots(List real) {
    if (adManager.isPremium) return real;
    final out = <dynamic>[];
    for (int i = 0; i < real.length; i++) {
      out.add(real[i]);
      if ((i + 1) % 5 == 0 && i + 1 < real.length) out.add({'_isAd': true});
    }
    return out;
  }

  // ── Mutations ─────────────────────────────────────────────────────────────

  Future<void> _toggleJoin(Map group) async {
    final wasJoined = group['is_joined'] == true;
    HapticFeedback.lightImpact();
    setState(() => group['is_joined'] = !wasJoined);
    try {
      final res = await api.toggleGroup(group['id'].toString());
      if (mounted) setState(() => group['is_joined'] = res['joined'] == true);
      // Persist updated list
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kGroupsCache, jsonEncode(_groups));
    } catch (_) {
      if (mounted) {
        setState(() => group['is_joined'] = wasJoined);
        _showErrorSnack('Could not update membership. Please try again.');
      }
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showErrorSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showSuccessSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── Navigation — context.push so detail screen can pop back ──────────────
  void _openGroup(Map group) {
    context.push(
      '/group/${group['id']}?name=${Uri.encodeComponent(group['name']?.toString() ?? '')}',
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark       = Theme.of(context).brightness == Brightness.dark;
    final bgColor      = isDark ? Colors.black          : Colors.white;
    final cardColor    = isDark ? AppColors.bgCard      : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface   : Colors.grey.shade100;
    final borderColor  = isDark ? AppColors.bgSurface   : Colors.grey.shade200;
    final textColor    = isDark ? Colors.white          : Colors.black87;
    final subColor     = isDark ? Colors.white54        : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Groups',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.add_square, color: textColor, size: 22),
            onPressed: () => _showCreateGroupSheet(
                context, isDark, surfaceColor, borderColor, textColor, subColor),
            tooltip: 'Create group',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: subColor,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'My Groups (${_myGroups.length})'),
                const Tab(text: 'Discover'),
              ],
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: _loading && _groups.isEmpty
              ? _buildSkeleton(isDark, cardColor, borderColor)
              : _hasError
                  ? _buildErrorState(textColor, subColor)
                  : TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildMyGroupsTab(isDark, textColor, subColor,
                            cardColor, borderColor, surfaceColor),
                        _buildDiscoverTab(isDark, textColor, subColor,
                            cardColor, borderColor, surfaceColor),
                      ],
                    ),
        ),
        if (!adManager.isPremium) ScreenBannerAd(isDark: isDark),
      ]),
    );
  }

  // ── My Groups tab ─────────────────────────────────────────────────────────

  Widget _buildMyGroupsTab(bool isDark, Color textColor, Color subColor,
      Color cardColor, Color borderColor, Color surfaceColor) {
    if (_myGroups.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child:
              Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('👥', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 14),
            Text("You haven't joined any groups yet",
                style: TextStyle(color: subColor, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => _tabCtrl.animateTo(1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(22)),
                child: const Text('Discover Groups',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _myGroups.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _GroupCard(
          group: _myGroups[i],
          isDark: isDark,
          textColor: textColor,
          subColor: subColor,
          cardColor: cardColor,
          borderColor: borderColor,
          surfaceColor: surfaceColor,
          onJoin: () => _toggleJoin(_myGroups[i]),
          onTap: () => _openGroup(_myGroups[i]),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 50)),
      ),
    );
  }

  // ── Discover tab ──────────────────────────────────────────────────────────

  Widget _buildDiscoverTab(bool isDark, Color textColor, Color subColor,
      Color cardColor, Color borderColor, Color surfaceColor) {
    final items = _withAdSlots(_filteredGroups);

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                style: TextStyle(fontSize: 14, color: textColor),
                decoration: InputDecoration(
                  hintText: 'Search groups, topics...',
                  hintStyle: TextStyle(color: subColor, fontSize: 13),
                  prefixIcon: Icon(Iconsax.search_normal_1,
                      size: 18, color: subColor),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: subColor),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          })
                      : null,
                  filled: true,
                  fillColor: isDark
                      ? AppColors.bgSurface
                      : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          if (items.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Text('🔍',
                      style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isNotEmpty
                        ? 'No groups match "$_searchQuery"'
                        : 'No groups available yet',
                    style: TextStyle(color: subColor, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  if (_searchQuery.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: () => _showCreateGroupSheet(
                          context,
                          isDark,
                          isDark
                              ? AppColors.bgSurface
                              : Colors.grey.shade100,
                          isDark
                              ? AppColors.bgSurface
                              : Colors.grey.shade200,
                          textColor,
                          subColor),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20)),
                        child: const Text('Create this group',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ]),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final item = items[i];
                    if (item is Map && item['_isAd'] == true) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: FeedAdCard(
                          isDark: isDark,
                          cardColor: cardColor,
                          borderColor: borderColor,
                          textColor: textColor,
                          subColor: subColor,
                        ),
                      );
                    }
                    final group = item as Map;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _GroupCard(
                        group: group,
                        isDark: isDark,
                        textColor: textColor,
                        subColor: subColor,
                        cardColor: cardColor,
                        borderColor: borderColor,
                        surfaceColor: surfaceColor,
                        onJoin: () => _toggleJoin(group),
                        onTap: () => _openGroup(group),
                      ).animate().fadeIn(
                            delay:
                                Duration(milliseconds: i * 40)),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Skeleton ──────────────────────────────────────────────────────────────

  Widget _buildSkeleton(bool isDark, Color cardColor, Color borderColor) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, __) => Container(
        height: 94,
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
      )
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(
              duration: 1200.ms,
              color: isDark ? Colors.white10 : Colors.grey.shade100),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildErrorState(Color textColor, Color subColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('😕', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Couldn\'t load groups',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textColor)),
          const SizedBox(height: 8),
          Text('Check your connection and try again.',
              style: TextStyle(color: subColor, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 22),
          GestureDetector(
            onTap: _load,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 13),
              decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(22)),
              child: const Text('Retry',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Create Group sheet ────────────────────────────────────────────────────

  void _showCreateGroupSheet(BuildContext ctx, bool isDark, Color surfaceColor,
      Color borderColor, Color textColor, Color subColor) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String selectedTopic = _kAllTopics.first;
    bool   creating      = false;

    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(builder: (sheetCtx, setSt) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.92,
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
              24, 16, 24, MediaQuery.of(ctx).padding.bottom + 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: subColor.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text('Create a Group',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: textColor)),
              const SizedBox(height: 4),
              Text('Build a community around your wealth niche',
                  style: TextStyle(fontSize: 13, color: subColor)),
              const SizedBox(height: 24),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SheetLabel(label: 'Group name *', subColor: subColor),
                      const SizedBox(height: 8),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(fontSize: 14, color: textColor),
                        textCapitalization: TextCapitalization.words,
                        maxLength: 60,
                        decoration: InputDecoration(
                          hintText: 'e.g. Crypto Investors Club',
                          hintStyle:
                              TextStyle(color: subColor, fontSize: 13),
                          filled: true,
                          fillColor: surfaceColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 14),
                          counterStyle:
                              TextStyle(color: subColor, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SheetLabel(label: 'Description', subColor: subColor),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descCtrl,
                        maxLines: 3,
                        maxLength: 200,
                        style: TextStyle(fontSize: 14, color: textColor),
                        decoration: InputDecoration(
                          hintText:
                              'What is this group about? Who should join?',
                          hintStyle:
                              TextStyle(color: subColor, fontSize: 13),
                          filled: true,
                          fillColor: surfaceColor,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.all(14),
                          counterStyle:
                              TextStyle(color: subColor, fontSize: 11),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _SheetLabel(
                          label: 'Topic / Category *', subColor: subColor),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _kAllTopics.map((topic) {
                          final sel = topic == selectedTopic;
                          return GestureDetector(
                            onTap: () =>
                                setSt(() => selectedTopic = topic),
                            child: AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: sel
                                    ? AppColors.primary
                                    : surfaceColor,
                                borderRadius:
                                    BorderRadius.circular(20),
                                border: Border.all(
                                    color: sel
                                        ? AppColors.primary
                                        : borderColor),
                              ),
                              child: Text(
                                topic,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: sel
                                      ? Colors.white
                                      : subColor,
                                  fontWeight: sel
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: creating
                    ? null
                    : () async {
                        final name = nameCtrl.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(ctx)
                              .showSnackBar(const SnackBar(
                            content:
                                Text('Please enter a group name'),
                            backgroundColor: AppColors.error,
                            behavior: SnackBarBehavior.floating,
                          ));
                          return;
                        }
                        setSt(() => creating = true);
                        try {
                          final (emoji, label) =
                              _splitTopic(selectedTopic);
                          await api.post('/groups', {
                            'name': name,
                            'description': descCtrl.text.trim(),
                            'category': label,
                            'topic': selectedTopic,
                            'emoji': emoji,
                          });
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            _silentRefresh();
                            _showSuccessSnack(
                                '$emoji Group "$name" created!');
                          }
                        } catch (_) {
                          setSt(() => creating = false);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx)
                                .showSnackBar(const SnackBar(
                              content: Text(
                                  'Failed to create group. Please try again.'),
                              backgroundColor: AppColors.error,
                              behavior: SnackBarBehavior.floating,
                            ));
                          }
                        }
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: creating
                        ? null
                        : const LinearGradient(
                            colors: [
                                AppColors.primary,
                                AppColors.accent
                              ]),
                    color: creating
                        ? AppColors.primary.withOpacity(0.45)
                        : null,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: creating
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Text('Create Group',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ── Sheet label ───────────────────────────────────────────────────────────────
class _SheetLabel extends StatelessWidget {
  final String label;
  final Color  subColor;
  const _SheetLabel({required this.label, required this.subColor});

  @override
  Widget build(BuildContext context) => Text(label,
      style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w500, color: subColor));
}

// ── Group card ────────────────────────────────────────────────────────────────
class _GroupCard extends StatelessWidget {
  final Map      group;
  final bool     isDark;
  final Color    textColor, subColor, cardColor, borderColor, surfaceColor;
  final VoidCallback onJoin, onTap;

  const _GroupCard({
    required this.group,
    required this.isDark,
    required this.textColor,
    required this.subColor,
    required this.cardColor,
    required this.borderColor,
    required this.surfaceColor,
    required this.onJoin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final joined     = group['is_joined'] == true;
    final members    = group['members_count'] as int? ?? group['member_count'] as int? ?? 0;
    final membersStr = members >= 1000
        ? '${(members / 1000).toStringAsFixed(1)}K'
        : '$members';
    final emoji     = group['emoji']?.toString() ?? '💬';
    final name      = group['name']?.toString() ?? '';
    final desc      = group['description']?.toString() ?? '';
    final category  = group['category']?.toString() ?? group['topic']?.toString() ?? '';
    final isPremium = group['is_premium'] == true;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Row(children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child:
                Center(child: Text(emoji, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(name,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                if (isPremium)
                  const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Text('⭐', style: TextStyle(fontSize: 12)),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(desc,
                  style: TextStyle(
                      fontSize: 12, color: subColor, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Row(children: [
                Icon(Iconsax.people, size: 12, color: subColor),
                const SizedBox(width: 4),
                Text('$membersStr members',
                    style: TextStyle(fontSize: 11, color: subColor)),
                if (category.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(category,
                          style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onJoin,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: joined ? surfaceColor : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: joined ? borderColor : AppColors.primary),
              ),
              child: Text(
                joined ? 'Joined' : 'Join',
                style: TextStyle(
                    color: joined ? subColor : Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
