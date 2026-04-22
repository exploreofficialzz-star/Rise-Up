// frontend/lib/screens/home/home_screen.dart
// RiseUp v3.0 — The Mission Command Center
//
// Architecture:
//   • One screen. No bottom nav.
//   • Top bar: ≡ | RiseUp 🪙tokens | 🔍 | 🔔
//   • Mission circles (horizontal scroll, like stories)
//   • Chat interface (Claude-like) — messages from RiseUp + user
//   • APEX mode: split panel (left=thoughts, right=browser screenshot)
//   • Ad gate overlay when tokens exhausted
//   • Sidebar drawer: profile, missions list, navigation
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/app_constants.dart';
import '../../services/ad_service.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

enum MessageRole { user, riseup, system }
enum ApexStatus  { idle, thinking, browsing, paused, done, error }
enum MissionStatus { active, paused, completed }

class ChatMessage {
  final String       id;
  final MessageRole  role;
  final String       text;
  final DateTime     ts;
  final bool         isStreaming;
  final String?      apexThought;
  final Uint8List?   screenshotBytes;
  final Map<String, dynamic>? actionCard;

  ChatMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.ts,
    this.isStreaming    = false,
    this.apexThought,
    this.screenshotBytes,
    this.actionCard,
  });

  ChatMessage copyWith({String? text, bool? isStreaming,
      String? apexThought, Uint8List? screenshotBytes}) => ChatMessage(
    id: id, role: role, ts: ts,
    text:            text            ?? this.text,
    isStreaming:     isStreaming      ?? this.isStreaming,
    apexThought:     apexThought     ?? this.apexThought,
    screenshotBytes: screenshotBytes ?? this.screenshotBytes,
    actionCard:      actionCard,
  );
}

class Mission {
  final String id;
  final String title;
  final String emoji;
  final MissionStatus status;
  final String platform;
  final List<ChatMessage> messages;
  final int incomeEarned;
  final DateTime createdAt;

  Mission({
    required this.id,
    required this.title,
    required this.emoji,
    required this.status,
    required this.platform,
    required this.messages,
    this.incomeEarned = 0,
    required this.createdAt,
  });

  Mission copyWith({List<ChatMessage>? messages, MissionStatus? status, int? incomeEarned}) =>
      Mission(
        id: id, title: title, emoji: emoji, platform: platform, createdAt: createdAt,
        status:        status        ?? this.status,
        messages:      messages      ?? this.messages,
        incomeEarned:  incomeEarned  ?? this.incomeEarned,
      );
}

class TokenState {
  final int remaining;
  final int dailyLimit;
  final bool exhausted;
  final bool canRedeemAds;
  final int nextRewardTokens;
  final int redemptionsLeft;
  final bool locked;
  final int lockMinutesLeft;
  final bool dayLocked;
  final bool isPremium;

  const TokenState({
    this.remaining       = 500,
    this.dailyLimit      = 500,
    this.exhausted       = false,
    this.canRedeemAds    = true,
    this.nextRewardTokens= 40,
    this.redemptionsLeft = 3,
    this.locked          = false,
    this.lockMinutesLeft = 0,
    this.dayLocked       = false,
    this.isPremium       = false,
  });

