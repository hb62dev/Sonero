import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/settings_provider.dart';
import '../ui/theme.dart';

class SetupModal extends StatefulWidget {
  const SetupModal({super.key});

  @override
  State<SetupModal> createState() => _SetupModalState();
}

class _SetupModalState extends State<SetupModal> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      try {
        await [
          Permission.audio,
          Permission.videos,
          Permission.storage,
          Permission.manageExternalStorage,
          Permission.notification,
          Permission.microphone,
        ].request();
        
        if (mounted) {
          await context.read<SettingsProvider>().refreshFolders();
          setState(() {});
        }
      } catch (e) {
        debugPrint('Error requesting permissions in SetupModal: $e');
      }
    }
  }

  Future<void> _pickMusicFolder(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final result = await FilePicker.getDirectoryPath();
    if (result != null) {
      await settings.setMusicFolder(result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickVideoFolder(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final result = await FilePicker.getDirectoryPath();
    if (result != null) {
      await settings.setVideoFolder(result);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final isReady = settings.hasMusicFolder;
    final isMobile = MediaQuery.of(context).size.width < 600;
    final screenH = MediaQuery.of(context).size.height;

    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: context.colors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: isMobile
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 24)
            : const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 450,
            maxHeight: isMobile ? screenH * 0.88 : double.infinity,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.all(isMobile ? 18 : 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Título ─────────────────────────────────────────────────
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (b) => context.colors.gradient.createShader(b),
                      child: Icon(Icons.music_note_rounded,
                          color: Colors.white, size: isMobile ? 24 : 30),
                    ),
                    SizedBox(width: isMobile ? 8 : 12),
                    Expanded(
                      child: Text(
                        '¡Bienvenido a Sonero!',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: isMobile ? 18 : 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isMobile ? 10 : 14),
                Text(
                  'Selecciona la carpeta donde guardarás tu música. Sonero buscará canciones, playlists y guardará tus descargas aquí.',
                  style: TextStyle(
                      color: context.colors.textSecondary,
                      fontSize: isMobile ? 12 : 13,
                      height: 1.5),
                ),
                SizedBox(height: isMobile ? 18 : 24),

                // ── Carpeta de Música ───────────────────────────────────────
                _FolderLabel(
                  icon: Icons.folder_rounded,
                  title: 'Carpeta de Música',
                  required: true,
                  isMobile: isMobile,
                  color: Theme.of(context).colorScheme.primary,
                ),
                SizedBox(height: isMobile ? 6 : 8),
                _FolderPicker(
                  path: settings.musicFolder,
                  placeholder: 'Ninguna seleccionada',
                  isMobile: isMobile,
                  onPick: () => _pickMusicFolder(context),
                  buttonColor: Theme.of(context).colorScheme.primary,
                  buttonTextColor: Colors.white,
                ),
                SizedBox(height: isMobile ? 14 : 18),

                // ── Carpeta de Videos ───────────────────────────────────────
                _FolderLabel(
                  icon: Icons.videocam_rounded,
                  title: 'Carpeta de Videos',
                  required: false,
                  isMobile: isMobile,
                  color: context.colors.textSecondary,
                ),
                SizedBox(height: isMobile ? 6 : 8),
                _FolderPicker(
                  path: settings.videoFolder,
                  placeholder: 'Misma que música',
                  isMobile: isMobile,
                  onPick: () => _pickVideoFolder(context),
                  buttonColor: Colors.transparent,
                  buttonTextColor: context.colors.textPrimary,
                  outlined: true,
                ),
                SizedBox(height: isMobile ? 22 : 28),

                // ── Botón Continuar ─────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isReady && !_isLoading
                        ? () async {
                            setState(() => _isLoading = true);
                            if (settings.videoFolder.isEmpty) {
                              await settings.setVideoFolder(settings.musicFolder);
                            }
                            if (mounted) Navigator.pop(context);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: context.colors.border,
                      padding: EdgeInsets.symmetric(
                        vertical: isMobile ? 14 : 16,
                      ),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Continuar →',
                            style: TextStyle(
                                fontSize: isMobile ? 14 : 15,
                                fontWeight: FontWeight.bold),
                          ),
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

// ── Helper widgets ────────────────────────────────────────────────────────────

class _FolderLabel extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool required;
  final bool isMobile;
  final Color color;

  const _FolderLabel({
    required this.icon,
    required this.title,
    required this.required,
    required this.isMobile,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: isMobile ? 14 : 16, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: context.colors.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: isMobile ? 13 : 14,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: required
                  ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                  : context.colors.border,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              required ? 'Requerido' : 'Opcional',
              style: TextStyle(
                fontSize: 10,
                color: required
                    ? Theme.of(context).colorScheme.primary
                    : context.colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
}

class _FolderPicker extends StatelessWidget {
  final String path;
  final String placeholder;
  final bool isMobile;
  final VoidCallback onPick;
  final Color buttonColor;
  final Color buttonTextColor;
  final bool outlined;

  const _FolderPicker({
    required this.path,
    required this.placeholder,
    required this.isMobile,
    required this.onPick,
    required this.buttonColor,
    required this.buttonTextColor,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: 10,
                vertical: isMobile ? 9 : 11,
              ),
              decoration: BoxDecoration(
                color: context.colors.bg.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.colors.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.folder_outlined,
                      size: 14, color: context.colors.textSecondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      path.isEmpty ? placeholder : path,
                      style: TextStyle(
                        color: path.isEmpty
                            ? context.colors.textSecondary
                            : context.colors.textPrimary,
                        fontSize: isMobile ? 11 : 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: isMobile ? 38 : 42,
            child: outlined
                ? OutlinedButton.icon(
                    onPressed: onPick,
                    icon: Icon(Icons.folder_open, size: 14),
                    label: Text('Elegir',
                        style: TextStyle(fontSize: isMobile ? 12 : 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: buttonTextColor,
                      side: BorderSide(color: context.colors.border),
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 16, vertical: 0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: onPick,
                    icon: Icon(Icons.folder_open, size: 14),
                    label: Text('Elegir',
                        style: TextStyle(fontSize: isMobile ? 12 : 13)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: buttonColor,
                      foregroundColor: buttonTextColor,
                      padding: EdgeInsets.symmetric(
                          horizontal: isMobile ? 12 : 16, vertical: 0),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
          ),
        ],
      );
}

