import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.hide_track' hide Track;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';
import '../../providers/player_provider.dart';
import '../theme.dart';

class VideoOverlay extends StatefulWidget {
  const VideoOverlay({super.key});

  @override
  State<VideoOverlay> createState() => _VideoOverlayState();
}

class _VideoOverlayState extends State<VideoOverlay>
    with SingleTickerProviderStateMixin {
  bool _controlsVisible = true;
  Timer? _hideTimer;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  bool get _isDesktop => !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1.0,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    if (_isDesktop) {
      windowManager.isFullScreen().then((val) {
        if (mounted) {
          context.read<PlayerProvider>().setFullscreen(val);
        }
      });
    }
    _resetHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _fadeController.dispose();
    final player = context.read<PlayerProvider>();
    if (player.isFullscreen) {
      if (_isDesktop) {
        windowManager.setFullScreen(false);
      }
      player.setFullscreen(false);
    }
    super.dispose();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      _fadeController.forward();
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _controlsVisible = false);
        _fadeController.reverse();
      }
    });
  }

  Future<void> _toggleFullscreen(PlayerProvider player) async {
    final next = !player.isFullscreen;
    if (_isDesktop) {
      await windowManager.setFullScreen(next);
    }
    player.setFullscreen(next);
    _resetHideTimer();
  }

  void _exitVideoMode(BuildContext context) {
    final player = context.read<PlayerProvider>();
    if (player.isFullscreen) {
      if (_isDesktop) {
        windowManager.setFullScreen(false);
      }
      player.setFullscreen(false);
    }
    player.pause();        // pause playback when closing video
    player.setVideoMode(false);
  }

  String _format(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes.remainder(60));
    final s = two(d.inSeconds.remainder(60));
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track  = player.currentTrack;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_isDesktop) {
        final windowFs = await windowManager.isFullScreen();
        if (windowFs != player.isFullscreen) {
          windowManager.setFullScreen(player.isFullscreen);
        }
      }
    });

    return Listener(
      onPointerMove: (_) => _resetHideTimer(),
      onPointerDown: (_) => _resetHideTimer(),
      child: Stack(
        children: [
          // ── Video fills the entire area ───────────────────────────────
          Positioned.fill(
            child: GestureDetector(
              onTap: () {
                player.playPause();
                _resetHideTimer();
              },
              child: Video(
                controller: player.videoController,
                controls: NoVideoControls,
                fill: Colors.black,
              ),
            ),
          ),

          // ── Top bar: sidebar toggle + title + fullscreen + close ──────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _TopBar(
                title: track != null
                    ? (track.title.isNotEmpty ? track.title : track.filename)
                    : '',
                artist: track?.artist ?? '',
                isSidebarVisible: player.isSidebarVisible,
                isFullscreen: player.isFullscreen,
                onToggleSidebar: player.toggleSidebar,
                onToggleFullscreen: () => _toggleFullscreen(player),
                onClose: () => _exitVideoMode(context),
              ),
            ),
          ),

          // ── Bottom controls bar ───────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: _BottomControls(
                player: player,
                formatFn: _format,
                onInteract: _resetHideTimer,
              ),
            ),
          ),

          // ── Center pause indicator ────────────────────────────────────
          if (!player.isPlaying)
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 52,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final String title;
  final String artist;
  final bool isSidebarVisible;
  final bool isFullscreen;
  final VoidCallback onToggleSidebar;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onClose;

  const _TopBar({
    required this.title,
    required this.artist,
    required this.isSidebarVisible,
    required this.isFullscreen,
    required this.onToggleSidebar,
    required this.onToggleFullscreen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final isMobile = context.isMobile;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 16 + topPadding, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          if (!isMobile) ...[
            _GlassButton(
              icon: isSidebarVisible ? Icons.menu_open_rounded : Icons.menu_rounded,
              onTap: onToggleSidebar,
              tooltip: isSidebarVisible ? 'Ocultar panel' : 'Mostrar panel',
              size: 20,
            ),
            const SizedBox(width: 12),
          ],

          // Title + artist
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (title.isNotEmpty)
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (artist.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    artist,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.70),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          if (!isMobile) ...[
            _GlassButton(
              icon: isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              onTap: onToggleFullscreen,
              tooltip: isFullscreen ? 'Salir de pantalla completa' : 'Pantalla completa',
              size: 22,
            ),
            const SizedBox(width: 8),
          ],

          // Close video mode
          _GlassButton(
            icon: Icons.close_rounded,
            onTap: onClose,
            tooltip: 'Cerrar video',
            size: 20,
          ),
        ],
      ),
    );
  }
}