  factory TokenState.fromJson(Map<String, dynamic> j) => TokenState(
    remaining:        j['tokens_remaining']  ?? 500,
    dailyLimit:       j['tokens_daily_limit']?? 500,
    exhausted:        j['exhausted']         ?? false,
    canRedeemAds:     j['can_redeem_ads']    ?? true,
    nextRewardTokens: j['next_reward_tokens']?? 40,
    redemptionsLeft:  j['redemptions_left']  ?? 3,
    locked:           j['locked']            ?? false,
    lockMinutesLeft:  j['lock_minutes_left'] ?? 0,
    dayLocked:        j['day_locked']        ?? false,
    isPremium:        j['is_premium']        ?? false,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// SOUND SERVICE
// ─────────────────────────────────────────────────────────────────────────────

class _Sound {
  static final _player = AudioPlayer();

  static Future<void> _play(String asset) async {
    try { await _player.play(AssetSource(asset)); } catch (_) {}
  }

  static void tap()     => HapticFeedback.selectionClick();
  static void send()    { HapticFeedback.mediumImpact(); _play('sounds/send.mp3'); }
  static void receive() { HapticFeedback.lightImpact();  _play('sounds/receive.mp3'); }
  static void apexStart(){ HapticFeedback.heavyImpact(); _play('sounds/apex_start.mp3'); }
  static void success() { HapticFeedback.heavyImpact();  _play('sounds/success.mp3'); }
  static void token()   { HapticFeedback.lightImpact();  _play('sounds/token.mp3'); }
}

// ─────────────────────────────────────────────────────────────────────────────
// HOME SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  final String? openMissionId;
  const HomeScreen({super.key, this.openMissionId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── State ──────────────────────────────────────────────────────────────────
  final _scrollCtrl  = ScrollController();
  final _inputCtrl   = TextEditingController();
  final _inputFocus  = FocusNode();
  final _globalKey   = GlobalKey<ScaffoldState>();

  List<Mission>  _missions       = [];
  String?        _activeMissionId;
  TokenState     _tokens         = const TokenState();
  ApexStatus     _apexStatus     = ApexStatus.idle;
  bool           _apexMode       = false; // split-panel active
  String         _apexThought    = '';
  Uint8List?     _apexScreenshot;
  bool           _isLoading      = false;
  bool           _isSending      = false;
  String?        _userAvatar;
  String?        _userName;
  String         _userStage      = 'survival';
  bool           _showAdGate     = false;
  int            _adWatchCount   = 0;   // ads watched in current cycle
  StreamSubscription? _apexSub;

  late final AnimationController _tokenPulse;
  late final AnimationController _apexPulse;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tokenPulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _apexPulse  = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose(); _inputCtrl.dispose(); _inputFocus.dispose();
    _tokenPulse.dispose(); _apexPulse.dispose();
    _apexSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      authService.tryRefreshOnResume();
      _fetchTokens();
    }
  }

  // ── Boot ───────────────────────────────────────────────────────────────────
  Future<void> _boot() async {
    setState(() => _isLoading = true);
    await Future.wait([_fetchProfile(), _fetchTokens(), _fetchMissions()]);
    setState(() => _isLoading = false);

    if (widget.openMissionId != null) {
      _selectMission(widget.openMissionId!);
    } else if (_missions.isEmpty) {
      _addWelcomeMission();
    } else {
      _activeMissionId = _missions.first.id;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _fetchProfile() async {
    try {
      final r = await api.get('/auth/me');
      if (r is Map) {
        setState(() {
          _userName   = r['full_name'] ?? r['username'] ?? 'Hustler';
          _userAvatar = r['avatar_url'];
          _userStage  = r['stage'] ?? 'survival';
        });
      }
    } catch (_) {}
  }

  Future<void> _fetchTokens() async {
    try {
      final r = await api.get('/agent/tokens');
      if (r is Map) setState(() => _tokens = TokenState.fromJson(r.cast()));
    } catch (_) {}
  }

  Future<void> _fetchMissions() async {
    try {
      final r = await api.get('/mentor/sessions');
      if (r is Map) {
        final sessions = (r['sessions'] as List? ?? []);
        final missions = sessions.map<Mission>((s) => Mission(
          id:        s['id']?.toString()    ?? _uuid(),
          title:     s['title']?.toString() ?? 'Mission',
          emoji:     s['emoji']?.toString() ?? '🎯',
          platform:  s['platform']?.toString() ?? '',
          status:    MissionStatus.active,
          messages:  _parseMsgs(s['messages']),
          createdAt: DateTime.tryParse(s['created_at'] ?? '') ?? DateTime.now(),
        )).toList();
        setState(() => _missions = missions);
      }
    } catch (_) {}
  }

  List<ChatMessage> _parseMsgs(dynamic raw) {
    if (raw is! List) return [];
    return raw.map<ChatMessage>((m) => ChatMessage(
      id:   m['id']?.toString()   ?? _uuid(),
      role: m['role'] == 'user'   ? MessageRole.user : MessageRole.riseup,
      text: m['content']?.toString() ?? '',
      ts:   DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
    )).toList();
  }

  void _addWelcomeMission() {
    final welcome = Mission(
      id:       _uuid(),
      title:    'Start Here',
      emoji:    '🚀',
      platform: '',
      status:   MissionStatus.active,
      createdAt: DateTime.now(),
      messages: [
        ChatMessage(
          id:   _uuid(),
          role: MessageRole.riseup,
          text: '## Do your best hustle with RiseUp 💪\n\nI\'m your AI income partner. I know **10,000+ ways** people make money — from freelancing to trading to building businesses.\n\nTell me where you are right now:\n- Do you have any skills or experience?\n- How much time can you dedicate daily?\n- Do you have any starting capital?\n\nOr just say **"surprise me"** and I\'ll pick the best path for you.',
          ts:   DateTime.now(),
        ),
      ],
    );
    setState(() {
      _missions.add(welcome);
      _activeMissionId = welcome.id;
    });
  }

  // ── Active mission helpers ──────────────────────────────────────────────────
  Mission? get _activeMission =>
      _missions.where((m) => m.id == _activeMissionId).firstOrNull;

  List<ChatMessage> get _activeMessages => _activeMission?.messages ?? [];

  void _selectMission(String id) {
    setState(() => _activeMissionId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _newMission() async {
    _Sound.tap();
    final m = Mission(
      id: _uuid(), title: 'New Mission', emoji: '➕',
      platform: '', status: MissionStatus.active,
      createdAt: DateTime.now(),
      messages: [ChatMessage(
        id: _uuid(), role: MessageRole.riseup,
        text: '## New mission started 🎯\n\nWhat income path do you want to explore? You can describe it, or ask me to **recommend something** based on your profile.',
        ts: DateTime.now(),
      )],
    );
    setState(() { _missions.insert(0, m); _activeMissionId = m.id; });
    _scrollToBottom();
  }

  // ── Send message ──────────────────────────────────────────────────────────
  Future<void> _sendMessage([String? override]) async {
    final text = (override ?? _inputCtrl.text).trim();
    if (text.isEmpty || _isSending) return;
    if (_tokens.exhausted) { _showTokenGate(); return; }

    _Sound.send();
    _inputCtrl.clear();
    setState(() => _isSending = true);

    final userMsg = ChatMessage(id: _uuid(), role: MessageRole.user, text: text, ts: DateTime.now());
    _appendMsg(userMsg);
    _scrollToBottom();

    // Check if this is an APEX request
    final isApex = _detectApex(text);

    // Placeholder RiseUp response
    final placeholder = ChatMessage(id: _uuid(), role: MessageRole.riseup,
        text: '', ts: DateTime.now(), isStreaming: true);
    _appendMsg(placeholder);

    try {
      if (isApex) {
        await _handleApexRequest(text, placeholder.id);
      } else {
        await _handleMentorChat(text, placeholder.id);
      }
    } catch (e) {
      _updateMsg(placeholder.id, '⚠️ Connection issue. Please try again.');
    } finally {
      setState(() => _isSending = false);
      _fetchTokens();
    }
  }

  bool _detectApex(String text) {
    final lower = text.toLowerCase();
    final triggers = ['do it', 'set it up', 'create my', 'open', 'register me',
        'sign me up', 'apply for me', 'build this', 'execute', 'run it',
        'make it happen', 'handle it', 'automate', 'use apex', 'go ahead'];
    return triggers.any((t) => lower.contains(t));
  }

  Future<void> _handleMentorChat(String text, String placeholderId) async {
    try {
      final sessionId = _activeMission?.id;
      final res = await api.post('/mentor/chat', {
        'message':    text,
        'session_id': sessionId,
      });
      if (res is Map) {
        final reply = res['reply']?.toString() ?? res['message']?.toString() ?? '...';
        _updateMsg(placeholderId, reply);
        _Sound.receive();

        // Update session title if returned
        if (res['session_title'] != null && _activeMission != null) {
          _updateMissionTitle(_activeMissionId!, res['session_title']);
        }

        // Check if mentor wants to hand off to APEX
        if (res['escalate_to_apex'] == true) {
          await Future.delayed(const Duration(milliseconds: 800));
          _launchApex(res['apex_task']?.toString() ?? text, res['apex_template']);
        }
      }
    } catch (e) {
      _updateMsg(placeholderId, 'I\'m having trouble connecting right now. Try again in a moment.');
    }
  }

  Future<void> _handleApexRequest(String text, String placeholderId) async {
    _Sound.apexStart();
    setState(() { _apexStatus = ApexStatus.thinking; _apexMode = true; });
    _updateMsg(placeholderId, '🤖 **APEX activated.** Analysing your request...');

    // Classify task and get template
    try {
      final classify = await api.post('/agent/classify', {'task': text});
      if (classify is Map) {
        final template = classify['template']?.toString() ?? 'general';
        final questions = (classify['preflight_questions'] as List?)?.cast<Map>() ?? [];

        if (questions.isNotEmpty) {
          // Ask preflight questions before starting
          _updateMsg(placeholderId,
              '🤖 **APEX** needs a few details before I start:\n\n' +
              questions.asMap().entries.map((e) => '**${e.key + 1}.** ${e.value['question']}').join('\n'));
          setState(() { _apexStatus = ApexStatus.paused; });
        } else {
          await _launchApex(text, {'template': template});
        }
      }
    } catch (e) {
      await _launchApex(text, null);
    }
  }

  Future<void> _launchApex(String task, Map<String, dynamic>? template) async {
    setState(() { _apexStatus = ApexStatus.browsing; _apexMode = true; });

    try {
      final body = <String, dynamic>{
        'task':     task,
        'template': template,
        'stream':   true,
      };

      // Stream APEX events via SSE
      final stream = api.streamPost('/agent/browser/run', body);
      _apexSub?.cancel();
      _apexSub = stream.listen(
        (event) => _onApexEvent(event),
        onError: (_) => setState(() => _apexStatus = ApexStatus.error),
        onDone:  () => _onApexDone(),
      );
    } catch (e) {
      setState(() { _apexStatus = ApexStatus.error; _apexMode = false; });
      _appendMsg(ChatMessage(id: _uuid(), role: MessageRole.riseup,
          text: '⚠️ APEX encountered an issue. ${e.toString()}', ts: DateTime.now()));
    }
  }

  void _onApexEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    setState(() {
      if (event['thought'] != null) _apexThought = event['thought'].toString();
      if (event['screenshot_b64'] != null) {
        try { _apexScreenshot = base64Decode(event['screenshot_b64'].toString()); } catch (_) {}
      }
    });

    switch (type) {
      case 'thinking':
        setState(() => _apexStatus = ApexStatus.thinking);
        break;
      case 'action':
        setState(() => _apexStatus = ApexStatus.browsing);
        break;
      case 'human_required':
        setState(() => _apexStatus = ApexStatus.paused);
        _appendMsg(ChatMessage(id: _uuid(), role: MessageRole.riseup,
            text: '⏸️ **APEX paused.** ${event['message'] ?? 'I need your input to continue.'}',
            ts: DateTime.now()));
        break;
      case 'done':
        _onApexDone();
        break;
      case 'error':
        setState(() => _apexStatus = ApexStatus.error);
        break;
    }
    _scrollToBottom();
  }

  void _onApexDone() {
    _Sound.success();
    setState(() { _apexStatus = ApexStatus.done; });
    _appendMsg(ChatMessage(id: _uuid(), role: MessageRole.riseup,
        text: '✅ **APEX mission complete!** What would you like to do next?', ts: DateTime.now()));
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() { _apexMode = false; _apexStatus = ApexStatus.idle; });
    });
    _fetchTokens();
  }

  void _stopApex() {
    _apexSub?.cancel();
    api.post('/agent/browser/stop', {}).catchError((_) {});
    setState(() { _apexStatus = ApexStatus.idle; _apexMode = false; });
  }

  // ── Message helpers ────────────────────────────────────────────────────────
  void _appendMsg(ChatMessage msg) {
    if (_activeMissionId == null) return;
    setState(() {
      _missions = _missions.map((m) {
        if (m.id != _activeMissionId) return m;
        return m.copyWith(messages: [...m.messages, msg]);
      }).toList();
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _updateMsg(String id, String text) {
    setState(() {
      _missions = _missions.map((m) {
        if (m.id != _activeMissionId) return m;
        final msgs = m.messages.map((msg) =>
            msg.id == id ? msg.copyWith(text: text, isStreaming: false) : msg).toList();
        return m.copyWith(messages: msgs);
      }).toList();
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _updateMissionTitle(String id, String title) {
    setState(() {
      _missions = _missions.map((m) => m.id == id
          ? Mission(id: m.id, title: title, emoji: m.emoji, platform: m.platform,
                    status: m.status, messages: m.messages, createdAt: m.createdAt)
          : m).toList();
    });
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(_scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    }
  }

  // ── Token gate ─────────────────────────────────────────────────────────────
  void _showTokenGate() => setState(() => _showAdGate = true);

  Future<void> _watchAd() async {
    try {
      // Record ad watch on backend
      final r = await api.post('/agent/tokens/record-ad', {});
      if (r is Map && r['day_locked'] == true) {
        _showDayLockedDialog();
        return;
      }
      setState(() => _adWatchCount++);
      _Sound.token();
      if (r is Map && r['redemption_ready'] == true) {
        await _claimRedemption();
      }
    } catch (_) {}
  }

  Future<void> _claimRedemption() async {
    try {
      final r = await api.post('/agent/tokens/claim-redemption', {});
      if (r is Map && r['granted'] == true) {
        _Sound.success();
        setState(() { _showAdGate = false; _adWatchCount = 0; });
        await _fetchTokens();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('🎉 ${r['tokens_granted']} tokens unlocked!'),
            backgroundColor: AppColors.success,
          ));
        }
      }
    } catch (_) {}
  }

  void _showDayLockedDialog() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: AppColors.bgCard,
      title: const Text('Come back tomorrow 🌅', style: TextStyle(color: Colors.white)),
      content: const Text("You've reached today's ad limit. Your tokens reset at midnight.\n\nSubscribe to Premium for unlimited access!",
          style: TextStyle(color: AppColors.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
          onPressed: () { Navigator.pop(context); context.push('/premium'); },
          child: const Text('Go Premium'),
        ),
      ],
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      key: _globalKey,
      backgroundColor: AppColors.bgDark,
      drawer: _buildSidebar(context),
      body: SafeArea(
        child: Stack(
          children: [
            Column(children: [
              _buildTopBar(context),
              _buildMissionCircles(),
              Expanded(child: _apexMode ? _buildApexSplitPanel() : _buildChatArea()),
              if (_showAdGate) _buildAdGate() else _buildInputBar(),
            ]),
            if (_isLoading) const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(bottom: BorderSide(color: AppColors.bgSurface, width: 0.8)),
      ),
      child: Row(children: [
        // ≡ Menu
        GestureDetector(
          onTap: () { _Sound.tap(); _globalKey.currentState?.openDrawer(); },
          child: const Icon(Iconsax.menu_1, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 12),

        // RiseUp logo + token badge
        Expanded(child: Row(children: [
          RichText(text: const TextSpan(
            children: [
              TextSpan(text: 'Rise', style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800, color: Color(0xFFFF6B00))),
              TextSpan(text: 'Up', style: TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w800, color: AppColors.primary)),
            ],
          )),
          const SizedBox(width: 8),
          _TokenBadge(tokens: _tokens, pulse: _tokenPulse),
        ])),

        // Search
        GestureDetector(
          onTap: () => _Sound.tap(),
          child: const Icon(Iconsax.search_normal, color: Colors.white70, size: 22),
        ),
        const SizedBox(width: 16),

        // Notifications
        GestureDetector(
          onTap: () { _Sound.tap(); context.push('/notifications'); },
          child: const Icon(Iconsax.notification, color: Colors.white70, size: 22),
        ),
      ]),
    );
  }

  // ── Mission circles ────────────────────────────────────────────────────────
  Widget _buildMissionCircles() {
    return Container(
      height: 88,
      color: AppColors.bgCard,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _missions.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          if (i == 0) return _NewMissionCircle(onTap: _newMission);
          final m = _missions[i - 1];
          final isActive = m.id == _activeMissionId;
          return _MissionCircle(
            mission: m,
            isActive: isActive,
            onTap: () { _Sound.tap(); _selectMission(m.id); },
          );
        },
      ),
    );
  }

  // ── Chat area ──────────────────────────────────────────────────────────────
  Widget _buildChatArea() {
    final msgs = _activeMessages;
    if (msgs.isEmpty) {
      return Center(child: Text('Select a mission or start a new one',
          style: TextStyle(color: AppColors.textMuted)));
    }
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount: msgs.length,
      itemBuilder: (ctx, i) => _ChatBubble(msg: msgs[i]),
    );
  }

