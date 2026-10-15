import 'dart:async';
import 'package:sonero_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/player_provider.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../theme.dart';
import '../widgets/track_cover_image.dart';
import 'download_options_dialog.dart';


class SearchView extends StatefulWidget {
  final Function(int)? onNavigate;
  final TextEditingController? searchController;
  const SearchView({super.key, this.onNavigate, this.searchController});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> with SingleTickerProviderStateMixin {
  late final TextEditingController _searchController;
  String _query = '';
  Timer? _debounce;
  late TabController _mobileTabController;

  bool _isSearchingOnline = false;
  List<dynamic> _onlineResults = [];
  String? _onlineError;
  bool _isListening = false;
  String? _listenStatus;

  // Latest releases from detected artist
  List<dynamic> _latestReleases = [];
  String? _detectedArtist;

  @override
  void initState() {
    super.initState();
    _searchController = widget.searchController ?? TextEditingController();
    _query = _searchController.text;
    _searchController.addListener(_onControllerChanged);
    _mobileTabController = TabController(length: 2, vsync: this);
    if (_query.trim().isNotEmpty) {
      _searchYouTube(_query.trim());
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onControllerChanged);
    if (widget.searchController == null) {
      _searchController.dispose();
    }
    _debounce?.cancel();
    _mobileTabController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _query) {
      _onSearchChanged(newQuery);
    }
  }

