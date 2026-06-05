import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import '../../providers/player_provider.dart';
import '../theme.dart';
import 'lyrics_view.dart';

class MobileExpandedPlayer extends StatelessWidget {
  const MobileExpandedPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    final hasCover = track.coverUrl != null && track.coverUrl!.isNotEmpty;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: context.colors.bg,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(28),
          topRight: Radius.circular(28),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // ── Background artwork blur ────────────────────────────────────────
          if (hasCover)
            Positioned.fill(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  decoration: BoxDecoration(
                    image: DecorationImage(
                      image: NetworkImage(track.coverUrl!),
                      fit: BoxFit.cover,
                      colorFilter: ColorFilter.mode(
                        Colors.black.withValues(alpha: 0.65),
                        BlendMode.darken,
                      ),
                    ),
                  ),
                ),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.colors.surfaceAlt,
                      context.colors.bg,
                    ],
                  ),
                ),
              ),
            ),

          // ── Player Content ──────────────────────────────────────────────────
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Drag Handle & Top Header ────────────────────────────────
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded,
                            color: context.colors.textPrimary, size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Text(
                        'Reproduciendo',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 1.0,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_horiz_rounded,
                            color: context.colors.textPrimary, size: 24),
                        onPressed: () => _showMoreOptions(context, player, track),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // ── Large Cover Art ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  child: Center(
                    child: Hero(
                      tag: 'mobile_player_cover',
                      child: Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: context.colors.surface,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                              offset: const Offset(0, 10),
                            ),
                          ],
                          image: hasCover
                              ? DecorationImage(
                                  image: NetworkImage(track.coverUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: !hasCover
                            ? Icon(Icons.music_note_rounded,
                                color: context.colors.textSecondary, size: 80)
                            : null,
                      ),
                    ),
                  ),
                ),

                const Spacer(),

                // ── Song Details (Title & Artist) ────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        track.title.isNotEmpty ? track.title : track.filename,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (track.artist.isNotEmpty)
                        Text(
                          track.artist,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Interactive Seek Bar Slider ──────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: primaryColor,
                          inactiveTrackColor: context.colors.border.withValues(alpha: 0.4),
                          thumbColor: context.colors.textPrimary,
                        ),
                        child: Slider(
                          value: player.position.inMilliseconds.toDouble().clamp(
                                0.0,
                                player.duration.inMilliseconds > 0
                                    ? player.duration.inMilliseconds.toDouble()
                                    : 100.0,
                              ),
                          max: player.duration.inMilliseconds > 0
                              ? player.duration.inMilliseconds.toDouble()
                              : 100.0,
                          onChanged: (val) =>
                              player.seek(Duration(milliseconds: val.toInt())),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _formatDuration(player.position),
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                            Text(
                              _formatDuration(player.duration),
                              style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── Playback Controls Row ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Shuffle Button
                      IconButton(
                        icon: Icon(
                          Icons.shuffle_rounded,
                          color: player.isShuffle
                              ? primaryColor
                              : context.colors.textSecondary,
                          size: 24,
                        ),
                        onPressed: player.toggleShuffle,
                      ),
                      // Previous Button
                      IconButton(
                        icon: Icon(Icons.skip_previous_rounded,
                            color: context.colors.textPrimary, size: 36),
                        onPressed: player.previous,
                      ),
                      // Play/Pause circular button
                      GestureDetector(
                        onTap: player.playPause,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: [primaryColor, primaryColor.withValues(alpha: 0.8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.4),
                                blurRadius: 12,
                                spreadRadius: 1,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Icon(
                            player.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                      // Next Button
                      IconButton(
                        icon: Icon(Icons.skip_next_rounded,
                            color: context.colors.textPrimary, size: 36),
                        onPressed: player.next,
                      ),
                      // Repeat Button
                      IconButton(
                        icon: Icon(
                          player.repeatMode == PlaylistMode.single
                              ? Icons.repeat_one_rounded
                              : Icons.repeat_rounded,
                          color: player.repeatMode != PlaylistMode.none
                              ? primaryColor
                              : context.colors.textSecondary,
                          size: 24,
                        ),
                        onPressed: player.toggleRepeat,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Volume & Utilities Row ────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceAlt.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: context.colors.border.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Volume slider control
                        Row(
                          children: [
                            Icon(
                              player.volume > 0
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_mute_rounded,
                              color: context.colors.textSecondary,
                              size: 18,
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  trackHeight: 3,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                                  activeTrackColor: context.colors.textSecondary,
                                  inactiveTrackColor: context.colors.border.withValues(alpha: 0.3),
                                  thumbColor: context.colors.textPrimary,
                                ),
                                child: Slider(
                                  value: player.volume.toDouble().clamp(0.0, 100.0),
                                  max: 100,
                                  onChanged: (val) => player.setVolume(val),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Quick Toggles
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Lyrics Button
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop(); // Close sheet
                                _showLyricsDialog(
                                  context,
                                  track.title,
                                  track.artist,
                                  track.filename,
                                );
                              },
                              icon: Icon(Icons.lyrics_outlined,
                                  color: context.colors.textSecondary, size: 18),
                              label: Text(
                                'Letras',
                                style: TextStyle(
                                    color: context.colors.textSecondary, fontSize: 12),
                              ),
                            ),
                            // Video Toggle
                            if (player.isVideo)
                              TextButton.icon(
                                onPressed: () {
                                  Navigator.of(context).pop(); // Close sheet
                                  player.setVideoMode(true);
                                },
                                icon: Icon(Icons.fullscreen_rounded,
                                    color: context.colors.textSecondary, size: 18),
                                label: Text(
                                  'Video',
                                  style: TextStyle(
                                      color: context.colors.textSecondary, fontSize: 12),
                                ),
                              ),
                            // Stop Button
                            TextButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop(); // Close sheet
                                player.stop();
                              },
                              icon: const Icon(Icons.stop_rounded,
                                  color: Colors.redAccent, size: 18),
                              label: const Text(
                                'Detener',
                                style: TextStyle(color: Colors.redAccent, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  void _showLyricsDialog(
      BuildContext context, String title, String artist, String? filename) {
    showDialog(
      context: context,
      builder: (_) => LyricsView(title: title, artist: artist, filename: filename),
    );
  }

  void _showMoreOptions(BuildContext context, PlayerProvider player, dynamic track) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.playlist_add_rounded, color: context.colors.textPrimary),
                title: Text('Añadir a playlist', style: TextStyle(color: context.colors.textPrimary)),
                onTap: () {
                  // Implement playlist addition if applicable
                  Navigator.of(context).pop();
                },
              ),
              ListTile(
                leading: const Icon(Icons.share_rounded, color: Colors.blueAccent),
                title: Text('Compartir', style: TextStyle(color: context.colors.textPrimary)),
                onTap: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        );
      },
    );
  }
}
