import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_constants.dart';
import 'config/router.dart';
import 'services/ad_service.dart';
import 'utils/storage_service.dart';
import 'utils/connectivity_wrapper.dart';
import 'utils/version_check_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Init platform-safe storage first
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

  await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  await adService.initialize();

  // Global Flutter error handler — catch all unhandled errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    // TODO: Add Sentry.captureException(details.exception) when you add Sentry
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
    // Run version check after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (router.routerDelegate.currentConfiguration.matches.isNotEmpty) {
        final ctx = router.routerDelegate.navigatorKey.currentContext;
        if (ctx != null) versionCheckService.checkAndPrompt(ctx);
      }
    });
  }

  @override
  void dispose() {
    if (!kIsWeb) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb && state == AppLifecycleState.resumed) {
      adService.showAppOpenAdIfAvailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ConnectivityWrapper(
      child: MaterialApp.router(
        title: 'RiseUp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: router,
        // Global error widget for uncaught widget errors
        builder: (context, child) {
          ErrorWidget.builder = (details) => _GlobalErrorWidget(details: details);
          return child ?? const SizedBox.shrink();
        },
      ),
    );
  }
}

// ── Global error widget ───────────────────────────────────────
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
              const Text('Something went wrong',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Please restart the app.',
                  style: TextStyle(color: Colors.grey), textAlign: TextAlign.center),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => context.go('/home'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Go Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
