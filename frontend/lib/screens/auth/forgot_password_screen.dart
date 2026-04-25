import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import '../../config/app_constants.dart';
import '../../services/api_service.dart';
import '../../widgets/gradient_button.dart';

enum _Step { email, otp, password, success }

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  _Step _step = _Step.email;

  // Step 1 — email
  final _emailCtrl = TextEditingController();

  // Step 2 — OTP
  final List<TextEditingController> _otpControllers =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(6, (_) => FocusNode());
  int    _countdown = 0;
  Timer? _timer;
  bool   _resending = false;
  bool   _resent    = false;

  // Step 3 — new password
  String _resetAccessToken  = '';
  String _resetRefreshToken = '';
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool  _obscureNew  = true;
  bool  _obscureConf = true;

  bool    _loading    = false;
  String? _error;
  bool    _shakeError = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    for (final c in _otpControllers) c.dispose();
    for (final f in _otpFocusNodes) f.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    _timer?.cancel();
    super.dispose();
  }

  // ── OTP helpers ───────────────────────────────────────────────────────────

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _countdown = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) { t.cancel(); return; }
      if (_countdown <= 0) { t.cancel(); return; }
      setState(() => _countdown--);
    });
  }

  void _clearOtpBoxes() {
    for (final c in _otpControllers) c.clear();
    if (mounted) Future.microtask(() => _otpFocusNodes[0].requestFocus());
  }

  void _onOtpChanged(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length > 1) {
      for (int j = index; j < 6 && (j - index) < digits.length; j++) {
        _otpControllers[j].text = digits[j - index];
      }
      final lastFilled = (index + digits.length - 1).clamp(0, 5);
      _otpFocusNodes[lastFilled].requestFocus();
      setState(() { _error = null; _shakeError = false; });
      if (index + digits.length >= 6) _verifyOtp();
      return;
    }
    if (digits.isNotEmpty) {
      setState(() { _error = null; _shakeError = false; });
      if (index < 5) {
        _otpFocusNodes[index + 1].requestFocus();
      } else {
        _otpFocusNodes[index].unfocus();
        _verifyOtp();
      }
    }
  }

  KeyEventResult _onOtpKeyEvent(int index, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      if (event.logicalKey == LogicalKeyboardKey.backspace) {
        if (_otpControllers[index].text.isEmpty && index > 0) {
          _otpControllers[index - 1].clear();
          _otpFocusNodes[index - 1].requestFocus();
          setState(() {});
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  // ── Step actions ──────────────────────────────────────────────────────────

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() { _error = 'Please enter your email address'; _shakeError = true; });
      return;
    }
    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w{2,}$').hasMatch(email)) {
      setState(() { _error = 'Please enter a valid email address'; _shakeError = true; });
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await api.forgotPassword(email);
    } catch (_) { /* always show success */ }
    if (!mounted) return;
    setState(() { _loading = false; _step = _Step.otp; });
    _startCountdown();
    Future.microtask(() => _otpFocusNodes[0].requestFocus());
  }

  Future<void> _verifyOtp() async {
    final code = _otpCode;
    if (code.length < 6) {
      setState(() { _error = 'Please enter all 6 digits'; _shakeError = true; });
      return;
    }
    setState(() { _loading = true; _error = null; _shakeError = false; });
    try {
      final data = await api.verifyResetOtp(_emailCtrl.text.trim(), code);
      _resetAccessToken  = data['access_token']  as String? ?? '';
      _resetRefreshToken = data['refresh_token'] as String? ?? '';
      if (!mounted) return;
      setState(() { _loading = false; _step = _Step.password; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Invalid or expired code. Please try again.';
        _shakeError = true;
        _loading = false;
      });
      _clearOtpBoxes();
    }
  }

  Future<void> _resendCode() async {
    if (_countdown > 0 || _resending) return;
    setState(() { _resending = true; _resent = false; _error = null; });
    try {
      await api.forgotPassword(_emailCtrl.text.trim());
    } catch (_) {}
    if (mounted) {
      setState(() { _resent = true; _resending = false; });
      _startCountdown();
      _clearOtpBoxes();
    }
  }

  Future<void> _resetPassword() async {
    final newPass  = _passCtrl.text;
    final confPass = _confirmCtrl.text;
    if (newPass.isEmpty || confPass.isEmpty) {
      setState(() { _error = 'Please fill in both password fields'; _shakeError = true; });
      return;
    }
    if (newPass.length < 8) {
      setState(() { _error = 'Password must be at least 8 characters'; _shakeError = true; });
      return;
    }
    if (!RegExp(r'^(?=.*[a-zA-Z])(?=.*\d)').hasMatch(newPass)) {
      setState(() { _error = 'Password must contain letters and numbers'; _shakeError = true; });
      return;
    }
    if (newPass != confPass) {
      setState(() { _error = "Passwords don't match"; _shakeError = true; });
      return;
    }
    setState(() { _loading = true; _error = null; _shakeError = false; });
    try {
      await api.resetPassword(
        accessToken:  _resetAccessToken,
        refreshToken: _resetRefreshToken,
        newPassword:  newPass,
      );
      if (!mounted) return;
      setState(() { _loading = false; _step = _Step.success; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to reset password. Please try again.';
        _shakeError = true;
        _loading = false;
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs     = theme.colorScheme;

    // ── Semantic theme tokens ─────────────────────────────────────────────
    final bgColor    = cs.surface;
    final textColor  = cs.onSurface;
    final subColor   = cs.onSurface.withOpacity(0.55);
    final labelColor = cs.onSurface.withOpacity(0.65);
    final inputFill  = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerHighest.withOpacity(0.45);
    final inputTextColor  = cs.onSurface;
    final iconColor       = cs.onSurface.withOpacity(0.35);
    final borderInactive  = cs.outlineVariant.withOpacity(0.3);
    final resendBg        = isDark
        ? cs.surfaceContainerHighest
        : cs.surfaceContainerHighest.withOpacity(0.5);
    final resendBorder    = cs.outlineVariant.withOpacity(isDark ? 0.15 : 0.25);
    final resendDisabled  = cs.onSurface.withOpacity(0.3);

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
              if (_step != _Step.success)
                GestureDetector(
                  onTap: () {
                    if (_step == _Step.password) {
                      setState(() { _step = _Step.otp;   _error = null; });
                    } else if (_step == _Step.otp) {
                      setState(() { _step = _Step.email; _error = null; });
                    } else {
                      context.go('/login');
                    }
                  },
                  child: Icon(
                    Icons.arrow_back_ios_rounded,
                    color: cs.onSurface.withOpacity(0.6),
                    size: 22,
                  ),
                ),

              const SizedBox(height: 36),

              // ── Step indicator ──────────────────────────────────────────
              if (_step != _Step.success) ...[
                _StepIndicator(currentStep: _step, cs: cs),
                const SizedBox(height: 32),
              ],

              // ── Content ─────────────────────────────────────────────────
              AnimatedSwitcher(
                duration: 280.ms,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.05, 0),
                      end:   Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: _buildStep(
                  isDark:       isDark,
                  textColor:    textColor,
                  subColor:     subColor,
                  labelColor:   labelColor,
                  inputFill:    inputFill,
                  inputText:    inputTextColor,
                  iconColor:    iconColor,
                  borderInactive: borderInactive,
                  resendBg:     resendBg,
                  resendBorder: resendBorder,
                  resendDisabled: resendDisabled,
                  cs:           cs,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep({
    required bool   isDark,
    required Color  textColor,
    required Color  subColor,
    required Color  labelColor,
    required Color  inputFill,
    required Color  inputText,
    required Color  iconColor,
    required Color  borderInactive,
    required Color  resendBg,
    required Color  resendBorder,
    required Color  resendDisabled,
    required ColorScheme cs,
  }) {
    switch (_step) {
      case _Step.email:
        return _EmailStep(
          key:        const ValueKey('email'),
          emailCtrl:  _emailCtrl,
          loading:    _loading,
          error:      _error,
          shakeError: _shakeError,
          textColor:  textColor,
          subColor:   subColor,
          labelColor: labelColor,
          inputFill:  inputFill,
          inputText:  inputText,
          iconColor:  iconColor,
          cs:         cs,
          onSend:     _sendCode,
        );
      case _Step.otp:
        return _OtpStep(
          key:           const ValueKey('otp'),
          email:         _emailCtrl.text.trim(),
          otpControllers: _otpControllers,
          otpFocusNodes:  _otpFocusNodes,
          loading:       _loading,
          resending:     _resending,
          resent:        _resent,
          countdown:     _countdown,
          error:         _error,
          shakeError:    _shakeError,
          textColor:     textColor,
          subColor:      subColor,
          inputFill:     inputFill,
          inputText:     inputText,
          iconColor:     iconColor,
          borderInactive: borderInactive,
          resendBg:      resendBg,
          resendBorder:  resendBorder,
          resendDisabled: resendDisabled,
          cs:            cs,
          onVerify:      _verifyOtp,
          onResend:      _resendCode,
          onOtpChanged:  _onOtpChanged,
          onKeyEvent:    _onOtpKeyEvent,
        );
      case _Step.password:
        return _PasswordStep(
          key:         const ValueKey('password'),
          passCtrl:    _passCtrl,
          confirmCtrl: _confirmCtrl,
          loading:     _loading,
          obscureNew:  _obscureNew,
          obscureConf: _obscureConf,
          error:       _error,
          shakeError:  _shakeError,
          textColor:   textColor,
          subColor:    subColor,
          labelColor:  labelColor,
          inputFill:   inputFill,
          inputText:   inputText,
          iconColor:   iconColor,
          cs:          cs,
          onToggleNew:  () => setState(() => _obscureNew  = !_obscureNew),
          onToggleConf: () => setState(() => _obscureConf = !_obscureConf),
          onSubmit:    _resetPassword,
        );
      case _Step.success:
        return _SuccessStep(
          key:      const ValueKey('success'),
          subColor: subColor,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 1 — Email
// ─────────────────────────────────────────────────────────────────────────────

class _EmailStep extends StatelessWidget {
  final TextEditingController emailCtrl;
  final bool    loading;
  final String? error;
  final bool    shakeError;
  final Color   textColor, subColor, labelColor, inputFill, inputText, iconColor;
  final ColorScheme cs;
  final VoidCallback onSend;

  const _EmailStep({
    super.key,
    required this.emailCtrl,
    required this.loading,
    required this.error,
    required this.shakeError,
    required this.textColor,
    required this.subColor,
    required this.labelColor,
    required this.inputFill,
    required this.inputText,
    required this.iconColor,
    required this.cs,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_reset_rounded,
              color: AppColors.primary, size: 30),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

        const SizedBox(height: 24),

        Text('Reset password',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: textColor))
            .animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 8),

        Text("Enter your email and we'll send you a 6-digit code.",
            style: TextStyle(fontSize: 14, color: subColor, height: 1.5))
            .animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 36),

        _ErrorBanner(error: error, shakeError: shakeError, cs: cs),

        Text('Email address',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: labelColor)),
        const SizedBox(height: 8),

        TextField(
          controller:   emailCtrl,
          keyboardType: TextInputType.emailAddress,
          style:        TextStyle(fontSize: 14, color: inputText),
          onSubmitted:  (_) => onSend(),
          decoration: InputDecoration(
            hintText:  'you@example.com',
            hintStyle: TextStyle(color: iconColor, fontSize: 14),
            filled:    true,
            fillColor: inputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide:   BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            prefixIcon: Icon(Icons.mail_outline_rounded,
                color: iconColor, size: 20),
          ),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 32),

        GradientButton(
          text:      loading ? 'Sending...' : 'Send Code',
          onTap:     loading ? null : onSend,
          isLoading: loading,
        ).animate().fadeIn(delay: 300.ms),

        const SizedBox(height: 24),

        Center(
          child: GestureDetector(
            onTap: () => context.go('/login'),
            child: const Text('Back to Sign In',
                style: TextStyle(
                    color:      AppColors.primary,
                    fontWeight: FontWeight.w600,
                    fontSize:   14)),
          ),
        ).animate().fadeIn(delay: 350.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 2 — OTP
// ─────────────────────────────────────────────────────────────────────────────

class _OtpStep extends StatelessWidget {
  final String email;
  final List<TextEditingController> otpControllers;
  final List<FocusNode>             otpFocusNodes;
  final bool    loading, resending, resent;
  final int     countdown;
  final String? error;
  final bool    shakeError;
  final Color   textColor, subColor, inputFill, inputText, iconColor;
  final Color   borderInactive, resendBg, resendBorder, resendDisabled;
  final ColorScheme cs;
  final VoidCallback             onVerify, onResend;
  final void Function(int, String)      onOtpChanged;
  final KeyEventResult Function(int, KeyEvent) onKeyEvent;

  const _OtpStep({
    super.key,
    required this.email,
    required this.otpControllers,
    required this.otpFocusNodes,
    required this.loading,
    required this.resending,
    required this.resent,
    required this.countdown,
    required this.error,
    required this.shakeError,
    required this.textColor,
    required this.subColor,
    required this.inputFill,
    required this.inputText,
    required this.iconColor,
    required this.borderInactive,
    required this.resendBg,
    required this.resendBorder,
    required this.resendDisabled,
    required this.cs,
    required this.onVerify,
    required this.onResend,
    required this.onOtpChanged,
    required this.onKeyEvent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.password_rounded,
              color: AppColors.accent, size: 30),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

        const SizedBox(height: 24),

        Text('Enter the code',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: textColor))
            .animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 8),

        RichText(
          text: TextSpan(
            style: TextStyle(fontSize: 14, color: subColor, height: 1.5),
            children: [
              const TextSpan(text: 'We sent a 6-digit code to\n'),
              TextSpan(
                text: email,
                style: const TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ).animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 36),

        _ErrorBanner(error: error, shakeError: shakeError, cs: cs),

        if (resent && error == null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color:  AppColors.success.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline,
                  color: AppColors.success, size: 16),
              const SizedBox(width: 8),
              const Text('New code sent!',
                  style: TextStyle(color: AppColors.success, fontSize: 13)),
            ]),
          ).animate().fadeIn(),
          const SizedBox(height: 16),
        ],

        // OTP boxes
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) => _OtpBox(
            controller:     otpControllers[i],
            focusNode:      otpFocusNodes[i],
            isFilled:       otpControllers[i].text.isNotEmpty,
            hasError:       error != null,
            inputFill:      inputFill,
            textColor:      textColor,
            iconColor:      iconColor,
            borderInactive: borderInactive,
            onChanged:      (v) => onOtpChanged(i, v),
            onKeyEvent:     (e) => onKeyEvent(i, e),
          )),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 36),

        GradientButton(
          text:      loading ? 'Verifying...' : 'Verify Code',
          onTap:     loading ? null : onVerify,
          isLoading: loading,
        ).animate().fadeIn(delay: 300.ms),

        const SizedBox(height: 14),

        GestureDetector(
          onTap: (countdown > 0 || resending) ? null : onResend,
          child: Container(
            width: double.infinity, height: 52,
            decoration: BoxDecoration(
              color:        resendBg,
              borderRadius: BorderRadius.circular(14),
              border:       Border.all(color: resendBorder),
            ),
            child: Center(
              child: resending
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : Text(
                      countdown > 0
                          ? 'Resend code in ${countdown}s'
                          : "Didn't receive it? Resend",
                      style: TextStyle(
                        fontSize:   14,
                        fontWeight: FontWeight.w600,
                        color: countdown > 0
                            ? resendDisabled
                            : AppColors.primary,
                      ),
                    ),
            ),
          ),
        ).animate().fadeIn(delay: 350.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step 3 — New Password
// ─────────────────────────────────────────────────────────────────────────────

class _PasswordStep extends StatelessWidget {
  final TextEditingController passCtrl, confirmCtrl;
  final bool    loading, obscureNew, obscureConf;
  final String? error;
  final bool    shakeError;
  final Color   textColor, subColor, labelColor, inputFill, inputText, iconColor;
  final ColorScheme cs;
  final VoidCallback onToggleNew, onToggleConf, onSubmit;

  const _PasswordStep({
    super.key,
    required this.passCtrl,
    required this.confirmCtrl,
    required this.loading,
    required this.obscureNew,
    required this.obscureConf,
    required this.error,
    required this.shakeError,
    required this.textColor,
    required this.subColor,
    required this.labelColor,
    required this.inputFill,
    required this.inputText,
    required this.iconColor,
    required this.cs,
    required this.onToggleNew,
    required this.onToggleConf,
    required this.onSubmit,
  });

  InputDecoration _inputDec({
    required String hint,
    required Color  fill,
    required Color  icon,
    required bool   obscure,
    required VoidCallback onToggle,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      hintText:  hint,
      hintStyle: TextStyle(color: icon, fontSize: 14),
      filled:    true,
      fillColor: fill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide:   BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      prefixIcon: Icon(prefixIcon, color: icon, size: 20),
      suffixIcon: IconButton(
        icon: Icon(
          obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
          color: icon, size: 20,
        ),
        onPressed: onToggle,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.lock_open_rounded,
              color: AppColors.success, size: 30),
        ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),

        const SizedBox(height: 24),

        Text('New password',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, color: textColor))
            .animate().fadeIn(delay: 100.ms),

        const SizedBox(height: 8),

        Text('Choose a strong password for your account.',
            style: TextStyle(fontSize: 14, color: subColor, height: 1.5))
            .animate().fadeIn(delay: 150.ms),

        const SizedBox(height: 36),

        _ErrorBanner(error: error, shakeError: shakeError, cs: cs),

        Text('New password',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: labelColor)),
        const SizedBox(height: 8),

        TextField(
          controller:  passCtrl,
          obscureText: obscureNew,
          style:       TextStyle(fontSize: 14, color: inputText),
          decoration:  _inputDec(
            hint:      'Min 8 chars, include numbers',
            fill:      inputFill,
            icon:      iconColor,
            obscure:   obscureNew,
            onToggle:  onToggleNew,
            prefixIcon: Icons.lock_outline_rounded,
          ),
        ).animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 18),

        Text('Confirm password',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w500, color: labelColor)),
        const SizedBox(height: 8),

        TextField(
          controller:  confirmCtrl,
          obscureText: obscureConf,
          style:       TextStyle(fontSize: 14, color: inputText),
          onSubmitted: (_) => onSubmit(),
          decoration:  _inputDec(
            hint:      'Repeat your new password',
            fill:      inputFill,
            icon:      iconColor,
            obscure:   obscureConf,
            onToggle:  onToggleConf,
            prefixIcon: Icons.lock_outline_rounded,
          ),
        ).animate().fadeIn(delay: 250.ms),

        const SizedBox(height: 10),

        Row(children: [
          const Icon(Icons.shield_outlined, size: 13, color: AppColors.success),
          const SizedBox(width: 5),
          Text('Your password is encrypted & secure',
              style: TextStyle(color: AppColors.success, fontSize: 12)),
        ]).animate().fadeIn(delay: 280.ms),

        const SizedBox(height: 32),

        GradientButton(
          text:      loading ? 'Saving...' : 'Set New Password',
          onTap:     loading ? null : onSubmit,
          isLoading: loading,
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Success screen
// ─────────────────────────────────────────────────────────────────────────────

class _SuccessStep extends StatelessWidget {
  final Color subColor;
  const _SuccessStep({super.key, required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Container(
          width: 88, height: 88,
          decoration: BoxDecoration(
            color: AppColors.success.withOpacity(0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_rounded,
              color: AppColors.success, size: 44),
        ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),

        const SizedBox(height: 32),

        const Text('Password reset! 🎉',
            style: TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800,
                color: AppColors.success))
            .animate().fadeIn(delay: 200.ms),

        const SizedBox(height: 12),

        Text(
          'Your password has been updated.\nYou can now sign in with your new password.',
          style: TextStyle(fontSize: 14, color: subColor, height: 1.5),
          textAlign: TextAlign.center,
        ).animate().fadeIn(delay: 300.ms),

        const SizedBox(height: 52),

        GradientButton(
          text:  'Sign In Now',
          onTap: () => context.go('/login'),
        ).animate().fadeIn(delay: 400.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Step Indicator — theme-driven
// ─────────────────────────────────────────────────────────────────────────────

class _StepIndicator extends StatelessWidget {
  final _Step      currentStep;
  final ColorScheme cs;
  const _StepIndicator({required this.currentStep, required this.cs});

  int get _activeIndex {
    switch (currentStep) {
      case _Step.email:    return 0;
      case _Step.otp:      return 1;
      case _Step.password: return 2;
      case _Step.success:  return 3;
    }
  }

  @override
  Widget build(BuildContext context) {
    const labels = ['Email', 'Code', 'Password'];
    return Row(
      children: List.generate(3, (i) {
        final isDone   = i < _activeIndex;
        final isActive = i == _activeIndex;

        final dotColor = (isActive || isDone)
            ? AppColors.primary
            : cs.outlineVariant.withOpacity(0.5);

        final labelColor = isActive
            ? AppColors.primary
            : isDone
                ? AppColors.primary.withOpacity(0.6)
                : cs.onSurface.withOpacity(0.3);

        return Expanded(
          child: Row(children: [
            AnimatedContainer(
              duration: 300.ms,
              width:  isActive ? 28 : 20,
              height: 20,
              decoration: BoxDecoration(
                color:        dotColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 12)
                    : Text('${i + 1}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 6),
            Text(labels[i],
                style: TextStyle(
                    fontSize:   12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    color:      labelColor)),
            if (i < 2) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 1.5,
                  color: i < _activeIndex
                      ? AppColors.primary.withOpacity(0.4)
                      : cs.outlineVariant.withOpacity(0.3),
                ),
              ),
            ],
          ]),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Error Banner — theme-driven
// ─────────────────────────────────────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String? error;
  final bool    shakeError;
  final ColorScheme cs;
  const _ErrorBanner({
    required this.error,
    required this.shakeError,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        cs.error.withOpacity(0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.error.withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(Icons.error_outline, color: cs.error, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(error!,
                style: TextStyle(color: cs.error, fontSize: 13)),
          ),
        ]),
      ).animate(key: ValueKey(shakeError))
          .shake(hz: 4, offset: const Offset(6, 0))
          .fadeIn(),
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
  final ValueChanged<String>             onChanged;
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
    final cs   = Theme.of(context).colorScheme;
    final fill = hasError ? cs.error.withOpacity(0.08) : inputFill;
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
