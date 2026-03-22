import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});
  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  late TabController _tabCtrl;
  bool _searching = false;
  String _query = '';
  List _realTrending = [];
  bool _trendingLoaded = false;

  static const _categories = [
    ('💰', 'Wealth'),
    ('📈', 'Investing'),
    ('💼', 'Business'),
    ('🧠', 'Mindset'),
    ('⚡', 'Hustle'),
    ('🎯', 'Skills'),
    ('🏠', 'Real Estate'),
    ('💻', 'Tech'),
  ];

  static const _trending = [
    _TrendPost(name: 'Marcus Wealth', username: '@marcusw', avatar: '💎',
        tag: '🧠 Mindset', verified: true,
        content: 'Broke people buy things. Middle class buy liabilities. Rich people buy assets. Which one are you?',
        likes: 4201, comments: 312),
    _TrendPost(name: 'Sarah Builds', username: '@sarahbuilds', avatar: '🚀',
        tag: '📈 Investing',
        content: '10 investment rules I wish I knew at 20:\n\n1. Start now, not later\n2. Compound is king\n3. Never invest what you can\'t lose\n4. Diversify always\n5. Emotions are your enemy',
        likes: 2891, comments: 198),
    _TrendPost(name: 'Alex Johnson', username: '@alexj', avatar: '💼',
        tag: '💰 Wealth', verified: true,
        content: 'My first \$100K took 4 years. My second took 18 months. My third took 6 months. The math of wealth acceleration is real.',
        likes: 6103, comments: 445),
    _TrendPost(name: 'Priya Skills', username: '@priyaskills', avatar: '🎯',
        tag: '💼 Business', verified: true,
        content: 'Skills that will make you rich in 2025:\n\n• Copywriting\n• Sales\n• Coding\n• Video editing\n• Digital marketing\n\nPick one. Master it. Monetize it.',
        likes: 3456, comments: 287),
  ];

  static const _creators = [
    _Creator(name: 'Marcus Wealth', username: '@marcusw', avatar: '💎',
        bio: 'Building wealth one post at a time', followers: '42.1K', verified: true),
    _Creator(name: 'Sarah Builds', username: '@sarahbuilds', avatar: '🚀',
        bio: 'From broke to \$10K/month — documenting the journey', followers: '28.5K'),
    _Creator(name: 'Alex Johnson', username: '@alexj', avatar: '💼',
        bio: 'Freelancer → Agency owner. 7 figures online', followers: '61.2K', verified: true),
    _Creator(name: 'Priya Skills', username: '@priyaskills', avatar: '🎯',
        bio: 'Helping you monetize your skills globally', followers: '35.8K', verified: true),
    _Creator(name: 'David Hustle', username: '@davidh', avatar: '🔥',
        bio: 'Graphic design → \$3K/month in 6 months', followers: '19.3K'),
    _Creator(name: 'Linda Growth', username: '@lindagrowth', avatar: '🌱',
        bio: 'Personal finance & wealth mindset coach', followers: '22.7K'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _loadTrending();
  }

  Future<void> _loadTrending() async {
    try {
      final data = await api.getFeed(tab: 'trending', limit: 20, offset: 0);
      if (mounted) setState(() {
        _realTrending = (data['posts'] as List? ?? []);
        _trendingLoaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _trendingLoaded = true);
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Explore',
            style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor)),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ───────────────────────────────
          Container(
            color: cardColor,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(fontSize: 14, color: textColor),
              onChanged: (v) => setState(() { _query = v; _searching = v.isNotEmpty; }),
              decoration: InputDecoration(
                hintText: 'Search wealth creators, topics...',
                hintStyle: TextStyle(color: subColor, fontSize: 13),
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: Icon(Iconsax.search_normal, color: subColor, size: 18),
                suffixIcon: _searching
                    ? IconButton(
                        icon: Icon(Icons.close, color: subColor, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() { _query = ''; _searching = false; });
                        })
                    : null,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // ── Tabs ─────────────────────────────────────
          Container(
            color: cardColor,
            child: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: subColor,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2.5,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'Trending'),
                Tab(text: 'Creators'),
                Tab(text: 'Groups'),
                Tab(text: 'Leaderboard'),
                Tab(text: 'Challenges'),
                Tab(text: 'Topics'),
              ],
            ),
          ),

          Divider(height: 1, color: borderColor),

          // ── Content ──────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                // Trending posts
                ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _trending.length,
                  separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: borderColor),
                  itemBuilder: (_, i) {
                    final p = _trending[i];
                    return Container(
                      color: cardColor,
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                shape: BoxShape.circle,
                              ),
                              child: Center(child: Text(p.avatar, style: const TextStyle(fontSize: 20))),
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Text(p.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor)),
                                  if (p.verified) ...[
                                    const SizedBox(width: 3),
                                    const Icon(Icons.verified_rounded, color: AppColors.primary, size: 13),
                                  ],
                                ]),
                                Text(p.username, style: TextStyle(fontSize: 11, color: subColor)),
                              ],
                            )),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(p.tag, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Text(p.content, style: TextStyle(fontSize: 14, color: textColor, height: 1.55)),
                          const SizedBox(height: 10),
                          Row(children: [
                            Icon(Icons.favorite_border_rounded, color: subColor, size: 18),
                            const SizedBox(width: 4),
                            Text(_fmt(p.likes), style: TextStyle(color: subColor, fontSize: 12)),
                            const SizedBox(width: 16),
                            Icon(Iconsax.message, color: subColor, size: 18),
                            const SizedBox(width: 4),
                            Text(_fmt(p.comments), style: TextStyle(color: subColor, fontSize: 12)),
                          ]),
                        ],
                      ),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                  },
                ),

                // Creators
                ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _creators.length,
                  separatorBuilder: (_, __) => Divider(height: 16, color: borderColor),
                  itemBuilder: (_, i) {
                    final c = _creators[i];
                    return Row(children: [
                      Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                          shape: BoxShape.circle,
                        ),
                        child: Center(child: Text(c.avatar, style: const TextStyle(fontSize: 24))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(c.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                            if (c.verified) ...[
                              const SizedBox(width: 3),
                              const Icon(Icons.verified_rounded, color: AppColors.primary, size: 13),
                            ],
                          ]),
                          Text(c.username, style: TextStyle(fontSize: 12, color: subColor)),
                          Text(c.bio, style: TextStyle(fontSize: 12, color: subColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text('${c.followers} followers', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                        ],
                      )),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Following!'), backgroundColor: AppColors.success, duration: Duration(seconds: 1)),
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Follow', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                  },
                ),

                // ── Groups ───────────────────────────
                _GroupsTab(isDark: isDark, bgColor: bgColor, cardColor: cardColor, borderColor: borderColor, textColor: textColor, subColor: subColor),

                // ── Leaderboard ──────────────────────
                _LeaderboardTab(isDark: isDark, bgColor: bgColor, cardColor: cardColor, textColor: textColor, subColor: subColor),

                // ── Challenges ───────────────────────
                _ChallengesTab(isDark: isDark, bgColor: bgColor, cardColor: cardColor, borderColor: borderColor, textColor: textColor, subColor: subColor),

                // ── Topics/Categories ─────────────────
                GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.6,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (_, i) {
                    final c = _categories[i];
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Browsing \${c.\$2}...'), duration: const Duration(seconds: 1)),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(isDark ? 0.15 : 0.08),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(c.$1, style: const TextStyle(fontSize: 28)),
                            const SizedBox(height: 6),
                            Text(c.$2, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                          ],
                        ),
                      ),
                    ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _TrendPost {
  final String name, username, avatar, tag, content;
  final int likes, comments;
  final bool verified;
  const _TrendPost({required this.name, required this.username, required this.avatar, required this.tag, required this.content, required this.likes, required this.comments, this.verified = false});
}