  void _onSearchChanged(String query) {
    setState(() => _query = query);
    
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      if (_query.trim().isNotEmpty) {
        _searchYouTube(_query.trim());
      } else {
        setState(() {
          _onlineResults = [];
          _onlineError = null;
        });
      }
    });
  }

  Future<void> _searchYouTube(String query) async {
    setState(() {
      _isSearchingOnline = true;
      _onlineError = null;
    });
    try {
      final settings = context.read<SettingsProvider>();
      if (query.contains('list=')) {
        final info = await settings.api.getPlaylistInfo(query);
        if (mounted) {
          setState(() {
            _onlineResults = [
              {
                'is_playlist': true,
                'url': query,
                'title': info['title'] ?? 'YouTube Playlist',
                'thumbnail': info['thumbnail'],
                'videos_count': info['videos']?.length ?? 0,
              }
            ];
            _isSearchingOnline = false;
          });
        }
      } else {
        final results = await settings.api.searchOnline(query, limit: 20);
        if (mounted) {
          setState(() {
            _onlineResults = results;
            _isSearchingOnline = false;
          });
          // Detect dominant artist and fetch latest releases
          _fetchLatestReleases(results, settings);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _onlineError = e.toString();
          _isSearchingOnline = false;
        });
      }
    }
  }
  /// Detect the most common channel from results and fetch their latest releases
  Future<void> _fetchLatestReleases(List<dynamic> results, SettingsProvider settings) async {
    if (results.isEmpty) {
      setState(() {
        _latestReleases = [];
        _detectedArtist = null;
      });
      return;
    }

    // Count channel occurrences to find the dominant artist
    final channelCounts = <String, int>{};
    for (final r in results) {
      final channel = (r['channel'] ?? '').toString().trim();
      if (channel.isNotEmpty) {
        channelCounts[channel] = (channelCounts[channel] ?? 0) + 1;
      }
    }
    if (channelCounts.isEmpty) return;

    // Find the most frequent channel
    final sortedChannels = channelCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topChannel = sortedChannels.first.key;

    // Only fetch latest if the channel appears in at least 2 results (likely an artist search)
    if (sortedChannels.first.value < 2) {
      setState(() {
        _latestReleases = [];
        _detectedArtist = null;
      });
      return;
    }

    // Extract clean artist name (remove "VEVO", "Official", etc.)
    final cleanArtist = topChannel
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*(Official|Music|TV|Channel)\s*$', caseSensitive: false), '')
        .trim();
    final searchArtist = cleanArtist.isNotEmpty ? cleanArtist : topChannel;

    try {
      // Search for the artist's recent releases (solo + collabs/features)
      final latestResults = await settings.api.searchOnline(
        '"$searchArtist" 2024 2025 official', limit: 15,
      );
      if (mounted) {
        // Accept results that mention the artist (in title or channel) — includes collabs
        final artistLower = searchArtist.toLowerCase();
        final topChannelLower = topChannel.toLowerCase();
        final filtered = latestResults.where((r) {
          final ch = (r['channel'] ?? '').toString().toLowerCase();
          final title = (r['title'] ?? '').toString().toLowerCase();
          return ch.contains(artistLower) ||
                 artistLower.contains(ch) ||
                 ch.contains(topChannelLower) ||
                 title.contains(artistLower);
        }).toList();

        // Remove duplicates that already appear in main results
        final mainIds = results.map((r) => r['id']).toSet();
        final unique = filtered.where((r) => !mainIds.contains(r['id'])).take(10).toList();

        setState(() {
          _latestReleases = unique;
          _detectedArtist = searchArtist;
        });
      }
    } catch (_) {
      // Silently fail — latest releases is a nice-to-have
    }
  }



  List<Track> _getFilteredLocalTracks(List<Track> allTracks) {
    if (_query.trim().isEmpty) return [];
    final q = _query.toLowerCase();
    return allTracks.where((t) {
      return t.title.toLowerCase().contains(q) ||
             t.artist.toLowerCase().contains(q) ||
             t.album.toLowerCase().contains(q) ||
             t.filename.toLowerCase().contains(q);
    }).toList();
  }

  List<Playlist> _getFilteredPlaylists(List<Playlist> allPlaylists) {
    if (_query.trim().isEmpty) return [];
    final q = _query.toLowerCase();
    return allPlaylists.where((p) {
      if (p.isLibrary) return false;
      return p.name.toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _startListening() async {
    if (_isListening) return;
    setState(() {
      _isListening = true;
      _listenStatus = 'Escuchando...';
    });
    try {
      final settings = context.read<SettingsProvider>();
      final duration = settings.listenDuration;
      final jobId = await settings.api.startListening(
        duration: duration,
        autoDownload: false,
        source: 'mic',
        deviceIndex: settings.deviceIndex,
      );

      // Poll for results
      Map<String, dynamic> status;
      do {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        status = await settings.api.getJobStatus(jobId);
        final step = status['step']?.toString() ?? '';
        setState(() => _listenStatus = step.isNotEmpty ? step : 'Procesando...');
      } while (status['status'] != 'done' && status['status'] != 'error' && mounted);

      if (!mounted) return;

      if (status['status'] == 'error') {
        final msg = status['error']?.toString() ?? 'Error desconocido';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo identificar: $msg'), backgroundColor: context.colors.error),
        );
      } else {
        // Extract track info from job result
        final track = status['track'] as Map<String, dynamic>?;
        if (track != null && track['title'] != null) {
          final title = track['title']?.toString() ?? '';
          final artist = track['artist']?.toString() ?? '';
          final searchQuery = '$artist $title'.trim();
          _searchController.text = searchQuery;
          _onSearchChanged(searchQuery);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Canción identificada: $title - $artist'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('No se pudo identificar la canción. Intenta con más volumen.'),
              backgroundColor: context.colors.error,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.error),
        );
      }
    } finally {
      if (mounted) setState(() {
        _isListening = false;
        _listenStatus = null;
      });
    }
  }

  bool get _hasResults => _query.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final localResults = _getFilteredLocalTracks(library.tracks);
    final localPlaylists = _getFilteredPlaylists(library.playlists);
    final isMobile = MediaQuery.of(context).size.width < 600;
    final accent = Theme.of(context).colorScheme.primary;

    // Split online results into playlists, normal videos, and shorts
    final normalVideos = _onlineResults.where((r) => r['is_short'] != true && r['is_playlist'] != true).toList();
    final shortVideos = _onlineResults.where((r) => r['is_short'] == true && r['is_playlist'] != true).toList();
    final onlinePlaylists = _onlineResults.where((r) => r['is_playlist'] == true).toList();

    return Column(
      children: [
        // ── Hero Gradient + Search Bar ─────────────────────────────────────
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          height: _hasResults ? (isMobile ? 100 : 120) : (isMobile ? 280 : 340),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                accent.withOpacity(0.04),
                context.colors.bg,
              ],
              stops: const [0.0, 0.6],
            ),
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isMobile ? 24 : 60),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title text — only when no results
                  AnimatedCrossFade(
                    duration: const Duration(milliseconds: 300),
                    crossFadeState: _hasResults ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                    firstChild: Column(
                      children: [
                        Icon(Icons.search_rounded, size: 40, color: accent.withOpacity(0.4)),
                        const SizedBox(height: 12),
                        Text(
                          'Busca tu música',
                          style: TextStyle(
                            fontSize: isMobile ? 22 : 28,
                            fontWeight: FontWeight.w800,
                            color: context.colors.textPrimary,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Coloca el nombre, link o artista para escuchar y descargar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: isMobile ? 12 : 14,
                            color: context.colors.textSecondary.withOpacity(0.7),
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                    secondChild: const SizedBox(height: 8),
                  ),
                  // ── Pill Search Bar ──────────────────────────────────────
                  Container(
                    constraints: const BoxConstraints(maxWidth: 640),
                    decoration: BoxDecoration(
                      color: context.colors.surface,
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: context.colors.border.withOpacity(0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: _onSearchChanged,
                      style: TextStyle(
                        fontSize: isMobile ? 14 : 15,
                        color: context.colors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Buscar canciones, artistas, o YouTube...',
                        hintStyle: TextStyle(
                          color: context.colors.textSecondary.withOpacity(0.4),
                          fontSize: isMobile ? 13 : 14,
                        ),
                        prefixIcon: Padding(
                          padding: const EdgeInsets.only(left: 16, right: 8),
                          child: _isSearchingOnline
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: accent,
                                  ),
                                )
                              : Icon(Icons.search_rounded, size: 20, color: context.colors.textSecondary.withOpacity(0.5)),
                        ),
                        prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 20),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ear / Audio recognition button
                            Tooltip(
                              message: _isListening
                                  ? (_listenStatus ?? 'Escuchando...')
                                  : 'Identificar canción por audio',
                              child: IconButton(
                                icon: _isListening
                                    ? SizedBox(
                                        width: 19,
                                        height: 19,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: accent,
                                        ),
                                      )
                                    : Icon(Icons.hearing_rounded, size: 19, color: accent.withOpacity(0.6)),
                                onPressed: _isListening ? null : _startListening,
                                style: IconButton.styleFrom(
                                  shape: const CircleBorder(),
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide.none,
                                ),
                              ),
                            ),
                            if (_query.isNotEmpty)
                              IconButton(
                                icon: Icon(Icons.close_rounded, size: 18, color: context.colors.textSecondary),
                                onPressed: () {
                                  _searchController.clear();
                                  _onSearchChanged('');
                                },
                                style: IconButton.styleFrom(
                                  shape: const CircleBorder(),
                                  backgroundColor: Colors.transparent,
                                  side: BorderSide.none,
                                ),
                              ),
                            const SizedBox(width: 4),
                          ],
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // ── Mobile: TabBar ─────────────────────────────────────────────────
        if (isMobile && _hasResults)
          TabBar(
            controller: _mobileTabController,
            indicatorColor: accent,
            labelColor: accent,
            unselectedLabelColor: context.colors.textSecondary,
            labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.library_music_rounded, size: 16),
                  const SizedBox(width: 6),
                  Text('Local (${localResults.length + localPlaylists.length})'),
                ]),
              ),
              Tab(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.play_circle_outline_rounded, size: 16),
                  const SizedBox(width: 6),
                  const Text('YouTube'),
                ]),
              ),
            ],
          ),

        if (_hasResults)
          Divider(height: 1, color: context.colors.border.withOpacity(0.3)),

        // ── Results ───────────────────────────────────────────────────────
        Expanded(
          child: !_hasResults
              ? const SizedBox.shrink()
              : isMobile
                  ? TabBarView(
                      controller: _mobileTabController,
                      children: [
                        _LocalResultsColumn(
                          tracks: localResults,
                          playlists: localPlaylists,
                          onNavigate: widget.onNavigate,
                        ),
                        _YouTubeResultsColumn(
                          isLoading: _isSearchingOnline,
                          error: _onlineError,
                          normalVideos: normalVideos,
                          shortVideos: shortVideos,
                          playlists: onlinePlaylists,
                          latestReleases: _latestReleases,
                          detectedArtist: _detectedArtist,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 1,
                          child: _LocalResultsColumn(
                            tracks: localResults,
                            playlists: localPlaylists,
                            onNavigate: widget.onNavigate,
                          ),
                        ),
                        Container(width: 1, color: context.colors.border.withOpacity(0.3)),
                        Expanded(
                          flex: 1,
                          child: _YouTubeResultsColumn(
                            isLoading: _isSearchingOnline,
                            error: _onlineError,
                            normalVideos: normalVideos,
                            shortVideos: shortVideos,
                            playlists: onlinePlaylists,
                            latestReleases: _latestReleases,
                            detectedArtist: _detectedArtist,
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }
}

// ── Local Results ─────────────────────────────────────────────────────────────

class _LocalResultsColumn extends StatelessWidget {
  final List<Track> tracks;
  final List<Playlist> playlists;
  final Function(int)? onNavigate;
  const _LocalResultsColumn({required this.tracks, required this.playlists, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty && playlists.isEmpty) {
      return Center(
        child: Text('No hay resultados locales', style: TextStyle(color: context.colors.textSecondary)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        if (playlists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Playlists (${playlists.length})', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          ),
          ...playlists.map((pl) => ListTile(
                leading: Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.queue_music_rounded, color: context.colors.textSecondary),
                ),
                title: Text(pl.name, style: TextStyle(color: context.colors.textPrimary)),
                subtitle: Text('${pl.trackCount} canciones', style: TextStyle(color: context.colors.textSecondary)),
                onTap: () {
                  final settings = context.read<SettingsProvider>();
                  context.read<LibraryProvider>().selectPlaylist(settings.api, pl);
                  if (onNavigate != null) onNavigate!(1);
                },
              )).toList(),
        ],
        if (tracks.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Canciones/Videos (${tracks.length})', 
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          ),
          ...tracks.map((track) => ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: TrackCoverImage(
                    coverUrl: track.coverUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorWidget: Container(
                      width: 48,
                      height: 48,
                      color: context.colors.surfaceAlt,
                      child: const Icon(Icons.music_note),
                    ),
                  ),
                ),
                title: Text(track.title.isNotEmpty ? track.title : track.filename, style: TextStyle(color: context.colors.textPrimary)),
                subtitle: Text(track.artist, style: TextStyle(color: context.colors.textSecondary)),
                onTap: () async {
                  final settings = context.read<SettingsProvider>();
                  final library = context.read<LibraryProvider>();
                  context.read<PlayerProvider>().playTrack(track, library.tracks, settings);
                },
              )).toList(),
        ],
      ],
    );
  }
}

