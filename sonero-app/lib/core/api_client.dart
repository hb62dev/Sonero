import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path/path.dart' as p;
import '../services/database_service.dart';
import '../services/native_download_manager.dart';

class ApiClient {
  final String baseUrl;
  String? musicFolder;
  String? videoFolder;

  ApiClient({required this.baseUrl, this.musicFolder, this.videoFolder});

  bool get isNative => Platform.isAndroid || Platform.isIOS || baseUrl == 'native';

  // ── Listen pipeline ──────────────────────────────────────────────────────

  Future<String> startListening({
    int duration = 10,
    bool autoDownload = true,
    String source = 'mic',
    int? deviceIndex,
    String? playlist,
  }) async {
    if (isNative) {
      return 'local_native';
    }
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
    if (isNative) {
      return 'local_native';
    }
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
    if (isNative) {
      return {
        'job_id': jobId,
        'status': 'done',
        'step': 'Completado',
        'progress': 100,
      };
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/listen/jobs/$jobId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Playlists ────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getPlaylists() async {
    if (isNative) {
      if (musicFolder == null || musicFolder!.isEmpty) {
        return {'root': '', 'playlists': []};
      }
      final dir = Directory(musicFolder!);
      if (!await dir.exists()) {
        return {'root': musicFolder, 'playlists': []};
      }
      
      final playlistsList = <Map<String, dynamic>>[];
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          final name = p.basename(entity.path);
          if (name == 'lyrics' || name.startsWith('.')) continue;
          
          var count = 0;
          try {
            await for (final file in entity.list(recursive: true)) {
              if (file is File && (file.path.endsWith('.mp3') || file.path.endsWith('.m4a'))) {
                count++;
              }
            }
          } catch (_) {}
          
          playlistsList.add({
            'name': name,
            'path': entity.path,
            'track_count': count,
          });
        }
      }
      
      playlistsList.sort((a, b) => a['name'].compareTo(b['name']));
      return {'root': musicFolder, 'playlists': playlistsList};
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/playlists'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> createPlaylist(String name) async {
    if (isNative) {
      final path = p.join(musicFolder ?? '', name);
      await Directory(path).create(recursive: true);
      
      await DatabaseService.instance.createPlaylist(name);
      return;
    }
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/playlists'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name}),
    );
    _check(res);
  }

