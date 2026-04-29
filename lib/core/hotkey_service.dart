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
  static const _keyVideo = 'hotkey_video';

  static const _keyHide = 'hotkey_hide';
  static const _keyShow = 'hotkey_show';

  HotKey? _micHotkey;
  HotKey? _systemHotkey;
  HotKey? _videoHotkey;
  HotKey? _hideHotkey;
  HotKey? _showHotkey;

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

  static HotKey get defaultVideoHotkey => HotKey(
        key: PhysicalKeyboardKey.keyV,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );

  static HotKey get defaultHideHotkey => HotKey(
        key: PhysicalKeyboardKey.keyH,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );

  static HotKey get defaultShowHotkey => HotKey(
        key: PhysicalKeyboardKey.keyU,
        modifiers: [HotKeyModifier.control, HotKeyModifier.shift],
        scope: HotKeyScope.system,
      );

  VoidCallback? _onMicTriggered;
  VoidCallback? _onSystemTriggered;
  VoidCallback? _onVideoTriggered;
  VoidCallback? _onHideTriggered;
  VoidCallback? _onShowTriggered;

  /// Loads saved hotkeys (or defaults) and registers them.
  Future<void> initialize({
    required VoidCallback onMicTriggered,
    required VoidCallback onSystemTriggered,
    required VoidCallback onVideoTriggered,
    required VoidCallback onHideTriggered,
    required VoidCallback onShowTriggered,
  }) async {
    _onMicTriggered = onMicTriggered;
    _onSystemTriggered = onSystemTriggered;
    _onVideoTriggered = onVideoTriggered;
    _onHideTriggered = onHideTriggered;
    _onShowTriggered = onShowTriggered;

    final prefs = await SharedPreferences.getInstance();

    _micHotkey = _loadHotkey(prefs, _keyMic) ?? defaultMicHotkey;
    _systemHotkey = _loadHotkey(prefs, _keySystem) ?? defaultSystemHotkey;
    _videoHotkey = _loadHotkey(prefs, _keyVideo) ?? defaultVideoHotkey;
    _hideHotkey = _loadHotkey(prefs, _keyHide) ?? defaultHideHotkey;
    _showHotkey = _loadHotkey(prefs, _keyShow) ?? defaultShowHotkey;

    await _register(_micHotkey!, _onMicTriggered!);
    await _register(_systemHotkey!, _onSystemTriggered!);
    await _register(_videoHotkey!, _onVideoTriggered!);
    await _register(_hideHotkey!, _onHideTriggered!);
    await _register(_showHotkey!, _onShowTriggered!);
  }

  /// Re-registers a new hotkey for the mic action.
  Future<void> updateMicHotkey(HotKey hotkey) async {
    if (_micHotkey != null) await hotKeyManager.unregister(_micHotkey!);
    _micHotkey = hotkey;
    if (_onMicTriggered != null) await _register(hotkey, _onMicTriggered!);
    await _save(_keyMic, hotkey);
  }

  /// Re-registers a new hotkey for the system audio action.
  Future<void> updateSystemHotkey(HotKey hotkey) async {
    if (_systemHotkey != null) await hotKeyManager.unregister(_systemHotkey!);
    _systemHotkey = hotkey;
    if (_onSystemTriggered != null) await _register(hotkey, _onSystemTriggered!);
    await _save(_keySystem, hotkey);
  }

  Future<void> updateVideoHotkey(HotKey hotkey) async {
    if (_videoHotkey != null) await hotKeyManager.unregister(_videoHotkey!);
    _videoHotkey = hotkey;
    if (_onVideoTriggered != null) await _register(hotkey, _onVideoTriggered!);
    await _save(_keyVideo, hotkey);
  }

  Future<void> updateHideHotkey(HotKey hotkey) async {
    if (_hideHotkey != null) await hotKeyManager.unregister(_hideHotkey!);
    _hideHotkey = hotkey;
    if (_onHideTriggered != null) await _register(hotkey, _onHideTriggered!);
    await _save(_keyHide, hotkey);
  }

  Future<void> updateShowHotkey(HotKey hotkey) async {
    if (_showHotkey != null) await hotKeyManager.unregister(_showHotkey!);
    _showHotkey = hotkey;
    if (_onShowTriggered != null) await _register(hotkey, _onShowTriggered!);
    await _save(_keyShow, hotkey);
  }

  Future<void> dispose() async {
    if (_micHotkey != null) await hotKeyManager.unregister(_micHotkey!);
    if (_systemHotkey != null) await hotKeyManager.unregister(_systemHotkey!);
    if (_videoHotkey != null) await hotKeyManager.unregister(_videoHotkey!);
    if (_hideHotkey != null) await hotKeyManager.unregister(_hideHotkey!);
    if (_showHotkey != null) await hotKeyManager.unregister(_showHotkey!);
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
  HotKey get currentVideoHotkey => _videoHotkey ?? defaultVideoHotkey;
  HotKey get currentHideHotkey => _hideHotkey ?? defaultHideHotkey;
  HotKey get currentShowHotkey => _showHotkey ?? defaultShowHotkey;

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
