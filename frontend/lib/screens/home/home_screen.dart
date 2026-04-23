// frontend/lib/screens/home/home_screen.dart
// RiseUp v4.0 — Redesigned Mission Command Center
//
// What changed vs v3.0:
//  • Full light/dark theme awareness — zero hardcoded dark backgrounds
//  • "RiseUp" wordmark uses EXACT splash_screen.dart gradient
//    [Color(0xFFFF6B00) → Color(0xFFFFD700) → Color(0xFF6C5CE7)] stops 0/0.4/1
//  • Token badge positioned exactly as screenshot: floating pill above-right of wordmark
//  • Mission circles preserved intact — revealed only after user's first conversation
//  • Sidebar trimmed to: Profile header · Missions list · Settings
//  • Income / Goals / Skills / Premium moved into the [+] button inside input bar
//  • Welcome hero "DO YOUR BEST HUSTLE WITH RISEUP" shown before first conversation
//  • Input bar redesigned: [+] · [Chat with RiseUp field] · [Send]
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

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
import '../../services/api_service_stream.dart';
import '../../services/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MODELS  (unchanged from v3.0)
// ─────────────────────────────────────────────────────────────────────────────

enum MessageRole  { user, riseup, system }
enum ApexStatus   { idle, thinking, browsing, paused, done, error }
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

  ChatMessage copyWith({
    String?    text,
    bool?      isStreaming,
    String?    apexThought,
    Uint8List? screenshotBytes,
  }) =>
      ChatMessage(
        id:              id,
        role:            role,
        ts:              ts,
        text:            text            ?? this.text,
        isStreaming:     isStreaming      ?? this.isStreaming,
        apexThought:     apexThought     ?? this.apexThought,
        screenshotBytes: screenshotBytes ?? this.screenshotBytes,
        actionCard:      actionCard,
      );
}

class Mission {
  final String        id;
  final String        title;
  final String        emoji;
  final MissionStatus status;
  final String        platform;
  final List<ChatMessage> messages;
  final int           incomeEarned;
  final DateTime      createdAt;

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

  Mission copyWith({
    List<ChatMessage>? messages,
    MissionStatus?     status,
    int?               incomeEarned,
  }) =>
      Mission(
        id:           id,
        title:        title,
        emoji:        emoji,
        platform:     platform,
        createdAt:    createdAt,
        status:       status       ?? this.status,
        messages:     messages     ?? this.messages,
        incomeEarned: incomeEarned ?? this.incomeEarned,
      );
}

class TokenState {
  final int  remaining;
  final int  dailyLimit;
  final bool exhausted;
  final bool canRedeemAds;
  final int  nextRewardTokens;
  final int  redemptionsLeft;
  final bool locked;
  final int  lockMinutesLeft;
  final bool dayLocked;
  final bool isPremium;

  const TokenState({
    this.remaining        = 500,
    this.dailyLimit       = 500,
    this.exhausted        = false,
    this.canRedeemAds     = true,
    this.nextRewardTokens = 40,
    this.redemptionsLeft  = 3,
    this.locked           = false,
    this.lockMinutesLeft  = 0,
    this.dayLocked        = false,
    this.isPremium        = false,
  });

