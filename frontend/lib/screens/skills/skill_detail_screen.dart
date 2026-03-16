import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class SkillDetailScreen extends StatefulWidget {
  final String moduleId;
  const SkillDetailScreen({super.key, required this.moduleId});
  @override
  State<SkillDetailScreen> createState() => _SkillDetailScreenState();
}

class _SkillDetailScreenState extends State<SkillDetailScreen> {
  Map? _module;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getSkillModules();
      final modules = data['modules'] as List? ?? [];
      final m = modules.firstWhere((m) => m['id'] == widget.moduleId, orElse: () => null);
      setState(() { _module = m; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    if (_module == null) return Scaffold(appBar: AppBar(), body: const Center(child: Text('Module not found')));

    final lessons = (_module!['lessons'] as List?) ?? [];
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text(_module!['title'] ?? '', style: AppTextStyles.h4),
        leading: IconButton(icon: const Icon(Icons.arrow_back_rounded), onPressed: () => context.pop()),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_module!['title'] ?? '', style: AppTextStyles.h3),
                  const SizedBox(height: 8),
                  Text(_module!['description'] ?? '', style: AppTextStyles.body),
                  const SizedBox(height: 16),
                  Row(children: [
                    _Chip('${_module!['duration_days']} days', AppColors.primary),
                    const SizedBox(width: 8),
                    _Chip(_module!['difficulty'] ?? '', AppColors.accent),
                    const SizedBox(width: 8),
                    _Chip(_module!['income_potential'] ?? '', AppColors.success),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Course Lessons', style: AppTextStyles.h4),
            const SizedBox(height: 12),
            ...lessons.asMap().entries.map((e) {
              final lesson = e.value as Map;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.bgCard, borderRadius: AppRadius.md),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                      child: Center(child: Text('${lesson['day']}', style: AppTextStyles.label.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(lesson['title'] ?? '', style: AppTextStyles.h4.copyWith(fontSize: 14)),
                          const SizedBox(height: 2),
                          Text('Task: ${lesson['task'] ?? ''}', style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip(this.label, this.color);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: AppRadius.pill),
      child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w600)),
    );
  }
}
