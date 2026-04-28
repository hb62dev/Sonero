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
  }

  Future<void> playTrack(Track track, String musicFolder) async {
    _currentTrack = track;
    _isVideo = _isVideoExt(track.filename);
    notifyListeners();

    String uri = track.filename;
    if (!uri.startsWith('http')) {
      if (!p.isAbsolute(uri)) {
        if (track.playlist.isNotEmpty) {
          uri = p.join(musicFolder, track.playlist, track.filename);
        } else {
          uri = p.join(musicFolder, track.filename);
        }
      }
      uri = p.normalize(uri);
      
      // Check if file exists locally
      if (!File(uri).existsSync()) {
        debugPrint('File does not exist: $uri');
        throw Exception('El archivo no existe en el disco: $uri\nVerifica tu "Directorio de Música" en Ajustes.');
      }
    }

    try {
      debugPrint('Attempting to play: $uri');
      await player.open(Media(uri));
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
