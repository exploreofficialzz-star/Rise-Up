// frontend/lib/main_shell.dart — RiseUp v3.0
// Shell removed — HomeScreen IS the app. This file kept for compatibility.

import 'package:flutter/material.dart';

/// In v3.0 the bottom-nav shell is gone.
/// HomeScreen manages its own scaffold, sidebar, and missions.
/// This wrapper is a passthrough kept so any lingering ShellRoute
/// references still compile.
class MainShell extends StatelessWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
