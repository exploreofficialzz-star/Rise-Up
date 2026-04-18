// lib/main.dart
// Fix v2 — Three boot/lifecycle bugs resolved:
//
//  BUG 1 (re-login every restart) — ORIGINAL v1 comment said it was fixed,
//    but storageService.init() was still NOT awaited. Tokens read before
//    storage was ready → always null → unauthenticated → forced re-login.
//    Fix: await storageService.init()
//
//  BUG 2 (silent logout after ~1 hr in background):
//    didChangeAppLifecycleState was empty, so tokens were never refreshed
//    when the app resumed. By the time the user opened the app after
//    background time, the token was expired, the first API call got 401,
//    and the refresh race lost to the Supabase signedOut event.
//    Fix: call authService.tryRefreshOnResume() on AppLifecycleState.resumed
//
//  BUG 3 (black screen before splash) — already fixed in v1, retained here.

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

  // ── FIX 1: AWAIT storage init ────────────────────────────────────────
  // Without await, storage isn't ready when authService.initialize()
  // reads tokens milliseconds later → always returns null → unauthenticated.
  // This was the primary cause of "re-login on every cold start".
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

  // authService.initialize() is instant (local reads only).
  // Any token refresh fires silently in the background from auth_service.dart.
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

  // ── FIX 2: Refresh token when app resumes from background ────────────
  // Without this, a user who leaves the app for 1+ hours comes back to an
  // expired token. The first API call gets a 401, triggers handleUnauthorized,
  // but by then Supabase may have already fired signedOut → logged out.
  // Now we proactively refresh the moment the app is foregrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      authService.tryRefreshOnResume();
    }
  }

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
