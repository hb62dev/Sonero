import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../providers/library_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';
import '../settings/settings_page.dart';

class SidebarWidget extends StatelessWidget {
  const SidebarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final settings = context.read<SettingsProvider>();

    return Container(
      width: 220,
      color: context.colors.sidebarBg ?? context.colors.surface,
      child: Column(
        children: [
          // ── Header ─────────────────────────────────────────────────────
          _Header(onSettings: () => _openSettings(context)),

          Divider(height: 1, color: context.colors.border),

          // ── Playlists list ─────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _SectionLabel('LIBRERÍA'),
                for (final pl in library.playlists)
                  _PlaylistTile(
                    playlist: pl,
                    isSelected: library.selected.name == pl.name,
                    onTap: () => library.selectPlaylist(settings.api, pl),
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

          // ── New playlist button ─────────────────────────────────────────
          _NewPlaylistButton(
            onPressed: () => _createDialog(context, library, settings),
          ),
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
        title: Text('Nueva Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nombre de la playlist'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text('Crear'),
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
        title: Text('Renombrar Playlist'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nuevo nombre'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text('Renombrar'),
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
        title: Text('Eliminar Playlist'),
        content: Text(
          'Se eliminará "${pl.name}". Las canciones volverán a la Biblioteca.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancelar')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.colors.error),
            onPressed: () => Navigator.pop(context, true),
            child: Text('Eliminar'),
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
  final VoidCallback onSettings;
  const _Header({required this.onSettings});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          ShaderMask(
            shaderCallback: (b) => context.colors.gradient.createShader(b),
            child: Icon(Icons.music_note_rounded, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 8),
          Text(
            'Sonero',
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.settings_outlined, size: 18),
            color: context.colors.textSecondary,
            onPressed: onSettings,
            tooltip: 'Configuración',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
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
        ),
      );
}

class _PlaylistTile extends StatelessWidget {
  final Playlist playlist;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback? onRename;

  const _PlaylistTile({
    required this.playlist,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (onDelete != null || onRename != null)
          ? (details) => _showContextMenu(context, details.globalPosition)
          : null,
      child: ListTile(
        dense: true,
        selected: isSelected,
        selectedTileColor: Theme.of(context).colorScheme.primary.withOpacity(0.12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        leading: Icon(
          playlist.isLibrary
              ? Icons.library_music_outlined
              : Icons.queue_music_outlined,
          size: 18,
          color: isSelected ? Theme.of(context).colorScheme.primary : context.colors.textSecondary,
        ),
        title: Text(
          playlist.name,
          style: TextStyle(
            fontSize: 13,
            color: isSelected ? context.colors.textPrimary : context.colors.textSecondary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        trailing: playlist.trackCount > 0
            ? Text(
                '${playlist.trackCount}',
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 11,
                ),
              )
            : null,
        onTap: onTap,
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
          const PopupMenuItem(value: 'rename', child: Text('Renombrar')),
        if (onDelete != null)
          PopupMenuItem(value: 'delete',
            child: Text('Eliminar', style: TextStyle(color: context.colors.error)),
          ),
      ],
    );
    if (action == 'rename') onRename?.call();
    if (action == 'delete') onDelete?.call();
  }
}

class _NewPlaylistButton extends StatelessWidget {
  final VoidCallback onPressed;
  const _NewPlaylistButton({required this.onPressed});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            icon: Icon(Icons.add, size: 16),
            label: Text('Nueva Playlist', style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.primary,
              side: BorderSide(color: Theme.of(context).colorScheme.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
            onPressed: onPressed,
          ),
        ),
      );
}



