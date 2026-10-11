import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'ui.dart';

/// Finds a Sonero computer on the WiFi and pairs with it using the PIN shown
/// in Sonero (Compartir → TV).
class ConnectScreen extends StatefulWidget {
  final ValueChanged<SoneroApi> onConnected;
  final String? message;

  const ConnectScreen({super.key, required this.onConnected, this.message});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  List<SoneroServer>? _servers;
  bool _searching = false;
  bool _manual = false;
  String? _error;
  final _ipController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _error = widget.message;
    _search();
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final found = await discoverServers();
    if (!mounted) return;
    setState(() {
      _servers = found;
      _searching = false;
    });
  }

  Future<void> _connectManual() async {
    final host = _ipController.text.trim();
    if (host.isEmpty) return;
    setState(() => _error = null);
    try {
      final server = await SoneroApi.probe(host);
      if (mounted) _pair(server);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pair(SoneroServer server) async {
    final api = await Navigator.of(context).push<SoneroApi>(
      MaterialPageRoute(builder: (_) => PairScreen(server: server)),
    );
    if (api != null) widget.onConnected(api);
  }

  @override
  Widget build(BuildContext context) {
    final servers = _servers ?? const [];
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Left: instructions ──
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Image.asset('assets/logo.png', height: 48),
                  const SizedBox(height: 40),
                  const Text('Conecta tu TV a Sonero', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  const _Step(n: 1, text: 'En tu computadora, abre Sonero y entra en Compartir → TV.'),
                  const _Step(n: 2, text: 'Activa "Sonero TV" y pulsa "Emparejar TV" para ver el PIN.'),
                  const _Step(n: 3, text: 'Elige tu computadora en la lista y escribe el PIN.'),
                  const SizedBox(height: 24),
                  const Text(
                    'La TV y la computadora deben estar en la misma red WiFi. No hace falta internet.',
                    style: TextStyle(fontSize: 18, color: SoneroColors.muted, height: 1.4),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 24),
                    Text(_error!, style: const TextStyle(fontSize: 18, color: SoneroColors.error)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 64),
            // ── Right: servers ──
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Text('Computadoras con Sonero',
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: SoneroColors.muted)),
                      const SizedBox(width: 16),
                      if (_searching)
                        const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final (i, s) in servers.indexed)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: TvFocusable(
                              autofocus: i == 0,
                              onPressed: () => _pair(s),
                              builder: (context, focused) => _ServerTile(server: s, focused: focused),
                            ),
                          ),
                        if (!_searching && servers.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No encontré ninguna. Revisa que Sonero TV esté activado en tu computadora.',
                              style: TextStyle(fontSize: 18, color: SoneroColors.muted, height: 1.4),
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 16,
                          runSpacing: 16,
                          children: [
                            TvButton(
                              icon: Icons.refresh_rounded,
                              label: 'Buscar de nuevo',
                              autofocus: servers.isEmpty,
                              onPressed: _searching ? null : _search,
                            ),
                            TvButton(
                              icon: Icons.keyboard_rounded,
                              label: 'Escribir IP',
                              onPressed: () => setState(() => _manual = !_manual),
                            ),
                          ],
                        ),
                        if (_manual) ...[
                          const SizedBox(height: 20),
                          TextField(
                            controller: _ipController,
                            autofocus: true,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: const TextStyle(fontSize: 24),
                            onSubmitted: (_) => _connectManual(),
                            decoration: InputDecoration(
                              hintText: '192.168.1.50',
                              labelText: 'IP de la computadora',
                              filled: true,
                              fillColor: SoneroColors.surfaceAlt,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TvButton(icon: Icons.arrow_forward_rounded, label: 'Conectar', onPressed: _connectManual),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: SoneroColors.accent,
            child: Text('$n', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 22, height: 1.35))),
        ],
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final SoneroServer server;
  final bool focused;
  const _ServerTile({required this.server, required this.focused});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: focused ? SoneroColors.surfaceAlt : SoneroColors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.laptop_mac_rounded, size: 40, color: SoneroColors.accent),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(server.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600)),
                Text(server.host, style: const TextStyle(fontSize: 16, color: SoneroColors.muted)),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, size: 32, color: SoneroColors.muted),
        ],
      ),
    );
  }
}

/// 6-digit PIN entry with an on-screen keypad (typing on a TV keyboard is painful).
/// The remote's number keys work too.
class PairScreen extends StatefulWidget {
  final SoneroServer server;
  const PairScreen({super.key, required this.server});

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  void _type(String digit) {
    if (_busy || _pin.length >= 6) return;
    setState(() {
      _pin += digit;
      _error = null;
    });
    if (_pin.length == 6) _submit();
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final token = await SoneroApi(widget.server).pair(_pin, 'Android TV');
      await ConnectionStore.save(widget.server, token);
      if (mounted) Navigator.of(context).pop(SoneroApi(widget.server, token: token));
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _pin = '';
          _busy = false;
        });
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final label = event.logicalKey.keyLabel;
    final digit = RegExp(r'^(?:Numpad )?(\d)$').firstMatch(label)?.group(1);
    if (digit != null) {
      _type(digit);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.backspace || event.logicalKey == LogicalKeyboardKey.delete) {
      _backspace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onPressed, IconData? icon, bool autofocus = false}) => TvFocusable(
          autofocus: autofocus,
          onPressed: onPressed,
          radius: 16,
          focusScale: 1.08,
          builder: (context, focused) => Container(
            width: 96,
            height: 76,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: focused ? SoneroColors.accent : SoneroColors.surfaceAlt,
              borderRadius: BorderRadius.circular(16),
            ),
            child: icon != null
                ? Icon(icon, size: 32, color: Colors.white)
                : Text(label, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        );

    return Scaffold(
      body: Focus(
        onKeyEvent: _onKey,
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Escribe el PIN', style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Text(
                      'Aparece en Sonero, en "${widget.server.name}" → Compartir → TV.',
                      style: const TextStyle(fontSize: 20, color: SoneroColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 36),
                    Row(
                      children: [
                        for (var i = 0; i < 6; i++)
                          Container(
                            width: 64,
                            height: 80,
                            margin: const EdgeInsets.only(right: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: SoneroColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: i == _pin.length && !_busy ? SoneroColors.accent : SoneroColors.border,
                                width: 2,
                              ),
                            ),
                            child: Text(i < _pin.length ? _pin[i] : '',
                                style: const TextStyle(fontSize: 38, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 32,
                      child: _busy
                          ? const Text('Conectando…', style: TextStyle(fontSize: 20, color: SoneroColors.muted))
                          : _error != null
                              ? Text(_error!, style: const TextStyle(fontSize: 20, color: SoneroColors.error))
                              : null,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 72),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final d in row)
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 7),
                              child: key(d, onPressed: () => _type(d), autofocus: d == '1'),
                            ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: key('', icon: Icons.arrow_back_rounded, onPressed: () => Navigator.of(context).pop()),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: key('0', onPressed: () => _type('0')),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        child: key('', icon: Icons.backspace_rounded, onPressed: _backspace),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
