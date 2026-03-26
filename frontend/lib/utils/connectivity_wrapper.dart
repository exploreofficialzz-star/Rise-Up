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

class _ConnectivityWrapperState extends State<ConnectivityWrapper> {
  bool _isOnline = true;
  bool _showBanner = false;
  StreamSubscription? _sub;

  @override
  void initState() {
    super.initState();
    _checkInitial();
    _sub = Connectivity().onConnectivityChanged.listen(_onChanged);
  }

  Future<void> _checkInitial() async {
    // connectivity_plus v6+ returns List<ConnectivityResult>
    final results = await Connectivity().checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _handleResult(result);
  }

  void _onChanged(List<ConnectivityResult> results) {
    _handleResult(results.isNotEmpty ? results.first : ConnectivityResult.none);
  }

  void _handleResult(ConnectivityResult result) {
    final online = result != ConnectivityResult.none;
    if (online == _isOnline) return;
    setState(() {
      _isOnline = online;
      _showBanner = true;
    });
    if (online) {
      // Hide the "back online" banner after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showBanner = false);
      });
    }
  }

  @override
  void dispose() { _sub?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_showBanner)
          Positioned(
            bottom: 80, left: 16, right: 16,
            child: _ConnectivityBanner(isOnline: _isOnline)
                .animate().fadeIn(duration: 300.ms).slideY(begin: 0.3),
          ),
        // Full offline overlay for extended outages
        if (!_isOnline)
          IgnorePointer(
            ignoring: false,
            child: Container(
              color: Colors.transparent,
              // Allow interaction but show the banner — don't block full app
            ),
          ),
      ],
    );
  }
}

class _ConnectivityBanner extends StatelessWidget {
  final bool isOnline;
  const _ConnectivityBanner({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Container(
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
              isOnline ? 'Back online! 🎉' : 'No internet connection',
              style: AppTextStyles.label.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!isOnline)
            Text(
              'Some features limited',
              style: AppTextStyles.caption.copyWith(color: Colors.white70),
            ),
        ],
      ),
    );
  }
}
