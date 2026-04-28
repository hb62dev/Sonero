import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiClient {
  final String baseUrl;

  ApiClient({required this.baseUrl});

  // ── Listen pipeline ──────────────────────────────────────────────────────

  Future<String> startListening({
    int duration = 10,
    bool autoDownload = true,
    String source = 'mic',
    int? deviceIndex,
    String? playlist,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/listen'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'duration': duration,
        'auto_download': autoDownload,
        'source': source,
        if (deviceIndex != null) 'device_index': deviceIndex,
        if (playlist != null) 'playlist': playlist,
      }),
    );
    _check(res);
    return jsonDecode(res.body)['job_id'] as String;
  }

  Future<Map<String, dynamic>> getJobStatus(String jobId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/listen/jobs/$jobId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Playlists ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPlaylists() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/playlists'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> createPlaylist(String name) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/playlists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    _check(res);
  }

  Future<void> renamePlaylist(String oldName, String newName) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/v1/playlists/rename'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'old_name': oldName, 'new_name': newName}),
    );
    _check(res);
  }

  Future<void> deletePlaylist(String name) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/v1/playlists/$name'));
    _check(res);
  }

  Future<Map<String, dynamic>> getPlaylistTracks(String name) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/playlists/$name/tracks'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Tracks ───────────────────────────────────────────────────────────────

  Future<void> moveTrack({
    required String filename,
    String? fromPlaylist,
    String? toPlaylist,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/tracks/move'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'filename': filename,
        'from_playlist': fromPlaylist,
        'to_playlist': toPlaylist,
      }),
    );
    _check(res);
  }

  Future<void> autoFillMetadata(List<String> filenames) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/metadata/auto'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'filenames': filenames}),
    );
    _check(res);
  }

  Future<Map<String, dynamic>?> getTrackMetadata(String filename) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/metadata?filenames=$filename'));
    _check(res);
    final list = jsonDecode(res.body) as List;
    if (list.isNotEmpty) {
      return list.first as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> updateTrackMetadata(Map<String, dynamic> update) async {
    final res = await http.patch(
      Uri.parse('$baseUrl/api/v1/metadata'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'updates': [update]}),
    );
    _check(res);
  }

  // ── Downloads (library root) ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getDownloads() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Devices ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDevices() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/devices'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Health ───────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/health')).timeout(
            const Duration(seconds: 3),
          );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void _check(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      final body = jsonDecode(res.body);
      throw ApiException(
        statusCode: res.statusCode,
        message: body['detail']?.toString() ?? 'Unknown error',
      );
    }
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException({required this.statusCode, required this.message});

  @override
  String toString() => 'ApiException($statusCode): $message';
}
