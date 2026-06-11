import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';
import '../providers/library_provider.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class VideoDownloadDialog extends StatefulWidget {
  const VideoDownloadDialog({super.key});

  @override
  State<VideoDownloadDialog> createState() => _VideoDownloadDialogState();
}

class _VideoDownloadDialogState extends State<VideoDownloadDialog> {
  final _urlController = TextEditingController();
  bool _isFetching = false;
  bool _isDownloading = false;
  Map<String, dynamic>? _videoInfo;
  String? _selectedFormatId;
  String? _errorMessage;
  double _progress = 0.0;
  String _step = '';

  bool get _isPlaylist => _urlController.text.trim().contains('list=');

  @override
  void initState() {
    super.initState();
    _urlController.addListener(_onUrlChanged);
  }

  void _onUrlChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _urlController.removeListener(_onUrlChanged);
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _fetchInfo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;

    setState(() {
      _isFetching = true;
      _errorMessage = null;
      _videoInfo = null;
    });

    try {
      final api = context.read<SettingsProvider>().api;
      if (_isPlaylist) {
        final info = await api.getPlaylistInfo(url);
        final playlistFormats = [
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

        setState(() {
          _videoInfo = {
            'title': info['title'] ?? 'YouTube Playlist',
            'thumbnail': info['thumbnail'] ?? '',
            'formats': playlistFormats,
            'videos': info['videos'],
          };
          _selectedFormatId = 'bestaudio/best';
        });
      } else {
        final info = await api.getVideoInfo(url);
        final rawFormats = info['formats'] as List<dynamic>? ?? [];
        final mp4VideoFormats = rawFormats.where((f) {
          final isAudio = f['is_audio_only'] == true;
          final ext = (f['ext'] as String? ?? '').toLowerCase();
          return !isAudio && ext == 'mp4';
        }).toList();

        final filteredFormats = <Map<String, dynamic>>[];
        filteredFormats.add({
          'format_id': 'bestaudio/best',
          'resolution': '320kbps',
          'ext': 'mp3',
          'filesize_mb': null,
          'is_audio_only': true,
        });
        filteredFormats.addAll(mp4VideoFormats.cast<Map<String, dynamic>>());

        setState(() {
          _videoInfo = {
            ...info,
            'formats': filteredFormats,
          };
          if (filteredFormats.isNotEmpty) {
            _selectedFormatId = 'bestaudio/best';
          }
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isFetching = false;
      });
    }
  }

  Future<void> _download() async {
    if (_selectedFormatId == null) return;
    final url = _urlController.text.trim();

    if (_isPlaylist) {
      await _downloadPlaylist();
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

      final isAudioSelected = _selectedFormatId == 'bestaudio/best';
      if (isAudioSelected) {
        jobId = await api.downloadMp3Direct(
          url: url,
          title: _videoInfo!['title'] ?? 'Audio',
        );
      } else {
        jobId = await api.downloadVideo(url, _selectedFormatId!);
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

  Future<void> _downloadPlaylist() async {
    final videos = _videoInfo!['videos'] as List<dynamic>? ?? [];
    final l10n = AppLocalizations.of(context)!;
    
    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _step = l10n.enqueuingDownloads(videos.length);
    });

    try {
      final settings = context.read<SettingsProvider>();
      final api = settings.api;
      final library = context.read<LibraryProvider>();

      final isAudio = _selectedFormatId == 'bestaudio/best';
      String? playlistName;
      
      if (isAudio) {
        final title = _videoInfo!['title'] as String? ?? 'YouTube Playlist';
        playlistName = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
        
        setState(() {
          _step = 'Creando playlist local...';
        });
        await api.createPlaylist(playlistName);
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
            playlist: playlistName,
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
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.playlistEnqueued(videos.length)),
            backgroundColor: Colors.green,
          ),
        );
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
    final l10n = AppLocalizations.of(context)!;
    
    return AlertDialog(
      title: Text(_isPlaylist ? l10n.downloadPlaylist : l10n.downloadYouTubeVideo),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlController,
                enabled: !_isDownloading && !_isFetching,
                decoration: InputDecoration(
                  labelText: 'YouTube URL',
                  hintText: 'https://youtube.com/watch?v=...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: (_isDownloading || _isFetching) ? null : () async {
                      final data = await Clipboard.getData('text/plain');
                      if (data?.text != null) {
                        _urlController.text = data!.text!;
                      }
                    },
                  ),
                ),
                onSubmitted: (_) => _fetchInfo(),
              ),
              const SizedBox(height: 16),
              if (_isFetching)
                const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
                )
              else if (_videoInfo != null)
                _buildVideoInfo(),
                
              if (_isDownloading) ...[
                const SizedBox(height: 16),
                LinearProgressIndicator(value: _progress > 0 ? _progress : null),
                const SizedBox(height: 8),
                Text(_step, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isDownloading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        if (_videoInfo == null)
          ElevatedButton(
            onPressed: _isFetching ? null : _fetchInfo,
            child: Text(l10n.fetchInfo),
          )
        else
          ElevatedButton(
            onPressed: _isDownloading ? null : _download,
            child: Text(l10n.download),
          ),
      ],
    );
  }

  Widget _buildVideoInfo() {
    final title = _videoInfo!['title'] as String;
    final thumbnail = _videoInfo!['thumbnail'] as String;
    final formats = _videoInfo!['formats'] as List;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumbnail.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(thumbnail, height: 180, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_,__,___) => const SizedBox()),
          ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
        if (_isPlaylist) ...[
          const SizedBox(height: 8),
          Text(
            l10n.playlistVideosCount(_videoInfo!['videos']?.length ?? 0),
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 16),
        Text(l10n.selectFormat, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedFormatId,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: formats.map((f) {
            final formatId = f['format_id'] as String;
            final resolution = f['resolution'] as String;
            final ext = f['ext'] as String;
            final sizeMb = f['filesize_mb'];
            final sizeStr = sizeMb != null ? ' (${sizeMb}MB)' : '';
            return DropdownMenuItem(
              value: formatId,
              child: Text(_isPlaylist ? resolution : '$resolution - $ext$sizeStr'),
            );
          }).toList(),
          onChanged: _isDownloading ? null : (val) {
            setState(() {
              _selectedFormatId = val;
            });
          },
        ),
      ],
    );
  }
}
