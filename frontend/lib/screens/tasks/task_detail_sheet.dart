// frontend/lib/screens/tasks/task_detail_sheet.dart
// v2.0 — Full Light/Dark Theme Adaptive
//
// Every color is now derived from Theme.of(context).brightness at build time.
// The sheet passes theme colors down to every child widget.
// No AppColors.bgDark / bgCard / bgSurface hardcoded anywhere.

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
// Resource maps (unchanged)
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, List<Map<String, String>>> kLearningResources = {
  'freelance': [
    {'title': 'Upwork Success Handbook',      'url': 'https://www.upwork.com/resources/beginners-guide-to-upwork', 'emoji': '📗'},
    {'title': 'Fiverr Learn',                 'url': 'https://learn.fiverr.com',                                   'emoji': '🎓'},
    {'title': 'Freelancing 101 (Coursera)',   'url': 'https://www.coursera.org/courses?query=freelancing',         'emoji': '🏫'},
    {'title': 'How to Get Your First Client', 'url': 'https://www.youtube.com/results?search_query=how+to+get+first+freelance+client+2024', 'emoji': '▶️'},
  ],
  'content': [
    {'title': 'YouTube Creator Academy',    'url': 'https://creatoracademy.youtube.com',                         'emoji': '▶️'},
    {'title': 'HubSpot Content Marketing', 'url': 'https://academy.hubspot.com/courses/content-marketing',      'emoji': '📝'},
    {'title': 'Canva Design School',        'url': 'https://www.canva.com/designschool',                         'emoji': '🎨'},
    {'title': 'TikTok Creator Portal',      'url': 'https://www.tiktok.com/creators/creator-portal',             'emoji': '🎵'},
  ],
  'digital': [
    {'title': 'Google Digital Garage',        'url': 'https://learndigital.withgoogle.com',                  'emoji': '🔍'},
    {'title': 'Meta Blueprint (Free)',         'url': 'https://www.facebook.com/business/learn',              'emoji': '📱'},
    {'title': 'Shopify Free Courses',         'url': 'https://www.shopify.com/learn',                        'emoji': '🛍️'},
    {'title': 'Semrush Academy',              'url': 'https://www.semrush.com/academy',                      'emoji': '📊'},
  ],
  'gig': [
    {'title': 'TaskRabbit Pro Guide',     'url': 'https://support.taskrabbit.com/hc/en-us',                              'emoji': '🔧'},
    {'title': 'Gig Economy Success Tips', 'url': 'https://www.youtube.com/results?search_query=gig+economy+tips+2024',   'emoji': '💼'},
    {'title': 'Side Hustle Nation',       'url': 'https://www.sidehustlenation.com/ideas',                               'emoji': '🚀'},
    {'title': 'Rideshare Dashboard',      'url': 'https://www.ridesharedashboard.com',                                   'emoji': '🚗'},
  ],
  'investment': [
    {'title': 'Investopedia Academy',         'url': 'https://www.investopedia.com/financial-advisor-4427709',  'emoji': '📈'},
    {'title': 'Khan Academy Finance',         'url': 'https://www.khanacademy.org/economics-finance-domain',    'emoji': '🏦'},
    {'title': 'CFA Institute Free Resources', 'url': 'https://www.cfainstitute.org/en/programs',                'emoji': '💎'},
    {'title': 'Morningstar Investing Guide',  'url': 'https://www.morningstar.com/start-investing',             'emoji': '⭐'},
  ],
  'default': [
    {'title': 'Udemy Free Courses',            'url': 'https://www.udemy.com/courses/free',                                              'emoji': '🎓'},
    {'title': 'Google Free Certifications',    'url': 'https://grow.google/certificates',                                                'emoji': '🔍'},
    {'title': 'LinkedIn Learning (1 mo free)', 'url': 'https://www.linkedin.com/learning',                                               'emoji': '💼'},
    {'title': 'YouTube How-To Guides',         'url': 'https://www.youtube.com/results?search_query=how+to+make+money+online+2024',      'emoji': '▶️'},
  ],
};

