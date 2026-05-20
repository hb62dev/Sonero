import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';
import '../../core/hotkey_service.dart';
import '../../providers/listen_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';
import '../../services/log_service.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _apiUrlCtrl;
  late final TextEditingController _durationCtrl;

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _apiUrlCtrl = TextEditingController(text: settings.apiUrl);
    _durationCtrl = TextEditingController(text: settings.listenDuration.toString());
  }

  @override
  void dispose() {
    _apiUrlCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: context.colors.surface,
        title: Text(AppLocalizations.of(context)!.settings,
            style: TextStyle(color: context.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        iconTheme: IconThemeData(color: context.colors.textSecondary),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: context.colors.border),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.of(context).size.width < 600 ? 16 : 24,  // left
          MediaQuery.of(context).size.width < 600 ? 16 : 24,  // top
          MediaQuery.of(context).size.width < 600 ? 16 : 24,  // right
          MediaQuery.of(context).size.width < 600 ? 40 : 32,  // bottom — extra para que no quede cortado
        ),
        children: [
          // ── Music folder ───────────────────────────────────────────────
          _Section(
            title: AppLocalizations.of(context)!.musicFolder,
            icon: Icons.folder_outlined,
            children: [
              _InfoText(
                settings.hasMusicFolder
                    ? settings.musicFolder
                    : 'No seleccionada',
              ),
              const SizedBox(height: 10),
            // ── Botones: Seleccionar + Abrir (Wrap para mobile) ──────────────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Seleccionar carpeta'),
                    onPressed: () async {
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
                      onPressed: () {
                        final path = settings.musicFolder;
                        if (Platform.isWindows) {
                          Process.run('explorer', [path]);
                        } else if (Platform.isMacOS) {
                          Process.run('open', [path]);
                        } else if (Platform.isLinux) {
                          Process.run('xdg-open', [path]);
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

          const SizedBox(height: 24),

          // ── Video folder ───────────────────────────────────────────────
          _Section(
            title: 'Carpeta de Video',
            icon: Icons.video_library_outlined,
            children: [
              _InfoText(
                settings.hasVideoFolder
                    ? settings.videoFolder
                    : 'No seleccionada',
              ),
              const SizedBox(height: 10),
              // ── Botones: Seleccionar + Abrir video (Wrap para mobile) ──────
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Seleccionar carpeta'),
                    onPressed: () async {
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
                      onPressed: () {
                        final path = settings.videoFolder;
                        if (Platform.isWindows) {
                          Process.run('explorer', [path]);
                        } else if (Platform.isMacOS) {
                          Process.run('open', [path]);
                        } else if (Platform.isLinux) {
                          Process.run('xdg-open', [path]);
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

          const SizedBox(height: 24),

          // ── Language ────────────────────────────────────────────────────
          _Section(
            title: AppLocalizations.of(context)!.language,
            icon: Icons.language,
            children: [
              DropdownButton<String>(
                value: settings.locale,
                dropdownColor: context.colors.surfaceAlt,
                underline: const SizedBox(),
                isExpanded: true,
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

          const SizedBox(height: 24),

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
            ],
          ),

          const SizedBox(height: 24),

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

          const SizedBox(height: 24),
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
              // ── Botones API: Wrap para que bajen de línea en mobile ──────────
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

          const SizedBox(height: 24),

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

          const SizedBox(height: 24),

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

          const SizedBox(height: 24),

          // ── Hotkeys ──────────────────────────────────────────────────
          // Solo se muestran en escritorio: en Android no existen teclas globales
          if (!Platform.isAndroid) ...[
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
            const SizedBox(height: 24),
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
          const SizedBox(height: 24),
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

  void _showLogsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final logs = LogService.getLogs();
            return AlertDialog(
              backgroundColor: context.colors.surfaceAlt,
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Logs de Diagnóstico'),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: 'Actualizar',
                        onPressed: () => setState(() {}),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: 'Limpiar',
                        onPressed: () {
                          LogService.clear();
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
                child: logs.isEmpty
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
    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      decoration: BoxDecoration(
        color: context.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: isMobile ? 16 : 18, color: Theme.of(context).colorScheme.primary),
              SizedBox(width: isMobile ? 6 : 8),
              Text(title,
                  style: TextStyle(
                      color: context.colors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: isMobile ? 13 : 14)),
            ],
          ),
          SizedBox(height: isMobile ? 12 : 16),
          ...children,
        ],
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
          border: Border.all(color: context.colors.border),
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
                // ── Chip de atajo de teclado ───────────────────────────────
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




