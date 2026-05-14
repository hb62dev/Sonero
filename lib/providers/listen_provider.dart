import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../core/api_client.dart';
import '../models/listen_job.dart';
import 'package:local_notifier/local_notifier.dart';

class ListenProvider extends ChangeNotifier {
  ListenJob? _currentJob;
  bool _isListening = false;
  Timer? _pollTimer;

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
    required ApiClient api,
    required String source, // 'mic' or 'system'
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
      String jobId;

      if (!kIsWeb && Platform.isAndroid && source == 'mic') {
        _currentJob = ListenJob(
          jobId: 'local',
          status: ListenJobStatus.listening,
          step: '🎙️ Escuchando...',
          progress: 10,
        );
        notifyListeners();

        final record = AudioRecorder();
        if (await record.hasPermission()) {
          final dir = await getTemporaryDirectory();
          final path = '${dir.path}/listen_temp.wav';
          
          await record.start(
            const RecordConfig(encoder: AudioEncoder.wav), 
            path: path,
          );
          
          await Future.delayed(Duration(seconds: duration));
          final finalPath = await record.stop();
          record.dispose();
          
          if (finalPath != null) {
            _currentJob = ListenJob(
              jobId: 'local',
              status: ListenJobStatus.recognizing,
              step: '⏳ Procesando audio...',
              progress: 20,
            );
            notifyListeners();

            jobId = await api.uploadAudioForListen(
              filePath: finalPath,
              autoDownload: true,
              playlist: playlist,
            );
          } else {
            throw Exception('No se pudo grabar el audio.');
          }
        } else {
          throw Exception('Permiso de micrófono denegado.');
        }
      } else {
        jobId = await api.startListening(
          duration: duration,
          autoDownload: true,
          source: source,
          deviceIndex: deviceIndex,
          playlist: playlist,
        );
      }

      // Set initial job state
      _currentJob = ListenJob(
        jobId: jobId,
        status: ListenJobStatus.pending,
        step: 'Iniciando...',
        progress: 0,
      );
      notifyListeners();

      // Poll until done or failed
      _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
        try {
          final data = await api.getJobStatus(jobId);
          _currentJob = ListenJob.fromJson(data);
          notifyListeners();

          if (_currentJob!.isDone) {
            _stopPolling();
            _isListening = false;
            notifyListeners();
            onDone?.call();
            _showNotification('Canción identificada y descargada', '${_currentJob!.step.replaceAll('✅ Listo: ', '')}');
          } else if (_currentJob!.isFailed) {
            _stopPolling();
            _isListening = false;
            notifyListeners();
            onError?.call(_currentJob?.error ?? 'Error desconocido');
            _showNotification('Error al escuchar', _currentJob?.error ?? 'Error desconocido');
          }
        } catch (e) {
          _stopPolling();
          _isListening = false;
          notifyListeners();
          onError?.call(e.toString());
        }
      });
    } catch (e) {
      _isListening = false;
      notifyListeners();
      onError?.call(e.toString());
    }
  }

  void cancel() {
    _stopPolling();
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
    // local_notifier is only supported on Desktop platforms
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

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  @override
  void dispose() {
    _stopPolling();
    super.dispose();
  }
}
