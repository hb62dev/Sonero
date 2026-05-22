import 'package:audio_service/audio_service.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import '../models/track.dart';

class SoneroAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  Player? _player;
  
  static late final SoneroAudioHandler instance;

  void setPlayer(Player player) {
    _player = player;
    
    // Listen to player state events and sync to system notification
    _player!.stream.playing.listen((_) => _updateState());
    _player!.stream.position.listen((_) => _updateState());
    _player!.stream.duration.listen((_) => _updateState());
    _player!.stream.buffering.listen((_) => _updateState());
    _player!.stream.completed.listen((_) => _updateState());
    _player!.stream.playlist.listen((_) => _updateState());
  }

  void updateTrackMetadata(Track track, Duration duration) {
    mediaItem.add(MediaItem(
      id: track.filename,
      album: track.album.isNotEmpty ? track.album : 'Sonero Library',
      title: track.title,
      artist: track.artist.isNotEmpty ? track.artist : 'Desconocido',
      duration: duration,
      artUri: (track.coverUrl != null && track.coverUrl!.isNotEmpty)
          ? Uri.parse(track.coverUrl!)
          : null,
    ));
  }

  void _updateState() {
    if (_player == null) return;
    
    final playing = _player!.state.playing;
    final position = _player!.state.position;
    final buffering = _player!.state.buffering;
    final completed = _player!.state.completed;
    
    final hasMedia = _player!.state.playlist.index != -1 && 
                     _player!.state.playlist.medias.isNotEmpty;

    AudioProcessingState processingState = AudioProcessingState.idle;
    if (!hasMedia) {
      processingState = AudioProcessingState.idle;
    } else if (completed) {
      processingState = AudioProcessingState.completed;
    } else if (buffering) {
      processingState = AudioProcessingState.buffering;
    } else if (_player!.state.duration == Duration.zero) {
      processingState = AudioProcessingState.loading;
    } else {
      processingState = AudioProcessingState.ready;
    }
    
    playbackState.add(PlaybackState(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.stop,
        MediaControl.skipToNext,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
        MediaAction.playPause,
      },
      androidCompactActionIndices: const [0, 1, 3],
      playing: playing,
      processingState: processingState,
      updatePosition: position,
      bufferedPosition: position,
      speed: 1.0,
      updateTime: DateTime.now(),
    ));
  }

  @override
  Future<void> play() async {
    await _player?.play();
  }

  @override
  Future<void> pause() async {
    await _player?.pause();
  }

  @override
  Future<void> stop() async {
    await _player?.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player?.seek(position);
  }

  @override
  Future<void> skipToNext() async {
    await _player?.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _player?.previous();
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
  }
}