const Map<String, List<Map<String, String>>> kCommunities = {
  'freelance': [
    {'name': 'r/freelance',       'url': 'https://reddit.com/r/freelance',         'size': '450K+', 'type': 'Reddit'},
    {'name': 'r/forhire',         'url': 'https://reddit.com/r/forhire',           'size': '150K+', 'type': 'Reddit'},
    {'name': 'Upwork Community',  'url': 'https://community.upwork.com',           'size': '1M+',   'type': 'Forum'},
    {'name': 'Fiverr Community',  'url': 'https://community.fiverr.com',           'size': '500K+', 'type': 'Forum'},
  ],
  'content': [
    {'name': 'r/NewTubers',       'url': 'https://reddit.com/r/NewTubers',         'size': '300K+', 'type': 'Reddit'},
    {'name': 'r/ContentCreators', 'url': 'https://reddit.com/r/content_creators',  'size': '80K+',  'type': 'Reddit'},
    {'name': 'Creator Economy',   'url': 'https://creatoreconomy.so/community',    'size': '25K+',  'type': 'Community'},
    {'name': 'IndieHackers Media','url': 'https://www.indiehackers.com/group/content-creators', 'size': '30K+', 'type': 'Forum'},
  ],
  'digital': [
    {'name': 'r/Entrepreneur',    'url': 'https://reddit.com/r/Entrepreneur',      'size': '1.2M+', 'type': 'Reddit'},
    {'name': 'IndieHackers',      'url': 'https://www.indiehackers.com',           'size': '100K+', 'type': 'Forum'},
    {'name': 'r/ecommerce',       'url': 'https://reddit.com/r/ecommerce',         'size': '200K+', 'type': 'Reddit'},
    {'name': 'Digital Nomad Forum','url': 'https://reddit.com/r/digitalnomad',     'size': '500K+', 'type': 'Reddit'},
  ],
  'gig': [
    {'name': 'r/gigwork',          'url': 'https://reddit.com/r/gigwork',                   'size': '45K+',  'type': 'Reddit'},
    {'name': 'Side Hustle Nation', 'url': 'https://www.facebook.com/groups/sidehustlenation','size': '100K+', 'type': 'Facebook'},
    {'name': 'r/SideHustle',       'url': 'https://reddit.com/r/SideHustle',                'size': '60K+',  'type': 'Reddit'},
    {'name': 'Gig Workers Alliance','url': 'https://gigworkersalliance.com',                 'size': '20K+',  'type': 'Org'},
  ],
  'default': [
    {'name': 'r/Entrepreneur',   'url': 'https://reddit.com/r/Entrepreneur',   'size': '1.2M+', 'type': 'Reddit'},
    {'name': 'r/passive_income', 'url': 'https://reddit.com/r/passive_income', 'size': '350K+', 'type': 'Reddit'},
    {'name': 'IndieHackers',     'url': 'https://www.indiehackers.com',        'size': '100K+', 'type': 'Forum'},
    {'name': 'r/SideHustle',     'url': 'https://reddit.com/r/SideHustle',     'size': '60K+',  'type': 'Reddit'},
  ],
};

const Map<String, String> kPlatformUrls = {
  'upwork':     'https://www.upwork.com',     'fiverr':    'https://www.fiverr.com',
  'toptal':     'https://www.toptal.com',     'freelancer':'https://www.freelancer.com',
  'contra':     'https://contra.com',          'jiji':      'https://jiji.ng',
  'piggyvest':  'https://piggyvest.com',       'cowrywise': 'https://cowrywise.com',
  'shopee':     'https://shopee.com',          'lazada':    'https://www.lazada.com',
  'etsy':       'https://www.etsy.com',        'amazon':    'https://www.amazon.com',
  'youtube':    'https://www.youtube.com',     'tiktok':    'https://www.tiktok.com',
  'instagram':  'https://www.instagram.com',  'linkedin':  'https://www.linkedin.com',
  'taskrabbit': 'https://www.taskrabbit.com', 'airtasker': 'https://www.airtasker.com',
  'doordash':   'https://www.doordash.com',   'uber':      'https://www.uber.com',
  'gojek':      'https://www.gojek.com',      'shopify':   'https://www.shopify.com',
  'gumroad':    'https://gumroad.com',         'teachable': 'https://teachable.com',
  'substack':   'https://substack.com',        'patreon':   'https://www.patreon.com',
};

