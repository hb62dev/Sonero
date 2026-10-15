import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'card_model.dart';
import 'coverflow_carousel.dart';

/// The core layout rendering engine for [CoverflowCarousel].
///
/// Responsible for building the stacked card widget hierarchy, calculating horizontal
/// offsets with spacing fanning, computing 3D transformation matrices (skew angle and perspective),
/// sorting cards by depth (z-index), and applying entry animation timelines.
class CoverflowCarouselRenderer extends StatelessWidget {
  /// The total number of items in the carousel.
  final int itemCount;

  /// Builder callback that returns the child widget representing the card at the given index.
  final IndexedWidgetBuilder itemBuilder;

  /// The active scroll position as a fractional page index (e.g. `2.5` represents halfway between index 2 and index 3).
  final double centerIndex;

  /// The maximum available width from the parent layout constraints.
  final double maxWidth;

  /// The maximum available height from the parent layout constraints.
  final double maxHeight;

  /// The axis along which the carousel scrolls.
  final Axis scrollDirection;

  /// The width of the focused center card.
  final double itemWidth;

  /// The height of the focused center card.
  final double itemHeight;

  /// The number of visible cards to render on each side of the active center card.
  final int visibleItems;

  /// Intensity of the blur effect applied to off-center cards.
  final double obscure;

  /// The rotation angle (in radians) applied to off-center cards along the Y-axis (or X-axis if vertical).
  final double skewAngle;

  /// Horizontal (or vertical if vertical direction) spacing between the center card and the immediately adjacent cards.
  final double nearCardSpacing;

  /// Horizontal (or vertical if vertical direction) spacing between adjacent background cards.
  final double farCardSpacing;

  /// Perspective factor for 3D projection, modifying the matrix entry `(3, 2)`.
  final double perspective;

  /// The underlying page controller used to synchronize programmatically triggered scroll animations.
  final PageController controller;

  /// Duration for card transition animations.
  final Duration animationDuration;

  /// Easing curve for card transition animations.
  final Curve animationCurve;

  /// Whether the carousel wraps around infinitely.
  final bool isInfinite;

  /// The active entry animation type.
  final CoverflowEntryAnimation entryAnimation;

  /// The current progression of the entry animation, from `0.0` (start) to `1.0` (complete).
  final double entryProgress;

  /// The initial virtual page index.
  final int initialPage;

  /// Optional builder that returns a widget to stack on top of the active centered card.
  final Widget Function(BuildContext context, int index)? centerOverlayBuilder;

  /// Whether to enable 3D hover/tilt effects on cards.
  final bool enableHoverTilt;

  /// The maximum tilt angle (in radians) applied during the 3D hover effect.
  final double maxHoverTiltAngle;

  /// Whether to enable 3D perspective shadows on cards.
  final bool enableShadow;

  /// The color of the drop shadow.
  final Color shadowColor;

  /// The shadow elevation/depth.
  final double elevation;

  /// The card corner border radius.
  final BorderRadius cardBorderRadius;

  /// Creates a [CoverflowCarouselRenderer] to lay out and paint the carousel cards.
  const CoverflowCarouselRenderer({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.centerIndex,
    required this.maxWidth,
    required this.maxHeight,
    required this.scrollDirection,
    required this.itemWidth,
    required this.itemHeight,
    required this.obscure,
    required this.skewAngle,
    required this.nearCardSpacing,
    required this.farCardSpacing,
    required this.controller,
    required this.animationDuration,
    required this.animationCurve,
    required this.visibleItems,
    required this.perspective,
    required this.isInfinite,
    required this.entryAnimation,
    required this.entryProgress,
    required this.initialPage,
    required this.enableHoverTilt,
    required this.maxHoverTiltAngle,
    required this.enableShadow,
    required this.shadowColor,
    required this.elevation,
    required this.cardBorderRadius,
    this.centerOverlayBuilder,
  });

