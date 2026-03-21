import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_constants.dart';
import 'config/router.dart';
import 'services/ad_service.dart';
import 'services/notification_service.dart';
import 'utils/storage_service.dart';
import 'utils/connectivity_wrapper.dart';
import 'utils/version_check_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Platform-safe storage (must be first)
  storageService.init();

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: AppColors.bgDark,
    ));
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  // Supabase — required
  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);

  // Firebase / Notifications — optional, graceful fail
  if (!kIsWeb) {
    try {
      await notificationService.initialize();
    } catch (e) {
      debugPrint('[RiseUp] Firebase/notifications init skipped: $e');
    }
  }

  // Ads — graceful fail
  try {
    await adService.initialize();
  } catch (e) {
    debugPrint('[RiseUp] Ads init error: $e');
  }

  // Global Flutter error handler
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runApp(const ProviderScope(child: RiseUpApp()));
}

class RiseUpApp extends StatefulWidget {
  const RiseUpApp({super.key});
  @override
  State<RiseUpApp> createState() => _RiseUpAppState();
}

class _RiseUpAppState extends State<RiseUpApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _runVersionCheck());
  }

  Future<void> _runVersionCheck() async {
    try {
      final matches = router.routerDelegate.currentConfiguration.matches;
      if (matches.isNotEmpty) {
        final ctx = router.routerDelegate.navigatorKey.currentContext;
        if (ctx != null && ctx.mounted) {
          versionCheckService.checkAndPrompt(ctx);
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App Open Ad disabled — caused black screen on startup
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityWrapper(
      child: MaterialApp.router(
        title: 'RiseUp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: router,
        builder: (context, child) {
          ErrorWidget.builder =
              (details) => _GlobalErrorWidget(details: details);
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}

// ── Global error widget ──────────────────────────────────────
class _GlobalErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _GlobalErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgDark,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('😕', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              const Text(
                'Something went wrong',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please restart the app.',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => router.go('/home'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
