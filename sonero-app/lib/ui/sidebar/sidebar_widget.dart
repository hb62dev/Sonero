import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:sonero_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/downloads_provider.dart';
import '../theme.dart';
import '../settings/settings_page.dart';
import '../video_download_dialog.dart';
import '../widgets/hover_scale.dart';
import '../widgets/app_logo.dart';

class SidebarWidget extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigate;
  final bool isCollapsed;
  final VoidCallback onToggle;

  const SidebarWidget({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
    required this.isCollapsed,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final settings = context.read<SettingsProvider>();
    final downloads = context.watch<DownloadsProvider>();
    final accent = Theme.of(context).colorScheme.primary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: isCollapsed ? 72 : 240,
      decoration: BoxDecoration(
        color: context.colors.sidebarBg ?? Color.lerp(context.colors.bg, Colors.black, 0.3),
      ),
      clipBehavior: Clip.hardEdge,
      child: ClipRect(
        child: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: SafeArea(
        left: false,
        right: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Brand Header ──────────────────────────────────────────────
            _BrandHeader(
              isCollapsed: isCollapsed,
              onToggle: onToggle,
            ),

            const SizedBox(height: 8),

            // ── Main Navigation ──────────────────────────────────────────
            _SectionLabel(label: 'MENÚ', isCollapsed: isCollapsed),
            const SizedBox(height: 4),
            _NavItem(
              key: const ValueKey('nav_home'),
              icon: Icons.home_rounded,
              label: AppLocalizations.of(context)!.navHome,
              isSelected: currentIndex == 0,
              isCollapsed: isCollapsed,
              onTap: () => onNavigate(0),
            ),
            _NavItem(
              key: const ValueKey('nav_analytics'),
              icon: Icons.insights_rounded,
              label: AppLocalizations.of(context)!.navAnalytics,
              isSelected: currentIndex == 2,
              isCollapsed: isCollapsed,
              onTap: () => onNavigate(2),
            ),
            _NavItem(
              key: const ValueKey('nav_search'),
              icon: Icons.search_rounded,
              label: 'Buscador',
              isSelected: currentIndex == 3,
              isCollapsed: isCollapsed,
              onTap: () => onNavigate(3),
            ),
            _NavItem(
              key: const ValueKey('nav_download'),
              icon: Icons.download_rounded,
              label: AppLocalizations.of(context)!.navDownload,
              isSelected: false,
              isCollapsed: isCollapsed,
              onTap: () {
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
              },
            ),
            _NavItem(
              key: const ValueKey('nav_active_downloads'),
              icon: downloads.activeJobsCount > 0 ? Icons.downloading_rounded : Icons.download_done_rounded,
              label: AppLocalizations.of(context)!.navActiveDownloads,
              isSelected: currentIndex == 4,
              isCollapsed: isCollapsed,
              badgeCount: downloads.activeJobsCount,
              onTap: () => onNavigate(4),
            ),
            _NavItem(
              key: const ValueKey('nav_wifi_share'),
              icon: Icons.wifi_tethering_rounded,
              label: AppLocalizations.of(context)!.navShare,
              isSelected: currentIndex == 5,
              isCollapsed: isCollapsed,
              onTap: () => onNavigate(5),
            ),

            const SizedBox(height: 12),

            // ── Library section ──────────────────────────────────────────
            _SectionLabel(label: 'BIBLIOTECA', isCollapsed: isCollapsed),
            const SizedBox(height: 4),

            // ── Playlists list ───────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  for (final pl in library.playlists)
                    _PlaylistTile(
                      key: ValueKey('playlist_${pl.name}'),
                      playlist: pl,
                      isSelected: library.selected.name == pl.name,
                      isCollapsed: isCollapsed,
                      onTap: () {
                        onNavigate(1);
                        library.selectPlaylist(settings.api, pl);
                      },
                      onDelete: pl.isLibrary
                          ? null
                          : () => _confirmDelete(context, library, settings, pl),
                      onRename: pl.isLibrary
                          ? null
                          : () => _renameDialog(context, library, settings, pl),
                    ),
                ],
              ),
            ),

            // ── Bottom actions ───────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.colors.border.withOpacity(0.3)),
                ),
              ),
              child: Column(
                children: [
                  _NavItem(
                    key: const ValueKey('nav_settings'),
                    icon: Icons.settings_rounded,
                    label: AppLocalizations.of(context)!.settings,
                    isSelected: false,
                    isCollapsed: isCollapsed,
                    onTap: () => _openSettings(context),
                    compact: true,
                  ),
                  const SizedBox(height: 6),
                  _ThemeToggle(isCollapsed: isCollapsed),
                  const SizedBox(height: 6),
                  _NewPlaylistButton(
                    isCollapsed: isCollapsed,
                    onPressed: () => _createDialog(context, library, settings),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
      ),
      ),
    );
  }

  void _openSettings(BuildContext context) {
    try {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SettingsPage()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Configuración no disponible en esta plataforma: $e')),
      );
    }
  }

  Future<void> _createDialog(
    BuildContext context,
    LibraryProvider library,
    SettingsProvider settings,
  ) async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.colors.surfaceAlt,
        title: Text(AppLocalizations.of(context)!.newPlaylist),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: AppLocalizations.of(context)!.newPlaylistHint),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await library.createPlaylist(settings.api, name.trim());
    }
  }

  Future<void> _renameDialog(
    BuildContext context,
    LibraryProvider library,
    SettingsProvider settings,
    Playlist pl,
  ) async {
    final ctrl = TextEditingController(text: pl.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.colors.surfaceAlt,
        title: Text(AppLocalizations.of(context)!.renamePlaylist),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: AppLocalizations.of(context)!.newPlaylistName),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.cancel)),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(AppLocalizations.of(context)!.rename),
          ),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty && newName != pl.name) {
      await library.renamePlaylist(settings.api, pl.name, newName.trim());
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    LibraryProvider library,
    SettingsProvider settings,
    Playlist pl,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.colors.surfaceAlt,
        title: Text(AppLocalizations.of(context)!.deletePlaylist),
        content: Text(
          AppLocalizations.of(context)!.deletePlaylistConfirm(pl.name),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.cancel)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await library.deletePlaylist(settings.api, pl.name);
    }
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _BrandHeader extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;

  const _BrandHeader({required this.isCollapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    if (isCollapsed) {
      // Collapsed: logo + expand arrow stacked vertically
      return Container(
        height: 92,
        padding: const EdgeInsets.only(top: 12),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: accent.withOpacity(0.25),
                      width: 1,
                    ),
                  ),
                  child: const AppLogo(size: 40, borderRadius: 12),
                ),
              ),
            ),
            const SizedBox(height: 14),
            // Expand arrow
            GestureDetector(
              onTap: onToggle,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(
                    Icons.keyboard_double_arrow_right_rounded,
                    size: 16,
                    color: context.colors.textSecondary.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Expanded: logo + title + collapse arrow in a row
    return Container(
      height: 72,
      padding: const EdgeInsets.only(left: 16, right: 16, top: 10),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          // Logo
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: accent.withOpacity(0.25),
                    width: 1,
                  ),
                ),
                child: const AppLogo(size: 40, borderRadius: 12),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppLocalizations.of(context)!.appTitle,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  'Music Player',
                  style: TextStyle(
                    color: context.colors.textSecondary.withOpacity(0.5),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onToggle,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Icon(
                Icons.keyboard_double_arrow_left_rounded,
                size: 18,
                color: context.colors.textSecondary.withOpacity(0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final bool isCollapsed;
  const _SectionLabel({required this.label, required this.isCollapsed});

  @override
  Widget build(BuildContext context) {
    if (isCollapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Divider(height: 1, color: context.colors.border.withOpacity(0.3)),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          color: context.colors.textSecondary.withOpacity(0.4),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 2.0,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _PlaylistTile extends StatefulWidget {
  final Playlist playlist;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  const _PlaylistTile({
    super.key,
    required this.playlist,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    this.onDelete,
    this.onRename,
  });

  @override
  State<_PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends State<_PlaylistTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isSelected = widget.isSelected;

    Widget leadingIcon;
    if (widget.playlist.isLibrary) {
      leadingIcon = Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isSelected ? accent.withOpacity(0.15) : context.colors.border.withOpacity(0.3),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.library_music_rounded,
          size: 16,
          color: isSelected ? accent : context.colors.textSecondary,
        ),
      );
    } else {
      final nameLC = widget.playlist.name.toLowerCase();
      final bool isVideoPlaylist = nameLC.contains('video');
      final initial = widget.playlist.name.isNotEmpty ? widget.playlist.name[0].toUpperCase() : '?';
      final hasCover = widget.playlist.coverUrl != null && widget.playlist.coverUrl!.isNotEmpty;

      if (hasCover) {
        final settings = context.read<SettingsProvider>();
        final imageUrl = widget.playlist.coverUrl!.startsWith('file://')
            ? widget.playlist.coverUrl!
            : '${settings.apiUrl}${widget.playlist.coverUrl}';
        leadingIcon = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            imageUrl,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.colors.border.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(initial, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: context.colors.textSecondary)),
            ),
          ),
        );
      } else {
        leadingIcon = Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(colors: [accent.withOpacity(0.3), accent.withOpacity(0.1)])
                : null,
            color: isSelected ? null : context.colors.border.withOpacity(0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: isVideoPlaylist
              ? Icon(
                  Icons.play_circle_rounded,
                  size: 18,
                  color: isSelected ? accent : context.colors.textSecondary,
                )
              : Text(
                  initial,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? accent : context.colors.textSecondary,
                  ),
                ),
        );
      }
    }

    return Tooltip(
      message: widget.isCollapsed ? widget.playlist.name : '',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onSecondaryTapUp: (details) => _showContextMenu(context, details.globalPosition),
          onLongPress: () async {
                  final RenderBox box = context.findRenderObject() as RenderBox;
                  final pos = box.localToGlobal(Offset.zero);
                  _showContextMenu(context, Offset(pos.dx + box.size.width / 2, pos.dy));
                },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            margin: EdgeInsets.symmetric(horizontal: widget.isCollapsed ? 12 : 12, vertical: 1),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: BorderRadius.circular(10),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 42,
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accent.withOpacity(0.1)
                        : _isHovered
                            ? context.colors.textPrimary.withOpacity(0.04)
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: isSelected
                        ? Border.all(color: accent.withOpacity(0.15), width: 1)
                        : null,
                  ),
                  padding: EdgeInsets.symmetric(horizontal: widget.isCollapsed ? 0 : 8),
                  alignment: widget.isCollapsed ? Alignment.center : Alignment.centerLeft,
                  child: Row(
                    mainAxisAlignment: widget.isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      leadingIcon,
                      if (!widget.isCollapsed) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.playlist.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected ? context.colors.textPrimary : context.colors.textSecondary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (widget.playlist.trackCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: context.colors.border.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${widget.playlist.trackCount}',
                              style: TextStyle(
                                color: context.colors.textSecondary.withOpacity(0.6),
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        // 3-dot menu button
                        if (_isHovered || MediaQuery.of(context).size.width < 600)
                          GestureDetector(
                            onTap: () {
                              final RenderBox box = context.findRenderObject() as RenderBox;
                              final pos = box.localToGlobal(Offset(box.size.width, box.size.height / 2));
                              _showContextMenu(context, pos);
                            },
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.more_vert_rounded,
                                size: 16,
                                color: context.colors.textSecondary.withOpacity(0.5),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: context.colors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'cover',
          child: Row(
            children: [
              Icon(Icons.image_rounded, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 10),
              const Text('Subir imagen'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'cover_from_track',
          child: Row(
            children: [
              Icon(Icons.album_rounded, size: 18, color: context.colors.textSecondary),
              const SizedBox(width: 10),
              const Text('Usar portada de canción'),
            ],
          ),
        ),
        if (widget.onRename != null)
          PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                Icon(Icons.edit_rounded, size: 18, color: context.colors.textSecondary),
                const SizedBox(width: 10),
                Text(AppLocalizations.of(context)!.rename),
              ],
            ),
          ),
        if (widget.onDelete != null)
          PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded, size: 18, color: context.colors.error),
                const SizedBox(width: 10),
                Text(AppLocalizations.of(context)!.delete, style: TextStyle(color: context.colors.error)),
              ],
            ),
          ),
      ],
    );
    if (!mounted) return;
    if (action == 'rename') widget.onRename?.call();
    if (action == 'delete') widget.onDelete?.call();
    if (action == 'cover') _pickAndUploadCover(context);
    if (action == 'cover_from_track') _showPickCoverFromTrack(context);
  }

  void _showPickCoverFromTrack(BuildContext context) {
    final library = context.read<LibraryProvider>();
    final settings = context.read<SettingsProvider>();
    final playlistName = widget.playlist.name;

    // Get tracks that belong to this playlist and have cover art
    final tracksWithCover = library.tracks
        .where((t) => t.playlist == playlistName && t.coverUrl != null && t.coverUrl!.isNotEmpty)
        .toList();

    if (tracksWithCover.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('No hay canciones con portada en esta carpeta'),
          backgroundColor: context.colors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.album_rounded, color: Theme.of(context).colorScheme.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Elegir portada', style: TextStyle(color: context.colors.textPrimary, fontSize: 16)),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          height: 300,
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: tracksWithCover.length,
            itemBuilder: (ctx, index) {
              final track = tracksWithCover[index];
              final coverFullUrl = track.coverUrl!.startsWith('http')
                  ? track.coverUrl!
                  : '${settings.apiUrl}${track.coverUrl}';
              return Tooltip(
                message: '${track.title}\n${track.artist}',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _uploadCoverFromTrackUrl(context, coverFullUrl);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          coverFullUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: context.colors.surfaceAlt,
                            child: Icon(Icons.broken_image_rounded, color: context.colors.textSecondary),
                          ),
                        ),
                        // Gradient overlay with track name
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black87, Colors.transparent],
                              ),
                            ),
                            child: Text(
                              track.title.isNotEmpty ? track.title : track.filename,
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancelar', style: TextStyle(color: context.colors.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _uploadCoverFromTrackUrl(BuildContext context, String coverUrl) async {
    try {
      // Download the track's cover image
      final response = await http.get(Uri.parse(coverUrl));
      if (response.statusCode != 200) throw Exception('No se pudo obtener la imagen');

      final settings = context.read<SettingsProvider>();
      final playlistName = widget.playlist.name;
      final uri = Uri.parse('${settings.apiUrl}/api/v1/playlists/$playlistName/cover');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        response.bodyBytes,
        filename: 'cover.jpg',
      ));

      final uploadResponse = await request.send();
      if (uploadResponse.statusCode == 200 && mounted) {
        context.read<LibraryProvider>().loadPlaylists(settings.api);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Portada actualizada'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _pickAndUploadCover(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      if (file.bytes == null) return;

      final settings = context.read<SettingsProvider>();
      final playlistName = widget.playlist.name;
      final uri = Uri.parse('${settings.apiUrl}/api/v1/playlists/$playlistName/cover');

      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        file.bytes!,
        filename: file.name,
      ));

      final response = await request.send();
      if (response.statusCode == 200 && mounted) {
        // Refresh playlists to show new cover
        context.read<LibraryProvider>().loadPlaylists(settings.api);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('✅ Portada actualizada'),
            backgroundColor: Theme.of(context).colorScheme.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al subir portada (${response.statusCode})'),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: context.colors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

class _NewPlaylistButton extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onPressed;
  const _NewPlaylistButton({required this.isCollapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    if (isCollapsed) {
      return Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: accent.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.add_rounded, size: 18, color: accent),
            ),
          ),
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [accent.withOpacity(0.12), accent.withOpacity(0.05)],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: accent.withOpacity(0.2)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_rounded, size: 16, color: accent),
              const SizedBox(width: 6),
              Text(
                AppLocalizations.of(context)!.newPlaylist,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;
  final int badgeCount;
  final bool compact;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
    this.badgeCount = 0,
    this.compact = false,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final isSelected = widget.isSelected;

    return Tooltip(
      message: widget.isCollapsed ? widget.label : '',
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.compact ? 0 : 1),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(10),
              hoverColor: Colors.transparent,
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              focusColor: Colors.transparent,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: widget.compact ? 42 : 40,
                width: widget.isCollapsed ? (widget.compact ? 42 : 40) : null,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: isSelected
                      ? accent.withOpacity(0.1)
                      : _isHovered
                          ? context.colors.textPrimary.withOpacity(0.06)
                          : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected
                      ? Border.all(color: accent.withOpacity(0.15), width: 1)
                      : null,
                ),
                padding: EdgeInsets.symmetric(horizontal: widget.isCollapsed ? 0 : 14),
                alignment: widget.isCollapsed ? Alignment.center : Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: widget.isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          widget.icon,
                          size: 20,
                          color: isSelected ? accent : context.colors.textSecondary.withOpacity(0.7),
                        ),
                        if (widget.badgeCount > 0)
                          Positioned(
                            right: -6,
                            top: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                              child: Text(
                                '${widget.badgeCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!widget.isCollapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected
                                ? context.colors.textPrimary
                                : context.colors.textSecondary.withOpacity(0.8),
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Active indicator
                      if (isSelected)
                        Container(
                          width: 3,
                          height: 16,
                          decoration: BoxDecoration(
                            color: accent,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThemeToggle extends StatelessWidget {
  final bool isCollapsed;
  const _ThemeToggle({required this.isCollapsed});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isDark = settings.themeMode == ThemeMode.dark || 
        (settings.themeMode == ThemeMode.system && 
         MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    final accent = Theme.of(context).colorScheme.primary;

    if (isCollapsed) {
      // Collapsed: just an icon button
      return Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => settings.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 40,
              height: 36,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: context.colors.border.withOpacity(0.2),
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                size: 18,
                color: isDark ? Colors.amber.shade300 : Colors.orange.shade400,
              ),
            ),
          ),
        ),
      );
    }

    // Expanded: label + toggle switch
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: context.colors.border.withOpacity(0.15),
        ),
        child: Row(
          children: [
            Icon(
              isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
              size: 18,
              color: isDark ? Colors.amber.shade300 : Colors.orange.shade400,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isDark ? 'Modo Oscuro' : 'Modo Claro',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: context.colors.textSecondary.withOpacity(0.8),
                ),
              ),
            ),
            SizedBox(
              height: 24,
              width: 40,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Switch(
                  value: isDark,
                  onChanged: (val) => settings.setThemeMode(val ? ThemeMode.dark : ThemeMode.light),
                  activeColor: accent,
                  activeTrackColor: accent.withOpacity(0.3),
                  inactiveThumbColor: Colors.orange.shade300,
                  inactiveTrackColor: Colors.orange.shade100.withOpacity(0.3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
