import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';

class MetadataDialog extends StatefulWidget {
  final Track track;
  const MetadataDialog({super.key, required this.track});

  @override
  State<MetadataDialog> createState() => _MetadataDialogState();
}

class _MetadataDialogState extends State<MetadataDialog> {
  final _titleCtrl = TextEditingController();
  final _artistCtrl = TextEditingController();
  final _albumCtrl = TextEditingController();
  final _genreCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();

  bool _isLoading = true;
  String? _coverArtBase64;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final api = context.read<SettingsProvider>().api;

    try {
      final metadata = await api.getTrackMetadata(widget.track.filename);
      if (metadata != null) {
        _titleCtrl.text = metadata['title'] ?? widget.track.title;
        _artistCtrl.text = metadata['artist'] ?? widget.track.artist;
        _albumCtrl.text = metadata['album'] ?? widget.track.album;
        _genreCtrl.text = metadata['genre'] ?? widget.track.genre;
        _yearCtrl.text = metadata['year']?.toString() ?? widget.track.year;
        _coverArtBase64 = metadata['cover_art_base64'];
      } else {
        _titleCtrl.text = widget.track.title;
        _artistCtrl.text = widget.track.artist;
      }
    } catch (_) {
      _titleCtrl.text = widget.track.title;
      _artistCtrl.text = widget.track.artist;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveMetadata() async {
    final api = context.read<SettingsProvider>().api;
    try {
      await api.updateTrackMetadata({
        'filename': widget.track.filename,
        'title': _titleCtrl.text.trim(),
        'artist': _artistCtrl.text.trim(),
        'album': _albumCtrl.text.trim(),
        'genre': _genreCtrl.text.trim(),
        'year': _yearCtrl.text.trim(),
        // cover_art_base64 is not updated as requested
      });
      if (mounted) {
        Navigator.pop(context, true); // true = changes saved
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando: $e'),
            backgroundColor: context.colors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return AlertDialog(
        backgroundColor: context.colors.surfaceAlt,
        content: const SizedBox(height: 100, child: Center(child: CircularProgressIndicator())),
      );
    }

    Widget? coverArtWidget;
    if (_coverArtBase64 != null && _coverArtBase64!.isNotEmpty) {
      try {
        final imageBytes = base64Decode(_coverArtBase64!);
        coverArtWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            imageBytes,
            width: 120,
            height: 120,
            fit: BoxFit.cover,
          ),
        );
      } catch (_) {
        coverArtWidget = _buildPlaceholderCover(context);
      }
    } else {
      coverArtWidget = _buildPlaceholderCover(context);
    }

    return AlertDialog(
      backgroundColor: context.colors.surfaceAlt,
      title: const Text('Editar Metadatos'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (coverArtWidget != null) ...[
              coverArtWidget,
              const SizedBox(height: 16),
            ],
            _Field('Título', _titleCtrl),
            const SizedBox(height: 12),
            _Field('Artista', _artistCtrl),
            const SizedBox(height: 12),
            _Field('Álbum', _albumCtrl),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _Field('Año', _yearCtrl, isNumber: true)),
                const SizedBox(width: 12),
                Expanded(child: _Field('Género', _genreCtrl)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _saveMetadata,
          child: const Text('Guardar'),
        ),
      ],
    );
  }

  Widget _buildPlaceholderCover(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.music_note, size: 50, color: context.colors.textSecondary),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final bool isNumber;

  const _Field(this.label, this.controller, {this.isNumber = false});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: context.colors.textSecondary),
      ),
      style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
    );
  }
}
