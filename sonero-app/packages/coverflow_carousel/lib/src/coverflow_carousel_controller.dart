import 'package:flutter/material.dart';
import 'dart:async';

/// A controller used to programmatically control a [CoverflowCarousel].
///
/// Pass an instance of [CoverflowCarouselController] to [CoverflowCarousel.builder]
/// to trigger scroll animations programmatically (e.g., jumping/animating to a page,
/// transitioning to the next or previous card) and listen to real-time scroll progress.
///
/// Also exposes autoplay controls — [startAutoplay], [stopAutoplay], and
/// [setAutoplayDirection] — plus instant [jumpTo] navigation without animation.
///
/// Remember to call [dispose] when discarding the controller to clean up stream subscriptions.
class CoverflowCarouselController {
  void Function()? _next;
  void Function()? _previous;
  void Function(int)? _animateTo;
  void Function(int)? _jumpTo;
  void Function()? _startAutoplay;
  void Function()? _stopAutoplay;

  final ValueNotifier<double> _pageNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<double> _rawPageNotifier = ValueNotifier<double>(0.0);

  final StreamController<double> _pageStreamController =
      StreamController<double>.broadcast();
  final StreamController<double> _rawPageStreamController =
      StreamController<double>.broadcast();

  bool _autoplayForward = true;

  /// A [ValueNotifier] that emits the current normalized fractional page index.
  ///
  /// If the carousel is infinite, this value is normalized to the range `[0, itemCount)`
  /// and wraps around smoothly.
  ValueNotifier<double> get pageListenable => _pageNotifier;

  /// A [ValueNotifier] that emits the raw fractional page index from the underlying scroll controller.
  ValueNotifier<double> get rawPageListenable => _rawPageNotifier;

  /// The current normalized fractional page index.
  double get page => _pageNotifier.value;

  /// The current raw fractional page index.
  double get rawPage => _rawPageNotifier.value;

  /// A broadcast stream emitting the current normalized fractional page index on every scroll update.
  Stream<double> get pageStream => _pageStreamController.stream;

  /// A broadcast stream emitting the current raw fractional page index on every scroll update.
  Stream<double> get rawPageStream => _rawPageStreamController.stream;

  /// Whether autoplay is currently moving forward (`true`) or backward (`false`).
  ///
  /// Defaults to `true`. Use [setAutoplayDirection] to change at runtime.
  bool get autoplayForward => _autoplayForward;

  /// Programmatically transitions the carousel to the next card.
  ///
  /// Uses the default animation duration and curve specified on the carousel.
  void next() => _next?.call();

  /// Programmatically transitions the carousel to the previous card.
  ///
  /// Uses the default animation duration and curve specified on the carousel.
  void previous() => _previous?.call();

  /// Programmatically animates the carousel to the card at the specified index.
  ///
  /// On infinite carousels, this automatically finds the shortest distance
  /// (shortest-path animation) to transition to the target [index].
  void animateTo(int index) => _animateTo?.call(index);

  /// Instantly jumps to the card at [index] with no slide animation.
  ///
  /// On infinite carousels this picks the nearest virtual page, so the
  /// carousel wraps around the shortest way.
  void jumpTo(int index) => _jumpTo?.call(index);

  /// Forces autoplay to start, even if the carousel widget was created
  /// with `autoplay: false`.
  void startAutoplay() => _startAutoplay?.call();

  /// Stops autoplay entirely. The carousel will not auto-advance until
  /// [startAutoplay] is called again or the widget's `autoplay` property
  /// is `true`.
  void stopAutoplay() => _stopAutoplay?.call();

  /// Sets the autoplay scroll direction.
  ///
  /// Pass `true` for forward (next card), `false` for backward (previous card).
  /// The change takes effect on the next autoplay tick.
  void setAutoplayDirection(bool forward) {
    _autoplayForward = forward;
  }

  /// Attaches the controller to a [CoverflowCarousel] state.
  ///
  /// Called internally by the carousel state; do not call this method directly.
  void attach({
    required VoidCallback next,
    required VoidCallback previous,
    required ValueChanged<int> animateTo,
    void Function(int)? jumpTo,
    VoidCallback? startAutoplay,
    VoidCallback? stopAutoplay,
  }) {
    _next = next;
    _previous = previous;
    _animateTo = animateTo;
    _jumpTo = jumpTo;
    _startAutoplay = startAutoplay;
    _stopAutoplay = stopAutoplay;
  }

  /// Detaches the controller from the carousel.
  ///
  /// Called internally when the carousel is disposed or updated; do not call this
  /// method directly.
  void detach() {
    _next = null;
    _previous = null;
    _animateTo = null;
    _jumpTo = null;
    _startAutoplay = null;
    _stopAutoplay = null;
  }

  /// Updates the internal metrics of the controller.
  ///
  /// Called internally by the carousel state; do not call this method directly.
  void updateMetrics({
    required double rawPage,
    required double normalizedPage,
  }) {
    if (_rawPageNotifier.value != rawPage) {
      _rawPageNotifier.value = rawPage;
      if (!_rawPageStreamController.isClosed) {
        _rawPageStreamController.add(rawPage);
      }
    }
    if (_pageNotifier.value != normalizedPage) {
      _pageNotifier.value = normalizedPage;
      if (!_pageStreamController.isClosed) {
        _pageStreamController.add(normalizedPage);
      }
    }
  }

  /// Disposes the controller, closing all broadcast streams and page value notifiers.
  ///
  /// Developers must call this method when the controller is no longer needed to prevent memory leaks.
  void dispose() {
    _pageStreamController.close();
    _rawPageStreamController.close();
    _pageNotifier.dispose();
    _rawPageNotifier.dispose();
  }
}
