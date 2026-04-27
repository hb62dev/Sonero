import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Desktop-only setup (window manager + hotkeys)
  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        size: Size(1100, 720),
        minimumSize: Size(800, 580),
        center: true,
        title: 'Sonero',
        titleBarStyle: TitleBarStyle.normal,
        backgroundColor: Color(0xFF0A0A10),
      ),
    );
    await windowManager.show();
    await hotKeyManager.unregisterAll();
  }

  runApp(const ShazamApp());
}
