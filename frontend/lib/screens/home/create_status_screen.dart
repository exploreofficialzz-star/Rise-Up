// frontend/lib/screens/home/create_status_screen.dart
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class CreateStatusScreen extends StatefulWidget {
  const CreateStatusScreen({super.key});

  @override
  State<CreateStatusScreen> createState() =>
      _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final _textCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _linkTitleCtrl = TextEditingController();

  String _type = 'text'; // text | image | video | link

  // FIX: Replaced dart:io File with XFile + Uint8List for
  // full cross-platform support (Android, iOS, Web)
  XFile? _mediaXFile;
  Uint8List? _mediaPreviewBytes;

  String? _mediaUrl;
  String _mediaType = 'image';
  String _bgColor = '#6C5CE7';
  bool _uploading = false;
  bool _posting = false;
  int _durationHours = 24;

  static const _bgColors = [
    '#6C5CE7', '#00B894', '#FF6B35', '#FF3CAC',
    '#4776E6', '#E17055', '#2D3436', '#0984E3',
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _linkCtrl.dispose();
    _linkTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(ImageSource source,
      {bool isVideo = false}) async {
    try {
      final picker = ImagePicker();
      XFile? file;
      if (isVideo) {
        file = await picker.pickVideo(
            source: source,
            maxDuration: const Duration(seconds: 60));
      } else {
        file = await picker.pickImage(
            source: source, maxWidth: 1080, imageQuality: 85);
      }
      if (file == null) return;

      // Read bytes — works on Android, iOS, and Web
      final bytes = await file.readAsBytes();

      setState(() {
        _mediaXFile = file;
        _mediaPreviewBytes = bytes;
        _mediaType = isVideo ? 'video' : 'image';
        _type = isVideo ? 'video' : 'image';
        _uploading = true;
      });

      await _uploadMedia(file, bytes: bytes, isVideo: isVideo);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not pick media: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _uploadMedia(XFile file,
      {required Uint8List bytes, bool isVideo = false}) async {
    try {
      final token = await api.getToken();
      if (token == null) throw Exception('Not authenticated');

      final contentType =
          isVideo ? 'video/mp4' : 'image/jpeg';
      final filename =
          isVideo ? 'status.mp4' : 'status.jpg';

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          bytes,
          filename: filename,
          contentType: DioMediaType(
            isVideo ? 'video' : 'image',
            isVideo ? 'mp4' : 'jpeg',
          ),
        ),
      });

      // FIX: Use kApiBaseUrl from app_constants — no hardcoding
      final dio = Dio();
      final resp = await dio.post(
        '$kApiBaseUrl/posts/status/upload-media',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (s) => s != null && s < 600,
        ),
      );

      if (resp.statusCode == 200) {
        setState(() {
          _mediaUrl = resp.data['url']?.toString();
          _mediaType = resp.data['media_type']?.toString() ??
              (isVideo ? 'video' : 'image');
          _uploading = false;
        });
      } else {
        throw Exception(
            'Upload failed with status ${resp.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploading = false;
          _mediaXFile = null;
          _mediaPreviewBytes = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Upload failed: ${e.toString()}'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _post() async {
    final hasContent =
        _textCtrl.text.trim().isNotEmpty ||
            _mediaUrl != null ||
            (_type == 'link' &&
                _linkCtrl.text.trim().isNotEmpty);

    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add some content to your status'),
            backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _posting = true);
    try {
      await api.post('/posts/status', {
        if (_textCtrl.text.trim().isNotEmpty)
          'content': _textCtrl.text.trim(),
        if (_mediaUrl != null) 'media_url': _mediaUrl,
        'media_type':
            _type == 'link' ? 'link' : _mediaType,
        if (_type == 'link' &&
            _linkCtrl.text.trim().isNotEmpty)
          'link_url': _linkCtrl.text.trim(),
        if (_type == 'link' &&
            _linkTitleCtrl.text.trim().isNotEmpty)
          'link_title': _linkTitleCtrl.text.trim(),
        'background_color': _bgColor,
        'duration_hours': _durationHours,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Status posted! 🚀'),
              backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed: ${e.toString()}'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final border =
        isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final textClr = isDark ? Colors.white : Colors.black87;
    final sub = isDark
        ? Colors.white.withOpacity(0.54)
        : Colors.black45;
    final field = isDark
        ? AppColors.bgSurface
        : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: textClr),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'New Status',
          style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: textClr),
        ),
        actions: [
          TextButton(
            onPressed: (_uploading || _posting) ? null : _post,
            child: _posting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2))
                : const Text(
                    'Post',
                    style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Preview ──────────────────────────────
            _buildPreview(isDark, sub),
            const SizedBox(height: 20),

            // ── Type selector ────────────────────────
            _label('STATUS TYPE', sub),
            Row(children: [
              _typeBtn('text', Icons.text_fields_rounded,
                  'Text', isDark, textClr),
              const SizedBox(width: 8),
              _typeBtn('image', Icons.image_rounded, 'Image',
                  isDark, textClr),
              const SizedBox(width: 8),
              _typeBtn('video', Icons.videocam_rounded,
                  'Video', isDark, textClr),
              const SizedBox(width: 8),
              _typeBtn('link', Icons.link_rounded, 'Link',
                  isDark, textClr),
            ]),
            const SizedBox(height: 20),

            // ── Caption ─────────────────────────────
            _label('CAPTION / TEXT', sub),
            Container(
              decoration: BoxDecoration(
                  color: field,
                  borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _textCtrl,
                maxLines: 3,
                maxLength: 280,
                style: TextStyle(color: textClr, fontSize: 14),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: _type == 'text'
                      ? 'What\'s on your mind?'
                      : 'Add a caption (optional)...',
                  hintStyle:
                      TextStyle(color: sub, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                  counterStyle:
                      TextStyle(color: sub, fontSize: 11),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Media picker ─────────────────────────
            if (_type == 'image' || _type == 'video') ...[
              _label('ADD MEDIA', sub),
              Row(children: [
                Expanded(
                  child: _mediaBtn(
                    Icons.camera_alt_rounded,
                    'Camera',
                    () => _pickMedia(ImageSource.camera,
                        isVideo: _type == 'video'),
                    isDark,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _mediaBtn(
                    Icons.photo_library_rounded,
                    'Gallery',
                    () => _pickMedia(ImageSource.gallery,
                        isVideo: _type == 'video'),
                    isDark,
                  ),
                ),
              ]),
              const SizedBox(height: 16),
            ],

            // ── Link fields ──────────────────────────
            if (_type == 'link') ...[
              _label('LINK URL', sub),
              Container(
                decoration: BoxDecoration(
                    color: field,
                    borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: _linkCtrl,
                  keyboardType: TextInputType.url,
                  style: TextStyle(color: textClr, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'https://...',
                    hintStyle:
                        TextStyle(color: sub, fontSize: 13),
                    prefixIcon: const Icon(Icons.link_rounded,
                        color: AppColors.primary, size: 20),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _label('LINK TITLE (optional)', sub),
              Container(
                decoration: BoxDecoration(
                    color: field,
                    borderRadius: BorderRadius.circular(12)),
                child: TextField(
                  controller: _linkTitleCtrl,
                  style: TextStyle(color: textClr, fontSize: 14),
                  decoration: InputDecoration(
                    hintText:
                        'e.g. "Check out this opportunity"',
                    hintStyle:
                        TextStyle(color: sub, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(14),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Background color ─────────────────────
            if (_type == 'text') ...[
              _label('BACKGROUND COLOR', sub),
              Wrap(
                spacing: 8,
                children: List.generate(
                  _bgColors.length,
                  (i) => GestureDetector(
                    onTap: () =>
                        setState(() => _bgColor = _bgColors[i]),
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Color(int.parse(
                            _bgColors[i]
                                .replaceFirst('#', '0xFF'))),
                        shape: BoxShape.circle,
                        border: _bgColor == _bgColors[i]
                            ? Border.all(
                                color: Colors.white, width: 3)
                            : null,
                        boxShadow: _bgColor == _bgColors[i]
                            ? [
                                BoxShadow(
                                  color: Color(int.parse(
                                          _bgColors[i]
                                              .replaceFirst(
                                                  '#', '0xFF')))
                                      .withOpacity(0.5),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                )
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Duration ────────────────────────────
            _label('EXPIRES AFTER', sub),
            Row(children: [
              _durationBtn(24, '24h', isDark, textClr),
              const SizedBox(width: 8),
              _durationBtn(48, '48h', isDark, textClr),
              const SizedBox(width: 8),
              _durationBtn(72, '3 days', isDark, textClr),
              const SizedBox(width: 8),
              _durationBtn(168, '7 days', isDark, textClr),
            ]),

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(bool isDark, Color sub) {
    // Uploading spinner
    if (_uploading) {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color:
              isDark ? AppColors.bgCard : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                  color: AppColors.primary),
              SizedBox(height: 12),
              Text('Uploading media...',
                  style: TextStyle(
                      color: AppColors.textMuted)),
            ],
          ),
        ),
      );
    }

    // Image preview — uses Image.memory for cross-platform
    if (_mediaPreviewBytes != null && _mediaType == 'image') {
      return ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Image.memory(
          _mediaPreviewBytes!,
          height: 240,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    // Video selected (no preview frame — show placeholder)
    if (_mediaPreviewBytes != null && _mediaType == 'video') {
      return Container(
        height: 180,
        decoration: BoxDecoration(
          color:
              isDark ? AppColors.bgCard : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.video_file_rounded,
                  color: AppColors.primary, size: 48),
              SizedBox(height: 8),
              Text('Video ready to post',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    // Text/default preview
    return Container(
      width: double.infinity,
      height: 180,
      decoration: BoxDecoration(
        color: Color(
            int.parse(_bgColor.replaceFirst('#', '0xFF'))),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            _textCtrl.text.isEmpty
                ? 'Your status preview'
                : _textCtrl.text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String t, Color sub) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: sub,
              letterSpacing: 1),
        ),
      );

  Widget _typeBtn(String type, IconData icon, String label,
      bool isDark, Color textClr) {
    final active = _type == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _type = type;
          _mediaXFile = null;
          _mediaPreviewBytes = null;
          _mediaUrl = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primary.withOpacity(0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? AppColors.primary
                  : (isDark
                      ? Colors.white.withOpacity(0.24)
                      : Colors.grey.shade300),
            ),
          ),
          child: Column(children: [
            Icon(icon,
                color:
                    active ? AppColors.primary : textClr,
                size: 20),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color:
                        active ? AppColors.primary : textClr,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }

  Widget _mediaBtn(
          IconData icon, String label, VoidCallback onTap,
          bool isDark) =>
      GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: isDark
                ? AppColors.bgSurface
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isDark
                  ? Colors.white.withOpacity(0.12)
                  : Colors.grey.shade300,
            ),
          ),
          child: Column(children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );

  Widget _durationBtn(
      int hours, String label, bool isDark, Color textClr) {
    final active = _durationHours == hours;
    return Expanded(
      child: GestureDetector(
        onTap: () =>
            setState(() => _durationHours = hours),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: active
                  ? AppColors.primary
                  : (isDark
                      ? Colors.white.withOpacity(0.24)
                      : Colors.grey.shade300),
            ),
          ),
          child: Center(
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color:
                        active ? Colors.white : textClr)),
          ),
        ),
      ),
    );
  }
}