  Future<void> renamePlaylist(String oldName, String newName) async {
    if (isNative) {
      final oldDir = Directory(p.join(musicFolder ?? '', oldName));
      final newDir = Directory(p.join(musicFolder ?? '', newName));
      if (await oldDir.exists()) {
        await oldDir.rename(newDir.path);
      }
      
      await DatabaseService.instance.renamePlaylist(oldName, newName);
      
      final db = await DatabaseService.instance.database;
      final tracks = await db.query('media', where: 'filename LIKE ?', whereArgs: ['$oldName/%']);
      for (final t in tracks) {
        final id = t['id'] as int;
        final oldFilename = t['filename'] as String;
        final newFilename = oldFilename.replaceFirst('$oldName/', '$newName/');
        await db.update('media', {'filename': newFilename}, where: 'id = ?', whereArgs: [id]);
      }
      return;
    }
    final res = await http.patch(
      Uri.parse('$baseUrl/api/v1/playlists/rename'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'old_name': oldName, 'new_name': newName}),
    );
    _check(res);
  }

  Future<void> deletePlaylist(String name) async {
    if (isNative) {
      final playlistDir = Directory(p.join(musicFolder ?? '', name));
      if (await playlistDir.exists()) {
        await for (final entity in playlistDir.list()) {
          if (entity is File) {
            final targetPath = p.join(musicFolder ?? '', p.basename(entity.path));
            await entity.rename(targetPath);
            
            final oldFilename = p.join(name, p.basename(entity.path)).replaceAll('\\', '/');
            final newFilename = p.basename(entity.path);
            
            final db = await DatabaseService.instance.database;
            await db.update('media', {'filename': newFilename}, where: 'filename = ?', whereArgs: [oldFilename]);
          }
        }
        await playlistDir.delete();
      }
      
      await DatabaseService.instance.deletePlaylist(name);
      return;
    }
    final res = await http.delete(Uri.parse('$baseUrl/api/v1/playlists/$name'));
    _check(res);
  }

  Future<Map<String, dynamic>> getPlaylistTracks(String name) async {
    if (isNative) {
      final dbList = await DatabaseService.instance.getPlaylistTracks(name);
      final tracks = <Map<String, dynamic>>[];
      
      for (final media in dbList) {
        final filename = media['filename'] as String;
        final baseName = p.basename(filename);
        final fullPath = p.join(musicFolder ?? '', name, baseName);
        final file = File(p.normalize(fullPath));
        
        if (await file.exists()) {
          final stat = await file.stat();
          tracks.add({
            'filename': baseName,
            'size_mb': (stat.size / 1024 / 1024 * 100).round() / 100,
            'created_at': stat.changed.millisecondsSinceEpoch / 1000,
            'title': media['title'] ?? p.basenameWithoutExtension(baseName),
            'artist': media['artist'] ?? '',
            'album': media['album'] ?? '',
            'year': media['year'] ?? '',
            'cover_url': media['cover_url'],
          });
        }
      }
      return {'playlist': name, 'total': tracks.length, 'tracks': tracks};
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/playlists/$name/tracks'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Tracks ───────────────────────────────────────────────────────────────

  Future<void> deleteTrack(String filename) async {
    if (isNative) {
      final isVideo = filename.startsWith('videos/');
      String fullPath;
      if (isVideo) {
        final cleanFilename = filename.startsWith('videos/')
            ? filename.substring(7)
            : filename;
        fullPath = p.join(videoFolder ?? '', cleanFilename);
      } else {
        fullPath = p.join(musicFolder ?? '', filename);
      }
      final file = File(p.normalize(fullPath));
      if (await file.exists()) {
        await file.delete();
      }
      
      await DatabaseService.instance.deleteMedia(filename);
      return;
    }
    final res = await http.delete(Uri.parse('$baseUrl/api/v1/downloads/$filename'));
    _check(res);
  }

  Future<void> moveTrack({
    required String filename,
    String? fromPlaylist,
    String? toPlaylist,
  }) async {
    if (isNative) {
      final srcDir = fromPlaylist != null && fromPlaylist.isNotEmpty
          ? Directory(p.join(musicFolder ?? '', fromPlaylist))
          : Directory(musicFolder ?? '');
      final dstDir = toPlaylist != null && toPlaylist.isNotEmpty
          ? Directory(p.join(musicFolder ?? '', toPlaylist))
          : Directory(musicFolder ?? '');
      
      final srcFile = File(p.join(srcDir.path, filename));
      final dstFile = File(p.join(dstDir.path, filename));
      
      if (!await srcFile.exists()) {
        throw Exception("Track not found: $filename");
      }
      if (!await dstDir.exists()) {
        await dstDir.create(recursive: true);
      }
      
      await srcFile.rename(dstFile.path);
      
      final oldRelativeFilename = fromPlaylist != null && fromPlaylist.isNotEmpty
          ? p.join(fromPlaylist, filename).replaceAll('\\', '/')
          : filename;
      final newRelativeFilename = toPlaylist != null && toPlaylist.isNotEmpty
          ? p.join(toPlaylist, filename).replaceAll('\\', '/')
          : filename;
      
      final db = await DatabaseService.instance.database;
      await db.update('media', {'filename': newRelativeFilename}, where: 'filename = ?', whereArgs: [oldRelativeFilename]);
      
      if (fromPlaylist != null && fromPlaylist.isNotEmpty) {
        await DatabaseService.instance.removeMediaFromPlaylist(newRelativeFilename, fromPlaylist);
      }
      if (toPlaylist != null && toPlaylist.isNotEmpty) {
        await DatabaseService.instance.addMediaToPlaylist(newRelativeFilename, toPlaylist);
      }
      return;
    }
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
    if (isNative) {
      return 'local_native';
    }
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/metadata/auto'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'filenames': filenames}),
    );
    _check(res);
    return jsonDecode(res.body)['job_id'] as String;
  }

  Future<Map<String, dynamic>> getAutofillJobStatus(String jobId) async {
    if (isNative) {
      return {'job_id': jobId, 'status': 'done', 'progress': 100};
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/metadata/auto/jobs/$jobId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> getTrackMetadata(String filename) async {
    if (isNative) {
      final media = await DatabaseService.instance.getMediaByFilename(filename);
      if (media != null) {
        return {
          'filename': media['filename'],
          'title': media['title'],
          'artist': media['artist'],
          'album': media['album'],
          'year': media['year'],
          'genre': media['genre'],
          'cover_url': media['cover_url'],
        };
      }
      return null;
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/metadata?filenames=$filename'));
    _check(res);
    final list = jsonDecode(res.body) as List;
    if (list.isNotEmpty) {
      return list.first as Map<String, dynamic>;
    }
    return null;
  }

  Future<void> updateTrackMetadata(Map<String, dynamic> update) async {
    if (isNative) {
      final filename = update['filename'] as String;
      await DatabaseService.instance.updateMediaMetadata(filename, {
        'title': update['title'],
        'artist': update['artist'],
        'album': update['album'],
        'year': update['year'],
        'genre': update['genre'],
      });
      return;
    }
    final res = await http.patch(
      Uri.parse('$baseUrl/api/v1/metadata'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'updates': [update]}),
    );
    _check(res);
  }

  Future<void> updatePaths({String? music, String? video}) async {
    if (isNative) {
      if (music != null) musicFolder = music;
      if (video != null) videoFolder = video;
      return;
    }
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
    if (isNative) {
      await DatabaseService.instance.syncWithFileSystem(
        musicFolder: musicFolder,
        videoFolder: videoFolder,
      );
      final dbList = await DatabaseService.instance.getAllDownloads();
      final downloads = <Map<String, dynamic>>[];
      
      for (final media in dbList) {
        final filename = media['filename'] as String;
        final isVideo = media['type'] == 'video' || filename.startsWith('videos/');
        
        String fullPath;
        if (isVideo) {
          final cleanFilename = filename.startsWith('videos/')
              ? filename.substring(7)
              : filename;
          fullPath = p.join(videoFolder ?? '', cleanFilename);
        } else {
          fullPath = p.join(musicFolder ?? '', filename);
        }
        
        final file = File(p.normalize(fullPath));
        if (await file.exists()) {
          final stat = await file.stat();
          
          String playlistName = '';
          if (!isVideo) {
            final parts = p.split(filename);
            if (parts.length > 1) {
              playlistName = parts[0];
            }
          }
          
          downloads.add({
            'filename': filename,
            'size_mb': (stat.size / 1024 / 1024 * 100).round() / 100,
            'created_at': stat.changed.millisecondsSinceEpoch / 1000,
            'title': media['title'] ?? p.basenameWithoutExtension(filename),
            'artist': media['artist'] ?? '',
            'album': media['album'] ?? '',
            'year': media['year'] ?? '',
            'cover_url': media['cover_url'],
            'playlist': playlistName,
          });
        }
      }
      return {'total': downloads.length, 'downloads': downloads};
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Search ───────────────────────────────────────────────────────────────

  Future<List<dynamic>> getMetadata({List<String>? filenames}) async {
    if (isNative) {
      final list = <Map<String, dynamic>>[];
      if (filenames != null) {
        for (final f in filenames) {
          final m = await getTrackMetadata(f);
          if (m != null) list.add(m);
        }
      }
      return list;
    }
    final query = filenames?.map((f) => 'filenames=${Uri.encodeComponent(f)}').join('&') ?? '';
    final url = '$baseUrl/api/v1/metadata${query.isNotEmpty ? '?$query' : ''}';
    final res = await http.get(Uri.parse(url));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  bool _isVideoExt(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  final _youtubeSuffixes = RegExp(
    r'[\(\[\|]'
    r'(?:official\s+)?(?:hd\s+|4k\s+|full\s+)?'
    r'(?:music\s+)?(?:hd\s+)?(?:video|audio|lyric(?:s)?|visualizer|'
    r'animated\s+video|performance|live|clip|hq|remaster(?:ed)?|'
    r'version|vevo|mv|official|remake|cover)\b.*',
    caseSensitive: false,
  );
  final _featuring = RegExp(r'\s+(?:ft\.?|feat\.?|featuring)\s+.+', caseSensitive: false);
  final _extraParens = RegExp(r'\s*\([^)]*\)\s*$');
  final _artistPrefix = RegExp(r'^([^\-\u2013]+?)\s*[\-\u2013]\s*(.+)$');

  String _cleanTitle(String title) {
    var t = title.trim();
    t = t.replaceAll(_youtubeSuffixes, '');
    t = t.replaceAll(_featuring, '');
    t = t.replaceAll(_extraParens, '');
    return t.replaceAll(RegExp(r'^[ \-|]+|[ \-|]+$'), '').trim();
  }

  Map<String, String> _extractArtistTitle(String rawTitle, String rawArtist) {
    final cleaned = _cleanTitle(rawTitle);
    final match = _artistPrefix.firstMatch(cleaned);
    if (match != null) {
      final extractedArtist = match.group(1)!.trim();
      final extractedTitle = _cleanTitle(match.group(2)!);
      final useArtist = rawArtist.trim().isNotEmpty ? rawArtist.trim() : extractedArtist;
      return {'artist': useArtist, 'title': extractedTitle};
    }
    return {'artist': rawArtist.trim(), 'title': cleaned};
  }

  Future<Map<String, dynamic>?> _lrclibFetch(String title, String artist) async {
    final cleanedMeta = _extractArtistTitle(title, artist);
    final useArtist = cleanedMeta['artist']!;
    final useTitle = cleanedMeta['title']!;
    
    Future<Map<String, dynamic>?> exact(String t, String a) async {
      try {
        final uri = Uri.parse('https://lrclib.net/api/get').replace(
          queryParameters: {
            'track_name': t,
            'artist_name': a,
          },
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final plain = data['plainLyrics'] as String?;
          final synced = data['syncedLyrics'] as String?;
          if ((plain != null && plain.isNotEmpty) || (synced != null && synced.isNotEmpty)) {
            return {'plain': plain, 'synced': synced};
          }
        }
      } catch (_) {}
      return null;
    }

    Future<Map<String, dynamic>?> fuzzy(String t, [String a = '']) async {
      try {
        final params = {
          'track_name': t,
          if (a.trim().isNotEmpty) 'artist_name': a.trim(),
        };
        final uri = Uri.parse('https://lrclib.net/api/search').replace(
          queryParameters: params,
        );
        final res = await http.get(uri).timeout(const Duration(seconds: 12));
        if (res.statusCode == 200) {
          final results = jsonDecode(res.body);
          if (results is List && results.isNotEmpty) {
            for (var hit in results) {
              if (hit is Map) {
                final plain = hit['plainLyrics'] as String?;
                final synced = hit['syncedLyrics'] as String?;
                if ((plain != null && plain.isNotEmpty) || (synced != null && synced.isNotEmpty)) {
                  return {'plain': plain, 'synced': synced};
                }
              }
            }
          }
        }
      } catch (_) {}
      return null;
    }

    var res = await exact(useTitle, useArtist);
    if (res != null) return res;

    res = await fuzzy(useTitle, useArtist);
    if (res != null) return res;

    res = await fuzzy(useTitle);
    if (res != null) return res;

    return null;
  }

  Future<Map<String, dynamic>> getLyrics(String title, String artist) async {
    if (isNative) {
      try {
        final result = await _lrclibFetch(title, artist);
        if (result != null) {
          return {
            'plain': result['plain'],
            'synced': result['synced'],
            'source': 'lrclib',
          };
        }
        return {
          'plain': null,
          'synced': null,
          'error': 'No se encontraron letras para esta canción en lrclib.net.',
        };
      } catch (e) {
        return {
          'plain': null,
          'synced': null,
          'error': 'Error al buscar letras: $e',
        };
      }
    }
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
    if (isNative) {
      final mFolder = musicFolder;
      if (mFolder == null || mFolder.isEmpty) {
        return {'saved': false, 'error': 'Directorio de música no configurado.'};
      }
      try {
        final result = await _lrclibFetch(title, artist);
        if (result == null) {
          return {'saved': false, 'error': 'No se encontraron letras para esta canción en lrclib.net.'};
        }
        final synced = result['synced'] as String?;
        final plain = result['plain'] as String?;
        final content = synced ?? plain;

        if (content == null || content.trim().isEmpty) {
          return {'saved': false, 'error': 'No se encontraron letras para esta canción en lrclib.net.'};
        }

        final isVideo = _isVideoExt(filename);
        final targetDir = isVideo ? (videoFolder ?? mFolder) : mFolder;

        final lDir = Directory(p.join(targetDir, 'lyrics'));
        if (!lDir.existsSync()) {
          await lDir.create(recursive: true);
        }

        final stem = p.basenameWithoutExtension(filename);
        final suffix = synced != null ? '.lrc' : '.txt';
        final lrcFile = File(p.join(lDir.path, '$stem$suffix'));
        await lrcFile.writeAsString(content);

        return {
          'saved': true,
          'path': lrcFile.path,
          'synced': synced,
          'plain': plain,
          'type': synced != null ? 'synced' : 'plain',
        };
      } catch (e) {
        return {'saved': false, 'error': 'Error al descargar letra: $e'};
      }
    }
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
    if (isNative) {
      final yt = YoutubeExplode();
      try {
        final videos = await yt.search.search(query);
        final results = <Map<String, dynamic>>[];
        for (final video in videos.take(limit)) {
          final durationSecs = video.duration?.inSeconds ?? 0;
          results.add({
            'id': video.id.value,
            'title': video.title,
            'channel': video.author,
            'duration': durationSecs,
            'url': video.url,
            'thumbnail': video.thumbnails.mediumResUrl.isNotEmpty ? video.thumbnails.mediumResUrl : null,
            'is_short': durationSecs <= 60,
          });
        }
        return results;
      } finally {
        yt.close();
      }
    }
    final encodedQuery = Uri.encodeQueryComponent(query);
    final res = await http.get(Uri.parse('$baseUrl/api/v1/search?q=$encodedQuery&limit=$limit'))
        .timeout(const Duration(seconds: 30));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  // ── Video Downloads ────────────────────────────────────────────────────────
  
  Future<Map<String, dynamic>> getVideoInfo(String url) async {
    if (isNative) {
      final yt = YoutubeExplode();
      try {
        final video = await yt.videos.get(url).timeout(const Duration(seconds: 15));
        final manifest = await yt.videos.streamsClient.getManifest(video.id).timeout(const Duration(seconds: 15));
        
        final formats = <Map<String, dynamic>>[];
        
        // Single MP3 320kbps option
        formats.add({
          'format_id': 'bestaudio/best',
          'resolution': '320kbps',
          'ext': 'mp3',
          'filesize_mb': null,
          'is_audio_only': true,
        });
        
        final seenResolutions = <String>{};
        for (final s in manifest.muxed) {
          if (s.container.name.toLowerCase() == 'mp4') {
            final res = s.videoQualityLabel;
            if (!seenResolutions.contains(res)) {
              seenResolutions.add(res);
              formats.add({
                'format_id': s.tag.toString(),
                'resolution': res,
                'ext': 'mp4',
                'filesize_mb': (s.size.totalMegaBytes * 100).round() / 100,
                'is_audio_only': false,
              });
            }
          }
        }

        // Add video-only formats for higher resolutions
        for (final s in manifest.videoOnly) {
          if (s.container.name.toLowerCase() == 'mp4') {
            final res = s.videoQualityLabel;
            if (!seenResolutions.contains(res)) {
              seenResolutions.add(res);
              formats.add({
                'format_id': s.tag.toString(),
                'resolution': res,
                'ext': 'mp4',
                'filesize_mb': (s.size.totalMegaBytes * 100).round() / 100,
                'is_audio_only': false,
              });
            }
          }
        }
        
        // Sort: audio first, then video resolutions descending
        int parseRes(String r) {
          final clean = r.replaceAll(RegExp(r'\D'), '');
          return int.tryParse(clean) ?? 0;
        }
        formats.sort((a, b) {
          if (a['is_audio_only'] == true && b['is_audio_only'] == true) return 0;
          if (a['is_audio_only'] == true) return -1;
          if (b['is_audio_only'] == true) return 1;
          return parseRes(b['resolution'] as String).compareTo(parseRes(a['resolution'] as String));
        });
        
        return {
          'title': video.title,
          'thumbnail': video.thumbnails.mediumResUrl,
          'formats': formats,
        };
      } finally {
        yt.close();
      }
    }
    final encodedUrl = Uri.encodeQueryComponent(url);
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/video/info?url=$encodedUrl'))
        .timeout(const Duration(seconds: 25));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<String> downloadVideo(String url, String formatId) async {
    if (isNative) {
      return await NativeDownloadManager.instance.downloadVideo(
        url: url,
        formatId: formatId,
        videoFolder: videoFolder ?? '',
      );
    }
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
    if (isNative) {
      return await NativeDownloadManager.instance.downloadMp3Direct(
        url: url,
        title: title,
        artist: artist,
        playlist: playlist,
        musicFolder: musicFolder ?? '',
      );
    }
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
    if (isNative) {
      return NativeDownloadManager.instance.getJob(jobId) ?? {
        'job_id': jobId,
        'status': 'failed',
        'step': 'Job not found',
        'progress': 0,
      };
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/video/jobs/$jobId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<List<dynamic>> getAllVideoJobs() async {
    if (isNative) {
      return NativeDownloadManager.instance.getAllJobs();
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/video/jobs'));
    _check(res);
    return jsonDecode(res.body) as List<dynamic>;
  }

  Future<void> pauseVideoJob(String jobId) async {
    if (isNative) {
      await NativeDownloadManager.instance.pauseJob(jobId);
      return;
    }
    final res = await http.post(Uri.parse('$baseUrl/api/v1/downloads/video/jobs/$jobId/pause'));
    _check(res);
  }

  Future<void> resumeVideoJob(String jobId) async {
    if (isNative) {
      await NativeDownloadManager.instance.resumeJob(jobId);
      return;
    }
    final res = await http.post(Uri.parse('$baseUrl/api/v1/downloads/video/jobs/$jobId/resume'));
    _check(res);
  }

  // ── Devices ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDevices() async {
    if (isNative) {
      return {'devices': [], 'current': null};
    }
    final res = await http.get(Uri.parse('$baseUrl/api/v1/devices'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Settings & Cookies ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> syncBenrioCookies() async {
    if (isNative) {
      return {'status': 'skipped', 'message': 'Modo nativo activo. Las cookies no son necesarias.'};
    }
    final res = await http.post(Uri.parse('$baseUrl/api/v1/settings/cookies/benrio'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> uploadCookies(String filePath) async {
    if (isNative) {
      return;
    }
    var request = http.MultipartRequest('POST', Uri.parse('$baseUrl/api/v1/settings/cookies/upload'));
    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    final streamedResponse = await request.send();
    final res = await http.Response.fromStream(streamedResponse);
    _check(res);
  }

  // ── Health ───────────────────────────────────────────────────────────────

  Future<bool> checkHealth() async {
    if (isNative) return true;
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

  // ── Sync Endpoints ─────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> exportSyncData(String userId) async {
    final res = await http.get(Uri.parse('$baseUrl/api/v1/sync/export?user_id=$userId'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> importSyncData(Map<String, dynamic> data) async {
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/sync/import'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(data),
    );
    _check(res);
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
