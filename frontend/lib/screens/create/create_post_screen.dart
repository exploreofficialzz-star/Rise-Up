// frontend/lib/screens/create/create_post_screen.dart
// v7.0 — Create Post  (background_color → API + post sound)
//
// NEW in v7.0:
//  1. BACKGROUND COLOR PASSTHROUGH → extracts #RRGGBB hex from the active theme
//     when text mode + background toggle is ON and sends it to api.createPost()
//     so the home feed PostCard renders the exact same colored background.
//  2. POST SOUND → on successful post or status, triggers a local notification
//     via NotificationService which plays the device's DEFAULT notification tone
//     (same as WhatsApp / Facebook — no custom sound file required).
//  3. STATUS SOUND → same local notification tone when status is created.
// ✅ ALL v6.0 FEATURES PRESERVED 100%:
//  Cache-first profile, shimmer skeleton, last-used topic, link preview cache,
//  system fallback, all gradients, themes, video trim, brain signal

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/notification_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SharedPreferences cache keys
// ─────────────────────────────────────────────────────────────────────────────
const _kCacheName       = 'cp_cache_name';
const _kCacheAvatar     = 'cp_cache_avatar';
const _kCacheLastTopic  = 'cp_cache_last_topic';

// ─────────────────────────────────────────────────────────────────────────────
// Safety filters
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
    final h = Uri.parse(url.startsWith('http') ? url : 'https://$url')
        .host.toLowerCase();
    return _kBlockedDomains.any((d) => h.contains(d));
  } catch (_) { return false; }
}

bool _hasScamContent(String t) =>
    _kScamKeywords.any((k) => t.toLowerCase().contains(k));

// ─────────────────────────────────────────────────────────────────────────────
// Theme model
// ─────────────────────────────────────────────────────────────────────────────
class _PostTheme {
  final List<Color> colors;
  final bool textDark;
  const _PostTheme(this.colors, {this.textDark = false});

  bool get isGradient => colors.length > 1;
  Color get textColor => textDark ? Colors.black87 : Colors.white;

  Decoration get decoration => BoxDecoration(
        color: isGradient ? null : colors.first,
        gradient: isGradient
            ? LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
      );

  // v7.0: extract hex for the dominant / first color
  String get hexColor {
    final c   = colors.first;
    final hex = c.value.toRadixString(16).padLeft(8, '0').substring(2);
    return '#$hex';
  }
}

const _kThemes = <_PostTheme>[
  // Gradients (0–11)
  _PostTheme([Color(0xFF7C6FCD), Color(0xFF5B4FCF)]),
  _PostTheme([Color(0xFFFF6B6B), Color(0xFFFF8E53)]),
  _PostTheme([Color(0xFF00B4DB), Color(0xFF0083B0)]),
  _PostTheme([Color(0xFF11998E), Color(0xFF38EF7D)]),
  _PostTheme([Color(0xFFFC5C7D), Color(0xFF6A82FB)]),
  _PostTheme([Color(0xFFF7971E), Color(0xFFFFD200)]),
  _PostTheme([Color(0xFF2C3E50), Color(0xFF4CA1AF)]),
  _PostTheme([Color(0xFF1FA2FF), Color(0xFF12D8FA)]),
  _PostTheme([Color(0xFFFF512F), Color(0xFFDD2476)]),
  _PostTheme([Color(0xFF134E5E), Color(0xFF71B280)]),
  _PostTheme([Color(0xFF360033), Color(0xFF0B8793)]),
  _PostTheme([Color(0xFFFFB347), Color(0xFFFF6961)]),
  // Solids (12–23)
  _PostTheme([Color(0xFF000000)]),
  _PostTheme([Color(0xFFFFFFFF)], textDark: true),
  _PostTheme([Color(0xFFE53935)]),
  _PostTheme([Color(0xFFE65100)]),
  _PostTheme([Color(0xFFF9A825)], textDark: true),
  _PostTheme([Color(0xFF2E7D32)]),
  _PostTheme([Color(0xFF1565C0)]),
  _PostTheme([Color(0xFF6A1B9A)]),
  _PostTheme([Color(0xFFAD1457)]),
  _PostTheme([Color(0xFF00695C)]),
  _PostTheme([Color(0xFF37474F)]),
  _PostTheme([Color(0xFF4E342E)]),
];

// ─────────────────────────────────────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────────────────────────────────────
enum _CType { text, image, video }
enum _Panel { none, theme, font, trim, link }

// ─────────────────────────────────────────────────────────────────────────────
// Topics
// ─────────────────────────────────────────────────────────────────────────────
const _kAllTopics = <String>[
  '💰 Wealth',          '📈 Investing',        '💼 Business',
  '🧠 Mindset',         '⚡ Hustle',            '🎯 Skills',
  '🏠 Real Estate',     '💻 Tech',              '📊 Budgeting',
  '🌱 Personal Growth', '💪 Finance',           '🚀 Startups',
  '🛒 Selling',         '🛍️ Buying',            '🔧 Services Offered',
  '🙋 Services Wanted', '🎓 Mentoring',         '🤝 Networking',
  '📚 Learning',        '💡 Ideas',             '🎨 Creativity',
  '🏛️ Education',       '📖 Reading',           '🧪 Research',
  '🏋️ Health & Fitness','🌍 Travel',            '🍕 Food & Lifestyle',
  '🎮 Gaming',          '🎵 Music',             '📱 Social Media',
  '📸 Photography',     '🎭 Entertainment',     '⚽ Sports',
  '💄 Beauty & Fashion','❤️ Relationships',     '👨‍👩‍👧 Family',
  '🤖 AI & Tech',       '🌐 Crypto & Web3',     '🖥️ Coding',
  '🔬 Science',         '🌿 Sustainability',    '🏦 Banking',
  '⚖️ Legal',           '🏥 Healthcare',        '🚗 Automotive',
  '🍳 Food Business',   '🏗️ Construction',      '🎪 Events & Marketing',
];