// ── YouTube Results ───────────────────────────────────────────────────────────

class _YouTubeResultsColumn extends StatelessWidget {
  final bool isLoading;
  final String? error;
  final List<dynamic> normalVideos;
  final List<dynamic> shortVideos;
  final List<dynamic> playlists;
  final List<dynamic> latestReleases;
  final String? detectedArtist;

  const _YouTubeResultsColumn({
    required this.isLoading,
    required this.error,
    required this.normalVideos,
    required this.shortVideos,
    required this.playlists,
    this.latestReleases = const [],
    this.detectedArtist,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (error != null) {
      return Center(child: Text('Error: $error', style: TextStyle(color: context.colors.error)));
    }
    if (normalVideos.isEmpty && shortVideos.isEmpty && playlists.isEmpty) {
      return Center(child: Text('No hay resultados en YouTube', style: TextStyle(color: context.colors.textSecondary)));
    }

    final l10n = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Latest Releases carousel ──
        if (latestReleases.isNotEmpty && detectedArtist != null) ...[
          _LatestReleasesCarousel(
            releases: latestReleases,
            artist: detectedArtist!,
          ),
          const SizedBox(height: 20),
          Divider(color: context.colors.border.withOpacity(0.2)),
          const SizedBox(height: 12),
        ],

        if (playlists.isNotEmpty) ...[
          Text(l10n.playlistDetected, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          const SizedBox(height: 16),
          ...playlists.map((pl) => _YouTubePlaylistResultItem(playlist: pl)),
          const SizedBox(height: 24),
        ],
        if (normalVideos.isNotEmpty) ...[
          Text('YouTube', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          const SizedBox(height: 16),
          ...normalVideos.map((v) => _YouTubeResultItem(video: v)),
        ],
        
        if (shortVideos.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Shorts', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: shortVideos.length,
              itemBuilder: (ctx, i) => _YouTubeShortItem(video: shortVideos[i]),
            ),
          ),
        ]
      ],
    );
  }
}

