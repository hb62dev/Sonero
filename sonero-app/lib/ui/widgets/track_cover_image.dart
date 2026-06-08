import 'dart:io';
import 'package:flutter/material.dart';

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
    return Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => errorWidget,
    );
  }
}