// =============================================================================
// TaskDetailSheet
// =============================================================================
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

  static Future<void> show(
    BuildContext context, {
    required Map        task,
    required bool       isPremium,
    VoidCallback?       onAccept,
    VoidCallback?       onComplete,
    VoidCallback?       onSkip,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TaskDetailSheet(
        task: task, isPremium: isPremium,
        onAccept: onAccept, onComplete: onComplete, onSkip: onSkip,
      ),
    );
  }

  @override
  State<TaskDetailSheet> createState() => _TaskDetailSheetState();
}

class _TaskDetailSheetState extends State<TaskDetailSheet> {
  String? _aiGuidance;
  bool    _aiLoading   = false;
  bool    _aiUnlocked  = false;
  bool    _aiError     = false;
  bool    _stepsExpanded = false;
  final ScrollController _scroll = ScrollController();

  // ── Theme colors — derived in build, passed down ──────────────────────────
  late bool  _dark;
  late Color _bg;        // sheet background
  late Color _card;      // card surfaces
  late Color _border;    // borders / dividers
  late Color _txt;       // primary text
  late Color _sub;       // secondary / muted text
  late Color _surface;   // inner chip/info surfaces

  Map  get t          => widget.task;
  bool get _isPremium => widget.isPremium;
  String get _category => t['category'] as String? ?? 'default';
  String get _currency => t['currency'] as String? ?? 'NGN';

  List<String> get _allSteps {
    final a = t['action_steps'];
    if (a is List && a.isNotEmpty) return a.map((s) => s.toString()).toList();
    final s = t['steps'];
    if (s is List && s.isNotEmpty) return s.map((s) => s.toString()).toList();
    return [];
  }

  List<Map<String, String>> get _platforms {
    final result = <Map<String, String>>[];
    for (final list in [t['local_platforms'], t['global_platforms']]) {
      if (list is List) {
        for (final p in list) {
          final name = p.toString().toLowerCase().trim();
          result.add({'name': p.toString(), 'url': kPlatformUrls[name] ?? 'https://www.google.com/search?q=$name+platform'});
        }
      }
    }
    final platform = t['platform'] as String?;
    if (platform != null && result.isEmpty) {
      final lower = platform.toLowerCase().trim();
      result.add({'name': platform, 'url': kPlatformUrls[lower] ?? 'https://www.google.com/search?q=$lower'});
    }
    final seen = <String>{};
    return result.where((p) => seen.add(p['name']!)).toList();
  }

