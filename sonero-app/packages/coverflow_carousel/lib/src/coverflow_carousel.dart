import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'coverflow_carousel_controller.dart';
import 'coverflow_carousel_renderer.dart';

/// Defines the visual entry animations available for cards when the carousel
/// is first mounted/displayed on the screen.
enum CoverflowEntryAnimation {
  /// No entry animation. Cards appear in their standard layout immediately.
  none,

  /// Cards fade in globally.
  fadeIn,

  /// Cards scale up from 80% to 100% of their calculated sizes.
  scaleUp,

  /// Card spacing starts compacted and expands outwards to their configured spacing values.
  spacingExpand,

  /// Cards slide in from the edges: center card drops from above, left cards slide from the left,
  /// and right cards slide from the right.
  staggeredSlide,

  /// Cards fade in and scale up simultaneously.
  fadeScale,

  /// Cards are stacked sequentially from the center card outwards to the adjacent cards.
  /// Inside the sequence, each card animates in sequentially using a scale down from 1.8 to 1.0.
  stack,
}

/// Defines the layout modes available for the carousel.
enum CoverflowMode {
  /// 3D Coverflow layout where off-center cards are skewed, scaled down, and layered.
  coverflow,

  /// Flat carousel slider layout where cards slide edge-to-edge with no 3D rotation.
  classic,
}

/// A 3D Coverflow Carousel widget for Flutter.
///
/// Displays a scrollable list of cards in a 3D perspective layout where the
/// active center card is prominent, and adjacent cards are skewed, scaled down,
/// and layered beneath the center card.
///
/// Supports gesture control, mouse wheel dragging, infinite scrolling, programmatic
/// animations via controller, card-click auto-centering, and multiple staggered entry animations.
class CoverflowCarousel extends StatefulWidget {
  /// The total number of items in the carousel.
  final int itemCount;

  /// Builder callback that returns the widget representing the card at the given index.
  ///
  /// The [index] provided is mapped to a real index in `[0, itemCount - 1]`.
  final IndexedWidgetBuilder itemBuilder;

  /// The layout mode of the carousel.
  ///
  /// Defaults to [CoverflowMode.coverflow].
  final CoverflowMode mode;

  /// The number of visible cards to render on each side of the active center card.
  ///
  /// If null, resolved dynamically based on [mode]: 3 for coverflow, 1 for classic.
  final int? visibleItems;

  /// The initial card index to focus/center.
  ///
  /// Must be in the range `[0, itemCount - 1]`. Defaults to `0`.
  final int initialPage;

  /// The width of the focused center card.
  final double itemWidth;

  /// The height of the focused center card.
  final double itemHeight;

  /// Intensity of the blur effect applied to off-center cards.
  ///
  /// Set to `0` to disable the blur. Higher values increase blur. Defaults to `0`.
  final double obscure;

  /// The rotation angle (in radians) applied to off-center cards along the Y-axis.
  ///
  /// If null, resolved dynamically based on [mode]: -0.35 for coverflow, 0.0 for classic.
  final double? skewAngle;

  /// Horizontal spacing between the center card and the immediately adjacent cards (distance = 1).
  ///
  /// If null, resolved dynamically based on [mode]: 45 for coverflow, [itemWidth] for classic.
  final double? nearCardSpacing;

  /// Horizontal spacing between adjacent background cards (distance >= 2).
  ///
  /// If null, resolved dynamically based on [mode]: 50 for coverflow, [itemWidth] for classic.
  final double? farCardSpacing;

  /// Perspective factor for 3D projection, modifying the matrix entry `(3, 2)`.
  ///
  /// Defaults to `0.0025` for a realistic depth effect.
  final double perspective;

  /// Duration for card transition animations (e.g., when tapping side cards or calling controller methods).
  ///
  /// Defaults to `350` milliseconds.
  final Duration animationDuration;

  /// Easing curve for card transition animations.
  ///
  /// Defaults to [Curves.easeOutCubic].
  final Curve animationCurve;

  /// Optional controller to programmatically drive next, previous, or jump/animateTo operations.
  final CoverflowCarouselController? controller;

