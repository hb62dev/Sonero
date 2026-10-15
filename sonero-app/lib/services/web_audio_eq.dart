// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Web Audio API equalizer — intercepts the browser's <audio>/<video> element
/// and routes it through BiquadFilter nodes for real EQ in the browser.
class WebAudioEqualizer {
  static bool _initialized = false;

  /// Initialize the Web Audio API EQ chain on the first media element.
  static void init() {
    if (_initialized) return;
    _eval(r'''
      (function() {
        if (window.__soneroEQ) return;
        
        var media = document.querySelector('audio') || document.querySelector('video');
        if (!media) return;
        
        var ctx = new (window.AudioContext || window.webkitAudioContext)();
        var src = ctx.createMediaElementSource(media);
        
        var filters = [];
        var freqs = [32, 64, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];
        for (var i = 0; i < freqs.length; i++) {
          var f = ctx.createBiquadFilter();
          f.type = i === 0 ? 'lowshelf' : (i === freqs.length - 1 ? 'highshelf' : 'peaking');
          f.frequency.value = freqs[i];
          f.Q.value = 1.4;
          f.gain.value = 0;
          filters.push(f);
        }
        
        var bassBoost = ctx.createBiquadFilter();
        bassBoost.type = 'lowshelf';
        bassBoost.frequency.value = 80;
        bassBoost.gain.value = 0;
        
        var gainNode = ctx.createGain();
        gainNode.gain.value = 1.0;
        
        src.connect(filters[0]);
        for (var i = 0; i < filters.length - 1; i++) {
          filters[i].connect(filters[i + 1]);
        }
        filters[filters.length - 1].connect(bassBoost);
        bassBoost.connect(gainNode);
        gainNode.connect(ctx.destination);
        
        window.__soneroEQ = {
          ctx: ctx,
          filters: filters,
          bassBoost: bassBoost,
          gainNode: gainNode,
          source: src
        };
      })();
    ''');
    _initialized = true;
  }

  /// Apply 10-band EQ gains (dB)
  static void setBands(List<double> gains) {
    if (gains.length != 10) return;
    final gainsStr = gains.map((g) => g.toStringAsFixed(1)).join(',');
    _eval('''
      (function() {
        var eq = window.__soneroEQ;
        if (!eq) return;
        var gains = [$gainsStr];
        for (var i = 0; i < eq.filters.length && i < gains.length; i++) {
          eq.filters[i].gain.value = gains[i];
        }
      })();
    ''');
  }

  /// Set bass boost gain in dB
  static void setBassBoost(double gainDb) {
    _eval('''
      (function() {
        var eq = window.__soneroEQ;
        if (!eq) return;
        eq.bassBoost.gain.value = ${gainDb.toStringAsFixed(1)};
      })();
    ''');
  }

  /// Set overall gain (1.0 = normal, >1.0 = louder)
  static void setGain(double multiplier) {
    _eval('''
      (function() {
        var eq = window.__soneroEQ;
        if (!eq) return;
        eq.gainNode.gain.value = ${multiplier.toStringAsFixed(2)};
      })();
    ''');
  }

  /// Set balance (-1 left, 0 center, +1 right) 
  static void setBalance(double balance) {
    _eval('''
      (function() {
        var eq = window.__soneroEQ;
        if (!eq || !eq.ctx) return;
        if (!eq.panner) {
          eq.panner = eq.ctx.createStereoPanner();
          eq.gainNode.disconnect();
          eq.gainNode.connect(eq.panner);
          eq.panner.connect(eq.ctx.destination);
        }
        eq.panner.pan.value = ${balance.toStringAsFixed(2)};
      })();
    ''');
  }

  /// Reset all
  static void reset() {
    _eval('''
      (function() {
        var eq = window.__soneroEQ;
        if (!eq) return;
        for (var i = 0; i < eq.filters.length; i++) {
          eq.filters[i].gain.value = 0;
        }
        eq.bassBoost.gain.value = 0;
        eq.gainNode.gain.value = 1.0;
        if (eq.panner) eq.panner.pan.value = 0;
      })();
    ''');
  }

  static void _eval(String code) {
    try {
      globalContext.callMethod('eval'.toJS, code.toJS);
    } catch (_) {}
  }
}
