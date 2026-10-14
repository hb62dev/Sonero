import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/library_provider.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/mixes_api.dart';
import '../theme.dart';
import '../widgets/track_cover_image.dart';

/// Biblioteca → Para ti: recommended mixes from Sonero's own algorithm and
/// from AI agents connected through the MCP server.
class ForYouTab extends StatefulWidget {
  const ForYouTab({super.key});

  @override
  State<ForYouTab> createState() => _ForYouTabState();
}

class _ForYouTabState extends State<ForYouTab> {
  late MixesApi _api;
  List<SmartMix>? _mixes;
  String? _error;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _api = MixesApi(context.read<SettingsProvider>().apiUrl);
    _load(generateIfEmpty: true);
  }

  Future<void> _load({bool generateIfEmpty = false}) async {
    try {
      final mixes = await _api.list();
      if (!mounted) return;
      setState(() {
        _mixes = mixes;
        _error = null;
      });
      if (generateIfEmpty && mixes.isEmpty) await _generate();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _generate() async {
    setState(() => _generating = true);
    try {
      final result = await _api.generate();
      await _load();
      if (mounted && result['online'] == false) {
        _snack('Sin internet: se generaron solo los mixes de tu biblioteca, sin descubrimientos.');
      }
    } catch (e) {
      _snack('No se pudieron generar los mixes: ${e.toString().replaceFirst('Exception: ', '')}');
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(SmartMix mix) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => MixDetailPage(api: _api, mixId: mix.id)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (context.read<SettingsProvider>().api.isNative) {
      return const _Centered(
        icon: Icons.auto_awesome_rounded,
        title: 'Para ti necesita el servidor de Sonero',
        body: 'Las recomendaciones se calculan en el servidor de Sonero de tu computadora.',
      );
    }
    final mixes = _mixes;
    if (mixes == null) {
      return _error != null
          ? _Centered(icon: Icons.cloud_off_rounded, title: 'No se pudieron cargar los mixes', body: _error,
              action: OutlinedButton(onPressed: _load, child: const Text('Reintentar')))
          : const Center(child: CircularProgressIndicator());
    }

    final agent = mixes.where((m) => m.byAgent).toList();
    final auto = mixes.where((m) => !m.byAgent).toList();
    final isMobile = MediaQuery.of(context).size.width < 600;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(isMobile ? 12 : 20, 16, isMobile ? 12 : 20, 120),
        children: [
          // ── Toolbar ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text(_generating ? 'Generando…' : 'Actualizar mixes'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => EnrichDialog(api: _api))
                    .then((_) => _load()),
                icon: const Icon(Icons.travel_explore_rounded, size: 18),
                label: const Text('Completar géneros y años'),
              ),
              OutlinedButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => AnalyzeDialog(api: _api)),
                icon: const Icon(Icons.graphic_eq_rounded, size: 18),
                label: const Text('Analizar audio'),
              ),
              TextButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AgentHelpDialog()),
                icon: const Icon(Icons.smart_toy_outlined, size: 18),
                label: const Text('Conectar un agente IA'),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (agent.isNotEmpty) ...[
            const _SectionTitle(icon: Icons.smart_toy_rounded, title: 'Creados por tu agente IA'),
            _MixGrid(mixes: agent, onOpen: _open),
            const SizedBox(height: 28),
          ],

          _SectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: 'Hechos para ti',
            subtitle: auto.isEmpty ? null : 'Según lo que escuchas, lo que saltas y cuándo escuchas',
          ),
          if (auto.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                _generating ? 'Analizando tu biblioteca y tu historial…' : 'Pulsa "Actualizar mixes" para crearlos.',
                style: TextStyle(color: context.colors.textSecondary),
              ),
            )
          else
            _MixGrid(mixes: auto, onOpen: _open),
        ],
      ),
    );
  }
}

// ── Cards ────────────────────────────────────────────────────────────────────