  String _earningsDisplay() {
    final actual = t['actual_earnings'];
    if (actual != null && (actual as num) > 0) return 'Earned: $_currency $actual';
    final potential = t['earning_potential'];
    if (potential is Map) {
      final min = potential['min']; final max = potential['max'];
      final cur = potential['currency'] ?? _currency; final per = potential['period'] ?? 'month';
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

  @override
  void initState() {
    super.initState();
    _aiUnlocked = _isPremium;
    if (_isPremium) _loadAiGuidance();
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

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

      final content = result['message']  as String? ??
                      result['response'] as String? ??
                      result['content']  as String? ??
                      (() { final d = result['data']; return d is Map ? d['message'] as String? : null; })() ??
                      'Guidance loaded. Tap refresh to try again if text is missing.';

      if (mounted) setState(() { _aiGuidance = content; _aiLoading = false; });
    } catch (_) {
      if (mounted) setState(() { _aiLoading = false; _aiError = true; });
    }
  }

  Future<void> _watchAdForGuidance() async {
    final ok = await adService.showRewardedAd(
      featureKey: 'task_ai_guidance',
      onRewarded: () {
        if (!mounted) return;
        setState(() => _aiUnlocked = true);
        _loadAiGuidance();
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

  void _handleAccept()   { Navigator.pop(context); widget.onAccept?.call();   }
  void _handleComplete() { Navigator.pop(context); widget.onComplete?.call(); }
  void _handleSkip()     { Navigator.pop(context); widget.onSkip?.call();     }

  // ── Build ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Derive theme colors once per build
    _dark    = Theme.of(context).brightness == Brightness.dark;
    _bg      = _dark ? const Color(0xFF0A0A0A) : Colors.white;
    _card    = _dark ? AppColors.bgCard        : Colors.white;
    _border  = _dark ? AppColors.bgSurface     : Colors.grey.shade200;
    _txt     = _dark ? Colors.white            : Colors.black87;
    _sub     = _dark ? Colors.white.withOpacity(0.54) : Colors.black45;
    _surface = _dark ? AppColors.bgSurface     : Colors.grey.shade100;

    final mq        = MediaQuery.of(context);
    final sheetH    = mq.size.height * 0.94;
    final footerH   = 80.0 + mq.padding.bottom;

    return Container(
      height: sheetH,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Stack(children: [
        // ── Scrollable content ───────────────────────────────────────────
        SingleChildScrollView(
          controller: _scroll,
          padding: EdgeInsets.only(bottom: footerH + 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHandle(),
            _buildHeroHeader(),
            _buildStatsRow(),
            if (t['why_its_perfect'] != null) _buildWhyPerfect(),
            _buildDescription(),
            if (_allSteps.isNotEmpty) _buildSteps(),
            if (!_isPremium) _buildMidAd(),
            if (_platforms.isNotEmpty) _buildPlatforms(),
            _buildLearningResources(),
            _buildCommunities(),
            _buildAiGuidanceSection(),
            const SizedBox(height: 8),
          ]),
        ),
        // ── Sticky footer ────────────────────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: _buildCTAFooter(footerH),
        ),
      ]),
    );
  }

  // ── Section builders ────────────────────────────────────────────────────────

  Widget _buildHandle() => Center(child: Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Container(width: 36, height: 4, decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(4))),
  ));

  Widget _buildHeroHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: _categoryColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
          child: Text(_category.toUpperCase(), style: TextStyle(fontSize: 10, color: _categoryColor, fontWeight: FontWeight.w800, letterSpacing: 0.8)),
        ),
        if (t['difficulty'] != null) ...[
          const SizedBox(width: 8),
          _difficultyBadge(t['difficulty'] as String),
        ],
        const Spacer(),
        if (t['success_probability'] != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(6)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.trending_up_rounded, size: 11, color: AppColors.success),
              const SizedBox(width: 4),
              Text('${_probabilityLabel(t['success_probability'] as String?)} success',
                  style: TextStyle(fontSize: 10, color: _sub)),
            ]),
          ),
      ]),
      const SizedBox(height: 14),
      Text(t['title'] as String? ?? 'Income Task', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: _txt, height: 1.25)),
      const SizedBox(height: 6),
      if (t['capital_stage'] != null)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(children: [
          const Icon(Icons.account_balance_wallet_rounded, size: 12, color: AppColors.gold),
          const SizedBox(width: 5),
          Text('Capital tier: ${t['capital_stage']}', style: const TextStyle(fontSize: 11, color: AppColors.gold)),
        ])),
    ]),
  );

  Widget _buildStatsRow() => Container(
    margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
    child: Row(children: [
      _StatItem(icon: Icons.attach_money_rounded, iconColor: AppColors.success, label: 'Earnings', value: _earningsDisplay(), textColor: _txt, subColor: _sub),
      _VertDivider(color: _border),
      _StatItem(icon: Icons.access_time_rounded, iconColor: AppColors.info, label: 'First income', value: t['time_to_first_earning'] as String? ?? 'Varies', textColor: _txt, subColor: _sub),
      if (t['startup_cost'] != null) ...[
        _VertDivider(color: _border),
        _StatItem(icon: Icons.account_balance_wallet_rounded, iconColor: AppColors.warning, label: 'Startup cost', value: t['startup_cost'] as String, textColor: _txt, subColor: _sub),
      ],
    ]),
  ).animate().fadeIn(delay: 100.ms);

  Widget _buildWhyPerfect() => _Section(
    title: '✨ Why This Task Is Perfect For You',
    textColor: _txt, subColor: _sub,
    child: Container(
      width: double.infinity, padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.2))),
      child: Text(t['why_its_perfect'] as String, style: TextStyle(fontSize: 14, color: _sub, height: 1.6)),
    ),
  );

  Widget _buildDescription() => _Section(
    title: '📋 What You\'ll Do',
    textColor: _txt, subColor: _sub,
    child: Text(t['description'] as String? ?? '', style: TextStyle(fontSize: 14, color: _txt, height: 1.7)),
  );

  Widget _buildSteps() {
    final steps     = _allSteps;
    final showAll   = _stepsExpanded || steps.length <= 4;
    final displayed = showAll ? steps : steps.take(4).toList();

    return _Section(
      title: '🗺️ Your Action Plan (${steps.length} steps)',
      textColor: _txt, subColor: _sub,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ...displayed.asMap().entries.map((e) => _StepTile(
          number: e.key + 1, text: e.value,
          isLast: e.key == displayed.length - 1,
          textColor: _txt, borderColor: _border,
        )),
        if (steps.length > 4) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _stepsExpanded = !_stepsExpanded),
            child: Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_stepsExpanded ? 'Show fewer steps' : 'Show all ${steps.length} steps',
                    style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Icon(_stepsExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, color: AppColors.primary, size: 18),
              ]),
            ),
          ),
        ],
        if (t['first_24h_action'] != null) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.success.withOpacity(0.3))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('⚡ Start RIGHT NOW', style: TextStyle(fontSize: 13, color: AppColors.success, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(t['first_24h_action'] as String, style: TextStyle(fontSize: 14, color: _sub, height: 1.5)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildMidAd() => Container(
    margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(padding: const EdgeInsets.only(bottom: 6), child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: _dark ? Colors.white10 : Colors.grey.shade100, borderRadius: BorderRadius.circular(4)),
        child: Text('Sponsored', style: TextStyle(fontSize: 10, color: _dark ? Colors.white38 : Colors.black38)),
      )),
      Center(child: BannerAdWidget()),
    ]),
  );

  Widget _buildPlatforms() => _Section(
    title: '🔗 Platforms & Tools',
    textColor: _txt, subColor: _sub,
    child: Wrap(spacing: 8, runSpacing: 8, children: _platforms.map((p) {
      return GestureDetector(
        onTap: () => _launch(p['url']!),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(20), border: Border.all(color: _border)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Iconsax.global, size: 12, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(p['name']!, style: TextStyle(fontSize: 13, color: _sub, fontWeight: FontWeight.w600)),
            const SizedBox(width: 4),
            Icon(Icons.open_in_new_rounded, size: 10, color: _sub),
          ]),
        ),
      );
    }).toList()),
  );

  Widget _buildLearningResources() {
    final resources = kLearningResources[_category] ?? kLearningResources['default']!;
    return _Section(
      title: '📚 Learn & Level Up',
      subtitle: 'Free resources curated for this task',
      textColor: _txt, subColor: _sub,
      child: Column(children: resources.map((r) => _ResourceTile(
        emoji: r['emoji']!, title: r['title']!, url: r['url']!,
        cardColor: _card, borderColor: _border, textColor: _sub,
        onTap: () => _launch(r['url']!),
      )).toList()),
    );
  }

  Widget _buildCommunities() {
    final communities = kCommunities[_category] ?? kCommunities['default']!;
    return _Section(
      title: '👥 Communities & Contacts',
      subtitle: 'Connect with people already doing this',
      textColor: _txt, subColor: _sub,
      child: Column(children: communities.map((c) => _CommunityTile(
        name: c['name']!, size: c['size']!, type: c['type']!, url: c['url']!,
        cardColor: _card, borderColor: _border, subColor: _sub,
        onTap: () => _launch(c['url']!),
      )).toList()),
    );
  }

  Widget _buildAiGuidanceSection() => _Section(
    title: '🤖 AI Mentor Guidance',
    subtitle: _isPremium ? 'Personalised by RiseUp AI for this task' : 'Watch a short ad to unlock AI mentor advice',
    textColor: _txt, subColor: _sub,
    child: _buildAiGuidanceContent(),
  );

  Widget _buildAiGuidanceContent() {
    // ── Locked ──────────────────────────────────────────────────────────────
    if (!_aiUnlocked) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
        child: Column(children: [
          Container(width: 56, height: 56, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle), child: const Center(child: Text('🔒', style: TextStyle(fontSize: 26)))),
          const SizedBox(height: 12),
          Text('AI Mentor Guidance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _txt), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Get a personalised script, proven strategies, and income milestones for this specific task — generated by your RiseUp AI mentor.', style: TextStyle(fontSize: 13, color: _sub, height: 1.5), textAlign: TextAlign.center),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            onPressed: _watchAdForGuidance,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            icon: const Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 20),
            label: const Text('Watch Ad — Unlock Free', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
          const SizedBox(height: 8),
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(12)),
            child: const Center(child: Text('⭐ Go Premium — Always Unlocked', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ),
        ]),
      );
    }

    // ── Loading ──────────────────────────────────────────────────────────────
    if (_aiLoading) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2.5),
          const SizedBox(height: 14),
          Text('Your AI mentor is crafting personalised guidance…', style: TextStyle(fontSize: 13, color: _sub), textAlign: TextAlign.center),
        ]),
      );
    }

    // ── Error ────────────────────────────────────────────────────────────────
    if (_aiError || _aiGuidance == null) {
      return Container(
        width: double.infinity, padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.error.withOpacity(0.08), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.error.withOpacity(0.3))),
        child: Column(children: [
          Text('Could not load AI guidance.', style: TextStyle(fontSize: 14, color: _sub)),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loadAiGuidance,
            icon: const Icon(Icons.refresh_rounded, color: AppColors.primary, size: 16),
            label: const Text('Retry', style: TextStyle(color: AppColors.primary)),
          ),
        ]),
      );
    }

    // ── Loaded ───────────────────────────────────────────────────────────────
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.primary.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(20)),
            child: const Text('RiseUp AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Text('Personalised for you', style: TextStyle(fontSize: 11, color: _sub)),
          const Spacer(),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _aiGuidance!));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Guidance copied!'), duration: Duration(seconds: 2)));
            },
            child: Icon(Icons.copy_rounded, size: 16, color: _sub),
          ),
        ]),
        const SizedBox(height: 14),
        _AiGuidanceText(text: _aiGuidance!, textColor: _txt, subColor: _sub),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: TextButton.icon(
          onPressed: _loadAiGuidance,
          icon: Icon(Icons.refresh_rounded, size: 14, color: _sub),
          label: Text('Refresh', style: TextStyle(fontSize: 11, color: _sub)),
        )),
      ]),
    ).animate().fadeIn(duration: 400.ms);
  }

  Widget _buildCTAFooter(double height) {
    final mq = MediaQuery.of(context);
    return Container(
      height: height,
      padding: EdgeInsets.fromLTRB(20, 12, 20, mq.padding.bottom + 12),
      decoration: BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(children: [
        if (widget.onSkip != null) ...[
          Expanded(flex: 1, child: OutlinedButton(
            onPressed: _handleSkip,
            style: OutlinedButton.styleFrom(side: BorderSide(color: _border), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: Text('Skip', style: TextStyle(color: _sub)),
          )),
          const SizedBox(width: 10),
        ],
        if (widget.onAccept != null)
          Expanded(flex: 2, child: ElevatedButton.icon(
            onPressed: _handleAccept,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            icon: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 18),
            label: const Text('Accept Task', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        if (widget.onComplete != null)
          Expanded(flex: 2, child: ElevatedButton.icon(
            onPressed: _handleComplete,
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), elevation: 0),
            icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            label: const Text('Mark Complete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          )),
        if (widget.onAccept == null && widget.onComplete == null)
          Expanded(child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.12), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.success.withOpacity(0.3))),
            child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_rounded, color: AppColors.success, size: 18),
              SizedBox(width: 8),
              Text('Task Completed', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w700)),
            ]),
          )),
      ]),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  Widget _difficultyBadge(String d) {
    final map = {
      'easy':   ('🟢 Easy',   AppColors.success),
      'medium': ('🟡 Medium', AppColors.warning),
      'hard':   ('🔴 Hard',   AppColors.error),
    };
    final (label, color) = map[d] ?? (d, _sub);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
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

// =============================================================================
// Reusable sub-widgets — all accept explicit color params
// =============================================================================
class _Section extends StatelessWidget {
  final String  title;
  final String? subtitle;
  final Widget  child;
  final Color   textColor, subColor;

  const _Section({
    required this.title,
    this.subtitle,
    required this.child,
    required this.textColor,
    required this.subColor,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
      if (subtitle != null) ...[
        const SizedBox(height: 3),
        Text(subtitle!, style: TextStyle(fontSize: 11, color: subColor)),
      ],
      const SizedBox(height: 12),
      child,
    ]),
  );
}

