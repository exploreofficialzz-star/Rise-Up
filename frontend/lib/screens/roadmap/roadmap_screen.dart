import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

class RoadmapScreen extends StatefulWidget {
  const RoadmapScreen({super.key});
  @override
  State<RoadmapScreen> createState() => _RoadmapScreenState();
}

class _RoadmapScreenState extends State<RoadmapScreen> {
  Map? _roadmap;
  bool _loading = true, _generating = false;
  bool _hasAccess = false;

  @override
  void initState() {
    super.initState();
    _checkAndLoad();
  }

  Future<void> _checkAndLoad() async {
    try {
      final access = await api.checkFeatureAccess(FeatureKeys.aiRoadmap);
      _hasAccess = access['has_access'] ?? false;
      if (_hasAccess) await _loadRoadmap();
      else setState(() => _loading = false);
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _loadRoadmap() async {
    setState(() => _loading = true);
    try {
      final data = await api.getRoadmap();
      setState(() { _roadmap = data['roadmap']; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final data = await api.generateRoadmap();
      setState(() { _roadmap = data['roadmap']; _generating = false; });
    } catch (_) { setState(() => _generating = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Wealth Roadmap', style: AppTextStyles.h3),
        actions: [
          if (_hasAccess && _roadmap != null)
            IconButton(
              icon: const Icon(Iconsax.refresh),
              onPressed: _generating ? null : _generate,
              tooltip: 'Regenerate',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : !_hasAccess
              ? _AccessGate(
                  onWatchAd: () async {
                    context.go('/payment?plan=monthly');
                  },
                  onSubscribe: () => context.go('/payment'),
                )
              : _roadmap == null
                  ? _EmptyRoadmap(onGenerate: _generate, generating: _generating)
                  : _RoadmapView(roadmap: _roadmap!, onRegenerate: _generate, generating: _generating),
    );
  }
}

class _AccessGate extends StatelessWidget {
  final VoidCallback onWatchAd, onSubscribe;
  const _AccessGate({required this.onWatchAd, required this.onSubscribe});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🗺️', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('Your Personalized Wealth Roadmap', style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('A 3-stage plan from where you are to where you want to be — tailored by AI to your exact situation.', style: AppTextStyles.body, textAlign: TextAlign.center),
            const SizedBox(height: 32),
            GradientButton(text: '👑 Unlock with Premium · \$15.99/mo', onTap: onSubscribe),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onWatchAd,
              child: Text('or watch an ad to unlock for 1 hour', style: AppTextStyles.label.copyWith(color: AppColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoadmap extends StatelessWidget {
  final VoidCallback onGenerate;
  final bool generating;
  const _EmptyRoadmap({required this.onGenerate, required this.generating});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚀', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text('Ready for your roadmap?', style: AppTextStyles.h3, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('AI will create a personalized 3-stage wealth plan based on your profile.', style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            GradientButton(text: generating ? 'Generating...' : 'Generate My Roadmap ✨', onTap: generating ? null : onGenerate, isLoading: generating),
          ],
        ),
      ),
    );
  }
}

class _RoadmapView extends StatelessWidget {
  final Map roadmap;
  final VoidCallback onRegenerate;
  final bool generating;
  const _RoadmapView({required this.roadmap, required this.onRegenerate, required this.generating});

  @override
  Widget build(BuildContext context) {
    final stages = [
      ('stage_1', '🎯', 'Stage 1', AppColors.survival),
      ('stage_2', '📈', 'Stage 2', AppColors.earning),
      ('stage_3', '💎', 'Stage 3', AppColors.wealth),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary
          if (roadmap['summary'] != null)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.15), AppColors.accent.withOpacity(0.05)]),
                borderRadius: AppRadius.lg,
                border: Border.all(color: AppColors.primary.withOpacity(0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.auto_awesome, color: AppColors.primary, size: 16),
                    const SizedBox(width: 8),
                    Text('AI Analysis', style: AppTextStyles.label.copyWith(color: AppColors.primary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(roadmap['summary'], style: AppTextStyles.body),
                ],
              ),
            ).animate().fadeIn(),

          if (roadmap['first_step_today'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.success.withOpacity(0.1), borderRadius: AppRadius.md, border: Border.all(color: AppColors.success.withOpacity(0.2))),
              child: Row(
                children: [
                  const Text('⚡', style: TextStyle(fontSize: 20)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Do this TODAY:', style: AppTextStyles.label.copyWith(color: AppColors.success, fontWeight: FontWeight.w700)),
                        Text(roadmap['first_step_today'], style: AppTextStyles.body.copyWith(fontSize: 13)),
                      ],
                    ),
                  ),
                ],
              ),
            ).animate().fadeIn(delay: 100.ms),
          ],

          const SizedBox(height: 24),
          Text('Your 3-Stage Journey', style: AppTextStyles.h4),
          const SizedBox(height: 16),

          ...stages.asMap().entries.map((entry) {
            final i = entry.key;
            final (key, emoji, label, color) = entry.value;
            final stage = roadmap[key] as Map? ?? {};
            if (stage.isEmpty) return const SizedBox();

            return _StageCard(
              emoji: emoji,
              label: label,
              stage: stage,
              color: color,
              isActive: roadmap['current_stage'] == _stageKey(i + 1),
            ).animate().fadeIn(delay: Duration(milliseconds: (i + 2) * 100)).slideY(begin: 0.2);
          }),

          if ((roadmap['recommended_skills'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 24),
            Text('Recommended Skills', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8, runSpacing: 8,
              children: (roadmap['recommended_skills'] as List).map((s) => GestureDetector(
                onTap: () => context.go('/skills'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: AppRadius.pill,
                    border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Iconsax.book, size: 12, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(s.toString(), style: AppTextStyles.bodySmall.copyWith(color: AppColors.primaryLight)),
                    ],
                  ),
                ),
              )).toList(),
            ).animate().fadeIn(delay: 500.ms),
          ],

          const SizedBox(height: 80),
        ],
      ),
    );
  }

  String _stageKey(int i) {
    switch (i) {
      case 1: return 'immediate_income';
      case 2: return 'skill_growth';
      case 3: return 'long_term_wealth';
      default: return '';
    }
  }
}

class _StageCard extends StatelessWidget {
  final String emoji, label;
  final Map stage;
  final Color color;
  final bool isActive;
  const _StageCard({required this.emoji, required this.label, required this.stage, required this.color, required this.isActive});

  @override
  Widget build(BuildContext context) {
    final milestones = (stage['milestones'] as List?) ?? [];
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: isActive ? color.withOpacity(0.5) : AppColors.bgSurface, width: isActive ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stage['title'] ?? label, style: AppTextStyles.h4.copyWith(color: color)),
                  Text(stage['duration'] ?? '', style: AppTextStyles.caption),
                ],
              ),
              const Spacer(),
              if (isActive) Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: AppRadius.pill),
                child: Text('Current', style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          if (stage['target_income'] != null) ...[
            const SizedBox(height: 8),
            Text('🎯 Target: ${stage['target_income']}', style: AppTextStyles.body.copyWith(color: color, fontSize: 13)),
          ],
          if (milestones.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...milestones.take(2).map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(m['title']?.toString() ?? '', style: AppTextStyles.bodySmall)),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}
