// frontend/lib/screens/methods/methods_brain_screen.dart
//
// The 10,000 Ways to Make Money — Methods Brain Library
// Browse, filter, search and track income methods from $0 to $1B+

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';

import '../../services/api_service.dart';
import '../../providers/currency_provider.dart';

// ─────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────

class IncomeMethod {
  final String  id;
  final int     methodNumber;
  final String  title;
  final String  description;
  final String  category;
  final String  investmentTier;
  final String? timeToFirst;
  final String? skillLevel;
  final String? sectionEmoji;
  final String? sectionTitle;
  final List    tags;
  final double? earnLow;
  final double? earnHigh;
  final int     demandScore;
  final bool    isFeatured;
  final bool    trending;
  final String? howToStart;
  final List    firstSteps;
  final List    platforms;

  IncomeMethod.fromJson(Map j)
      : id            = j['id']           ?? '',
        methodNumber  = (j['method_number'] as num?)?.toInt() ?? 0,
        title         = j['title']         ?? '',
        description   = j['description']   ?? '',
        category      = j['category']      ?? 'online',
        investmentTier= j['investment_tier']?? 'zero',
        timeToFirst   = j['time_to_first_dollar'],
        skillLevel    = j['skill_level'],
        sectionEmoji  = j['section_emoji'],
        sectionTitle  = j['section_title'],
        tags          = (j['tags'] as List?) ?? [],
        earnLow       = (j['avg_earning_monthly_usd_low'] as num?)?.toDouble(),
        earnHigh      = (j['avg_earning_monthly_usd_high'] as num?)?.toDouble(),
        demandScore   = (j['global_demand_score'] as num?)?.toInt() ?? 50,
        isFeatured    = j['is_featured'] == true,
        trending      = j['trending'] == true,
        howToStart    = j['how_to_start'],
        firstSteps    = (j['first_steps'] as List?) ?? [],
        platforms     = (j['platforms'] as List?) ?? [];
}

// ─────────────────────────────────────────────────────────────────
// TIER CONFIG
// ─────────────────────────────────────────────────────────────────

const _tiers = [
  {'id': '',         'label': 'All',        'emoji': '🌎', 'color': Color(0xFF6C63FF)},
  {'id': 'zero',     'label': '\$0',        'emoji': '🟢', 'color': Color(0xFF4CAF50)},
  {'id': 'micro',    'label': '\$1–\$500',  'emoji': '🟢', 'color': Color(0xFF66BB6A)},
  {'id': 'low',      'label': '\$500–\$10K','emoji': '🟡', 'color': Color(0xFFFFC107)},
  {'id': 'medium',   'label': '\$10K–\$100K','emoji': '🟠', 'color': Color(0xFFFF9800)},
  {'id': 'high',     'label': '\$100K–\$1M','emoji': '🔴', 'color': Color(0xFFFF5722)},
  {'id': 'major',    'label': '\$1M+',      'emoji': '🔴🔴','color': Color(0xFFF44336)},
  {'id': 'billion',  'label': '\$1B+',      'emoji': '💎', 'color': Color(0xFF9C27B0)},
];

// ─────────────────────────────────────────────────────────────────
// STATE
// ─────────────────────────────────────────────────────────────────

class _MethodsState {
  final List<IncomeMethod> methods;
  final bool               isLoading;
  final bool               hasMore;
  final String?            error;
  final String             selectedTier;
  final String             searchQuery;
  final int                offset;

  const _MethodsState({
    this.methods     = const [],
    this.isLoading   = false,
    this.hasMore     = true,
    this.error,
    this.selectedTier = '',
    this.searchQuery  = '',
    this.offset       = 0,
  });

  _MethodsState copyWith({
    List<IncomeMethod>? methods,
    bool? isLoading,
    bool? hasMore,
    String? error,
    String? selectedTier,
    String? searchQuery,
    int? offset,
  }) => _MethodsState(
    methods:      methods      ?? this.methods,
    isLoading:    isLoading    ?? this.isLoading,
    hasMore:      hasMore      ?? this.hasMore,
    error:        error        ?? this.error,
    selectedTier: selectedTier ?? this.selectedTier,
    searchQuery:  searchQuery  ?? this.searchQuery,
    offset:       offset       ?? this.offset,
  );
}

class _MethodsNotifier extends StateNotifier<_MethodsState> {
  _MethodsNotifier() : super(const _MethodsState()) { load(); }

