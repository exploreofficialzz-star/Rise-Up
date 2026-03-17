import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';
import '../../services/ad_service.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key});
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List _suggested = [], _active = [], _completed = [];
  bool _loading = false, _generating = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await api.getTasks() as List;
      setState(() {
        _suggested = all.where((t) => t['status'] == 'suggested').toList();
        _active = all.where((t) => t['status'] == 'in_progress').toList();
        _completed = all.where((t) => t['status'] == 'completed').toList();
        _loading = false;
      });
    } catch (_) { setState(() => _loading = false); }
  }

  Future<void> _generateTasks() async {
    setState(() => _generating = true);
    try {
      await api.generateTasks(count: 5);
      await _load();
    } catch (_) {
      setState(() => _generating = false);
    }
  }

  Future<void> _acceptTask(String id) async {
    await api.updateTask(id, status: 'in_progress');
    await _load();
  }

  Future<void> _completeTask(String id) async {
    double? earned;
    await showModalBottomSheet(
      context: context, backgroundColor: AppColors.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EarningsModal(onSave: (v) => earned = v),
    );
    await api.updateTask(id, status: 'completed', earnings: earned);
    await _load();
    if (mounted && earned != null && earned! > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('🎉 Earning logged! Keep it up!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
    // Show interstitial every 3rd task completion
    await adService.showInterstitialIfReady();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      appBar: AppBar(
        title: Text('Income Tasks', style: AppTextStyles.h3),
        bottom: TabBar(
          controller: _tabs,
          labelStyle: AppTextStyles.label.copyWith(fontWeight: FontWeight.w600),
          unselectedLabelStyle: AppTextStyles.label,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: [
            Tab(text: 'Suggested (${_suggested.length})'),
            Tab(text: 'Active (${_active.length})'),
            Tab(text: 'Done (${_completed.length})'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabs,
              children: [
                _TaskList(
                  tasks: _suggested,
                  emptyTitle: 'No tasks yet',
                  emptySubtitle: 'Generate AI-powered income tasks tailored for you',
                  emptyAction: GradientButton(
                    text: _generating ? 'Generating...' : '⚡ Generate Tasks',
                    onTap: _generating ? null : _generateTasks,
                    isLoading: _generating,
                  ),
                  onAccept: _acceptTask,
                  onRefresh: _load,
                ),
                _TaskList(
                  tasks: _active,
                  emptyTitle: 'No active tasks',
                  emptySubtitle: 'Accept tasks from suggestions to start working',
                  onComplete: _completeTask,
                  onRefresh: _load,
                ),
                _TaskList(
                  tasks: _completed,
                  emptyTitle: 'No completed tasks yet',
                  emptySubtitle: 'Complete your first task to see it here!',
                  isCompleted: true,
                  onRefresh: _load,
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _generating ? null : _generateTasks,
        backgroundColor: AppColors.primary,
        icon: _generating
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.add_rounded),
        label: Text(_generating ? 'Generating...' : 'New Tasks'),
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  final List tasks;
  final String emptyTitle, emptySubtitle;
  final Widget? emptyAction;
  final Function(String)? onAccept, onComplete;
  final Function() onRefresh;
  final bool isCompleted;

  const _TaskList({
    required this.tasks,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.emptyAction,
    this.onAccept,
    this.onComplete,
    required this.onRefresh,
    this.isCompleted = false,
  });

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(isCompleted ? Iconsax.medal : Iconsax.task, size: 64, color: AppColors.textMuted),
              const SizedBox(height: 16),
              Text(emptyTitle, style: AppTextStyles.h4, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(emptySubtitle, style: AppTextStyles.bodySmall, textAlign: TextAlign.center),
              if (emptyAction != null) ...[const SizedBox(height: 24), emptyAction!],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        itemBuilder: (_, i) => _TaskCard(
          task: tasks[i],
          onAccept: onAccept,
          onComplete: onComplete,
          isCompleted: isCompleted,
        ).animate().fadeIn(delay: Duration(milliseconds: i * 60)).slideY(begin: 0.1),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map task;
  final Function(String)? onAccept, onComplete;
  final bool isCompleted;
  const _TaskCard({required this.task, this.onAccept, this.onComplete, this.isCompleted = false});

  Color get _categoryColor {
    switch (task['category']) {
      case 'freelance': return AppColors.primary;
      case 'content': return AppColors.accent;
      case 'digital': return AppColors.gold;
      case 'gig': return AppColors.success;
      default: return AppColors.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: isCompleted ? AppColors.success.withOpacity(0.2) : AppColors.bgSurface),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: _categoryColor.withOpacity(0.15), borderRadius: AppRadius.pill),
                child: Text(task['category'] ?? '', style: AppTextStyles.caption.copyWith(color: _categoryColor, fontWeight: FontWeight.w600)),
              ),
              if (task['difficulty'] != null) ...[
                const SizedBox(width: 6),
                Text(_diffLabel(task['difficulty']), style: AppTextStyles.caption),
              ],
              const Spacer(),
              if (isCompleted) const Icon(Icons.check_circle, color: AppColors.success, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Text(task['title'] ?? '', style: AppTextStyles.h4.copyWith(fontSize: 15)),
          const SizedBox(height: 4),
          Text(task['description'] ?? '', style: AppTextStyles.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.attach_money, color: AppColors.success, size: 14),
              Text(
                task['actual_earnings'] != null && (task['actual_earnings'] as num) > 0
                    ? 'Earned: ${task['currency'] ?? 'NGN'} ${task['actual_earnings']}'
                    : 'Potential: ${task['currency'] ?? 'NGN'} ${task['estimated_earnings'] ?? '~'}',
                style: AppTextStyles.caption.copyWith(color: AppColors.success),
              ),
              if (task['platform'] != null) ...[
                const Spacer(),
                const Icon(Iconsax.global, size: 12, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(task['platform'], style: AppTextStyles.caption),
              ],
            ],
          ),
          if (!isCompleted && (task['steps'] as List?)?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _StepsPreview(steps: (task['steps'] as List).cast<String>()),
          ],
          if (!isCompleted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (onAccept != null) Expanded(
                  child: ElevatedButton(
                    onPressed: () => onAccept!(task['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                    ),
                    child: Text('Start Task ⚡', style: AppTextStyles.label.copyWith(color: Colors.white)),
                  ),
                ),
                if (onComplete != null) Expanded(
                  child: ElevatedButton(
                    onPressed: () => onComplete!(task['id']),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.md),
                    ),
                    child: Text('Mark Complete ✓', style: AppTextStyles.label.copyWith(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _diffLabel(String d) {
    switch (d) {
      case 'easy': return '🟢 Easy';
      case 'medium': return '🟡 Medium';
      case 'hard': return '🔴 Hard';
      default: return d;
    }
  }
}

class _StepsPreview extends StatelessWidget {
  final List<String> steps;
  const _StepsPreview({required this.steps});

  @override
  Widget build(BuildContext context) {
    final preview = steps.take(2).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: preview.asMap().entries.map((e) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${e.key + 1}. ', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
            Expanded(child: Text(e.value, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
      )).toList(),
    );
  }
}

class _EarningsModal extends StatefulWidget {
  final Function(double?) onSave;
  const _EarningsModal({required this.onSave});
  @override
  State<_EarningsModal> createState() => _EarningsModalState();
}

class _EarningsModalState extends State<_EarningsModal> {
  final _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('🎉 Amazing! How much did you earn?', style: AppTextStyles.h4),
          const SizedBox(height: 6),
          Text('Log your earnings to track your progress', style: AppTextStyles.bodySmall),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            keyboardType: TextInputType.number,
            style: AppTextStyles.body,
            decoration: InputDecoration(
              hintText: 'Amount earned (optional)',
              prefixText: '₦ ',
              prefixStyle: AppTextStyles.body.copyWith(color: AppColors.success),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () { widget.onSave(null); Navigator.pop(context); },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.bgSurface), padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Skip'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    widget.onSave(double.tryParse(_ctrl.text));
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Log Earning 💰'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
