import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

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
  bool _isDownloading = false;
  String? _errorMessage;
  double _progress = 0.0;
  String _step = '';

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
      String jobId;

      if (_isAudioSelected) {
        jobId = await api.downloadMp3Direct(
          url: widget.videoUrl,
          title: widget.title,
          playlist: _selectedPlaylist,
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
      if (isAudio && _selectedPlaylist != null && _selectedPlaylist!.isNotEmpty) {
        setState(() {
          _step = 'Creando playlist local...';
        });
        await api.createPlaylist(_selectedPlaylist!);
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
            playlist: _selectedPlaylist,
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

    return AlertDialog(
      title: Text(_isPlaylist ? l10n.playlistDownloadOptions : l10n.downloadMedia),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isPlaylist && _playlistInfo != null) ...[
              Text(
                _playlistInfo!['title'] ?? '',
                style: const TextStyle(fontWeight: FontWeight.bold),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.playlistVideosCount(_playlistInfo!['videos']?.length ?? 0),
                style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500),
              ),
            ] else ...[
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 16),
            Text(l10n.format),
            const SizedBox(height: 8),
            if (_isLoadingFormats)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            else if (_formatError != null)
              Text(l10n.formatLoadError(_formatError!), style: const TextStyle(color: Colors.red))
            else if (_formats != null)
              DropdownButtonFormField<String>(
                value: _selectedFormatId,
                isExpanded: true,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _formats!.map((f) {
                  final isAudio = f['is_audio_only'] == true;
                  final sizeStr = f['filesize_mb'] != null ? " - ${f['filesize_mb']} MB" : "";
                  final res = f['resolution'] as String? ?? '';
                  final label = _isPlaylist
                      ? res
                      : (isAudio 
                          ? 'Audio (MP3) - ${res.contains('kbps') ? res : '320kbps'}$sizeStr' 
                          : 'Video ($res)$sizeStr');
                  return DropdownMenuItem<String>(
                    value: f['format_id'] as String,
                    child: Text(label),
                  );
                }).toList(),
                onChanged: _isDownloading ? null : (val) {
                  setState(() {
                    _selectedFormatId = val;
                  });
                },
              ),
            
            if (_isAudioSelected) ...[
              const SizedBox(height: 16),
              Text(l10n.destinationPlaylist),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _selectedPlaylist,
                isExpanded: true,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  DropdownMenuItem(
                    value: null,
                    child: Text(l10n.libraryRoot),
                  ),
                  ...playlists.map((p) => DropdownMenuItem(
                    value: p.name,
                    child: Text(p.name),
                  )),
                ],
                onChanged: _isDownloading ? null : (val) {
                  setState(() {
                    _selectedPlaylist = val;
                  });
                },
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ],
            if (_isDownloading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Text(_step, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Theme.of(context).textTheme.bodyLarge?.color)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: (_isDownloading || _isLoadingFormats || _formatError != null) ? null : _startDownload,
          child: Text(l10n.download),
        ),
      ],
    );
  }
}
