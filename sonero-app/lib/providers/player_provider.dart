import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';
import '../models/track.dart';
import '../core/api_client.dart';
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
    notifyListeners();
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

  // ── Cover art adjustment (zoom & pan) ─────────────────────────────────────
  double _coverScale = 1.0;
  double get coverScale => _coverScale;

  double _coverOffsetX = 0.0;
  double get coverOffsetX => _coverOffsetX;

  double _coverOffsetY = 0.0;
  double get coverOffsetY => _coverOffsetY;

  void setCoverAdjustment({required double scale, required double offsetX, required double offsetY}) {
    _coverScale = scale;
    _coverOffsetX = offsetX;
    _coverOffsetY = offsetY;
    notifyListeners();
  }

  void resetCoverAdjustment() {
    _coverScale = 1.0;
    _coverOffsetX = 0.0;
    _coverOffsetY = 0.0;
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

  // ── Analytics tracking ─────────────────────────────────────────────────────
  ApiClient? _api;
  String? _trackingFilename;
  final Stopwatch _trackingWatch = Stopwatch();

  void setApiClient(ApiClient api) => _api = api;

  void _reportPrevious() {
    if (_trackingFilename != null && _api != null && _trackingWatch.elapsedMilliseconds > 2000) {
      final seconds = _trackingWatch.elapsed.inSeconds.toDouble();
      final completed = _duration.inSeconds > 0 && _position.inSeconds >= (_duration.inSeconds * 0.9);
      _api!.logPlayback(_trackingFilename!, seconds, completed);
    }
    _trackingWatch.reset();
    _trackingWatch.stop();
    _trackingFilename = null;
  }

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
      if (playing) {
        _trackingWatch.start();
      } else {
        _trackingWatch.stop();
      }
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
        // Report previous track's analytics
        _reportPrevious();

        _currentTrack = _queue[playlist.index];
        _isVideo = _isVideoExt(_currentTrack!.filename);
        if (_isVideo) _isVideoMode = true;   // auto-open overlay for video
        if (!_isVideo) _isVideoMode = false; // auto-close overlay for audio
        _position = Duration.zero;
        _duration = Duration.zero;

        // Start tracking new track
        _trackingFilename = _currentTrack!.filename;
        _trackingWatch.reset();

        if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
          try {
            SoneroAudioHandler.instance.updateTrackMetadata(_currentTrack!, Duration.zero);
          } catch (_) {}
        }
        notifyListeners();
      }
    });
  }

  // ── Guard against concurrent playTrack calls ────────────────────────────
  bool _isLoadingTrack = false;
  bool get isLoadingTrack => _isLoadingTrack;

  /// Cancellation token: each playTrack call increments this.
  /// If by the time we reach player.open() the token has changed,
  /// it means a newer playTrack was called and we must abort.
  int _playToken = 0;

  Future<void> playTrack(Track track, List<Track> queue, SettingsProvider settings) async {
    // Increment token — any previous in-flight playTrack is now stale
    final myToken = ++_playToken;

    // Immediately silence any current playback
    try {
      await player.pause();
      await player.stop();
    } catch (_) {}

    _isLoadingTrack = true;
    notifyListeners();

    try {
      final List<Track> resolvedTracks = [];
      final List<Media> resolvedMedias = [];
      
      for (var t in queue) {
        // Abort if a newer playTrack has been called
        if (_playToken != myToken) return;

        String uri = t.filename;
        if (!uri.startsWith('http')) {
          if (kIsWeb) {
            // On web, stream from the backend API
            final baseUrl = settings.api.baseUrl;
            if (_isVideoExt(t.filename)) {
              final cleanFilename = t.filename.startsWith('videos/')
                  ? t.filename.substring(7)
                  : t.filename;
              uri = '$baseUrl/api/v1/downloads/videos/${Uri.encodeComponent(cleanFilename)}';
            } else {
              uri = '$baseUrl/api/v1/downloads/${Uri.encodeComponent(t.filename)}';
            }
          } else {
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
        }
        resolvedTracks.add(t);
        resolvedMedias.add(Media(uri));
      }

      // Abort if stale
      if (_playToken != myToken) return;

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
      resetCoverAdjustment(); // Reset zoom/pan for new track
      _isVideo = _isVideoExt(track.filename);
      if (_isVideo) _isVideoMode = true; // auto-open video overlay
      _position = Duration.zero;
      _duration = Duration.zero;
      notifyListeners();

      // Final check before the heavy operation
      if (_playToken != myToken) return;

      // Force stop right before open to ensure the underlying media element is cleared
      try { await player.stop(); } catch (_) {}

      debugPrint('Attempting to play playlist, starting at: $startIndex');
      // player.open() already starts playback by default — do NOT call player.play() after
      await player.open(Playlist(_medias, index: startIndex));
      
      // Only set modes if we're still the current playback
      if (_playToken == myToken) {
        await player.setPlaylistMode(_repeatMode);
        await player.setShuffle(false);
      }
    } catch (e) {
      debugPrint('Error playing media: $e');
      if (_playToken == myToken) rethrow;
    } finally {
      if (_playToken == myToken) {
        _isLoadingTrack = false;
        notifyListeners();
      }
    }
  }

  void playPause() {
    if (_isLoadingTrack) return; // Don't toggle while a track is loading
    if (player.state.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  void pause() => player.pause();

  void seek(Duration pos) => player.seek(pos);

  void setVolume(double vol) {
    _volume = vol;
    player.setVolume(vol);
    notifyListeners();
  }

  void next() {
    if (_isLoadingTrack) return;
    player.next();
  }

  void previous() {
    if (_isLoadingTrack) return;
    player.previous();
  }

  void toggleShuffle() {
    if (_isLoadingTrack) return;
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
    _isLoadingTrack = false; // Reset loading flag to prevent stuck state
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
