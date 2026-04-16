// lib/main.dart
// Fix v1 — Two boot bugs resolved:
//
//  BUG 1 (re-login every restart):
//    storageService.init() was NOT awaited, so storage wasn't ready
//    when authService.initialize() read tokens → always got null → unauthenticated.
//    Fix: await storageService.init()
//
//  BUG 2 (black screen before splash):
//    authService.initialize() was awaited BEFORE runApp(), and when the
//    token was expired it made a 10-second HTTP call — app sat on a blank
//    screen the whole time.
//    Fix: authService.initialize() is now instant (local-only). Network
//    refresh fires in background from auth_service.dart itself.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_constants.dart';
import 'config/router.dart';
import 'services/ad_manager.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'utils/storage_service.dart';
import 'utils/connectivity_wrapper.dart';
import 'utils/version_check_service.dart';
import 'providers/locale_provider.dart';

// ── Isolated init helpers ─────────────────────────────────────────────────

Future<void> _initSupabase() async {
  if (kSupabaseUrl.isEmpty || kSupabaseAnonKey.isEmpty) return;
  try {
    await Supabase.initialize(url: kSupabaseUrl, anonKey: kSupabaseAnonKey);
  } catch (_) {}
}

Future<void> _initNotifications() async {
  if (kIsWeb) return;
  try {
    await notificationService.initialize();
  } catch (_) {}
}

// ── Entry point ───────────────────────────────────────────────────────────

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── FIX 1: AWAIT storage init so tokens can be read immediately ──────
  // Previously this was called without await — storage wasn't ready when
  // authService.initialize() tried to read tokens, causing every boot to
  // look like "no tokens" → unauthenticated → forced re-login.
  await storageService.init();

  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor:           Colors.transparent,
      statusBarIconBrightness:  Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    ));
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  }

  if (!kIsWeb) {
    await Firebase.initializeApp();
  }

  await _initSupabase();

  // ── FIX 2: authService.initialize() is now instant (local reads only) ──
  // It no longer makes any HTTP calls during boot, so this await returns
  // in microseconds. The splash screen renders immediately after runApp().
  // Any token refresh that is needed fires silently in the background.
  await Future.wait([
    authService.initialize(),
    _initNotifications(),
  ]);

  adManager.initialize(isPremium: false).catchError((_) {});

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  runApp(const ProviderScope(child: RiseUpApp()));
}

// ── App root ──────────────────────────────────────────────────────────────

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
  void didChangeAppLifecycleState(AppLifecycleState state) {}

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final locale = ref.watch(localeProvider);
        return MaterialApp.router(
          title:                      'RiseUp',
          debugShowCheckedModeBanner: false,
          theme:     AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: ThemeMode.system,
          locale:    locale,
          supportedLocales: const [
            Locale('en'), Locale('es'), Locale('fr'), Locale('de'),
            Locale('pt'), Locale('hi'), Locale('ar'), Locale('zh'),
            Locale('ja'), Locale('ru'), Locale('sw'), Locale('yo'),
            Locale('ig'), Locale('ha'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          routerConfig: router,
          builder: (context, child) {
            ErrorWidget.builder =
                (details) => _GlobalErrorWidget(details: details);
            return ConnectivityWrapper(
                child: child ?? const SizedBox.shrink());
          },
        );
      },
    );
  }
}

class _GlobalErrorWidget extends StatelessWidget {
  final FlutterErrorDetails details;
  const _GlobalErrorWidget({required this.details});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.bgDark : Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('😕', style: TextStyle(fontSize: 56)),
              const SizedBox(height: 16),
              Text(
                'Something went wrong',
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please restart the app.',
                style: TextStyle(
                    color: isDark ? Colors.grey : Colors.black54),
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
