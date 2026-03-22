import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class GroupDetailScreen extends StatefulWidget {
  final String groupId;
  final String groupName;
  const GroupDetailScreen({super.key, required this.groupId, required this.groupName});

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  Map _group = {};
  List _posts = [];
  List _members = [];
  bool _loading = true;
  bool _joined = false;
  final _postCtrl = TextEditingController();
  bool _posting = false;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      // Use generic get — group detail endpoint
      final data = await api.get('/messages/groups');
      final groups = (data['groups'] as List? ?? []);
      final group = groups.firstWhere(
        (g) => g['id'].toString() == widget.groupId,
        orElse: () => <String, dynamic>{},
      );
      if (mounted) {
        setState(() {
          _group = group;
          _joined = group['is_joined'] == true || group['is_member'] == true;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleJoin() async {
    try {
      await api.toggleGroup(widget.groupId);
      setState(() => _joined = !_joined);
    } catch (_) {}
  }

  @override
  void dispose() {
    _tabs.dispose();
    _postCtrl.dispose();
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
    final surface = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    final memberCount = _group['member_count'] as int? ?? _group['members_count'] as int? ?? 0;
    final emoji = _group['emoji']?.toString() ?? '💬';
    final description = _group['description']?.toString() ?? '';
    final tag = _group['topic']?.toString() ?? _group['tag']?.toString() ?? '';

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Expanded(child: Text(widget.groupName,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text),
                maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          GestureDetector(
            onTap: _toggleJoin,
            child: Container(
              margin: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: _joined ? Colors.transparent : AppColors.primary,
                borderRadius: BorderRadius.circular(20),
                border: _joined ? Border.all(color: isDark ? Colors.white24 : Colors.grey.shade300) : null,
              ),
              child: Text(
                _joined ? 'Joined' : 'Join',
                style: TextStyle(
                  color: _joined ? sub : Colors.white,
                  fontSize: 13, fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(49),
          child: Column(children: [
            TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: sub,
              indicatorColor: AppColors.primary,
              indicatorWeight: 2,
              labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              tabs: const [Tab(text: 'Posts'), Tab(text: 'About')],
            ),
            Divider(height: 1, color: border),
          ]),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Posts tab ────────────────────────────────
          Column(
            children: [
              // Post composer
              if (_joined)
                Container(
                  color: card,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                        child: const Center(child: Text('🌱', style: TextStyle(fontSize: 18))),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _showPostSheet(context, isDark, border, text, sub),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            decoration: BoxDecoration(
                              color: surface,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Share something with the group...',
                                style: TextStyle(color: sub, fontSize: 13)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Divider(height: 1, color: border),

              // Posts list
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                    : _posts.isEmpty
                        ? Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(emoji, style: const TextStyle(fontSize: 48)),
                              const SizedBox(height: 12),
                              Text('No posts yet in this group',
                                  style: TextStyle(color: sub, fontSize: 14)),
                              if (_joined) ...[
                                const SizedBox(height: 8),
                                GestureDetector(
                                  onTap: () => _showPostSheet(context, isDark, border, text, sub),
                                  child: Text('Be the first to post!',
                                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                                ),
                              ],
                            ],
                          ))
                        : ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: _posts.length,
                            separatorBuilder: (_, __) => Divider(height: 8, thickness: 8, color: border),
                            itemBuilder: (_, i) {
                              final p = _posts[i];
                              return Container(
                                color: card,
                                padding: const EdgeInsets.all(16),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Container(
                                      width: 38, height: 38,
                                      decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                                      child: Center(child: Text(p['avatar']?.toString() ?? '🌱', style: const TextStyle(fontSize: 18))),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(p['name']?.toString() ?? 'Member', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text)),
                                      Text(p['time']?.toString() ?? '', style: TextStyle(fontSize: 11, color: sub)),
                                    ])),
                                  ]),
                                  const SizedBox(height: 10),
                                  Text(p['content']?.toString() ?? '', style: TextStyle(fontSize: 14, color: text, height: 1.55)),
                                  const SizedBox(height: 10),
                                  Row(children: [
                                    Icon(Icons.favorite_border_rounded, color: sub, size: 18),
                                    const SizedBox(width: 4),
                                    Text('${p['likes'] ?? 0}', style: TextStyle(color: sub, fontSize: 12)),
                                    const SizedBox(width: 16),
                                    Icon(Iconsax.message, color: sub, size: 18),
                                    const SizedBox(width: 4),
                                    Text('${p['comments'] ?? 0}', style: TextStyle(color: sub, fontSize: 12)),
                                  ]),
                                ]),
                              ).animate().fadeIn(delay: Duration(milliseconds: i * 50));
                            },
                          ),
              ),
            ],
          ),

          // ── About tab ────────────────────────────────
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group info card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgCard : const Color(0xFFF8F8F8),
                    borderRadius: AppRadius.lg,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text(emoji, style: const TextStyle(fontSize: 36)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(widget.groupName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
                        if (tag.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(tag, style: const TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ])),
                    ]),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(description, style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
                    ],
                    const SizedBox(height: 16),
                    Row(children: [
                      Icon(Iconsax.people, size: 16, color: sub),
                      const SizedBox(width: 6),
                      Text('$memberCount members', style: TextStyle(fontSize: 13, color: text, fontWeight: FontWeight.w600)),
                    ]),
                  ]),
                ),
                const SizedBox(height: 20),

                // Rules / Guidelines
                Text('Community Guidelines', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text)),
                const SizedBox(height: 10),
                ...[
                  '✅ Share real experiences and income wins',
                  '✅ Ask questions — no question is too basic',
                  '🚫 No spam or self-promotion without value',
                  '🚫 Be respectful to all members',
                  '💡 Help others when you can',
                ].map((rule) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(rule, style: TextStyle(fontSize: 13, color: sub, height: 1.5)),
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPostSheet(BuildContext ctx, bool isDark, Color border, Color text, Color sub) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: AppRadius.pill))),
              const SizedBox(height: 16),
              Text('Post to ${widget.groupName}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
              const SizedBox(height: 12),
              TextField(
                controller: _postCtrl,
                maxLines: 4,
                style: TextStyle(fontSize: 14, color: text),
                decoration: InputDecoration(
                  hintText: 'Share a win, question, or insight...',
                  hintStyle: TextStyle(color: sub),
                  filled: true,
                  fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _posting ? null : () async {
                    if (_postCtrl.text.trim().isEmpty) return;
                    setState(() => _posting = true);
                    try {
                      await api.createPost(content: _postCtrl.text.trim(), tag: '💬 Group');
                      _postCtrl.clear();
                      if (ctx.mounted) Navigator.pop(ctx);
                      _load();
                    } catch (_) {} finally {
                      setState(() => _posting = false);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_posting ? 'Posting...' : 'Post', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
