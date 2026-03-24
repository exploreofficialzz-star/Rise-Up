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

// Country → local currency map
const _countryLocalCurrency = {
  'nigeria': 'NGN', 'ng': 'NGN',
  'ghana': 'GHS', 'gh': 'GHS',
  'kenya': 'KES', 'ke': 'KES',
  'south africa': 'ZAR', 'za': 'ZAR',
  'united states': 'USD', 'us': 'USD', 'usa': 'USD',
  'united kingdom': 'GBP', 'uk': 'GBP', 'gb': 'GBP',
  'india': 'INR', 'in': 'INR',
  'canada': 'CAD', 'ca': 'CAD',
  'australia': 'AUD', 'au': 'AUD',
  'europe': 'EUR', 'germany': 'EUR', 'france': 'EUR',
  'egypt': 'EGP', 'eg': 'EGP',
  'tanzania': 'TZS', 'tz': 'TZS',
  'uganda': 'UGX', 'ug': 'UGX',
  'rwanda': 'RWF', 'rw': 'RWF',
  'ethiopia': 'ETB', 'et': 'ETB',
  'senegal': 'XOF', 'sn': 'XOF',
  'cameroon': 'XAF', 'cm': 'XAF',
};

String _localCurrencyFromCountry(String country) {
  return _countryLocalCurrency[country.toLowerCase().trim()] ?? 'USD';
}

