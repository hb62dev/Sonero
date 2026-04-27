import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:provider/provider.dart';
import '../../core/hotkey_service.dart';
import '../../providers/listen_provider.dart';
import '../../providers/settings_provider.dart';
import '../theme.dart';

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
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Configuración',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        iconTheme: const IconThemeData(color: AppTheme.textSecondary),
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppTheme.border),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          // ── Music folder ───────────────────────────────────────────────
          _Section(
            title: 'Carpeta de música',
            icon: Icons.folder_outlined,
            children: [
              _InfoText(
                settings.hasMusicFolder
                    ? settings.musicFolder
                    : 'No seleccionada',
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Seleccionar carpeta'),
                    onPressed: () async {
                      final result = await FilePicker.platform.getDirectoryPath(
                        dialogTitle: 'Selecciona la carpeta donde guardar la música',
                      );
                      if (result != null) {
                        await settings.setMusicFolder(result);
                      }
                    },
                  ),
                  if (settings.hasMusicFolder) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => settings.setMusicFolder(''),
                      child: const Text('Limpiar',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ],
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Backend API URL ────────────────────────────────────────────
          _Section(
            title: 'Backend API',
            icon: Icons.api_outlined,
            children: [
              TextField(
                controller: _apiUrlCtrl,
                decoration: const InputDecoration(
                  hintText: 'http://localhost:8000',
                  prefixIcon: Icon(Icons.link, size: 18),
                ),
                style: const TextStyle(fontSize: 13),
                onSubmitted: (v) => settings.setApiUrl(v.trim()),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton(
                  onPressed: () => settings.setApiUrl(_apiUrlCtrl.text.trim()),
                  child: const Text('Guardar URL'),
                ),
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
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () {
                      final v = int.tryParse(_durationCtrl.text);
                      if (v != null && v >= 5 && v <= 60) {
                        settings.setListenDuration(v);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Duración guardada'),
                          duration: Duration(seconds: 1),
                        ));
                      }
                    },
                    child: const Text('Guardar'),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text('Entre 5 y 60 segundos.',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
            ],
          ),

          const SizedBox(height: 24),

          // ── Hotkeys ────────────────────────────────────────────────────
          _Section(
            title: 'Atajos de teclado globales',
            icon: Icons.keyboard_outlined,
            children: [
              const Text(
                'Funcionan aunque la ventana esté minimizada.',
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              _HotkeyRow(
                label: '🎙️ Escuchar con Micrófono',
                currentKey: HotkeyService.label(
                    context.read<HotkeyService>().currentMicHotkey),
                onRecord: () => _recordHotkey(context, isMic: true),
              ),
              const SizedBox(height: 12),
              _HotkeyRow(
                label: '🖥️ Escuchar Audio del Sistema',
                currentKey: HotkeyService.label(
                    context.read<HotkeyService>().currentSystemHotkey),
                onRecord: () => _recordHotkey(context, isMic: false),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Mic device ────────────────────────────────────────────────
          _Section(
            title: 'Dispositivo de micrófono',
            icon: Icons.mic_outlined,
            children: [
              _InfoText(settings.deviceIndex != null
                  ? 'Dispositivo #${settings.deviceIndex}'
                  : 'Default del sistema'),
              const SizedBox(height: 8),
              Row(
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
                      child: const Text('Usar default',
                          style: TextStyle(color: AppTheme.textSecondary)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _recordHotkey(BuildContext context, {required bool isMic}) async {
    // Show a dialog that captures the next key combination
    HotKey? recorded;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HotkeyRecorderDialog(
        title: isMic ? '🎙️ Atajo — Micrófono' : '🖥️ Atajo — Sistema',
        onRecorded: (hk) {
          recorded = hk;
          Navigator.pop(ctx);
        },
        onCancel: () => Navigator.pop(ctx),
      ),
    );
    if (recorded == null) return;

    final service = context.read<HotkeyService>();

    if (isMic) {
      await service.updateMicHotkey(
        recorded!,
        () => _triggerListen(context, source: 'mic'),
      );
    } else {
      await service.updateSystemHotkey(
        recorded!,
        () => _triggerListen(context, source: 'system'),
      );
    }

    setState(() {}); // refresh labels
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Atajo guardado'),
        backgroundColor: AppTheme.success,
        duration: Duration(seconds: 2),
      ));
    }
  }

  void _triggerListen(BuildContext context, {required String source}) {
    final settings = context.read<SettingsProvider>();
    context.read<ListenProvider>().startListening(
          api: settings.api,
          source: source,
          duration: settings.listenDuration,
          deviceIndex: settings.deviceIndex,
        );
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
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.error));
      }
      return;
    }

    if (!context.mounted) return;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceAlt,
        title: const Text('Dispositivos de audio'),
        content: SizedBox(
          width: 400,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (_, i) {
              final d = devices[i] as Map<String, dynamic>;
              return ListTile(
                title: Text('[${d['index']}] ${d['name']}',
                    style: const TextStyle(fontSize: 13)),
                trailing: settings.deviceIndex == d['index']
                    ? const Icon(Icons.check, color: AppTheme.success, size: 16)
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
              child: const Text('Cerrar')),
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
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: AppTheme.accent1),
                const SizedBox(width: 8),
                Text(title,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ],
            ),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );
}

class _InfoText extends StatelessWidget {
  final String text;
  const _InfoText(this.text);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(text,
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 13)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppTheme.bg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.accent1.withValues(alpha: 0.5)),
                  ),
                  child: Text(currentKey,
                      style: const TextStyle(
                          color: AppTheme.accent1,
                          fontSize: 12,
                          fontFamily: 'monospace')),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: onRecord,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.accent2,
              side: const BorderSide(color: AppTheme.accent2),
              shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Cambiar', style: TextStyle(fontSize: 12)),
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
      backgroundColor: AppTheme.surfaceAlt,
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Presiona la combinación de teclas que quieres usar.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
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
        TextButton(onPressed: widget.onCancel, child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: _recorded != null
              ? () => widget.onRecorded(_recorded!)
              : null,
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}

