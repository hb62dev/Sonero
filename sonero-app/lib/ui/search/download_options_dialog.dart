import 'dart:async';
import 'package:sonero_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';

enum _DestCategory { album, playlist, artist }

class DownloadOptionsDialog extends StatefulWidget {
  final String videoUrl;
  final String title;

  const DownloadOptionsDialog({
    super.key,
    required this.videoUrl,
    required this.title,
  });

  @override
  State<DownloadOptionsDialog> createState() => _DownloadOptionsDialogState();
}

class _DownloadOptionsDialogState extends State<DownloadOptionsDialog> {
  String? _selectedPlaylist;
  String _newPlaylistName = '';
  bool _isDownloading = false;
  String? _errorMessage;
  double _progress = 0.0;
  String _step = '';
  _DestCategory _destinationCategory = _DestCategory.playlist;
  final TextEditingController _artistController = TextEditingController();

  List<dynamic>? _formats;
  String? _selectedFormatId;
  bool _isLoadingFormats = true;
  String? _formatError;

  Map<String, dynamic>? _playlistInfo;

  bool get _isPlaylist => widget.videoUrl.contains('list=');

  @override
  void initState() {
    super.initState();
    _fetchFormats();
    // Try to extract artist from title (e.g. "Artist - Song Title")
    final parts = widget.title.split(RegExp(r'\s*[-–—]\s*'));
    if (parts.length >= 2) {
      _artistController.text = parts.first.trim();
    }
  }

  @override
  void dispose() {
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _fetchFormats() async {
    try {
      final api = context.read<SettingsProvider>().api;
      if (_isPlaylist) {
        final info = await api.getPlaylistInfo(widget.videoUrl);
        if (mounted) {
          setState(() {
            _formats = [
              {
                'format_id': 'bestaudio/best',
                'resolution': 'Solo Audio (MP3 - 320kbps)',
                'ext': 'mp3',
                'filesize_mb': null,
                'is_audio_only': true,
              },
              {
                'format_id': 'best',
                'resolution': 'Video (Mejor Calidad - MP4)',
                'ext': 'mp4',
                'filesize_mb': null,
                'is_audio_only': false,
              },
              {
                'format_id': '720p',
                'resolution': 'Video (720p - MP4)',
                'ext': 'mp4',
                'filesize_mb': null,
                'is_audio_only': false,
              },
              {
                'format_id': '360p',
                'resolution': 'Video (360p - MP4)',
                'ext': 'mp4',
                'filesize_mb': null,
                'is_audio_only': false,
              },
            ];
            _selectedFormatId = 'bestaudio/best';
            
            final playlistTitle = info['title'] as String? ?? 'YouTube Playlist';
            final cleanPlaylistName = playlistTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
            _selectedPlaylist = cleanPlaylistName;
            
            _playlistInfo = info;
            _isLoadingFormats = false;
          });
        }
      } else {
        final info = await api.getVideoInfo(widget.videoUrl);
        if (mounted) {
          setState(() {
            final rawFormats = info['formats'] as List<dynamic>? ?? [];
            
            final mp4VideoFormats = rawFormats.where((f) {
              final isAudio = f['is_audio_only'] == true;
              final ext = (f['ext'] as String? ?? '').toLowerCase();
              return !isAudio && ext == 'mp4';
            }).toList();

            _formats = [];
            
            _formats!.add({
              'format_id': 'bestaudio/best',
              'resolution': '320kbps',
              'ext': 'mp3',
              'filesize_mb': null,
              'is_audio_only': true,
            });
            
            _formats!.addAll(mp4VideoFormats);

            if (_formats!.isNotEmpty) {
              _selectedFormatId = 'bestaudio/best';
            }
            _isLoadingFormats = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _formatError = e.toString();
          _isLoadingFormats = false;
        });
      }
    }
  }

  bool get _isAudioSelected {
    if (_formats == null || _selectedFormatId == null) return true;
    final format = _formats!.cast<Map<String, dynamic>>().firstWhere((f) => f['format_id'] == _selectedFormatId, orElse: () => <String, dynamic>{});
    return format['is_audio_only'] == true;
  }

  Future<void> _startDownload() async {
    if (_isPlaylist) {
      await _startPlaylistDownload();
      return;
    }

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _step = 'Iniciando...';
    });

    try {
      final api = context.read<SettingsProvider>().api;
      final library = context.read<LibraryProvider>();
      String jobId;

      // Resolve the actual playlist name
      String? actualPlaylist = _selectedPlaylist;
      if (_selectedPlaylist == '__new__' && _newPlaylistName.isNotEmpty) {
        actualPlaylist = _newPlaylistName;
        // Create the new playlist first
        await api.createPlaylist(actualPlaylist);
        await library.loadPlaylists(api);
      } else if (_selectedPlaylist == '__new__') {
        actualPlaylist = null; // fallback to general if empty name
      }

      if (_isAudioSelected) {
        jobId = await api.downloadMp3Direct(
          url: widget.videoUrl,
          title: widget.title,
          playlist: actualPlaylist,
        );
      } else {
        jobId = await api.downloadVideo(
          widget.videoUrl,
          _selectedFormatId!,
        );
      }

      Timer.periodic(const Duration(milliseconds: 500), (timer) async {
        try {
          final status = await api.getVideoJobStatus(jobId);
          if (!mounted) {
            timer.cancel();
            return;
          }
          setState(() {
            _progress = (status['progress'] as num).toDouble() / 100;
            _step = status['step'] ?? '';
          });

          if (status['status'] == 'done') {
            timer.cancel();
            Navigator.of(context).pop(status['warning'] ?? true);
          } else if (status['status'] == 'failed') {
            timer.cancel();
            setState(() {
              _isDownloading = false;
              _errorMessage = status['error'] ?? 'Error desconocido';
            });
          }
        } catch (e) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isDownloading = false;
              _errorMessage = e.toString();
            });
          }
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _startPlaylistDownload() async {
    if (_playlistInfo == null) return;
    
    final videos = _playlistInfo!['videos'] as List<dynamic>? ?? [];
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _step = AppLocalizations.of(context)!.enqueuingDownloads(videos.length);
    });

