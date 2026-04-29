import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';
import '../settings/settings_page.dart';
import '../video_download_dialog.dart';
import '../widgets/hover_scale.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SidebarWidget extends StatefulWidget {
  final int currentIndex;
  final ValueChanged<int> onNavigate;

  const SidebarWidget({
    super.key,
    required this.currentIndex,
    required this.onNavigate,
  });

  @override
  State<SidebarWidget> createState() => _SidebarWidgetState();
}

class _SidebarWidgetState extends State<SidebarWidget> {
  bool isCollapsed = false;

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final settings = context.read<SettingsProvider>();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      width: isCollapsed ? 64 : 220,
      color: context.colors.sidebarBg ?? context.colors.surface,
      clipBehavior: Clip.hardEdge,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          _Header(
            isCollapsed: isCollapsed,
            onToggle: () => setState(() => isCollapsed = !isCollapsed),
          ),

          Divider(height: 1, color: context.colors.border),

          // ── Main Navigation ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                _NavItem(
                  key: const ValueKey('nav_home'),
                  icon: Icons.home_filled,
                  label: AppLocalizations.of(context)!.navHome,
                  isSelected: widget.currentIndex == 0,
                  isCollapsed: isCollapsed,
                  onTap: () => widget.onNavigate(0),
                ),
                _NavItem(
                  key: const ValueKey('nav_analytics'),
                  icon: Icons.analytics_outlined,
                  label: AppLocalizations.of(context)!.navAnalytics,
                  isSelected: widget.currentIndex == 2,
                  isCollapsed: isCollapsed,
                  onTap: () => widget.onNavigate(2),
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
                    ).then((success) {
                      if (success == true) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(AppLocalizations.of(context)!.downloadComplete)),
                        );
                        final settings = context.read<SettingsProvider>();
                        context.read<LibraryProvider>().loadTracks(settings.api);
                      }
                    });
                  },
                ),
              ],
            ),
          ),

          Divider(height: 1, color: context.colors.border),

          // ── Playlists list ─────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                if (!isCollapsed)
                  _SectionLabel(AppLocalizations.of(context)!.librarySection),
                for (final pl in library.playlists)
                  _PlaylistTile(
                    key: ValueKey('playlist_${pl.name}'),
                    playlist: pl,
                    isSelected: library.selected.name == pl.name,
                    isCollapsed: isCollapsed,
                    onTap: () {
                      widget.onNavigate(1); // Switch to library view
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

          Divider(height: 1, color: context.colors.border),

          // ── Settings & New playlist button ──────────────────────────────
          _NavItem(
            key: const ValueKey('nav_settings'),
            icon: Icons.settings_outlined,
            label: AppLocalizations.of(context)!.settings,
            isSelected: false,
            isCollapsed: isCollapsed,
            onTap: () => _openSettings(context),
          ),
          
          _NewPlaylistButton(
            isCollapsed: isCollapsed,
            onPressed: () => _createDialog(context, library, settings),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SettingsPage()),
    );
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

class _Header extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onToggle;

  const _Header({required this.isCollapsed, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 20 : 16),
      child: Row(
        mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          IconButton(
            icon: Icon(Icons.menu, size: 20),
            color: context.colors.textPrimary,
            onPressed: onToggle,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: AppLocalizations.of(context)!.appTitle,
          ),
          if (!isCollapsed) ...[
            const SizedBox(width: 12),
            ShaderMask(
              shaderCallback: (b) => context.colors.gradient.createShader(b),
              child: Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppLocalizations.of(context)!.appTitle,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          label,
          style: TextStyle(
            color: context.colors.textSecondary,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      );
}

class _PlaylistTile extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final color = isSelected ? Theme.of(context).colorScheme.primary : context.colors.textSecondary;
    
    Widget leadingIcon;
    if (playlist.isLibrary) {
      leadingIcon = Icon(Icons.library_music_outlined, size: 20, color: color);
    } else {
      final initial = playlist.name.isNotEmpty ? playlist.name[0].toUpperCase() : '?';
      leadingIcon = Container(
        width: 20,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.2) : context.colors.border,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: isSelected ? color : context.colors.textPrimary,
          ),
        ),
      );
    }

    return Tooltip(
      message: isCollapsed ? playlist.name : '',
      waitDuration: const Duration(milliseconds: 500),
      child: HoverScale(
        scale: 1.02,
        child: GestureDetector(
          onSecondaryTapUp: (onDelete != null || onRename != null)
              ? (details) => _showContextMenu(context, details.globalPosition)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 0 : 8),
                  alignment: isCollapsed ? Alignment.center : Alignment.centerLeft,
                  child: Row(
                    mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                    children: [
                      leadingIcon,
                      if (!isCollapsed) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            playlist.name,
                            style: TextStyle(
                              fontSize: 13,
                              color: isSelected ? context.colors.textPrimary : context.colors.textSecondary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (playlist.trackCount > 0)
                          Text(
                            '${playlist.trackCount}',
                            style: TextStyle(
                              color: context.colors.textSecondary,
                              fontSize: 11,
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
      items: [
        if (onRename != null)
          PopupMenuItem(value: 'rename', child: Text(AppLocalizations.of(context)!.rename)),
        if (onDelete != null)
          PopupMenuItem(value: 'delete',
            child: Text(AppLocalizations.of(context)!.delete, style: TextStyle(color: context.colors.error)),
          ),
      ],
    );
    if (action == 'rename') onRename?.call();
    if (action == 'delete') onDelete?.call();
  }
}

class _NewPlaylistButton extends StatelessWidget {
  final bool isCollapsed;
  final VoidCallback onPressed;
  const _NewPlaylistButton({required this.isCollapsed, required this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: SizedBox(
          width: double.infinity,
          height: 36,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: EdgeInsets.zero,
            ),
            onPressed: onPressed,
            child: Tooltip(
              message: isCollapsed ? AppLocalizations.of(context)!.newPlaylist : '',
              waitDuration: const Duration(milliseconds: 500),
              child: isCollapsed
                  ? Icon(Icons.add, size: 18)
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, size: 16),
                        const SizedBox(width: 8),
                        Text(AppLocalizations.of(context)!.newPlaylist, style: TextStyle(fontSize: 13)),
                      ],
                    ),
            ),
          ),
        ),
      );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onTap;

  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.isCollapsed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isCollapsed ? label : '',
      waitDuration: const Duration(milliseconds: 500),
      child: HoverScale(
        scale: 1.02,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).colorScheme.primary.withOpacity(0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(horizontal: isCollapsed ? 0 : 8),
                alignment: isCollapsed ? Alignment.center : Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: isCollapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
                  children: [
                    Icon(
                      icon,
                      size: 20,
                      color: isSelected ? Theme.of(context).colorScheme.primary : context.colors.textSecondary,
                    ),
                    if (!isCollapsed) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isSelected ? context.colors.textPrimary : context.colors.textSecondary,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
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