  /// Calculates the center position (logical pixels) for a card at [index] along the scroll axis.
  ///
  /// The center card sits exactly at the middle of the available viewport dimension.
  /// Adjacent cards are distributed outwards using [nearCardSpacing] for the first step,
  /// and [farCardSpacing] for subsequent steps, modified by the entry animation progress if active.
  double getCardPosition(int index) {
    final center =
        (scrollDirection == Axis.horizontal ? maxWidth : maxHeight) / 2;
    final distance = index - centerIndex;

    final spacingFactor =
        entryAnimation == CoverflowEntryAnimation.spacingExpand
        ? entryProgress
        : 1.0;
    final nearSpacing = nearCardSpacing * spacingFactor;
    final farSpacing = farCardSpacing * spacingFactor;

    if (distance.abs() <= 1) {
      return center + distance * nearSpacing;
    }

    return center +
        distance.sign * nearSpacing +
        distance.sign * (distance.abs() - 1) * farSpacing;
  }

  /// Calculates the scaled width of a card at [index].
  ///
  /// In horizontal mode, width scales down to 88% then 72%.
  /// In vertical mode, width scales down slightly (clamp to 75%).
  double getCardWidth(int index) {
    final distance = (centerIndex - index).abs();
    if (scrollDirection == Axis.horizontal) {
      final centerWidth = itemWidth;
      final nearWidth = itemWidth * 0.88;
      final farWidth = itemWidth * 0.72;

      if (distance < 1) {
        return centerWidth -
            (centerWidth - nearWidth) * (distance - distance.floor());
      }

      if (distance < 2) {
        return nearWidth -
            (nearWidth - farWidth) * (distance - distance.floor());
      }

      return farWidth;
    } else {
      return (itemWidth * (1 - distance * 0.08)).clamp(
        itemWidth * 0.75,
        itemWidth,
      );
    }
  }

  /// Calculates the scaled height of a card at [index].
  ///
  /// In vertical mode, height scales down to 88% then 72%.
  /// In horizontal mode, height scales down slightly (clamp to 75%).
  double getCardHeight(int index) {
    final distance = (centerIndex - index).abs();
    if (scrollDirection == Axis.vertical) {
      final centerHeight = itemHeight;
      final nearHeight = itemHeight * 0.88;
      final farHeight = itemHeight * 0.72;

      if (distance < 1) {
        return centerHeight -
            (centerHeight - nearHeight) * (distance - distance.floor());
      }

      if (distance < 2) {
        return nearHeight -
            (nearHeight - farHeight) * (distance - distance.floor());
      }

      return farHeight;
    } else {
      return (itemHeight * (1 - distance * 0.08)).clamp(
        itemHeight * 0.75,
        itemHeight,
      );
    }
  }

  /// Computes the 3D perspective matrix for a card at [index].
  ///
  /// Applies a perspective entry `(3, 2) = perspective` and rotates the card along the
  /// Y-axis by `skewAngle * distance` in horizontal mode, or the X-axis in vertical mode.
  Matrix4 getTransform(int index) {
    final distance = centerIndex - index;
    final transform = Matrix4.identity()..setEntry(3, 2, perspective);

    if (scrollDirection == Axis.horizontal) {
      transform.rotateY(skewAngle * distance);
    } else {
      transform.rotateX(-skewAngle * distance);
    }

    return transform;
  }

  /// Computes the blur filter applied to a card at [index] when [obscure] is enabled.
  ImageFilter getFilter(int index) {
    final distance = (centerIndex - index).abs();

    return ImageFilter.blur(
      sigmaX: 5 * obscure * distance,
      sigmaY: 5 * obscure * distance,
    );
  }

