import 'dart:io';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:audiotags/audiotags.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'recognizer_service.dart';

class DownloaderService {
  static final YoutubeExplode _yt = YoutubeExplode();
  static final Dio _dio = Dio();

  static Future<String> downloadAndTagTrack(TrackInfo track, {String? musicFolder, String? playlist}) async {
    // 1. Search for the track on YouTube
    final query = "${track.title} ${track.artist} audio";
    final searchResults = await _yt.search.search(query);
    
    if (searchResults.isEmpty) {
      throw Exception('No results found on YouTube for: $query');
    }
    
    final video = searchResults.first;
    
    // 2. Get the audio stream manifest
    final manifest = await _yt.videos.streamsClient.getManifest(
      video.id,
      ytClients: [YoutubeApiClient.androidVr],
    );
    final audioStreamInfo = manifest.audioOnly.withHighestBitrate();
    
    if (audioStreamInfo == null) {
      throw Exception('No audio stream available for video: ${video.id}');
    }

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
    final filename = safeArtist.isNotEmpty ? "$safeArtist - $safeTitle.m4a" : "$safeTitle.m4a";
    final filePath = p.join(targetDir.path, filename);

    // 4. Download the stream using youtube_explode streams client
    final stream = _yt.videos.streamsClient.get(audioStreamInfo);
    final file = File(filePath);
    final fileStream = file.openWrite();
    await stream.pipe(fileStream);
    await fileStream.flush();
    await fileStream.close();

    // 5. Download cover art if available
    String? coverPath;
    if (track.coverUrl != null && track.coverUrl!.isNotEmpty) {
      try {
        final coverFile = File(p.join(targetDir.path, "$filename.jpg"));
        await _dio.download(track.coverUrl!, coverFile.path);
        coverPath = coverFile.path;
      } catch (e) {
        print("[DownloaderService] Could not download cover art: $e");
      }
    }

    // 6. Apply ID3 Tags
    try {
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
      
      // Cleanup temporary cover image
      if (coverPath != null && await File(coverPath).exists()) {
        await File(coverPath).delete();
      }
    } catch (e) {
      print("[DownloaderService] Warning: Could not write ID3 tags: $e");
    }

    return filePath;
  }
}
