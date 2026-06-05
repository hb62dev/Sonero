import 'dart:io';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recognizer_service.dart';
import 'log_service.dart';

class DownloaderService {
  static final YoutubeExplode _yt = YoutubeExplode();
  static final Dio _dio = Dio();

  static Future<String> downloadAndTagTrack(TrackInfo track, {String? musicFolder, String? playlist}) async {
    // 1. Search for the track on YouTube
    final query = "${track.title} ${track.artist} audio";
    LogService.log('Buscando en YouTube: "$query"');
    final searchResults = await _yt.search.search(query);
    
    if (searchResults.isEmpty) {
      LogService.log('Error: No se encontraron resultados en YouTube para: $query');
      throw Exception('No results found on YouTube for: $query');
    }
    
    final video = searchResults.first;
    LogService.log('Video de YouTube seleccionado: "${video.title}" (ID: ${video.id})');
    
    // 2. Get the audio stream manifest
    LogService.log('Obteniendo manifiesto de streams de audio...');
    final manifest = await _yt.videos.streamsClient.getManifest(
      video.id,
      ytClients: [YoutubeApiClient.androidVr],
    );
    final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
    
    if (audioStreamInfo == null) {
      LogService.log('Error: No hay streams de audio disponibles para el video: ${video.id}');
      throw Exception('No audio stream available for video: ${video.id}');
    }
    LogService.log('Stream de audio seleccionado con tasa de bits más alta.');

    // 3. Prepare the file path
    Directory targetDir;
    if (musicFolder != null && musicFolder.isNotEmpty) {
      targetDir = playlist != null && playlist.isNotEmpty
          ? Directory(p.join(musicFolder, playlist))
          : Directory(musicFolder);
    } else {
      final Directory? extDir = Platform.isAndroid ? await getExternalStorageDirectory() : null;
      final fallbackBase = extDir != null ? extDir.path : (await getApplicationDocumentsDirectory()).path;
      final baseMusicDir = p.join(fallbackBase, 'Sonero', 'Music');
      targetDir = playlist != null && playlist.isNotEmpty
          ? Directory(p.join(baseMusicDir, playlist))
          : Directory(baseMusicDir);
    }

    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }
    
    // Ensure safe filename
    final safeTitle = track.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final safeArtist = track.artist.replaceAll(RegExp(r'[\\/:*?"<>|]'), '');
    final filename = safeArtist.isNotEmpty ? "$safeArtist - $safeTitle.mp3" : "$safeTitle.mp3";
    final filePath = p.join(targetDir.path, filename);
    LogService.log('Guardando archivo MP3 en: $filePath');

    // 4. Download the stream using youtube_explode streams client
    LogService.log('Iniciando descarga del stream de audio...');
    final stream = _yt.videos.streamsClient.get(audioStreamInfo);
    final file = File(filePath);
    final fileStream = file.openWrite();
    await stream.pipe(fileStream);
    await fileStream.flush();
    await fileStream.close();
    LogService.log('Descarga del stream finalizada.');

    // 5. Download cover art if available
    String? coverPath;
    if (track.coverUrl != null && track.coverUrl!.isNotEmpty) {
      try {
        final coverFile = File(p.join(targetDir.path, "$filename.jpg"));
        LogService.log('Descargando carátula desde: ${track.coverUrl}');
        await _dio.download(track.coverUrl!, coverFile.path);
        coverPath = coverFile.path;
        LogService.log('Carátula descargada en: $coverPath');
      } catch (e) {
        LogService.log('Error descargando carátula: $e');
      }
    }

    // 6. Apply ID3 Tags
    try {
      LogService.log('Escribiendo etiquetas ID3 (Título: ${track.title}, Artista: ${track.artist})...');
      final tag = Tag(
        title: track.title,
        trackArtist: track.artist,
        album: track.album,
        genre: track.genre,
        year: track.year != null ? int.tryParse(track.year!) : null,
        pictures: coverPath != null ? [
          Picture(
            pictureType: PictureType.coverFront,
            bytes: await File(coverPath).readAsBytes(),
            mimeType: MimeType.jpeg,
          )
        ] : [],
      );

      await AudioTags.write(filePath, tag);
      LogService.log('Etiquetas ID3 escritas exitosamente.');
      
      // Cleanup temporary cover image
      if (coverPath != null && await File(coverPath).exists()) {
        await File(coverPath).delete();
      }
    } catch (e) {
      LogService.log('Advertencia: No se pudieron escribir las etiquetas ID3: $e');
    }

    return filePath;
  }
}
