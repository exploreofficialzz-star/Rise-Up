import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_constants.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: RiseUpApp()));
}

class RiseUpApp extends StatelessWidget {
  const RiseUpApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RiseUp',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const Scaffold(
        body: Center(
          child: Text(
            'Router removed - app alive!',
            style: TextStyle(color: Colors.white, fontSize: 20),
          ),
        ),
      ),
    );
  }
}
