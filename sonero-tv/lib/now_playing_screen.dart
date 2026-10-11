import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'player.dart';
import 'ui.dart';

/// Full-screen player: big artwork, progress, remote-friendly controls,
/// synced lyrics, and an ambient mode when the remote is left alone.
class NowPlayingScreen extends StatefulWidget {
  final SoneroApi api;
  final PlayerController player;

  const NowPlayingScreen({super.key, required this.api, required this.player});

  /// True while a NowPlayingScreen is on screen (so remote "play" doesn't stack them).
  static bool get isOpen => _openCount > 0;
  static int _openCount = 0;

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  static const _idleBeforeAmbient = Duration(seconds: 25);

  Timer? _idleTimer;
  bool _ambient = false;
  bool _showLyrics = false;
  Lyrics? _lyrics;
  String? _lyricsFor;
  final _playFocus = FocusNode();

  PlayerController get player => widget.player;

  @override
  void initState() {
    super.initState();
    NowPlayingScreen._openCount++;
    // Keep the TV from dimming into its own screensaver: we have our ambient mode
    WakelockPlus.enable();
    player.addListener(_onPlayerChanged);
    _onPlayerChanged();
    _resetIdle();
  }

  @override
  void dispose() {
    NowPlayingScreen._openCount--;
    WakelockPlus.disable();
    player.removeListener(_onPlayerChanged);
    _idleTimer?.cancel();
    _playFocus.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    final t = player.current;
    if (t != null && t.id != _lyricsFor) {
      _lyricsFor = t.id;
      _lyrics = null;
      widget.api.lyrics(t).then((l) {
        if (mounted && _lyricsFor == t.id) setState(() => _lyrics = l);
      });
    }
    if (!player.isPlaying && _ambient) setState(() => _ambient = false);
  }

  void _resetIdle() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleBeforeAmbient, () {
      if (mounted && player.isPlaying) setState(() => _ambient = true);
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    _resetIdle();
    if (_ambient) {
      setState(() => _ambient = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _playFocus.requestFocus());
      // Media keys still act; any other key just wakes the screen
      final k = event.logicalKey;
      final isMedia = k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaTrackNext ||
          k == LogicalKeyboardKey.mediaTrackPrevious || k == LogicalKeyboardKey.mediaPlay ||
          k == LogicalKeyboardKey.mediaPause;
      return isMedia ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Focus(
        onKeyEvent: _onKey,
        child: ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final t = player.current;
            if (t == null) {
              return MessageView(
                icon: Icons.music_off_rounded,
                title: 'Nada en reproducción',
                action: TvButton(icon: Icons.arrow_back_rounded, label: 'Volver', autofocus: true,
                    onPressed: () => Navigator.of(context).pop()),
              );
            }
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: _ambient
                  ? _AmbientView(key: const ValueKey('ambient'), api: widget.api, track: t, player: player, lyrics: _lyrics)
                  : _buildPlayer(context, t),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPlayer(BuildContext context, Track t) {
    final hasLyrics = _lyrics != null && _lyrics!.lines.isNotEmpty;
    return Stack(
      key: const ValueKey('player'),
      fit: StackFit.expand,
      children: [
        _Backdrop(api: widget.api, track: t, opacity: 0.18),
        Padding(
          padding: const EdgeInsets.fromLTRB(96, 64, 96, 48),
          child: Row(
            children: [
              CoverArt(api: widget.api, track: t, size: 440, radius: 20),
              const SizedBox(width: 72),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 46, fontWeight: FontWeight.bold, height: 1.15)),
                    const SizedBox(height: 12),
                    if (t.artist.isNotEmpty)
                      Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 28, color: SoneroColors.muted)),
                    if (t.album.isNotEmpty)
                      Text(t.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 20, color: SoneroColors.muted)),
                    const SizedBox(height: 36),
                    _Progress(audio: player.audio),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        TvButton(icon: Icons.shuffle_rounded, primary: player.shuffle, onPressed: player.toggleShuffle),
                        const SizedBox(width: 20),
                        TvButton(icon: Icons.skip_previous_rounded, onPressed: player.previous),
                        const SizedBox(width: 20),
                        TvButton(
                          icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          primary: true,
                          autofocus: true,
                          focusNode: _playFocus,
                          onPressed: player.togglePlay,
                        ),
                        const SizedBox(width: 20),
                        TvButton(icon: Icons.skip_next_rounded, onPressed: player.next),
                        const SizedBox(width: 20),
                        TvButton(
                          icon: Icons.lyrics_rounded,
                          primary: _showLyrics,
                          onPressed: hasLyrics ? () => setState(() => _showLyrics = !_showLyrics) : null,
                        ),
                        const SizedBox(width: 20),
                        TvButton(icon: Icons.library_music_rounded, onPressed: () => Navigator.of(context).pop()),
                      ],
                    ),
                    if (player.error != null) ...[
                      const SizedBox(height: 20),
                      Text(player.error!, style: const TextStyle(fontSize: 18, color: SoneroColors.error)),
                    ],
                    const SizedBox(height: 28),
                    Expanded(
                      child: _showLyrics && hasLyrics
                          ? _LyricsPanel(lyrics: _lyrics!, audio: player.audio)
                          : _UpNext(tracks: player.upNext, hasLyrics: hasLyrics),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Backdrop extends StatelessWidget {
  final SoneroApi api;
  final Track track;
  final double opacity;
  const _Backdrop({required this.api, required this.track, required this.opacity});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        Opacity(
          opacity: opacity,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: OverflowBox(
              maxWidth: size.width * 1.2,
              maxHeight: size.width * 1.2,
              child: CoverArt(api: api, track: track, size: size.width * 1.2, radius: 0),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xB30F0F12), Color(0xF20F0F12)],
            ),
          ),
        ),
      ],
    );
  }
}

