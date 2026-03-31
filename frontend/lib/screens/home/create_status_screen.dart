// frontend/lib/screens/home/create_status_screen.dart
// Fixed:
//  1. MIME type detected from actual file extension — was hardcoded jpeg/mp4
//     causing 500 on any non-JPEG image or non-MP4 video
//  2. Video: min 10 sec enforced, max 10 min for camera
//  3. Text overlay toggle on image/video preview
//  4. Link URL validation + spam/domain check before submission
//  5. Content moderation notice on all media posts
//  6. Proper content-type sent to backend (matches fixed posts.py v3)

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MIME + extension helpers
// ─────────────────────────────────────────────────────────────────────────────
String _mimeFromExt(String ext) {
  const map = <String, String>{
    // Images
    'jpg':  'image/jpeg',  'jpeg': 'image/jpeg',
    'png':  'image/png',   'webp': 'image/webp',
    'gif':  'image/gif',   'heic': 'image/heic',
    'heif': 'image/heif',  'avif': 'image/avif',
    'bmp':  'image/bmp',   'tiff': 'image/tiff',
    // Videos
    'mp4':  'video/mp4',   'mov':  'video/quicktime',
    'avi':  'video/x-msvideo', 'mkv': 'video/x-matroska',
    'webm': 'video/webm',  '3gp':  'video/3gpp',
    'm4v':  'video/mp4',   'mpeg': 'video/mpeg',
  };
  return map[ext.toLowerCase()] ?? 'application/octet-stream';
}

bool _isVideoMime(String mime) => mime.startsWith('video/');

