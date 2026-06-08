import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'database_service.dart';
import 'log_service.dart';

class NativeDownloadManager {
  static final NativeDownloadManager instance = NativeDownloadManager._();
  NativeDownloadManager._();

  final List<Map<String, dynamic>> _jobs = [];
  final Map<String, StreamSubscription<List<int>>> _subscriptions = {};
  final Map<String, IOSink> _sinks = {};
  final Map<String, CancelToken> _cancelTokens = {};
  final Dio _dio = Dio();

  List<Map<String, dynamic>> getAllJobs() {
    return _jobs;
  }

  Map<String, dynamic>? getJob(String jobId) {
    return _jobs.firstWhere((j) => j['job_id'] == jobId, orElse: () => <String, dynamic>{});
  }

  Future<void> pauseJob(String jobId) async {
    final job = _jobs.firstWhere((j) => j['job_id'] == jobId, orElse: () => <String, dynamic>{});
    if (job.isNotEmpty && (job['status'] == 'pending' || job['status'] == 'downloading')) {
      final sub = _subscriptions[jobId];
      if (sub != null) {
        sub.pause();
        job['status'] = 'paused';
        job['step'] = '⏸️ Pausado';
        LogService.log('Job $jobId paused');
      }
      final cancelToken = _cancelTokens[jobId];
      if (cancelToken != null) {
        cancelToken.cancel("User paused download");
        job['status'] = 'paused';
        job['step'] = '⏸️ Pausado';
        LogService.log('Job $jobId cancelled/paused via CancelToken');
      }
    }
  }

  Future<void> resumeJob(String jobId) async {
    final job = _jobs.firstWhere((j) => j['job_id'] == jobId, orElse: () => <String, dynamic>{});
    if (job.isNotEmpty && job['status'] == 'paused') {
      final sub = _subscriptions[jobId];
      if (sub != null) {
        sub.resume();
        job['status'] = 'downloading';
        job['step'] = '⬇️ Descargando...';
        LogService.log('Job $jobId resumed');
      }
    }
  }