  factory TokenState.fromJson(Map<String, dynamic> j) => TokenState(
        remaining:        j['tokens_remaining']   ?? 500,
        dailyLimit:       j['tokens_daily_limit']  ?? 500,
        exhausted:        j['exhausted']           ?? false,
        canRedeemAds:     j['can_redeem_ads']      ?? true,
        nextRewardTokens: j['next_reward_tokens']  ?? 40,
        redemptionsLeft:  j['redemptions_left']    ?? 3,
        locked:           j['locked']              ?? false,
        lockMinutesLeft:  j['lock_minutes_left']   ?? 0,
        dayLocked:        j['day_locked']          ?? false,
        isPremium:        j['is_premium']          ?? false,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SOUND SERVICE  (unchanged)
// ─────────────────────────────────────────────────────────────────────────────

class _Sound {
  static void tap()       => HapticFeedback.selectionClick();
  static void send()      => HapticFeedback.mediumImpact();
  static void receive()   => HapticFeedback.lightImpact();
  static void apexStart() => HapticFeedback.heavyImpact();
  static void success()   => HapticFeedback.heavyImpact();
  static void token()     => HapticFeedback.lightImpact();
}

// ─────────────────────────────────────────────────────────────────────────────
// THEME HELPERS
// ─────────────────────────────────────────────────────────────────────────────

/// Exact "RiseUp" gradient from splash_screen.dart — DO NOT change.
const LinearGradient _kRiseUpGradient = LinearGradient(
  colors: [Color(0xFFFF6B00), Color(0xFFFFD700), Color(0xFF6C5CE7)],
  stops:  [0.0, 0.4, 1.0],
);

bool   _isDark(BuildContext ctx) => Theme.of(ctx).brightness == Brightness.dark;
Color  _bgScaffold(BuildContext ctx) => _isDark(ctx) ? const Color(0xFF0F0F1A) : Colors.white;
Color  _bgCard(BuildContext ctx)     => _isDark(ctx) ? const Color(0xFF1A1A2E) : const Color(0xFFF5F5FA);
Color  _bgSurface(BuildContext ctx)  => _isDark(ctx) ? const Color(0xFF252540) : const Color(0xFFEAEAF4);
Color  _border(BuildContext ctx)     => _isDark(ctx) ? Colors.white10 : Colors.black.withOpacity(0.08);
Color  _textPrimary(BuildContext ctx)   => _isDark(ctx) ? Colors.white   : Colors.black87;
Color  _textSecondary(BuildContext ctx) => _isDark(ctx) ? Colors.white60 : Colors.black54;
Color  _textMuted(BuildContext ctx)     => _isDark(ctx) ? Colors.white30 : Colors.black26;

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
  final _scrollCtrl = ScrollController();
  final _inputCtrl  = TextEditingController();
  final _inputFocus = FocusNode();
  final _globalKey  = GlobalKey<ScaffoldState>();

  List<Mission>  _missions        = [];
  String?        _activeMissionId;
  TokenState     _tokens          = const TokenState();
  ApexStatus     _apexStatus      = ApexStatus.idle;
  bool           _apexMode        = false;
  String         _apexThought     = '';
  Uint8List?     _apexScreenshot;
  bool           _isLoading       = false;
  bool           _isSending       = false;
  String?        _userAvatar;
  String?        _userName;
  String         _userStage       = 'survival';
  bool           _showAdGate      = false;
  int            _adWatchCount    = 0;
  StreamSubscription? _apexSub;

  /// Tracks whether the user has ever sent a message.
  /// Mission circles are hidden until this is true.
  bool _hasHadFirstConversation = false;

  static const _kFirstConvKey = 'riseup_first_conversation';

  late final AnimationController _tokenPulse;
  late final AnimationController _apexPulse;

  // ── Lifecycle ──────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tokenPulse = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _apexPulse = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _tokenPulse.dispose();
    _apexPulse.dispose();
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

    // Load first-conversation flag from prefs
    final prefs = await SharedPreferences.getInstance();
    final hadFirst = prefs.getBool(_kFirstConvKey) ?? false;

    await Future.wait([_fetchProfile(), _fetchTokens(), _fetchMissions()]);
    setState(() {
      _isLoading = false;
      _hasHadFirstConversation = hadFirst;
    });

    if (widget.openMissionId != null) {
      _selectMission(widget.openMissionId!);
    } else if (_missions.isEmpty) {
      _addWelcomeMission();
    } else {
      _activeMissionId = _missions.first.id;
      // If returning user already has missions, they've had a conversation
      if (_missions.isNotEmpty && !hadFirst) {
        _markFirstConversation();
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  Future<void> _markFirstConversation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFirstConvKey, true);
    if (mounted) setState(() => _hasHadFirstConversation = true);
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
              id:        s['id']?.toString()      ?? _uuid(),
              title:     s['title']?.toString()   ?? 'Mission',
              emoji:     s['emoji']?.toString()   ?? '🎯',
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
          id:   m['id']?.toString()      ?? _uuid(),
          role: m['role'] == 'user'      ? MessageRole.user : MessageRole.riseup,
          text: m['content']?.toString() ?? '',
          ts:   DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
        )).toList();
  }

  void _addWelcomeMission() {
    final welcome = Mission(
      id:        _uuid(),
      title:     'Start Here',
      emoji:     '🚀',
      platform:  '',
      status:    MissionStatus.active,
      createdAt: DateTime.now(),
      messages:  [],   // empty → hero text shown
    );
    setState(() {
      _missions.add(welcome);
      _activeMissionId = welcome.id;
    });
  }

  // ── Active mission helpers ─────────────────────────────────────────────────
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
      id:        _uuid(),
      title:     'New Mission',
      emoji:     '➕',
      platform:  '',
      status:    MissionStatus.active,
      createdAt: DateTime.now(),
      messages: [
        ChatMessage(
          id:   _uuid(),
          role: MessageRole.riseup,
          text:
              '## New mission started 🎯\n\nWhat income path do you want to explore? '
              'You can describe it, or ask me to **recommend something** based on your profile.',
          ts: DateTime.now(),
        ),
      ],
    );
    setState(() {
      _missions.insert(0, m);
      _activeMissionId = m.id;
    });
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

    // First-ever message → unlock mission circles
    if (!_hasHadFirstConversation) _markFirstConversation();

    final userMsg = ChatMessage(
        id: _uuid(), role: MessageRole.user, text: text, ts: DateTime.now());
    _appendMsg(userMsg);
    _scrollToBottom();

    final isApex = _detectApex(text);

    final placeholder = ChatMessage(
        id: _uuid(), role: MessageRole.riseup,
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
    const triggers = [
      'do it', 'set it up', 'create my', 'open', 'register me',
      'sign me up', 'apply for me', 'build this', 'execute', 'run it',
      'make it happen', 'handle it', 'automate', 'use apex', 'go ahead',
    ];
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
        final reply =
            res['reply']?.toString() ?? res['message']?.toString() ?? '...';
        _updateMsg(placeholderId, reply);
        _Sound.receive();
        if (res['session_title'] != null && _activeMission != null) {
          _updateMissionTitle(_activeMissionId!, res['session_title']);
        }
        if (res['escalate_to_apex'] == true) {
          await Future.delayed(const Duration(milliseconds: 800));
          _launchApex(
              res['apex_task']?.toString() ?? text, res['apex_template']);
        }
      }
    } catch (e) {
      _updateMsg(placeholderId,
          "I'm having trouble connecting right now. Try again in a moment.");
    }
  }

  Future<void> _handleApexRequest(String text, String placeholderId) async {
    _Sound.apexStart();
    setState(() { _apexStatus = ApexStatus.thinking; _apexMode = true; });
    _updateMsg(placeholderId, '🤖 **APEX activated.** Analysing your request...');

    try {
      final classify = await api.post('/agent/classify', {'task': text});
      if (classify is Map) {
        final template  = classify['template']?.toString() ?? 'general';
        final questions = (classify['preflight_questions'] as List?)?.cast<Map>() ?? [];

        if (questions.isNotEmpty) {
          _updateMsg(
            placeholderId,
            '🤖 **APEX** needs a few details before I start:\n\n' +
                questions.asMap().entries
                    .map((e) => '**${e.key + 1}.** ${e.value['question']}')
                    .join('\n'),
          );
          setState(() => _apexStatus = ApexStatus.paused);
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
      final stream = api.streamPost('/agent/browser/run', body);
      _apexSub?.cancel();
      _apexSub = stream.listen(
        (event) => _onApexEvent(event.data),
        onError: (_) => setState(() => _apexStatus = ApexStatus.error),
        onDone:  () => _onApexDone(),
      );
    } catch (e) {
      setState(() { _apexStatus = ApexStatus.error; _apexMode = false; });
      _appendMsg(ChatMessage(
          id:   _uuid(),
          role: MessageRole.riseup,
          text: '⚠️ APEX encountered an issue. ${e.toString()}',
          ts:   DateTime.now()));
    }
  }

  void _onApexEvent(Map<String, dynamic> event) {
    final type = event['type']?.toString() ?? '';
    setState(() {
      if (event['thought'] != null) _apexThought = event['thought'].toString();
      if (event['screenshot_b64'] != null) {
        try {
          _apexScreenshot = base64Decode(event['screenshot_b64'].toString());
        } catch (_) {}
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
        _appendMsg(ChatMessage(
            id:   _uuid(),
            role: MessageRole.riseup,
            text: '⏸️ **APEX paused.** ${event['message'] ?? 'I need your input to continue.'}',
            ts:   DateTime.now()));
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
    setState(() => _apexStatus = ApexStatus.done);
    _appendMsg(ChatMessage(
        id:   _uuid(),
        role: MessageRole.riseup,
        text: '✅ **APEX mission complete!** What would you like to do next?',
        ts:   DateTime.now()));
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
        final msgs = m.messages
            .map((msg) =>
                msg.id == id ? msg.copyWith(text: text, isStreaming: false) : msg)
            .toList();
        return m.copyWith(messages: msgs);
      }).toList();
    });
    Future.delayed(const Duration(milliseconds: 100), _scrollToBottom);
  }

  void _updateMissionTitle(String id, String title) {
    setState(() {
      _missions = _missions.map((m) => m.id == id
          ? Mission(
              id:        m.id,
              title:     title,
              emoji:     m.emoji,
              platform:  m.platform,
              status:    m.status,
              messages:  m.messages,
              createdAt: m.createdAt,
            )
          : m).toList();
    });
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve:    Curves.easeOut,
      );
    }
  }

  // ── Token gate ─────────────────────────────────────────────────────────────
  void _showTokenGate() => setState(() => _showAdGate = true);

  Future<void> _watchAd() async {
    try {
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
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bgCard(context),
        title: Text('Come back tomorrow 🌅',
            style: TextStyle(color: _textPrimary(context))),
        content: Text(
          "You've reached today's ad limit. Your tokens reset at midnight.\n\n"
          "Subscribe to Premium for unlimited access!",
          style: TextStyle(color: _textSecondary(context)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () { Navigator.pop(context); context.push('/premium'); },
            child: const Text('Go Premium'),
          ),
        ],
      ),
    );
  }

  // ── + button nav menu (Income / Goals / Skills / Premium) ─────────────────
  void _showNavMenu() {
    _Sound.tap();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _NavMenuSheet(
        isDark: _isDark(context),
        onIncome:  () { Navigator.pop(context); context.push('/earnings'); },
        onGoals:   () { Navigator.pop(context); context.push('/goals');    },
        onSkills:  () { Navigator.pop(context); context.push('/skills');   },
        onPremium: () { Navigator.pop(context); context.push('/premium');  },
        isPremium: _tokens.isPremium,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key:             _globalKey,
      backgroundColor: _bgScaffold(context),
      drawer:          _buildSidebar(context),
      body: SafeArea(
        child: Stack(
          children: [
            Column(children: [
              _buildTopBar(context),
              // Mission circles: only visible after the user's first conversation
              if (_hasHadFirstConversation) _buildMissionCircles(context),
              Expanded(
                child: _apexMode
                    ? _buildApexSplitPanel(context)
                    : _buildChatArea(context),
              ),
              if (_showAdGate)
                _buildAdGate(context)
              else
                _buildInputBar(context),
            ]),
            if (_isLoading)
              const Center(
                  child: CircularProgressIndicator(color: AppColors.primary)),
          ],
        ),
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────
  // Layout: ≡  |  [RiseUp wordmark + floating token badge]  |  🔍  🔔
  Widget _buildTopBar(BuildContext context) {
    final iconColor = _textPrimary(context).withOpacity(0.8);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color:  _bgCard(context),
        border: Border(
            bottom: BorderSide(color: _border(context), width: 0.8)),
      ),
      child: Row(children: [
        // ── Hamburger ──
        GestureDetector(
          onTap: () { _Sound.tap(); _globalKey.currentState?.openDrawer(); },
          child: Icon(Iconsax.menu_1, color: iconColor, size: 24),
        ),
        const SizedBox(width: 10),

        // ── RiseUp wordmark + token badge (Stack so badge floats above-right) ──
        Expanded(
          child: Row(children: [
            // Stack: wordmark behind, badge on top-right corner
            Stack(
              clipBehavior: Clip.none,
              children: [
                // Wordmark with exact splash_screen.dart gradient
                ShaderMask(
                  shaderCallback: (bounds) =>
                      _kRiseUpGradient.createShader(bounds),
                  blendMode: BlendMode.srcIn,
                  child: const Text(
                    'RiseUp',
                    style: TextStyle(
                      fontSize:   22,
                      fontWeight: FontWeight.w900,
                      color:      Colors.white, // masked by shader
                      letterSpacing: -0.5,
                    ),
                  ),
                ),

                // Token badge — floating above-right, exactly as in screenshot
                Positioned(
                  top:   -8,
                  right: -52,
                  child: _TokenBadge(tokens: _tokens, pulse: _tokenPulse),
                ),
              ],
            ),
          ]),
        ),

        // ── Search ──
        GestureDetector(
          onTap: () => _Sound.tap(),
          child: Icon(Iconsax.search_normal, color: iconColor, size: 22),
        ),
        const SizedBox(width: 18),

        // ── Notifications ──
        GestureDetector(
          onTap: () { _Sound.tap(); context.push('/notifications'); },
          child: Icon(Iconsax.notification, color: iconColor, size: 22),
        ),
      ]),
    );
  }

  // ── Mission circles (intact, shown only after first conversation) ──────────
  Widget _buildMissionCircles(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve:    Curves.easeOut,
      height:   88,
      color:    _bgCard(context),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding:         const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount:       _missions.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (ctx, i) {
          if (i == 0) return _NewMissionCircle(onTap: _newMission);
          final m        = _missions[i - 1];
          final isActive = m.id == _activeMissionId;
          return _MissionCircle(
            mission:  m,
            isActive: isActive,
            onTap:    () { _Sound.tap(); _selectMission(m.id); },
          );
        },
      ),
    );
  }

  // ── Chat area ──────────────────────────────────────────────────────────────
  Widget _buildChatArea(BuildContext context) {
    final msgs = _activeMessages;

    // No messages yet → show welcome hero (matches screenshot)
    if (msgs.isEmpty) return _buildHeroWelcome(context);

    return ListView.builder(
      controller: _scrollCtrl,
      padding:    const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      itemCount:  msgs.length,
      itemBuilder: (ctx, i) => _ChatBubble(msg: msgs[i]),
    );
  }

  // ── Hero welcome (shown before first message) ──────────────────────────────
  Widget _buildHeroWelcome(BuildContext context) {
    final textColor = _textPrimary(context);
    final shadowColor = _isDark(context)
        ? Colors.black54
        : Colors.black.withOpacity(0.18);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'DO YOUR BEST\nHUSTLE\nWITH RISEUP',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:   36,
                fontWeight: FontWeight.w900,
                color:      textColor,
                height:     1.1,
                letterSpacing: 0.5,
                shadows: [
                  Shadow(
                    color:  shadowColor,
                    offset: const Offset(2, 3),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.06),
    );
  }

  // ── APEX split panel (unchanged logic, theme-aware colors) ─────────────────
  Widget _buildApexSplitPanel(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // LEFT — Thought process (40%)
      Expanded(
        flex: 40,
        child: Container(
          color: _bgCard(context),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _ApexStatusBar(
                status: _apexStatus, pulse: _apexPulse, onStop: _stopApex),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._activeMessages.map((m) =>
                        _ChatBubble(msg: m, compact: true)),
                    if (_apexThought.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedBuilder(
                                animation: _apexPulse,
                                builder: (_, __) => Icon(Iconsax.cpu,
                                    size: 14,
                                    color: AppColors.primary.withOpacity(
                                        0.5 + _apexPulse.value * 0.5)),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                  child: Text(_apexThought,
                                      style: TextStyle(
                                          color: _textSecondary(context),
                                          fontSize: 12))),
                            ]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),

      // Divider
      Container(width: 1, color: _border(context)),

      // RIGHT — Browser screenshot (60%)
      Expanded(
        flex: 60,
        child: Container(
          color: _bgScaffold(context),
          child: _apexScreenshot != null
              ? Image.memory(_apexScreenshot!, fit: BoxFit.contain)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedBuilder(
                        animation: _apexPulse,
                        builder: (_, __) => Icon(Iconsax.monitor,
                            size: 48,
                            color: AppColors.primary.withOpacity(
                                0.3 + _apexPulse.value * 0.4)),
                      ),
                      const SizedBox(height: 12),
                      Text('APEX Browser',
                          style:
                              TextStyle(color: _textMuted(context))),
                      const SizedBox(height: 4),
                      Text(
                        _apexStatus == ApexStatus.thinking
                            ? 'Thinking...'
                            : 'Starting browser...',
                        style: TextStyle(
                            color: _textMuted(context), fontSize: 12),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    ]);
  }

  // ── Input bar ──────────────────────────────────────────────────────────────
  // Layout: [+]  [Chat with RiseUp ...]  [Send]
  Widget _buildInputBar(BuildContext context) {
    final fieldBg   = _bgSurface(context);
    final hintColor = _textMuted(context);
    final textColor = _textPrimary(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color:  _bgCard(context),
        border: Border(top: BorderSide(color: _border(context), width: 0.8)),
      ),
      child: Column(
        mainAxisSize:      MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Chat with RiseUp" label — shown above input when field is idle
          if (_inputCtrl.text.isEmpty && !_inputFocus.hasFocus)
            Padding(
              padding: const EdgeInsets.only(left: 50, bottom: 4),
              child: Text(
                'Chat with RiseUp',
                style: TextStyle(
                  color:      _textSecondary(context),
                  fontSize:   12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),

          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            // [+] button — opens Income / Goals / Skills / Premium
            GestureDetector(
              onTap: _showNavMenu,
              child: Container(
                width:  38,
                height: 38,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color:  fieldBg,
                  shape:  BoxShape.circle,
                  border: Border.all(color: _border(context)),
                ),
                child: const Icon(Icons.add, color: AppColors.primary, size: 20),
              ),
            ),

            // Text field
            Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 40, maxHeight: 120),
                decoration: BoxDecoration(
                  color:        fieldBg,
                  borderRadius: BorderRadius.circular(20),
                  border:       Border.all(color: _border(context)),
                ),
                child: TextField(
                  controller:      _inputCtrl,
                  focusNode:       _inputFocus,
                  maxLines:        null,
                  style:           TextStyle(color: textColor, fontSize: 15),
                  decoration: InputDecoration(
                    hintText:       'Message RiseUp...',
                    hintStyle:      TextStyle(color: hintColor),
                    border:         InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                  ),
                  onSubmitted:     (_) => _sendMessage(),
                  textInputAction: TextInputAction.send,
                  onChanged:       (_) => setState(() {}), // refresh label
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Send button
            GestureDetector(
              onTap: _isSending ? null : _sendMessage,
              child: Container(
                width:  38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: _isSending
                      ? null
                      : const LinearGradient(
                          colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                  color: _isSending ? fieldBg : null,
                  shape: BoxShape.circle,
                ),
                child: _isSending
                    ? const Center(
                        child: SizedBox(
                          width:  18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        ),
                      )
                    : const Icon(Iconsax.send_1, color: Colors.white, size: 18),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── Ad gate (theme-aware) ──────────────────────────────────────────────────
  Widget _buildAdGate(BuildContext context) {
    final needed   = 2 - _adWatchCount;
    const schedule = [40, 30, 20];
    final idx      = _tokens.redemptionsLeft >= 0
        ? (3 - _tokens.redemptionsLeft).clamp(0, 2)
        : 2;
    final reward   = idx < schedule.length ? schedule[idx] : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:  _bgCard(context),
        border: Border(top: BorderSide(color: _border(context), width: 0.8)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Iconsax.flash, color: AppColors.gold, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Tokens used up',
                style: TextStyle(
                    color: _textPrimary(context),
                    fontWeight: FontWeight.w600)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _showAdGate = false);
              context.push('/premium');
            },
            child: const Text('Go Premium',
                style: TextStyle(color: AppColors.primary)),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Watch $_adWatchCount/2 ads to earn +$reward tokens',
            style: TextStyle(color: _textSecondary(context), fontSize: 13)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            2,
            (i) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width:  32,
              height: 6,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                color: i < _adWatchCount
                    ? AppColors.success
                    : _bgSurface(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _showAdGate = false),
              style: OutlinedButton.styleFrom(
                side:            BorderSide(color: _border(context)),
                foregroundColor: _textSecondary(context),
              ),
              child: const Text('Later'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              icon:  const Icon(Iconsax.play, size: 16),
              label: Text('Watch ad ($needed left)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding:         const EdgeInsets.symmetric(vertical: 12),
                shape:           RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _watchAd,
            ),
          ),
        ]),
      ]),
    );
  }

  // ── Sidebar ────────────────────────────────────────────────────────────────
  // Kept: Profile header · Missions list · Settings
  // Removed: Income · Goals · Skills · Premium  (now in + input button)
  Widget _buildSidebar(BuildContext context) {
    final stageInfo = _stageInfo(_userStage);

    return Drawer(
      backgroundColor: _bgCard(context),
      child: SafeArea(
        child: Column(children: [
          // ── Profile header ──
          GestureDetector(
            onTap: () {
              _Sound.tap();
              context.push('/profile');
              Navigator.pop(context);
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                CircleAvatar(
                  radius:          28,
                  backgroundColor: AppColors.primary,
                  backgroundImage: _userAvatar != null
                      ? CachedNetworkImageProvider(_userAvatar!)
                      : null,
                  child: _userAvatar == null
                      ? Text(
                          (_userName ?? 'R')[0].toUpperCase(),
                          style: const TextStyle(
                              color:      Colors.white,
                              fontSize:   20,
                              fontWeight: FontWeight.bold),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _userName ?? 'Hustler',
                          style: TextStyle(
                              color:      _textPrimary(context),
                              fontSize:   16,
                              fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Row(children: [
                          Text(stageInfo['emoji']!,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(stageInfo['label']!,
                              style: TextStyle(
                                  color:    stageInfo['color']! as Color,
                                  fontSize: 12)),
                        ]),
                      ]),
                ),
                Icon(Iconsax.arrow_right_2,
                    color: _textMuted(context), size: 16),
              ]),
            ),
          ),

          Divider(color: _border(context), height: 1),
          const SizedBox(height: 8),

          // ── New mission button ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ElevatedButton.icon(
              icon:  const Icon(Iconsax.add, size: 18),
              label: const Text('New Mission'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                minimumSize:     const Size(double.infinity, 44),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () { Navigator.pop(context); _newMission(); },
            ),
          ),
          const SizedBox(height: 12),

          // ── Missions list header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'MISSIONS',
                style: TextStyle(
                    color:       _textMuted(context),
                    fontSize:    11,
                    fontWeight:  FontWeight.w700,
                    letterSpacing: 1.2),
              ),
            ),
          ),
          const SizedBox(height: 6),

          // ── Missions list (intact) ──
          Expanded(
            child: ListView.builder(
              itemCount: _missions.length,
              itemBuilder: (ctx, i) {
                final m        = _missions[i];
                final isActive = m.id == _activeMissionId;
                return ListTile(
                  dense:   true,
                  leading: Text(m.emoji,
                      style: const TextStyle(fontSize: 20)),
                  title: Text(
                    m.title,
                    maxLines:  1,
                    overflow:  TextOverflow.ellipsis,
                    style: TextStyle(
                      color:      isActive
                          ? _textPrimary(context)
                          : _textSecondary(context),
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w400,
                      fontSize:   14,
                    ),
                  ),
                  selected:          isActive,
                  selectedTileColor: AppColors.primary.withOpacity(0.1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  onTap: () {
                    _Sound.tap();
                    Navigator.pop(context);
                    _selectMission(m.id);
                  },
                );
              },
            ),
          ),

          Divider(color: _border(context), height: 1),

          // ── Settings only ──
          _SidebarNavItem(
            icon:    Iconsax.setting_2,
            label:   'Settings',
            isDark:  _isDark(context),
            onTap:   () { Navigator.pop(context); context.push('/settings'); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static Map<String, dynamic> _stageInfo(String stage) {
    const s = <String, Map<String, dynamic>>{
      'survival': {'emoji': '🆘', 'label': 'Survival', 'color': Color(0xFFE17055)},
      'earning':  {'emoji': '💪', 'label': 'Earning',  'color': Color(0xFF0984E3)},
      'growing':  {'emoji': '🚀', 'label': 'Growing',  'color': Color(0xFF00B894)},
      'wealth':   {'emoji': '💎', 'label': 'Wealth',   'color': Color(0xFF6C5CE7)},
    };
    return s[stage] ?? s['survival']!;
  }

  static String _uuid() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      Random().nextInt(9999).toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// NAV MENU SHEET  (replaces sidebar items Income / Goals / Skills / Premium)
// ─────────────────────────────────────────────────────────────────────────────

class _NavMenuSheet extends StatelessWidget {
  final bool         isDark;
  final VoidCallback onIncome;
  final VoidCallback onGoals;
  final VoidCallback onSkills;
  final VoidCallback onPremium;
  final bool         isPremium;

  const _NavMenuSheet({
    required this.isDark,
    required this.onIncome,
    required this.onGoals,
    required this.onSkills,
    required this.onPremium,
    required this.isPremium,
  });

  @override
  Widget build(BuildContext context) {
    final bg      = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final textClr = isDark ? Colors.white.withOpacity(0.87) : Colors.black87;
    final subClr  = isDark ? Colors.white54 : Colors.black45;

    Widget item({
      required IconData   icon,
      required Color      iconBg,
      required String     label,
      required String     sub,
      required VoidCallback onTap,
      String?             badge,
    }) {
      return ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color:        iconBg.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: iconBg, size: 20),
        ),
        title: Text(label,
            style: TextStyle(
                color:      textClr,
                fontWeight: FontWeight.w600,
                fontSize:   15)),
        subtitle: Text(sub,
            style: TextStyle(color: subClr, fontSize: 12)),
        trailing: badge != null
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color:        AppColors.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(badge,
                    style: const TextStyle(
                        color:    AppColors.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              )
            : const Icon(Iconsax.arrow_right_2, size: 16, color: Colors.grey),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          margin:  const EdgeInsets.only(top: 10, bottom: 6),
          width:   40, height: 4,
          decoration: BoxDecoration(
            color:        Colors.grey.withOpacity(0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Explore',
                style: TextStyle(
                    color:      textClr,
                    fontSize:   18,
                    fontWeight: FontWeight.w800)),
          ),
        ),
        item(
          icon:   Iconsax.chart_2,
          iconBg: const Color(0xFF00B894),
          label:  'Income',
          sub:    'Track your earnings & revenue',
          onTap:  onIncome,
        ),
        item(
          icon:   Iconsax.location,
          iconBg: const Color(0xFF0984E3),
          label:  'Goals',
          sub:    'Set and crush your targets',
          onTap:  onGoals,
        ),
        item(
          icon:   Iconsax.book,
          iconBg: const Color(0xFFE17055),
          label:  'Skills',
          sub:    'Level up your capabilities',
          onTap:  onSkills,
        ),
        item(
          icon:   Iconsax.crown_1,
          iconBg: const Color(0xFF6C5CE7),
          label:  'Premium',
          sub:    isPremium ? 'Active — enjoy unlimited access' : 'Unlock unlimited tokens & features',
          onTap:  onPremium,
          badge:  isPremium ? null : 'Upgrade',
        ),
        const SizedBox(height: 16),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

/// Token badge — floating pill displayed above-right of "RiseUp" wordmark.
class _TokenBadge extends StatelessWidget {
  final TokenState          tokens;
  final AnimationController pulse;
  const _TokenBadge({required this.tokens, required this.pulse});

  @override
  Widget build(BuildContext context) {
    final pct   = tokens.dailyLimit > 0
        ? tokens.remaining / tokens.dailyLimit
        : 1.0;
    final color = pct > 0.5
        ? AppColors.success
        : pct > 0.2
            ? AppColors.warning
            : AppColors.error;

    return AnimatedBuilder(
      animation: pulse,
      builder: (_, __) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        color.withOpacity(0.18 + pulse.value * 0.05),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: color.withOpacity(0.35)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Iconsax.flash_1, color: color, size: 11),
          const SizedBox(width: 3),
          Text(
            '${tokens.remaining} tokens',
            style: TextStyle(
                color:      color,
                fontSize:   11,
                fontWeight: FontWeight.w700),
          ),
        ]),
      ),
    );
  }
}

/// Mission circle — intact and unchanged from v3.0.
class _MissionCircle extends StatelessWidget {
  final Mission      mission;
  final bool         isActive;
  final VoidCallback onTap;
  const _MissionCircle(
      {required this.mission, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width:  52,
          height: 52,
          decoration: BoxDecoration(
            shape:    BoxShape.circle,
            gradient: isActive
                ? const LinearGradient(
                    colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)])
                : null,
            color:    isActive ? null : _bgSurface(context),
          ),
          child: Center(
              child: Text(mission.emoji,
                  style: const TextStyle(fontSize: 22))),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 56,
          child: Text(
            mission.title,
            textAlign: TextAlign.center,
            maxLines:  1,
            overflow:  TextOverflow.ellipsis,
            style: TextStyle(
                color: isActive
                    ? _textPrimary(context)
                    : _textMuted(context),
                fontSize: 10),
          ),
        ),
      ]),
    );
  }
}

