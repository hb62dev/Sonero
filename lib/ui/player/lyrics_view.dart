import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api_client.dart';
import '../../providers/player_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';

class SyncedLyric {
  final Duration time;
  final String text;

  SyncedLyric(this.time, this.text);
}

class LyricsView extends StatefulWidget {
  final String title;
  final String artist;

  const LyricsView({
    super.key,
    required this.title,
    required this.artist,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  bool _isLoading = true;
  String? _error;
  List<SyncedLyric>? _syncedLyrics;
  String? _plainLyrics;
  
  final ScrollController _scrollController = ScrollController();
  int _currentIndex = -1;

  @override
  void initState() {
    super.initState();
    _fetchLyrics();
  }

  Future<void> _fetchLyrics() async {
    try {
      final api = context.read<SettingsProvider>().api;
      final data = await api.getLyrics(widget.title, widget.artist);
      
      if (data['error'] != null) {
        setState(() {
          _error = data['error'];
          _isLoading = false;
        });
        return;
      }

      final synced = data['synced'] as String?;
      final plain = data['plain'] as String?;

      if (synced != null && synced.isNotEmpty) {
        _syncedLyrics = _parseSyncedLyrics(synced);
      }
      
      setState(() {
        _plainLyrics = plain;
        _isLoading = false;
        
        if (_syncedLyrics == null && _plainLyrics == null) {
          _error = 'No se encontraron letras para esta canción.';
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error al cargar letras: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<SyncedLyric> _parseSyncedLyrics(String synced) {
    final List<SyncedLyric> result = [];
    final lines = synced.split('\n');
    final RegExp timeRegex = RegExp(r'\[(\d{2}):(\d{2})\.(\d{2})\]');

    for (var line in lines) {
      final match = timeRegex.firstMatch(line);
      if (match != null) {
        final minutes = int.parse(match.group(1)!);
        final seconds = int.parse(match.group(2)!);
        final hundredths = int.parse(match.group(3)!);
        
        final duration = Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: hundredths * 10,
        );
        
        final text = line.substring(match.end).trim();
        if (text.isNotEmpty) {
          result.add(SyncedLyric(duration, text));
        }
      }
    }
    return result;
  }

  void _scrollToCurrentIndex(int index) {
    if (!_scrollController.hasClients || index < 0) return;
    
    // Smoothly animate to the active line (approx 50px per line)
    // We center it vertically.
    final targetOffset = (index * 50.0) - (MediaQuery.of(context).size.height / 3);
    
    _scrollController.animateTo(
      targetOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
          child: Container(
            color: context.colors.bg.withOpacity(0.7),
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title.isNotEmpty ? widget.title : 'Letras',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: context.colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (widget.artist.isNotEmpty)
                              Text(
                                widget.artist,
                                style: TextStyle(
                                  fontSize: 16,
                                  color: context.colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: context.colors.textSecondary, size: 32),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                
                // Content
                Expanded(
                  child: _buildContent(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lyrics_outlined, size: 64, color: context.colors.textSecondary.withOpacity(0.5)),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_syncedLyrics != null && _syncedLyrics!.isNotEmpty) {
      return Consumer<PlayerProvider>(
        builder: (context, player, child) {
          final position = player.position;
          
          // Find current line index
          int newIndex = -1;
          for (int i = 0; i < _syncedLyrics!.length; i++) {
            if (position >= _syncedLyrics![i].time) {
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

          return ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 100),
            itemCount: _syncedLyrics!.length,
            itemBuilder: (context, index) {
              final lyric = _syncedLyrics![index];
              final isActive = index == _currentIndex;
              final isPassed = index < _currentIndex;

              return Container(
                height: 50,
                alignment: Alignment.centerLeft,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: isActive ? 28 : 24,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                    color: isActive 
                        ? context.colors.textPrimary 
                        : context.colors.textPrimary.withOpacity(isPassed ? 0.3 : 0.5),
                  ),
                  child: Text(
                    lyric.text,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
                ),
              );
            },
          );
        },
      );
    }

    // Fallback to plain lyrics
    return SingleChildScrollView(
      padding: const EdgeInsets.all(40),
      child: Text(
        _plainLyrics ?? '',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w500,
          color: context.colors.textPrimary.withOpacity(0.8),
          height: 1.5,
        ),
      ),
    );
  }
}
