import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _Group {
  final String id, emoji, name, description, members, category;
  final bool isJoined, isPremium;
  bool joined;
  _Group({required this.id, required this.emoji, required this.name, required this.description, required this.members, required this.category, this.isJoined = false, this.isPremium = false}) : joined = isJoined;
}

class _GroupsScreenState extends State<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  final _groups = [
    _Group(id: '1', emoji: '💰', name: 'Wealth Builders Global', description: 'The #1 community for building generational wealth worldwide', members: '24.5K', category: 'Wealth', isJoined: true),
    _Group(id: '2', emoji: '📈', name: 'Stock Market Mastery', description: 'Learn investing, stocks, ETFs and portfolio building', members: '18.2K', category: 'Investing'),
    _Group(id: '3', emoji: '💼', name: 'Freelancers Hub', description: 'Connect with freelancers, share clients and opportunities', members: '31.7K', category: 'Business', isJoined: true),
    _Group(id: '4', emoji: '🧠', name: 'Millionaire Mindset', description: 'Daily mindset shifts for financial freedom', members: '15.9K', category: 'Mindset'),
    _Group(id: '5', emoji: '🏠', name: 'Real Estate Circle', description: 'Property investment strategies for all budgets', members: '9.3K', category: 'Real Estate', isPremium: true),
    _Group(id: '6', emoji: '💻', name: 'Tech & Income', description: 'Turn your tech skills into income streams', members: '22.1K', category: 'Tech'),
    _Group(id: '7', emoji: '📊', name: 'Budget Masters', description: 'Master budgeting, saving and debt elimination', members: '28.4K', category: 'Budgeting', isJoined: true),
    _Group(id: '8', emoji: '🎯', name: 'Goal Getters', description: 'Set, track and crush your personal & financial goals', members: '19.6K', category: 'Personal Growth'),
    _Group(id: '9', emoji: '⚡', name: 'Side Hustle Academy', description: 'From idea to income — build your side hustle', members: '35.8K', category: 'Hustle'),
    _Group(id: '10', emoji: '🌍', name: 'Global Entrepreneurs', description: 'Entrepreneurs from every corner of the world', members: '41.2K', category: 'Business', isPremium: true),
    _Group(id: '11', emoji: '💪', name: 'Financial Fitness', description: 'Your financial health matters. Fix it here.', members: '12.4K', category: 'Finance'),
    _Group(id: '12', emoji: '🚀', name: 'Startup Founders', description: 'Build, launch and scale your startup', members: '8.7K', category: 'Business'),
    _Group(id: '13', emoji: '🎨', name: 'Creative Monetizers', description: 'Turn your creativity into cash', members: '14.3K', category: 'Skills'),
    _Group(id: '14', emoji: '📚', name: 'Self Development Hub', description: 'Books, habits, routines for success', members: '26.9K', category: 'Personal Growth'),
    _Group(id: '15', emoji: '🏋️', name: 'Productive Warriors', description: 'Productivity systems for high performers', members: '17.2K', category: 'Personal Growth'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    final myGroups = _groups.where((g) => g.joined).toList();
    final allGroups = _groups;

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
            onPressed: () => _showCreateGroup(context, isDark),
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
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: [
                Tab(text: 'My Groups (${myGroups.length})'),
                const Tab(text: 'Discover'),
              ],
            ),
            Divider(height: 1, color: borderColor),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // My Groups
          myGroups.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('👥', style: TextStyle(fontSize: 56)),
                  const SizedBox(height: 12),
                  Text('You haven\'t joined any groups yet', style: TextStyle(color: subColor, fontSize: 14)),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _tabCtrl.animateTo(1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(20)),
                      child: const Text('Discover Groups', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: myGroups.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _GroupCard(group: myGroups[i], isDark: isDark, textColor: textColor, subColor: subColor, cardColor: cardColor, borderColor: borderColor, surfaceColor: surfaceColor, onJoinTap: () => setState(() => myGroups[i].joined = !myGroups[i].joined), onTap: () => context.go('/group/${myGroups[i].id}?name=${Uri.encodeComponent(myGroups[i].name)}')).animate().fadeIn(delay: Duration(milliseconds: i * 50)),

                ),

          // Discover
          ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: allGroups.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _GroupCard(
              group: allGroups[i], isDark: isDark, textColor: textColor,
              subColor: subColor, cardColor: cardColor, borderColor: borderColor, surfaceColor: surfaceColor,
              onJoinTap: () => setState(() => allGroups[i].joined = !allGroups[i].joined),
              onTap: () => context.go('/group/${allGroups[i].id}?name=${Uri.encodeComponent(allGroups[i].name)}'),
            ).animate().fadeIn(delay: Duration(milliseconds: i * 40)),
          ),
        ],
      ),
    );
  }

  void _showCreateGroup(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateGroupSheet(isDark: isDark),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final _Group group;
  final bool isDark;
  final Color textColor, subColor, cardColor, borderColor, surfaceColor;
  final VoidCallback onJoinTap, onTap;
  const _GroupCard({required this.group, required this.isDark, required this.textColor, required this.subColor, required this.cardColor, required this.borderColor, required this.surfaceColor, required this.onJoinTap, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
            child: Center(child: Text(group.emoji, style: const TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(group.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor), maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (group.isPremium) const Padding(padding: EdgeInsets.only(left: 4), child: Text('⭐', style: TextStyle(fontSize: 12))),
            ]),
            const SizedBox(height: 3),
            Text(group.description, style: TextStyle(fontSize: 12, color: subColor, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 5),
            Row(children: [
              Icon(Iconsax.people, size: 12, color: subColor),
              const SizedBox(width: 4),
              Text('${group.members} members', style: TextStyle(fontSize: 11, color: subColor)),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: Text(group.category, style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600)),
              ),
            ]),
          ])),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onJoinTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: group.joined ? surfaceColor : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: group.joined ? borderColor : AppColors.primary),
              ),
              child: Text(
                group.joined ? 'Joined' : 'Join',
                style: TextStyle(
                  color: group.joined ? subColor : Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _CreateGroupSheet extends StatefulWidget {
  final bool isDark;
  const _CreateGroupSheet({required this.isDark});
  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = 'Wealth';
  bool _isPremium = false;

  static const _categories = ['Wealth', 'Investing', 'Business', 'Mindset', 'Hustle', 'Skills', 'Budgeting', 'Personal Growth'];

  @override
  void dispose() { _nameCtrl.dispose(); _descCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.isDark ? AppColors.bgCard : Colors.white;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final subColor = widget.isDark ? Colors.white54 : Colors.black45;
    final surfaceColor = widget.isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = widget.isDark ? AppColors.bgSurface : Colors.grey.shade200;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
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
          TextField(controller: _nameCtrl, style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(hintText: 'e.g. Crypto Investors Nigeria', hintStyle: TextStyle(color: subColor, fontSize: 13), filled: true, fillColor: surfaceColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
          ),
          const SizedBox(height: 16),
          Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
          const SizedBox(height: 8),
          TextField(controller: _descCtrl, maxLines: 3, style: TextStyle(fontSize: 14, color: textColor),
            decoration: InputDecoration(hintText: 'What is this group about?', hintStyle: TextStyle(color: subColor, fontSize: 13), filled: true, fillColor: surfaceColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.all(14)),
          ),
          const SizedBox(height: 16),
          Text('Category', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: subColor)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: _categories.map((c) {
            final sel = c == _category;
            return GestureDetector(onTap: () => setState(() => _category = c), child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: sel ? AppColors.primary : surfaceColor, borderRadius: BorderRadius.circular(20), border: Border.all(color: sel ? AppColors.primary : borderColor)),
              child: Text(c, style: TextStyle(fontSize: 12, color: sel ? Colors.white : subColor, fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
            ));
          }).toList()),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.gold.withOpacity(widget.isDark ? 0.1 : 0.05), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.gold.withOpacity(0.3))),
            child: Row(children: [
              const Text('⭐', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Premium Group', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                Text('Only premium members can join. You earn coins.', style: TextStyle(fontSize: 12, color: subColor)),
              ])),
              Switch.adaptive(value: _isPremium, onChanged: (v) => setState(() => _isPremium = v), activeColor: AppColors.gold),
            ]),
          ),
        ]))),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(14)),
            child: const Center(child: Text('Create Group', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700))),
          ),
        ),
      ]),
    );
  }
}
