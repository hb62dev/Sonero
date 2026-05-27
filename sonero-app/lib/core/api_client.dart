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

  Future<String> uploadAudioForListen({
    required String filePath,
    bool autoDownload = true,
    String? playlist,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/listen/upload'));
    request.fields['auto_download'] = autoDownload.toString();
    if (playlist != null) {
      request.fields['playlist'] = playlist;
    }
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    
    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
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

  Future<void> deleteTrack(String filename) async {
    final res = await http.delete(Uri.parse('$baseUrl/api/v1/downloads/$filename'));
    _check(res);
  }

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

  Future<String> autoFillMetadata(List<String> filenames) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/metadata/auto'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'filenames': filenames}),
    );
    _check(res);
    return jsonDecode(res.body)['job_id'] as String;
  }

  Future<Map<String, dynamic>> getAutofillJobStatus(String jobId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/metadata/auto/jobs/$jobId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
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

  Future<void> updatePaths({String? music, String? video}) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/settings/paths'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'music_dir': music,
        'video_dir': video,
      }),
    );
    _check(res);
  }

  // ── Downloads (library root) ─────────────────────────────────────────────

  Future<Map<String, dynamic>> getDownloads() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Search ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> getMetadata({List<String>? filenames}) async {
    final query = filenames?.map((f) => 'filenames=${Uri.encodeComponent(f)}').join('&') ?? '';
    final url = '$baseUrl/api/v1/metadata${query.isNotEmpty ? '?$query' : ''}';
    final res = await http.get(Uri.parse(url));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<Map<String, dynamic>> getLyrics(String title, String artist) async {
    final uri = Uri.parse('$baseUrl/api/v1/metadata/lyrics').replace(
      queryParameters: {
        'title': title,
        'artist': artist,
      },
    );
    final res = await http.get(uri);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> saveLyrics({
    required String filename,
    required String title,
    String artist = '',
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/metadata/lyrics/save').replace(
      queryParameters: {
        'filename': filename,
        'title': title,
        'artist': artist,
      },
    );
    final res = await http.post(uri);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> searchOnline(String query, {int limit = 20}) async {
    final encodedQuery = Uri.encodeQueryComponent(query);
    final res = await http.get(Uri.parse('$baseUrl/api/v1/search?q=$encodedQuery&limit=$limit'))
        .timeout(const Duration(seconds: 30));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  // ── Video Downloads ────────────────────────────────────────────────────────
  
  Future<Map<String, dynamic>> getVideoInfo(String url) async {
    final encodedUrl = Uri.encodeQueryComponent(url);
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/video/info?url=$encodedUrl'))
        .timeout(const Duration(seconds: 25));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> downloadVideo(String url, String formatId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/downloads/video'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'url': url,
        'format_id': formatId,
      }),
    ).timeout(const Duration(minutes: 5));
    _check(res);
    return jsonDecode(res.body)['job_id'] as String;
  }

  Future<String> downloadMp3Direct({
    required String url,
    required String title,
    String artist = '',
    String? playlist,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/downloads/mp3'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'url': url,
        'title': title,
        'artist': artist,
        if (playlist != null) 'playlist': playlist,
      }),
    ).timeout(const Duration(minutes: 5));
    _check(res);
    return jsonDecode(res.body)['job_id'] as String;
  }

  Future<Map<String, dynamic>> getVideoJobStatus(String jobId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/video/jobs/$jobId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getAllVideoJobs() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/video/jobs'));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<void> pauseVideoJob(String jobId) async {
    final res = await http.post(Uri.parse('$baseUrl/api/v1/downloads/video/jobs/$jobId/pause'));
    _check(res);
  }

  Future<void> resumeVideoJob(String jobId) async {
    final res = await http.post(Uri.parse('$baseUrl/api/v1/downloads/video/jobs/$jobId/resume'));
    _check(res);
  }

  // ── Devices ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDevices() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/devices'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Settings & Cookies ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> syncBenrioCookies() async {
    final res = await http.post(Uri.parse('$baseUrl/api/v1/settings/cookies/benrio'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> uploadCookies(String filePath) async {
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/settings/cookies/upload'));
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
    _check(res);
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

  // ── Smart Music Endpoints ──────────────────────────────────────────────────

  Future<void> saveGeminiKey(String apiKey) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/settings/gemini-key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'api_key': apiKey}),
    );
    _check(res);
  }

  Future<Map<String, dynamic>> getActiveFocusSession(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/smart/focus/session/active?user_id=$userId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> startFocusSession(String userId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/smart/focus/session/start'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> endFocusSession(int sessionId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/smart/focus/session/end'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'session_id': sessionId}),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getOptimalBpm(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/smart/focus/bpm-optimum?user_id=$userId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getCurrentMood(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/smart/mood/current?user_id=$userId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getIsoPrincipleQueue(String userId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/smart/mood/iso-principle'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getWeeklyProductivityReport(String userId) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/smart/gemini/weekly-report'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'user_id': userId}),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getPlaybackHistory() async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/analytics/history'));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  // ── Authentication Endpoints ───────────────────────────────────────────────

  Future<Map<String, dynamic>> register(String name, String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email,
        'password': password,
      }),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
      }),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> googleAuth(String idToken) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/auth/google'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'id_token': idToken,
      }),
    );
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
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
