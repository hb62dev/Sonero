import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/csv_service.dart';
import '../theme.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final settings = context.read<SettingsProvider>();
    final selected = library.selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        _PageHeader(playlist: selected, tracks: library.tracks, settings: settings),

        const Divider(height: 1, color: AppTheme.border),

        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: library.loading
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent1))
              : library.tracks.isEmpty
                  ? _EmptyState(playlist: selected)
                  : _TrackGrid(tracks: library.tracks),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _PageHeader extends StatelessWidget {
  final Playlist playlist;
  final List<Track> tracks;
  final SettingsProvider settings;

  const _PageHeader({
    required this.playlist,
    required this.tracks,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                playlist.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${tracks.length} canción${tracks.length == 1 ? '' : 'es'}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Export CSV button (only for playlists, not library root)
          if (!playlist.isLibrary && tracks.isNotEmpty)
            _ExportButton(playlist: playlist, tracks: tracks, settings: settings),
          const SizedBox(width: 8),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: AppTheme.textSecondary,
            tooltip: 'Actualizar',
            onPressed: () {
              context.read<LibraryProvider>().loadTracks(settings.api);
            },
          ),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  final Playlist playlist;
  final List<Track> tracks;
  final SettingsProvider settings;

  const _ExportButton({
    required this.playlist,
    required this.tracks,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.download_outlined, size: 16),
      label: const Text('Exportar CSV', style: TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.accent2,
        side: const BorderSide(color: AppTheme.accent2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: () async {
        try {
          final path = await CsvService.exportPlaylistCsv(
            playlistName: playlist.name,
            tracks: tracks,
            outputDir: settings.musicFolder,
          );
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('CSV guardado: $path'),
                backgroundColor: AppTheme.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: AppTheme.error,
              ),
            );
          }
        }
      },
    );
  }
}

// ── Track grid ────────────────────────────────────────────────────────────────

class _TrackGrid extends StatelessWidget {
  final List<Track> tracks;
  const _TrackGrid({required this.tracks});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.78,
      ),
      itemCount: tracks.length,
      itemBuilder: (_, i) => _TrackCard(track: tracks[i]),
    );
  }
}

// ── Track card ────────────────────────────────────────────────────────────────

class _TrackCard extends StatefulWidget {
  final Track track;
  const _TrackCard({required this.track});

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onSecondaryTapUp: (d) => _showContextMenu(context, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered ? AppTheme.surfaceAlt : AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? AppTheme.accent1.withOpacity(0.5) : AppTheme.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: AppTheme.accent1.withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ]
                : [],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Cover / placeholder
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: track.coverUrl != null
                      ? Image.network(
                          track.coverUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          errorBuilder: (_, __, ___) => _CoverPlaceholder(),
                        )
                      : _CoverPlaceholder(),
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title.isNotEmpty ? track.title : track.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    if (track.artist.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final library = context.read<LibraryProvider>();
    final settings = context.read<SettingsProvider>();
    final playlists = library.playlists
        .where((p) => !p.isLibrary && p.name != widget.track.playlist)
        .toList();

    final action = await showMenu<String>(
      context: context,
      color: AppTheme.surfaceAlt,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx, position.dy),
      items: [
        const PopupMenuItem(
          enabled: false,
          child: Text('Mover a...',
              style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
        // Move to library root
        if (widget.track.playlist.isNotEmpty)
          const PopupMenuItem(
              value: '__root__', child: Text('Biblioteca (raíz)')),
        // Move to each playlist
        ...playlists.map(
          (pl) => PopupMenuItem(value: pl.name, child: Text(pl.name)),
        ),
      ],
    );

    if (action != null) {
      final toPlaylist = action == '__root__' ? null : action;
      await library.moveTrack(settings.api, widget.track, toPlaylist);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Movida a ${toPlaylist ?? 'Biblioteca'}'),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }
}

class _CoverPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: AppTheme.surfaceAlt,
        child: const Center(
          child: Icon(Icons.music_note_rounded,
              color: AppTheme.textSecondary, size: 36),
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final Playlist playlist;
  const _EmptyState({required this.playlist});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.library_music_outlined,
                color: AppTheme.textSecondary, size: 52),
            const SizedBox(height: 16),
            Text(
              playlist.isLibrary
                  ? 'Tu biblioteca está vacía'
                  : '${playlist.name} está vacía',
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text(
              'Presiona el atajo de teclado para reconocer una canción',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
}
