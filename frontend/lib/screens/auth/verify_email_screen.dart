import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import '../../utils/storage_service.dart';
import '../../widgets/gradient_button.dart';

class VerifyEmailScreen extends StatefulWidget {
  final String email;
  const VerifyEmailScreen({super.key, required this.email});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  final List<TextEditingController> _controllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(6, (_) => FocusNode());

  bool    _verifying  = false;
  bool    _resending  = false;
  bool    _resent     = false;
  int     _countdown  = 0;
  Timer?  _timer;
  String? _error;
  bool    _shakeError = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    for (final f in _focusNodes) f.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String get _code => _controllers.map((c) => c.text).join();

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 0) { t.cancel(); return; }
      setState(() => _countdown--);
    });
  }

  void _clearBoxes() {
    for (final c in _controllers) c.clear();
    if (mounted) _focusNodes[0].requestFocus();
  }

  // ── Input logic ───────────────────────────────────────────────────────────

  void _onChanged(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 1) {
      for (int j = index; j < 6 && (j - index) < digits.length; j++) {
        _controllers[j].text = digits[j - index];
      }
      final lastFilled = (index + digits.length - 1).clamp(0, 5);
      _focusNodes[lastFilled].requestFocus();
      setState(() { _error = null; _shakeError = false; });
      if (index + digits.length >= 6) _verify();
      return;
    }

    if (digits.isNotEmpty) {
      setState(() { _error = null; _shakeError = false; });
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
        _verify();
      }
    }
  }

  KeyEventResult _onKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_controllers[index].text.isEmpty && index > 0) {
          _controllers[index - 1].clear();
          _focusNodes[index - 1].requestFocus();
          setState(() {});
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _verify() async {
    final code = _code;
    if (code.length < 6) {
      setState(() { _error = 'Please enter all 6 digits'; _shakeError = true; });
      return;
    }
    setState(() { _verifying = true; _error = null; _shakeError = false; });
    try {
      final data = await api.verifyOtp(widget.email, code);
      await Future.wait([
        storageService.write(key: 'access_token',  value: data['access_token']  as String),
        storageService.write(key: 'refresh_token', value: data['refresh_token'] as String),
        storageService.write(key: 'user_id',       value: data['user_id']       as String),
      ]);
      authService.onLoginSuccess();
      if (!mounted) return;
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error      = 'Invalid or expired code. Please try again.';
        _shakeError = true;
        _verifying  = false;
      });
      _clearBoxes();
    }
  }

  Future<void> _resend() async {
    if (_countdown > 0 || _resending) return;
    setState(() { _resending = true; _resent = false; _error = null; });
    try {
      await api.resendVerification(widget.email);
      if (mounted) {
        setState(() { _resent = true; _resending = false; });
        _startCountdown();
        _clearBoxes();
      }
    } catch (_) {
      if (mounted) setState(() => _resending = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final isDark    = theme.brightness == Brightness.dark;
    final cs        = theme.colorScheme;

    // ── Semantic tokens derived from active theme ─────────────────────────
    final bgColor       = cs.surface;
    final textColor     = cs.onSurface;
    final subColor      = cs.onSurface.withOpacity(0.55);
    final inputFill     = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerHighest.withOpacity(0.45);
    final iconColor     = cs.onSurface.withOpacity(0.35);
    final borderInactive = cs.outlineVariant.withOpacity(0.3);
    final resendDisabledColor = cs.onSurface.withOpacity(0.3);
    final resendBg      = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerHighest.withOpacity(0.5);
    final resendBorder  = cs.outlineVariant.withOpacity(isDark ? 0.15 : 0.25);

    return Scaffold(
      backgroundColor: bgColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // ── Back ────────────────────────────────────────────────────
              GestureDetector(
                onTap: () => context.go('/register'),
                child: Icon(
                  Icons.arrow_back_ios_rounded,
                  color: cs.onSurface.withOpacity(0.6),
                  size: 22,
                ),
              ),

              const SizedBox(height: 36),

              // ── Icon ────────────────────────────────────────────────────
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(
                  Icons.mark_email_unread_rounded,
                  color: AppColors.primary,
                  size: 36,
                ),
              ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

              const SizedBox(height: 28),

              // ── Headline ────────────────────────────────────────────────
              Text(
                'Check your email 📬',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: textColor,
                ),
              ).animate().fadeIn(delay: 100.ms),

              const SizedBox(height: 10),

              RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 14, color: subColor, height: 1.5),
                  children: [
                    const TextSpan(text: 'We sent a 6-digit code to\n'),
                    TextSpan(
                      text: widget.email,
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ).animate().fadeIn(delay: 150.ms),

              const SizedBox(height: 6),
              Text(
                'Enter it below to confirm your account.',
                style: TextStyle(fontSize: 13, color: subColor),
              ).animate().fadeIn(delay: 170.ms),

              const SizedBox(height: 40),

              // ── OTP Boxes ───────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) => _OtpBox(
                  controller:  _controllers[i],
                  focusNode:   _focusNodes[i],
                  isFilled:    _controllers[i].text.isNotEmpty,
                  hasError:    _error != null,
                  inputFill:   inputFill,
                  textColor:   textColor,
                  iconColor:   iconColor,
                  borderInactive: borderInactive,
                  onChanged:   (v) => _onChanged(i, v),
                  onKeyEvent:  (e) => _onKeyEvent(i, e),
                )),
              ).animate().fadeIn(delay: 200.ms),

              const SizedBox(height: 20),

              // ── Error ───────────────────────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.error.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: cs.error.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline, color: cs.error, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(color: cs.error, fontSize: 13)),
                    ),
                  ]),
                ).animate(key: ValueKey(_shakeError))
                    .shake(hz: 4, offset: const Offset(6, 0))
                    .fadeIn(),

              // ── Resent success ──────────────────────────────────────────
              if (_resent && _error == null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Row(children: [
                    const Icon(Icons.check_circle_outline,
                        color: AppColors.success, size: 16),
                    const SizedBox(width: 8),
                    const Text('New code sent! Check your inbox.',
                        style: TextStyle(
                            color: AppColors.success, fontSize: 13)),
                  ]),
                ).animate().fadeIn().slideY(begin: -0.2),

              const SizedBox(height: 36),

              // ── Verify button ───────────────────────────────────────────
              GradientButton(
                text:      _verifying ? 'Verifying...' : 'Verify Email',
                onTap:     _verifying ? null : _verify,
                isLoading: _verifying,
              ).animate().fadeIn(delay: 300.ms),

              const SizedBox(height: 14),

              // ── Resend button ───────────────────────────────────────────
              GestureDetector(
                onTap: (_countdown > 0 || _resending) ? null : _resend,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    color:        resendBg,
                    borderRadius: BorderRadius.circular(14),
                    border:       Border.all(color: resendBorder),
                  ),
                  child: Center(
                    child: _resending
                        ? SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary))
                        : Text(
                            _countdown > 0
                                ? 'Resend code in ${_countdown}s'
                                : "Didn't receive it? Resend",
                            style: TextStyle(
                              fontSize:   14,
                              fontWeight: FontWeight.w600,
                              color: _countdown > 0
                                  ? resendDisabledColor
                                  : AppColors.primary,
                            ),
                          ),
                  ),
                ),
              ).animate().fadeIn(delay: 350.ms),

              const SizedBox(height: 28),

              // ── Wrong email ──────────────────────────────────────────────
              Center(
                child: GestureDetector(
                  onTap: () => context.go('/register'),
                  child: RichText(
                    text: TextSpan(
                      text: 'Wrong email? ',
                      style: TextStyle(color: subColor, fontSize: 13),
                      children: const [
                        TextSpan(
                          text: 'Go back',
                          style: TextStyle(
                            color:      AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ).animate().fadeIn(delay: 400.ms),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// OTP Box — fully theme-driven, zero hardcoded colors
// ─────────────────────────────────────────────────────────────────────────────

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode  focusNode;
  final bool       isFilled;
  final bool       hasError;
  final Color      inputFill;
  final Color      textColor;
  final Color      iconColor;
  final Color      borderInactive;
  final ValueChanged<String>        onChanged;
  final KeyEventResult Function(KeyEvent) onKeyEvent;

  const _OtpBox({
    required this.controller,
    required this.focusNode,
    required this.isFilled,
    required this.hasError,
    required this.inputFill,
    required this.textColor,
    required this.iconColor,
    required this.borderInactive,
    required this.onChanged,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final fill = hasError
        ? cs.error.withOpacity(0.08)
        : inputFill;

    final activeBorder = hasError ? cs.error : AppColors.primary;

    return Focus(
      onKeyEvent: (_, event) => onKeyEvent(event),
      child: SizedBox(
        width: 48, height: 60,
        child: TextField(
          controller:   controller,
          focusNode:    focusNode,
          textAlign:    TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          style: TextStyle(
            fontSize:   22,
            fontWeight: FontWeight.w700,
            color:      textColor,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled:      true,
            fillColor:   fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:   BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: activeBorder, width: 2.0),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: isFilled
                    ? AppColors.primary.withOpacity(0.4)
                    : borderInactive,
                width: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
