import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:flutter/services.dart';
import 'core/hotkey_service.dart';
import 'providers/settings_provider.dart';
import 'providers/library_provider.dart';
import 'providers/listen_provider.dart';
import 'providers/player_provider.dart';
import 'providers/downloads_provider.dart';
import 'ui/app_shell.dart';
import 'ui/theme.dart';
import 'ui/video_download_dialog.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class ShazamApp extends StatefulWidget {
  const ShazamApp({super.key});

  @override
  State<ShazamApp> createState() => _ShazamAppState();
}

class _ShazamAppState extends State<ShazamApp> with TrayListener, WindowListener {
  final _settings  = SettingsProvider();
  final _library   = LibraryProvider();
  final _listen    = ListenProvider();
  final _player    = PlayerProvider();
  final _downloads = DownloadsProvider();
  final _hotkeys   = HotkeyService();
  final _navigatorKey = GlobalKey<NavigatorState>();
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _settings.load();
    _downloads.startPolling(_settings.api);

    // Register global hotkeys (Windows desktop only)
    if (!kIsWeb && Platform.isWindows) {
      await localNotifier.setup(appName: 'Sonero');
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      
      trayManager.addListener(this);
      await trayManager.setIcon(
        Platform.isWindows ? 'windows/runner/resources/app_icon.ico' : 'app_icon.ico',
      );
      
      Menu menu = Menu(
        items: [
          MenuItem(key: 'show_window', label: 'Abrir Sonero'),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: 'Salir'),
        ],
      );
      await trayManager.setContextMenu(menu);

      await _hotkeys.initialize(
        onMicTriggered: _listenMic,
        onSystemTriggered: _listenSystem,
        onVideoTriggered: _listenVideo,
        onHideTriggered: () => windowManager.hide(),
        onShowTriggered: () async {
          await windowManager.show();
          await windowManager.focus();
        },
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

  void _listenVideo() {
    final context = _navigatorKey.currentContext;
    if (context != null) {
      showDialog(
        context: context,
        builder: (_) => const VideoDownloadDialog(),
      ).then((result) {
        if (result != null) {
          if (result is String) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Descarga completada con advertencias: $result'), backgroundColor: Colors.orange, duration: const Duration(seconds: 5)),
            );
          } else if (result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Video download started/completed successfully')),
            );
          }
          _library.loadTracks(_settings.api); // Optional: reload library to see the file, though videos go to /videos
        }
      });
    }
  }

  @override
  void onWindowClose() async {
    if (kIsWeb || !Platform.isWindows) return;
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      windowManager.hide();
    }
  }

  @override
  void onTrayIconMouseDown() {
    if (kIsWeb || !Platform.isWindows) return;
    windowManager.show();
    windowManager.focus();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (kIsWeb || !Platform.isWindows) return;
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (kIsWeb || !Platform.isWindows) return;
    if (menuItem.key == 'show_window') {
      windowManager.show();
      windowManager.focus();
    } else if (menuItem.key == 'exit_app') {
      windowManager.destroy();
    }
  }

  @override
  void dispose() {
    if (!kIsWeb && Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    _hotkeys.dispose();
    _downloads.dispose();
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
        ChangeNotifierProvider.value(value: _downloads),
        Provider.value(value: _hotkeys),
      ],
      child: Builder(
        builder: (context) {
          final settings = context.watch<SettingsProvider>();
          return MaterialApp(
            title: 'Sonero',
            debugShowCheckedModeBanner: false,
            navigatorKey: _navigatorKey,
            themeMode: settings.themeMode,
            theme: AppTheme.getTheme(settings, isDark: false),
            darkTheme: AppTheme.getTheme(settings, isDark: true),
            locale: Locale(settings.locale),
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [
              Locale('es'),
              Locale('en'),
              Locale('ja'),
            ],
            // ── Global mobile density ───────────────────────────────────────
            // Aplica a TODAS las rutas (push, dialog, etc.), no solo AppShell
            builder: (context, child) {
              final isMobile = MediaQuery.of(context).size.width < 600;
              if (!isMobile) return child!;

              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(0.82),
                ),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    elevatedButtonTheme: ElevatedButtonThemeData(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        textStyle: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                        minimumSize: const Size(0, 36),
                      ),
                    ),
                    outlinedButtonTheme: OutlinedButtonThemeData(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                        textStyle: const TextStyle(fontSize: 13),
                        minimumSize: const Size(0, 36),
                      ),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        textStyle: const TextStyle(fontSize: 12),
                        minimumSize: const Size(0, 30),
                      ),
                    ),
                    inputDecorationTheme:
                        Theme.of(context).inputDecorationTheme.copyWith(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      isDense: true,
                    ),
                    listTileTheme:
                        Theme.of(context).listTileTheme.copyWith(
                      dense: true,
                      minVerticalPadding: 4,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 0),
                    ),
                    appBarTheme: Theme.of(context).appBarTheme.copyWith(
                      toolbarHeight: 48,
                    ),
                  ),
                  child: child!,
                ),
              );
            },
            home: const AppShell(),
          );
        }
      ),
    );
  }
}
