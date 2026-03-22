import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _contentCtrl = TextEditingController();
  String _selectedTag = '💰 Wealth';
  bool _loading = false;
  int _charCount = 0;
  static const int _maxChars = 500;

  static const _tags = [
    '💰 Wealth', '📈 Investing', '💼 Business', '🧠 Mindset',
    '⚡ Hustle', '🎯 Skills', '🏠 Real Estate', '💻 Tech',
    '📊 Budgeting', '🌱 Personal Growth', '💪 Finance', '🚀 Startups',
  ];

  @override
  void initState() {
    super.initState();
    _contentCtrl.addListener(() => setState(() => _charCount = _contentCtrl.text.length));
  }

  @override
  void dispose() { _contentCtrl.dispose(); super.dispose(); }

  Future<void> _post() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty || _loading) return;
    setState(() => _loading = true);
    try {
      await api.createPost(content: content, tag: _selectedTag);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Post shared! 🚀'), backgroundColor: AppColors.success, duration: Duration(seconds: 2)),
        );
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to post. Please try again.'), backgroundColor: AppColors.error),
        );
      }
    }
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
    final remaining = _maxChars - _charCount;
    final isOverLimit = remaining < 0;
    final canPost = _charCount > 0 && !isOverLimit && !_loading;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(icon: Icon(Icons.close, color: textColor), onPressed: () => context.go('/home')),
        title: Text('Create Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: GestureDetector(
              onTap: canPost ? _post : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: canPost ? const LinearGradient(colors: [AppColors.primary, AppColors.accent]) : null,
                  color: canPost ? null : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _loading
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: borderColor)),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // User header
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), shape: BoxShape.circle),
                  child: const Center(child: Text('👤', style: TextStyle(fontSize: 22))),
                ),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('You', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Text(_selectedTag, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ]).animate().fadeIn(),

              const SizedBox(height: 16),

              // Text input
              TextField(
                controller: _contentCtrl,
                maxLines: null, minLines: 6,
                style: TextStyle(fontSize: 16, color: textColor, height: 1.6),
                decoration: InputDecoration(
                  hintText: 'Share your wealth journey, tips, wins or lessons...\n\n💡 What did you learn today?\n💰 What income milestone did you hit?\n🚀 What strategy worked for you?',
                  hintStyle: TextStyle(color: subColor, fontSize: 14, height: 1.6),
                  border: InputBorder.none,
                  filled: false,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 16),

              // Tag selector
              Text('Topic', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: subColor)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _tags.map((tag) {
                  final selected = tag == _selectedTag;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTag = tag),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.primary : surfaceColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: selected ? AppColors.primary : borderColor),
                      ),
                      child: Text(tag, style: TextStyle(fontSize: 12, color: selected ? Colors.white : subColor, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
                    ),
                  );
                }).toList(),
              ).animate().fadeIn(delay: 150.ms),
            ]),
          ),
        ),

        // Bottom toolbar
        Container(
          decoration: BoxDecoration(color: cardColor, border: Border(top: BorderSide(color: borderColor))),
          padding: EdgeInsets.fromLTRB(16, 10, 16, MediaQuery.of(context).padding.bottom + 10),
          child: Row(children: [
            GestureDetector(onTap: () {}, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(10)), child: Icon(Iconsax.image, color: subColor, size: 20))),
            const SizedBox(width: 10),
            GestureDetector(onTap: () {}, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(10)), child: Icon(Iconsax.video, color: subColor, size: 20))),
            const SizedBox(width: 10),
            GestureDetector(onTap: () {}, child: Container(width: 40, height: 40, decoration: BoxDecoration(color: surfaceColor, borderRadius: BorderRadius.circular(10)), child: Icon(Iconsax.chart_2, color: subColor, size: 20))),
            const Spacer(),
            Text(
              '$remaining',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isOverLimit ? AppColors.error : remaining < 50 ? AppColors.warning : subColor),
            ),
          ]),
        ),
      ]),
    );
  }
}
