import 'package:flutter/material.dart';

class HoverScale extends StatefulWidget {
  final Widget child;
  final double scale;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTapUp;

  const HoverScale({
    super.key,
    required this.child,
    this.scale = 1.05,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTapUp,
  });

  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix4.identity();
    if (_isPressed) {
      matrix.scale(0.98, 0.98);
    } else if (_isHovered) {
      matrix.scale(widget.scale, widget.scale);
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.onTap != null || widget.onSecondaryTapUp != null 
          ? SystemMouseCursors.click 
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onSecondaryTapUp: widget.onSecondaryTapUp != null 
            ? (details) => widget.onSecondaryTapUp!() 
            : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          transform: matrix,
          transformAlignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}
