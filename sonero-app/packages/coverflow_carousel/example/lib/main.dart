import 'package:flutter/material.dart';
import 'package:coverflow_carousel/coverflow_carousel.dart';
import 'dart:ui';

void main() {
  runApp(const CoverflowCarouselExampleApp());
}

class CoverflowCarouselExampleApp extends StatelessWidget {
  const CoverflowCarouselExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Coverflow Carousel Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.transparent,
        fontFamily: 'Roboto',
      ),
      home: const CoverflowDemoScreen(),
    );
  }
}

class CoverflowDemoScreen extends StatefulWidget {
  const CoverflowDemoScreen({super.key});

  @override
  State<CoverflowDemoScreen> createState() => _CoverflowDemoScreenState();
}

class _CoverflowDemoScreenState extends State<CoverflowDemoScreen> {
  final CoverflowCarouselController _controller = CoverflowCarouselController();

  // Carousel Configurations
  CoverflowMode _mode = CoverflowMode.coverflow;
  bool _isInfinite = true;
  double _obscure = 0.4;
  double _viewportFraction = 0.28;
  CoverflowEntryAnimation _entryAnimation = CoverflowEntryAnimation.stack;
  int _activePage = 0;
  bool _enableHoverTilt = true;
  double _maxHoverTiltAngle = 0.15;
  bool _enableScrollWheel = true;
  bool _useCustomHeight = false;
  double _carouselHeight = 360.0;
  bool _autoplay = false;
  double _autoplayIntervalSeconds = 3.0;
  bool _autoplayDirectionForward = true;
  bool _enableShadow = true;
  double _shadowElevation = 8.0;
  double _cardCornerRadiusValue = 24.0;

  // Page indicator settings
  double _indicatorDotSize = 8.0;
  double _indicatorDotSpacing = 12.0;
  bool _indicatorUseThemeColor = true;

  Axis _scrollDirection = Axis.horizontal;
  bool _useCustomWidth = false;
  double _carouselWidth = 340.0;

  // Active configuration categories for the control panel tabs
  int _configTab = 0; // 0: Layout, 1: Motion & Interactivity, 2: VFX & Shadows

  // Re-keying widget to easily trigger entry animation reload
  Key _carouselKey = UniqueKey();

  // Demo card colors & content
  final List<Map<String, dynamic>> _demoCards = [
    {
      'title': 'Nebula Voyage',
      'subtitle': 'Explore cosmic horizons',
      'colors': [const Color(0xFF6A11CB), const Color(0xFF2575FC)],
      'icon': Icons.rocket_launch,
    },
    {
      'title': 'Oceanic Abyss',
      'subtitle': 'Deep sea discoveries',
      'colors': [const Color(0xFF00c6ff), const Color(0xFF0072ff)],
      'icon': Icons.sailing,
    },
    {
      'title': 'Sunset Dunes',
      'subtitle': 'Warm desert winds',
      'colors': [const Color(0xFFf12711), const Color(0xFFf5af19)],
      'icon': Icons.wb_sunny,
    },
    {
      'title': 'Forest Oasis',
      'subtitle': 'Ancient whispering woods',
      'colors': [const Color(0xFF11998e), const Color(0xFF38ef7d)],
      'icon': Icons.forest,
    },
    {
      'title': 'Aurora Sky',
      'subtitle': 'Northern lights dance',
      'colors': [const Color(0xFF833ab4), const Color(0xFFfd1d1d)],
      'icon': Icons.ac_unit,
    },
  ];

