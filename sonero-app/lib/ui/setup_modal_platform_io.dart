import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/settings_provider.dart';

/// Native platform implementation — requests Android permissions
Future<void> requestPlatformPermissions(BuildContext context) async {
  if (Platform.isAndroid) {
    try {
      await [
        Permission.audio,
        Permission.videos,
        Permission.storage,
        Permission.manageExternalStorage,
        Permission.notification,
        Permission.microphone,
      ].request();

      if (context.mounted) {
        await context.read<SettingsProvider>().refreshFolders();
      }
    } catch (e) {
      debugPrint('Error requesting permissions in SetupModal: $e');
    }
  }
}
