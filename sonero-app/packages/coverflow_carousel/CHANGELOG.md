## 2.1.0

1. Added customizable page indicators
2. Extended controller support for autoplay

## 2.0.1

1. Beautified readme

## 2.0.0

1. **Vertical Scroll Direction**: Added full support for vertical scrolling layouts (`Axis.vertical`) with vertical-only 3D skew rotation along the X-axis and dynamic vertical spacing controls.
2. **Synchronized Overlay Translation**: Overlays now translate smoothly vertically from down to up (`30.0 * distance`) as they fade in, with automated alignment adjustments to eliminate cross-axis diagonal drift during card scaling transitions.
3. **Compulsory scrollDirection Parameter**: Marked the `scrollDirection` constructor parameter as `required` in `CoverflowCarousel.builder` to improve layout explicitness (breaking API change).
4. **Scroll Progress Streams & Notifiers**: Exposed broadcast streams (`pageStream` and `rawPageStream`) and value notifiers (`pageListenable` and `rawPageListenable`) on `CoverflowCarouselController` to listen to fractional and raw scroll progress.
5. **Robust Test Suite**: Refactored the widget test suite to prevent event loop hangs using synchronous notifiers, and verified vertical layout coordinates, overlay translation, and key preservation.

## 1.3.0

1. **Optimized Card Blur**: Replaced expensive `BackdropFilter` layout stacking with direct, offscreen hardware-accelerated `ImageFiltered` composition, eliminating GPU framebuffer readbacks and frame drops.
2. **Customizable Height Constraints**: Added `height` configuration to the carousel with developer safety assertions preventing layout overflows.
3. **Scroll Wheel Toggle**: Exposed `enableScrollWheel` to enable or disable mouse scroll wheel navigation to prevent vertical web scroll trapping.
4. **UX-Polished Autoplay Support**: Integrated `autoplay`, `autoplayInterval`, and `autoplayPauseOnHover` background loops with scroll-linked pause/resume controls (pauses on pointer drag and mouse hover).
5. **Skew-Aware 3D Elevation Shadows**: Added unified shadow parameters (`enableShadow`, `shadowColor`, `elevation`, and `cardBorderRadius`) drawing layered, soft double shadows. Background cards cast static skew-aligned shadows, and the centered card dynamically shifts its shadow offset simulating a shifting light source.
6. **Center Overlay Tilt Integration & Size Constraints**: Nested overlay stack elements inside the 3D hover region to tilt badges and play buttons in synchronization with the card surface, while explicitly setting `fit: StackFit.expand` on stack layers to preserve correct card dimensions.
7. **Buttery-Smooth Hover Interpolation**: Transitioned hover tilt updates to a frame-rate independent `Ticker`-based smooth lerp at 15% per frame with auto-sleeping when idle.
8. **Customizable Carousel Mode**: Added the `mode` parameter supporting `CoverflowMode.coverflow` (3D stacked) and `CoverflowMode.classic` (flat edge-to-edge carousel slider) presets with dynamic parameter resolutions (visible items, skew, spacing, and viewport fraction).

## 1.2.1

1. **Smooth Scroll**: The scroll is now smoother.
2. **New Demos**: Added new demos.

## 1.2.0

1. **Center Card Overlay**: Added `centerOverlayBuilder` to `CoverflowCarousel.builder` allowing custom overlay widgets (such as play buttons, badges, or tags) to be stacked on the active centered card.
2. **Smooth Fade Transition**: The center overlay automatically fades in and out smoothly using a scroll-linked opacity calculation based on the card's distance from the center.
3. **Flexible Positioning**: Developers can use standard Flutter alignment and layout widgets (`Align`, `Positioned`, `Center`) inside the overlay builder to place the widget anywhere on the card.
4. **Interactive Overlays**: Overlay widgets on the active centered card are fully interactive and support pointer events (like button taps/onPressed), while off-center cards redirect taps to focus the card.
5. **3D Hover/Tilt Effect**: Added support for interactive 3D perspective tilting of the active centered card as the mouse pointer hovers over it. Includes configuration properties `enableHoverTilt` and `maxHoverTiltAngle`.
6. **Mouse Scroll Wheel Navigation**: Added support for mouse scroll wheel and trackpad scroll navigation to scroll to the next and previous cards.
7. **Throttled Scroll Events**: Throttled consecutive scroll signals relative to the animation duration to prevent rapid card skipping and ensure smooth transitions.
8. **Performance Optimizations**:
   - Confined hover calculations and rebuilds locally to the centered card, preventing parent repaints.
   - Wrapped tilted card children in a `RepaintBoundary` to leverage GPU matrix transformations and prevent expensive rasterization repaints.
   - Fixed the resetting tilt animation to utilize linear interpolation from cached start offsets, preventing compounding timer decay.
9. **Robust Testing**: Expanded package and example tests to cover mouse wheel navigation, scroll throttling, and 3D hover gestures.

## 1.1.2

1. Fixed swiping on mobile applications.

## 1.1.1

1. **Example Application**: Added a complete, interactive, and beautifully styled example application under `example/` demonstrating infinite scroll, entry animations, blur obscuring, and programmatic controllers.

## 1.1.0

1. **Infinite Scroll**: Added `isInfinite` support for seamless circular scrolling and shortest-path programmatic animations.
2. **Entry Animations**: Added `entryAnimation` parameter supporting staggered fades, zooms, spacing expansions, slides, and front-stacking (`fadeIn`, `scaleUp`, `spacingExpand`, `staggeredSlide`, `fadeScale`, and `stack`).
3. **Card Interactivity**: Side-cards now support click-to-focus, and centered cards are fully interactive (clicks pass to inner buttons without interference).
4. **Web & Desktop Dragging**: Enabled mouse click-and-drag swiping on Web and Desktop.
5. **Scrollbar Suppression**: Disabled the native scrollbar from drawing behind cards.
6. **Custom Viewport Fraction**: Added `viewportFraction` property supporting dynamic hot updates.
7. **Optimized BackdropFilter**: Blur filters are only drawn when active, improving GPU rendering.
8. **Testing**: Built a full suite of 10 widget tests verifying layouts, gestures, entry transitions, and controllers.
9. **Code Documentation**: Added 100% pub.dev public API coverage with detailed Dart doc comments (`///`) on all classes, properties, constructors, methods, and enums.
10. **Architecture & Mathematics Reference**: Added `package_documentation.md` containing detailed 3D transform projection matrices, spacing equations, gesture layers, and timeline stagger formulas.
11. **Lint Fixes**: Resolved unnecessary library name lint warnings in export declarations.

## 1.0.1

1. Fixed README demo GIF link.

## 1.0.0

1. Smooth 3D coverflow-style carousel.
2. Customizable card dimensions.
3. Adjustable overlap and spacing.
4. Perspective and rotation effects.
5. Smooth swipe navigation.
6. Controller support.
7. Programmatic navigation.
8. Blur effects for non-focused cards.
9. Responsive layout.
10. Optimized rendering for large datasets.
11. Builder-based API.