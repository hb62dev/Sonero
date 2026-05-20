import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:local_notifier/local_notifier.dart';

import '../core/api_client.dart'; // Still imported for backwards compatibility signatures, but not used.
import '../models/listen_job.dart';
import '../services/recognizer_service.dart';
import '../services/downloader_service.dart';
import '../services/database_service.dart';

class ListenProvider extends ChangeNotifier {
  ListenJob? _currentJob;
  bool _isListening = false;

  ListenJob? get currentJob => _currentJob;
  bool get isListening => _isListening;

  // Parámetros para el reintento
  ApiClient? _lastApi;
  String? _lastSource;
  int? _lastDuration;
  int? _lastDeviceIndex;
  String? _lastPlaylist;
  VoidCallback? _lastOnDone;
  ValueChanged<String>? _lastOnError;

  Future<void> startListening({
    required ApiClient api, // Kept for method signature compatibility
    required String source,
    required int duration,
    int? deviceIndex,
    String? playlist,
    VoidCallback? onDone,
    ValueChanged<String>? onError,
  }) async {
    if (_isListening) return;

    _lastApi = api;
    _lastSource = source;
    _lastDuration = duration;
    _lastDeviceIndex = deviceIndex;
    _lastPlaylist = playlist;
    _lastOnDone = onDone;
    _lastOnError = onError;

    _isListening = true;
    _currentJob = null;
    notifyListeners();

    try {
      _currentJob = ListenJob(
        jobId: 'local_native',
        status: ListenJobStatus.listening,
        step: '🎙️ Escuchando...',
        progress: 10,
      );
      notifyListeners();

      final record = AudioRecorder();
      if (!await record.hasPermission()) {
        throw Exception('Permiso de micrófono denegado.');
      }

      final dir = await getTemporaryDirectory();
      final audioPath = '${dir.path}/listen_temp_${DateTime.now().millisecondsSinceEpoch}.wav';
      
      await record.start(
        const RecordConfig(encoder: AudioEncoder.wav), 
        path: audioPath,
      );
      
      await Future.delayed(Duration(seconds: duration));
      final finalPath = await record.stop();
      record.dispose();
      
      if (finalPath == null) {
        throw Exception('No se pudo grabar el audio.');
      }

      _currentJob = ListenJob(
        jobId: 'local_native',
        status: ListenJobStatus.recognizing,
        step: '⏳ Identificando canción...',
        progress: 40,
      );
      notifyListeners();

      // Reconocimiento Nativo
      final track = await RecognizerService.recognize(finalPath);
      
      if (track == null) {
        throw Exception('No se pudo identificar la canción.');
      }

      _currentJob = ListenJob(
        jobId: 'local_native',
        status: ListenJobStatus.downloading,
        step: '📥 Descargando: ${track.title} - ${track.artist}...',
        progress: 70,
      );
      notifyListeners();

      // Descarga Nativa
      final savedPath = await DownloaderService.downloadAndTagTrack(
        track,
        musicFolder: api.musicFolder,
        playlist: playlist,
      );

      _currentJob = ListenJob(
        jobId: 'local_native',
        status: ListenJobStatus.done,
        step: '✅ Guardado: ${track.title}',
        progress: 100,
      );
      
      final filename = p.basename(savedPath);
      final dbFilename = playlist != null && playlist.isNotEmpty
          ? p.join(playlist, filename).replaceAll('\\', '/')
          : filename;

      // Guardar en la base de datos local
      await DatabaseService.instance.insertMedia({
        'type': 'music',
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'genre': track.genre,
        'year': track.year,
        'filename': dbFilename,
        'format': 'm4a',
        'cover_url': track.coverUrl,
        'shazam_url': track.shazamUrl,
      });

      if (playlist != null && playlist.isNotEmpty) {
         await DatabaseService.instance.addMediaToPlaylist(dbFilename, playlist);
      }

      _isListening = false;
      notifyListeners();
      
      onDone?.call();
      _showNotification('Canción descargada', '${track.title} - ${track.artist}');

    } catch (e) {
      _currentJob = ListenJob(
        jobId: 'local_native',
        status: ListenJobStatus.failed,
        step: 'Error',
        progress: 0,
        error: e.toString(),
      );
      _isListening = false;
      notifyListeners();
      onError?.call(e.toString());
      _showNotification('Error', e.toString());
    }
  }

  void cancel() {
    _isListening = false;
    _currentJob = null;
    notifyListeners();
  }

  void retry() {
    if (_lastApi != null && _lastSource != null && _lastDuration != null) {
      dismiss();
      startListening(
        api: _lastApi!,
        source: _lastSource!,
        duration: _lastDuration!,
        deviceIndex: _lastDeviceIndex,
        playlist: _lastPlaylist,
        onDone: _lastOnDone,
        onError: _lastOnError,
      );
    }
  }

  void dismiss() {
    _currentJob = null;
    notifyListeners();
  }

  void _showNotification(String title, String body) {
    if (kIsWeb) return;
    try {
      if (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux) {
        LocalNotification notification = LocalNotification(
          title: title,
          body: body,
        );
        notification.show();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    super.dispose();
  }
}
