import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/playlist.dart';
import '../models/track.dart';

class LibraryProvider extends ChangeNotifier {
  List<Playlist> _playlists = [];
  Playlist _selected = Playlist.library;
  List<Track> _tracks = [];
  bool _loading = false;
  String? _error;

  List<Playlist> get playlists => _playlists;
  Playlist get selected => _selected;
  List<Track> get tracks => _tracks;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> loadPlaylists(ApiClient api) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final data = await api.getPlaylists();
      _playlists = [
        Playlist.library,
        ...(data['playlists'] as List)
            .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
            .toList(),
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
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> createPlaylist(ApiClient api, String name) async {
    await api.createPlaylist(name);
    await loadPlaylists(api);
  }

  Future<void> renamePlaylist(ApiClient api, String oldName, String newName) async {
    await api.renamePlaylist(oldName, newName);
    await loadPlaylists(api);
  }

  Future<void> deletePlaylist(ApiClient api, String name) async {
    await api.deletePlaylist(name);
    if (_selected.name == name) _selected = Playlist.library;
    await loadPlaylists(api);
    await loadTracks(api);
  }

  Future<void> moveTrack(
    ApiClient api,
    Track track,
    String? toPlaylist,
  ) async {
    await api.moveTrack(
      filename: track.filename,
      fromPlaylist: track.playlist.isEmpty ? null : track.playlist,
      toPlaylist: toPlaylist,
    );
    await loadTracks(api);
    await loadPlaylists(api);
  }

  Future<void> deleteTrack(ApiClient api, Track track) async {
    await api.deleteTrack(track.filename);
    await loadTracks(api);
  }
}
