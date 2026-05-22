import 'database_service.dart';

class LogService {
  static void log(String msg) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    final line = '[$timestamp] $msg';
    // Print to console
    print('[SoneroLog] $line');

    // Fire and forget database write
    DatabaseService.instance.insertLog(timestamp, msg).catchError((e) {
      print('[LogService] SQLite write error: $e');
      return -1;
    });
  }

  static Future<List<String>> getLogs() async {
    try {
      final rows = await DatabaseService.instance.getLogs();
      // Reverse to get chronological order (oldest to newest) since database query returned newest first (id DESC)
      return rows.reversed.map((row) {
        final ts = row['timestamp'] ?? '';
        final msg = row['message'] ?? '';
        return '[$ts] $msg';
      }).toList();
    } catch (e) {
      print('[LogService] SQLite read error: $e');
      return ['Error reading logs: $e'];
    }
  }

  static Future<void> clear() async {
    try {
      await DatabaseService.instance.clearLogs();
    } catch (e) {
      print('[LogService] SQLite clear error: $e');
    }
  }
}