class _Creator {
  final String name, username, avatar, bio, followers;
  final bool verified;
  const _Creator({required this.name, required this.username, required this.avatar, required this.bio, required this.followers, this.verified = false});
}

// ── Groups Tab ────────────────────────────────────────
class _GroupsTab extends StatelessWidget {
  final bool isDark;
  final Color bgColor, cardColor, borderColor, textColor, subColor;
  const _GroupsTab({required this.isDark, required this.bgColor, required this.cardColor, required this.borderColor, required this.textColor, required this.subColor});

  static const _groups = [
    (emoji: '💰', name: 'Wealth Builders NG', members: '12.4K', tag: 'Finance', joined: true),
    (emoji: '💻', name: 'Freelancers Africa', members: '8.1K', tag: 'Freelance', joined: false),
    (emoji: '📈', name: 'Stock Market Hub', members: '6.7K', tag: 'Investing', joined: false),
    (emoji: '🚀', name: 'Online Hustlers', members: '15.2K', tag: 'Side Income', joined: true),
    (emoji: '🧠', name: 'Mindset & Money', members: '9.3K', tag: 'Mindset', joined: false),
    (emoji: '🛍️', name: 'eCommerce Masters', members: '5.8K', tag: 'eCommerce', joined: false),
    (emoji: '🎯', name: 'Skill Monetizers', members: '7.1K', tag: 'Skills', joined: false),
    (emoji: '🏠', name: 'Real Estate Investors', members: '4.2K', tag: 'Real Estate', joined: false),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _groups.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: borderColor),
      itemBuilder: (_, i) {
        final g = _groups[i];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(child: Text(g.emoji, style: const TextStyle(fontSize: 22))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(g.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 2),
              Row(children: [
                Text('${g.members} members', style: TextStyle(fontSize: 11, color: subColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(g.tag, style: const TextStyle(fontSize: 9, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              ]),
            ])),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.go('/groups'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: g.joined ? Colors.transparent : AppColors.primary,
                  borderRadius: BorderRadius.circular(20),
                  border: g.joined ? Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300) : null,
                ),
                child: Text(g.joined ? 'Joined' : 'Join',
                    style: TextStyle(color: g.joined ? subColor : Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ── Leaderboard Tab ───────────────────────────────────
class _LeaderboardTab extends StatelessWidget {
  final bool isDark;
  final Color bgColor, cardColor, textColor, subColor;
  const _LeaderboardTab({required this.isDark, required this.bgColor, required this.cardColor, required this.textColor, required this.subColor});

  static const _leaders = [
    (rank: 1, emoji: '💎', name: 'Marcus Wealth', username: '@marcusw', score: '142,500', badge: '🥇'),
    (rank: 2, emoji: '🚀', name: 'Sarah Builds', username: '@sarahbuilds', score: '98,320', badge: '🥈'),
    (rank: 3, emoji: '💼', name: 'Alex Johnson', username: '@alexj', score: '87,150', badge: '🥉'),
    (rank: 4, emoji: '🎯', name: 'Priya Skills', username: '@priyaskills', score: '76,400', badge: ''),
    (rank: 5, emoji: '🔥', name: 'David Hustle', username: '@davidh', score: '65,200', badge: ''),
    (rank: 6, emoji: '🌱', name: 'Linda Growth', username: '@lindagrowth', score: '54,800', badge: ''),
    (rank: 7, emoji: '💪', name: 'James Earn', username: '@jamese', score: '43,100', badge: ''),
    (rank: 8, emoji: '🧠', name: 'Kwame Smart', username: '@kwames', score: '38,700', badge: ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter row
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: cardColor,
          child: Row(
            children: ['Weekly', 'Monthly', 'All Time'].map((label) {
              final selected = label == 'Weekly';
              return GestureDetector(
                onTap: () => HapticFeedback.lightImpact(),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    border: selected ? null : Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300),
                  ),
                  child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? Colors.white : subColor)),
                ),
              );
            }).toList(),
          ),
        ),

        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _leaders.length,
            itemBuilder: (_, i) {
              final l = _leaders[i];
              final isTop3 = l.rank <= 3;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isTop3
                      ? AppColors.primary.withOpacity(isDark ? 0.12 : 0.06)
                      : (isDark ? AppColors.bgCard : const Color(0xFFF8F8F8)),
                  borderRadius: BorderRadius.circular(14),
                  border: isTop3 ? Border.all(color: AppColors.primary.withOpacity(0.2)) : null,
                ),
                child: Row(children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      l.badge.isNotEmpty ? l.badge : '#${l.rank}',
                      style: TextStyle(fontSize: l.badge.isNotEmpty ? 20 : 14, fontWeight: FontWeight.w700, color: subColor),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 42, height: 42,
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                    child: Center(child: Text(l.emoji, style: const TextStyle(fontSize: 20))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(l.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                    Text(l.username, style: TextStyle(fontSize: 11, color: subColor)),
                  ])),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(l.score, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w800, fontSize: 14)),
                    Text('points', style: TextStyle(fontSize: 10, color: subColor)),
                  ]),
                ]),
              ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
            },
          ),
        ),
      ],
    );
  }
}

