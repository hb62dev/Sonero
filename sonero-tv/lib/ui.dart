import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';

/// Sonero's palette, matching the desktop app.
class SoneroColors {
  static const bg = Color(0xFF0F0F12);
  static const surface = Color(0xFF1A1A1F);
  static const surfaceAlt = Color(0xFF232329);
  static const border = Color(0xFF2E2E36);
  static const text = Color(0xFFF4F4F6);
  static const muted = Color(0xFF9A9AA6);
  static const accent = Color(0xFF7C4DFF);
  static const error = Color(0xFFFF5C6C);
}

ThemeData soneroTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: SoneroColors.accent,
      brightness: Brightness.dark,
      surface: SoneroColors.bg,
    ),
    scaffoldBackgroundColor: SoneroColors.bg,
    // TV text is read from ~3 m away: everything a step larger than on a phone
    textTheme: Typography.whiteMountainView.apply(
      bodyColor: SoneroColors.text,
      displayColor: SoneroColors.text,
    ),
  );
  return base.copyWith(
    focusColor: SoneroColors.accent.withValues(alpha: 0.25),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: SoneroColors.accent),
  );
}

/// Remote-control keys that should "press" the focused element. Most TV
/// remotes send DPAD_CENTER (select); some send Enter or a gamepad A button.
const tvShortcuts = <ShortcutActivator, Intent>{
  SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
  SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
};

/// A D-pad friendly tappable: grows and gets an accent outline when focused,
/// activates with the remote's center button (or a click on the emulator).
class TvFocusable extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final double radius;
  final double focusScale;
  final ValueChanged<bool>? onFocusChange;

  const TvFocusable({
    super.key,
    required this.builder,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.radius = 14,
    this.focusScale = 1.04,
    this.onFocusChange,
  });

  @override
  State<TvFocusable> createState() => _TvFocusableState();
}

class _TvFocusableState extends State<TvFocusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      enabled: widget.onPressed != null,
      onShowFocusHighlight: (f) {
        setState(() => _focused = f);
        widget.onFocusChange?.call(f);
        if (f) {
          Scrollable.ensureVisible(context,
              alignment: 0.5, duration: const Duration(milliseconds: 180), curve: Curves.easeOut);
        }
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          widget.onPressed?.call();
          return null;
        }),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _focused ? widget.focusScale : 1,
          duration: const Duration(milliseconds: 140),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              border: Border.all(
                color: _focused ? SoneroColors.accent : Colors.transparent,
                width: 3,
              ),
              boxShadow: _focused
                  ? [BoxShadow(color: SoneroColors.accent.withValues(alpha: 0.35), blurRadius: 18)]
                  : null,
            ),
            child: widget.builder(context, _focused),
          ),
        ),
      ),
    );
  }
}

/// Big pill button for the remote.
class TvButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool autofocus;
  final bool primary;
  final FocusNode? focusNode;

  const TvButton({
    super.key,
    required this.icon,
    this.label,
    this.onPressed,
    this.autofocus = false,
    this.primary = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TvFocusable(
      autofocus: autofocus,
      focusNode: focusNode,
      onPressed: onPressed,
      radius: 40,
      focusScale: 1.08,
      builder: (context, focused) => Container(
        padding: EdgeInsets.symmetric(horizontal: label == null ? 18 : 26, vertical: 16),
        decoration: BoxDecoration(
          color: primary || focused ? SoneroColors.accent : SoneroColors.surfaceAlt,
          borderRadius: BorderRadius.circular(40),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: label == null ? 34 : 26, color: Colors.white),
            if (label != null) ...[
              const SizedBox(width: 10),
              Text(label!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Album art streamed from the server, with a placeholder when there's none.
class CoverArt extends StatelessWidget {
  final SoneroApi api;
  final Track? track;
  final double size;
  final double radius;

  const CoverArt({super.key, required this.api, required this.track, required this.size, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    final t = track;
    final placeholder = Container(
      width: size,
      height: size,
      color: SoneroColors.surfaceAlt,
      child: Icon(Icons.music_note_rounded, size: size * 0.45, color: SoneroColors.muted),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: t == null || !t.hasCover
          ? placeholder
          : Image.network(
              api.coverUri(t).toString(),
              headers: api.authHeaders,
              width: size,
              height: size,
              fit: BoxFit.cover,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => placeholder,
            ),
    );
  }
}

String formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Centered message with an optional action, for empty/error states.
class MessageView extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  const MessageView({super.key, required this.icon, required this.title, this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: SoneroColors.muted),
            const SizedBox(height: 20),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
            if (body != null) ...[
              const SizedBox(height: 12),
              Text(body!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, color: SoneroColors.muted, height: 1.4)),
            ],
            if (action != null) ...[const SizedBox(height: 28), action!],
          ],
        ),
      ),
    );
  }
}


/// Lays the UI out on a fixed 1440-wide canvas and scales it to the screen.
///
/// TVs report very different logical sizes (a 1080p panel at density 2 is
/// 960×540 dp, a 4K one may be 1920×1080 dp); designing in "TV pixels" keeps
/// text readable from the couch and the layout identical on every set.
class TvCanvas extends StatelessWidget {
  static const designWidth = 1440.0;
  final Widget child;

  const TvCanvas({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    if (size.width <= 0) return child;
    final scale = size.width / designWidth;
    final canvas = Size(designWidth, size.height / scale);
    return FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: canvas,
        child: MediaQuery(
          data: mq.copyWith(
            size: canvas,
            devicePixelRatio: mq.devicePixelRatio * scale,
            padding: mq.padding / scale,
            viewPadding: mq.viewPadding / scale,
            viewInsets: mq.viewInsets / scale,
            textScaler: TextScaler.noScaling,
          ),
          child: child,
        ),
      ),
    );
  }
}