IconData _mixIcon(SmartMix m) {
  final k = m.kind ?? '';
  if (m.byAgent) return Icons.smart_toy_rounded;
  if (k == 'daily_mix') return Icons.wb_sunny_rounded;
  if (k == 'favorites') return Icons.favorite_rounded;
  if (k == 'rediscover') return Icons.history_rounded;
  if (k == 'unplayed') return Icons.new_releases_rounded;
  if (k == 'recent') return Icons.fiber_new_rounded;
  if (k == 'discovery') return Icons.explore_rounded;
  if (k == 'energy') return Icons.bolt_rounded;
  if (k == 'calm') return Icons.spa_rounded;
  if (k.startsWith('radio:')) return Icons.radio_rounded;
  if (k.startsWith('genre:')) return Icons.category_rounded;
  if (k == 'time_noche') return Icons.nightlight_round;
  if (k.startsWith('time_')) return Icons.wb_twilight_rounded;
  return Icons.queue_music_rounded;
}

List<Color> _mixColors(SmartMix m, Color accent) {
  // Stable hue per mix kind so each card keeps its colour between refreshes
  final seed = (m.kind ?? m.title).codeUnits.fold<int>(0, (a, b) => (a * 31 + b) & 0xffff);
  final base = HSLColor.fromColor(accent);
  final hue = (base.hue + (seed % 7) * 40) % 360;
  return [
    base.withHue(hue).withLightness(0.42).toColor(),
    base.withHue((hue + 35) % 360).withLightness(0.22).toColor(),
  ];
}

class _MixGrid extends StatelessWidget {
  final List<SmartMix> mixes;
  final ValueChanged<SmartMix> onOpen;
  const _MixGrid({required this.mixes, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final columns = (c.maxWidth / 220).floor().clamp(2, 6);
      return GridView.count(
        crossAxisCount: columns,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
        children: [for (final m in mixes) _MixCard(mix: m, onTap: () => onOpen(m))],
      );
    });
  }
}