  Future<void> load({bool reset = false}) async {
    if (state.isLoading) return;
    if (!reset && !state.hasMore) return;

    final newOffset = reset ? 0 : state.offset;
    if (reset) state = state.copyWith(methods: [], offset: 0, hasMore: true, error: null);

    state = state.copyWith(isLoading: true, error: null);

    try {
      final params = <String, dynamic>{
        'limit': 20,
        'offset': newOffset,
      };
      if (state.selectedTier.isNotEmpty)
        params['investment_tier'] = state.selectedTier;
      if (state.searchQuery.isNotEmpty)
        params['search'] = state.searchQuery;

      final res = await api.get('/brain/methods', queryParams: params);
      final data = (res as Map?)?['methods'] as List? ?? [];

      final newMethods = data.map((m) => IncomeMethod.fromJson(m)).toList();
      state = state.copyWith(
        methods:   reset ? newMethods : [...state.methods, ...newMethods],
        isLoading: false,
        hasMore:   newMethods.length == 20,
        offset:    newOffset + newMethods.length,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setTier(String tier) {
    state = state.copyWith(selectedTier: tier);
    load(reset: true);
  }

  void setSearch(String q) {
    state = state.copyWith(searchQuery: q);
    load(reset: true);
  }

  Future<void> loadMore() => load(reset: false);
}

final _methodsProvider = StateNotifierProvider<_MethodsNotifier, _MethodsState>(
  (_) => _MethodsNotifier(),
);

// ─────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────

class MethodsBrainScreen extends ConsumerStatefulWidget {
  const MethodsBrainScreen({super.key});

  @override
  ConsumerState<MethodsBrainScreen> createState() => _MethodsBrainScreenState();
}

class _MethodsBrainScreenState extends ConsumerState<MethodsBrainScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  Timer?               _debounce;
  IncomeMethod?        _selectedMethod;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels > _scrollCtrl.position.maxScrollExtent - 300) {
      ref.read(_methodsProvider.notifier).loadMore();
    }
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      ref.read(_methodsProvider.notifier).setSearch(q);
    });
  }

  @override
  Widget build(BuildContext context) {
    final st  = ref.watch(_methodsProvider);
    final cs  = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_selectedMethod != null) {
      return _MethodDetailScreen(
        method:  _selectedMethod!,
        onBack:  () => setState(() => _selectedMethod = null),
      );
    }

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF6C63FF), Color(0xFF3B82F6)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Iconsax.cpu, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Methods Brain',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold,
                        color: cs.onSurface)),
                Text('10,000 ways to make money',
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Iconsax.cpu),
            tooltip: 'Ask Mentor',
            onPressed: () => context.push('/agent'),
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged:  _onSearchChanged,
              decoration: InputDecoration(
                hintText:    'Search 10,000 income methods...',
                prefixIcon:  const Icon(Iconsax.search_normal_1, size: 20),
                suffixIcon:  _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Iconsax.close_circle, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(_methodsProvider.notifier).setSearch('');
                        })
                    : null,
                filled:      true,
                fillColor:   cs.surfaceContainerHigh,
                border:      OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide:   BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),

          // Tier filter chips
          SizedBox(
            height: 52,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _tiers.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final tier     = _tiers[i];
                final isSelected = st.selectedTier == tier['id'];
                final color    = tier['color'] as Color;
                return FilterChip(
                  label: Text(
                      '${tier['emoji']}  ${tier['label']}',
                      style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? Colors.white : cs.onSurface,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                  selected:     isSelected,
                  onSelected:   (_) => ref.read(_methodsProvider.notifier).setTier(tier['id'] as String),
                  backgroundColor: cs.surfaceContainerLow,
                  selectedColor:   color,
                  checkmarkColor:  Colors.white,
                  side:            BorderSide(
                      color: isSelected ? color : cs.outlineVariant, width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                );
              },
            ),
          ),

          // Stats bar
          if (!st.isLoading && st.methods.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Text(
                    st.selectedTier.isEmpty
                        ? 'Showing all methods'
                        : 'Filtered: ${_tiers.firstWhere((t) => t['id'] == st.selectedTier, orElse: () => _tiers[0])['label']}',
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  Text('${st.methods.length}+ methods',
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),

          // Methods list
          Expanded(
            child: st.error != null
                ? _ErrorState(error: st.error!, onRetry: () =>
                    ref.read(_methodsProvider.notifier).load(reset: true))
                : st.isLoading && st.methods.isEmpty
                    ? _LoadingGrid()
                    : st.methods.isEmpty
                        ? _EmptyState()
                        : ListView.builder(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
                            itemCount: st.methods.length +
                                (st.isLoading && st.methods.isNotEmpty ? 1 : 0),
                            itemBuilder: (ctx, i) {
                              if (i == st.methods.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Center(child: CircularProgressIndicator()),
                                );
                              }
                              return _MethodCard(
                                method: st.methods[i],
                                onTap:  () => setState(
                                    () => _selectedMethod = st.methods[i]),
                              ).animate().fadeIn(
                                  duration: 250.ms, delay: (i * 30).ms);
                            },
                          ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/agent'),
        icon:  const Icon(Iconsax.cpu),
        label: const Text('Ask AI Mentor'),
        backgroundColor: const Color(0xFF6C63FF),
        foregroundColor: Colors.white,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// METHOD CARD
// ─────────────────────────────────────────────────────────────────

class _MethodCard extends StatelessWidget {
  final IncomeMethod method;
  final VoidCallback onTap;
  const _MethodCard({required this.method, required this.onTap});

  static const _tierColors = <String, Color>{
    'zero':    Color(0xFF4CAF50),
    'micro':   Color(0xFF66BB6A),
    'low':     Color(0xFFFFC107),
    'medium':  Color(0xFFFF9800),
    'high':    Color(0xFFFF5722),
    'major':   Color(0xFFF44336),
    'ultra':   Color(0xFF9C27B0),
    'billion': Color(0xFF673AB7),
  };

  @override
  Widget build(BuildContext context) {
    final cs    = Theme.of(context).colorScheme;
    final color = _tierColors[method.investmentTier] ?? const Color(0xFF6C63FF);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:         cs.surfaceContainerLow,
          borderRadius:  BorderRadius.circular(16),
          border:        Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Method number + emoji
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color:  color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      method.sectionEmoji ?? '💡',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        method.title,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize:   14,
                            color:      cs.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '#${method.methodNumber} · ${method.sectionTitle ?? method.category}',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                // Tier badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:  color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(
                    method.investmentTier.toUpperCase(),
                    style: TextStyle(
                        fontSize:   9,
                        fontWeight: FontWeight.bold,
                        color:      color),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),
            Text(
              method.description,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurfaceVariant, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 10),
            Row(
              children: [
                // Earnings
                if (method.earnLow != null && method.earnLow! > 0) ...[
                  Icon(Iconsax.money_send, size: 13, color: cs.primary),
                  const SizedBox(width: 4),
                  Text(
                    '\$${_fmt(method.earnLow!)}–\$${_fmt(method.earnHigh ?? 0)}/mo',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.primary),
                  ),
                  const SizedBox(width: 12),
                ],
                // Time to first $
                if (method.timeToFirst != null) ...[
                  Icon(Iconsax.clock, size: 13, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    '${method.timeToFirst} to first \$',
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                ],
                const Spacer(),
                // Demand score
                Row(
                  children: [
                    Text(
                      '${method.demandScore}%',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color:      _demandColor(method.demandScore)),
                    ),
                    const SizedBox(width: 3),
                    Text('demand',
                        style: TextStyle(
                            fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ],
            ),

            // Tags
            if (method.tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: method.tags.take(4).map((tag) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag.toString(),
                      style: TextStyle(
                          fontSize: 10, color: cs.onPrimaryContainer),
                    ),
                  );
                }).toList(),
              ),
            ],

            // Badges
            if (method.trending || method.isFeatured) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  if (method.trending)
                    _Badge('🔥 Trending', const Color(0xFFFF5722)),
                  if (method.isFeatured) ...[
                    if (method.trending) const SizedBox(width: 6),
                    _Badge('⭐ Featured', const Color(0xFFFFB300)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  Color _demandColor(int score) {
    if (score >= 85) return const Color(0xFF4CAF50);
    if (score >= 70) return const Color(0xFFFFC107);
    return const Color(0xFFFF5722);
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// METHOD DETAIL SCREEN
// ─────────────────────────────────────────────────────────────────

class _MethodDetailScreen extends ConsumerWidget {
  final IncomeMethod method;
  final VoidCallback onBack;
  const _MethodDetailScreen({required this.method, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs    = Theme.of(context).colorScheme;
    final color = const {
      'zero': Color(0xFF4CAF50), 'micro': Color(0xFF66BB6A),
      'low': Color(0xFFFFC107), 'medium': Color(0xFFFF9800),
      'high': Color(0xFFFF5722), 'major': Color(0xFFF44336),
      'ultra': Color(0xFF9C27B0), 'billion': Color(0xFF673AB7),
    }[method.investmentTier] ?? const Color(0xFF6C63FF);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        leading: IconButton(
            icon: const Icon(Iconsax.arrow_left),
            onPressed: onBack),
        title: Text('#${method.methodNumber} Method',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold,
                color: cs.onSurface)),
        actions: [
          // Track method button
          TextButton.icon(
            onPressed: () => _trackMethod(context, ref),
            icon: const Icon(Iconsax.add_circle, size: 16),
            label: const Text('Track'),
            style: TextButton.styleFrom(foregroundColor: cs.primary),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Hero
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withOpacity(0.15), color.withOpacity(0.05)]),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      method.sectionEmoji ?? '💡',
                      style: const TextStyle(fontSize: 40),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(method.title,
                              style: const TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              method.investmentTier.toUpperCase(),
                              style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(method.description,
                    style: TextStyle(
                        fontSize: 14, color: cs.onSurfaceVariant, height: 1.5)),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 20),

          // Stats row
          Row(
            children: [
              _StatChip('⏱', method.timeToFirst ?? 'weeks', 'To first \$'),
              const SizedBox(width: 10),
              _StatChip('📶', method.skillLevel ?? 'basic', 'Skill needed'),
              const SizedBox(width: 10),
              _StatChip('📊', '${method.demandScore}%', 'Demand'),
            ],
          ),

          if (method.earnLow != null && method.earnLow! > 0) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Iconsax.money_4, color: cs.primary, size: 24),
                  const SizedBox(width: 10),
                  Column(
                    children: [
                      Text(
                        '\$${_fmt(method.earnLow!)} – \$${_fmt(method.earnHigh ?? 0)}',
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: cs.primary),
                      ),
                      Text('per month potential',
                          style: TextStyle(
                              fontSize: 12, color: cs.onSurfaceVariant)),
                    ],
                  ),
                ],
              ),
            ),
          ],

          if (method.howToStart != null) ...[
            const SizedBox(height: 20),
            _SectionHeader('How to Start', Iconsax.flash),
            const SizedBox(height: 8),
            Text(method.howToStart!,
                style: TextStyle(
                    fontSize: 14, color: cs.onSurfaceVariant, height: 1.5)),
          ],

          if (method.firstSteps.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('First Steps', Iconsax.task_square),
            const SizedBox(height: 8),
            ...method.firstSteps.asMap().entries.map((e) =>
                _StepRow(e.key + 1, e.value.toString())),
          ],

          if (method.platforms.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionHeader('Key Platforms', Iconsax.global),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: method.platforms.map((p) =>
                  _PlatformChip(p.toString())).toList(),
            ),
          ],

          const SizedBox(height: 28),

          // Action buttons
          ElevatedButton.icon(
            onPressed: () {
              context.push('/agent');
            },
            icon: const Icon(Iconsax.cpu, size: 18),
            label: Text('Ask AI Mentor — Help me start ${method.title}'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6C63FF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: () => _trackMethod(context, ref),
            icon: const Icon(Iconsax.add_circle, size: 18),
            label: const Text('Add to My Methods'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _trackMethod(BuildContext context, WidgetRef ref) async {
    try {
      await api.post('/brain/methods/${method.id}/track', {'status': 'exploring'});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${method.title} to your methods!'),
            backgroundColor: const Color(0xFF4CAF50),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  String _fmt(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000)    return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

// ─────────────────────────────────────────────────────────────────
// HELPER WIDGETS
// ─────────────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String emoji;
  final String value;
  final String label;
  const _StatChip(this.emoji, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: cs.onSurface),
                textAlign: TextAlign.center),
            Text(label,
                style: TextStyle(
                    fontSize: 10, color: cs.onSurfaceVariant),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String  label;
  final IconData icon;
  const _SectionHeader(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: cs.primary),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: cs.onSurface)),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final int    number;
  final String text;
  const _StepRow(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22, height: 22,
            decoration: BoxDecoration(
                color: cs.primary, shape: BoxShape.circle),
            child: Center(
              child: Text('$number',
                  style: TextStyle(
                      color: cs.onPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurfaceVariant, height: 1.5)),
          ),
        ],
      ),
    );
  }
}

class _PlatformChip extends StatelessWidget {
  final String label;
  const _PlatformChip(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.4),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.primary.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: cs.onPrimaryContainer)),
    );
  }
}

class _LoadingGrid extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 8,
      itemBuilder: (_, i) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        height: 120,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
      ).animate(onPlay: (c) => c.repeat(reverse: true))
          .shimmer(duration: 1200.ms),
    );
  }
}

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.search_normal_1, size: 64,
              color: cs.primary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No methods found',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: cs.onSurface)),
          const SizedBox(height: 8),
          Text('Try a different search or filter',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String    error;
  final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Iconsax.warning_2, size: 48, color: cs.error),
          const SizedBox(height: 16),
          Text('Something went wrong', style: TextStyle(color: cs.error)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
