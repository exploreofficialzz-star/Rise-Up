import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';
import '../ai/post_ai_sheet.dart';

// ── Post Model ────────────────────────────────────────
class PostModel {
  final String id;
  final String name;
  final String username;
  final String time;
  final String avatar;
  final String tag;
  final String content;
  final int likes;
  final int comments;
  final int shares;
  final bool verified;
  final bool isPremiumPost;

  const PostModel({
    required this.id,
    required this.name,
    required this.username,
    required this.time,
    required this.avatar,
    required this.tag,
    required this.content,
    required this.likes,
    required this.comments,
    required this.shares,
    this.verified = false,
    this.isPremiumPost = false,
  });
}

// ── Sample Posts ──────────────────────────────────────
final _samplePosts = [
  PostModel(
    id: '1',
    name: 'Alex Johnson',
    username: '@alexj',
    time: '2m ago',
    avatar: '💼',
    tag: '💰 Wealth',
    content:
        'Just closed my first \$5,000 freelance deal this month!\n\nThe key was niching down and solving ONE specific problem for clients. Stop trying to do everything. Pick one skill. Go deep.',
    likes: 247,
    comments: 38,
    shares: 12,
    verified: true,
  ),
  PostModel(
    id: '2',
    name: 'Sarah Builds',
    username: '@sarahbuilds',
    time: '15m ago',
    avatar: '🚀',
    tag: '📈 Investing',
    content:
        'How I went from \$0 savings to \$10K in 8 months on a 9–5:\n\n① Cut 3 subscriptions I never used\n② Automated 20% of every paycheck\n③ Started one side skill (copywriting)\n④ Reinvested every extra dollar\n\nSimple. Not easy. But absolutely simple.',
    likes: 891,
    comments: 124,
    shares: 67,
    isPremiumPost: true,
  ),
  PostModel(
    id: '3',
    name: 'Marcus Wealth',
    username: '@marcusw',
    time: '1h ago',
    avatar: '💎',
    tag: '🧠 Mindset',
    content:
        'The people who say "I don\'t have time" spend 4+ hours on social media daily.\n\nTime is not the problem. Priority is.\n\nWhat you do before 8am and after 8pm defines your financial future.',
    likes: 2103,
    comments: 89,
    shares: 445,
    verified: true,
  ),
  PostModel(
    id: '4',
    name: 'Priya Skills',
    username: '@priyaskills',
    time: '3h ago',
    avatar: '🎯',
    tag: '💼 Business',
    content:
        'I\'ve hired 50+ freelancers globally. Here\'s what makes someone stand out:\n\n• Asks smart questions before starting\n• Delivers before the deadline\n• Communicates problems early\n• Gives options, not just problems\n\nSkill matters. Character matters MORE.',
    likes: 1456,
    comments: 203,
    shares: 178,
    verified: true,
  ),
  PostModel(
    id: '5',
    name: 'David Hustle',
    username: '@davidh',
    time: '5h ago',
    avatar: '🔥',
    tag: '⚡ Hustle',
    content:
        'Turned my graphic design hobby into \$3K/month in 6 months.\n\nPosted 1 tip daily on LinkedIn, reached out to 5 clients every day, offered free work for testimonials first.\n\nNow I have a waiting list. Your skill is worth more than you think.',
    likes: 673,
    comments: 91,
    shares: 55,
  ),
];