// ─────────────────────────────────────────────────────────
class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl    = TextEditingController();
  final _bioCtrl     = TextEditingController();
  final _statusCtrl  = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _skillsCtrl  = TextEditingController();
  final _goalCtrl    = TextEditingController();

  String? _avatarUrl;
  File?   _pickedImage;
  bool    _loading        = true;
  bool    _saving         = false;
  bool    _uploadingPhoto = false;
  String  _localCurrency  = 'USD';
  String  _stage          = 'survival';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _bioCtrl, _statusCtrl, _countryCtrl, _skillsCtrl, _goalCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await api.getProfile();
      final p = data['profile'] as Map? ?? {};
      final country = p['country']?.toString() ?? '';
      setState(() {
        _nameCtrl.text    = p['full_name']?.toString() ?? '';
        _bioCtrl.text     = p['bio']?.toString() ?? '';
        _statusCtrl.text  = p['status']?.toString() ?? '';
        _countryCtrl.text = country;
        _skillsCtrl.text  = (p['current_skills'] as List? ?? []).join(', ');
        _goalCtrl.text    = p['short_term_goal']?.toString() ?? '';
        _avatarUrl        = p['avatar_url']?.toString();
        _localCurrency    = _localCurrencyFromCountry(country);
        _stage            = p['stage']?.toString() ?? 'survival';
        _loading          = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhotoPickerSheet(isDark: isDark),
    );
    if (source == null) return;
    final picker = ImagePicker();
    final XFile? file = await picker.pickImage(
      source: source, maxWidth: 800, maxHeight: 800, imageQuality: 85,
    );
    if (file == null) return;
    setState(() { _pickedImage = File(file.path); _uploadingPhoto = true; });
    await _uploadAvatar(File(file.path));
  }

  Future<void> _uploadAvatar(File file) async {
    try {
      final token = await api.getToken();
      if (token == null) throw Exception('Not authenticated');
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path, filename: 'avatar.jpg',
          contentType: DioMediaType('image', 'jpeg'),
        ),
      });
      final baseUrl = const String.fromEnvironment(
        'API_BASE_URL', defaultValue: 'https://riseup-api.onrender.com/api/v1',
      );
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 30);
      dio.options.receiveTimeout = const Duration(seconds: 30);
      final response = await dio.post(
        '$baseUrl/progress/avatar',
        data: formData,
        options: Options(
          headers: {'Authorization': 'Bearer $token'},
          validateStatus: (s) => s != null && s < 600,
        ),
      );
      if (response.statusCode == 200) {
        setState(() { _avatarUrl = response.data['avatar_url']; _uploadingPhoto = false; });
        if (mounted) _showSnack('Profile photo updated! ✅', AppColors.success);
      } else {
        throw Exception(response.data?['detail'] ?? 'Server error ${response.statusCode}');
      }
    } catch (e) {
      setState(() => _uploadingPhoto = false);
      if (mounted) _showSnack('Photo upload failed: ${_friendlyError(e)}', AppColors.error);
    }
  }

  String _friendlyError(dynamic e) {
    final s = e.toString();
    if (s.contains('413'))   return 'Image too large. Try a smaller photo.';
    if (s.contains('401'))   return 'Session expired — please log in again.';
    if (s.contains('500'))   return 'Server error. Check storage bucket is public.';
    if (s.contains('NETWORK') || s.contains('connect')) return 'No internet connection.';
    return s.replaceAll('Exception: ', '');
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      _showSnack('Name is required', AppColors.error);
      return;
    }
    setState(() => _saving = true);
    try {
      final skills = _skillsCtrl.text
          .split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      await api.updateProfile({
        'full_name':       _nameCtrl.text.trim(),
        'bio':             _bioCtrl.text.trim(),
        'status':          _statusCtrl.text.trim(),
        'country':         _countryCtrl.text.trim(),
        'currency':        'USD',
        'current_skills':  skills,
        'short_term_goal': _goalCtrl.text.trim(),
        'stage':           _stage,
      });
      if (mounted) {
        _showSnack('Profile saved! 🎉', AppColors.success);
        context.pop();
      }
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) _showSnack('Save failed: $e', AppColors.error);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ));
  }

  // ── Build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Theme-aware colours
    final bg      = isDark ? Colors.black         : Colors.white;
    final surface = isDark ? const Color(0xFF111111) : const Color(0xFFF7F7F7);
    final card    = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final divider = isDark ? Colors.white12       : Colors.black12;
    final textPri = isDark ? Colors.white          : Colors.black87;
    final textSub = isDark ? Colors.white54        : Colors.black45;
    final iconCol = isDark ? Colors.white70        : Colors.black54;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      appBar: _buildAppBar(isDark, textPri, divider),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Avatar hero ────────────────────────────────────────
            _AvatarSection(
              isDark: isDark,
              bg: bg,
              avatarUrl: _avatarUrl,
              pickedImage: _pickedImage,
              uploading: _uploadingPhoto,
              nameInitial: _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?',
              onTap: _uploadingPhoto ? null : _pickImage,
            ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1),

            const SizedBox(height: 8),

            // ── Form sections ───────────────────────────────────────
            _SectionCard(
              isDark: isDark,
              surface: surface,
              card: card,
              divider: divider,
              children: [
                _FieldRow(label: 'Status',    icon: Iconsax.message_edit,  ctrl: _statusCtrl,  hint: 'Building my channel, Open to freelance…', iconCol: iconCol, textPri: textPri, textSub: textSub, isDark: isDark, surface: surface),
                _divLine(divider),
                _FieldRow(label: 'Full Name', icon: Iconsax.user,          ctrl: _nameCtrl,    hint: 'Your full name',                          iconCol: iconCol, textPri: textPri, textSub: textSub, isDark: isDark, surface: surface),
                _divLine(divider),
                _FieldRow(label: 'Bio',       icon: Iconsax.note_text,     ctrl: _bioCtrl,     hint: 'Where you\'re from, what you\'re building…', iconCol: iconCol, textPri: textPri, textSub: textSub, isDark: isDark, surface: surface, maxLines: 3),
              ],
            ),

            const SizedBox(height: 12),

            _SectionCard(
              isDark: isDark,
              surface: surface,
              card: card,
              divider: divider,
              children: [
                _FieldRow(
                  label: 'Country',
                  icon: Iconsax.location,
                  ctrl: _countryCtrl,
                  hint: 'Nigeria, Ghana, United Kingdom…',
                  iconCol: iconCol, textPri: textPri, textSub: textSub, isDark: isDark, surface: surface,
                  onChanged: (v) {
                    final lc = _localCurrencyFromCountry(v);
                    if (lc != _localCurrency) setState(() => _localCurrency = lc);
                  },
                ),
                if (_localCurrency.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 56, right: 16, bottom: 12),
                    child: Row(children: [
                      const Icon(Icons.info_outline_rounded, size: 12, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        'Earnings in USD · Local currency: $_localCurrency',
                        style: const TextStyle(fontSize: 11, color: AppColors.primary),
                      ),
                    ]),
                  ),
                ],
                _divLine(divider),
                _FieldRow(label: 'Skills',     icon: Iconsax.award,       ctrl: _skillsCtrl, hint: 'Video editing, Graphic design, Copywriting…', iconCol: iconCol, textPri: textPri, textSub: textSub, isDark: isDark, surface: surface),
                _divLine(divider),
                _FieldRow(label: 'Goal',       icon: Iconsax.flag,        ctrl: _goalCtrl,   hint: 'Earn \$1,000/month by June',                  iconCol: iconCol, textPri: textPri, textSub: textSub, isDark: isDark, surface: surface),
              ],
            ),

            const SizedBox(height: 12),

            // ── Wealth Stage ────────────────────────────────────────
            _SectionCard(
              isDark: isDark,
              surface: surface,
              card: card,
              divider: divider,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      Icon(Iconsax.chart_21, color: iconCol, size: 20),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Wealth Stage',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                                  color: textSub, letterSpacing: 0.5)),
                            const SizedBox(height: 2),
                            DropdownButton<String>(
                              value: _stage,
                              isExpanded: true,
                              underline: const SizedBox(),
                              dropdownColor: card,
                              style: TextStyle(color: textPri, fontSize: 14, fontWeight: FontWeight.w600),
                              icon: Icon(Icons.keyboard_arrow_down_rounded, color: iconCol),
                              items: [
                                _stageItem('survival', '🆘', 'Survival — Getting stable',  textPri),
                                _stageItem('earning',  '💪', 'Earning — Building income',   textPri),
                                _stageItem('growing',  '🚀', 'Growing — Scaling up',         textPri),
                                _stageItem('wealth',   '💎', 'Wealth — Building assets',     textPri),
                              ],
                              onChanged: (v) => setState(() => _stage = v ?? 'survival'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // ── Save button ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.5),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                      : const Text('Save Changes',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
                ),
              ),
            ),

            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(bool isDark, Color textPri, Color divider) {
    return AppBar(
      backgroundColor: isDark ? Colors.black : Colors.white,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      systemOverlayStyle: isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded,
            color: isDark ? Colors.white : Colors.black87),
        onPressed: () => context.pop(),
      ),
      title: Text('Edit Profile',
        style: TextStyle(
          fontSize: 17, fontWeight: FontWeight.w700,
          color: textPri,
        ),
      ),
      centerTitle: true,
      actions: [
        TextButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2))
              : const Text('Save',
                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Divider(height: 1, color: divider),
      ),
    );
  }

  DropdownMenuItem<String> _stageItem(String v, String emoji, String label, Color text) =>
      DropdownMenuItem(
        value: v,
        child: Text('$emoji  $label', style: TextStyle(color: text, fontSize: 14)),
      );

  Widget _divLine(Color c) => Divider(height: 1, indent: 56, endIndent: 16, color: c);
}

