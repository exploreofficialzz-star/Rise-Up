// frontend/lib/screens/tasks/task_detail_sheet.dart
//
// TaskDetailSheet — full-screen bottom sheet that opens when user taps any task
// ─────────────────────────────────────────────────────────────────────────────
//  Sections:
//    1. Hero header  — title, category, difficulty, earnings, time to earn
//    2. Why this task? — AI-personalised reason from task data
//    3. Full description
//    4. Step-by-step action plan  (all steps, numbered)
//    5. Platforms & tools  (tappable chips with real URLs)
//    6. Learning resources  (curated by category)
//    7. Community & contacts  (where to find peers doing this)
//    8. AI Mentor guidance  — premium: auto-loads; free: behind rewarded-ad gate
//    9. Sticky CTA footer  — Accept / Mark Complete / Skip
//
//  Ad strategy:
//    • Free users see a banner ad between Steps and Learning sections
//    • AI Mentor guidance is behind a rewarded-ad gate for free users
//    • One extra interstitial fired when sheet opens for free users (via caller)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';
import '../../widgets/ad_widgets.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Static resource maps — real, verified educational URLs by category
// ─────────────────────────────────────────────────────────────────────────────

const Map<String, List<Map<String, String>>> kLearningResources = {
  'freelance': [
    {'title': 'Upwork Success Handbook',      'url': 'https://www.upwork.com/resources/beginners-guide-to-upwork', 'emoji': '📗'},
    {'title': 'Fiverr Learn',                 'url': 'https://learn.fiverr.com',                                   'emoji': '🎓'},
    {'title': 'Freelancing 101 (Coursera)',   'url': 'https://www.coursera.org/courses?query=freelancing',         'emoji': '🏫'},
    {'title': 'How to Get Your First Client', 'url': 'https://www.youtube.com/results?search_query=how+to+get+first+freelance+client+2024', 'emoji': '▶️'},
  ],
  'content': [
    {'title': 'YouTube Creator Academy',      'url': 'https://creatoracademy.youtube.com',                         'emoji': '▶️'},
    {'title': 'HubSpot Content Marketing',    'url': 'https://academy.hubspot.com/courses/content-marketing',      'emoji': '📝'},
    {'title': 'Canva Design School',          'url': 'https://www.canva.com/designschool',                         'emoji': '🎨'},
    {'title': 'TikTok Creator Portal',        'url': 'https://www.tiktok.com/creators/creator-portal',             'emoji': '🎵'},
  ],
  'digital': [
    {'title': 'Google Digital Garage',        'url': 'https://learndigital.withgoogle.com',                        'emoji': '🔍'},
    {'title': 'Meta Blueprint (Free)',         'url': 'https://www.facebook.com/business/learn',                    'emoji': '📱'},
    {'title': 'Shopify Free Courses',         'url': 'https://www.shopify.com/learn',                              'emoji': '🛍️'},
    {'title': 'Semrush Academy',              'url': 'https://www.semrush.com/academy',                            'emoji': '📊'},
  ],
  'gig': [
    {'title': 'TaskRabbit Pro Guide',         'url': 'https://support.taskrabbit.com/hc/en-us',                    'emoji': '🔧'},
    {'title': 'Gig Economy Success Tips',     'url': 'https://www.youtube.com/results?search_query=gig+economy+tips+2024', 'emoji': '💼'},
    {'title': 'Side Hustle Nation',           'url': 'https://www.sidehustlenation.com/ideas',                     'emoji': '🚀'},
    {'title': 'Rideshare Dashboard',          'url': 'https://www.ridesharedashboard.com',                         'emoji': '🚗'},
  ],
  'investment': [
    {'title': 'Investopedia Academy',         'url': 'https://www.investopedia.com/financial-advisor-4427709',     'emoji': '📈'},
    {'title': 'Khan Academy Finance',         'url': 'https://www.khanacademy.org/economics-finance-domain',       'emoji': '🏦'},
    {'title': 'CFA Institute Free Resources', 'url': 'https://www.cfainstitute.org/en/programs',                   'emoji': '💎'},
    {'title': 'Morningstar Investing Guide',  'url': 'https://www.morningstar.com/start-investing',                'emoji': '⭐'},
  ],
  'default': [
    {'title': 'Udemy Free Courses',           'url': 'https://www.udemy.com/courses/free',                         'emoji': '🎓'},
    {'title': 'Google Free Certifications',   'url': 'https://grow.google/certificates',                           'emoji': '🔍'},
    {'title': 'LinkedIn Learning (1 mo free)','url': 'https://www.linkedin.com/learning',                          'emoji': '💼'},
    {'title': 'YouTube How-To Guides',        'url': 'https://www.youtube.com/results?search_query=how+to+make+money+online+2024', 'emoji': '▶️'},
  ],
};

