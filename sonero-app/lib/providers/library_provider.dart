import 'dart:async';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/database_service.dart';

enum SortOption {
  dateAdded,
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
}

class LibraryProvider extends ChangeNotifier {
  List<Playlist> _playlists = [];
  Playlist _selected = Playlist.library;
  List<Track> _tracks = [];
  bool _loading = false;
  String? _error;
  SortOption _sortOption = SortOption.dateAdded;

  List<Playlist> get playlists => _playlists;
  Playlist get selected => _selected;
  List<Track> get tracks => _tracks;
  bool get loading => _loading;
  String? get error => _error;
  SortOption get sortOption => _sortOption;

  void setSortOption(SortOption option) {
    _sortOption = option;
    _applySort();
    notifyListeners();
  }

  void _applySort() {
    switch (_sortOption) {
      case SortOption.titleAsc:
        _tracks.sort((a, b) {
          final tA = a.title.isNotEmpty ? a.title : a.filename;
          final tB = b.title.isNotEmpty ? b.title : b.filename;
          return tA.toLowerCase().compareTo(tB.toLowerCase());
        });
        break;
      case SortOption.titleDesc:
        _tracks.sort((a, b) {
          final tA = a.title.isNotEmpty ? a.title : a.filename;
          final tB = b.title.isNotEmpty ? b.title : b.filename;
          return tB.toLowerCase().compareTo(tA.toLowerCase());
        });
        break;
      case SortOption.artistAsc:
        _tracks.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case SortOption.artistDesc:
        _tracks.sort((a, b) => b.artist.toLowerCase().compareTo(a.artist.toLowerCase()));
        break;
      case SortOption.dateAdded:
        _tracks.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
    }
  }

  Future<void> loadPlaylists(ApiClient api) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      if (api.isNative) {
        final dbPlaylists = await DatabaseService.instance.getPlaylists();
        _playlists = [
          Playlist.library,
          ...dbPlaylists.map((e) => Playlist(name: e['name'], path: '')).toList(),
        ];
      } else {
        final data = await api.getPlaylists();
        _playlists = [
          Playlist.library,
          ...(data['playlists'] as List)
              .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
              .toList(),
        ];
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> selectPlaylist(ApiClient api, Playlist playlist) async {
    _selected = playlist;
    _tracks = [];
    notifyListeners();
    await loadTracks(api);
  }

  Future<void> loadTracks(ApiClient api) async {
    _loading = true;
    notifyListeners();
    try {
      if (api.isNative) {
        await DatabaseService.instance.syncWithFileSystem(
          musicFolder: api.musicFolder,
          videoFolder: api.videoFolder,
        );
        if (_selected.isLibrary) {
          final data = await DatabaseService.instance.getAllDownloads();
          _tracks = data
              .map((e) => Track.fromApiFile(e, baseUrl: ''))
              .toList();
        } else {
          final data = await DatabaseService.instance.getPlaylistTracks(_selected.name);
          _tracks = data
              .map((e) => Track.fromApiFile(e, playlist: _selected.name, baseUrl: ''))
              .toList();
        }
      } else {
        if (_selected.isLibrary) {
          final data = await api.getDownloads();
          _tracks = (data['downloads'] as List)
              .map((e) => Track.fromApiFile(e as Map<String, dynamic>, baseUrl: api.baseUrl))
              .toList();
        } else {
          final data = await api.getPlaylistTracks(_selected.name);
          _tracks = (data['tracks'] as List)
              .map((e) => Track.fromApiFile(e as Map<String, dynamic>, playlist: _selected.name, baseUrl: api.baseUrl))
              .toList();
        }
      }
      _applySort();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> createPlaylist(ApiClient api, String name) async {
    if (api.isNative) {
      await DatabaseService.instance.createPlaylist(name);
    } else {
      await api.createPlaylist(name);
    }
    await loadPlaylists(api);
  }

  Future<void> renamePlaylist(ApiClient api, String oldName, String newName) async {
    if (api.isNative) {
      await DatabaseService.instance.renamePlaylist(oldName, newName);
    } else {
      await api.renamePlaylist(oldName, newName);
    }
    await loadPlaylists(api);
  }

  Future<void> deletePlaylist(ApiClient api, String name) async {
    if (api.isNative) {
      await DatabaseService.instance.deletePlaylist(name);
    } else {
      await api.deletePlaylist(name);
    }
    if (_selected.name == name) _selected = Playlist.library;
    await loadPlaylists(api);
    await loadTracks(api);
  }

  Future<void> moveTrack(
    ApiClient api,
    Track track,
    String? toPlaylist,
  ) async {
    if (api.isNative) {
      // Si viene de una playlist, se elimina de esa playlist
      if (track.playlist.isNotEmpty) {
        await DatabaseService.instance.removeMediaFromPlaylist(track.filename, track.playlist);
      }
      
      // Se añade a la nueva
      if (toPlaylist != null && toPlaylist.isNotEmpty) {
        await DatabaseService.instance.addMediaToPlaylist(track.filename, toPlaylist);
      }
    } else {
      await api.moveTrack(
        filename: track.filename,
        fromPlaylist: track.playlist.isEmpty ? null : track.playlist,
        toPlaylist: toPlaylist,
      );
    }
    await loadTracks(api);
    await loadPlaylists(api);
  }

  Future<void> deleteTrack(ApiClient api, Track track) async {
    if (api.isNative) {
      final isVideo = track.filename.toLowerCase().endsWith('.mp4') ||
          track.filename.toLowerCase().endsWith('.mkv') ||
          track.filename.toLowerCase().endsWith('.avi') ||
          track.filename.toLowerCase().endsWith('.mov') ||
          track.filename.toLowerCase().endsWith('.webm') ||
          track.filename.startsWith('videos/');

      final activeFolder = isVideo ? (api.videoFolder ?? api.musicFolder) : api.musicFolder;
      if (activeFolder != null && activeFolder.isNotEmpty) {
        final cleanFilename = track.filename.startsWith('videos/') ? track.filename.substring(7) : track.filename;
        final file = File(p.join(activeFolder, cleanFilename));
        
        try {
          if (await file.exists()) {
            await file.delete();
            print("[LibraryProvider] Deleted physical file: ${file.path}");
          }
        } catch (e) {
          print("[LibraryProvider] Error deleting physical file: $e");
        }

        // Also delete lyric files if present
        try {
          final stem = p.basenameWithoutExtension(cleanFilename);
          
          // 1. Delete from lyrics/ folder
          final lrcFile = File(p.join(activeFolder, 'lyrics', '$stem.lrc'));
          if (await lrcFile.exists()) await lrcFile.delete();
          final txtFile = File(p.join(activeFolder, 'lyrics', '$stem.txt'));
          if (await txtFile.exists()) await txtFile.delete();
          
          // 2. Delete next to the audio file if it is there
          final dirPath = p.dirname(file.path);
          final localLrc = File(p.join(dirPath, '$stem.lrc'));
          if (await localLrc.exists()) await localLrc.delete();
          final localTxt = File(p.join(dirPath, '$stem.txt'));
          if (await localTxt.exists()) await localTxt.delete();
        } catch (e) {
          print("[LibraryProvider] Error deleting lyric files: $e");
        }
      }
      await DatabaseService.instance.deleteMedia(track.filename);
    } else {
      await api.deleteTrack(track.filename);
    }
    await loadTracks(api);
  }
}
