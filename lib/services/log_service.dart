import 'package:flutter/services.dart';

class LogService {
  static final List<String> _logs = [];

  static void log(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$timestamp] $msg';
    _logs.add(line);
    if (_logs.length > 200) {
      _logs.removeAt(0);
    }
    // Also print to console
    print('[SoneroLog] $line');
  }

  static List<String> getLogs() {
    return List.unmodifiable(_logs);
  }

  static void clear() {
    _logs.clear();
  }
}
