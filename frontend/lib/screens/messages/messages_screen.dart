import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _Convo {
  final String id, avatar, name, lastMsg, time;
  final bool online, isAI;
  int unread;
  _Convo({required this.id, required this.avatar, required this.name, required this.lastMsg, required this.time, this.online = false, this.isAI = false, this.unread = 0});
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  final _convos = [
    _Convo(id: '1', avatar: '🤖', name: 'RiseUp AI', lastMsg: 'Your wealth roadmap is ready! 🎯', time: '2m', isAI: true, unread: 1),
    _Convo(id: '2', avatar: '💎', name: 'Marcus Wealth', lastMsg: 'Bro that strategy you shared was 🔥', time: '15m', online: true, unread: 3),
    _Convo(id: '3', avatar: '🚀', name: 'Sarah Builds', lastMsg: 'Can we collaborate on a project?', time: '1h', online: true),
    _Convo(id: '4', avatar: '🎯', name: 'Priya Skills', lastMsg: 'Thanks for the advice! Already seeing results', time: '3h', online: false),
    _Convo(id: '5', avatar: '🔥', name: 'David Hustle', lastMsg: 'Let\'s do a live session this weekend?', time: '1d', online: false),
    _Convo(id: '6', avatar: '🌱', name: 'Linda Growth', lastMsg: 'Sent you my budget template', time: '2d', online: false),
  ];

  List<_Convo> get _filtered => _query.isEmpty
      ? _convos
      : _convos.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
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

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Messages',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.edit, color: textColor, size: 22),
            onPressed: () {},
            tooltip: 'New message',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(
        children: [
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
                filled: true,
                fillColor: surfaceColor,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                prefixIcon: Icon(Iconsax.search_normal, color: subColor, size: 18),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Divider(height: 1, color: borderColor),

          // ── Online users row ─────────────────────────
          Container(
            color: cardColor,
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              itemCount: _convos.where((c) => c.online).length + 1,
              itemBuilder: (_, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Column(children: [
                      Container(
                        width: 48, height: 48,
                        decoration: BoxDecoration(
                          color: surfaceColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5),
                        ),
                        child: Icon(Icons.add, color: AppColors.primary, size: 22),
                      ),
                      const SizedBox(height: 4),
                      Text('New', style: TextStyle(fontSize: 10, color: subColor)),
                    ]),
                  );
                }
                final online = _convos.where((c) => c.online).toList()[i - 1];
                return Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: GestureDetector(
                    onTap: () => context.go('/conversation/${online.id}?name=${Uri.encodeComponent(online.name)}&avatar=${Uri.encodeComponent(online.avatar)}'),
                    child: Column(children: [
                      Stack(children: [
                        Container(
                          width: 48, height: 48,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text(online.avatar, style: const TextStyle(fontSize: 22))),
                        ),
                        Positioned(bottom: 0, right: 0, child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.success, shape: BoxShape.circle,
                            border: Border.all(color: cardColor, width: 2),
                          ),
                        )),
                      ]),
                      const SizedBox(height: 4),
                      Text(online.name.split(' ')[0], style: TextStyle(fontSize: 10, color: subColor)),
                    ]),
                  ),
                );
              },
            ),
          ),
          Divider(height: 1, color: borderColor),

          // ── Conversations list ───────────────────────
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: borderColor, indent: 76),
              itemBuilder: (_, i) {
                final c = _filtered[i];
                return GestureDetector(
                  onTap: () {
                    setState(() => c.unread = 0);
                    context.go('/conversation/${c.id}?name=${Uri.encodeComponent(c.name)}&avatar=${Uri.encodeComponent(c.avatar)}&isAI=${c.isAI}');
                  },
                  child: Container(
                    color: bgColor,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      // Avatar
                      Stack(children: [
                        Container(
                          width: 52, height: 52,
                          decoration: BoxDecoration(
                            gradient: c.isAI
                                ? const LinearGradient(colors: [AppColors.primary, AppColors.accent])
                                : const LinearGradient(colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: Text(c.avatar, style: const TextStyle(fontSize: 24))),
                        ),
                        if (c.online || c.isAI)
                          Positioned(bottom: 1, right: 1, child: Container(
                            width: 14, height: 14,
                            decoration: BoxDecoration(
                              color: AppColors.success, shape: BoxShape.circle,
                              border: Border.all(color: bgColor, width: 2),
                            ),
                          )),
                      ]),
                      const SizedBox(width: 12),

                      // Content
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(child: Row(children: [
                              Text(c.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: textColor)),
                              if (c.isAI) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700)),
                                ),
                              ],
                            ])),
                            Text(c.time, style: TextStyle(fontSize: 11, color: c.unread > 0 ? AppColors.primary : subColor)),
                          ]),
                          const SizedBox(height: 3),
                          Row(children: [
                            Expanded(child: Text(c.lastMsg,
                                style: TextStyle(fontSize: 13, color: c.unread > 0 ? textColor : subColor,
                                    fontWeight: c.unread > 0 ? FontWeight.w500 : FontWeight.w400),
                                maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (c.unread > 0)
                              Container(
                                width: 20, height: 20,
                                decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                                child: Center(child: Text('${c.unread}',
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                              ),
                          ]),
                        ],
                      )),
                    ]),
                  ),
                ).animate().fadeIn(delay: Duration(milliseconds: i * 40));
              },
            ),
          ),
        ],
      ),
    );
  }
}