class _StatItem extends StatelessWidget {
  final IconData icon; final Color iconColor;
  final String label, value;
  final Color textColor, subColor;
  const _StatItem({required this.icon, required this.iconColor, required this.label, required this.value, required this.textColor, required this.subColor});
  @override
  Widget build(BuildContext context) => Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Icon(icon, size: 12, color: iconColor), const SizedBox(width: 4), Text(label, style: TextStyle(fontSize: 10, color: subColor))]),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textColor), maxLines: 2, overflow: TextOverflow.ellipsis),
  ]));
}

class _VertDivider extends StatelessWidget {
  final Color color;
  const _VertDivider({required this.color});
  @override
  Widget build(BuildContext context) => Container(width: 1, height: 36, margin: const EdgeInsets.symmetric(horizontal: 12), color: color);
}

class _StepTile extends StatelessWidget {
  final int number; final String text; final bool isLast;
  final Color textColor, borderColor;
  const _StepTile({required this.number, required this.text, this.isLast = false, required this.textColor, required this.borderColor});
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Column(children: [
      Container(width: 28, height: 28, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: AppColors.primary.withOpacity(0.4))), child: Center(child: Text('$number', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w800)))),
      if (!isLast) Container(width: 2, height: 20, color: borderColor),
    ]),
    const SizedBox(width: 12),
    Expanded(child: Padding(padding: const EdgeInsets.only(top: 5, bottom: 8), child: Text(text, style: TextStyle(fontSize: 14, color: textColor, height: 1.55)))),
  ]);
}