  /// Callback triggered whenever the active centered card index changes.
  final ValueChanged<int>? onPageChanged;

  /// Fraction of the viewport occupied by each card scroll slot.
  ///
  /// Controls drag responsiveness and scrolling speed. Defaults to `0.25` for coverflow, `0.88` for classic.
  final double? viewportFraction;

  /// Whether the carousel should wrap around infinitely at the ends.
  ///
  /// If `true`, the user can scroll infinitely in both directions. Defaults to `false`.
  final bool isInfinite;

  /// The entry animation to play when the carousel is first rendered.
  ///
  /// Defaults to [CoverflowEntryAnimation.none].
  final CoverflowEntryAnimation entryAnimation;

  /// The duration of the entry animation.
  ///
  /// Defaults to `1000` milliseconds.
  final Duration entryAnimationDuration;

  /// Easing curve applied to the entry animation.
  ///
  /// Defaults to [Curves.easeOutCubic].
  final Curve entryAnimationCurve;

  /// Optional builder that returns a widget to stack on top of the active centered card.
  ///
  /// Can be used to display play buttons, badges, controls, or overlays.
  /// Standard positioning widgets (like [Align], [Positioned], or [Center]) can be
  /// used within this builder to place the overlay anywhere on the card.
  final Widget Function(BuildContext context, int index)? centerOverlayBuilder;

  /// Whether to enable 3D hover/tilt effects on cards when hovered by a mouse.
  ///
  /// Defaults to `true`.
  final bool enableHoverTilt;

  /// The maximum tilt angle (in radians) applied during the 3D hover effect.
  ///
  /// Defaults to `0.15` (approx 8.5 degrees).
  final double maxHoverTiltAngle;

  /// Whether to enable mouse scroll wheel and trackpad scroll navigation.
  ///
  /// Defaults to `true`.
  final bool enableScrollWheel;

  /// The total height of the carousel widget container.
  ///
  /// If not specified, defaults to [itemHeight] + 80 logical pixels to provide
  /// sufficient space for 3D card perspective tilt, shadow elevations, and active card overlays.
  final double? height;

  /// The total width of the carousel widget container.
  ///
  /// If not specified, defaults to taking up all available horizontal space in horizontal mode,
  /// or [itemWidth] + 80 logical pixels in vertical mode.
  final double? width;

  /// The axis along which the carousel scrolls.
  ///
  /// Defaults to [Axis.horizontal].
  final Axis scrollDirection;

  /// Whether to enable auto-advancement of cards.
  ///
  /// Defaults to `false`.
  final bool autoplay;

  /// The duration of the interval between autoplay loops.
  ///
  /// Defaults to `3` seconds.
  final Duration autoplayInterval;

  /// Whether to pause card auto-advancements when the mouse pointer is hovering over the carousel.
  ///
  /// Defaults to `true`.
  final bool autoplayPauseOnHover;

  /// Whether to enable built-in 3D perspective shadows on cards.
  ///
  /// Defaults to `true`.
  final bool enableShadow;

  /// The color of the cast drop shadow.
  ///
  /// Defaults to [Colors.black].
  final Color shadowColor;

  /// The depth/intensity of the cast drop shadow.
  ///
  /// Controls offset and blur radius spread. Defaults to `8.0`.
  final double elevation;

  /// The border radius matching the card child's shape to crop the shadow path correctly.
  ///
  /// Defaults to `BorderRadius.circular(24)`.
  final BorderRadius cardBorderRadius;