  void _reloadCarousel() {
    setState(() {
      _carouselKey = UniqueKey();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          'COVERFLOW CAROUSEL',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            letterSpacing: 2.0,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: _AmbientBackdrop(
        pageListenable: _controller.pageListenable,
        demoCards: _demoCards,
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // 1. The Coverflow Carousel Container
                  SizedBox(
                    width: _useCustomWidth ? _carouselWidth : null,
                    height: _useCustomHeight ? _carouselHeight : 380,
                    child: Center(
                      child: CoverflowCarousel.builder(
                        key: _carouselKey,
                        controller: _controller,
                        itemCount: _demoCards.length,
                        itemWidth: 260,
                        itemHeight: 280,
                        width: _useCustomWidth ? _carouselWidth : null,
                        height: _useCustomHeight ? _carouselHeight : null,
                        scrollDirection: _scrollDirection,
                        mode: _mode,
                        isInfinite: _isInfinite,
                        obscure: _obscure,
                        viewportFraction: _viewportFraction,
                        entryAnimation: _entryAnimation,
                        entryAnimationDuration: const Duration(
                          milliseconds: 1000,
                        ),
                        entryAnimationCurve: Curves.easeOutBack,
                        enableHoverTilt: _enableHoverTilt,
                        maxHoverTiltAngle: _maxHoverTiltAngle,
                        enableScrollWheel: _enableScrollWheel,
                        autoplay: _autoplay,
                        autoplayInterval: Duration(
                          milliseconds: (_autoplayIntervalSeconds * 1000)
                              .toInt(),
                        ),
                        enableShadow: _enableShadow,
                        elevation: _shadowElevation,
                        cardBorderRadius: BorderRadius.circular(
                          _cardCornerRadiusValue,
                        ),
                        onPageChanged: (index) {
                          setState(() {
                            _activePage = index;
                          });
                        },
                        centerOverlayBuilder: (context, index) {
                          return Positioned(
                            right: 130 - 28 - 8,
                            bottom: -30,
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: _PremiumPlayButton(
                                title: _demoCards[index]['title'] as String,
                              ),
                            ),
                          );
                        },
                        itemBuilder: (context, index) {
                          final card = _demoCards[index];
                          return Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(
                                _cardCornerRadiusValue,
                              ),
                              gradient: LinearGradient(
                                colors: card['colors'] as List<Color>,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: (card['colors'][0] as Color)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 15,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                _cardCornerRadiusValue,
                              ),
                              child: Stack(
                                children: [
                                  // Glassmorphic top glow overlay
                                  Positioned(
                                    top: -50,
                                    left: -50,
                                    child: Container(
                                      width: 150,
                                      height: 150,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withValues(
                                          alpha: 0.15,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      alignment: Alignment.bottomLeft,
                                      child: SizedBox(
                                        width:
                                            220, // itemWidth 260 minus horizontal padding 40
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.end,
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(
                                                  alpha: 0.15,
                                                ),
                                                shape: BoxShape.circle,
                                              ),
                                              child: Icon(
                                                card['icon'],
                                                size: 28,
                                                color: Colors.white,
                                              ),
                                            ),
                                            const SizedBox(height: 24),
                                            Text(
                                              card['title'] as String,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              card['subtitle'],
                                              style: TextStyle(
                                                color: Colors.white.withValues(
                                                  alpha: 0.8,
                                                ),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                          ],
                                        ),
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
                  ),

                  const SizedBox(height: 24),

                  // Dynamic Liquid Page Indicator
                  CoverflowPageIndicator(
                    controller: _controller,
                    itemCount: _demoCards.length,
                    activeColor: _indicatorUseThemeColor
                        ? Colors.pinkAccent
                        : Colors.white,
                    dotSize: _indicatorDotSize,
                    dotSpacing: _indicatorDotSpacing,
                    onTap: (index) {
                      _controller.animateTo(index);
                    },
                  ),

                  const SizedBox(height: 20),

                  // Programmatic Actions Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _CompactIconButton(
                        icon: Icons.arrow_back_rounded,
                        onPressed: () => _controller.previous(),
                      ),
                      const SizedBox(width: 24),
                      Text(
                        'INDEX ${_activePage + 1} / ${_demoCards.length}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 24),
                      _CompactIconButton(
                        icon: Icons.arrow_forward_rounded,
                        onPressed: () => _controller.next(),
                      ),
                    ],
                  ),

                  const SizedBox(height: 28),

                  // Glassmorphic Settings Card Panel
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.08),
                        width: 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(24),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
                        child: Material(
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Category Headers Tabs
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    _TabHeader(
                                      title: 'LAYOUT',
                                      isActive: _configTab == 0,
                                      onTap: () =>
                                          setState(() => _configTab = 0),
                                    ),
                                    _TabHeader(
                                      title: 'MOTION',
                                      isActive: _configTab == 1,
                                      onTap: () =>
                                          setState(() => _configTab = 1),
                                    ),
                                    _TabHeader(
                                      title: 'EFFECTS',
                                      isActive: _configTab == 2,
                                      onTap: () =>
                                          setState(() => _configTab = 2),
                                    ),
                                  ],
                                ),
                                const Divider(
                                  height: 32,
                                  color: Colors.white24,
                                ),

                                if (_configTab == 0) ...[
                                  // Tab 0: Layout settings
                                  _GlassDropdown<CoverflowMode>(
                                    title: 'Carousel Preset Mode',
                                    value: _mode,
                                    items: CoverflowMode.values,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _mode = val;
                                          _viewportFraction =
                                              val == CoverflowMode.classic
                                              ? 0.88
                                              : 0.28;
                                        });
                                      }
                                    },
                                    labelBuilder: (m) =>
                                        m == CoverflowMode.coverflow
                                        ? '3D Coverflow'
                                        : 'Classic Slider',
                                  ),
                                  _GlassDropdown<Axis>(
                                    title: 'Scroll Direction',
                                    value: _scrollDirection,
                                    items: Axis.values,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _scrollDirection = val);
                                      }
                                    },
                                    labelBuilder: (a) => a == Axis.horizontal
                                        ? 'Horizontal'
                                        : 'Vertical',
                                  ),
                                  _GlassSwitch(
                                    title: 'Custom Width Constraints',
                                    value: _useCustomWidth,
                                    onChanged: (val) =>
                                        setState(() => _useCustomWidth = val),
                                  ),
                                  if (_useCustomWidth)
                                    _GlassSlider(
                                      title: 'Carousel Width',
                                      value: _carouselWidth,
                                      min: 280.0,
                                      max: 450.0,
                                      onChanged: (val) =>
                                          setState(() => _carouselWidth = val),
                                      suffix: 'px',
                                    ),
                                  _GlassSlider(
                                    title:
                                        'Viewport Fraction (Card Scale / Swipe Area)',
                                    value: _viewportFraction,
                                    min: 0.15,
                                    max: 1.0,
                                    divisions: 85,
                                    onChanged: (val) =>
                                        setState(() => _viewportFraction = val),
                                  ),
                                  _GlassSwitch(
                                    title: 'Custom Height Constraints',
                                    value: _useCustomHeight,
                                    onChanged: (val) =>
                                        setState(() => _useCustomHeight = val),
                                  ),
                                  if (_useCustomHeight)
                                    _GlassSlider(
                                      title: 'Carousel Height',
                                      value: _carouselHeight,
                                      min: 280.0,
                                      max: 450.0,
                                      onChanged: (val) =>
                                          setState(() => _carouselHeight = val),
                                      suffix: 'px',
                                    ),
                                  _GlassSlider(
                                    title: 'Card Border Radius',
                                    value: _cardCornerRadiusValue,
                                    min: 0.0,
                                    max: 40.0,
                                    onChanged: (val) => setState(
                                      () => _cardCornerRadiusValue = val,
                                    ),
                                    suffix: 'px',
                                  ),
                                  const Divider(
                                    height: 32,
                                    color: Colors.white24,
                                  ),
                                  _GlassSlider(
                                    title: 'Indicator Dot Size',
                                    value: _indicatorDotSize,
                                    min: 4.0,
                                    max: 16.0,
                                    onChanged: (val) =>
                                        setState(() => _indicatorDotSize = val),
                                    suffix: 'px',
                                  ),
                                  _GlassSlider(
                                    title: 'Indicator Dot Spacing',
                                    value: _indicatorDotSpacing,
                                    min: 4.0,
                                    max: 24.0,
                                    onChanged: (val) => setState(
                                      () => _indicatorDotSpacing = val,
                                    ),
                                    suffix: 'px',
                                  ),
                                  _GlassSwitch(
                                    title: 'Theme-colored Active Dot',
                                    value: _indicatorUseThemeColor,
                                    onChanged: (val) => setState(
                                      () => _indicatorUseThemeColor = val,
                                    ),
                                  ),
                                ] else if (_configTab == 1) ...[
                                  // Tab 1: Motion settings
                                  _GlassSwitch(
                                    title: 'Infinite Scroll Looping',
                                    value: _isInfinite,
                                    onChanged: (val) =>
                                        setState(() => _isInfinite = val),
                                  ),
                                  _GlassSwitch(
                                    title: 'Autoplay (Auto Advance)',
                                    value: _autoplay,
                                    onChanged: (val) =>
                                        setState(() => _autoplay = val),
                                  ),
                                  if (_autoplay) ...[
                                    _GlassSlider(
                                      title: 'Autoplay Speed (Interval)',
                                      value: _autoplayIntervalSeconds,
                                      min: 1.0,
                                      max: 8.0,
                                      divisions: 70,
                                      onChanged: (val) => setState(
                                        () => _autoplayIntervalSeconds = val,
                                      ),
                                      suffix: 's',
                                    ),
                                    _GlassSwitch(
                                      title: 'Autoplay Direction',
                                      value: _autoplayDirectionForward,
                                      onChanged: (val) {
                                        setState(
                                          () => _autoplayDirectionForward = val,
                                        );
                                        _controller.setAutoplayDirection(val);
                                      },
                                    ),
                                  ],
                                  _GlassSwitch(
                                    title: 'Mouse Scroll Wheel Navigation',
                                    value: _enableScrollWheel,
                                    onChanged: (val) => setState(
                                      () => _enableScrollWheel = val,
                                    ),
                                  ),
                                  const Divider(
                                    height: 20,
                                    color: Colors.white12,
                                  ),
                                  _ProgrammaticAutoplayControls(
                                    controller: _controller,
                                  ),
                                  const Divider(
                                    height: 20,
                                    color: Colors.white12,
                                  ),
                                  _GlassDropdown<int>(
                                    title: 'Jump to Page',
                                    value: _activePage,
                                    items: List.generate(
                                      _demoCards.length,
                                      (i) => i,
                                    ),
                                    onChanged: (val) {
                                      if (val != null) _controller.jumpTo(val);
                                    },
                                    labelBuilder: (i) => 'Card #$i',
                                  ),
                                ] else ...[
                                  // Tab 2: VFX settings
                                  _GlassDropdown<CoverflowEntryAnimation>(
                                    title: 'Entry Intro Animation',
                                    value: _entryAnimation,
                                    items: CoverflowEntryAnimation.values,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _entryAnimation = val);
                                        _reloadCarousel();
                                      }
                                    },
                                    labelBuilder: (a) => a.name,
                                  ),
                                  _GlassSlider(
                                    title: 'Obscure Blur (Background Cards)',
                                    value: _obscure,
                                    min: 0.0,
                                    max: 1.0,
                                    divisions: 10,
                                    onChanged: (val) =>
                                        setState(() => _obscure = val),
                                  ),
                                  _GlassSwitch(
                                    title: '3D Elevation Shadows',
                                    value: _enableShadow,
                                    onChanged: (val) =>
                                        setState(() => _enableShadow = val),
                                  ),
                                  if (_enableShadow)
                                    _GlassSlider(
                                      title: 'Shadow Depth (Elevation)',
                                      value: _shadowElevation,
                                      min: 0.0,
                                      max: 20.0,
                                      onChanged: (val) => setState(
                                        () => _shadowElevation = val,
                                      ),
                                    ),
                                  _GlassSwitch(
                                    title: '3D Pointer Hover Tilt',
                                    value: _enableHoverTilt,
                                    onChanged: (val) =>
                                        setState(() => _enableHoverTilt = val),
                                  ),
                                  if (_enableHoverTilt)
                                    _GlassSlider(
                                      title: 'Max Hover Tilt Angle',
                                      value: _maxHoverTiltAngle,
                                      min: 0.05,
                                      max: 0.35,
                                      onChanged: (val) => setState(
                                        () => _maxHoverTiltAngle = val,
                                      ),
                                      suffix: ' rad',
                                    ),
                                ],

                                const SizedBox(height: 24),
                                Center(
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: _reloadCarousel,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                        vertical: 12,
                                      ),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [
                                            Colors.pinkAccent,
                                            Colors.purpleAccent,
                                          ],
                                        ),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.refresh,
                                            color: Colors.white,
                                            size: 18,
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            'Trigger Entry Animation',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dynamic background that listens to page updates and interpolates gradient colors
class _AmbientBackdrop extends StatelessWidget {
  final ValueNotifier<double> pageListenable;
  final List<Map<String, dynamic>> demoCards;
  final Widget child;