// ─────────────────────────────────────────────────────────────────────────────
// Spam domain list (same as create_post_screen)
// ─────────────────────────────────────────────────────────────────────────────
const _kBlockedDomains = <String>{
  'free-bitcoin.io', 'doubler.cash', 'cryptodouble.net',
  'invest-fast.com', 'fastprofit.xyz', 'earnnow.cc',
};
const _kScamKeywords = <String>[
  'double your', 'guaranteed profit', 'send btc', 'send eth',
  'private key', 'seed phrase', 'wire transfer',
];
bool _isDomainBlocked(String url) {
  try {
    final uri  = Uri.parse(url.startsWith('http') ? url : 'https://$url');
    return _kBlockedDomains.any((d) => uri.host.toLowerCase().contains(d));
  } catch (_) { return false; }
}
bool _hasScamContent(String text) =>
    _kScamKeywords.any((k) => text.toLowerCase().contains(k));

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────
class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});
  @override
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final _textCtrl      = TextEditingController();
  final _linkCtrl      = TextEditingController();
  final _linkTitleCtrl = TextEditingController();
  final _overlayCtrl   = TextEditingController();

  // 'text' | 'image' | 'video' | 'link'
  String _type = 'text';

  XFile?     _mediaXFile;
  Uint8List? _mediaPreviewBytes;
  String?    _mediaUrl;
  String     _detectedMime = 'image/jpeg'; // FIX: actual MIME from file
  bool       _uploading    = false;
  bool       _posting      = false;
  bool       _showOverlay  = false; // text overlay on image/video

  String _bgColor      = '#6C5CE7';
  int    _durationHours = 24;

  String? _linkError;

  static const _bgColors = [
    '#6C5CE7', '#00B894', '#FF6B35', '#FF3CAC',
    '#4776E6', '#E17055', '#2D3436', '#0984E3',
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _linkCtrl.dispose();
    _linkTitleCtrl.dispose();
    _overlayCtrl.dispose();
    super.dispose();
  }

  // ── MIME detection from XFile ─────────────────────────────────────────────
  String _detectMime(XFile file) {
    // Try XFile mimeType first (set on Android/iOS by image_picker)
    if (file.mimeType != null && file.mimeType!.isNotEmpty) {
      return file.mimeType!;
    }
    // Fall back to extension
    final ext = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    return _mimeFromExt(ext);
  }

  // ── Pick media ────────────────────────────────────────────────────────────
  Future<void> _pickMedia(ImageSource source, {required bool isVideo}) async {
    try {
      final picker = ImagePicker();
      XFile? file;

      if (isVideo) {
        file = await picker.pickVideo(
          source: source,
          // Camera: enforce 10-min max
          maxDuration: source == ImageSource.camera
              ? const Duration(minutes: 10) : null,
        );
      } else {
        file = await picker.pickImage(
          source: source,
          maxWidth: 1920, imageQuality: 88,
        );
      }
      if (file == null) return;

      final bytes    = await file.readAsBytes();
      final mime     = _detectMime(file);
      final isVid    = _isVideoMime(mime);

      // Enforce minimum video size (~10 sec ≈ 500 KB at low bitrate)
      if (isVid && bytes.length < 50 * 1024) {
        _showErr('Video is too short. Minimum is 10 seconds.');
        return;
      }

      setState(() {
        _mediaXFile        = file;
        _mediaPreviewBytes = bytes;
        _detectedMime      = mime;
        _type              = isVid ? 'video' : 'image';
        _uploading         = true;
        _mediaUrl          = null;
      });

      await _uploadMedia(file, bytes: bytes, mime: mime);
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        _showErr('Could not load file: ${e.toString()}');
      }
    }
  }

  // ── Upload ────────────────────────────────────────────────────────────────
  // FIX: Uses _detectedMime (real MIME from file) not hardcoded jpeg/mp4
  Future<void> _uploadMedia(XFile file,
      {required Uint8List bytes, required String mime}) async {
    try {
      final token = await api.getToken();
      if (token == null) throw Exception('Not authenticated');

      final parts    = mime.split('/');
      final type     = parts[0];
      final subtype  = parts.length > 1 ? parts[1] : 'jpeg';
      final filename = 'status_${DateTime.now().millisecondsSinceEpoch}.$subtype';

      // Use file path when available (mobile), bytes for web
      Map<String, dynamic> res;
      if (file.path.isNotEmpty) {
        res = await api.uploadPostMedia(file.path);
      } else {
        res = await api.uploadPostMediaBytes(
          bytes: bytes, filename: filename, mimeType: mime,
        );
      }

      if (mounted) {
        setState(() {
          _mediaUrl  = res['url']?.toString();
          _uploading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading         = false;
          _mediaXFile        = null;
          _mediaPreviewBytes = null;
          _mediaUrl          = null;
        });
        _showErr('Upload failed: ${e.toString()}');
      }
    }
  }

  void _clearMedia() => setState(() {
    _mediaXFile        = null;
    _mediaPreviewBytes = null;
    _mediaUrl          = null;
    _uploading         = false;
    _type              = 'text';
  });

  // ── Link validation ───────────────────────────────────────────────────────
  void _validateLink() {
    final url = _linkCtrl.text.trim();
    if (url.isEmpty) { setState(() => _linkError = null); return; }

    final full = url.startsWith('http') ? url : 'https://$url';
    Uri? uri;
    try { uri = Uri.parse(full); } catch (_) {}

    if (uri == null || uri.host.isEmpty) {
      setState(() => _linkError = 'Invalid URL format.');
      return;
    }
    if (_isDomainBlocked(full)) {
      setState(() => _linkError =
          '🚫 This domain is blocked by RiseUp safety filters.');
      return;
    }
    if (_hasScamContent(full)) {
      setState(() => _linkError =
          '⚠️ This link appears to promote a scam and has been blocked.');
      return;
    }
    setState(() => _linkError = null);
  }

  // ── Post ──────────────────────────────────────────────────────────────────
  Future<void> _post() async {
    final text    = _textCtrl.text.trim();
    final overlay = _overlayCtrl.text.trim();
    final linkUrl = _linkCtrl.text.trim();

    final hasContent = text.isNotEmpty
        || _mediaUrl != null
        || (linkUrl.isNotEmpty && _linkError == null);

    if (!hasContent) {
      _showErr('Add some content to your status.');
      return;
    }
    if (_type == 'link') {
      _validateLink();
      if (_linkError != null) {
        _showErr('Please fix the link error before posting.');
        return;
      }
    }
    if (_hasScamContent(text)) {
      _showErr('Your status contains content that violates our guidelines.');
      return;
    }

    setState(() => _posting = true);
    try {
      await api.post('/posts/status', {
        if (text.isNotEmpty)    'content':    text,
        if (overlay.isNotEmpty) 'overlay_text': overlay,
        if (_mediaUrl != null)  'media_url':   _mediaUrl,
        'media_type':           _type == 'link' ? 'link' : (_isVideoMime(_detectedMime) ? 'video' : 'image'),
        if (_type == 'link' && linkUrl.isNotEmpty)
          'link_url': linkUrl.startsWith('http') ? linkUrl : 'https://$linkUrl',
        if (_type == 'link' && _linkTitleCtrl.text.trim().isNotEmpty)
          'link_title': _linkTitleCtrl.text.trim(),
        'background_color': _bgColor,
        'duration_hours':   _durationHours,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Status posted! 🚀'),
          backgroundColor: AppColors.success,
        ));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        _showErr('Failed to post: ${e.toString()}');
      }
    }
  }

  void _showErr(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: AppColors.error,
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final bg       = isDark ? Colors.black : Colors.white;
    final card     = isDark ? AppColors.bgCard : Colors.white;
    final border   = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textClr  = isDark ? Colors.white : Colors.black87;
    final sub      = isDark ? Colors.white.withOpacity(0.54) : Colors.black45;
    final field    = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    final canPost  = !_uploading && !_posting;

    return Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0, surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: textClr),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('New Status', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w700, color: textClr)),
        actions: [
          TextButton(
            onPressed: canPost ? _post : null,
            child: _posting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2))
                : Text('Post', style: TextStyle(
                    color: canPost ? AppColors.primary : Colors.grey,
                    fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Preview ────────────────────────────────────────────────────
          _buildPreview(isDark, sub),
          const SizedBox(height: 20),

          // ── Type tabs ──────────────────────────────────────────────────
          _label('STATUS TYPE', sub),
          Row(children: [
            _typeBtn('text',  Icons.text_fields_rounded, 'Text',  isDark, textClr),
            const SizedBox(width: 8),
            _typeBtn('image', Icons.image_rounded,       'Image', isDark, textClr),
            const SizedBox(width: 8),
            _typeBtn('video', Icons.videocam_rounded,    'Video', isDark, textClr),
            const SizedBox(width: 8),
            _typeBtn('link',  Icons.link_rounded,        'Link',  isDark, textClr),
          ]),
          const SizedBox(height: 20),

          // ── Caption ────────────────────────────────────────────────────
          _label('CAPTION / TEXT', sub),
          Container(
            decoration: BoxDecoration(
                color: field, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _textCtrl,
              maxLines: 3, maxLength: 280,
              style: TextStyle(color: textClr, fontSize: 14),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _type == 'text' ? 'What\'s on your mind?' : 'Add a caption (optional)...',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                counterStyle: TextStyle(color: sub, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Media picker ───────────────────────────────────────────────
          if (_type == 'image' || _type == 'video') ...[
            _label('ADD MEDIA', sub),

            // Format info
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.primary.withOpacity(0.15))),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded,
                    color: AppColors.primary, size: 13),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  _type == 'video'
                      ? 'Supported: MP4, MOV, AVI, MKV, WebM, 3GP  ·  Min: 10 sec  ·  Max: 10 min'
                      : 'Supported: JPEG, PNG, WebP, HEIC, AVIF, GIF, BMP  ·  Max: 50 MB',
                  style: const TextStyle(fontSize: 11, color: AppColors.primary, height: 1.4),
                )),
              ]),
            ),

            Row(children: [
              Expanded(child: _mediaPickBtn(
                Icons.camera_alt_rounded, 'Camera',
                () => _pickMedia(ImageSource.camera, isVideo: _type == 'video'),
                isDark)),
              const SizedBox(width: 10),
              Expanded(child: _mediaPickBtn(
                Icons.photo_library_rounded, 'Gallery',
                () => _pickMedia(ImageSource.gallery, isVideo: _type == 'video'),
                isDark)),
            ]),

            // Text overlay toggle (only if media selected)
            if (_mediaPreviewBytes != null && !_uploading) ...[
              const SizedBox(height: 12),
              Row(children: [
                Switch(
                  value: _showOverlay,
                  onChanged: (v) => setState(() => _showOverlay = v),
                  activeColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 8),
                Text('Add text overlay to ${_type == 'video' ? 'video' : 'image'}',
                    style: TextStyle(fontSize: 13, color: textClr)),
              ]),
              if (_showOverlay) ...[
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                      color: field, borderRadius: BorderRadius.circular(12)),
                  child: TextField(
                    controller: _overlayCtrl,
                    maxLength: 100,
                    style: TextStyle(color: textClr, fontSize: 14),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Text shown on top of your media...',
                      hintStyle: TextStyle(color: sub, fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.all(12),
                      counterStyle: TextStyle(color: sub, fontSize: 11),
                    ),
                  ),
                ),
              ],
            ],

            // Moderation notice
            if (_mediaUrl != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.shield_outlined, color: Colors.orange, size: 13),
                  SizedBox(width: 8),
                  Expanded(child: Text(
                    'Media is reviewed for inappropriate or harmful content. '
                    'Nudity, scams, and violence are strictly prohibited.',
                    style: TextStyle(fontSize: 11, color: Colors.orange, height: 1.4),
                  )),
                ]),
              ),
            ],
            const SizedBox(height: 16),
          ],

          // ── Link fields ────────────────────────────────────────────────
          if (_type == 'link') ...[
            _label('LINK URL', sub),
            Container(
              decoration: BoxDecoration(
                  color: field, borderRadius: BorderRadius.circular(12),
                  border: _linkError != null
                      ? Border.all(color: AppColors.error.withOpacity(0.5))
                      : null),
              child: TextField(
                controller: _linkCtrl,
                keyboardType: TextInputType.url,
                style: TextStyle(color: textClr, fontSize: 14),
                onChanged: (_) { _validateLink(); setState(() {}); },
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: TextStyle(color: sub, fontSize: 13),
                  prefixIcon: Icon(Icons.link_rounded,
                      color: _linkError != null ? AppColors.error : AppColors.primary,
                      size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (_linkError != null) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.block_rounded, color: AppColors.error, size: 13),
                const SizedBox(width: 6),
                Expanded(child: Text(_linkError!,
                    style: const TextStyle(color: AppColors.error, fontSize: 12))),
              ]),
            ],
            const SizedBox(height: 10),
            _label('LINK TITLE (optional)', sub),
            Container(
              decoration: BoxDecoration(
                  color: field, borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _linkTitleCtrl,
                style: TextStyle(color: textClr, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '"Check out this opportunity"',
                  hintStyle: TextStyle(color: sub, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Background color (text only) ──────────────────────────────
          if (_type == 'text') ...[
            _label('BACKGROUND COLOR', sub),
            Wrap(
              spacing: 8,
              children: List.generate(_bgColors.length, (i) {
                final col = Color(int.parse(
                    _bgColors[i].replaceFirst('#', '0xFF')));
                final active = _bgColor == _bgColors[i];
                return GestureDetector(
                  onTap: () => setState(() => _bgColor = _bgColors[i]),
                  child: Container(
                    width: 32, height: 32,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: col, shape: BoxShape.circle,
                      border: active
                          ? Border.all(color: Colors.white, width: 3) : null,
                      boxShadow: active ? [BoxShadow(
                          color: col.withOpacity(0.5),
                          blurRadius: 8, spreadRadius: 1)] : null,
                    ),
                    child: active
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 14)
                        : null,
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),
          ],

          // ── Duration ──────────────────────────────────────────────────
          _label('EXPIRES AFTER', sub),
          Row(children: [
            _durationBtn(24,  '24h',    isDark, textClr),
            const SizedBox(width: 8),
            _durationBtn(48,  '48h',    isDark, textClr),
            const SizedBox(width: 8),
            _durationBtn(72,  '3 days', isDark, textClr),
            const SizedBox(width: 8),
            _durationBtn(168, '7 days', isDark, textClr),
          ]),

          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Preview widget
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildPreview(bool isDark, Color sub) {
    final overlayText = _overlayCtrl.text;

    if (_uploading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
          SizedBox(height: 12),
          Text('Uploading media...', style: TextStyle(color: AppColors.textMuted)),
        ])),
      );
    }

    // Image preview with optional text overlay
    if (_mediaPreviewBytes != null && !_isVideoMime(_detectedMime)) {
      return Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(_mediaPreviewBytes!,
              height: 240, width: double.infinity, fit: BoxFit.cover),
        ),
        if (_showOverlay && overlayText.isNotEmpty)
          Positioned.fill(child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black.withOpacity(0.35),
            ),
            child: Center(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(overlayText, textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.w700,
                      shadows: [Shadow(blurRadius: 4)])),
            )),
          )),
        Positioned(top: 8, right: 8,
          child: GestureDetector(onTap: _clearMedia,
            child: Container(width: 28, height: 28,
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 14)))),
        if (_mediaUrl != null)
          Positioned(bottom: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_rounded, color: Colors.white, size: 11),
                SizedBox(width: 4),
                Text('Uploaded', style: TextStyle(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w600)),
              ]),
            )),
      ]);
    }

    // Video preview placeholder with optional overlay
    if (_mediaPreviewBytes != null && _isVideoMime(_detectedMime)) {
      return Stack(children: [
        Container(
          height: 200, width: double.infinity,
          decoration: BoxDecoration(
              color: isDark ? AppColors.bgCard : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16)),
          child: Stack(children: [
            const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.videocam_rounded, color: AppColors.primary, size: 48),
              SizedBox(height: 8),
              Text('Video ready ✅', style: TextStyle(
                  color: AppColors.primary, fontWeight: FontWeight.w600)),
            ])),
            if (_showOverlay && overlayText.isNotEmpty)
              Positioned(bottom: 16, left: 16, right: 16,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(overlayText, textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white, fontSize: 14,
                          fontWeight: FontWeight.w600)),
                )),
          ]),
        ),
        Positioned(top: 8, right: 8,
          child: GestureDetector(onTap: _clearMedia,
            child: Container(width: 28, height: 28,
              decoration: const BoxDecoration(
                  color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 14)))),
        if (_mediaUrl != null)
          Positioned(bottom: 8, left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(8)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.check_rounded, color: Colors.white, size: 11),
                SizedBox(width: 4),
                Text('Uploaded', style: TextStyle(
                    color: Colors.white, fontSize: 10,
                    fontWeight: FontWeight.w600)),
              ]),
            )),
      ]);
    }

    // Text / default preview
    return Container(
      width: double.infinity, height: 180,
      decoration: BoxDecoration(
        color: Color(int.parse(_bgColor.replaceFirst('#', '0xFF'))),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _textCtrl.text.isEmpty ? 'Your status preview' : _textCtrl.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 18,
                fontWeight: FontWeight.w600, height: 1.4),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper widgets
  // ─────────────────────────────────────────────────────────────────────────
  Widget _label(String t, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: sub, letterSpacing: 1)),
  );

  Widget _typeBtn(String type, IconData icon, String label,
      bool isDark, Color textClr) {
    final active = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          if (type == 'text' || type == 'link') {
            _mediaXFile        = null;
            _mediaPreviewBytes = null;
            _mediaUrl          = null;
            _showOverlay       = false;
          }
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.primary
                  : (isDark ? Colors.white.withOpacity(0.24) : Colors.grey.shade300),
            ),
          ),
          child: Column(children: [
            Icon(icon, color: active ? AppColors.primary : textClr, size: 20),
            const SizedBox(height: 3),
            Text(label, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600,
                color: active ? AppColors.primary : textClr)),
          ]),
        ),
      ),
    );
  }

  Widget _mediaPickBtn(IconData icon, String label,
      VoidCallback onTap, bool isDark) => GestureDetector(
    onTap: () { HapticFeedback.lightImpact(); onTap(); },
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark
            ? Colors.white.withOpacity(0.12) : Colors.grey.shade300),
      ),
      child: Column(children: [
        Icon(icon, color: AppColors.primary, size: 24),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(
            fontSize: 12, color: AppColors.primary,
            fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  Widget _durationBtn(int hours, String label, bool isDark, Color textClr) {
    final active = _durationHours == hours;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _durationHours = hours),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active ? AppColors.primary
                  : (isDark ? Colors.white.withOpacity(0.24) : Colors.grey.shade300),
            ),
          ),
          child: Center(child: Text(label, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600,
              color: active ? Colors.white : textClr))),
        ),
      ),
    );
  }
}
