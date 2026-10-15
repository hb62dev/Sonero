import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:coverflow_carousel/coverflow_carousel.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/track.dart';
import '../theme.dart';
import '../widgets/track_cover_image.dart';
import 'mobile_player_sheet.dart';

/// Cover Flow carousel — uses coverflow_carousel package for smooth 3D scrolling.
class QueueCarouselView extends StatefulWidget {
  const QueueCarouselView({super.key});

  @override
  State<QueueCarouselView> createState() => _QueueCarouselViewState();
}

class _QueueCarouselViewState extends State<QueueCarouselView> {
  final Set<int> _flippedCards = {};
  CoverflowCarouselController? _controller;
  int _viewingIndex = 0;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerProvider>();
    final queue = player.queue;
    final current = player.currentTrack;
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (queue.isEmpty) return const SizedBox.shrink();

    final currentIndex = current != null
        ? queue.indexWhere((t) => t.filename == current.filename)
        : 0;

    // Track the browsing index for the counter display
    if (_viewingIndex < 0 || _viewingIndex >= queue.length) {
      _viewingIndex = currentIndex >= 0 ? currentIndex : 0;
    }

    // Card size
    final cardWidth = isMobile ? screenWidth * 0.65 : (screenWidth * 0.28).clamp(200.0, 420.0);
    final cardHeight = cardWidth * 1.05;

    // Create controller with initial page
    _controller?.dispose();
    _controller = CoverflowCarouselController();

    return DefaultTextStyle(
      style: const TextStyle(decoration: TextDecoration.none, color: Colors.white),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.95),
              Colors.black.withValues(alpha: 0.8),
            ],
          ),
        ),
        child: Column(
          children: [
            // ── Header ──
            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 8, isMobile ? 16 : 24, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                          size: 24,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'Cover Flow',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        letterSpacing: 0.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${(_viewingIndex >= 0 ? _viewingIndex + 1 : 1)} / ${queue.length}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ── 3D Carousel using coverflow_carousel ──
            Expanded(
              child: CoverflowCarousel.builder(
                controller: _controller,
                itemCount: queue.length,
                itemWidth: cardWidth,
                itemHeight: cardHeight,
                scrollDirection: Axis.horizontal,
                initialPage: currentIndex >= 0 ? currentIndex : 0,
                isInfinite: false,
                entryAnimation: CoverflowEntryAnimation.stack,
                entryAnimationDuration: const Duration(milliseconds: 800),
                enableHoverTilt: true,
                enableShadow: true,
                cardBorderRadius: BorderRadius.circular(16),
                onPageChanged: (index) {
                  // Only update the viewing index for the counter
                  setState(() => _viewingIndex = index);
                },
                itemBuilder: (context, index) {
                  final track = queue[index];
                  final isCurrentTrack = player.currentTrack?.filename == track.filename;
                  final hasCover = track.coverUrl != null && track.coverUrl!.isNotEmpty;

                  return GestureDetector(
                    onTap: () {
                      setState(() {
                        if (_flippedCards.contains(index)) {
                          _flippedCards.remove(index);
                        } else {
                          _flippedCards.add(index);
                        }
                      });
                    },
                    onDoubleTap: () {
                      // Double tap plays the track
                      final settings = context.read<SettingsProvider>();
                      player.playTrack(track, queue, settings);
                    },
                    child: _flippedCards.contains(index)
                        ? _buildBackFace(context, player, track, isCurrentTrack, cardWidth)
                        : _buildFrontFace(context, player, track, hasCover, isCurrentTrack),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FRONT FACE: Cover Art ──
  Widget _buildFrontFace(BuildContext context, PlayerProvider player, Track track, bool hasCover, bool isCurrentTrack) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: context.colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isCurrentTrack ? 0.5 : 0.3),
            blurRadius: isCurrentTrack ? 30 : 15,
            spreadRadius: isCurrentTrack ? 4 : 1,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Cover image
          if (hasCover && getCoverImageProvider(track.coverUrl) != null)
            AdjustedCoverImage(
              coverUrl: track.coverUrl,
              width: double.infinity,
              height: double.infinity,
            )
          else
            Container(
              color: context.colors.surfaceAlt,
              child: Icon(Icons.music_note_rounded, color: context.colors.textSecondary, size: 60),
            ),

          // Bottom gradient with track info
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 40, 14, 14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.85)],
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    track.title.isNotEmpty ? track.title : track.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, decoration: TextDecoration.none),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, fontWeight: FontWeight.w500, decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
          ),

          // Playing indicator
          if (isCurrentTrack && player.isPlaying)
            Positioned(
              top: 10, right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.equalizer_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 3),
                    Text('Sonando', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── BACK FACE: Track List (iPod style) ──
  Widget _buildBackFace(BuildContext context, PlayerProvider player, Track track, bool isCurrentTrack, double side) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasCover = track.coverUrl != null && track.coverUrl!.isNotEmpty;
    final queue = player.queue;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: 4,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Blurred background
          if (hasCover && getCoverImageProvider(track.coverUrl) != null)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: Image(
                image: getCoverImageProvider(track.coverUrl)!,
                fit: BoxFit.cover,
              ),
            ),

          // Dark overlay
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.black.withValues(alpha: 0.75),
            ),
          ),

          // Track list
          Material(
            color: Colors.transparent,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 0.5)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        track.title.isNotEmpty ? track.title : track.filename,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: side * 0.042, fontWeight: FontWeight.w700, decoration: TextDecoration.none),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist.isNotEmpty ? track.artist : 'Desconocido',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: side * 0.033, decoration: TextDecoration.none),
                      ),
                    ],
                  ),
                ),

                // Track list
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: queue.length,
                    itemBuilder: (context, i) {
                      final qTrack = queue[i];
                      final isPlaying = player.currentTrack?.filename == qTrack.filename;
                      return InkWell(
                        onTap: () async {
                          try {
                            final settings = context.read<SettingsProvider>();
                            await player.playTrack(qTrack, queue, settings);
                          } catch (_) {}
                          if (mounted) {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(
                              PageRouteBuilder(
                                opaque: true,
                                pageBuilder: (_, __, ___) => const MobileExpandedPlayer(),
                                transitionsBuilder: (_, anim, __, child) {
                                  return SlideTransition(
                                    position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                                        .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                                    child: child,
                                  );
                                },
                                transitionDuration: const Duration(milliseconds: 350),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 12, vertical: side * 0.02),
                          decoration: BoxDecoration(
                            color: isPlaying ? accent.withValues(alpha: 0.2) : Colors.transparent,
                            border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08), width: 0.5)),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 22,
                                child: isPlaying
                                    ? Icon(Icons.equalizer_rounded, color: accent, size: 14)
                                    : Text(
                                        '${i + 1}',
                                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: side * 0.03, decoration: TextDecoration.none),
                                      ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  qTrack.title.isNotEmpty ? qTrack.title : qTrack.filename,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isPlaying ? accent : Colors.white,
                                    fontSize: side * 0.035,
                                    fontWeight: isPlaying ? FontWeight.w700 : FontWeight.w500,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
