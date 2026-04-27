import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/listen_job.dart';

class ListenProvider extends ChangeNotifier {
  ListenJob? _currentJob;
  bool _isListening = false;
  Timer? _pollTimer;

  ListenJob? get currentJob => _currentJob;
  bool get isListening => _isListening;

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

    _isListening = true;
    _currentJob = null;
    notifyListeners();

    try {
      final jobId = await api.startListening(
        duration: duration,
        autoDownload: true,
        source: source,
        deviceIndex: deviceIndex,
        playlist: playlist,
      );

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
          } else if (_currentJob!.isFailed) {
            _stopPolling();
            _isListening = false;
            notifyListeners();
            onError?.call(_currentJob?.error ?? 'Error desconocido');
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

  void dismiss() {
    _currentJob = null;
    notifyListeners();
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
