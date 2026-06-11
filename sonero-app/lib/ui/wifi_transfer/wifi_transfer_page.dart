import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/wifi_transfer_service.dart';
import '../theme.dart';

class WifiTransferPage extends StatefulWidget {
  final List<Map<String, dynamic>>? initialFilesToSend;
  final VoidCallback? onClearFiles;

  const WifiTransferPage({
    super.key,
    this.initialFilesToSend,
    this.onClearFiles,
  });

  @override
  State<WifiTransferPage> createState() => _WifiTransferPageState();
}

class _WifiTransferPageState extends State<WifiTransferPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _ipController = TextEditingController();

  final Map<String, TransferProgress> _receiveItems = {};
  final Map<String, TransferProgress> _sendItems = {};
  List<Map<String, dynamic>> _filesToSend = [];

  StreamSubscription<TransferProgress>? _receiveSub;
  StreamSubscription<TransferProgress>? _sendSub;

  bool _isSending = false;
  String? _localIp;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    if (widget.initialFilesToSend != null) {
      _filesToSend = List.from(widget.initialFilesToSend!);
    } else {
      // Default: Receive tab first if nothing to send
      _tabController.index = 1;
    }

    _loadLocalIp();
    _setupProgressSubscriptions();
  }

  Future<void> _loadLocalIp() async {
    final ip = await WifiTransferService.instance.getLocalIpAddress();
    if (mounted) {
      setState(() {
        _localIp = ip;
      });
    }
  }

  void _setupProgressSubscriptions() {
    _receiveSub = WifiTransferService.instance.receiveProgressStream.listen((event) {
      if (mounted) {
        setState(() {
          _receiveItems[event.filename] = event;
        });
      }
    });

    _sendSub = WifiTransferService.instance.sendProgressStream.listen((event) {
      if (mounted) {
        setState(() {
          _sendItems[event.filename] = event;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _ipController.dispose();
    _receiveSub?.cancel();
    _sendSub?.cancel();
    super.dispose();
  }

  void _clearSelectedFiles() {
    setState(() {
      _filesToSend.clear();
      _sendItems.clear();
    });
    if (widget.onClearFiles != null) {
      widget.onClearFiles!();
    }
  }

  Future<void> _startSending() async {
    final targetIp = _ipController.text.trim();
    if (targetIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, ingresa la IP del destinatario.')),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      await WifiTransferService.instance.sendFiles(
        targetIp: targetIp,
        files: _filesToSend,
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Envío de archivos finalizado.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error en el envío: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  Future<void> _toggleServer(SettingsProvider settings, LibraryProvider library) async {
    final service = WifiTransferService.instance;
    if (service.isServerRunning) {
      await service.stopServer(() {
        if (mounted) setState(() {});
      });
    } else {
      try {
        await service.startServer(
          musicFolder: settings.musicFolder,
          videoFolder: settings.videoFolder,
          onUpdate: () {
            if (mounted) {
              setState(() {});
              // Reload library dynamically if new items are added
              library.loadTracks(settings.api);
              library.loadPlaylists(settings.api);
            }
          },
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar el servidor: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final library = context.watch<LibraryProvider>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.swap_horizontal_circle_rounded, color: primaryColor, size: 24),
            const SizedBox(width: 8),
            const Text(
              'Compartir vía WiFi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryColor,
          labelColor: context.colors.textPrimary,
          unselectedLabelColor: context.colors.textSecondary,
          tabs: const [
            Tab(text: 'Enviar'),
            Tab(text: 'Recibir'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSendTab(isMobile),
          _buildReceiveTab(settings, library, isMobile),
        ],
      ),
    );
  }

  Widget _buildSendTab(bool isMobile) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    if (_filesToSend.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.colors.surfaceAlt,
                ),
                child: Icon(Icons.wifi_off_rounded, size: 48, color: context.colors.textSecondary.withValues(alpha: 0.5)),
              ),
              const SizedBox(height: 16),
              Text(
                'Sin archivos seleccionados',
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Ve a tu Biblioteca, mantén presionado un archivo para activar el modo de selección, marca las canciones o videos que deseas enviar y toca el icono de WiFi en la barra inferior.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.colors.textSecondary,
                  fontSize: 12,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final totalFiles = _filesToSend.length;
    int completedFiles = 0;
    for (var file in _filesToSend) {
      final filename = file['filename'] as String;
      if (_sendItems[filename]?.status == 'done') {
        completedFiles++;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header/Config Card ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Enviar $totalFiles archivo(s)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    TextButton.icon(
                      onPressed: _isSending ? null : _clearSelectedFiles,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: const Text('Limpiar', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: context.colors.error),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _ipController,
                        enabled: !_isSending,
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Ej. 192.168.1.50',
                          labelText: 'IP del Recibidor',
                          prefixIcon: const Icon(Icons.network_wifi_3_bar, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _isSending ? null : _startSending,
                      icon: _isSending
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, size: 16),
                      label: Text(_isSending ? 'Enviando' : 'Enviar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Queue Header ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cola de Envío',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                '$completedFiles / $totalFiles completados',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Send items list ────────────────────────────────────────────────
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _filesToSend.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final file = _filesToSend[index];
              final filename = file['filename'] as String;
              final type = file['type'] as String;
              final progress = _sendItems[filename];

              return _buildTransferTile(filename, type, progress);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildReceiveTab(SettingsProvider settings, LibraryProvider library, bool isMobile) {
    final service = WifiTransferService.instance;
    final isRunning = service.isServerRunning;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Pulse / Toggle Card ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: context.colors.surfaceAlt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: context.colors.border),
            ),
            child: Column(
              children: [
                // Pulser Radar
                SizedBox(
                  height: 140,
                  width: 140,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isRunning) ...[
                        // Staggered circles
                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withValues(alpha: 0.08),
                            border: Border.all(color: primaryColor.withValues(alpha: 0.2), width: 1.5),
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat())
                        .scale(begin: const Offset(0.7, 0.7), end: const Offset(2.0, 2.0), duration: 2.5.seconds)
                        .fade(begin: 1.0, end: 0.0, duration: 2.5.seconds),

                        Container(
                          width: 130,
                          height: 130,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: primaryColor.withValues(alpha: 0.08),
                            border: Border.all(color: primaryColor.withValues(alpha: 0.2), width: 1.5),
                          ),
                        )
                        .animate(onPlay: (c) => c.repeat())
                        .scale(begin: const Offset(0.7, 0.7), end: const Offset(2.0, 2.0), duration: 2.5.seconds, delay: 1.2.seconds)
                        .fade(begin: 1.0, end: 0.0, duration: 2.5.seconds, delay: 1.2.seconds),
                      ],
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isRunning ? primaryColor : context.colors.border,
                          boxShadow: isRunning
                              ? [
                                  BoxShadow(
                                    color: primaryColor.withValues(alpha: 0.4),
                                    blurRadius: 16,
                                    spreadRadius: 2,
                                  )
                                ]
                              : null,
                        ),
                        child: Icon(
                          isRunning ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                          size: 32,
                          color: isRunning ? Colors.white : context.colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // IP & instructions
                if (isRunning) ...[
                  const Text(
                    'Listo para recibir archivos',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SelectableText(
                        _localIp != null ? '$_localIp' : 'Cargando IP...',
                        style: TextStyle(
                          color: primaryColor,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        onPressed: () {
                          if (_localIp != null) {
                            Clipboard.setData(ClipboardData(text: _localIp!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('IP copiada al portapapeles.')),
                            );
                          }
                        },
                        tooltip: 'Copiar IP',
                      ),
                    ],
                  ),
                  Text(
                    'Ingresa esta dirección IP en el dispositivo emisor para iniciar la transferencia.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                ] else ...[
                  const Text(
                    'Recepción Desactivada',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Activa el servidor para poder recibir música o videos desde otros dispositivos en la misma red WiFi.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),

                // Toggle Button
                SizedBox(
                  width: 200,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: () => _toggleServer(settings, library),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRunning ? context.colors.error : primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(isRunning ? 'Apagar Servidor' : 'Iniciar Recepción'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Incoming list header ───────────────────────────────────────────
          if (_receiveItems.isNotEmpty) ...[
            const Row(
              children: [
                Text(
                  'Archivos Recibidos / En Progreso',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Incoming list
            Expanded(
              child: ListView.separated(
                itemCount: _receiveItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final filename = _receiveItems.keys.elementAt(index);
                  final progress = _receiveItems[filename]!;
                  final isVideo = filename.endsWith('.mp4') || filename.endsWith('.mkv');
                  final type = isVideo ? 'video' : (filename.endsWith('.jpg') ? 'cover' : 'music');

                  return _buildTransferTile(filename, type, progress);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTransferTile(String filename, String type, TransferProgress? progress) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    IconData icon;
    Color iconColor;

    if (type == 'music') {
      icon = Icons.music_note_rounded;
      iconColor = primaryColor;
    } else if (type == 'video') {
      icon = Icons.videocam_rounded;
      iconColor = Colors.cyan;
    } else {
      icon = Icons.image_rounded;
      iconColor = Colors.orange;
    }

    final int pct = progress?.progress ?? 0;
    final String status = progress?.status ?? 'preparing';
    String statusLabel = '⏳ Esperando...';
    Color statusColor = context.colors.textSecondary;

    if (status == 'transferring') {
      statusLabel = '⚡ Transfiriendo... $pct%';
      statusColor = primaryColor;
    } else if (status == 'done') {
      statusLabel = '✅ Completado';
      statusColor = Colors.lightGreen;
    } else if (status == 'failed') {
      statusLabel = '❌ Falló: ${progress?.error ?? 'Error desconocido'}';
      statusColor = context.colors.error;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
              ),
              if (status == 'transferring')
                Text(
                  '$pct%',
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                ),
            ],
          ),
          if (status == 'transferring') ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct / 100.0,
                minHeight: 4,
                backgroundColor: context.colors.border,
                valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
