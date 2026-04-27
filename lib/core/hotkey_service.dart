import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages two configurable global hotkeys:
///   - hotkey_mic:    triggers listen with microphone
///   - hotkey_system: triggers listen with system audio
class HotkeyService {
  static const _keyMic = 'hotkey_mic';
  static const _keySystem = 'hotkey_system';

  HotKey? _micHotkey;
  HotKey? _systemHotkey;

  /// Default hotkeys
  static HotKey get defaultMicHotkey => HotKey(
        key: PhysicalKeyboardKey.keyM,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );

  static HotKey get defaultSystemHotkey => HotKey(
        key: PhysicalKeyboardKey.keyS,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );

  /// Loads saved hotkeys (or defaults) and registers them.
  Future<void> initialize({
    required VoidCallback onMicTriggered,
    required VoidCallback onSystemTriggered,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    _micHotkey = _loadHotkey(prefs, _keyMic) ?? defaultMicHotkey;
    _systemHotkey = _loadHotkey(prefs, _keySystem) ?? defaultSystemHotkey;

    await _register(_micHotkey!, onMicTriggered);
    await _register(_systemHotkey!, onSystemTriggered);
  }

  /// Re-registers a new hotkey for the mic action.
  Future<void> updateMicHotkey(HotKey hotkey, VoidCallback onTriggered) async {
    if (_micHotkey != null) await hotKeyManager.unregister(_micHotkey!);
    _micHotkey = hotkey;
    await _register(hotkey, onTriggered);
    await _save(_keyMic, hotkey);
  }

  /// Re-registers a new hotkey for the system audio action.
  Future<void> updateSystemHotkey(HotKey hotkey, VoidCallback onTriggered) async {
    if (_systemHotkey != null) await hotKeyManager.unregister(_systemHotkey!);
    _systemHotkey = hotkey;
    await _register(hotkey, onTriggered);
    await _save(_keySystem, hotkey);
  }

  Future<void> dispose() async {
    if (_micHotkey != null) await hotKeyManager.unregister(_micHotkey!);
    if (_systemHotkey != null) await hotKeyManager.unregister(_systemHotkey!);
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  HotKey? _loadHotkey(SharedPreferences prefs, String key) {
    final json = prefs.getString(key);
    if (json == null) return null;
    try {
      return HotKey.fromJson(Map<String, dynamic>.from(
        (json.startsWith('{') ? _parseJson(json) : null) ?? {},
      ));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save(String key, HotKey hotkey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, hotkey.toJson().toString());
  }

  Future<void> _register(HotKey hotkey, VoidCallback callback) async {
    await hotKeyManager.register(hotkey, keyDownHandler: (_) => callback());
  }

  Map<String, dynamic>? _parseJson(String src) {
    // Minimal JSON-like parse for HotKey serialized map
    try {
      return Map<String, dynamic>.from(
        (src.replaceAll(RegExp(r'^\{|\}$'), ''))
            .split(',')
            .map((e) => e.trim().split(':'))
            .fold<Map<String, dynamic>>({}, (m, parts) {
          if (parts.length == 2) {
            m[parts[0].trim().replaceAll('"', '')] =
                parts[1].trim().replaceAll('"', '');
          }
          return m;
        }),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  HotKey get currentMicHotkey => _micHotkey ?? defaultMicHotkey;
  HotKey get currentSystemHotkey => _systemHotkey ?? defaultSystemHotkey;

  /// Human-readable label for a hotkey, e.g. "Ctrl + Shift + M"
  static String label(HotKey hotkey) {
    final mods = (hotkey.modifiers ?? []).map((m) {
      switch (m) {
        case HotKeyModifier.control:
          return 'Ctrl';
        case HotKeyModifier.shift:
          return 'Shift';
        case HotKeyModifier.alt:
          return 'Alt';
        case HotKeyModifier.meta:
          return 'Win';
        default:
          return m.name;
      }
    }).join(' + ');

    final keyLabel = hotkey.key is PhysicalKeyboardKey
        ? (hotkey.key as PhysicalKeyboardKey).debugName ?? 'Key'
        : hotkey.key.toString();
    return mods.isEmpty ? keyLabel : '$mods + $keyLabel';
  }
}
