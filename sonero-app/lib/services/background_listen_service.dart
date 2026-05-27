import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import '../providers/settings_provider.dart';
import '../providers/listen_provider.dart';

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  
  service.on('listen_now').listen((event) async {
    // Show a notification that we are listening (Android only)
    if (Platform.isAndroid) {
       // Need to dynamically invoke to avoid importing android specific types on iOS
       try {
           service.invoke('setAsForeground');
       } catch(_) {}
    }

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
        final job = listen.currentJob;
        final message = job?.isDone == true
          ? job!.step.replaceAll('✅ Listo: ', '')
          : '❌ No se pudo reconocer la canción.';

        if (Platform.isAndroid) {
            try {
                // Update the background notification
                service.invoke('stopService'); // stop background service when done
            } catch(_) {}
        }
      },
    );
  });
}

class BackgroundListenService {
  static Future<void> initialize() async {
    final service = FlutterBackgroundService();

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
