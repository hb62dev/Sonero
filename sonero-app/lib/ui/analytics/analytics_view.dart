import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/settings_provider.dart';
import '../../core/api_client.dart';
import '../theme.dart';
import '../auth/auth_dialog.dart';

class AnalyticsView extends StatefulWidget {
  const AnalyticsView({super.key});

  @override
  State<AnalyticsView> createState() => _AnalyticsViewState();
}

class _AnalyticsViewState extends State<AnalyticsView> with SingleTickerProviderStateMixin {
  String? _lastLoadedUserId;
  
  bool _isLoading = true;
  String _errorMessage = '';
  
  // Real stats gathered from backend
  double _totalHours = 0.0;
  int _completedCount = 0;
  int _musicCount = 0;
  List<dynamic> _history = [];
  
  // Smart features data
  Map<String, dynamic>? _bpmAnalysis;
  List<dynamic> _prioritizedTracks = [];
  Map<String, dynamic>? _currentMood;
  List<dynamic> _isoQueue = [];
  Map<String, dynamic>? _weeklyReport;
  
  // Focus Session Status
  bool _isFocusSessionActive = false;
  int? _activeSessionId;
  DateTime? _focusSessionStart;
  
  // Controllers
  final TextEditingController _apiKeyController = TextEditingController();
  bool _isSavingKey = false;
  bool _isGeneratingReport = false;
  bool _isEndingSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final userId = context.watch<SettingsProvider>().currentUserId;
    if (userId != _lastLoadedUserId) {
      _loadData();
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final settings = context.read<SettingsProvider>();
    final ApiClient api = settings.api;
    final userId = settings.currentUserId;
    _lastLoadedUserId = userId;

    try {
      // 1. Fetch active focus session
      final activeSessionRes = await api.getActiveFocusSession(userId);
      _isFocusSessionActive = activeSessionRes['active'] ?? false;
      if (_isFocusSessionActive && activeSessionRes['session'] != null) {
        _activeSessionId = activeSessionRes['session']['id'];
        final startStr = activeSessionRes['session']['started_at'];
        if (startStr != null) {
          _focusSessionStart = DateTime.parse(startStr);
        }
      } else {
        _activeSessionId = null;
        _focusSessionStart = null;
      }

      // 2. Fetch playback history to compute real metrics
      final historyList = await api.getPlaybackHistory();
      _history = historyList;
      
      // Calculate stats
      double secondsWatched = 0.0;
      int completed = 0;
      int music = 0;
      for (var event in historyList) {
        secondsWatched += (event['duration_watched'] ?? 0.0) as double;
        if (event['completed'] == true) {
          completed++;
        }
        music++; // Assume each playback log is a track
      }
      
      _totalHours = secondsWatched / 3600.0;
      _completedCount = completed;
      _musicCount = music;

      // 3. Fetch optimal BPM range
      final bpmRes = await api.getOptimalBpm(userId);
      _bpmAnalysis = bpmRes['bpm_analysis'];
      _prioritizedTracks = bpmRes['prioritized_tracks'] ?? [];

      // 4. Fetch current mood
      _currentMood = await api.getCurrentMood(userId);

      // Clean default values or errors
      _errorMessage = '';
    } catch (e) {
      _errorMessage = 'Error al cargar datos del backend: $e';
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _toggleFocusSession() async {
    final settings = context.read<SettingsProvider>();
    final api = settings.api;
    final userId = settings.currentUserId;

    if (_isFocusSessionActive) {
      // End Focus Session
      if (_activeSessionId == null) return;
      setState(() {
        _isEndingSession = true;
      });

      try {
        final res = await api.endFocusSession(_activeSessionId!);
        final score = res['focus_score'] ?? 0.0;
        final totalSkips = res['total_skips'] ?? 0;
        
        setState(() {
          _isFocusSessionActive = false;
          _activeSessionId = null;
          _focusSessionStart = null;
        });

        // Show a beautiful score summary dialog
        if (mounted) {
          _showFocusScoreDialog(score as double, totalSkips as int);
        }
      } catch (e) {
        _showSnackBar('Error al finalizar sesión de enfoque: $e', isError: true);
      } finally {
        setState(() {
          _isEndingSession = false;
        });
        _loadData();
      }
    } else {
      // Start Focus Session
      try {
        final res = await api.startFocusSession(userId);
        setState(() {
          _isFocusSessionActive = true;
          _activeSessionId = res['session_id'];
          _focusSessionStart = DateTime.now();
        });
        _showSnackBar('¡Sesión de enfoque iniciada! Concéntrate en tus tareas.');
      } catch (e) {
        _showSnackBar('Error al iniciar sesión de enfoque: $e', isError: true);
      }
    }
  }

  void _showFocusScoreDialog(double score, int skips) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🎯 Sesión de Enfoque Concluida', textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 16),
            Text(
              '${(score * 100).toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 64, 
                fontWeight: FontWeight.bold, 
                color: Theme.of(context).colorScheme.primary
              ),
            ).animate().scale(duration: 600.ms, curve: Curves.elasticOut),
            const Text('Índice de Enfoque (Focus Score)', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPopupStat('Saltos', '$skips', Icons.skip_next_outlined),
                _buildPopupStat('Calidad', score >= 0.7 ? 'Excelente' : score >= 0.4 ? 'Media' : 'Baja', Icons.verified_user_outlined),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              score >= 0.7 
                  ? '¡Excelente trabajo! Has logrado un estado de flujo óptimo.' 
                  : score >= 0.4 
                      ? 'Buen ritmo, pero intenta evitar saltar canciones instrumentales para mejorar tu enfoque.'
                      : 'Muchas interrupciones. Prueba a activar el filtro de BPM Barroco/Lo-Fi.',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Entendido'),
          )
        ],
      ),
    );
  }

  Widget _buildPopupStat(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: context.colors.textSecondary, size: 20),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Future<void> _saveGeminiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) {
      _showSnackBar('Por favor ingresa una clave válida.', isError: true);
      return;
    }

    setState(() {
      _isSavingKey = true;
    });

    try {
      final settings = context.read<SettingsProvider>();
      await settings.api.saveGeminiKey(key);
      _apiKeyController.clear();
      _showSnackBar('Clave API de Gemini guardada correctamente en la base de datos.');
    } catch (e) {
      _showSnackBar('Error al guardar la clave API: $e', isError: true);
    } finally {
      setState(() {
        _isSavingKey = false;
      });
    }
  }

  Future<void> _generateWeeklyReport() async {
    setState(() {
      _isGeneratingReport = true;
    });

    try {
      final settings = context.read<SettingsProvider>();
      final reportRes = await settings.api.getWeeklyProductivityReport(settings.currentUserId);
      setState(() {
        _weeklyReport = reportRes;
      });
      _showSnackBar('¡Reporte semanal de productividad musical generado!');
    } catch (e) {
      _showSnackBar('Error al generar el reporte: $e', isError: true);
    } finally {
      setState(() {
        _isGeneratingReport = false;
      });
    }
  }

  Future<void> _generateIsoQueue() async {
    try {
      final settings = context.read<SettingsProvider>();
      final queueRes = await settings.api.getIsoPrincipleQueue(settings.currentUserId);
      setState(() {
        _isoQueue = queueRes['queue'] ?? [];
      });
      _showSnackBar('¡Cola de Ecualización Emocional (Iso-Principle) cargada!');
    } catch (e) {
      _showSnackBar('Error al generar la cola Iso: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? context.colors.error : context.colors.success,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    if (_isLoading) {
      return Scaffold(
        backgroundColor: context.colors.bg,
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final double focusValence = _currentMood?['valence'] ?? 0.5;
    final double focusEnergy = _currentMood?['energy'] ?? 0.5;
    final String moodDescription = _currentMood?['description'] ?? 'Calma/Relajado';
    final String moodQuadrant = _currentMood?['quadrant'] ?? 'Baja Energía, Alta Valencia';
    
    // BPM analysis
    final String rangeName = _bpmAnalysis?['range_name'] ?? 'Barroco/Lo-Fi (60-90 BPM)';
    final List<dynamic> optimalRange = _bpmAnalysis?['optimal_range'] ?? [60, 90];
    final double? baroqueRate = _bpmAnalysis?['baroque_skip_rate'] != null ? (_bpmAnalysis!['baroque_skip_rate'] as num).toDouble() : null;
    final double? technoRate = _bpmAnalysis?['techno_skip_rate'] != null ? (_bpmAnalysis!['techno_skip_rate'] as num).toDouble() : null;

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Música Inteligente & Productividad', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar Datos',
            onPressed: _loadData,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSyncHeader(context, settings),
              const SizedBox(height: 24),
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: context.colors.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: context.colors.error)
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: context.colors.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _errorMessage, 
                          style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold)
                        ),
                      ),
                    ],
                  ),
                ),
                
              Text(
                'Tus Hábitos Semanales',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
              ).animate().fadeIn(duration: 300.ms),
              const SizedBox(height: 16),
              
              // ── Stat Cards ─────────────────────────────────────────────────
              Row(
                children: [
                  _buildStatCard(
                    context, 
                    'Horas de enfoque', 
                    '${_totalHours.toStringAsFixed(1)} h', 
                    Icons.timer, 
                    Theme.of(context).colorScheme.primary
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    context, 
                    'Completadas', 
                    '$_completedCount', 
                    Icons.check_circle_outline, 
                    context.colors.success
                  ),
                  const SizedBox(width: 16),
                  _buildStatCard(
                    context, 
                    'Música Escuchada', 
                    '$_musicCount', 
                    Icons.music_note, 
                    Colors.orange
                  ),
                ],
              ).animate().fade(duration: 400.ms).slideX(begin: 0.1, end: 0),
              
              const SizedBox(height: 32),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left Column: Focus Session & BPM
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Focus Session control card
                        _buildFocusSessionCard(),
                        const SizedBox(height: 24),
                        // BPM analysis card
                        _buildBpmAnalysisCard(rangeName, optimalRange, baroqueRate, technoRate),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Right Column: Russell Model mood tracking & Iso principle
                  Expanded(
                    flex: 5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildMoodCircumplexCard(focusValence, focusEnergy, moodDescription, moodQuadrant),
                        const SizedBox(height: 24),
                        _buildIsoPrincipleCard(),
                      ],
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 32),
              
              // Gemini Section: Weekly Report & Key Configuration
              Text(
                'Inteligencia Artificial (Gemini API)',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
              ),
              const SizedBox(height: 16),
              _buildGeminiSectionCard(),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.colors.border.withOpacity(0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4)
            )
          ]
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withOpacity(0.1),
              radius: 24,
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: context.colors.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusSessionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🎯 Sesión de Enfoque',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_isFocusSessionActive)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Theme.of(context).colorScheme.primary)
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Activa',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isFocusSessionActive
                  ? 'El sistema está registrando tu telemetría de forma automática en segundo plano. Evita realizar saltos de canción.'
                  : 'El tracking es 100% automático al reproducir música. Puedes usar este botón si deseas iniciar un bloque de tiempo de forma manual.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_isFocusSessionActive && _focusSessionStart != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Text(
                  'Iniciada a las: ${_focusSessionStart!.toLocal().toString().substring(11, 16)} hs',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: _isEndingSession
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isFocusSessionActive 
                            ? context.colors.error 
                            : Theme.of(context).colorScheme.primary
                      ),
                      icon: Icon(_isFocusSessionActive ? Icons.stop : Icons.play_arrow),
                      label: Text(_isFocusSessionActive ? 'Finalizar Sesión' : 'Iniciar Sesión'),
                      onPressed: _toggleFocusSession,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBpmAnalysisCard(String rangeName, List<dynamic> range, double? baroqueRate, double? technoRate) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚡ Filtro de BPM Óptimo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rangeName,
                        style: TextStyle(
                          fontSize: 16, 
                          fontWeight: FontWeight.bold, 
                          color: Theme.of(context).colorScheme.primary
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Rango ideal para reducir tu tasa de saltos (skips).',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 32),
            const Text(
              'Tasas de salto por género (Histórico)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildBpmRateRow('Barroco/Lo-Fi (60-90 BPM)', baroqueRate),
            const SizedBox(height: 8),
            _buildBpmRateRow('Techno/Deep House (120-140 BPM)', technoRate),
            
            if (_prioritizedTracks.isNotEmpty) ...[
              const Divider(height: 32),
              Text(
                'Canciones instrumentales recomendadas (${_prioritizedTracks.length})',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _prioritizedTracks.length,
                  itemBuilder: (ctx, idx) {
                    final t = _prioritizedTracks[idx];
                    return Container(
                      width: 150,
                      margin: const EdgeInsets.only(right: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.bg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.border.withOpacity(0.3))
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            t['title'] ?? 'Instrumental',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          Text(
                            t['artist'] ?? 'Desconocido',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 10),
                          ),
                          const Spacer(),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${t['bpm']?.toInt()} BPM', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 10, fontWeight: FontWeight.bold)),
                              Icon(Icons.multitrack_audio, size: 14, color: context.colors.textSecondary),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildBpmRateRow(String range, double? rate) {
    final hasData = rate != null;
    final pctStr = hasData ? '${(rate * 100).toStringAsFixed(1)}%' : 'Sin datos';
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(range, style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
        Row(
          children: [
            if (hasData)
              Container(
                width: 60,
                height: 8,
                margin: const EdgeInsets.only(right: 8),
                child: LinearProgressIndicator(
                  value: rate,
                  backgroundColor: context.colors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    rate > 0.4 ? context.colors.error : context.colors.success
                  ),
                ),
              ),
            Text(
              pctStr, 
              style: TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 13,
                color: !hasData 
                    ? context.colors.textSecondary 
                    : rate > 0.4 ? context.colors.error : context.colors.success
              )
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMoodCircumplexCard(double valence, double energy, String desc, String quad) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '🧠 Estado de Ánimo (Russell EA)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Últimos 45 minutos de escucha ponderados:',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 16, 
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.primary
                  ),
                ),
                Text(' ($quad)', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 20),
            
            // Russell Circumplex Plot Representation
            Center(
              child: Container(
                width: 200, height: 200,
                decoration: BoxDecoration(
                  color: context.colors.bg.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.colors.border)
                ),
                child: Stack(
                  children: [
                    // Axis lines
                    Center(child: Container(width: double.infinity, height: 1, color: context.colors.border.withOpacity(0.5))),
                    Center(child: Container(width: 1, height: double.infinity, color: context.colors.border.withOpacity(0.5))),
                    
                    // Grid Labels
                    Positioned(top: 8, left: 0, right: 0, child: Text('ACTIVACIÓN / ENERGÍA', textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: context.colors.textSecondary, fontWeight: FontWeight.bold))),
                    Positioned(bottom: 8, left: 0, right: 0, child: Text('DESACTIVACIÓN', textAlign: TextAlign.center, style: TextStyle(fontSize: 8, color: context.colors.textSecondary, fontWeight: FontWeight.bold))),
                    Positioned(left: 8, top: 90, child: Text('VALENCIA -', style: TextStyle(fontSize: 8, color: context.colors.textSecondary, fontWeight: FontWeight.bold))),
                    Positioned(right: 8, top: 90, child: Text('VALENCIA +', style: TextStyle(fontSize: 8, color: context.colors.textSecondary, fontWeight: FontWeight.bold))),
                    
                    // User Mood Dot Locator (valence: X, energy: Y)
                    // Scale values (0-1) to (0-200 pixels)
                    Positioned(
                      left: (valence * 200).clamp(10, 190) - 8,
                      bottom: (energy * 200).clamp(10, 190) - 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
                              blurRadius: 10,
                              spreadRadius: 2
                            )
                          ]
                        ),
                      ).animate(onPlay: (controller) => controller.repeat(reverse: true))
                       .scale(begin: const Offset(1, 1), end: const Offset(1.2, 1.2), duration: 800.ms),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIsoPrincipleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '🎶 Ecualización Emocional',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: Size.zero
                  ),
                  icon: const Icon(Icons.psychology_outlined, size: 16),
                  label: const Text('Calcular Cola Iso', style: TextStyle(fontSize: 12)),
                  onPressed: _generateIsoQueue,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Aplica el principio ISO: inicia con música en tu estado actual y gradualmente transiciona hacia la Calma.',
              style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
            ),
            
            if (_isoQueue.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Secuencia de Transición Recomendada (5 Canciones):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Column(
                children: List.generate(_isoQueue.length, (idx) {
                  final item = _isoQueue[idx];
                  final track = item['track'];
                  final targetE = item['target_energy'];
                  final targetV = item['target_valence'];
                  
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.bg.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: context.colors.border.withOpacity(0.3))
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                          radius: 12,
                          child: Text('${idx + 1}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(track['title'] ?? 'Track', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              Text(track['artist'] ?? 'Artista', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('E: ${(track['energy'] as double).toStringAsFixed(2)} ➔ ${targetE.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                            Text('V: ${(track['valence'] as double).toStringAsFixed(2)} ➔ ${targetV.toStringAsFixed(2)}', style: const TextStyle(fontSize: 10, fontFamily: 'monospace')),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              )
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildGeminiSectionCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // API Key setup row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '🔑 Configurar Clave de Gemini',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        child: TextField(
                          controller: _apiKeyController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            hintText: 'Pega tu api_key de Google AI Studio...',
                            contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  height: 48,
                  child: _isSavingKey 
                      ? const Center(child: CircularProgressIndicator())
                      : OutlinedButton(
                          onPressed: _saveGeminiKey,
                          child: const Text('Guardar en BD'),
                        ),
                ),
              ],
            ),
            const Divider(height: 40),
            
            // Weekly Report Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📈 Reporte Semanal de Productividad Musical',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Analiza tu historial, skips y genera consejos psicológicos personalizados.',
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
                _isGeneratingReport 
                    ? const CircularProgressIndicator()
                    : ElevatedButton.icon(
                        icon: const Icon(Icons.insights),
                        label: const Text('Generar Reporte'),
                        onPressed: _generateWeeklyReport,
                      ),
              ],
            ),
            
            if (_weeklyReport != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.colors.bg.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: context.colors.border)
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // A simple parser to show Markdown report beautifully in lists and headings
                    ..._renderMarkdownToWidgets(_weeklyReport!['report'] ?? ''),
                  ],
                ),
              ).animate().fadeIn(duration: 400.ms),
            ]
          ],
        ),
      ),
    );
  }

  List<Widget> _renderMarkdownToWidgets(String markdown) {
    final List<Widget> widgets = [];
    final lines = markdown.split('\n');
    
    for (var line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }
      
      // Headers
      if (trimmed.startsWith('# ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
          child: Text(
            trimmed.substring(2), 
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)
          ),
        ));
      } else if (trimmed.startsWith('## ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14.0, bottom: 6.0),
          child: Text(
            trimmed.substring(3), 
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)
          ),
        ));
      } else if (trimmed.startsWith('### ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 12.0, bottom: 4.0),
          child: Text(
            trimmed.substring(4), 
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white70)
          ),
        ));
      } 
      // Bullet points
      else if (trimmed.startsWith('* ') || trimmed.startsWith('- ')) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 16, fontWeight: FontWeight.bold)),
              Expanded(
                child: Text(
                  trimmed.substring(2), 
                  style: TextStyle(color: context.colors.textPrimary, fontSize: 13, height: 1.4)
                ),
              ),
            ],
          ),
        ));
      } 
      // Ordered points
      else if (RegExp(r'^\d+\.\s').hasMatch(trimmed)) {
        final match = RegExp(r'^(\d+)\.\s(.*)$').firstMatch(trimmed);
        if (match != null) {
          widgets.add(Padding(
            padding: const EdgeInsets.only(left: 12.0, bottom: 4.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${match.group(1)}. ', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
                Expanded(
                  child: Text(
                    match.group(2) ?? '', 
                    style: TextStyle(color: context.colors.textPrimary, fontSize: 13, height: 1.4)
                  ),
                ),
              ],
            ),
          ));
        }
      }
      // Table rows (simple parser)
      else if (trimmed.startsWith('|') && !trimmed.contains('---')) {
        final cells = trimmed.split('|').map((c) => c.trim()).where((c) => c.isNotEmpty).toList();
        // Skip markdown table delimiters
        if (cells.isNotEmpty && cells.any((c) => c.contains('--'))) continue;
        
        widgets.add(Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          decoration: BoxDecoration(
            color: context.colors.bg.withOpacity(0.3),
            borderRadius: BorderRadius.circular(4)
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: cells.map((cell) => Text(
              cell, 
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)
            )).toList(),
          ),
        ));
      }
      // Normal paragraph
      else {
        // Remove bold delimiters ** for display
        final cleanText = trimmed.replaceAll('**', '');
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6.0),
          child: Text(
            cleanText, 
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13, height: 1.4)
          ),
        ));
      }
    }
    
    return widgets;
  }

  Widget _buildSyncHeader(BuildContext context, SettingsProvider settings) {
    final colors = context.colors;
    final isLoggedIn = settings.isLoggedIn;
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isLoggedIn 
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
            : colors.surfaceAlt.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isLoggedIn 
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.3)
              : colors.border.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Avatar/Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: isLoggedIn 
                  ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)
                  : colors.border.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isLoggedIn ? Icons.person_rounded : Icons.person_outline_rounded,
              color: isLoggedIn ? Theme.of(context).colorScheme.primary : colors.textSecondary,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Info Text
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLoggedIn 
                      ? 'Sincronizado como: ${settings.currentUserName}' 
                      : 'Sesión Local (Invitado)',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isLoggedIn
                      ? 'Correo: ${settings.currentUserEmail} • ID de Google: ${settings.currentUserId.length > 15 ? "${settings.currentUserId.substring(0, 12)}..." : settings.currentUserId}'
                      : 'Tus datos se guardan solo en esta máquina. Inicia sesión para sincronizar.',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Action button
          if (isLoggedIn)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.error,
                side: BorderSide(color: colors.error.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.logout_rounded, size: 16),
              label: const Text('Cerrar Sesión'),
              onPressed: () async {
                await settings.logout();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: const Text('Sesión cerrada correctamente. Volviendo a la cuenta local.'),
                    backgroundColor: colors.success,
                  ));
                }
              },
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.sync_rounded, size: 16),
              label: const Text('Sincronizar / Entrar'),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (_) => const AuthDialog(),
                ).then((success) {
                  if (success == true) {
                    _loadData();
                  }
                });
              },
            ),
        ],
      ),
    );
  }
}

class _StatData {
  final String title;
  final String value;
  final IconData icon;
  const _StatData(this.title, this.value, this.icon);
}
