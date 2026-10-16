import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coverflow_carousel/coverflow_carousel.dart';
import 'package:coverflow_carousel_example/main.dart';

void main() {
  testWidgets(
    'Example app runs, hovers, and scrolls with mouse wheel without errors',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(500 * 3.0, 800 * 3.0);
      tester.view.devicePixelRatio = 3.0;

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(const CoverflowCarouselExampleApp());
      await tester.pumpAndSettle();

      // Verify Nebula Voyage (index 0) is initial focused index
      expect(find.text('Nebula Voyage'), findsOneWidget);
      expect(find.text('INDEX 1 / 5'), findsOneWidget);

      // 1. Test Mouse Scroll Wheel navigation
      final Offset carouselCenter = tester.getCenter(
        find.byType(CoverflowCarousel),
      );

      final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
      pointer.hover(carouselCenter);

      // Scroll down/next (positive dy)
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 100)));
      await tester.pumpAndSettle();

      // The focused index should now be 1 (Oceanic Abyss)
      expect(find.text('INDEX 2 / 5'), findsOneWidget);
      expect(find.text('Oceanic Abyss'), findsOneWidget);

      // Wait for scroll throttle cooldown to expire
      await tester.pump(const Duration(milliseconds: 100));

      // Scroll up/prev (negative dy)
      await tester.sendEventToBinding(
        pointer.scroll(
          const Offset(0, -100),
          timeStamp: const Duration(milliseconds: 500),
        ),
      );
      await tester.pumpAndSettle();

      // The focused index should be back to 0
      expect(find.text('INDEX 1 / 5'), findsOneWidget);

      // 2. Test Hover Tilt
      final Offset cardOffset = tester.getCenter(find.text('Nebula Voyage'));
      await tester.sendEventToBinding(
        pointer.hover(cardOffset + const Offset(50, -50)),
      );
      await tester.pump();

      // Re-exit hover
      await tester.sendEventToBinding(pointer.hover(const Offset(0, 0)));
      await tester.pumpAndSettle();
    },
  );
}