  Future<bool> _isDirectoryWritable(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final testFile = File(p.join(path, '.write_test_${const Uuid().v4().substring(0, 8)}'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> _getEffectiveMusicFolder(String folder) async {
    if (folder.trim().isNotEmpty) {
      try {
        final dir = Directory(folder);
        if (await dir.exists() || folder.startsWith('/') || folder.contains(':')) {
          final isWritable = await _isDirectoryWritable(folder);
          if (isWritable) {
            return folder;
          } else {
            LogService.log('Custom music folder "$folder" is NOT writable on this device.');
          }
        }
      } catch (e) {
        LogService.log('Error checking custom music folder: $e');
      }
    }
    final Directory? extDir = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final fallbackBase = extDir != null ? extDir.path : (await getApplicationDocumentsDirectory()).path;
    final fallback = p.join(fallbackBase, 'Sonero', 'Music');
    final fallbackDir = Directory(fallback);
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    LogService.log('Using fallback music folder: $fallback');
    return fallback;
  }

  Future<String> _getEffectiveVideoFolder(String folder) async {
    if (folder.trim().isNotEmpty) {
      try {
        final dir = Directory(folder);
        if (await dir.exists() || folder.startsWith('/') || folder.contains(':')) {
          final isWritable = await _isDirectoryWritable(folder);
          if (isWritable) {
            return folder;
          } else {
            LogService.log('Custom video folder "$folder" is NOT writable on this device.');
          }
        }
      } catch (e) {
        LogService.log('Error checking custom video folder: $e');
      }
    }
    final Directory? extDir = Platform.isAndroid ? await getExternalStorageDirectory() : null;
    final fallbackBase = extDir != null ? extDir.path : (await getApplicationDocumentsDirectory()).path;
    final fallback = p.join(fallbackBase, 'Sonero', 'Videos');
    final fallbackDir = Directory(fallback);
    if (!await fallbackDir.exists()) {
      await fallbackDir.create(recursive: true);
    }
    LogService.log('Using fallback video folder: $fallback');
    return fallback;
  }

  Future<void> _downloadStreamWithProgress({
    required String jobId,
    required StreamInfo streamInfo,
    required String targetPath,
    required YoutubeExplode yt,
    required Function(int progress) onProgress,
  }) async {
    final file = File(targetPath);
    final fileStream = file.openWrite();
    final completer = Completer<void>();
    final totalSize = streamInfo.size.totalBytes;
    
    int downloaded = 0;
    StreamSubscription<List<int>>? subscription;
    
    try {
      final stream = yt.videos.streamsClient.get(streamInfo);
      subscription = stream.listen(
        (data) {
          fileStream.add(data);
          downloaded += data.length;
          final progress = totalSize > 0 ? (downloaded / totalSize * 100).toInt() : 0;
          onProgress(progress);
        },
        onError: (e) {
          if (!completer.isCompleted) completer.completeError(e);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );
      
      _subscriptions[jobId] = subscription;
      await completer.future;
    } finally {
      _subscriptions.remove(jobId);
      await fileStream.flush();
      await fileStream.close();
    }
  }

  // Native MP3 download
  Future<String> downloadMp3Direct({
    required String url,
    required String title,
    required String musicFolder,
    String artist = '',
    String? playlist,
  }) async {
    final jobId = const Uuid().v4().substring(0, 8);
    LogService.log('Registered MP3 download job: $jobId for URL: $url');
    final job = {
      'job_id': jobId,
      'status': 'pending',
      'step': '⏳ Preparando descarga...',
      'progress': 0,
      'url': url,
      'is_mp3': true,
    };
    _jobs.add(job);

    // Run asynchronously
    _runMp3Download(jobId, url, title, artist, playlist, musicFolder);

    return jobId;
  }

  Future<void> _runMp3Download(
    String jobId,
    String url,
    String title,
    String artist,
    String? playlist,
    String musicFolder,
  ) async {
    final job = _jobs.firstWhere((j) => j['job_id'] == jobId);
    final yt = YoutubeExplode();
    LogService.log('[_runMp3Download] Initializing download for job $jobId');
    try {
      job['status'] = 'downloading';
      job['step'] = '🔎 Obteniendo video...';

      LogService.log('[_runMp3Download] Fetching video metadata for $url...');
      final video = await yt.videos.get(url).timeout(const Duration(seconds: 25));
      LogService.log('[_runMp3Download] Metadata fetched. Title: "${video.title}", Author: "${video.author}"');
      
      final manifest = await yt.videos.streamsClient.getManifest(
        video.id,
        ytClients: [YoutubeApiClient.androidVr],
      ).timeout(const Duration(seconds: 25));
      final audioStreamInfo = manifest.audioOnly.withHighestBitrate();

      if (audioStreamInfo == null) {
        throw Exception('No audio stream available');
      }
      LogService.log('[_runMp3Download] Selected audio stream size: ${audioStreamInfo.size.totalMegaBytes.toStringAsFixed(2)} MB');

      LogService.log('[_runMp3Download] Resolving target folders...');
      final resolvedMusicFolder = await _getEffectiveMusicFolder(musicFolder);
      final targetDir = playlist != null && playlist.isNotEmpty
          ? Directory(p.join(resolvedMusicFolder, playlist))
          : Directory(resolvedMusicFolder);

      LogService.log('[_runMp3Download] Target directory: ${targetDir.path}');
      if (!await targetDir.exists()) {
        LogService.log('[_runMp3Download] Target directory does not exist. Creating recursively...');
        await targetDir.create(recursive: true);
      }

      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      final safeArtist = artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      final filename = safeArtist.isNotEmpty ? "$safeArtist - $safeTitle.mp3" : "$safeTitle.mp3";
      final filePath = p.join(targetDir.path, filename);
      LogService.log('[_runMp3Download] Target file path: $filePath');

      final totalSize = audioStreamInfo.size.totalBytes;
      final file = File(filePath);
      
      LogService.log('[_runMp3Download] Downloading stream via youtube_explode streams client...');
      await _downloadStreamWithProgress(
        jobId: jobId,
        streamInfo: audioStreamInfo,
        targetPath: filePath,
        yt: yt,
        onProgress: (progress) {
          job['progress'] = progress;
          job['step'] = '⬇️ Descargando MP3: $progress%';
        },
      );

      LogService.log('[_runMp3Download] Stream successfully downloaded to disk.');

      job['step'] = '🏷️ Aplicando etiquetas...';
      LogService.log('[_runMp3Download] Applying audio metadata tags...');

      // 3. Write record to local database
      final relativeFilename = playlist != null && playlist.isNotEmpty
          ? p.join(playlist, filename)
          : filename;

      // 1. Try to download thumbnail as cover art
      String? coverPath;
      String? dbCoverUrl;
      if (video.thumbnails.mediumResUrl.isNotEmpty) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final coversDir = Directory(p.join(supportDir.path, 'covers'));
          if (!await coversDir.exists()) {
            await coversDir.create(recursive: true);
          }
          final filenameHash = relativeFilename.hashCode.toString();
          coverPath = p.join(coversDir.path, '$filenameHash.jpg');
          LogService.log('[_runMp3Download] Downloading cover art from: ${video.thumbnails.mediumResUrl} to $coverPath');
          await _dio.download(video.thumbnails.mediumResUrl, coverPath);
          dbCoverUrl = coverPath.replaceAll('\\', '/');
        } catch (e) {
          LogService.log('[_runMp3Download] Cover art download skipped: $e');
          coverPath = null;
        }
      }

      // 2. Write metadata tags
      try {
        final tag = Tag(
          title: title,
          trackArtist: artist,
          pictures: coverPath != null
              ? [
                  Picture(
                    pictureType: PictureType.coverFront,
                    bytes: await File(coverPath).readAsBytes(),
                    mimeType: MimeType.jpeg,
                  )
                ]
              : [],
        );
        LogService.log('[_runMp3Download] Writing tags with audiotags...');
        await AudioTags.write(filePath, tag);
        LogService.log('[_runMp3Download] AudioTags write finished.');
      } catch (e) {
        LogService.log('[_runMp3Download] Writing audio tags failed: $e');
      }

      LogService.log('[_runMp3Download] Registering track in local database...');
      await DatabaseService.instance.insertMedia({
        'type': 'music',
        'title': title,
        'artist': artist,
        'filename': relativeFilename,
        'format': 'mp3',
        'cover_url': dbCoverUrl,
      });

      if (playlist != null && playlist.isNotEmpty) {
        LogService.log('[_runMp3Download] Adding media to playlist "$playlist"...');
        await DatabaseService.instance.addMediaToPlaylist(relativeFilename, playlist);
      }

      job['status'] = 'done';
      job['step'] = '✅ Guardado: $filename';
      job['progress'] = 100;
      job['file_path'] = filePath;
      LogService.log('[_runMp3Download] MP3 job completed successfully!');

    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        LogService.log('[_runMp3Download] Job $jobId was cancelled.');
        return;
      }
      LogService.log('[_runMp3Download] Fatal job exception: $e');
      _subscriptions.remove(jobId);
      final sink = _sinks.remove(jobId);
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }
      job['status'] = 'failed';
      job['step'] = '❌ Error en descarga';
      job['error'] = e.toString();
    } finally {
      yt.close();
    }
  }