// ── Latest Releases Carousel with arrow navigation ──
class _LatestReleasesCarousel extends StatefulWidget {
  final List<dynamic> releases;
  final String artist;
  const _LatestReleasesCarousel({required this.releases, required this.artist});

  @override
  State<_LatestReleasesCarousel> createState() => _LatestReleasesCarouselState();
}

class _LatestReleasesCarouselState extends State<_LatestReleasesCarousel> {
  final ScrollController _scrollCtrl = ScrollController();
  bool _showLeftArrow = false;
  bool _showRightArrow = true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_updateArrows);
  }

  void _updateArrows() {
    if (!mounted) return;
    setState(() {
      _showLeftArrow = _scrollCtrl.offset > 10;
      _showRightArrow = _scrollCtrl.offset < _scrollCtrl.position.maxScrollExtent - 10;
    });
  }

  void _scrollBy(double delta) {
    _scrollCtrl.animateTo(
      (_scrollCtrl.offset + delta).clamp(0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.new_releases_rounded, color: accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Últimos Lanzamientos · ${widget.artist}',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Desktop arrow buttons
            if (!isMobile) ...[
              _ArrowButton(
                icon: Icons.chevron_left_rounded,
                visible: _showLeftArrow,
                onTap: () => _scrollBy(-220),
              ),
              const SizedBox(width: 4),
              _ArrowButton(
                icon: Icons.chevron_right_rounded,
                visible: _showRightArrow,
                onTap: () => _scrollBy(220),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        // Scrollable cards
        SizedBox(
          height: 185,
          child: ListView.builder(
            controller: _scrollCtrl,
            scrollDirection: Axis.horizontal,
            physics: isMobile
                ? const BouncingScrollPhysics()
                : const ClampingScrollPhysics(),
            itemCount: widget.releases.length,
            itemBuilder: (ctx, i) => _LatestReleaseCard(video: widget.releases[i]),
          ),
        ),
      ],
    );
  }
}

/// Small arrow button for desktop carousel navigation
class _ArrowButton extends StatelessWidget {
  final IconData icon;
  final bool visible;
  final VoidCallback onTap;
  const _ArrowButton({required this.icon, required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.3,
      duration: const Duration(milliseconds: 200),
      child: GestureDetector(
        onTap: visible ? onTap : null,
        child: MouseRegion(
          cursor: visible ? SystemMouseCursors.click : SystemMouseCursors.basic,
          child: Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.colors.surfaceAlt,
              border: Border.all(color: context.colors.border.withOpacity(0.3)),
            ),
            child: Icon(icon, color: context.colors.textPrimary, size: 18),
          ),
        ),
      ),
    );
  }
}

