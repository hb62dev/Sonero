import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';
import '../models/track.dart';
import 'settings_provider.dart';
import 'package:flutter/foundation.dart';
import '../services/audio_handler.dart';

class PlayerProvider extends ChangeNotifier {
  late final Player player;
  late final VideoController videoController;

  Track? _currentTrack;
  Track? get currentTrack => _currentTrack;

  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Duration _position = Duration.zero;
  Duration get position => _position;

  Duration _duration = Duration.zero;
  Duration get duration => _duration;

  double _volume = 100.0;
  double get volume => _volume;

  bool _isVideo = false;
  bool get isVideo => _isVideo;

  // ── Video overlay mode ────────────────────────────────────────────────────
  bool _isVideoMode = false;
  bool get isVideoMode => _isVideoMode;

  void setVideoMode(bool val) {
    _isVideoMode = val;
    if (val) _isSidebarVisible = false; // auto-hide sidebar when video starts
    if (!val) _isFullscreen = false;    // exit fullscreen when closing video
    notifyListeners();
  }

  void toggleVideoMode() {
    _isVideoMode = !_isVideoMode;
    notifyListeners();
  }

  // ── Fullscreen (shared so keyboard handler can trigger it) ────────────────
  bool _isFullscreen = false;
  bool get isFullscreen => _isFullscreen;

  void setFullscreen(bool val) {
    _isFullscreen = val;
    notifyListeners();
  }

  void toggleFullscreen() {
    _isFullscreen = !_isFullscreen;
    notifyListeners();
  }

  // ── Mute toggle ───────────────────────────────────────────────────────────
  double _previousVolume = 100.0;

  void toggleMute() {
    if (_volume > 0) {
      _previousVolume = _volume;
      setVolume(0);
    } else {
      setVolume(_previousVolume > 0 ? _previousVolume : 100.0);
    }
  }

  // ── Sidebar visibility (shared across AppShell & MiniPlayer) ─────────────
  bool _isSidebarVisible = false; // starts collapsed
  bool get isSidebarVisible => _isSidebarVisible;

  void toggleSidebar() {
    _isSidebarVisible = !_isSidebarVisible;
    notifyListeners();
  }

  void setSidebarVisible(bool val) {
    _isSidebarVisible = val;
    notifyListeners();
  }

  // ── Shuffle / Repeat ──────────────────────────────────────────────────────
  bool _isShuffle = false;
  bool get isShuffle => _isShuffle;

  PlaylistMode _repeatMode = PlaylistMode.none;
  PlaylistMode get repeatMode => _repeatMode;

  List<Track> _queue = [];
  List<Track> get queue => _queue;

  List<Track> _originalQueue = [];
  List<Media> _originalMedias = [];
  List<Media> _medias = [];

