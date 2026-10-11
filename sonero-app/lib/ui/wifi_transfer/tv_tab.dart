import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sonero_app/l10n/app_localizations.dart';
import '../../services/tv_backend.dart';
import '../theme.dart';

/// Compartir → TV: turn on Sonero TV, show the pairing PIN and manage paired TVs.
class TvTab extends StatefulWidget {
  final String apiUrl;
  const TvTab({super.key, required this.apiUrl});

  @override
  State<TvTab> createState() => _TvTabState();
}

class _TvTabState extends State<TvTab> {
  late final TvBackend _backend = TvBackend(widget.apiUrl);
  TvStatus? _status;
  Timer? _poll;
  bool _busy = false;
  /// Volume being dragged per TV, so the slider follows the finger between polls
  final Map<String, double> _dragVolume = {};

  @override
  void initState() {
    super.initState();
    _refresh();
    // Fast enough for the PIN countdown and to notice when a TV pairs
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await _backend.status();
      if (mounted) setState(() => _status = s);
    } catch (_) {}
  }

  Future<void> _run(Future<TvStatus> Function() action) async {
    setState(() => _busy = true);
    try {
      final s = await action();
      if (mounted) setState(() => _status = s);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.tvError(e.toString().replaceFirst('Exception: ', ''))),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDate(String iso) {
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return iso;
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final s = _status;
    final primary = Theme.of(context).colorScheme.primary;
    if (s == null) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── On/off ─────────────────────────────────────────────────────────
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
                  children: [
                    Icon(Icons.tv_rounded, color: primary, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.tvEnable, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          Text(
                            s.running && s.ip != null ? l10n.tvActiveOn('${s.ip}') : l10n.tvOff,
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: s.enabled && s.running,
                      onChanged: _busy ? null : (v) => _run(() => _backend.setEnabled(v)),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(l10n.tvIntro, style: TextStyle(color: context.colors.textSecondary, fontSize: 12, height: 1.4)),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Pairing ────────────────────────────────────────────────────────
          if (s.running) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: context.colors.surfaceAlt,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: s.pin != null ? primary : context.colors.border),
              ),
              child: s.pin == null
                  ? Column(
                      children: [
                        Text(l10n.tvGetApp,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 12, height: 1.4)),
                        const SizedBox(height: 14),
                        ElevatedButton.icon(
                          onPressed: _busy ? null : () => _run(_backend.startPairing),
                          icon: const Icon(Icons.link_rounded, size: 18),
                          label: Text(l10n.tvPairButton),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        Text(l10n.tvPinTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 12),
                        SelectableText(
                          '${s.pin!.substring(0, 3)} ${s.pin!.substring(3)}',
                          style: TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 6,
                            color: primary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(l10n.tvPinExpires(s.pinExpiresIn),
                            style: TextStyle(color: context.colors.textSecondary, fontSize: 12)),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: _busy ? null : () => _run(_backend.cancelPairing),
                          child: Text(l10n.tvCancel),
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            if (s.ip != null) _remoteCard(context, 'http://${s.ip}:${s.port}'),
            const SizedBox(height: 20),
          ],

          // ── Paired devices ─────────────────────────────────────────────────
          Text(l10n.tvDevices, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 8),
          if (s.devices.isEmpty)
            Text(l10n.tvNoDevices, style: TextStyle(color: context.colors.textSecondary, fontSize: 12))
          else
            for (final d in s.devices) _deviceTile(context, d),
        ],
      ),
    );
  }

  Widget _remoteCard(BuildContext context, String url) {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.phone_iphone_rounded, color: context.colors.textSecondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tvRemoteTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 2),
                Text(l10n.tvRemoteHint, style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                const SizedBox(height: 4),
                SelectableText(url, style: TextStyle(color: primary, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: l10n.wifiCopy,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.wifiCopied)));
            },
          ),
        ],
      ),
    );
  }

  Future<void> _command(String deviceId, String action, {double? value, bool? shuffle}) async {
    try {
      await _backend.command(deviceId, action, value: value, shuffle: shuffle);
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(AppLocalizations.of(context)!.tvError(e.toString().replaceFirst('Exception: ', ''))),
      ));
    }
  }

  Widget _deviceTile(BuildContext context, TvDevice d) {
    final l10n = AppLocalizations.of(context)!;
    final primary = Theme.of(context).colorScheme.primary;
    final np = d.nowPlaying;
    final controllable = d.isTv && d.online;
    String fmt(double secs) {
      final t = secs.round();
      return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: controllable ? primary.withValues(alpha: 0.5) : context.colors.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(d.isTv ? Icons.tv_rounded : Icons.phone_iphone_rounded,
                  color: controllable ? primary : context.colors.textSecondary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(d.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
                        ),
                        if (!d.isTv) ...[
                          const SizedBox(width: 6),
                          Text('· ${l10n.tvKindRemote}',
                              style: TextStyle(color: context.colors.textSecondary, fontSize: 11)),
                        ],
                        if (d.online) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.circle, size: 8, color: context.colors.success),
                          const SizedBox(width: 4),
                          Text(l10n.tvOnline, style: TextStyle(color: context.colors.success, fontSize: 11)),
                        ],
                      ],
                    ),
                    Text(
                      d.lastSeen != null ? l10n.tvLastSeen(_formatDate(d.lastSeen!)) : l10n.tvNeverSeen,
                      style: TextStyle(color: context.colors.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(() => _backend.revoke(d.id)),
                style: TextButton.styleFrom(foregroundColor: context.colors.error),
                child: Text(l10n.tvRevoke),
              ),
            ],
          ),
          if (controllable) ...[
            const SizedBox(height: 8),
            Text(
              np == null || np.title.isEmpty
                  ? l10n.tvNothingPlaying
                  : (np.artist.isEmpty ? np.title : '${np.title} · ${np.artist}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            if (np != null && np.duration > 0) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (np.position / np.duration).clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: context.colors.border,
                ),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(fmt(np.position), style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
                  Text(fmt(np.duration), style: TextStyle(fontSize: 10, color: context.colors.textSecondary)),
                ],
              ),
            ],
            Row(
              children: [
                IconButton(
                  icon: Icon(Icons.shuffle_rounded, color: np?.shuffle == true ? primary : null),
                  onPressed: () => _command(d.id, 'shuffle', shuffle: !(np?.shuffle ?? false)),
                ),
                IconButton(icon: const Icon(Icons.skip_previous_rounded), onPressed: () => _command(d.id, 'previous')),
                IconButton.filled(
                  icon: Icon(np?.playing == true ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  onPressed: () => _command(d.id, 'toggle'),
                ),
                IconButton(icon: const Icon(Icons.skip_next_rounded), onPressed: () => _command(d.id, 'next')),
                const SizedBox(width: 8),
                Icon(Icons.volume_down_rounded, size: 18, color: context.colors.textSecondary),
                Expanded(
                  child: Slider(
                    value: (_dragVolume[d.id] ?? np?.volume ?? 1).clamp(0.0, 1.0),
                    onChanged: (v) => setState(() => _dragVolume[d.id] = v),
                    onChangeEnd: (v) async {
                      await _command(d.id, 'volume', value: v);
                      if (mounted) setState(() => _dragVolume.remove(d.id));
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