class _LatestReleaseCard extends StatefulWidget {
  final dynamic video;
  const _LatestReleaseCard({required this.video});

  @override
  State<_LatestReleaseCard> createState() => _LatestReleaseCardState();
}

class _LatestReleaseCardState extends State<_LatestReleaseCard> {
  bool _justDownloaded = false;

  bool _isAlreadyDownloaded(BuildContext context) {
    if (_justDownloaded) return true;
    final library = context.watch<LibraryProvider>();
    final videoTitle = (widget.video['title'] ?? '').toString().toLowerCase();
    return library.tracks.any((t) {
      final trackTitle = t.title.toLowerCase();
      final trackFilename = t.filename.toLowerCase().replaceAll('.mp3', '').replaceAll('.m4a', '');
      return videoTitle.contains(trackTitle) ||
             trackTitle.contains(videoTitle) ||
             trackFilename.contains(videoTitle) ||
             videoTitle.contains(trackFilename);
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final dur = (video['duration'] as num?)?.toInt();
    final durStr = dur != null ? '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}' : '';
    final accent = Theme.of(context).colorScheme.primary;
    final isDownloaded = _isAlreadyDownloaded(context);

    return GestureDetector(
      onTap: () async {
        final result = await showDialog<dynamic>(
          context: context,
          builder: (_) => DownloadOptionsDialog(videoUrl: video['url'], title: video['title']),
        );
        if (result != null && context.mounted) {
          if (result == true) {
            setState(() => _justDownloaded = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Text('Descargada ✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          final settings = context.read<SettingsProvider>();
          context.read<LibraryProvider>().loadTracks(settings.api);
        }
      },
      child: Container(
        width: 200,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: isDownloaded
              ? Colors.green.shade900.withOpacity(0.3)
              : context.colors.surfaceAlt,
          border: Border.all(
            color: isDownloaded
                ? Colors.green.shade600.withOpacity(0.5)
                : accent.withOpacity(0.15),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail with badges
            Stack(
              children: [
                video['thumbnail'] != null
                    ? Image.network(
                        video['thumbnail'],
                        width: 200,
                        height: 112,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 200, height: 112,
                          color: context.colors.border,
                          child: Icon(Icons.music_video_rounded, color: context.colors.textSecondary),
                        ),
                      )
                    : Container(
                        width: 200, height: 112,
                        color: context.colors.border,
                        child: Icon(Icons.music_video_rounded, color: context.colors.textSecondary),
                      ),
                // NUEVO badge (top-left)
                if (!isDownloaded)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NUEVO',
                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                      ),
                    ),
                  ),
                // Downloaded check badge (top-left, replaces NUEVO)
                if (isDownloaded)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_rounded, color: Colors.white, size: 10),
                          SizedBox(width: 3),
                          Text(
                            'DESCARGADA',
                            style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Duration badge (bottom-right)
                if (durStr.isNotEmpty)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(durStr, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500)),
                    ),
                  ),
              ],
            ),
            // Title + optional check icon
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        video['title'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isDownloaded ? Colors.green.shade300 : context.colors.textPrimary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (isDownloaded) ...[
                      const SizedBox(width: 4),
                      Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 16),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _YouTubePlaylistResultItem extends StatelessWidget {
  final dynamic playlist;
  const _YouTubePlaylistResultItem({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: playlist['thumbnail'] != null && (playlist['thumbnail'] as String).isNotEmpty
                          ? Image.network(
                              playlist['thumbnail'],
                              width: 100,
                              height: 56,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 100,
                                height: 56,
                                color: context.colors.border,
                                child: Icon(Icons.playlist_play_rounded, color: context.colors.textSecondary, size: 28),
                              ),
                            )
                          : Container(
                              width: 100,
                              height: 56,
                              color: context.colors.border,
                              child: Icon(Icons.playlist_play_rounded, color: context.colors.textSecondary, size: 28),
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            playlist['title'] ?? 'YouTube Playlist',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            l10n.playlistVideosCount(playlist['videos_count'] ?? 0),
                            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(l10n.downloadPlaylist),
                  onPressed: () => _downloadPlaylist(context),
                ),
              ],
            )
          : Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: playlist['thumbnail'] != null && (playlist['thumbnail'] as String).isNotEmpty
                      ? Image.network(
                          playlist['thumbnail'],
                          width: 120,
                          height: 68,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 120,
                            height: 68,
                            color: context.colors.border,
                            child: Icon(Icons.playlist_play_rounded, color: context.colors.textSecondary, size: 32),
                          ),
                        )
                      : Container(
                          width: 120,
                          height: 68,
                          color: context.colors.border,
                          child: Icon(Icons.playlist_play_rounded, color: context.colors.textSecondary, size: 32),
                        ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlist['title'] ?? 'YouTube Playlist',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        l10n.playlistVideosCount(playlist['videos_count'] ?? 0),
                        style: TextStyle(fontSize: 13, color: context.colors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text(l10n.downloadPlaylist),
                  onPressed: () => _downloadPlaylist(context),
                ),
              ],
            ),
    );
  }

  void _downloadPlaylist(BuildContext context) async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (_) => DownloadOptionsDialog(
        videoUrl: playlist['url'],
        title: playlist['title'],
      ),
    );
    
    if (result != null && context.mounted) {
      if (result is Map && result['playlist'] == true) {
        final count = result['count'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.playlistEnqueued(count)),
            backgroundColor: context.colors.success,
          ),
        );
      }
      final settings = context.read<SettingsProvider>();
      context.read<LibraryProvider>().loadTracks(settings.api);
    }
  }
}


