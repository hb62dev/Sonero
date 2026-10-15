import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:sonero_app/l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../providers/library_provider.dart';
import '../../services/wifi_transfer_backend.dart';
import '../../services/wifi_transfer_service.dart';
import '../theme.dart';

/// Share music/videos with other Sonero devices on the same WiFi network.
///
/// Two transports, chosen by how the app talks to its data:
///  * Backend mode (Windows/macOS desktop and web): the Python backend runs the
///    receiver on port 8090 and sends files from its own music folder.
///  * Native mode (Android standalone): the Flutter app itself runs the receiver.
/// Both speak the same /prepare + /upload protocol, so they interoperate.
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

  // Backend mode
  WifiTransferBackend? _backend;
  BackendTransferStatus? _backendStatus;
  String? _backendError;
  Timer? _pollTimer;
  int? _receivedDoneCount; // null until the first status arrives
  bool _togglingReceiver = false;

  bool _isSending = false;
  String? _localIp;

  bool get _useBackend => _backend != null;

  bool get _isReceiving =>
      _useBackend ? (_backendStatus?.receiving ?? false) : WifiTransferService.instance.isServerRunning;

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

    final settings = context.read<SettingsProvider>();
    if (!settings.api.isNative) {
      _backend = WifiTransferBackend(settings.apiUrl);
      _pollBackend();
      _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) => _pollBackend());
    } else {
      _loadLocalIp();
      _setupProgressSubscriptions();
    }
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

  Future<void> _pollBackend() async {
    final backend = _backend;
    if (backend == null) return;
    try {
      _applyBackendStatus(await backend.status());
      _backendError = null;
    } catch (e) {
      if (mounted) setState(() => _backendError = e.toString());
    }
  }

  void _applyBackendStatus(BackendTransferStatus status) {
    if (!mounted) return;

    // Refresh the library when new files finished arriving
    final doneCount = status.receive.where((i) => i.status == 'done' && !i.duplicate).length;
    if (_receivedDoneCount != null && doneCount > _receivedDoneCount!) {
      final settings = context.read<SettingsProvider>();
      final library = context.read<LibraryProvider>();
      library.loadTracks(settings.api);
      library.loadPlaylists(settings.api);
    }
    _receivedDoneCount = doneCount;

    final wasSending = _isSending;
    setState(() {
      _backendStatus = status;
      _localIp = status.ip;
      _receiveItems
        ..clear()
        ..addEntries(status.receive.map((i) => MapEntry(i.filename, i)));
      _sendItems
        ..clear()
        ..addEntries(status.send.map((i) => MapEntry(i.filename, i)));
      _isSending = status.sending;
    });

    if (wasSending && !status.sending) _showSendSummary();
  }

  void _showSendSummary() {
    final l10n = AppLocalizations.of(context)!;
    final failed = _sendItems.values.where((i) => i.status == 'failed').toList();
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(failed.isEmpty
          ? l10n.wifiSendFinished
          : l10n.wifiSendError(failed.first.error ?? l10n.wifiUnknownError)),
    ));
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
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
    _backend?.clearFinished().then(_applyBackendStatus).catchError((_) {});
    if (widget.onClearFiles != null) {
      widget.onClearFiles!();
    }
  }

  Future<void> _startSending() async {
    final l10n = AppLocalizations.of(context)!;
    final targetIp = _ipController.text.trim();
    if (targetIp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.wifiEnterIp)),
      );
      return;
    }

    setState(() {
      _isSending = true;
    });

    if (_useBackend) {
      try {
        _applyBackendStatus(await _backend!.send(targetIp: targetIp, files: _filesToSend));
      } catch (e) {
        if (!mounted) return;
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wifiSendError(_cleanError(e)))),
        );
      }
      return; // progress and the final summary come from polling
    }

    try {
      await WifiTransferService.instance.sendFiles(
        targetIp: targetIp,
        files: _filesToSend,
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );
      if (!mounted) return;
      _showSendSummary();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.wifiSendError(_cleanError(e)))),
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
    final l10n = AppLocalizations.of(context)!;

    if (_useBackend) {
      setState(() => _togglingReceiver = true);
      try {
        _applyBackendStatus(_isReceiving
            ? await _backend!.stopReceiving()
            : await _backend!.startReceiving());
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.wifiStartError(_cleanError(e)))),
        );
      } finally {
        if (mounted) setState(() => _togglingReceiver = false);
      }
      return;
    }

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
          SnackBar(content: Text(l10n.wifiStartError(_cleanError(e)))),
        );
      }
    }
  }

  String _cleanError(Object e) => e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  void _copy(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.wifiCopied)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = context.watch<SettingsProvider>();
    final library = context.watch<LibraryProvider>();
    final isMobile = MediaQuery.of(context).size.width < 600;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 24,
        title: Row(
          children: [
            Icon(Icons.swap_horizontal_circle_rounded, color: primaryColor, size: 24),
            const SizedBox(width: 8),
            Text(
              l10n.wifiTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: primaryColor,
          labelColor: context.colors.textPrimary,
          unselectedLabelColor: context.colors.textSecondary,
          tabs: [
            Tab(text: l10n.wifiTabSend),
            Tab(text: l10n.wifiTabReceive),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_useBackend && _backendError != null && _backendStatus == null)
            _buildBanner(Icons.cloud_off_rounded, l10n.wifiBackendUnavailable, context.colors.error),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSendTab(isMobile),
                _buildReceiveTab(settings, library, isMobile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBanner(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: context.colors.textPrimary, fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildSendTab(bool isMobile) {
    final l10n = AppLocalizations.of(context)!;
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
                l10n.wifiNoFilesTitle,
                style: TextStyle(
                  color: context.colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  l10n.wifiNoFilesHint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: context.colors.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
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

    final ipField = TextField(
      controller: _ipController,
      enabled: !_isSending,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(fontSize: 14),
      onSubmitted: (_) => _isSending ? null : _startSending(),
      decoration: InputDecoration(
        hintText: l10n.wifiReceiverIpHint,
        labelText: l10n.wifiReceiverIp,
        prefixIcon: const Icon(Icons.network_wifi_3_bar, size: 18),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );

    final sendButton = ElevatedButton.icon(
      onPressed: _isSending ? null : _startSending,
      icon: _isSending
          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
          : const Icon(Icons.send_rounded, size: 16),
      label: Text(_isSending ? l10n.wifiSending : l10n.wifiSend),
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );

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
                      l10n.wifiSendCount(totalFiles),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    TextButton.icon(
                      onPressed: _isSending ? null : _clearSelectedFiles,
                      icon: const Icon(Icons.clear_all, size: 16),
                      label: Text(l10n.wifiClear, style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(foregroundColor: context.colors.error),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (isMobile) ...[
                  ipField,
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: sendButton),
                ] else
                  Row(
                    children: [
                      Expanded(child: ipField),
                      const SizedBox(width: 12),
                      sendButton,
                    ],
                  ),
                const SizedBox(height: 10),
                Text(
                  l10n.wifiSameNetworkTip,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Queue Header ───────────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.wifiQueue,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              Text(
                l10n.wifiCompleted(completedFiles, totalFiles),
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
    final l10n = AppLocalizations.of(context)!;
    final isRunning = _isReceiving;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final uploadUrl = _backendStatus?.uploadUrl;
    final otherIps = (_backendStatus?.ips ?? const <String>[]).where((ip) => ip != _localIp).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // ── Pulse / Toggle Card ────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(isMobile ? 16 : 24),
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
                  Text(
                    l10n.wifiReady,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  if (_localIp == null)
                    Text(l10n.wifiNoNetwork,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.colors.error, fontSize: 12))
                  else
                    _copyableValue(_localIp!, primaryColor, fontSize: 20),
                  Text(
                    l10n.wifiEnterIpOnSender,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                  if (otherIps.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.wifiOtherIps(otherIps.join(', ')),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                    ),
                  ],
                  if (uploadUrl != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: context.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: context.colors.border),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.phone_iphone_rounded, size: 16, color: context.colors.textSecondary),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  l10n.wifiOrOpenInBrowser,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          _copyableValue(uploadUrl, primaryColor, fontSize: 15),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  Text(
                    l10n.wifiReceiveOff,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l10n.wifiReceiveOffHint,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),

                // Toggle Button
                SizedBox(
                  width: 220,
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _togglingReceiver || (_useBackend && _backendStatus == null)
                        ? null
                        : () => _toggleServer(settings, library),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isRunning ? context.colors.error : primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _togglingReceiver
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(isRunning ? l10n.wifiStopReceiving : l10n.wifiStartReceiving),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.wifiSameNetworkTip,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: context.colors.textSecondary, fontSize: 11, height: 1.4),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Incoming list ──────────────────────────────────────────────────
          if (_receiveItems.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.wifiReceivedList,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _receiveItems.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                // Newest first
                final filename = _receiveItems.keys.elementAt(_receiveItems.length - 1 - index);
                final progress = _receiveItems[filename]!;
                return _buildTransferTile(filename, _typeFromFilename(filename), progress);
              },
            ),
          ],
        ],
      ),
    );
  }

  String _typeFromFilename(String filename) {
    final lower = filename.toLowerCase();
    if (RegExp(r'\.(mp4|mkv|mov)$').hasMatch(lower)) return 'video';
    if (RegExp(r'\.(jpe?g|png|webp)$').hasMatch(lower)) return 'cover';
    return 'music';
  }

  Widget _copyableValue(String value, Color color, {required double fontSize}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: SelectableText(
            value,
            textAlign: TextAlign.center,
            style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.copy_rounded, size: 18),
          onPressed: () => _copy(value),
          tooltip: AppLocalizations.of(context)!.wifiCopy,
        ),
      ],
    );
  }

  Widget _buildTransferTile(String filename, String type, TransferProgress? progress) {
    final l10n = AppLocalizations.of(context)!;
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
    String statusLabel = '⏳ ${l10n.wifiStatusWaiting}';
    Color statusColor = context.colors.textSecondary;

    if (status == 'transferring') {
      statusLabel = '⚡ ${l10n.wifiStatusTransferring(pct)}';
      statusColor = primaryColor;
    } else if (status == 'done') {
      statusLabel = progress?.duplicate == true ? '↩︎ ${l10n.wifiStatusDuplicate}' : '✅ ${l10n.wifiStatusDone}';
      statusColor = progress?.duplicate == true ? context.colors.textSecondary : context.colors.success;
    } else if (status == 'failed') {
      statusLabel = '❌ ${l10n.wifiStatusFailed(progress?.error ?? l10n.wifiUnknownError)}';
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
          Text(
            statusLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600),
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
