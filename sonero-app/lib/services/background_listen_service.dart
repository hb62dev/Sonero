import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/settings_provider.dart';
import 'recognizer_service.dart';
import 'downloader_service.dart';
import 'database_service.dart';
import 'log_service.dart';

@pragma('vm:entry-point')
void backgroundNotificationActionHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (response.actionId == 'action_listen') {
    FlutterBackgroundService().invoke('bg_listen');
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();
  
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
      InitializationSettings(android: initializationSettingsAndroid);
      
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveBackgroundNotificationResponse: backgroundNotificationActionHandler,
  );

  // Ensure notification channel exists in background isolate
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'sonero_background',
    'Servicio Sonero',
    description: 'Identificación y descargas rápidas',
    importance: Importance.low,
  );
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  service.on('bg_listen').listen((event) async {
    final settings = SettingsProvider();
    await settings.load();
    await _startListeningFlow(service, flutterLocalNotificationsPlugin, settings);
  });

  service.on('listen_now').listen((event) async {
    final settings = SettingsProvider();
    await settings.load();
    await _startListeningFlow(service, flutterLocalNotificationsPlugin, settings);
  });

  // Display initial idle state notification
  await _showIdleNotification(flutterLocalNotificationsPlugin);

  // Check if we should trigger listening immediately (from Quick Settings tile)
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final startedFromTile = prefs.getBool('started_from_tile') ?? false;
  if (startedFromTile) {
    await prefs.setBool('started_from_tile', false);
    final settings = SettingsProvider();
    await settings.load();
    await _startListeningFlow(service, flutterLocalNotificationsPlugin, settings);
  }
}

Future<void> _startListeningFlow(
    ServiceInstance service,
    FlutterLocalNotificationsPlugin notifications,
    SettingsProvider settings,
) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  await prefs.setBool('is_listening', true);
  LogService.log('Iniciando flujo de escucha en background...');

  try {
    await _showListeningNotification(notifications);

    final record = AudioRecorder();
    final hasMicPermission = await Permission.microphone.isGranted;
    LogService.log('Permiso de micrófono: $hasMicPermission');
    if (!hasMicPermission) {
      LogService.log('Error: Permiso de micrófono denegado');
      await _showSimpleNotification(notifications, 'Error', 'Permiso de micrófono denegado');
      _resetToIdle(notifications);
      if (service is AndroidServiceInstance) {
        await service.openApp();
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final audioPath = p.join(dir.path, 'bg_listen_${DateTime.now().millisecondsSinceEpoch}.wav');

    LogService.log('Grabando audio temporal en: $audioPath');
    await record.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: audioPath,
    );

    final duration = settings.listenDuration > 0 ? settings.listenDuration : 15;
    LogService.log('Grabando por $duration segundos...');
    await Future.delayed(Duration(seconds: duration));

    final finalPath = await record.stop();
    record.dispose();
    LogService.log('Grabación detenida. Path final: $finalPath');

    if (finalPath == null) {
      LogService.log('Error: finalPath es nulo tras detener grabación');
      await _showSimpleNotification(notifications, 'Error', 'No se pudo grabar el audio');
      _resetToIdle(notifications);
      return;
    }

    await _showRecognizingNotification(notifications);
    LogService.log('Enviando audio para reconocimiento Shazam...');

    final track = await RecognizerService.recognize(finalPath);
    
    // Clean up temporary wav file
    try {
      final f = File(finalPath);
      if (await f.exists()) {
        await f.delete();
        LogService.log('Archivo de audio temporal eliminado.');
      }
    } catch (e) {
      LogService.log('No se pudo borrar el archivo temporal: $e');
    }

    if (track == null) {
      LogService.log('Reconocimiento fallido: no se pudo identificar la canción.');
      await _showSimpleNotification(notifications, 'Sonero', '❌ No se pudo identificar la canción');
      await Future.delayed(const Duration(seconds: 4));
      _resetToIdle(notifications);
      return;
    }

    LogService.log('¡Canción identificada! "${track.title}" de ${track.artist}');
    await _showDownloadingNotification(notifications, track);

    // Download and Tag
    LogService.log('Iniciando descarga y etiquetado MP3...');
    final savedPath = await DownloaderService.downloadAndTagTrack(
      track,
      musicFolder: settings.musicFolder,
    );
    LogService.log('Descarga completada. Guardada en: $savedPath');

    // Register in DB
    final filename = p.basename(savedPath);
    LogService.log('Registrando archivo "$filename" en base de datos local...');
    await DatabaseService.instance.insertMedia({
      'type': 'music',
      'title': track.title,
      'artist': track.artist,
      'album': track.album ?? '',
      'genre': track.genre ?? '',
      'year': track.year ?? '',
      'filename': filename,
      'format': 'mp3',
      'cover_url': track.coverUrl,
      'shazam_url': track.shazamUrl,
    });
    LogService.log('Registro en base de datos finalizado con éxito.');

    // Download lyrics offline
    try {
      LogService.log('Buscando y descargando letras para: ${track.title}...');
      final lyricsRes = await settings.api.saveLyrics(
        filename: filename,
        title: track.title,
        artist: track.artist,
      );
      if (lyricsRes['saved'] == true) {
        LogService.log('Letras descargadas con éxito en: ${lyricsRes['path']}');
      } else {
        LogService.log('No se pudieron descargar las letras en este momento: ${lyricsRes['error']}');
      }
    } catch (e) {
      LogService.log('Error intentando descargar letras en background: $e');
    }

    await _showSimpleNotification(
      notifications,
      '¡Canción Descargada!',
      '${track.title} - ${track.artist}',
    );

    await Future.delayed(const Duration(seconds: 5));
    _resetToIdle(notifications);

  } catch (e) {
    LogService.log('Error fatal en el flujo de escucha/descarga: $e');
    debugPrint('[BackgroundListenService] Error: $e');
    await _showSimpleNotification(notifications, 'Error en Descarga', e.toString());
    await Future.delayed(const Duration(seconds: 5));
    _resetToIdle(notifications);
  } finally {
    await prefs.setBool('is_listening', false);
    LogService.log('Flujo de escucha finalizado. is_listening establecido a false.');
  }
}

