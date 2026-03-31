// frontend/lib/screens/create/create_post_screen.dart
// Full rewrite:
//  1. Image/video upload → real API call → mediaUrl attached to post
//  2. Hashtag auto-detection from text + manual add chips
//  3. Link input with URL validation, spam/scam check, link preview card
//  4. Content moderation notice for all media posts
//  5. Media preview with remove button
//  6. 500-char limit with char counter
//
// FIX v2:
//  • User header now loads real profile (avatar_url + full_name) from
//    /progress/profile on initState instead of showing hardcoded 👤 / "You"
//  • Avatar renders as NetworkImage when url starts with http, falls back
//    to gradient + initial letter when no avatar is set
//  • Profile load is non-blocking — screen appears instantly, avatar fades in

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
// Spam / scam domain list — enforced client-side before submission
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
    if (_kBlockedDomains.any((d) => host.contains(d))) return true;
    return false;
  } catch (_) {
    return false;
  }
}

bool _hasScamContent(String text) =>
    _kScamKeywords.any((k) => text.toLowerCase().contains(k));

// ─────────────────────────────────────────────────────────────────────────────
// Link Preview Model
// ─────────────────────────────────────────────────────────────────────────────
class _LinkPreview {
  final String url, title, description, domain;
  final String? imageUrl, favicon;
  final bool isBlocked;
  final String? blockReason;

