import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'connect_screen.dart';
import 'library_screen.dart';
import 'now_playing_screen.dart';
import 'player.dart';
import 'remote_link.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // TV is always driven by a remote: show focus from the first frame, not after the first key press
  FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  final saved = await ConnectionStore.load();
  runApp(SoneroTvApp(initialApi: saved));
}

class SoneroTvApp extends StatefulWidget {
  final SoneroApi? initialApi;
  const SoneroTvApp({super.key, this.initialApi});

  @override
  State<SoneroTvApp> createState() => _SoneroTvAppState();
}

class _SoneroTvAppState extends State<SoneroTvApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  SoneroApi? _api;
  PlayerController? _player;
  RemoteLink? _link;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.initialApi != null) _connect(widget.initialApi!);
  }

  void _connect(SoneroApi api) {
    _link?.dispose();
    _player?.dispose();
    final player = PlayerController(api);
    setState(() {
      _api = api;
      _player = player;
      _link = RemoteLink(
        api: api,
        player: player,
        onRemotePlay: () => _showNowPlaying(api, player),
        onUnauthorized: () async {
          await ConnectionStore.clear();
          _disconnect('Esta TV ya no está autorizada en ${api.server.name}. Vuelve a emparejarla.');
        },
      );
      _message = null;
    });
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);
  }

  void _showNowPlaying(SoneroApi api, PlayerController player) {
    final nav = _navigatorKey.currentState;
    if (nav == null || NowPlayingScreen.isOpen) return;
    nav.push(MaterialPageRoute(builder: (_) => NowPlayingScreen(api: api, player: player)));
  }

  void _disconnect(String? message) {
    _link?.dispose();
    _player?.dispose();
    setState(() {
      _api = null;
      _player = null;
      _link = null;
      _message = message;
    });
    _navigatorKey.currentState?.popUntil((r) => r.isFirst);
  }

  /// Remote media keys work on every screen.
  KeyEventResult _onMediaKey(FocusNode _, KeyEvent event) {
    final player = _player;
    if (player == null || !player.hasQueue || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.mediaPlayPause) {
      player.togglePlay();
    } else if (key == LogicalKeyboardKey.mediaPlay) {
      player.audio.play();
    } else if (key == LogicalKeyboardKey.mediaPause) {
      player.audio.pause();
    } else if (key == LogicalKeyboardKey.mediaTrackNext) {
      player.next();
    } else if (key == LogicalKeyboardKey.mediaTrackPrevious) {
      player.previous();
    } else if (key == LogicalKeyboardKey.mediaFastForward) {
      player.seekRelative(const Duration(seconds: 15));
    } else if (key == LogicalKeyboardKey.mediaRewind) {
      player.seekRelative(const Duration(seconds: -15));
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _link?.dispose();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final api = _api;
    final player = _player;
    return MaterialApp(
      title: 'Sonero TV',
      debugShowCheckedModeBanner: false,
      theme: soneroTheme(),
      navigatorKey: _navigatorKey,
      shortcuts: {...WidgetsApp.defaultShortcuts, ...tvShortcuts},
      builder: (context, child) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onMediaKey,
        child: TvCanvas(child: child!),
      ),
      home: api == null || player == null
          ? ConnectScreen(key: ValueKey(_message), onConnected: _connect, message: _message)
          : LibraryScreen(
              key: ValueKey('${api.server.host}:${api.server.port}'),
              api: api,
              player: player,
              link: _link,
              onServerMoved: _connect,
              onDisconnect: _disconnect,
            ),
    );
  }
}
