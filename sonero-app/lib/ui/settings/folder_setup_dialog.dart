import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';

/// A premium-looking setup dialog shown on first launch.
/// Asks the user to select where to save music and videos.
class FolderSetupDialog extends StatefulWidget {
  const FolderSetupDialog({super.key});

  /// Shows the dialog and returns true if setup was completed.
  static Future<bool> show(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const FolderSetupDialog(),
    );
    return result ?? false;
  }

  @override
  State<FolderSetupDialog> createState() => _FolderSetupDialogState();
}

class _FolderSetupDialogState extends State<FolderSetupDialog>
    with SingleTickerProviderStateMixin {
  String? _musicPath;
  String? _videoPath;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  /// Calls the backend to open the native OS folder picker dialog.
  /// Returns the selected path or null if cancelled/failed.
  Future<String?> _pickFolderViaBackend({required bool isMusic}) async {
    final title = isMusic
        ? 'Selecciona la carpeta para guardar música'
        : 'Selecciona la carpeta para guardar videos';
    try {
      final uri = Uri.parse(
        'http://127.0.0.1:8000/api/v1/settings/pick-folder?title=${Uri.encodeComponent(title)}',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 120));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final path = data['path'] as String?;
        if (path != null && path.isNotEmpty) {
          return path;
        }
      }
    } catch (_) {
      // Backend unreachable — fall through to manual input
    }
    return null;
  }

  /// Fallback: shows a text input dialog for manually typing the path.
  Future<String?> _showManualPathDialog({required bool isMusic}) async {
    final controller = TextEditingController(
      text: isMusic ? _musicPath : _videoPath,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final accent = Theme.of(ctx).colorScheme.primary;
        return AlertDialog(
          backgroundColor: context.colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(isMusic ? Icons.music_note_rounded : Icons.videocam_rounded, color: accent, size: 20),
              const SizedBox(width: 10),
              Text(
                isMusic ? 'Carpeta de Música' : 'Carpeta de Videos',
                style: TextStyle(color: context.colors.textPrimary, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Escribe la ruta completa de la carpeta:',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: isMusic
                      ? r'Ej: C:\Users\tu_usuario\Music\Sonero'
                      : r'Ej: C:\Users\tu_usuario\Videos\Sonero',
                  hintStyle: TextStyle(color: context.colors.textSecondary.withOpacity(0.4), fontSize: 13),
                  filled: true,
                  fillColor: context.colors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.colors.border.withOpacity(0.2)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: context.colors.border.withOpacity(0.2)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  prefixIcon: Icon(Icons.folder_rounded, color: accent.withOpacity(0.5), size: 20),
                ),
                onSubmitted: (val) => Navigator.of(ctx).pop(val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('Cancelar', style: TextStyle(color: context.colors.textSecondary)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 0,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );
    return result;
  }

  Future<void> _pickFolder({required bool isMusic}) async {
    if (kIsWeb) {
      // On web, ask the backend to open the native OS folder picker
      final picked = await _pickFolderViaBackend(isMusic: isMusic);
      if (picked != null && picked.isNotEmpty) {
        setState(() {
          if (isMusic) {
            _musicPath = picked;
          } else {
            _videoPath = picked;
          }
        });
        return;
      }
      // Fallback to manual text input if backend picker failed/cancelled
      final manual = await _showManualPathDialog(isMusic: isMusic);
      if (manual != null && manual.isNotEmpty) {
        setState(() {
          if (isMusic) {
            _musicPath = manual;
          } else {
            _videoPath = manual;
          }
        });
      }
      return;
    }
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: isMusic
          ? 'Selecciona la carpeta para guardar música'
          : 'Selecciona la carpeta para guardar videos',
    );
    if (result != null) {
      setState(() {
        if (isMusic) {
          _musicPath = result;
        } else {
          _videoPath = result;
        }
      });
    }
  }

  Future<void> _confirm() async {
    final settings = context.read<SettingsProvider>();
    if (_musicPath != null && _musicPath!.isNotEmpty) {
      await settings.setMusicFolder(_musicPath!);
      // Auto-configure video folder as a subfolder of music if not set
      if (_videoPath == null || _videoPath!.isEmpty) {
        final autoVideoPath = '${_musicPath!}/videos';
        await settings.setVideoFolder(autoVideoPath);
      }
    }
    if (_videoPath != null && _videoPath!.isNotEmpty) {
      await settings.setVideoFolder(_videoPath!);
    }
    await settings.completeSetup();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SlideTransition(
        position: _slideAnim,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(24),
          child: Container(
            width: 480,
            constraints: const BoxConstraints(maxWidth: 520),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accent.withOpacity(0.15),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accent.withOpacity(0.08),
                  blurRadius: 40,
                  spreadRadius: 0,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Header ──────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.fromLTRB(28, 28, 28, 20),
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        accent.withOpacity(0.08),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [accent, accent.withOpacity(0.7)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: accent.withOpacity(0.3),
                              blurRadius: 16,
                              spreadRadius: 0,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.folder_rounded, color: Colors.white, size: 28),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '¿Dónde guardamos tu música?',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: context.colors.textPrimary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Elige las carpetas donde Sonero guardará tus descargas de música y video.',
                        style: TextStyle(
                          fontSize: 13,
                          color: context.colors.textSecondary,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),

                // ── Folder pickers ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  child: Column(
                    children: [
                      _FolderPickerTile(
                        icon: Icons.music_note_rounded,
                        label: 'Carpeta de Música',
                        path: _musicPath,
                        onPick: () => _pickFolder(isMusic: true),
                      ),
                      const SizedBox(height: 10),
                      _FolderPickerTile(
                        icon: Icons.videocam_rounded,
                        label: 'Carpeta de Videos',
                        path: _videoPath,
                        onPick: () => _pickFolder(isMusic: false),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // ── Actions ─────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: _confirm,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            _musicPath != null || _videoPath != null
                                ? 'Guardar y continuar'
                                : 'Usar carpetas por defecto',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),
                      if (_musicPath == null && _videoPath == null) ...[
                        const SizedBox(height: 10),
                        Text(
                          'Puedes cambiar esto después en Ajustes → Almacenamiento',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.colors.textSecondary.withOpacity(0.6),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single folder picker row with icon, label, path preview, and pick button.
class _FolderPickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? path;
  final VoidCallback onPick;

  const _FolderPickerTile({
    required this.icon,
    required this.label,
    required this.path,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final hasPath = path != null && path!.isNotEmpty;

    return Material(
      color: context.colors.bg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onPick,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasPath ? accent.withOpacity(0.3) : context.colors.border.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: (hasPath ? accent : context.colors.textSecondary).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: hasPath ? accent : context.colors.textSecondary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: context.colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasPath ? path! : 'Toca para seleccionar...',
                      style: TextStyle(
                        fontSize: 11,
                        color: hasPath ? accent.withOpacity(0.8) : context.colors.textSecondary.withOpacity(0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                hasPath ? Icons.check_circle_rounded : Icons.folder_open_rounded,
                size: 20,
                color: hasPath ? accent : context.colors.textSecondary.withOpacity(0.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
