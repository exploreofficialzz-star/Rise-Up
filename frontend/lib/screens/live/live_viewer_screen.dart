import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class LiveViewerScreen extends StatefulWidget {
  final String sessionId;
  final String host;
  final String title;
  const LiveViewerScreen({
    super.key,
    required this.sessionId,
    required this.host,
    required this.title,
  });

  @override
  State<LiveViewerScreen> createState() => _LiveViewerScreenState();
}

class _LiveViewerScreenState extends State<LiveViewerScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _joined = false;
  int _viewers = 0;
  int _coins = 0;
  List<Map> _messages = [];

  // Coin gift amounts
  static const _giftAmounts = [10, 50, 100, 500];

  @override
  void initState() {
    super.initState();
    _joinSession();
  }

  Future<void> _joinSession() async {
    try {
      final data = await api.post('/live/sessions/${widget.sessionId}/join', {});
      setState(() {
        _joined = true;
        _viewers = data['viewers'] as int? ?? 0;
      });
    } catch (_) {
      setState(() => _joined = true);
    }

    // Add welcome message
    setState(() {
      _messages.add({'user': '🎉 System', 'text': 'You joined the live!', 'isSystem': true});
      _messages.add({'user': '${widget.host}', 'text': 'Welcome everyone! 👋', 'isSystem': false});
    });
  }

  Future<void> _sendCoins(int amount) async {
    HapticFeedback.mediumImpact();
    try {
      await api.post('/live/sessions/${widget.sessionId}/coins', {'amount': amount});
      setState(() {
        _coins += amount;
        _messages.add({'user': 'You', 'text': '🪙 Sent $amount coins!', 'isSystem': true});
      });
      _scrollToBottom();
    } catch (_) {}
  }

  void _sendMessage() {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _messages.add({'user': 'You', 'text': text, 'isSystem': false}));
    _msgCtrl.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Stream placeholder (dark bg) ─────────────
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('📺', style: TextStyle(fontSize: 72)),
                const SizedBox(height: 16),
                Text(widget.title,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text('Hosted by ${widget.host}',
                    style: const TextStyle(color: Colors.white54, fontSize: 14)),
              ],
            ),
          ),

          // ── Top bar ──────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  // Back
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Live badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Colors.white, size: 8),
                        SizedBox(width: 4),
                        Text('LIVE', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Iconsax.eye, color: Colors.white70, size: 13),
                        const SizedBox(width: 4),
                        Text('${_viewers + _messages.length}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const Spacer(),
                  // Share
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Share link copied!'), backgroundColor: AppColors.success, duration: Duration(seconds: 1)),
                      );
                    },
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Iconsax.send_1, color: Colors.white, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Chat overlay ─────────────────────────────
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withOpacity(0.9), Colors.transparent],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Messages list
                    SizedBox(
                      height: 180,
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        itemCount: _messages.length,
                        itemBuilder: (_, i) {
                          final m = _messages[i];
                          final isSystem = m['isSystem'] == true;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${m['user']}: ',
                                  style: TextStyle(
                                    color: isSystem ? AppColors.gold : AppColors.primary,
                                    fontSize: 12, fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Expanded(
                                  child: Text(
                                    m['text'] ?? '',
                                    style: const TextStyle(color: Colors.white, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),

                    // Coin gifts row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: _giftAmounts.map((amt) {
                          return GestureDetector(
                            onTap: () => _sendCoins(amt),
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: AppColors.gold.withOpacity(0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('🪙', style: TextStyle(fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Text('$amt', style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    // Message input
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _msgCtrl,
                                style: const TextStyle(color: Colors.white, fontSize: 13),
                                decoration: const InputDecoration(
                                  hintText: 'Say something...',
                                  hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                ),
                                onSubmitted: (_) => _sendMessage(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: _sendMessage,
                            child: Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
                              child: const Icon(Iconsax.send_1, color: Colors.white, size: 18),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