  // ── APEX split panel ───────────────────────────────────────────────────────
  Widget _buildApexSplitPanel() {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // LEFT — Thought process (40%)
      Expanded(flex: 40, child: Container(
        color: AppColors.bgCard,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _ApexStatusBar(status: _apexStatus, pulse: _apexPulse, onStop: _stopApex),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Chat history
                ..._activeMessages.map((m) => _ChatBubble(msg: m, compact: true)),
                // Current thought
                if (_apexThought.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      AnimatedBuilder(animation: _apexPulse, builder: (_, __) =>
                          Icon(Iconsax.cpu, size: 14,
                              color: AppColors.primary.withOpacity(0.5 + _apexPulse.value * 0.5))),
                      const SizedBox(width: 6),
                      Expanded(child: Text(_apexThought,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12))),
                    ]),
                  ),
                ],
              ],
            ),
          )),
        ]),
      )),

      // Divider
      Container(width: 1, color: AppColors.bgSurface),

      // RIGHT — Browser screenshot (60%)
      Expanded(flex: 60, child: Container(
        color: AppColors.bgDark,
        child: _apexScreenshot != null
            ? Image.memory(_apexScreenshot!, fit: BoxFit.contain)
            : Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                AnimatedBuilder(animation: _apexPulse, builder: (_, __) =>
                    Icon(Iconsax.monitor, size: 48,
                        color: AppColors.primary.withOpacity(0.3 + _apexPulse.value * 0.4))),
                const SizedBox(height: 12),
                const Text('APEX Browser', style: TextStyle(color: AppColors.textMuted)),
                const SizedBox(height: 4),
                Text(_apexStatus == ApexStatus.thinking ? 'Thinking...' : 'Starting browser...',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ])),
      )),
    ]);
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.bgSurface, width: 0.8)),
      ),
      child: Row(children: [
        Expanded(child: Container(
          constraints: const BoxConstraints(minHeight: 40, maxHeight: 120),
          decoration: BoxDecoration(
            color: AppColors.bgSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.bgSurface),
          ),
          child: TextField(
            controller: _inputCtrl,
            focusNode: _inputFocus,
            maxLines: null,
            style: const TextStyle(color: Colors.white, fontSize: 15),
            decoration: const InputDecoration(
              hintText: 'Message RiseUp...',
              hintStyle: TextStyle(color: AppColors.textMuted),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            onSubmitted: (_) => _sendMessage(),
            textInputAction: TextInputAction.send,
          ),
        )),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _isSending ? null : _sendMessage,
          child: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              gradient: _isSending ? null : const LinearGradient(
                colors: [Color(0xFFFF6B00), AppColors.primary]),
              color: _isSending ? AppColors.bgSurface : null,
              shape: BoxShape.circle,
            ),
            child: _isSending
                ? const Center(child: SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                : const Icon(Iconsax.send_1, color: Colors.white, size: 18),
          ),
        ),
      ]),
    );
  }

  // ── Ad gate ────────────────────────────────────────────────────────────────
  Widget _buildAdGate() {
    final needed   = 2 - _adWatchCount;
    final schedule = [40, 30, 20];
    final idx      = _tokens.redemptionsLeft >= 0
        ? (3 - _tokens.redemptionsLeft).clamp(0, 2)
        : 2;
    final reward   = idx < schedule.length ? schedule[idx] : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        border: Border(top: BorderSide(color: AppColors.bgSurface, width: 0.8)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Iconsax.flash, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Tokens used up', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          TextButton(
            onPressed: () { setState(() => _showAdGate = false); context.push('/premium'); },
            child: const Text('Go Premium', style: TextStyle(color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Watch $_adWatchCount/2 ads to earn +$reward tokens',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        const SizedBox(height: 12),

        // Progress dots
        Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(2, (i) =>
          Container(margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 32, height: 6,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(3),
              color: i < _adWatchCount ? AppColors.success : AppColors.bgSurface,
            )))),
        const SizedBox(height: 12),

        Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: () => setState(() => _showAdGate = false),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.bgSurface),
              foregroundColor: AppColors.textSecondary,
            ),
            child: const Text('Later'),
          )),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: ElevatedButton.icon(
            icon: const Icon(Iconsax.play, size: 16),
            label: Text('Watch ad ($needed left)'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _watchAd,
          )),
        ]),
      ]),
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────
  Widget _buildSidebar(BuildContext context) {
    final stageInfo = _stageInfo(_userStage);
    return Drawer(
      backgroundColor: AppColors.bgCard,
      child: SafeArea(child: Column(children: [
        // Profile header
        GestureDetector(
          onTap: () { _Sound.tap(); context.push('/profile'); Navigator.pop(context); },
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: AppColors.primary,
                backgroundImage: _userAvatar != null ? CachedNetworkImageProvider(_userAvatar!) : null,
                child: _userAvatar == null ? Text((_userName ?? 'R')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)) : null,
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_userName ?? 'Hustler', style: const TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Row(children: [
                  Text(stageInfo['emoji']!, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  Text(stageInfo['label']!, style: TextStyle(color: stageInfo['color']! as Color, fontSize: 12)),
                ]),
              ])),
              const Icon(Iconsax.arrow_right_2, color: AppColors.textMuted, size: 16),
            ]),
          ),
        ),

        Divider(color: AppColors.bgSurface, height: 1),
        const SizedBox(height: 8),

        // New mission button
        Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ElevatedButton.icon(
            icon: const Icon(Iconsax.add, size: 18),
            label: const Text('New Mission'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () { Navigator.pop(context); _newMission(); },
          ),
        ),
        const SizedBox(height: 12),

        // Missions list
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('MISSIONS', style: TextStyle(color: AppColors.textMuted,
                fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)))),
        const SizedBox(height: 6),
        Expanded(child: ListView.builder(
          itemCount: _missions.length,
          itemBuilder: (ctx, i) {
            final m = _missions[i];
            final isActive = m.id == _activeMissionId;
            return ListTile(
              dense: true,
              leading: Text(m.emoji, style: const TextStyle(fontSize: 20)),
              title: Text(m.title, style: TextStyle(
                  color: isActive ? Colors.white : AppColors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 14),
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              selected: isActive,
              selectedTileColor: AppColors.primary.withOpacity(0.1),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onTap: () { _Sound.tap(); Navigator.pop(context); _selectMission(m.id); },
            );
          },
        )),

        Divider(color: AppColors.bgSurface, height: 1),

        // Bottom nav items
        _SidebarNavItem(icon: Iconsax.chart_2,  label: 'Income',     onTap: () { Navigator.pop(context); context.push('/earnings'); }),
        _SidebarNavItem(icon: Iconsax.target,   label: 'Goals',      onTap: () { Navigator.pop(context); context.push('/goals'); }),
        _SidebarNavItem(icon: Iconsax.book,     label: 'Skills',     onTap: () { Navigator.pop(context); context.push('/skills'); }),
        _SidebarNavItem(icon: Iconsax.crown_1,  label: 'Premium',    onTap: () { Navigator.pop(context); context.push('/premium'); },
            badge: _tokens.isPremium ? null : 'Upgrade'),
        _SidebarNavItem(icon: Iconsax.setting_2,label: 'Settings',   onTap: () { Navigator.pop(context); context.push('/settings'); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Map<String, dynamic> _stageInfo(String stage) {
    const s = <String, Map<String, dynamic>>{
      'survival': {'emoji': '🆘', 'label': 'Survival',   'color': Color(0xFFE17055)},
      'earning':  {'emoji': '💪', 'label': 'Earning',    'color': Color(0xFF0984E3)},
      'growing':  {'emoji': '🚀', 'label': 'Growing',    'color': Color(0xFF00B894)},
      'wealth':   {'emoji': '💎', 'label': 'Wealth',     'color': Color(0xFF6C5CE7)},
    };
    return s[stage] ?? s['survival']!;
  }

  static String _uuid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      Random().nextInt(9999).toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _TokenBadge extends StatelessWidget {
  final TokenState tokens;
  final AnimationController pulse;
  const _TokenBadge({required this.tokens, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final pct   = tokens.dailyLimit > 0 ? tokens.remaining / tokens.dailyLimit : 1.0;
    final color = pct > 0.5 ? AppColors.success : pct > 0.2 ? AppColors.warning : AppColors.error;

    return AnimatedBuilder(animation: pulse, builder: (_, __) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15 + pulse.value * 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Iconsax.flash_1, color: color, size: 12),
        const SizedBox(width: 4),
        Text('${tokens.remaining}', style: TextStyle(color: color,
            fontSize: 12, fontWeight: FontWeight.w700)),
      ]),
    ));
  }
}

