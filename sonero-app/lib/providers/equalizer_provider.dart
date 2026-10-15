import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:media_kit/media_kit.dart';
import '../services/web_audio_eq_stub.dart'
    if (dart.library.js_interop) '../services/web_audio_eq.dart';

/// 10-band frequency labels (Hz).
const List<String> kEqBandLabels = [
  '32', '64', '125', '250', '500', '1k', '2k', '4k', '8k', '16k',
];

/// Channel output mode.
enum ChannelMode { stereo, mono, extraStereo }

/// Named EQ presets.
enum EqPreset {
  flat,
  rock,
  pop,
  jazz,
  classical,
  electronic,
  bassBoost,
  vocal,
  acoustic,
  rap,
  hiphop,
  drill,
  custom,
}

extension EqPresetLabel on EqPreset {
  String get label => switch (this) {
    EqPreset.flat        => 'Flat',
    EqPreset.rock        => 'Rock',
    EqPreset.pop         => 'Pop',
    EqPreset.jazz        => 'Jazz',
    EqPreset.classical   => 'Clásica',
    EqPreset.electronic  => 'Electrónica',
    EqPreset.bassBoost   => 'Bass Boost',
    EqPreset.vocal       => 'Vocal',
    EqPreset.acoustic    => 'Acústico',
    EqPreset.rap         => 'Rap',
    EqPreset.hiphop      => 'Hip Hop',
    EqPreset.drill       => 'Drill',
    EqPreset.custom      => 'Personalizado',
  };
}

/// Predefined band gain values (dB, range –12 … +12).
/// Tuned aggressively so the difference is immediately noticeable,
/// even on cheap earbuds.
const Map<EqPreset, List<double>> kPresetValues = {
  EqPreset.flat:       [ 0,  0,  0,  0,  0,  0,  0,  0,  0,  0],
  EqPreset.rock:       [ 8,  6,  4,  2, -2,  2,  5,  7,  9, 10],
  EqPreset.pop:        [-2,  2,  5,  7,  5,  1, -1,  0,  3,  5],
  EqPreset.jazz:       [ 6,  5,  2,  3, -2, -1,  1,  3,  6,  8],
  EqPreset.classical:  [ 8,  7,  5,  3, -2, -2,  1,  4,  6,  8],
  EqPreset.electronic: [10,  8,  3,  0, -3,  3,  2,  6,  9, 11],
  EqPreset.bassBoost:  [12, 10,  8,  5,  2,  0,  0,  0,  0,  0],
  EqPreset.vocal:      [-4, -3,  0,  4,  8,  8,  6,  2,  0, -2],
  EqPreset.acoustic:   [ 7,  5,  3,  1, -2,  1,  3,  5,  7,  6],
  // Rap: heavy bass, punchy mids, clear highs for vocals
  EqPreset.rap:        [10,  8,  5,  3,  1,  3,  5,  4,  6,  7],
  // Hip Hop: deep sub-bass, warm mids, crisp highs
  EqPreset.hiphop:     [11,  9,  7,  4,  0,  2,  3,  5,  7,  8],
  // Drill: aggressive sub-bass, dark tone, sharp hi-hats
  EqPreset.drill:      [12, 11,  8,  3, -2, -1,  2,  6, 10, 11],
};

class EqualizerProvider extends ChangeNotifier {
  // ── State ──────────────────────────────────────────────────────────────────
  bool _enabled = false;
  bool get enabled => _enabled;

  EqPreset _preset = EqPreset.flat;
  EqPreset get preset => _preset;

  /// 10 band gains in dB (–12 … +12).
  List<double> _bands = List.filled(10, 0.0);
  List<double> get bands => List.unmodifiable(_bands);

  // Bass boost
  bool _bassBoostEnabled = false;
  bool get bassBoostEnabled => _bassBoostEnabled;

  double _bassBoostGain = 12.0; // dB — starts punchy
  double get bassBoostGain => _bassBoostGain;

  // Channel mode
  ChannelMode _channelMode = ChannelMode.stereo;
  ChannelMode get channelMode => _channelMode;