class _MixCard extends StatelessWidget {
  final SmartMix mix;
  final VoidCallback onTap;
  const _MixCard({required this.mix, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = _mixColors(mix, Theme.of(context).colorScheme.primary);
    final online = mix.count - mix.inLibrary;
    return Material(
      color: context.colors.surfaceAlt,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_mixIcon(mix), color: Colors.white.withValues(alpha: 0.9), size: 26),
                    const Spacer(),
                    Text(mix.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 17, height: 1.15)),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    mix.description ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    [
                      '${mix.count} canciones',
                      if (online > 0) '$online nuevas',
                      if (mix.byAgent && mix.author != null) mix.author!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: context.colors.textSecondary.withValues(alpha: 0.8), fontSize: 10),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          if (subtitle != null) ...[
            const SizedBox(width: 10),
            Flexible(
              child: Text(subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;
  const _Centered({required this.icon, required this.title, this.body, this.action});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.colors.textSecondary.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            if (body != null) ...[
              const SizedBox(height: 6),
              Text(body!, textAlign: TextAlign.center, style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
            ],
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

// ── Mix detail ───────────────────────────────────────────────────────────────

class MixDetailPage extends StatefulWidget {
  final MixesApi api;
  final int mixId;
  const MixDetailPage({super.key, required this.api, required this.mixId});

  @override
  State<MixDetailPage> createState() => _MixDetailPageState();
}

class _MixDetailPageState extends State<MixDetailPage> {
  SmartMix? _mix;
  String? _error;
  final Set<int> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mix = await widget.api.get(widget.mixId);
      if (mounted) setState(() => _mix = mix);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  /// Library items use the library's own Track (with its cover); online items
  /// play their 30 s preview straight from the URL.
  Track _toTrack(MixItem item, Map<String, Track> library, String baseUrl) {
    if (item.inLibrary && item.filename != null) {
      final known = library[item.filename!] ?? library[item.filename!.split('/').last];
      if (known != null) return known;
      return Track(
        filename: item.filename!,
        title: item.title,
        artist: item.artist,
        album: item.album ?? '',
        coverUrl: '$baseUrl/api/v1/metadata/cover/${item.filename}',
      );
    }
    return Track(
      filename: item.previewUrl ?? '',
      title: item.title,
      artist: item.artist,
      album: item.album ?? '',
      coverUrl: item.coverUrl,
    );
  }

  Future<void> _play(List<MixItem> items, int index) async {
    final settings = context.read<SettingsProvider>();
    final library = {
      for (final t in context.read<LibraryProvider>().tracks) ...{t.filename: t, t.filename.split('/').last: t}
    };
    // Online songs without a preview can't be played: skip them
    final playable = items.where((i) => i.inLibrary || (i.previewUrl?.isNotEmpty ?? false)).toList();
    if (playable.isEmpty) return;
    final start = playable.indexOf(items[index]).clamp(0, playable.length - 1);
    final queue = [for (final i in playable) _toTrack(i, library, settings.apiUrl)];
    await context.read<PlayerProvider>().playTrack(queue[start], queue, settings);
  }

  Future<void> _download(MixItem item) async {
    setState(() => _downloading.add(item.id));
    try {
      final jobId = await widget.api.downloadItem(widget.mixId, item.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Descargando "${item.title}". Aparecerá en tu biblioteca al terminar (ver Descargas).'),
      ));
      _watchDownload(item, jobId);
    } catch (e) {
      if (!mounted) return;
      setState(() => _downloading.remove(item.id));
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo descargar: ${e.toString().replaceFirst('Exception: ', '')}')));
    }
  }

  /// Follows the download job, then re-reads the mix so the song shows up as a library item.
  void _watchDownload(MixItem item, String jobId) {
    var tries = 0;
    Timer.periodic(const Duration(seconds: 3), (timer) async {
      tries++;
      if (!mounted || tries > 120) {
        timer.cancel();
        if (mounted) setState(() => _downloading.remove(item.id));
        return;
      }
      final settings = context.read<SettingsProvider>();
      try {
        final job = await settings.api.getVideoJobStatus(jobId);
        if (job['status'] == 'failed') {
          timer.cancel();
          if (!mounted) return;
          setState(() => _downloading.remove(item.id));
          final error = '${job['error'] ?? ''}';
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            duration: const Duration(seconds: 8),
            content: Text(error.contains('not a bot') || error.contains('cookies')
                ? 'YouTube bloqueó la descarga de "${item.title}" (verificación anti-bot). Activa "Leer cookies '
                    'de un navegador" o carga un cookies.txt en Ajustes → Autenticación.'
                : 'No se pudo descargar "${item.title}".'),
          ));
          return;
        }
        if (job['status'] != 'done') return;
      } catch (_) {}
      await _load();
      final now = _mix?.items.where((i) => i.id == item.id).firstOrNull;
      if (now != null && now.inLibrary) {
        timer.cancel();
        if (!mounted) return;
        setState(() => _downloading.remove(item.id));
        final settings = context.read<SettingsProvider>();
        context.read<LibraryProvider>().loadTracks(settings.api);
      }
    });
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Borrar este mix?'),
        content: const Text('Tus archivos de música no se borran, solo la lista.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.api.delete(widget.mixId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final mix = _mix;
    final primary = Theme.of(context).colorScheme.primary;
    final settings = context.watch<SettingsProvider>();
    final library = {
      for (final t in context.watch<LibraryProvider>().tracks) ...{t.filename: t, t.filename.split('/').last: t}
    };

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(mix?.title ?? ''),
        actions: [
          if (mix != null && mix.byAgent)
            IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Borrar mix'),
        ],
      ),
      body: mix == null
          ? (_error != null
              ? _Centered(icon: Icons.error_outline_rounded, title: 'No se pudo abrir el mix', body: _error)
              : const Center(child: CircularProgressIndicator()))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
              children: [
                // ── Header ──
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: _mixColors(mix, primary)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(_mixIcon(mix), color: Colors.white, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          mix.byAgent ? 'Creado por ${mix.author ?? 'tu agente IA'}' : 'Hecho por Sonero',
                          style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      if (mix.description != null)
                        Text(mix.description!, style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35)),
                      if (mix.reason != null) ...[
                        const SizedBox(height: 8),
                        Text('Por qué: ${mix.reason}', style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35)),
                      ],
                      const SizedBox(height: 14),
                      Wrap(spacing: 10, runSpacing: 8, children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                          onPressed: mix.items.isEmpty ? null : () => _play(mix.items, 0),
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Reproducir'),
                        ),
                        Text(
                          '${mix.items.where((i) => i.inLibrary).length} en tu biblioteca · '
                          '${mix.items.where((i) => !i.inLibrary).length} nuevas (vista previa de 30 s)',
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ── Songs ──
                for (final (index, item) in mix.items.indexed)
                  _MixItemTile(
                    item: item,
                    track: _toTrack(item, library, settings.apiUrl),
                    downloading: _downloading.contains(item.id),
                    onPlay: () => _play(mix.items, index),
                    onDownload: item.inLibrary ? null : () => _download(item),
                  ),
              ],
            ),
    );
  }
}

class _MixItemTile extends StatelessWidget {
  final MixItem item;
  final Track track;
  final bool downloading;
  final VoidCallback onPlay;
  final VoidCallback? onDownload;