  /// Creates a Coverflow Carousel with a builder pattern.
  const CoverflowCarousel.builder({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.itemWidth,
    required this.itemHeight,
    this.mode = CoverflowMode.coverflow,
    this.visibleItems,
    this.obscure = 0,
    this.skewAngle,
    this.initialPage = 0,
    this.onPageChanged,
    this.nearCardSpacing,
    this.farCardSpacing,
    this.perspective = 0.0025,
    this.animationDuration = const Duration(milliseconds: 350),
    this.animationCurve = Curves.easeOutCubic,
    this.controller,
    this.viewportFraction,
    this.isInfinite = false,
    this.entryAnimation = CoverflowEntryAnimation.none,
    this.entryAnimationDuration = const Duration(milliseconds: 1000),
    this.entryAnimationCurve = Curves.easeOutCubic,
    this.centerOverlayBuilder,
    this.enableHoverTilt = true,
    this.maxHoverTiltAngle = 0.15,
    this.enableScrollWheel = true,
    this.height,
    this.width,
    required this.scrollDirection,
    this.autoplay = false,
    this.autoplayInterval = const Duration(seconds: 3),
    this.autoplayPauseOnHover = true,
    this.enableShadow = true,
    this.shadowColor = Colors.black,
    this.elevation = 8.0,
    this.cardBorderRadius = const BorderRadius.all(Radius.circular(24)),
  }) : assert(
         height == null || height >= itemHeight,
         'height must be greater than or equal to itemHeight to prevent layout clipping.',
       ),
       assert(
         width == null || width >= itemWidth,
         'width must be greater than or equal to itemWidth to prevent layout clipping.',
       );

  @override
  State<CoverflowCarousel> createState() => _CoverflowCarouselState();
}