// ── Home Screen ───────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Map _profile = {};
  int _aiUsedToday = 0;
  static const int _dailyFreeLimit = 3;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final data = await api.getProfile();
      if (mounted) setState(() => _profile = data['profile'] ?? {});
    } catch (_) {}
  }

  bool get _isPremium =>
      (_profile['subscription_tier'] ?? 'free') == 'premium';

  int get _aiRemaining =>
      (_dailyFreeLimit - _aiUsedToday).clamp(0, _dailyFreeLimit);

  Future<void> _handleAiRequest(PostModel post,
      {required bool isPrivate}) async {
    if (_isPremium) {
      _openAi(post, isPrivate: isPrivate);
      return;
    }
    if (_aiUsedToday < _dailyFreeLimit) {
      setState(() => _aiUsedToday++);
      _openAi(post, isPrivate: isPrivate);
      return;
    }
    final confirmed = await _showAdPrompt();
    if (!confirmed) return;
    await adService.showRewardedAd(
      featureKey: 'post_ai',
      onRewarded: () {
        setState(() => _aiUsedToday = 0);
        _openAi(post, isPrivate: isPrivate);
      },
      onDismissed: () {},
    );
  }

  Future<bool> _showAdPrompt() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: isDark ? AppColors.bgCard : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text('Watch a short ad? 🎬',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: isDark ? Colors.white : Colors.black87)),
            content: Text(
              'You\'ve used your 3 free AI responses today.\n\nWatch a 30-second ad to unlock more, or upgrade to Premium for unlimited access.',
              style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.black54,
                  height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now',
                    style: TextStyle(color: AppColors.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Watch Ad',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _openAi(PostModel post, {required bool isPrivate}) {
    if (isPrivate) {
      context.go(
          '/chat?mode=general&postContext=${Uri.encodeComponent(post.content)}&postAuthor=${Uri.encodeComponent(post.name)}');
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PostAiSheet(post: post),
      );
    }
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
    final borderColor =
        isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;
    final iconColor = isDark ? Colors.white70 : Colors.black54;

    return Scaffold(
      backgroundColor: bgColor,

      // ── Fixed AppBar — never scrolls ─────────────────
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        // Left: Message + Task buttons
        leading: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => context.go('/chat'),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.bgSurface
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child:
                    Icon(Iconsax.message, color: iconColor, size: 18),
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: () => context.go('/tasks'),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.bgSurface
                      : Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(Iconsax.task_square,
                    color: iconColor, size: 18),
              ),
            ),
          ],
        ),
        leadingWidth: 90,

        // Center: RiseUp gradient
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Color(0xFFFF6B00),
              Color(0xFFFFD700),
              Color(0xFF6C5CE7),
            ],
            stops: [0.0, 0.4, 1.0],
          ).createShader(bounds),
          child: const Text(
            'RiseUp',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
        ),
        centerTitle: true,

        // Right: AI counter + Search + Bell
        actions: [
          if (!_isPremium)
            Container(
              margin:
                  const EdgeInsets.only(top: 12, bottom: 12),
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '🤖 $_aiRemaining left',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600),
              ),
            ),
          IconButton(
            icon: Icon(Iconsax.search_normal,
                color: iconColor, size: 20),
            onPressed: () => context.go('/explore'),
          ),
          IconButton(
            icon: Icon(Iconsax.notification,
                color: iconColor, size: 20),
            onPressed: () => context.go('/notifications'),
          ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),

      body: Column(
        children: [
          // ── Fixed Stories — never scrolls ─────────────
          Container(
            color: cardColor,
            child: Column(
              children: [
                SizedBox(
                  height: 92,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: 8,
                    itemBuilder: (_, i) =>
                        _StoryItem(index: i, isDark: isDark),
                  ),
                ),
                Divider(height: 1, color: borderColor),
              ],
            ),
          ),

          // ── Fixed TabBar — never scrolls ──────────────
          Container(
            color: cardColor,
            child: Column(
              children: [
                TabBar(
                  controller: _tabCtrl,
                  labelColor: AppColors.primary,
                  unselectedLabelColor: subColor,
                  indicatorColor: AppColors.primary,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  tabs: const [
                    Tab(text: 'For You'),
                    Tab(text: 'Following'),
                    Tab(text: 'Trending'),
                  ],
                ),
                Divider(height: 1, color: borderColor),
              ],
            ),
          ),

          // ── Only Feed scrolls ─────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: List.generate(
                3,
                (_) => _FeedList(
                  posts: _samplePosts,
                  isDark: isDark,
                  cardColor: cardColor,
                  borderColor: borderColor,
                  textColor: textColor,
                  subColor: subColor,
                  onAskAI: (p) =>
                      _handleAiRequest(p, isPrivate: false),
                  onPrivateChat: (p) =>
                      _handleAiRequest(p, isPrivate: true),
                  isPremium: _isPremium,
                  aiRemaining: _aiRemaining,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Feed List ─────────────────────────────────────────
class _FeedList extends StatelessWidget {
  final List<PostModel> posts;
  final bool isDark, isPremium;
  final Color cardColor, borderColor, textColor, subColor;
  final Function(PostModel) onAskAI;
  final Function(PostModel) onPrivateChat;
  final int aiRemaining;

  const _FeedList({
    required this.posts,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
    required this.onAskAI,
    required this.onPrivateChat,
    required this.isPremium,
    required this.aiRemaining,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: posts.length,
      separatorBuilder: (_, __) =>
          Divider(height: 8, thickness: 8, color: borderColor),
      itemBuilder: (_, i) => PostCard(
        post: posts[i],
        isDark: isDark,
        cardColor: cardColor,
        borderColor: borderColor,
        textColor: textColor,
        subColor: subColor,
        onAskAI: onAskAI,
        onPrivateChat: onPrivateChat,
        isPremium: isPremium,
        aiRemaining: aiRemaining,
      ).animate().fadeIn(delay: Duration(milliseconds: i * 60)),
    );
  }
}

// ── Post Card ─────────────────────────────────────────
class PostCard extends StatefulWidget {
  final PostModel post;
  final bool isDark, isPremium;
  final Color cardColor, borderColor, textColor, subColor;
  final Function(PostModel) onAskAI;
  final Function(PostModel) onPrivateChat;
  final int aiRemaining;

  const PostCard({
    super.key,
    required this.post,
    required this.isDark,
    required this.cardColor,
    required this.borderColor,
    required this.textColor,
    required this.subColor,
    required this.onAskAI,
    required this.onPrivateChat,
    required this.isPremium,
    required this.aiRemaining,
  });

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _liked = false;
  bool _saved = false;
  late int _likes;

  @override
  void initState() {
    super.initState();
    _likes = widget.post.likes;
  }

  String _fmt(int n) {
    if (n >= 1000000)
      return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.post;

    return Container(
      color: widget.cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Post Header ──────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color:
                            AppColors.primary.withOpacity(0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(p.avatar,
                            style:
                                const TextStyle(fontSize: 22)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Text(p.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: widget.textColor,
                                )),
                            if (p.verified) ...[
                              const SizedBox(width: 3),
                              const Icon(
                                  Icons.verified_rounded,
                                  color: AppColors.primary,
                                  size: 14),
                            ],
                            if (p.isPremiumPost) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.gold
                                      .withOpacity(0.2),
                                  borderRadius:
                                      BorderRadius.circular(4),
                                ),
                                child: const Text('⭐',
                                    style: TextStyle(
                                        fontSize: 9)),
                              ),
                            ],
                          ]),
                          const SizedBox(height: 1),
                          Row(children: [
                            Text(p.username,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: widget.subColor)),
                            Text(' · ${p.time}',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: widget.subColor)),
                          ]),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color:
                            AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(p.tag,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.more_horiz,
                        color: widget.subColor, size: 20),
                  ],
                ),

                const SizedBox(height: 12),

                // ── Post Content ─────────────────────
                Text(
                  p.content,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: widget.isDark
                        ? const Color(0xFFE8E8F0)
                        : Colors.black87,
                    height: 1.6,
                    letterSpacing: 0.1,
                  ),
                ),

                const SizedBox(height: 14),

                // ── Actions ──────────────────────────
                Row(children: [
                  _ActionBtn(
                    icon: _liked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,
                    label: _fmt(_likes),
                    color: _liked ? Colors.red : widget.subColor,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _liked = !_liked;
                        _likes += _liked ? 1 : -1;
                      });
                    },
                  ),
                  const SizedBox(width: 18),
                  _ActionBtn(
                    icon: Iconsax.message,
                    label: _fmt(p.comments),
                    color: widget.subColor,
                    onTap: () {},
                  ),
                  const SizedBox(width: 18),
                  _ActionBtn(
                    icon: Iconsax.send_1,
                    label: _fmt(p.shares),
                    color: widget.subColor,
                    onTap: () {},
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() => _saved = !_saved);
                    },
                    child: Icon(
                      _saved
                          ? Iconsax.archive_tick
                          : Iconsax.archive_add,
                      color: _saved
                          ? AppColors.primary
                          : widget.subColor,
                      size: 20,
                    ),
                  ),
                ]),

                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── AI Buttons ───────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              border: Border(
                  top: BorderSide(
                      color: widget.borderColor, width: 0.8)),
              color: widget.isDark
                  ? Colors.black.withOpacity(0.3)
                  : Colors.grey.shade50,
            ),
            child: Row(children: [
              // Ask AI publicly
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onAskAI(p),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(
                          widget.isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AppColors.primary.withOpacity(0.25),
                          width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [
                              AppColors.primary,
                              AppColors.accent
                            ]),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: const Icon(Icons.auto_awesome,
                              color: Colors.white, size: 10),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          widget.isPremium
                              ? 'Ask RiseUp AI'
                              : widget.aiRemaining > 0
                                  ? 'Ask RiseUp AI'
                                  : 'Ask RiseUp AI 📺',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Chat privately
              Expanded(
                child: GestureDetector(
                  onTap: () => widget.onPrivateChat(p),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withOpacity(
                          widget.isDark ? 0.15 : 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color:
                              AppColors.accent.withOpacity(0.25),
                          width: 0.8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Iconsax.lock,
                            color: AppColors.accent, size: 14),
                        const SizedBox(width: 6),
                        const Text(
                          'Chat Privately',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.accent,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Action Button ─────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Row(children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

// ── Story Item ────────────────────────────────────────
class _StoryItem extends StatelessWidget {
  final int index;
  final bool isDark;
  const _StoryItem({required this.index, required this.isDark});

  static const _emojis = [
    '💰', '🚀', '💎', '📈', '🔥', '💼', '🧠', '🎯'
  ];
  static const _names = [
    'You', 'Marcus', 'Priya', 'Sarah',
    'Alex', 'James', 'Linda', 'Kwame'
  ];

  @override
  Widget build(BuildContext context) {
    final isYou = index == 0;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: Column(
        children: [
          Stack(children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: isYou
                    ? null
                    : const LinearGradient(
                        colors: [
                          Color(0xFFFF6B00),
                          Color(0xFF6C5CE7)
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: isYou
                    ? (isDark
                        ? AppColors.bgSurface
                        : Colors.grey.shade200)
                    : null,
                border: isYou
                    ? Border.all(
                        color: AppColors.primary.withOpacity(0.4),
                        width: 1.5)
                    : null,
              ),
              child: Center(
                child: isYou
                    ? Icon(Icons.add,
                        color: AppColors.primary, size: 24)
                    : Text(_emojis[index],
                        style: const TextStyle(fontSize: 26)),
              ),
            ),
            if (!isYou)
              Positioned(
                bottom: 1,
                right: 1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: isDark
                            ? AppColors.bgCard
                            : Colors.white,
                        width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 5),
          Text(
            _names[index],
            style: TextStyle(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
              fontWeight:
                  isYou ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
