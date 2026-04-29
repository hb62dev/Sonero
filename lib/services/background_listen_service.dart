import 'dart:async';
import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../providers/settings_provider.dart';
import '../providers/listen_provider.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  service.on('listen_now').listen((event) async {
    // Show a notification that we are listening
    await flutterLocalNotificationsPlugin.show(
      888,
      'Sonero',
      'Escuchando el entorno...',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sonero_background',
          'Sonero Background Service',
          icon: 'ic_launcher',
          ongoing: true,
        ),
      ),
    );

    // Initialize dependencies
    final settings = SettingsProvider();
    await settings.load();
    final listen = ListenProvider();

    listen.startListening(
      api: settings.api,
      source: 'mic',
      duration: settings.listenDuration,
      deviceIndex: settings.deviceIndex,
      onDone: () async {
        // Stop ongoing notification and show result
        final track = listen.currentTrack;
        final message = track != null 
          ? '✅ Descargado: ${track.artist} - ${track.title}'
          : '❌ No se pudo reconocer la canción.';

        await flutterLocalNotificationsPlugin.show(
          888,
          'Sonero',
          message,
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'sonero_background',
              'Sonero Background Service',
              icon: 'ic_launcher',
              ongoing: false,
            ),
          ),
        );
        service.stopSelf(); // Stop the service when done
      },
    );
  });
}

class BackgroundListenService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'sonero_background',
      'Sonero Background Service',
      description: 'Notificaciones en segundo plano de Sonero',
      importance: Importance.high,
    );

    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false,
        isForegroundMode: true,
        notificationChannelId: 'sonero_background',
        initialNotificationTitle: 'Sonero Service',
        initialNotificationContent: 'Listo para escuchar',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
  }

  static Future<void> triggerListen() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
    service.invoke("listen_now");
  }
}