const Map<String, List<Map<String, String>>> kCommunities = {
  'freelance': [
    {'name': 'r/freelance',         'url': 'https://reddit.com/r/freelance',          'size': '450K+',  'type': 'Reddit'},
    {'name': 'r/forhire',           'url': 'https://reddit.com/r/forhire',            'size': '150K+',  'type': 'Reddit'},
    {'name': 'Upwork Community',    'url': 'https://community.upwork.com',            'size': '1M+',    'type': 'Forum'},
    {'name': 'Fiverr Community',    'url': 'https://community.fiverr.com',            'size': '500K+',  'type': 'Forum'},
  ],
  'content': [
    {'name': 'r/NewTubers',         'url': 'https://reddit.com/r/NewTubers',          'size': '300K+',  'type': 'Reddit'},
    {'name': 'r/ContentCreators',   'url': 'https://reddit.com/r/content_creators',   'size': '80K+',   'type': 'Reddit'},
    {'name': 'Creator Economy',     'url': 'https://creatoreconomy.so/community',     'size': '25K+',   'type': 'Community'},
    {'name': 'IndieHackers Media',  'url': 'https://www.indiehackers.com/group/content-creators', 'size': '30K+', 'type': 'Forum'},
  ],
  'digital': [
    {'name': 'r/Entrepreneur',      'url': 'https://reddit.com/r/Entrepreneur',       'size': '1.2M+',  'type': 'Reddit'},
    {'name': 'IndieHackers',        'url': 'https://www.indiehackers.com',            'size': '100K+',  'type': 'Forum'},
    {'name': 'r/ecommerce',         'url': 'https://reddit.com/r/ecommerce',          'size': '200K+',  'type': 'Reddit'},
    {'name': 'Digital Nomad Forum', 'url': 'https://reddit.com/r/digitalnomad',       'size': '500K+',  'type': 'Reddit'},
  ],
  'gig': [
    {'name': 'r/gigwork',           'url': 'https://reddit.com/r/gigwork',            'size': '45K+',   'type': 'Reddit'},
    {'name': 'Gig Workers Alliance','url': 'https://gigworkersalliance.com',           'size': '20K+',   'type': 'Org'},
    {'name': 'Side Hustle Nation',  'url': 'https://www.facebook.com/groups/sidehustlenation', 'size': '100K+', 'type': 'Facebook'},
    {'name': 'r/SideHustle',        'url': 'https://reddit.com/r/SideHustle',         'size': '60K+',   'type': 'Reddit'},
  ],
  'default': [
    {'name': 'r/Entrepreneur',      'url': 'https://reddit.com/r/Entrepreneur',       'size': '1.2M+',  'type': 'Reddit'},
    {'name': 'r/passive_income',    'url': 'https://reddit.com/r/passive_income',     'size': '350K+',  'type': 'Reddit'},
    {'name': 'IndieHackers',        'url': 'https://www.indiehackers.com',            'size': '100K+',  'type': 'Forum'},
    {'name': 'r/SideHustle',        'url': 'https://reddit.com/r/SideHustle',         'size': '60K+',   'type': 'Reddit'},
  ],
};

