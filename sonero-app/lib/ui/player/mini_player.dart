import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';
import '../theme.dart';
import '../widgets/track_cover_image.dart';
import 'mobile_player_sheet.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final track  = player.currentTrack;
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (track == null) return const SizedBox.shrink();
    if (player.isVideoMode) return const SizedBox.shrink();

    // ── MOBILE: pill mini player ──────────────────────────────────────
    if (isMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color: context.colors.surface.withOpacity(0.97),
            borderRadius: BorderRadius.circular(32),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: context.colors.border.withOpacity(0.12),
              width: 0.5,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // Thin progress bar at top
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SizedBox(
                  height: 2.5,
                  child: LinearProgressIndicator(
                    value: player.duration.inMilliseconds > 0
                        ? player.position.inMilliseconds / player.duration.inMilliseconds
                        : 0.0,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                  ),
                ),
              ),
              // Content
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const MobileExpandedPlayer(),
                          );
                        },
                        child: Row(
                          children: [
                            Hero(
                              tag: 'mobile_player_cover',
                              child: ClipOval(
                                child: Container(
                                  width: 40,
                                  height: 40,
                                  color: context.colors.surfaceAlt,
                                  child: getCoverImageProvider(track.coverUrl) != null
                                      ? AdjustedCoverImage(
                                          coverUrl: track.coverUrl,
                                          width: 40,
                                          height: 40,
                                        )
                                      : Icon(Icons.music_note, color: context.colors.textSecondary, size: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
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
                                      fontSize: 13,
                                    ),
                                  ),
                                  if (track.artist.isNotEmpty)
                                    Text(
                                      track.artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: context.colors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.skip_previous_rounded, color: context.colors.textPrimary, size: 20),
                      onPressed: player.previous,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none, elevation: 0),
                    ),
                    IconButton(
                      icon: Icon(
                        player.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: context.colors.textPrimary,
                        size: 24,
                      ),
                      onPressed: player.playPause,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                      style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none, elevation: 0),
                    ),
                    IconButton(
                      icon: Icon(Icons.skip_next_rounded, color: context.colors.textPrimary, size: 20),
                      onPressed: player.next,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none, elevation: 0),
                    ),
                    Container(
                      width: 1,
                      height: 18,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      color: context.colors.border.withOpacity(0.3),
                    ),
                    IconButton(
                      icon: Icon(Icons.stop_rounded, color: Colors.red.shade300, size: 20),
                      onPressed: player.stop,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Detener',
                      style: IconButton.styleFrom(backgroundColor: Colors.transparent, side: BorderSide.none, elevation: 0),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Desktop/tablet player is now handled by app_shell's unified bottom bar
    return const SizedBox.shrink();
  }
}
