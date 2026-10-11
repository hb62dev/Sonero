import 'package:flutter/material.dart';

import 'api.dart';
import 'now_playing_screen.dart';
import 'player.dart';
import 'remote_link.dart';
import 'stats_screen.dart';
import 'ui.dart';

/// Browse the Sonero library with the remote: playlists on the left, songs on
/// the right, and a now-playing bar at the bottom.
class LibraryScreen extends StatefulWidget {
  final SoneroApi api;
  final PlayerController player;
  final RemoteLink? link;
  final ValueChanged<SoneroApi> onServerMoved;
  final ValueChanged<String?> onDisconnect;

  const LibraryScreen({
    super.key,
    required this.api,
    required this.player,
    this.link,
    required this.onServerMoved,
    required this.onDisconnect,
  });

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  Library? _library;
  String? _error;
  bool _loading = true;
  String? _playlist; // null = all songs

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final lib = await widget.api.library();
      widget.player.knownTracks = {for (final t in lib.tracks) t.id: t};
      if (mounted) setState(() => _library = lib);
    } on ApiException catch (e) {
      if (e.unauthorized) {
        await ConnectionStore.clear();
        widget.onDisconnect('Esta TV ya no está autorizada en ${widget.api.server.name}. Vuelve a emparejarla.');
        return;
      }
      // The computer may have a new IP (DHCP): look for it by name before giving up
      if (await _relocate()) return;
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _relocate() async {
    final current = widget.api.server;
    final found = await discoverServers();
    for (final s in found) {
      if (s.name == current.name && (s.host != current.host || s.port != current.port)) {
        final token = widget.api.token!;
        await ConnectionStore.save(s, token);
        widget.onServerMoved(SoneroApi(s, token: token));
        return true;
      }
    }
    return false;
  }

  List<Track> get _visible {
    final tracks = _library?.tracks ?? const <Track>[];
    return _playlist == null ? tracks : tracks.where((t) => t.playlist == _playlist).toList();
  }

  Future<void> _play(List<Track> tracks, {int index = 0, bool shuffle = false}) async {
    await widget.player.playQueue(tracks, startIndex: index, shuffle: shuffle);
    if (mounted) _openNowPlaying();
  }

  void _openNowPlaying() {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => NowPlayingScreen(api: widget.api, player: widget.player),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final lib = _library;
    if (lib == null) {
      return Scaffold(
        body: _loading
            ? const MessageView(icon: Icons.wifi_tethering_rounded, title: 'Conectando con Sonero…')
            : MessageView(
                icon: Icons.wifi_off_rounded,
                title: 'No se pudo conectar',
                body: _error,
                action: Wrap(spacing: 16, children: [
                  TvButton(icon: Icons.refresh_rounded, label: 'Reintentar', autofocus: true, onPressed: _load),
                  TvButton(
                    icon: Icons.swap_horiz_rounded,
                    label: 'Cambiar de computadora',
                    onPressed: () => widget.onDisconnect(null),
                  ),
                ]),
              ),
      );
    }

    final visible = _visible;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Sidebar(
                  library: lib,
                  selected: _playlist,
                  onSelect: (p) => setState(() => _playlist = p),
                  link: widget.link,
                  onStats: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => StatsScreen(api: widget.api, player: widget.player),
                  )),
                  onDisconnect: () async {
                    await ConnectionStore.clear();
                    widget.onDisconnect(null);
                  },
                ),
                Expanded(
                  child: FocusTraversalGroup(
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(40, 40, 48, 20),
                          sliver: SliverToBoxAdapter(
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(_playlist ?? 'Todas las canciones',
                                          style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                                      Text('${visible.length} canciones',
                                          style: const TextStyle(fontSize: 20, color: SoneroColors.muted)),
                                    ],
                                  ),
                                ),
                                TvButton(
                                  icon: Icons.play_arrow_rounded,
                                  label: 'Reproducir',
                                  primary: true,
                                  autofocus: true,
                                  onPressed: visible.isEmpty ? null : () => _play(visible),
                                ),
                                const SizedBox(width: 16),
                                TvButton(
                                  icon: Icons.shuffle_rounded,
                                  label: 'Aleatorio',
                                  onPressed: visible.isEmpty ? null : () => _play(visible, shuffle: true),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (visible.isEmpty)
                          const SliverFillRemaining(
                            hasScrollBody: false,
                            child: MessageView(
                              icon: Icons.library_music_outlined,
                              title: 'No hay canciones aquí',
                              body: 'Agrega música a Sonero en tu computadora y vuelve a abrir esta pantalla.',
                            ),
                          )
                        else
                          SliverPadding(
                            padding: const EdgeInsets.fromLTRB(32, 0, 40, 32),
                            sliver: SliverList.builder(
                              itemCount: visible.length,
                              itemBuilder: (context, i) => _TrackRow(
                                api: widget.api,
                                track: visible[i],
                                player: widget.player,
                                onPressed: () => _play(visible, index: i),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: widget.player,
            builder: (context, _) => widget.player.current == null
                ? const SizedBox.shrink()
                : _NowPlayingBar(api: widget.api, player: widget.player, onOpen: _openNowPlaying),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final Library library;
  final String? selected;
  final ValueChanged<String?> onSelect;
  final VoidCallback onDisconnect;
  final VoidCallback onStats;
  final RemoteLink? link;

  const _Sidebar({
    required this.library,
    required this.selected,
    required this.onSelect,
    required this.onDisconnect,
    required this.onStats,
    this.link,
  });

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, String? value, int count) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: TvFocusable(
            onPressed: () => onSelect(value),
            radius: 12,
            focusScale: 1.02,
            builder: (context, focused) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected == value ? SoneroColors.surfaceAlt : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(icon, size: 24, color: selected == value ? SoneroColors.accent : SoneroColors.muted),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(label,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20)),
                  ),
                  Text('$count', style: const TextStyle(fontSize: 16, color: SoneroColors.muted)),
                ],
              ),
            ),
          ),
        );

    return Container(
      width: 320,
      color: SoneroColors.surface,
      padding: const EdgeInsets.fromLTRB(20, 36, 20, 20),
      child: FocusTraversalGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Image.asset('assets/logo.png', height: 30, alignment: Alignment.centerLeft),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
              child: Row(children: [
                const Icon(Icons.laptop_mac_rounded, size: 18, color: SoneroColors.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(library.serverName,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 16, color: SoneroColors.muted)),
                ),
                if (link != null)
                  ListenableBuilder(
                    listenable: link!,
                    builder: (context, _) => Tooltip(
                      message: link!.connected ? 'Control remoto conectado' : 'Reconectando…',
                      child: Icon(Icons.circle, size: 10,
                          color: link!.connected ? const Color(0xFF8BC34A) : SoneroColors.muted),
                    ),
                  ),
              ]),
            ),
            Expanded(
              child: ListView(
                children: [
                  item(Icons.library_music_rounded, 'Todas las canciones', null, library.tracks.length),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: TvFocusable(
                      onPressed: onStats,
                      radius: 12,
                      focusScale: 1.02,
                      builder: (context, focused) => const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(children: [
                          Icon(Icons.insights_rounded, size: 24, color: SoneroColors.muted),
                          SizedBox(width: 14),
                          Text('Estadísticas', style: TextStyle(fontSize: 20)),
                        ]),
                      ),
                    ),
                  ),
                  if (library.playlists.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
                      child: Text('PLAYLISTS',
                          style: TextStyle(fontSize: 14, letterSpacing: 1.5, color: SoneroColors.muted)),
                    ),
                  for (final p in library.playlists) item(Icons.queue_music_rounded, p.name, p.name, p.count),
                ],
              ),
            ),
            TvFocusable(
              onPressed: onDisconnect,
              radius: 12,
              focusScale: 1.02,
              builder: (context, focused) => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(children: [
                  Icon(Icons.swap_horiz_rounded, size: 22, color: SoneroColors.muted),
                  SizedBox(width: 14),
                  Expanded(
                    child: Text('Cambiar de computadora',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 18, color: SoneroColors.muted)),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final SoneroApi api;
  final Track track;
  final PlayerController player;
  final VoidCallback onPressed;

  const _TrackRow({required this.api, required this.track, required this.player, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TvFocusable(
        onPressed: onPressed,
        radius: 12,
        focusScale: 1.015,
        builder: (context, focused) => ListenableBuilder(
          listenable: player,
          builder: (context, _) {
            final isCurrent = player.current?.id == track.id;
            return Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: focused ? SoneroColors.surfaceAlt : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CoverArt(api: api, track: track, size: 64, radius: 8),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: isCurrent ? SoneroColors.accent : SoneroColors.text,
                            )),
                        if (track.artist.isNotEmpty)
                          Text(track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
                      ],
                    ),
                  ),
                  if (isCurrent)
                    Padding(
                      padding: const EdgeInsets.only(right: 16),
                      child: Icon(player.isPlaying ? Icons.equalizer_rounded : Icons.pause_rounded,
                          color: SoneroColors.accent, size: 28),
                    ),
                  if (track.duration != null)
                    Text(formatDuration(Duration(seconds: track.duration!.round())),
                        style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
                  const SizedBox(width: 8),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NowPlayingBar extends StatelessWidget {
  final SoneroApi api;
  final PlayerController player;
  final VoidCallback onOpen;

  const _NowPlayingBar({required this.api, required this.player, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final t = player.current!;
    return TvFocusable(
      onPressed: onOpen,
      radius: 0,
      focusScale: 1,
      builder: (context, focused) => Container(
        height: 96,
        padding: const EdgeInsets.symmetric(horizontal: 32),
        decoration: BoxDecoration(
          color: focused ? SoneroColors.surfaceAlt : SoneroColors.surface,
          border: const Border(top: BorderSide(color: SoneroColors.border)),
        ),
        child: Row(
          children: [
            CoverArt(api: api, track: t, size: 64, radius: 8),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
                ],
              ),
            ),
            Icon(player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 36),
            const SizedBox(width: 12),
            Text(focused ? 'Abrir reproductor' : 'Reproduciendo',
                style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
          ],
        ),
      ),
    );
  }
}