/// Platform name → URL lookup (fallback when task data has no URL)
const Map<String, String> kPlatformUrls = {
  'upwork':      'https://www.upwork.com',
  'fiverr':      'https://www.fiverr.com',
  'toptal':      'https://www.toptal.com',
  'freelancer':  'https://www.freelancer.com',
  'contra':      'https://contra.com',
  'jiji':        'https://jiji.ng',
  'piggyvest':   'https://piggyvest.com',
  'cowrywise':   'https://cowrywise.com',
  'shopee':      'https://shopee.com',
  'lazada':      'https://www.lazada.com',
  'etsy':        'https://www.etsy.com',
  'amazon':      'https://www.amazon.com',
  'youtube':     'https://www.youtube.com',
  'tiktok':      'https://www.tiktok.com',
  'instagram':   'https://www.instagram.com',
  'linkedin':    'https://www.linkedin.com',
  'taskrabbit':  'https://www.taskrabbit.com',
  'airtasker':   'https://www.airtasker.com',
  'doordash':    'https://www.doordash.com',
  'uber':        'https://www.uber.com',
  'gojek':       'https://www.gojek.com',
  'shopify':     'https://www.shopify.com',
  'gumroad':     'https://gumroad.com',
  'teachable':   'https://teachable.com',
  'substack':    'https://substack.com',
  'patreon':     'https://www.patreon.com',
};

// ═══════════════════════════════════════════════════════════════════════════════
// TaskDetailSheet
// ═══════════════════════════════════════════════════════════════════════════════

class TaskDetailSheet extends StatefulWidget {
  final Map        task;
  final bool       isPremium;
  final VoidCallback? onAccept;
  final VoidCallback? onComplete;
  final VoidCallback? onSkip;

  const TaskDetailSheet({
    super.key,
    required this.task,
    required this.isPremium,
    this.onAccept,
    this.onComplete,
    this.onSkip,
  });

  /// Convenience static opener
  static Future<void> show(
    BuildContext context, {
    required Map        task,
    required bool       isPremium,
    VoidCallback?       onAccept,
    VoidCallback?       onComplete,
    VoidCallback?       onSkip,
  }) {
    return showModalBottomSheet(
      context:          context,
      isScrollControlled: true,
      useSafeArea:      true,
      backgroundColor:  Colors.transparent,
      builder: (_) => TaskDetailSheet(
        task:       task,
        isPremium:  isPremium,
        onAccept:   onAccept,
        onComplete: onComplete,
        onSkip:     onSkip,
      ),
    );
  }

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  // ── AI guidance state ──────────────────────────────────────────────────────
  String? _aiGuidance;
  bool    _aiLoading   = false;
  bool    _aiUnlocked  = false;   // true when premium or rewarded ad watched
  bool    _aiError     = false;

  // ── UI state ───────────────────────────────────────────────────────────────
  bool _stepsExpanded = false;
  final ScrollController _scroll = ScrollController();

  // ── Helpers ────────────────────────────────────────────────────────────────

  Map  get t  => widget.task;
  bool get _isPremium => widget.isPremium;

  String get _category => t['category'] as String? ?? 'default';
  String get _currency => t['currency'] as String? ?? 'NGN';

  List<String> get _allSteps {
    final actionSteps = t['action_steps'];
    if (actionSteps is List && actionSteps.isNotEmpty) {
      return actionSteps.map((s) => s.toString()).toList();
    }
    final steps = t['steps'];
    if (steps is List && steps.isNotEmpty) {
      return steps.map((s) => s.toString()).toList();
    }
    return [];
  }

  List<Map<String, String>> get _platforms {
    final result = <Map<String, String>>[];

    // local_platforms and global_platforms from AI generation
    for (final list in [t['local_platforms'], t['global_platforms']]) {
      if (list is List) {
        for (final p in list) {
          final name = p.toString().toLowerCase().trim();
          result.add({
            'name': p.toString(),
            'url':  kPlatformUrls[name] ?? 'https://www.google.com/search?q=$name+platform',
          });
        }
      }
    }

    // Single platform field
    final platform = t['platform'] as String?;
    if (platform != null && result.isEmpty) {
      final lower = platform.toLowerCase().trim();
      result.add({
        'name': platform,
        'url':  kPlatformUrls[lower] ?? 'https://www.google.com/search?q=$lower',
      });
    }

    // Deduplicate by name
    final seen = <String>{};
    return result.where((p) => seen.add(p['name']!)).toList();
  }

