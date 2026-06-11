import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:audiotags/audiotags.dart';

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
    final result = await db.rawQuery('''
      SELECT p.*, COUNT(pm.media_id) as track_count
      FROM playlists p
      LEFT JOIN playlist_media pm ON p.id = pm.playlist_id
      GROUP BY p.id
    ''');
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

                if (coverUrl == null || coverUrl.isEmpty) {
                  coverUrl = await _fallbackGetCover(entity.path, relativePath);
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

                // Proactively extract cover art if missing or is a remote URL
                final isRemote = existingCover != null && (existingCover.startsWith('http://') || existingCover.startsWith('https://'));
                if (existingCover == null || existingCover.isEmpty || isRemote) {
                  bool localSaved = false;
                  // Try to extract from file tags first
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
                      localSaved = true;
                    }
                  } catch (e) {
                    print("[DatabaseService] Error reading tags/cover for existing track ${entity.path}: $e");
                  }

                  if (!localSaved) {
                    final fallbackCover = await _fallbackGetCover(entity.path, relativePath);
                    if (fallbackCover != null) {
                      await db.update('media', {'cover_url': fallbackCover}, where: 'id = ?', whereArgs: [mediaId]);
                      localSaved = true;
                    }
                  }

                  // If still not saved and it was a remote URL, download it locally
                  if (!localSaved && isRemote) {
                    try {
                      final supportDir = await getApplicationSupportDirectory();
                      final coversDir = Directory(p.join(supportDir.path, 'covers'));
                      if (!await coversDir.exists()) {
                        await coversDir.create(recursive: true);
                      }
                      final filenameHash = relativePath.hashCode.toString();
                      final coverFile = File(p.join(coversDir.path, '$filenameHash.jpg'));
                      final dio = Dio();
                      await dio.download(existingCover!, coverFile.path);
                      final coverUrl = coverFile.path.replaceAll('\\', '/');
                      await db.update('media', {'cover_url': coverUrl}, where: 'id = ?', whereArgs: [mediaId]);
                      print("[DatabaseService] Cached remote cover locally for: $relativePath");
                    } catch (e) {
                      print("[DatabaseService] Error caching remote cover locally for $relativePath: $e");
                    }
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
                } else {
                  final existingRow = existing.first;
                  final mediaId = existingRow['id'] as int;
                  final existingCover = existingRow['cover_url'] as String?;
                  final isRemote = existingCover != null && (existingCover.startsWith('http://') || existingCover.startsWith('https://'));
                  if (isRemote) {
                    try {
                      final supportDir = await getApplicationSupportDirectory();
                      final coversDir = Directory(p.join(supportDir.path, 'covers'));
                      if (!await coversDir.exists()) {
                        await coversDir.create(recursive: true);
                      }
                      final filenameHash = dbFilename.hashCode.toString();
                      final coverFile = File(p.join(coversDir.path, '$filenameHash.jpg'));
                      final dio = Dio();
                      await dio.download(existingCover!, coverFile.path);
                      final coverUrl = coverFile.path.replaceAll('\\', '/');
                      await db.update('media', {'cover_url': coverUrl}, where: 'id = ?', whereArgs: [mediaId]);
                      print("[DatabaseService] Cached remote video cover locally: $dbFilename");
                    } catch (e) {
                      print("[DatabaseService] Error caching remote video cover locally for $dbFilename: $e");
                    }
                  }
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

  Future<Uint8List?> _extractId3v2Cover(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      // Read header (10 bytes)
      final header = await raf.read(10);
      if (header.length < 10) return null;
      
      // Check magic "ID3"
      if (header[0] != 0x49 || header[1] != 0x44 || header[2] != 0x33) return null;
      
      final versionMajor = header[3];
      if (versionMajor < 2 || versionMajor > 4) return null; // Only ID3v2.2, ID3v2.3, ID3v2.4
      
      // Size is synchsafe integer (4 bytes, MSB is 0)
      int size = ((header[6] & 0x7F) << 21) |
                 ((header[7] & 0x7F) << 14) |
                 ((header[8] & 0x7F) << 7)  |
                 (header[9] & 0x7F);
                 
      // Let's read the tag content
      final tagData = await raf.read(size);
      if (tagData.length < size) {
        size = tagData.length;
      }
      
      // Parse frames in tagData
      int offset = 0;
      while (offset < size - 10) {
        String frameId;
        int frameSize;
        int headerSize;
        
        if (versionMajor == 2) {
          if (offset + 6 > size) break;
          frameId = String.fromCharCodes(tagData.sublist(offset, offset + 3));
          frameSize = (tagData[offset + 3] << 16) | (tagData[offset + 4] << 8) | tagData[offset + 5];
          headerSize = 6;
        } else {
          if (offset + 10 > size) break;
          frameId = String.fromCharCodes(tagData.sublist(offset, offset + 4));
          if (versionMajor == 4) {
            // ID3v2.4 size is synchsafe
            frameSize = ((tagData[offset + 4] & 0x7F) << 21) |
                        ((tagData[offset + 5] & 0x7F) << 14) |
                        ((tagData[offset + 6] & 0x7F) << 7)  |
                        (tagData[offset + 7] & 0x7F);
          } else {
            // ID3v2.3 size is normal 32-bit int
            frameSize = (tagData[offset + 4] << 24) |
                        (tagData[offset + 5] << 16) |
                        (tagData[offset + 6] << 8)  |
                        tagData[offset + 7];
          }
          headerSize = 10;
        }
        
        if (frameSize <= 0 || offset + headerSize + frameSize > size) {
          break;
        }
        
        final isApic = (versionMajor == 2 && frameId == "PIC") || (versionMajor > 2 && frameId == "APIC");
        if (isApic) {
          final frameData = tagData.sublist(offset + headerSize, offset + headerSize + frameSize);
          int dataOffset = 1; // skip encoding byte
          
          if (versionMajor == 2) {
            // Format (3 bytes, e.g. "JPG" or "PNG")
            dataOffset += 3;
            if (dataOffset < frameData.length) {
              dataOffset += 1; // Picture Type (1 byte)
            }
            // Description (null terminated)
            while (dataOffset < frameData.length && frameData[dataOffset] != 0) {
              dataOffset++;
            }
            dataOffset++; // skip null terminator
          } else {
            // MIME type (null terminated)
            while (dataOffset < frameData.length && frameData[dataOffset] != 0) {
              dataOffset++;
            }
            dataOffset++; // skip null terminator
            
            // Picture Type (1 byte)
            if (dataOffset < frameData.length) {
              dataOffset += 1;
            }
            
            // Description (null terminated)
            final encoding = frameData[0];
            if (encoding == 1 || encoding == 2) {
              // UTF-16, double null terminated
              while (dataOffset < frameData.length - 1 && (frameData[dataOffset] != 0 || frameData[dataOffset + 1] != 0)) {
                dataOffset += 2;
              }
              dataOffset += 2; // skip both nulls
            } else {
              while (dataOffset < frameData.length && frameData[dataOffset] != 0) {
                dataOffset++;
              }
              dataOffset++; // skip null
            }
          }
          
          if (dataOffset < frameData.length) {
            return Uint8List.fromList(frameData.sublist(dataOffset));
          }
          break;
        }
        
        offset += headerSize + frameSize;
      }
    } catch (e) {
      print("[DatabaseService] Pure Dart ID3 APIC extraction error: $e");
    } finally {
      if (raf != null) {
        await raf.close();
      }
    }
    return null;
  }

  Future<Uint8List?> _extractM4aCover(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return null;

    RandomAccessFile? raf;
    try {
      raf = await file.open(mode: FileMode.read);
      final length = await raf.length();
      
      Future<Uint8List?> findCovr(int offset, int limit) async {
        int pos = offset;
        while (pos < limit - 8) {
          await raf!.setPosition(pos);
          final header = await raf!.read(8);
          if (header.length < 8) break;
          
          final size = (header[0] << 24) | (header[1] << 16) | (header[2] << 8) | header[3];
          final type = String.fromCharCodes(header.sublist(4, 8));
          
          if (size <= 0) break;
          
          if (type == 'covr') {
            await raf!.setPosition(pos + 8);
            final subHeader = await raf!.read(8);
            if (subHeader.length < 8) return null;
            final subSize = (subHeader[0] << 24) | (subHeader[1] << 16) | (subHeader[2] << 8) | subHeader[3];
            final subType = String.fromCharCodes(subHeader.sublist(4, 8));
            if (subType == 'data') {
              final imageSize = subSize - 16;
              if (imageSize > 0 && pos + 8 + 16 + imageSize <= length) {
                await raf!.setPosition(pos + 8 + 16);
                final imgBytes = await raf!.read(imageSize);
                return Uint8List.fromList(imgBytes);
              }
            }
            return null;
          } else if (type == 'moov' || type == 'udta' || type == 'meta' || type == 'ilst') {
            int startOffset = pos + 8;
            if (type == 'meta') {
              startOffset += 4; // skip 4 bytes version/flags
            }
            final res = await findCovr(startOffset, pos + size);
            if (res != null) return res;
          }
          
          pos += size;
        }
        return null;
      }
      
      return await findCovr(0, length);
    } catch (e) {
      print("[DatabaseService] Pure Dart M4A covr extraction error: $e");
    } finally {
      if (raf != null) {
        await raf.close();
      }
    }
    return null;
  }

  Future<String?> _fallbackGetCover(String filePath, String relativePath) async {
    // 1. Try to extract from file tags using pure Dart
    try {
      final ext = p.extension(filePath).toLowerCase();
      Uint8List? bytes;
      if (ext == '.mp3') {
        bytes = await _extractId3v2Cover(filePath);
      } else if (ext == '.m4a') {
        bytes = await _extractM4aCover(filePath);
      }
      
      if (bytes != null && bytes.isNotEmpty) {
        final supportDir = await getApplicationSupportDirectory();
        final coversDir = Directory(p.join(supportDir.path, 'covers'));
        if (!await coversDir.exists()) {
          await coversDir.create(recursive: true);
        }
        final filenameHash = relativePath.hashCode.toString();
        // Detect magic bytes for jpeg (FF D8 FF) or png (89 50 4E 47)
        String picExt = 'jpg';
        if (bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
          picExt = 'png';
        }
        final coverFile = File(p.join(coversDir.path, '$filenameHash.$picExt'));
        await coverFile.writeAsBytes(bytes);
        print("[DatabaseService] Extracted embedded cover for $relativePath to ${coverFile.path}");
        return coverFile.path.replaceAll('\\', '/');
      }
    } catch (e) {
      print("[DatabaseService] Error extracting fallback tags cover: $e");
    }

    // 2. Try to search for a folder image (cover.jpg, folder.jpg, etc.) in the same directory
    try {
      final dirPath = p.dirname(filePath);
      final possibleNames = ['cover.jpg', 'cover.png', 'folder.jpg', 'folder.png', 'album.jpg', 'album.png', 'cover.jpeg', 'folder.jpeg', 'album.jpeg'];
      for (final name in possibleNames) {
        final coverImgFile = File(p.join(dirPath, name));
        if (await coverImgFile.exists()) {
          print("[DatabaseService] Found local folder cover image for $relativePath at ${coverImgFile.path}");
          return coverImgFile.path.replaceAll('\\', '/');
        }
      }
    } catch (e) {
      print("[DatabaseService] Error searching folder cover image: $e");
    }

    return null;
  }

  Future close() async {
    final db = await instance.database;
    db.close();
  }
}