  PlayerProvider() {
    player = Player();
    videoController = VideoController(player);

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        SoneroAudioHandler.instance.setPlayer(player);
      } catch (e) {
        debugPrint('Could not set player on AudioHandler: $e');
      }
    }

    player.stream.playing.listen((playing) {
      _isPlaying = playing;
      notifyListeners();
    });

    player.stream.position.listen((pos) {
      _position = pos;
      notifyListeners();
    });

    player.stream.duration.listen((dur) {
      _duration = dur;
      if (!kIsWeb && (Platform.isAndroid || Platform.isIOS) && _currentTrack != null) {
        try {
          SoneroAudioHandler.instance.updateTrackMetadata(_currentTrack!, dur);
        } catch (_) {}
      }
      notifyListeners();
    });

    player.stream.volume.listen((vol) {
      _volume = vol;
      notifyListeners();
    });

    player.stream.tracks.listen((tracks) {
      _isVideo = tracks.video.isNotEmpty && tracks.video.first.id != 'no';
      notifyListeners();
    });

    player.stream.playlist.listen((playlist) {
      if (playlist.index >= 0 && playlist.index < _queue.length) {
        _currentTrack = _queue[playlist.index];
        _isVideo = _isVideoExt(_currentTrack!.filename);
        if (_isVideo) _isVideoMode = true;   // auto-open overlay for video
        if (!_isVideo) _isVideoMode = false; // auto-close overlay for audio
        _position = Duration.zero;
        _duration = Duration.zero;

        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          try {
            SoneroAudioHandler.instance.updateTrackMetadata(_currentTrack!, Duration.zero);
          } catch (_) {}
        }
        notifyListeners();
      }
    });
  }

  Future<void> playTrack(Track track, List<Track> queue, SettingsProvider settings) async {
    final List<Track> resolvedTracks = [];
    final List<Media> resolvedMedias = [];
    
    for (var t in queue) {
      String uri = t.filename;
      if (!uri.startsWith('http')) {
        if (!p.isAbsolute(uri)) {
          if (_isVideoExt(t.filename)) {
            final cleanFilename = t.filename.startsWith('videos/')
                ? t.filename.substring(7)
                : t.filename;
            uri = p.join(settings.videoFolder, cleanFilename);
          } else if (t.playlist.isNotEmpty) {
            uri = p.join(settings.musicFolder, t.playlist, t.filename);
          } else {
            uri = p.join(settings.musicFolder, t.filename);
          }
        }
        uri = p.normalize(uri);
        if (t == track && !File(uri).existsSync()) {
          debugPrint('File does not exist: $uri');
          throw Exception(
              'El archivo no existe en el disco: $uri\nVerifica tu "Directorio de Música" en Ajustes.');
        }
      }
      resolvedTracks.add(t);
      resolvedMedias.add(Media(uri));
    }

    _originalQueue = List<Track>.from(resolvedTracks);
    _originalMedias = List<Media>.from(resolvedMedias);

    int startIndex = resolvedTracks.indexOf(track);
    if (startIndex == -1) startIndex = 0;

    if (_isShuffle) {
      final indices = List<int>.generate(resolvedTracks.length, (i) => i)..remove(startIndex);
      indices.shuffle();
      final playIndices = [startIndex, ...indices];
      
      _queue = playIndices.map((i) => _originalQueue[i]).toList();
      _medias = playIndices.map((i) => _originalMedias[i]).toList();
      startIndex = 0;
    } else {
      _queue = List<Track>.from(_originalQueue);
      _medias = List<Media>.from(_originalMedias);
    }

    _currentTrack = track;
    _isVideo = _isVideoExt(track.filename);
    if (_isVideo) _isVideoMode = true; // auto-open video overlay
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    try {
      debugPrint('Attempting to play playlist, starting at: $startIndex');
      await player.open(Playlist(_medias, index: startIndex));
      await player.setPlaylistMode(_repeatMode);
      await player.setShuffle(false);
      await player.play();
    } catch (e) {
      debugPrint('Error playing media: $e');
      throw Exception('No se pudo reproducir: $e');
    }
  }

  void playPause() {
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  void pause() => player.pause();

  void seek(Duration pos) => player.seek(pos);

  void setVolume(double vol) => player.setVolume(vol);

  void next() => player.next();

  void previous() => player.previous();

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    
    if (_currentTrack != null && _queue.isNotEmpty && _originalQueue.isNotEmpty) {
      final currentPosition = player.state.position;
      final wasPlaying = player.state.playing;
      
      int newIndex;
      if (_isShuffle) {
        final currentInOriginal = _originalQueue.indexOf(_currentTrack!);
        if (currentInOriginal != -1) {
          final indices = List<int>.generate(_originalQueue.length, (i) => i)..remove(currentInOriginal);
          indices.shuffle();
          final playIndices = [currentInOriginal, ...indices];
          
          _queue = playIndices.map((i) => _originalQueue[i]).toList();
          _medias = playIndices.map((i) => _originalMedias[i]).toList();
          newIndex = 0;
        } else {
          newIndex = 0;
        }
      } else {
        _queue = List<Track>.from(_originalQueue);
        _medias = List<Media>.from(_originalMedias);
        newIndex = _originalQueue.indexOf(_currentTrack!);
        if (newIndex == -1) newIndex = 0;
      }
      
      player.open(Playlist(_medias, index: newIndex), play: wasPlaying).then((_) {
        player.seek(currentPosition);
        player.setPlaylistMode(_repeatMode);
        player.setShuffle(false);
      }).catchError((e) {
        debugPrint('Error updating playlist on shuffle toggle: $e');
      });
    }
    
    notifyListeners();
  }

  void toggleRepeat() {
    if (_repeatMode == PlaylistMode.none) {
      _repeatMode = PlaylistMode.loop;
    } else if (_repeatMode == PlaylistMode.loop) {
      _repeatMode = PlaylistMode.single;
    } else {
      _repeatMode = PlaylistMode.none;
    }
    player.setPlaylistMode(_repeatMode);
    notifyListeners();
  }

  void stop() {
    player.stop();
    _currentTrack = null;
    _isVideoMode = false;
    notifyListeners();
  }

  bool _isVideoExt(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