  // Native Video download
  Future<String> downloadVideo({
    required String url,
    required String formatId,
    required String videoFolder,
  }) async {
    final jobId = const Uuid().v4();
    LogService.log('Registered Video download job: $jobId for URL: $url, formatId: $formatId');
    _jobs.add({
      'job_id': jobId,
      'url': url,
      'format_id': formatId,
      'status': 'pending',
      'step': '⏳ Preparando descarga...',
      'progress': 0,
      'is_mp3': false,
    });

    _runVideoDownload(jobId, url, formatId, videoFolder);

    return jobId;
  }

  Future<void> _runVideoDownload(
    String jobId,
    String url,
    String formatId,
    String videoFolder,
  ) async {
    final job = _jobs.firstWhere((j) => j['job_id'] == jobId);
    File? tempVideoFile;
    File? tempAudioFile;
    final yt = YoutubeExplode();
    LogService.log('[_runVideoDownload] Initializing download for job $jobId');
    try {
      job['status'] = 'downloading';
      job['step'] = '🔎 Obteniendo video...';

      LogService.log('[_runVideoDownload] Fetching video metadata for $url...');
      final video = await yt.videos.get(url).timeout(const Duration(seconds: 25));
      LogService.log('[_runVideoDownload] Metadata fetched. Title: "${video.title}"');

      final manifest = await yt.videos.streamsClient.getManifest(
        video.id,
        ytClients: [YoutubeApiClient.androidVr],
      ).timeout(const Duration(seconds: 25));

      final tagNum = int.tryParse(formatId);
      StreamInfo? streamInfo;
      if (tagNum != null) {
        for (var s in manifest.streams) {
          if (s.tag == tagNum) {
            streamInfo = s;
            break;
          }
        }
      }

      if (streamInfo == null) {
        LogService.log('[_runVideoDownload] Stream tag $formatId not found in manifest. Falling back to highest quality streams...');
        streamInfo = manifest.videoOnly.withHighestBitrate();
      }
      if (streamInfo == null) {
        streamInfo = manifest.muxed.withHighestBitrate();
      }

      if (streamInfo == null) {
        throw Exception('No suitable video stream found');
      }
      LogService.log('[_runVideoDownload] Selected video stream container: ${streamInfo.container.name}, size: ${streamInfo.size.totalMegaBytes.toStringAsFixed(2)} MB');

      final resolvedVideoFolder = await _getEffectiveVideoFolder(videoFolder);
      final targetDir = Directory(resolvedVideoFolder);
      LogService.log('[_runVideoDownload] Video target directory: ${targetDir.path}');
      if (!await targetDir.exists()) {
        LogService.log('[_runVideoDownload] Creating video target directory...');
        await targetDir.create(recursive: true);
      }

      final safeTitle = video.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
      final filename = "$safeTitle.mp4";
      final filePath = p.join(targetDir.path, filename);
      LogService.log('[_runVideoDownload] Target video path: $filePath');

      final isVideoOnly = manifest.videoOnly.any((s) => s.tag == streamInfo?.tag);

      if (isVideoOnly) {
        LogService.log('[_runVideoDownload] Muxed video detected as video-only. Muxing with highest bitrate audio stream...');
        final audioStreamInfo = manifest.audioOnly.firstWhere(
          (s) => s.container.name.toLowerCase() == 'mp4',
          orElse: () => manifest.audioOnly.withHighestBitrate()!,
        );
        LogService.log('[_runVideoDownload] Selected audio stream: ${audioStreamInfo.size.totalMegaBytes.toStringAsFixed(2)} MB');

        final tempDir = await getTemporaryDirectory();
        tempVideoFile = File(p.join(tempDir.path, '${jobId}_temp_video.mp4'));
        tempAudioFile = File(p.join(tempDir.path, '${jobId}_temp_audio.m4a'));
        LogService.log('[_runVideoDownload] Temp video file: ${tempVideoFile.path}');
        LogService.log('[_runVideoDownload] Temp audio file: ${tempAudioFile.path}');

        // 1. Download Video
        LogService.log('[_runVideoDownload] Downloading video track via youtube_explode...');
        await _downloadStreamWithProgress(
          jobId: jobId,
          streamInfo: streamInfo,
          targetPath: tempVideoFile.path,
          yt: yt,
          onProgress: (progress) {
            final overallProgress = (progress * 0.8).toInt();
            job['progress'] = overallProgress;
            job['step'] = '⬇️ Descargando video (80%): $overallProgress%';
          },
        );

        // 2. Download Audio
        LogService.log('[_runVideoDownload] Downloading audio track via youtube_explode...');
        await _downloadStreamWithProgress(
          jobId: jobId,
          streamInfo: audioStreamInfo,
          targetPath: tempAudioFile.path,
          yt: yt,
          onProgress: (progress) {
            final overallProgress = 80 + (progress * 0.2).toInt();
            job['progress'] = overallProgress;
            job['step'] = '⬇️ Descargando audio (20%): $overallProgress%';
          },
        );

        // 3. Mux natively
        LogService.log('[_runVideoDownload] Invoking native MethodChannel to merge video and audio...');
        job['step'] = '⏳ Procesando video...';
        const channel = MethodChannel('com.example.sonero/media');
        await channel.invokeMethod('mergeVideoAndAudio', {
          'videoPath': tempVideoFile.path,
          'audioPath': tempAudioFile.path,
          'outputPath': filePath,
        });
        LogService.log('[_runVideoDownload] Native merge completed.');
      } else {
        LogService.log('[_runVideoDownload] Muxed video is already standard container. Downloading directly via youtube_explode...');
        await _downloadStreamWithProgress(
          jobId: jobId,
          streamInfo: streamInfo,
          targetPath: filePath,
          yt: yt,
          onProgress: (progress) {
            job['progress'] = progress;
            job['step'] = '⬇️ Descargando video: $progress%';
          },
        );
      }

      // Cleanup temp files
      try {
        if (tempVideoFile != null && await tempVideoFile.exists()) {
          LogService.log('[_runVideoDownload] Cleaning up temporary video file...');
          await tempVideoFile.delete();
        }
        if (tempAudioFile != null && await tempAudioFile.exists()) {
          LogService.log('[_runVideoDownload] Cleaning up temporary audio file...');
          await tempAudioFile.delete();
        }
      } catch (e) {
        LogService.log('[_runVideoDownload] Temp file cleanup warning: $e');
      }

      final relativeFilename = p.join('videos', filename);

      String? dbCoverUrl;
      if (video.thumbnails.mediumResUrl.isNotEmpty) {
        try {
          final supportDir = await getApplicationSupportDirectory();
          final coversDir = Directory(p.join(supportDir.path, 'covers'));
          if (!await coversDir.exists()) {
            await coversDir.create(recursive: true);
          }
          final filenameHash = relativeFilename.hashCode.toString();
          final coverPath = p.join(coversDir.path, '$filenameHash.jpg');
          LogService.log('[_runVideoDownload] Downloading video thumbnail from: ${video.thumbnails.mediumResUrl} to $coverPath');
          await _dio.download(video.thumbnails.mediumResUrl, coverPath);
          dbCoverUrl = coverPath.replaceAll('\\', '/');
        } catch (e) {
          LogService.log('[_runVideoDownload] Video thumbnail download skipped: $e');
        }
      }

      LogService.log('[_runVideoDownload] Registering video in database...');
      await DatabaseService.instance.insertMedia({
        'type': 'video',
        'title': video.title,
        'artist': video.author,
        'filename': relativeFilename,
        'format': 'mp4',
        'cover_url': dbCoverUrl,
      });

      job['status'] = 'done';
      job['step'] = '✅ Guardado: $filename';
      job['progress'] = 100;
      job['file_path'] = filePath;
      LogService.log('[_runVideoDownload] Video job completed successfully!');

    } catch (e) {
      if (e is DioException && CancelToken.isCancel(e)) {
        LogService.log('[_runVideoDownload] Job $jobId was cancelled.');
        return;
      }
      LogService.log('[_runVideoDownload] Fatal job exception: $e');
      _subscriptions.remove(jobId);
      final sink = _sinks.remove(jobId);
      if (sink != null) await sink.close();
      try {
        if (tempVideoFile != null && await tempVideoFile.exists()) await tempVideoFile.delete();
        if (tempAudioFile != null && await tempAudioFile.exists()) await tempAudioFile.delete();
      } catch (_) {}
      job['status'] = 'failed';
      job['step'] = '❌ Error en descarga';
      job['error'] = e.toString();
    } finally {
      yt.close();
    }
  }
}
