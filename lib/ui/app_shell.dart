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
import 'downloads/downloads_page.dart';
import 'search/search_view.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentViewIndex = 0; // 0: Home, 1: Library, 2: Analytics, 3: Search
  bool _isSidebarCollapsed = true; // start collapsed by default

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
      ).then((result) {
        if (result != null) {
          if (result is String) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Descarga completada con advertencias: $result'), backgroundColor: Colors.orange, duration: const Duration(seconds: 5)),
            );
          } else if (result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(AppLocalizations.of(context)!.downloadComplete)),
            );
          }
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
      case 3:
        currentView = SearchView(onNavigate: (index) => setState(() => _currentViewIndex = index));
        break;
      case 4:
        currentView = const DownloadsPage();
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
              isCollapsed: false,
              onToggle: () => Navigator.pop(context),
              onNavigate: (index) {
                setState(() => _currentViewIndex = index);
                Navigator.pop(context);
              },
            ),
          ) : null,
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Main content
                    Positioned.fill(
                      left: isMobile ? 0 : 64, // Keep space for collapsed sidebar
                      child: currentView,
                    ),
                    // Invisible barrier to close sidebar when tapping outside
                    if (!isMobile && !_isSidebarCollapsed)
                      Positioned.fill(
                        left: 64, // Cover only the content area, not the collapsed sidebar area
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() => _isSidebarCollapsed = true),
                          child: Container(
                            color: Colors.black.withOpacity(0.3), // Optional: Add a slight dimming effect
                          ),
                        ),
                      ),
                    // Sidebar
                    if (!isMobile)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        child: SidebarWidget(
                          currentIndex: _currentViewIndex,
                          isCollapsed: _isSidebarCollapsed,
                          onToggle: () => setState(() => _isSidebarCollapsed = !_isSidebarCollapsed),
                          onNavigate: (index) => setState(() => _currentViewIndex = index),
                        ),
                      ),
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


