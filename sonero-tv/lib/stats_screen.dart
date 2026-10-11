import 'package:flutter/material.dart';

import 'api.dart';
import 'player.dart';
import 'ui.dart';

/// Listening statistics from the Sonero computer (TV playback included).
class StatsScreen extends StatefulWidget {
  final SoneroApi api;
  final PlayerController player;

  const StatsScreen({super.key, required this.api, required this.player});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  static const _periods = [7, 30, 365];
  int _days = 30;
  Map<String, dynamic>? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await widget.api.stats(days: _days);
      if (mounted) setState(() => _data = data);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return Scaffold(
      body: data == null
          ? (_error == null
              ? const MessageView(icon: Icons.insights_rounded, title: 'Cargando estadísticas…')
              : MessageView(
                  icon: Icons.wifi_off_rounded,
                  title: 'No se pudieron cargar',
                  body: _error,
                  action: TvButton(icon: Icons.refresh_rounded, label: 'Reintentar', autofocus: true, onPressed: _load),
                ))
          : _buildStats(data),
    );
  }

  Widget _buildStats(Map<String, dynamic> data) {
    final s = data['summary'] as Map<String, dynamic>;
    final topTracks = (data['top_tracks'] as List).cast<Map<String, dynamic>>();
    final topArtists = (data['top_artists'] as List).cast<Map<String, dynamic>>();
    final timeline = (data['timeline'] as List).cast<Map<String, dynamic>>();
    final minutes = (s['minutes_listened'] as num?)?.toDouble() ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(80, 48, 80, 48),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Tus estadísticas', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            ),
            for (final d in _periods) ...[
              TvButton(
                icon: Icons.calendar_month_rounded,
                label: d == 7 ? '7 días' : d == 30 ? '30 días' : '1 año',
                primary: d == _days,
                autofocus: d == _days,
                onPressed: () {
                  setState(() => _days = d);
                  _load();
                },
              ),
              const SizedBox(width: 12),
            ],
            TvButton(icon: Icons.arrow_back_rounded, onPressed: () => Navigator.of(context).pop()),
          ],
        ),
        const SizedBox(height: 32),
        Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            _StatCard(label: 'Reproducciones', value: '${s['plays'] ?? 0}'),
            _StatCard(
              label: 'Tiempo escuchado',
              value: minutes >= 120 ? '${(minutes / 60).toStringAsFixed(1)} h' : '${minutes.round()} min',
            ),
            _StatCard(label: 'Canciones distintas', value: '${s['unique_tracks'] ?? 0}'),
            _StatCard(
              label: 'Racha',
              value: (s['current_streak_days'] ?? 0) == 1 ? '1 día' : '${s['current_streak_days'] ?? 0} días',
            ),
            _StatCard(label: 'Hora favorita', value: s['peak_hour'] == null ? '—' : '${s['peak_hour']}:00'),
            _StatCard(label: 'Día favorito', value: (s['peak_weekday'] as String?) ?? '—'),
          ],
        ),
        const SizedBox(height: 40),
        const _SectionTitle('Minutos por día (últimos 30)'),
        _DailyChart(series: timeline),
        const SizedBox(height: 40),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Lo más escuchado'),
                  if (topTracks.isEmpty)
                    const Text('Aún no hay reproducciones en este periodo.',
                        style: TextStyle(fontSize: 18, color: SoneroColors.muted)),
                  for (final (i, t) in topTracks.indexed) _topTrackRow(i, t),
                ],
              ),
            ),
            const SizedBox(width: 48),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _SectionTitle('Artistas'),
                  for (final (i, a) in topArtists.indexed)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 36,
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 20, color: SoneroColors.muted)),
                          ),
                          Expanded(
                            child: Text(a['artist'] as String, maxLines: 1, overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 20)),
                          ),
                          Text('${a['plays']} rep.', style: const TextStyle(fontSize: 16, color: SoneroColors.muted)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _topTrackRow(int i, Map<String, dynamic> t) {
    final id = t['track_id'] as String?;
    final track = id == null ? null : widget.player.knownTracks[id];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TvFocusable(
        onPressed: track == null ? null : () => widget.player.playQueue([track]),
        radius: 12,
        focusScale: 1.015,
        builder: (context, focused) => Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: focused ? SoneroColors.surfaceAlt : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontSize: 20, color: SoneroColors.muted))),
              CoverArt(api: widget.api, track: track, size: 56, radius: 8),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                    Text(t['artist'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, color: SoneroColors.muted)),
                  ],
                ),
              ),
              Text('${t['plays']} rep. · ${(t['minutes'] as num).round()} min',
                  style: const TextStyle(fontSize: 16, color: SoneroColors.muted)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 16, letterSpacing: 1.5, color: SoneroColors.muted)),
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  const _StatCard({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: SoneroColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 18, color: SoneroColors.muted)),
        ],
      ),
    );
  }
}

class _DailyChart extends StatelessWidget {
  final List<Map<String, dynamic>> series;
  const _DailyChart({required this.series});

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in series) (p['minutes'] as num).toDouble()];
    final maxV = values.fold<double>(0, (a, b) => a > b ? a : b);
    return Container(
      height: 180,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(color: SoneroColors.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final v in values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: FractionallySizedBox(
                        heightFactor: maxV == 0 ? 0.02 : (v / maxV).clamp(0.02, 1.0),
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          decoration: BoxDecoration(
                            color: v > 0 ? SoneroColors.accent : SoneroColors.border,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(series.isEmpty ? '' : _short(series.first['bucket'] as String),
                  style: const TextStyle(fontSize: 14, color: SoneroColors.muted)),
              Text('máx. ${maxV.round()} min', style: const TextStyle(fontSize: 14, color: SoneroColors.muted)),
              const Text('hoy', style: TextStyle(fontSize: 14, color: SoneroColors.muted)),
            ],
          ),
        ],
      ),
    );
  }

  static String _short(String isoDate) {
    final parts = isoDate.split('-');
    return parts.length == 3 ? '${parts[2]}/${parts[1]}' : isoDate;
  }
}