Future<void> _showIdleNotification(FlutterLocalNotificationsPlugin notifications) async {
  const androidDetails = AndroidNotificationDetails(
    'sonero_background',
    'Servicio Sonero',
    channelDescription: 'Identificación y descargas rápidas',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
    actions: [
      AndroidNotificationAction(
        'action_listen',
        'Escuchar',
        showsUserInterface: false,
        cancelNotification: false,
      ),
    ],
  );
  await notifications.show(
    888,
    'Sonero Quick Action',
    'Listo para escuchar e identificar',
    const NotificationDetails(android: androidDetails),
  );
}

Future<void> _showListeningNotification(FlutterLocalNotificationsPlugin notifications) async {
  const androidDetails = AndroidNotificationDetails(
    'sonero_background',
    'Servicio Sonero',
    channelDescription: 'Identificación y descargas rápidas',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
  );
  await notifications.show(
    888,
    'Sonero',
    '🎙️ Grabando audio...',
    const NotificationDetails(android: androidDetails),
  );
}

Future<void> _showRecognizingNotification(FlutterLocalNotificationsPlugin notifications) async {
  const androidDetails = AndroidNotificationDetails(
    'sonero_background',
    'Servicio Sonero',
    channelDescription: 'Identificación y descargas rápidas',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
  );
  await notifications.show(
    888,
    'Sonero',
    '⏳ Identificando canción...',
    const NotificationDetails(android: androidDetails),
  );
}

Future<void> _showDownloadingNotification(
  FlutterLocalNotificationsPlugin notifications,
  TrackInfo track,
) async {
  const androidDetails = AndroidNotificationDetails(
    'sonero_background',
    'Servicio Sonero',
    channelDescription: 'Identificación y descargas rápidas',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: true,
    autoCancel: false,
    showWhen: false,
  );
  await notifications.show(
    888,
    'Sonero',
    '📥 Descargando: ${track.title} - ${track.artist}...',
    const NotificationDetails(android: androidDetails),
  );
}

Future<void> _showSimpleNotification(
  FlutterLocalNotificationsPlugin notifications,
  String title,
  String body,
) async {
  const androidDetails = AndroidNotificationDetails(
    'sonero_background',
    'Servicio Sonero',
    channelDescription: 'Identificación y descargas rápidas',
    importance: Importance.low,
    priority: Priority.low,
    ongoing: false,
    autoCancel: true,
  );
  await notifications.show(
    889,
    title,
    body,
    const NotificationDetails(android: androidDetails),
  );
}

void _resetToIdle(FlutterLocalNotificationsPlugin notifications) {
  _showIdleNotification(notifications);
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
        initialNotificationTitle: 'Sonero Quick Action',
        initialNotificationContent: 'Listo para escuchar',
        foregroundServiceNotificationId: 888,
        foregroundServiceTypes: [
          AndroidForegroundType.dataSync,
          AndroidForegroundType.microphone,
        ],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
      ),
    );
  }

  static Future<void> start() async {
    if (Platform.isAndroid) {
      final hasMic = await Permission.microphone.isGranted;
      if (!hasMic) {
        debugPrint('[BackgroundListenService] Microphone permission not granted. Cannot start foreground service.');
        return;
      }
    }
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
    }
  }

  static Future<void> triggerListen() async {
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      if (await Permission.microphone.isGranted) {
        await service.startService();
      } else {
        final status = await Permission.microphone.request();
        if (status.isGranted) {
          await service.startService();
        } else {
          return;
        }
      }
    }
    service.invoke("listen_now");
  }
}
