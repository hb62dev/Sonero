import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:audiotags/audiotags.dart';
import 'package:permission_handler/permission_handler.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('media.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getApplicationSupportDirectory();
    final path = p.join(dbPath.path, filePath);

    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS logs (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT,
          message TEXT
        )
      ''');
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE media (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        type TEXT,
        title TEXT,
        artist TEXT,
        album TEXT,
        genre TEXT,
        year TEXT,
        filename TEXT UNIQUE,
        format TEXT,
        cover_url TEXT,
        shazam_url TEXT,
        added_at TEXT,
        tags TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE playlists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE,
        is_smart INTEGER DEFAULT 0,
        created_at TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE playlist_media (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        playlist_id INTEGER,
        media_id INTEGER,
        added_at TEXT,
        FOREIGN KEY (playlist_id) REFERENCES playlists (id) ON DELETE CASCADE,
        FOREIGN KEY (media_id) REFERENCES media (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        timestamp TEXT,
        message TEXT
      )
    ''');
  }

  // --- Playlists ---

  Future<List<Map<String, dynamic>>> getPlaylists() async {
    final db = await instance.database;
    final result = await db.query('playlists');
    return result;
  }

  Future<int> createPlaylist(String name) async {
    final db = await instance.database;
    return await db.insert('playlists', {
      'name': name,
      'is_smart': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> renamePlaylist(String oldName, String newName) async {
    final db = await instance.database;
    return await db.update(
      'playlists',
      {'name': newName},
      where: 'name = ?',
      whereArgs: [oldName],
    );
  }

  Future<int> deletePlaylist(String name) async {
    final db = await instance.database;
    return await db.delete(
      'playlists',
      where: 'name = ?',
      whereArgs: [name],
    );
  }

  Future<List<Map<String, dynamic>>> getPlaylistTracks(String playlistName) async {
    final db = await instance.database;
    final playlistRes = await db.query('playlists', where: 'name = ?', whereArgs: [playlistName]);
    if (playlistRes.isEmpty) return [];

    final playlistId = playlistRes.first['id'];
    
    // Join playlist_media and media
    final result = await db.rawQuery('''
      SELECT m.*, pm.added_at as added_to_playlist
      FROM media m
      INNER JOIN playlist_media pm ON m.id = pm.media_id
      WHERE pm.playlist_id = ?
      ORDER BY pm.added_at ASC
    ''', [playlistId]);
    return result;
  }

  // --- Tracks / Media ---

  Future<int> insertMedia(Map<String, dynamic> media) async {
    final db = await instance.database;
    
    // Convert tags to JSON string if it's a list
    if (media['tags'] is List) {
      media['tags'] = jsonEncode(media['tags']);
    }
    
    if (!media.containsKey('added_at') || media['added_at'] == null) {
      media['added_at'] = DateTime.now().toIso8601String();
    }

    return await db.insert('media', media, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getAllDownloads() async {
    final db = await instance.database;
    return await db.query('media', orderBy: 'added_at DESC');
  }

  Future<Map<String, dynamic>?> getMediaByFilename(String filename) async {
    final db = await instance.database;
    final maps = await db.query('media', where: 'filename = ?', whereArgs: [filename]);
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<int> deleteMedia(String filename) async {
    final db = await instance.database;
    return await db.delete('media', where: 'filename = ?', whereArgs: [filename]);
  }

  Future<int> updateMediaMetadata(String filename, Map<String, dynamic> updates) async {
    final db = await instance.database;
    return await db.update('media', updates, where: 'filename = ?', whereArgs: [filename]);
  }

  // --- Playlist Media linking ---

  Future<int> addMediaToPlaylist(String filename, String playlistName) async {
    final db = await instance.database;
    
    final pRes = await db.query('playlists', where: 'name = ?', whereArgs: [playlistName]);
    if (pRes.isEmpty) return 0;
    
    final mRes = await db.query('media', where: 'filename = ?', whereArgs: [filename]);
    if (mRes.isEmpty) return 0;

    return await db.insert('playlist_media', {
      'playlist_id': pRes.first['id'],
      'media_id': mRes.first['id'],
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> removeMediaFromPlaylist(String filename, String playlistName) async {
    final db = await instance.database;
    
    final pRes = await db.query('playlists', where: 'name = ?', whereArgs: [playlistName]);
    if (pRes.isEmpty) return 0;
    
    final mRes = await db.query('media', where: 'filename = ?', whereArgs: [filename]);
    if (mRes.isEmpty) return 0;

    return await db.delete('playlist_media', 
      where: 'playlist_id = ? AND media_id = ?', 
      whereArgs: [pRes.first['id'], mRes.first['id']]);
  }

  Future<void> syncWithFileSystem({String? musicFolder, String? videoFolder}) async {
    if (musicFolder == null || musicFolder.isEmpty) return;

    // Request permissions on Android
    if (Platform.isAndroid) {
      try {
        final statusAudio = await Permission.audio.status;
        final statusVideo = await Permission.videos.status;
        final statusStorage = await Permission.storage.status;
        final statusManage = await Permission.manageExternalStorage.status;

        if (!statusAudio.isGranted || !statusVideo.isGranted || !statusStorage.isGranted || !statusManage.isGranted) {
          await [
            Permission.audio,
            Permission.videos,
            Permission.storage,
            Permission.manageExternalStorage,
          ].request();
        }
      } catch (e) {
        print("[DatabaseService] Permission request warning: $e");
      }
    }

    final db = await database;
    final Set<String> existingFiles = {};

    // 0. Scan immediate subdirectories to register all folders as playlists (even if empty)
    try {
      final musicDir = Directory(musicFolder);
      if (await musicDir.exists()) {
        await for (final entity in musicDir.list(recursive: false)) {
          if (entity is Directory) {
            final dirName = p.basename(entity.path);
            if (dirName != 'lyrics' && dirName != '.git' && dirName != 'covers') {
              final pRes = await db.query('playlists', where: 'name = ?', whereArgs: [dirName]);
              if (pRes.isEmpty) {
                await db.insert('playlists', {
                  'name': dirName,
                  'is_smart': 0,
                  'created_at': DateTime.now().toIso8601String(),
                });
                print("[DatabaseService] Registered subdirectory playlist: $dirName");
              }
            }
          }
        }
      }
    } catch (e) {
      print("[DatabaseService] Error scanning subdirectory playlists: $e");
    }

    // 1. Scan Music Folder
    try {
      final musicDir = Directory(musicFolder);
      if (await musicDir.exists()) {
        await for (final entity in musicDir.list(recursive: true)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.mp3' || ext == '.m4a') {
              final relativePath = p.relative(entity.path, from: musicFolder).replaceAll('\\', '/');
              existingFiles.add(relativePath);

              // Check if already exists in DB
              final existing = await db.query('media', where: 'filename = ?', whereArgs: [relativePath]);
              int? mediaId;

              if (existing.isEmpty) {
                // Read tags for this new file
                String title = p.basenameWithoutExtension(entity.path);
                String artist = '';
                String album = '';
                String genre = '';
                String year = '';
                String? coverUrl;

                try {
                  final tag = await AudioTags.read(entity.path);
                  if (tag != null) {
                    if (tag.title != null && tag.title!.trim().isNotEmpty) {
                      title = tag.title!.trim();
                    }
                    if (tag.trackArtist != null && tag.trackArtist!.trim().isNotEmpty) {
                      artist = tag.trackArtist!.trim();
                    }
                    if (tag.album != null && tag.album!.trim().isNotEmpty) {
                      album = tag.album!.trim();
                    }
                    if (tag.genre != null && tag.genre!.trim().isNotEmpty) {
                      genre = tag.genre!.trim();
                    }
                    if (tag.year != null) {
                      year = tag.year!.toString();
                    }

                    // Extract embedded album art cover
                    if (tag.pictures != null && tag.pictures!.isNotEmpty) {
                      final picture = tag.pictures!.first;
                      final supportDir = await getApplicationSupportDirectory();
                      final coversDir = Directory(p.join(supportDir.path, 'covers'));
                      if (!await coversDir.exists()) {
                        await coversDir.create(recursive: true);
                      }
                      final filenameHash = relativePath.hashCode.toString();
                      final picExt = picture.mimeType == MimeType.png ? 'png' : 'jpg';
                      final coverFile = File(p.join(coversDir.path, '$filenameHash.$picExt'));
                      await coverFile.writeAsBytes(picture.bytes);
                      coverUrl = coverFile.path.replaceAll('\\', '/');
                    }
                  }
                } catch (e) {
                  print("[DatabaseService] Error reading tags for ${entity.path}: $e");
                }

                // Add to DB
                mediaId = await db.insert('media', {
                  'type': 'music',
                  'title': title,
                  'artist': artist,
                  'album': album,
                  'genre': genre,
                  'year': year,
                  'filename': relativePath,
                  'format': ext.replaceAll('.', ''),
                  'cover_url': coverUrl,
                  'added_at': DateTime.now().toIso8601String(),
                });
                print("[DatabaseService] Synced new music file: $relativePath");
              } else {
                final existingRow = existing.first;
                mediaId = existingRow['id'] as int;
                final existingCover = existingRow['cover_url'] as String?;

                // Proactively extract cover art if missing for existing database row
                if (existingCover == null || existingCover.isEmpty) {
                  try {
                    final tag = await AudioTags.read(entity.path);
                    if (tag != null && tag.pictures != null && tag.pictures!.isNotEmpty) {
                      final picture = tag.pictures!.first;
                      final supportDir = await getApplicationSupportDirectory();
                      final coversDir = Directory(p.join(supportDir.path, 'covers'));
                      if (!await coversDir.exists()) {
                        await coversDir.create(recursive: true);
                      }
                      final filenameHash = relativePath.hashCode.toString();
                      final picExt = picture.mimeType == MimeType.png ? 'png' : 'jpg';
                      final coverFile = File(p.join(coversDir.path, '$filenameHash.$picExt'));
                      await coverFile.writeAsBytes(picture.bytes);
                      final coverUrl = coverFile.path.replaceAll('\\', '/');
                      await db.update('media', {'cover_url': coverUrl}, where: 'id = ?', whereArgs: [mediaId]);
                      print("[DatabaseService] Updated cover for existing music file: $relativePath");
                    }
                  } catch (e) {
                    print("[DatabaseService] Error reading tags/cover for existing track ${entity.path}: $e");
                  }
                }
              }

              // Handle subdirectory playlist mapping
              final parts = relativePath.split('/');
              if (parts.length > 1 && mediaId != null) {
                final playlistName = parts.first;

                // Ensure playlist exists in DB
                final pRes = await db.query('playlists', where: 'name = ?', whereArgs: [playlistName]);
                int playlistId;
                if (pRes.isEmpty) {
                  playlistId = await db.insert('playlists', {
                    'name': playlistName,
                    'is_smart': 0,
                    'created_at': DateTime.now().toIso8601String(),
                  });
                } else {
                  playlistId = pRes.first['id'] as int;
                }

                // Ensure relation exists in playlist_media
                final pmRes = await db.query('playlist_media',
                    where: 'playlist_id = ? AND media_id = ?',
                    whereArgs: [playlistId, mediaId]);
                if (pmRes.isEmpty) {
                  await db.insert('playlist_media', {
                    'playlist_id': playlistId,
                    'media_id': mediaId,
                    'added_at': DateTime.now().toIso8601String(),
                  });
                  print("[DatabaseService] Linked track $relativePath to playlist $playlistName");
                }
              }
            }
          }
        }
      }
    } catch (e) {
      print("[DatabaseService] Error scanning music folder: $e");
    }

    // 2. Scan Video Folder (if different/exists)
    if (videoFolder != null && videoFolder.isNotEmpty) {
      try {
        final videoDir = Directory(videoFolder);
        if (await videoDir.exists()) {
          await for (final entity in videoDir.list(recursive: true)) {
            if (entity is File) {
              final ext = p.extension(entity.path).toLowerCase();
              if (ext == '.mp4' || ext == '.webm' || ext == '.mkv') {
                final relPath = p.relative(entity.path, from: videoFolder).replaceAll('\\', '/');
                final dbFilename = videoFolder != musicFolder ? 'videos/$relPath' : relPath;
                existingFiles.add(dbFilename);

                // Check if already exists in DB
                final existing = await db.query('media', where: 'filename = ?', whereArgs: [dbFilename]);
                if (existing.isEmpty) {
                  final title = p.basenameWithoutExtension(entity.path);
                  await db.insert('media', {
                    'type': 'video',
                    'title': title,
                    'filename': dbFilename,
                    'format': ext.replaceAll('.', ''),
                    'added_at': DateTime.now().toIso8601String(),
                  });
                  print("[DatabaseService] Synced new video file: $dbFilename");
                }
              }
            }
          }
        }
      } catch (e) {
        print("[DatabaseService] Error scanning video folder: $e");
      }
    }

    // 3. Clean up database records for files that don't exist on disk
    try {
      final dbList = await db.query('media');
      for (final row in dbList) {
        final filename = row['filename'] as String;
        if (!existingFiles.contains(filename)) {
          // Double check if file really doesn't exist on disk
          final isVideo = row['type'] == 'video' || filename.startsWith('videos/');
          String fullPath;
          if (isVideo) {
            final cleanFilename = filename.startsWith('videos/') ? filename.substring(7) : filename;
            fullPath = p.join(videoFolder ?? musicFolder, cleanFilename);
          } else {
            fullPath = p.join(musicFolder, filename);
          }

          if (!await File(fullPath).exists()) {
            await db.delete('media', where: 'filename = ?', whereArgs: [filename]);
            print("[DatabaseService] Cleaned up missing file: $filename");
          }
        }
      }
    } catch (e) {
      print("[DatabaseService] Error cleaning up missing files: $e");
    }

    // 4. Clean up playlists in DB whose physical directories no longer exist
    try {
      final playlists = await db.query('playlists');
      for (final playlist in playlists) {
        final name = playlist['name'] as String;
        final isSmart = playlist['is_smart'] as int? ?? 0;
        if (isSmart == 0) {
          final dir = Directory(p.join(musicFolder, name));
          if (!await dir.exists()) {
            await db.delete('playlists', where: 'name = ?', whereArgs: [name]);
            print("[DatabaseService] Cleaned up missing playlist: $name");
          }
        }
      }
    } catch (e) {
      print("[DatabaseService] Error cleaning up missing playlists: $e");
    }
  }

  // --- Diagnostic Logs ---

  Future<int> insertLog(String timestamp, String message) async {
    final db = await instance.database;
    return await db.insert('logs', {
      'timestamp': timestamp,
      'message': message,
    });
  }

  Future<List<Map<String, dynamic>>> getLogs() async {
    final db = await instance.database;
    return await db.query('logs', orderBy: 'id DESC', limit: 200);
  }

  Future<int> clearLogs() async {
    final db = await instance.database;
    return await db.delete('logs');
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
