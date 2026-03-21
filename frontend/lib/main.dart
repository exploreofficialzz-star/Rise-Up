import 'package:flutter/material.dart';

void main() {
  runApp(const MaterialApp(
    home: Scaffold(
      backgroundColor: Color(0xFF6C5CE7),
      body: Center(
        child: Text(
          'Flutter is alive!',
          style: TextStyle(color: Colors.white, fontSize: 24),
        ),
      ),
    ),
  ));
}