// ── Bottom controls ───────────────────────────────────────────────────────────
class _BottomControls extends StatefulWidget {
  final PlayerProvider player;
  final String Function(Duration) formatFn;
  final VoidCallback onInteract;

  const _BottomControls({
    required this.player,
    required this.formatFn,
    required this.onInteract,
  });

  @override
  State<_BottomControls> createState() => _BottomControlsState();
}

class _BottomControlsState extends State<_BottomControls> {
  bool _volumeExpanded = false;

  @override
  Widget build(BuildContext context) {
    final player = widget.player;
    final pos = player.position.inMilliseconds.toDouble();
    final dur = player.duration.inMilliseconds > 0
        ? player.duration.inMilliseconds.toDouble()
        : 100.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final isMobile = context.isMobile;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPadding),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xCC000000), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Seek bar ─────────────────────────────────────────────────
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
              activeTrackColor: Colors.red,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.red,
              overlayColor: Colors.red.withOpacity(0.2),
            ),
            child: Slider(
              value: pos.clamp(0.0, dur),
              max: dur,
              onChanged: (val) {
                widget.onInteract();
                player.seek(Duration(milliseconds: val.toInt()));
              },
            ),
          ),

          // ── Controls row ─────────────────────────────────────────────
          Row(
            children: [
              // Skip prev
              _GlassButton(
                icon: Icons.skip_previous_rounded,
                onTap: () { widget.onInteract(); player.previous(); },
                size: 24,
              ),
              const SizedBox(width: 6),

              // Play / Pause
              _GlassButton(
                icon: player.isPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                onTap: () { widget.onInteract(); player.playPause(); },
                size: 32,
                large: true,
              ),
              const SizedBox(width: 6),

              // Skip next
              _GlassButton(
                icon: Icons.skip_next_rounded,
                onTap: () { widget.onInteract(); player.next(); },
                size: 24,
              ),
              const SizedBox(width: 14),

              // Time display
              Text(
                '${widget.formatFn(player.position)} / ${widget.formatFn(player.duration)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),

              const Spacer(),

              // Volume (hidden on mobile)
              if (!isMobile) ...[
                _GlassButton(
                  icon: player.volume == 0
                      ? Icons.volume_off_rounded
                      : player.volume < 50
                          ? Icons.volume_down_rounded
                          : Icons.volume_up_rounded,
                  onTap: () => setState(() => _volumeExpanded = !_volumeExpanded),
                  size: 20,
                ),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: _volumeExpanded ? 100 : 0,
                  clipBehavior: Clip.hardEdge,
                  decoration: const BoxDecoration(),
                  child: _volumeExpanded
                      ? SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white30,
                            thumbColor: Colors.white,
                          ),
                          child: Slider(
                            value: player.volume.clamp(0.0, 100.0),
                            max: 100,
                            onChanged: (val) {
                              widget.onInteract();
                              player.setVolume(val);
                            },
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],

              // Repeat
              const SizedBox(width: 4),
              _GlassButton(
                icon: player.repeatMode == PlaylistMode.single
                    ? Icons.repeat_one_rounded
                    : Icons.repeat_rounded,
                onTap: () { widget.onInteract(); player.toggleRepeat(); },
                size: 20,
                active: player.repeatMode != PlaylistMode.none,
              ),

              // Shuffle
              const SizedBox(width: 4),
              _GlassButton(
                icon: Icons.shuffle_rounded,
                onTap: () { widget.onInteract(); player.toggleShuffle(); },
                size: 20,
                active: player.isShuffle,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Glass icon button with hover ──────────────────────────────────────────────
class _GlassButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool large;
  final bool active;
  final String? tooltip;

  const _GlassButton({
    required this.icon,
    required this.onTap,
    this.size = 22,
    this.large = false,
    this.active = false,
    this.tooltip,
  });

  @override
  State<_GlassButton> createState() => _GlassButtonState();
}

class _GlassButtonState extends State<_GlassButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active ? Colors.red : Colors.white;
    final btn = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit:  (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width:  widget.large ? 48 : 36,
          height: widget.large ? 48 : 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _hovered
                ? Colors.white.withOpacity(0.20)
                : Colors.transparent,
          ),
          child: Icon(widget.icon, color: color, size: widget.size),
        ),
      ),
    );

    if (widget.tooltip != null) {
      return Tooltip(message: widget.tooltip!, child: btn);
    }
    return btn;
  }
}
