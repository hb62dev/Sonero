import 'dart:convert';
import 'package:http/http.dart' as http;

/// What a connected TV reports it is playing.
class TvNowPlaying {
  final String? trackId;
  final String title;
  final String artist;
  final bool playing;
  final double position;
  final double duration;
  final double volume;
  final bool shuffle;

  const TvNowPlaying({
    required this.trackId,
    required this.title,
    required this.artist,
    required this.playing,
    required this.position,
    required this.duration,
    required this.volume,
    required this.shuffle,
  });

  factory TvNowPlaying.fromJson(Map<String, dynamic> j) => TvNowPlaying(
        trackId: j['track_id'] as String?,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        playing: j['playing'] as bool? ?? false,
        position: (j['position'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        volume: (j['volume'] as num?)?.toDouble() ?? 1,
        shuffle: j['shuffle'] as bool? ?? false,
      );
}

class TvDevice {
  final String id;
  final String name;
  /// "tv" (Sonero TV app) or "remote" (phone remote page)
  final String kind;
  final bool online;
  final TvNowPlaying? nowPlaying;
  final String? pairedAt;
  final String? lastSeen;

  const TvDevice({
    required this.id,
    required this.name,
    this.kind = 'tv',
    this.online = false,
    this.nowPlaying,
    this.pairedAt,
    this.lastSeen,
  });

  bool get isTv => kind == 'tv';

  factory TvDevice.fromJson(Map<String, dynamic> j) => TvDevice(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Android TV',
        kind: j['kind'] as String? ?? 'tv',
        online: j['online'] as bool? ?? false,
        nowPlaying: j['now_playing'] == null
            ? null
            : TvNowPlaying.fromJson(j['now_playing'] as Map<String, dynamic>),
        pairedAt: j['paired_at'] as String?,
        lastSeen: j['last_seen'] as String?,
      );
}

/// Snapshot of GET /api/v1/tv/status.
class TvStatus {
  final bool enabled;
  final bool running;
  final String? ip;
  final int port;
  final String serverName;
  final String? pin;
  final int pinExpiresIn;
  final List<TvDevice> devices;

  const TvStatus({
    required this.enabled,
    required this.running,
    required this.ip,
    required this.port,
    required this.serverName,
    required this.pin,
    required this.pinExpiresIn,
    required this.devices,
  });

  factory TvStatus.fromJson(Map<String, dynamic> j) {
    final pairing = j['pairing'] as Map<String, dynamic>?;
    return TvStatus(
      enabled: j['enabled'] as bool? ?? false,
      running: j['running'] as bool? ?? false,
      ip: j['ip'] as String?,
      port: (j['port'] as num?)?.toInt() ?? 8091,
      serverName: j['server_name'] as String? ?? '',
      pin: pairing?['pin'] as String?,
      pinExpiresIn: (pairing?['expires_in'] as num?)?.toInt() ?? 0,
      devices: ((j['devices'] as List?) ?? const [])
          .map((e) => TvDevice.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Controls the backend's Sonero TV server (sonero-api/routers/tv.py).
class TvBackend {
  final String baseUrl;
  TvBackend(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1/tv$path');

  TvStatus _decode(http.Response res) {
    if (res.statusCode >= 400) {
      String message = res.body;
      try {
        message = (jsonDecode(res.body) as Map<String, dynamic>)['detail']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
    return TvStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<TvStatus> status() async => _decode(await http.get(_uri('/status')).timeout(const Duration(seconds: 5)));

  Future<TvStatus> setEnabled(bool enabled) async => _decode(await http
      .put(_uri('/enabled'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'enabled': enabled}))
      .timeout(const Duration(seconds: 10)));

  Future<TvStatus> startPairing() async => _decode(await http.post(_uri('/pairing')));

  Future<TvStatus> cancelPairing() async => _decode(await http.delete(_uri('/pairing')));

  Future<TvStatus> revoke(String deviceId) async => _decode(await http.delete(_uri('/devices/$deviceId')));

  /// Sends a command to a connected TV: play (with library [filenames]),
  /// pause, resume, toggle, next, previous, seek, volume, shuffle, stop.
  Future<void> command(String deviceId, String action, {
    List<String>? filenames,
    int index = 0,
    double? position,
    double? value,
    bool? shuffle,
  }) async {
    final res = await http
        .post(
          _uri('/devices/$deviceId/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'action': action,
            if (filenames != null) 'filenames': filenames,
            'index': index,
            if (position != null) 'position': position,
            if (value != null) 'value': value,
            if (shuffle != null) 'shuffle': shuffle,
          }),
        )
        .timeout(const Duration(seconds: 10));
    if (res.statusCode >= 400) {
      String message = res.body;
      try {
        message = (jsonDecode(res.body) as Map<String, dynamic>)['detail']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
  }
}
