import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../models/listen_job.dart';
import '../../providers/listen_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';
import '../widgets/track_cover_image.dart';

class ListenOverlay extends StatelessWidget {
  const ListenOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final listen = context.watch<ListenProvider>();

    if (listen.currentJob == null) return const SizedBox.shrink();

    return Positioned.fill(
      child: GestureDetector(
        onTap: () {}, // absorb taps
        child: ColoredBox(
          color: Colors.black.withOpacity(0.7),
          child: Center(
            child: _OverlayCard(job: listen.currentJob!),
          ),
        ),
      )
          .animate()
          .fadeIn(duration: 200.ms),
    );
  }
}

class _OverlayCard extends StatelessWidget {
  final ListenJob job;
  const _OverlayCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final listen = context.read<ListenProvider>();
    final library = context.read<LibraryProvider>();
    final settings = context.read<SettingsProvider>();

    return Container(
      width: 340,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.colors.border),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
            blurRadius: 15,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Waveform / status icon ──────────────────────────────────────
          if (job.isActive) ...[
            _WaveformAnimation(),
            const SizedBox(height: 20),
          ] else if (job.isDone) ...[
            _SuccessIcon(track: job.track),
            const SizedBox(height: 20),
          ] else if (job.isFailed) ...[
            Icon(Icons.error_outline_rounded,
                color: context.colors.error, size: 52),
            const SizedBox(height: 20),
          ],

          // ── Step label ─────────────────────────────────────────────────
          Text(
            job.step.replaceAll(RegExp(r'^[^\w]*'), ''),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),

          // ── Progress bar (only when active) ────────────────────────────
          if (job.isActive) ...[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: job.progress / 100,
                backgroundColor: context.colors.border,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
                minHeight: 4,
              ),
            ),
          ],

          // ── Error message ──────────────────────────────────────────────
          if (job.isFailed && job.error != null) ...[
            const SizedBox(height: 8),
            Text(
              job.error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: context.colors.textSecondary, fontSize: 12),
            ),
          ],

          const SizedBox(height: 24),

          // ── Action buttons ─────────────────────────────────────────────
          if (job.isActive)
            TextButton(
              onPressed: listen.cancel,
              child: Text('Cancelar',
                  style: TextStyle(color: context.colors.textSecondary)),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (job.isFailed) ...[
                  ElevatedButton(
                    onPressed: listen.retry,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                    ),
                    child: Text('Reintentar'),
                  ),
                  const SizedBox(width: 12),
                ],
                ElevatedButton(
                  onPressed: () {
                    listen.dismiss();
                    // Refresh library when done
                    if (job.isDone) {
                      library.loadTracks(settings.api);
                      library.loadPlaylists(settings.api);
                    }
                  },
                  style: job.isFailed ? ElevatedButton.styleFrom(
                    backgroundColor: context.colors.border,
                    foregroundColor: context.colors.textPrimary,
                  ) : null,
                  child: Text('Cerrar'),
                ),
              ],
            ),
        ],
      ),
    )
        .animate()
        .slideY(begin: 0.1, end: 0, duration: 300.ms, curve: Curves.easeOut)
        .fadeIn(duration: 200.ms);
  }
}

// ── Waveform animation ────────────────────────────────────────────────────────

class _WaveformAnimation extends StatefulWidget {
  @override
  State<_WaveformAnimation> createState() => _WaveformAnimationState();
}

class _WaveformAnimationState extends State<_WaveformAnimation>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  static const _barCount = 12;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(_barCount, (i) {
      final ctrl = AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 600 + (i * 80)),
      )..repeat(reverse: true);
      Future.delayed(Duration(milliseconds: i * 60), () {
        if (mounted) ctrl.forward();
      });
      return ctrl;
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barCount, (i) {
          return AnimatedBuilder(
            animation: _controllers[i],
            builder: (_, __) {
              final h = 8 + (_controllers[i].value * 36);
              return Container(
                width: 5,
                height: h,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  gradient: context.colors.gradient,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// ── Success icon with album art ───────────────────────────────────────────────

class _SuccessIcon extends StatelessWidget {
  final TrackResult? track;
  const _SuccessIcon({this.track});

  @override
  Widget build(BuildContext context) {
    if (track?.coverUrl != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: TrackCoverImage(
          coverUrl: track!.coverUrl,
          width: 80,
          height: 80,
          fit: BoxFit.cover,
          errorWidget: _defaultIcon(context),
        ),
      );
    }
    return _defaultIcon(context);
  }

  Widget _defaultIcon(BuildContext context) => Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: context.colors.gradient,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.check_rounded, color: Colors.white, size: 40),
      );
}



