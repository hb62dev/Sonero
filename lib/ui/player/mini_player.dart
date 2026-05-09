import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import '../../providers/player_provider.dart';
import '../theme.dart';
import '../widgets/hover_scale.dart';
import 'video_player_view.dart';
import 'lyrics_view.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        border: Border(top: BorderSide(color: context.colors.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          // Track Info
          Expanded(
            flex: 1,
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: context.colors.surface,
                    image: track.coverUrl != null
                        ? DecorationImage(
                            image: NetworkImage(track.coverUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: track.coverUrl == null
                      ? Icon(Icons.music_note, color: context.colors.textSecondary)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title.isNotEmpty ? track.title : track.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      if (track.artist.isNotEmpty)
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: context.colors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Controls
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          HoverScale(
                            scale: 1.15,
                            child: IconButton(
                              icon: Icon(
                                Icons.shuffle_rounded, 
                                color: player.isShuffle ? Theme.of(context).colorScheme.primary : context.colors.textSecondary, 
                                size: 20
                              ),
                              tooltip: 'Aleatorio',
                              onPressed: player.toggleShuffle,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ),
                          const SizedBox(width: 4),
                          HoverScale(
                            scale: 1.15,
                            child: IconButton(
                              icon: Icon(Icons.skip_previous_rounded, color: context.colors.textPrimary, size: 26),
                              tooltip: 'Anterior',
                              onPressed: player.previous,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    HoverScale(
                      scale: 1.15,
                      child: IconButton(
                        icon: Icon(
                          player.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_filled_rounded,
                          color: Theme.of(context).colorScheme.primary,
                          size: 40,
                        ),
                        onPressed: player.playPause,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          HoverScale(
                            scale: 1.15,
                            child: IconButton(
                              icon: Icon(Icons.skip_next_rounded, color: context.colors.textPrimary, size: 26),
                              tooltip: 'Siguiente',
                              onPressed: player.next,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ),
                          const SizedBox(width: 4),
                          HoverScale(
                            scale: 1.15,
                            child: IconButton(
                              icon: Icon(
                                player.repeatMode == PlaylistMode.single ? Icons.repeat_one_rounded : Icons.repeat_rounded, 
                                color: player.repeatMode != PlaylistMode.none ? Theme.of(context).colorScheme.primary : context.colors.textSecondary, 
                                size: 20
                              ),
                              tooltip: 'Repetir',
                              onPressed: player.toggleRepeat,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ),
                          if (player.isVideo) ...[
                            const SizedBox(width: 8),
                            HoverScale(
                              scale: 1.15,
                              child: IconButton(
                                icon: Icon(Icons.fullscreen_rounded, color: context.colors.textSecondary, size: 22),
                                tooltip: 'Mostrar Video',
                                onPressed: () {
                                  _showVideoDialog(context);
                                },
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          HoverScale(
                            scale: 1.15,
                            child: IconButton(
                              icon: Icon(Icons.lyrics_outlined, color: context.colors.textSecondary, size: 22),
                              tooltip: 'Ver Letras',
                              onPressed: () {
                                _showLyricsDialog(context, track.title, track.artist);
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      _formatDuration(player.position),
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          activeTrackColor: Theme.of(context).colorScheme.primary,
                          inactiveTrackColor: context.colors.border,
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
                          onChanged: (val) {
                            player.seek(Duration(milliseconds: val.toInt()));
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDuration(player.duration),
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Volume & Actions
          Expanded(
            flex: 1,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.volume_up_rounded, color: context.colors.textSecondary, size: 20),
                SizedBox(
                  width: 100,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: context.colors.textSecondary,
                      inactiveTrackColor: context.colors.border,
                      thumbColor: context.colors.textPrimary,
                    ),
                    child: Slider(
                      value: player.volume.toDouble().clamp(0.0, 100.0),
                      max: 100,
                      onChanged: (val) {
                        player.setVolume(val);
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: context.colors.textSecondary, size: 20),
                  onPressed: player.stop,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  void _showVideoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => const VideoPlayerView(),
    );
  }

  void _showLyricsDialog(BuildContext context, String title, String artist) {
    showDialog(
      context: context,
      builder: (_) => LyricsView(title: title, artist: artist),
    );
  }
}