class _MissionCircle extends StatelessWidget {
  final Mission mission;
  final bool    isActive;
  final VoidCallback onTap;
  const _MissionCircle({required this.mission, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isActive ? const LinearGradient(
                colors: [Color(0xFFFF6B00), AppColors.primary]) : null,
            color: isActive ? null : AppColors.bgSurface,
          ),
          child: Center(child: Text(mission.emoji, style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(height: 4),
        SizedBox(width: 56, child: Text(mission.title,
            textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: isActive ? Colors.white : AppColors.textMuted, fontSize: 10))),
      ]),
    );
  }
}

class _NewMissionCircle extends StatelessWidget {
  final VoidCallback onTap;
  const _NewMissionCircle({required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.primary, width: 2, style: BorderStyle.solid),
          ),
          child: const Center(child: Icon(Iconsax.add, color: AppColors.primary, size: 22)),
        ),
        const SizedBox(height: 4),
        const Text('New', style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
      ]),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool compact;
  const _ChatBubble({required this.msg, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == MessageRole.user;
    final padding = compact ? 6.0 : 12.0;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.fromLTRB(48, padding / 2, 8, padding / 2),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFFF6B00), AppColors.primary]),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(18), topRight: Radius.circular(4),
              bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
          ),
          child: Text(msg.text, style: TextStyle(color: Colors.white, fontSize: compact ? 13 : 15)),
        ),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.1);
    }

    // RiseUp message
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!compact) Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 0, 2),
          child: Row(children: [
            Container(width: 20, height: 20,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [Color(0xFFFF6B00), AppColors.primary])),
              child: const Center(child: Text('R', style: TextStyle(color: Colors.white,
                  fontSize: 10, fontWeight: FontWeight.bold)))),
            const SizedBox(width: 6),
            const Text('RiseUp', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        Container(
          margin: EdgeInsets.fromLTRB(8, 2, 48, padding / 2),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4), topRight: Radius.circular(18),
              bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
            border: Border.all(color: AppColors.bgSurface),
          ),
          child: msg.isStreaming
              ? _TypingIndicator()
              : MarkdownBody(
                  data: msg.text,
                  styleSheet: MarkdownStyleSheet(
                    p:         TextStyle(color: Colors.white, fontSize: compact ? 13 : 15, height: 1.5),
                    h2:        const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
                    h3:        const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                    strong:    const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    em:        TextStyle(color: AppColors.primary),
                    blockquoteDecoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      border: Border(left: BorderSide(color: AppColors.primary, width: 3)),
                    ),
                    code:      const TextStyle(color: Color(0xFF00CEC9), fontFamily: 'monospace', fontSize: 13),
                    codeblockDecoration: BoxDecoration(
                      color: AppColors.bgSurface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    listBullet: TextStyle(color: AppColors.primary),
                  ),
                  onTapLink: (text, href, title) {
                    if (href != null) {}
                  },
                ),
        ),
      ]),
    ).animate().fadeIn(duration: 250.ms).slideX(begin: -0.05);
  }
}