class _UpNext extends StatelessWidget {
  final List<Track> tracks;
  final bool hasLyrics;
  const _UpNext({required this.tracks, required this.hasLyrics});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('A CONTINUACIÓN', style: TextStyle(fontSize: 14, letterSpacing: 1.5, color: SoneroColors.muted)),
        const SizedBox(height: 8),
        for (final n in tracks.take(3))
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              n.artist.isEmpty ? n.title : '${n.title}  ·  ${n.artist}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, color: SoneroColors.muted),
            ),
          ),
      ],
    );
  }
}

/// Synced lyrics: the current line stays centered and highlighted.
class _LyricsPanel extends StatefulWidget {
  final Lyrics lyrics;
  final AudioPlayer audio;
  const _LyricsPanel({required this.lyrics, required this.audio});

  @override
  State<_LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<_LyricsPanel> {
  static const _lineHeight = 44.0;
  final _scroll = ScrollController();
  int _current = -1;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lines = widget.lyrics.lines;
    return StreamBuilder<Duration>(
      stream: widget.audio.positionStream,
      builder: (context, snap) {
        final idx = widget.lyrics.indexAt(snap.data ?? Duration.zero);
        if (idx != _current) {
          _current = idx;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scroll.hasClients || idx < 0) return;
            final viewport = _scroll.position.viewportDimension;
            final target = (idx * _lineHeight - viewport / 2 + _lineHeight / 2)
                .clamp(0.0, _scroll.position.maxScrollExtent);
            _scroll.animateTo(target, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
          });
        }
        return ShaderMask(
          shaderCallback: (r) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
            stops: [0, 0.15, 0.85, 1],
          ).createShader(r),
          blendMode: BlendMode.dstIn,
          child: ListView.builder(
            controller: _scroll,
            itemCount: lines.length,
            itemExtent: _lineHeight,
            padding: const EdgeInsets.symmetric(vertical: 40),
            itemBuilder: (context, i) {
              final active = widget.lyrics.synced ? i == idx : true;
              return AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                style: TextStyle(
                  fontSize: active && widget.lyrics.synced ? 28 : 24,
                  fontWeight: active && widget.lyrics.synced ? FontWeight.bold : FontWeight.w500,
                  color: active ? SoneroColors.text : SoneroColors.muted.withValues(alpha: 0.6),
                ),
                child: Text(lines[i].text.isEmpty ? '♪' : lines[i].text, maxLines: 1, overflow: TextOverflow.ellipsis),
              );
            },
          ),
        );
      },
    );
  }
}

/// Screensaver-like view: blurred artwork, a big clock and the current lyric.
class _AmbientView extends StatefulWidget {
  final SoneroApi api;
  final Track track;
  final PlayerController player;
  final Lyrics? lyrics;

  const _AmbientView({super.key, required this.api, required this.track, required this.player, this.lyrics});

  @override
  State<_AmbientView> createState() => _AmbientViewState();
}

class _AmbientViewState extends State<_AmbientView> with SingleTickerProviderStateMixin {
  late final AnimationController _drift =
      AnimationController(vsync: this, duration: const Duration(seconds: 40))..repeat(reverse: true);
  late Timer _clock;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 10), (_) => setState(() => _now = DateTime.now()));
  }

  @override
  void dispose() {
    _drift.dispose();
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final time = '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final synced = widget.lyrics != null && widget.lyrics!.synced;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Slow "Ken Burns" drift so a static image doesn't burn into the panel
        AnimatedBuilder(
          animation: _drift,
          builder: (context, child) => Transform.scale(
            scale: 1.15 + _drift.value * 0.1,
            child: Transform.translate(offset: Offset((_drift.value - 0.5) * 80, 0), child: child),
          ),
          child: Opacity(
            opacity: 0.55,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: CoverArt(api: widget.api, track: widget.track, size: size.width, radius: 0),
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x660F0F12), Color(0xE60F0F12)],
            ),
          ),
        ),
        Positioned(
          top: 56,
          right: 80,
          child: Text(time, style: const TextStyle(fontSize: 96, fontWeight: FontWeight.w200, letterSpacing: 2)),
        ),
        if (synced)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 120),
              child: StreamBuilder<Duration>(
                stream: widget.player.audio.positionStream,
                builder: (context, snap) {
                  final i = widget.lyrics!.indexAt(snap.data ?? Duration.zero);
                  final line = i >= 0 ? widget.lyrics!.lines[i].text : '';
                  return AnimatedSwitcher(
                    duration: const Duration(milliseconds: 400),
                    child: Text(line, key: ValueKey('$i'), textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 52, fontWeight: FontWeight.bold, height: 1.25)),
                  );
                },
              ),
            ),
          ),
        Positioned(
          left: 80,
          bottom: 64,
          right: 80,
          child: Row(
            children: [
              CoverArt(api: widget.api, track: widget.track, size: 120, radius: 12),
              const SizedBox(width: 28),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.track.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
                    Text(widget.track.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 24, color: SoneroColors.muted)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  final AudioPlayer audio;
  const _Progress({required this.audio});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: audio.positionStream,
      builder: (context, snap) {
        final pos = snap.data ?? Duration.zero;
        final total = audio.duration ?? Duration.zero;
        final value = total.inMilliseconds > 0 ? (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0) : 0.0;
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: value, minHeight: 8, backgroundColor: SoneroColors.border),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(formatDuration(pos), style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
                Text(formatDuration(total), style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
              ],
            ),
          ],
        );
      },
    );
  }
}