// ─────────────────────────────────────────────────────────────────────────────
// Hashtag bank
// ─────────────────────────────────────────────────────────────────────────────
const _kHashtagBank = <String>[
  'wealth','wealthbuilding','wealthtips','wealthmindset','investing',
  'investingtips','investingforbeginners','stockmarket','business','businesstips',
  'businessgrowth','entrepreneur','entrepreneurlife','mindset','growthmindset',
  'mindsetshift','hustle','hustlehard','sidehustle','grind','skills',
  'skillbuilding','learneveryday','levelup','realestate','propertyinvesting',
  'landlord','tech','technology','coding','programming','softwaredeveloper',
  'budgeting','savemoney','personalfinance','frugal','financetips','personalgrowth',
  'selfdevelopment','selfimprovement','finance','financialfreedom',
  'financialindependence','moneymanagement','startup','startuplife','founder',
  'buildinpublic','selling','forsale','marketplace','ecommerce','dropshipping',
  'buying','lookingfor','services','freelance','hireme','offeringservices',
  'remotework','mentoring','mentor','coaching','lifeadvice','careerguidance',
  'networking','connections','collaboration','ideas','innovation','creative',
  'fitness','health','workout','wellness','gym','nutrition','motivation',
  'inspiration','success','goals','dailymotivation','money','income',
  'passiveincome','multiplestreams','crypto','bitcoin','web3','blockchain',
  'defi','ai','artificialintelligence','machinelearning','education','learning',
  'travel','adventure','explore','digitalnomad','food','foodbusiness',
  'marketing','digitalmarketing','contentcreator','socialmedia','sports',
  'athlete','training','photography','music','artist','fashion','style',
  'lifestyle','beauty','investment','rentalincome','property',
];

