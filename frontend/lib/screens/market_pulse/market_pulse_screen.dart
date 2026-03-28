import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ads/ad_service_mobile.dart';

class MarketPulseScreen extends StatefulWidget {
  const MarketPulseScreen({super.key});

  @override
  State<MarketPulseScreen> createState() => _MarketPulseScreenState();
}

class _MarketPulseScreenState extends State<MarketPulseScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final AdService _adService = AdService();

  // ── Data ─────────────────────────────────────────────────
  Map<String, dynamic> _pulse = {};
  Map<String, dynamic> _arbitrage = {};
  Map<String, dynamic> _international = {};
  Map<String, dynamic> _local = {};
  Map<String, dynamic> _careerForecast = {};
  Map<String, dynamic> _entrepreneurial = {};
  Map<String, dynamic> _wealthStrategies = {};
  Map<String, dynamic> _personalGrowth = {};
  Map<String, dynamic> _scan = {};

  // ── Loading flags ─────────────────────────────────────────
  bool _loading = true;
  bool _scanning = false;
  bool _loadingInternational = false;
  bool _loadingLocal = false;
  bool _loadingCareer = false;
  bool _loadingEntrepreneurial = false;
  bool _loadingWealth = false;
  bool _loadingGrowth = false;

  // ── User state ────────────────────────────────────────────
  bool _isPremium = false;

  // ── Selection state ───────────────────────────────────────
  String _selectedSkill = '';
  String _selectedCapitalTier = 'bootstrap';
  String _selectedRiskTolerance = 'moderate';
  String _selectedTimeframe = 'all';

  // ── Tab indices ───────────────────────────────────────────
  static const int _kToday = 0;
  static const int _kGlobal = 1;
  static const int _kLocal = 2;
  static const int _kCareer = 3;
  static const int _kBusiness = 4;
  static const int _kWealth = 5;
  static const int _kGrowth = 6;
  static const int _kScan = 7;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
    _tabs.addListener(_onTabChanged);
    _load();
  }

  // ── Tab change: interstitial + proactive lazy loads ────────
  void _onTabChanged() {
    // Show interstitial when tab settles (free users only, frequency-capped inside ad service)
    if (!_tabs.indexIsChanging && !_isPremium) {
      _adService.showInterstitialIfReady();
    }

    // Trigger lazy loads immediately so the data is ready when animation finishes
    switch (_tabs.index) {
      case _kGlobal:
        _loadInternational();
        break;
      case _kLocal:
        _loadLocal();
        break;
      case _kCareer:
        _loadCareerForecast();
        break;
      case _kBusiness:
        _loadEntrepreneurial();
        break;
      case _kWealth:
        _loadWealthStrategies();
        break;
      case _kGrowth:
        _loadPersonalGrowth();
        break;
    }
  }

  // ── Initial load ──────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/pulse/today'),
        api.get('/pulse/arbitrage'),
      ]);
      if (!mounted) return;
      setState(() {
        _pulse = Map<String, dynamic>.from(results[0] ?? {});
        _arbitrage = Map<String, dynamic>.from(results[1] ?? {});
        _loading = false;
      });

      // Check premium from profile (non-blocking)
      _checkPremium();
    } catch (e) {
      debugPrint('Market Pulse Load Error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkPremium() async {
    try {
      final profile = await api.get('/auth/profile') as Map<String, dynamic>?;
      if (mounted && profile != null) {
        setState(() => _isPremium = profile['is_premium'] == true);
      }
    } catch (_) {
      // Non-critical — default to free
    }
  }

  // ── Lazy loaders ──────────────────────────────────────────

  Future<void> _loadInternational() async {
    if (_international.isNotEmpty || _loadingInternational) return;
    setState(() => _loadingInternational = true);
    try {
      final data = await api.get('/pulse/international');
      if (mounted) {
        setState(() {
          _international = Map<String, dynamic>.from(data ?? {});
          _loadingInternational = false;
        });
      }
    } catch (e) {
      debugPrint('International load error: $e');
      if (mounted) setState(() => _loadingInternational = false);
    }
  }

  Future<void> _loadLocal() async {
    if (_local.isNotEmpty || _loadingLocal) return;
    setState(() => _loadingLocal = true);
    try {
      final data = await api.get('/pulse/local');
      if (mounted) {
        setState(() {
          _local = Map<String, dynamic>.from(data ?? {});
          _loadingLocal = false;
        });
      }
    } catch (e) {
      debugPrint('Local load error: $e');
      if (mounted) setState(() => _loadingLocal = false);
    }
  }

  Future<void> _loadCareerForecast() async {
    if (_careerForecast.isNotEmpty || _loadingCareer) return;
    setState(() => _loadingCareer = true);
    try {
      final data = await api.get('/pulse/career-forecast',
          queryParams: {'timeframe': _selectedTimeframe});
      if (mounted) {
        setState(() {
          _careerForecast = Map<String, dynamic>.from(data ?? {});
          _loadingCareer = false;
        });
      }
    } catch (e) {
      debugPrint('Career forecast error: $e');
      if (mounted) setState(() => _loadingCareer = false);
    }
  }

  Future<void> _loadEntrepreneurial() async {
    if (_entrepreneurial.isNotEmpty || _loadingEntrepreneurial) return;
    setState(() => _loadingEntrepreneurial = true);
    try {
      final data = await api.get('/pulse/entrepreneurial-opportunities',
          queryParams: {'capital_tier': _selectedCapitalTier});
      if (mounted) {
        setState(() {
          _entrepreneurial = Map<String, dynamic>.from(data ?? {});
          _loadingEntrepreneurial = false;
        });
      }
    } catch (e) {
      debugPrint('Entrepreneurial error: $e');
      if (mounted) setState(() => _loadingEntrepreneurial = false);
    }
  }

  Future<void> _loadWealthStrategies() async {
    if (_wealthStrategies.isNotEmpty || _loadingWealth) return;
    setState(() => _loadingWealth = true);
    try {
      final data = await api.get('/pulse/wealth-strategies',
          queryParams: {'risk_tolerance': _selectedRiskTolerance});
      if (mounted) {
        setState(() {
          _wealthStrategies = Map<String, dynamic>.from(data ?? {});
          _loadingWealth = false;
        });
      }
    } catch (e) {
      debugPrint('Wealth strategies error: $e');
      if (mounted) setState(() => _loadingWealth = false);
    }
  }

  Future<void> _loadPersonalGrowth() async {
    if (_personalGrowth.isNotEmpty || _loadingGrowth) return;
    setState(() => _loadingGrowth = true);
    try {
      final data = await api.get('/pulse/personal-growth');
      if (mounted) {
        setState(() {
          _personalGrowth = Map<String, dynamic>.from(data ?? {});
          _loadingGrowth = false;
        });
      }
    } catch (e) {
      debugPrint('Personal growth error: $e');
      if (mounted) setState(() => _loadingGrowth = false);
    }
  }

  // ── Full refresh (clear all caches) ──────────────────────
  Future<void> _refresh() async {
    setState(() {
      _pulse = {};
      _arbitrage = {};
      _international = {};
      _local = {};
      _careerForecast = {};
      _entrepreneurial = {};
      _wealthStrategies = {};
      _personalGrowth = {};
      _scan = {};
    });
    await _load();
  }

  // ── Skill scan — properly gated behind rewarded ad ────────
  Future<void> _scanSkill(String skill) async {
    if (_adService.isRewardedReady) {
      // Ad is available — gate behind watching it
      await _adService.showRewardedAd(
        featureKey: 'skill_scan',
        onRewarded: () => _performScan(skill),
        onDismissed: () {
          // User dismissed without watching — do NOT scan
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Watch the short video to unlock a deep scan'),
                action: SnackBarAction(
                  label: 'Watch',
                  onPressed: () => _scanSkill(skill),
                ),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
              ),
            );
          }
        },
      );
    } else {
      // No ad loaded — allow scan as fallback (don't block user indefinitely)
      _performScan(skill);
    }
  }

  Future<void> _performScan(String skill) async {
    if (!mounted) return;
    setState(() {
      _scanning = true;
      _selectedSkill = skill;
    });
    try {
      final data =
          await api.get('/pulse/opportunity-scan', queryParams: {'skill': skill});
      if (mounted) {
        setState(() {
          _scan = Map<String, dynamic>.from(data ?? {});
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ── Filter helpers — clear cache before reloading ─────────

  void _onTimeframeChanged(String tf) {
    setState(() {
      _selectedTimeframe = tf;
      _careerForecast = {}; // clear so loader runs again
    });
    _loadCareerForecast();
  }

  void _onCapitalTierChanged(String tier) {
    setState(() {
      _selectedCapitalTier = tier;
      _entrepreneurial = {};
    });
    _loadEntrepreneurial();
  }

  void _onRiskToleranceChanged(String risk) {
    setState(() {
      _selectedRiskTolerance = risk;
      _wealthStrategies = {};
    });
    _loadWealthStrategies();
  }

  @override
  void dispose() {
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () => context.pop(),
        ),
        title: Row(children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.trending_up_rounded,
                color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Text('Market Pulse',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: text)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Iconsax.refresh, color: AppColors.primary, size: 20),
            onPressed: _refresh,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppColors.primary,
          unselectedLabelColor: sub,
          indicatorColor: AppColors.primary,
          indicatorWeight: 2,
          labelStyle:
              const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          tabs: const [
            Tab(text: 'Today', icon: Icon(Iconsax.calendar_1, size: 18)),
            Tab(text: 'Global', icon: Icon(Iconsax.global, size: 18)),
            Tab(text: 'Local', icon: Icon(Iconsax.location, size: 18)),
            Tab(text: 'Career', icon: Icon(Iconsax.briefcase, size: 18)),
            Tab(text: 'Business', icon: Icon(Iconsax.shop, size: 18)),
            Tab(text: 'Wealth', icon: Icon(Iconsax.money_4, size: 18)),
            Tab(text: 'Growth', icon: Icon(Iconsax.chart_3, size: 18)),
            Tab(text: 'Scan', icon: Icon(Iconsax.scan_barcode, size: 18)),
          ],
        ),
      ),

      // ── Body: tabs + persistent banner for free users ────────
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.primary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildTodayTab(isDark, text, sub, card),
                      _buildInternationalTab(isDark, text, sub, card),
                      _buildLocalTab(isDark, text, sub, card),
                      _buildCareerTab(isDark, text, sub, card),
                      _buildEntrepreneurialTab(isDark, text, sub, card),
                      _buildWealthTab(isDark, text, sub, card),
                      _buildGrowthTab(isDark, text, sub, card),
                      _buildScanTab(isDark, text, sub, card),
                    ],
                  ),
          ),

          // Persistent banner ad for free users
          if (!_isPremium) const BannerAdWidget(),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 1 — TODAY
  // Keys from backend: trending_now, emerging_opportunities,
  // overbooked_avoid, morning_briefing, date, action_today,
  // platform_intelligence, rate_trends
  // ============================================================
  Widget _buildTodayTab(
      bool isDark, Color text, Color sub, Color card) {
    final trending =
        (_pulse['trending_now'] as List?)?.cast<dynamic>() ?? [];
    final emerging =
        (_pulse['emerging_opportunities'] as List?)?.cast<dynamic>() ?? [];
    final avoid =
        (_pulse['overbooked_avoid'] as List?)?.cast<dynamic>() ?? [];
    final briefing = _pulse['morning_briefing']?.toString() ?? '';
    final actions =
        (_pulse['action_today'] as List?)?.cast<dynamic>() ?? [];

    final colors = [
      AppColors.primary,
      AppColors.accent,
      AppColors.gold,
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Morning briefing card
        if (briefing.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]),
              borderRadius: AppRadius.lg,
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFF6B35).withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('MORNING BRIEFING',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2)),
                  const SizedBox(height: 8),
                  Text(briefing,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.5,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 10),
                  Text(_pulse['date']?.toString() ?? '',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                ]),
          ).animate().slideY(begin: 0.1).fadeIn(),

        // Trending now
        _sectionHeader('EXPLODING DEMAND', sub),
        ...trending.asMap().entries.map((e) => _trendCard(
              e.value.toString(),
              'High Volume',
              colors[e.key % colors.length],
              isDark,
              text,
              sub,
            ).animate().fadeIn(delay: Duration(milliseconds: e.key * 80))),

        const SizedBox(height: 20),

        // Emerging opportunities
        _sectionHeader('EARLY OPPORTUNITIES', sub),
        ...emerging.map((e) => _trendCard(
            e.toString(), 'Low Competition', AppColors.success, isDark, text, sub)),

        const SizedBox(height: 20),

        // Oversaturated
        _sectionHeader('SATURATED MARKETS', sub),
        ...avoid.map((e) => _avoidCard(e.toString(), text)),

        const SizedBox(height: 24),

        // Platform & rate intel
        _infoSection(
            'Platform Intelligence', _pulse['platform_intelligence'], isDark, text),
        _infoSection('Rate Trends', _pulse['rate_trends'], isDark, text),

        // Actions
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionHeader('ACTIONS FOR TODAY', sub),
          ...actions.asMap().entries.map((e) => _actionCard(
              '${e.key + 1}', e.value.toString(), AppColors.primary, isDark, text)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================
  // TAB 2 — GLOBAL
  // ============================================================
  Widget _buildInternationalTab(
      bool isDark, Color text, Color sub, Color card) {
    if (_international.isEmpty && !_loadingInternational) {
      _loadInternational();
      return _buildLoadingState('Loading global market intelligence...');
    }
    if (_loadingInternational) {
      return _buildLoadingState('Analysing global trends...');
    }

    final globalTrends =
        (_international['global_trends'] as Map?)?.cast<String, dynamic>() ??
            {};
    final emergingSectors =
        (_international['emerging_sectors'] as List?)?.cast<dynamic>() ?? [];
    final geoArbitrage =
        (_international['geographic_arbitrage'] as List?)?.cast<dynamic>() ??
            [];
    final futureProofing =
        (_international['future_proofing'] as Map?)?.cast<String, dynamic>() ??
            {};
    final skillMatches =
        (_international['your_skill_matches'] as List?)?.cast<dynamic>() ?? [];

    return ListView(padding: const EdgeInsets.all(16), children: [
      _buildPremiumBanner('INTERNATIONAL MARKET IMPULSE', 'Global trends & opportunities',
          [const Color(0xFF667eea), const Color(0xFF764ba2)]),

      _sectionHeader('TECH ADOPTION IMPACT', sub),
      if (globalTrends['tech_adoption_impact'] != null)
        _insightCard('Tech Impact',
            globalTrends['tech_adoption_impact'].toString(), AppColors.info, isDark, text),

      if ((globalTrends['fastest_growing_roles'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 20),
        _sectionHeader('FASTEST GROWING ROLES', sub),
        ...(globalTrends['fastest_growing_roles'] as List)
            .map((r) => _roleCard(r, isDark, text, sub)),
      ],

      if ((globalTrends['declining_roles'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 20),
        _sectionHeader('ROLES TO AVOID', sub),
        ...(globalTrends['declining_roles'] as List)
            .take(5)
            .map((r) => _avoidCard(r.toString(), text)),
      ],

      const SizedBox(height: 20),
      _sectionHeader('EMERGING SECTORS', sub),
      ...emergingSectors
          .asMap()
          .entries
          .map((e) => _sectorCard(e.value, e.key, isDark, text, sub)),

      if (geoArbitrage.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('GEOGRAPHIC ARBITRAGE', sub),
        ...geoArbitrage.map((g) => _geoArbitrageCard(g, isDark, text, sub)),
      ],

      if (futureProofing.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('FUTURE-PROOFING', sub),
        if (futureProofing['immediate_skills'] != null)
          _skillListCard('Skills to Acquire Now',
              futureProofing['immediate_skills'] as List, AppColors.success, isDark, text),
        if (futureProofing['ai_augmentation'] != null)
          _insightCard('AI Strategy', futureProofing['ai_augmentation'].toString(),
              AppColors.accent, isDark, text),
      ],

      if (skillMatches.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('YOUR SKILL MATCHES', sub),
        ...skillMatches.map((m) => _skillMatchCard(m, isDark, text, sub)),
      ],

      const SizedBox(height: 40),
    ]);
  }

  // ============================================================
  // TAB 3 — LOCAL
  // ============================================================
  Widget _buildLocalTab(bool isDark, Color text, Color sub, Color card) {
    if (_local.isEmpty && !_loadingLocal) {
      _loadLocal();
      return _buildLoadingState('Loading local market data...');
    }
    if (_loadingLocal) {
      return _buildLoadingState('Analysing local trends...');
    }

    final economicIndicators =
        (_local['economic_indicators'] as Map?)?.cast<String, dynamic>() ?? {};
    final skillDemand =
        (_local['skill_demand'] as Map?)?.cast<String, dynamic>() ?? {};
    final platforms =
        (_local['platform_landscape'] as List?)?.cast<dynamic>() ?? [];
    final recommendations =
        (_local['local_recommendations'] as Map?)?.cast<String, dynamic>() ?? {};

    return ListView(padding: const EdgeInsets.all(16), children: [
      _buildPremiumBanner('LOCAL MARKET TRENDS', 'Country-specific insights',
          [const Color(0xFFf093fb), const Color(0xFFf5576c)]),

      if (economicIndicators.isNotEmpty) ...[
        _sectionHeader('ECONOMIC PULSE', sub),
        _economicIndicatorsCard(economicIndicators, isDark, text, sub),
      ],

      if ((skillDemand['hot_skills'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 20),
        _sectionHeader('HOT SKILLS LOCALLY', sub),
        ...(skillDemand['hot_skills'] as List)
            .map((s) => _hotSkillCard(s, isDark, text, sub)),
      ],

      if ((skillDemand['oversaturated'] as List?)?.isNotEmpty == true) ...[
        const SizedBox(height: 20),
        _sectionHeader('OVERSATURATED SKILLS', sub),
        ...(skillDemand['oversaturated'] as List)
            .take(5)
            .map((s) => _avoidCard(s.toString(), text)),
      ],

      if (platforms.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('PLATFORM INTELLIGENCE', sub),
        ...platforms.map((p) => _platformCard(p, isDark, text, sub)),
      ],

      _infoSection('SEASONAL CONTEXT', _local['seasonal_context'], isDark, text),
      _infoSection('CULTURAL INSIGHTS', _local['cultural_notes'], isDark, text),

      if (recommendations.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionHeader('LOCAL RECOMMENDATIONS', sub),
        if (recommendations['platforms_to_join'] != null)
          _skillListCard('Platforms to Join',
              recommendations['platforms_to_join'] as List, AppColors.primary, isDark, text),
        if (recommendations['skills_to_highlight'] != null)
          _skillListCard('Skills to Highlight',
              recommendations['skills_to_highlight'] as List, AppColors.success, isDark, text),
      ],

      const SizedBox(height: 40),
    ]);
  }

  // ============================================================
  // TAB 4 — CAREER
  // ============================================================
  Widget _buildCareerTab(bool isDark, Color text, Color sub, Color card) {
    if (_careerForecast.isEmpty && !_loadingCareer) {
      _loadCareerForecast();
      return _buildLoadingState('Generating career forecast...');
    }
    if (_loadingCareer) {
      return _buildLoadingState('Analysing career paths...');
    }

    final careerPaths =
        (_careerForecast['career_paths'] as List?)?.cast<dynamic>() ?? [];
    final recommendedPath =
        _careerForecast['recommended_path'] as Map<String, dynamic>?;

    return ListView(padding: const EdgeInsets.all(16), children: [
      _buildPremiumBanner('CAREER FORECAST', 'Your personalised path forward',
          [const Color(0xFF4facfe), const Color(0xFF00f2fe)]),

      _buildTimeframeFilter(isDark, text, sub),

      if (recommendedPath != null) ...[
        _sectionHeader('RECOMMENDED PATH', sub),
        _careerPathCard(recommendedPath, true, isDark, text, sub),
      ],

      if (careerPaths.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('ALL CAREER PATHS', sub),
        ...careerPaths
            .skip(recommendedPath != null ? 1 : 0)
            .take(5)
            .map((p) => _careerPathCard(p, false, isDark, text, sub)),
      ],

      const SizedBox(height: 24),
      _buildRewardAdButton(
        'Unlock Premium Career Insights',
        'Watch a short video to refresh with 3 additional career paths',
        () {
          setState(() => _careerForecast = {});
          _loadCareerForecast();
        },
      ),

      const SizedBox(height: 40),
    ]);
  }

  // ============================================================
  // TAB 5 — BUSINESS
  // ============================================================
  Widget _buildEntrepreneurialTab(
      bool isDark, Color text, Color sub, Color card) {
    if (_entrepreneurial.isEmpty && !_loadingEntrepreneurial) {
      _loadEntrepreneurial();
      return _buildLoadingState('Scanning business opportunities...');
    }
    if (_loadingEntrepreneurial) {
      return _buildLoadingState('Finding opportunities...');
    }

    final opportunities =
        (_entrepreneurial['opportunities'] as List?)?.cast<dynamic>() ?? [];
    final recommendedFocus =
        _entrepreneurial['recommended_focus'] as Map<String, dynamic>?;
    final nextSteps =
        (_entrepreneurial['next_steps'] as List?)?.cast<dynamic>() ?? [];

    return ListView(padding: const EdgeInsets.all(16), children: [
      _buildPremiumBanner('ENTREPRENEURIAL OPPORTUNITIES', 'Start your business journey',
          [const Color(0xFFfa709a), const Color(0xFFfee140)]),

      _buildCapitalTierFilter(isDark, text, sub),

      if (recommendedFocus != null) ...[
        _sectionHeader('TOP OPPORTUNITY', sub),
        _opportunityCard(recommendedFocus, true, isDark, text, sub),
      ],

      if (opportunities.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('MORE OPPORTUNITIES', sub),
        ...opportunities
            .skip(1)
            .take(4)
            .map((o) => _opportunityCard(o, false, isDark, text, sub)),
      ],

      if (nextSteps.isNotEmpty) ...[
        const SizedBox(height: 24),
        _sectionHeader('NEXT STEPS', sub),
        ...nextSteps.asMap().entries.map((e) =>
            _actionCard('${e.key + 1}', e.value.toString(), AppColors.accent, isDark, text)),
      ],

      const SizedBox(height: 40),
    ]);
  }

  // ============================================================
  // TAB 6 — WEALTH
  // ============================================================
  Widget _buildWealthTab(bool isDark, Color text, Color sub, Color card) {
    if (_wealthStrategies.isEmpty && !_loadingWealth) {
      _loadWealthStrategies();
      return _buildLoadingState('Building wealth strategies...');
    }
    if (_loadingWealth) {
      return _buildLoadingState('Calculating strategies...');
    }

    final strategies =
        (_wealthStrategies['strategies'] as List?)?.cast<dynamic>() ?? [];
    final quickWins =
        (_wealthStrategies['quick_wins'] as List?)?.cast<dynamic>() ?? [];
    final longTerm =
        (_wealthStrategies['long_term_builders'] as List?)?.cast<dynamic>() ?? [];
    final userProfile =
        (_wealthStrategies['user_profile'] as Map?)?.cast<String, dynamic>() ?? {};

    return ListView(padding: const EdgeInsets.all(16), children: [
      _buildPremiumBanner('WEALTH BUILDING', 'Strategies for financial growth',
          [const Color(0xFF30cfd0), const Color(0xFF330867)]),

      _buildRiskFilter(isDark, text, sub),

      if (userProfile.isNotEmpty) _userProfileCard(userProfile, isDark, text, sub),

      if (quickWins.isNotEmpty) ...[
        _sectionHeader('QUICK WINS', sub),
        ...quickWins.map((s) => _strategyCard(s, AppColors.success, isDark, text, sub)),
      ],

      if (longTerm.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('LONG-TERM BUILDERS', sub),
        ...longTerm.map((s) => _strategyCard(s, AppColors.primary, isDark, text, sub)),
      ],

      if (strategies.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('ALL STRATEGIES', sub),
        ...strategies
            .skip(quickWins.length + longTerm.length)
            .take(3)
            .map((s) => _strategyCard(s, AppColors.accent, isDark, text, sub)),
      ],

      const SizedBox(height: 40),
    ]);
  }

  // ============================================================
  // TAB 7 — GROWTH
  // ============================================================
  Widget _buildGrowthTab(bool isDark, Color text, Color sub, Color card) {
    if (_personalGrowth.isEmpty && !_loadingGrowth) {
      _loadPersonalGrowth();
      return _buildLoadingState('Loading personal growth insights...');
    }
    if (_loadingGrowth) {
      return _buildLoadingState('Generating insights...');
    }

    final insights =
        (_personalGrowth['insights'] as List?)?.cast<dynamic>() ?? [];
    final priorityAction =
        _personalGrowth['priority_action'] as Map<String, dynamic>?;
    final focusAreas =
        (_personalGrowth['focus_areas'] as List?)?.cast<dynamic>() ?? [];

    return ListView(padding: const EdgeInsets.all(16), children: [
      _buildPremiumBanner('PERSONAL GROWTH', 'Level up your mindset & skills',
          [const Color(0xFFa8edea), const Color(0xFFfed6e3)]),

      if (priorityAction != null) ...[
        _sectionHeader('PRIORITY ACTION', sub),
        _growthCard(priorityAction, true, isDark, text, sub),
      ],

      if (focusAreas.isNotEmpty) ...[
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: focusAreas
              .map((a) => Chip(
                    label: Text(a.toString(),
                        style: TextStyle(color: text, fontSize: 12)),
                    backgroundColor: isDark
                        ? AppColors.bgSurface
                        : Colors.grey.shade200,
                  ))
              .toList(),
        ),
      ],

      if (insights.isNotEmpty) ...[
        const SizedBox(height: 20),
        _sectionHeader('ALL INSIGHTS', sub),
        ...insights
            .skip(priorityAction != null ? 1 : 0)
            .map((i) => _growthCard(i, false, isDark, text, sub)),
      ],

      const SizedBox(height: 40),
    ]);
  }

  // ============================================================
  // TAB 8 — SCAN
  // ============================================================
  Widget _buildScanTab(bool isDark, Color text, Color sub, Color card) {
    // Trending skills from Today tab used as quick-select chips
    final trending =
        (_pulse['trending_now'] as List?)?.cast<dynamic>() ?? [];
    final suggestions = trending.take(8).toList();
    final scanData =
        (_scan['scan_results'] as Map?)?.cast<String, dynamic>() ?? {};

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildPremiumBanner('SKILL SCANNER', 'Deep market analysis for any skill',
            [const Color(0xFFffecd2), const Color(0xFFfcb69f)]),

        const SizedBox(height: 20),
        _sectionHeader('QUICK SCAN TRENDS', sub),

        if (suggestions.isEmpty)
          Text('Load the Today tab first to see trending skills.',
              style: TextStyle(color: sub, fontSize: 12))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions
                .map((s) => ChoiceChip(
                      label: Text(s.toString(),
                          style: TextStyle(
                              fontSize: 11,
                              color: _selectedSkill == s
                                  ? Colors.white
                                  : text)),
                      selected: _selectedSkill == s,
                      onSelected: (_) => _scanSkill(s.toString()),
                      selectedColor: AppColors.primary,
                      backgroundColor:
                          isDark ? AppColors.bgCard : Colors.grey.shade100,
                    ))
                .toList(),
          ),

        const SizedBox(height: 24),

        // Show reward ad prompt when nothing scanned yet
        if (_selectedSkill.isEmpty && scanData.isEmpty)
          _buildRewardAdButton(
            'Unlock Deep Scan',
            'Watch a short video to get a full AI market analysis for any skill',
            () {}, // Tapping chips above triggers the scan
          ),

        if (_scanning)
          const Center(
              child: Padding(
                  padding: EdgeInsets.all(40),
                  child:
                      CircularProgressIndicator(color: AppColors.primary)))
        else if (scanData.isNotEmpty)
          _buildScanResult(scanData, isDark, text, sub)
        else if (_selectedSkill.isNotEmpty)
          _buildEmptyScanState(sub),

        const SizedBox(height: 40),
      ]),
    );
  }

  // ============================================================
  // SHARED UI COMPONENTS
  // ============================================================

  Widget _buildPremiumBanner(
      String title, String subtitle, List<Color> gradient) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: AppRadius.lg,
        boxShadow: [
          BoxShadow(
              color: gradient[0].withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5)),
        const SizedBox(height: 4),
        Text(subtitle,
            style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ]),
    ).animate().slideY(begin: 0.1).fadeIn();
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 16),
        Text(message, style: const TextStyle(color: Colors.grey)),
      ]),
    );
  }

  /// Rewarded ad button — shows ad, calls onRewarded if user watches fully.
  Widget _buildRewardAdButton(
      String title, String subtitle, VoidCallback onRewarded) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ElevatedButton.icon(
        onPressed: () => _adService.showRewardedAd(
          featureKey: 'market_pulse_unlock',
          onRewarded: onRewarded,
          onDismissed: () {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Watch the full video to unlock this feature'),
                behavior: SnackBarBehavior.floating,
              ));
            }
          },
        ),
        icon: const Icon(Icons.play_circle_outline, color: Colors.white),
        label: Column(children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(subtitle,
              style:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
        ]),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
          padding:
              const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape:
              RoundedRectangleBorder(borderRadius: AppRadius.lg),
        ),
      ),
    );
  }

  Widget _buildTimeframeFilter(bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['all', 'immediate', 'short', 'long']
              .map((tf) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tf.toUpperCase(),
                          style: const TextStyle(fontSize: 11)),
                      selected: _selectedTimeframe == tf,
                      onSelected: (_) => _onTimeframeChanged(tf),
                      selectedColor: AppColors.primary,
                      backgroundColor:
                          isDark ? AppColors.bgSurface : Colors.grey.shade200,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildCapitalTierFilter(bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['bootstrap', 'moderate', 'well-funded']
              .map((tier) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(tier.toUpperCase(),
                          style: const TextStyle(fontSize: 11)),
                      selected: _selectedCapitalTier == tier,
                      onSelected: (_) => _onCapitalTierChanged(tier),
                      selectedColor: AppColors.primary,
                      backgroundColor:
                          isDark ? AppColors.bgSurface : Colors.grey.shade200,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  Widget _buildRiskFilter(bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['conservative', 'moderate', 'aggressive']
              .map((risk) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(risk.toUpperCase(),
                          style: const TextStyle(fontSize: 11)),
                      selected: _selectedRiskTolerance == risk,
                      onSelected: (_) => _onRiskToleranceChanged(risk),
                      selectedColor: AppColors.primary,
                      backgroundColor:
                          isDark ? AppColors.bgSurface : Colors.grey.shade200,
                    ),
                  ))
              .toList(),
        ),
      ),
    );
  }

  // ── Card components ──────────────────────────────────────

  Widget _trendCard(String title, String subtitle, Color color, bool isDark,
      Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)
        ],
      ),
      child: Row(children: [
        Container(
            width: 4,
            height: 32,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: text)),
            Text(subtitle,
                style: TextStyle(fontSize: 11, color: sub)),
          ]),
        ),
        Icon(Icons.trending_up_rounded,
            size: 16, color: color.withOpacity(0.5)),
      ]),
    );
  }

  Widget _avoidCard(String title, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.05),
          borderRadius: AppRadius.md),
      child: Row(children: [
        const Icon(Icons.block, color: AppColors.error, size: 16),
        const SizedBox(width: 12),
        Expanded(
            child: Text(title,
                style: TextStyle(
                    fontSize: 13,
                    color: text,
                    fontWeight: FontWeight.w500))),
        const Text('Saturated',
            style: TextStyle(
                color: AppColors.error,
                fontSize: 10,
                fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _actionCard(
      String number, String action, Color color, bool isDark, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: AppRadius.md,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 24,
          height: 24,
          decoration:
              BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
              child: Text(number,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700))),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Text(action,
                style: TextStyle(
                    fontSize: 13, color: text, height: 1.4))),
      ]),
    );
  }

  Widget _infoSection(String title, dynamic content, bool isDark, Color text) {
    if (content == null || content.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(title.toUpperCase(), text.withOpacity(0.5)),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : const Color(0xFFF8F9FA),
            borderRadius: AppRadius.lg),
        child: Text(content.toString(),
            style: TextStyle(fontSize: 13, color: text, height: 1.6)),
      ),
      const SizedBox(height: 20),
    ]);
  }

  Widget _insightCard(
      String title, String content, Color color, bool isDark, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 8),
        Text(content,
            style: TextStyle(fontSize: 13, color: text, height: 1.5)),
      ]),
    );
  }

  Widget _roleCard(dynamic role, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
              child: Text(role['role']?.toString() ?? 'Unknown',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: text))),
          if (role['growth_rate'] != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(role['growth_rate'].toString(),
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.success,
                      fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }

  Widget _sectorCard(
      dynamic sector, int index, bool isDark, Color text, Color sub) {
    final colors = [
      AppColors.primary, AppColors.accent, AppColors.success,
      AppColors.gold, AppColors.info
    ];
    final color = colors[index % colors.length];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(sector['sector']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: text))),
        ]),
        if (sector['market_size_growth'] != null) ...[
          const SizedBox(height: 8),
          Text(sector['market_size_growth'].toString(),
              style: TextStyle(
                  fontSize: 12, color: color, fontWeight: FontWeight.w600)),
        ],
        if ((sector['top_opportunities'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: (sector['top_opportunities'] as List)
                .map((o) => Chip(
                      label: Text(o.toString(),
                          style: const TextStyle(fontSize: 10)),
                      backgroundColor: color.withOpacity(0.1),
                      padding: EdgeInsets.zero,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ))
                .toList(),
          ),
        ],
      ]),
    );
  }

  Widget _geoArbitrageCard(
      dynamic geo, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Iconsax.global, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text(geo['region']?.toString() ?? '',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: text))),
          if (geo['remote_friendly'] == true)
            const Icon(Iconsax.verify, size: 16, color: AppColors.success),
        ]),
        const SizedBox(height: 8),
        Text(geo['opportunity']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
      ]),
    );
  }

  Widget _skillMatchCard(
      dynamic match, bool isDark, Color text, Color sub) {
    const colorMap = {
      'direct': AppColors.success,
      'adjacent': AppColors.accent,
      'transferable': AppColors.info,
    };
    final color = colorMap[match['match_type']] ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.md,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(match['opportunity']?.toString() ?? '',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: text)),
            const SizedBox(height: 2),
            Text('Matches: ${match['your_skill']}',
                style: TextStyle(fontSize: 11, color: sub)),
          ]),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4)),
          child: Text(
            match['match_type']?.toString().toUpperCase() ?? '',
            style: TextStyle(
                fontSize: 9, color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _skillListCard(
      String title, List skills, Color color, bool isDark, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: skills
              .map((s) => Chip(
                    label: Text(s.toString(),
                        style: const TextStyle(fontSize: 11)),
                    backgroundColor: color.withOpacity(0.1),
                    side: BorderSide.none,
                  ))
              .toList(),
        ),
      ]),
    );
  }

  Widget _economicIndicatorsCard(
      Map<String, dynamic> indicators, bool isDark, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
      ),
      child: Column(children: [
        _indicatorRow('Unemployment',
            indicators['unemployment_rate'], Iconsax.people, AppColors.error),
        const Divider(height: 16),
        _indicatorRow('Inflation',
            indicators['inflation_trend'], Iconsax.chart_2, AppColors.warning),
        const Divider(height: 16),
        _indicatorRow('Currency',
            indicators['currency_strength'], Iconsax.money, AppColors.success),
        const Divider(height: 16),
        _indicatorRow('GDP Growth',
            indicators['gdp_growth'], Iconsax.trend_up, AppColors.primary),
      ]),
    );
  }

  Widget _indicatorRow(
      String label, dynamic value, IconData icon, Color color) {
    return Row(children: [
      Icon(icon, size: 18, color: color),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(fontSize: 13)),
      const Spacer(),
      Text(value?.toString() ?? 'N/A',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: color)),
    ]);
  }

  Widget _hotSkillCard(dynamic skill, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: AppColors.success.withOpacity(0.2)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(skill['skill']?.toString() ?? '',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: text)),
            if (skill['local_salary_range'] != null)
              Text(skill['local_salary_range'].toString(),
                  style: TextStyle(fontSize: 12, color: sub)),
          ]),
        ),
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12)),
          child: Text(
            skill['demand_level']?.toString().toUpperCase() ?? 'HIGH',
            style: const TextStyle(
                fontSize: 10,
                color: AppColors.success,
                fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

  Widget _platformCard(dynamic platform, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(platform['platform']?.toString() ?? '',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: text)),
            if (platform['effectiveness'] != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Text(platform['effectiveness'].toString(),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.primary)),
              ),
          ],
        ),
        if ((platform['payment_methods'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children:
                (platform['payment_methods'] as List).map((m) => Chip(
                      label: Text(m.toString(),
                          style: const TextStyle(fontSize: 9)),
                      backgroundColor: isDark
                          ? AppColors.bgSurface
                          : Colors.grey.shade200,
                      padding: EdgeInsets.zero,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    )).toList(),
          ),
        ],
      ]),
    );
  }

  Widget _careerPathCard(dynamic path, bool isRecommended, bool isDark,
      Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: isRecommended
            ? Border.all(color: AppColors.gold, width: 2)
            : null,
        boxShadow: isRecommended
            ? [
                BoxShadow(
                    color: AppColors.gold.withOpacity(0.2), blurRadius: 10)
              ]
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isRecommended)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(4)),
            child: const Text('RECOMMENDED',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
          ),
        Text(path['title']?.toString() ?? '',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        Row(children: [
          _miniBadge(
              path['current_demand']?.toString() ?? '', AppColors.success),
          const SizedBox(width: 8),
          _miniBadge(
              path['growth_projection']?.toString() ?? '', AppColors.info),
        ]),
        if (path['salary_range_usd'] != null) ...[
          const SizedBox(height: 8),
          Text(
            '\$${path['salary_range_usd']['min']} - \$${path['salary_range_usd']['max']}/yr',
            style: TextStyle(fontSize: 12, color: sub),
          ),
        ],
        if ((path['required_skills'] as List?)?.isNotEmpty == true) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: (path['required_skills'] as List).take(5).map((s) => Chip(
                  label: Text(s.toString(),
                      style: const TextStyle(fontSize: 10)),
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )).toList(),
          ),
        ],
      ]),
    );
  }

  Widget _opportunityCard(dynamic opp, bool isFeatured, bool isDark,
      Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: isFeatured
            ? Border.all(color: AppColors.gold, width: 2)
            : Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isFeatured)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: AppColors.gold,
                borderRadius: BorderRadius.circular(4)),
            child: const Text('FEATURED',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
          ),
        Text(opp['sector']?.toString() ?? '',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 8),
        Text(opp['problem_statement']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
        const SizedBox(height: 12),
        Row(children: [
          _miniBadge(
              'Scale: ${opp['scalability_score']}/10', AppColors.primary),
          const SizedBox(width: 8),
          _miniBadge(
              opp['risk_level']?.toString() ?? '', AppColors.warning),
        ]),
        if (opp['startup_cost_range_usd'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Startup: \$${opp['startup_cost_range_usd']['min']} - \$${opp['startup_cost_range_usd']['max']}',
            style: TextStyle(fontSize: 12, color: sub),
          ),
        ],
      ]),
    );
  }

  Widget _strategyCard(
      dynamic strategy, Color color, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
                child: Text(strategy['title']?.toString() ?? '',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: text))),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(
                '${strategy['expected_roi_annual_percent']}%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(strategy['description']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4)),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Iconsax.clock, size: 14, color: sub),
          const SizedBox(width: 4),
          Text('${strategy['time_commitment_hours_week']} hrs/week',
              style: TextStyle(fontSize: 11, color: sub)),
          const SizedBox(width: 16),
          Icon(Iconsax.money, size: 14, color: sub),
          const SizedBox(width: 4),
          Text('\$${strategy['initial_capital_required_usd']} needed',
              style: TextStyle(fontSize: 11, color: sub)),
        ]),
      ]),
    );
  }

  Widget _userProfileCard(
      Map<String, dynamic> profile, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
        borderRadius: AppRadius.lg,
      ),
      child: Row(children: [
        Icon(Iconsax.user, size: 18, color: sub),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              '${profile['country'] ?? ''} • ${profile['income_level'] ?? ''} income',
              style: TextStyle(fontSize: 12, color: text),
            ),
            Text(
              '${profile['time_available_hours_week'] ?? 0} hrs/week available',
              style: TextStyle(fontSize: 11, color: sub),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _growthCard(
      dynamic insight, bool isPriority, bool isDark, Color text, Color sub) {
    const categoryColors = {
      'mindset': AppColors.primary,
      'productivity': AppColors.accent,
      'networking': AppColors.success,
      'health': AppColors.error,
      'learning': AppColors.info,
    };
    final color =
        categoryColors[insight['category']] ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border:
            isPriority ? Border.all(color: color, width: 2) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4)),
            child: Text(
              insight['category']?.toString().toUpperCase() ?? '',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: color),
            ),
          ),
          if (isPriority) ...[
            const SizedBox(width: 8),
            const Icon(Iconsax.star_1, size: 14, color: AppColors.gold),
          ],
        ]),
        const SizedBox(height: 12),
        Text(insight['insight']?.toString() ?? '',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: text)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: color.withOpacity(0.05),
              borderRadius: AppRadius.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Iconsax.lamp_charge, size: 16, color: color),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                insight['actionable_tip']?.toString() ?? '',
                style:
                    TextStyle(fontSize: 12, color: text, height: 1.4),
              )),
            ],
          ),
        ),
        if (insight['implementation_timeline'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Timeline: ${insight['implementation_timeline']}',
            style: TextStyle(
                fontSize: 11,
                color: sub,
                fontStyle: FontStyle.italic),
          ),
        ],
      ]),
    );
  }

  // ── Scan result ──────────────────────────────────────────

  Widget _buildScanResult(
      Map<String, dynamic> data, bool isDark, Color text, Color sub) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('LIVE MARKET REPORT',
          style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: AppColors.primary)),
      const SizedBox(height: 4),
      Text(_selectedSkill.toUpperCase(),
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w900, color: text)),
      const SizedBox(height: 16),
      _gridStat('Demand', data['demand_level'], Iconsax.flash),
      _gridStat('Platform', data['best_platform_now'], Iconsax.global),
      _gridStat(
          'Avg Rate', '\$${data['average_rate_usd']}/hr', Iconsax.money),
      _gridStat('Momentum', data['momentum'], Iconsax.graph),
      const SizedBox(height: 20),
      _actionBox('NEXT STEP', data['action_today'], AppColors.success),
      if (data['fastest_path_to_client'] != null)
        _actionBox('FASTEST PATH', data['fastest_path_to_client'],
            AppColors.primary),
      if (data['niche_down_suggestion'] != null)
        _actionBox('NICHE DOWN', data['niche_down_suggestion'],
            AppColors.accent),
    ]).animate().fadeIn();
  }

  Widget _gridStat(String label, dynamic val, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.03),
          borderRadius: AppRadius.md),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(val?.toString() ?? '-',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _actionBox(String title, dynamic content, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(
                color: color,
                fontWeight: FontWeight.w900,
                fontSize: 10,
                letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(content?.toString() ?? '',
            style:
                const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(4)),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sectionHeader(String title, Color sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(title,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: sub,
              letterSpacing: 1.5)),
    );
  }

  Widget _buildEmptyScanState(Color sub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(children: [
          Icon(Iconsax.search_status,
              size: 64, color: sub.withOpacity(0.2)),
          const SizedBox(height: 16),
          Text('Select a skill above to get a live AI market scan',
              textAlign: TextAlign.center,
              style: TextStyle(color: sub, fontSize: 13)),
        ]),
      ),
    );
  }
}
