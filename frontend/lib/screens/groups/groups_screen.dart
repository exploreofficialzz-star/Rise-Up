import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List _groups = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getGroups();
      if (mounted) setState(() { _groups = data['groups'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List get _myGroups => _groups.where((g) => g['is_joined'] == true).toList();

  Future<void> _toggleJoin(Map group) async {
    try {
      final res = await api.toggleGroup(group['id'].toString());
      setState(() => group['is_joined'] = res['joined'] == true);
    } catch (_) {}
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Groups', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.add_square, color: textColor, size: 22),
            onPressed: () => _showCreateGroup(context, isDark, surfaceColor, borderColor, textColor, subColor),
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
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [Tab(text: 'My Groups (${_myGroups.length})'), const Tab(text: 'Discover')],
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                // My Groups
                _myGroups.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Text('👥', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 12),
                        Text('You haven\'t joined any groups yet', style: TextStyle(color: subColor, fontSize: 14)),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => _tabCtrl.animateTo(1),
                          child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)), child: const Text('Discover Groups', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                        ),
                      ]))
                    : RefreshIndicator(
                        onRefresh: _load,
                        color: AppColors.primary,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _myGroups.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, i) => _GroupCard(group: _myGroups[i], isDark: isDark, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, surfaceColor: surfaceColor, onJoin: () => _toggleJoin(_myGroups[i]), onTap: () => context.go('/group/${_myGroups[i]['id']}?name=${Uri.encodeComponent(_myGroups[i]['name'] ?? '')}')).animate().fadeIn(delay: Duration(milliseconds: i * 50)),
                        ),
                      ),

                // Discover
                RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _groups.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _GroupCard(group: _groups[i], isDark: isDark, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, surfaceColor: surfaceColor, onJoin: () => _toggleJoin(_groups[i]), onTap: () => context.go('/group/${_groups[i]['id']}?name=${Uri.encodeComponent(_groups[i]['name'] ?? '')}')).animate().fadeIn(delay: Duration(milliseconds: i * 40)),
                  ),
                ),
              ],
            ),
    );
  }

  void _showCreateGroup(BuildContext context, bool isDark, Color surfaceColor, Color borderColor, Color textColor, Color subColor) {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    String category = 'Wealth';
    bool isPremium = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (_, setSt) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(color: isDark ? AppColors.bgCard : Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
          padding: EdgeInsets.fromLTRB(24, 16, 24, MediaQuery.of(context).padding.bottom + 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: subColor.withOpacity(0.3), borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 20),
            Text('Create Group', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
            const SizedBox(height: 4),
            Text('Build a community around your wealth niche', style: TextStyle(fontSize: 13, color: subColor)),
            const SizedBox(height: 24),
            Expanded(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Group name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
              const SizedBox(height: 8),
              TextField(controller: nameCtrl, style: TextStyle(fontSize: 14, color: textColor), decoration: InputDecoration(hintText: 'e.g. Crypto Investors', hintStyle: TextStyle(color: subColor, fontSize: 13), filled: true, fillColor: surfaceColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14))),
              const SizedBox(height: 16),
              Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
              const SizedBox(height: 8),
              TextField(controller: descCtrl, maxLines: 3, style: TextStyle(fontSize: 14, color: textColor), decoration: InputDecoration(hintText: 'What is this group about?', hintStyle: TextStyle(color: subColor, fontSize: 13), filled: true, fillColor: surfaceColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(14))),
              const SizedBox(height: 16),
              Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: ['Wealth', 'Investing', 'Business', 'Mindset', 'Hustle', 'Skills', 'Budgeting', 'Personal Growth'].map((c) {
                final sel = c == category;
                return GestureDetector(onTap: () => setSt(() => category = c), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: sel ? AppColors.primary : surfaceColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppColors.primary : borderColor)), child: Text(c, style: TextStyle(fontSize: 12, color: sel ? Colors.white : subColor, fontWeight: sel ? FontWeight.w600 : FontWeight.w400))));
              }).toList()),
            ]))),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(width: double.infinity, height: 52, decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(14)), child: const Center(child: Text('Create Group', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)))),
            ),
          ]),
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final Map group;
  final bool isDark;
  final Color textColor, subColor, cardColor, borderColor, surfaceColor;
  final VoidCallback onJoin, onTap;
  const _GroupCard({required this.group, required this.isDark, required this.textColor, required this.subColor, required this.cardColor, required this.borderColor, required this.surfaceColor, required this.onJoin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final joined = group['is_joined'] == true;
    final members = group['members_count'] as int? ?? 0;
    final membersStr = members >= 1000 ? '${(members / 1000).toStringAsFixed(1)}K' : '$members';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: borderColor)),
        child: Row(children: [
          Container(
            width: 54, height: 54,
            decoration: BoxDecoration(color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08), borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text(group['emoji']?.toString() ?? '💰', style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(group['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (group['is_premium'] == true) const Padding(padding: EdgeInsets.only(left: 4), child: Text('⭐', style: TextStyle(fontSize: 12))),
            ]),
            const SizedBox(height: 3),
            Text(group['description']?.toString() ?? '', style: TextStyle(fontSize: 12, color: subColor, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Row(children: [
              Icon(Iconsax.people, size: 12, color: subColor),
              const SizedBox(width: 4),
              Text('$membersStr members', style: TextStyle(fontSize: 11, color: subColor)),
              const SizedBox(width: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)), child: Text(group['category']?.toString() ?? '', style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600))),
            ]),
          ])),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onJoin,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(color: joined ? surfaceColor : AppColors.primary, borderRadius: BorderRadius.circular(20), border: Border.all(color: joined ? borderColor : AppColors.primary)),
              child: Text(joined ? 'Joined' : 'Join', style: TextStyle(color: joined ? subColor : Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}