    try {
      final settings = context.read<SettingsProvider>();
      final api = settings.api;
      final library = context.read<LibraryProvider>();

      final isAudio = _isAudioSelected;
      // Resolve __new__ playlist name
      String? actualPlaylist = _selectedPlaylist;
      if (_selectedPlaylist == '__new__' && _newPlaylistName.isNotEmpty) {
        actualPlaylist = _newPlaylistName;
      } else if (_selectedPlaylist == '__new__') {
        actualPlaylist = null;
      }

      if (isAudio && actualPlaylist != null && actualPlaylist.isNotEmpty) {
        setState(() {
          _step = 'Creando playlist local...';
        });
        await api.createPlaylist(actualPlaylist);
        await library.loadTracks(api);
      }

      for (int i = 0; i < videos.length; i++) {
        final video = videos[i];
        final vUrl = video['url'] as String;
        final vTitle = video['title'] as String;

        setState(() {
          _progress = (i + 1) / videos.length;
          _step = 'Encolando (${i + 1}/${videos.length}): $vTitle';
        });

        if (isAudio) {
          await api.downloadMp3Direct(
            url: vUrl,
            title: vTitle,
            playlist: actualPlaylist,
          );
        } else {
          await api.downloadVideo(
            vUrl,
            _selectedFormatId!,
          );
        }
        
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (mounted) {
        Navigator.of(context).pop({
          'playlist': true,
          'count': videos.length,
          'title': _playlistInfo!['title'],
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = context.read<LibraryProvider>().playlists.where((p) => !p.isLibrary).toList();
    final l10n = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        _isPlaylist ? l10n.playlistDownloadOptions : 'Descargar',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title preview
            if (_isPlaylist && _playlistInfo != null) ...[
              Text(
                _playlistInfo!['title'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                l10n.playlistVideosCount(_playlistInfo!['videos']?.length ?? 0),
                style: TextStyle(color: accent, fontWeight: FontWeight.w500, fontSize: 13),
              ),
            ] else ...[
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 20),

            // ── Audio / Video Toggle ──────────────────────────────
            Text('Tipo de descarga', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodySmall?.color)),
            const SizedBox(height: 8),
            if (_isLoadingFormats)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))))
            else if (_formatError != null)
              Text(l10n.formatLoadError(_formatError!), style: const TextStyle(color: Colors.red, fontSize: 12))
            else if (_formats != null)
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isDownloading ? null : () {
                        setState(() => _selectedFormatId = 'bestaudio/best');
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: _isAudioSelected ? accent.withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _isAudioSelected ? accent : Theme.of(context).dividerColor.withOpacity(0.3),
                            width: _isAudioSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.music_note_rounded, size: 22, color: _isAudioSelected ? accent : Theme.of(context).textTheme.bodySmall?.color),
                            const SizedBox(height: 4),
                            Text('Audio', style: TextStyle(
                              fontSize: 13,
                              fontWeight: _isAudioSelected ? FontWeight.w700 : FontWeight.w500,
                              color: _isAudioSelected ? accent : Theme.of(context).textTheme.bodySmall?.color,
                            )),
                            Text('MP3 320kbps', style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6))),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: _isDownloading ? null : () {
                        // Select first video format
                        final videoFormat = _formats!.cast<Map<String, dynamic>>().firstWhere(
                          (f) => f['is_audio_only'] != true,
                          orElse: () => <String, dynamic>{},
                        );
                        if (videoFormat.isNotEmpty) {
                          setState(() => _selectedFormatId = videoFormat['format_id'] as String);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !_isAudioSelected ? accent.withOpacity(0.1) : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !_isAudioSelected ? accent : Theme.of(context).dividerColor.withOpacity(0.3),
                            width: !_isAudioSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(Icons.videocam_rounded, size: 22, color: !_isAudioSelected ? accent : Theme.of(context).textTheme.bodySmall?.color),
                            const SizedBox(height: 4),
                            Text('Video', style: TextStyle(
                              fontSize: 13,
                              fontWeight: !_isAudioSelected ? FontWeight.w700 : FontWeight.w500,
                              color: !_isAudioSelected ? accent : Theme.of(context).textTheme.bodySmall?.color,
                            )),
                            Text('MP4', style: TextStyle(fontSize: 10, color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6))),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

            // Video quality selector (only when video is selected)
            if (!_isAudioSelected && _formats != null) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedFormatId,
                isExpanded: true,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 13),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  labelText: 'Calidad',
                  labelStyle: const TextStyle(fontSize: 13),
                ),
                items: _formats!.where((f) => f['is_audio_only'] != true).map((f) {
                  final sizeStr = f['filesize_mb'] != null ? " - ${f['filesize_mb']} MB" : "";
                  final res = f['resolution'] as String? ?? 'Mejor calidad';
                  return DropdownMenuItem<String>(
                    value: f['format_id'] as String,
                    child: Text('$res$sizeStr'),
                  );
                }).toList(),
                onChanged: _isDownloading ? null : (val) {
                  setState(() => _selectedFormatId = val);
                },
              ),
            ],

            const SizedBox(height: 20),

            // ── Destination ──────────────────────────────────────
            Text('Guardar en', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Theme.of(context).textTheme.bodySmall?.color)),
            const SizedBox(height: 8),
            DropdownButtonFormField<String?>(
              value: _selectedPlaylist == '__new__' ? '__new__' : _selectedPlaylist,
              isExpanded: true,
              style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 13),
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                prefixIcon: Icon(
                  _selectedPlaylist == null
                      ? Icons.folder_rounded
                      : _selectedPlaylist == '__new__'
                          ? Icons.create_new_folder_rounded
                          : Icons.playlist_play_rounded,
                  size: 18,
                  color: accent,
                ),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('General (raíz)'),
                ),
                ...playlists.map((p) => DropdownMenuItem(
                  value: p.name,
                  child: Row(
                    children: [
                      Icon(Icons.playlist_play_rounded, size: 16, color: accent.withOpacity(0.7)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.name, overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                )),
                DropdownMenuItem(
                  value: '__new__',
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline_rounded, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Text('Crear nueva etiqueta', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              onChanged: _isDownloading ? null : (val) {
                setState(() => _selectedPlaylist = val);
              },
            ),
            // New playlist name field
            if (_selectedPlaylist == '__new__') ...[
              const SizedBox(height: 10),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Nombre de la nueva etiqueta...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  prefixIcon: Icon(Icons.label_outline_rounded, size: 18, color: accent),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (val) {
                  _newPlaylistName = val.trim();
                },
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: _progress > 0 && _progress < 1.0
                              ? CircularProgressIndicator(
                                  value: _progress,
                                  strokeWidth: 2.5,
                                  color: Theme.of(context).colorScheme.primary,
                                )
                              : CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _step.replaceAll(RegExp(r'[\u{1F4E5}\u{2B07}\u{FE0F}]', unicode: true), '').trim(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_progress > 0)
                          Text(
                            '${(_progress * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _progress > 0 ? _progress : null,
                        minHeight: 6,
                        backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton.icon(
          onPressed: (_isDownloading || _isLoadingFormats || _formatError != null) ? null : _startDownload,
          icon: Icon(_isAudioSelected ? Icons.music_note_rounded : Icons.videocam_rounded, size: 16),
          label: Text(l10n.download),
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ],
    );
  }
}

class _DestinationCategoryBar extends StatelessWidget {
  final _DestCategory selected;
  final ValueChanged<_DestCategory>? onChanged;

  const _DestinationCategoryBar({required this.selected, this.onChanged});

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: [
          _buildTab(context, _DestCategory.album, Icons.album_rounded, 'Álbum', accent),
          const SizedBox(width: 4),
          _buildTab(context, _DestCategory.playlist, Icons.playlist_play_rounded, 'Lista', accent),
          const SizedBox(width: 4),
          _buildTab(context, _DestCategory.artist, Icons.person_rounded, 'Artista', accent),
        ],
      ),
    );
  }

  Widget _buildTab(BuildContext context, _DestCategory cat, IconData icon, String label, Color accent) {
    final isActive = selected == cat;

    return Expanded(
      child: GestureDetector(
        onTap: onChanged != null ? () => onChanged!(cat) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? accent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: isActive ? Border.all(color: accent.withOpacity(0.3), width: 1) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isActive ? accent : Theme.of(context).textTheme.bodySmall?.color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? accent : Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
