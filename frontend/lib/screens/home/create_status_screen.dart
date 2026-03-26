import 'dart:io';
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
  State<CreateStatusScreen> createState() => _CreateStatusScreenState();
}

class _CreateStatusScreenState extends State<CreateStatusScreen> {
  final _textCtrl = TextEditingController();
  final _linkCtrl = TextEditingController();
  final _linkTitleCtrl = TextEditingController();

  String _type = 'text';   // text | image | video | link
  File?  _mediaFile;
  String? _mediaUrl;
  String  _mediaType = 'image';
  String  _bgColor   = '#6C5CE7';
  bool    _uploading  = false;
  bool    _posting    = false;
  int     _durationHours = 24;

  static const _bgColors = [
    '#6C5CE7', '#00B894', '#FF6B35', '#FF3CAC',
    '#4776E6', '#E17055', '#2D3436', '#0984E3',
  ];

  static const _bgNames = [
    'Purple', 'Green', 'Orange', 'Pink',
    'Blue', 'Coral', 'Dark', 'Sky',
  ];

  @override
  void dispose() {
    _textCtrl.dispose();
    _linkCtrl.dispose();
    _linkTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickMedia(ImageSource source, {bool isVideo = false}) async {
    final picker = ImagePicker();
    XFile? file;
    if (isVideo) {
      file = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 60));
    } else {
      file = await picker.pickImage(source: source, maxWidth: 1080, imageQuality: 85);
    }
    if (file == null) return;

    setState(() {
      _mediaFile = File(file!.path);
      _mediaType = isVideo ? 'video' : 'image';
      _type      = isVideo ? 'video' : 'image';
      _uploading = true;
    });

