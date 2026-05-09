import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:media_kit_video/media_kit_video.dart';
import '../models/track.dart';

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

  bool _isShuffle = false;
  bool get isShuffle => _isShuffle;

  PlaylistMode _repeatMode = PlaylistMode.none;
  PlaylistMode get repeatMode => _repeatMode;

  List<Track> _queue = [];
  List<Track> get queue => _queue;

  PlayerProvider() {
    player = Player();
    videoController = VideoController(player);

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
      notifyListeners();
    });

    player.stream.volume.listen((vol) {
      _volume = vol;
      notifyListeners();
    });
    
    player.stream.tracks.listen((tracks) {
      // Basic check: if there's a video track, it might be a video
      _isVideo = tracks.video.isNotEmpty && tracks.video.first.id != 'no';
      notifyListeners();
    });

    player.stream.playlist.listen((playlist) {
      if (playlist.index >= 0 && playlist.index < _queue.length) {
        _currentTrack = _queue[playlist.index];
        _isVideo = _isVideoExt(_currentTrack!.filename);
        // Reset position/duration to avoid stale values from the previous
        // track causing Slider assertion errors (value > max) during the
        // brief moment before the new track's streams update.
        _position = Duration.zero;
        _duration = Duration.zero;
        notifyListeners();
      }
    });
  }

  Future<void> playTrack(Track track, List<Track> queue, SettingsProvider settings) async {
    _queue = queue;
    int startIndex = queue.indexOf(track);
    if (startIndex == -1) startIndex = 0;

    _currentTrack = track;
    _isVideo = _isVideoExt(track.filename);
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();

    final medias = <Media>[];
    for (var t in queue) {
      String uri = t.filename;
      if (!uri.startsWith('http')) {
        if (!p.isAbsolute(uri)) {
          if (_isVideoExt(t.filename)) {
            // Remove 'videos/' prefix if present
            final cleanFilename = t.filename.startsWith('videos/') ? t.filename.substring(7) : t.filename;
            uri = p.join(settings.videoFolder, cleanFilename);
          } else if (t.playlist.isNotEmpty) {
            uri = p.join(settings.musicFolder, t.playlist, t.filename);
          } else {
            uri = p.join(settings.musicFolder, t.filename);
          }
        }
        uri = p.normalize(uri);
        
        // Ensure the clicked track's file exists locally, others we can skip if not found
        // But for simplicity, we won't throw exception for whole queue.
        if (t == track && !File(uri).existsSync()) {
          debugPrint('File does not exist: $uri');
          throw Exception('El archivo no existe en el disco: $uri\nVerifica tu "Directorio de Música" en Ajustes.');
        }
      }
      medias.add(Media(uri));
    }

    try {
      debugPrint('Attempting to play playlist, starting at: $startIndex');
      await player.open(Playlist(medias, index: startIndex));
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

  void seek(Duration pos) {
    player.seek(pos);
  }

  void setVolume(double vol) {
    player.setVolume(vol);
  }

  void next() {
    player.next();
  }

  void previous() {
    player.previous();
  }

  void toggleShuffle() {
    _isShuffle = !_isShuffle;
    player.setShuffle(_isShuffle);
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
    notifyListeners();
  }

  bool _isVideoExt(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.mp4') || lower.endsWith('.mkv') || lower.endsWith('.avi') || lower.endsWith('.mov') || lower.endsWith('.webm');
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }
}
