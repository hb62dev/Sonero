import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/player_provider.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../theme.dart';
import 'download_options_dialog.dart';

class SearchView extends StatefulWidget {
  final Function(int)? onNavigate;
  const SearchView({super.key, this.onNavigate});

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  Timer? _debounce;
  
  bool _isSearchingOnline = false;
  List<dynamic> _onlineResults = [];
  String? _onlineError;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() => _query = query);
    
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 1000), () {
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
      final results = await settings.api.searchOnline(query, limit: 20);
      if (mounted) {
        setState(() {
          _onlineResults = results;
          _isSearchingOnline = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final localResults = _getFilteredLocalTracks(library.tracks);
    final localPlaylists = _getFilteredPlaylists(library.playlists);
    
    // Split online results into normal videos and shorts
    final normalVideos = _onlineResults.where((r) => r['is_short'] != true).toList();
    final shortVideos = _onlineResults.where((r) => r['is_short'] == true).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header / Search Bar ───────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 32, 32, 16),
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            style: TextStyle(fontSize: 24, color: context.colors.textPrimary, fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: 'Buscar canciones, artistas, o YouTube...',
              hintStyle: TextStyle(color: context.colors.textSecondary.withOpacity(0.5)),
              prefixIcon: Icon(Icons.search_rounded, size: 32, color: context.colors.textSecondary),
              filled: true,
              fillColor: context.colors.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 20),
            ),
          ),
        ),

        Divider(height: 1, color: context.colors.border),

        // ── Results ───────────────────────────────────────────────────────
        Expanded(
          child: _query.trim().isEmpty
              ? _EmptySearchState()
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Local Results
                    Expanded(
                      flex: 1,
                      child: _LocalResultsColumn(tracks: localResults, playlists: localPlaylists, onNavigate: widget.onNavigate),
                    ),
                    Container(width: 1, color: context.colors.border),
                    // YouTube Results
                    Expanded(
                      flex: 1,
                      child: _YouTubeResultsColumn(
                        isLoading: _isSearchingOnline,
                        error: _onlineError,
                        normalVideos: normalVideos,
                        shortVideos: shortVideos,
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
                  child: track.coverUrl != null
                      ? Image.network(track.coverUrl!, width: 48, height: 48, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.music_note))
                      : Container(width: 48, height: 48, color: context.colors.surfaceAlt, child: const Icon(Icons.music_note)),
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

  const _YouTubeResultsColumn({
    required this.isLoading,
    required this.error,
    required this.normalVideos,
    required this.shortVideos,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary));
    }
    if (error != null) {
      return Center(child: Text('Error: $error', style: TextStyle(color: context.colors.error)));
    }
    if (normalVideos.isEmpty && shortVideos.isEmpty) {
      return Center(child: Text('No hay resultados en YouTube', style: TextStyle(color: context.colors.textSecondary)));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('YouTube', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
        const SizedBox(height: 16),
        ...normalVideos.map((v) => _YouTubeResultItem(video: v)),
        
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

class _YouTubeResultItem extends StatelessWidget {
  final dynamic video;
  const _YouTubeResultItem({required this.video});

  @override
  Widget build(BuildContext context) {
    final dur = (video['duration'] as num?)?.toInt();
    final durStr = dur != null ? '${dur ~/ 60}:${(dur % 60).toString().padLeft(2, '0')}' : '--:--';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: video['thumbnail'] != null
            ? Image.network(video['thumbnail'], width: 80, height: 45, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(width: 80, height: 45, color: context.colors.surfaceAlt))
            : Container(width: 80, height: 45, color: context.colors.surfaceAlt),
      ),
      title: Text(video['title'] ?? 'Unknown', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.textPrimary, fontSize: 14)),
      subtitle: Text('${video['channel']} • $durStr', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
      trailing: IconButton(
        icon: Icon(Icons.download_rounded, color: Theme.of(context).colorScheme.primary),
        onPressed: () => _download(context, video),
      ),
      onTap: () => _download(context, video),
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
          SnackBar(content: Text('Descarga completada con advertencias: $result'), backgroundColor: Colors.orange, duration: const Duration(seconds: 5)),
        );
      } else if (result == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Descarga completada'), backgroundColor: context.colors.success),
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
              SnackBar(content: Text('Descarga completada con advertencias: $result'), backgroundColor: Colors.orange, duration: const Duration(seconds: 5)),
            );
          } else if (result == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: const Text('Descarga completada'), backgroundColor: context.colors.success),
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
                child: video['thumbnail'] != null
                    ? Image.network(video['thumbnail'], width: double.infinity, fit: BoxFit.cover, errorBuilder: (_,__,___) => const SizedBox())
                    : const SizedBox(),
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