// ── Sub-widgets ───────────────────────────────────────────────────────

class _AvatarSection extends StatelessWidget {
  final bool isDark;
  final Color bg;
  final String? avatarUrl;
  final File? pickedImage;
  final bool uploading;
  final String nameInitial;
  final VoidCallback? onTap;

  const _AvatarSection({
    required this.isDark, required this.bg,
    required this.avatarUrl, required this.pickedImage,
    required this.uploading, required this.nameInitial,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ringColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: bg,
        border: Border(bottom: BorderSide(color: ringColor)),
      ),
      child: Column(children: [
        GestureDetector(
          onTap: onTap,
          child: Stack(clipBehavior: Clip.none, children: [
            Container(
              width: 96, height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.primary.withOpacity(0.5),
                  width: 2.5,
                ),
                color: isDark ? const Color(0xFF1A1A1A) : Colors.grey.shade200,
              ),
              child: ClipOval(
                child: uploading
                    ? const Center(child: CircularProgressIndicator(
                        color: AppColors.primary, strokeWidth: 2))
                    : pickedImage != null
                        ? Image.file(pickedImage!, fit: BoxFit.cover)
                        : avatarUrl != null && avatarUrl!.isNotEmpty
                            ? Image.network(avatarUrl!, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _initial(isDark))
                            : _initial(isDark),
              ),
            ),
            // Camera badge
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: 30, height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: bg, width: 2),
                ),
                child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 15),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: onTap,
          child: const Text('Change Photo',
            style: TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _initial(bool isDark) => Center(
    child: Text(
      nameInitial,
      style: TextStyle(
        fontSize: 36, fontWeight: FontWeight.w800,
        color: isDark ? Colors.white70 : Colors.black54,
      ),
    ),
  );
}

class _SectionCard extends StatelessWidget {
  final bool isDark;
  final Color surface, card, divider;
  final List<Widget> children;

  const _SectionCard({
    required this.isDark, required this.surface,
    required this.card, required this.divider,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: divider),
      ),
      child: Column(children: children),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final String label;
  final IconData icon;
  final TextEditingController ctrl;
  final String hint;
  final Color iconCol, textPri, textSub, surface;
  final bool isDark;
  final int maxLines;
  final ValueChanged<String>? onChanged;

  const _FieldRow({
    required this.label, required this.icon, required this.ctrl,
    required this.hint, required this.iconCol, required this.textPri,
    required this.textSub, required this.isDark, required this.surface,
    this.maxLines = 1, this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          // Icon — always aligned with first line of text
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 2 : 0),
            child: Icon(icon, color: iconCol, size: 20),
          ),
          const SizedBox(width: 16),
          // Label + input stacked
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700,
                    color: textSub, letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 3),
                TextField(
                  controller: ctrl,
                  maxLines: maxLines,
                  onChanged: onChanged,
                  style: TextStyle(
                    color: textPri,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: isDark ? Colors.white30 : Colors.black26,
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photo picker bottom sheet ─────────────────────────────────────────
class _PhotoPickerSheet extends StatelessWidget {
  final bool isDark;
  const _PhotoPickerSheet({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg   = isDark ? const Color(0xFF1A1A1A) : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub  = isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Handle
        Container(
          width: 36, height: 4,
          decoration: BoxDecoration(
            color: isDark ? Colors.white24 : Colors.black12,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 20),
        Text('Update Profile Photo',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: text)),
        const SizedBox(height: 20),
        _PickerBtn(
          icon: Icons.camera_alt_rounded, label: 'Take a Photo',
          source: ImageSource.camera, bg: sub, text: text,
        ),
        const SizedBox(height: 10),
        _PickerBtn(
          icon: Icons.photo_library_rounded, label: 'Choose from Gallery',
          source: ImageSource.gallery, bg: sub, text: text,
        ),
      ]),
    );
  }
}

class _PickerBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final ImageSource source;
  final Color bg, text;
  const _PickerBtn({required this.icon, required this.label, required this.source, required this.bg, required this.text});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context, source),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(width: 14),
          Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: text)),
        ]),
      ),
    );
  }
}
