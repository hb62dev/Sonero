import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/lyrics_service.dart';
import '../theme.dart';

class SyncedLyric {
  final Duration time;
  final String text;

  SyncedLyric(this.time, this.text);
}

/// Source of the currently displayed lyrics.
enum LyricsSource { local, online, none }

class LyricsView extends StatefulWidget {
  final String title;
  final String artist;
  final String? filename;

  const LyricsView({
    super.key,
    required this.title,
    required this.artist,
    this.filename,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  bool _isLoading = true;
  String? _error;

  List<SyncedLyric>? _syncedLyrics;
  String? _plainLyrics;
  LyricsSource _source = LyricsSource.none;

  final ScrollController _scrollController = ScrollController();
  int _currentIndex = -1;

  PlayerProvider? _player;
  late String _currentTitle;
  late String _currentArtist;
  String? _currentFilename;
  
  int _manualOffsetMs = 0;

  bool _isVideoExt(String filename) {
    final lower = filename.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm');
  }

  @override
  void initState() {
    super.initState();
    _currentTitle = widget.title;
    _currentArtist = widget.artist;
    _currentFilename = widget.filename;
    _player = context.read<PlayerProvider>();
    _player?.addListener(_onPlayerUpdate);
    _loadLyrics();
  }

  @override
  void dispose() {
    _player?.removeListener(_onPlayerUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlayerUpdate() {
    final track = _player?.currentTrack;
    if (track != null && track.filename != _currentFilename) {
      if (!mounted) return;
      setState(() {
        _currentFilename = track.filename;
        _currentTitle = track.title;
        _currentArtist = track.artist;
      });
      _loadLyrics();
    } else if (track == null && _currentFilename != null) {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ── Loading strategy: local → online (auto-save) ──────────────────────────

  Future<void> _loadLyrics() async {
    final settings = context.read<SettingsProvider>();
    int initialOffset = settings.lyricsOffset;
    if (_currentFilename != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        initialOffset = prefs.getInt('lyrics_offset_$_currentFilename') ?? settings.lyricsOffset;
      } catch (_) {}
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _syncedLyrics = null;
      _plainLyrics = null;
      _source = LyricsSource.none;
      _currentIndex = -1;
      _manualOffsetMs = initialOffset;
    });

    // 1. Try local file first (works without internet)
    if (_currentFilename != null) {
      final isVideo = _isVideoExt(_currentFilename!);
      final activeFolder = isVideo ? settings.videoFolder : settings.musicFolder;
      if (activeFolder.isNotEmpty) {
        final lrcContent = LyricsService.readLrc(activeFolder, _currentFilename!);
        if (lrcContent != null && lrcContent.trim().isNotEmpty) {
          final parsed = _parseSyncedLyrics(lrcContent);
          if (parsed.isNotEmpty) {
            setState(() {
              _syncedLyrics = parsed;
              _source = LyricsSource.local;
              _isLoading = false;
            });
            return;
          }
          // .lrc with no timestamps → treat as plain text
          setState(() {
            _plainLyrics = lrcContent.trim();
            _source = LyricsSource.local;
            _isLoading = false;
            });
          return;
        }

        final txtContent = LyricsService.readTxt(activeFolder, _currentFilename!);
        if (txtContent != null && txtContent.trim().isNotEmpty) {
          setState(() {
            _plainLyrics = txtContent.trim();
            _source = LyricsSource.local;
            _isLoading = false;
          });
          return;
        }
      }
    }

    // 2. Fetch from backend and auto-save to disk
    await _fetchAndSave();
  }

  /// Fetches lyrics from the backend. If successful, automatically persists
  /// them to the local `lyrics/` folder — no user action required.
  Future<void> _fetchAndSave() async {
    try {
      final settings    = context.read<SettingsProvider>();
      final api         = settings.api;
      final isVideo     = _isVideoExt(_currentFilename ?? '');
      final activeFolder = isVideo ? settings.videoFolder : settings.musicFolder;

      final data = await api.getLyrics(_currentTitle, _currentArtist);
      if (!mounted) return;

      final errorMsg = data['error'] as String?;
      if (errorMsg != null) {
        setState(() {
          _error = errorMsg;
          _source = LyricsSource.none;
          _isLoading = false;
        });
        return;
      }

      final synced = data['synced'] as String?;
      final plain  = data['plain']  as String?;

      List<SyncedLyric>? parsed;
      if (synced != null && synced.trim().isNotEmpty) {
        parsed = _parseSyncedLyrics(synced);
      }

      final hasSynced = parsed != null && parsed.isNotEmpty;
      final hasPlain  = plain != null && plain.trim().isNotEmpty;

      if (!hasSynced && !hasPlain) {
        setState(() {
          _error = 'No se encontraron letras para esta canción.';
          _source = LyricsSource.none;
          _isLoading = false;
        });
        return;
      }

      // ── Auto-save to disk ────────────────────────────────────────────────
      if (_currentFilename != null && activeFolder.isNotEmpty) {
        try {
          if (hasSynced && synced != null) {
            await LyricsService.saveLrc(activeFolder, _currentFilename!, synced);
          } else if (hasPlain && plain != null) {
            await LyricsService.saveTxt(activeFolder, _currentFilename!, plain);
          }
        } catch (_) {
          // Saving failed silently — lyrics still displayed from memory
        }
      }

      setState(() {
        _syncedLyrics = hasSynced ? parsed : null;
        _plainLyrics  = (hasPlain && plain != null) ? plain.trim() : null;
        // Mark as local since we just saved it (next open will read from disk)
        _source    = LyricsSource.local;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Sin letra guardada. Conéctate a internet\n'
              'para descargar la letra automáticamente.';
          _source = LyricsSource.none;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateOffset(int newOffset) async {
    setState(() {
      _manualOffsetMs = newOffset;
    });
    if (_currentFilename != null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('lyrics_offset_$_currentFilename', newOffset);
      } catch (_) {}
    }
  }

  Future<void> _saveAsGlobalDefault() async {
    final settings = context.read<SettingsProvider>();
    await settings.setLyricsOffset(_manualOffsetMs);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Guardado como retraso global por defecto'),
        duration: Duration(seconds: 2),
      ));
    }
  }

  // ── Parsing ───────────────────────────────────────────────────────────────

  List<SyncedLyric> _parseSyncedLyrics(String synced) {
    final List<SyncedLyric> result = [];
    final lines = synced.split('\n');
    final RegExp timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2,3})\]');
    final RegExp offsetRegex = RegExp(r'\[offset:\s*([+-]?\d+)\]', caseSensitive: false);

    int offsetMs = 0;

    for (var line in lines) {
      final offsetMatch = offsetRegex.firstMatch(line);
      if (offsetMatch != null) {
        offsetMs = int.tryParse(offsetMatch.group(1)!) ?? 0;
        continue;
      }

      final match = timeRegex.firstMatch(line);
      if (match != null) {
        final minutes    = int.parse(match.group(1)!);
        final seconds    = int.parse(match.group(2)!);
        final centesimal = int.parse(match.group(3)!);
        final ms = match.group(3)!.length == 2 ? centesimal * 10 : centesimal;

        int totalMs = (minutes * 60 * 1000) + (seconds * 1000) + ms - offsetMs;
        if (totalMs < 0) totalMs = 0;

        final duration = Duration(milliseconds: totalMs);
        final text = line.substring(match.end).trim();
        if (text.isNotEmpty) result.add(SyncedLyric(duration, text));
      }
    }
    return result;
  }

  void _scrollToCurrentIndex(int index) {
    if (!_scrollController.hasClients || index < 0) return;
    final isMobile = context.isMobile;
    final itemHeight = isMobile ? 44.0 : 54.0;
    final targetOffset =
        (index * itemHeight) - (MediaQuery.of(context).size.height / 3);
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isMobile = context.isMobile;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: isMobile ? const EdgeInsets.all(8) : const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(isMobile ? 16 : 24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            color: context.colors.bg.withValues(alpha: 0.88),
            child: SafeArea(
              top: false,
              bottom: true,
              child: Column(
                children: [
                  _buildHeader(),
                  if (_source == LyricsSource.local) _buildLocalBadge(),
                  if (_syncedLyrics != null && _syncedLyrics!.isNotEmpty) _buildSyncControls(),
                  Expanded(child: _buildContent()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSyncControls() {
    final isMobile = context.isMobile;
    final settings = context.watch<SettingsProvider>();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: isMobile ? 2 : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Sincronización: ',
                style: TextStyle(fontSize: isMobile ? 11 : 12, color: context.colors.textSecondary),
              ),
              InkWell(
                onTap: () => _updateOffset(_manualOffsetMs - 100),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(Icons.remove_circle_outline_rounded, size: isMobile ? 14 : 16, color: context.colors.textSecondary),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${_manualOffsetMs >= 0 ? "+" : ""}${(_manualOffsetMs / 1000.0).toStringAsFixed(2)}s',
                style: TextStyle(
                  fontSize: isMobile ? 11 : 12, 
                  fontWeight: FontWeight.bold,
                  color: _manualOffsetMs == 0 ? context.colors.textSecondary : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 4),
              InkWell(
                onTap: () => _updateOffset(_manualOffsetMs + 100),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(Icons.add_circle_outline_rounded, size: isMobile ? 14 : 16, color: context.colors.textSecondary),
                ),
              ),
              if (_manualOffsetMs != settings.lyricsOffset) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => _updateOffset(settings.lyricsOffset),
                  child: Text(
                    'Restablecer',
                    style: TextStyle(
                      fontSize: isMobile ? 10 : 11, 
                      color: Theme.of(context).colorScheme.primary, 
                      decoration: TextDecoration.underline,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '(-) Adelantar letra | Atrasar letra (+)',
            style: TextStyle(
              fontSize: isMobile ? 9 : 10,
              color: context.colors.textSecondary.withValues(alpha: 0.7),
            ),
          ),
          if (_manualOffsetMs != settings.lyricsOffset) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: _saveAsGlobalDefault,
              child: Text(
                'Definir como predeterminado global',
                style: TextStyle(
                  fontSize: isMobile ? 10 : 11,
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final isMobile = context.isMobile;
    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, isMobile ? 12 : 20, 16, 12),
      child: Row(
        children: [
          Container(
            width: isMobile ? 36 : 44,
            height: isMobile ? 36 : 44,
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(isMobile ? 8 : 10),
            ),
            child: Icon(Icons.lyrics_rounded,
                color: Theme.of(context).colorScheme.primary, size: isMobile ? 18 : 22),
          ),
          SizedBox(width: isMobile ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentTitle.isNotEmpty ? _currentTitle : 'Letras',
                  style: TextStyle(
                    fontSize: isMobile ? 16 : 20,
                    fontWeight: FontWeight.bold,
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_currentArtist.isNotEmpty)
                  Text(
                    _currentArtist,
                    style: TextStyle(
                        fontSize: isMobile ? 12 : 14, color: context.colors.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: context.colors.textSecondary, size: isMobile ? 24 : 28),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBadge() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.offline_pin_rounded,
                    size: 14, color: Colors.green.shade400),
                const SizedBox(width: 5),
                Text(
                  'Disponible offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade400,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Refresh from online (overwrites local copy)
          Tooltip(
            message: 'Actualizar desde internet',
            child: InkWell(
              onTap: _fetchAndSave,
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh_rounded,
                        size: 14, color: context.colors.textSecondary),
                    const SizedBox(width: 4),
                    Text('Actualizar',
                        style: TextStyle(
                            fontSize: 12,
                            color: context.colors.textSecondary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final isMobile = context.isMobile;
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off_rounded,
                  size: 64,
                  color: context.colors.textSecondary.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                    color: context.colors.textSecondary, fontSize: 15),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              OutlinedButton.icon(
                onPressed: _fetchAndSave,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Reintentar'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.colors.textSecondary,
                  side: BorderSide(color: context.colors.border),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Synced (karaoke-style) lyrics
    if (_syncedLyrics != null && _syncedLyrics!.isNotEmpty) {
      return Consumer<PlayerProvider>(
        builder: (context, player, child) {
          final position = player.position;
          
          // Compensate for the 250ms visual animation delay + manual offset
          // Note: a positive manual offset means delaying the lyrics, so we subtract it from adjustedPosition.
          final adjustedPosition = position + Duration(milliseconds: 250 - _manualOffsetMs);

          int newIndex = -1;
          for (int i = 0; i < _syncedLyrics!.length; i++) {
            if (adjustedPosition >= _syncedLyrics![i].time) {
              newIndex = i;
            } else {
              break;
            }
          }

          if (newIndex != _currentIndex) {
            _currentIndex = newIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _scrollToCurrentIndex(_currentIndex);
            });
          }

          final itemHeight = isMobile ? 44.0 : 54.0;

          return ListView.builder(
            controller: _scrollController,
            padding:
                EdgeInsets.symmetric(horizontal: isMobile ? 24 : 40, vertical: isMobile ? 60 : 100),
            itemExtent: itemHeight,
            itemCount: _syncedLyrics!.length,
            itemBuilder: (context, index) {
              final lyric    = _syncedLyrics![index];
              final isActive = index == _currentIndex;
              final isPassed = index < _currentIndex;

              return Container(
                height: itemHeight,
                alignment: Alignment.centerLeft,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: isActive ? (isMobile ? 20 : 28) : (isMobile ? 16 : 24),
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.w600,
                    color: isActive
                        ? context.colors.textPrimary
                        : context.colors.textPrimary
                            .withValues(alpha: isPassed ? 0.3 : 0.5),
                  ),
                  child: Text(
                    lyric.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // Plain text lyrics
    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 24 : 40),
      child: Text(
        _plainLyrics ?? '',
        style: TextStyle(
          fontSize: isMobile ? 18 : 22,
          fontWeight: FontWeight.w500,
          color: context.colors.textPrimary.withValues(alpha: 0.85),
          height: 1.6,
        ),
      ),
    );
  }
}