  String _earningsDisplay() {
    final actual    = t['actual_earnings'];
    if (actual != null && (actual as num) > 0) return 'Earned: $_currency $actual';

    final potential = t['earning_potential'];
    if (potential is Map) {
      final min = potential['min'];
      final max = potential['max'];
      final cur = potential['currency'] ?? _currency;
      final per = potential['period'] ?? 'month';
      if (min != null && max != null) return '$cur $min–$max/$per';
    }

    final est = t['estimated_earnings'];
    if (est != null) return '$_currency $est';
    return 'Varies';
  }

  Color get _categoryColor {
    switch (_category) {
      case 'freelance':  return AppColors.primary;
      case 'content':    return AppColors.accent;
      case 'digital':    return AppColors.gold;
      case 'gig':        return AppColors.success;
      case 'investment': return AppColors.info;
      default:           return AppColors.textMuted;
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _aiUnlocked = _isPremium;
    if (_isPremium) _loadAiGuidance();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // ── AI guidance loader ─────────────────────────────────────────────────────

  Future<void> _loadAiGuidance() async {
    if (_aiLoading) return;
    setState(() { _aiLoading = true; _aiError = false; });

    try {
      final steps   = _allSteps.take(5).join(', ');
      final earning = _earningsDisplay();
      final title   = t['title']    as String? ?? 'this task';
      final cat     = _category;
      final plat    = t['platform'] as String? ?? 'the relevant platforms';

      final result = await api.chat(
        message: '''
You are the RiseUp AI wealth mentor. Give me ultra-practical, detailed guidance for this specific income task.

Task: $title
Category: $cat
Platform: $plat
Earnings potential: $earning
Action steps: $steps

Your guidance must cover exactly these 5 areas — be specific, not generic:

**1. FASTEST PATH TO FIRST INCOME (24–48 hours)**
What exactly do I do right now today? Give me the single most important first action.

**2. WINNING SCRIPT / TEMPLATE**
Give me exact words I can copy-paste — a pitch, cold message, post caption, or email subject line that works for this task.

**3. THREE MISTAKES THAT KILL EARNINGS**
Real pitfalls specific to $title that beginners make. How to avoid each one.

**4. HOW TO FIND YOUR FIRST CLIENT / CUSTOMER**
Step-by-step for $plat. Where to look, what to search, how to filter.

**5. INCOME MILESTONES**
Realistic numbers: Week 1 target, Month 1 target, Month 3 target in $_currency.

Be direct. Use numbers. No fluff. Format with bold headers for each section.
''',
        mode: 'task_guidance',
      );

      // Handle multiple possible response shapes from backend
      final content = result['message']   as String? ??
                      result['response']  as String? ??
                      result['content']   as String? ??
                      (() {
                        final d = result['data'];
                        return d is Map ? d['message'] as String? : null;
                      })() ??
                      'Guidance loaded. Tap refresh to try again if text is missing.';

      if (mounted) {
        setState(() {
          _aiGuidance = content;
          _aiLoading  = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _aiLoading = false;
          _aiError   = true;
        });
      }
    }
  }

  // ── Rewarded ad gate ───────────────────────────────────────────────────────

  Future<void> _watchAdForGuidance() async {
    final ok = await adService.showRewardedAd(
      featureKey: 'task_ai_guidance',
      onRewarded: () {
        if (mounted) {
          setState(() => _aiUnlocked = true);
          _loadAiGuidance();
        }
      },
      onDismissed: () {},
    );

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Ad not available right now. Try again shortly.'),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── URL launcher ───────────────────────────────────────────────────────────

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open $url'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── CTA helpers ────────────────────────────────────────────────────────────

  void _handleAccept() {
    Navigator.pop(context);
    widget.onAccept?.call();
  }

  void _handleComplete() {
    Navigator.pop(context);
    widget.onComplete?.call();
  }

  void _handleSkip() {
    Navigator.pop(context);
    widget.onSkip?.call();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final mq         = MediaQuery.of(context);
    final sheetHeight = mq.size.height * 0.94;
    // CTA footer height: 80 + safe area bottom
    final footerH    = 80.0 + mq.padding.bottom;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: AppColors.bgDark,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(
        children: [
          // ── Scrollable content ─────────────────────────────────────────
          SingleChildScrollView(
            controller: _scroll,
            padding: EdgeInsets.only(bottom: footerH + 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHandle(),
                _buildHeroHeader(),
                _buildStatsRow(),
                if (t['why_its_perfect'] != null) _buildWhyPerfect(),
                _buildDescription(),
                if (_allSteps.isNotEmpty) _buildSteps(),

                // ── Inline banner for free users (between steps & resources)
                if (!_isPremium) _buildMidAd(),

                if (_platforms.isNotEmpty) _buildPlatforms(),
                _buildLearningResources(),
                _buildCommunities(),
                _buildAiGuidanceSection(),

                const SizedBox(height: 8),
              ],
            ),
          ),

          // ── Sticky CTA footer ──────────────────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: _buildCTAFooter(footerH),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section builders
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHandle() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Category + difficulty badges
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _categoryColor.withOpacity(0.15),
                borderRadius: AppRadius.pill,
              ),
              child: Text(
                _category.toUpperCase(),
                style: AppTextStyles.caption.copyWith(
                  color: _categoryColor, fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            if (t['difficulty'] != null) ...[
              const SizedBox(width: 8),
              _difficultyBadge(t['difficulty'] as String),
            ],
            const Spacer(),
            // Success probability
            if (t['success_probability'] != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: AppRadius.sm,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.trending_up_rounded,
                      size: 11, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text(
                    '${_probabilityLabel(t['success_probability'] as String?)} success',
                    style: AppTextStyles.caption,
                  ),
                ]),
              ),
          ]),

          const SizedBox(height: 14),

          // Task title
          Text(
            t['title'] as String? ?? 'Income Task',
            style: AppTextStyles.h3.copyWith(fontSize: 22, height: 1.25),
          ),

          const SizedBox(height: 6),

          // Capital stage badge if present
          if (t['capital_stage'] != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.account_balance_wallet_rounded,
                    size: 12, color: AppColors.gold),
                const SizedBox(width: 5),
                Text(
                  'Capital tier: ${t['capital_stage']}',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.gold),
                ),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.bgSurface),
      ),
      child: Row(
        children: [
          _StatItem(
            icon: Icons.attach_money_rounded,
            iconColor: AppColors.success,
            label: 'Earnings',
            value: _earningsDisplay(),
          ),
          _Divider(),
          _StatItem(
            icon: Icons.access_time_rounded,
            iconColor: AppColors.info,
            label: 'First income',
            value: t['time_to_first_earning'] as String? ?? 'Varies',
          ),
          if (t['startup_cost'] != null) ...[
            _Divider(),
            _StatItem(
              icon: Icons.account_balance_wallet_rounded,
              iconColor: AppColors.warning,
              label: 'Startup cost',
              value: t['startup_cost'] as String,
            ),
          ],
        ],
      ),
    ).animate().fadeIn(delay: 100.ms);
  }

  Widget _buildWhyPerfect() {
    return _Section(
      title: '✨ Why This Task Is Perfect For You',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: AppRadius.md,
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Text(
          t['why_its_perfect'] as String,
          style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary, height: 1.6),
        ),
      ),
    );
  }

  Widget _buildDescription() {
    return _Section(
      title: '📋 What You\'ll Do',
      child: Text(
        t['description'] as String? ?? '',
        style: AppTextStyles.body.copyWith(height: 1.7),
      ),
    );
  }

  Widget _buildSteps() {
    final steps     = _allSteps;
    final showAll   = _stepsExpanded || steps.length <= 4;
    final displayed = showAll ? steps : steps.take(4).toList();

    return _Section(
      title: '🗺️ Your Action Plan (${steps.length} steps)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...displayed.asMap().entries.map((e) => _StepTile(
            number: e.key + 1,
            text:   e.value,
            isLast: e.key == displayed.length - 1,
          )),

          if (steps.length > 4) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: () => setState(() => _stepsExpanded = !_stepsExpanded),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.bgSurface,
                  borderRadius: AppRadius.md,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _stepsExpanded
                          ? 'Show fewer steps'
                          : 'Show all ${steps.length} steps',
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.primary),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _stepsExpanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: AppColors.primary, size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ],

          // First 24h action callout
          if (t['first_24h_action'] != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                borderRadius: AppRadius.md,
                border: Border.all(
                    color: AppColors.success.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('⚡ Start RIGHT NOW',
                      style: AppTextStyles.label.copyWith(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(
                    t['first_24h_action'] as String,
                    style: AppTextStyles.body.copyWith(
                        color: AppColors.textSecondary, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMidAd() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('Sponsored',
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textMuted)),
              ),
            ]),
          ),
          Center(child: BannerAdWidget()),
        ],
      ),
    );
  }

  Widget _buildPlatforms() {
    return _Section(
      title: '🔗 Platforms & Tools',
      child: Wrap(
        spacing: 8, runSpacing: 8,
        children: _platforms.map((p) {
          return GestureDetector(
            onTap: () => _launch(p['url']!),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgCard,
                borderRadius: AppRadius.pill,
                border: Border.all(color: AppColors.bgSurface),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Iconsax.global, size: 12,
                    color: AppColors.primary),
                const SizedBox(width: 6),
                Text(p['name']!,
                    style: AppTextStyles.label
                        .copyWith(color: AppColors.textSecondary)),
                const SizedBox(width: 4),
                const Icon(Icons.open_in_new_rounded,
                    size: 10, color: AppColors.textMuted),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLearningResources() {
    final resources = kLearningResources[_category] ??
                      kLearningResources['default']!;

    return _Section(
      title: '📚 Learn & Level Up',
      subtitle: 'Free resources curated for this task',
      child: Column(
        children: resources.map((r) {
          return _ResourceTile(
            emoji:    r['emoji']!,
            title:    r['title']!,
            url:      r['url']!,
            onTap:    () => _launch(r['url']!),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildCommunities() {
    final communities = kCommunities[_category] ??
                        kCommunities['default']!;

    return _Section(
      title: '👥 Communities & Contacts',
      subtitle: 'Connect with people already doing this',
      child: Column(
        children: communities.map((c) {
          return _CommunityTile(
            name:  c['name']!,
            size:  c['size']!,
            type:  c['type']!,
            url:   c['url']!,
            onTap: () => _launch(c['url']!),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAiGuidanceSection() {
    return _Section(
      title: '🤖 AI Mentor Guidance',
      subtitle: _isPremium
          ? 'Personalised by RiseUp AI for this task'
          : 'Watch a short ad to unlock AI mentor advice',
      child: _buildAiGuidanceContent(),
    );
  }

  Widget _buildAiGuidanceContent() {
    // ── Locked (free user, not yet watched ad) ─────────────────────────────
    if (!_aiUnlocked) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.bgSurface),
        ),
        child: Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('🔒', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(height: 12),
          Text('AI Mentor Guidance',
              style: AppTextStyles.h4, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(
            'Get a personalised script, proven strategies, and income milestones for this specific task — generated by your RiseUp AI mentor.',
            style: AppTextStyles.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Rewarded ad CTA
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _watchAdForGuidance,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.md),
                elevation: 0,
              ),
              icon: const Icon(Icons.play_circle_fill_rounded,
                  color: Colors.white, size: 20),
              label: Text('Watch Ad — Unlock Free',
                  style: AppTextStyles.label
                      .copyWith(color: Colors.white,
                          fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 8),
          // Premium upsell
          GestureDetector(
            onTap: () {
              // context.go('/premium');
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: AppRadius.md,
              ),
              child: Center(
                child: Text('⭐ Go Premium — Always Unlocked',
                    style: AppTextStyles.label
                        .copyWith(color: Colors.white,
                            fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ]),
      );
    }

    // ── Loading ────────────────────────────────────────────────────────────
    if (_aiLoading) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.bgSurface),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(
              color: AppColors.primary, strokeWidth: 2.5),
          const SizedBox(height: 14),
          Text('Your AI mentor is crafting personalised guidance…',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center),
        ]),
      );
    }

    // ── Error ──────────────────────────────────────────────────────────────
    if (_aiError || _aiGuidance == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.08),
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.error.withOpacity(0.3)),
        ),
        child: Column(children: [
          Text('Could not load AI guidance.',
              style: AppTextStyles.body
                  .copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loadAiGuidance,
            icon: const Icon(Icons.refresh_rounded,
                color: AppColors.primary, size: 16),
            label: Text('Retry',
                style: AppTextStyles.label
                    .copyWith(color: AppColors.primary)),
          ),
        ]),
      );
    }

    // ── Loaded guidance ────────────────────────────────────────────────────
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(
            color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // AI badge
          Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent]),
                borderRadius: AppRadius.pill,
              ),
              child: Text('RiseUp AI',
                  style: AppTextStyles.caption.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text('Personalised for you',
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Clipboard.setData(
                    ClipboardData(text: _aiGuidance!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Guidance copied!'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              child: const Icon(Icons.copy_rounded,
                  size: 16, color: AppColors.textMuted),
            ),
          ]),
          const SizedBox(height: 14),
          // Parsed guidance — render bold headers, normal body
          _AiGuidanceText(text: _aiGuidance!),
          const SizedBox(height: 8),
          // Refresh button
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _loadAiGuidance,
              icon: const Icon(Icons.refresh_rounded,
                  size: 14, color: AppColors.textMuted),
              label: Text('Refresh',
                  style: AppTextStyles.caption
                      .copyWith(color: AppColors.textMuted)),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildCTAFooter(double height) {
    final mq     = MediaQuery.of(context);
    final status = t['status'] as String? ?? '';

    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, mq.padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppColors.bgDark,
        border: const Border(
            top: BorderSide(color: AppColors.bgSurface)),
      ),
      child: Row(children: [
        // Skip — only for suggested
        if (widget.onSkip != null) ...[
          Expanded(
            flex: 1,
            child: OutlinedButton(
              onPressed: _handleSkip,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppColors.bgSurface),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.md),
              ),
              child: const Text('Skip'),
            ),
          ),
          const SizedBox(width: 10),
        ],

        // Accept — suggested
        if (widget.onAccept != null)
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _handleAccept,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.md),
                elevation: 0,
              ),
              icon: const Icon(Icons.flash_on_rounded,
                  color: Colors.white, size: 18),
              label: Text('Accept Task',
                  style: AppTextStyles.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),

        // Complete — active
        if (widget.onComplete != null)
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _handleComplete,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.success,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.md),
                elevation: 0,
              ),
              icon: const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 18),
              label: Text('Mark Complete',
                  style: AppTextStyles.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700)),
            ),
          ),

        // Completed state — no action
        if (widget.onAccept == null &&
            widget.onComplete == null)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.12),
                borderRadius: AppRadius.md,
                border: Border.all(
                    color: AppColors.success.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  Text('Task Completed',
                      style: AppTextStyles.label
                          .copyWith(color: AppColors.success,
                              fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  // ─── Small helpers ─────────────────────────────────────────────────────────

  Widget _difficultyBadge(String d) {
    final map = {
      'easy':   ('🟢 Easy',   AppColors.success),
      'medium': ('🟡 Medium', AppColors.warning),
      'hard':   ('🔴 Hard',   AppColors.error),
    };
    final (label, color) = map[d] ?? (d, AppColors.textMuted);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: AppRadius.pill,
      ),
      child: Text(label,
          style: AppTextStyles.caption
              .copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }

  String _probabilityLabel(String? p) {
    switch (p) {
      case 'high':   return 'High';
      case 'medium': return 'Medium';
      case 'low':    return 'Low';
      default:       return p ?? '';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Reusable sub-widgets
// ═══════════════════════════════════════════════════════════════════════════════

/// Standard section wrapper with title + optional subtitle
class _Section extends StatelessWidget {
  final String  title;
  final String? subtitle;
  final Widget  child;

  const _Section({
    required this.title,
    this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.h4.copyWith(fontSize: 16)),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(subtitle!,
                style: AppTextStyles.caption
                    .copyWith(color: AppColors.textMuted)),
          ],
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Stats row item
class _StatItem extends StatelessWidget {
  final IconData icon;
  final Color    iconColor;
  final String   label;
  final String   value;

  const _StatItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 12, color: iconColor),
            const SizedBox(width: 4),
            Text(label, style: AppTextStyles.caption),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: AppTextStyles.label.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

/// Vertical divider for stats row
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1, height: 36,
      margin: const EdgeInsets.symmetric(horizontal: 12),
      color: AppColors.bgSurface,
    );
  }
}

/// Numbered step tile with connecting line
class _StepTile extends StatelessWidget {
  final int    number;
  final String text;
  final bool   isLast;

  const _StepTile({
    required this.number,
    required this.text,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Number + connector
        Column(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              shape: BoxShape.circle,
              border: Border.all(
                  color: AppColors.primary.withOpacity(0.4)),
            ),
            child: Center(
              child: Text('$number',
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w800,
                  )),
            ),
          ),
          if (!isLast)
            Container(
              width: 2, height: 20,
              color: AppColors.bgSurface,
            ),
        ]),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 8),
            child: Text(text,
                style: AppTextStyles.body
                    .copyWith(height: 1.55)),
          ),
        ),
      ],
    );
  }
}