  const _MixItemTile({
    required this.item,
    required this.track,
    required this.downloading,
    required this.onPlay,
    this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final playable = item.inLibrary || (item.previewUrl?.isNotEmpty ?? false);
    final isCurrent = context.select<PlayerProvider, bool>((p) => p.currentTrack?.filename == track.filename);
    final primary = Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onTap: playable ? onPlay : null,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: TrackCoverImage(
          coverUrl: track.coverUrl,
          width: 48,
          height: 48,
          errorWidget: Container(
            width: 48,
            height: 48,
            color: context.colors.surfaceAlt,
            child: Icon(Icons.music_note_rounded, color: context.colors.textSecondary),
          ),
        ),
      ),
      title: Text(item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: isCurrent ? primary : null)),
      subtitle: Text(
        [if (item.artist.isNotEmpty) item.artist, if (item.note != null) item.note!].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
      ),
      trailing: item.inLibrary
          ? Icon(Icons.library_music_rounded, size: 18, color: context.colors.textSecondary.withValues(alpha: 0.6))
          : Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(playable ? 'Nueva · 30 s' : 'Nueva',
                    style: TextStyle(color: primary, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
              IconButton(
                tooltip: 'Descargar a mi biblioteca',
                onPressed: downloading ? null : onDownload,
                icon: downloading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
              ),
            ]),
    );
  }
}

// ── Metadata review ──────────────────────────────────────────────────────────

class EnrichDialog extends StatefulWidget {
  final MixesApi api;
  const EnrichDialog({super.key, required this.api});

  @override
  State<EnrichDialog> createState() => _EnrichDialogState();
}

class _EnrichDialogState extends State<EnrichDialog> {
  LibraryJob? _job;
  Timer? _poll;
  final Set<int> _selected = {};
  bool _initialized = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      var job = await widget.api.enrichStatus();
      if (!job.running && job.proposals.isEmpty) job = await widget.api.enrichStart();
      _update(job);
      _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
        try {
          _update(await widget.api.enrichStatus());
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) setState(() => _job = LibraryJob(running: false, done: 0, total: 0, error: '$e'));
    }
  }

  void _update(LibraryJob job) {
    if (!mounted) return;
    setState(() {
      _job = job;
      if (!job.running && !_initialized) {
        _initialized = true;
        _selected.addAll(job.proposals.where((p) => p['selected'] == true).map((p) => (p['media_id'] as num).toInt()));
      }
    });
    if (!job.running) _poll?.cancel();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _apply() async {
    setState(() => _saving = true);
    try {
      final r = await widget.api.enrichApply(_selected.toList());
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Metadatos guardados en ${r['applied']} canciones. Pulsa "Actualizar mixes" para usarlos.'),
      ));
      final settings = context.read<SettingsProvider>();
      context.read<LibraryProvider>().loadTracks(settings.api);
    } catch (e) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    const labels = {'artist': 'Artista', 'album': 'Álbum', 'genre': 'Género', 'year': 'Año'};
    return AlertDialog(
      title: const Text('Completar géneros, años y álbumes'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: job == null
            ? const Center(child: CircularProgressIndicator())
            : job.running
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total),
                    const SizedBox(height: 12),
                    Text('Buscando en catálogos públicos (Deezer, iTunes)… ${job.done} / ${job.total}'),
                    const SizedBox(height: 6),
                    Text('Solo se completan datos vacíos. Revisarás todo antes de guardar.',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                  ])
                : job.proposals.isEmpty
                    ? _Centered(
                        icon: job.error != null ? Icons.cloud_off_rounded : Icons.check_circle_outline_rounded,
                        title: job.error ?? 'No hay nada que completar',
                        body: job.error == null ? 'No se encontraron datos nuevos con suficiente confianza.' : null,
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${job.proposals.length} canciones con datos nuevos. Marcadas: coincidencias seguras; '
                          'revisa las demás antes de incluirlas.',
                          style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: ListView.builder(
                            itemCount: job.proposals.length,
                            itemBuilder: (context, i) {
                              final p = job.proposals[i];
                              final id = (p['media_id'] as num).toInt();
                              final changes = (p['changes'] as Map).cast<String, dynamic>();
                              final confidence = ((p['confidence'] as num) * 100).round();
                              final current = (p['current'] as Map).cast<String, dynamic>();
                              return CheckboxListTile(
                                dense: true,
                                value: _selected.contains(id),
                                onChanged: (v) => setState(() => v == true ? _selected.add(id) : _selected.remove(id)),
                                title: Text(current['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  '${changes.entries.map((e) => '${labels[e.key]}: ${e.value}').join(' · ')}  ($confidence%)',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            },
                          ),
                        ),
                      ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar')),
        if (job != null && !job.running && job.proposals.isNotEmpty)
          FilledButton(
            onPressed: _saving || _selected.isEmpty ? null : _apply,
            child: Text('Guardar ${_selected.length}'),
          ),
      ],
    );
  }
}

