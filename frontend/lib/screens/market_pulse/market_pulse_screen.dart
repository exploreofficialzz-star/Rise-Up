import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/ad_service.dart';

class MarketPulseScreen extends StatefulWidget {
  const MarketPulseScreen({super.key});
  
  @override
  State<MarketPulseScreen> createState() => _MarketPulseScreenState();
}

class _MarketPulseScreenState extends State<MarketPulseScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final AdService _adService = AdService();
  
  // Data states
  Map<String, dynamic> _pulse = {};
  Map<String, dynamic> _arbitrage = {};
  Map<String, dynamic> _scan = {};
  Map<String, dynamic> _international = {};
  Map<String, dynamic> _local = {};
  Map<String, dynamic> _careerForecast = {};
  Map<String, dynamic> _entrepreneurial = {};
  Map<String, dynamic> _wealthStrategies = {};
  Map<String, dynamic> _personalGrowth = {};
  Map<String, dynamic> _comprehensive = {};
  
  // Loading states
  bool _loading = true;
  bool _scanning = false;
  bool _loadingInternational = false;
  bool _loadingLocal = false;
  bool _loadingCareer = false;
  bool _loadingEntrepreneurial = false;
  bool _loadingWealth = false;
  bool _loadingGrowth = false;
  
  // Selection states
  String _selectedSkill = '';
  String _selectedCapitalTier = 'bootstrap';
  String _selectedRiskTolerance = 'moderate';
  String _selectedTimeframe = 'all';
  
  // Ad states
  bool _showHomeBanner = false;
  bool _showInlineAd = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 8, vsync: this);
    _tabs.addListener(_onTabChanged);
    _load();
    _loadAds();
  }

  void _onTabChanged() {
    // Show interstitial ad every 3 tab changes
    if (_tabs.indexIsChanging && _tabs.index % 3 == 0) {
      _adService.showInterstitialAd();
    }
  }

  Future<void> _loadAds() async {
    _adService.loadHomeBannerAd(onLoaded: () {
      if (mounted) setState(() => _showHomeBanner = true);
    });
    _adService.loadInlineBannerAd(onLoaded: () {
      if (mounted) setState(() => _showInlineAd = true);
    });
    _adService.loadInterstitialAd();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        api.get('/pulse/today'),
        api.get('/pulse/arbitrage'),
        api.get('/pulse/comprehensive'),
      ]);
      if (mounted) {
        setState(() {
          _pulse = Map<String, dynamic>.from(results[0] ?? {});
          _arbitrage = Map<String, dynamic>.from(results[1] ?? {});
          _comprehensive = Map<String, dynamic>.from(results[2] ?? {});
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint("Market Pulse Load Error: $e");
      if (mounted) setState(() => _loading = false);
    }
  }

  // Individual loaders for each tab
  Future<void> _loadInternational() async {
    if (_international.isNotEmpty) return;
    setState(() => _loadingInternational = true);
    try {
      final data = await api.get('/pulse/international');
      if (mounted) setState(() {
        _international = Map<String, dynamic>.from(data ?? {});
        _loadingInternational = false;
      });
    } catch (e) {
      debugPrint("International load error: $e");
      if (mounted) setState(() => _loadingInternational = false);
    }
  }

  Future<void> _loadLocal() async {
    if (_local.isNotEmpty) return;
    setState(() => _loadingLocal = true);
    try {
      final data = await api.get('/pulse/local');
      if (mounted) setState(() {
        _local = Map<String, dynamic>.from(data ?? {});
        _loadingLocal = false;
      });
    } catch (e) {
      debugPrint("Local load error: $e");
      if (mounted) setState(() => _loadingLocal = false);
    }
  }

  Future<void> _loadCareerForecast() async {
    if (_careerForecast.isNotEmpty) return;
    setState(() => _loadingCareer = true);
    try {
      final data = await api.get('/pulse/career-forecast', queryParams: {
        'timeframe': _selectedTimeframe,
      });
      if (mounted) setState(() {
        _careerForecast = Map<String, dynamic>.from(data ?? {});
        _loadingCareer = false;
      });
    } catch (e) {
      debugPrint("Career forecast error: $e");
      if (mounted) setState(() => _loadingCareer = false);
    }
  }

  Future<void> _loadEntrepreneurial() async {
    if (_entrepreneurial.isNotEmpty) return;
    setState(() => _loadingEntrepreneurial = true);
    try {
      final data = await api.get('/pulse/entrepreneurial-opportunities', queryParams: {
        'capital_tier': _selectedCapitalTier,
      });
      if (mounted) setState(() {
        _entrepreneurial = Map<String, dynamic>.from(data ?? {});
        _loadingEntrepreneurial = false;
      });
    } catch (e) {
      debugPrint("Entrepreneurial error: $e");
      if (mounted) setState(() => _loadingEntrepreneurial = false);
    }
  }

  Future<void> _loadWealthStrategies() async {
    if (_wealthStrategies.isNotEmpty) return;
    setState(() => _loadingWealth = true);
    try {
      final data = await api.get('/pulse/wealth-strategies', queryParams: {
        'risk_tolerance': _selectedRiskTolerance,
      });
      if (mounted) setState(() {
        _wealthStrategies = Map<String, dynamic>.from(data ?? {});
        _loadingWealth = false;
      });
    } catch (e) {
      debugPrint("Wealth strategies error: $e");
      if (mounted) setState(() => _loadingWealth = false);
    }
  }

  Future<void> _loadPersonalGrowth() async {
    if (_personalGrowth.isNotEmpty) return;
    setState(() => _loadingGrowth = true);
    try {
      final data = await api.get('/pulse/personal-growth');
      if (mounted) setState(() {
        _personalGrowth = Map<String, dynamic>.from(data ?? {});
        _loadingGrowth = false;
      });
    } catch (e) {
      debugPrint("Personal growth error: $e");
      if (mounted) setState(() => _loadingGrowth = false);
    }
  }

  Future<void> _scanSkill(String skill) async {
    // Show rewarded ad before scan
    _adService.showRewardedAd(
      onRewarded: () async {
        setState(() { 
          _scanning = true; 
          _selectedSkill = skill; 
        });
        try {
          final data = await api.get('/pulse/opportunity-scan', queryParams: {'skill': skill});
          if (mounted) setState(() { 
            _scan = Map<String, dynamic>.from(data ?? {}); 
            _scanning = false; 
          });
        } catch (e) {
          if (mounted) setState(() => _scanning = false);
        }
      },
      onDismissed: () {
        // Continue without reward if ad dismissed
        _performScan(skill);
      },
    );
  }

  Future<void> _performScan(String skill) async {
    setState(() { 
      _scanning = true; 
      _selectedSkill = skill; 
    });
    try {
      final data = await api.get('/pulse/opportunity-scan', queryParams: {'skill': skill});
      if (mounted) setState(() { 
        _scan = Map<String, dynamic>.from(data ?? {}); 
        _scanning = false; 
      });
    } catch (e) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  void dispose() { 
    _tabs.dispose(); 
    _adService.dispose();
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text), 
          onPressed: () => context.pop()
        ),
        title: Row(children: [
          Container(
            width: 28, 
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]), 
              borderRadius: BorderRadius.circular(8)
            ),
            child: const Icon(Icons.trending_up_rounded, color: Colors.white, size: 16)
          ),
          const SizedBox(width: 10),
          Text('Market Pulse', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        ]),
        actions: [
          IconButton(
            icon: Icon(Iconsax.refresh, color: AppColors.primary, size: 20), 
            onPressed: _load
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: AppColors.primary, 
          unselectedLabelColor: sub,
          indicatorColor: AppColors.primary, 
          indicatorWeight: 2,
          labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          unselectedLabelStyle: const TextStyle(fontSize: 10),
          tabs: const [
            Tab(text: "Today", icon: Icon(Iconsax.calendar_1, size: 18)),
            Tab(text: "Global", icon: Icon(Iconsax.global, size: 18)),
            Tab(text: "Local", icon: Icon(Iconsax.location, size: 18)),
            Tab(text: "Career", icon: Icon(Iconsax.briefcase, size: 18)),
            Tab(text: "Business", icon: Icon(Iconsax.shop, size: 18)),
            Tab(text: "Wealth", icon: Icon(Iconsax.money_4, size: 18)),
            Tab(text: "Growth", icon: Icon(Iconsax.chart_3, size: 18)),
            Tab(text: "Scan", icon: Icon(Iconsax.scan_barcode, size: 18)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Home Banner Ad
          if (_showHomeBanner)
            BannerAdWidget(
              ad: _adService.homeBannerAd,
              isLoaded: _adService.isHomeBannerLoaded,
              height: 100,
            ),
          
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _buildTodayTab(isDark, text, sub, card, border),
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
        ],
      ),
    );
  }

  // ============================================================================
  // TAB 1: TODAY (Combined Briefing)
  // ============================================================================
  Widget _buildTodayTab(bool isDark, Color text, Color sub, Color card, Color border) {
    final trending = _pulse['trending_now'] as List? ?? [];
    final emerging = _pulse['emerging_opportunities'] as List? ?? [];
    final avoid = _pulse['overbooked_avoid'] as List? ?? [];
    final briefing = _pulse['morning_briefing']?.toString() ?? '';
    final actions = _pulse['action_today'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (briefing.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFFFF6B35), Color(0xFFFF3CAC)]),
              borderRadius: AppRadius.lg,
              boxShadow: [BoxShadow(color: const Color(0xFFFF6B35).withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 4))]
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('☀️ MORNING BRIEFING', style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
              const SizedBox(height: 8),
              Text(briefing, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5, fontWeight: FontWeight.w500)),
              const SizedBox(height: 10),
              Text(_pulse['date']?.toString() ?? '', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ]),
          ).animate().slideY(begin: 0.1, curve: Curves.easeOutQuad).fadeIn(),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        _sectionHeader('🔥 EXPLODING DEMAND', sub),
        ...trending.asMap().entries.map((e) => _trendCard(
          e.value.toString(), 'High Volume', 
          [AppColors.primary, AppColors.accent, AppColors.gold][e.key % 3], 
          isDark, text, sub
        ).animate().fadeIn(delay: Duration(milliseconds: e.key * 100))),

        const SizedBox(height: 20),
        _sectionHeader('🚀 EARLY OPPORTUNITIES', sub),
        ...emerging.map((e) => _trendCard(e.toString(), 'Low Competition', AppColors.success, isDark, text, sub)),

        const SizedBox(height: 20),
        _sectionHeader('⚠️ SATURATED MARKETS', sub),
        ...avoid.map((e) => _avoidCard(e.toString(), text)),

        const SizedBox(height: 24),
        _infoSection('📊 Platform Intelligence', _pulse['platform_intelligence'], isDark, text),
        _infoSection('📈 Rate Trends', _pulse['rate_trends'], isDark, text),
        
        // Action Today
        if (actions.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionHeader('✅ ACTIONS FOR TODAY', sub),
          ...actions.asMap().entries.map((e) => _actionCard('${e.key + 1}', e.value.toString(), AppColors.primary, isDark, text)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 2: INTERNATIONAL (Global Market Impulse)
  // ============================================================================
  Widget _buildInternationalTab(bool isDark, Color text, Color sub, Color card) {
    if (_international.isEmpty && !_loadingInternational) {
      _loadInternational();
      return _buildLoadingState('Loading global market intelligence...');
    }
    if (_loadingInternational) {
      return _buildLoadingState('Analyzing global trends...');
    }

    final globalTrends = _international['global_trends'] as Map? ?? {};
    final emergingSectors = _international['emerging_sectors'] as List? ?? [];
    final geoArbitrage = _international['geographic_arbitrage'] as List? ?? [];
    final futureProofing = _international['future_proofing'] as Map? ?? {};
    final skillMatches = _international['your_skill_matches'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPremiumBanner(
          '🌍 INTERNATIONAL MARKET IMPULSE',
          'Global trends & opportunities',
          [const Color(0xFF667eea), const Color(0xFF764ba2)],
        ),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        // Tech Adoption Impact
        if (globalTrends['tech_adoption_impact'] != null)
          _insightCard(
            '⚡ Tech Adoption Impact',
            globalTrends['tech_adoption_impact'].toString(),
            AppColors.info,
            isDark,
            text,
          ),

        // Fastest Growing Roles
        if (globalTrends['fastest_growing_roles'] != null) ...[
          const SizedBox(height: 20),
          _sectionHeader('📈 FASTEST GROWING ROLES', sub),
          ...(globalTrends['fastest_growing_roles'] as List).map((role) => _roleCard(role, isDark, text, sub)),
        ],

        // Declining Roles
        if (globalTrends['declining_roles'] != null) ...[
          const SizedBox(height: 20),
          _sectionHeader('📉 ROLES TO AVOID', sub),
          ...(globalTrends['declining_roles'] as List).take(5).map((role) => _avoidCard(role.toString(), text)),
        ],

        // Emerging Sectors
        const SizedBox(height: 20),
        _sectionHeader('🚀 EMERGING SECTORS', sub),
        ...emergingSectors.asMap().entries.map((e) => _sectorCard(e.value, e.key, isDark, text, sub)),

        // Geographic Arbitrage
        if (geoArbitrage.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('🌏 GEOGRAPHIC ARBITRAGE', sub),
          ...geoArbitrage.map((geo) => _geoArbitrageCard(geo, isDark, text, sub)),
        ],

        // Future Proofing
        if (futureProofing.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('🛡️ FUTURE-PROOFING', sub),
          if (futureProofing['immediate_skills'] != null)
            _skillListCard('Skills to Acquire Now', futureProofing['immediate_skills'] as List, AppColors.success, isDark, text),
          if (futureProofing['ai_augmentation'] != null)
            _insightCard('🤖 AI Strategy', futureProofing['ai_augmentation'].toString(), AppColors.accent, isDark, text),
        ],

        // Skill Matches
        if (skillMatches.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('🎯 YOUR SKILL MATCHES', sub),
          ...skillMatches.map((match) => _skillMatchCard(match, isDark, text, sub)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 3: LOCAL (Local Market Trends)
  // ============================================================================
  Widget _buildLocalTab(bool isDark, Color text, Color sub, Color card) {
    if (_local.isEmpty && !_loadingLocal) {
      _loadLocal();
      return _buildLoadingState('Loading local market data...');
    }
    if (_loadingLocal) {
      return _buildLoadingState('Analyzing local trends...');
    }

    final economicIndicators = _local['economic_indicators'] as Map? ?? {};
    final skillDemand = _local['skill_demand'] as Map? ?? {};
    final platforms = _local['platform_landscape'] as List? ?? [];
    final recommendations = _local['local_recommendations'] as Map? ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPremiumBanner(
          '📍 LOCAL MARKET TRENDS',
          'Country-specific insights',
          [const Color(0xFFf093fb), const Color(0xFFf5576c)],
        ),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        // Economic Indicators
        if (economicIndicators.isNotEmpty) ...[
          _sectionHeader('📊 ECONOMIC PULSE', sub),
          _economicIndicatorsCard(economicIndicators, isDark, text, sub),
        ],

        // Hot Skills
        if (skillDemand['hot_skills'] != null) ...[
          const SizedBox(height: 20),
          _sectionHeader('🔥 HOT SKILLS LOCALLY', sub),
          ...(skillDemand['hot_skills'] as List).map((skill) => _hotSkillCard(skill, isDark, text, sub)),
        ],

        // Oversaturated
        if (skillDemand['oversaturated'] != null) ...[
          const SizedBox(height: 20),
          _sectionHeader('⚠️ OVERSATURATED SKILLS', sub),
          ...(skillDemand['oversaturated'] as List).take(5).map((skill) => _avoidCard(skill.toString(), text)),
        ],

        // Platform Landscape
        if (platforms.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('💼 PLATFORM INTELLIGENCE', sub),
          ...platforms.map((platform) => _platformCard(platform, isDark, text, sub)),
        ],

        // Seasonal Context
        if (_local['seasonal_context'] != null)
          _infoSection('🗓️ SEASONAL CONTEXT', _local['seasonal_context'], isDark, text),

        // Cultural Notes
        if (_local['cultural_notes'] != null)
          _infoSection('🎭 CULTURAL INSIGHTS', _local['cultural_notes'], isDark, text),

        // Recommendations
        if (recommendations.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionHeader('💡 LOCAL RECOMMENDATIONS', sub),
          if (recommendations['platforms_to_join'] != null)
            _skillListCard('Platforms to Join', recommendations['platforms_to_join'] as List, AppColors.primary, isDark, text),
          if (recommendations['skills_to_highlight'] != null)
            _skillListCard('Skills to Highlight', recommendations['skills_to_highlight'] as List, AppColors.success, isDark, text),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 4: CAREER (Career Forecasting)
  // ============================================================================
  Widget _buildCareerTab(bool isDark, Color text, Color sub, Color card) {
    if (_careerForecast.isEmpty && !_loadingCareer) {
      _loadCareerForecast();
      return _buildLoadingState('Generating career forecast...');
    }
    if (_loadingCareer) {
      return _buildLoadingState('Analyzing career paths...');
    }

    final careerPaths = _careerForecast['career_paths'] as List? ?? [];
    final recommendedPath = _careerForecast['recommended_path'] as Map?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPremiumBanner(
          '🎯 CAREER FORECAST',
          'Your personalized path forward',
          [const Color(0xFF4facfe), const Color(0xFF00f2fe)],
        ),

        // Timeframe Filter
        _buildTimeframeFilter(isDark, text, sub),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        // Recommended Path
        if (recommendedPath != null) ...[
          _sectionHeader('⭐ RECOMMENDED PATH', sub),
          _careerPathCard(recommendedPath, true, isDark, text, sub),
        ],

        // All Paths
        if (careerPaths.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('📋 ALL CAREER PATHS', sub),
          ...careerPaths.take(5).map((path) => _careerPathCard(path, false, isDark, text, sub)),
        ],

        // Watch Ad for More
        const SizedBox(height: 24),
        _buildRewardAdButton(
          '🔓 Unlock Premium Career Insights',
          'Watch a short video to get 3 additional career paths',
          () => _loadCareerForecast(),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 5: ENTREPRENEURIAL (Business Opportunities)
  // ============================================================================
  Widget _buildEntrepreneurialTab(bool isDark, Color text, Color sub, Color card) {
    if (_entrepreneurial.isEmpty && !_loadingEntrepreneurial) {
      _loadEntrepreneurial();
      return _buildLoadingState('Scanning business opportunities...');
    }
    if (_loadingEntrepreneurial) {
      return _buildLoadingState('Finding opportunities...');
    }

    final opportunities = _entrepreneurial['opportunities'] as List? ?? [];
    final recommendedFocus = _entrepreneurial['recommended_focus'] as Map?;
    final nextSteps = _entrepreneurial['next_steps'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPremiumBanner(
          '🚀 ENTREPRENEURIAL OPPORTUNITIES',
          'Start your business journey',
          [const Color(0xFFfa709a), const Color(0xFFfee140)],
        ),

        // Capital Tier Filter
        _buildCapitalTierFilter(isDark, text, sub),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        // Recommended Opportunity
        if (recommendedFocus != null) ...[
          _sectionHeader('💎 TOP OPPORTUNITY', sub),
          _opportunityCard(recommendedFocus, true, isDark, text, sub),
        ],

        // All Opportunities
        if (opportunities.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('📊 MORE OPPORTUNITIES', sub),
          ...opportunities.skip(1).take(4).map((opp) => _opportunityCard(opp, false, isDark, text, sub)),
        ],

        // Next Steps
        if (nextSteps.isNotEmpty) ...[
          const SizedBox(height: 24),
          _sectionHeader('📝 NEXT STEPS', sub),
          ...nextSteps.asMap().entries.map((e) => _actionCard('${e.key + 1}', e.value.toString(), AppColors.accent, isDark, text)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 6: WEALTH (Wealth Building Strategies)
  // ============================================================================
  Widget _buildWealthTab(bool isDark, Color text, Color sub, Color card) {
    if (_wealthStrategies.isEmpty && !_loadingWealth) {
      _loadWealthStrategies();
      return _buildLoadingState('Building wealth strategies...');
    }
    if (_loadingWealth) {
      return _buildLoadingState('Calculating strategies...');
    }

    final strategies = _wealthStrategies['strategies'] as List? ?? [];
    final quickWins = _wealthStrategies['quick_wins'] as List? ?? [];
    final longTerm = _wealthStrategies['long_term_builders'] as List? ?? [];
    final userProfile = _wealthStrategies['user_profile'] as Map? ?? {};

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPremiumBanner(
          '💰 WEALTH BUILDING',
          'Strategies for financial growth',
          [const Color(0xFF30cfd0), const Color(0xFF330867)],
        ),

        // Risk Filter
        _buildRiskFilter(isDark, text, sub),

        // User Profile Summary
        if (userProfile.isNotEmpty)
          _userProfileCard(userProfile, isDark, text, sub),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        // Quick Wins
        if (quickWins.isNotEmpty) ...[
          _sectionHeader('⚡ QUICK WINS', sub),
          ...quickWins.map((s) => _strategyCard(s, AppColors.success, isDark, text, sub)),
        ],

        // Long Term Builders
        if (longTerm.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('🏗️ LONG-TERM BUILDERS', sub),
          ...longTerm.map((s) => _strategyCard(s, AppColors.primary, isDark, text, sub)),
        ],

        // All Strategies
        if (strategies.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('📈 ALL STRATEGIES', sub),
          ...strategies.skip(quickWins.length + longTerm.length).take(3).map(
            (s) => _strategyCard(s, AppColors.accent, isDark, text, sub)
          ),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 7: GROWTH (Personal Growth)
  // ============================================================================
  Widget _buildGrowthTab(bool isDark, Color text, Color sub, Color card) {
    if (_personalGrowth.isEmpty && !_loadingGrowth) {
      _loadPersonalGrowth();
      return _buildLoadingState('Loading personal growth insights...');
    }
    if (_loadingGrowth) {
      return _buildLoadingState('Generating insights...');
    }

    final insights = _personalGrowth['insights'] as List? ?? [];
    final priorityAction = _personalGrowth['priority_action'] as Map?;
    final focusAreas = _personalGrowth['focus_areas'] as List? ?? [];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildPremiumBanner(
          '🌱 PERSONAL GROWTH',
          'Level up your mindset & skills',
          [const Color(0xFFa8edea), const Color(0xFFfed6e3)],
        ),

        // Inline Ad
        InlineAdWidget(ad: _adService.inlineBannerAd, isLoaded: _showInlineAd),

        // Priority Action
        if (priorityAction != null) ...[
          _sectionHeader('🎯 PRIORITY ACTION', sub),
          _growthCard(priorityAction, true, isDark, text, sub),
        ],

        // Focus Areas
        if (focusAreas.isNotEmpty) ...[
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: focusAreas.map((area) => Chip(
              label: Text(area.toString(), style: TextStyle(color: text, fontSize: 12)),
              backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
            )).toList(),
          ),
        ],

        // All Insights
        if (insights.isNotEmpty) ...[
          const SizedBox(height: 20),
          _sectionHeader('💡 ALL INSIGHTS', sub),
          ...insights.skip(1).map((insight) => _growthCard(insight, false, isDark, text, sub)),
        ],

        const SizedBox(height: 40),
      ],
    );
  }

  // ============================================================================
  // TAB 8: SCAN (Skill Scanner)
  // ============================================================================
  Widget _buildScanTab(bool isDark, Color text, Color sub, Color card) {
    final scanData = _scan['scan_results'] as Map? ?? {};
    final trending = _pulse['trending_now'] as List? ?? [];
    final suggestions = trending.take(8).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _buildPremiumBanner(
          '🔍 SKILL SCANNER',
          'Deep market analysis for any skill',
          [const Color(0xFFffecd2), const Color(0xFFfcb69f)],
        ),

        const SizedBox(height: 20),
        _sectionHeader('QUICK SCAN TRENDS', sub),
        Wrap(
          spacing: 8, 
          runSpacing: 8, 
          children: suggestions.map((s) => ChoiceChip(
            label: Text(s.toString(), style: TextStyle(fontSize: 11, color: _selectedSkill == s ? Colors.white : text)),
            selected: _selectedSkill == s,
            onSelected: (val) => _scanSkill(s.toString()),
            selectedColor: AppColors.primary,
            backgroundColor: isDark ? AppColors.bgCard : Colors.grey.shade100,
          )).toList()
        ),
        
        const SizedBox(height: 24),
        
        // Reward Ad Prompt
        if (_selectedSkill.isEmpty && _scan.isEmpty)
          _buildRewardAdButton(
            '🎁 Unlock Deep Scan',
            'Watch a short video to get detailed market analysis for any skill',
            () {},
          ),

        if (_scanning)
          const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
        else if (scanData.isNotEmpty) ...[
          _buildScanResult(scanData, isDark, text, sub),
        ] else if (_selectedSkill.isNotEmpty)
          _buildEmptyScanState(sub),
          
        const SizedBox(height: 40),
      ]),
    );
  }

  // ============================================================================
  // UI COMPONENTS
  // ============================================================================

  Widget _buildPremiumBanner(String title, String subtitle, List<Color> gradient) {
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
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    ).animate().slideY(begin: 0.1, curve: Curves.easeOutQuad).fadeIn();
  }

  Widget _buildLoadingState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: 16),
          Text(message, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTimeframeFilter(bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: ['all', 'immediate', 'short', 'long'].map((tf) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tf.toUpperCase(), style: TextStyle(fontSize: 11)),
              selected: _selectedTimeframe == tf,
              onSelected: (val) {
                setState(() => _selectedTimeframe = tf);
                _loadCareerForecast();
              },
              selectedColor: AppColors.primary,
              backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
            ),
          )).toList(),
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
          children: ['bootstrap', 'moderate', 'well-funded'].map((tier) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(tier.toUpperCase(), style: TextStyle(fontSize: 11)),
              selected: _selectedCapitalTier == tier,
              onSelected: (val) {
                setState(() => _selectedCapitalTier = tier);
                _loadEntrepreneurial();
              },
              selectedColor: AppColors.primary,
              backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
            ),
          )).toList(),
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
          children: ['conservative', 'moderate', 'aggressive'].map((risk) => Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(risk.toUpperCase(), style: TextStyle(fontSize: 11)),
              selected: _selectedRiskTolerance == risk,
              onSelected: (val) {
                setState(() => _selectedRiskTolerance = risk);
                _loadWealthStrategies();
              },
              selectedColor: AppColors.primary,
              backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
            ),
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildRewardAdButton(String title, String subtitle, VoidCallback onReward) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: ElevatedButton.icon(
        onPressed: () => _adService.showRewardedAd(
          onRewarded: onReward,
          onDismissed: () {},
        ),
        icon: const Icon(Icons.play_circle_outline, color: Colors.white),
        label: Column(
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text(subtitle, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w400)),
          ],
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lg),
        ),
      ),
    );
  }

  // Card Components
  Widget _trendCard(String title, String subtitle, Color color, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Row(children: [
        Container(width: 4, height: 32, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text)),
          Text(subtitle, style: TextStyle(fontSize: 11, color: sub)),
        ])),
        Icon(Icons.trending_up_rounded, size: 16, color: color.withOpacity(0.5)),
      ]),
    );
  }

  Widget _avoidCard(String title, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.05), borderRadius: AppRadius.md),
      child: Row(children: [
        const Icon(Icons.block, color: AppColors.error, size: 16),
        const SizedBox(width: 12),
        Text(title, style: TextStyle(fontSize: 13, color: text, fontWeight: FontWeight.w500)),
        const Spacer(),
        const Text('Saturated', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _actionCard(String number, String action, Color color, bool isDark, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: AppRadius.md,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: Center(child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(action, style: TextStyle(fontSize: 13, color: text, height: 1.4))),
        ],
      ),
    );
  }

  Widget _infoSection(String title, dynamic content, bool isDark, Color text) {
    if (content == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title.toUpperCase(), text.withOpacity(0.5)),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: isDark ? AppColors.bgCard : const Color(0xFFF8F9FA), borderRadius: AppRadius.lg),
          child: Text(content.toString(), style: TextStyle(fontSize: 13, color: text, height: 1.6)),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _insightCard(String title, String content, Color color, bool isDark, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 8),
          Text(content, style: TextStyle(fontSize: 13, color: text, height: 1.5)),
        ],
      ),
    );
  }

  Widget _roleCard(dynamic role, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  role['role']?.toString() ?? 'Unknown Role',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  role['growth_rate']?.toString() ?? '',
                  style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (role['avg_salary_usd'] != null) ...[
            const SizedBox(height: 4),
            Text(
              '\$${role['avg_salary_usd']}/year avg',
              style: TextStyle(fontSize: 12, color: sub),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectorCard(dynamic sector, int index, bool isDark, Color text, Color sub) {
    final colors = [AppColors.primary, AppColors.accent, AppColors.success, AppColors.gold, AppColors.info];
    final color = colors[index % colors.length];
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sector['sector']?.toString() ?? 'Unknown Sector',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (sector['market_size_growth'] != null)
            Text(
              sector['market_size_growth'].toString(),
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
            ),
          if (sector['top_opportunities'] != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (sector['top_opportunities'] as List).map((opp) => Chip(
                label: Text(opp.toString(), style: const TextStyle(fontSize: 10)),
                backgroundColor: color.withOpacity(0.1),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _geoArbitrageCard(dynamic geo, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.05),
            Colors.transparent,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Iconsax.global, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  geo['region']?.toString() ?? 'Unknown Region',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                ),
              ),
              if (geo['remote_friendly'] == true)
                const Icon(Iconsax.verify, size: 16, color: AppColors.success),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            geo['opportunity']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4),
          ),
        ],
      ),
    );
  }

  Widget _skillMatchCard(dynamic match, bool isDark, Color text, Color sub) {
    final colors = {
      'direct': AppColors.success,
      'adjacent': AppColors.accent,
      'transferable': AppColors.info,
    };
    final color = colors[match['match_type']] ?? AppColors.primary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.md,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  match['opportunity']?.toString() ?? '',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: text),
                ),
                const SizedBox(height: 2),
                Text(
                  'Matches: ${match['your_skill']}',
                  style: TextStyle(fontSize: 11, color: sub),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              match['match_type']?.toString().toUpperCase() ?? '',
              style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _skillListCard(String title, List skills, Color color, bool isDark, Color text) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: skills.map((skill) => Chip(
              label: Text(skill.toString(), style: const TextStyle(fontSize: 11)),
              backgroundColor: color.withOpacity(0.1),
              side: BorderSide.none,
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _economicIndicatorsCard(dynamic indicators, bool isDark, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
      ),
      child: Column(
        children: [
          _indicatorRow('Unemployment', indicators['unemployment_rate'], Iconsax.people, AppColors.error),
          const Divider(height: 16),
          _indicatorRow('Inflation', indicators['inflation_trend'], Iconsax.chart_2, AppColors.warning),
          const Divider(height: 16),
          _indicatorRow('Currency', indicators['currency_strength'], Iconsax.money, AppColors.success),
          const Divider(height: 16),
          _indicatorRow('GDP Growth', indicators['gdp_growth'], Iconsax.trend_up, AppColors.primary),
        ],
      ),
    );
  }

  Widget _indicatorRow(String label, dynamic value, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13)),
        const Spacer(),
        Text(
          value?.toString() ?? 'N/A',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
      ],
    );
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
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill['skill']?.toString() ?? '',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                ),
                if (skill['local_salary_range'] != null)
                  Text(
                    skill['local_salary_range'].toString(),
                    style: TextStyle(fontSize: 12, color: sub),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              skill['demand_level']?.toString().toUpperCase() ?? 'HIGH',
              style: const TextStyle(fontSize: 10, color: AppColors.success, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                platform['platform']?.toString() ?? '',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  platform['effectiveness']?.toString() ?? '',
                  style: const TextStyle(fontSize: 10, color: AppColors.primary),
                ),
              ),
            ],
          ),
          if (platform['payment_methods'] != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: (platform['payment_methods'] as List).map((method) => Chip(
                label: Text(method.toString(), style: const TextStyle(fontSize: 9)),
                backgroundColor: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _careerPathCard(dynamic path, bool isRecommended, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: isRecommended ? Border.all(color: AppColors.gold, width: 2) : null,
        boxShadow: isRecommended ? [BoxShadow(color: AppColors.gold.withOpacity(0.2), blurRadius: 10)] : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isRecommended)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(4)),
              child: const Text('RECOMMENDED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
          Text(
            path['title']?.toString() ?? '',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniBadge(path['current_demand']?.toString() ?? '', AppColors.success),
              const SizedBox(width: 8),
              _miniBadge(path['growth_projection']?.toString() ?? '', AppColors.info),
            ],
          ),
          const SizedBox(height: 12),
          if (path['salary_range_usd'] != null)
            Text(
              'Salary: \$${path['salary_range_usd']['min']} - \$${path['salary_range_usd']['max']}',
              style: TextStyle(fontSize: 12, color: sub),
            ),
          if (path['required_skills'] != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: (path['required_skills'] as List).take(5).map((skill) => Chip(
                label: Text(skill.toString(), style: const TextStyle(fontSize: 10)),
                backgroundColor: AppColors.primary.withOpacity(0.1),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _opportunityCard(dynamic opp, bool isFeatured, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: isFeatured ? Border.all(color: AppColors.gold, width: 2) : Border.all(color: AppColors.accent.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isFeatured)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(4)),
              child: const Text('FEATURED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
          Text(
            opp['sector']?.toString() ?? '',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
          ),
          const SizedBox(height: 8),
          Text(
            opp['problem_statement']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _miniBadge('Scale: ${opp['scalability_score']}/10', AppColors.primary),
              const SizedBox(width: 8),
              _miniBadge(opp['risk_level']?.toString() ?? '', AppColors.warning),
            ],
          ),
          if (opp['startup_cost_range_usd'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Startup Cost: \$${opp['startup_cost_range_usd']['min']} - \$${opp['startup_cost_range_usd']['max']}',
              style: TextStyle(fontSize: 12, color: sub),
            ),
          ],
        ],
      ),
    );
  }

  Widget _strategyCard(dynamic strategy, Color color, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  strategy['title']?.toString() ?? '',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  '${strategy['expected_roi_annual_percent']}%',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            strategy['description']?.toString() ?? '',
            style: TextStyle(fontSize: 12, color: sub, height: 1.4),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Iconsax.clock, size: 14, color: sub),
              const Sized SizedBox(width: 4),
              Text('${strategy['time_commitment_hours_week']} hrs/week', style: TextStyle(fontSize: 11, color: sub)),
              const SizedBox(width: 16),
             Box(width: 4),
              Text('${strategy['time_commitment_hours_week']} hrs/week', style: TextStyle(fontSize: 11, color: sub)),
              const SizedBox(width: 16),
              Icon(Iconsax.money, size: 14, color: sub),
              const SizedBox(width: 4),
              Text('\$${strategy['initial_capital_required_usd']} needed', style: TextStyle(fontSize: 11, color: sub)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _userProfileCard(dynamic profile, bool isDark, Color text, Color sub) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
        borderRadius: AppRadius.lg,
      ),
      child: Row(
        children: [
          Icon(Iconsax.user, size: 18, color: sub),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${profile['country']} • ${profile['income_level']} income', style: TextStyle(fontSize: 12, color: text)),
                Text('${profile['time_available_hours_week']} hrs/week available', style: TextStyle(fontSize: 11, color: sub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _growthCard(dynamic insight, bool isPriority, bool isDark, Color text, Color sub) {
    final categoryColors = {
      'mindset': AppColors.primary,
      'productivity': AppColors.accent,
      'networking': AppColors.success,
      'health': AppColors.error,
      'learning': AppColors.info,
    };
    final color = categoryColors[insight['category']] ?? AppColors.primary;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgCard : Colors.white,
        borderRadius: AppRadius.lg,
        border: isPriority ? Border.all(color: color, width: 2) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text(
                  insight['category']?.toString().toUpperCase() ?? '',
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color),
                ),
              ),
              if (isPriority) ...[
                const SizedBox(width: 8),
                const Icon(Iconsax.star_1, size: 14, color: AppColors.gold),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Text(
            insight['insight']?.toString() ?? '',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: color.withOpacity(0.05), borderRadius: AppRadius.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Iconsax.lamp_charge, size: 16, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    insight['actionable_tip']?.toString() ?? '',
                    style: TextStyle(fontSize: 12, color: text, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (insight['implementation_timeline'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Timeline: ${insight['implementation_timeline']}',
              style: TextStyle(fontSize: 11, color: sub, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildScanResult(Map data, bool isDark, Color text, Color sub) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LIVE MARKET REPORT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: AppColors.primary)),
        const SizedBox(height: 4),
        Text(_selectedSkill.toUpperCase(), style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: text)),
        const SizedBox(height: 16),
        _gridStat('Demand', data['demand_level'], Iconsax.flash),
        _gridStat('Platform', data['best_platform_now'], Iconsax.global),
        _gridStat('Avg Rate', '\$${data['average_rate_usd']}/hr', Iconsax.money),
        _gridStat('Momentum', data['momentum'], Iconsax.graph),
        const SizedBox(height: 20),
        _actionBox('NEXT STEP', data['action_today'], AppColors.success),
        if (data['fastest_path_to_client'] != null)
          _actionBox('FASTEST PATH', data['fastest_path_to_client'], AppColors.primary),
        if (data['niche_down_suggestion'] != null)
          _actionBox('NICHE DOWN', data['niche_down_suggestion'], AppColors.accent),
      ],
    ).animate().fadeIn();
  }

  Widget _gridStat(String label, dynamic val, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.03), borderRadius: AppRadius.md),
      child: Row(children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const Spacer(),
        Text(val?.toString() ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
    );
  }

  Widget _actionBox(String title, dynamic content, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: AppRadius.lg, border: Border.all(color: color.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 1)),
        const SizedBox(height: 8),
        Text(content?.toString() ?? '', style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sectionHeader(String title, Color sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 4),
      child: Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: sub, letterSpacing: 1.5)),
    );
  }

  Widget _buildEmptyScanState(Color sub) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          children: [
            Icon(Iconsax.search_status, size: 64, color: sub.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text('Select a skill above to perform a live AI market scan', textAlign: TextAlign.center, ‌‍
