import 'package:sonero_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:carousel_slider/carousel_slider.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/track.dart';
import '../../models/playlist.dart';
import '../theme.dart';
import '../widgets/hover_scale.dart';
import '../widgets/track_cover_image.dart';
import 'package:file_picker/file_picker.dart';

class HomeView extends StatelessWidget {
  final Function(int)? onNavigate;
  
  const HomeView({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();
    final colors = context.colors;

    // Just some sample data logic
    final recentItems = library.tracks.take(5).toList();
    final allPlaylists = library.playlists;

    return Scaffold(
      backgroundColor: colors.bg,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: _buildHeroBanner(context, recentItems.isNotEmpty ? recentItems.first : null),
          ),
          if (recentItems.isNotEmpty)
            SliverToBoxAdapter(
              child: _buildCarouselRow(context, AppLocalizations.of(context)!.continueWatching, recentItems),
            ),
          SliverToBoxAdapter(
            child: _buildPlaylistsRow(context, AppLocalizations.of(context)!.yourSmartPlaylists, allPlaylists),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 100)), // Space for mini player
        ],
      ),
    );
  }

  Widget _buildHeroBanner(BuildContext context, Track? mainTrack) {
    final title = mainTrack?.title.isNotEmpty == true ? mainTrack!.title : AppLocalizations.of(context)!.welcomeHome;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final heroBannerHeight = isMobile ? 180.0 : 400.0;

    return Container(
      height: heroBannerHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.3),
            context.colors.bg!,
          ],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 40),
            child: Text(
              title,
              style: TextStyle(
                fontSize: isMobile ? 26 : 48,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (mainTrack != null && mainTrack.artist.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6.0, left: isMobile ? 20 : 40, right: isMobile ? 20 : 40),
              child: Text(
                mainTrack.artist,
                style: TextStyle(
                  fontSize: isMobile ? 16 : 24,
                  color: context.colors.textSecondary,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          SizedBox(height: isMobile ? 16 : 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  if (mainTrack != null) {
                    try {
                      final settings = context.read<SettingsProvider>();
                      final library = context.read<LibraryProvider>();
                      await context.read<PlayerProvider>().playTrack(mainTrack, library.tracks, settings);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(e.toString().replaceAll('Exception: ', '')),
                          backgroundColor: context.colors.error,
                          duration: const Duration(seconds: 4),
                        ));
                      }
                    }
                  }
                },
                icon: Icon(Icons.play_arrow, color: context.colors.surface),
                label: Text(AppLocalizations.of(context)!.play, style: TextStyle(color: context.colors.surface, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: context.colors.textPrimary,
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 20 : 24,
                    vertical: isMobile ? 10 : 12,
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: Icon(Icons.info_outline, color: context.colors.textPrimary),
                label: Text(AppLocalizations.of(context)!.moreInfo, style: TextStyle(color: context.colors.textPrimary)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: context.colors.textPrimary),
                  padding: EdgeInsets.symmetric(
                    horizontal: isMobile ? 20 : 24,
                    vertical: isMobile ? 10 : 12,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isMobile ? 24 : 40),
        ],
      ),
    );
  }

  Widget _buildCarouselRow(BuildContext context, String title, List<Track> items) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32, vertical: isMobile ? 12 : 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 16 : 20,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
        ),
        CarouselSlider(
          options: CarouselOptions(
            height: isMobile ? 160 : 200,
            viewportFraction: isMobile ? 0.72 : 0.2,
            enableInfiniteScroll: false,
            padEnds: false,
            disableCenter: true,
          ),
          items: items.map((item) {
            return Builder(
              builder: (BuildContext context) {
                return HoverScale(
                  key: ValueKey('carousel_${item.filename}'),
                  onTap: () async {
                    try {
                      final settings = context.read<SettingsProvider>();
                      await context.read<PlayerProvider>().playTrack(item, items, settings);
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
                  child: Container(
                    width: MediaQuery.of(context).size.width,
                    margin: const EdgeInsets.symmetric(horizontal: 8.0),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.09),
                          blurRadius: 4,
                          spreadRadius: 0,
                          offset: const Offset(0, 1),
                        )
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Cover with zoom/pan adjustment
                        if (item.coverUrl != null && item.coverUrl!.isNotEmpty && getCoverImageProvider(item.coverUrl) != null)
                          AdjustedCoverImage(
                            coverUrl: item.coverUrl,
                            width: MediaQuery.of(context).size.width,
                            height: 300,
                          ),
                        // Gradient overlay with text
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          alignment: Alignment.bottomLeft,
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title.isNotEmpty ? item.title : item.filename,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.artist.isNotEmpty)
                                Text(
                                  item.artist,
                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPlaylistsRow(BuildContext context, String title, List<Playlist> playlists) {
    if (playlists.isEmpty) return const SizedBox.shrink();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: isMobile ? 20 : 32, vertical: isMobile ? 12 : 16),
          child: Text(
            title,
            style: TextStyle(
              fontSize: isMobile ? 16 : 20,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
        ),
        SizedBox(
          height: isMobile ? 120 : 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28),
            itemCount: playlists.length + 1,
            itemBuilder: (context, index) {
              // Last item = "+" button
              if (index == playlists.length) {
                return HoverScale(
                  key: const ValueKey('add_playlist_card'),
                  onTap: () => _showAddCardDialog(context),
                  child: Container(
                    width: 150,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceAlt.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: context.colors.border.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 36, color: context.colors.textSecondary.withOpacity(0.5)),
                          const SizedBox(height: 6),
                          Text(
                            'Nuevo',
                            style: TextStyle(
                              color: context.colors.textSecondary.withOpacity(0.6),
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }

              final pl = playlists[index];
              final hasCover = pl.coverUrl != null && pl.coverUrl!.isNotEmpty;
              final settings = context.read<SettingsProvider>();
              final apiUrl = settings.apiUrl;

              Widget coverWidget;
              if (hasCover) {
                final imageUrl = pl.coverUrl!.startsWith('file://')
                    ? pl.coverUrl!
                    : '$apiUrl${pl.coverUrl}';
                coverWidget = ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    width: 150,
                    height: isMobile ? 120 : 150,
                    errorBuilder: (_, __, ___) => _PlaylistFallbackIcon(
                      name: pl.name,
                      accent: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                );
              } else {
                coverWidget = _PlaylistFallbackIcon(
                  name: pl.name,
                  accent: Theme.of(context).colorScheme.primary,
                );
              }

              return GestureDetector(
                onSecondaryTapUp: (details) {
                  _showPlaylistCoverMenu(context, details.globalPosition, pl);
                },
                child: HoverScale(
                  key: ValueKey('playlist_card_${pl.name}'),
                  onTap: () async {
                    final library = context.read<LibraryProvider>();
                    await library.selectPlaylist(settings.api, pl);
                    if (onNavigate != null) {
                      onNavigate!(1);
                    }
                  },
                  child: Container(
                    width: 150,
                    margin: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: hasCover ? Colors.transparent : Theme.of(context).colorScheme.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: hasCover ? null : Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.1), width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Stack(
                      children: [
                        coverWidget,
                        if (hasCover)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.75),
                                  ],
                                ),
                              ),
                              child: Text(
                                pl.name,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  shadows: [Shadow(blurRadius: 4, color: Colors.black)],
                                ),
                                maxLines: 2,
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
      ],
    );
  }

  void _showAddCardDialog(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: context.colors.textSecondary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'Agregar acceso rápido',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: context.colors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              // Option: Create new playlist
              _AddOptionTile(
                icon: Icons.add_circle_outline_rounded,
                title: 'Nueva lista de reproducción',
                subtitle: 'Crea una playlist personalizada',
                color: accent,
                onTap: () {
                  Navigator.pop(ctx);
                  _showCreatePlaylistDialog(context);
                },
              ),
              const SizedBox(height: 8),
              // Option: Go to Library (Biblioteca)
              _AddOptionTile(
                icon: Icons.library_music_rounded,
                title: 'Ir a Biblioteca',
                subtitle: 'Ver toda tu colección de música',
                color: accent,
                onTap: () {
                  Navigator.pop(ctx);
                  if (onNavigate != null) onNavigate!(1);
                },
              ),
              const SizedBox(height: 8),
              // Option: Go to Analytics
              _AddOptionTile(
                icon: Icons.bar_chart_rounded,
                title: 'Ver Analíticas',
                subtitle: 'Estadísticas de reproducción',
                color: accent,
                onTap: () {
                  Navigator.pop(ctx);
                  if (onNavigate != null) onNavigate!(3);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    final accent = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Nueva lista de reproducción',
          style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: context.colors.textPrimary),
          decoration: InputDecoration(
            hintText: 'Nombre de la playlist',
            hintStyle: TextStyle(color: context.colors.textSecondary.withOpacity(0.5)),
            filled: true,
            fillColor: context.colors.surfaceAlt,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar', style: TextStyle(color: context.colors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              final settings = context.read<SettingsProvider>();
              await context.read<LibraryProvider>().createPlaylist(settings.api, name);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Playlist "$name" creada'),
                    backgroundColor: accent,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showPlaylistCoverMenu(BuildContext context, Offset position, Playlist pl) {
    final accent = Theme.of(context).colorScheme.primary;
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      color: context.colors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          child: Row(
            children: [
              Icon(Icons.image_rounded, size: 18, color: accent),
              const SizedBox(width: 10),
              Text(pl.coverUrl != null ? 'Cambiar imagen' : 'Agregar imagen'),
            ],
          ),
          onTap: () async {
            final result = await FilePicker.pickFiles(
              type: FileType.image,
              allowMultiple: false,
              withData: true,
            );
            if (result != null && result.files.isNotEmpty && result.files.first.bytes != null) {
              final file = result.files.first;
              final settings = context.read<SettingsProvider>();
              await settings.api.uploadPlaylistCover(
                pl.name,
                file.bytes!.toList(),
                file.name,
              );
              if (context.mounted) {
                await context.read<LibraryProvider>().loadPlaylists(settings.api);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Imagen de "${pl.name}" actualizada'),
                    backgroundColor: accent,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }
}

class _AddOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _AddOptionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: color.withOpacity(0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    )),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: 12,
                    )),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary.withOpacity(0.4), size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistFallbackIcon extends StatelessWidget {
  final String name;
  final Color accent;

  const _PlaylistFallbackIcon({required this.name, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.queue_music, size: 40, color: accent),
          const SizedBox(height: 8),
          Text(
            name,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
