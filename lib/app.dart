import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/hotkey_service.dart';
import 'providers/settings_provider.dart';
import 'providers/library_provider.dart';
import 'providers/listen_provider.dart';
import 'providers/player_provider.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';

class ShazamApp extends StatefulWidget {
  const ShazamApp({super.key});

  @override
  State<ShazamApp> createState() => _ShazamAppState();
}

class _ShazamAppState extends State<ShazamApp> {
  final _settings  = SettingsProvider();
  final _library   = LibraryProvider();
  final _listen    = ListenProvider();
  final _player    = PlayerProvider();
  final _hotkeys   = HotkeyService();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _settings.load();

    // Register global hotkeys (Windows desktop only)
    if (!kIsWeb && Platform.isWindows) {
      await _hotkeys.initialize(
        onMicTriggered: _listenMic,
        onSystemTriggered: _listenSystem,
      );
    }

    setState(() => _initialized = true);
  }

  void _listenMic() {
    _listen.startListening(
      api: _settings.api,
      source: 'mic',
      duration: _settings.listenDuration,
      deviceIndex: _settings.deviceIndex,
      onDone: () {
        _library.loadTracks(_settings.api);
        _library.loadPlaylists(_settings.api);
      },
    );
  }

  void _listenSystem() {
    _listen.startListening(
      api: _settings.api,
      source: 'system',
      duration: _settings.listenDuration,
      onDone: () {
        _library.loadTracks(_settings.api);
        _library.loadPlaylists(_settings.api);
      },
    );
  }

  @override
  void dispose() {
    _hotkeys.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const MaterialApp(
        home: Scaffold(
          backgroundColor: Color(0xFF0A0A10),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF7B2FFF)),
          ),
        ),
      );
    }

    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _settings),
        ChangeNotifierProvider.value(value: _library),
        ChangeNotifierProvider.value(value: _listen),
        ChangeNotifierProvider.value(value: _player),
        Provider.value(value: _hotkeys),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<SettingsProvider>();
          return MaterialApp(
            title: 'Sonero',
            debugShowCheckedModeBanner: false,
            themeMode: settings.themeMode,
            theme: AppTheme.getTheme(settings, isDark: false),
            darkTheme: AppTheme.getTheme(settings, isDark: true),
            home: const AppShell(),
          );
        }
      ),
    );
  }
}
