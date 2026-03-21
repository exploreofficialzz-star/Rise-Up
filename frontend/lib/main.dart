import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_constants.dart';
import 'config/router.dart';
import 'utils/connectivity_wrapper.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RiseUpApp()));
}

class RiseUpApp extends StatelessWidget {
  const RiseUpApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ConnectivityWrapper(
      child: MaterialApp.router(
        title: 'RiseUp',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        routerConfig: router,
      ),
    );
  }
}
