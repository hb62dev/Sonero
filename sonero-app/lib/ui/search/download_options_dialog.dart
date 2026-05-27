import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';

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

  @override
  void initState() {
    super.initState();
    _fetchFormats();
  }

  Future<void> _fetchFormats() async {
    try {
      final api = context.read<SettingsProvider>().api;
      final info = await api.getVideoInfo(widget.videoUrl);
      if (mounted) {
        setState(() {
          _formats = info['formats'] as List<dynamic>;
          if (_formats != null && _formats!.isNotEmpty) {
            final audioFormat = _formats!.cast<Map<String, dynamic>>().firstWhere((f) => f['is_audio_only'] == true, orElse: () => _formats!.first);
            _selectedFormatId = audioFormat['format_id'];
          }
          _isLoadingFormats = false;
        });
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

  @override
  Widget build(BuildContext context) {
    final playlists = context.read<LibraryProvider>().playlists.where((p) => !p.isLibrary).toList();

    return AlertDialog(
      title: const Text('Descargar Medio'),
      content: SizedBox(
        width: 350,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 16),
            const Text('Formato:'),
            const SizedBox(height: 8),
            if (_isLoadingFormats)
              const Center(child: Padding(padding: EdgeInsets.all(8.0), child: CircularProgressIndicator()))
            else if (_formatError != null)
              Text('Error cargando formatos: $_formatError', style: const TextStyle(color: Colors.red))
            else if (_formats != null)
              DropdownButtonFormField<String>(
                value: _selectedFormatId,
                isExpanded: true,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: _formats!.map((f) {
                  final isAudio = f['is_audio_only'] == true;
                  final sizeStr = f['filesize_mb'] != null ? " - ${f['filesize_mb']} MB" : "";
                  final label = isAudio ? 'Audio (MP3)$sizeStr' : 'Video (${f['resolution']})$sizeStr';
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
              const Text('Destino (Playlist):'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _selectedPlaylist,
                isExpanded: true,
                style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color, fontSize: 14),
                decoration: const InputDecoration(border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Biblioteca (Raíz)'),
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
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: (_isDownloading || _isLoadingFormats || _formatError != null) ? null : _startDownload,
          child: const Text('Descargar'),
        ),
      ],
    );
  }
}
