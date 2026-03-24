import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../config/app_constants.dart';

// ── AppTextField ──────────────────────────────────────
class AppTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final TextInputType? keyboardType;
  final IconData? prefixIcon;
  final Function(String)? onSubmitted;
  final int? maxLines;

  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.keyboardType,
    this.prefixIcon,
    this.onSubmitted,
    this.maxLines = 1,
  });

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.label, style: AppTextStyles.label),
        const SizedBox(height: 6),
        TextField(
          controller: widget.controller,
          obscureText: widget.obscureText && _obscure,
          keyboardType: widget.keyboardType,
          maxLines: widget.obscureText ? 1 : widget.maxLines,
          style: AppTextStyles.body,
          onSubmitted: widget.onSubmitted,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: AppTextStyles.label,
            prefixIcon: widget.prefixIcon != null
                ? Icon(widget.prefixIcon,
                    color: AppColors.textMuted, size: 18)
                : null,
            suffixIcon: widget.obscureText
                ? IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: AppColors.textMuted,
                      size: 18,
                    ),
                    onPressed: () =>
                        setState(() => _obscure = !_obscure),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

// ── StatCard ──────────────────────────────────────────
class StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: AppRadius.lg,
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(value,
              style: AppTextStyles.h3.copyWith(color: color)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.caption),
        ],
      ),
    );
  }
}

// ── StageBadge ────────────────────────────────────────
class StageBadge extends StatelessWidget {
  final String stage;

  const StageBadge({super.key, required this.stage});

  @override
  Widget build(BuildContext context) {
    final info = StageInfo.get(stage);
    final color = info['color'] as Color;
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: AppRadius.pill,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '${info['emoji']} ${info['label']}',
        style: AppTextStyles.caption.copyWith(
            color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── TaskPreviewCard ───────────────────────────────────
class TaskPreviewCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;

  const TaskPreviewCard({
    super.key,
    required this.task,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: AppRadius.lg,
          border: Border.all(color: AppColors.bgSurface),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.task_alt_rounded,
                color: AppColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    task['title'] ?? '',
                    style: AppTextStyles.h4.copyWith(fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(
                        Icons.attach_money_rounded,
                        size: 12,
                        color: AppColors.success,
                      ),
                      Text(
                        '${task['currency'] ?? 'NGN'} ${task['estimated_earnings'] ?? '?'}',
                        style: AppTextStyles.caption
                            .copyWith(color: AppColors.success),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.bgSurface,
                          borderRadius: AppRadius.pill,
                        ),
                        child: Text(
                          task['category'] ?? '',
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textMuted,
            ),
          ],
        ),
      ),
    );
  }
}

// ── LoadingOverlay ────────────────────────────────────
class LoadingOverlay extends StatelessWidget {
  final bool isLoading;
  final Widget child;

  const LoadingOverlay({
    super.key,
    required this.isLoading,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (isLoading)
          Container(
            color: Colors.black.withOpacity(0.4),
            child: const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            ),
          ),
      ],
    );
  }
}

// ── EmptyState ────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: AppColors.textMuted),
            const SizedBox(height: 16),
            Text(
              title,
              style: AppTextStyles.h3,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── GradientText ──────────────────────────────────────
class GradientText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final List<Color> colors;

  const GradientText(
    this.text, {
    super.key,
    required this.style,
    this.colors = const [AppColors.primary, AppColors.accent],
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) =>
          LinearGradient(colors: colors).createShader(bounds),
      child: Text(text, style: style),
    );
  }
}

// ── Shimmer skeleton widgets ──────────────────────────────────────────

class _SkeletonBox extends StatelessWidget {
  final double width, height;
  final double radius;
  const _SkeletonBox({required this.width, required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// Feed post skeleton — matches the real PostCard layout
class PostSkeleton extends StatelessWidget {
  const PostSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base   = isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100;
    final high   = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade300;

    return Shimmer.fromColors(
      baseColor: base, highlightColor: high,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _SkeletonBox(width: 40, height: 40, radius: 20),
            const SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _SkeletonBox(width: 120, height: 12),
              const SizedBox(height: 6),
              _SkeletonBox(width: 80, height: 10),
            ]),
          ]),
          const SizedBox(height: 14),
          _SkeletonBox(width: double.infinity, height: 12),
          const SizedBox(height: 8),
          _SkeletonBox(width: 220, height: 12),
          const SizedBox(height: 8),
          _SkeletonBox(width: 160, height: 12),
          const SizedBox(height: 16),
          Row(children: [
            _SkeletonBox(width: 48, height: 28, radius: 14),
            const SizedBox(width: 12),
            _SkeletonBox(width: 48, height: 28, radius: 14),
            const SizedBox(width: 12),
            _SkeletonBox(width: 48, height: 28, radius: 14),
          ]),
        ]),
      ),
    );
  }
}

/// Dashboard stat card skeleton
class StatCardSkeleton extends StatelessWidget {
  const StatCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base   = isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100;
    final high   = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade300;

    return Shimmer.fromColors(
      baseColor: base, highlightColor: high,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111111) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _SkeletonBox(width: 32, height: 32, radius: 8),
          const SizedBox(height: 14),
          _SkeletonBox(width: 80, height: 22),
          const SizedBox(height: 8),
          _SkeletonBox(width: 60, height: 10),
        ]),
      ),
    );
  }
}

/// Profile header skeleton
class ProfileHeaderSkeleton extends StatelessWidget {
  const ProfileHeaderSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base   = isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade100;
    final high   = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade300;

    return Shimmer.fromColors(
      baseColor: base, highlightColor: high,
      child: Column(children: [
        _SkeletonBox(width: 80, height: 80, radius: 40),
        const SizedBox(height: 12),
        _SkeletonBox(width: 120, height: 16),
        const SizedBox(height: 8),
        _SkeletonBox(width: 200, height: 12),
      ]),
    );
  }
}
