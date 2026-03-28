import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:iconsax/iconsax.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';

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
  'europe': 'EUR', 'germany': 'EUR', 'france': 'EUR', 'it': 'EUR', 'es': 'EUR',
  'egypt': 'EGP', 'eg': 'EGP',
  'tanzania': 'TZS', 'tz': 'TZS',
  'uganda': 'UGX', 'ug': 'UGX',
  'rwanda': 'RWF', 'rw': 'RWF',
  'ethiopia': 'ETB', 'et': 'ETB',
  'senegal': 'XOF', 'sn': 'XOF',
  'cameroon': 'XAF', 'cm': 'XAF',
  'philippines': 'PHP', 'ph': 'PHP',
  'indonesia': 'IDR', 'id': 'IDR',
  'malaysia': 'MYR', 'my': 'MYR',
  'singapore': 'SGD', 'sg': 'SGD',
  'thailand': 'THB', 'th': 'THB',
  'vietnam': 'VND', 'vn': 'VND',
  'brazil': 'BRL', 'br': 'BRL',
  'mexico': 'MXN', 'mx': 'MXN',
  'argentina': 'ARS', 'ar': 'ARS',
  'south korea': 'KRW', 'kr': 'KRW',
  'japan': 'JPY', 'jp': 'JPY',
  'china': 'CNY', 'cn': 'CNY',
  'hong kong': 'HKD', 'hk': 'HKD',
  'taiwan': 'TWD', 'tw': 'TWD',
  'turkey': 'TRY', 'tr': 'TRY',
  'russia': 'RUB', 'ru': 'RUB',
  'pakistan': 'PKR', 'pk': 'PKR',
  'bangladesh': 'BDT', 'bd': 'BDT',
  'sri lanka': 'LKR', 'lk': 'LKR',
  'nepal': 'NPR', 'np': 'NPR',
  'morocco': 'MAD', 'ma': 'MAD',
  'tunisia': 'TND', 'tn': 'TND',
  'algeria': 'DZD', 'dz': 'DZD',
  'ivory coast': 'XOF', 'ci': 'XOF',
  'botswana': 'BWP', 'bw': 'BWP',
  'zambia': 'ZMW', 'zm': 'ZMW',
  'zimbabwe': 'ZWL', 'zw': 'ZWL',
  'malawi': 'MWK', 'mw': 'MWK',
  'mozambique': 'MZN', 'mz': 'MZN',
  'angola': 'AOA', 'ao': 'AOA',
  'namibia': 'NAD', 'na': 'NAD',
  'lesotho': 'LSL', 'ls': 'LSL',
  'eswatini': 'SZL', 'sz': 'SZL',
  'mauritius': 'MUR', 'mu': 'MUR',
  'seychelles': 'SCR', 'sc': 'SCR',
  'madagascar': 'MGA', 'mg': 'MGA',
  'comoros': 'KMF', 'km': 'KMF',
  'djibouti': 'DJF', 'dj': 'DJF',
  'eritrea': 'ERN', 'er': 'ERN',
  'somalia': 'SOS', 'so': 'SOS',
  'sudan': 'SDG', 'sd': 'SDG',
  'south sudan': 'SSP', 'ss': 'SSP',
  'chad': 'XAF', 'td': 'XAF',
  'central african republic': 'XAF', 'cf': 'XAF',
  'equatorial guinea': 'XAF', 'gq': 'XAF',
  'gabon': 'XAF', 'ga': 'XAF',
  'congo': 'XAF', 'cg': 'XAF',
  'democratic republic of congo': 'CDF', 'cd': 'CDF',
  'burundi': 'BIF', 'bi': 'BIF',
  'liberia': 'LRD', 'lr': 'LRD',
  'sierra leone': 'SLL', 'sl': 'SLL',
  'guinea': 'GNF', 'gn': 'GNF',
  'guinea bissau': 'XOF', 'gw': 'XOF',
  'gambia': 'GMD', 'gm': 'GMD',
  'cape verde': 'CVE', 'cv': 'CVE',
  'mauritania': 'MRU', 'mr': 'MRU',
  'mali': 'XOF', 'ml': 'XOF',
  'burkina faso': 'XOF', 'bf': 'XOF',
  'niger': 'XOF', 'ne': 'XOF',
  'benin': 'XOF', 'bj': 'XOF',
  'togo': 'XOF', 'tg': 'XOF',
};