  const _LinkPreview({
    required this.url,
    required this.title,
    required this.description,
    required this.domain,
    this.imageUrl,
    this.favicon,
    this.isBlocked = false,
    this.blockReason,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Post Screen
// ─────────────────────────────────────────────────────────────────────────────
class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});
  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen>
    with SingleTickerProviderStateMixin {
  final _contentCtrl  = TextEditingController();
  final _hashtagCtrl  = TextEditingController();
  final _linkCtrl     = TextEditingController();
  final _linkFocus    = FocusNode();
  final _scrollCtrl   = ScrollController();

  String _selectedTag   = '💰 Wealth';
  bool   _loading       = false;
  bool   _uploading     = false;
  bool   _linkChecking  = false;
  bool   _showLinkInput = false;
  int    _charCount     = 0;

  static const int _maxChars = 500;

  // ── Media ─────────────────────────────────────────────────────────────────
  XFile?    _mediaFile;
  Uint8List? _mediaBytes;
  String?   _mediaUrl;
  String    _mediaType = 'image';

  // ── Hashtags ──────────────────────────────────────────────────────────────
  final Set<String> _hashtags = {};

  // ── Link ──────────────────────────────────────────────────────────────────
  _LinkPreview? _linkPreview;
  String?       _linkError;
  Timer?        _linkDebounce;

  // ── FIX: Real user profile ────────────────────────────────────────────────
  // Loaded asynchronously in initState so the screen opens instantly while
  // the avatar fetches in the background.
  String  _userName      = 'You';
  String? _userAvatarUrl; // null = not loaded yet; empty = no avatar set

  static const _tags = [
    '💰 Wealth',     '📈 Investing',    '💼 Business',
    '🧠 Mindset',    '⚡ Hustle',        '🎯 Skills',
    '🏠 Real Estate','💻 Tech',          '📊 Budgeting',
    '🌱 Personal Growth', '💪 Finance', '🚀 Startups',
  ];

  @override
  void initState() {
    super.initState();
    _contentCtrl.addListener(_onTextChanged);
    _loadProfile(); // FIX: load real profile on open
  }

  @override
  void dispose() {
    _contentCtrl.removeListener(_onTextChanged);
    _contentCtrl.dispose();
    _hashtagCtrl.dispose();
    _linkCtrl.dispose();
    _linkFocus.dispose();
    _scrollCtrl.dispose();
    _linkDebounce?.cancel();
    super.dispose();
  }

  // ── FIX: Load real profile (name + avatar) ────────────────────────────────
  Future<void> _loadProfile() async {
    try {
      final data = await api.getProfile();
      if (!mounted) return;
      final profile = data['profile'] as Map? ?? data;
      final name    = profile['full_name']?.toString()
          ?? profile['name']?.toString()
          ?? '';
      final avatar  = profile['avatar_url']?.toString() ?? '';
      setState(() {
        if (name.isNotEmpty) _userName = name;
        _userAvatarUrl = avatar; // empty string = no avatar, show initial
      });
    } catch (_) {
      // Non-fatal: keep defaults ('You', no avatar)
    }
  }

  // ── Text listener: auto-detect hashtags ──────────────────────────────────
  void _onTextChanged() {
    final text = _contentCtrl.text;
    setState(() {
      _charCount = text.length;
      final matches = RegExp(r'#(\w+)').allMatches(text);
      for (final m in matches) {
        final tag = m.group(1)!.toLowerCase();
        if (tag.length > 1) _hashtags.add(tag);
      }
    });
  }

  // ── Add manual hashtag ────────────────────────────────────────────────────
  void _addHashtag(String raw) {
    final tag = raw.trim().replaceAll('#', '').toLowerCase();
    if (tag.length < 2 || tag.length > 30) return;
    setState(() => _hashtags.add(tag));
    _hashtagCtrl.clear();
  }

  void _removeHashtag(String tag) => setState(() => _hashtags.remove(tag));

  // ── Media picker ──────────────────────────────────────────────────────────
  Future<void> _pickMedia(ImageSource source, {required bool isVideo}) async {
    HapticFeedback.lightImpact();
    try {
      final picker = ImagePicker();
      XFile? file;
      if (isVideo) {
        file = await picker.pickVideo(
          source: source,
          maxDuration: source == ImageSource.camera
              ? const Duration(minutes: 10)
              : null,
        );
      } else {
        file = await picker.pickImage(
          source: source,
          maxWidth: 1920,
          imageQuality: 88,
        );
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

  // ── Upload media to backend ───────────────────────────────────────────────
  Future<void> _uploadMedia(XFile file,
      {required Uint8List bytes, required bool isVideo}) async {
    try {
      final name    = file.name.toLowerCase();
      final extRaw  = name.contains('.') ? name.split('.').last : '';
      final mime    = _mimeFromExt(extRaw, isVideo: isVideo);

      Map<String, dynamic> res;
      if (file.path.isNotEmpty) {
        res = await api.uploadPostMedia(file.path);
      } else {
        res = await api.uploadPostMediaBytes(
          bytes: bytes,
          filename: file.name.isNotEmpty
              ? file.name
              : 'media.${isVideo ? 'mp4' : 'jpg'}',
          mimeType: mime,
        );
      }

      if (mounted) {
        setState(() {
          _mediaUrl   = res['url']?.toString();
          _mediaType  = res['media_type']?.toString() ?? (isVideo ? 'video' : 'image');
          _uploading  = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading  = false;
          _mediaFile  = null;
          _mediaBytes = null;
          _mediaUrl   = null;
        });
        _showError('Upload failed. Check your connection and try again.');
      }
    }
  }

  String _mimeFromExt(String ext, {required bool isVideo}) {
    const imgMap = {
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
      'png': 'image/png',  'webp': 'image/webp',
      'gif': 'image/gif',  'heic': 'image/heic',
      'heif': 'image/heif','avif': 'image/avif',
      'bmp': 'image/bmp',  'tiff': 'image/tiff',
    };
    const vidMap = {
      'mp4': 'video/mp4',  'mov': 'video/quicktime',
      'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska',
      'webm': 'video/webm','3gp': 'video/3gpp',
      'm4v': 'video/mp4',  'mpeg': 'video/mpeg',
    };
    final map = isVideo ? vidMap : imgMap;
    return map[ext] ?? (isVideo ? 'video/mp4' : 'image/jpeg');
  }

  void _clearMedia() {
    setState(() {
      _mediaFile  = null;
      _mediaBytes = null;
      _mediaUrl   = null;
      _uploading  = false;
    });
  }

  // ── Link validation ───────────────────────────────────────────────────────
  void _onLinkChanged(String value) {
    _linkDebounce?.cancel();
    setState(() { _linkPreview = null; _linkError = null; });
    if (value.trim().isEmpty) return;

    _linkDebounce = Timer(const Duration(milliseconds: 800), () {
      _validateLink(value.trim());
    });
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
      if (mounted) {
        setState(() => _linkError =
            '🚫 This domain is blocked. RiseUp does not allow spam or scam links.');
      }
      return;
    }

    if (_hasScamContent(url)) {
      if (mounted) {
        setState(() => _linkError =
            '⚠️ This link appears to promote a scam. It has been blocked to protect our community.');
      }
      return;
    }

    if (mounted) setState(() => _linkChecking = true);
    try {
      final data = await api.getLinkPreview(url);
      if (mounted) {
        if (data['blocked'] == true) {
          setState(() {
            _linkChecking = false;
            _linkError    = data['reason']?.toString() ??
                '🚫 This link has been blocked by RiseUp safety filters.';
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
            favicon:     data['favicon']?.toString(),
          );
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _linkChecking = false;
          _linkPreview  = _LinkPreview(
            url:         url,
            title:       uri!.host,
            description: '',
            domain:      uri.host,
          );
        });
      }
    }
  }

  // ── Post ──────────────────────────────────────────────────────────────────
  Future<void> _post() async {
    final content = _contentCtrl.text.trim();
    if (content.isEmpty && _mediaUrl == null && _linkPreview == null) return;
    if (_loading || _uploading) return;

    if (_hasScamContent(content)) {
      _showError('⚠️ Your post appears to contain content that violates '
          'RiseUp community guidelines. Please review and edit.');
      return;
    }

    if (_showLinkInput && _linkError != null) {
      _showError('Please remove the blocked link before posting.');
      return;
    }

    setState(() => _loading = true);

    try {
      final allTags = <String>{};
      allTags.addAll(_hashtags);
      RegExp(r'#(\w+)').allMatches(content).forEach((m) {
        final t = m.group(1)!.toLowerCase();
        if (t.length > 1) allTags.add(t);
      });

      final inlineTagSet = RegExp(r'#(\w+)').allMatches(content)
          .map((m) => m.group(1)!.toLowerCase())
          .toSet();
      final extraTags = allTags.where((t) => !inlineTagSet.contains(t));
      final finalContent = extraTags.isEmpty
          ? content
          : '$content\n\n${extraTags.map((t) => '#$t').join(' ')}';

      final linkUrl = (_showLinkInput && _linkPreview != null)
          ? _linkPreview!.url : null;

      await api.createPost(
        content:   finalContent.isNotEmpty ? finalContent : '🔗 Link post',
        tag:       _selectedTag,
        mediaUrl:  _mediaUrl,
        mediaType: _mediaUrl != null ? _mediaType : null,
        linkUrl:   linkUrl,
        linkTitle: _linkPreview?.title,
      );

      if (mounted) {
        HapticFeedback.mediumImpact();
        final msg = _mediaUrl != null
            ? 'Post submitted for review! 🔍 Media posts are checked to keep the community safe.'
            : 'Post shared! 🚀';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg),
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

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppColors.error,
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final bgColor     = isDark ? Colors.black : Colors.white;
    final cardColor   = isDark ? AppColors.bgCard : Colors.white;
    final surfColor   = isDark ? AppColors.bgSurface : Colors.grey.shade100;
    final borderColor = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textColor   = isDark ? Colors.white : Colors.black87;
    final subColor    = isDark ? Colors.white54 : Colors.black45;

    final remaining   = _maxChars - _charCount;
    final isOverLimit = remaining < 0;
    final hasContent  = (_charCount > 0 || _mediaUrl != null ||
                        (_showLinkInput && _linkPreview != null)) &&
                        !isOverLimit && !_loading && !_uploading;

    return Scaffold(
      backgroundColor: bgColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: textColor),
          onPressed: () => context.go('/home'),
        ),
        title: Text('Create Post', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w700, color: textColor)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16, top: 10, bottom: 10),
            child: GestureDetector(
              onTap: hasContent ? _post : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: hasContent
                      ? const LinearGradient(
                          colors: [AppColors.primary, AppColors.accent])
                      : null,
                  color: hasContent ? null : Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: _loading
                    ? const SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Post', style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 14)),
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: borderColor),
        ),
      ),
      body: Column(children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _scrollCtrl,
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ── FIX: Real user header ──────────────────────────────────────
              // Shows actual avatar from profile.avatar_url (NetworkImage when
              // URL is set, gradient + initial when not). Fades in when loaded.
              Row(children: [
                _buildAvatar(isDark),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _userName,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: textColor),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(_selectedTag, style: const TextStyle(
                        fontSize: 10, color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
                  ),
                ]),
              ]).animate().fadeIn(),

