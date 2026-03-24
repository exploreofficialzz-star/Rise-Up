import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  // Placeholder community data – replace with real API calls
  final List<Map> _posts = [
    {
      'id': '1',
      'name': 'Amaka O.',
      'stage': 'earning',
      'type': 'win',
      'content': 'Just completed my first Canva design job and earned ₦15,000! RiseUp AI found the client for me 🎉',
      'likes': 42,
      'created_at': DateTime.now().subtract(const Duration(hours: 2)),
    },
    {
      'id': '2',
      'name': 'Tunde A.',
      'stage': 'growing',
      'type': 'tip',
      'content': 'Tip: For Nigerian freelancers — price your social media management at ₦25k-₦50k/month minimum. Clients will pay once they see your portfolio.',
      'likes': 67,
      'created_at': DateTime.now().subtract(const Duration(hours: 5)),
    },
    {
      'id': '3',
      'name': 'Sarah K.',
      'stage': 'wealth',
      'type': 'win',
      'content': 'Hit my first ₦100k month through copywriting! Started 3 months ago with zero experience. The skill module was 🔑',
      'likes': 128,
      'created_at': DateTime.now().subtract(const Duration(hours: 8)),
    },
    {
      'id': '4',
      'name': 'Chidi E.',
      'stage': 'survival',
      'type': 'question',
      'content': 'Which platforms are best for selling digital products in Nigeria? Paystack or Flutterwave for the store?',
      'likes': 15,
      'created_at': DateTime.now().subtract(const Duration(days: 1)),
    },
  ];

  final List<Map> _leaderboard = [
    {'name': 'Sarah K.', 'earned': '₦320,000', 'stage': 'wealth', 'rank': 1},
    {'name': 'Tunde A.', 'earned': '₦215,000', 'stage': 'growing', 'rank': 2},
    {'name': 'Amaka O.', 'earned': '₦89,000', 'stage': 'earning', 'rank': 3},
    {'name': 'Ngozi B.', 'earned': '₦67,500', 'stage': 'earning', 'rank': 4},
    {'name': 'Emeka C.', 'earned': '₦52,000', 'stage': 'earning', 'rank': 5},
  ];

  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Community', style: AppTextStyles.h3),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: [
                _TabChip('Feed', 0, _tab, () => setState(() => _tab = 0)),
                const SizedBox(width: 8),
                _TabChip('Leaderboard', 1, _tab, () => setState(() => _tab = 1)),
                const SizedBox(width: 8),
                _TabChip('Challenges', 2, _tab, () => setState(() => _tab = 2)),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          _FeedTab(posts: _posts),
          _LeaderboardTab(leaderboard: _leaderboard),
          _ChallengesTab(),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _showPostModal,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Share Win'),
            )
          : null,
    );
  }

  void _showPostModal() {
    final ctrl = TextEditingController();
    String type = 'win';
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Share with the community', style: AppTextStyles.h4),
              const SizedBox(height: 16),
              // Type selector
              Row(
                children: [
                  for (final t in [('🎉 Win', 'win'), ('💡 Tip', 'tip'), ('❓ Question', 'question')])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: () => set(() => type = t.$2),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: type == t.$2 ? AppColors.primary.withOpacity(0.2) : AppColors.bgSurface,
                            borderRadius: AppRadius.pill,
                            border: Border.all(color: type == t.$2 ? AppColors.primary : Colors.transparent),
                          ),
                          child: Text(t.$1, style: AppTextStyles.bodySmall.copyWith(
                            color: type == t.$2 ? AppColors.primary : AppColors.textSecondary,
                          )),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 4,
                style: AppTextStyles.body,
                decoration: InputDecoration(
                  hintText: type == 'win'
                      ? 'Share your win — what did you achieve?'
                      : type == 'tip'
                          ? 'What income or skill tip would help others?'
                          : 'Ask the community a question...',
                  hintStyle: AppTextStyles.label,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: const Text('🌟 Post shared with the community!'),
                      backgroundColor: AppColors.success,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Post to Community'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final int index, current;
  final VoidCallback onTap;
  const _TabChip(this.label, this.index, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final selected = index == current;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bgCard,
          borderRadius: AppRadius.pill,
          border: Border.all(color: selected ? AppColors.primary : AppColors.bgSurface),
        ),
        child: Text(
          label,
          style: AppTextStyles.label.copyWith(
            color: selected ? Colors.white : AppColors.textMuted,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _FeedTab extends StatelessWidget {
  final List<Map> posts;
  const _FeedTab({required this.posts});

  Color _typeColor(String type) {
    switch (type) {
      case 'win': return AppColors.success;
      case 'tip': return AppColors.accent;
      case 'question': return AppColors.warning;
      default: return AppColors.primary;
    }
  }

  String _typeEmoji(String type) {
    switch (type) {
      case 'win': return '🎉';
      case 'tip': return '💡';
      case 'question': return '❓';
      case 'challenge': return '⚡';
      default: return '📝';
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: posts.length,
      itemBuilder: (_, i) {
        final post = posts[i];
        final stageInfo = StageInfo.get(post['stage'] ?? 'survival');
        final created = post['created_at'] as DateTime;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.lg,
            border: Border.all(color: AppColors.bgSurface),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: (stageInfo['color'] as Color).withOpacity(0.2),
                    child: Text(
                      (post['name'] as String).isNotEmpty ? post['name'][0] : 'U',
                      style: AppTextStyles.label.copyWith(color: stageInfo['color'] as Color),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(post['name'], style: AppTextStyles.h4.copyWith(fontSize: 13)),
                      Row(
                        children: [
                          Text('${stageInfo['emoji']} ${stageInfo['label']}', style: AppTextStyles.caption.copyWith(color: stageInfo['color'] as Color)),
                          Text(' · ${timeago.format(created)}', style: AppTextStyles.caption),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _typeColor(post['type']).withOpacity(0.12),
                      borderRadius: AppRadius.pill,
                    ),
                    child: Text(
                      '${_typeEmoji(post['type'])} ${post['type']}',
                      style: AppTextStyles.caption.copyWith(color: _typeColor(post['type']), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(post['content'], style: AppTextStyles.body.copyWith(fontSize: 13, height: 1.5)),
              const SizedBox(height: 12),
              Row(
                children: [
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                    },
                    child: Row(
                      children: [
                        Icon(Iconsax.heart, size: 16, color: AppColors.textMuted),
                        const SizedBox(width: 4),
                        Text('${post['likes']}', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Row(
                    children: [
                      Icon(Iconsax.message, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 4),
                      Text('Reply', style: AppTextStyles.caption),
                    ],
                  ),
                  const Spacer(),
                  Icon(Iconsax.share, size: 16, color: AppColors.textMuted),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 60)).slideY(begin: 0.1);
      },
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  final List<Map> leaderboard;
  const _LeaderboardTab({required this.leaderboard});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Top 3 podium
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2D1B69), Color(0xFF1A3A4F)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: AppRadius.xl,
          ),
          child: Column(
            children: [
              Text('🏆 Monthly Earners', style: AppTextStyles.h4.copyWith(color: AppColors.gold)),
              const SizedBox(height: 4),
              Text('Top performers this month', style: AppTextStyles.caption),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (leaderboard.length > 1) _PodiumItem(leaderboard[1], 2),
                  if (leaderboard.isNotEmpty) _PodiumItem(leaderboard[0], 1),
                  if (leaderboard.length > 2) _PodiumItem(leaderboard[2], 3),
                ],
              ),
            ],
          ),
        ).animate().fadeIn(),

        const SizedBox(height: 20),
        Text('Full Rankings', style: AppTextStyles.h4),
        const SizedBox(height: 12),

        ...leaderboard.asMap().entries.map((e) {
          final rank = e.key + 1;
          final user = e.value;
          final stageInfo = StageInfo.get(user['stage'] ?? 'survival');
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: rank <= 3 ? AppColors.gold.withOpacity(0.06) : AppColors.bgCard,
              borderRadius: AppRadius.md,
              border: Border.all(color: rank <= 3 ? AppColors.gold.withOpacity(0.2) : AppColors.bgSurface),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  child: Text(
                    rank <= 3 ? ['🥇', '🥈', '🥉'][rank - 1] : '#$rank',
                    style: AppTextStyles.h4.copyWith(fontSize: rank <= 3 ? 20 : 13),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 12),
                CircleAvatar(
                  radius: 16,
                  backgroundColor: (stageInfo['color'] as Color).withOpacity(0.2),
                  child: Text(
                    (user['name'] as String)[0],
                    style: AppTextStyles.caption.copyWith(color: stageInfo['color'] as Color),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(user['name'], style: AppTextStyles.h4.copyWith(fontSize: 14))),
                Text(
                  user['earned'],
                  style: AppTextStyles.h4.copyWith(color: AppColors.success, fontSize: 14),
                ),
              ],
            ),
          ).animate().fadeIn(delay: Duration(milliseconds: e.key * 50));
        }),
      ],
    );
  }
}

class _PodiumItem extends StatelessWidget {
  final Map user;
  final int rank;
  const _PodiumItem(this.user, this.rank);

  @override
  Widget build(BuildContext context) {
    final isFirst = rank == 1;
    return Column(
      children: [
        if (isFirst) const Text('👑', style: TextStyle(fontSize: 20)),
        CircleAvatar(
          radius: isFirst ? 30 : 22,
          backgroundColor: rank == 1 ? AppColors.gold.withOpacity(0.3) : AppColors.primary.withOpacity(0.2),
          child: Text(
            (user['name'] as String)[0],
            style: AppTextStyles.h3.copyWith(
              fontSize: isFirst ? 24 : 18,
              color: rank == 1 ? AppColors.gold : AppColors.primary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(user['name'].toString().split(' ').first, style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600)),
        Text(user['earned'], style: AppTextStyles.caption.copyWith(color: AppColors.success)),
        Container(
          margin: const EdgeInsets.only(top: 4),
          width: isFirst ? 60 : 50,
          height: isFirst ? 50 : 35,
          decoration: BoxDecoration(
            color: rank == 1 ? AppColors.gold.withOpacity(0.2) : AppColors.primary.withOpacity(0.15),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Center(child: Text('#$rank', style: AppTextStyles.label.copyWith(color: rank == 1 ? AppColors.gold : AppColors.primary))),
        ),
      ],
    );
  }
}

class _ChallengesTab extends StatelessWidget {
  final List<Map> _challenges = const [
    {
      'title': '7-Day Income Sprint',
      'description': 'Earn at least ₦5,000 from a new task within 7 days',
      'prize': '🏆 Task Booster Unlocked',
      'participants': 234,
      'daysLeft': 4,
      'emoji': '⚡',
      'color': 0xFFE17055,
    },
    {
      'title': 'Skill Fast-Track',
      'description': 'Complete any skill module in under 14 days',
      'prize': '🎓 Mentorship Session',
      'participants': 89,
      'daysLeft': 10,
      'emoji': '📚',
      'color': 0xFF6C5CE7,
    },
    {
      'title': 'Community Builder',
      'description': 'Share 3 wins or tips in the community feed',
      'prize': '👑 Premium Week Free',
      'participants': 156,
      'daysLeft': 6,
      'emoji': '🌟',
      'color': 0xFF00B894,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _challenges.length,
      itemBuilder: (_, i) {
        final c = _challenges[i];
        final color = Color(c['color'] as int);
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: AppRadius.lg,
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(c['emoji'] as String, style: const TextStyle(fontSize: 28)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['title'] as String, style: AppTextStyles.h4.copyWith(color: color)),
                        Text('${c['daysLeft']} days left · ${c['participants']} joined', style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(c['description'] as String, style: AppTextStyles.body.copyWith(fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: AppRadius.pill),
                child: Text('Prize: ${c['prize']}', style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('🎯 Joined "${c['title']}"! Good luck!'),
                    backgroundColor: AppColors.success,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  )),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                  ),
                  child: const Text('Join Challenge →', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 80)).slideY(begin: 0.15);
      },
    );
  }
}
