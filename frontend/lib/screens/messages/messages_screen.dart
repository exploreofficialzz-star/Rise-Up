import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _searchCtrl = TextEditingController();
  List _convos = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getConversations();
      if (mounted) setState(() { _convos = data['conversations'] ?? []; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List get _filtered => _query.isEmpty
      ? _convos
      : _convos.where((c) {
          final name = (c['other_user']?['full_name'] ?? '').toString().toLowerCase();
          return name.contains(_query.toLowerCase());
        }).toList();

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? Colors.black : Colors.white;
    final cardColor = isDark ? AppColors.bgCard : Colors.white;
    final surfaceColor = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Messages', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.edit, color: textColor, size: 22),
            onPressed: () {},
            tooltip: 'New message',
          ),
        ],
        bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: borderColor)),
      ),
      body: Column(children: [
        // ── Search ──────────────────────────────────
        Container(
          color: cardColor,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: TextField(
            controller: _searchCtrl,
            style: TextStyle(fontSize: 14, color: textColor),
            onChanged: (v) => setState(() => _query = v),
            decoration: InputDecoration(
              hintText: 'Search messages...',
              hintStyle: TextStyle(color: subColor, fontSize: 13),
              filled: true, fillColor: surfaceColor,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              prefixIcon: Icon(Iconsax.search_normal, color: subColor, size: 18),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Divider(height: 1, color: borderColor),

        // ── AI Mentor always pinned at top ───────────
        GestureDetector(
          onTap: () => context.go('/conversation/ai?name=RiseUp+AI&avatar=🤖&isAI=true'),
          child: Container(
            color: bgColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                  shape: BoxShape.circle,
                ),
                child: const Center(child: Text('🤖', style: TextStyle(fontSize: 26))),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('RiseUp AI', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]), borderRadius: BorderRadius.circular(4)),
                    child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                  ),
                ]),
                Text('Your personal wealth mentor — always online', style: TextStyle(fontSize: 13, color: subColor), maxLines: 1, overflow: TextOverflow.ellipsis),
              ])),
              Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
            ]),
          ),
        ),
        Divider(height: 1, color: borderColor, indent: 76),

        // ── Real conversations ────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _filtered.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Text('💬', style: TextStyle(fontSize: 56)),
                      const SizedBox(height: 12),
                      Text('No messages yet', style: TextStyle(color: subColor, fontSize: 14)),
                      const SizedBox(height: 8),
                      Text('Start a conversation!', style: TextStyle(color: subColor, fontSize: 12)),
                    ]))
                  : RefreshIndicator(
                      onRefresh: _load,
                      color: AppColors.primary,
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: borderColor, indent: 76),
                        itemBuilder: (_, i) {
                          final c = _filtered[i];
                          final other = c['other_user'] as Map? ?? {};
                          final lastMsg = c['last_message'] as Map?;
                          final unread = c['unread_count'] as int? ?? 0;
                          final convId = c['id']?.toString() ?? '';
                          final name = other['full_name']?.toString() ?? 'User';
                          final avatar = other['avatar_url']?.toString() ?? '';

                          return GestureDetector(
                            onTap: () => context.go('/conversation/$convId?name=${Uri.encodeComponent(name)}&avatar=${Uri.encodeComponent(avatar.isEmpty ? '👤' : avatar)}'),
                            child: Container(
                              color: bgColor,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(children: [
                                Stack(children: [
                                  Container(
                                    width: 52, height: 52,
                                    decoration: BoxDecoration(
                                      gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(child: Text(
                                      name.isNotEmpty ? name[0].toUpperCase() : '👤',
                                      style: const TextStyle(fontSize: 22, color: Colors.white, fontWeight: FontWeight.w700),
                                    )),
                                  ),
                                  if (other['is_online'] == true)
                                    Positioned(bottom: 1, right: 1, child: Container(
                                      width: 14, height: 14,
                                      decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: bgColor, width: 2)),
                                    )),
                                ]),
                                const SizedBox(width: 12),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Expanded(child: Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor))),
                                    Text(_timeAgo(c['updated_at']?.toString()), style: TextStyle(fontSize: 11, color: unread > 0 ? AppColors.primary : subColor)),
                                  ]),
                                  const SizedBox(height: 3),
                                  Row(children: [
                                    Expanded(child: Text(
                                      lastMsg?['content']?.toString() ?? 'Start a conversation...',
                                      style: TextStyle(fontSize: 13, color: unread > 0 ? textColor : subColor, fontWeight: unread > 0 ? FontWeight.w500 : FontWeight.w400),
                                      maxLines: 1, overflow: TextOverflow.ellipsis,
                                    )),
                                    if (unread > 0)
                                      Container(
                                        width: 20, height: 20,
                                        decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                        child: Center(child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                                      ),
                                  ]),
                                ])),
                              ]),
                            ),
                          ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
