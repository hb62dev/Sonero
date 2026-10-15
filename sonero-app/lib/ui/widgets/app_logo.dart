import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';

/// Reusable logo widget that shows the user's custom logo if set,
/// otherwise falls back to the bundled asset logo.
class AppLogo extends StatelessWidget {
  final double size;
  final double borderRadius;

  const AppLogo({super.key, this.size = 40, this.borderRadius = 12});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final customPath = settings.customLogoPath;

    Widget image;

    if (customPath.isNotEmpty && customPath.startsWith('data:')) {
      // Base64 data URI
      try {
        final base64Data = customPath.split(',').last;
        image = Image.memory(
          base64Decode(base64Data),
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _defaultLogo(),
        );
      } catch (_) {
        image = _defaultLogo();
      }
    } else {
      image = _defaultLogo();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: size,
        height: size,
        child: image,
      ),
    );
  }

  Widget _defaultLogo() {
    return Image.asset(
      'assets/images/logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}
