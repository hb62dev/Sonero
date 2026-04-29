import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/listen_provider.dart';
import '../providers/settings_provider.dart';
import 'sidebar/sidebar_widget.dart';
import 'library/library_page.dart';
import 'home/home_view.dart';
import 'analytics/analytics_view.dart';
import 'listen/listen_overlay.dart';
import 'player/mini_player.dart';
import 'theme.dart';
import 'video_download_dialog.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentViewIndex = 0; // 0: Home, 1: Library, 2: Analytics

  @override
  void initState() {
    super.initState();
    // Register in-app keyboard shortcuts (works on Web + any platform)
    HardwareKeyboard.instance.addHandler(_handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final ctrl  = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key   = event.logicalKey;

    if (ctrl && shift && key == LogicalKeyboardKey.keyM) {
      _triggerListen('mic');
      return true;
    }
    if (ctrl && shift && key == LogicalKeyboardKey.keyS) {
      _triggerListen('system');
      return true;
    }
    if (ctrl && shift && key == LogicalKeyboardKey.keyV) {
      showDialog(
        context: context,
        builder: (_) => const VideoDownloadDialog(),
      ).then((success) {
        if (success == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.downloadComplete)),
          );
          final settings = context.read<SettingsProvider>();
          context.read<LibraryProvider>().loadTracks(settings.api);
        }
      });
      return true;
    }
    return false;
  }

  void _triggerListen(String source) {
    final settings = context.read<SettingsProvider>();
    final listen   = context.read<ListenProvider>();
    if (listen.isListening) return;
    listen.startListening(
      api: settings.api,
      source: source,
      duration: settings.listenDuration,
      deviceIndex: settings.deviceIndex,
      onDone: () {
        context.read<LibraryProvider>().loadTracks(settings.api);
        context.read<LibraryProvider>().loadPlaylists(settings.api);
      },
    );
  }

  Future<void> _init() async {
    final settings = context.read<SettingsProvider>();
    final library  = context.read<LibraryProvider>();
    await library.loadPlaylists(settings.api);
    await library.loadTracks(settings.api);
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    Widget currentView;
    switch (_currentViewIndex) {
      case 0:
        currentView = HomeView(onNavigate: (index) => setState(() => _currentViewIndex = index));
        break;
      case 1:
        currentView = const LibraryPage();
        break;
      case 2:
        currentView = const AnalyticsView();
        break;
      default:
        currentView = HomeView(onNavigate: (index) => setState(() => _currentViewIndex = index));
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: context.colors.bg,
          appBar: isMobile ? AppBar(
            backgroundColor: context.colors.bg,
            elevation: 0,
            iconTheme: IconThemeData(color: context.colors.textPrimary),
            title: Text(AppLocalizations.of(context)!.appTitle, style: TextStyle(color: context.colors.textPrimary)),
          ) : null,
          drawer: isMobile ? Drawer(
            child: SidebarWidget(
              currentIndex: _currentViewIndex,
              onNavigate: (index) {
                setState(() => _currentViewIndex = index);
                Navigator.pop(context);
              },
            ),
          ) : null,
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    if (!isMobile) ...[
                      SidebarWidget(
                        currentIndex: _currentViewIndex,
                        onNavigate: (index) => setState(() => _currentViewIndex = index),
                      ),
                      VerticalDivider(width: 1, color: context.colors.border),
                    ],
                    Expanded(child: currentView),
                  ],
                ),
              ),
              const MiniPlayer(),
            ],
          ),
        ),
        const ListenOverlay(),
      ],
    );
  }
}


