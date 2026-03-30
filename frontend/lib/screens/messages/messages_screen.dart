// frontend/lib/screens/messages/messages_screen.dart
// v4 — Production ready
//
// Changes:
//  • Presence heartbeat every 30 s (POST /messages/presence)
//  • Conversation list auto-refreshes every 15 s (live unread + online dots)
//  • AppLifecycleObserver: heartbeat pauses when app backgrounded, resumes on foreground
//  • setOffline() called on dispose
//  • is_online now comes from backend last_seen computation — no guessing

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _MessagesScreenState extends State<MessagesScreen>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  final _searchCtrl = TextEditingController();

  List  _convos  = [];
  bool  _loading = true;
  bool  _error   = false;
  String _query  = '';

  Timer? _presenceTimer;
  Timer? _refreshTimer;

  @override
  bool get wantKeepAlive => true;

  // ── Lifecycle ───────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _startPresence();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _refreshTimer?.cancel();
    _searchCtrl.dispose();
    // Tell the server this user is no longer active
    api.setOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startPresence();
      _load();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive) {
      _presenceTimer?.cancel();
      api.setOffline();
    }
  }

  // ── Presence heartbeat ──────────────────────────────────────────────────
  void _startPresence() {
    api.updatePresence(); // immediate
    _presenceTimer?.cancel();
    _presenceTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => api.updatePresence());
  }

  // ── Auto-refresh conversation list ──────────────────────────────────────
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadSilent();
    });
  }

  // ── Data loading ────────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      final data = await api.getDMConversations();
      if (mounted) setState(() { _convos = data; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = true; });
    }
  }

  /// Refresh without showing the loading spinner (background refresh)
  Future<void> _loadSilent() async {
    try {
      final data = await api.getDMConversations();
      if (mounted) setState(() => _convos = data);
    } catch (_) {}
  }

  // ── Filtering ───────────────────────────────────────────────────────────
  List get _filtered {
    if (_query.isEmpty) return _convos;
    final q = _query.toLowerCase();
    return _convos.where((c) {
      final name = (c['other_user']?['full_name'] ?? '').toString().toLowerCase();
      return name.contains(q);
    }).toList();
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds < 60)  return 'now';
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m';
    if (diff.inHours < 24)    return '${diff.inHours}h';
    if (diff.inDays < 7)      return '${diff.inDays}d';
    return '${(diff.inDays / 7).floor()}w';
  }

  // ── New message sheet ───────────────────────────────────────────────────
  void _openNewMessage() {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewMessageSheet(
        onConversationCreated: (convId, name, avatar) {
          Navigator.pop(context);
          context.push(
            '/conversation/$convId'
            '?name=${Uri.encodeComponent(name)}'
            '&avatar=${Uri.encodeComponent(avatar)}',
          );
          _load();
        },
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black : Colors.white;
    final cardColor   = isDark ? AppColors.bgCard : Colors.white;
    final surfColor   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white : Colors.black87;
    final subColor    = isDark ? Colors.white54 : Colors.black45;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text('Messages', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          IconButton(
            icon: Icon(Iconsax.edit, color: textColor, size: 22),
            tooltip: 'New message',
            onPressed: _openNewMessage,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(children: [
        // Search bar
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
              filled: true, fillColor: surfColor,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              prefixIcon: Icon(Iconsax.search_normal, color: subColor, size: 18),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: subColor, size: 16),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      })
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
        Divider(height: 1, color: borderColor),

        // Pinned RiseUp AI tile
        if (_query.isEmpty) ...[
          _AIPinnedTile(
            isDark: isDark, bgColor: bgColor,
            textColor: textColor, subColor: subColor,
            onTap: () => context.push(
                '/conversation/ai?name=RiseUp+AI&avatar=🤖&isAI=true'),
          ),
          Divider(height: 1, color: borderColor, indent: 76),
        ],

        Expanded(
          child: _buildBody(isDark, bgColor, borderColor, textColor, subColor),
        ),
      ]),
    );
  }

  Widget _buildBody(
      bool isDark, Color bg, Color border, Color text, Color sub) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
          color: AppColors.primary, strokeWidth: 2));
    }

    if (_error) {
      return Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('😕', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Could not load messages',
            style: TextStyle(color: sub, fontSize: 14)),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh, color: AppColors.primary),
          label: const Text('Retry',
              style: TextStyle(color: AppColors.primary)),
        ),
      ]));
    }

    if (_filtered.isEmpty) {
      return Center(child: Column(
          mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(_query.isEmpty ? '💬' : '🔍',
            style: const TextStyle(fontSize: 52)),
        const SizedBox(height: 12),
        Text(
          _query.isEmpty
              ? 'No conversations yet'
              : 'No results for "$_query"',
          style: TextStyle(
              color: sub, fontSize: 14, fontWeight: FontWeight.w500),
        ),
        if (_query.isEmpty) ...[
          const SizedBox(height: 8),
          Text('Tap ✏️ to message someone',
              style: TextStyle(color: sub, fontSize: 12)),
        ],
      ]));
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: AppColors.primary,
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: _filtered.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: border, indent: 76),
        itemBuilder: (_, i) => _ConvoTile(
          convo: _filtered[i],
          isDark: isDark,
          bgColor: bg,
          textColor: text,
          subColor: sub,
          timeAgo: _timeAgo,
          index: i,
        ),
      ),
    );
  }
}

