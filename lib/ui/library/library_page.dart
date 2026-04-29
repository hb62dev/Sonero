import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/player_provider.dart';
import '../../core/csv_service.dart';
import '../theme.dart';
import 'metadata_dialog.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  bool _isListView = false;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final settings = context.read<SettingsProvider>();
    final selected = library.selected;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        _PageHeader(
          playlist: selected, 
          tracks: library.tracks, 
          settings: settings,
          isListView: _isListView,
          onToggleView: () => setState(() => _isListView = !_isListView),
        ),

        Divider(height: 1, color: context.colors.border),

        // ── Content ───────────────────────────────────────────────────────
        Expanded(
          child: library.loading
              ? Center(
                  child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
              : library.tracks.isEmpty
                  ? _EmptyState(playlist: selected)
                  : _isListView 
                      ? _TrackList(tracks: library.tracks)
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
  final bool isListView;
  final VoidCallback onToggleView;

  const _PageHeader({
    required this.playlist,
    required this.tracks,
    required this.settings,
    required this.isListView,
    required this.onToggleView,
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
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${tracks.length} canción${tracks.length == 1 ? '' : 'es'}',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const Spacer(),
          // Export CSV button (only for playlists, not library root)
          // AutoFill Button
          if (tracks.isNotEmpty)
            _AutoFillButton(tracks: tracks, settings: settings),
          if (tracks.isNotEmpty && !playlist.isLibrary)
            const SizedBox(width: 8),
          // Export CSV button (only for playlists, not library root)
          if (!playlist.isLibrary && tracks.isNotEmpty)
            _ExportButton(playlist: playlist, tracks: tracks, settings: settings),
          const SizedBox(width: 8),
          // View Toggle Button
          IconButton(
            icon: Icon(isListView ? Icons.grid_view_rounded : Icons.list_rounded),
            color: context.colors.textSecondary,
            tooltip: isListView ? 'Vista de Cuadrícula' : 'Vista de Lista',
            onPressed: onToggleView,
          ),
          const SizedBox(width: 8),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: context.colors.textSecondary,
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

class _AutoFillButton extends StatefulWidget {
  final List<Track> tracks;
  final SettingsProvider settings;

  const _AutoFillButton({
    required this.tracks,
    required this.settings,
  });

  @override
  State<_AutoFillButton> createState() => _AutoFillButtonState();
}

class _AutoFillButtonState extends State<_AutoFillButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: _isLoading 
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.auto_fix_high, size: 16),
      label: Text('Autocompletar Metadatos', style: const TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.primary,
        side: BorderSide(color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      onPressed: _isLoading ? null : () async {
        setState(() => _isLoading = true);
        try {
          final filenames = widget.tracks.map((t) => t.filename).toList();
          final jobId = await widget.settings.api.autoFillMetadata(filenames);
          
          if (context.mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => _AutofillProgressDialog(jobId: jobId, settings: widget.settings),
            );
            context.read<LibraryProvider>().loadTracks(widget.settings.api);
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'),
              backgroundColor: context.colors.error,
            ));
          }
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
      },
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
      icon: Icon(Icons.download_outlined, size: 16),
      label: Text('Exportar CSV', style: TextStyle(fontSize: 13)),
      style: OutlinedButton.styleFrom(
        foregroundColor: Theme.of(context).colorScheme.secondary,
        side: BorderSide(color: Theme.of(context).colorScheme.secondary),
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
                backgroundColor: context.colors.success,
              ),
            );
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error: $e'),
                backgroundColor: context.colors.error,
              ),
            );
          }
        }
      },
    );
  }
}

// ── Track list ────────────────────────────────────────────────────────────────

class _TrackList extends StatelessWidget {
  final List<Track> tracks;
  const _TrackList({required this.tracks});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: tracks.length,
      itemBuilder: (_, i) => _TrackListRow(track: tracks[i]),
    );
  }
}

