# Coverflow Carousel

[![pub package](https://img.shields.io/pub/v/coverflow_carousel.svg?label=pub.dev&color=blue&style=flat-square)](https://pub.dev/packages/coverflow_carousel)
[![likes](https://img.shields.io/pub/likes/coverflow_carousel?style=flat-square)](https://pub.dev/packages/coverflow_carousel)
[![pub points](https://img.shields.io/pub/points/coverflow_carousel?style=flat-square)](https://pub.dev/packages/coverflow_carousel)
[![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=flat-square&logo=Flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-%230175C2.svg?style=flat-square&logo=Dart&logoColor=white)](https://dart.dev)
[![license](https://img.shields.io/badge/license-BSD--3--Clause-blue?style=flat-square)](https://github.com/GalaxyPhoenix716/coverflow_carousel_package/blob/main/LICENSE)

> A beautiful, highly customizable 3D coverflow-style carousel for Flutter.
> 
> Create immersive experiences with smooth perspective effects, overlapping cards, dynamic scaling, and effortless programmatic navigation.
> 
> Perfect for music apps, movie browsers, ecommerce showcases, galleries, portfolios, and modern mobile interfaces.

---



## Features

| 🎬 Visuals & 3D Perspective | 🛠️ Customization & Builders |
| :--- | :--- |
| ![3D Coverflow](https://img.shields.io/badge/3D_Coverflow-02569B?style=flat-square)<br>**Smooth 3D Coverflow Design**<br>Immersive carousel layout with customizable 3D perspective, skew angles, and depth scaling. | ![Center Overlays](https://img.shields.io/badge/Center_Overlays-ff69b4?style=flat-square)<br>**Center Card Overlays**<br>Stack play buttons, badges, or details directly on the centered card with distance-linked fade transitions. |
| ![Layouts & Loop](https://img.shields.io/badge/Layouts_%26_Loop-blueviolet?style=flat-square)<br>**Layouts & Infinite Loop**<br>Horizontal or vertical scroll directions with properly oriented 3D transforms and seamless circular looping. | ![Adjustable Spacing](https://img.shields.io/badge/Adjustable_Spacing-009688?style=flat-square)<br>**Fully Adjustable Spacing**<br>Set custom overlap parameters, near/far card spacing, viewport fractions, and visible card counts. |
| ![Entry Animations](https://img.shields.io/badge/Entry_Animations-orange?style=flat-square)<br>**Dynamic Entry Animations**<br>Staggered fades, zoom scales, spacing expansions (horizontal fanning), sliding, and physical stacking effects. | ![Custom Dimensions](https://img.shields.io/badge/Custom_Dimensions-9c27b0?style=flat-square)<br>**Custom Dimensions**<br>Support for explicit card width and height constraints. |
| ![Depth & Shadows](https://img.shields.io/badge/Depth_%26_Shadows-db7093?style=flat-square)<br>**Depth, Shadows & Blur**<br>Real-time drop shadow calculations, customizable elevation, and blur/obscure effects for off-center cards. | ![Builder API](https://img.shields.io/badge/Builder_API-009688?style=flat-square)<br>**Builder-Based API**<br>On-demand widget creation optimizes rendering performance for large or infinite datasets. |
| **🎮 Interactions & Input** | **⚡ Performance & Controller** |
| ![3D Hover Tilt](https://img.shields.io/badge/3D_Hover_Tilt-brightgreen?style=flat-square)<br>**3D Hover & Tilt Effects**<br>Interactive pointer-tracking that tilts cards in 3D space with customizable angles and smooth deceleration. | ![External Control](https://img.shields.io/badge/External_Control-9c27b0?style=flat-square)<br>**Synchronous & Stream Controllers**<br>Programmatic navigation (`next`, `previous`, `animateTo`) paired with real-time stream/notifier scroll updates. |
| ![Mouse & Trackpad](https://img.shields.io/badge/Mouse_%26_Trackpad-db7093?style=flat-square)<br>**Mouse Wheel & Trackpad**<br>Throttled desktop scroll wheel and trackpad swipe support for smooth page transitions. | ![Desktop Optimizations](https://img.shields.io/badge/Desktop_Optimizations-lightgrey?style=flat-square)<br>**Desktop Optimizations**<br>Automatic scrollbar suppression and platform-tailored drag/scroll sensitivity controls. |
| ![Gestures & Focus](https://img.shields.io/badge/Gestures_%26_Focus-yellowgreen?style=flat-square)<br>**Gestures & Click-to-Focus**<br>Active cards support internal gestures naturally, and off-center cards auto-navigate to center when clicked. | ![Production Ready](https://img.shields.io/badge/Production_Ready-green?style=flat-square)<br>**Production Ready**<br>Optimized performance, fully tested, and zero external widget dependencies. |


## Preview

> [!NOTE]
> This is a demo of an application of this package. You can download the example app from the github repo to test all the features.

![Coverflow Carousel Demo 1](assets/coverflow_carousel_demo.gif)
![Coverflow Carousel Demo 2](assets/coverflow_carousel_demo_2.gif)

---

## Installation

Add the package to your `pubspec.yaml`.

```yaml
dependencies:
  coverflow_carousel: ^2.0.1
```

OR

Run the command in the terminal in your project root

```
flutter pub add coverflow_carousel
```

Then run:

```
flutter pub get
```

## Basic Usage

> [!IMPORTANT]
> **API Change in v2.0.0**: The `scrollDirection` parameter is now **required** (compulsory) in the `CoverflowCarousel.builder` constructor to make layout orientation explicit.

```dart
CoverflowCarousel.builder(
    itemCount: 10,
    itemWidth: 250,
    itemHeight: 320,
    scrollDirection: Axis.horizontal,
    itemBuilder: (context, index) {
        return Container(
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: Colors.blue,
            ),
        );
    },
)
```

## Controller Support

Control the carousel from anywhere in your application.

```dart
final controller = CoverflowCarouselController();
```

```dart
CoverflowCarousel.builder(
  controller: controller,
  itemCount: items.length,
  itemWidth: 250,
  itemHeight: 320,
  scrollDirection: Axis.horizontal,
  itemBuilder: (context, index) {
    return MyCard(index: index);
  },
)
```

#### Programmatic Navigation

```dart
controller.next();
controller.previous();
controller.animateTo(5);
```

#### Listen to Scroll Progress

You can listen to real-time scroll updates (for custom page indicators, ambient colors, animations, etc.) using streams or value notifiers:

```dart
// Notifiers (synchronous value updates)
controller.pageListenable.addListener(() {
  double currentPage = controller.page; // Normalized index in [0, itemCount)
});

controller.rawPageListenable.addListener(() {
  double rawPage = controller.rawPage; // Raw PageController values
});

// Broadcast Streams
controller.pageStream.listen((double normalizedPage) {
  // Triggers on every fractional scroll update
});

controller.rawPageStream.listen((double rawPage) {
  // Triggers on every raw scroll update
});
```

Make sure to call `controller.dispose()` when the controller is no longer needed to clean up stream subscriptions.

> [!TIP]
> **Performance Tip**: For lightweight, synchronous UI bindings (e.g. customized page indicators), prefer using `controller.pageListenable` or `controller.rawPageListenable` to avoid the asynchronous overhead of streams.

## Entry Animations

Make the carousel feel organic and alive when it first appears on the screen. Select from staggered fades, zoom scaling, spacing expansions, or horizontal slides.

```dart
CoverflowCarousel.builder(
  itemCount: items.length,
  itemWidth: 250,
  itemHeight: 320,
  scrollDirection: Axis.horizontal,
  entryAnimation: CoverflowEntryAnimation.stack, // Physical stacking effect fanning center-out!
  entryAnimationDuration: const Duration(milliseconds: 1000),
  entryAnimationCurve: Curves.easeOutCubic,
  itemBuilder: (context, index) {
    return MyCard(index: index);
  },
)
```

### Available Animation Types:

- `CoverflowEntryAnimation.none` (Default): Instantly mounts without animation.
- `CoverflowEntryAnimation.fadeIn`: Staggered opacity fade-in from the center outward.
- `CoverflowEntryAnimation.scaleUp`: Staggered zoom scale-up from the center outward.
- `CoverflowEntryAnimation.spacingExpand`: Cards fan out horizontally from a center stack.
- `CoverflowEntryAnimation.staggeredSlide`: Staggered slides in from left/right/top.
- `CoverflowEntryAnimation.fadeScale`: Smooth staggered zoom and fade combined.
- `CoverflowEntryAnimation.stack`: Physical stacking effect where cards scale down from the front fanning center-to-outside.

---

## Center Card Overlay

Stack custom widgets (like play buttons, badges, overlays) directly on the active centered card. Overlays automatically fade out smoothly as the card moves away from the center.

```dart
CoverflowCarousel.builder(
  itemCount: items.length,
  itemWidth: 250,
  itemHeight: 320,
  scrollDirection: Axis.horizontal,
  centerOverlayBuilder: (context, index) {
    return Positioned(
      bottom: 20,
      right: 20,
      child: FloatingActionButton(
        onPressed: () => print("Playing $index"),
        child: Icon(Icons.play_arrow),
      ),
    );
  },
  itemBuilder: (context, index) => MyCard(index: index),
)
```

## 3D Hover/Tilt Effect

Bring your carousel to life on web and desktop. The focused card tilts in 3D space tracking the user's mouse movements. When the mouse leaves, the card smoothly decelerates back to center.

Configure tilt support with:
- `enableHoverTilt`: Whether to enable 3D hover/tilt effects on the center card (defaults to `true`).
- `maxHoverTiltAngle`: The maximum rotation angle in radians (defaults to `0.15`, approximately 8.5 degrees).

## Mouse Scroll Wheel Navigation

Support scroll wheel and trackpad swipe movements to change pages. Navigation requests are automatically throttled relative to the transition animation duration to guarantee smooth transitions.

---

## Parameters

| Parameter              | Type                         | Description                                                         |
| :--------------------- | :--------------------------- | :------------------------------------------------------------------ |
| itemCount              | int                          | Number of carousel items                                            |
| itemBuilder            | IndexedWidgetBuilder         | Builds each carousel item                                           |
| itemWidth              | double                       | Width of the focused card                                           |
| itemHeight             | double                       | Height of the focused card                                          |
| scrollDirection        | Axis                         | Scroll direction (compulsory: `Axis.horizontal` or `Axis.vertical`) |
| visibleItems           | int                          | Number of visible cards on each side of focused item (default: `3`) |
| initialPage            | int                          | Initial focused page index (default: `0`)                           |
| nearCardSpacing        | double                       | Spacing for adjacent cards (default: `45`)                          |
| farCardSpacing         | double                       | Spacing for distant cards (default: `50`)                           |
| skewAngle              | double                       | Card rotation angle (default: `-0.35` for coverflow, `0.0` for classic)|
| perspective            | double                       | 3D perspective intensity (default: `0.0025`)                        |
| obscure                | double                       | Blur intensity for side cards (default: `0`)                        |
| controller             | CoverflowCarouselController? | External carousel controller                                        |
| animationDuration      | Duration                     | Navigation animation duration (default: `350ms`)                    |
| animationCurve         | Curve                        | Navigation animation curve (default: `Curves.easeOutCubic`)         |
| viewportFraction       | double                       | PageView swipe sensitivity and width ratio (default: `0.25`)        |
| isInfinite             | bool                         | Enable circular scrolling loop (default: `false`)                   |
| entryAnimation         | CoverflowEntryAnimation      | Entrance animation type (default: `.none`)                          |
| entryAnimationDuration | Duration                     | Entrance animation duration (default: `600ms`)                      |
| entryAnimationCurve    | Curve                        | Entrance animation curve (default: `Curves.easeOutCubic`)           |
| centerOverlayBuilder   | Widget Function(BuildContext, int)? | Builder for overlays stacked on the active centered card (default: `null`) |
| enableHoverTilt        | bool                         | Enable 3D hover/tilt effects on the active centered card (default: `true`) |
| maxHoverTiltAngle      | double                       | Maximum tilt angle in radians applied during mouse hover (default: `0.15`) |
| height                 | double?                      | Custom height constraint of the carousel container                  |
| width                  | double?                      | Custom width constraint of the carousel container                   |
| autoplay               | bool                         | Enable auto-advancing of cards (default: `false`)                   |
| autoplayInterval       | Duration                     | Delay between autoplay advances (default: `3s`)                    |
| autoplayPauseOnHover   | bool                         | Pause autoplay when hovered by mouse (default: `true`)              |
| enableShadow           | bool                         | Enable drop shadows on cards (default: `true`)                      |
| elevation              | double                       | Shadow elevation depth (default: `8.0`)                             |
| shadowColor            | Color                        | Color of the drop shadows (default: `Colors.black`)                 |
| cardBorderRadius       | BorderRadius                 | Border radius of the cards to clip shadow paths (default: `24.0`)    |

---

## 🎯 Perfect For

* 🎵 **Music & Audio Apps**: Album art browsers, playlist selections, and artist discographies.
* 🎬 **Streaming & Media**: Movie posters, video selections, and channel guides.
* 🛍️ **E-Commerce**: Product showcases, style catalogs, and featured collections.
* 📸 **Galleries & Portfolios**: Photography displays, creative portfolios, and image browsers.
* ✈️ **Travel Apps**: Destination highlights, hotel galleries, and trip planners.
* 🎮 **Gaming Interfaces**: Character selection screens, level selectors, and item shops.
* 📱 **Modern Mobile UI**: High-impact onboardings, splash displays, and feature lists.

---

## 💎 Why Coverflow Carousel?

Unlike traditional flat carousels, this package is designed to create a premium, dimensional user experience:

* **True 3D Perspective**: Utilizes projection matrices to skew and scale cards dynamically based on scroll distance.
* **Depth Overlap Layouts**: Overlap cards elegantly to fit more content visually while maintaining focus on the center card.
* **Liquid Transitions**: Seamless card scaling, blur offsets, drop shadows, and overlay fades animate dynamically as you scroll.
* **Zero Dependencies**: Built entirely on top of the native Flutter SDK to guarantee performance, stability, and future compatibility.

---

## 🤝 Contributing & Support

We welcome contributions, bug reports, and suggestions to make Coverflow Carousel even better!

> **🐛 Found a Bug?**
> Please open an issue on our [GitHub Issues](https://github.com/GalaxyPhoenix716/coverflow_carousel_package/issues) page and include your Flutter version, package version, steps to reproduce, and any relevant logs or screenshots.

> **💡 Have a Feature Request?**
> We'd love to hear your ideas! Open an issue describing your use case and proposed solution.

> **🛠️ Want to Contribute?**
> Pull requests are highly appreciated. Before submitting, please ensure your code follows Dart guidelines, all tests pass (`flutter test`), and static analysis is clean (`flutter analyze`).

Thank you for using Coverflow Carousel!

