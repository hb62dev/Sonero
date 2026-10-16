import 'package:flutter/material.dart';
import 'coverflow_carousel_controller.dart';

const double _tapTargetSize = 40.0;

/// Shows the current page as a sliding pill over dots.
///
/// Listens to [controller]'s [ValueNotifier] and animates the active
/// indicator between pages as the carousel scrolls.
class CoverflowPageIndicator extends StatelessWidget {
  const CoverflowPageIndicator({
    super.key,
    required this.controller,
    required this.itemCount,
    this.activeColor = Colors.white,
    this.inactiveColor = Colors.white38,
    this.dotSize = 8.0,
    this.dotSpacing = 12.0,
    this.onTap,
  }) : assert(dotSize > 0, 'dotSize must be greater than zero'),
       assert(dotSpacing >= 0, 'dotSpacing must be non-negative');

  final CoverflowCarouselController controller;
  final int itemCount;
  final Color activeColor;
  final Color inactiveColor;
  final double dotSize;
  final double dotSpacing;
  final void Function(int index)? onTap;

  @override
  Widget build(BuildContext context) {
    final step = dotSize + dotSpacing;

    return ValueListenableBuilder<double>(
      valueListenable: controller.pageListenable,
      builder: (context, page, _) {
        if (itemCount <= 0) return const SizedBox.shrink();

        final count = itemCount;
        final normalized = count > 1 ? page % count : 0.0;
        final floor = normalized.floor();
        final t = normalized - floor;
        final indexB = (floor + 1) % count;
        final isWrapping = count > 1 && indexB == 0 && floor == count - 1;

        final rowWidth = count * dotSize + (count - 1) * dotSpacing;
        // Symmetric padding so the tap surface is dotSize + 2*pad ==
        // _tapTargetSize in both directions, matching the requested 40px.
        final pad = (_tapTargetSize - dotSize) / 2;
        final totalWidth = rowWidth + pad * 2;
        const totalHeight = _tapTargetSize;

        return SizedBox(
          width: totalWidth,
          height: totalHeight,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Single tap surface for the whole strip. Resolves taps by
              // nearest-dot-center instead of per-dot overlapping regions,
              // so there's no z-order ambiguity between neighbors.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: onTap == null
                      ? null
                      : (details) {
                          final dx =
                              details.localPosition.dx - pad - dotSize / 2;
                          final index = (dx / step).round().clamp(0, count - 1);
                          onTap!(index);
                        },
                ),
              ),
              for (final i in List.generate(count, (i) => i))
                Positioned(
                  left: pad + i * step,
                  top: (totalHeight - dotSize) / 2,
                  width: dotSize,
                  height: dotSize,
                  child: IgnorePointer(
                    child: Semantics(
                      button: true,
                      label: 'Page ${i + 1} of $count',
                      onTap: onTap == null ? null : () => onTap!(i),
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: inactiveColor,
                        ),
                      ),
                    ),
                  ),
                ),
              if (isWrapping) ...[
                _buildActivePill(left: pad, width: dotSize * t),
                _buildActivePill(
                  left: pad + floor * step,
                  width: dotSize * (1.0 - t),
                ),
              ] else
                _buildActivePill(
                  left:
                      pad +
                      floor * step +
                      (t < 0.5 ? 0 : ((t - 0.5) / 0.5) * step),
                  width:
                      dotSize +
                      (t < 0.5
                          ? (t / 0.5) * step
                          : (1.0 - (t - 0.5) / 0.5) * step),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActivePill({required double left, required double width}) {
    return Positioned(
      left: left,
      top: (_tapTargetSize - dotSize) / 2,
      width: width,
      height: dotSize,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            color: activeColor,
            borderRadius: BorderRadius.circular(dotSize / 2),
          ),
        ),
      ),
    );
  }
}
