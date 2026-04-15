// frontend/lib/screens/messages/dm_conversation_screen.dart
// RiseUp DM Screen — Production v1.0
// User-to-user private DMs: accurate online/offline, edit/delete messages.
// Only shows human-to-human messages (no AI sender_type rows).
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ── Message model ────────────────────────────────────────────────────────────
class _DMsg {
  final String id;
  final bool isMe;
  bool isDeleted, isEdited;
  String content;
  final DateTime time;
  final String? mediaUrl;

  _DMsg({
    String? id, required this.content, required this.isMe,
    this.isDeleted = false, this.isEdited = false,
    this.mediaUrl, DateTime? time,
  })  : id   = id ?? 'local_${DateTime.now().microsecondsSinceEpoch}',
        time = time ?? DateTime.now();
}

// ── Screen ────────────────────────────────────────────────────────────────────
class DmConversationScreen extends StatefulWidget {
  final String conversationId; // actual DB conversation UUID
  final String name;
  final String avatar;        // URL or '' for gradient fallback
  final String otherUserId;

  const DmConversationScreen({
    super.key,
    required this.conversationId,
    required this.name,
    required this.avatar,
    required this.otherUserId,
  });

  @override
  State<DmConversationScreen> createState() => _DmConversationScreenState();
}

class _DmConversationScreenState extends State<DmConversationScreen>
    with WidgetsBindingObserver {
  final _textCtrl   = TextEditingController();
  final _scroll     = ScrollController();
  final _inputFocus = FocusNode();
  final List<_DMsg> _msgs = [];

  bool _historyLoaded = false;
  bool _sending       = false;

  String? _lastPollTime;
  String? _cachedMyId;

  // Presence state
  bool    _isOtherOnline  = false;
  String? _lastSeenText;
  Timer?  _presenceTimer;
  Timer?  _pollTimer;

  // Cache keys
  String get _cacheKey => 'dm_msgs_${widget.conversationId}';

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bootstrap();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _presenceTimer?.cancel();
    _pollTimer?.cancel();
    _textCtrl.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    api.setOffline();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      api.updatePresence();
      _pollOtherPresence();
    } else if (state == AppLifecycleState.paused) {
      api.setOffline();
    }
  }

  // ── Bootstrap ─────────────────────────────────────────────────────────────
  Future<void> _bootstrap() async {
    _cachedMyId = await api.getUserId();
    await _loadCachedMsgs();
    await _loadHistory();
    _startPresenceHeartbeat();
    _startPolling();
    await _pollOtherPresence();
  }

  // ── Cache ──────────────────────────────────────────────────────────────────
  Future<void> _saveMsgCache() async {
    try {
      final prefs   = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_msgs
          .where((m) => !m.isDeleted)
          .take(100)
          .map((m) => {
                'id': m.id, 'content': m.content, 'isMe': m.isMe,
                'isEdited': m.isEdited, 'time': m.time.toIso8601String(),
                if (m.mediaUrl != null) 'mediaUrl': m.mediaUrl,
              })
          .toList());
      await prefs.setString(_cacheKey, encoded);
    } catch (_) {}
  }

  Future<void> _loadCachedMsgs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw   = prefs.getString(_cacheKey);
      if (raw == null) return;
      final list  = jsonDecode(raw) as List;
      if (!mounted) return;
      setState(() {
        _msgs.clear();
        _msgs.addAll(list.map((m) => _DMsg(
          id:        m['id']?.toString(),
          content:   m['content']?.toString() ?? '',
          isMe:      m['isMe'] == true,
          isEdited:  m['isEdited'] == true,
          mediaUrl:  m['mediaUrl']?.toString(),
          time:      DateTime.tryParse(m['time']?.toString() ?? '')?.toLocal(),
        )));
        _historyLoaded = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown(jump: true));
    } catch (_) {}
  }

  // ── History ────────────────────────────────────────────────────────────────
  Future<void> _loadHistory() async {
    try {
      final msgs = await api.getDMMessages(widget.conversationId, limit: 60);
      if (!mounted) return;

      final filtered = msgs.where((m) {
        final st = m['sender_type']?.toString() ?? '';
        return st != 'ai' && st != 'system';
      }).toList();

      setState(() {
        _msgs.clear();
        for (final m in filtered) _msgs.add(_parseMsg(m));
        _historyLoaded = true;
      });

      if (msgs.isNotEmpty) {
        _lastPollTime = (msgs.last)['created_at']?.toString();
      }

      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollDown(jump: true));
      await _saveMsgCache();
    } catch (e) {
      debugPrint('[DM] history error: $e');
      if (mounted && !_historyLoaded) setState(() => _historyLoaded = true);
    }
  }

  _DMsg _parseMsg(Map<String, dynamic> m) {
    final senderId = m['sender_id']?.toString() ?? '';
    final isMe     = _cachedMyId != null && senderId == _cachedMyId;
    return _DMsg(
      id:        m['id']?.toString(),
      content:   m['content']?.toString() ?? '',
      isMe:      isMe,
      isDeleted: m['is_deleted'] == true,
      isEdited:  m['is_edited']  == true,
      mediaUrl:  m['media_url']?.toString(),
      time:      DateTime.tryParse(m['created_at']?.toString() ?? '')?.toLocal(),
    );
  }

  // ── Presence ───────────────────────────────────────────────────────────────
  void _startPresenceHeartbeat() {
    api.updatePresence();
    _presenceTimer?.cancel();
    _presenceTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      api.updatePresence();
    });
  }

  Future<void> _pollOtherPresence() async {
    try {
      final res = await api.get(
        '/messages/conversations/${widget.conversationId}/other-presence',
      );
      if (!mounted) return;
      setState(() {
        _isOtherOnline = res['is_online'] == true;
        _lastSeenText  = res['last_seen_text']?.toString();
      });
    } catch (_) {}
  }

  // ── Polling ────────────────────────────────────────────────────────────────
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _poll());
    // Presence poll every 30 s
    Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _pollOtherPresence();
    });
  }

  Future<void> _poll() async {
    if (!_historyLoaded || _sending) return;
    try {
      final msgs = await api.getDMMessages(
        widget.conversationId,
        since: _lastPollTime,
        limit: 20,
      );
      if (!mounted || msgs.isEmpty) return;

      final existingIds = _msgs.map((m) => m.id).toSet();
      bool added        = false;

      setState(() {
        for (final raw in msgs) {
          final st = raw['sender_type']?.toString() ?? '';
          if (st == 'ai' || st == 'system') continue;
          final id = raw['id']?.toString() ?? '';
          if (id.isEmpty || existingIds.contains(id)) continue;

          // Reconcile optimistic local messages
          final content  = raw['content']?.toString() ?? '';
          final senderId = raw['sender_id']?.toString() ?? '';
          final isMe     = _cachedMyId != null && senderId == _cachedMyId;
          if (isMe) {
            final optIdx = _msgs.indexWhere(
                (m) => m.id.startsWith('local_') && m.isMe && m.content == content);
            if (optIdx != -1) {
              final old = _msgs[optIdx];
              _msgs[optIdx] = _DMsg(id: id, content: old.content, isMe: true, time: old.time);
              existingIds.add(id);
              added = true;
              continue;
            }
          }

          _msgs.add(_parseMsg(raw));
          existingIds.add(id);
          added = true;
        }
      });

      if (msgs.isNotEmpty) _lastPollTime = msgs.last['created_at']?.toString();
      if (added) { _scrollDown(); await _saveMsgCache(); }
    } catch (_) {}
  }

  // ── Send ───────────────────────────────────────────────────────────────────
  Future<void> _onSend() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    _textCtrl.clear();
    final localId = 'local_${DateTime.now().millisecondsSinceEpoch}';
    setState(() {
      _msgs.add(_DMsg(id: localId, content: text, isMe: true));
      _sending = true;
    });
    _scrollDown();

    try {
      final result = await api.sendDMMessage(widget.conversationId, text);
      final msgMap = (result['message'] as Map?) ?? result as Map;
      final realId = msgMap['id']?.toString();
      if (mounted) {
        setState(() {
          final idx = _msgs.indexWhere((m) => m.id == localId);
          if (idx != -1 && realId != null && realId.isNotEmpty) {
            final old = _msgs[idx];
            _msgs[idx] = _DMsg(id: realId, content: old.content, isMe: true, time: old.time);
          }
          _sending = false;
        });
        _lastPollTime = DateTime.now().toUtc().toIso8601String();
        await _saveMsgCache();
      }
    } catch (e) {
      debugPrint('[DM] send error: $e');
      if (!mounted) return;
      setState(() {
        final idx = _msgs.indexWhere((m) => m.id == localId);
        if (idx != -1) {
          final old = _msgs[idx];
          _msgs[idx] = _DMsg(id: localId, content: old.content, isMe: true,
              isDeleted: false, time: old.time); // keep but mark failed via color
        }
        _sending = false;
      });
      _showSnack('Message failed. Tap to retry.');
    }
  }

  // ── Edit / Delete ──────────────────────────────────────────────────────────
  Future<void> _editMessage(_DMsg msg) async {
    final ctrl = TextEditingController(text: msg.content);
    final confirmed = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.bgCard : Colors.white,
          title: Text('Edit message',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
          content: TextField(
            controller: ctrl, autofocus: true, maxLines: 5, minLines: 1,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              filled: true, fillColor: isDark ? AppColors.bgSurface : Colors.grey.shade100,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    ctrl.dispose();
    if (confirmed == null || confirmed.isEmpty || confirmed == msg.content) return;

    try {
      await api.patch(
          '/messages/conversations/${widget.conversationId}/messages/${msg.id}',
          {'content': confirmed});
      if (mounted) setState(() { msg.content = confirmed; msg.isEdited = true; });
    } catch (_) {
      if (mounted) _showSnack('Could not edit message. Please try again.');
    }
  }

  Future<void> _deleteMessage(_DMsg msg) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? AppColors.bgCard : Colors.white,
          title: Text('Delete message',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16)),
          content: Text('This cannot be undone.',
              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await api.delete(
          '/messages/conversations/${widget.conversationId}/messages/${msg.id}');
      if (mounted) setState(() { msg.content = 'This message was deleted.'; msg.isDeleted = true; });
    } catch (_) {
      if (mounted) _showSnack('Could not delete message. Please try again.');
    }
  }

  // ── Bubble long-press menu ─────────────────────────────────────────────────
  void _showBubbleMenu(BuildContext ctx, _DMsg m) {
    if (m.isDeleted) return;
    HapticFeedback.mediumImpact();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    showModalBottomSheet(
      context: ctx, backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: isDark ? AppColors.bgCard : Colors.white,
            borderRadius: BorderRadius.circular(20)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(2))),
          _menuItem(Icons.copy_rounded, 'Copy', isDark, () {
            Navigator.pop(ctx);
            Clipboard.setData(ClipboardData(text: m.content));
            _showSnack('Copied ✓');
          }),
          if (m.isMe) ...[
            _menuItem(Icons.edit_rounded, 'Edit', isDark, () {
              Navigator.pop(ctx);
              _editMessage(m);
            }),
            _menuItem(Icons.delete_rounded, 'Delete', isDark, () {
              Navigator.pop(ctx);
              _deleteMessage(m);
            }, color: AppColors.error),
          ],
          SizedBox(height: MediaQuery.of(ctx).padding.bottom + 12),
        ]),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, bool isDark, VoidCallback onTap, {Color? color}) =>
      ListTile(
        leading: Icon(icon, color: color ?? AppColors.primary, size: 20),
        title: Text(label, style: TextStyle(
            color: color ?? (isDark ? Colors.white : Colors.black87),
            fontSize: 14, fontWeight: FontWeight.w500)),
        onTap: onTap, dense: true,
      );

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.bgCard,
    ));
  }

  void _scrollDown({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final maxExt = _scroll.position.maxScrollExtent;
      if (jump) _scroll.jumpTo(maxExt);
      else _scroll.animateTo(maxExt, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
    });
  }

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final bg        = isDark ? Colors.black       : Colors.white;
    final card      = isDark ? AppColors.bgCard   : Colors.white;
    final border    = isDark ? AppColors.bgSurface: Colors.grey.shade200;
    final textColor = isDark ? Colors.white       : Colors.black87;
    final subColor  = isDark ? Colors.white54     : Colors.black45;
    final surf      = isDark ? AppColors.bgSurface: Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark, card, border, textColor, subColor),
      body: Column(children: [
        Expanded(
          child: !_historyLoaded
              ? const Center(child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2))
              : _msgs.isEmpty
                  ? _emptyState(isDark, subColor, textColor)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      itemCount: _msgs.length,
                      itemBuilder: (_, i) =>
                          _buildBubble(_msgs[i], isDark, textColor, surf),
                    ),
        ),
        _buildInputBar(isDark, card, border, textColor, subColor, surf),
      ]),
    );
  }

  PreferredSizeWidget _buildAppBar(
      bool isDark, Color card, Color border, Color text, Color sub) {
    final avatarIsUrl = widget.avatar.startsWith('http');
    final initial     = widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';

    final statusText = _isOtherOnline
        ? 'Online'
        : (_lastSeenText != null ? 'Last seen $_lastSeenText' : 'Offline');

    return AppBar(
      backgroundColor: card, elevation: 0, surfaceTintColor: Colors.transparent,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: text, size: 18),
        onPressed: () =>
            Navigator.of(context).canPop() ? context.pop() : context.go('/messages'),
      ),
      title: Row(children: [
        Stack(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: avatarIsUrl ? null
                  : const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
              image: avatarIsUrl
                  ? DecorationImage(image: NetworkImage(widget.avatar), fit: BoxFit.cover)
                  : null,
              shape: BoxShape.circle,
            ),
            child: avatarIsUrl ? null
                : Center(child: Text(initial,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
          ),
          Positioned(
            bottom: 0, right: 0,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              width: 10, height: 10,
              decoration: BoxDecoration(
                color: _isOtherOnline ? AppColors.success : Colors.grey.shade500,
                shape: BoxShape.circle,
                border: Border.all(color: card, width: 1.5),
              ),
            ),
          ),
        ]),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: text),
                  overflow: TextOverflow.ellipsis),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(statusText,
                    key: ValueKey(statusText),
                    style: TextStyle(fontSize: 11,
                        color: _isOtherOnline ? AppColors.success : sub)),
              ),
            ],
          ),
        ),
      ]),
      actions: [
        IconButton(
          icon: Icon(Iconsax.call, color: text, size: 20),
          onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Voice calls coming soon 📞'),
                  duration: Duration(seconds: 1))),
        ),
      ],
      bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border)),
    );
  }

  Widget _buildInputBar(bool isDark, Color card, Color border,
      Color text, Color sub, Color surf) =>
      Container(
        decoration: BoxDecoration(
            color: card, border: Border(top: BorderSide(color: border))),
        padding: EdgeInsets.fromLTRB(
            12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          IconButton(
            icon: Icon(Iconsax.image, color: sub, size: 22),
            onPressed: () async {
              final file = await ImagePicker().pickImage(source: ImageSource.gallery);
              if (file != null && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('Photo selected ✅ — media upload coming soon')));
              }
            },
          ),
          Expanded(
            child: TextField(
              controller: _textCtrl, focusNode: _inputFocus,
              style: TextStyle(fontSize: 14, color: text),
              maxLines: 5, minLines: 1, enabled: !_sending,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Message ${widget.name}...',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                filled: true, fillColor: surf,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onSubmitted: _sending ? null : (_) => _onSend(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _sending ? null : () { HapticFeedback.lightImpact(); _onSend(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: _sending
                    ? [Colors.grey.shade500, Colors.grey.shade500]
                    : [AppColors.primary, AppColors.accent]),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Center(child: _sending
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 18)),
            ),
          ),
        ]),
      );

  Widget _buildBubble(_DMsg m, bool isDark, Color textColor, Color surf) {
    final bg       = isDark ? const Color(0xFF1A1A2E) : Colors.grey.shade100;
    final deleteBg = isDark ? AppColors.bgSurface     : Colors.grey.shade200;
    final bubbleBg = m.isDeleted ? deleteBg : m.isMe ? AppColors.userBubble : bg;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment:
            m.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                m.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!m.isMe) ...[
                _buildAvatar(),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showBubbleMenu(context, m),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft:     const Radius.circular(18),
                        topRight:    const Radius.circular(18),
                        bottomLeft:  Radius.circular(m.isMe ? 18 : 4),
                        bottomRight: Radius.circular(m.isMe ? 4 : 18),
                      ),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: m.isDeleted
                        ? Text('This message was deleted.',
                            style: TextStyle(
                                color: isDark ? Colors.white38 : Colors.black38,
                                fontSize: 13, fontStyle: FontStyle.italic))
                        : Text(m.content, style: TextStyle(
                            color: m.isMe ? Colors.white : textColor,
                            fontSize: 14, height: 1.5)),
                  ),
                ),
              ),
            ],
          ),

          // Edited + timestamp row
          Padding(
            padding: EdgeInsets.only(
                top: 3, left: m.isMe ? 0 : 44, right: m.isMe ? 4 : 0),
            child: Row(
              mainAxisAlignment:
                  m.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                if (m.isEdited && !m.isDeleted) ...[
                  Text('edited',
                      style: TextStyle(fontSize: 9,
                          color: isDark ? Colors.white24 : Colors.black26,
                          fontStyle: FontStyle.italic)),
                  const SizedBox(width: 4),
                ],
                Text(_fmt(m.time),
                    style: TextStyle(fontSize: 10,
                        color: isDark ? Colors.white24 : Colors.black26)),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }

  Widget _buildAvatar() {
    final isUrl   = widget.avatar.startsWith('http');
    final initial = widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?';
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        gradient: isUrl ? null
            : const LinearGradient(colors: [AppColors.primary, AppColors.accent]),
        image: isUrl
            ? DecorationImage(image: NetworkImage(widget.avatar), fit: BoxFit.cover)
            : null,
        shape: BoxShape.circle,
      ),
      child: isUrl
          ? null
          : Center(child: Text(initial,
              style: const TextStyle(color: Colors.white,
                  fontSize: 12, fontWeight: FontWeight.w700))),
    );
  }

  Widget _emptyState(bool isDark, Color sub, Color text) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('👋', style: TextStyle(fontSize: 56)),
      const SizedBox(height: 16),
      Text('Say hello!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: text)),
      const SizedBox(height: 8),
      Text('Start a conversation below',
          style: TextStyle(fontSize: 14, color: sub)),
    ]),
  );

  String _fmt(DateTime dt) {
    final l = dt.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}
