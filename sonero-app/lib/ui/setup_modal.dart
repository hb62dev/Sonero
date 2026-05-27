import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import '../providers/settings_provider.dart';
import '../ui/theme.dart';

class SetupModal extends StatefulWidget {
  const SetupModal({super.key});

  @override
  State<SetupModal> createState() => _SetupModalState();
}

class _SetupModalState extends State<SetupModal> {
  bool _isLoading = false;

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
    final loc = AppLocalizations.of(context)!;
    final isReady = settings.hasMusicFolder;

    return PopScope(
      canPop: false, // Prevent dismissing by tapping outside or pressing back
      child: Dialog(
        backgroundColor: context.colors.surfaceAlt,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 450,
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '¡Bienvenido a Sonero!',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Para comenzar, selecciona la carpeta principal donde guardarás tu música. Sonero buscará tus canciones, listas de reproducción y guardará tus descargas aquí.',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 24),

              // Music Folder Picker
              Text('Carpeta de Música (Requerido)',
                  style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: context.colors.bg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Text(
                        settings.musicFolder.isEmpty ? 'Ninguna seleccionada' : settings.musicFolder,
                        style: TextStyle(
                          color: settings.musicFolder.isEmpty
                              ? context.colors.textSecondary
                              : context.colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _pickMusicFolder(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Examinar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Video Folder Picker
              Text('Carpeta de Videos (Opcional)',
                  style: TextStyle(color: context.colors.textPrimary, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      decoration: BoxDecoration(
                        color: context.colors.bg.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Text(
                        settings.videoFolder.isEmpty ? 'Misma que música' : settings.videoFolder,
                        style: TextStyle(
                          color: settings.videoFolder.isEmpty
                              ? context.colors.textSecondary
                              : context.colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => _pickVideoFolder(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: context.colors.textPrimary,
                      side: BorderSide(color: context.colors.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Examinar'),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isReady && !_isLoading
                      ? () async {
                          setState(() => _isLoading = true);
                          // Ensure video uses music if empty
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
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Continuar', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