class _YouTubeResultItem extends StatefulWidget {
  final dynamic video;
  const _YouTubeResultItem({required this.video});

  @override
  State<_YouTubeResultItem> createState() => _YouTubeResultItemState();
}

class _YouTubeResultItemState extends State<_YouTubeResultItem> {
  bool _justDownloaded = false;

  bool _isAlreadyDownloaded(BuildContext context) {
    if (_justDownloaded) return true;
    final library = context.watch<LibraryProvider>();
    final videoTitle = (widget.video['title'] ?? '').toString().toLowerCase();
    return library.tracks.any((t) {
      final trackTitle = t.title.toLowerCase();
      final trackFilename = t.filename.toLowerCase().replaceAll('.mp3', '').replaceAll('.m4a', '');
      // Match if title contains the track title or filename
      return videoTitle.contains(trackTitle) || 
             trackTitle.contains(videoTitle) ||
             trackFilename.contains(videoTitle) ||
             videoTitle.contains(trackFilename);
    });
  }

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final dur = (video['duration'] as num?)?.toInt();
    final durStr = dur != null ? '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}' : '--:--';
    final isDownloaded = _isAlreadyDownloaded(context);

    return _HoverContainer(
      onTap: () => _download(context, video),
      borderRadius: BorderRadius.circular(12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: video['thumbnail'] != null
                ? Image.network(video['thumbnail'], width: 80, height: 45, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width: 80, height: 45, color: context.colors.surfaceAlt))
                : Container(width: 80, height: 45, color: context.colors.surfaceAlt),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(video['title'] ?? 'Unknown', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.textPrimary, fontSize: 14)),
                const SizedBox(height: 2),
                Text('${video['channel']} • $durStr', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          isDownloaded
              ? Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Icon(Icons.check_circle_rounded, color: Colors.green.shade400, size: 22),
                )
              : IconButton(
                  icon: Icon(Icons.download_rounded, color: Theme.of(context).colorScheme.primary),
                  onPressed: () => _download(context, video),
                ),
        ],
      ),
    );
  }

  void _download(BuildContext context, dynamic video) async {
    final result = await showDialog<dynamic>(
      context: context,
      builder: (_) => DownloadOptionsDialog(videoUrl: video['url'], title: video['title']),
    );
    if (result != null && context.mounted) {
      if (result is String) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(child: Text('Advertencia: $result', style: const TextStyle(fontSize: 13))),
              ],
            ),
            backgroundColor: Colors.orange.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 4),
          ),
        );
      } else if (result == true) {
        setState(() => _justDownloaded = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                const Text('Descargada ✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      final settings = context.read<SettingsProvider>();
      context.read<LibraryProvider>().loadTracks(settings.api);
    }
  }
}