// ── Pinned AI tile ────────────────────────────────────────────────────────
class _AIPinnedTile extends StatelessWidget {
  final bool isDark;
  final Color bgColor, textColor, subColor;
  final VoidCallback onTap;

  const _AIPinnedTile({
    required this.isDark,
    required this.bgColor,
    required this.textColor,
    required this.subColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () { HapticFeedback.lightImpact(); onTap(); },
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.accent]),
              shape: BoxShape.circle,
            ),
            child: const Center(
                child: Text('🤖', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text('RiseUp AI', style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: textColor)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent]),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('AI', style: TextStyle(
                    color: Colors.white, fontSize: 8,
                    fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 2),
            Text('Your personal wealth mentor — always online',
                style: TextStyle(fontSize: 13, color: subColor),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          // AI is always "online"
          Container(
            width: 9, height: 9,
            decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle),
          ),
        ]),
      ),
    );
  }
}

// ── Conversation list tile ────────────────────────────────────────────────
class _ConvoTile extends StatelessWidget {
  final Map convo;
  final bool isDark;
  final Color bgColor, textColor, subColor;
  final String Function(String?) timeAgo;
  final int index;

  const _ConvoTile({
    required this.convo,
    required this.isDark,
    required this.bgColor,
    required this.textColor,
    required this.subColor,
    required this.timeAgo,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final other   = convo['other_user'] as Map? ?? {};
    final lastMsg = convo['last_message'] as Map?;
    final unread  = convo['unread_count'] as int? ?? 0;

    final convId =
        convo['id']?.toString() ?? convo['conversation_id']?.toString() ?? '';
    final name     = other['full_name']?.toString() ?? 'User';
    final avatar   = other['avatar_url']?.toString() ?? '';
    final isOnline = other['is_online'] == true;  // computed server-side from last_seen
    final initial  = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return GestureDetector(
      onTap: () {
        if (convId.isEmpty) return;
        HapticFeedback.lightImpact();
        context.push(
          '/conversation/$convId'
          '?name=${Uri.encodeComponent(name)}'
          '&avatar=${Uri.encodeComponent(avatar.isEmpty ? initial : avatar)}',
        );
      },
      child: Container(
        color: bgColor,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          // Avatar + online dot
          Stack(children: [
            _buildAvatar(avatar, initial, 52),
            if (isOnline)
              Positioned(
                bottom: 1, right: 1,
                child: Container(
                  width: 14, height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                    border: Border.all(color: bgColor, width: 2),
                  ),
                ),
              ),
          ]),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: textColor))),
              Text(
                timeAgo(convo['updated_at']?.toString()),
                style: TextStyle(
                  fontSize: 11,
                  color: unread > 0 ? AppColors.primary : subColor,
                  fontWeight:
                      unread > 0 ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ]),
            const SizedBox(height: 3),
            Row(children: [
              Expanded(child: Text(
                lastMsg?['content']?.toString() ??
                    'Start a conversation...',
                style: TextStyle(
                  fontSize: 13,
                  color: unread > 0 ? textColor : subColor,
                  fontWeight:
                      unread > 0 ? FontWeight.w500 : FontWeight.w400,
                ),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              )),
              if (unread > 0)
                Container(
                  constraints: const BoxConstraints(minWidth: 20),
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: const BoxDecoration(
                      color: AppColors.primary, shape: BoxShape.circle),
                  child: Center(child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w700),
                  )),
                ),
            ]),
          ])),
        ]),
      ),
    ).animate().fadeIn(delay: Duration(milliseconds: index * 40));
  }

  Widget _buildAvatar(String avatar, String initial, double size) {
    final isUrl = avatar.startsWith('http');
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: isUrl ? null : const LinearGradient(
            colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
        image: isUrl
            ? DecorationImage(
                image: NetworkImage(avatar), fit: BoxFit.cover)
            : null,
        shape: BoxShape.circle,
      ),
      child: isUrl
          ? null
          : Center(child: Text(initial, style: TextStyle(
              fontSize: size * 0.42, color: Colors.white,
              fontWeight: FontWeight.w700))),
    );
  }
}

