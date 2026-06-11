import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:path/path.dart' as p;
import 'package:audiotags/audiotags.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import '../services/database_service.dart';
import '../services/native_download_manager.dart';
import '../services/lyrics_service.dart';

class ApiClient {
  final String baseUrl;
  String? musicFolder;
  String? videoFolder;
  
  static final Map<String, Map<String, dynamic>> _nativeJobs = {};
  DateTime? _lastSyncTime;
  bool _isBackgroundSyncing = false;

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
      final jobId = 'native_${DateTime.now().millisecondsSinceEpoch}';
      _nativeJobs[jobId] = {
        'job_id': jobId,
        'status': 'running',
        'total': filenames.length,
        'completed': 0,
        'failed': 0,
        'current': 'Iniciando escaneo...',
      };
      _runNativeAutofill(jobId, filenames);
      return jobId;
    }
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/metadata/auto'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'filenames': filenames}),
    );
    _check(res);
    return jsonDecode(res.body)['job_id'] as String;
  }

  Future<Map<String, String>?> autofillSingleTrack(String filename) async {
    try {
      final fullPath = p.join(musicFolder ?? '', filename);
      final file = File(fullPath);
      if (!await file.exists()) return null;

      // 1. Get current tag info if possible to guide the search
      String artist = '';
      String title = _cleanTitle(p.basenameWithoutExtension(filename));
      try {
        final tag = await AudioTags.read(fullPath);
        if (tag != null) {
          if (tag.trackArtist != null && tag.trackArtist!.trim().isNotEmpty) {
            artist = tag.trackArtist!.trim();
          }
          if (tag.title != null && tag.title!.trim().isNotEmpty) {
            title = tag.title!.trim();
          }
        }
      } catch (_) {}

      // Build query
      final query = artist.isNotEmpty ? '$artist $title' : title;
      final url = Uri.parse('https://itunes.apple.com/search?term=${Uri.encodeComponent(query)}&media=music&limit=1');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List;
        if (results.isNotEmpty) {
          final result = results.first as Map<String, dynamic>;
          final matchTitle = result['trackName'] as String? ?? title;
          final matchArtist = result['artistName'] as String? ?? artist;
          final matchAlbum = result['collectionName'] as String? ?? '';
          final matchGenre = result['primaryGenreName'] as String? ?? '';
          final releaseDate = result['releaseDate'] as String? ?? '';
          String matchYear = '';
          if (releaseDate.length >= 4) {
            matchYear = releaseDate.substring(0, 4);
          }

          // Cover Art URL (higher resolution)
          final artworkUrl100 = result['artworkUrl100'] as String?;
          String? coverUrl;
          List<Picture> pictures = [];

          if (artworkUrl100 != null && artworkUrl100.isNotEmpty) {
            final artworkUrl600 = artworkUrl100.replaceAll('100x100bb.jpg', '600x600bb.jpg');
            try {
              final coverRes = await http.get(Uri.parse(artworkUrl600)).timeout(const Duration(seconds: 15));
              if (coverRes.statusCode == 200) {
                final supportDir = await getApplicationSupportDirectory();
                final coversDir = Directory(p.join(supportDir.path, 'covers'));
                if (!await coversDir.exists()) {
                  await coversDir.create(recursive: true);
                }
                final filenameHash = filename.hashCode.toString();
                final picExt = artworkUrl600.toLowerCase().contains('.png') ? 'png' : 'jpg';
                final coverFile = File(p.join(coversDir.path, '$filenameHash.$picExt'));
                await coverFile.writeAsBytes(coverRes.bodyBytes);
                coverUrl = coverFile.path.replaceAll('\\', '/');

                pictures = [
                  Picture(
                    pictureType: PictureType.coverFront,
                    bytes: coverRes.bodyBytes,
                    mimeType: artworkUrl600.toLowerCase().contains('.png') ? MimeType.png : MimeType.jpeg,
                  )
                ];
              }
            } catch (e) {
              print("[autofillSingleTrack] Error downloading cover art: $e");
            }
          }

          // Write tags to file
          try {
            final tag = Tag(
              title: matchTitle,
              trackArtist: matchArtist,
              album: matchAlbum,
              genre: matchGenre,
              year: int.tryParse(matchYear),
              pictures: pictures,
            );
            await AudioTags.write(fullPath, tag);
          } catch (e) {
            print("[autofillSingleTrack] Error writing tags to file: $e");
          }

          // Update local DB
          await DatabaseService.instance.updateMediaMetadata(filename, {
            'title': matchTitle,
            'artist': matchArtist,
            'album': matchAlbum,
            'genre': matchGenre,
            'year': matchYear,
            if (coverUrl != null) 'cover_url': coverUrl,
          });

          return {'title': matchTitle, 'artist': matchArtist};
        }
      }
    } catch (e) {
      print("[autofillSingleTrack] Error: $e");
    }
    return null;
  }

  Future<void> _runNativeAutofill(String jobId, List<String> filenames) async {
    final job = _nativeJobs[jobId]!;
    for (final filename in filenames) {
      if (job['status'] == 'cancelled') break;
      final basename = p.basename(filename);
      job['current'] = 'Buscando: $basename';
      
      try {
        final res = await autofillSingleTrack(filename);
        if (res != null) {
          // Automatically download lyrics for this autofilled track
          try {
            await saveLyrics(
              filename: filename,
              title: res['title']!,
              artist: res['artist']!,
            );
          } catch (e) {
            print("[NativeAutofill] Error downloading lyrics for $basename: $e");
          }
          job['completed'] = (job['completed'] as int) + 1;
          continue;
        }
      } catch (e) {
        print("[NativeAutofill] Error processing track $filename: $e");
      }
      job['failed'] = (job['failed'] as int) + 1;
    }
    job['status'] = 'done';
    job['current'] = 'Completado';
  }

  Future<bool> backgroundSyncMetadataAndLyrics() async {
    if (!isNative || _isBackgroundSyncing) return false;
    
    // Rate limit check: only run once every 5 minutes
    final now = DateTime.now();
    if (_lastSyncTime != null && now.difference(_lastSyncTime!) < const Duration(minutes: 5)) {
      return false;
    }
    _lastSyncTime = now;
    _isBackgroundSyncing = true;

    print('[BackgroundSync] Checking WAN internet connectivity...');

    // 1. Verify actual internet connectivity first by resolving google.com
    bool hasInternet = false;
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      hasInternet = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      hasInternet = false;
    }

    if (!hasInternet) {
      print('[BackgroundSync] No internet connection detected. Skipping sync.');
      _isBackgroundSyncing = false;
      return false;
    }

    print('[BackgroundSync] Internet connection detected. Starting background sync...');

    try {
      final rawTracks = await DatabaseService.instance.getAllDownloads();
      int metadataAutofilled = 0;
      int lyricsDownloaded = 0;
      
      for (final track in rawTracks) {
        final filename = track['filename'] as String? ?? '';
        String title = track['title'] as String? ?? '';
        String artist = track['artist'] as String? ?? '';
        final type = track['type'] as String? ?? 'music';

        if (filename.isEmpty || type == 'video') continue;

        final mFolder = musicFolder ?? '';
        if (mFolder.isEmpty) continue;

        // A candidate for metadata autofill if artist is empty/missing
        final isMissingMetadata = artist.isEmpty || 
                                  artist.trim().toLowerCase() == 'unknown' || 
                                  artist.trim().toLowerCase() == 'artista desconocido';

        if (isMissingMetadata) {
          print('[BackgroundSync] Autocompleting metadata for: $filename');
          final res = await autofillSingleTrack(filename);
          if (res != null) {
            title = res['title']!;
            artist = res['artist']!;
            metadataAutofilled++;
          }
        }

        // Now, if we have title/artist, check and download lyrics
        if (title.isNotEmpty && !LyricsService.hasLocal(mFolder, filename)) {
          try {
            print('[BackgroundSync] Downloading missing lyrics for: $title - $artist');
            final res = await saveLyrics(
              filename: filename,
              title: title,
              artist: artist,
            );
            if (res['saved'] == true) {
              lyricsDownloaded++;
            }
          } catch (e) {
            print('[BackgroundSync] Error downloading lyrics for $title: $e');
          }
        }
      }

      print('[BackgroundSync] Background sync finished. Autofilled: $metadataAutofilled, Lyrics downloaded: $lyricsDownloaded');
      _isBackgroundSyncing = false;
      return metadataAutofilled > 0;
    } catch (e) {
      print('[BackgroundSync] Error in background sync: $e');
    } finally {
      _isBackgroundSyncing = false;
    }
    return false;
  }

  Future<Map<String, dynamic>> getAutofillJobStatus(String jobId) async {
    if (isNative) {
      final job = _nativeJobs[jobId];
      if (job != null) {
        return job;
      }
      return {'job_id': jobId, 'status': 'done', 'progress': 100, 'total': 1, 'completed': 1, 'failed': 0, 'current': 'Completado'};
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
      final fullPath = p.join(musicFolder ?? '', filename);
      
      // Update physical file tags
      try {
        final file = File(fullPath);
        if (await file.exists()) {
          final tag = Tag(
            title: update['title'],
            trackArtist: update['artist'],
            album: update['album'],
            year: update['year'] != null ? int.tryParse(update['year'].toString()) : null,
            genre: update['genre'],
            pictures: const [],
          );
          await AudioTags.write(fullPath, tag);
          print("[api_client] Updated physical file tags for: $fullPath");
        }
      } catch (e) {
        print("[api_client] Error writing tags to physical file: $e");
      }

      await DatabaseService.instance.updateMediaMetadata(filename, {
        'title': update['title'],
        'artist': update['artist'],
        'album': update['album'],
        'year': update['year'],
        'genre': update['genre'],
      });

      // Download/update lyrics automatically
      try {
        await saveLyrics(
          filename: filename,
          title: update['title'] ?? '',
          artist: update['artist'] ?? '',
        );
      } catch (e) {
        print("[api_client] Error updating lyrics during metadata update: $e");
      }
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
    // Remove extension if present
    t = t.replaceAll(RegExp(r'\.(mp3|m4a|mp4|webm|mkv|avi|mov)$', caseSensitive: false), '');
    t = t.replaceAll(_youtubeSuffixes, '');
    t = t.replaceAll(_featuring, '');
    t = t.replaceAll(_extraParens, '');
    return t.replaceAll(RegExp(r'^[ \-|]+|[ \-|]+$'), '').trim();
  }

  Map<String, String> _extractArtistTitle(String rawTitle, String rawArtist) {
    // Strip extension before parsing
    var title = rawTitle.replaceAll(RegExp(r'\.(mp3|m4a|mp4|webm|mkv|avi|mov)$', caseSensitive: false), '');
    final cleaned = _cleanTitle(title);
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

  Future<Map<String, dynamic>> getPlaylistInfo(String url) async {
    // Tier 1: Try backend API first if configured and not standalone 'native'
    if (baseUrl != 'native' && baseUrl.startsWith('http')) {
      try {
        final encodedUrl = Uri.encodeQueryComponent(url);
        final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/playlist/info?url=$encodedUrl'))
            .timeout(const Duration(seconds: 8));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body) as Map<String, dynamic>;
          final videos = decoded['videos'] as List?;
          if (videos != null && videos.isNotEmpty) {
            print('[getPlaylistInfo] Successfully fetched playlist via backend API.');
            return decoded;
          }
        }
      } catch (e) {
        print('[getPlaylistInfo] Backend API fetch failed: $e. Trying native methods...');
      }
    }

    // Tier 2: Try custom HTML scraper with desktop User-Agent
    try {
      final res = await _getPlaylistInfoCustomScraper(url);
      print('[getPlaylistInfo] Successfully fetched playlist via custom HTML scraper.');
      return res;
    } catch (e) {
      print('[getPlaylistInfo] Custom HTML scraper failed: $e. Trying youtube_explode fallback...');
    }

    // Tier 3: Fallback to youtube_explode_dart
    final yt = YoutubeExplode();
    try {
      final uri = Uri.tryParse(url);
      final playlistIdStr = uri?.queryParameters['list'] ?? url;
      final playlistId = PlaylistId(playlistIdStr);
      final playlist = await yt.playlists.get(playlistId);
      
      final videos = <Map<String, dynamic>>[];
      await for (final video in yt.playlists.getVideos(playlist.id)) {
        videos.add({
          'url': video.url,
          'title': video.title,
          'duration': video.duration?.inSeconds,
        });
      }
      
      return {
        'title': playlist.title,
        'thumbnail': playlist.thumbnails.mediumResUrl,
        'videos': videos,
      };
    } finally {
      yt.close();
    }
  }

  Future<Map<String, dynamic>> _getPlaylistInfoCustomScraper(String url) async {
    final response = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
      'Accept-Language': 'es-ES,es;q=0.9,en;q=0.8',
      'Cookie': 'CONSENT=YES+cb.20210328-17-p0.en+FX+999; SOCS=CAESEwgDEgk0ODE3Nzk3MjQaAmVuIAEaBgiA_LyaBg',
    }).timeout(const Duration(seconds: 15));

    if (response.statusCode != 200) {
      throw Exception('Failed to load playlist page: ${response.statusCode}');
    }

    final html = response.body;
    final marker = 'ytInitialData =';
    final index = html.indexOf(marker);
    if (index == -1) {
      throw Exception('ytInitialData not found');
    }

    final start = index + marker.length;
    var braceCount = 0;
    var end = -1;
    var inString = false;
    var escape = false;

    for (var i = start; i < html.length; i++) {
      final char = html[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (char == '\\') {
        escape = true;
        continue;
      }
      if (char == '"') {
        inString = !inString;
        continue;
      }
      if (!inString) {
        if (char == '{') {
          braceCount++;
        } else if (char == '}') {
          braceCount--;
          if (braceCount == 0) {
            end = i + 1;
            break;
          }
        }
      }
    }

    if (end == -1) {
      throw Exception('Failed to locate end of ytInitialData JSON');
    }

    final jsonStr = html.substring(start, end).trim().replaceAll(RegExp(r';$'), '');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    var playlistTitle = 'YouTube Playlist';
    try {
      playlistTitle = data['metadata']?['playlistMetadataRenderer']?['title'] ?? 'YouTube Playlist';
    } catch (_) {}
    
    final videos = <Map<String, dynamic>>[];
    
    void findVideosRecursive(dynamic node) {
      if (node is Map) {
        // 1. Classic Layout
        if (node.containsKey('playlistVideoRenderer')) {
          final videoRenderer = node['playlistVideoRenderer'];
          final videoId = videoRenderer['videoId'] as String?;
          final title = videoRenderer['title']?['runs']?[0]?['text'] ?? videoRenderer['title']?['simpleText'];
          final lengthSecondsText = videoRenderer['lengthSeconds'] as String?;
          final lengthSecs = lengthSecondsText != null ? int.tryParse(lengthSecondsText) : null;
          if (videoId != null && title != null) {
            videos.add({
              'url': 'https://www.youtube.com/watch?v=$videoId',
              'title': title,
              'duration': lengthSecs,
            });
          }
        }
        // 2. New Lockup Layout
        if (node.containsKey('lockupViewModel')) {
          final lockup = node['lockupViewModel'];
          final contentId = lockup['contentId'] as String?;
          final title = lockup['metadata']?['lockupMetadataViewModel']?['title']?['content'] as String?;
          if (contentId != null && title != null) {
            videos.add({
              'url': 'https://www.youtube.com/watch?v=$contentId',
              'title': title,
              'duration': null,
            });
          }
        }
        for (var val in node.values) {
          findVideosRecursive(val);
        }
      } else if (node is List) {
        for (var val in node) {
          findVideosRecursive(val);
        }
      }
    }

    findVideosRecursive(data);

    if (videos.isEmpty) {
      throw Exception('No videos found in parsed HTML data');
    }

    var playlistThumbnail = '';
    if (videos.isNotEmpty) {
      final firstId = videos.first['url'].toString().split('v=').last;
      playlistThumbnail = 'https://img.youtube.com/vi/$firstId/mqdefault.jpg';
    }

    return {
      'title': playlistTitle,
      'thumbnail': playlistThumbnail,
      'videos': videos,
    };
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

  // ── Duplicates Endpoints ───────────────────────────────────────────────────

  Future<Map<String, dynamic>> getDuplicates() async {
    if (isNative) {
      if (musicFolder == null || musicFolder!.isEmpty) {
        return {'exact_duplicates': []};
      }
      
      final musicDir = Directory(musicFolder!);
      final videoDir = videoFolder != null && videoFolder!.isNotEmpty ? Directory(videoFolder!) : null;
      
      final allFiles = <File>[];
      final seenPaths = <String>{};
      
      final validExtensions = {'.mp3', '.m4a', '.mp4', '.webm', '.mkv', '.avi', '.mov'};
      
      Future<void> scanDir(Directory dir) async {
        if (!await dir.exists()) return;
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (validExtensions.contains(ext)) {
              final normPath = p.normalize(entity.path);
              if (!seenPaths.contains(normPath)) {
                seenPaths.add(normPath);
                allFiles.add(entity);
              }
            }
          }
        }
      }
      
      try {
        await scanDir(musicDir);
      } catch (e) {
        print("[ApiClient] Error scanning music folder for duplicates: $e");
      }
      
      if (videoDir != null && p.normalize(videoDir.path) != p.normalize(musicDir.path)) {
        try {
          await scanDir(videoDir);
        } catch (e) {
          print("[ApiClient] Error scanning video folder for duplicates: $e");
        }
      }
      
      // Group by size
      final filesBySize = <int, List<File>>{};
      for (final file in allFiles) {
        try {
          final stat = await file.stat();
          filesBySize.putIfAbsent(stat.size, () => []).add(file);
        } catch (_) {}
      }
      
      // Calculate MD5 for groups with multiple files
      final duplicatesByHash = <String, List<File>>{};
      for (final entry in filesBySize.entries) {
        if (entry.value.length < 2) continue;
        for (final file in entry.value) {
          try {
            final stream = file.openRead();
            final digest = await md5.bind(stream).first;
            final md5Hash = digest.toString();
            duplicatesByHash.putIfAbsent(md5Hash, () => []).add(file);
          } catch (_) {}
        }
      }
      
      // Construct return structure
      final db = await DatabaseService.instance.database;
      final exactGroups = <Map<String, dynamic>>[];
      
      for (final entry in duplicatesByHash.entries) {
        final hash = entry.key;
        final files = entry.value;
        if (files.length < 2) continue;
        
        final groupFiles = <Map<String, dynamic>>[];
        for (final file in files) {
          String filename;
          if (videoFolder != null && videoFolder!.isNotEmpty && p.normalize(file.path).startsWith(p.normalize(videoFolder!)) && videoFolder != musicFolder) {
            filename = 'videos/${p.relative(file.path, from: videoFolder!).replaceAll('\\', '/')}';
          } else {
            filename = p.relative(file.path, from: musicFolder!).replaceAll('\\', '/');
          }
          
          final mediaRows = await db.query('media', where: 'filename = ?', whereArgs: [filename]);
          final inDb = mediaRows.isNotEmpty;
          final stat = await file.stat();
          
          groupFiles.add({
            'filename': filename,
            'absolute_path': file.path.replaceAll('\\', '/'),
            'in_db': inDb,
            'size_mb': (stat.size / 1024 / 1024 * 100).round() / 100,
            'created_at': stat.changed.millisecondsSinceEpoch / 1000,
            'title': inDb ? (mediaRows.first['title'] ?? p.basenameWithoutExtension(file.path)) : p.basenameWithoutExtension(file.path),
            'artist': inDb ? (mediaRows.first['artist'] ?? '') : '',
          });
        }
        
        final sizeMb = groupFiles.first['size_mb'];
        exactGroups.add({
          'hash': hash,
          'size_mb': sizeMb,
          'files': groupFiles,
        });
      }
      
      return {'exact_duplicates': exactGroups};
    }
    
    final res = await http.get(Uri.parse('$baseUrl/api/v1/downloads/duplicates'));
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cleanDuplicates({bool dryRun = false}) async {
    if (isNative) {
      if (musicFolder == null || musicFolder!.isEmpty) {
        return {
          'dry_run': dryRun,
          'deleted_count': 0,
          'deleted_files': [],
          'space_saved_mb': 0.0,
        };
      }
      
      final dupResult = await getDuplicates();
      final exactDuplicates = dupResult['exact_duplicates'] as List;
      
      final deletedFiles = <String>[];
      var spaceSavedBytes = 0;
      
      final db = await DatabaseService.instance.database;
      
      for (final groupObj in exactDuplicates) {
        final group = groupObj as Map<String, dynamic>;
        final files = group['files'] as List;
        if (files.length < 2) continue;
        
        final groupItems = <Map<String, dynamic>>[];
        for (final fileObj in files) {
          final fileMap = fileObj as Map<String, dynamic>;
          final filename = fileMap['filename'] as String;
          final absolutePath = fileMap['absolute_path'] as String;
          
          final mediaRows = await db.query('media', where: 'filename = ?', whereArgs: [filename]);
          final dbEntry = mediaRows.isNotEmpty ? mediaRows.first : null;
          final file = File(absolutePath);
          final stat = await file.stat();
          final stem = p.basenameWithoutExtension(absolutePath);
          
          final hasDupSuffix = RegExp(r'\s*\(\d+\)$|\s*_\d+$').hasMatch(stem);
          
          groupItems.add({
            'path': file,
            'filename': filename,
            'db_entry': dbEntry,
            'ctime': stat.changed.millisecondsSinceEpoch / 1000,
            'size': stat.size,
            'has_dup_suffix': hasDupSuffix,
          });
        }
        
        // Prioritize winner
        groupItems.sort((a, b) {
          final hasDbA = a['db_entry'] != null;
          final hasDbB = b['db_entry'] != null;
          if (hasDbA && !hasDbB) return -1;
          if (!hasDbA && hasDbB) return 1;
          
          final suffixA = a['has_dup_suffix'] as bool;
          final suffixB = b['has_dup_suffix'] as bool;
          if (!suffixA && suffixB) return -1;
          if (suffixA && !suffixB) return 1;
          
          final num timeA = hasDbA ? (DateTime.tryParse(a['db_entry']['added_at'] as String)?.millisecondsSinceEpoch ?? 0) / 1000 : a['ctime'] as num;
          final num timeB = hasDbB ? (DateTime.tryParse(b['db_entry']['added_at'] as String)?.millisecondsSinceEpoch ?? 0) / 1000 : b['ctime'] as num;
          return timeA.compareTo(timeB);
        });
        
        final winner = groupItems.first;
        final losers = groupItems.sublist(1);
        
        final mediaWin = winner['db_entry'];
        
        for (final loser in losers) {
          final mediaDel = loser['db_entry'];
          
          if (mediaDel != null && mediaWin != null) {
            final winId = mediaWin['id'] as int;
            final delId = mediaDel['id'] as int;
            
            // Reassociate playlist media in database
            final playlistMedia = await db.query('playlist_media', where: 'media_id = ?', whereArgs: [delId]);
            for (final pm in playlistMedia) {
              final pmId = pm['id'] as int;
              final playlistId = pm['playlist_id'] as int;
              
              final exists = await db.query('playlist_media', 
                  where: 'playlist_id = ? AND media_id = ?', 
                  whereArgs: [playlistId, winId]);
                  
              if (exists.isEmpty) {
                await db.update('playlist_media', {'media_id': winId}, where: 'id = ?', whereArgs: [pmId]);
              } else {
                await db.delete('playlist_media', where: 'id = ?', whereArgs: [pmId]);
              }
            }
            
            await db.delete('media', where: 'id = ?', whereArgs: [delId]);
          } else if (mediaDel != null) {
            final delId = mediaDel['id'] as int;
            await db.delete('media', where: 'id = ?', whereArgs: [delId]);
          }
          
          // Delete file physically
          if (!dryRun) {
            try {
              final file = loser['path'] as File;
              if (await file.exists()) {
                await file.delete();
              }
            } catch (e) {
              print("[ApiClient] Error deleting duplicate file ${loser['filename']}: $e");
            }
          }
          
          deletedFiles.add(loser['filename'] as String);
          spaceSavedBytes += loser['size'] as int;
        }
      }
      
      return {
        'dry_run': dryRun,
        'deleted_count': deletedFiles.length,
        'deleted_files': deletedFiles,
        'space_saved_mb': (spaceSavedBytes / 1024 / 1024 * 100).round() / 100,
      };
    }
    
    final res = await http.post(
      Uri.parse('$baseUrl/api/v1/downloads/duplicates/clean'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'dry_run': dryRun}),
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