/// New mission circle — intact from v3.0.
class _NewMissionCircle extends StatelessWidget {
  final VoidCallback onTap;
  const _NewMissionCircle({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width:  52,
          height: 52,
          decoration: BoxDecoration(
            shape:  BoxShape.circle,
            border: Border.all(
                color: AppColors.primary, width: 2,
                style: BorderStyle.solid),
          ),
          child: const Center(
              child: Icon(Iconsax.add, color: AppColors.primary, size: 22)),
        ),
        const SizedBox(height: 4),
        Text('New',
            style: TextStyle(color: _textMuted(context), fontSize: 10)),
      ]),
    );
  }
}

/// Chat bubble — theme-aware, logic intact from v3.0.
class _ChatBubble extends StatelessWidget {
  final ChatMessage msg;
  final bool        compact;
  const _ChatBubble({required this.msg, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final isUser  = msg.role == MessageRole.user;
    final padding = compact ? 6.0 : 12.0;

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: EdgeInsets.fromLTRB(48, padding / 2, 8, padding / 2),
          padding: EdgeInsets.all(padding),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
            borderRadius: BorderRadius.only(
              topLeft:     Radius.circular(18),
              topRight:    Radius.circular(4),
              bottomLeft:  Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
          ),
          child: Text(msg.text,
              style: TextStyle(
                  color:    Colors.white,
                  fontSize: compact ? 13 : 15)),
        ),
      ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.1);
    }

    // RiseUp message
    final bubbleBg = _bgSurface(context);
    final textClr  = _textPrimary(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (!compact)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 0, 2),
            child: Row(children: [
              Container(
                width:  20,
                height: 20,
                decoration: const BoxDecoration(
                  shape:    BoxShape.circle,
                  gradient: LinearGradient(
                      colors: [Color(0xFFFF6B00), Color(0xFF6C5CE7)]),
                ),
                child: const Center(
                  child: Text('R',
                      style: TextStyle(
                          color:      Colors.white,
                          fontSize:   10,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 6),
              Text('RiseUp',
                  style: TextStyle(
                      color: _textMuted(context), fontSize: 12)),
            ]),
          ),
        Container(
          margin:  EdgeInsets.fromLTRB(8, 2, 48, padding / 2),
          padding: EdgeInsets.all(padding),
          decoration: BoxDecoration(
            color:        bubbleBg,
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(4),
              topRight:    Radius.circular(18),
              bottomLeft:  Radius.circular(18),
              bottomRight: Radius.circular(18),
            ),
            border: Border.all(color: _border(context)),
          ),
          child: msg.isStreaming
              ? _TypingIndicator()
              : MarkdownBody(
                  data:        msg.text,
                  styleSheet:  MarkdownStyleSheet(
                    p: TextStyle(
                        color:    textClr,
                        fontSize: compact ? 13 : 15,
                        height:   1.5),
                    h2: TextStyle(
                        color:      textClr,
                        fontSize:   17,
                        fontWeight: FontWeight.w700),
                    h3: TextStyle(
                        color:      textClr,
                        fontSize:   15,
                        fontWeight: FontWeight.w600),
                    strong: TextStyle(
                        color:      textClr,
                        fontWeight: FontWeight.w700),
                    em: const TextStyle(color: AppColors.primary),
                    blockquoteDecoration: BoxDecoration(
                      color:  AppColors.primary.withOpacity(0.1),
                      border: const Border(
                          left: BorderSide(
                              color: AppColors.primary, width: 3)),
                    ),
                    code: const TextStyle(
                        color:      Color(0xFF00CEC9),
                        fontFamily: 'monospace',
                        fontSize:   13),
                    codeblockDecoration: BoxDecoration(
                      color:        _bgSurface(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    listBullet:
                        const TextStyle(color: AppColors.primary),
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
    _ctrl = AnimationController(
        vsync:    this,
        duration: const Duration(milliseconds: 1200))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.33;
            final t     = (_ctrl.value - delay).clamp(0.0, 1.0);
            final y     = sin(t * pi) * 4;
            return Transform.translate(
              offset: Offset(0, -y),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                width:  6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.5 + t * 0.5),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ApexStatusBar extends StatelessWidget {
  final ApexStatus          status;
  final AnimationController pulse;
  final VoidCallback         onStop;
  const _ApexStatusBar(
      {required this.status, required this.pulse, required this.onStop});

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
      color:   color.withOpacity(0.08),
      child: Row(children: [
        AnimatedBuilder(
          animation: pulse,
          builder: (_, __) => Icon(Iconsax.cpu,
              size:  14,
              color: color.withOpacity(0.6 + pulse.value * 0.4)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                color:      color,
                fontSize:   12,
                fontWeight: FontWeight.w600)),
        const Spacer(),
        GestureDetector(
          onTap: onStop,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color:        AppColors.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
              border:       Border.all(
                  color: AppColors.error.withOpacity(0.3)),
            ),
            child: const Text('Stop',
                style: TextStyle(
                    color: AppColors.error, fontSize: 11)),
          ),
        ),
      ]),
    );
  }
}

class _SidebarNavItem extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final bool         isDark;
  final VoidCallback onTap;
  final String?      badge;
  const _SidebarNavItem({
    required this.icon,
    required this.label,
    required this.isDark,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    final textClr = isDark ? Colors.white60 : Colors.black54;
    return ListTile(
      dense:   true,
      leading: Icon(icon, color: textClr, size: 20),
      title:   Text(label,
          style: TextStyle(color: textClr, fontSize: 14)),
      trailing: badge != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color:        AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(badge!,
                  style: const TextStyle(
                      color:    AppColors.primary,
                      fontSize: 10)),
            )
          : null,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
    );
  }
}
