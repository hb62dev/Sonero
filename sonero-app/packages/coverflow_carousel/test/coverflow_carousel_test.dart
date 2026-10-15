import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/gestures.dart';
import 'package:coverflow_carousel/coverflow_carousel.dart';
import 'package:coverflow_carousel/src/coverflow_carousel_renderer.dart';

void main() {
  testWidgets('CoverflowCarousel renders correctly with basic parameters', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 5,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            itemBuilder: (context, index) {
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    // Verify initial state (visible cards should show up, default visibleItems is 3)
    expect(find.text('Item 0'), findsOneWidget);
    expect(find.text('Item 1'), findsOneWidget);
    expect(find.text('Item 2'), findsOneWidget);
    // Item 4 should not be visible (too far away)
    expect(find.text('Item 4'), findsNothing);
  });

  testWidgets(
    'CoverflowCarousel custom viewportFraction is passed to PageController',
    (WidgetTester tester) async {
      const customViewportFraction = 0.4;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              viewportFraction: customViewportFraction,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.viewportFraction, customViewportFraction);
    },
  );

  testWidgets('Tapping on a side card animates to it', (
    WidgetTester tester,
  ) async {
    int pageChangedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 5,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            nearCardSpacing: 250,
            farCardSpacing: 250,
            initialPage: 0,
            onPageChanged: (index) {
              pageChangedIndex = index;
            },
            itemBuilder: (context, index) {
              return KeyedSubtree(
                key: Key('card-$index'),
                child: Text('Item $index'),
              );
            },
          ),
        ),
      ),
    );

    // Tap on Item 1 (side card)
    await tester.tap(find.byKey(const Key('card-1')), warnIfMissed: false);
    await tester.pumpAndSettle();

    // The page should have changed to 1
    expect(pageChangedIndex, 1);
  });

  testWidgets('Tapping on focused card child elements works', (
    WidgetTester tester,
  ) async {
    bool buttonPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 3,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            initialPage: 0,
            itemBuilder: (context, index) {
              if (index == 0) {
                return ElevatedButton(
                  key: const Key('btn-0'),
                  onPressed: () {
                    buttonPressed = true;
                  },
                  child: const Text('Button'),
                );
              }
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    // Tap the button inside the focused card (Item 0)
    await tester.tap(find.byKey(const Key('btn-0')));
    await tester.pump();

    expect(buttonPressed, isTrue);
  });

  testWidgets('CoverflowCarouselController next/previous/animateTo works', (
    WidgetTester tester,
  ) async {
    final controller = CoverflowCarouselController();
    int pageChangedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            controller: controller,
            itemCount: 5,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            initialPage: 0,
            onPageChanged: (index) {
              pageChangedIndex = index;
            },
            itemBuilder: (context, index) {
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    // Go to next page
    controller.next();
    await tester.pumpAndSettle();
    expect(pageChangedIndex, 1);

    // Go to next page again
    controller.next();
    await tester.pumpAndSettle();
    expect(pageChangedIndex, 2);

    // Go back to previous page
    controller.previous();
    await tester.pumpAndSettle();
    expect(pageChangedIndex, 1);

    // Animate to page 3
    controller.animateTo(3);
    await tester.pumpAndSettle();
    expect(pageChangedIndex, 3);
  });

  testWidgets(
    'Tapping on a side card with internal gestures animates it to center instead of triggering inner gesture',
    (WidgetTester tester) async {
      int pageChangedIndex = -1;
      bool innerTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              nearCardSpacing: 250,
              farCardSpacing: 250,
              initialPage: 0,
              onPageChanged: (index) {
                pageChangedIndex = index;
              },
              itemBuilder: (context, index) {
                return GestureDetector(
                  key: Key('card-$index'),
                  onTap: () {
                    innerTapped = true;
                  },
                  child: Text('Item $index'),
                );
              },
            ),
          ),
        ),
      );

      // Tap on Item 1 (side card) which has an internal onTap handler
      await tester.tap(find.byKey(const Key('card-1')), warnIfMissed: false);
      await tester.pumpAndSettle();

      // The page should have changed to 1, but the inner tap handler should NOT have fired
      expect(pageChangedIndex, 1);
      expect(innerTapped, isFalse);

      // Now that Item 1 is centered, tap it again
      await tester.tap(find.byKey(const Key('card-1')));
      await tester.pump();

      // Now the inner tap handler should have fired!
      expect(innerTapped, isTrue);
    },
  );

  testWidgets(
    'CoverflowCarousel infinite scroll starts at high page and maps indices',
    (WidgetTester tester) async {
      int pageChangedIndex = -1;
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              controller: controller,
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              isInfinite: true,
              initialPage: 0,
              onPageChanged: (index) {
                pageChangedIndex = index;
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      // PageView controller should be initialized at a high page number (10000 * 5 = 50000)
      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.initialPage, 50000);

      // Let's call controller.next() to verify it goes to 1
      controller.next();
      await tester.pumpAndSettle();
      expect(pageChangedIndex, 1);

      // Let's call controller.previous() twice to go to index 4
      controller.previous();
      await tester.pumpAndSettle();
      controller.previous();
      await tester.pumpAndSettle();
      expect(pageChangedIndex, 4);
      expect(pageView.controller!.page, 49999.0);
    },
  );

  testWidgets(
    'CoverflowCarouselController animateTo selects shortest path on infinite scroll',
    (WidgetTester tester) async {
      final controller = CoverflowCarouselController();
      int pageChangedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              controller: controller,
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              isInfinite: true,
              initialPage: 0,
              onPageChanged: (index) {
                pageChangedIndex = index;
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.page, 50000.0);

      // Animate to index 4. The nearest virtual page is 49999 (1 page back) instead of 50004 (4 pages forward).
      controller.animateTo(4);
      await tester.pumpAndSettle();

      expect(pageView.controller!.page, 49999.0);
      expect(pageChangedIndex, 4);

      // Animate to index 1. Nearest virtual page from 49999 is 50001 (2 pages forward) instead of 49996 (3 pages back).
      controller.animateTo(1);
      await tester.pumpAndSettle();

      expect(pageView.controller!.page, 50001.0);
      expect(pageChangedIndex, 1);
    },
  );

  testWidgets(
    'CoverflowCarousel infinite scroll does not throw RangeError when accessing lists in itemBuilder',
    (WidgetTester tester) async {
      final list = ['A', 'B', 'C', 'D', 'E']; // Length 5

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: list.length,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              isInfinite: true,
              initialPage: 0,
              itemBuilder: (context, index) {
                // This would throw RangeError if index was virtual (e.g. 5000) instead of mapped (0-4)
                return Text(list[index]);
              },
            ),
          ),
        ),
      );

      // Verify it renders successfully and we can see items
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
    },
  );

  testWidgets(
    'CoverflowCarousel entry animations build successfully and progress',
    (WidgetTester tester) async {
      for (final animation in CoverflowEntryAnimation.values) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoverflowCarousel.builder(
                key: UniqueKey(),
                itemCount: 5,
                itemWidth: 200,
                itemHeight: 300,
                scrollDirection: Axis.horizontal,
                entryAnimation: animation,
                entryAnimationDuration: const Duration(milliseconds: 100),
                itemBuilder: (context, index) {
                  return Text('Item $index');
                },
              ),
            ),
          ),
        );

        // Verify the widget tree builds correctly for this animation
        expect(find.text('Item 0'), findsOneWidget);

        // Let the entry animation complete
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets(
    'CoverflowCarousel renders custom centerOverlayBuilder and handles clicks',
    (WidgetTester tester) async {
      int overlayTappedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              centerOverlayBuilder: (context, index) {
                return ElevatedButton(
                  key: Key('overlay-$index'),
                  onPressed: () {
                    overlayTappedIndex = index;
                  },
                  child: Text('Play $index'),
                );
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      // Centered card (index 0) overlay should exist and be clickable
      expect(find.byKey(const Key('overlay-0')), findsOneWidget);
      await tester.tap(find.byKey(const Key('overlay-0')));
      await tester.pump();
      expect(overlayTappedIndex, 0);

      // Background card (index 1) overlay should not be built since overlayOpacity is 0.0
      expect(find.byKey(const Key('overlay-1')), findsNothing);
    },
  );

  testWidgets(
    'CoverflowCarousel supports direct Positioned return in centerOverlayBuilder',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              centerOverlayBuilder: (context, index) {
                return Positioned(
                  top: 25,
                  left: 35,
                  width: 50,
                  height: 50,
                  child: Container(
                    key: const Key('positioned-overlay'),
                    color: Colors.red,
                  ),
                );
              },
              itemBuilder: (context, index) {
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );

      // Positioned child should exist
      final containerFinder = find.byKey(const Key('positioned-overlay'));
      expect(containerFinder, findsOneWidget);

      // Verify its size is exactly 50x50 (it does not expand to the full 200x300 card)
      final size = tester.getSize(containerFinder);
      expect(size.width, 50.0);
      expect(size.height, 50.0);
    },
  );

  testWidgets('CoverflowCarousel handles mouse scroll wheel correctly', (
    WidgetTester tester,
  ) async {
    int pageChangedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 5,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            initialPage: 0,
            onPageChanged: (index) {
              pageChangedIndex = index;
            },
            itemBuilder: (context, index) {
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    // Initial index is 0
    expect(find.text('Item 0'), findsOneWidget);

    final carouselCenter = tester.getCenter(find.byType(CoverflowCarousel));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    pointer.hover(carouselCenter);

    // Send PointerScrollEvent for scrolling forward (dy > 0)
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
    await tester.pumpAndSettle();

    // Verify it changed to page 1
    expect(pageChangedIndex, 1);

    // Wait for cooldown throttle (350ms - 50ms = 300ms)
    await tester.pump(const Duration(milliseconds: 310));

    // Send PointerScrollEvent for scrolling backward (dy < 0)
    await tester.sendEventToBinding(
      pointer.scroll(
        const Offset(0, -100),
        timeStamp: const Duration(milliseconds: 500),
      ),
    );
    await tester.pumpAndSettle();

    // Verify it changed back to 0
    expect(pageChangedIndex, 0);
  });

  testWidgets('CoverflowCarousel supports 3D Hover Tilt', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 3,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            initialPage: 0,
            enableHoverTilt: true,
            maxHoverTiltAngle: 0.2,
            itemBuilder: (context, index) {
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    final itemCenter = tester.getCenter(find.text('Item 0'));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);

    // Enter and hover offset on active item
    await tester.sendEventToBinding(
      pointer.hover(itemCenter + const Offset(50, -50)),
    );
    await tester.pump();

    // Exit hover
    await tester.sendEventToBinding(pointer.hover(const Offset(0, 0)));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'CoverflowCarousel scroll wheel can be disabled via enableScrollWheel',
    (WidgetTester tester) async {
      int pageChangedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              enableScrollWheel: false,
              onPageChanged: (index) {
                pageChangedIndex = index;
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      expect(find.text('Item 0'), findsOneWidget);

      final carouselCenter = tester.getCenter(find.byType(CoverflowCarousel));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(carouselCenter);

      // Send PointerScrollEvent for scrolling forward
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await tester.pumpAndSettle();

      // Verify it did NOT change to page 1 because scroll wheel was disabled
      expect(pageChangedIndex, -1);
    },
  );

  testWidgets('CoverflowCarousel custom height constraint is applied', (
    WidgetTester tester,
  ) async {
    const double customHeight = 420.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 3,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            height: customHeight,
            itemBuilder: (context, index) {
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    // Verify the container SizedBox has the custom height
    final containerFinder = find.byKey(const Key('coverflow-container'));
    expect(containerFinder, findsOneWidget);

    final double height = tester.getSize(containerFinder).height;
    expect(height, customHeight);
  });

  testWidgets('CoverflowCarousel autoplay advances pages automatically', (
    WidgetTester tester,
  ) async {
    int pageChangedIndex = -1;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverflowCarousel.builder(
            itemCount: 3,
            itemWidth: 200,
            itemHeight: 300,
            scrollDirection: Axis.horizontal,
            initialPage: 0,
            autoplay: true,
            autoplayInterval: const Duration(seconds: 1),
            onPageChanged: (index) {
              pageChangedIndex = index;
            },
            itemBuilder: (context, index) {
              return Text('Item $index');
            },
          ),
        ),
      ),
    );

    // Initial page is 0
    expect(find.text('Item 0'), findsOneWidget);

    // Pump for 1 second (interval) + some settle frames
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify it transitioned to page 1
    expect(pageChangedIndex, 1);

    // Pump for another 1 second
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify it transitioned to page 2
    expect(pageChangedIndex, 2);
  });

  testWidgets(
    'CoverflowCarousel autoplay loops back to 0 on non-infinite scroll',
    (WidgetTester tester) async {
      int pageChangedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 2, // Start at last page
              autoplay: true,
              autoplayInterval: const Duration(seconds: 1),
              onPageChanged: (index) {
                pageChangedIndex = index;
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      // Verify we are at page 2
      expect(find.text('Item 2'), findsOneWidget);

      // Pump for 1 second to trigger autoplay tick
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Verify it looped back to index 0
      expect(pageChangedIndex, 0);
    },
  );

  testWidgets(
    'CoverflowCarousel autoplay pauses on hover and resumes on exit',
    (WidgetTester tester) async {
      int pageChangedIndex = -1;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              autoplay: true,
              autoplayInterval: const Duration(seconds: 1),
              autoplayPauseOnHover: true,
              onPageChanged: (index) {
                pageChangedIndex = index;
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      // Initial page is 0
      expect(find.text('Item 0'), findsOneWidget);

      // Hover over the carousel container
      final carouselCenter = tester.getCenter(find.byType(CoverflowCarousel));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(carouselCenter));
      await tester.pump();

      // Pump for 1.5 seconds (longer than autoplayInterval)
      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      // Verify it did NOT transition because of hover pause
      expect(pageChangedIndex, -1);

      // Move mouse out to exit hover
      await tester.sendEventToBinding(pointer.hover(const Offset(9999, 9999)));
      await tester.pumpAndSettle();

      // Pump for 1 second + settle frames
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      // Verify it now transitioned to page 1
      expect(pageChangedIndex, 1);
    },
  );

  testWidgets(
    'CoverflowCarousel 3D elevation shadows render and shift offset on hover',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              enableShadow: true,
              elevation: 10.0,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      // Find the container drawing the shadows on the centered card
      final hoverTiltFinder = find.byWidgetPredicate(
        (widget) =>
            widget.runtimeType.toString() == '_CoverflowHoverTilt' &&
            (widget as dynamic).enabled == true,
      );
      expect(hoverTiltFinder, findsOneWidget);

      final containerFinder = find
          .descendant(
            of: hoverTiltFinder,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Container &&
                  widget.decoration is BoxDecoration &&
                  (widget.decoration as BoxDecoration).boxShadow != null,
            ),
          )
          .first;
      expect(containerFinder, findsOneWidget);

      final containerWidget = tester.widget<Container>(containerFinder);
      final decoration = containerWidget.decoration as BoxDecoration;
      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow!.length, 2); // 2 layered shadows

      // Capture initial shadow offset
      final initialOffset1 = decoration.boxShadow![0].offset;

      // Simulate mouse hover using TestPointer
      final itemCenter = tester.getCenter(find.text('Item 0'));
      final pointer = TestPointer(1, PointerDeviceKind.mouse);

      // Hover offset on active item
      await tester.sendEventToBinding(
        pointer.hover(itemCenter + const Offset(50, -50)),
      );
      await tester.pump();

      // Verify shadow offset shifted dynamically
      final updatedContainerWidget = tester.widget<Container>(containerFinder);
      final updatedDecoration =
          updatedContainerWidget.decoration as BoxDecoration;
      final updatedOffset1 = updatedDecoration.boxShadow![0].offset;

      expect(updatedOffset1, isNot(initialOffset1));

      // Exit hover
      await tester.sendEventToBinding(pointer.hover(const Offset(0, 0)));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'CoverflowCarousel resolves classic mode defaults and custom overrides correctly',
    (WidgetTester tester) async {
      // 1. Check classic presets
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              mode: CoverflowMode.classic,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      final renderer = tester.widget<CoverflowCarouselRenderer>(
        find.byType(CoverflowCarouselRenderer),
      );
      expect(renderer.visibleItems, 1);
      expect(renderer.skewAngle, 0.0);
      expect(renderer.nearCardSpacing, 200.0); // equal to itemWidth
      expect(renderer.farCardSpacing, 200.0);

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.controller!.viewportFraction, 0.88);

      // 2. Check custom overrides on classic mode
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              mode: CoverflowMode.classic,
              visibleItems: 2,
              skewAngle: -0.1,
              nearCardSpacing: 100,
              viewportFraction: 0.75,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      final overriddenRenderer = tester.widget<CoverflowCarouselRenderer>(
        find.byType(CoverflowCarouselRenderer),
      );
      expect(overriddenRenderer.visibleItems, 2);
      expect(overriddenRenderer.skewAngle, -0.1);
      expect(overriddenRenderer.nearCardSpacing, 100.0);
      expect(
        overriddenRenderer.farCardSpacing,
        200.0,
      ); // defaults to itemWidth because not overridden

      final overriddenPageView = tester.widget<PageView>(find.byType(PageView));
      expect(overriddenPageView.controller!.viewportFraction, 0.75);
    },
  );

  testWidgets(
    'CoverflowCarouselController emits normalized and raw progress updates',
    (WidgetTester tester) async {
      final controller = CoverflowCarouselController();
      final List<double> normalizedValues = [];
      final List<double> rawValues = [];

      void onNormalizedChange() {
        normalizedValues.add(controller.page);
      }

      void onRawChange() {
        rawValues.add(controller.rawPage);
      }

      controller.pageListenable.addListener(onNormalizedChange);
      controller.rawPageListenable.addListener(onRawChange);

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CoverflowCarousel.builder(
                itemCount: 5,
                itemWidth: 200,
                itemHeight: 300,
                scrollDirection: Axis.horizontal,
                isInfinite: false,
                controller: controller,
                initialPage: 0,
                itemBuilder: (context, index) {
                  return Text('Item $index');
                },
              ),
            ),
          ),
        );

        expect(controller.page, 0.0);
        expect(controller.rawPage, 0.0);

        controller.animateTo(1);
        await tester.pumpAndSettle();

        expect(controller.page, 1.0);
        expect(controller.rawPage, 1.0);

        expect(normalizedValues, contains(1.0));
        expect(rawValues, contains(1.0));
      } finally {
        controller.pageListenable.removeListener(onNormalizedChange);
        controller.rawPageListenable.removeListener(onRawChange);
        controller.dispose();
      }
    },
  );

  testWidgets(
    'CoverflowCarousel resolves classic mode defaults and custom overrides correctly in vertical direction',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              initialPage: 0,
              mode: CoverflowMode.classic,
              scrollDirection: Axis.vertical,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      final renderer = tester.widget<CoverflowCarouselRenderer>(
        find.byType(CoverflowCarouselRenderer),
      );
      expect(renderer.visibleItems, 1);
      expect(renderer.skewAngle, 0.0);
      expect(
        renderer.nearCardSpacing,
        300.0,
      ); // equal to itemHeight in vertical mode
      expect(renderer.farCardSpacing, 300.0);

      final pageView = tester.widget<PageView>(find.byType(PageView));
      expect(pageView.scrollDirection, Axis.vertical);
      expect(pageView.controller!.viewportFraction, 0.88);
    },
  );

  testWidgets(
    'CoverflowCarouselRenderer calculates coordinates correctly in vertical scroll direction',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              initialPage: 0,
              scrollDirection: Axis.vertical,
              itemBuilder: (context, index) {
                return KeyedSubtree(
                  key: Key('card-$index'),
                  child: Text('Item $index'),
                );
              },
            ),
          ),
        ),
      );

      final card0Finder = find
          .ancestor(
            of: find.byKey(const Key('card-0')),
            matching: find.byType(Positioned),
          )
          .first;

      final Positioned cardPositioned = tester.widget<Positioned>(card0Finder);
      expect(cardPositioned.left, isNotNull);
      expect(cardPositioned.top, isNotNull);
    },
  );

  testWidgets(
    'CoverflowCarouselRenderer applies vertical overlay translation',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              itemCount: 3,
              itemWidth: 200,
              itemHeight: 300,
              initialPage: 0,
              scrollDirection: Axis.vertical,
              centerOverlayBuilder: (context, index) {
                return Positioned(
                  key: const Key('overlay-widget'),
                  left: 10,
                  bottom: 10,
                  child: Text('Overlay $index'),
                );
              },
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      final overlayFinder = find.byKey(const Key('overlay-widget'));
      expect(overlayFinder, findsOneWidget);

      final transformFinder = find.descendant(
        of: overlayFinder,
        matching: find.byType(Transform),
      );
      expect(transformFinder, findsOneWidget);
    },
  );

  test('Controller stream test', () async {
    final controller = CoverflowCarouselController();
    final List<double> values = [];
    final sub = controller.pageStream.listen((val) {
      values.add(val);
    });
    controller.updateMetrics(rawPage: 1.0, normalizedPage: 1.0);
    await Future.delayed(Duration.zero);
    expect(values, contains(1.0));
    await sub.cancel();
    controller.dispose();
  });

  group('CoverflowCarouselController jumpTo', () {
    testWidgets('jumpTo changes page instantly without animation', (
      WidgetTester tester,
    ) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              controller: controller,
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 0,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      expect(controller.page, 0.0);

      controller.jumpTo(2);
      await tester.pump();

      expect(controller.page, 2.0);
    });

    testWidgets('jumpTo works on infinite carousel', (
      WidgetTester tester,
    ) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              controller: controller,
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              isInfinite: true,
              initialPage: 0,
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      controller.jumpTo(4);
      await tester.pump();

      expect(controller.page, 4.0);
    });

    test('jumpTo does nothing before attach', () {
      final controller = CoverflowCarouselController();
      expect(() => controller.jumpTo(2), returnsNormally);
    });
  });

  group('CoverflowCarouselController autoplay controls', () {
    testWidgets('startAutoplay and stopAutoplay work', (
      WidgetTester tester,
    ) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              controller: controller,
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              autoplay: false,
              onPageChanged: (_) {},
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      expect(controller.page, 0.0);

      controller.startAutoplay();
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));

      expect(controller.page, 1.0);

      controller.stopAutoplay();
      final pageAfterStop = controller.page;

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));

      expect(controller.page, pageAfterStop);
    });

    test('methods do nothing before attach', () {
      final controller = CoverflowCarouselController();
      expect(() => controller.startAutoplay(), returnsNormally);
      expect(() => controller.stopAutoplay(), returnsNormally);
    });
  });

  group('CoverflowCarouselController autoplay direction', () {
    testWidgets('setAutoplayDirection changes tick direction', (
      WidgetTester tester,
    ) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowCarousel.builder(
              controller: controller,
              itemCount: 5,
              itemWidth: 200,
              itemHeight: 300,
              scrollDirection: Axis.horizontal,
              initialPage: 2,
              autoplay: true,
              onPageChanged: (_) {},
              itemBuilder: (context, index) {
                return Text('Item $index');
              },
            ),
          ),
        ),
      );

      expect(controller.page, 2.0);

      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.page, 3.0);

      controller.setAutoplayDirection(false);
      await tester.pump(const Duration(seconds: 4));
      await tester.pump(const Duration(milliseconds: 500));
      expect(controller.page, 2.0);
    });

    test('default direction is forward', () {
      final controller = CoverflowCarouselController();
      expect(controller.autoplayForward, isTrue);
    });

    test('setAutoplayDirection updates autoplayForward', () {
      final controller = CoverflowCarouselController();
      controller.setAutoplayDirection(false);
      expect(controller.autoplayForward, isFalse);
      controller.setAutoplayDirection(true);
      expect(controller.autoplayForward, isTrue);
    });
  });
}