class _ResourceTile extends StatelessWidget {
  final String emoji, title, url; final VoidCallback onTap;
  final Color cardColor, borderColor, textColor;
  const _ResourceTile({required this.emoji, required this.title, required this.url, required this.onTap, required this.cardColor, required this.borderColor, required this.textColor});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 18)),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w600))),
        Icon(Icons.open_in_new_rounded, size: 14, color: textColor.withOpacity(0.4)),
      ]),
    ),
  );
}

class _CommunityTile extends StatelessWidget {
  final String name, size, type, url; final VoidCallback onTap;
  final Color cardColor, borderColor, subColor;
  const _CommunityTile({required this.name, required this.size, required this.type, required this.url, required this.onTap, required this.cardColor, required this.borderColor, required this.subColor});

  Color _typeColor() {
    switch (type) {
      case 'Reddit':   return const Color(0xFFFF4500);
      case 'Facebook': return const Color(0xFF1877F2);
      case 'Forum':    return AppColors.primary;
      default:         return AppColors.textMuted;
    }
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(color: cardColor, borderRadius: BorderRadius.circular(10), border: Border.all(color: borderColor)),
      child: Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3), decoration: BoxDecoration(color: _typeColor().withOpacity(0.12), borderRadius: BorderRadius.circular(6)), child: Text(type, style: TextStyle(fontSize: 10, color: _typeColor(), fontWeight: FontWeight.w700))),
        const SizedBox(width: 10),
        Expanded(child: Text(name, style: TextStyle(fontSize: 13, color: subColor, fontWeight: FontWeight.w600))),
        Text(size, style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
        const SizedBox(width: 6),
        Icon(Icons.open_in_new_rounded, size: 12, color: subColor.withOpacity(0.5)),
      ]),
    ),
  );
}

class _AiGuidanceText extends StatelessWidget {
  final String text; final Color textColor, subColor;
  const _AiGuidanceText({required this.text, required this.textColor, required this.subColor});
  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: lines.map((line) {
      if (line.trim().isEmpty) return const SizedBox(height: 6);
      if (line.trim().startsWith('**') && line.trim().endsWith('**')) {
        final content = line.trim().replaceAll(RegExp(r'^\*\*'), '').replaceAll(RegExp(r'\*\*$'), '');
        return Padding(padding: const EdgeInsets.only(top: 14, bottom: 4), child: Text(content, style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w800)));
      }
      final cleaned = line.replaceAll('**', '');
      return Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(cleaned, style: TextStyle(fontSize: 14, color: subColor, height: 1.65)));
    }).toList());
  }
}