class _YouTubeShortItem extends StatelessWidget {
  final dynamic video;
  const _YouTubeShortItem({required this.video});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final result = await showDialog<dynamic>(
          context: context,
          builder: (_) => DownloadOptionsDialog(videoUrl: video['url'], title: video['title']),
        );
        if (result != null && context.mounted) {
          if (result is String) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Flexible(child: Text('Advertencia: $result', style: const TextStyle(fontSize: 13))),
                  ],
                ),
                backgroundColor: Colors.orange.shade700,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 4),
              ),
            );
          } else if (result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    const Text('Descargada ✓', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                  ],
                ),
                backgroundColor: Colors.green.shade700,
                behavior: SnackBarBehavior.floating,
                margin: const EdgeInsets.only(bottom: 80, left: 16, right: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                duration: const Duration(seconds: 2),
              ),
            );
          }
          final settings = context.read<SettingsProvider>();
          context.read<LibraryProvider>().loadTracks(settings.api);
        }
      },
      child: Container(
        width: 110,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: context.colors.surfaceAlt,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                child: SizedBox.expand(
                  child: video['thumbnail'] != null
                      ? Image.network(video['thumbnail'], width: double.infinity, height: double.infinity, fit: BoxFit.cover, errorBuilder: (_,__,___) => const SizedBox())
                      : const SizedBox(),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                video['title'] ?? 'Short',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: context.colors.textPrimary, fontSize: 11),
              ),
            )
          ],
        ),
      ),
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 64, color: context.colors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 16),
          Text('Escribe para buscar...', style: TextStyle(color: context.colors.textSecondary, fontSize: 18)),
        ],
      ),
    );
  }
}

class _HoverContainer extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;

  const _HoverContainer({
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(12)),
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
  });

  @override
  State<_HoverContainer> createState() => _HoverContainerState();
}

class _HoverContainerState extends State<_HoverContainer> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: widget.padding,
          decoration: BoxDecoration(
            color: _isHovered
                ? context.colors.textPrimary.withOpacity(0.05)
                : Colors.transparent,
            borderRadius: widget.borderRadius,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
