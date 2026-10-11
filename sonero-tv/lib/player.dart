import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'api.dart';

/// Plays a queue of tracks streamed from the Sonero server and reports what
/// was listened to, so TV playback shows up in Sonero's statistics.
class PlayerController extends ChangeNotifier {
  final SoneroApi api;
  // Android's ExoPlayer sends the auth header itself; no localhost proxy needed
  final AudioPlayer _player = AudioPlayer(useProxyForRequestHeaders: false);
  final List<StreamSubscription> _subs = [];

  List<Track> _queue = const [];
  /// Library tracks by id, so remote commands (which send ids) can be played.
  Map<String, Track> knownTracks = const {};
  int? _index;
  Duration _lastPosition = Duration.zero;
  String? error;

  PlayerController(this.api) {
    _subs.add(_player.currentIndexStream.listen(_onIndexChanged));
    _subs.add(_player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed) {
        _reportCurrent(completed: true);
        _player.pause();
        _player.seek(Duration.zero, index: 0);
      }
      notifyListeners();
    }));
    _subs.add(_player.positionStream.listen((p) => _lastPosition = p));
    _subs.add(_player.playbackEventStream.listen((_) {}, onError: (Object e, StackTrace _) {
      error = 'No se pudo reproducir: $e';
      notifyListeners();
    }));
  }

  AudioPlayer get audio => _player;
  bool get isPlaying => _player.playing;
  bool get shuffle => _player.shuffleModeEnabled;
  bool get hasQueue => _queue.isNotEmpty;
  Track? get current => _index != null && _index! < _queue.length ? _queue[_index!] : null;
  List<Track> get queue => _queue;

  /// Upcoming tracks in play order (respects shuffle).
  List<Track> get upNext {
    final order = _player.effectiveIndices;
    if (_index == null || order.isEmpty) return const [];
    final pos = order.indexOf(_index!);
    return [for (final i in order.skip(pos + 1).take(20)) _queue[i]];
  }

  Future<void> playQueue(List<Track> tracks, {int startIndex = 0, bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    _reportCurrent();
    error = null;
    _queue = List.unmodifiable(tracks);
    _index = null;
    final sources = [
      for (final t in tracks) AudioSource.uri(api.streamUri(t), headers: api.authHeaders, tag: t),
    ];
    try {
      await _player.setShuffleModeEnabled(shuffle);
      await _player.setAudioSources(sources, initialIndex: shuffle ? null : startIndex);
      if (shuffle) await _player.shuffle();
      _player.play();
    } catch (e) {
      error = 'No se pudo reproducir: $e';
    }
    notifyListeners();
  }

  /// Plays tracks by id (remote "play" command). Unknown ids are skipped.
  Future<bool> playIds(List<String> ids, {int index = 0, bool shuffle = false}) async {
    final tracks = <Track>[];
    var start = 0;
    for (final (i, id) in ids.indexed) {
      final t = knownTracks[id];
      if (t == null) continue;
      if (i == index) start = tracks.length;
      tracks.add(t);
    }
    if (tracks.isEmpty) return false;
    await playQueue(tracks, startIndex: start, shuffle: shuffle);
    return true;
  }

  double get volume => _player.volume;

  Future<void> setVolume(double value) async {
    await _player.setVolume(value.clamp(0.0, 1.0));
    notifyListeners();
  }

  Future<void> seekTo(Duration position) => _player.seek(position);

  Future<void> setShuffle(bool enabled) async {
    if (enabled == _player.shuffleModeEnabled) return;
    await toggleShuffle();
  }

  /// What the TV reports to the computer and the phone remote.
  Map<String, dynamic> snapshot() => {
        'type': 'state',
        'track_id': current?.id,
        'title': current?.title,
        'artist': current?.artist,
        'playing': _player.playing,
        'position': _player.position.inMilliseconds / 1000,
        'duration': (_player.duration?.inMilliseconds ?? 0) / 1000,
        'volume': _player.volume,
        'shuffle': _player.shuffleModeEnabled,
      };

  void togglePlay() => _player.playing ? _player.pause() : _player.play();

  Future<void> next() async {
    if (_player.hasNext) await _player.seekToNext();
  }

  Future<void> previous() async {
    // Like most players: restart the song unless we're at its very beginning
    if (_player.position > const Duration(seconds: 3) || !_player.hasPrevious) {
      await _player.seek(Duration.zero);
    } else {
      await _player.seekToPrevious();
    }
  }

  Future<void> seekRelative(Duration delta) async {
    final duration = _player.duration;
    var target = _player.position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (duration != null && target > duration) target = duration;
    await _player.seek(target);
  }

  Future<void> toggleShuffle() async {
    final enable = !_player.shuffleModeEnabled;
    if (enable) await _player.shuffle();
    await _player.setShuffleModeEnabled(enable);
    notifyListeners();
  }

  void _onIndexChanged(int? index) {
    if (index == _index) return;
    _reportCurrent();
    _index = index;
    _lastPosition = Duration.zero;
    notifyListeners();
  }

  void _reportCurrent({bool completed = false}) {
    final track = current;
    if (track == null) return;
    final seconds = _lastPosition.inMilliseconds / 1000;
    final duration = track.duration ?? _player.duration?.inSeconds.toDouble();
    final done = completed || (duration != null && duration > 0 && seconds >= duration * 0.9);
    api.reportPlayed(track, seconds, done);
    _lastPosition = Duration.zero;
  }

  @override
  void dispose() {
    _reportCurrent();
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }
}
