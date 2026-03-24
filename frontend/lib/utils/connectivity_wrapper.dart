import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../config/app_constants.dart';

class ConnectivityWrapper extends StatefulWidget {
  final Widget child;
  const ConnectivityWrapper({super.key, required this.child});

  @override
  State<ConnectivityWrapper> createState() => _ConnectivityWrapperState();
}

class _ConnectivityWrapperState extends State<ConnectivityWrapper>
    with SingleTickerProviderStateMixin {
  bool _isOnline = true;
  bool _showBanner = false;
  bool _wasOffline = false;
  Timer? _bannerHideTimer;
  StreamSubscription? _sub;
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _checkInitial();
    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
  }

  Future<void> _checkInitial() async {
    final results = await Connectivity().checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _handleResult(result, initial: true);
  }

  void _onChanged(List<ConnectivityResult> results) {
    _handleResult(results.isNotEmpty ? results.first : ConnectivityResult.none);
  }

  void _handleResult(ConnectivityResult result, {bool initial = false}) {
    final online = result != ConnectivityResult.none;
    if (online == _isOnline && !initial) return;
    _bannerHideTimer?.cancel();
    setState(() {
      _isOnline = online;
      _showBanner = !initial;
    });
    if (!online) {
      _wasOffline = true;
    } else if (_wasOffline) {
      setState(() => _showBanner = true);
      _bannerHideTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showBanner = false);
      });
      _wasOffline = false;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bannerHideTimer?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_isOnline) _OfflineOverlay(pulseCtrl: _pulseCtrl),
        if (_showBanner && _isOnline)
          Positioned(
            bottom: 90,
            left: 16,
            right: 16,
            child: _ConnectivityBanner(isOnline: true)
                .animate()
                .fadeIn(duration: 300.ms)
                .slideY(begin: 0.4),
          ),
      ],
    );
  }
}

class _OfflineOverlay extends StatelessWidget {
  final AnimationController pulseCtrl;
  const _OfflineOverlay({required this.pulseCtrl});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? Colors.black : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white54 : Colors.black45;

    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) => Container(
        color: bg,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.error.withOpacity(0.08 + 0.08 * pulseCtrl.value),
                  ),
                  child: Icon(
                    Icons.wifi_off_rounded,
                    size: 44,
                    color: AppColors.error.withOpacity(0.6 + 0.4 * pulseCtrl.value),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'No Internet Connection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: text,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Please check your Wi-Fi or mobile data\nand try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: sub, height: 1.6),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.bgSurface : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary.withOpacity(0.5 + 0.5 * pulseCtrl.value),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Waiting for connection…',
                        style: TextStyle(fontSize: 13, color: sub, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms);
  }
}

class _ConnectivityBanner extends StatelessWidget {
  final bool isOnline;
  const _ConnectivityBanner({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isOnline ? AppColors.success : AppColors.error,
          borderRadius: AppRadius.md,
          boxShadow: AppShadows.card,
        ),
        child: Row(
          children: [
            Icon(
              isOnline ? Icons.wifi_rounded : Icons.wifi_off_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isOnline ? '🎉 Back online! Everything is syncing.' : 'No internet connection',
                style: AppTextStyles.label.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
