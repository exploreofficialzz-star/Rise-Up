import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/app_constants.dart';
import 'config/router.dart';
import 'services/ad_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgDark,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Init Supabase
  await Supabase.initialize(
    url: kSupabaseUrl,
    anonKey: kSupabaseAnonKey,
  );

  // Init AdMob (preloads rewarded, interstitial, and app-open ads)
  await adService.initialize();

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
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Show app-open ad when app is resumed from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      adService.showAppOpenAdIfAvailable();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'RiseUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: router,
    );
  }
}