class _CoverflowCarouselState extends State<CoverflowCarousel>
    with SingleTickerProviderStateMixin {
  late PageController _controller;
  late double currentPage;
  int _lastReportedPage = -1;
  late int _initialVirtualPage;
  AnimationController? _entryController;
  Animation<double>? _entryAnimation;
  Duration? _lastScrollEventTimeStamp;
  Timer? _autoplayTimer;
  bool _isHovering = false;
  bool _isUserDragging = false;
  bool? _autoplayControllerOverride;
  bool _disposed = false;

  void _resumeAutoplay() {
    final shouldAutoplay = _autoplayControllerOverride ?? widget.autoplay;
    if (!shouldAutoplay) return;
    if (_isUserDragging) return;
    if (_isHovering && widget.autoplayPauseOnHover) return;
    if (widget.itemCount <= 1) return;

    _autoplayTimer?.cancel();
    _autoplayTimer = Timer.periodic(
      widget.autoplayInterval,
      (_) => _handleAutoplayTick(),
    );
  }

  void _pauseAutoplay() {
    _autoplayTimer?.cancel();
    _autoplayTimer = null;
  }

  void _handleAutoplayTick() {
    if (!_controller.hasClients) return;
    if (widget.itemCount <= 1) return;

    final forward = widget.controller?.autoplayForward ?? true;
    final page = _controller.page ?? 0.0;
    final targetPage = page.round() + (forward ? 1 : -1);

    if (widget.isInfinite) {
      if (forward) {
        _controller.nextPage(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      } else {
        _controller.previousPage(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      }
    } else {
      if (forward && targetPage < widget.itemCount) {
        _controller.nextPage(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      } else if (forward) {
        _controller.animateToPage(
          0,
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      } else if (targetPage >= 0) {
        _controller.previousPage(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      } else {
        _controller.animateToPage(
          widget.itemCount - 1,
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initialVirtualPage = widget.isInfinite
        ? (10000 * widget.itemCount) + widget.initialPage
        : widget.initialPage;
    currentPage = _initialVirtualPage.toDouble();
    final resolvedViewportFraction =
        widget.viewportFraction ??
        (widget.mode == CoverflowMode.classic ? 0.88 : 0.25);
    _controller = PageController(
      viewportFraction: resolvedViewportFraction,
      initialPage: _initialVirtualPage,
    );

    if (widget.entryAnimation != CoverflowEntryAnimation.none) {
      _entryController = AnimationController(
        vsync: this,
        duration: widget.entryAnimationDuration,
      );
      _entryAnimation = CurveTween(
        curve: widget.entryAnimationCurve,
      ).animate(_entryController!);
      _entryController!.forward();
    }

    _controller.addListener(_pageListener);
    _attachController();
    if (widget.autoplay) {
      _resumeAutoplay();
    }
  }

  void _pageListener() {
    if (_disposed || !mounted) return;
    final page = _controller.page ?? 0.0;

    void update() {
      if (!mounted) return;
      setState(() {
        currentPage = page;
      });

      if (widget.controller != null) {
        final realCount = widget.itemCount;
        double normalized = page;
        if (widget.isInfinite && realCount > 0) {
          normalized = page % realCount;
          if (normalized < 0) {
            normalized += realCount;
          }
        }
        widget.controller!.updateMetrics(
          rawPage: page,
          normalizedPage: normalized,
        );
      }

      final rounded = page.round();
      final realIndex = widget.isInfinite && widget.itemCount > 0
          ? ((rounded % widget.itemCount) + widget.itemCount) % widget.itemCount
          : rounded;

      if (realIndex != _lastReportedPage) {
        _lastReportedPage = realIndex;
        widget.onPageChanged?.call(realIndex);
      }
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => update());
    } else {
      update();
    }
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final double delta;
      if (widget.scrollDirection == Axis.vertical) {
        delta = event.scrollDelta.dy;
      } else {
        delta = event.scrollDelta.dy != 0
            ? event.scrollDelta.dy
            : event.scrollDelta.dx;
      }
      if (delta.abs() < 1) return;

      if (!_controller.hasClients) return;

      final now = event.timeStamp;
      final throttleDuration =
          widget.animationDuration - const Duration(milliseconds: 50);
      if (_lastScrollEventTimeStamp != null &&
          (now - _lastScrollEventTimeStamp!) < throttleDuration) {
        return;
      }

      if (delta > 0) {
        if (widget.isInfinite || _controller.page! < widget.itemCount - 1) {
          _controller.nextPage(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
          );
          _lastScrollEventTimeStamp = now;
        }
      } else if (delta < 0) {
        if (widget.isInfinite || _controller.page! > 0) {
          _controller.previousPage(
            duration: widget.animationDuration,
            curve: widget.animationCurve,
          );
          _lastScrollEventTimeStamp = now;
        }
      }
    }
  }

  @override
  void didUpdateWidget(covariant CoverflowCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.detach();
      _attachController();
    }

    final oldResolvedViewportFraction =
        oldWidget.viewportFraction ??
        (oldWidget.mode == CoverflowMode.classic ? 0.88 : 0.25);
    final resolvedViewportFraction =
        widget.viewportFraction ??
        (widget.mode == CoverflowMode.classic ? 0.88 : 0.25);

    if (oldResolvedViewportFraction != resolvedViewportFraction ||
        oldWidget.isInfinite != widget.isInfinite ||
        oldWidget.scrollDirection != widget.scrollDirection) {
      final double currentRawPage = _controller.positions.isNotEmpty
          ? _controller.page ?? widget.initialPage.toDouble()
          : widget.initialPage.toDouble();
      final int nextPageIndex;

      if (oldWidget.isInfinite != widget.isInfinite) {
        if (widget.isInfinite) {
          final int currentRealIndex = widget.itemCount > 0
              ? ((currentRawPage.round() % widget.itemCount) +
                        widget.itemCount) %
                    widget.itemCount
              : 0;
          nextPageIndex = (10000 * widget.itemCount) + currentRealIndex;
        } else {
          nextPageIndex = widget.itemCount > 0
              ? ((currentRawPage.round() % widget.itemCount) +
                        widget.itemCount) %
                    widget.itemCount
              : 0;
        }
      } else {
        nextPageIndex = currentRawPage.round();
      }

      _controller.removeListener(_pageListener);
      _controller.dispose();
      _controller = PageController(
        viewportFraction: resolvedViewportFraction,
        initialPage: nextPageIndex,
      );
      currentPage = nextPageIndex.toDouble();
      _controller.addListener(_pageListener);
      _attachController();
    }

    if (oldWidget.autoplay != widget.autoplay ||
        oldWidget.autoplayInterval != widget.autoplayInterval) {
      if (_autoplayControllerOverride ?? widget.autoplay) {
        _resumeAutoplay();
      } else {
        _pauseAutoplay();
      }
    }
  }

  void _updateControllerMetrics() {
    if (widget.controller == null) return;
    final page = _controller.hasClients
        ? (_controller.page ?? _initialVirtualPage.toDouble())
        : _initialVirtualPage.toDouble();
    final realCount = widget.itemCount;
    double normalized = page;
    if (widget.isInfinite && realCount > 0) {
      normalized = page % realCount;
      if (normalized < 0) {
        normalized += realCount;
      }
    }
    widget.controller!.updateMetrics(rawPage: page, normalizedPage: normalized);
  }

  void _attachController() {
    widget.controller?.attach(
      next: () {
        if (!_controller.hasClients) return;
        _controller.nextPage(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      },
      previous: () {
        if (!_controller.hasClients) return;
        _controller.previousPage(
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      },
      animateTo: (index) {
        if (!_controller.hasClients) return;
        final targetPage = widget.isInfinite
            ? _getNearestVirtualPage(index, currentPage, widget.itemCount)
            : index;
        _controller.animateToPage(
          targetPage,
          duration: widget.animationDuration,
          curve: widget.animationCurve,
        );
      },
      jumpTo: (index) {
        if (!_controller.hasClients) return;
        final targetPage = widget.isInfinite
            ? _getNearestVirtualPage(index, currentPage, widget.itemCount)
            : index;
        _controller.jumpToPage(targetPage);
      },
      startAutoplay: () {
        _autoplayControllerOverride = true;
        _resumeAutoplay();
      },
      stopAutoplay: () {
        _autoplayControllerOverride = false;
        _pauseAutoplay();
      },
    );
    _updateControllerMetrics();
  }

  int _getNearestVirtualPage(
    int targetRealIndex,
    double currentVirtualPage,
    int itemCount,
  ) {
    if (itemCount <= 0) return 0;
    final int currentVirtualRound = currentVirtualPage.round();
    final int currentRealIndex =
        ((currentVirtualRound % itemCount) + itemCount) % itemCount;
    int diff = targetRealIndex - currentRealIndex;
    if (diff > itemCount / 2) {
      diff -= itemCount;
    } else if (diff < -itemCount / 2) {
      diff += itemCount;
    }
    return currentVirtualRound + diff;
  }

  @override
  void dispose() {
    _disposed = true;
    _autoplayTimer?.cancel();
    widget.controller?.detach();
    _controller.dispose();
    _entryController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedVisibleItems =
        widget.visibleItems ?? (widget.mode == CoverflowMode.classic ? 1 : 3);
    final resolvedSkewAngle =
        widget.skewAngle ??
        (widget.mode == CoverflowMode.classic ? 0.0 : -0.35);
    final resolvedNearCardSpacing =
        widget.nearCardSpacing ??
        (widget.mode == CoverflowMode.classic
            ? (widget.scrollDirection == Axis.horizontal
                  ? widget.itemWidth
                  : widget.itemHeight)
            : 45.0);
    final resolvedFarCardSpacing =
        widget.farCardSpacing ??
        (widget.mode == CoverflowMode.classic
            ? (widget.scrollDirection == Axis.horizontal
                  ? widget.itemWidth
                  : widget.itemHeight)
            : 50.0);

    final double? containerWidth = widget.scrollDirection == Axis.horizontal
        ? widget.width
        : (widget.width ?? widget.itemWidth + 80);
    final double? containerHeight = widget.scrollDirection == Axis.vertical
        ? widget.height
        : (widget.height ?? widget.itemHeight + 80);

    final Widget carouselContent = SizedBox(
      key: const Key('coverflow-container'),
      width: containerWidth,
      height: containerHeight,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (ScrollNotification notification) {
              if (notification is ScrollStartNotification) {
                _isUserDragging = true;
                _pauseAutoplay();
              } else if (notification is ScrollEndNotification) {
                _isUserDragging = false;
                _resumeAutoplay();
              }
              return false;
            },
            child: PageView.builder(
              scrollDirection: widget.scrollDirection,
              controller: _controller,
              itemCount: widget.isInfinite ? null : widget.itemCount,
              scrollBehavior: const _CoverflowScrollBehavior(),
              itemBuilder: (context, index) {
                return const SizedBox.shrink();
              },
            ),
          ),

          if (widget.entryAnimation == CoverflowEntryAnimation.none)
            _CoverflowGesturePassThrough(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return CoverflowCarouselRenderer(
                    controller: _controller,
                    centerIndex: currentPage,
                    maxWidth: constraints.maxWidth,
                    maxHeight: constraints.maxHeight,
                    scrollDirection: widget.scrollDirection,
                    itemWidth: widget.itemWidth,
                    itemHeight: widget.itemHeight,
                    itemCount: widget.itemCount,
                    visibleItems: resolvedVisibleItems,
                    itemBuilder: widget.itemBuilder,
                    obscure: widget.obscure,
                    skewAngle: resolvedSkewAngle,
                    nearCardSpacing: resolvedNearCardSpacing,
                    farCardSpacing: resolvedFarCardSpacing,
                    perspective: widget.perspective,
                    animationDuration: widget.animationDuration,
                    animationCurve: widget.animationCurve,
                    isInfinite: widget.isInfinite,
                    entryAnimation: CoverflowEntryAnimation.none,
                    entryProgress: 1.0,
                    initialPage: _initialVirtualPage,
                    centerOverlayBuilder: widget.centerOverlayBuilder,
                    enableHoverTilt: widget.enableHoverTilt,
                    maxHoverTiltAngle: widget.maxHoverTiltAngle,
                    enableShadow: widget.enableShadow,
                    shadowColor: widget.shadowColor,
                    elevation: widget.elevation,
                    cardBorderRadius: widget.cardBorderRadius,
                  );
                },
              ),
            )
          else
            AnimatedBuilder(
              animation: _entryAnimation!,
              builder: (context, child) {
                return _CoverflowGesturePassThrough(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return CoverflowCarouselRenderer(
                        controller: _controller,
                        centerIndex: currentPage,
                        maxWidth: constraints.maxWidth,
                        maxHeight: constraints.maxHeight,
                        scrollDirection: widget.scrollDirection,
                        itemWidth: widget.itemWidth,
                        itemHeight: widget.itemHeight,
                        itemCount: widget.itemCount,
                        visibleItems: resolvedVisibleItems,
                        itemBuilder: widget.itemBuilder,
                        obscure: widget.obscure,
                        skewAngle: resolvedSkewAngle,
                        nearCardSpacing: resolvedNearCardSpacing,
                        farCardSpacing: resolvedFarCardSpacing,
                        perspective: widget.perspective,
                        animationDuration: widget.animationDuration,
                        animationCurve: widget.animationCurve,
                        isInfinite: widget.isInfinite,
                        entryAnimation: widget.entryAnimation,
                        entryProgress: _entryAnimation!.value,
                        initialPage: _initialVirtualPage,
                        centerOverlayBuilder: widget.centerOverlayBuilder,
                        enableHoverTilt: widget.enableHoverTilt,
                        maxHoverTiltAngle: widget.maxHoverTiltAngle,
                        enableShadow: widget.enableShadow,
                        shadowColor: widget.shadowColor,
                        elevation: widget.elevation,
                        cardBorderRadius: widget.cardBorderRadius,
                      );
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );

    Widget result = carouselContent;

    if (widget.enableScrollWheel) {
      result = Listener(onPointerSignal: _handlePointerSignal, child: result);
    }

    if (widget.autoplay && widget.autoplayPauseOnHover) {
      result = MouseRegion(
        onEnter: (_) {
          _isHovering = true;
          _pauseAutoplay();
        },
        onExit: (_) {
          _isHovering = false;
          _resumeAutoplay();
        },
        child: result,
      );
    }

    return result;
  }
}

class _CoverflowScrollBehavior extends ScrollBehavior {
  const _CoverflowScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Custom render object widget that intercepts gestures but allows them to fall through
/// to stack layers underneath.
///
/// Hit-tests children and registers them in the gesture system (allowing buttons and
/// taps to work), but returns false on hit-testing so sibling overlay widgets (like
/// the underlying swiping PageView) can still receive drag events.
class _CoverflowGesturePassThrough extends SingleChildRenderObjectWidget {
  const _CoverflowGesturePassThrough({required Widget child})
    : super(child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderCoverflowGesturePassThrough();
  }
}

class _RenderCoverflowGesturePassThrough extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    hitTestChildren(result, position: position);
    return false;
  }
}
