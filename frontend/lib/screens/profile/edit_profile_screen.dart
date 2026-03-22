import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl    = TextEditingController();
  final _bioCtrl     = TextEditingController();
  final _statusCtrl  = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _skillsCtrl  = TextEditingController();
  final _goalCtrl    = TextEditingController();

  String? _avatarUrl;
  File? _pickedImage;
  bool _loading = true;
  bool _saving  = false;
  bool _uploadingPhoto = false;
  String _currency = 'NGN';
  String _stage = 'survival';
  Map _profile = {};

  final _currencies = ['NGN', 'USD', 'GBP', 'EUR', 'GHS', 'KES', 'ZAR', 'CAD', 'AUD'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await api.getProfile();
      final p = data['profile'] as Map? ?? {};
      setState(() {
        _profile    = p;
        _nameCtrl.text    = p['full_name']?.toString() ?? '';
        _bioCtrl.text     = p['bio']?.toString() ?? '';
        _statusCtrl.text  = p['status']?.toString() ?? '';
        _locationCtrl.text = p['country']?.toString() ?? '';
        _skillsCtrl.text  = (p['current_skills'] as List? ?? []).join(', ');
        _goalCtrl.text    = p['short_term_goal']?.toString() ?? '';
        _avatarUrl        = p['avatar_url']?.toString();
        _currency         = p['currency']?.toString() ?? 'NGN';
        _stage            = p['stage']?.toString() ?? 'survival';
        _loading          = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 20),
            Text('Update Profile Photo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : Colors.black87)),
            const SizedBox(height: 20),
            _sourceOption(Icons.camera_alt_rounded, 'Take a Photo', ImageSource.camera, isDark),
            const SizedBox(height: 12),
            _sourceOption(Icons.photo_library_rounded, 'Choose from Gallery', ImageSource.gallery, isDark),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );

    if (file == null) return;

    setState(() {
      _pickedImage = File(file.path);
      _uploadingPhoto = true;
    });

    await _uploadAvatar(File(file.path));
  }

  Future<void> _uploadAvatar(File file) async {
    try {
      final token = await api.getToken();
      final dio = Dio();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: 'avatar.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });

      final response = await dio.post(
        '${const String.fromEnvironment('API_BASE_URL', defaultValue: 'https://riseup-api.onrender.com/api/v1')}/progress/avatar',
        data: formData,
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );

      if (response.statusCode == 200) {
        setState(() {
          _avatarUrl = response.data['avatar_url'];
          _uploadingPhoto = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('✅ Profile photo updated!'),
                backgroundColor: AppColors.success),
          );
        }
      }
    } catch (e) {
      setState(() => _uploadingPhoto = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _sourceOption(IconData icon, String label, ImageSource source, bool isDark) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87)),
        ]),
      ),
    );
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name is required'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final skills = _skillsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      await api.updateProfile({
        'full_name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'status': _statusCtrl.text.trim(),
        'country': _locationCtrl.text.trim(),
        'currency': _currency,
        'current_skills': skills,
        'short_term_goal': _goalCtrl.text.trim(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Profile saved!'), backgroundColor: AppColors.success),
        );
        context.pop();
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _statusCtrl.dispose();
    _locationCtrl.dispose();
    _skillsCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final card = isDark ? AppColors.bgCard : Colors.white;
    final border = isDark ? AppColors.bgSurface : Colors.grey.shade200;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;
    final field = isDark ? AppColors.bgSurface : Colors.grey.shade100;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: text),
          onPressed: () => context.pop(),
        ),
        title: Text('Edit Profile',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text)),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
                : const Text('Save', style: TextStyle(color: AppColors.primary,
                    fontWeight: FontWeight.w700, fontSize: 15)),
          ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Divider(height: 1, color: border)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Profile Photo ─────────────────────────────
                  Center(
                    child: GestureDetector(
                      onTap: _pickImage,
                      child: Stack(
                        children: [
                          Container(
                            width: 90, height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 2),
                            ),
                            child: ClipOval(
                              child: _uploadingPhoto
                                  ? Container(
                                      color: isDark ? AppColors.bgSurface : Colors.grey.shade200,
                                      child: const Center(child: CircularProgressIndicator(
                                          color: AppColors.primary, strokeWidth: 2)),
                                    )
                                  : _pickedImage != null
                                      ? Image.file(_pickedImage!, fit: BoxFit.cover)
                                      : _avatarUrl != null && _avatarUrl!.isNotEmpty
                                          ? Image.network(_avatarUrl!, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _avatarPlaceholder(text))
                                          : _avatarPlaceholder(text),
                            ),
                          ),
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: bg, width: 2),
                              ),
                              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                            ),
                          ),
                        ],
                      ),
                    ).animate().scale(),
                  ),

                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: _pickImage,
                      icon: const Icon(Iconsax.camera, size: 14, color: AppColors.primary),
                      label: const Text('Change Photo',
                          style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Status line ───────────────────────────────
                  _label('STATUS', sub),
                  _field(
                    ctrl: _statusCtrl,
                    hint: 'e.g. "Building my YouTube channel 🚀" or "Open to freelance work 💼"',
                    icon: Iconsax.status,
                    isDark: isDark, text: text, fieldBg: field,
                  ),

                  const SizedBox(height: 16),

                  // ── Name ──────────────────────────────────────
                  _label('FULL NAME', sub),
                  _field(ctrl: _nameCtrl, hint: 'Your full name',
                      icon: Iconsax.user, isDark: isDark, text: text, fieldBg: field),

                  const SizedBox(height: 16),

                  // ── Bio ───────────────────────────────────────
                  _label('BIO', sub),
                  _field(ctrl: _bioCtrl, hint: 'Tell your story — where you\'re from, what you\'re building',
                      icon: Iconsax.note_text, isDark: isDark, text: text, fieldBg: field, maxLines: 3),

                  const SizedBox(height: 16),

                  // ── Location ──────────────────────────────────
                  _label('LOCATION', sub),
                  _field(ctrl: _locationCtrl, hint: 'Your country (e.g. Nigeria, Ghana, UK)',
                      icon: Iconsax.location, isDark: isDark, text: text, fieldBg: field),

                  const SizedBox(height: 16),

                  // ── Currency ──────────────────────────────────
                  _label('CURRENCY', sub),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: field,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<String>(
                      value: _currency,
                      isExpanded: true,
                      underline: const SizedBox(),
                      dropdownColor: isDark ? AppColors.bgCard : Colors.white,
                      style: TextStyle(color: text, fontSize: 14),
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: sub),
                      items: _currencies.map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(c, style: TextStyle(color: text)),
                      )).toList(),
                      onChanged: (v) => setState(() => _currency = v ?? 'NGN'),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Skills ────────────────────────────────────
                  _label('SKILLS', sub),
                  _field(ctrl: _skillsCtrl,
                      hint: 'e.g. Video editing, Graphic design, Copywriting (comma-separated)',
                      icon: Iconsax.award, isDark: isDark, text: text, fieldBg: field),

                  const SizedBox(height: 16),

                  // ── Goal ──────────────────────────────────────
                  _label('SHORT-TERM GOAL', sub),
                  _field(ctrl: _goalCtrl, hint: 'e.g. Earn ₦100k/month by June 2025',
                      icon: Iconsax.flag, isDark: isDark, text: text, fieldBg: field),

                  const SizedBox(height: 32),

                  // ── Save button ───────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 20, height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text('Save Changes',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }

  Widget _avatarPlaceholder(Color text) {
    final name = _nameCtrl.text;
    return Container(
      color: AppColors.primary.withOpacity(0.15),
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '👤',
          style: const TextStyle(fontSize: 36, color: AppColors.primary, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _label(String text, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
        color: color, letterSpacing: 1.1)),
  );

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    required bool isDark,
    required Color text,
    required Color fieldBg,
    int maxLines = 1,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: ctrl,
        maxLines: maxLines,
        style: TextStyle(color: text, fontSize: 14),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
          prefixIcon: Icon(icon, size: 18, color: isDark ? Colors.white38 : Colors.black38),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
              horizontal: 16, vertical: maxLines > 1 ? 14 : 0),
        ),
      ),
    );
  }
}
