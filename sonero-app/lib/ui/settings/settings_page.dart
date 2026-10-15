import 'dart:ui' as ui;
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'platform_stub.dart'
    if (dart.library.io) 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:sonero_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';
import '../../core/hotkey_service.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../theme.dart';
import '../../services/log_service.dart';
import '../player/equalizer_view.dart';
import 'favicon_stub.dart'
    if (dart.library.js_interop) 'favicon_web.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _apiUrlCtrl;
  late final TextEditingController _durationCtrl;
  late final TextEditingController _googleClientIdCtrl;
  late final TextEditingController _googleClientSecretCtrl;
  late final TextEditingController _geminiKeyCtrl;
  late final TextEditingController _auddTokenCtrl;
  late final TextEditingController _rapidApiKeyCtrl;
  late final TextEditingController _rapidApiHostCtrl;
  late final TextEditingController _shazamProxyUrlCtrl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _apiUrlCtrl = TextEditingController(text: settings.apiUrl);
    _durationCtrl = TextEditingController(text: settings.listenDuration.toString());
    _googleClientIdCtrl = TextEditingController(text: settings.googleClientId);
    _googleClientSecretCtrl = TextEditingController(text: settings.googleClientSecret);
    _geminiKeyCtrl = TextEditingController(text: settings.geminiApiKey);
    _auddTokenCtrl = TextEditingController(text: settings.auddApiToken);
    _rapidApiKeyCtrl = TextEditingController(text: settings.rapidApiKey);
    _rapidApiHostCtrl = TextEditingController(text: settings.rapidApiHost);
    _shazamProxyUrlCtrl = TextEditingController(text: settings.shazamProxyUrl);
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _durationCtrl.dispose();
    _googleClientIdCtrl.dispose();
    _googleClientSecretCtrl.dispose();
    _geminiKeyCtrl.dispose();
    _auddTokenCtrl.dispose();
    _rapidApiKeyCtrl.dispose();
    _rapidApiHostCtrl.dispose();
    _shazamProxyUrlCtrl.dispose();
    super.dispose();
  }
  Future<String?> _showWebFolderInput(BuildContext context, String title, String currentPath) async {
    // First, try the backend native folder picker
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
    // Fallback: manual text input
    final controller = TextEditingController(text: currentPath);
    final accent = Theme.of(context).colorScheme.primary;
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.folder_rounded, color: accent, size: 20),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(color: context.colors.textPrimary, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Escribe la ruta completa de la carpeta:', style: TextStyle(color: context.colors.textSecondary, fontSize: 13)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(color: context.colors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: r'Ej: C:\Users\tu_usuario\Music\Sonero',
                hintStyle: TextStyle(color: context.colors.textSecondary.withOpacity(0.4), fontSize: 13),
                filled: true,
                fillColor: context.colors.bg,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.colors.border.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: context.colors.border.withOpacity(0.2))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accent, width: 1.5)),
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
            style: ElevatedButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), elevation: 0),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Widget _buildWebSettingsSection(BuildContext context, SettingsProvider settings) {
    return SizedBox(
      width: 500,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('URL del Servidor', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          const SizedBox(height: 8),
          TextField(
            controller: _apiUrlCtrl,
            decoration: const InputDecoration(hintText: 'http://localhost:8000'),
            onSubmitted: (v) => settings.setApiUrl(v),
          ),
          const SizedBox(height: 16),
          Text('API Key de Gemini', style: TextStyle(fontWeight: FontWeight.bold, color: context.colors.textPrimary)),
          const SizedBox(height: 8),
          TextField(
            controller: _geminiKeyCtrl,
            obscureText: true,
            decoration: const InputDecoration(hintText: 'Tu clave de Google AI Studio'),
            onSubmitted: (v) => settings.setGeminiApiKey(v),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                settings.setApiUrl(_apiUrlCtrl.text);
                settings.setGeminiApiKey(_geminiKeyCtrl.text);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Configuración guardada.')),
                );
              },
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoPreview(SettingsProvider settings, double size) {
    final path = settings.customLogoPath;
    if (path.isEmpty) {
      return Image.asset('assets/images/logo.png', width: size, height: size, fit: BoxFit.cover);
    }
    if (path.startsWith('data:')) {
      try {
        final b64 = path.split(',').last;
        return Image.memory(
          base64Decode(b64),
          width: size, height: size, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Image.asset('assets/images/logo.png', width: size, height: size, fit: BoxFit.cover),
        );
      } catch (_) {
        return Image.asset('assets/images/logo.png', width: size, height: size, fit: BoxFit.cover);
      }
    }
    // Fallback for any other stored path — just show default
    return Image.asset('assets/images/logo.png', width: size, height: size, fit: BoxFit.cover);
  }

  Future<void> _pickLogoImage(SettingsProvider settings) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.image,
        allowMultiple: false,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          // Decode, resize to 200x200 max, and re-encode as PNG to keep small
          final original = await decodeImageFromList(file.bytes!);
          final size = 200.0;
          double w = original.width.toDouble();
          double h = original.height.toDouble();
          if (w > size || h > size) {
            final scale = size / (w > h ? w : h);
            w = (w * scale).roundToDouble();
            h = (h * scale).roundToDouble();
          }
          // Use Canvas to resize
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));
          canvas.drawImageRect(
            original,
            Rect.fromLTWH(0, 0, original.width.toDouble(), original.height.toDouble()),
            Rect.fromLTWH(0, 0, w, h),
            Paint()..filterQuality = FilterQuality.high,
          );
          final picture = recorder.endRecording();
          final resized = await picture.toImage(w.toInt(), h.toInt());
          final byteData = await resized.toByteData(format: ui.ImageByteFormat.png);
          if (byteData != null) {
            final pngBytes = byteData.buffer.asUint8List();
            final b64 = base64Encode(pngBytes);
            final dataUri = 'data:image/png;base64,$b64';
            debugPrint('Logo saved: ${dataUri.length} chars');
            await settings.setCustomLogoPath(dataUri);
            // Update favicon on web
            if (kIsWeb) {
              _updateFavicon(dataUri);
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Logo pick error: $e');
    }
  }

  /// Updates the browser favicon dynamically (web only)
  void _updateFavicon(String dataUri) {
    try {
      setFaviconDataUri(dataUri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();



    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        titleSpacing: 20,
        title: Text(AppLocalizations.of(context)!.settings,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        iconTheme: IconThemeData(color: context.colors.textSecondary),
        elevation: 0,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            style: IconButton.styleFrom(shape: const CircleBorder(), backgroundColor: Colors.transparent, side: BorderSide.none),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.border.withOpacity(0.3)),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.of(context).size.width < 600 ? 16 : 32,  // left
          MediaQuery.of(context).size.width < 600 ? 16 : 28,  // top
          MediaQuery.of(context).size.width < 600 ? 16 : 32,  // right
          MediaQuery.of(context).size.width < 600 ? 40 : 40,  // bottom
        ),
        children: [
          // ── Music folder ───────────────────────────────────────────────
          // ── Carpetas (lado a lado) ─────────────────────────────────
          _SectionLabel('Almacenamiento'),
          Builder(builder: (context) {
            final isMobile = MediaQuery.of(context).size.width < 600;
            return Flex(
              direction: isMobile ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              // Music folder
              Flexible(
                fit: isMobile ? FlexFit.loose : FlexFit.tight,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.music_note_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Música', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.colors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _InfoText(
                        settings.hasMusicFolder
                            ? settings.musicFolder
                            : 'No seleccionada',
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: const Text('Seleccionar carpeta'),
                            onPressed: () async {
                              if (kIsWeb) {
                                final path = await _showWebFolderInput(context, 'Carpeta de Música', settings.musicFolder);
                                if (path != null && path.isNotEmpty) {
                                  await settings.setMusicFolder(path);
                                }
                                return;
                              }
                              final result = await FilePicker.getDirectoryPath(
                                dialogTitle: 'Selecciona la carpeta donde guardar la música',
                              );
                              if (result != null) {
                                await settings.setMusicFolder(result);
                              }
                            },
                          ),
                          if (settings.hasMusicFolder) ...[
                            OutlinedButton.icon(
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Abrir'),
                              onPressed: kIsWeb ? null : () {
                                final path = settings.musicFolder;
                                if (!kIsWeb) {
                                  if (Platform.isWindows) {
                                    Process.run('explorer', [path]);
                                  } else if (Platform.isMacOS) {
                                    Process.run('open', [path]);
                                  } else if (Platform.isLinux) {
                                    Process.run('xdg-open', [path]);
                                  }
                                }
                              },
                            ),
                            TextButton(
                              onPressed: () => settings.setMusicFolder(''),
                              child: Text('Limpiar',
                                  style: TextStyle(color: context.colors.textSecondary)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 12 : 0),
              // Video folder
              Flexible(
                fit: isMobile ? FlexFit.loose : FlexFit.tight,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.colors.surface,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.videocam_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                          const SizedBox(width: 8),
                          Text('Video', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: context.colors.textPrimary)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _InfoText(
                        settings.hasVideoFolder
                            ? settings.videoFolder
                            : 'No seleccionada',
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.folder_open, size: 16),
                            label: const Text('Seleccionar carpeta'),
                            onPressed: () async {
                              if (kIsWeb) {
                                final path = await _showWebFolderInput(context, 'Carpeta de Videos', settings.videoFolder);
                                if (path != null && path.isNotEmpty) {
                                  await settings.setVideoFolder(path);
                                }
                                return;
                              }
                              final result = await FilePicker.getDirectoryPath(
                                dialogTitle: 'Selecciona la carpeta donde guardar los videos',
                              );
                              if (result != null) {
                                await settings.setVideoFolder(result);
                              }
                            },
                          ),
                          if (settings.hasVideoFolder) ...[
                            OutlinedButton.icon(
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Abrir'),
                              onPressed: kIsWeb ? null : () {
                                final path = settings.videoFolder;
                                if (!kIsWeb) {
                                  if (Platform.isWindows) {
                                    Process.run('explorer', [path]);
                                  } else if (Platform.isMacOS) {
                                    Process.run('open', [path]);
                                  } else if (Platform.isLinux) {
                                    Process.run('xdg-open', [path]);
                                  }
                                }
                              },
                            ),
                            TextButton(
                              onPressed: () => settings.setVideoFolder(''),
                              child: Text('Limpiar',
                                  style: TextStyle(color: context.colors.textSecondary)),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
          }),

          const SizedBox(height: 16),

          // ── Audio / Ecualizador ─────────────────────────────────────
          _SectionLabel('Audio'),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => showEqualizerDialog(context),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(Icons.equalizer_rounded, size: 20, color: Theme.of(context).colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ecualizador', style: TextStyle(
                                color: context.colors.textPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              )),
                              const SizedBox(height: 2),
                              Text('EQ de 10 bandas, presets, bass boost, canal y más',
                                style: TextStyle(
                                  color: context.colors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: context.colors.textSecondary, size: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Idioma (row inline) ──────────────────────────────────────
          _SectionLabel('General'),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.language_rounded, size: 18, color: context.colors.textSecondary),
                        const SizedBox(width: 10),
                        Text('Idioma', style: TextStyle(color: context.colors.textPrimary, fontSize: 13)),
                      ],
                    ),
                    DropdownButton<String>(
                      value: settings.locale,
                      dropdownColor: context.colors.surfaceAlt,
                      underline: const SizedBox(),
                      items: [
                        DropdownMenuItem(value: 'es', child: Text(AppLocalizations.of(context)!.languageSpanish)),
                        DropdownMenuItem(value: 'en', child: Text(AppLocalizations.of(context)!.languageEnglish)),
                        DropdownMenuItem(value: 'ja', child: Text(AppLocalizations.of(context)!.languageJapanese)),
                      ],
                      onChanged: (lang) {
                        if (lang != null) settings.setLocale(lang);
                      },
                    ),
                  ],
                ),
                Divider(height: 24, color: context.colors.border.withOpacity(0.3)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.color_lens_rounded, size: 18, color: context.colors.textSecondary),
                        const SizedBox(width: 10),
                        Text('Color Principal', style: TextStyle(color: context.colors.textPrimary, fontSize: 13)),
                      ],
                    ),
                    InkWell(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            backgroundColor: context.colors.surface,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            title: const Text('Elegir color'),
                            content: SingleChildScrollView(
                              child: BlockPicker(
                                pickerColor: settings.accentColor,
                                onColorChanged: (color) {
                                  settings.setAccentColor(color);
                                },
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(),
                                child: Text('Cerrar', style: TextStyle(color: settings.accentColor)),
                              ),
                            ],
                          ),
                        );
                      },
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: settings.accentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.colors.border.withOpacity(0.5), width: 1.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Logo personalizado ────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                // Current logo preview
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: _buildLogoPreview(settings, 56),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Logo personalizado',
                        style: TextStyle(
                          color: context.colors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cambia el ícono de la app donde aparezca',
                        style: TextStyle(
                          color: context.colors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.image_rounded, size: 16),
                            label: const Text('Elegir imagen'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                            onPressed: () => _pickLogoImage(settings),
                          ),
                          if (settings.customLogoPath.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            TextButton.icon(
                              icon: Icon(Icons.restore_rounded, size: 16, color: context.colors.error),
                              label: Text('Restaurar', style: TextStyle(color: context.colors.error, fontSize: 12)),
                              onPressed: () => settings.clearCustomLogo(),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Authentication (Anti-Bot) ──────────────────────────────────
          _Section(
            title: 'Autenticación (Anti-Bot)',
            icon: Icons.security_outlined,
            children: [
              Text(
                'Usa tus cookies de YouTube para evitar bloqueos al descargar.',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: Icon(Icons.cloud_sync, size: 16),
                      label: Text('Sincronizar (Benrio)'),
                      onPressed: () async {
                        try {
                          await settings.api.syncBenrioCookies();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Cookies sincronizadas correctamente.'),
                              backgroundColor: context.colors.success,
                            ));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Error: $e'),
                              backgroundColor: context.colors.error,
                            ));
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: Icon(Icons.upload_file, size: 16),
                      label: Text('Cargar cookies.txt'),
                      onPressed: () async {
                        if (kIsWeb) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Carga de archivos no disponible en la versión web.')),
                          );
                          return;
                        }
                        final result = await FilePicker.pickFiles(
                          dialogTitle: 'Selecciona tu archivo cookies.txt',
                          type: FileType.custom,
                          allowedExtensions: ['txt'],
                        );
                        if (result != null && result.files.single.path != null) {
                          try {
                            await settings.api.uploadCookies(result.files.single.path!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Archivo cargado correctamente.'),
                                backgroundColor: context.colors.success,
                              ));
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text('Error: $e'),
                                backgroundColor: context.colors.error,
                              ));
                            }
                          }
                        }
                      },
                    ),
                  ),
                ],
              ),
              if (!settings.api.isNative) ...[
                const SizedBox(height: 16),
                const _BrowserCookiesTile(),
                const SizedBox(height: 16),
                const _YoutubeStatusTile(),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // ── Google Cloud Integration ────────────────────────────────────
          _Section(
            title: 'Integración con Google Cloud',
            icon: Icons.cloud_queue_rounded,
            children: [
              Text(
                'Configura tu Client ID y Client Secret de aplicación de escritorio (Desktop App) de Google Cloud para habilitar la sincronización real con tu cuenta oficial.',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              Builder(builder: (ctx) {
                final isMobile = MediaQuery.of(ctx).size.width < 600;
                return Flex(
                  direction: isMobile ? Axis.vertical : Axis.horizontal,
                  children: [
                    Flexible(
                      fit: isMobile ? FlexFit.loose : FlexFit.tight,
                      child: TextField(
                        controller: _googleClientIdCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Google Client ID',
                          hintText: 'ej. 123456789-abc.apps.googleusercontent.com',
                          prefixIcon: Icon(Icons.vpn_key_outlined, size: 18),
                        ),
                        style: TextStyle(fontSize: 13),
                        onSubmitted: (v) => settings.setGoogleClientId(v),
                      ),
                    ),
                    SizedBox(width: isMobile ? 0 : 12, height: isMobile ? 12 : 0),
                    Flexible(
                      fit: isMobile ? FlexFit.loose : FlexFit.tight,
                      child: TextField(
                        controller: _googleClientSecretCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Google Client Secret',
                          hintText: 'Introduce tu Client Secret',
                          prefixIcon: Icon(Icons.lock_outline_rounded, size: 18),
                        ),
                        obscureText: true,
                        style: TextStyle(fontSize: 13),
                        onSubmitted: (v) => settings.setGoogleClientSecret(v),
                      ),
                    ),
                  ],
                );
              }),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  settings.setGoogleClientId(_googleClientIdCtrl.text);
                  settings.setGoogleClientSecret(_googleClientSecretCtrl.text);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Credenciales de Google guardadas correctamente.'),
                    backgroundColor: context.colors.success,
                    duration: Duration(seconds: 2),
                  ));
                },
                child: Text('Guardar Credenciales'),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Google Drive Sync ───────────────────────────────────────────
          if (settings.isLoggedIn) ...[
            _Section(
              title: 'Sincronización con Google Drive',
              icon: Icons.sync,
              children: [
                Text(
                  'Guarda y recupera tus estadísticas, historial y configuración de forma segura en tu Google Drive personal (AppData Folder). Es totalmente privado y sin servidores intermediarios.',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (settings.lastSyncTime != null) ...[
                  Row(
                    children: [
                      Icon(Icons.access_time, size: 14, color: context.colors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Última sincronización: ${settings.lastSyncTime!.toLocal().toString().split('.').first}',
                        style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (settings.syncError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.colors.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: context.colors.error.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: context.colors.error, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Error: ${settings.syncError}',
                            style: TextStyle(color: context.colors.error, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Row(
                  children: [
                    ElevatedButton.icon(
                      icon: settings.isSyncing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Icon(Icons.cloud_upload_outlined, size: 16),
                      label: Text(settings.isSyncing ? 'Sincronizando...' : 'Sincronizar ahora'),
                      onPressed: settings.isSyncing
                          ? null
                          : () async {
                              await settings.syncWithGoogleDrive();
                              if (context.mounted) {
                                if (settings.syncError == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: const Text('¡Sincronización completada con éxito!'),
                                    backgroundColor: context.colors.success,
                                  ));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Error al sincronizar: ${settings.syncError}'),
                                    backgroundColor: context.colors.error,
                                  ));
                                }
                              }
                            },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Appearance ──────────────────────────────────────────────────
          _Section(
            title: AppLocalizations.of(context)!.appearance,
            icon: Icons.palette_outlined,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Modo de tema', style: TextStyle(color: context.colors.textPrimary)),
                  DropdownButton<ThemeMode>(
                    value: settings.themeMode,
                    dropdownColor: context.colors.surfaceAlt,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('Sistema')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Claro')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Oscuro')),
                    ],
                    onChanged: (mode) {
                      if (mode != null) settings.setThemeMode(mode);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Color principal', style: TextStyle(color: context.colors.textPrimary)),
                  GestureDetector(
                    onTap: () => _pickColor(context, settings.accentColor, (c) => settings.setAccentColor(c)),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(color: settings.accentColor, shape: BoxShape.circle),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Color de barra lateral', style: TextStyle(color: context.colors.textPrimary)),
                  Row(
                    children: [
                      if (settings.sidebarColor != null)
                        TextButton(
                          onPressed: () => settings.setSidebarColor(null),
                          child: Text('Por defecto'),
                        ),
                      GestureDetector(
                        onTap: () => _pickColor(
                          context, 
                          settings.sidebarColor ?? context.colors.surface, 
                          (c) => settings.setSidebarColor(c)
                        ),
                        child: Container(
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                            color: settings.sidebarColor ?? context.colors.surface,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.colors.border),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Servicio de Reconocimiento ─────────────────────────────────
          _Section(
            title: 'Reconocimiento de Música',
            icon: Icons.music_note_rounded,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Proveedor', style: TextStyle(color: context.colors.textPrimary)),
                  DropdownButton<String>(
                    value: settings.recognitionService,
                    dropdownColor: context.colors.surfaceAlt,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'gemini', child: Text('Google Gemini (Flash)')),
                      DropdownMenuItem(value: 'audd', child: Text('AudD API')),
                      DropdownMenuItem(value: 'rapidapi', child: Text('RapidAPI Shazam')),
                      DropdownMenuItem(value: 'shazam_proxy', child: Text('Shazam (Servidor Proxy)')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        settings.setRecognitionService(val);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (settings.recognitionService == 'gemini') ...[
                TextField(
                  controller: _geminiKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Gemini API Key',
                    hintText: 'AIzaSy...',
                    prefixIcon: Icon(Icons.key, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (v) => settings.setGeminiApiKey(v.trim()),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    settings.setGeminiApiKey(_geminiKeyCtrl.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('API Key de Gemini guardada'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                  child: const Text('Guardar API Key'),
                ),
              ] else if (settings.recognitionService == 'audd') ...[
                TextField(
                  controller: _auddTokenCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'AudD API Token',
                    hintText: 'Tu token de AudD',
                    prefixIcon: Icon(Icons.key, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (v) => settings.setAudDApiToken(v.trim()),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    settings.setAudDApiToken(_auddTokenCtrl.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Token de AudD guardado'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                  child: const Text('Guardar Token'),
                ),
              ] else if (settings.recognitionService == 'rapidapi') ...[
                TextField(
                  controller: _rapidApiKeyCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'RapidAPI Key',
                    hintText: 'Tu clave x-rapidapi-key',
                    prefixIcon: Icon(Icons.key, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (v) => settings.setRapidApiKey(v.trim()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _rapidApiHostCtrl,
                  decoration: const InputDecoration(
                    labelText: 'RapidAPI Host',
                    hintText: 'shazam-song-recognizer.p.rapidapi.com',
                    prefixIcon: Icon(Icons.dns, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (v) => settings.setRapidApiHost(v.trim()),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
                    settings.setRapidApiKey(_rapidApiKeyCtrl.text.trim());
                    settings.setRapidApiHost(_rapidApiHostCtrl.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('Credenciales de RapidAPI guardadas'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                  child: const Text('Guardar Credenciales'),
                ),
              ] else if (settings.recognitionService == 'shazam_proxy') ...[
                TextField(
                  controller: _shazamProxyUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL del Servidor Proxy',
                    hintText: 'https://mi-espacio.hf.space o http://192.168.1.50:8000',
                    prefixIcon: Icon(Icons.link, size: 18),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onSubmitted: (v) => settings.setShazamProxyUrl(v.trim()),
                ),
                const SizedBox(height: 12),
                Text(
                  'Este modo envía el audio grabado a un servidor proxy que ejecuta shazamio. '
                  'Puedes usar tu backend local de Sonero o crear tu propio servidor gratuito '
                  'en Hugging Face Spaces (instrucciones y archivos en sonero-api/deploy_huggingface/).',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () {
                    settings.setShazamProxyUrl(_shazamProxyUrlCtrl.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('URL del Proxy de Shazam guardada'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                  child: const Text('Guardar URL del Proxy'),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),

          // ── Backend API URL ────────────────────────────────────────────
          _Section(
            title: AppLocalizations.of(context)!.apiConnection,
            icon: Icons.api_outlined,
            children: [
              TextField(
                controller: _apiUrlCtrl,
                decoration: const InputDecoration(
                  hintText: 'http://localhost:8000',
                  prefixIcon: Icon(Icons.link, size: 18),
                ),
                style: TextStyle(fontSize: 13),
                onSubmitted: (v) => settings.setApiUrl(v.trim()),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton(
                    onPressed: () => settings.setApiUrl(_apiUrlCtrl.text.trim()),
                    child: const Text('Guardar URL'),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refetch / Probar'),
                    onPressed: () async {
                      final isAlive = await settings.api.checkHealth();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(isAlive ? '✅ Conexión exitosa al backend.' : '❌ No se pudo conectar al backend.'),
                          backgroundColor: isAlive ? context.colors.success : context.colors.error,
                        ));
                      }
                    },
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Listen duration ────────────────────────────────────────────
          _Section(
            title: 'Duración de escucha',
            icon: Icons.timer_outlined,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _durationCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(suffixText: 'seg'),
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final v = int.tryParse(_durationCtrl.text);
                      if (v != null && v >= 5 && v <= 60) {
                        settings.setListenDuration(v);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Duración guardada'),
                          duration: Duration(seconds: 1),
                        ));
                      }
                    },
                    child: Text('Guardar'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('Entre 5 y 60 segundos.',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
            ],
          ),

          const SizedBox(height: 16),

          // ── Lyrics latency/offset ──────────────────────────────────────
          _Section(
            title: 'Retraso de letras global',
            icon: Icons.sync_rounded,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.remove_circle_outline_rounded, color: context.colors.textSecondary),
                    onPressed: () => settings.setLyricsOffset(settings.lyricsOffset - 100),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: context.colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${settings.lyricsOffset >= 0 ? "+" : ""}${(settings.lyricsOffset / 1000.0).toStringAsFixed(2)}s',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: settings.lyricsOffset == 0
                            ? context.colors.textSecondary
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.add_circle_outline_rounded, color: context.colors.textSecondary),
                    onPressed: () => settings.setLyricsOffset(settings.lyricsOffset + 100),
                  ),
                  if (settings.lyricsOffset != 0) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => settings.setLyricsOffset(0),
                      child: const Text('Restablecer'),
                    ),
                  ],
                ],
              ),
              Text(
                'Compensa la latencia del audio (ej. audífonos Bluetooth). Valores positivos retrasan las letras (se muestran después); negativos las adelantan (se muestran antes).',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Hotkeys ──────────────────────────────────────────────────
          // Solo se muestran en escritorio: en Android no existen teclas globales
          if (!kIsWeb && !Platform.isAndroid) ...[
            _Section(
              title: 'Atajos de teclado globales',
              icon: Icons.keyboard_outlined,
              children: [
                Text(
                  'Funcionan aunque la ventana esté minimizada.',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                ),
                const SizedBox(height: 16),
                _HotkeyRow(
                  label: '🎙️ Escuchar con Micrófono',
                  currentKey: HotkeyService.label(
                      context.read<HotkeyService>().currentMicHotkey),
                  onRecord: () => _recordHotkey(context, type: 'mic'),
                ),
                const SizedBox(height: 12),
                _HotkeyRow(
                  label: '🖥️ Escuchar Audio del Sistema',
                  currentKey: HotkeyService.label(
                      context.read<HotkeyService>().currentSystemHotkey),
                  onRecord: () => _recordHotkey(context, type: 'system'),
                ),
                const SizedBox(height: 12),
                _HotkeyRow(
                  label: '📺 Descargar Video (Portapapeles)',
                  currentKey: HotkeyService.label(
                      context.read<HotkeyService>().currentVideoHotkey),
                  onRecord: () => _recordHotkey(context, type: 'video'),
                ),
                const SizedBox(height: 12),
                _HotkeyRow(
                  label: '👀 Mostrar Ventana',
                  currentKey: HotkeyService.label(
                      context.read<HotkeyService>().currentShowHotkey),
                  onRecord: () => _recordHotkey(context, type: 'show'),
                ),
                const SizedBox(height: 12),
                _HotkeyRow(
                  label: '👻 Ocultar Ventana',
                  currentKey: HotkeyService.label(
                      context.read<HotkeyService>().currentHideHotkey),
                  onRecord: () => _recordHotkey(context, type: 'hide'),
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          // ── Mic device ─────────────────────────────────────────────
          _Section(
            title: 'Dispositivo de micrófono',
            icon: Icons.mic_outlined,
            children: [
              _InfoText(settings.deviceIndex != null
                  ? 'Dispositivo #${settings.deviceIndex}'
                  : 'Default del sistema'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.search, size: 16),
                    label: const Text('Detectar dispositivos'),
                    onPressed: () => _showDeviceDialog(context, settings),
                  ),
                  if (settings.deviceIndex != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => settings.setDeviceIndex(null),
                      child: Text('Usar default',
                          style: TextStyle(color: context.colors.textSecondary)),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Mantenimiento de Biblioteca ───────────────────────────────
          _Section(
            title: 'Mantenimiento de Biblioteca',
            icon: Icons.cleaning_services_rounded,
            children: [
              Text(
                'Busca y elimina archivos duplicados exactos en tus directorios de música y video para liberar espacio.',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                icon: const Icon(Icons.find_replace_rounded, size: 16),
                label: const Text('Buscar y Limpiar Duplicados'),
                onPressed: () => _showDuplicatesDialog(context),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // ── Logs de Diagnóstico ───────────────────────────────────────
          _Section(
            title: 'Logs de Diagnóstico',
            icon: Icons.developer_mode_outlined,
            children: [
              Text(
                'Usa esta sección para ver y depurar el funcionamiento interno de la aplicación (ej. descargas y sockets).',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.list_alt_rounded, size: 16),
                label: const Text('Ver Logs de Sonero'),
                onPressed: () => _showLogsDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showLogsDialog(BuildContext pageContext) {
    showDialog(
      context: pageContext,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return FutureBuilder<List<String>>(
              future: LogService.getLogs(),
              builder: (context, snapshot) {
                final logs = snapshot.data ?? [];
                final isLoading = snapshot.connectionState == ConnectionState.waiting;
                return AlertDialog(
                  backgroundColor: context.colors.surfaceAlt,
                  title: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Logs de Diagnóstico'),
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.copy_rounded),
                            tooltip: 'Copiar logs',
                            onPressed: () async {
                              if (logs.isNotEmpty) {
                                await Clipboard.setData(ClipboardData(text: logs.join('\n')));
                                if (pageContext.mounted) {
                                  ScaffoldMessenger.of(pageContext).showSnackBar(
                                    SnackBar(
                                      content: const Text('Logs copiados al portapapeles'),
                                      backgroundColor: pageContext.colors.success,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              } else {
                                if (pageContext.mounted) {
                                  ScaffoldMessenger.of(pageContext).showSnackBar(
                                    SnackBar(
                                      content: const Text('No hay logs para copiar'),
                                      backgroundColor: pageContext.colors.error,
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh_rounded),
                            tooltip: 'Actualizar',
                            onPressed: () => setState(() {}),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            tooltip: 'Limpiar',
                            onPressed: () async {
                              await LogService.clear();
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                  content: SizedBox(
                    width: double.maxFinite,
                    height: 400,
                    child: isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : logs.isEmpty
                            ? Center(
                                child: Text(
                                  'No hay logs registrados aún.',
                                  style: TextStyle(color: context.colors.textSecondary),
                                ),
                              )
                            : Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: context.colors.bg,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: context.colors.border),
                                ),
                                child: ListView.builder(
                                  itemCount: logs.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 2.0),
                                      child: Text(
                                        logs[index],
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 11,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  void _pickColor(BuildContext context, Color currentColor, ValueChanged<Color> onColorChanged) {
    Color tempColor = currentColor;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Theme.of(context).extension<SoneroColors>()!.surfaceAlt,
        title: Text('Seleccionar color'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: tempColor,
            onColorChanged: (c) => tempColor = c,
            enableAlpha: false,
            labelTypes: const [],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              onColorChanged(tempColor);
              Navigator.pop(context);
            },
            child: Text('Guardar'),
          ),
        ],
      ),
    );
  }

  Future<void> _recordHotkey(BuildContext context, {required String type}) async {
    String title = 'Atajo';
    if (type == 'mic') title = '🎙️ Atajo — Micrófono';
    else if (type == 'system') title = '🖥️ Atajo — Sistema';
    else if (type == 'video') title = '📺 Atajo — Video';
    else if (type == 'show') title = '👀 Atajo — Mostrar Ventana';
    else if (type == 'hide') title = '👻 Atajo — Ocultar Ventana';

    HotKey? recorded;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HotkeyRecorderDialog(
        title: title,
        onRecorded: (hk) {
          recorded = hk;
          Navigator.pop(ctx);
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
    if (recorded == null) return;

    final service = context.read<HotkeyService>();

    if (type == 'mic') {
      await service.updateMicHotkey(recorded!);
    } else if (type == 'system') {
      await service.updateSystemHotkey(recorded!);
    } else if (type == 'video') {
      await service.updateVideoHotkey(recorded!);
    } else if (type == 'show') {
      await service.updateShowHotkey(recorded!);
    } else if (type == 'hide') {
      await service.updateHideHotkey(recorded!);
    }

    setState(() {}); // refresh labels
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Atajo guardado'),
        backgroundColor: context.colors.success,
        duration: Duration(seconds: 2),
      ));
    }
  }

  Future<void> _showDeviceDialog(
      BuildContext context, SettingsProvider settings) async {
    List<dynamic> devices = [];
    try {
      final data = await settings.api.getDevices();
      devices = data['devices'] as List;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: context.colors.error));
      }
      return;
    }

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.colors.surfaceAlt,
        title: Text('Dispositivos de audio'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (_, i) {
              final d = devices[i] as Map<String, dynamic>;
              return ListTile(
                title: Text('[${d['index']}] ${d['name']}',
                    style: TextStyle(fontSize: 13)),
                trailing: settings.deviceIndex == d['index']
                    ? Icon(Icons.check, color: context.colors.success, size: 16)
                    : null,
                onTap: () {
                  settings.setDeviceIndex(d['index'] as int);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cerrar')),
        ],
      ),
    );
  }

  void _showDuplicatesDialog(BuildContext pageContext) {
    showDialog(
      context: pageContext,
      barrierDismissible: false,
      builder: (context) {
        return _DuplicatesDialog(pageContext: pageContext);
      },
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Uppercase section header label (outside the card)
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              color: context.colors.textSecondary.withOpacity(0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ),
        // Content card
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 14 : 20,
            vertical: isMobile ? 14 : 16,
          ),
          decoration: BoxDecoration(
            color: context.colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String title;
  const _SectionLabel(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: context.colors.textSecondary.withOpacity(0.6),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InfoText extends StatelessWidget {
  final String text;
  const _InfoText(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: context.colors.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: TextStyle(
                color: context.colors.textSecondary, fontSize: 12),
            overflow: TextOverflow.ellipsis),
      );
}

class _HotkeyRow extends StatelessWidget {
  final String label;
  final String currentKey;
  final VoidCallback onRecord;

  const _HotkeyRow({
    required this.label,
    required this.currentKey,
    required this.onRecord,
  });

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: context.colors.textPrimary,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: context.colors.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    currentKey,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 80,
            child: OutlinedButton(
              onPressed: onRecord,
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.secondary,
                side: BorderSide(color: Theme.of(context).colorScheme.secondary),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      );
}

class _HotkeyRecorderDialog extends StatefulWidget {
  final String title;
  final ValueChanged<HotKey> onRecorded;
  final VoidCallback onCancel;

  const _HotkeyRecorderDialog({
    required this.title,
    required this.onRecorded,
    required this.onCancel,
  });

  @override
  State<_HotkeyRecorderDialog> createState() => _HotkeyRecorderDialogState();
}

class _HotkeyRecorderDialogState extends State<_HotkeyRecorderDialog> {
  HotKey? _recorded;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.colors.surfaceAlt,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Presiona la combinación de teclas que quieres usar.',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 20),
          HotKeyRecorder(
            initalHotKey: HotKey(
              key: PhysicalKeyboardKey.keyM,
              modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
            ),
            onHotKeyRecorded: (hk) => setState(() => _recorded = hk),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: widget.onCancel, child: Text('Cancelar')),
        ElevatedButton(
          onPressed: _recorded != null
              ? () => widget.onRecorded(_recorded!)
              : null,
          child: Text('Confirmar'),
        ),
      ],
    );
  }
}

class _DuplicatesDialog extends StatefulWidget {
  final BuildContext pageContext;
  const _DuplicatesDialog({required this.pageContext});

  @override
  State<_DuplicatesDialog> createState() => _DuplicatesDialogState();
}

class _DuplicatesDialogState extends State<_DuplicatesDialog> {
  String _state = 'scanning'; // 'scanning', 'no_duplicates', 'found', 'cleaning', 'success', 'error'
  List<dynamic> _groups = [];
  int _duplicateCount = 0;
  double _totalSizeMb = 0.0;
  String _errorMessage = '';
  
  int _deletedCount = 0;
  double _spaceSavedMb = 0.0;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _state = 'scanning';
    });
    try {
      final settings = Provider.of<SettingsProvider>(widget.pageContext, listen: false);
      final result = await settings.api.getDuplicates();
      final exact = result['exact_duplicates'] as List? ?? [];
      
      int dupCount = 0;
      double sizeMb = 0.0;
      
      for (final g in exact) {
        final files = g['files'] as List? ?? [];
        if (files.length > 1) {
          dupCount += (files.length - 1);
          final num size = g['size_mb'] ?? 0.0;
          sizeMb += size.toDouble() * (files.length - 1);
        }
      }
      
      setState(() {
        _groups = exact;
        _duplicateCount = dupCount;
        _totalSizeMb = (sizeMb * 100).round() / 100;
        _state = dupCount > 0 ? 'found' : 'no_duplicates';
      });
    } catch (e) {
      setState(() {
        _state = 'error';
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _clean() async {
    setState(() {
      _state = 'cleaning';
    });
    try {
      final settings = Provider.of<SettingsProvider>(widget.pageContext, listen: false);
      final result = await settings.api.cleanDuplicates(dryRun: false);
      
      setState(() {
        _deletedCount = result['deleted_count'] as int? ?? 0;
        final num saved = result['space_saved_mb'] ?? 0.0;
        _spaceSavedMb = saved.toDouble();
        _state = 'success';
      });
    } catch (e) {
      setState(() {
        _state = 'error';
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    
    Widget title;
    Widget content;
    List<Widget> actions = [];

    if (_state == 'scanning') {
      title = const Text('Buscando Duplicados');
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Analizando biblioteca y calculando firmas de archivos...',
            style: TextStyle(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else if (_state == 'no_duplicates') {
      title = const Text('Biblioteca Limpia');
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded, color: colors.success, size: 64),
          const SizedBox(height: 20),
          Text(
            'No se encontraron archivos duplicados byte a byte en tu biblioteca.',
            style: TextStyle(color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
        ],
      );
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ];
    } else if (_state == 'found') {
      title = Text('Duplicados Detectados ($_duplicateCount)');
      content = SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Se encontraron $_duplicateCount archivos duplicados. Se pueden liberar $_totalSizeMb MB eliminando las copias redundantes.',
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Archivos que se eliminarán (se conservará la versión más antigua o vinculada a la base de datos):',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: colors.textPrimary),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200),
                decoration: BoxDecoration(
                  color: colors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.border),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: _groups.length,
                  separatorBuilder: (_, __) => Divider(color: colors.border, height: 16),
                  itemBuilder: (context, idx) {
                    final group = _groups[idx];
                    final files = group['files'] as List;
                    final size = group['size_mb'] ?? 0.0;
                    
                    final winner = files.first;
                    final losers = files.sublist(1);
                    
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Título: ${winner['title'] ?? winner['filename']}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Conservar: ${winner['filename']}',
                          style: TextStyle(fontSize: 11, color: colors.success),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        ...losers.map((loser) => Padding(
                          padding: const EdgeInsets.only(top: 2.0),
                          child: Text(
                            'Eliminar: ${loser['filename']} ($size MB)',
                            style: TextStyle(fontSize: 11, color: colors.error),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        )),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _clean,
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.error,
            foregroundColor: Colors.white,
          ),
          child: const Text('Limpiar Duplicados'),
        ),
      ];
    } else if (_state == 'cleaning') {
      title = const Text('Limpiando Biblioteca');
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 20),
          Text(
            'Eliminando archivos del disco y actualizando base de datos...',
            style: TextStyle(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      );
    } else if (_state == 'success') {
      title = const Text('Biblioteca Limpia');
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.done_all_rounded, color: colors.success, size: 64),
          const SizedBox(height: 20),
          Text(
            '¡Limpieza realizada con éxito!',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Se eliminaron $_deletedCount archivos duplicados.\nEspacio liberado: $_spaceSavedMb MB.',
            style: TextStyle(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      );
      actions = [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
            try {
              final libraryProvider = Provider.of<LibraryProvider>(widget.pageContext, listen: false);
              final settingsProvider = Provider.of<SettingsProvider>(widget.pageContext, listen: false);
              libraryProvider.loadTracks(settingsProvider.api);
            } catch (_) {}
          },
          child: const Text('Cerrar'),
        ),
      ];
    } else { // 'error'
      title = const Text('Error en Limpieza');
      content = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, color: colors.error, size: 64),
          const SizedBox(height: 20),
          Text(
            'Ocurrió un error al procesar la limpieza:',
            style: TextStyle(fontWeight: FontWeight.bold, color: colors.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      );
      actions = [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cerrar'),
        ),
      ];
    }

    return AlertDialog(
      backgroundColor: colors.surfaceAlt,
      title: title,
      content: content,
      actions: actions,
    );
  }
}


/// Opt-in for letting the backend read YouTube cookies from one browser.
/// Off by default: reading a browser's cookie store exposes all of its cookies
/// to the backend process and, on macOS, needs keychain access.
class _BrowserCookiesTile extends StatefulWidget {
  const _BrowserCookiesTile();

  @override
  State<_BrowserCookiesTile> createState() => _BrowserCookiesTileState();
}

class _BrowserCookiesTileState extends State<_BrowserCookiesTile> {
  static const _browsers = {
    'chrome': 'Chrome',
    'brave': 'Brave',
    'edge': 'Edge',
    'firefox': 'Firefox',
    'opera': 'Opera',
    'safari': 'Safari',
    'vivaldi': 'Vivaldi',
    'chromium': 'Chromium',
  };

  String? _browser;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final api = context.read<SettingsProvider>().api;
    api.getCookieBrowser().then((value) {
      if (mounted) setState(() { _browser = value; _loading = false; });
    }).catchError((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _change(String? browser) async {
    if (browser == _browser) return;
    if (browser != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('¿Usar cookies de ${_browsers[browser]}?'),
          content: const Text(
            'Sonero leerá las cookies de ese navegador para que YouTube no bloquee las descargas. '
            'Solo se envían a YouTube, pero el servidor de Sonero tendrá acceso a todas las cookies del navegador.\n\n'
            'En macOS el sistema te pedirá permiso para acceder al Llavero.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Permitir')),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final saved = await context.read<SettingsProvider>().api.setCookieBrowser(browser);
      if (mounted) setState(() => _browser = saved);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: context.colors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.cookie_outlined, size: 18, color: context.colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Leer cookies de un navegador',
            style: TextStyle(color: context.colors.textPrimary, fontSize: 13),
          ),
        ),
        if (_loading || _saving)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        else
          DropdownButton<String?>(
            value: _browser,
            underline: const SizedBox.shrink(),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('Desactivado')),
              ..._browsers.entries.map((e) => DropdownMenuItem<String?>(value: e.key, child: Text(e.value))),
            ],
            onChanged: _change,
          ),
      ],
    );
  }
}


/// What affects YouTube downloads: yt-dlp version, JavaScript runtime and cookies.
class _YoutubeStatusTile extends StatefulWidget {
  const _YoutubeStatusTile();

  @override
  State<_YoutubeStatusTile> createState() => _YoutubeStatusTileState();
}

class _YoutubeStatusTileState extends State<_YoutubeStatusTile> {
  Map<String, dynamic>? _status;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await context.read<SettingsProvider>().api.getYoutubeStatus();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null) {
      return _error == null
          ? const LinearProgressIndicator()
          : Text('No se pudo consultar el estado de YouTube.', style: TextStyle(color: context.colors.textSecondary, fontSize: 12));
    }
    final ok = s['ok'] == true;
    final issues = ((s['issues'] as List?) ?? const []).cast<String>();
    final cookies = s['cookies'] as String?;
    Widget row(IconData icon, String label, String value, {bool good = true}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(children: [
            Icon(icon, size: 16, color: good ? context.colors.success : Colors.orange),
            const SizedBox(width: 8),
            Text('$label: ', style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
            Expanded(child: Text(value, style: TextStyle(color: context.colors.textPrimary, fontSize: 12))),
          ]),
        );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? context.colors.border : Colors.orange.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                color: ok ? context.colors.success : Colors.orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(ok ? 'Descargas de YouTube listas' : 'Descargas de YouTube: revisa esto',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            ),
            IconButton(icon: const Icon(Icons.refresh_rounded, size: 18), tooltip: 'Actualizar', onPressed: _load),
          ]),
          row(Icons.system_update_alt_rounded, 'yt-dlp', '${s['ytdlp_version']}', good: s['outdated'] != true),
          row(Icons.code_rounded, 'Motor JavaScript', s['js_runtime'] as String? ?? 'no encontrado',
              good: s['js_runtime'] != null && s['ejs_installed'] == true),
          row(Icons.cookie_outlined, 'Cookies',
              cookies == null ? 'no configuradas (YouTube puede bloquear descargas, sobre todo con VPN)'
                  : cookies == 'file' ? 'archivo cookies.txt' : 'navegador ${cookies.replaceFirst('browser:', '')}',
              good: cookies != null),
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('• $issue', style: TextStyle(color: Colors.orange.shade300, fontSize: 12, height: 1.35)),
            ),
        ],
      ),
    );
  }
}
