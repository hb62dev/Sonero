import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:coverflow_carousel/coverflow_carousel.dart';

void main() {
  group('CoverflowPageIndicator', () {
    testWidgets('renders correct number of inactive dots', (tester) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowPageIndicator(controller: controller, itemCount: 5),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
        findsNWidgets(6),
      );
    });

    testWidgets('updates on controller page change', (tester) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowPageIndicator(controller: controller, itemCount: 5),
          ),
        ),
      );

      controller.updateMetrics(rawPage: 2.0, normalizedPage: 2.0);
      await tester.pump();

      expect(find.byType(CoverflowPageIndicator), findsOneWidget);
    });

    testWidgets('calls onTap with correct index', (tester) async {
      final controller = CoverflowCarouselController();
      int? tappedIndex;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: CoverflowPageIndicator(
                controller: controller,
                itemCount: 3,
                onTap: (index) => tappedIndex = index,
              ),
            ),
          ),
        ),
      );

      // Single GestureDetector covers the whole strip; tap near the last dot.
      final indicator = find.byType(CoverflowPageIndicator);
      await tester.tapAt(tester.getCenter(indicator) + const Offset(15, 0));
      expect(tappedIndex, 2);
    });

    testWidgets('applies custom colors and sizes', (tester) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowPageIndicator(
              controller: controller,
              itemCount: 3,
              activeColor: Colors.red,
              inactiveColor: Colors.grey,
              dotSize: 12.0,
              dotSpacing: 20.0,
            ),
          ),
        ),
      );

      expect(find.byType(CoverflowPageIndicator), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration,
        ),
        findsNWidgets(4),
      );
    });

    testWidgets('returns empty box for zero items', (tester) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowPageIndicator(controller: controller, itemCount: 0),
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('handles single item gracefully', (tester) async {
      final controller = CoverflowCarouselController();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CoverflowPageIndicator(controller: controller, itemCount: 1),
          ),
        ),
      );

      expect(find.byType(GestureDetector), findsOneWidget);
    });
  });
}
