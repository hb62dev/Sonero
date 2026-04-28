import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';
import '../theme.dart';
import 'video_player_view.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track = player.currentTrack;

    if (track == null) return const SizedBox.shrink();

    return Container(
      height: 80,
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
                    IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: context.colors.textPrimary,
                        size: 32,
                      ),
                      onPressed: player.playPause,
                    ),
                    if (player.isVideo)
                      IconButton(
                        icon: Icon(Icons.fullscreen_rounded, color: context.colors.textSecondary),
                        tooltip: 'Mostrar Video',
                        onPressed: () {
                          // TODO: Open video dialog/route
                          _showVideoDialog(context);
                        },
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
                          value: player.position.inMilliseconds.toDouble(),
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
                      value: player.volume,
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
}
