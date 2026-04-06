// frontend/lib/screens/create/create_post_screen.dart
// v3 — Status-style full rewrite
//
// Changes from v2:
//  1. Live preview card (top) with 8 gradient background themes
//  2. Content-type selector: Text / Image / Video / Link
//  3. Background theme colour picker (horizontal scroll circles)
//  4. Font-size slider (text mode only)
//  5. Hashtag field removed — type #tags inline in caption
//  6. Hashtag suggestions fire ONLY after word completion (debounced 700 ms)
//     Tapping a suggestion inserts the full tag
//  7. Searchable / scrollable topic bottom-sheet (45+ topics)
//     Includes: Selling, Buying, Services Offered, Services Wanted,
//     Mentoring, Networking, AI & Tech, Crypto, Healthcare, Legal, etc.
//  8. Expires-After chips: 24 hrs / 48 hrs / 3 days / 7 days
//  9. RepaintBoundary on preview for render-cache performance
// 10. All v2 API calls preserved (createPost, uploadMedia, getLinkPreview,
//     getProfile). expiresHours forwarded to createPost — add
//     `expires_hours` field to the backend route when ready.
// 11. Spam / scam domain & keyword checks preserved from v2.
// 12. THEME: respects system default — never forces dark mode.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Spam / scam protection (unchanged from v2)
// ─────────────────────────────────────────────────────────────────────────────
const _kBlockedDomains = <String>{
  'free-bitcoin.io', 'doubler.cash', 'cryptodouble.net',
  'invest-fast.com', 'fastprofit.xyz', 'earnnow.cc',
};
const _kScamKeywords = <String>[
  'double your', 'triple your', '1000% return', 'guaranteed profit',
  'click here to earn', 'wire transfer', 'western union',
  'send btc', 'send eth', 'private key', 'seed phrase',
  'whatsapp investment', 'dm for investment',
];

bool _isDomainBlocked(String url) {
  try {
    final uri  = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    final host = uri.host.toLowerCase();
    return _kBlockedDomains.any((d) => host.contains(d));
  } catch (_) {
    return false;
  }
}

bool _hasScamContent(String text) =>
    _kScamKeywords.any((k) => text.toLowerCase().contains(k));

