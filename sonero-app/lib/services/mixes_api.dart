import 'dart:convert';
import 'package:http/http.dart' as http;

/// A song in a mix: a library file, or an online track (with a 30 s preview).
class MixItem {
  final int id;
  final bool inLibrary;
  final String? filename;
  final String title;
  final String artist;
  final String? album;
  final String? coverUrl;
  final String? previewUrl;
  final String? note;

  /// The user's verdict: [like], [meh], [dislike], or null if not rated. Applies to every mix.
  final int? rating;

  static const like = 1;
  static const meh = 0;
  static const dislike = -1;

  const MixItem({
    required this.id,
    required this.inLibrary,
    required this.title,
    required this.artist,
    this.filename,
    this.album,
    this.coverUrl,
    this.previewUrl,
    this.note,
    this.rating,
  });

  MixItem withRating(int? value) => MixItem(
        id: id,
        inLibrary: inLibrary,
        title: title,
        artist: artist,
        filename: filename,
        album: album,
        coverUrl: coverUrl,
        previewUrl: previewUrl,
        note: note,
        rating: value,
      );

  factory MixItem.fromJson(Map<String, dynamic> j) => MixItem(
        id: (j['id'] as num).toInt(),
        inLibrary: j['in_library'] as bool? ?? false,
        filename: j['filename'] as String?,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String?,
        coverUrl: j['cover_url'] as String?,
        previewUrl: j['preview_url'] as String?,
        note: j['note'] as String?,
        rating: (j['rating'] as num?)?.toInt(),
      );
}

/// A recommended playlist from Sonero's algorithm (source "auto") or an AI agent ("agent").
class SmartMix {
  final int id;
  final String title;
  final String? description;
  final String? reason;
  final String source;
  final String? author;
  final String? kind;
  final int count;
  final int inLibrary;
  final DateTime? updatedAt;
  final List<MixItem> items;

  const SmartMix({
    required this.id,
    required this.title,
    required this.source,
    required this.count,
    required this.inLibrary,
    this.description,
    this.reason,
    this.author,
    this.kind,
    this.updatedAt,
    this.items = const [],
  });

  bool get byAgent => source == 'agent' || source == 'ai';

  factory SmartMix.fromJson(Map<String, dynamic> j) => SmartMix(
        id: (j['id'] as num).toInt(),
        title: j['title'] as String? ?? 'Mix',
        description: j['description'] as String?,
        reason: j['reason'] as String?,
        source: j['source'] as String? ?? 'auto',
        author: j['author'] as String?,
        kind: j['kind'] as String?,
        count: (j['count'] as num?)?.toInt() ?? 0,
        inLibrary: (j['in_library'] as num?)?.toInt() ?? 0,
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal(),
        items: ((j['items'] as List?) ?? const [])
            .map((e) => MixItem.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Progress of a background library job (metadata lookup or audio analysis).
class LibraryJob {
  final bool running;
  final int done;
  final int total;
  final String? error;
  final bool available;
  final List<Map<String, dynamic>> proposals;

  const LibraryJob({
    required this.running,
    required this.done,
    required this.total,
    this.error,
    this.available = true,
    this.proposals = const [],
  });

  factory LibraryJob.fromJson(Map<String, dynamic> j) => LibraryJob(
        running: j['running'] as bool? ?? false,
        done: (j['done'] as num?)?.toInt() ?? 0,
        total: (j['total'] as num?)?.toInt() ?? 0,
        error: j['error'] as String?,
        available: j['available'] as bool? ?? true,
        proposals: ((j['proposals'] as List?) ?? const []).cast<Map<String, dynamic>>(),
      );
}

/// Client for Biblioteca → Para ti (sonero-api/routers/mixes.py).
class MixesApi {
  final String baseUrl;
  MixesApi(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1$path');

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 400) {
      String message = res.body;
      try {
        message = (jsonDecode(res.body) as Map<String, dynamic>)['detail']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<List<SmartMix>> list() async {
    final data = _decode(await http.get(_uri('/mixes')).timeout(const Duration(seconds: 15)));
    return ((data['mixes'] as List?) ?? const [])
        .map((e) => SmartMix.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<SmartMix> get(int id) async =>
      SmartMix.fromJson(_decode(await http.get(_uri('/mixes/$id')).timeout(const Duration(seconds: 15))));

  /// Rebuilds Sonero's automatic mixes; looks up related artists online when possible.
  Future<Map<String, dynamic>> generate() async =>
      _decode(await http.post(_uri('/mixes/generate')).timeout(const Duration(minutes: 2)));

  /// Curates creative, non-templated playlists using Gemini AI based on user activity.
  Future<Map<String, dynamic>> curateAi() async =>
      _decode(await http.post(_uri('/mixes/ai-curate')).timeout(const Duration(minutes: 2)));

  Future<void> delete(int id) async => _decode(await http.delete(_uri('/mixes/$id')));

  /// Downloads an online song of a mix as MP3; returns the download job id.
  Future<String> downloadItem(int mixId, int itemId) async {
    final data = _decode(await http.post(_uri('/mixes/$mixId/items/$itemId/download'))
        .timeout(const Duration(seconds: 60)));
    return data['job_id'] as String;
  }

  /// Rates a song of a mix (1 me gusta, 0 me da igual, -1 no me gusta, null to clear).
  Future<void> rate(int mixId, int itemId, int? rating) async => _decode(await http
      .put(
        _uri('/mixes/$mixId/items/$itemId/rating'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'rating': rating}),
      )
      .timeout(const Duration(seconds: 15)));

  Future<LibraryJob> enrichStart() async => LibraryJob.fromJson(_decode(await http.post(_uri('/library/enrich'))));
  Future<LibraryJob> enrichStatus() async => LibraryJob.fromJson(_decode(await http.get(_uri('/library/enrich'))));

  Future<Map<String, dynamic>> enrichApply(List<int> mediaIds) async => _decode(await http.post(
        _uri('/library/enrich/apply'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'media_ids': mediaIds}),
      ));

  Future<LibraryJob> analyzeStart() async => LibraryJob.fromJson(_decode(await http.post(_uri('/library/analyze'))));
  Future<LibraryJob> analyzeStatus() async => LibraryJob.fromJson(_decode(await http.get(_uri('/library/analyze'))));
}
