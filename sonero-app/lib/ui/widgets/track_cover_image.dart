import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';

ImageProvider? getCoverImageProvider(String? coverUrl) {
  if (coverUrl == null || coverUrl.isEmpty) {
    return null;
  }
  if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
    return NetworkImage(coverUrl);
  }
  final file = File(coverUrl);
  if (file.existsSync()) {
    return FileImage(file);
  }
  return null;
}

class TrackCoverImage extends StatelessWidget {
  final String? coverUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget errorWidget;

  const TrackCoverImage({
    super.key,
    required this.coverUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    required this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    final provider = getCoverImageProvider(coverUrl);
    if (provider == null) {
      return errorWidget;
    }
    final settings = context.watch<SettingsProvider>();
    final adjustment = settings.getCoverAdjustment(coverUrl);
    final scale = adjustment?.scale ?? 1.0;
    final offsetX = adjustment?.offsetX ?? 0.0;
    final offsetY = adjustment?.offsetY ?? 0.0;

    return SizedBox(
      width: width,
      height: height,
      child: Transform.translate(
        offset: Offset(offsetX, offsetY),
        child: Transform.scale(
          scale: scale,
          child: Image(
            image: provider,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => errorWidget,
          ),
        ),
      ),
    );
  }
}

/// A cover image widget that applies the user's zoom/pan adjustment
/// from PlayerProvider when the coverUrl matches the current track.
/// Use this wherever a track's cover is displayed and should respect
/// the "Ajustar imagen" settings.
class AdjustedCoverImage extends StatelessWidget {
  final String? coverUrl;
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Widget? fallback;

  const AdjustedCoverImage({
    super.key,
    required this.coverUrl,
    required this.width,
    required this.height,
    this.borderRadius = BorderRadius.zero,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final provider = getCoverImageProvider(coverUrl);
    if (provider == null) {
      return fallback ?? SizedBox(width: width, height: height);
    }

    final settings = context.watch<SettingsProvider>();
    final adjustment = settings.getCoverAdjustment(coverUrl);
    final scale = adjustment?.scale ?? 1.0;
    final offsetX = adjustment?.offsetX ?? 0.0;
    final offsetY = adjustment?.offsetY ?? 0.0;

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: Transform.translate(
          offset: Offset(offsetX, offsetY),
          child: Transform.scale(
            scale: scale,
            child: Image(
              image: provider,
              width: width,
              height: height,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback ?? SizedBox(width: width, height: height),
            ),
          ),
        ),
      ),
    );
  }
}
