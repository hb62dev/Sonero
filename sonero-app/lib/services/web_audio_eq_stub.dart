/// Non-web platforms: the Web Audio equalizer is a no-op here (native
/// players apply the EQ through their own pipeline).
class WebAudioEqualizer {
  static void init() {}
  static void setBands(List<double> gains) {}
  static void setBassBoost(double gainDb) {}
  static void setGain(double multiplier) {}
  static void setBalance(double balance) {}
  static void reset() {}
}
