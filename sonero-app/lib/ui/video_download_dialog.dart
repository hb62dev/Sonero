import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

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

  @override
  void dispose() {
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
      final info = await api.getVideoInfo(url);
      setState(() {
        _videoInfo = info;
        final formats = info['formats'] as List;
        if (formats.isNotEmpty) {
          _selectedFormatId = formats.first['format_id'];
        }
      });
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

    setState(() {
      _isDownloading = true;
      _errorMessage = null;
      _progress = 0.0;
      _step = 'Iniciando...';
    });

    try {
      final api = context.read<SettingsProvider>().api;
      final jobId = await api.downloadVideo(url, _selectedFormatId!);
      
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
    return AlertDialog(
      title: const Text('Download YouTube Video'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _urlController,
                decoration: InputDecoration(
                  labelText: 'YouTube URL',
                  hintText: 'https://youtube.com/watch?v=...',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.paste),
                    onPressed: () async {
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
          child: const Text('Cancel'),
        ),
        if (_videoInfo == null)
          ElevatedButton(
            onPressed: _isFetching ? null : _fetchInfo,
            child: const Text('Fetch Info'),
          )
        else
          ElevatedButton(
            onPressed: _isDownloading ? null : _download,
            child: const Text('Download'),
          ),
      ],
    );
  }

  Widget _buildVideoInfo() {
    final title = _videoInfo!['title'] as String;
    final thumbnail = _videoInfo!['thumbnail'] as String;
    final formats = _videoInfo!['formats'] as List;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thumbnail.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(thumbnail, height: 180, width: double.infinity, fit: BoxFit.cover),
          ),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16), maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 16),
        const Text('Select Format:', style: TextStyle(fontWeight: FontWeight.w500)),
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
              child: Text('$resolution - $ext$sizeStr'),
            );
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedFormatId = val;
            });
          },
        ),
      ],
    );
  }
}