  /// Builds a single styled card widget with transformations, gesture handling, and animations.
  ///
  /// Handles transition gestures, entry animation timelines (scaling, slide translations, stacking fades),
  /// 3D transformations, vertical scaling padding, and backdrop blur filters.
  Widget buildCard(BuildContext context, int index, Widget child) {
    final distance = (centerIndex - index).abs();
    final width = getCardWidth(index);
    final height = getCardHeight(index);
    final position = getCardPosition(index);

    final double paddingValue =
        (scrollDirection == Axis.horizontal ? width : height) * 0.05 * distance;
    final padding = scrollDirection == Axis.horizontal
        ? EdgeInsets.symmetric(vertical: paddingValue)
        : EdgeInsets.symmetric(horizontal: paddingValue);

    final bool isCentered = index == centerIndex.round();

    final double cardProgress;
    if (entryAnimation == CoverflowEntryAnimation.none) {
      cardProgress = 1.0;
    } else if (entryAnimation == CoverflowEntryAnimation.stack) {
      final double maxDistance = visibleItems.toDouble();
      final double intervals = maxDistance > 0 ? maxDistance + 1 : 1.0;
      final double intervalWidth = 1.0 / intervals;
      final double distance = (initialPage - index).abs().toDouble().clamp(
        0.0,
        maxDistance,
      );
      final double start = distance * intervalWidth;
      final double end = start + intervalWidth;

      if (entryProgress <= start) {
        cardProgress = 0.0;
      } else if (entryProgress >= end) {
        cardProgress = 1.0;
      } else {
        cardProgress = (entryProgress - start) / intervalWidth;
      }
    } else {
      final double staggerDistance = (initialPage - index).abs().toDouble();
      final double start = (staggerDistance * 0.15).clamp(0.0, 0.75);
      const double end = 1.0;
      if (entryProgress <= start) {
        cardProgress = 0.0;
      } else if (entryProgress >= end) {
        cardProgress = 1.0;
      } else {
        cardProgress = (entryProgress - start) / (end - start);
      }
    }

    double opacity = 1.0;
    double scale = 1.0;
    double translateX = 0.0;
    double translateY = 0.0;

    if (entryAnimation != CoverflowEntryAnimation.none) {
      if (entryAnimation == CoverflowEntryAnimation.fadeIn ||
          entryAnimation == CoverflowEntryAnimation.fadeScale) {
        opacity = cardProgress;
      }
      if (entryAnimation == CoverflowEntryAnimation.scaleUp ||
          entryAnimation == CoverflowEntryAnimation.fadeScale) {
        scale = 0.8 + (0.2 * cardProgress);
      }
      if (entryAnimation == CoverflowEntryAnimation.staggeredSlide) {
        opacity = cardProgress;
        if (index == initialPage) {
          translateY = -50.0 * (1.0 - cardProgress);
        } else if (index < initialPage) {
          if (scrollDirection == Axis.horizontal) {
            translateX = -150.0 * (1.0 - cardProgress);
          } else {
            translateY = -150.0 * (1.0 - cardProgress);
          }
        } else {
          if (scrollDirection == Axis.horizontal) {
            translateX = 150.0 * (1.0 - cardProgress);
          } else {
            translateY = 150.0 * (1.0 - cardProgress);
          }
        }
      }
      if (entryAnimation == CoverflowEntryAnimation.stack) {
        scale = 1.8 - (0.8 * cardProgress);
        opacity = (cardProgress * 2.0).clamp(0.0, 1.0);
        translateX = 0.0;
        translateY = 0.0;
      }
    }

    final double overlayOpacity = (1.0 - distance).clamp(0.0, 1.0);
    final Widget cardChild = obscure > 0 && distance > 0
        ? ImageFiltered(imageFilter: getFilter(index), child: child)
        : child;

    final realIndex = isInfinite && itemCount > 0
        ? ((index % itemCount) + itemCount) % itemCount
        : index;

    Widget mainContent = cardChild;

    if (centerOverlayBuilder != null && overlayOpacity > 0.0) {
      final overlayWidget = centerOverlayBuilder!(context, realIndex);
      final double overlayTranslateY = scrollDirection == Axis.vertical
          ? 30.0 * distance
          : 0.0;

      // Calculate the size difference (shrinkage) of the stack content area relative
      // to the standard itemWidth and itemHeight to keep the positioned coordinates fixed
      // relative to the card's center.
      final double horizontalPadding = scrollDirection == Axis.vertical
          ? 2 * paddingValue
          : 0.0;
      final double verticalPadding = scrollDirection == Axis.horizontal
          ? 2 * paddingValue
          : 0.0;
      final double stackWidth = width - horizontalPadding;
      final double stackHeight = height - verticalPadding;
      final double dx = itemWidth - stackWidth;
      final double dy = itemHeight - stackHeight;

      if (overlayWidget is Positioned) {
        final double? left = overlayWidget.left != null
            ? overlayWidget.left! - dx / 2
            : null;
        final double? right = overlayWidget.right != null
            ? overlayWidget.right! - dx / 2
            : null;
        final double? top = overlayWidget.top != null
            ? overlayWidget.top! - dy / 2
            : null;
        final double? bottom = overlayWidget.bottom != null
            ? overlayWidget.bottom! - dy / 2
            : null;

        mainContent = Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            mainContent,
            Positioned(
              key: overlayWidget.key,
              left: left,
              top: top,
              right: right,
              bottom: bottom,
              width: overlayWidget.width,
              height: overlayWidget.height,
              child: IgnorePointer(
                ignoring: !isCentered,
                child: Opacity(
                  opacity: overlayOpacity,
                  child: Transform.translate(
                    offset: Offset(0, overlayTranslateY),
                    child: overlayWidget.child,
                  ),
                ),
              ),
            ),
          ],
        );
      } else if (overlayWidget is PositionedDirectional) {
        final double? start = overlayWidget.start != null
            ? overlayWidget.start! - dx / 2
            : null;
        final double? end = overlayWidget.end != null
            ? overlayWidget.end! - dx / 2
            : null;
        final double? top = overlayWidget.top != null
            ? overlayWidget.top! - dy / 2
            : null;
        final double? bottom = overlayWidget.bottom != null
            ? overlayWidget.bottom! - dy / 2
            : null;

        mainContent = Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            mainContent,
            PositionedDirectional(
              key: overlayWidget.key,
              start: start,
              top: top,
              end: end,
              bottom: bottom,
              width: overlayWidget.width,
              height: overlayWidget.height,
              child: IgnorePointer(
                ignoring: !isCentered,
                child: Opacity(
                  opacity: overlayOpacity,
                  child: Transform.translate(
                    offset: Offset(0, overlayTranslateY),
                    child: overlayWidget.child,
                  ),
                ),
              ),
            ),
          ],
        );
      } else {
        mainContent = Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            mainContent,
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !isCentered,
                child: Opacity(
                  opacity: overlayOpacity,
                  child: Transform.translate(
                    offset: Offset(0, overlayTranslateY),
                    child: overlayWidget,
                  ),
                ),
              ),
            ),
          ],
        );
      }
    }

    final Widget cardWidget = Center(
      child: Container(
        width: width,
        height: height,
        padding: padding,
        child: AbsorbPointer(
          absorbing: !isCentered,
          child: _CoverflowHoverTilt(
            enabled: enableHoverTilt && isCentered,
            maxTiltAngle: maxHoverTiltAngle,
            perspective: perspective,
            enableShadow: enableShadow,
            shadowColor: shadowColor,
            elevation: elevation,
            borderRadius: cardBorderRadius,
            child: mainContent,
          ),
        ),
      ),
    );

    final double leftCoord = scrollDirection == Axis.horizontal
        ? position - width / 2
        : (maxWidth - itemWidth) / 2;
    final double topCoord = scrollDirection == Axis.vertical
        ? position - height / 2
        : (maxHeight - itemHeight) / 2;

    final double posWidth = scrollDirection == Axis.horizontal
        ? width
        : itemWidth;
    final double posHeight = scrollDirection == Axis.vertical
        ? height
        : itemHeight;

    return Positioned(
      left: leftCoord,
      top: topCoord,
      width: posWidth,
      height: posHeight,
      child: GestureDetector(
        onTap: !isCentered
            ? () {
                controller.animateToPage(
                  index,
                  duration: animationDuration,
                  curve: animationCurve,
                );
              }
            : null,
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(translateX, translateY),
            child: Transform.scale(
              scale: scale,
              child: Transform(
                alignment: Alignment.center,
                transform: getTransform(index),
                child: cardWidget,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Evaluates which cards should be rendered and calculates their stacking order.
  ///
  /// Filters cards based on whether they fall within the [visibleItems] threshold.
  /// Computes a [zIndex] for each card using:
  /// `card.zIndex = -(centerIndex - card.id).abs()` (and `999` for the active center card).
  /// Sorts cards ascending by [zIndex] so that background cards paint first and the center
  /// card paints on top.
  List<Widget> buildCards(BuildContext context) {
    final centerRound = centerIndex.round();
    final cards = <CardModel>[];
    final buffer = visibleItems + 1;

    for (int i = centerRound - buffer; i <= centerRound + buffer; i++) {
      if (!isInfinite && (i < 0 || i >= itemCount)) {
        continue;
      }
      if (itemCount <= 0) continue;

      if ((centerIndex - i).abs() > visibleItems + 0.5) {
        continue;
      }

      final realIndex = ((i % itemCount) + itemCount) % itemCount;
      cards.add(CardModel(id: i, child: itemBuilder(context, realIndex)));
    }

    for (final card in cards) {
      if (card.id == centerRound) {
        card.zIndex = 999;
      } else {
        card.zIndex = -(centerIndex - card.id).abs();
      }
    }

    cards.sort((a, b) => a.zIndex.compareTo(b.zIndex));

    return cards
        .map((card) => buildCard(context, card.id, card.child))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: buildCards(context),
    );
  }
}

/// A highly optimized helper widget that applies a 3D hover tilt effect to its child.
///
/// Tracks mouse entry and pointer movements to calculate normalized offsets and apply
/// perspective skew rotation around the horizontal and vertical axes.
class _CoverflowHoverTilt extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double maxTiltAngle;
  final double perspective;
  final bool enableShadow;
  final Color shadowColor;
  final double elevation;
  final BorderRadius borderRadius;

  const _CoverflowHoverTilt({
    required this.child,
    required this.enabled,
    required this.maxTiltAngle,
    required this.perspective,
    required this.enableShadow,
    required this.shadowColor,
    required this.elevation,
    required this.borderRadius,
  });

  @override
  State<_CoverflowHoverTilt> createState() => _CoverflowHoverTiltState();
}

class _CoverflowHoverTiltState extends State<_CoverflowHoverTilt>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  double _targetTiltX = 0.0;
  double _targetTiltY = 0.0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _tick());
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick() {
    final double nextX = lerpDouble(_tiltX, _targetTiltX, 0.15) ?? _targetTiltX;
    final double nextY = lerpDouble(_tiltY, _targetTiltY, 0.15) ?? _targetTiltY;

    if ((nextX - _targetTiltX).abs() < 0.0001 &&
        (nextY - _targetTiltY).abs() < 0.0001) {
      setState(() {
        _tiltX = _targetTiltX;
        _tiltY = _targetTiltY;
      });
      _ticker.stop();
      return;
    }

    setState(() {
      _tiltX = nextX;
      _tiltY = nextY;
    });
  }

  void _ensureTickerRunning() {
    if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  void _onEnter(PointerEnterEvent event) {
    if (!widget.enabled) return;
    _ensureTickerRunning();
  }

  void _onHover(PointerHoverEvent event) {
    if (!widget.enabled) return;
    final size = context.size;
    if (size == null) return;

    final double x = event.localPosition.dx;
    final double y = event.localPosition.dy;

    final double nx = (x / size.width) - 0.5;
    final double ny = (y / size.height) - 0.5;

    _targetTiltX = -ny * widget.maxTiltAngle;
    _targetTiltY = nx * widget.maxTiltAngle;

    _ensureTickerRunning();
  }

  void _onExit(PointerExitEvent event) {
    if (!widget.enabled) return;
    _targetTiltX = 0.0;
    _targetTiltY = 0.0;
    _ensureTickerRunning();
  }

  List<BoxShadow> _buildDynamicShadows() {
    final double elev = widget.elevation;
    if (elev <= 0) return [];

    return [
      BoxShadow(
        color: widget.shadowColor.withValues(alpha: 0.18),
        blurRadius: elev * 1.5,
        offset: Offset(-_tiltY * elev * 2.0, elev + (_tiltX * elev * 2.0)),
        spreadRadius: -elev * 0.1,
      ),
      BoxShadow(
        color: widget.shadowColor.withValues(alpha: 0.1),
        blurRadius: elev * 3.0,
        offset: Offset(
          -_tiltY * elev * 3.0,
          elev * 1.5 + (_tiltX * elev * 3.0),
        ),
        spreadRadius: -elev * 0.2,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final Widget content = Container(
      decoration: BoxDecoration(
        borderRadius: widget.borderRadius,
        boxShadow: widget.enableShadow ? _buildDynamicShadows() : null,
      ),
      child: RepaintBoundary(child: widget.child),
    );

    if (!widget.enabled) {
      return content;
    }

    final transform = Matrix4.identity()
      ..setEntry(3, 2, widget.perspective)
      ..rotateX(_tiltX)
      ..rotateY(_tiltY);

    return MouseRegion(
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      child: Transform(
        alignment: Alignment.center,
        transform: transform,
        child: content,
      ),
    );
  }
}