/// Tappable learning resource tile
class _ResourceTile extends StatelessWidget {
  final String   emoji;
  final String   title;
  final String   url;
  final VoidCallback onTap;

  const _ResourceTile({
    required this.emoji,
    required this.title,
    required this.url,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.md,
          border: Border.all(color: AppColors.bgSurface),
        ),
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(child: Text(title,
              style: AppTextStyles.label
                  .copyWith(color: AppColors.textSecondary))),
          const Icon(Icons.open_in_new_rounded,
              size: 14, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

/// Community tile with member count badge
class _CommunityTile extends StatelessWidget {
  final String   name;
  final String   size;
  final String   type;
  final String   url;
  final VoidCallback onTap;

  const _CommunityTile({
    required this.name,
    required this.size,
    required this.type,
    required this.url,
    required this.onTap,
  });

  Color _typeColor() {
    switch (type) {
      case 'Reddit':   return const Color(0xFFFF4500);
      case 'Facebook': return const Color(0xFF1877F2);
      case 'Forum':    return AppColors.primary;
      default:         return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.md,
          border: Border.all(color: AppColors.bgSurface),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: _typeColor().withOpacity(0.12),
              borderRadius: AppRadius.sm,
            ),
            child: Text(type,
                style: AppTextStyles.caption
                    .copyWith(color: _typeColor(),
                        fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(name,
              style: AppTextStyles.label
                  .copyWith(color: AppColors.textSecondary))),
          Text(size,
              style: AppTextStyles.caption
                  .copyWith(color: AppColors.success,
                      fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          const Icon(Icons.open_in_new_rounded,
              size: 12, color: AppColors.textMuted),
        ]),
      ),
    );
  }
}

/// Renders AI guidance text with simple bold-header parsing
/// Handles **Header** markdown from the AI response
class _AiGuidanceText extends StatelessWidget {
  final String text;
  const _AiGuidanceText({required this.text});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        if (line.trim().isEmpty) return const SizedBox(height: 6);

        // Bold header: **some text** at start of line
        if (line.trim().startsWith('**') && line.trim().endsWith('**')) {
          final content = line.trim()
              .replaceAll(RegExp(r'^\*\*'), '')
              .replaceAll(RegExp(r'\*\*$'), '');
          return Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 4),
            child: Text(content,
                style: AppTextStyles.label.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                )),
          );
        }

        // Inline bold: strip ** markers for mixed lines
        final cleaned = line.replaceAll('**', '');
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(cleaned,
              style: AppTextStyles.body.copyWith(
                  height: 1.65,
                  color: AppColors.textSecondary)),
        );
      }).toList(),
    );
  }
}