  const _AmbientBackdrop({
    required this.pageListenable,
    required this.demoCards,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: pageListenable,
      builder: (context, page, _) {
        final len = demoCards.length;
        if (len == 0) return child;

        // Extract floating bounds
        final int indexA = page.floor() % len;
        final int indexB = (indexA + 1) % len;
        final double t = page - page.floor();

        final Color colorAA = demoCards[indexA]['colors'][0];
        final Color colorAB = demoCards[indexA]['colors'][1];
        final Color colorBA = demoCards[indexB]['colors'][0];
        final Color colorBB = demoCards[indexB]['colors'][1];

        final Color colorA = Color.lerp(colorAA, colorBA, t) ?? colorAA;
        final Color colorB = Color.lerp(colorAB, colorBB, t) ?? colorAB;

        return Stack(
          children: [
            // Dark solid canvas
            Positioned.fill(child: Container(color: const Color(0xFF060509))),
            // Top ambient gradient glow
            Positioned(
              top: -200,
              left: -150,
              width: 650,
              height: 650,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorA.withValues(alpha: 0.18),
                      colorA.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // Bottom ambient gradient glow
            Positioned(
              bottom: -200,
              right: -150,
              width: 650,
              height: 650,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      colorB.withValues(alpha: 0.15),
                      colorB.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            // The content
            Positioned.fill(child: child),
          ],
        );
      },
    );
  }
}

/// Row of buttons for programmatic autoplay control via the controller.
class _ProgrammaticAutoplayControls extends StatefulWidget {
  final CoverflowCarouselController controller;

  const _ProgrammaticAutoplayControls({required this.controller});

  @override
  State<_ProgrammaticAutoplayControls> createState() =>
      _ProgrammaticAutoplayControlsState();
}

class _ProgrammaticAutoplayControlsState
    extends State<_ProgrammaticAutoplayControls> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Controller Autoplay Override',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _running
                    ? null
                    : () {
                        widget.controller.startAutoplay();
                        setState(() => _running = true);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: _running
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.greenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _running
                          ? Colors.white12
                          : Colors.greenAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Start',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _running ? Colors.white38 : Colors.greenAccent,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: !_running
                    ? null
                    : () {
                        widget.controller.stopAutoplay();
                        setState(() => _running = false);
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: !_running
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: !_running
                          ? Colors.white12
                          : Colors.redAccent.withValues(alpha: 0.3),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Stop',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: !_running ? Colors.white38 : Colors.redAccent,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Premium Play Button with dynamic scale on press
class _PremiumPlayButton extends StatefulWidget {
  final String title;

  const _PremiumPlayButton({required this.title});

  @override
  State<_PremiumPlayButton> createState() => _PremiumPlayButtonState();
}

class _PremiumPlayButtonState extends State<_PremiumPlayButton> {
  double _scale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _scale = 0.9),
      onTapUp: (_) {
        setState(() => _scale = 1.0);
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF1E1C29),
            content: Text(
              'Playing "${widget.title}"...',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      },
      onTapCancel: () => setState(() => _scale = 1.0),
      child: Transform.scale(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.pinkAccent, Color(0xFFFD5E53)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.pinkAccent.withValues(alpha: 0.4),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }
}

class _CompactIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _CompactIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.06),
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(icon, color: Colors.white70, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}

class _TabHeader extends StatelessWidget {
  final String title;
  final bool isActive;
  final VoidCallback onTap;

  const _TabHeader({
    required this.title,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
                color: isActive ? Colors.pinkAccent : Colors.white54,
              ),
            ),
            const SizedBox(height: 4),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isActive ? 16 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: Colors.pinkAccent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassSwitch extends StatelessWidget {
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _GlassSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(
          title,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        value: value,
        activeThumbColor: Colors.pinkAccent,
        inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
        onChanged: onChanged,
      ),
    );
  }
}

class _GlassSlider extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String suffix;

  const _GlassSlider({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    this.suffix = '',
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
              Text(
                '${value.toStringAsFixed(2)}$suffix',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.pinkAccent,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Colors.pinkAccent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.1),
              thumbColor: Colors.white,
              overlayColor: Colors.pinkAccent.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _GlassDropdown<T> extends StatelessWidget {
  final String title;
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;
  final String Function(T) labelBuilder;

  const _GlassDropdown({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.labelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            ),
            child: DropdownButton<T>(
              value: value,
              underline: const SizedBox(),
              dropdownColor: const Color(0xFF1E1C29),
              borderRadius: BorderRadius.circular(14),
              onChanged: onChanged,
              items: items.map((item) {
                return DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelBuilder(item),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
