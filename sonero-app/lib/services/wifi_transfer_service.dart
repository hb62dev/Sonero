import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';
import 'log_service.dart';
import '../providers/settings_provider.dart';

class TransferProgress {
  final String filename;
  final int progress; // 0 to 100
  final String status; // 'preparing', 'transferring', 'done', 'failed'
  final String? error;

  TransferProgress({
    required this.filename,
    required this.progress,
    required this.status,
    this.error,
  });
}

class WifiTransferService {
  static final WifiTransferService instance = WifiTransferService._();
  WifiTransferService._();

  HttpServer? _server;
  final StreamController<TransferProgress> _receiveProgress = StreamController<TransferProgress>.broadcast();
  final StreamController<TransferProgress> _sendProgress = StreamController<TransferProgress>.broadcast();

  Stream<TransferProgress> get receiveProgressStream => _receiveProgress.stream;
  Stream<TransferProgress> get sendProgressStream => _sendProgress.stream;

  bool get isServerRunning => _server != null;

  /// Retrieves the active local IPv4 address.
  Future<String?> getLocalIpAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback &&
              (addr.address.startsWith('192.168.') ||
               addr.address.startsWith('10.') ||
               addr.address.startsWith('172.'))) {
            return addr.address;
          }
        }
      }
      // Fallback to first non-loopback
      for (var interface in interfaces) {
        for (var addr in interface.addresses) {
          if (!addr.isLoopback) return addr.address;
        }
      }
    } catch (e) {
      LogService.log('[WifiTransfer] Error determining local IP: $e');
    }
    return null;
  }

  /// Starts the receiving HttpServer on port 8090.
  Future<void> startServer({
    required String musicFolder,
    required String videoFolder,
    required Function() onUpdate,
  }) async {
    if (_server != null) return;

    try {
      final ip = await getLocalIpAddress();
      if (ip == null) {
        throw Exception('No se pudo encontrar una interfaz de red local válida.');
      }

      _server = await HttpServer.bind(InternetAddress.anyIPv4, 8090);
      LogService.log('[WifiTransfer] Servidor iniciado en http://$ip:8090');
      onUpdate();

      final Map<String, Map<String, dynamic>> pendingUploads = {};

      _server!.listen((HttpRequest request) async {
        // CORS Headers
        request.response.headers.add('Access-Control-Allow-Origin', '*');
        request.response.headers.add('Access-Control-Allow-Methods', 'POST, OPTIONS');
        request.response.headers.add('Access-Control-Allow-Headers', '*');

        if (request.method == 'OPTIONS') {
          request.response.statusCode = HttpStatus.ok;
          await request.response.close();
          return;
        }

        // 1. Prepare endpoint
        if (request.method == 'POST' && request.uri.path == '/prepare') {
          try {
            final body = await utf8.decoder.bind(request).join();
            final data = jsonDecode(body) as Map<String, dynamic>;
            final filename = data['filename'] as String;
            final type = data['type'] as String; // 'music', 'video', 'cover'
            final playlist = data['playlist'] as String?;
            final size = data['size'] as int;
            final title = data['title'] as String? ?? '';
            final artist = data['artist'] as String? ?? '';
            final album = data['album'] as String? ?? '';
            final genre = data['genre'] as String? ?? '';
            final year = data['year'] as String? ?? '';
            final coverUrl = data['cover_url'] as String?;

            pendingUploads[filename] = {
              'type': type,
              'playlist': playlist,
              'size': size,
              'title': title,
              'artist': artist,
              'album': album,
              'genre': genre,
              'year': year,
              'cover_url': coverUrl,
            };

            LogService.log('[WifiTransfer] Preparando transferencia de $filename (${(size / 1024 / 1024).toStringAsFixed(2)} MB)');
            request.response.statusCode = HttpStatus.ok;
            request.response.write(jsonEncode({'status': 'ready'}));
            await request.response.close();
          } catch (e) {
            LogService.log('[WifiTransfer] Error en /prepare: $e');
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write(jsonEncode({'error': e.toString()}));
            await request.response.close();
          }
          return;
        }

        // 2. Upload endpoint
        if (request.method == 'POST' && request.uri.path == '/upload') {
          final filename = request.uri.queryParameters['filename'];
          if (filename == null || !pendingUploads.containsKey(filename)) {
            LogService.log('[WifiTransfer] Error: Subida no preparada o nombre de archivo faltante: $filename');
            request.response.statusCode = HttpStatus.badRequest;
            request.response.write(jsonEncode({'error': 'Subida no preparada.'}));
            await request.response.close();
            return;
          }

          final uploadInfo = pendingUploads.remove(filename)!;
          final type = uploadInfo['type'] as String;
          final playlist = uploadInfo['playlist'] as String?;
          final size = uploadInfo['size'] as int;
          final title = uploadInfo['title'] as String? ?? '';
          final artist = uploadInfo['artist'] as String? ?? '';
          final album = uploadInfo['album'] as String? ?? '';
          final genre = uploadInfo['genre'] as String? ?? '';
          final year = uploadInfo['year'] as String? ?? '';
          final coverUrl = uploadInfo['cover_url'] as String?;

          _receiveProgress.add(TransferProgress(
            filename: filename,
            progress: 0,
            status: 'transferring',
          ));
          onUpdate();

          try {
            String targetPath;
            if (type == 'music') {
              final destDir = playlist != null && playlist.isNotEmpty
                  ? Directory(p.join(musicFolder, playlist))
                  : Directory(musicFolder);
              if (!await destDir.exists()) await destDir.create(recursive: true);
              targetPath = p.join(destDir.path, filename);
            } else if (type == 'video') {
              final destDir = Directory(videoFolder);
              if (!await destDir.exists()) await destDir.create(recursive: true);
              targetPath = p.join(destDir.path, filename);
            } else if (type == 'cover') {
              final supportDir = await getApplicationSupportDirectory();
              final coversDir = Directory(p.join(supportDir.path, 'covers'));
              if (!await coversDir.exists()) await coversDir.create(recursive: true);
              targetPath = p.join(coversDir.path, filename);
            } else {
              throw Exception('Tipo de subida no soportado: $type');
            }

            final file = File(targetPath);
            final sink = file.openWrite();

            int received = 0;
            request.listen(
              (data) {
                sink.add(data);
                received += data.length;
                final progress = size > 0 ? (received / size * 100).toInt() : 0;
                _receiveProgress.add(TransferProgress(
                  filename: filename,
                  progress: progress.clamp(0, 100),
                  status: 'transferring',
                ));
              },
              onDone: () async {
                await sink.flush();
                await sink.close();

                // Register file in DB
                if (type == 'music') {
                  final relativeFilename = playlist != null && playlist.isNotEmpty
                      ? p.join(playlist, filename)
                      : filename;

                  String? dbCoverUrl;
                  if (coverUrl != null && coverUrl.isNotEmpty) {
                    final expectedCoverFile = File(p.join(
                      (await getApplicationSupportDirectory()).path, 'covers', coverUrl
                    ));
                    if (expectedCoverFile.existsSync()) {
                      dbCoverUrl = expectedCoverFile.path.replaceAll('\\', '/');
                    }
                  }

                  await DatabaseService.instance.insertMedia({
                    'type': 'music',
                    'title': title.isNotEmpty ? title : p.basenameWithoutExtension(filename),
                    'artist': artist,
                    'album': album,
                    'genre': genre,
                    'year': year,
                    'filename': relativeFilename,
                    'format': 'mp3',
                    'cover_url': dbCoverUrl,
                  });

                  if (playlist != null && playlist.isNotEmpty) {
                    await DatabaseService.instance.addMediaToPlaylist(relativeFilename, playlist);
                  }

                  // Automatically download lyrics for the received song if online
                  try {
                    final settings = SettingsProvider();
                    await settings.load();
                    await settings.api.saveLyrics(
                      filename: relativeFilename,
                      title: title.isNotEmpty ? title : p.basenameWithoutExtension(filename),
                      artist: artist,
                    );
                  } catch (e) {
                    LogService.log('[WifiTransfer] Omitiendo descarga inmediata de letras (dispositivo offline o error): $e');
                  }
                } else if (type == 'video') {
                  final relativeFilename = p.join('videos', filename);
                  await DatabaseService.instance.insertMedia({
                    'type': 'video',
                    'title': title.isNotEmpty ? title : p.basenameWithoutExtension(filename),
                    'artist': artist,
                    'filename': relativeFilename,
                    'format': 'mp4',
                  });
                }

                LogService.log('[WifiTransfer] Archivo guardado con éxito: $filename');
                _receiveProgress.add(TransferProgress(
                  filename: filename,
                  progress: 100,
                  status: 'done',
                ));

                request.response.statusCode = HttpStatus.ok;
                request.response.write(jsonEncode({'status': 'success'}));
                await request.response.close();
                onUpdate();
              },
              onError: (e) async {
                await sink.close();
                LogService.log('[WifiTransfer] Error recibiendo bytes: $e');
                _receiveProgress.add(TransferProgress(
                  filename: filename,
                  progress: 0,
                  status: 'failed',
                  error: e.toString(),
                ));
                request.response.statusCode = HttpStatus.internalServerError;
                request.response.write(jsonEncode({'error': e.toString()}));
                await request.response.close();
                onUpdate();
              },
              cancelOnError: true,
            );
          } catch (e) {
            LogService.log('[WifiTransfer] Error procesando archivo: $e');
            _receiveProgress.add(TransferProgress(
              filename: filename,
              progress: 0,
              status: 'failed',
              error: e.toString(),
            ));
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write(jsonEncode({'error': e.toString()}));
            await request.response.close();
            onUpdate();
          }
          return;
        }

        // Not Found fallback
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      });
    } catch (e) {
      LogService.log('[WifiTransfer] Error iniciando el servidor: $e');
      _server = null;
      rethrow;
    }
  }

  /// Stops the receiving HttpServer.
  Future<void> stopServer(Function() onUpdate) async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      LogService.log('[WifiTransfer] Servidor de transferencia apagado.');
      onUpdate();
    }
  }

  /// Sends a list of files sequentially to the target IP address.
  Future<void> sendFiles({
    required String targetIp,
    required List<Map<String, dynamic>> files,
    required Function() onUpdate,
  }) async {
    final dio = Dio();

    for (var fileInfo in files) {
      final filePath = fileInfo['filePath'] as String;
      final type = fileInfo['type'] as String;
      final filename = fileInfo['filename'] as String;
      final playlist = fileInfo['playlist'] as String?;
      final title = fileInfo['title'] as String? ?? '';
      final artist = fileInfo['artist'] as String? ?? '';
      final album = fileInfo['album'] as String? ?? '';
      final genre = fileInfo['genre'] as String? ?? '';
      final year = fileInfo['year'] as String? ?? '';
      final coverUrl = fileInfo['cover_url'] as String?;

      final file = File(filePath);
      if (!file.existsSync()) {
        LogService.log('[WifiTransfer] El archivo local no existe para enviar: $filePath');
        continue;
      }
      final size = file.lengthSync();

      _sendProgress.add(TransferProgress(
        filename: filename,
        progress: 0,
        status: 'preparing',
      ));
      onUpdate();

      try {
        // 1. Prepare target
        final prepareRes = await dio.post(
          'http://$targetIp:8090/prepare',
          data: {
            'filename': filename,
            'type': type,
            'playlist': playlist,
            'size': size,
            'title': title,
            'artist': artist,
            'album': album,
            'genre': genre,
            'year': year,
            'cover_url': coverUrl,
          },
        );

        if (prepareRes.statusCode != 200) {
          throw Exception('La preparación de transferencia falló: ${prepareRes.data}');
        }

        // 2. Stream raw file bytes via POST
        _sendProgress.add(TransferProgress(
          filename: filename,
          progress: 0,
          status: 'transferring',
        ));
        onUpdate();

        final stream = file.openRead();
        await dio.post(
          'http://$targetIp:8090/upload?filename=${Uri.encodeComponent(filename)}',
          data: stream,
          options: Options(
            headers: {
              Headers.contentTypeHeader: 'application/octet-stream',
              Headers.contentLengthHeader: size,
            },
          ),
          onSendProgress: (sent, total) {
            final progress = total > 0 ? (sent / total * 100).toInt() : 0;
            _sendProgress.add(TransferProgress(
              filename: filename,
              progress: progress.clamp(0, 100),
              status: 'transferring',
            ));
            onUpdate();
          },
        );

        _sendProgress.add(TransferProgress(
          filename: filename,
          progress: 100,
          status: 'done',
        ));
        onUpdate();
      } catch (e) {
        LogService.log('[WifiTransfer] Error enviando archivo $filename: $e');
        _sendProgress.add(TransferProgress(
          filename: filename,
          progress: 0,
          status: 'failed',
          error: e.toString(),
        ));
        onUpdate();
      }
    }
  }
}
