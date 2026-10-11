import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// UDP port where the Sonero backend answers discovery broadcasts
/// (sonero-api: settings.TV_DISCOVERY_PORT).
const discoveryPort = 8092;
const defaultTvPort = 8091;

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);

  bool get unauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// A Sonero computer found on the network.
class SoneroServer {
  final String host;
  final int port;
  final String name;

  const SoneroServer({required this.host, required this.port, required this.name});

  Uri uri(String path, [Map<String, String>? query]) =>
      Uri(scheme: 'http', host: host, port: port, path: path, queryParameters: query);
}

class Track {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final String playlist;
  final double? duration;
  final bool hasCover;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.genre,
    required this.playlist,
    required this.duration,
    required this.hasCover,
  });

  factory Track.fromJson(Map<String, dynamic> j) => Track(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        genre: j['genre'] as String? ?? '',
        playlist: j['playlist'] as String? ?? '',
        duration: (j['duration'] as num?)?.toDouble(),
        hasCover: j['has_cover'] as bool? ?? false,
      );
}

class Library {
  final String serverName;
  final List<Track> tracks;
  final List<({String name, int count})> playlists;

  const Library({required this.serverName, required this.tracks, required this.playlists});
}

/// Finds Sonero servers by broadcasting "SONERO_DISCOVER" on the local network.
Future<List<SoneroServer>> discoverServers({Duration timeout = const Duration(seconds: 3)}) async {
  final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
  socket.broadcastEnabled = true;
  final found = <String, SoneroServer>{};

  final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
  try {
    for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
      for (final addr in iface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length == 4 && !addr.isLoopback) {
          // Assume a /24 home network for the directed broadcast
          targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    }
  } catch (_) {}

  final sub = socket.listen((event) {
    if (event != RawSocketEvent.read) return;
    final dg = socket.receive();
    if (dg == null) return;
    try {
      final data = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
      if (data['app'] != 'sonero') return;
      final host = dg.address.address;
      found[host] = SoneroServer(
        host: host,
        port: (data['port'] as num?)?.toInt() ?? defaultTvPort,
        name: data['name'] as String? ?? host,
      );
    } catch (_) {}
  });

  final message = utf8.encode('SONERO_DISCOVER');
  // Send a few times: UDP broadcasts are easily dropped on WiFi
  for (var i = 0; i < 3; i++) {
    for (final target in targets) {
      try {
        socket.send(message, target, discoveryPort);
      } catch (_) {}
    }
    await Future.delayed(timeout ~/ 3);
  }

  await sub.cancel();
  socket.close();
  return found.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

/// Talks to the Sonero TV API (sonero-api/services/tv_server.py).
class SoneroApi {
  final SoneroServer server;
  final String? token;
  final http.Client _client = http.Client();

  SoneroApi(this.server, {this.token});

  Map<String, String> get authHeaders => token == null ? {} : {'Authorization': 'Bearer $token'};

  Uri streamUri(Track t) => server.uri('/tv/stream/${t.id}');
  Uri coverUri(Track t) => server.uri('/tv/cover/${t.id}');

  Future<Map<String, dynamic>> _json(Future<http.Response> request) async {
    final http.Response res;
    try {
      res = await request.timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw ApiException('Sonero no responde en ${server.host}. ¿Está encendida la computadora?');
    } on SocketException {
      throw ApiException('No se pudo conectar con ${server.host}. Revisa que ambos estén en la misma red WiFi.');
    }
    Map<String, dynamic> body = {};
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {}
    if (res.statusCode >= 400) {
      throw ApiException(body['detail']?.toString() ?? 'Error ${res.statusCode}', res.statusCode);
    }
    return body;
  }

  /// Checks that [server] is a Sonero server (used for manual IP entry).
  static Future<SoneroServer> probe(String host, {int port = defaultTvPort}) async {
    final candidate = SoneroServer(host: host, port: port, name: host);
    final body = await SoneroApi(candidate)._json(http.get(candidate.uri('/tv/info')));
    if (body['app'] != 'sonero') throw ApiException('$host no es un servidor de Sonero.');
    return SoneroServer(host: host, port: port, name: body['name'] as String? ?? host);
  }

  Future<String> pair(String pin, String deviceName) async {
    final body = await _json(http.post(
      server.uri('/tv/pair'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'pin': pin, 'device_name': deviceName}),
    ));
    return body['token'] as String;
  }

  Future<Library> library() async {
    final body = await _json(_client.get(server.uri('/tv/library'), headers: authHeaders));
    return Library(
      serverName: body['server_name'] as String? ?? server.name,
      tracks: ((body['tracks'] as List?) ?? const [])
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList(),
      playlists: ((body['playlists'] as List?) ?? const [])
          .map((e) => (name: e['name'] as String, count: (e['count'] as num).toInt()))
          .toList(),
    );
  }

  Uri get controlUri => Uri(scheme: 'ws', host: server.host, port: server.port, path: '/tv/ws');

  /// Lyrics saved on the computer (.lrc). Null when the song has none.
  Future<Lyrics?> lyrics(Track t) async {
    try {
      final body = await _json(_client.get(server.uri('/tv/lyrics/${t.id}'), headers: authHeaders));
      final text = body['lyrics'] as String?;
      return text == null || text.trim().isEmpty ? null : Lyrics.parse(text);
    } catch (_) {
      return null;
    }
  }

  Future<void> ping() => _json(_client.get(server.uri('/tv/ping'), headers: authHeaders));

  Future<Map<String, dynamic>> stats({int days = 30}) =>
      _json(_client.get(server.uri('/tv/stats', {'days': '$days'}), headers: authHeaders));

  /// Counts a play in Sonero's statistics. Best effort: never throws.
  Future<void> reportPlayed(Track t, double seconds, bool completed) async {
    if (seconds < 1) return;
    try {
      await _client
          .post(
            server.uri('/tv/played'),
            headers: {...authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode({'id': t.id, 'seconds': seconds, 'completed': completed}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

/// Remembers the paired server between launches.
class ConnectionStore {
  static const _host = 'server_host', _port = 'server_port', _name = 'server_name', _token = 'token';

  static Future<SoneroApi?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_host);
    final token = prefs.getString(_token);
    if (host == null || token == null) return null;
    final server = SoneroServer(
      host: host,
      port: prefs.getInt(_port) ?? defaultTvPort,
      name: prefs.getString(_name) ?? host,
    );
    return SoneroApi(server, token: token);
  }

  static Future<void> save(SoneroServer server, String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_host, server.host);
    await prefs.setInt(_port, server.port);
    await prefs.setString(_name, server.name);
    await prefs.setString(_token, token);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_host, _port, _name, _token]) {
      await prefs.remove(k);
    }
  }
}


/// Song lyrics; [synced] when every line has an LRC timestamp ([mm:ss.xx]).
class Lyrics {
  final List<({Duration? at, String text})> lines;
  final bool synced;

  const Lyrics(this.lines, this.synced);

  static final _stamp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');

  factory Lyrics.parse(String raw) {
    final lines = <({Duration? at, String text})>[];
    var timed = 0;
    for (final line in const LineSplitter().convert(raw)) {
      final stamps = _stamp.allMatches(line).toList();
      // Skip LRC metadata tags like [ar:Artist]
      if (stamps.isEmpty && RegExp(r'^\[[a-z]+:.*\]$').hasMatch(line.trim())) continue;
      final text = line.replaceAll(_stamp, '').trim();
      if (stamps.isEmpty) {
        if (text.isNotEmpty) lines.add((at: null, text: text));
        continue;
      }
      for (final m in stamps) {
        final ms = (int.parse(m.group(1)!) * 60 + double.parse(m.group(2)!)) * 1000;
        lines.add((at: Duration(milliseconds: ms.round()), text: text));
        timed++;
      }
    }
    final synced = timed > 0 && timed >= lines.length * 0.8;
    if (synced) {
      lines.removeWhere((l) => l.at == null);
      lines.sort((a, b) => a.at!.compareTo(b.at!));
    }
    return Lyrics(lines, synced);
  }

  /// Index of the line being sung at [position] (synced lyrics only).
  int indexAt(Duration position) {
    if (!synced) return -1;
    var i = -1;
    for (var j = 0; j < lines.length && lines[j].at! <= position; j++) {
      i = j;
    }
    return i;
  }
}