              const SizedBox(height: 16),

              // ── Text input ────────────────────────────────────────────────
              TextField(
                controller: _contentCtrl,
                maxLines: null, minLines: 4,
                style: TextStyle(fontSize: 16, color: textColor, height: 1.6),
                decoration: InputDecoration(
                  hintText:
                      'Share your wealth journey, tips, wins or lessons...\n\n'
                      '💡 What did you learn today?\n'
                      '💰 What income milestone did you hit?\n'
                      '🚀 What strategy worked for you?',
                  hintStyle: TextStyle(color: subColor, fontSize: 14, height: 1.6),
                  border: InputBorder.none,
                ),
              ).animate().fadeIn(delay: 50.ms),

              // ── Media preview ─────────────────────────────────────────────
              if (_uploading)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  height: 160,
                  decoration: BoxDecoration(
                    color: surfColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                      SizedBox(height: 10),
                      Text('Uploading...', style: TextStyle(
                          color: AppColors.textMuted, fontSize: 13)),
                    ]),
                  ),
                )
              else if (_mediaBytes != null) ...[
                Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _mediaType == 'image'
                        ? Image.memory(_mediaBytes!,
                            width: double.infinity, height: 220,
                            fit: BoxFit.cover)
                        : Container(
                            width: double.infinity, height: 200,
                            color: surfColor,
                            child: const Center(child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.videocam_rounded,
                                    color: AppColors.primary, size: 48),
                                SizedBox(height: 8),
                                Text('Video ready ✅',
                                    style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ))),
                  ),
                  Positioned(top: 8, right: 8,
                    child: GestureDetector(
                      onTap: _clearMedia,
                      child: Container(
                        width: 30, height: 30,
                        decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle),
                        child: const Icon(Icons.close_rounded,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  ),
                  if (_mediaUrl != null)
                    Positioned(bottom: 8, left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Row(mainAxisSize: MainAxisSize.min,
                            children: [
                          Icon(Icons.check_rounded,
                              color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text('Uploaded', style: TextStyle(
                              color: Colors.white, fontSize: 11,
                              fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: const Row(children: [
                    Icon(Icons.shield_outlined, color: Colors.orange, size: 14),
                    SizedBox(width: 8),
                    Expanded(child: Text(
                      'Media posts are reviewed to keep the community safe from '
                      'inappropriate or harmful content.',
                      style: TextStyle(fontSize: 11, color: Colors.orange, height: 1.4),
                    )),
                  ]),
                ),
                const SizedBox(height: 12),
              ],

              // ── Link input + preview ──────────────────────────────────────
              if (_showLinkInput) ...[
                Container(
                  decoration: BoxDecoration(
                    color: surfColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _linkError != null
                          ? AppColors.error.withOpacity(0.5)
                          : borderColor,
                    ),
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
                        controller: _linkCtrl,
                        focusNode: _linkFocus,
                        keyboardType: TextInputType.url,
                        style: TextStyle(fontSize: 14, color: textColor),
                        onChanged: _onLinkChanged,
                        decoration: InputDecoration(
                          hintText: 'Paste a link (https://...)',
                          hintStyle: TextStyle(color: subColor, fontSize: 13),
                          border: InputBorder.none,
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
                    else
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18),
                        color: subColor,
                        onPressed: () {
                          setState(() {
                            _showLinkInput = false;
                            _linkCtrl.clear();
                            _linkPreview   = null;
                            _linkError     = null;
                          });
                        },
                      ),
                  ]),
                ),
                if (_linkError != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.block_rounded,
                        color: AppColors.error, size: 13),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_linkError!,
                        style: const TextStyle(
                            color: AppColors.error, fontSize: 12))),
                  ]),
                ],
                if (_linkPreview != null && _linkError == null) ...[
                  const SizedBox(height: 8),
                  _buildLinkPreviewCard(
                      _linkPreview!, isDark, textColor, subColor, surfColor),
                ],
                const SizedBox(height: 12),
              ],

              // ── Hashtag chips ─────────────────────────────────────────────
              if (_hashtags.isNotEmpty) ...[
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _hashtags.map((tag) => Chip(
                    label: Text('#$tag',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                    backgroundColor: AppColors.primary.withOpacity(0.08),
                    side: const BorderSide(
                        color: AppColors.primary, width: 0.5),
                    deleteIcon: const Icon(Icons.close_rounded,
                        size: 14, color: AppColors.primary),
                    onDeleted: () => _removeHashtag(tag),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  )).toList(),
                ),
                const SizedBox(height: 12),
              ],

              const SizedBox(height: 8),

              // ── Add hashtag input ─────────────────────────────────────────
              Container(
                height: 38,
                decoration: BoxDecoration(
                  color: surfColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: borderColor),
                ),
                child: Row(children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 4),
                    child: Text('#', style: TextStyle(
                        fontSize: 15, color: AppColors.primary,
                        fontWeight: FontWeight.w700)),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _hashtagCtrl,
                      style: TextStyle(fontSize: 13, color: textColor),
                      decoration: InputDecoration(
                        hintText: 'Add hashtag...',
                        hintStyle: TextStyle(color: subColor, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onSubmitted: _addHashtag,
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded,
                        color: AppColors.primary, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                        minWidth: 36, minHeight: 36),
                    onPressed: () => _addHashtag(_hashtagCtrl.text),
                  ),
                ]),
              ),

              const SizedBox(height: 20),

              // ── Topic selector ────────────────────────────────────────────
              Text('Topic', style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: subColor)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: _tags.map((tag) {
                  final sel = tag == _selectedTag;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedTag = tag),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? AppColors.primary : surfColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: sel ? AppColors.primary : borderColor),
                      ),
                      child: Text(tag, style: TextStyle(
                          fontSize: 12,
                          color: sel ? Colors.white : subColor,
                          fontWeight: sel
                              ? FontWeight.w600 : FontWeight.w400)),
                    ),
                  );
                }).toList(),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 24),
            ]),
          ),
        ),

        // ── Bottom toolbar ────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: cardColor,
            border: Border(top: BorderSide(color: borderColor)),
          ),
          padding: EdgeInsets.fromLTRB(
              12, 8, 12, MediaQuery.of(context).padding.bottom + 8),
          child: Row(children: [
            _ToolbarBtn(
              icon: Iconsax.image,
              active: _mediaType == 'image' && _mediaBytes != null,
              color: subColor,
              onTap: () => _showMediaPicker(isVideo: false),
            ),
            const SizedBox(width: 8),
            _ToolbarBtn(
              icon: Iconsax.video,
              active: _mediaType == 'video' && _mediaBytes != null,
              color: subColor,
              onTap: () => _showMediaPicker(isVideo: true),
            ),
            const SizedBox(width: 8),
            _ToolbarBtn(
              icon: Icons.link_rounded,
              active: _showLinkInput,
              color: subColor,
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() => _showLinkInput = !_showLinkInput);
                if (_showLinkInput) {
                  Future.delayed(const Duration(milliseconds: 200), () {
                    _linkFocus.requestFocus();
                    _scrollCtrl.animateTo(
                      _scrollCtrl.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  });
                }
              },
            ),
            const SizedBox(width: 8),
            _ToolbarBtn(
              icon: Iconsax.chart_2,
              active: false,
              color: subColor,
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Polls coming soon 🗳️'),
                      duration: Duration(seconds: 1))),
            ),
            const Spacer(),
            Text(
              '${_maxChars - _charCount}',
              style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600,
                color: isOverLimit
                    ? AppColors.error
                    : (_maxChars - _charCount) < 50
                        ? AppColors.warning : subColor,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── FIX: Avatar widget ────────────────────────────────────────────────────
  // Renders real avatar URL as NetworkImage.
  // Falls back to gradient + first letter of name when:
  //   • _userAvatarUrl is null (still loading) → shows shimmer gradient
  //   • _userAvatarUrl is empty (no avatar set) → shows initial
  //   • NetworkImage fails to load (errorBuilder) → shows initial
  Widget _buildAvatar(bool isDark) {
    const size = 44.0;
    final hasUrl = _userAvatarUrl != null && _userAvatarUrl!.startsWith('http');
    final initial = _userName.isNotEmpty
        ? _userName.trim()[0].toUpperCase()
        : 'Y';

    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        gradient: hasUrl
            ? null
            : const LinearGradient(
                colors: [AppColors.primary, AppColors.accent]),
        shape: BoxShape.circle,
      ),
      clipBehavior: Clip.antiAlias,
      child: hasUrl
          ? Image.network(
              _userAvatarUrl!,
              width: size, height: size,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _avatarInitial(initial),
              loadingBuilder: (_, child, progress) {
                if (progress == null) return child;
                return _avatarInitial(initial);
              },
            )
          : _avatarInitial(initial),
    ).animate(
      // Fade in when avatar loads (only when we get a real URL)
      effects: _userAvatarUrl != null
          ? [const FadeEffect(duration: Duration(milliseconds: 300))]
          : [],
    );
  }

  Widget _avatarInitial(String initial) => Center(
    child: Text(
      initial,
      style: const TextStyle(
        fontSize: 20,
        color: Colors.white,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  void _showMediaPicker({required bool isVideo}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.bgCard : Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, margin: const EdgeInsets.only(top: 12, bottom: 8),
              decoration: BoxDecoration(color: Colors.grey.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2))),
          if (isVideo) Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Videos: min 10 seconds · max 10 minutes\n'
                  'Supported: MP4, MOV, AVI, MKV, WebM',
                  style: TextStyle(fontSize: 11, color: AppColors.primary, height: 1.4),
                )),
              ]),
            ),
          ) else Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: const Row(children: [
                Icon(Icons.info_outline_rounded, color: AppColors.primary, size: 14),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'Supported: JPEG, PNG, WebP, HEIC, AVIF, GIF, BMP',
                  style: TextStyle(fontSize: 11, color: AppColors.primary),
                )),
              ]),
            ),
          ),
          ListTile(
            leading: Container(width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.camera_alt_rounded, color: AppColors.primary, size: 20)),
            title: Text(isVideo ? 'Record video' : 'Take photo',
                style: TextStyle(fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87)),
            onTap: () {
              Navigator.pop(context);
              _pickMedia(ImageSource.camera, isVideo: isVideo);
            },
          ),
          ListTile(
            leading: Container(width: 40, height: 40,
                decoration: BoxDecoration(color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.photo_library_rounded, color: AppColors.accent, size: 20)),
            title: Text(isVideo ? 'Choose from gallery' : 'Choose photo',
                style: TextStyle(fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87)),
            onTap: () {
              Navigator.pop(context);
              _pickMedia(ImageSource.gallery, isVideo: isVideo);
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _buildLinkPreviewCard(
    _LinkPreview p, bool isDark, Color textColor, Color subColor, Color surfColor,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: surfColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.15)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.imageUrl != null)
          Image.network(p.imageUrl!, height: 140, width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const SizedBox.shrink()),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
              Flexible(child: Text(p.domain, style: TextStyle(
                  fontSize: 11, color: subColor))),
              const Spacer(),
              const Icon(Icons.verified_rounded,
                  color: AppColors.success, size: 14),
              const SizedBox(width: 4),
              const Text('Link verified', style: TextStyle(
                  fontSize: 10, color: AppColors.success,
                  fontWeight: FontWeight.w600)),
            ]),
            if (p.title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                      color: textColor)),
            ],
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: subColor, height: 1.4)),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ── Toolbar button ────────────────────────────────────────────────────────────
class _ToolbarBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final Color color;
  final VoidCallback onTap;
  const _ToolbarBtn({required this.icon, required this.active,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: active
            ? AppColors.primary.withOpacity(0.12)
            : (Theme.of(context).brightness == Brightness.dark
                ? AppColors.bgSurface : Colors.grey.shade100),
        borderRadius: BorderRadius.circular(10),
        border: active
            ? Border.all(color: AppColors.primary.withOpacity(0.4))
            : null,
      ),
      child: Icon(icon,
          color: active ? AppColors.primary : color, size: 20),
    ),
  );
}
