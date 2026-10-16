import 'dart:math';
import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../core/api_client.dart';
import '../theme.dart';

// PNG download: browser download on web, file on Android/desktop
import 'image_download_io.dart' if (dart.library.js_interop) 'image_download_web.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> with TickerProviderStateMixin {
  bool _isLoading = true;
  String _errorMessage = '';

  // Advanced stats data
  Map<String, dynamic> _library = {};
  Map<String, dynamic> _listening = {};
  Map<String, dynamic> _topContent = {};
  Map<String, dynamic> _patterns = {};
  Map<String, dynamic> _mood = {};
  Map<String, dynamic> _trends = {};

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() { _isLoading = true; _errorMessage = ''; });

    final settings = context.read<SettingsProvider>();
    final ApiClient api = settings.api;

    try {
      await api.syncDownloads();
      final data = await api.getAdvancedStats();
      _library = Map<String, dynamic>.from(data['library'] ?? {});
      _listening = Map<String, dynamic>.from(data['listening'] ?? {});
      _topContent = Map<String, dynamic>.from(data['top_content'] ?? {});
      _patterns = Map<String, dynamic>.from(data['patterns'] ?? {});
      _mood = Map<String, dynamic>.from(data['mood'] ?? {});
      _trends = Map<String, dynamic>.from(data['trends'] ?? {});
      _errorMessage = '';
      _animController.forward(from: 0);
    } catch (e) {
      _errorMessage = 'Error al cargar estadísticas: $e';
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final accent = Theme.of(context).colorScheme.primary;
    final pad = isMobile ? 16.0 : 32.0;

    return Scaffold(
      backgroundColor: context.colors.bg,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: accent))
          : FadeTransition(
              opacity: _fadeAnim,
              child: RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: EdgeInsets.fromLTRB(pad, isMobile ? 16 : 24, pad, 100),
                  children: [
                    // ── HEADER ──
                    _buildHeader(context, isMobile, accent),
                    const SizedBox(height: 20),

                    // ── ERROR ──
                    if (_errorMessage.isNotEmpty) ...[
                      _buildError(context),
                      const SizedBox(height: 16),
                    ],

                    // ── HERO CARDS ──
                    _buildHeroCards(context, isMobile, accent),
                    const SizedBox(height: 20),

                    // ── HOY / MOOD ──
                    _buildTodayAndMood(context, isMobile, accent),
                    const SizedBox(height: 20),

                    // ── GRÁFICO 7 DÍAS ──
                    _buildWeekChart(context, isMobile, accent),
                    const SizedBox(height: 20),

                    // ── ACTIVIDAD POR HORA ──
                    _buildHourlyActivity(context, isMobile, accent),
                    const SizedBox(height: 20),

                    // ── TOP CANCIONES & ARTISTAS ──
                    if (!isMobile)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildTopSongs(context, accent)),
                          const SizedBox(width: 16),
                          Expanded(child: _buildTopArtists(context, accent)),
                        ],
                      )
                    else ...[
                      _buildTopSongs(context, accent),
                      const SizedBox(height: 16),
                      _buildTopArtists(context, accent),
                    ],
                    const SizedBox(height: 20),

                    // ── PATRONES & GÉNEROS ──
                    _buildPatternsAndGenres(context, isMobile, accent),
                  ],
                ),
              ),
            ),
    );
  }

  // ════════════════════════════════════════════
  // HEADER
  // ════════════════════════════════════════════
  Widget _buildHeader(BuildContext context, bool isMobile, Color accent) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [accent, accent.withOpacity(0.6)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Estadísticas', style: TextStyle(fontSize: isMobile ? 22 : 28, fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
              Text('Tu música en números', style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
            ],
          ),
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.pinkAccent, Colors.purpleAccent]),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.share_rounded, color: Colors.white, size: 16),
          ),
          onPressed: () => _showShareCard(context, accent),
          tooltip: 'Compartir',
        ),
        const SizedBox(width: 4),
        IconButton(icon: Icon(Icons.refresh_rounded, color: context.colors.textSecondary), onPressed: _loadData, tooltip: 'Recargar'),
      ],
    );
  }

  // ════════════════════════════════════════════
  // ERROR
  // ════════════════════════════════════════════
  Widget _buildError(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: context.colors.error, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(_errorMessage, style: TextStyle(color: context.colors.textPrimary, fontSize: 13))),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // HERO CARDS (4 big stats)
  // ════════════════════════════════════════════
  Widget _buildHeroCards(BuildContext context, bool isMobile, Color accent) {
    final cards = [
      _HeroData(Icons.music_note_rounded, '${_library['total_songs'] ?? 0}', 'Canciones', accent),
      _HeroData(Icons.videocam_rounded, '${_library['total_videos'] ?? 0}', 'Videos', Colors.pinkAccent),
      _HeroData(Icons.headphones_rounded, '${_listening['total_hours'] ?? 0}h', 'Escuchado', Colors.tealAccent.shade400),
      _HeroData(Icons.folder_rounded, '${_library['total_playlists'] ?? 0}', 'Playlists', Colors.orangeAccent),
    ];

    if (isMobile) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.6,
        children: cards.map((c) => _buildHeroCard(context, c)).toList(),
      );
    }

    return Row(
      children: cards.map((c) => Expanded(
        child: Padding(
          padding: EdgeInsets.only(right: c == cards.last ? 0 : 12),
          child: _buildHeroCard(context, c),
        ),
      )).toList(),
    );
  }

  Widget _buildHeroCard(BuildContext context, _HeroData data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: data.color.withOpacity(0.15)),
        boxShadow: [BoxShadow(color: data.color.withOpacity(0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(data.icon, color: data.color, size: 22),
          const SizedBox(height: 8),
          Text(data.value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: context.colors.textPrimary, height: 1)),
          const SizedBox(height: 2),
          Text(data.label, style: TextStyle(fontSize: 12, color: context.colors.textSecondary)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // HOY + MOOD
  // ════════════════════════════════════════════
  Widget _buildTodayAndMood(BuildContext context, bool isMobile, Color accent) {
    final minutesToday = _listening['minutes_today'] ?? 0;
    final playsToday = _listening['plays_today'] ?? 0;
    final streak = _patterns['daily_streak'] ?? 0;
    final moodLabel = _mood['mood_label'] ?? 'Equilibrado ✨';
    final moodEmoji = _mood['mood_emoji'] ?? '✨';
    final energy = (_mood['avg_energy'] ?? 0.5) as num;
    final valence = (_mood['avg_valence'] ?? 0.5) as num;
    final sizeGb = _library['total_size_gb'] ?? 0;

    final todayCard = _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.today_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text('Hoy', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('🔥 $streak días', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _miniStat(context, '$minutesToday', 'min', accent),
              const SizedBox(width: 20),
              _miniStat(context, '$playsToday', 'plays', Colors.pinkAccent),
              const SizedBox(width: 20),
              _miniStat(context, '$sizeGb', 'GB', Colors.tealAccent.shade400),
            ],
          ),
          const SizedBox(height: 12),
          // Progress bar for today (target: 60 min)
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (minutesToday as num).toDouble().clamp(0, 120) / 120,
              backgroundColor: context.colors.border.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(accent),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 4),
          Text('Meta: 2 horas diarias', style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
        ],
      ),
    );

    final moodCard = _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(moodEmoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Text('Tu Mood', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 10),
          Text(moodLabel, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: context.colors.textPrimary)),
          const SizedBox(height: 14),
          _moodBar(context, 'Energía', energy.toDouble(), Colors.orangeAccent),
          const SizedBox(height: 8),
          _moodBar(context, 'Felicidad', valence.toDouble(), Colors.greenAccent.shade400),
        ],
      ),
    );

    if (isMobile) {
      return Column(children: [todayCard, const SizedBox(height: 12), moodCard]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: todayCard), const SizedBox(width: 16), Expanded(child: moodCard)],
    );
  }

  Widget _miniStat(BuildContext context, String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color, height: 1)),
        Text(label, style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
      ],
    );
  }

  Widget _moodBar(BuildContext context, String label, double value, Color color) {
    return Row(
      children: [
        SizedBox(width: 65, child: Text(label, style: TextStyle(fontSize: 12, color: context.colors.textSecondary))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: value,
              backgroundColor: context.colors.border.withOpacity(0.15),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 6,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('${(value * 100).toInt()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.colors.textSecondary)),
      ],
    );
  }

  // ════════════════════════════════════════════
  // 7 DAY CHART
  // ════════════════════════════════════════════
  Widget _buildWeekChart(BuildContext context, bool isMobile, Color accent) {
    final trend = (_trends['listening_trend_7d'] as List<dynamic>?) ?? [];
    if (trend.isEmpty) return const SizedBox.shrink();

    final maxHours = trend.map((d) => (d['hours'] as num?) ?? 0).reduce((a, b) => a > b ? a : b);
    final maxVal = maxHours == 0 ? 1.0 : maxHours.toDouble();

    return _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text('Últimos 7 días', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
              const Spacer(),
              Text('${_listening['hours_this_week'] ?? 0}h total', style: TextStyle(fontSize: 12, color: accent, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.map<Widget>((day) {
                final hours = ((day['hours'] as num?) ?? 0).toDouble();
                final plays = (day['plays'] as int?) ?? 0;
                final name = (day['day_name'] as String?) ?? '';
                final barHeight = maxVal > 0 ? (hours / maxVal) * 90 : 0.0;
                final isToday = trend.indexOf(day) == trend.length - 1;
                
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${hours.toStringAsFixed(1)}h', style: TextStyle(fontSize: 9, color: context.colors.textSecondary, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Container(
                          height: max(barHeight, 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: isToday
                                  ? [accent, accent.withOpacity(0.6)]
                                  : [accent.withOpacity(0.4), accent.withOpacity(0.15)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(name.substring(0, min(3, name.length)), style: TextStyle(fontSize: 10, color: isToday ? accent : context.colors.textSecondary, fontWeight: isToday ? FontWeight.w700 : FontWeight.w400)),
                        Text('$plays', style: TextStyle(fontSize: 9, color: context.colors.textSecondary.withOpacity(0.5))),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // HOURLY ACTIVITY HEATMAP
  // ════════════════════════════════════════════
  Widget _buildHourlyActivity(BuildContext context, bool isMobile, Color accent) {
    final byHour = (_patterns['listening_by_hour'] as List<dynamic>?) ?? List.filled(24, 0);
    final maxCount = byHour.map((e) => (e as num).toInt()).reduce((a, b) => a > b ? a : b);
    final maxVal = maxCount == 0 ? 1 : maxCount;
    final peakHour = _patterns['peak_hour'] ?? '0:00';

    return _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.access_time_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text('Actividad por hora', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: accent.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text('⏰ Pico: $peakHour', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(24, (h) {
              final count = (byHour[h] as num).toInt();
              final intensity = count / maxVal;
              return Tooltip(
                message: '$h:00 - $count reproducciones',
                child: Container(
                  width: isMobile ? ((MediaQuery.of(context).size.width - 64) / 12 - 4) : 36,
                  height: isMobile ? 24 : 28,
                  decoration: BoxDecoration(
                    color: count == 0
                        ? context.colors.border.withOpacity(0.1)
                        : accent.withOpacity(0.15 + intensity * 0.85),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: Text('${h}h', style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w600,
                    color: count > 0 ? Colors.white : context.colors.textSecondary.withOpacity(0.4),
                  )),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // TOP SONGS
  // ════════════════════════════════════════════
  Widget _buildTopSongs(BuildContext context, Color accent) {
    final songs = (_topContent['top_songs'] as List<dynamic>?) ?? [];
    return _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.queue_music_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text('Top Canciones', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          if (songs.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Escucha música para ver tu top', style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
            )
          else
            ...songs.take(5).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final s = entry.value;
              final medals = ['🥇', '🥈', '🥉'];
              final medal = i < 3 ? medals[i] : '${i + 1}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(width: 24, child: Text(medal, style: TextStyle(fontSize: i < 3 ? 16 : 13, color: context.colors.textSecondary), textAlign: TextAlign.center)),
                    const SizedBox(width: 10),
                    if ((s['cover_url'] ?? '').isNotEmpty)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network('${context.read<SettingsProvider>().apiUrl}${s['cover_url']}', width: 36, height: 36, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(width: 36, height: 36, color: context.colors.surfaceAlt, child: Icon(Icons.music_note, size: 16, color: context.colors.textSecondary))),
                      )
                    else
                      Container(width: 36, height: 36, decoration: BoxDecoration(color: context.colors.surfaceAlt, borderRadius: BorderRadius.circular(6)),
                        child: Icon(Icons.music_note, size: 16, color: context.colors.textSecondary)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['title'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textPrimary), overflow: TextOverflow.ellipsis),
                          Text(s['artist'] ?? '', style: TextStyle(fontSize: 11, color: context.colors.textSecondary), overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: accent.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                      child: Text('${s['plays']}x', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: accent)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // TOP ARTISTS
  // ════════════════════════════════════════════
  Widget _buildTopArtists(BuildContext context, Color accent) {
    final artists = (_topContent['top_artists'] as List<dynamic>?) ?? [];
    final colors = [accent, Colors.pinkAccent, Colors.tealAccent.shade400, Colors.orangeAccent, Colors.purpleAccent];

    return _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text('Top Artistas', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          if (artists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Escucha música para ver tu top', style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
            )
          else
            ...artists.take(5).toList().asMap().entries.map((entry) {
              final i = entry.key;
              final a = entry.value;
              final maxPlays = (artists.first['plays'] as num?) ?? 1;
              final plays = (a['plays'] as num?) ?? 0;
              final barWidth = maxPlays > 0 ? plays / maxPlays : 0.0;
              final c = colors[i % colors.length];

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 28, height: 28,
                          decoration: BoxDecoration(color: c.withOpacity(0.15), shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: Text('${i + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: c)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(a['artist'] ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.colors.textPrimary), overflow: TextOverflow.ellipsis)),
                        Text('${a['plays']} plays', style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: barWidth.toDouble(),
                        backgroundColor: context.colors.border.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(c.withOpacity(0.6)),
                        minHeight: 4,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // PATTERNS & GENRES
  // ════════════════════════════════════════════
  Widget _buildPatternsAndGenres(BuildContext context, bool isMobile, Color accent) {
    final byDay = (_patterns['listening_by_day'] as List<dynamic>?) ?? [];
    final genres = (_topContent['top_genres'] as List<dynamic>?) ?? [];
    final peakDay = _patterns['peak_day'] ?? 'N/A';
    final newArtists = _trends['new_artists_this_month'] ?? 0;
    final completionRate = _listening['completion_rate'] ?? 0;

    final patternsCard = _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.insights_rounded, color: accent, size: 18),
              const SizedBox(width: 8),
              Text('Patrones', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 16),
          _infoRow(context, '📅 Día favorito', peakDay, accent),
          _infoRow(context, '⏰ Hora pico', _patterns['peak_hour'] ?? '0:00', Colors.orangeAccent),
          _infoRow(context, '🔥 Racha', '${_patterns['daily_streak'] ?? 0} días', Colors.redAccent),
          _infoRow(context, '🎯 Completadas', '$completionRate%', Colors.greenAccent.shade400),
          _infoRow(context, '🆕 Artistas nuevos', '$newArtists este mes', Colors.purpleAccent),
          const SizedBox(height: 12),
          // Day of week mini bars
          if (byDay.isNotEmpty) ...[
            Text('Por día de la semana:', style: TextStyle(fontSize: 11, color: context.colors.textSecondary)),
            const SizedBox(height: 8),
            ...byDay.map((d) {
              final count = (d['count'] as num?)?.toInt() ?? 0;
              final maxDayCount = byDay.map((x) => (x['count'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b);
              final w = maxDayCount > 0 ? count / maxDayCount : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(width: 30, child: Text((d['day'] as String?)?.substring(0, 3) ?? '', style: TextStyle(fontSize: 10, color: context.colors.textSecondary))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(value: w, backgroundColor: context.colors.border.withOpacity(0.1), valueColor: AlwaysStoppedAnimation(accent.withOpacity(0.5)), minHeight: 6),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(width: 24, child: Text('$count', style: TextStyle(fontSize: 10, color: context.colors.textSecondary), textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );

    final genresCard = _buildGlassCard(
      context,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.category_rounded, color: Colors.pinkAccent, size: 18),
              const SizedBox(width: 8),
              Text('Géneros', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: context.colors.textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          if (genres.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(child: Text('Sin datos de géneros', style: TextStyle(color: context.colors.textSecondary, fontSize: 13))),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: genres.take(10).toList().asMap().entries.map((entry) {
                final g = entry.value;
                final genreColors = [accent, Colors.pinkAccent, Colors.tealAccent.shade400, Colors.orangeAccent, Colors.purpleAccent, Colors.blueAccent, Colors.greenAccent.shade400, Colors.redAccent, Colors.indigoAccent, Colors.amber];
                final c = genreColors[entry.key % genreColors.length];
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: c.withOpacity(0.2)),
                  ),
                  child: Text('${g['genre']} (${g['count']})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
                );
              }).toList(),
            ),
        ],
      ),
    );

    if (isMobile) {
      return Column(children: [patternsCard, const SizedBox(height: 12), genresCard]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [Expanded(child: patternsCard), const SizedBox(width: 16), Expanded(child: genresCard)],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: context.colors.textSecondary)),
          const Spacer(),
          Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  // GLASS CARD HELPER
  // ════════════════════════════════════════════
  Widget _buildGlassCard(BuildContext context, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border.withOpacity(0.08)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: child,
    );
  }

  // ════════════════════════════════════════════
  // SHARE CARD
  // ════════════════════════════════════════════
  void _showShareCard(BuildContext context, Color accent) {
    final totalHours = _listening['total_hours'] ?? 0;
    final moodLabel = (_mood['mood_label'] ?? 'Equilibrado').toString().replaceAll(RegExp(r'[^\w\sáéíóúñÑ]'), '').trim();

    final topArtists = (_topContent['top_artists'] as List<dynamic>?) ?? [];
    final topSongs = (_topContent['top_songs'] as List<dynamic>?) ?? [];
    final topGenres = (_topContent['top_genres'] as List<dynamic>?) ?? [];
    final topAlbums = (_topContent['top_albums'] as List<dynamic>?) ?? [];

    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => _ShareCardDialog(
        accent: accent,
        totalHours: totalHours,
        moodLabel: moodLabel,
        topArtists: topArtists,
        topSongs: topSongs,
        topGenres: topGenres,
        topAlbums: topAlbums,
      ),
    );
  }
}

// ════════════════════════════════════════════
// SHARE DIALOG
// ════════════════════════════════════════════
class _ShareCardDialog extends StatefulWidget {
  final Color accent;
  final dynamic totalHours;
  final String moodLabel;
  final List<dynamic> topArtists, topSongs, topGenres, topAlbums;

  const _ShareCardDialog({
    required this.accent, required this.totalHours,
    required this.moodLabel, required this.topArtists,
    required this.topSongs, required this.topGenres,
    required this.topAlbums,
  });

  @override
  State<_ShareCardDialog> createState() => _ShareCardDialogState();
}

class _ShareCardDialogState extends State<_ShareCardDialog> {
  int _format = 0;
  int _currentSlide = 0;
  final _postKey = GlobalKey();
  final _storyKey = GlobalKey();
  final _slideKeys = List.generate(6, (_) => GlobalKey());
  bool _busy = false;

  String _val(List<dynamic> list, int i, String field) {
    if (i >= list.length) return '—';
    return (list[i][field] ?? '—').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(color: const Color(0xFF1e1e2a), borderRadius: BorderRadius.circular(10)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [_tab('Post', 0), _tab('Historia', 1), _tab('Video', 2)],
              ),
            ),
            const SizedBox(height: 16),
            if (_format == 0) RepaintBoundary(key: _postKey, child: _postCard())
            else if (_format == 1) RepaintBoundary(key: _storyKey, child: _storyCard())
            else _videoCarousel(),
            const SizedBox(height: 16),
            _busy
              ? const SizedBox(height: 44, child: Center(child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : FilledButton.icon(
                  onPressed: _format == 2 ? _downloadSlides : _download,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: Text(_format == 0 ? 'Descargar 1080×1080' : _format == 1 ? 'Descargar 1080×1920' : 'Descargar 6 slides', style: const TextStyle(fontSize: 13)),
                  style: FilledButton.styleFrom(backgroundColor: widget.accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                ),
            const SizedBox(height: 6),
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cerrar', style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13))),
          ],
        ),
      ),
    );
  }

  Widget _tab(String label, int idx) {
    final on = _format == idx;
    return GestureDetector(
      onTap: () => setState(() => _format = idx),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(color: on ? widget.accent.withOpacity(0.9) : Colors.transparent, borderRadius: BorderRadius.circular(8)),
        child: Text(label, style: TextStyle(color: on ? Colors.white : Colors.white38, fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }

  // ═══ POST 1:1 (360×360) ═══
  Widget _postCard() {
    return Container(
      width: 360, height: 360,
      color: const Color(0xFF0e0e14),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Image.asset('assets/images/logo.png', width: 100, height: 28, fit: BoxFit.contain),
            const SizedBox(height: 10),
            Text('${widget.totalHours}h', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: Colors.white, height: 1, letterSpacing: -1)),
            Text('escuchadas', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.25))),
            const SizedBox(height: 10),
            Container(height: 0.5, color: Colors.white.withOpacity(0.06)),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _postCol('Artistas', widget.topArtists, 'artist')),
                  Container(width: 0.5, color: Colors.white.withOpacity(0.04), margin: const EdgeInsets.symmetric(horizontal: 6)),
                  Expanded(child: _postCol('Canciones', widget.topSongs, 'title')),
                  Container(width: 0.5, color: Colors.white.withOpacity(0.04), margin: const EdgeInsets.symmetric(horizontal: 6)),
                  Expanded(child: _postCol('Géneros', widget.topGenres, 'genre')),
                ],
              ),
            ),
            Container(height: 0.5, color: Colors.white.withOpacity(0.06)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Álbumes', style: TextStyle(fontSize: 7, color: Colors.white.withOpacity(0.2))),
                  for (int i = 0; i < min(3, widget.topAlbums.length); i++)
                    Text(_val(widget.topAlbums, i, 'album'), style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.45)), maxLines: 1, overflow: TextOverflow.ellipsis),
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Mood', style: TextStyle(fontSize: 7, color: Colors.white.withOpacity(0.2))),
                  Text(widget.moodLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: widget.accent.withOpacity(0.8))),
                ]),
              ],
            ),
            const SizedBox(height: 2),
            Text(_month(), style: TextStyle(fontSize: 7, color: Colors.white.withOpacity(0.1))),
          ],
        ),
      ),
    );
  }

  Widget _postCol(String title, List<dynamic> items, String field) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.2), letterSpacing: 0.5)),
      const SizedBox(height: 3),
      for (int i = 0; i < 3; i++) ...[
        if (i > 0) const SizedBox(height: 3),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${i + 1}', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: widget.accent.withOpacity(i == 0 ? 0.7 : 0.3))),
          const SizedBox(width: 3),
          Expanded(child: Text(_val(items, i, field), style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(i == 0 ? 0.8 : 0.4), fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400), maxLines: 2, overflow: TextOverflow.ellipsis)),
        ]),
      ],
    ]);
  }

  // ═══ STORY 9:16 (270×480) ═══
  Widget _storyCard() {
    return Container(
      width: 270, height: 480,
      color: const Color(0xFF0e0e14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Column(
          children: [
            Image.asset('assets/images/logo.png', width: 120, height: 32, fit: BoxFit.contain),
            const SizedBox(height: 14),
            Text('${widget.totalHours}h', style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Colors.white, height: 1, letterSpacing: -2)),
            Text('escuchadas', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.25))),
            const SizedBox(height: 12),
            Container(height: 0.5, color: Colors.white.withOpacity(0.05)),
            const SizedBox(height: 10),
            _storyTop3('Top Artistas', widget.topArtists, 'artist'),
            const SizedBox(height: 8),
            _storyTop3('Top Canciones', widget.topSongs, 'title'),
            const SizedBox(height: 8),
            _storyTop3('Top Álbumes', widget.topAlbums, 'album'),
            const SizedBox(height: 8),
            Row(children: [
              Text('Géneros  ', style: TextStyle(fontSize: 7, color: Colors.white.withOpacity(0.2))),
              Expanded(child: Text(List.generate(min(3, widget.topGenres.length), (i) => _val(widget.topGenres, i, 'genre')).join(' · '), style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.5), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ]),
            const Spacer(),
            Container(height: 0.5, color: Colors.white.withOpacity(0.04)),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.favorite_rounded, size: 12, color: widget.accent.withOpacity(0.5)),
              const SizedBox(width: 5),
              Text(widget.moodLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: widget.accent.withOpacity(0.8))),
            ]),
            const SizedBox(height: 6),
            Text(_month(), style: TextStyle(fontSize: 7, color: Colors.white.withOpacity(0.1))),
          ],
        ),
      ),
    );
  }

  Widget _storyTop3(String title, List<dynamic> items, String field) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.2), letterSpacing: 0.5)),
      const SizedBox(height: 3),
      for (int i = 0; i < min(3, max(1, items.length)); i++)
        Padding(padding: const EdgeInsets.only(bottom: 1), child: Row(children: [
          Container(width: 13, height: 13, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.accent.withOpacity(i == 0 ? 0.6 : i == 1 ? 0.3 : 0.15)), alignment: Alignment.center,
            child: Text('${i + 1}', style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w700, color: Colors.white))),
          const SizedBox(width: 5),
          Expanded(child: Text(_val(items, i, field), style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(i == 0 ? 0.8 : 0.4), fontWeight: i == 0 ? FontWeight.w600 : FontWeight.w400), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])),
    ]);
  }

  // ═══ VIDEO CAROUSEL (6 slides) ═══
  Widget _videoCarousel() {
    final slides = _buildSlides();
    return Column(children: [
      Stack(alignment: Alignment.center, children: [
        for (int i = 0; i < slides.length; i++)
          Offstage(offstage: i != _currentSlide, child: RepaintBoundary(key: _slideKeys[i], child: _slideWidget(slides[i], i))),
        Positioned(left: 0, child: _currentSlide > 0 ? IconButton(onPressed: () => setState(() => _currentSlide--), icon: const Icon(Icons.chevron_left_rounded, color: Colors.white54, size: 28)) : const SizedBox(width: 40)),
        Positioned(right: 0, child: _currentSlide < slides.length - 1 ? IconButton(onPressed: () => setState(() => _currentSlide++), icon: const Icon(Icons.chevron_right_rounded, color: Colors.white54, size: 28)) : const SizedBox(width: 40)),
      ]),
      const SizedBox(height: 10),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(slides.length, (i) => Container(
        width: i == _currentSlide ? 16 : 6, height: 6, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(3), color: i == _currentSlide ? widget.accent : Colors.white.withOpacity(0.15)),
      ))),
    ]);
  }

  List<_SlideInfo> _buildSlides() => [
    _SlideInfo('horas', '${widget.totalHours}h', 'escuchadas', Icons.headphones_rounded, null),
    _SlideInfo('top artistas', null, null, Icons.person_rounded, widget.topArtists.take(3).map((a) => a['artist']?.toString() ?? '—').toList()),
    _SlideInfo('top canciones', null, null, Icons.music_note_rounded, widget.topSongs.take(3).map((s) => s['title']?.toString() ?? '—').toList()),
    _SlideInfo('top álbumes', null, null, Icons.album_rounded, widget.topAlbums.take(3).map((a) => a['album']?.toString() ?? '—').toList()),
    _SlideInfo('top géneros', null, null, Icons.library_music_rounded, widget.topGenres.take(3).map((g) => g['genre']?.toString() ?? '—').toList()),
    _SlideInfo('mi mood', widget.moodLabel, 'estado de ánimo', Icons.favorite_rounded, null),
  ];

  Widget _slideWidget(_SlideInfo s, int idx) {
    final ac = [const Color(0xFF1a0a2e), const Color(0xFF0f3460), const Color(0xFF1a2a1a), const Color(0xFF3d0a0a), const Color(0xFF2a1a0a), const Color(0xFF2a0a2a)][idx];
    return Container(
      width: 270, height: 480, color: const Color(0xFF0e0e14),
      child: Stack(children: [
        Positioned(bottom: 0, left: 0, right: 0, child: Container(height: 200, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [ac.withOpacity(0.4), Colors.transparent])))),
        Padding(padding: const EdgeInsets.all(28), child: Column(children: [
          Image.asset('assets/images/logo.png', width: 100, height: 28, fit: BoxFit.contain),
          const SizedBox(height: 4),
          Text('${idx + 1} / 6', style: TextStyle(fontSize: 9, color: Colors.white.withOpacity(0.12))),
          const Spacer(),
          Icon(s.icon, size: 28, color: widget.accent.withOpacity(0.4)),
          const SizedBox(height: 10),
          Text(s.title.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white.withOpacity(0.2), letterSpacing: 1.5)),
          const SizedBox(height: 10),
          if (s.value != null) ...[
            Text(s.value!, style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.white, height: 1)),
            if (s.sub != null) Text(s.sub!, style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.25))),
          ],
          if (s.items != null)
            for (int i = 0; i < s.items!.length; i++)
              Padding(padding: const EdgeInsets.only(bottom: 6), child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 18, height: 18, decoration: BoxDecoration(shape: BoxShape.circle, color: widget.accent.withOpacity(i == 0 ? 0.6 : i == 1 ? 0.3 : 0.15)), alignment: Alignment.center,
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white))),
                const SizedBox(width: 8),
                Flexible(child: Text(s.items![i], style: TextStyle(fontSize: 16, fontWeight: i == 0 ? FontWeight.w700 : FontWeight.w400, color: Colors.white.withOpacity(i == 0 ? 0.85 : 0.5)), maxLines: 1, overflow: TextOverflow.ellipsis)),
              ])),
          const Spacer(),
          Container(height: 0.5, color: Colors.white.withOpacity(0.04)),
          const SizedBox(height: 8),
          Text(_month(), style: TextStyle(fontSize: 8, color: Colors.white.withOpacity(0.1))),
        ])),
      ]),
    );
  }

  String _month() {
    const m = ['Ene', 'Feb', 'Mar', 'Abr', 'May', 'Jun', 'Jul', 'Ago', 'Sep', 'Oct', 'Nov', 'Dic'];
    final n = DateTime.now();
    return '${m[n.month - 1]} ${n.year}';
  }

  Future<void> _downloadSlides() async {
    setState(() => _busy = true);
    try {
      for (int i = 0; i < 6; i++) { setState(() => _currentSlide = i); await Future.delayed(const Duration(milliseconds: 100)); }
      for (int i = 0; i < 6; i++) {
        setState(() => _currentSlide = i);
        await Future.delayed(const Duration(milliseconds: 50));
        final boundary = _slideKeys[i].currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) continue;
        final image = await boundary.toImage(pixelRatio: 4.0);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        if (data == null) continue;
        await saveImageBytes(data.buffer.asUint8List(), 'sonero_slide_${i + 1}.png');
        await Future.delayed(const Duration(milliseconds: 300));
      }
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('6 slides descargados'), backgroundColor: widget.accent, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _download() async {
    setState(() => _busy = true);
    try {
      final key = _format == 0 ? _postKey : _storyKey;
      final boundary = key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Error');
      final ratio = _format == 0 ? 3.0 : 4.0;
      final image = await boundary.toImage(pixelRatio: ratio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw Exception('Error');
      await saveImageBytes(data.buffer.asUint8List(), 'sonero_${_format == 0 ? "post" : "story"}.png');
      if (mounted) { Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Descargado ${_format == 0 ? "1080×1080" : "1080×1920"}'), backgroundColor: widget.accent, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)))); }
    } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
}

class _HeroData {
  final IconData icon; final String value; final String label; final Color color;
  const _HeroData(this.icon, this.value, this.label, this.color);
}

class _SlideInfo {
  final String title; final String? value; final String? sub; final IconData icon; final List<String>? items;
  const _SlideInfo(this.title, this.value, this.sub, this.icon, this.items);
}

