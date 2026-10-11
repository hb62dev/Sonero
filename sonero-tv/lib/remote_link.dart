import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'player.dart';

/// Keeps a WebSocket open to the Sonero computer so the desktop app or the
/// phone remote can control this TV ("Reproducir en TV", pause, next…).
///
/// The TV is the client, so nothing listens on the TV and no firewall rule is
/// needed on it. Reconnects with backoff when the computer sleeps or the WiFi
/// drops, and reports what is playing every couple of seconds.
class RemoteLink extends ChangeNotifier {
  final SoneroApi api;
  final PlayerController player;
  /// Called after a remote "play" so the UI can show the player.
  final VoidCallback? onRemotePlay;
  /// Called when the computer revoked this TV.
  final VoidCallback? onUnauthorized;

  WebSocket? _socket;
  Timer? _reportTimer;
  Timer? _retryTimer;
  int _retries = 0;
  bool _closed = false;
  bool get connected => _socket != null;

  RemoteLink({required this.api, required this.player, this.onRemotePlay, this.onUnauthorized}) {
    player.addListener(_report);
    _connect();
  }

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final ws = await WebSocket.connect(api.controlUri.toString(), headers: api.authHeaders)
          .timeout(const Duration(seconds: 8));
      if (_closed) {
        await ws.close();
        return;
      }
      _socket = ws;
      _retries = 0;
      ws.pingInterval = const Duration(seconds: 20);
      notifyListeners();
      _report();
      _reportTimer = Timer.periodic(const Duration(seconds: 2), (_) => _report());
      ws.listen(
        _onMessage,
        onDone: () => _onClosed(ws.closeCode),
        onError: (_) => _onClosed(null),
        cancelOnError: true,
      );
    } on WebSocketException {
      // The handshake error doesn't say why it was refused: ask the API whether
      // this TV is still authorized before retrying forever.
      try {
        await api.ping();
      } on ApiException catch (e) {
        if (e.unauthorized) {
          onUnauthorized?.call();
          return;
        }
      } catch (_) {}
      _scheduleRetry();
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _onClosed(int? code) {
    _reportTimer?.cancel();
    _socket = null;
    notifyListeners();
    if (code == 4401) {
      onUnauthorized?.call();
      return;
    }
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retryTimer?.cancel();
    // 1, 2, 4, 8… up to 30 s
    final delay = Duration(seconds: (1 << _retries.clamp(0, 5)).clamp(1, 30));
    _retries++;
    _retryTimer = Timer(delay, _connect);
  }

  void _report() {
    final ws = _socket;
    if (ws == null) return;
    try {
      ws.add(jsonEncode(player.snapshot()));
    } catch (_) {}
  }

  Future<void> _onMessage(dynamic raw) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    if (msg['type'] != 'command') return;

    switch (msg['action']) {
      case 'play':
        final ids = ((msg['track_ids'] as List?) ?? const []).cast<String>();
        final index = (msg['index'] as num?)?.toInt() ?? 0;
        final shuffle = msg['shuffle'] as bool? ?? false;
        var ok = await player.playIds(ids, index: index, shuffle: shuffle);
        if (!ok) {
          // The library may have changed on the computer since we loaded it
          try {
            final lib = await api.library();
            player.knownTracks = {for (final t in lib.tracks) t.id: t};
            ok = await player.playIds(ids, index: index, shuffle: shuffle);
          } catch (_) {}
        }
        final position = (msg['position'] as num?)?.toDouble();
        if (ok && position != null && position > 0) {
          await player.seekTo(Duration(milliseconds: (position * 1000).round()));
        }
        if (ok) onRemotePlay?.call();
      case 'pause':
        await player.audio.pause();
      case 'resume':
        player.audio.play();
      case 'toggle':
        player.togglePlay();
      case 'stop':
        await player.audio.pause();
        await player.seekTo(Duration.zero);
      case 'next':
        await player.next();
      case 'previous':
        await player.previous();
      case 'seek':
        final position = (msg['position'] as num?)?.toDouble();
        if (position != null) await player.seekTo(Duration(milliseconds: (position * 1000).round()));
      case 'volume':
        final value = (msg['value'] as num?)?.toDouble();
        if (value != null) await player.setVolume(value);
      case 'shuffle':
        final enabled = msg['shuffle'] as bool?;
        if (enabled != null) await player.setShuffle(enabled);
    }
    _report();
  }

  @override
  void dispose() {
    _closed = true;
    player.removeListener(_report);
    _reportTimer?.cancel();
    _retryTimer?.cancel();
    _socket?.close();
    super.dispose();
  }
}
