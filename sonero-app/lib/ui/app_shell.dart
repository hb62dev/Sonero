import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../providers/listen_provider.dart';
import '../providers/player_provider.dart';
import '../providers/settings_provider.dart';
import '../models/track.dart';
import 'sidebar/sidebar_widget.dart';
import 'library/library_page.dart';
import 'home/home_view.dart';
import 'analytics/analytics_view.dart';
import 'listen/listen_overlay.dart';
import 'player/mini_player.dart';
import 'player/video_player_view.dart';
import 'player/lyrics_view.dart';
import 'theme.dart';
import 'video_download_dialog.dart';
import 'downloads/downloads_page.dart';
import 'search/search_view.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'setup_modal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'wifi_transfer/wifi_transfer_page.dart';
import '../services/background_listen_service.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentViewIndex = 1;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>>? _wifiFilesToSend;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchQueryChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchQueryChanged);
    _searchController.dispose();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  void _onSearchQueryChanged() {
    final query = _searchController.text;
    if (query.isNotEmpty && _currentViewIndex != 3) {
      setState(() {
        _currentViewIndex = 3;
      });
    }
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;

    final ctrl  = HardwareKeyboard.instance.isControlPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final key   = event.logicalKey;
    final player = context.read<PlayerProvider>();
    final hasTrack = player.currentTrack != null;

    // ── Existing listen shortcuts (Ctrl+Shift+M/S/V) ──────────────────────
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
              SnackBar(
                content: Text('Descarga completada con advertencias: $result'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
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

    // ── Player shortcuts (only when a track is loaded) ────────────────────

    // Guard: don't fire single-key shortcuts while the user is typing in a field
    final bool typing = _isTyping();

    // Volume: Ctrl+↑ / Ctrl+↓  (avoids conflicts with sidebar list navigation)
    if (ctrl && !shift) {
      if (key == LogicalKeyboardKey.arrowUp && hasTrack) {
        player.setVolume((player.volume + 5).clamp(0, 100));
        return true;
      }
      if (key == LogicalKeyboardKey.arrowDown && hasTrack) {
        player.setVolume((player.volume - 5).clamp(0, 100));
        return true;
      }
    }

    if (!ctrl && !shift) {
      // ← / → : prev / next track (no conflict — sidebar navigates vertically)
      if (key == LogicalKeyboardKey.arrowLeft && hasTrack) {
        player.previous();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight && hasTrack) {
        player.next();
        return true;
      }

      // Space: play/pause (only if not typing, to allow text-field spaces)
      if (key == LogicalKeyboardKey.space && hasTrack && !typing) {
        player.playPause();
        return true;
      }

      // Single-letter shortcuts — skip when typing in any text field
      if (!typing) {
        if (key == LogicalKeyboardKey.keyM && hasTrack) {
          player.toggleMute();
          return true;
        }
        if (key == LogicalKeyboardKey.keyS && hasTrack) {
          player.toggleShuffle();
          return true;
        }
        if (key == LogicalKeyboardKey.keyR && hasTrack) {
          player.toggleRepeat();
          return true;
        }
        if (key == LogicalKeyboardKey.keyX && hasTrack) {
          player.stop();
          return true;
        }
        if (key == LogicalKeyboardKey.keyF && player.isVideoMode) {
          player.toggleFullscreen();
          return true;
        }
        if (key == LogicalKeyboardKey.keyL && hasTrack && !player.isVideoMode) {
          final track = player.currentTrack!;
          showDialog(
            context: context,
            builder: (_) => LyricsView(
              title: track.title,
              artist: track.artist,
              filename: track.filename,
            ),
          );
          return true;
        }
      }

      if (key == LogicalKeyboardKey.escape) {
        if (player.isFullscreen) {
          player.setFullscreen(false);
          return true;
        }
        if (player.isVideoMode) {
          player.setVideoMode(false);
          return true;
        }
      }
    }

    return false;
  }

  /// Returns true when focus is inside an editable text widget, so single-key
  /// shortcuts don't interfere with typing in the search bar or other fields.
  ///
  /// We walk up the focus scope from the primary focus node and check whether
  /// any ancestor widget in the element tree is an [EditableText].  This covers
  /// cases where the focused node's own context points to a wrapper widget
  /// (e.g. TextField, SearchBar) whose child is the actual EditableText.
  bool _isTyping() {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) return false;

    // Walk up the focus-node ancestors checking each context
    FocusNode? node = focus;
    while (node != null) {
      final ctx = node.context;
      if (ctx != null) {
        // Check if this element or any ancestor up to the nearest route is an
        // EditableText — visitAncestorElements stops when the callback returns false.
        bool found = false;
        ctx.visitAncestorElements((element) {
          if (element.widget is EditableText) {
            found = true;
            return false; // stop
          }
          return true; // keep walking
        });
        if (found) return true;
        // Also check the widget at this node itself
        if (ctx.widget is EditableText) return true;
      }
      // Move to the parent focus node
      node = node.parent;
      // Stop at the root scope to avoid infinite loops
      if (node == FocusManager.instance.rootScope) break;
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
    
    if (!settings.hasMusicFolder) {
      // Show setup modal. Since it is non-dismissible, we wait for it to close.
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const SetupModal(),
      );
    } else {
      // Already set up, but let's check/request permissions sequentially just in case
      if (!kIsWeb && Platform.isAndroid) {
        try {
          await [
            Permission.audio,
            Permission.videos,
            Permission.storage,
            Permission.manageExternalStorage,
            Permission.notification,
            Permission.microphone,
          ].request();
          await settings.refreshFolders();
        } catch (e) {
          debugPrint('Error requesting permissions in app_shell: $e');
        }
      }
    }
    
    await library.loadPlaylists(settings.api);
    await library.loadTracks(settings.api);

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      try {
        await BackgroundListenService.start();
      } catch (e) {
        debugPrint('Error starting BackgroundListenService: $e');
      }
    }
  }

  List<Map<String, dynamic>> _prepareWifiUploadQueue(List<Track> selectedTracks, SettingsProvider settings) {
    final List<Map<String, dynamic>> queue = [];
    for (var track in selectedTracks) {
      final audioPath = p.join(settings.musicFolder, track.filename);
      
      final relativePath = track.filename;
      final hasFolder = relativePath.contains('/');
      final playlist = hasFolder ? p.dirname(relativePath) : null;
      final filename = p.basename(relativePath);

      String? coverFilename;
      if (track.coverUrl != null && track.coverUrl!.isNotEmpty && !track.coverUrl!.startsWith('http')) {
        final coverFile = File(track.coverUrl!);
        if (coverFile.existsSync()) {
          coverFilename = p.basename(track.coverUrl!);
          queue.add({
            'filePath': coverFile.path,
            'type': 'cover',
            'filename': coverFilename,
            'playlist': null,
            'title': '',
            'artist': '',
          });
        }
      }

      queue.add({
        'filePath': audioPath,
        'type': 'music',
        'filename': filename,
        'playlist': playlist,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'genre': track.genre,
        'year': track.year,
        'cover_url': coverFilename,
      });
    }
    return queue;
  }



  PopupMenuItem<int> _buildPopupMenuItem(int index, IconData icon, String title) {
    final isSelected = _currentViewIndex == index;
    return PopupMenuItem<int>(
      value: index,
      child: Row(
        children: [
          Icon(
            icon,
            color: isSelected ? Theme.of(context).colorScheme.primary : context.colors.textSecondary,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: isSelected ? context.colors.textPrimary : context.colors.textSecondary,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player       = context.watch<PlayerProvider>();
    final isSidebarOpen = player.isSidebarVisible;
    final isVideoMode  = player.isVideoMode;
    final isMobile     = MediaQuery.of(context).size.width < 600;

    Widget currentView;
    switch (_currentViewIndex) {
      case 0:
        currentView = HomeView(onNavigate: (i) => setState(() => _currentViewIndex = i));
        break;
      case 1:
        currentView = LibraryPage(
          onWiFiShare: (selectedTracks) {
            final settings = context.read<SettingsProvider>();
            final queue = _prepareWifiUploadQueue(selectedTracks, settings);
            setState(() {
              _wifiFilesToSend = queue;
              _currentViewIndex = 5;
            });
          },
        );
        break;
      case 2:
        currentView = const AnalyticsView();
        break;
      case 3:
        currentView = SearchView(
          onNavigate: (i) => setState(() => _currentViewIndex = i),
          searchController: _searchController,
        );
        break;
      case 4:
        currentView = const DownloadsPage();
        break;
      case 5:
        currentView = WifiTransferPage(
          initialFilesToSend: _wifiFilesToSend,
          onClearFiles: () {
            setState(() {
              _wifiFilesToSend = null;
            });
          },
        );
        break;
      default:
        currentView = HomeView(onNavigate: (i) => setState(() => _currentViewIndex = i));
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: context.colors.bg,
          drawer: isMobile
              ? Drawer(
                  backgroundColor: context.colors.bg,
                  child: SidebarWidget(
                    currentIndex: _currentViewIndex,
                    isCollapsed: false,
                    onToggle: () => Navigator.pop(context),
                    onNavigate: (index) {
                      setState(() => _currentViewIndex = index);
                      Navigator.pop(context); // Close the drawer
                    },
                  ),
                )
              : null,
          appBar: isMobile
              ? AppBar(
                  backgroundColor: context.colors.bg,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  titleSpacing: 12,
                  title: Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 38,
                          decoration: BoxDecoration(
                            color: context.colors.surfaceAlt,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _searchController,
                            builder: (context, value, _) {
                              return TextField(
                                controller: _searchController,
                                style: TextStyle(
                                  color: context.colors.textPrimary,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Buscar música...',
                                  hintStyle: TextStyle(
                                    color: context.colors.textSecondary.withOpacity(0.5),
                                    fontSize: 13,
                                  ),
                                  prefixIcon: Icon(
                                    Icons.search_rounded,
                                    color: context.colors.textSecondary.withOpacity(0.7),
                                    size: 18,
                                  ),
                                  suffixIcon: value.text.isNotEmpty
                                      ? IconButton(
                                          icon: Icon(Icons.close_rounded, color: context.colors.textSecondary, size: 16),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () => _searchController.clear(),
                                        )
                                      : null,
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 9),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Builder(
                        builder: (context) => IconButton(
                          icon: Icon(
                            Icons.menu_rounded,
                            color: context.colors.textSecondary,
                            size: 20,
                          ),
                          onPressed: () {
                            Scaffold.of(context).openDrawer();
                          },
                        ),
                      ),
                    ],
                  ),
                )
              : null,
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // 1. Main content (offset for collapsed sidebar icon strip)
                    Positioned.fill(
                      left: isMobile ? 0 : (isVideoMode ? 0 : 64),
                      child: currentView,
                    ),

                    // 2. Collapsed sidebar icon strip (normal mode only)
                    if (!isMobile && !isVideoMode && !isSidebarOpen)
                      Positioned(
                        left: 0, top: 0, bottom: 0,
                        child: SidebarWidget(
                          currentIndex: _currentViewIndex,
                          isCollapsed: true,
                          onToggle: () => player.toggleSidebar(),
                          onNavigate: (index) =>
                              setState(() => _currentViewIndex = index),
                        ),
                      ),

                    // 3. Netflix-style Video Overlay (full width, under sidebar)
                    if (isVideoMode)
                      const Positioned.fill(
                        child: VideoOverlay(),
                      ),

                    // 4. Dim barrier (full-width, renders BELOW the sidebar)
                    if (!isMobile && isSidebarOpen)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => player.setSidebarVisible(false),
                          child: Container(
                            color: Colors.black.withOpacity(
                                isVideoMode ? 0.55 : 0.30)),
                        ),
                      ),

                    // 5. Expanded sidebar — renders on TOP of the dim overlay
                    if (!isMobile && isSidebarOpen)
                      Positioned(
                        left: 0, top: 0, bottom: 0,
                        child: SidebarWidget(
                          currentIndex: _currentViewIndex,
                          isCollapsed: false,
                          onToggle: () => player.toggleSidebar(),
                          onNavigate: (index) =>
                              setState(() => _currentViewIndex = index),
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