// ════════════════════════════════════════════════════════════════════════════
// NEW MESSAGE BOTTOM SHEET
// ════════════════════════════════════════════════════════════════════════════
class _NewMessageSheet extends StatefulWidget {
  final void Function(String convId, String name, String avatar)
      onConversationCreated;

  const _NewMessageSheet({required this.onConversationCreated});

  @override
  State<_NewMessageSheet> createState() => _NewMessageSheetState();
}

class _NewMessageSheetState extends State<_NewMessageSheet> {
  final _ctrl     = TextEditingController();
  List  _results  = [];
  bool  _loading  = false;
  bool  _opening  = false;
  String _lastQ   = '';

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  Future<void> _search(String q) async {
    if (q == _lastQ) return;
    _lastQ = q;
    if (q.trim().length < 2) {
      setState(() { _results = []; _loading = false; });
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await api.searchUsers(q);
      if (mounted && q == _lastQ) {
        setState(() { _results = res; _loading = false; });
      }
    } catch (_) {
      if (mounted) setState(() { _results = []; _loading = false; });
    }
  }

  Future<void> _openDM(Map user) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final convId = await api.getOrCreateDM(user['id'].toString());
      if (convId.isEmpty) throw Exception('No conversation ID');
      final name   = user['full_name']?.toString() ?? 'User';
      final avatar = user['avatar_url']?.toString()
          ?? (name.isNotEmpty ? name[0].toUpperCase() : '?');
      widget.onConversationCreated(convId, name, avatar);
    } catch (_) {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final sheetColor = isDark ? AppColors.bgCard : Colors.white;
    final surfColor  = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final textColor  = isDark ? Colors.white : Colors.black87;
    final subColor   = isDark ? Colors.white54 : Colors.black45;
    final bottomPad  = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sheetColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: isDark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(children: [
            Text('New Message', style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: textColor)),
            const Spacer(),
            IconButton(
              icon: Icon(Icons.close, color: subColor),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            style: TextStyle(fontSize: 14, color: textColor),
            onChanged: _search,
            decoration: InputDecoration(
              hintText: 'Search by name...',
              hintStyle: TextStyle(color: subColor, fontSize: 13),
              filled: true, fillColor: surfColor,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
              prefixIcon: Icon(Iconsax.search_normal, color: subColor, size: 18),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(
                color: AppColors.primary, strokeWidth: 2),
          )
        else if (_results.isEmpty && _ctrl.text.length >= 2)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Text('No users found',
                style: TextStyle(color: subColor, fontSize: 13)),
          )
        else
          ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.45),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: _results.length,
              itemBuilder: (_, i) {
                final u       = _results[i] as Map;
                final name    = u['full_name']?.toString() ?? 'User';
                final av      = u['avatar_url']?.toString() ?? '';
                final isUrl   = av.startsWith('http');
                final stage   = u['stage']?.toString() ?? '';
                final online  = u['is_online'] == true;

                return ListTile(
                  onTap: () => _openDM(u),
                  leading: Stack(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: AppColors.primary,
                      backgroundImage: isUrl ? NetworkImage(av) : null,
                      child: isUrl
                          ? null
                          : Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                    ),
                    if (online)
                      Positioned(
                        bottom: 0, right: 0,
                        child: Container(
                          width: 12, height: 12,
                          decoration: BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: isDark
                                    ? AppColors.bgCard
                                    : Colors.white,
                                width: 2),
                          ),
                        ),
                      ),
                  ]),
                  title: Text(name, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600,
                      color: textColor)),
                  subtitle: stage.isNotEmpty
                      ? Text(
                          stage[0].toUpperCase() + stage.substring(1),
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.stageColor(stage)))
                      : null,
                  trailing: _opening
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.primary))
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                                colors: [
                                  AppColors.primary,
                                  AppColors.accent
                                ]),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text('Message',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ),
                );
              },
            ),
          ),
      ]),
    );
  }
}