class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (_, __) {
      return Row(mainAxisSize: MainAxisSize.min, children: List.generate(3, (i) {
        final delay = i * 0.33;
        final t = (_ctrl.value - delay).clamp(0.0, 1.0);
        final y = sin(t * pi) * 4;
        return Transform.translate(
          offset: Offset(0, -y),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withOpacity(0.5 + t * 0.5),
            ),
          ),
        );
      }));
    });
  }
}

class _ApexStatusBar extends StatelessWidget {
  final ApexStatus status;
  final AnimationController pulse;
  final VoidCallback onStop;
  const _ApexStatusBar({required this.status, required this.pulse, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ApexStatus.thinking => ('APEX · Thinking...', AppColors.warning),
      ApexStatus.browsing => ('APEX · Browsing',    AppColors.primary),
      ApexStatus.paused   => ('APEX · Waiting',     AppColors.info),
      ApexStatus.done     => ('APEX · Done ✓',      AppColors.success),
      ApexStatus.error    => ('APEX · Error',        AppColors.error),
      ApexStatus.idle     => ('APEX · Ready',        AppColors.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: color.withOpacity(0.08),
      child: Row(children: [
        AnimatedBuilder(animation: pulse, builder: (_, __) =>
            Icon(Iconsax.cpu, size: 14,
                color: color.withOpacity(0.6 + pulse.value * 0.4))),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: onStop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppColors.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.error.withOpacity(0.3)),
            ),
            child: const Text('Stop', style: TextStyle(color: AppColors.error, fontSize: 11)),
          ),
        ),
      ]),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final String? badge;
  const _SidebarNavItem({required this.icon, required this.label, required this.onTap, this.badge});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon, color: AppColors.textSecondary, size: 20),
      title: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
      trailing: badge != null ? Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(badge!, style: const TextStyle(color: AppColors.primary, fontSize: 10)),
      ) : null,
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
    );
  }
}
