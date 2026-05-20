import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';
import 'app.dart';
import 'services/background_listen_service.dart';
import 'package:audio_service/audio_service.dart';
import 'services/audio_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    try {
      SoneroAudioHandler.instance = await AudioService.init(
        builder: () => SoneroAudioHandler(),
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.example.sonero.channel.audio',
          androidNotificationChannelName: 'Reproductor Sonero',
          androidNotificationOngoing: true,
          androidShowNotificationBadge: true,
        ),
      );
    } catch (e) {
      debugPrint('Error initializing AudioService: $e');
    }

    try {
      final notifications = FlutterLocalNotificationsPlugin();
      const channel = AndroidNotificationChannel(
        'sonero_background',
        'Servicio Sonero',
        description: 'Identificación y descargas rápidas',
        importance: Importance.low,
      );
      await notifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
    } catch (e) {
      debugPrint('Error creating notification channel: $e');
    }

    try {
      await BackgroundListenService.initialize();
    } catch (e) {
      debugPrint('Error initializing BackgroundListenService: $e');
    }
  }

  // Suppress transient red error screens (e.g. during track transitions).
  // In debug mode, keep the default error widget for development visibility.
  if (!kDebugMode) {
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint('Suppressed ErrorWidget: ${details.exception}');
      return const SizedBox.shrink();
    };
  }

  // Database initialization logic could go here if needed

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