  double _extraStereoMultiplier = 3.0;
  double get extraStereoMultiplier => _extraStereoMultiplier;

  // Loudness normalization
  bool _loudnessEnabled = false;
  bool get loudnessEnabled => _loudnessEnabled;

  // Balance L/R  (–1.0 = full left, 0 = centre, +1.0 = full right)
  double _balance = 0.0;
  double get balance => _balance;

  // Reference to the Player instance – set once from PlayerProvider.
  Player? _player;

  // ── Init ───────────────────────────────────────────────────────────────────

  EqualizerProvider() {
    _loadFromPrefs();
  }

  void setPlayer(Player player) {
    _player = player;
    // Apply current state immediately.
    _applyFilters();
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  void toggle() {
    _enabled = !_enabled;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setEnabled(bool value) {
    _enabled = value;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setPreset(EqPreset preset) {
    _preset = preset;
    if (preset != EqPreset.custom) {
      _bands = List<double>.from(kPresetValues[preset]!);
    }
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setBand(int index, double gainDb) {
    if (index < 0 || index >= 10) return;
    _bands[index] = gainDb.clamp(-12.0, 12.0);
    _preset = EqPreset.custom;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setBassBoostEnabled(bool value) {
    _bassBoostEnabled = value;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setBassBoostGain(double gain) {
    _bassBoostGain = gain.clamp(0.0, 30.0);
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setChannelMode(ChannelMode mode) {
    _channelMode = mode;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setExtraStereoMultiplier(double m) {
    _extraStereoMultiplier = m.clamp(1.0, 4.0);
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setLoudnessEnabled(bool value) {
    _loudnessEnabled = value;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void setBalance(double value) {
    _balance = value.clamp(-1.0, 1.0);
    _applyFilters();
    _persist();
    notifyListeners();
  }

  void reset() {
    _preset = EqPreset.flat;
    _bands = List.filled(10, 0.0);
    _bassBoostEnabled = false;
    _bassBoostGain = 12.0;
    _channelMode = ChannelMode.stereo;
    _extraStereoMultiplier = 3.0;
    _loudnessEnabled = false;
    _balance = 0.0;
    _applyFilters();
    _persist();
    notifyListeners();
  }

  // ── MPV filter builder ─────────────────────────────────────────────────────

  void _applyFilters() {
    // ── Web: use Web Audio API ──────────────────────────────────────────
    if (kIsWeb) {
      _applyWebFilters();
      return;
    }

    // ── Native: use MPV filters ────────────────────────────────────────
    if (_player == null) return;

    if (!_enabled) {
      _setProperty('af', '');
      return;
    }

    final filters = <String>[];

    // 1. Superequalizer (18-band, we use the first 10)
    final hasEq = _bands.any((g) => g != 0.0);
    if (hasEq) {
      final sb = StringBuffer('superequalizer=');
      const mapping = [1, 2, 3, 5, 7, 9, 11, 13, 15, 17];
      for (int i = 0; i < 10; i++) {
        if (i > 0) sb.write(':');
        sb.write('${mapping[i]}b=${_bands[i].toStringAsFixed(1)}');
      }
      filters.add(sb.toString());
    }

    // 2. Bass boost
    if (_bassBoostEnabled && _bassBoostGain > 0) {
      final midGain = (_bassBoostGain * 0.5).toStringAsFixed(1);
      filters.add('bass=g=${_bassBoostGain.toStringAsFixed(1)}:f=80:w=0.7');
      filters.add('bass=g=$midGain:f=150:w=0.5');
    }

    // 3. Channel mode
    switch (_channelMode) {
      case ChannelMode.mono:
        filters.add('pan=1c|c0=0.5*c0+0.5*c1');
        break;
      case ChannelMode.extraStereo:
        filters.add('extrastereo=m=${_extraStereoMultiplier.toStringAsFixed(1)}');
        break;
      case ChannelMode.stereo:
        break;
    }

    // 4. Balance
    if (_balance != 0.0) {
      final left  = (1.0 - _balance.clamp(0.0, 1.0));
      final right = (1.0 + _balance.clamp(-1.0, 0.0));
      filters.add('pan=2c|c0=${left.toStringAsFixed(2)}*c0|c1=${right.toStringAsFixed(2)}*c1');
    }

    // 5. Loudness
    if (_loudnessEnabled) {
      filters.add('loudnorm=I=-10:TP=-1:LRA=7');
      filters.add('acompressor=threshold=0.05:ratio=4:attack=5:release=100:makeup=6');
    }

    final chain = filters.join(',');
    debugPrint('[EQ] Setting af=$chain');
    _setProperty('af', chain);
  }

  /// Apply filters via Web Audio API for browser builds.
  void _applyWebFilters() {
    // Initialize Web Audio chain if not done yet
    WebAudioEqualizer.init();

    if (!_enabled) {
      WebAudioEqualizer.reset();
      return;
    }

    // 1. EQ bands
    WebAudioEqualizer.setBands(_bands);

    // 2. Bass boost
    if (_bassBoostEnabled && _bassBoostGain > 0) {
      WebAudioEqualizer.setBassBoost(_bassBoostGain);
    } else {
      WebAudioEqualizer.setBassBoost(0);
    }

    // 3. Balance
    if (_balance != 0.0) {
      WebAudioEqualizer.setBalance(_balance);
    }

    // 4. Loudness (boost gain)
    if (_loudnessEnabled) {
      WebAudioEqualizer.setGain(2.0); // +6dB boost
    } else {
      WebAudioEqualizer.setGain(1.0);
    }

    debugPrint('[EQ-Web] Filters applied: bands=${_bands}, bass=${_bassBoostEnabled ? _bassBoostGain : 0}, balance=$_balance, loud=$_loudnessEnabled');
  }

  void _setProperty(String name, String value) {
    if (_player == null) return;
    try {
      final platform = _player!.platform;
      (platform as dynamic).setProperty(name, value);
    } catch (e) {
      debugPrint('[EQ] Error setting property $name: $e');
    }
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      prefs.setBool('eq_enabled', _enabled);
      prefs.setInt('eq_preset', _preset.index);
      prefs.setStringList('eq_bands', _bands.map((b) => b.toString()).toList());
      prefs.setBool('eq_bass_enabled', _bassBoostEnabled);
      prefs.setDouble('eq_bass_gain', _bassBoostGain);
      prefs.setInt('eq_channel_mode', _channelMode.index);
      prefs.setDouble('eq_extra_stereo', _extraStereoMultiplier);
      prefs.setBool('eq_loudness', _loudnessEnabled);
      prefs.setDouble('eq_balance', _balance);
    } catch (e) {
      debugPrint('[EQ] Error persisting: $e');
    }
  }

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('eq_enabled') ?? false;
      final presetIdx = prefs.getInt('eq_preset') ?? 0;
      _preset = EqPreset.values[presetIdx.clamp(0, EqPreset.values.length - 1)];
      final savedBands = prefs.getStringList('eq_bands');
      if (savedBands != null && savedBands.length == 10) {
        _bands = savedBands.map((s) => double.tryParse(s) ?? 0.0).toList();
      } else if (_preset != EqPreset.custom && kPresetValues.containsKey(_preset)) {
        _bands = List<double>.from(kPresetValues[_preset]!);
      }
      _bassBoostEnabled = prefs.getBool('eq_bass_enabled') ?? false;
      _bassBoostGain = prefs.getDouble('eq_bass_gain') ?? 8.0;
      final channelIdx = prefs.getInt('eq_channel_mode') ?? 0;
      _channelMode = ChannelMode.values[channelIdx.clamp(0, ChannelMode.values.length - 1)];
      _extraStereoMultiplier = prefs.getDouble('eq_extra_stereo') ?? 2.5;
      _loudnessEnabled = prefs.getBool('eq_loudness') ?? false;
      _balance = prefs.getDouble('eq_balance') ?? 0.0;
      notifyListeners();
    } catch (e) {
      debugPrint('[EQ] Error loading prefs: $e');
    }
  }
}
