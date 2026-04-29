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
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
    return Container(
      height: 400,
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
          Text(
            title,
            style: const TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            textAlign: TextAlign.center,
          ),
          if (mainTrack != null && mainTrack.artist.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: Text(
                mainTrack.artist,
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.white.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  if (mainTrack != null) {
                    try {
                      final settings = context.read<SettingsProvider>();
                      final library = context.read<LibraryProvider>();
                      await context.read<PlayerProvider>().playTrack(mainTrack, library.tracks, settings.musicFolder);
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
                icon: const Icon(Icons.play_arrow, color: Colors.black),
                label: Text(AppLocalizations.of(context)!.play, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
              const SizedBox(width: 16),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.info_outline, color: Colors.white),
                label: Text(AppLocalizations.of(context)!.moreInfo, style: const TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildCarouselRow(BuildContext context, String title, List<Track> items) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        CarouselSlider(
          options: CarouselOptions(
            height: 200,
            viewportFraction: 0.2,
            enableInfiniteScroll: false,
            padEnds: false,
            disableCenter: true,
          ),
          items: items.map((item) {
            return Builder(
              builder: (BuildContext context) {
                return HoverScale(
                  key: ValueKey('carousel_${item.filename}'),
                  scale: 1.05,
                  child: InkWell(
                    onTap: () async {
                      try {
                        final settings = context.read<SettingsProvider>();
                        await context.read<PlayerProvider>().playTrack(item, items, settings.musicFolder);
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
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                        image: item.coverUrl != null && item.coverUrl!.isNotEmpty
                            ? DecorationImage(
                                image: NetworkImage(item.coverUrl!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
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
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        SizedBox(
          height: 150,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: playlists.length,
            itemBuilder: (context, index) {
              final pl = playlists[index];
              return HoverScale(
                key: ValueKey('playlist_card_${pl.name}'),
                scale: 1.05,
                child: InkWell(
                  onTap: () async {
                    final settings = context.read<SettingsProvider>();
                    final library = context.read<LibraryProvider>();
                    await library.selectPlaylist(settings.api, pl);
                    if (onNavigate != null) {
                      onNavigate!(1); // navigate to library
                    }
                  },
                  child: Container(
                    width: 150,
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          blurRadius: 6,
                          spreadRadius: 0,
                        )
                      ],
                    ),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.queue_music, size: 40, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(height: 8),
                          Text(
                            pl.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
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
}