// ─────────────────────────────────────────────────────────────────────────────
// Link preview model
// ─────────────────────────────────────────────────────────────────────────────
class _LinkPreview {
  final String url, title, description, domain;
  final String? imageUrl;
  const _LinkPreview({
    required this.url, required this.title,
    required this.description, required this.domain,
    this.imageUrl,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Shimmer skeleton widget
// ─────────────────────────────────────────────────────────────────────────────
class _Shimmer extends StatelessWidget {
  final double width, height, radius;
  final bool circle;
  const _Shimmer({this.width = double.infinity, this.height = 14, this.radius = 8, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base   = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final shine  = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);
    return Container(
      width:  circle ? height : width,
      height: height,
      decoration: BoxDecoration(
        color:        base,
        shape:        circle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: circle ? null : BorderRadius.circular(radius),
      ),
    ).animate(onPlay: (c) => c.repeat()).shimmer(duration: 1400.ms, color: shine, angle: 0.3);
  }
}

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

  // Core
  _CType _ctype        = _CType.text;
  _Panel _panel        = _Panel.none;
  int    _themeIndex   = 0;
  double _fontSize     = 22.0;
  String _topic        = '💰 Wealth';
  bool   _loading      = false;
  bool   _uploading    = false;

  // Text background on/off
  bool _useBackground = true;

  // Link
  bool          _linkEnabled  = false;
  _LinkPreview? _linkPreview;
  String?       _linkError;
  bool          _linkChecking = false;
  Timer?        _linkDebounce;

  // In-memory link preview cache
  final Map<String, _LinkPreview?> _linkCache   = {};
  final Map<String, String>        _linkErrCache = {};

  // Media
  XFile?     _mediaFile;
  Uint8List? _mediaBytes;
  String?    _mediaUrl;
  String     _mediaType    = 'image';
  bool       _uploadFailed = false;

  // Video
  VideoPlayerController? _videoCtrl;
  bool                   _videoReady   = false;
  bool                   _videoPlaying = false;
  Duration               _videoDur     = Duration.zero;
  Duration               _videoPos     = Duration.zero;
  RangeValues            _trim         = const RangeValues(0.0, 1.0);

  // Hashtags
  List<String> _hashSugg    = [];
  Timer?       _hashDebounce;

  // Profile
  bool    _profileLoading    = true;
  bool    _profileRefreshing = false;
  String  _userName          = '';
  String? _userAvatar;

  static const int _maxChars = 500;
  int get _charCount => _captionCtrl.text.length;

  bool get _canPost {
    if (_charCount > _maxChars || _loading || _uploading) return false;
    if (_mediaBytes != null && _mediaUrl == null) return false;
    final hasCaption = _captionCtrl.text.trim().isNotEmpty;
    final hasMedia   = _mediaUrl != null;
    final hasLink    = _linkEnabled && _linkPreview != null && _linkError == null;
    return hasCaption || hasMedia || hasLink;
  }

  // ── v7.0: extract background color hex ──────────────────────────────────
  // Returns hex string when: text mode, background toggle ON, no media attached.
  // Returns null for image/video posts (no colored background on those).
  String? get _activeBackgroundColorHex {
    if (_ctype != _CType.text) return null;
    if (!_useBackground) return null;
    return _kThemes[_themeIndex].hexColor;
  }

  // ── Init / dispose ────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _captionCtrl.addListener(_onCaptionChanged);
    _initFromCache();
    _loadProfileFromApi();
  }

  @override
  void dispose() {
    _captionCtrl.removeListener(_onCaptionChanged);
    _captionCtrl.dispose();
    _linkCtrl.dispose();
    _linkDebounce?.cancel();
    _hashDebounce?.cancel();
    _videoCtrl?.dispose();
    super.dispose();
  }

  // ── Cache restore ─────────────────────────────────────────────────────────
  Future<void> _initFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedName   = prefs.getString(_kCacheName);
      final cachedAvatar = prefs.getString(_kCacheAvatar);
      final cachedTopic  = prefs.getString(_kCacheLastTopic);
      if (!mounted) return;
      setState(() {
        if (cachedName   != null && cachedName.isNotEmpty)   _userName   = cachedName;
        if (cachedAvatar != null && cachedAvatar.isNotEmpty) _userAvatar = cachedAvatar;
        if (cachedTopic  != null && cachedTopic.isNotEmpty && _kAllTopics.contains(cachedTopic)) _topic = cachedTopic;
        if (cachedName   != null && cachedName.isNotEmpty)   _profileLoading = false;
      });
    } catch (_) {}
  }

  // ── API refresh ──────────────────────────────────────────────────────────
  Future<void> _loadProfileFromApi() async {
    if (mounted) setState(() => _profileRefreshing = true);
    try {
      final data    = await api.getProfile();
      if (!mounted)  return;
      final profile = data['profile'] as Map? ?? data;
      final name    = profile['full_name']?.toString() ?? profile['name']?.toString() ?? '';
      final avatar  = profile['avatar_url']?.toString();
      final prefs   = await SharedPreferences.getInstance();
      if (name.isNotEmpty)  await prefs.setString(_kCacheName,   name);
      if (avatar != null)   await prefs.setString(_kCacheAvatar, avatar);
      if (!mounted) return;
      setState(() {
        _userName          = name.isNotEmpty ? name : (_userName.isNotEmpty ? _userName : 'You');
        _userAvatar        = avatar ?? _userAvatar;
        _profileLoading    = false;
        _profileRefreshing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (_userName.isEmpty) _userName = 'You';
        _profileLoading    = false;
        _profileRefreshing = false;
      });
    }
  }

  Future<void> _saveTopic(String topic) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCacheLastTopic, topic);
    } catch (_) {}
  }

  // ── Caption / hashtags ────────────────────────────────────────────────────
  void _onCaptionChanged() {
    setState(() {});
    _hashDebounce?.cancel();
    _hashDebounce = Timer(const Duration(milliseconds: 700), _computeHashSugg);
  }

  void _computeHashSugg() {
    final text   = _captionCtrl.text;
    final cursor = _captionCtrl.selection.baseOffset;
    if (cursor < 0 || cursor > text.length) {
      if (mounted) setState(() => _hashSugg = []);
      return;
    }
    final before = text.substring(0, cursor);
    final match  = RegExp(r'#(\w{2,})$').firstMatch(before);
    if (match == null) {
      if (mounted) setState(() => _hashSugg = []);
      return;
    }
    final word = match.group(1)!.toLowerCase();
    final next = cursor < text.length ? text[cursor] : ' ';
    final done = next == ' ' || next == '\n' || cursor == text.length;
    final list = _kHashtagBank
        .where((h) => done ? (h.startsWith(word) || h.contains(word)) && h != word : h.startsWith(word) && h != word)
        .take(done ? 6 : 5)
        .toList();
    if (mounted) setState(() => _hashSugg = list);
  }

  void _applyHashSugg(String tag) {
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
    setState(() => _hashSugg = []);
  }

  // ── Media ─────────────────────────────────────────────────────────────────
  Future<void> _pickMedia({required bool isVideo}) async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      final file   = isVideo
          ? await picker.pickVideo(source: ImageSource.gallery)
          : await picker.pickImage(source: ImageSource.gallery, maxWidth: 1920, imageQuality: 88);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      setState(() {
        _mediaFile    = file;
        _mediaBytes   = bytes;
        _mediaType    = isVideo ? 'video' : 'image';
        _mediaUrl     = null;
        _uploadFailed = false;
        _trim         = const RangeValues(0.0, 1.0);
      });
      if (isVideo) _initVideo(file, bytes);
      _uploadMedia(file, bytes: bytes, isVideo: isVideo);
    } catch (_) {
      _showErr('Could not load file. Try again.');
    }
  }

  void _clearMedia() {
    _videoCtrl?.dispose();
    setState(() {
      _mediaFile = _mediaBytes = _mediaUrl = null;
      _videoCtrl = null;
      _videoReady = _videoPlaying = false;
      _trim = const RangeValues(0.0, 1.0);
      _uploading = false;
      _uploadFailed = false;
      if (_panel == _Panel.trim) _panel = _Panel.none;
    });
  }

  // ── Video ─────────────────────────────────────────────────────────────────
  Future<void> _initVideo(XFile xfile, Uint8List bytes) async {
    await _videoCtrl?.dispose();
    setState(() { _videoReady = false; _videoPlaying = false; });
    VideoPlayerController ctrl;
    if (kIsWeb) {
      ctrl = VideoPlayerController.networkUrl(Uri.dataFromBytes(bytes, mimeType: 'video/mp4'));
    } else {
      if (xfile.path.isNotEmpty) {
        // ignore: deprecated_member_use
        ctrl = VideoPlayerController.contentUri(Uri.file(xfile.path));
      } else {
        ctrl = VideoPlayerController.networkUrl(Uri.dataFromBytes(bytes, mimeType: 'video/mp4'));
      }
    }
    try {
      await ctrl.initialize();
    } catch (_) { ctrl.dispose(); return; }
    if (!mounted) { ctrl.dispose(); return; }
    ctrl.setLooping(false);
    ctrl.addListener(_onVideoTick);
    setState(() { _videoCtrl = ctrl; _videoReady = true; _videoDur = ctrl.value.duration; _videoPos = Duration.zero; _videoPlaying = false; });
  }

  void _onVideoTick() {
    if (!mounted || _videoCtrl == null) return;
    final pos = _videoCtrl!.value.position;
    if (pos != _videoPos) {
      setState(() => _videoPos = pos);
      if (_videoDur.inMilliseconds > 0) {
        final endMs = (_trim.end * _videoDur.inMilliseconds).round();
        if (pos.inMilliseconds >= endMs) {
          _videoCtrl!.pause();
          _videoCtrl!.seekTo(Duration(milliseconds: (_trim.start * _videoDur.inMilliseconds).round()));
          setState(() => _videoPlaying = false);
        }
      }
    }
  }

  void _togglePlay() {
    if (!_videoReady || _videoCtrl == null) return;
    if (_videoPlaying) {
      _videoCtrl!.pause();
    } else {
      final startMs = (_trim.start * _videoDur.inMilliseconds).round();
      final endMs   = (_trim.end   * _videoDur.inMilliseconds).round();
      if (_videoPos.inMilliseconds < startMs || _videoPos.inMilliseconds >= endMs) {
        _videoCtrl!.seekTo(Duration(milliseconds: startMs));
      }
      _videoCtrl!.play();
    }
    setState(() => _videoPlaying = !_videoPlaying);
  }

  String _mimeFromExt(String ext, {required bool isVideo}) {
    const img = {'jpg':'image/jpeg','jpeg':'image/jpeg','png':'image/png','webp':'image/webp','gif':'image/gif','heic':'image/heic'};
    const vid = {'mp4':'video/mp4','mov':'video/quicktime','avi':'video/x-msvideo','mkv':'video/x-matroska','webm':'video/webm'};
    return (isVideo ? vid : img)[ext.toLowerCase()] ?? (isVideo ? 'video/mp4' : 'image/jpeg');
  }

  Future<void> _uploadMedia(XFile file, {required Uint8List bytes, required bool isVideo}) async {
    if (mounted) setState(() { _uploading = true; _uploadFailed = false; });
    try {
      final ext = file.name.contains('.') ? file.name.split('.').last : '';
      final res = (!kIsWeb && file.path.isNotEmpty)
          ? await api.uploadPostMedia(file.path)
          : await api.uploadPostMediaBytes(bytes: bytes, filename: file.name.isNotEmpty ? file.name : 'media.${isVideo ? 'mp4' : 'jpg'}', mimeType: _mimeFromExt(ext, isVideo: isVideo));
      final url = res['url']?.toString();
      if (url == null || url.isEmpty) throw Exception('No URL returned from upload');
      if (mounted) setState(() { _mediaUrl = url; _mediaType = isVideo ? 'video' : (res['media_type']?.toString() ?? 'image'); _uploading = false; _uploadFailed = false; });
    } catch (e) {
      if (mounted) {
        setState(() { _uploading = false; _uploadFailed = true; _mediaUrl = null; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Upload failed. Tap Retry to try again.'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 8),
          action: SnackBarAction(label: 'Retry', textColor: Colors.white, onPressed: () {
            if (_mediaFile != null && _mediaBytes != null) {
              _uploadMedia(_mediaFile!, bytes: _mediaBytes!, isVideo: _mediaType == 'video');
            }
          }),
        ));
      }
    }
  }

  // ── Link ──────────────────────────────────────────────────────────────────
  void _toggleLink() {
    HapticFeedback.selectionClick();
    setState(() {
      _linkEnabled = !_linkEnabled;
      _panel = _linkEnabled ? _Panel.link : _Panel.none;
      if (!_linkEnabled) { _linkCtrl.clear(); _linkPreview = null; _linkError = null; }
    });
  }

  void _onLinkChanged(String v) {
    _linkDebounce?.cancel();
    setState(() { _linkPreview = null; _linkError = null; });
    if (v.trim().isEmpty) return;
    final normalised = v.trim().startsWith('http') ? v.trim() : 'https://${v.trim()}';
    if (_linkCache.containsKey(normalised)) {
      setState(() { _linkPreview = _linkCache[normalised]; _linkError = _linkErrCache[normalised]; });
      return;
    }
    _linkDebounce = Timer(const Duration(milliseconds: 800), () => _validateLink(v.trim()));
  }

  Future<void> _validateLink(String raw) async {
    final url = raw.startsWith('http') ? raw : 'https://$raw';
    Uri? uri;
    try { uri = Uri.parse(url); } catch (_) {}
    if (uri == null || !uri.hasAuthority) {
      final err = 'Invalid URL format.';
      _linkErrCache[url] = err;
      if (mounted) setState(() => _linkError = err);
      return;
    }
    if (_isDomainBlocked(url)) {
      final err = '🚫 Domain blocked by RiseUp safety filters.';
      _linkErrCache[url] = err;
      if (mounted) setState(() => _linkError = err);
      return;
    }
    if (_hasScamContent(url)) {
      final err = '⚠️ Link appears to promote a scam.';
      _linkErrCache[url] = err;
      if (mounted) setState(() => _linkError = err);
      return;
    }
    setState(() => _linkChecking = true);
    try {
      final data = await api.getLinkPreview(url);
      if (!mounted) return;
      if (data['blocked'] == true) {
        final err = data['reason']?.toString() ?? '🚫 Blocked by RiseUp safety filters.';
        _linkErrCache[url] = err; _linkCache[url] = null;
        setState(() { _linkChecking = false; _linkError = err; });
        return;
      }
      final preview = _LinkPreview(url: url, title: data['title']?.toString() ?? uri!.host, description: data['description']?.toString() ?? '', domain: uri!.host, imageUrl: data['image']?.toString());
      _linkCache[url] = preview;
      setState(() { _linkChecking = false; _linkPreview = preview; });
    } catch (_) {
      final preview = _LinkPreview(url: url, title: uri!.host, description: '', domain: uri.host);
      _linkCache[url] = preview;
      if (mounted) setState(() { _linkChecking = false; _linkPreview = preview; });
    }
  }

  // ── Post ──────────────────────────────────────────────────────────────────
  Future<void> _post() async {
    if (!_canPost) return;
    final content = _captionCtrl.text.trim();
    if (_hasScamContent(content)) { _showErr('⚠️ Post violates community guidelines.'); return; }
    setState(() => _loading = true);
    try {
      // v7.0: Extract background color hex for colored text posts
      final String? bgColorHex = _activeBackgroundColorHex;

      final postResult = await api.createPost(
        content:         content.isNotEmpty ? content : (_linkPreview != null ? '🔗 ${_linkPreview!.title}' : '📷 Post'),
        tag:             _topic,
        mediaUrl:        _mediaUrl,
        mediaType:       _mediaUrl != null ? _mediaType : null,
        linkUrl:         _linkEnabled ? _linkPreview?.url : null,
        linkTitle:       _linkEnabled ? _linkPreview?.title : null,
        backgroundColor: bgColorHex,   // v7.0: pass color to API
      );

      // Brain signal
      final postId = (postResult as Map?)?['post']?['id']?.toString() ?? '';
      if (postId.isNotEmpty && content.isNotEmpty) {
        api.recordPostSignal(postId: postId, content: content, tag: _topic);
      }

      if (mounted) {
        // v7.0: Heavy haptic + device default notification sound
        HapticFeedback.heavyImpact();
        notificationService.showLocalNotification(
          id:    1001,
          title: '🚀 Post shared!',
          body:  'Your post is now live in the community',
        );

        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_mediaUrl != null ? 'Post submitted for review! 🔍' : 'Post shared! 🚀'),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: _mediaUrl != null ? 4 : 2),
        ));
        context.go('/home');
      }
    } catch (_) {
      if (mounted) { setState(() => _loading = false); _showErr('Failed to post. Try again.'); }
    }
  }

  void _showErr(String msg) => ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.error, duration: const Duration(seconds: 3)));

  void _togglePanel(_Panel p) {
    HapticFeedback.selectionClick();
    setState(() => _panel = _panel == p ? _Panel.none : p);
  }

  void _setType(_CType t) {
    HapticFeedback.selectionClick();
    setState(() {
      _ctype = t;
      if (_panel == _Panel.font && t != _CType.text)  _panel = _Panel.none;
      if (_panel == _Panel.trim && t != _CType.video) _panel = _Panel.none;
    });
    if (t == _CType.image) _pickMedia(isVideo: false);
    if (t == _CType.video) _pickMedia(isVideo: true);
  }

  void _openTopicPicker() {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (_) => _TopicSheet(selected: _topic, onSelect: (t) {
        setState(() => _topic = t);
        _saveTopic(t);
        Navigator.pop(context);
      }),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF0A0A0A) : Colors.white;
    final barClr  = isDark ? const Color(0xFF111111) : Colors.white;
    final surf    = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
    final border  = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA);
    final txtClr  = isDark ? Colors.white            : Colors.black87;
    final subClr  = isDark ? Colors.white54          : Colors.black45;
    final lblClr  = isDark ? Colors.white24          : Colors.black26;

    return Scaffold(
      backgroundColor:          bgColor,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(barClr, border, txtClr),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(children: [
              Expanded(child: _buildPreview(isDark)),
              AnimatedSize(
                duration: const Duration(milliseconds: 240),
                curve:    Curves.easeOutCubic,
                child:    _panel == _Panel.none ? const SizedBox.shrink()
                    : _buildPanel(isDark, surf, border, txtClr, subClr),
              ),
              _buildCaptionBar(isDark, surf, border, txtClr, subClr, lblClr),
            ]),
          ),
          _buildToolbar(barClr, border, subClr),
        ],
      ),
    );
  }

  // ── AppBar ────────────────────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar(Color bar, Color border, Color txt) {
    return AppBar(
      backgroundColor:  bar, elevation: 0, surfaceTintColor: Colors.transparent,
      leading: IconButton(icon: Icon(Icons.close_rounded, color: txt), onPressed: () => context.go('/home')),
      title: Text('New Post', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: txt)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14, top: 10, bottom: 10),
          child: GestureDetector(
            onTap: _canPost ? _post : null,
            child: AnimatedContainer(
              duration:   const Duration(milliseconds: 200),
              padding:    const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              decoration: BoxDecoration(
                gradient: _canPost ? const LinearGradient(colors: [AppColors.primary, AppColors.accent]) : null,
                color:        _canPost ? null : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(20),
              ),
              child: _loading
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Post', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14)),
            ),
          ),
        ),
      ],
      bottom: PreferredSize(preferredSize: const Size.fromHeight(1), child: Divider(height: 1, color: border)),
    );
  }

  // ── Preview ───────────────────────────────────────────────────────────────
  Widget _buildPreview(bool isDark) {
    final theme   = _kThemes[_themeIndex];
    final caption = _captionCtrl.text;
    final showBg  = _ctype == _CType.text && _useBackground;

    return GestureDetector(
      onTap: (_ctype == _CType.image || _ctype == _CType.video) ? () => _pickMedia(isVideo: _ctype == _CType.video) : null,
      child: Stack(fit: StackFit.expand, children: [
        // Background
        if (_ctype == _CType.image && _mediaBytes != null)
          Image.memory(_mediaBytes!, fit: BoxFit.cover)
        else if (_ctype == _CType.video && _videoReady && _videoCtrl != null)
          FittedBox(fit: BoxFit.cover, child: SizedBox(width: _videoCtrl!.value.size.width, height: _videoCtrl!.value.size.height, child: VideoPlayer(_videoCtrl!)))
        else if (showBg)
          Container(decoration: theme.decoration)
        else
          Container(color: isDark ? const Color(0xFF0A0A0A) : Colors.white),

        // Text overlay
        if (_ctype == _CType.text)
          Center(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
              child: Text(
                caption.isEmpty ? 'Start typing below…' : caption,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize:   _fontSize,
                  color:      showBg ? theme.textColor : (isDark ? Colors.white : Colors.black87),
                  fontWeight: FontWeight.w600,
                  height:     1.45,
                  shadows: showBg ? [Shadow(blurRadius: 12, color: theme.textDark ? Colors.white38 : Colors.black26)] : null,
                ),
              ),
            ),
          ),

        // v7.0: Active background color indicator chip
        if (_ctype == _CType.text && _useBackground)
          Positioned(
            bottom: 12, right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                    color: theme.colors.first,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white38),
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  theme.hexColor,
                  style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),

        // Link preview card
        if (_linkEnabled && _linkPreview != null && _linkError == null)
          Positioned(
            left: 16, right: 16, bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(children: [
                const Icon(Icons.link_rounded, color: Colors.white70, size: 14),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(_linkPreview!.domain, style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    const SizedBox(height: 2),
                    Text(_linkPreview!.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.verified_rounded, color: AppColors.success, size: 14),
              ]),
            ),
          ),

        // Link preview shimmer
        if (_linkEnabled && _linkChecking && _linkPreview == null)
          Positioned(
            left: 16, right: 16, bottom: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.45), borderRadius: BorderRadius.circular(14)),
              child: Row(children: [
                const _Shimmer(width: 14, height: 14, circle: true),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: const [_Shimmer(width: 60, height: 8), SizedBox(height: 6), _Shimmer(height: 10)])),
              ]),
            ),
          ),

        // Video controls
        if (_ctype == _CType.video && _videoReady)
          GestureDetector(
            onTap: _togglePlay,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _videoPlaying ? 0.0 : 1.0,
              child: Container(color: Colors.black26, child: Center(child: Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                child: Icon(_videoPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 34),
              ))),
            ),
          ),

        // Video loading
        if (_ctype == _CType.video && _mediaBytes != null && !_videoReady)
          Container(color: Colors.black38, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [CircularProgressIndicator(color: Colors.white, strokeWidth: 2), SizedBox(height: 12), Text('Loading video…', style: TextStyle(color: Colors.white70, fontSize: 13))]))),

        // Media placeholder
        if ((_ctype == _CType.image || _ctype == _CType.video) && _mediaBytes == null)
          Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), shape: BoxShape.circle), child: Icon(_ctype == _CType.video ? Icons.video_call_rounded : Icons.add_photo_alternate_rounded, color: Colors.grey, size: 30)),
            const SizedBox(height: 12),
            Text(_ctype == _CType.video ? 'Tap to add video' : 'Tap to add photo', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          ])),

        // Upload badges
        if (_uploading)
          Positioned(bottom: 12, left: 12, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), SizedBox(width: 8), Text('Uploading…', style: TextStyle(color: Colors.white, fontSize: 11))]),
          )),

        if (_uploadFailed && !_uploading)
          Positioned(bottom: 12, left: 12, child: GestureDetector(
            onTap: () { if (_mediaFile != null && _mediaBytes != null) _uploadMedia(_mediaFile!, bytes: _mediaBytes!, isVideo: _mediaType == 'video'); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: AppColors.error.withOpacity(0.9), borderRadius: BorderRadius.circular(16)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.refresh_rounded, color: Colors.white, size: 13), SizedBox(width: 5), Text('Upload failed — tap to retry', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))]),
            ),
          )),

        if (_mediaUrl != null && !_uploading && !_uploadFailed)
          Positioned(bottom: 12, left: 12, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(color: AppColors.success.withOpacity(0.9), borderRadius: BorderRadius.circular(16)),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_rounded, color: Colors.white, size: 12), SizedBox(width: 4), Text('Uploaded', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))]),
          )),

        // Remove media
        if (_mediaBytes != null)
          Positioned(top: 10, left: 10, child: GestureDetector(
            onTap: _clearMedia,
            child: Container(width: 28, height: 28, decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle), child: const Icon(Icons.close_rounded, color: Colors.white, size: 15)),
          )),

        // Video time badge
        if (_ctype == _CType.video && _videoReady)
          Positioned(top: 10, right: 10, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
            child: Text(_fmtDur(_videoPos), style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          )),

        // Topic chip
        Positioned(top: 10, left: 0, right: 0, child: Center(child: GestureDetector(
          onTap: _openTopicPicker,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(color: Colors.black.withOpacity(0.40), borderRadius: BorderRadius.circular(14)),
            child: Text(_topic, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ))),
      ]),
    );
  }

  // ── Sliding panel ─────────────────────────────────────────────────────────
  Widget _buildPanel(bool isDark, Color surf, Color border, Color txt, Color sub) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: surf, border: Border(top: BorderSide(color: border), bottom: BorderSide(color: border))),
      child: AnimatedSwitcher(
        duration:      const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        child: KeyedSubtree(
          key: ValueKey(_panel),
          child: switch (_panel) {
            _Panel.theme => _panelTheme(sub),
            _Panel.font  => _panelFont(sub),
            _Panel.trim  => _panelTrim(sub),
            _Panel.link  => _panelLink(isDark, txt, sub, border),
            _Panel.none  => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _panelTheme(Color sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('GRADIENTS', style: TextStyle(fontSize: 9, color: sub, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        SizedBox(height: 38, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: 12, itemBuilder: (_, i) => _themeCircle(i))),
        const SizedBox(height: 8),
        Text('SOLID COLOURS', style: TextStyle(fontSize: 9, color: sub, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        const SizedBox(height: 6),
        SizedBox(height: 38, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: 12, itemBuilder: (_, i) => _themeCircle(12 + i))),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _themeCircle(int i) {
    final t   = _kThemes[i];
    final sel = i == _themeIndex;
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); setState(() => _themeIndex = i); },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 32, height: 32, margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          shape:    BoxShape.circle,
          color:    t.isGradient ? null : t.colors.first,
          gradient: t.isGradient ? LinearGradient(colors: t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight) : null,
          border:   Border.all(color: sel ? Colors.white : Colors.transparent, width: 2.5),
          boxShadow: sel ? [BoxShadow(color: t.colors.first.withOpacity(0.55), blurRadius: 8, spreadRadius: 1)] : [],
        ),
        child: sel ? const Center(child: Icon(Icons.check_rounded, color: Colors.white, size: 14)) : null,
      ),
    );
  }

  Widget _panelFont(Color sub) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Row(children: [
        Text('Aa', style: TextStyle(fontSize: 13, color: sub, fontWeight: FontWeight.w600)),
        Expanded(child: SliderTheme(
          data: SliderThemeData(activeTrackColor: AppColors.primary, inactiveTrackColor: AppColors.primary.withOpacity(0.2), thumbColor: AppColors.primary, overlayColor: AppColors.primary.withOpacity(0.12), trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10)),
          child: Slider(value: _fontSize, min: 14, max: 40, divisions: 26, onChanged: (v) => setState(() => _fontSize = v)),
        )),
        Text('${_fontSize.round()}px', style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _panelTrim(Color sub) {
    if (!_videoReady) return const SizedBox.shrink();
    final startS = _trim.start * _videoDur.inSeconds;
    final endS   = _trim.end   * _videoDur.inSeconds;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 2),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.content_cut_rounded, color: AppColors.primary, size: 13),
          const SizedBox(width: 6),
          Text('${_fmtS(startS)} → ${_fmtS(endS)}', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('Clip: ${_fmtS(endS - startS)}', style: TextStyle(fontSize: 11, color: sub)),
        ]),
        SliderTheme(
          data: SliderThemeData(activeTrackColor: AppColors.primary, inactiveTrackColor: AppColors.primary.withOpacity(0.2), thumbColor: AppColors.primary, overlayColor: AppColors.primary.withOpacity(0.1), rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 10), trackHeight: 4),
          child: RangeSlider(
            values: _trim, min: 0.0, max: 1.0, divisions: 200,
            onChanged: (v) {
              final minF = _videoDur.inSeconds > 0 ? 3.0 / _videoDur.inSeconds : 0.0;
              if ((v.end - v.start) < minF) return;
              setState(() => _trim = v);
              _videoCtrl?.seekTo(Duration(milliseconds: (v.start * _videoDur.inMilliseconds).round()));
            },
          ),
        ),
        Row(children: [
          Text(_fmtS(0), style: TextStyle(fontSize: 9, color: sub)),
          const Spacer(),
          Text(_fmtS(_videoDur.inSeconds.toDouble()), style: TextStyle(fontSize: 9, color: sub)),
        ]),
        const SizedBox(height: 4),
      ]),
    );
  }

  Widget _panelLink(bool isDark, Color txt, Color sub, Color border) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Icon(Icons.add_link_rounded, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Text('Add link to this post', style: TextStyle(fontSize: 12, color: txt, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('Works with text, photo & video', style: TextStyle(fontSize: 10, color: sub)),
        ]),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(color: isDark ? const Color(0xFF2C2C2E) : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: _linkError != null ? AppColors.error.withOpacity(0.6) : border)),
          child: Row(children: [
            Padding(padding: const EdgeInsets.only(left: 12), child: Icon(Icons.link_rounded, color: _linkError != null ? AppColors.error : AppColors.primary, size: 17)),
            Expanded(child: TextField(
              controller: _linkCtrl, keyboardType: TextInputType.url,
              style: TextStyle(fontSize: 13, color: txt),
              onChanged: _onLinkChanged,
              decoration: InputDecoration(hintText: 'Paste URL (https://…)', hintStyle: TextStyle(color: sub, fontSize: 12), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11)),
            )),
            if (_linkChecking)
              const Padding(padding: EdgeInsets.only(right: 10), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
            else if (_linkCtrl.text.isNotEmpty)
              GestureDetector(onTap: () => setState(() { _linkCtrl.clear(); _linkPreview = null; _linkError = null; }), child: Padding(padding: const EdgeInsets.only(right: 10), child: Icon(Icons.close_rounded, color: sub, size: 15))),
          ]),
        ),
        if (_linkError != null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [const Icon(Icons.block_rounded, color: AppColors.error, size: 12), const SizedBox(width: 6), Flexible(child: Text(_linkError!, style: const TextStyle(color: AppColors.error, fontSize: 11)))])),
        if (_linkPreview != null && _linkError == null)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(children: [
            const Icon(Icons.verified_rounded, color: AppColors.success, size: 13),
            const SizedBox(width: 6),
            Flexible(child: Text('${_linkPreview!.domain} · ${_linkPreview!.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: sub, fontWeight: FontWeight.w500))),
          ])),
      ]),
    );
  }

  // ── Caption bar ───────────────────────────────────────────────────────────
  Widget _buildCaptionBar(bool isDark, Color surf, Color border, Color txt, Color sub, Color lbl) {
    final overLimit = _charCount > _maxChars;
    return Container(
      decoration: BoxDecoration(color: surf, border: Border(top: BorderSide(color: border, width: 0.5))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_hashSugg.isNotEmpty)
          SizedBox(height: 38, child: ListView.separated(
            scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            itemCount: _hashSugg.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, i) {
              final tag = _hashSugg[i];
              return GestureDetector(
                onTap: () => _applyHashSugg(tag),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.primary.withOpacity(0.22))),
                  child: Text('#$tag', style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ),
              );
            },
          )),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _buildAvatar(),
            const SizedBox(width: 10),
            Expanded(child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 96),
              child: TextField(
                controller: _captionCtrl, maxLines: null,
                style: TextStyle(fontSize: 14, color: txt, height: 1.5),
                decoration: InputDecoration(
                  hintText:  _ctype == _CType.text ? 'Write your post… use #hashtags' : 'Add a caption… use #hashtags',
                  hintStyle: TextStyle(color: sub, fontSize: 13),
                  border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  isDense: true, contentPadding: EdgeInsets.zero,
                ),
              ),
            )),
            const SizedBox(width: 8),
            Text('${_maxChars - _charCount}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: overLimit ? AppColors.error : (_maxChars - _charCount) < 50 ? AppColors.warning : lbl)),
          ]),
        ),
        if (_mediaBytes != null)
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 6), child: Row(children: const [Icon(Icons.shield_outlined, color: Colors.orange, size: 11), SizedBox(width: 6), Expanded(child: Text('Media is reviewed before publishing.', style: TextStyle(fontSize: 10, color: Colors.orange)))])),
        SizedBox(height: MediaQuery.of(context).padding.bottom),
      ]),
    );
  }

  Widget _buildAvatar() {
    if (_profileLoading && _userName.isEmpty) return const _Shimmer(height: 36, circle: true);
    final initial = _userName.isNotEmpty ? _userName[0].toUpperCase() : 'U';
    return Stack(clipBehavior: Clip.none, children: [
      CircleAvatar(
        radius: 18, backgroundColor: AppColors.primary.withOpacity(0.15),
        child:       _userAvatar != null ? null : Text(initial, style: const TextStyle(fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.w700)),
        backgroundImage: _userAvatar != null ? NetworkImage(_userAvatar!) : null,
        onBackgroundImageError: _userAvatar != null ? (_, __) {} : null,
      ),
      if (_profileRefreshing && _userAvatar != null)
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 1.5))).animate(onPlay: (c) => c.repeat(reverse: true)).fadeIn(duration: 700.ms).fadeOut(begin: 1.0, duration: 700.ms)),
    ]);
  }

  // ── Right toolbar ─────────────────────────────────────────────────────────
  Widget _buildToolbar(Color bar, Color border, Color sub) {
    return Container(
      width: 62,
      decoration: BoxDecoration(color: bar, border: Border(left: BorderSide(color: border, width: 0.5))),
      child: SafeArea(left: false, right: false, bottom: false, child: Column(children: [
        const SizedBox(height: 10),
        _toolBtn(icon: Iconsax.text, label: 'Text', active: _ctype == _CType.text, onTap: () { if (_ctype != _CType.text) _setType(_CType.text); }, sub: sub),
        _toolBtn(icon: Iconsax.image, label: 'Photo', active: _ctype == _CType.image, onTap: () => _setType(_CType.image), sub: sub),
        _toolBtn(icon: Iconsax.video, label: 'Video', active: _ctype == _CType.video, onTap: () => _setType(_CType.video), sub: sub),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Divider(color: border, height: 1)),
        _toolBtn(icon: Icons.palette_outlined, label: 'Theme', active: _panel == _Panel.theme, onTap: () => _togglePanel(_Panel.theme), sub: sub),
        if (_ctype == _CType.text)
          _toolBtnToggle(icon: Icons.format_color_fill_rounded, label: 'BG', enabled: _useBackground, sub: sub, onTap: () { HapticFeedback.selectionClick(); setState(() => _useBackground = !_useBackground); }),
        if (_ctype == _CType.text)
          _toolBtn(icon: Icons.text_fields_rounded, label: 'Font', active: _panel == _Panel.font, onTap: () => _togglePanel(_Panel.font), sub: sub),
        _toolBtnToggle(icon: Icons.add_link_rounded, label: 'Link', enabled: _linkEnabled, sub: sub, onTap: _toggleLink),
        _toolBtn(icon: Iconsax.hashtag, label: 'Topic', active: false, onTap: _openTopicPicker, sub: sub),
        if (_ctype == _CType.video && _videoReady)
          _toolBtn(icon: Icons.content_cut_rounded, label: 'Trim', active: _panel == _Panel.trim, onTap: () => _togglePanel(_Panel.trim), sub: sub),
        const Spacer(),
        GestureDetector(
          onTap: () { HapticFeedback.mediumImpact(); _post(); },
          child: Container(
            margin: const EdgeInsets.fromLTRB(6, 0, 6, 14),
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [AppColors.primary, AppColors.accent], begin: Alignment.topCenter, end: Alignment.bottomCenter), borderRadius: BorderRadius.circular(14)),
            child: _loading
                ? const Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                : const Center(child: Text('POST', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.8))),
          ),
        ),
      ])),
    );
  }

  Widget _toolBtn({required IconData icon, required String label, required bool active, required VoidCallback onTap, required Color sub}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180), width: 54, margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: active ? AppColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: active ? AppColors.primary : sub),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9, color: active ? AppColors.primary : sub, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }

  Widget _toolBtnToggle({required IconData icon, required String label, required bool enabled, required VoidCallback onTap, required Color sub}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180), width: 54, margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4), padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(color: enabled ? AppColors.primary.withOpacity(0.12) : Colors.transparent, borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, size: 20, color: enabled ? AppColors.primary : sub),
            if (enabled) Positioned(top: -2, right: -4, child: Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle))),
          ]),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(fontSize: 9, color: enabled ? AppColors.primary : sub, fontWeight: enabled ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _fmtDur(Duration d) => '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  String _fmtS(double s) => '${(s / 60).floor().toString().padLeft(2, '0')}:${(s % 60).floor().toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────────────────────
// Topic picker bottom-sheet (unchanged from v6)
// ─────────────────────────────────────────────────────────────────────────────
class _TopicSheet extends StatefulWidget {
  final String selected;
  final ValueChanged<String> onSelect;
  const _TopicSheet({required this.selected, required this.onSelect});
  @override
  State<_TopicSheet> createState() => _TopicSheetState();
}

class _TopicSheetState extends State<_TopicSheet> {
  final _ctrl = TextEditingController();
  List<String> _filtered = _kAllTopics;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() {
      final q = _ctrl.text.toLowerCase().trim();
      setState(() => _filtered = q.isEmpty ? _kAllTopics : _kAllTopics.where((t) => t.toLowerCase().contains(q)).toList());
    });
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? AppColors.bgCard    : Colors.white;
    final surf   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final txt    = isDark ? Colors.white        : Colors.black87;
    final sub    = isDark ? Colors.white54      : Colors.black45;

    return DraggableScrollableSheet(
      initialChildSize: 0.72, minChildSize: 0.4, maxChildSize: 0.92, expand: false,
      builder: (_, sc) => Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 16), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: Row(children: [
            Text('Choose Topic', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: txt)),
            const Spacer(),
            Text('${_kAllTopics.length} topics', style: TextStyle(fontSize: 12, color: sub)),
          ])),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Container(
            decoration: BoxDecoration(color: surf, borderRadius: BorderRadius.circular(14), border: Border.all(color: border)),
            child: Row(children: [
              const Padding(padding: EdgeInsets.only(left: 12), child: Icon(Icons.search_rounded, color: AppColors.primary, size: 20)),
              Expanded(child: TextField(
                controller: _ctrl, style: TextStyle(fontSize: 14, color: txt),
                decoration: InputDecoration(hintText: 'Search topics…', hintStyle: TextStyle(color: sub, fontSize: 13), border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13)),
              )),
              if (_ctrl.text.isNotEmpty)
                IconButton(icon: const Icon(Icons.close_rounded, size: 18), color: sub, onPressed: () => _ctrl.clear()),
            ]),
          )),
          const SizedBox(height: 10),
          Expanded(child: _filtered.isEmpty
              ? Center(child: Text('No topics found', style: TextStyle(color: sub, fontSize: 14)))
              : ListView.builder(
                  controller: sc, padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final t   = _filtered[i];
                    final sel = t == widget.selected;
                    return GestureDetector(
                      onTap: () => widget.onSelect(t),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                        decoration: BoxDecoration(
                          color: sel ? AppColors.primary.withOpacity(0.1) : surf,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: sel ? AppColors.primary.withOpacity(0.4) : Colors.transparent),
                        ),
                        child: Row(children: [
                          Expanded(child: Text(t, style: TextStyle(fontSize: 14, fontWeight: sel ? FontWeight.w600 : FontWeight.w400, color: sel ? AppColors.primary : txt))),
                          if (sel) const Icon(Icons.check_circle_rounded, color: AppColors.primary, size: 18),
                        ]),
                      ),
                    );
                  }),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
        ]),
      ),
    );
  }
}