    await _uploadMedia(File(file.path), isVideo: isVideo);
  }

  Future<void> _uploadMedia(File file, {bool isVideo = false}) async {
    try {
      final token = await api.getToken();
      if (token == null) throw Exception('Not authenticated');

      final ct = isVideo ? 'video/mp4' : 'image/jpeg';
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: isVideo ? 'status.mp4' : 'status.jpg',
          contentType: DioMediaType(isVideo ? 'video' : 'image',
              isVideo ? 'mp4' : 'jpeg'),
        ),
      });

      final baseUrl = const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'https://riseup-api.onrender.com/api/v1');

      final dio   = Dio();
      final resp  = await dio.post(
        '$baseUrl/posts/status/upload-media',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $token'},
            validateStatus: (s) => s != null && s < 600),
      );

      if (resp.statusCode == 200) {
        setState(() {
          _mediaUrl  = resp.data['url'];
          _mediaType = resp.data['media_type'] ?? (isVideo ? 'video' : 'image');
          _uploading = false;
        });
      } else {
        throw Exception('Upload failed: ${resp.statusCode}');
      }
    } catch (e) {
      setState(() { _uploading = false; _mediaFile = null; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _post() async {
    final hasContent = _textCtrl.text.trim().isNotEmpty
        || _mediaUrl != null
        || (_type == 'link' && _linkCtrl.text.trim().isNotEmpty);

    if (!hasContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add some content to your status'),
            backgroundColor: AppColors.error));
      return;
    }

    setState(() => _posting = true);
    try {
      await api.post('/posts/status', {
        'content':          _textCtrl.text.trim().isEmpty ? null : _textCtrl.text.trim(),
        'media_url':        _mediaUrl,
        'media_type':       _type == 'link' ? 'link' : _mediaType,
        'link_url':         _type == 'link' ? _linkCtrl.text.trim() : null,
        'link_title':       _type == 'link' ? _linkTitleCtrl.text.trim() : null,
        'background_color': _bgColor,
        'duration_hours':   _durationHours,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Status posted!'),
              backgroundColor: AppColors.success));
        if (context.canPop()) context.pop(); else context.go('/home');
      }
    } catch (e) {
      setState(() => _posting = false);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = isDark ? Colors.black : Colors.white;
    final card   = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text   = isDark ? Colors.white : Colors.black87;
    final sub    = isDark ? Colors.white54 : Colors.black45;
    final field  = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
            icon: Icon(Icons.close_rounded, color: text),
            onPressed: () => context.canPop() ? context.pop() : context.go('/home')),
        title: Text('New Status',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        actions: [
          TextButton(
            onPressed: (_uploading || _posting) ? null : _post,
            child: _posting
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : const Text('Post', style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 15)),
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // ── Preview ────────────────────────────────────────────
          if (_type == 'text' || _mediaFile == null)
            Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: Color(int.parse(_bgColor.replaceFirst('#', '0xFF'))),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _textCtrl.text.isEmpty ? 'Your status preview' : _textCtrl.text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 18,
                      fontWeight: FontWeight.w600, height: 1.4),
                ),
              )),
            )
          else if (_uploading)
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 12),
                Text('Uploading media...', style: TextStyle(color: AppColors.textMuted)),
              ])),
            )
          else if (_mediaType == 'image')
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.file(_mediaFile!, height: 240, width: double.infinity,
                  fit: BoxFit.cover),
            )
          else
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: isDark ? AppColors.bgCard : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.video_file_rounded, color: AppColors.primary, size: 48),
                SizedBox(height: 8),
                Text('Video ready', style: TextStyle(color: AppColors.primary,
                    fontWeight: FontWeight.w600)),
              ])),
            ),

          const SizedBox(height: 20),

          // ── Type selector ───────────────────────────────────────
          _label('STATUS TYPE', sub),
          Row(children: [
            _typeBtn('text',  Icons.text_fields_rounded,   'Text',   isDark, text),
            const SizedBox(width: 8),
            _typeBtn('image', Icons.image_rounded,          'Image',  isDark, text),
            const SizedBox(width: 8),
            _typeBtn('video', Icons.videocam_rounded,       'Video',  isDark, text),
            const SizedBox(width: 8),
            _typeBtn('link',  Icons.link_rounded,           'Link',   isDark, text),
          ]),
          const SizedBox(height: 20),

          // ── Text content ────────────────────────────────────────
          _label('CAPTION / TEXT', sub),
          Container(
            decoration: BoxDecoration(
                color: field, borderRadius: BorderRadius.circular(12)),
            child: TextField(
              controller: _textCtrl,
              maxLines: 3,
              maxLength: 280,
              style: TextStyle(color: text, fontSize: 14),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _type == 'text'
                    ? 'What\'s on your mind?'
                    : 'Add a caption (optional)...',
                hintStyle: TextStyle(color: sub, fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(14),
                counterStyle: TextStyle(color: sub, fontSize: 11),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Media picker ────────────────────────────────────────
          if (_type == 'image' || _type == 'video') ...[
            _label('ADD MEDIA', sub),
            Row(children: [
              Expanded(child: _mediaBtn(
                Icons.camera_alt_rounded, 'Camera',
                () => _pickMedia(ImageSource.camera, isVideo: _type == 'video'),
                isDark,
              )),
              const SizedBox(width: 10),
              Expanded(child: _mediaBtn(
                Icons.photo_library_rounded, 'Gallery',
                () => _pickMedia(ImageSource.gallery, isVideo: _type == 'video'),
                isDark,
              )),
            ]),
            const SizedBox(height: 16),
          ],

          // ── Link fields ─────────────────────────────────────────
          if (_type == 'link') ...[
            _label('LINK URL', sub),
            Container(
              decoration: BoxDecoration(
                  color: field, borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _linkCtrl,
                keyboardType: TextInputType.url,
                style: TextStyle(color: text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'https://...',
                  hintStyle: TextStyle(color: sub, fontSize: 13),
                  prefixIcon: Icon(Icons.link_rounded, color: AppColors.primary, size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _label('LINK TITLE (optional)', sub),
            Container(
              decoration: BoxDecoration(
                  color: field, borderRadius: BorderRadius.circular(12)),
              child: TextField(
                controller: _linkTitleCtrl,
                style: TextStyle(color: text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. "Check out this income opportunity"',
                  hintStyle: TextStyle(color: sub, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Background color ────────────────────────────────────
          if (_type == 'text') ...[
            _label('BACKGROUND COLOR', sub),
            Row(children: List.generate(_bgColors.length, (i) => GestureDetector(
              onTap: () => setState(() => _bgColor = _bgColors[i]),
              child: Container(
                width: 32, height: 32,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Color(int.parse(_bgColors[i].replaceFirst('#', '0xFF'))),
                  shape: BoxShape.circle,
                  border: _bgColor == _bgColors[i]
                      ? Border.all(color: Colors.white, width: 3)
                      : null,
                  boxShadow: _bgColor == _bgColors[i] ? [
                    BoxShadow(color: Color(int.parse(_bgColors[i].replaceFirst('#', '0xFF'))).withOpacity(0.5),
                        blurRadius: 8, spreadRadius: 1)
                  ] : null,
                ),
              ),
            ))),
            const SizedBox(height: 16),
          ],

          // ── Duration ────────────────────────────────────────────
          _label('EXPIRES AFTER', sub),
          Row(children: [
            _durationBtn(24,  '24h', isDark, text),
            const SizedBox(width: 8),
            _durationBtn(48,  '48h', isDark, text),
            const SizedBox(width: 8),
            _durationBtn(72,  '3 days', isDark, text),
            const SizedBox(width: 8),
            _durationBtn(168, '7 days', isDark, text),
          ]),

          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _label(String t, Color sub) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1)),
  );

  Widget _typeBtn(String type, IconData icon, String label, bool isDark, Color text) {
    final active = _type == type;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() { _type = type; _mediaFile = null; _mediaUrl = null; }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppColors.primary.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? AppColors.primary : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        child: Column(children: [
          Icon(icon, color: active ? AppColors.primary : text, size: 20),
          const SizedBox(height: 3),
          Text(label, style: TextStyle(
              fontSize: 10, color: active ? AppColors.primary : text,
              fontWeight: FontWeight.w600)),
        ]),
      ),
    ));
  }

  Widget _mediaBtn(IconData icon, String label, VoidCallback onTap, bool isDark) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isDark ? Colors.white12 : Colors.grey.shade300),
        ),
        child: Column(children: [
          Icon(icon, color: AppColors.primary, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(
              fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600)),
        ]),
      ),
    );

  Widget _durationBtn(int hours, String label, bool isDark, Color text) {
    final active = _durationHours == hours;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _durationHours = hours),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: active ? AppColors.primary : (isDark ? Colors.white24 : Colors.grey.shade300)),
        ),
        child: Center(child: Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600,
            color: active ? Colors.white : text))),
      ),
    ));
  }
}