// ── Audio analysis ───────────────────────────────────────────────────────────

class AnalyzeDialog extends StatefulWidget {
  final MixesApi api;
  const AnalyzeDialog({super.key, required this.api});

  @override
  State<AnalyzeDialog> createState() => _AnalyzeDialogState();
}

class _AnalyzeDialogState extends State<AnalyzeDialog> {
  LibraryJob? _job;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      var job = await widget.api.analyzeStatus();
      if (!job.available) {
        setState(() => _error = 'El análisis de audio no está instalado en el servidor (librosa).');
        return;
      }
      if (!job.running) job = await widget.api.analyzeStart();
      if (mounted) setState(() => _job = job);
      _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
        try {
          final j = await widget.api.analyzeStatus();
          if (!mounted) return;
          setState(() => _job = j);
          if (!j.running) _poll?.cancel();
        } catch (_) {}
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    return AlertDialog(
      title: const Text('Analizar audio'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            'Calcula el BPM, la energía y qué tan bailable es cada canción, en tu computadora y sin internet. '
            'Permite mixes como "Alta energía" o "Modo calma".',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Text(_error!, style: TextStyle(color: context.colors.error))
          else if (job == null)
            const LinearProgressIndicator()
          else if (job.running) ...[
            LinearProgressIndicator(value: job.total == 0 ? null : job.done / job.total),
            const SizedBox(height: 8),
            Text('${job.done} / ${job.total} canciones · puedes cerrar esta ventana, sigue en segundo plano'),
          ] else
            Text(
              job.total == 0
                  ? 'Todas tus canciones ya están analizadas.'
                  : 'Listo: ${job.done} canciones analizadas.${job.error != null ? ' ${job.error}' : ''} '
                      'Pulsa "Actualizar mixes" para usar los resultados.',
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}

// ── Agent help ───────────────────────────────────────────────────────────────

class AgentHelpDialog extends StatelessWidget {
  const AgentHelpDialog({super.key});

  static const _command = 'claude mcp add --transport http sonero http://127.0.0.1:8000/mcp';
  static const _prompt = 'Usa el MCP de Sonero: analiza mis estadísticas y crea 4 mixes recomendados '
      '(favoritas, descubrimiento, según el momento del día y uno sorpresa), mezclando mi biblioteca '
      'con música nueva.';

  @override
  Widget build(BuildContext context) {
    Widget copyable(String label, String text) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              decoration: BoxDecoration(
                color: context.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(children: [
                Expanded(
                  child: SelectableText(
                    text,
                    // No ligatures: "--transport" must not render as an en dash
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontFeatures: [
                      FontFeature.disable('liga'),
                      FontFeature.disable('calt'),
                    ]),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  tooltip: 'Copiar',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado.')));
                  },
                ),
              ]),
            ),
          ],
        );

    return AlertDialog(
      title: const Text('Conectar un agente IA'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Un agente como Claude Code o Claude Desktop puede leer tus estadísticas a través del servidor MCP '
              'de Sonero, buscar música nueva en internet y crear mixes que aparecerán aquí, en "Creados por tu '
              'agente IA". Sonero no envía tus datos a ninguna IA por su cuenta.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 16),
            copyable('1. Conecta Sonero (Claude Code, en una terminal)', _command),
            const SizedBox(height: 14),
            copyable('2. Pídele los mixes', _prompt),
            const SizedBox(height: 12),
            Text(
              'También puedes usar el prompt "Crear mis mixes recomendados" que ofrece el servidor. '
              'Para Claude Desktop y otros clientes, ver la sección MCP del README.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 11, height: 1.4),
            ),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
    );
  }
}