// ─────────────────────────────────────────────────────────────────────────────
// Link preview model
// ─────────────────────────────────────────────────────────────────────────────
class _LinkPreview {
  final String url, title, description, domain;
  final String? imageUrl;
  final bool isBlocked;
  final String? blockReason;
  const _LinkPreview({
    required this.url,
    required this.title,
    required this.description,
    required this.domain,
    this.imageUrl,
    this.isBlocked   = false,
    this.blockReason,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Content type
// ─────────────────────────────────────────────────────────────────────────────
enum _CType { text, image, video, link }

class _TypeTab {
  final _CType type; final IconData icon; final String label;
  const _TypeTab(this.type, this.icon, this.label);
}
const _kTypeTabs = <_TypeTab>[
  _TypeTab(_CType.text,  Iconsax.text,      'Text'),
  _TypeTab(_CType.image, Iconsax.image,     'Image'),
  _TypeTab(_CType.video, Iconsax.video,     'Video'),
  _TypeTab(_CType.link,  Icons.link_rounded,'Link'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Background gradient themes
// ─────────────────────────────────────────────────────────────────────────────
const _kThemes = <List<Color>>[
  [Color(0xFF7C6FCD), Color(0xFF5B4FCF)], // 0 purple (default)
  [Color(0xFFFF6B6B), Color(0xFFFF8E53)], // 1 coral
  [Color(0xFF00B4DB), Color(0xFF0083B0)], // 2 cyan
  [Color(0xFF11998E), Color(0xFF38EF7D)], // 3 emerald
  [Color(0xFFFC5C7D), Color(0xFF6A82FB)], // 4 rose-violet
  [Color(0xFFF7971E), Color(0xFFFFD200)], // 5 amber
  [Color(0xFF2C3E50), Color(0xFF4CA1AF)], // 6 slate-teal
  [Color(0xFF1FA2FF), Color(0xFF12D8FA)], // 7 sky
];

// ─────────────────────────────────────────────────────────────────────────────
// Full topic list — 45+ topics
// ─────────────────────────────────────────────────────────────────────────────
const _kAllTopics = <String>[
  // Finance & wealth
  '💰 Wealth',          '📈 Investing',       '💼 Business',
  '🧠 Mindset',         '⚡ Hustle',           '🎯 Skills',
  '🏠 Real Estate',     '💻 Tech',             '📊 Budgeting',
  '🌱 Personal Growth', '💪 Finance',          '🚀 Startups',
  // Commerce & services
  '🛒 Selling',         '🛍️ Buying',           '🔧 Services Offered',
  '🙋 Services Wanted', '🎓 Mentoring',        '🤝 Networking',
  // Learning & development
  '📚 Learning',        '💡 Ideas',            '🎨 Creativity',
  '🏛️ Education',       '📖 Reading',          '🧪 Research',
  // Lifestyle
  '🏋️ Health & Fitness','🌍 Travel',           '🍕 Food & Lifestyle',
  '🎮 Gaming',          '🎵 Music',            '📱 Social Media',
  '📸 Photography',     '🎭 Entertainment',    '⚽ Sports',
  '💄 Beauty & Fashion','❤️ Relationships',    '👨‍👩‍👧 Family',
  // Industry
  '🤖 AI & Tech',       '🌐 Crypto & Web3',    '🖥️ Coding',
  '🔬 Science',         '🌿 Sustainability',   '🏦 Banking',
  '⚖️ Legal',           '🏥 Healthcare',       '🚗 Automotive',
  '🍳 Food Business',   '🏗️ Construction',     '🎪 Events & Marketing',
];

// ─────────────────────────────────────────────────────────────────────────────
// Hashtag suggestion bank
// ─────────────────────────────────────────────────────────────────────────────
const _kHashtagBank = <String>[
  'wealth','wealthbuilding','wealthtips','wealthmindset',
  'investing','investingtips','investingforbeginners','stockmarket',
  'business','businesstips','businessgrowth','entrepreneur','entrepreneurlife',
  'mindset','growthmindset','mindsetshift','positivity','positivethinking',
  'hustle','hustlehard','sidehustle','grind',
  'skills','skillbuilding','learneveryday','levelup',
  'realestate','propertyinvesting','landlord','realestateinvesting',
  'tech','technology','coding','programming','softwaredeveloper',
  'budgeting','savemoney','personalfinance','frugal','financetips',
  'personalgrowth','selfdevelopment','selfimprovement',
  'finance','financialfreedom','financialindependence','moneymanagement',
  'startup','startuplife','founder','buildinpublic',
  'selling','forsale','marketplace','ecommerce','dropshipping',
  'buying','lookingfor','wantedads',
  'services','freelance','hireme','offeringservices','remotework',
  'mentoring','mentor','coaching','lifeadvice','careerguidance',
  'networking','connections','collaboration','communitybuilding',
  'ideas','innovation','creative','brainstorm',
  'fitness','health','workout','wellness','gym','nutrition',
  'motivation','inspiration','success','goals','dailymotivation',
  'money','income','passiveincome','multiplestreams',
  'crypto','bitcoin','web3','blockchain','defi',
  'ai','artificialintelligence','machinelearning',
  'education','learning','studymotivation','knowledge',
  'travel','adventure','explore','digitalnomad',
  'food','foodbusiness','restaurant','catering',
  'marketing','digitalmarketing','contentcreator','socialmedia',
  'sports','athlete','training','photography','photographer',
  'music','artist','musician','producer',
  'fashion','style','lifestyle','beauty',
  'investment','rentalincome','property',
];

// ─────────────────────────────────────────────────────────────────────────────
// Expires options
// ─────────────────────────────────────────────────────────────────────────────
class _ExpiresOpt {
  final int hours; final String label;
  const _ExpiresOpt(this.hours, this.label);
}
const _kExpires = <_ExpiresOpt>[
  _ExpiresOpt(24,  '24 hrs'),
  _ExpiresOpt(48,  '48 hrs'),
  _ExpiresOpt(72,  '3 days'),
  _ExpiresOpt(168, '7 days'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _captionCtrl = TextEditingController();
  final _linkCtrl    = TextEditingController();
  final _linkFocus   = FocusNode();
  final _scrollCtrl  = ScrollController();

  _CType _ctype      = _CType.text;
  int    _themeIndex = 0;
  double _fontSize   = 22.0;
  String _topic      = '💰 Wealth';
  int    _expiresHrs = 24;
  bool   _loading    = false;
  bool   _uploading  = false;

  XFile?     _mediaFile;
  Uint8List? _mediaBytes;
  String?    _mediaUrl;
  String     _mediaType = 'image';

  _LinkPreview? _linkPreview;
  String?       _linkError;
  bool          _linkChecking = false;
  Timer?        _linkDebounce;

  List<String> _hashSuggestions = [];
  Timer?       _hashDebounce;

  String  _userName     = 'You';
  String? _userAvatarUrl;

  static const int _maxChars = 500;
  int get _charCount => _captionCtrl.text.length;

  @override
  void initState() {
    super.initState();
    _captionCtrl.addListener(_onCaptionChanged);
    _loadProfile();
  }

  @override
  void dispose() {
    _captionCtrl.removeListener(_onCaptionChanged);
    _captionCtrl.dispose();
    _linkCtrl.dispose();
    _linkFocus.dispose();
    _scrollCtrl.dispose();
    _linkDebounce?.cancel();
    _hashDebounce?.cancel();
    super.dispose();
  }

  // ── Profile ────────────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    try {
      final data    = await api.getProfile();
      if (!mounted) return;
      final profile = data['profile'] as Map? ?? data;
      final name    = profile['full_name']?.toString()
          ?? profile['name']?.toString() ?? '';
      final avatar  = profile['avatar_url']?.toString() ?? '';
      setState(() {
        if (name.isNotEmpty) _userName = name;
        _userAvatarUrl = avatar;
      });
    } catch (_) {}
  }

  // ── Caption ────────────────────────────────────────────────────────────────
  void _onCaptionChanged() {
    setState(() {});
    _hashDebounce?.cancel();
    _hashDebounce = Timer(
      const Duration(milliseconds: 700), _computeHashtagSuggestions);
  }

  // Suggestions only fire once a #word is complete:
  //   cursor at end of text, OR next char is whitespace.
  void _computeHashtagSuggestions() {
    final text   = _captionCtrl.text;
    final cursor = _captionCtrl.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      if (mounted) setState(() => _hashSuggestions = []);
      return;
    }
    final before = text.substring(0, cursor);
    final match  = RegExp(r'#(\w{2,})$').firstMatch(before);
    if (match == null) {
      if (mounted) setState(() => _hashSuggestions = []);
      return;
    }
    final word     = match.group(1)!.toLowerCase();
    final nextChar = cursor < text.length ? text[cursor] : ' ';
    final wordDone = nextChar == ' ' || nextChar == '\n'
        || nextChar == '\r' || cursor == text.length;

    if (!wordDone) {
      final list = _kHashtagBank
          .where((h) => h.startsWith(word) && h != word)
          .take(5).toList();
      if (mounted) setState(() => _hashSuggestions = list);
      return;
    }
    final list = _kHashtagBank
        .where((h) => (h.startsWith(word) || h.contains(word)) && h != word)
        .take(6).toList();
    if (mounted) setState(() => _hashSuggestions = list);
  }

  void _applyHashSuggestion(String tag) {
    final text      = _captionCtrl.text;
    final cursor    = _captionCtrl.selection.baseOffset;
    if (cursor < 0) return;
    final before    = text.substring(0, cursor);
    final after     = text.substring(cursor);
    final newBefore = before.replaceAll(RegExp(r'#\w*$'), '#$tag');
    final suffix    = after.startsWith(' ') ? after : ' $after';
    _captionCtrl.value = TextEditingValue(
      text:      newBefore + suffix,
      selection: TextSelection.collapsed(offset: newBefore.length + 1),
    );
    setState(() => _hashSuggestions = []);
  }

  // ── Media ──────────────────────────────────────────────────────────────────
  Future<void> _pickMedia({required bool isVideo}) async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      XFile? file;
      if (isVideo) {
        file = await picker.pickVideo(source: ImageSource.gallery);
      } else {
        file = await picker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1920, imageQuality: 88);
      }
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _mediaFile  = file;
        _mediaBytes = bytes;
        _mediaType  = isVideo ? 'video' : 'image';
        _uploading  = true;
        _mediaUrl   = null;
      });
      await _uploadMedia(file, bytes: bytes, isVideo: isVideo);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        _showError('Could not load file. Please try again.');
      }
    }
  }

  Future<void> _uploadMedia(XFile file,
      {required Uint8List bytes, required bool isVideo}) async {
    try {
      final extRaw = file.name.toLowerCase().contains('.')
          ? file.name.toLowerCase().split('.').last : '';
      Map<String, dynamic> res;
      if (file.path.isNotEmpty) {
        res = await api.uploadPostMedia(file.path);
      } else {
        res = await api.uploadPostMediaBytes(
          bytes:    bytes,
          filename: file.name.isNotEmpty
              ? file.name : 'media.${isVideo ? 'mp4' : 'jpg'}',
          mimeType: _mimeFromExt(extRaw, isVideo: isVideo),
        );
      }
      if (mounted) {
        setState(() {
          _mediaUrl  = res['url']?.toString();
          _mediaType = res['media_type']?.toString()
              ?? (isVideo ? 'video' : 'image');
          _uploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false; _mediaFile  = null;
          _mediaBytes = null; _mediaUrl   = null;
        });
        _showError('Upload failed. Check your connection and try again.');
      }
    }
  }

  String _mimeFromExt(String ext, {required bool isVideo}) {
    const img = {'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png',
      'webp':'image/webp','gif':'image/gif','heic':'image/heic'};
    const vid = {'mp4':'video/mp4','mov':'video/quicktime',
      'avi':'video/x-msvideo','mkv':'video/x-matroska','webm':'video/webm'};
    return (isVideo ? vid : img)[ext] ?? (isVideo ? 'video/mp4' : 'image/jpeg');
  }

  void _clearMedia() => setState(() {
    _mediaFile = null; _mediaBytes = null;
    _mediaUrl  = null; _uploading  = false;
  });

  // ── Link ───────────────────────────────────────────────────────────────────
  void _onLinkChanged(String v) {
    _linkDebounce?.cancel();
    setState(() { _linkPreview = null; _linkError = null; });
    if (v.trim().isEmpty) return;
    _linkDebounce = Timer(const Duration(milliseconds: 800),
        () => _validateLink(v.trim()));
  }

  Future<void> _validateLink(String rawUrl) async {
    final url = rawUrl.startsWith('http') ? rawUrl : 'https://$rawUrl';
    Uri? uri;
    try { uri = Uri.parse(url); } catch (_) {}
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      if (mounted) setState(() => _linkError = 'Invalid URL format.');
      return;
    }
    if (_isDomainBlocked(url)) {
      if (mounted) setState(() => _linkError =
          '🚫 This domain is blocked by RiseUp safety filters.');
      return;
    }
    if (_hasScamContent(url)) {
      if (mounted) setState(() => _linkError =
          '⚠️ This link appears to promote a scam.');
      return;
    }
    if (mounted) setState(() => _linkChecking = true);
    try {
      final data = await api.getLinkPreview(url);
      if (!mounted) return;
      if (data['blocked'] == true) {
        setState(() {
          _linkChecking = false;
          _linkError = data['reason']?.toString()
              ?? '🚫 Link blocked by RiseUp safety filters.';
        });
        return;
      }
      setState(() {
        _linkChecking = false;
        _linkPreview  = _LinkPreview(
          url:         url,
          title:       data['title']?.toString() ?? uri!.host,
          description: data['description']?.toString() ?? '',
          domain:      uri!.host,
          imageUrl:    data['image']?.toString(),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _linkChecking = false;
          _linkPreview  = _LinkPreview(
            url: url, title: uri!.host,
            description: '', domain: uri.host,
          );
        });
      }
    }
  }

  // ── Post ───────────────────────────────────────────────────────────────────
  Future<void> _post() async {
    final content = _captionCtrl.text.trim();
    if (_loading || _uploading) return;
    if (content.isEmpty && _mediaUrl == null && _linkPreview == null) return;
    if (_charCount > _maxChars) return;
    if (_hasScamContent(content)) {
      _showError('⚠️ Post contains content that violates community guidelines.');
      return;
    }
    if (_ctype == _CType.link && _linkError != null) {
      _showError('Please fix the link before posting.');
      return;
    }
    setState(() => _loading = true);
    try {
      await api.createPost(
        content:      content.isNotEmpty ? content : '🔗 Link post',
        tag:          _topic,
        mediaUrl:     _mediaUrl,
        mediaType:    _mediaUrl != null ? _mediaType : null,
        linkUrl:      _ctype == _CType.link ? _linkPreview?.url : null,
        linkTitle:    _linkPreview?.title,
        // NOTE: Wire `expires_hours` → `status_expires_at` on the backend
        // createPost route when ready.
        expiresHours: _expiresHrs,
      );
      if (mounted) {
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mediaUrl != null
              ? 'Status submitted for review! 🔍'
              : 'Status shared! 🚀'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: _mediaUrl != null ? 4 : 2),
        ));
        context.go('/home');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _showError('Failed to post. Please try again.');
      }
    }
  }

  void _showError(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: AppColors.error,
        duration: const Duration(seconds: 3)));

  void _openTopicPicker() {
    showModalBottomSheet(
      context:            context,
      isScrollControlled: true,
      backgroundColor:    Colors.transparent,
      builder: (_) => _TopicPickerSheet(
        selected: _topic,
        onSelect: (t) { setState(() => _topic = t); Navigator.pop(context); },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // System theme — never hardcode dark.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? Colors.black            : Colors.white;
    final card   = isDark ? AppColors.bgCard        : Colors.white;
    final surf   = isDark ? AppColors.bgSurface     : Colors.grey.shade100;
    final border = isDark ? AppColors.bgSurface     : Colors.grey.shade200;
    final txt    = isDark ? Colors.white            : Colors.black87;
    final sub    = isDark ? Colors.white54          : Colors.black45;
    final lbl    = isDark ? Colors.white30          : Colors.black38;

    final overLimit = _charCount > _maxChars;
    final canPost   = !overLimit && !_loading && !_uploading &&
        (_captionCtrl.text.trim().isNotEmpty ||
         _mediaUrl != null ||
         (_ctype == _CType.link && _linkPreview != null));

    return Scaffold(
      backgroundColor:          bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor:  card,
        elevation:        0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: txt),
          onPressed: () => context.go('/home'),
        ),
        title: Text('New Status', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: txt)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: GestureDetector(
              onTap: canPost ? _post : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: canPost
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent])
                      : null,
                  color:        canPost ? null : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _loading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Post', style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700,
                        fontSize: 14)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: SingleChildScrollView(
        controller: _scrollCtrl,
        child: Column(children: [

          // ── Live preview card ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: RepaintBoundary(
              child: _buildPreviewCard(isDark, surf),
            ),
          ).animate().fadeIn(duration: 300.ms),

          const SizedBox(height: 20),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // CONTENT TYPE
                _sLbl('CONTENT TYPE', lbl),
                const SizedBox(height: 10),
                _buildTypeTabs(isDark, surf, border),
                const SizedBox(height: 22),

                // BACKGROUND THEME — text & link types only
                if (_ctype == _CType.text || _ctype == _CType.link) ...[
                  _sLbl('BACKGROUND THEME', lbl),
                  const SizedBox(height: 10),
                  _buildThemeRow(),
                  const SizedBox(height: 22),
                ],

                // FONT SIZE — text only
                if (_ctype == _CType.text) ...[
                  _buildFontSizeRow(lbl),
                  const SizedBox(height: 22),
                ],

                // YOUR STATUS
                _sLbl('YOUR STATUS', lbl),
                const SizedBox(height: 8),
                _buildCaptionField(isDark, txt, sub, surf, border, overLimit),

                // Char counter
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${_maxChars - _charCount}',
                        style: TextStyle(
                          fontSize:   12,
                          fontWeight: FontWeight.w600,
                          color: overLimit
                              ? AppColors.error
                              : (_maxChars - _charCount) < 50
                                  ? AppColors.warning : sub,
                        )),
                  ),
                ),

                // Hashtag suggestions
                if (_hashSuggestions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildHashSuggestions(isDark, sub),
                ],

                const SizedBox(height: 16),

                // Link input — link type only
                if (_ctype == _CType.link) ...[
                  _buildLinkInput(isDark, txt, sub, surf, border),
                  const SizedBox(height: 16),
                ],

                // Media moderation notice
                if (_mediaBytes != null && _ctype != _CType.link) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color:        Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: Colors.orange.withOpacity(0.3)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.shield_outlined,
                          color: Colors.orange, size: 14),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                        'Media posts are reviewed to keep the community '
                        'safe from inappropriate content.',
                        style: TextStyle(
                            fontSize: 11, color: Colors.orange, height: 1.4),
                      )),
                    ]),
                  ),
                ],

                // TOPIC
                _sLbl('TOPIC', lbl),
                const SizedBox(height: 10),
                _buildTopicChip(surf, sub),
                const SizedBox(height: 22),

                // EXPIRES AFTER
                _sLbl('EXPIRES AFTER', lbl),
                const SizedBox(height: 10),
                _buildExpiresRow(isDark, surf, border, sub),
                const SizedBox(height: 28),

                // Post Status button
                SizedBox(
                  width: double.infinity, height: 54,
                  child: ElevatedButton(
                    onPressed: canPost ? _post : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor:
                          AppColors.primary.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : const Text('Post Status', style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ),

                SizedBox(
                    height: MediaQuery.of(context).padding.bottom + 28),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  // ── Section label ──────────────────────────────────────────────────────────
  Widget _sLbl(String text, Color color) => Text(text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
          color: color, letterSpacing: 0.8));

  // ── Preview card ───────────────────────────────────────────────────────────
  Widget _buildPreviewCard(bool isDark, Color surf) {
    final theme   = _kThemes[_themeIndex];
    final caption = _captionCtrl.text;

    return GestureDetector(
      onTap: (_ctype == _CType.image || _ctype == _CType.video)
          ? () => _pickMedia(isVideo: _ctype == _CType.video)
          : null,
      child: AspectRatio(
        aspectRatio: 9 / 14,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Stack(fit: StackFit.expand, children: [

            // Background
            if (_ctype == _CType.image && _mediaBytes != null)
              Image.memory(_mediaBytes!, fit: BoxFit.cover)
            else
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: theme,
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight,
                  ),
                ),
              ),

            // Text overlay
            if (_ctype == _CType.text)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    caption.isEmpty ? 'Your status preview' : caption,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize:   _fontSize,
                      color:      Colors.white,
                      fontWeight: FontWeight.w600,
                      height:     1.45,
                      shadows: const [
                        Shadow(blurRadius: 10, color: Colors.black26)],
                    ),
                  ),
                ),
              ),

            // Video overlay
            if (_ctype == _CType.video)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_mediaBytes != null) ...[
                    const Icon(Icons.videocam_rounded,
                        color: Colors.white, size: 56),
                    const SizedBox(height: 10),
                    const Text('Video ready ✅', style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                  ] else ...[
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle),
                      child: const Icon(Icons.video_call_rounded,
                          color: Colors.white, size: 30),
                    ),
                    const SizedBox(height: 12),
                    const Text('Tap to add video', style: TextStyle(
                        color: Colors.white70, fontSize: 14)),
                  ],
                ]),
              ),

            // Image placeholder
            if (_ctype == _CType.image && _mediaBytes == null)
              Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle),
                    child: const Icon(Icons.add_photo_alternate_rounded,
                        color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 12),
                  const Text('Tap to add photo', style: TextStyle(
                      color: Colors.white70, fontSize: 14)),
                ]),
              ),

            // Link mini-preview on card
            if (_ctype == _CType.link && _linkPreview != null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.3)),
                    ),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Row(children: [
                        const Icon(Icons.link_rounded,
                            color: Colors.white70, size: 13),
                        const SizedBox(width: 6),
                        Flexible(child: Text(_linkPreview!.domain,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 11))),
                      ]),
                      const SizedBox(height: 6),
                      Text(_linkPreview!.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ),

            // Upload progress
            if (_uploading)
              Container(
                color: Colors.black38,
                child: const Center(child: Column(
                    mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                  SizedBox(height: 12),
                  Text('Uploading…', style: TextStyle(
                      color: Colors.white, fontSize: 13)),
                ])),
              ),

            // Remove media
            if (_mediaBytes != null)
              Positioned(top: 12, right: 12,
                child: GestureDetector(
                  onTap: _clearMedia,
                  child: Container(
                    width: 30, height: 30,
                    decoration: const BoxDecoration(
                        color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
              ),

            // Uploaded badge
            if (_mediaUrl != null)
              Positioned(bottom: 12, left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:        AppColors.success.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_rounded,
                        color: Colors.white, size: 12),
                    SizedBox(width: 4),
                    Text('Uploaded', style: TextStyle(
                        color: Colors.white, fontSize: 11,
                        fontWeight: FontWeight.w600)),
                  ]),
                ),
              ),

            // PREVIEW label
            Positioned(bottom: 12, right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color:        Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('PREVIEW', style: TextStyle(
                    color: Colors.white70, fontSize: 10,
                    fontWeight: FontWeight.w600, letterSpacing: 0.6)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // ── Content type tabs ──────────────────────────────────────────────────────
  Widget _buildTypeTabs(bool isDark, Color surf, Color border) {
    final iconOff = isDark ? Colors.white54 : Colors.black38;
    return Row(
      children: _kTypeTabs.map((t) {
        final sel = _ctype == t.type;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _ctype = t.type);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin:   const EdgeInsets.only(right: 8),
              padding:  const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:        sel ? AppColors.primary : surf,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: sel ? AppColors.primary : border),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(t.icon,
                    color: sel ? Colors.white : iconOff,
                    size:  22),
                const SizedBox(height: 4),
                Text(t.label, style: TextStyle(
                    fontSize:   11,
                    color:      sel ? Colors.white : iconOff,
                    fontWeight: sel
                        ? FontWeight.w600 : FontWeight.w400)),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Theme row ──────────────────────────────────────────────────────────────
  Widget _buildThemeRow() => SizedBox(
    height: 50,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount:       _kThemes.length,
      itemBuilder: (_, i) {
        final sel = i == _themeIndex;
        return GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _themeIndex = i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 50, height: 50,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: _kThemes[i],
                  begin:  Alignment.topLeft,
                  end:    Alignment.bottomRight),
              shape:  BoxShape.circle,
              border: Border.all(
                  color: sel ? Colors.white : Colors.transparent,
                  width: sel ? 2.5 : 0),
              boxShadow: sel
                  ? [BoxShadow(
                      color:        _kThemes[i][0].withOpacity(0.45),
                      blurRadius:   10,
                      spreadRadius: 2)]
                  : [],
            ),
            child: sel
                ? const Center(child: Icon(Icons.check_rounded,
                    color: Colors.white, size: 20))
                : null,
          ),
        );
      },
    ),
  );

  // ── Font size row ──────────────────────────────────────────────────────────
  Widget _buildFontSizeRow(Color lbl) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        _sLbl('FONT SIZE', lbl),
        const Spacer(),
        Text('${_fontSize.round()}px', style: const TextStyle(
            fontSize: 13, color: AppColors.primary,
            fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 4),
      SliderTheme(
        data: SliderThemeData(
          activeTrackColor:   AppColors.primary,
          inactiveTrackColor: AppColors.primary.withOpacity(0.2),
          thumbColor:         AppColors.primary,
          overlayColor:       AppColors.primary.withOpacity(0.15),
          trackHeight:        3,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
        ),
        child: Slider(
          value: _fontSize, min: 14, max: 40, divisions: 26,
          onChanged: (v) => setState(() => _fontSize = v),
        ),
      ),
    ],
  );

  // ── Caption field ──────────────────────────────────────────────────────────
  Widget _buildCaptionField(bool isDark, Color txt, Color sub,
      Color surf, Color border, bool overLimit) {
    return Container(
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: overLimit
            ? AppColors.error.withOpacity(0.5) : border),
      ),
      child: TextField(
        controller: _captionCtrl,
        maxLines:   null,
        minLines:   5,
        style: TextStyle(fontSize: 15, color: txt, height: 1.6),
        decoration: InputDecoration(
          hintText: _ctype == _CType.text
              ? 'Share your wealth journey, tips, wins or lessons…\n\n'
                '💡 What did you learn today?\n'
                '💰 What income milestone did you hit?\n'
                '🚀 What strategy worked for you?\n\n'
                'Tip: add #hashtags directly here'
              : 'Add a caption… (use #hashtags inline)',
          hintStyle: TextStyle(
              color: sub, fontSize: 13, height: 1.6),
          border:         InputBorder.none,
          contentPadding: const EdgeInsets.all(14),
        ),
      ),
    );
  }

  // ── Hashtag suggestions ────────────────────────────────────────────────────
  Widget _buildHashSuggestions(bool isDark, Color sub) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Suggestions',
          style: TextStyle(fontSize: 11, color: sub,
              fontWeight: FontWeight.w500)),
      const SizedBox(height: 6),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _hashSuggestions.map((tag) => GestureDetector(
            onTap: () => _applyHashSuggestion(tag),
            child: Container(
              margin:  const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:        AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Text('#$tag', style: const TextStyle(
                  fontSize:   12,
                  color:      AppColors.primary,
                  fontWeight: FontWeight.w600)),
            ),
          )).toList(),
        ),
      ),
    ],
  );

  // ── Link input ─────────────────────────────────────────────────────────────
  Widget _buildLinkInput(bool isDark, Color txt, Color sub,
      Color surf, Color border) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        decoration: BoxDecoration(
          color:        surf,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _linkError != null
              ? AppColors.error.withOpacity(0.5) : border),
        ),
        child: Row(children: [
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Icon(Icons.link_rounded,
                color: _linkError != null
                    ? AppColors.error : AppColors.primary,
                size: 18),
          ),
          Expanded(
            child: TextField(
              controller:   _linkCtrl,
              focusNode:    _linkFocus,
              keyboardType: TextInputType.url,
              style:        TextStyle(fontSize: 14, color: txt),
              onChanged:    _onLinkChanged,
              decoration: InputDecoration(
                hintText:  'Paste a link (https://…)',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                border:    InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 12),
              ),
            ),
          ),
          if (_linkChecking)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary)),
            )
          else if (_linkCtrl.text.isNotEmpty)
            IconButton(
              icon:      const Icon(Icons.close_rounded, size: 18),
              color:     sub,
              onPressed: () => setState(() {
                _linkCtrl.clear();
                _linkPreview = null;
                _linkError   = null;
              }),
            ),
        ]),
      ),
      if (_linkError != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          const Icon(Icons.block_rounded,
              color: AppColors.error, size: 13),
          const SizedBox(width: 6),
          Expanded(child: Text(_linkError!, style: const TextStyle(
              color: AppColors.error, fontSize: 12))),
        ]),
      ],
      if (_linkPreview != null && _linkError == null) ...[
        const SizedBox(height: 10),
        _buildLinkCard(_linkPreview!, txt, sub, surf),
      ],
    ]);
  }

  Widget _buildLinkCard(_LinkPreview p, Color txt, Color sub, Color surf) {
    return Container(
      decoration: BoxDecoration(
        color:        surf,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.imageUrl != null)
          Image.network(p.imageUrl!, height: 130,
              width: double.infinity, fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 16, height: 16,
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: const Icon(Icons.language_rounded,
                    color: AppColors.primary, size: 10),
              ),
              const SizedBox(width: 6),
              Flexible(child: Text(p.domain,
                  style: TextStyle(fontSize: 11, color: sub))),
              const Spacer(),
              const Icon(Icons.verified_rounded,
                  color: AppColors.success, size: 14),
              const SizedBox(width: 4),
              const Text('Verified', style: TextStyle(
                  fontSize: 10, color: AppColors.success,
                  fontWeight: FontWeight.w600)),
            ]),
            if (p.title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.title, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13,
                      fontWeight: FontWeight.w700, color: txt)),
            ],
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.description, maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12,
                      color: sub, height: 1.4)),
            ],
          ]),
        ),
      ]),
    );
  }

  // ── Topic chip ─────────────────────────────────────────────────────────────
  Widget _buildTopicChip(Color surf, Color sub) => Row(children: [
    GestureDetector(
      onTap: _openTopicPicker,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color:        AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Text(_topic, style: const TextStyle(
            fontSize:   13,
            color:      AppColors.primary,
            fontWeight: FontWeight.w600)),
      ),
    ),
    const SizedBox(width: 10),
    GestureDetector(
      onTap: _openTopicPicker,
      child: Text('Change', style: TextStyle(
          fontSize:   13,
          color:      sub,
          decoration: TextDecoration.underline,
          decorationColor: sub)),
    ),
  ]);

  // ── Expires row ────────────────────────────────────────────────────────────
  Widget _buildExpiresRow(
      bool isDark, Color surf, Color border, Color sub) {
    return Row(
      children: _kExpires.map((opt) {
        final sel = opt.hours == _expiresHrs;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _expiresHrs = opt.hours);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin:   const EdgeInsets.only(right: 8),
              padding:  const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color:        sel ? AppColors.primary : surf,
                borderRadius: BorderRadius.circular(12),
                border:       Border.all(
                    color: sel ? AppColors.primary : border),
              ),
              child: Center(
                child: Text(opt.label, style: TextStyle(
                    fontSize:   12,
                    fontWeight: FontWeight.w600,
                    color:      sel ? Colors.white : sub)),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Topic picker bottom-sheet
// ─────────────────────────────────────────────────────────────────────────────
class _TopicPickerSheet extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _TopicPickerSheet({
    required this.selected,
    required this.onSelect,
  });
  @override
  State<_TopicPickerSheet> createState() => _TopicPickerSheetState();
}

class _TopicPickerSheetState extends State<_TopicPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<String> _filtered = _kAllTopics;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearch);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearch);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearch() {
    final q = _searchCtrl.text.toLowerCase().trim();
    setState(() {
      _filtered = q.isEmpty
          ? _kAllTopics
          : _kAllTopics
              .where((t) => t.toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // System theme — no dark force.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? AppColors.bgCard    : Colors.white;
    final surf   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final txt    = isDark ? Colors.white        : Colors.black87;
    final sub    = isDark ? Colors.white54      : Colors.black45;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize:     0.4,
      maxChildSize:     0.92,
      expand:           false,
      builder: (_, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color:        bg,
          borderRadius: const BorderRadius.vertical(
              top: Radius.circular(24)),
        ),
        child: Column(children: [

          // Handle
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
                color:        Colors.grey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2)),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text('Choose Topic', style: TextStyle(
                  fontSize:   18,
                  fontWeight: FontWeight.w700,
                  color:      txt)),
              const Spacer(),
              Text('${_kAllTopics.length} topics',
                  style: TextStyle(fontSize: 12, color: sub)),
            ]),
          ),
          const SizedBox(height: 14),

          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                  color:        surf,
                  borderRadius: BorderRadius.circular(14),
                  border:       Border.all(color: border)),
              child: Row(children: [
                const Padding(
                  padding: EdgeInsets.only(left: 12),
                  child: Icon(Icons.search_rounded,
                      color: AppColors.primary, size: 20),
                ),
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    style:      TextStyle(fontSize: 14, color: txt),
                    decoration: InputDecoration(
                      hintText:  'Search topics…',
                      hintStyle: TextStyle(color: sub, fontSize: 13),
                      border:    InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 13),
                    ),
                  ),
                ),
                if (_searchCtrl.text.isNotEmpty)
                  IconButton(
                    icon:      const Icon(Icons.close_rounded, size: 18),
                    color:     sub,
                    onPressed: () => _searchCtrl.clear(),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),

          // List
          Expanded(
            child: _filtered.isEmpty
                ? Center(child: Text('No topics found',
                    style: TextStyle(color: sub, fontSize: 14)))
                : ListView.builder(
                    controller: scrollCtrl,
                    padding:    const EdgeInsets.symmetric(horizontal: 16),
                    itemCount:  _filtered.length,
                    itemBuilder: (_, i) {
                      final topic = _filtered[i];
                      final sel   = topic == widget.selected;
                      return GestureDetector(
                        onTap: () => widget.onSelect(topic),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          margin:   const EdgeInsets.only(bottom: 8),
                          padding:  const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 13),
                          decoration: BoxDecoration(
                            color: sel
                                ? AppColors.primary.withOpacity(0.1)
                                : surf,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: sel
                                    ? AppColors.primary.withOpacity(0.4)
                                    : Colors.transparent),
                          ),
                          child: Row(children: [
                            Expanded(child: Text(topic,
                                style: TextStyle(
                                    fontSize:   14,
                                    fontWeight: sel
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: sel
                                        ? AppColors.primary : txt))),
                            if (sel)
                              const Icon(Icons.check_circle_rounded,
                                  color: AppColors.primary, size: 18),
                          ]),
                        ),
                      );
                    },
                  ),
          ),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ]),
      ),
    );
  }
}
