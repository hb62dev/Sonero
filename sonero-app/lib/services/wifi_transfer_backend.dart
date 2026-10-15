import 'dart:convert';
import 'package:http/http.dart' as http;
import 'wifi_transfer_service.dart' show TransferProgress;

/// Snapshot of GET /api/v1/transfer/status.
class BackendTransferStatus {
  final bool receiving;
  final bool sending;
  final String? ip;
  final List<String> ips;
  final int port;
  final String? uploadUrl;
  final List<TransferProgress> receive;
  final List<TransferProgress> send;

  const BackendTransferStatus({
    required this.receiving,
    required this.sending,
    required this.ip,
    required this.ips,
    required this.port,
    required this.uploadUrl,
    required this.receive,
    required this.send,
  });

  factory BackendTransferStatus.fromJson(Map<String, dynamic> json) {
    List<TransferProgress> items(String key) => ((json[key] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .map((e) => TransferProgress(
              filename: e['filename'] as String? ?? '',
              progress: (e['progress'] as num?)?.toInt() ?? 0,
              status: e['status'] as String? ?? 'preparing',
              error: e['error'] as String?,
              duplicate: e['duplicate'] as bool? ?? false,
            ))
        .toList();

    return BackendTransferStatus(
      receiving: json['receiving'] as bool? ?? false,
      sending: json['sending'] as bool? ?? false,
      ip: json['ip'] as String?,
      ips: ((json['ips'] as List?) ?? const []).cast<String>(),
      port: (json['port'] as num?)?.toInt() ?? 8090,
      uploadUrl: json['upload_url'] as String?,
      receive: items('receive'),
      send: items('send'),
    );
  }
}

/// WiFi transfer driven by the Python backend (Windows/macOS desktop and web).
///
/// The backend owns the receiver on port 8090 and reads/writes the music
/// folder directly, so this works even where the Flutter app can't open
/// sockets or touch the filesystem (web).
class WifiTransferBackend {
  final String baseUrl;
  WifiTransferBackend(this.baseUrl);

  Uri _uri(String path) => Uri.parse('$baseUrl/api/v1/transfer$path');

  Future<BackendTransferStatus> _decode(http.Response res) async {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      String message = res.body;
      try {
        message = (jsonDecode(res.body) as Map<String, dynamic>)['detail']?.toString() ?? message;
      } catch (_) {}
      throw Exception(message);
    }
    return BackendTransferStatus.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<BackendTransferStatus> status() async =>
      _decode(await http.get(_uri('/status')).timeout(const Duration(seconds: 5)));

  Future<BackendTransferStatus> startReceiving() async =>
      _decode(await http.post(_uri('/receive/start')).timeout(const Duration(seconds: 10)));

  Future<BackendTransferStatus> stopReceiving() async =>
      _decode(await http.post(_uri('/receive/stop')).timeout(const Duration(seconds: 10)));

  Future<BackendTransferStatus> clearFinished() async =>
      _decode(await http.post(_uri('/clear')).timeout(const Duration(seconds: 5)));

  /// [files] entries need `source` (library filename) plus optional metadata.
  Future<BackendTransferStatus> send({
    required String targetIp,
    required List<Map<String, dynamic>> files,
  }) async {
    final body = jsonEncode({
      'target_ip': targetIp,
      'files': files
          .map((f) => {
                'filename': f['source'] ?? f['filename'],
                'title': f['title'] ?? '',
                'artist': f['artist'] ?? '',
                'album': f['album'] ?? '',
                'genre': f['genre'] ?? '',
                'year': f['year'] ?? '',
              })
          .toList(),
    });
    return _decode(await http
        .post(_uri('/send'), headers: {'Content-Type': 'application/json'}, body: body)
        .timeout(const Duration(seconds: 10)));
  }
}