class _TrackListRow extends StatefulWidget {
  final Track track;
  const _TrackListRow({required this.track});

  @override
  State<_TrackListRow> createState() => _TrackListRowState();
}

class _TrackListRowState extends State<_TrackListRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () async {
          try {
            final settings = context.read<SettingsProvider>();
            final library = context.read<LibraryProvider>();
            await context.read<PlayerProvider>().playTrack(track, library.tracks, settings.musicFolder);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: context.colors.error,
                duration: const Duration(seconds: 4),
              ));
            }
          }
        },
        onSecondaryTapUp: (d) => _showTrackContextMenu(context, track, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: _hovered ? context.colors.surfaceAlt : context.colors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _hovered ? Theme.of(context).colorScheme.primary.withOpacity(0.3) : context.colors.border,
            ),
          ),
          child: Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: track.coverUrl != null
                      ? Image.network(
                          track.coverUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _CoverPlaceholderSmall(),
                        )
                      : _CoverPlaceholderSmall(),
                ),
              ),
              const SizedBox(width: 16),
              // Title & Artist
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      track.title.isNotEmpty ? track.title : track.filename,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: context.colors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    if (track.artist.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Album
              Expanded(
                flex: 2,
                child: Text(
                  track.album,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                ),
              ),
              // Year
              SizedBox(
                width: 60,
                child: Text(
                  track.year,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
                ),
              ),
              // Options Menu Button
              IconButton(
                icon: const Icon(Icons.more_horiz),
                color: context.colors.textSecondary,
                onPressed: () {
                  final renderBox = context.findRenderObject() as RenderBox;
                  final position = renderBox.localToGlobal(Offset(renderBox.size.width, renderBox.size.height / 2));
                  _showTrackContextMenu(context, track, position);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CoverPlaceholderSmall extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: context.colors.surfaceAlt,
        child: Center(
          child: Icon(Icons.music_note_rounded,
              color: context.colors.textSecondary, size: 20),
        ),
      );
}

// ── Track context menu ────────────────────────────────────────────────────────
void _showTrackContextMenu(BuildContext context, Track track, Offset position) async {
  final library = context.read<LibraryProvider>();
  final settings = context.read<SettingsProvider>();
  final playlists = library.playlists
      .where((p) => !p.isLibrary && p.name != track.playlist)
      .toList();

  final action = await showMenu<String>(
    context: context,
    color: context.colors.surfaceAlt,
    position: RelativeRect.fromLTRB(
        position.dx, position.dy, position.dx, position.dy),
    items: [
      const PopupMenuItem(
        value: '__edit__',
        child: Text('Editar metadatos'),
      ),
      const PopupMenuItem(
        value: '__auto__',
        child: Text('Autocompletar metadatos (API)'),
      ),
      PopupMenuItem(
        value: '__delete__',
        child: Text('Eliminar archivo', style: TextStyle(color: context.colors.error)),
      ),
      const PopupMenuDivider(),
      PopupMenuItem(enabled: false,
        child: Text('Mover a...',
            style: TextStyle(
                color: context.colors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
      // Move to library root
      if (track.playlist.isNotEmpty)
        const PopupMenuItem(
            value: '__root__', child: Text('Biblioteca (raíz)')),
      // Move to each playlist
      ...playlists.map(
        (pl) => PopupMenuItem(value: pl.name, child: Text(pl.name)),
      ),
    ],
  );

  if (action != null) {
    if (action == '__edit__') {
      final changed = await showDialog<bool>(
        context: context,
        builder: (_) => MetadataDialog(track: track),
      );
      if (changed == true && context.mounted) {
        context.read<LibraryProvider>().loadTracks(settings.api);
      }
      return;
    }

    if (action == '__auto__') {
      try {
        final jobId = await settings.api.autoFillMetadata([track.filename]);
        if (context.mounted) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => _AutofillProgressDialog(jobId: jobId, settings: settings),
          );
          context.read<LibraryProvider>().loadTracks(settings.api);
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error: $e'),
            backgroundColor: context.colors.error,
          ));
        }
      }
      return;
    }

    if (action == '__delete__') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Eliminar canción'),
          content: Text('¿Seguro que quieres eliminar "${track.title.isNotEmpty ? track.title : track.filename}" del disco?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Eliminar', style: TextStyle(color: context.colors.error)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        try {
          await library.deleteTrack(settings.api, track);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Archivo eliminado'),
              backgroundColor: context.colors.success,
              duration: const Duration(seconds: 2),
            ));
          }
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Error: $e'),
              backgroundColor: context.colors.error,
            ));
          }
        }
      }
      return;
    }

    final toPlaylist = action == '__root__' ? null : action;
    await library.moveTrack(settings.api, track, toPlaylist);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Movida a ${toPlaylist ?? 'Biblioteca'}'),
        backgroundColor: context.colors.success,
        duration: const Duration(seconds: 2),
      ));
    }
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
        onTap: () async {
          try {
            final settings = context.read<SettingsProvider>();
            final library = context.read<LibraryProvider>();
            await context.read<PlayerProvider>().playTrack(track, library.tracks, settings.musicFolder);
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(e.toString().replaceAll('Exception: ', '')),
                backgroundColor: context.colors.error,
                duration: const Duration(seconds: 4),
              ));
            }
          }
        },
        onSecondaryTapUp: (d) => _showTrackContextMenu(context, track, d.globalPosition),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: _hovered ? context.colors.surfaceAlt : context.colors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered ? Theme.of(context).colorScheme.primary.withOpacity(0.5) : context.colors.border,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                      blurRadius: 8,
                      spreadRadius: 0,
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
                      style: TextStyle(
                        color: context.colors.textPrimary,
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
                        style: TextStyle(
                          color: context.colors.textSecondary,
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
}

class _CoverPlaceholder extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        color: context.colors.surfaceAlt,
        child: Center(
          child: Icon(Icons.music_note_rounded,
              color: context.colors.textSecondary, size: 36),
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
            Icon(Icons.library_music_outlined,
                color: context.colors.textSecondary, size: 52),
            const SizedBox(height: 16),
            Text(
              playlist.isLibrary
                  ? 'Tu biblioteca está vacía'
                  : '${playlist.name} está vacía',
              style: TextStyle(
                  color: context.colors.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'Presiona el atajo de teclado para reconocer una canción',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
      );
}

class _AutofillProgressDialog extends StatefulWidget {
  final String jobId;
  final SettingsProvider settings;
  const _AutofillProgressDialog({required this.jobId, required this.settings});

  @override
  State<_AutofillProgressDialog> createState() => _AutofillProgressDialogState();
}

class _AutofillProgressDialogState extends State<_AutofillProgressDialog> {
  double _progress = 0.0;
  String _step = 'Iniciando escaneo...';
  String? _errorMessage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _startPolling() {
    _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      try {
        final status = await widget.settings.api.getAutofillJobStatus(widget.jobId);
        if (!mounted) {
          timer.cancel();
          return;
        }
        
        final total = status['total'] as int? ?? 1;
        final completed = status['completed'] as int? ?? 0;
        final failed = status['failed'] as int? ?? 0;
        
        setState(() {
          _progress = total > 0 ? (completed + failed) / total : 0;
          _step = status['current'] ?? '';
        });

        if (status['status'] == 'done' || status['status'] == 'failed') {
          timer.cancel();
          if (mounted) {
            Navigator.of(context).pop(true);
          }
        }
      } catch (e) {
        timer.cancel();
        if (mounted) {
          setState(() {
            _errorMessage = e.toString();
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Escaneando Metadatos'),
      content: SizedBox(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red))
            else ...[
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 16),
              Text(_step, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        if (_errorMessage != null || _progress >= 1.0)
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cerrar')),
      ],
    );
  }
}