String _localCurrencyFromCountry(String country) {
  final key = country.toLowerCase().trim();
  return _countryLocalCurrency[key] ?? 'USD';
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _statusCtrl = TextEditingController();
  final _countryCtrl = TextEditingController();
  final _skillsCtrl = TextEditingController();
  final _goalCtrl = TextEditingController();

  String? _avatarUrl;
  File? _pickedImage;
  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  String _localCurrency = 'USD';
  String _stage = 'survival';

  final _formKey = GlobalKey<FormState>();
  bool _isFormValid = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _statusCtrl.dispose();
    _countryCtrl.dispose();
    _skillsCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await api.getProfile();
      final p = data['profile'] as Map? ?? {};
      final country = p['country']?.toString() ?? '';

      if (mounted) {
        setState(() {
          _nameCtrl.text = p['full_name']?.toString() ?? '';
          _bioCtrl.text = p['bio']?.toString() ?? '';
          _statusCtrl.text = p['status']?.toString() ?? '';
          _countryCtrl.text = country;
          _skillsCtrl.text = (p['current_skills'] as List? ?? []).join(', ');
          _goalCtrl.text = p['short_term_goal']?.toString() ?? '';
          _avatarUrl = p['avatar_url']?.toString();
          _localCurrency = _localCurrencyFromCountry(country);
          _stage = p['stage']?.toString() ?? 'survival';
          _loading = false;
          _validateForm();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _validateForm() {
    setState(() {
      _isFormValid = _nameCtrl.text.trim().isNotEmpty;
    });
  }

  Future<void> _pickImage() async {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.bgCard : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Update Profile Photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 20),
              _sourceBtn(Icons.camera_alt_rounded, 'Take a Photo', ImageSource.camera, isDark),
              const SizedBox(height: 12),
              _sourceBtn(Icons.photo_library_rounded, 'Choose from Gallery', ImageSource.gallery, isDark),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );

    if (source == null) return;

    try {
      final picker = ImagePicker();
      final XFile? file = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (file == null) return;

      setState(() {
        _pickedImage = File(file.path);
        _uploadingPhoto = true;
      });

      await _uploadAvatar(File(file.path));
    } catch (_) {}
  }

  Future<void> _uploadAvatar(File file) async {
    try {
      final token = await api.getToken();
      if (token == null) return;

      final fileSize = await file.length();
      if (fileSize > 5 * 1024 * 1024) {
        throw Exception('Image too large');
      }

      final result = await api.uploadAvatar(file.path);
      
      if (mounted) {
        setState(() {
          _avatarUrl = result['avatar_url'];
          _uploadingPhoto = false;
        });
        _showSnackBar('Profile photo updated', isError: false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _uploadingPhoto = false);
        _showSnackBar('Photo upload failed', isError: true);
      }
    }
  }

  Future<void> _save() async {
    if (!_isFormValid) {
      _showSnackBar('Please enter your name', isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      final country = _countryCtrl.text.trim();
      final skills = _skillsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      await api.updateProfile({
        'full_name': _nameCtrl.text.trim(),
        'bio': _bioCtrl.text.trim(),
        'status': _statusCtrl.text.trim(),
        'country': country,
        'currency': 'USD',
        'current_skills': skills,
        'short_term_goal': _goalCtrl.text.trim(),
        'stage': _stage,
      });

      if (mounted) {
        _showSnackBar('Profile saved', isError: false);
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) context.pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        _showSnackBar('Save failed', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    if (!mounted) return;
    
    if (isError) HapticFeedback.vibrate();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle,
              color: Colors.white,
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
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

    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 600;

    if (_loading) {
      return Scaffold(
        backgroundColor: bg,
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

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
        title: Text(
          'Edit Profile',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: text),
        ),
        actions: [
          TextButton(
            onPressed: (_saving || !_isFormValid) ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      color: _isFormValid ? AppColors.primary : sub,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(height: 1, color: border),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isTablet ? 600 : double.infinity),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: _uploadingPhoto ? null : _pickImage,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 100,
                                height: 100,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: AppColors.primary.withOpacity(0.4), width: 3),
                                  color: isDark ? AppColors.bgCard : Colors.grey.shade200,
                                ),
                                child: ClipOval(
                                  child: _uploadingPhoto
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                            color: AppColors.primary,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : _pickedImage != null
                                          ? Image.file(_pickedImage!, fit: BoxFit.cover)
                                          : _avatarUrl != null && _avatarUrl!.isNotEmpty
                                              ? Image.network(
                                                  _avatarUrl!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (_, __, ___) => _avatarFallback(text),
                                                )
                                              : _avatarFallback(text),
                                ),
                              ),
                              Positioned(
                                bottom: 2,
                                right: 2,
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: bg, width: 2),
                                  ),
                                  child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        GestureDetector(
                          onTap: _uploadingPhoto ? null : _pickImage,
                          child: const Text(
                            'Change Photo',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(),

                  const SizedBox(height: 28),

                  _label('STATUS', sub),
                  _field(
                    ctrl: _statusCtrl,
                    hint: 'e.g. "Building my YouTube channel"',
                    icon: Icons.circle_rounded,
                    isDark: isDark,
                    text: text,
                    fieldBg: field,
                  ),
                  const SizedBox(height: 16),

                  _label('FULL NAME *', sub),
                  _field(
                    ctrl: _nameCtrl,
                    hint: 'Your full name',
                    icon: Iconsax.user,
                    isDark: isDark,
                    text: text,
                    fieldBg: field,
                    onChanged: (_) => _validateForm(),
                  ),
                  const SizedBox(height: 16),

                  _label('BIO', sub),
                  _field(
                    ctrl: _bioCtrl,
                    hint: 'Tell your story',
                    icon: Iconsax.note_text,
                    isDark: isDark,
                    text: text,
                    fieldBg: field,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),

                  _label('COUNTRY', sub),
                  _field(
                    ctrl: _countryCtrl,
                    hint: 'e.g. Nigeria, Ghana, United Kingdom',
                    icon: Iconsax.location,
                    isDark: isDark,
                    text: text,
                    fieldBg: field,
                    onChanged: (v) {
                      final local = _localCurrencyFromCountry(v);
                      if (local != _localCurrency) {
                        setState(() => _localCurrency = local);
                      }
                    },
                  ),
                  if (_localCurrency.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const SizedBox(width: 4),
                        const Icon(Icons.info_outline_rounded, size: 13, color: AppColors.primary),
                        const SizedBox(width: 5),
                        Text(
                          'Earnings in USD · Local: $_localCurrency',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),

                  _label('SKILLS', sub),
                  _field(
                    ctrl: _skillsCtrl,
                    hint: 'e.g. Video editing, Graphic design',
                    icon: Iconsax.award,
                    isDark: isDark,
                    text: text,
                    fieldBg: field,
                  ),
                  const SizedBox(height: 16),

                  _label('SHORT-TERM GOAL', sub),
                  _field(
                    ctrl: _goalCtrl,
                    hint: 'e.g. Earn \$1,000/month by June',
                    icon: Iconsax.flag,
                    isDark: isDark,
                    text: text,
                    fieldBg: field,
                  ),
                  const SizedBox(height: 16),

                  _label('WEALTH STAGE', sub),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(color: field, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _stage,
                        isExpanded: true,
                        dropdownColor: isDark ? AppColors.bgCard : Colors.white,
                        style: TextStyle(color: text, fontSize: 14),
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: sub),
                        items: const [
                          DropdownMenuItem(value: 'survival', child: Text('🌱 Survival')),
                          DropdownMenuItem(value: 'earning', child: Text('💰 Earning')),
                          DropdownMenuItem(value: 'growing', child: Text('📈 Growing')),
                          DropdownMenuItem(value: 'wealth', child: Text('👑 Wealth')),
                        ],
                        onChanged: (v) => setState(() => _stage = v ?? 'survival'),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_saving || !_isFormValid) ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        disabledBackgroundColor: AppColors.primary.withOpacity(0.3),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : const Text(
                              'Save Changes',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                            ),
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatarFallback(Color text) => Center(
        child: Text(
          _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : '?',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800, color: text),
        ),
      );

  Widget _label(String t, Color sub) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          t,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: sub, letterSpacing: 1),
        ),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    required bool isDark,
    required Color text,
    required Color fieldBg,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) =>
      Container(
        decoration: BoxDecoration(color: fieldBg, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Padding(
              padding: EdgeInsets.only(top: maxLines > 1 ? 14 : 0, left: 14),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            Expanded(
              child: TextFormField(
                controller: ctrl,
                maxLines: maxLines,
                style: TextStyle(color: text, fontSize: 14),
                onChanged: onChanged,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 13),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _sourceBtn(IconData icon, String label, ImageSource source, bool isDark) => GestureDetector(
        onTap: () => Navigator.pop(context, source),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 22),
              const SizedBox(width: 12),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
}
