import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sonero_app/l10n/app_localizations.dart';
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
import 'player/mobile_player_sheet.dart';
import 'widgets/track_cover_image.dart';
import 'player/video_player_view.dart';
import 'player/lyrics_view.dart';
import 'theme.dart';
import 'video_download_dialog.dart';
import 'downloads/downloads_page.dart';
import 'search/search_view.dart';
import 'setup_modal.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as p;
import 'wifi_transfer/wifi_transfer_page.dart';
import 'wifi_transfer/cast_to_tv.dart';
import '../services/background_listen_service.dart';
import '../providers/downloads_provider.dart';
import 'settings/settings_page.dart' as settings_page;
import 'widgets/app_logo.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentViewIndex = 1;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>>? _wifiFilesToSend;
  bool _isBottomNavVisible = true;
  double _lastScrollOffset = 0;

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

  static final _videoExt = RegExp(r'\.(mp4|mkv|mov)$', caseSensitive: false);

  List<Map<String, dynamic>> _prepareWifiUploadQueue(List<Track> selectedTracks, SettingsProvider settings) {
    final List<Map<String, dynamic>> queue = [];
    for (var track in selectedTracks) {
      final relativePath = track.filename;
      final isVideo = relativePath.startsWith('videos/') || _videoExt.hasMatch(relativePath);
      final filename = p.basename(relativePath);

      // Backend mode (desktop/web): the backend reads the file from its own
      // library, so only the library filename and metadata are needed.
      if (!settings.api.isNative) {
        queue.add({
          'source': relativePath,
          'type': isVideo ? 'video' : 'music',
          'filename': filename,
          'title': track.title,
          'artist': track.artist,
          'album': track.album,
          'genre': track.genre,
          'year': track.year,
        });
        continue;
      }

      final String filePath;
      String? playlist;
      if (isVideo) {
        final inVideos = relativePath.startsWith('videos/');
        filePath = p.join(settings.videoFolder, inVideos ? relativePath.substring('videos/'.length) : relativePath);
      } else {
        filePath = p.join(settings.musicFolder, relativePath);
        playlist = relativePath.contains('/') ? p.dirname(relativePath) : null;
      }

      if (isVideo) {
        queue.add({
          'filePath': filePath,
          'type': 'video',
          'filename': filename,
          'playlist': null,
          'title': track.title,
          'artist': track.artist,
        });
        continue;
      }

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
        'filePath': filePath,
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

  // ── Apple Music-style unified bottom bar for desktop/tablet ──
  Widget _buildDesktopBottomBar(BuildContext context, PlayerProvider player) {
    final accent = Theme.of(context).colorScheme.primary;
    final track = player.currentTrack;
    final hasTrack = track != null;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final progressValue = hasTrack && player.duration.inMilliseconds > 0
        ? (player.position.inMilliseconds / player.duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final downloadsCount = context.watch<DownloadsProvider>().activeJobsCount;

    return ClipRect(
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Progress bar (only when track is playing) ──
        if (hasTrack)
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTapDown: (details) {
                if (player.duration.inMilliseconds > 0) {
                  final box = context.findRenderObject() as RenderBox;
                  final percent = (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
                  player.seek(Duration(milliseconds: (percent * player.duration.inMilliseconds).toInt()));
                }
              },
              child: Container(
                height: 3,
                color: context.colors.border.withOpacity(0.15),
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progressValue,
                  child: Container(
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        // ── Main bar ──
        Container(
          height: 56 + bottomPadding,
          padding: EdgeInsets.fromLTRB(0, 0, 0, bottomPadding),
          decoration: BoxDecoration(
            color: context.colors.surface,
            border: Border(top: BorderSide(color: context.colors.border.withOpacity(0.08), width: 0.5)),
          ),
          child: Row(
            children: [
              // ── LEFT: Navigation tabs (always evenly spaced in their section) ──
              if (hasTrack)
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _buildNavTabs(context, downloadsCount),
                  ),
                )
              else
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _buildNavTabs(context, downloadsCount),
                  ),
                ),

              // ── DIVIDER ──
              if (hasTrack) ...[
                const Spacer(),
                Container(
                  width: 1,
                  height: 30,
                  margin: const EdgeInsets.only(left: 2, right: 16),
                  color: context.colors.border.withOpacity(0.15),
                ),

                // ── RIGHT: Player section ──
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        // Cover art
                        GestureDetector(
                          onTap: () => _openExpandedPlayer(context),
                          child: MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                color: context.colors.surfaceAlt,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.12),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: getCoverImageProvider(track!.coverUrl) != null
                                  ? AdjustedCoverImage(
                                      coverUrl: track.coverUrl,
                                      width: 38,
                                      height: 38,
                                      borderRadius: BorderRadius.circular(6),
                                    )
                                  : Icon(Icons.music_note_rounded, color: context.colors.textSecondary, size: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Track title marquee
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: GestureDetector(
                            onTap: () => _openExpandedPlayer(context),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: SizedBox(
                                height: 16,
                                child: _MarqueeText(
                                  text: '${track.title.isNotEmpty ? track.title : track.filename}${track.artist.isNotEmpty ? '  •  ${track.artist}' : ''}',
                                  style: TextStyle(
                                    color: context.colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        // ── Playback controls ──
                        _BarIconBtn(icon: Icons.skip_previous_rounded, size: 20, color: context.colors.textPrimary, onTap: player.previous),
                        const SizedBox(width: 8),
                        _BarIconBtn(
                          icon: player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          size: 24,
                          color: context.colors.textPrimary,
                          onTap: player.playPause,
                        ),
                        const SizedBox(width: 8),
                        _BarIconBtn(icon: Icons.skip_next_rounded, size: 20, color: context.colors.textPrimary, onTap: player.next),
                        const SizedBox(width: 12),
                        _BarIconBtn(icon: Icons.stop_rounded, size: 16, color: Colors.red.shade300, onTap: player.stop),
                        const SizedBox(width: 16),
                        // ── Play on TV (continues where it is, pauses here) ──
                        if (!context.read<SettingsProvider>().api.isNative && player.currentTrack != null) ...[
                          Tooltip(
                            message: AppLocalizations.of(context)!.castToTv,
                            child: _BarIconBtn(
                              icon: Icons.cast_rounded,
                              size: 16,
                              color: context.colors.textSecondary,
                              onTap: () => _castCurrentToTv(context, player),
                            ),
                          ),
                          const SizedBox(width: 12),
                        ],
                        // ── Volume ──
                        _BarIconBtn(
                          icon: player.volume <= 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          size: 16,
                          color: context.colors.textSecondary.withOpacity(0.6),
                          onTap: player.toggleMute,
                        ),
                        SizedBox(
                          width: 80,
                          height: 18,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 7),
                              activeTrackColor: context.colors.textSecondary.withOpacity(0.5),
                              inactiveTrackColor: context.colors.border.withOpacity(0.2),
                              thumbColor: context.colors.textPrimary,
                            ),
                            child: Slider(
                              value: player.volume.toDouble().clamp(0.0, 100.0),
                              max: 100,
                              onChanged: (val) => player.setVolume(val),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
  Future<void> _castCurrentToTv(BuildContext context, PlayerProvider player) async {
    final current = player.currentTrack;
    if (current == null) return;
    final queue = player.queue.isNotEmpty ? player.queue : [current];
    final index = queue.indexWhere((t) => t.filename == current.filename);
    final sent = await showCastToTvDialog(
      context,
      apiUrl: context.read<SettingsProvider>().apiUrl,
      filenames: [for (final t in queue) t.filename],
      index: index < 0 ? 0 : index,
      position: player.position.inMilliseconds / 1000,
    );
    if (sent) player.pause();
  }

  List<Widget> _buildNavTabs(BuildContext context, int downloadsCount) {
    return [
      _DesktopNavTab(
        icon: Icons.home_rounded,
        label: 'Inicio',
        isSelected: _currentViewIndex == 0,
        onTap: () => setState(() => _currentViewIndex = 0),
        customIcon: context.watch<SettingsProvider>().customLogoPath.isNotEmpty
            ? const AppLogo(size: 20, borderRadius: 4)
            : null,
      ),
      _DesktopNavTab(
        icon: Icons.library_music_rounded,
        label: 'Biblioteca',
        isSelected: _currentViewIndex == 1,
        onTap: () => setState(() => _currentViewIndex = 1),
      ),
      _DesktopNavTab(
        icon: Icons.bar_chart_rounded,
        label: 'Estadísticas',
        isSelected: _currentViewIndex == 2,
        onTap: () => setState(() => _currentViewIndex = 2),
        badgeCount: downloadsCount,
      ),
      _DesktopNavTab(
        icon: Icons.search_rounded,
        label: 'Buscar',
        isSelected: _currentViewIndex == 3,
        onTap: () => setState(() => _currentViewIndex = 3),
      ),
      _DesktopNavTab(
        icon: Icons.wifi_tethering_rounded,
        label: AppLocalizations.of(context)!.navShare,
        isSelected: _currentViewIndex == 5,
        onTap: () => setState(() => _currentViewIndex = 5),
      ),
    ];
  }

  void _openExpandedPlayer(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        pageBuilder: (_, __, ___) => const MobileExpandedPlayer(),
        transitionsBuilder: (_, anim, __, child) {
          return SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  void _openMobileSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const SettingsPageRoute(),
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
          extendBody: true,
          body: Column(
            children: [
              Expanded(
                child: Row(
                  children: [
                    // Sidebar (only for playlists panel, toggled from player bar)
                    if (!isMobile && !isVideoMode && isSidebarOpen)
                      SidebarWidget(
                        currentIndex: _currentViewIndex,
                        isCollapsed: false,
                        onToggle: () => player.toggleSidebar(),
                        onNavigate: (index) =>
                            setState(() => _currentViewIndex = index),
                      ),

                    // Main content (takes full remaining space)
                    Expanded(
                      child: Stack(
                        children: [
                          // Main view — extends behind the floating nav
                          Positioned.fill(
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollUpdateNotification) {
                                  final delta = notification.scrollDelta ?? 0;
                                  if (delta > 2 && _isBottomNavVisible) {
                                    setState(() => _isBottomNavVisible = false);
                                  } else if (delta < -2 && !_isBottomNavVisible) {
                                    setState(() => _isBottomNavVisible = true);
                                  }
                                }
                                return false;
                              },
                              child: MediaQuery.removePadding(
                                context: context,
                                removeBottom: true,
                                child: currentView,
                              ),
                            ),
                          ),

                          // Netflix-style Video Overlay (full width)
                          if (isVideoMode)
                            const Positioned.fill(
                              child: VideoOverlay(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Desktop/Tablet: Apple Music unified bottom bar (nav + player)
              if (!isMobile && !isVideoMode)
                _buildDesktopBottomBar(context, player),
            ],
          ),
        ),
        const ListenOverlay(),
        // ── Mobile: gradient fade at the bottom so content fades behind nav ──
        if (isMobile)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).padding.bottom + 140,
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      context.colors.bg.withOpacity(0.0),
                      context.colors.bg.withOpacity(0.6),
                      context.colors.bg.withOpacity(0.95),
                      context.colors.bg,
                    ],
                    stops: const [0.0, 0.35, 0.7, 1.0],
                  ),
                ),
              ),
            ),
          ),
        // ── Floating Mini Player Pill (Mobile only) ── ALWAYS VISIBLE ──
        if (isMobile && player.currentTrack != null && !player.isVideoMode)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 0,
            right: 0,
            bottom: _isBottomNavVisible
                ? MediaQuery.of(context).padding.bottom + 80
                : MediaQuery.of(context).padding.bottom + 12,
            child: const MiniPlayer(),
          ),
        // ── Floating Pill Bottom Nav (Mobile only) ───────────────────
        if (isMobile)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
            left: 24,
            right: 24,
            bottom: _isBottomNavVisible ? MediaQuery.of(context).padding.bottom + 12 : -100,
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: context.colors.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
                border: Border.all(
                  color: context.colors.border.withOpacity(0.15),
                  width: 0.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _MobilePillNavItem(
                    icon: Icons.home_rounded,
                    label: 'Inicio',
                    isSelected: _currentViewIndex == 0,
                    onTap: () => setState(() => _currentViewIndex = 0),
                    customIcon: context.watch<SettingsProvider>().customLogoPath.isNotEmpty
                        ? const AppLogo(size: 22, borderRadius: 4)
                        : null,
                  ),
                  _MobilePillNavItem(
                    icon: Icons.library_music_rounded,
                    label: 'Biblioteca',
                    isSelected: _currentViewIndex == 1,
                    onTap: () => setState(() => _currentViewIndex = 1),
                  ),
                  _MobilePillNavItem(
                    icon: Icons.bar_chart_rounded,
                    label: 'Estadísticas',
                    isSelected: _currentViewIndex == 2,
                    onTap: () => setState(() => _currentViewIndex = 2),
                    badgeCount: context.watch<DownloadsProvider>().activeJobsCount,
                  ),
                  _MobilePillNavItem(
                    icon: Icons.search_rounded,
                    label: 'Buscar',
                    isSelected: _currentViewIndex == 3,
                    onTap: () => setState(() => _currentViewIndex = 3),
                  ),
                  _MobilePillNavItem(
                    icon: Icons.wifi_tethering_rounded,
                    label: AppLocalizations.of(context)!.navShare,
                    isSelected: _currentViewIndex == 5,
                    onTap: () => setState(() => _currentViewIndex = 5),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class SettingsPageRoute extends StatelessWidget {
  const SettingsPageRoute({super.key});

  @override
  Widget build(BuildContext context) {
    return const settings_page.SettingsPage();
  }
}

class _MobilePillNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;
  final Widget? customIcon;

  const _MobilePillNavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                customIcon ?? Icon(
                  icon,
                  size: 22,
                  color: isSelected ? accent : context.colors.textSecondary.withOpacity(0.6),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(minWidth: 14, minHeight: 12),
                      child: Text(
                        '$badgeCount',
                        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? accent : context.colors.textSecondary.withOpacity(0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apple Music-style nav tab for the desktop bottom bar
class _DesktopNavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final int badgeCount;
  final Widget? customIcon;

  const _DesktopNavTab({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.badgeCount = 0,
    this.customIcon,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final color = isSelected ? accent : context.colors.textSecondary.withOpacity(0.5);
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  customIcon ?? Icon(icon, size: 20, color: color),
                  if (badgeCount > 0)
                    Positioned(
                      right: -8,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)),
                        constraints: const BoxConstraints(minWidth: 14, minHeight: 12),
                        child: Text('$badgeCount', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Minimal icon button for the player section of the bottom bar
class _BarIconBtn extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color color;
  final VoidCallback onTap;

  const _BarIconBtn({required this.icon, required this.size, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}

/// Auto-scrolling marquee text widget — scrolls when text is wider than its container
class _MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _MarqueeText({required this.text, required this.style});

  @override
  State<_MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<_MarqueeText> with SingleTickerProviderStateMixin {
  late final ScrollController _scrollController;
  Timer? _timer;
  bool _needsScroll = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndStartScroll());
  }

  @override
  void didUpdateWidget(covariant _MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _timer?.cancel();
      _scrollController.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAndStartScroll());
    }
  }

  void _checkAndStartScroll() {
    if (!mounted) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    _needsScroll = maxScroll > 0;
    if (_needsScroll) {
      _startScrollLoop();
    }
  }

  void _startScrollLoop() {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_needsScroll) return;
      _animateForward();
    });
  }

  void _animateForward() {
    if (!mounted) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final duration = Duration(milliseconds: (maxScroll * 40).toInt().clamp(2000, 8000));
    _scrollController.animateTo(maxScroll, duration: duration, curve: Curves.linear).then((_) {
      if (!mounted) return;
      _timer = Timer(const Duration(seconds: 2), () {
        if (!mounted) return;
        _scrollController.animateTo(0, duration: const Duration(milliseconds: 800), curve: Curves.easeOut).then((_) {
          if (mounted) _startScrollLoop();
        });
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Text(widget.text, style: widget.style, maxLines: 1),
    );
  }
}
