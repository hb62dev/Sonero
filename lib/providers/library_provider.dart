import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart'; // Kept for backwards compatibility signatures
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
      final dbPlaylists = await DatabaseService.instance.getPlaylists();
      _playlists = [
        Playlist.library,
        ...dbPlaylists.map((e) => Playlist(name: e['name'], path: '')).toList(),
      ];
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
      }
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
      _applySort();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> createPlaylist(ApiClient api, String name) async {
    await DatabaseService.instance.createPlaylist(name);
    await loadPlaylists(api);
  }

  Future<void> renamePlaylist(ApiClient api, String oldName, String newName) async {
    await DatabaseService.instance.renamePlaylist(oldName, newName);
    await loadPlaylists(api);
  }

  Future<void> deletePlaylist(ApiClient api, String name) async {
    await DatabaseService.instance.deletePlaylist(name);
    if (_selected.name == name) _selected = Playlist.library;
    await loadPlaylists(api);
    await loadTracks(api);
  }

  Future<void> moveTrack(
    ApiClient api,
    Track track,
    String? toPlaylist,
  ) async {
    // Si viene de una playlist, se elimina de esa playlist
    if (track.playlist.isNotEmpty) {
      await DatabaseService.instance.removeMediaFromPlaylist(track.filename, track.playlist);
    }
    
    // Se añade a la nueva
    if (toPlaylist != null && toPlaylist.isNotEmpty) {
      await DatabaseService.instance.addMediaToPlaylist(track.filename, toPlaylist);
    }
    
    await loadTracks(api);
    await loadPlaylists(api);
  }

  Future<void> deleteTrack(ApiClient api, Track track) async {
    await DatabaseService.instance.deleteMedia(track.filename);
    await loadTracks(api);
  }
}
