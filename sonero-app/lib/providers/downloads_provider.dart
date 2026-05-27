import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';

class DownloadsProvider extends ChangeNotifier {
  List<Map<String, dynamic>> _jobs = [];
  Timer? _timer;
  ApiClient? _api;

  List<Map<String, dynamic>> get jobs => _jobs;
  
  int get activeJobsCount => _jobs.where((j) => j['status'] == 'pending' || j['status'] == 'downloading').length;

  Future<void> pauseJob(String jobId) async {
    if (_api == null) return;
    try {
      await _api!.pauseVideoJob(jobId);
      // Let polling update the state, or manually set it to paused locally for instant feedback
      final jobIndex = _jobs.indexWhere((j) => j['job_id'] == jobId);
      if (jobIndex != -1) {
        _jobs[jobIndex]['status'] = 'paused';
        _jobs[jobIndex]['step'] = '⏸️ Pausando...';
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Failed to pause job: $e");
    }
  }

  Future<void> resumeJob(String jobId) async {
    if (_api == null) return;
    try {
      await _api!.resumeVideoJob(jobId);
      final jobIndex = _jobs.indexWhere((j) => j['job_id'] == jobId);
      if (jobIndex != -1) {
        _jobs[jobIndex]['status'] = 'pending';
        _jobs[jobIndex]['step'] = '⏳ Reanudando...';
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Failed to resume job: $e");
    }
  }

  void startPolling(ApiClient api) {
    _api = api;
    _timer?.cancel();
    _poll(api);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll(api));
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll(ApiClient api) async {
    try {
      final newJobs = await api.getAllVideoJobs();
      
      // Sort jobs by active first, then by ID or something consistent
      // Actually let's just keep them as returned, maybe reverse to show newest first
      _jobs = newJobs.cast<Map<String, dynamic>>().reversed.toList();
      notifyListeners();
    } catch (e) {
      // Handle error gracefully if API is down
      debugPrint("Failed to poll video jobs: $e");
    }
  }

  @override
  void dispose() {
    stopPolling();
    super.dispose();
  }
}