// ── Challenges Tab ────────────────────────────────────
class _ChallengesTab extends StatelessWidget {
  final bool isDark;
  final Color bgColor, cardColor, borderColor, textColor, subColor;
  const _ChallengesTab({required this.isDark, required this.bgColor, required this.cardColor, required this.borderColor, required this.textColor, required this.subColor});

  static const _challenges = [
    (emoji: '💰', title: '7-Day Income Sprint', desc: 'Earn at least \$50 in 7 days using any method', participants: '2.4K', daysLeft: 3, reward: '500 pts', joined: false),
    (emoji: '📝', title: '30-Day Skill Challenge', desc: 'Learn one marketable skill in 30 days', participants: '5.1K', daysLeft: 18, reward: '1,000 pts', joined: true),
    (emoji: '🚀', title: 'First Client Sprint', desc: 'Land your first freelance client this week', participants: '1.8K', daysLeft: 5, reward: '750 pts', joined: false),
    (emoji: '📊', title: 'Budget Master', desc: 'Track every expense for 21 days straight', participants: '3.2K', daysLeft: 12, reward: '600 pts', joined: false),
    (emoji: '🔥', title: '100-Day Hustle', desc: 'Post about your income journey for 100 days', participants: '890', daysLeft: 67, reward: '2,000 pts', joined: true),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _challenges.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final c = _challenges[i];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
            borderRadius: BorderRadius.circular(16),
            border: c.joined ? Border.all(color: AppColors.primary.withOpacity(0.3)) : null,
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(c.emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c.title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                Text('${c.participants} joined · ${c.daysLeft}d left', style: TextStyle(fontSize: 11, color: subColor)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: AppColors.gold.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(c.reward, style: const TextStyle(fontSize: 10, color: AppColors.gold, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            Text(c.desc, style: TextStyle(fontSize: 13, color: subColor, height: 1.4)),
            const SizedBox(height: 12),
            // Progress bar (visual only for now)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: c.joined ? 0.35 : 0,
                backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(c.joined ? 'Already joined!' : 'Joined challenge! 🎯'),
                      backgroundColor: AppColors.success,
                      duration: const Duration(seconds: 1),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.joined ? Colors.transparent : AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                    border: c.joined ? Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300) : null,
                  ),
                  child: Text(c.joined ? '✓ Joined' : 'Join Challenge',
                      style: TextStyle(color: c.joined ? subColor : Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ]),
          ]),
        ).animate().fadeIn(delay: Duration(milliseconds: i * 60));
      },
    );
  }
}
