import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/equalizer_provider.dart';
import '../theme.dart';

/// Full-featured equalizer panel.
/// Can be shown in a dialog, bottom-sheet, or inline.
class EqualizerView extends StatelessWidget {
  const EqualizerView({super.key});

  @override
  Widget build(BuildContext context) {
    final eq = context.watch<EqualizerProvider>();
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border.withOpacity(0.2)),
      ),
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 20),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            _Header(enabled: eq.enabled, onToggle: eq.toggle, onReset: eq.reset),
            if (eq.enabled) ...[
              const SizedBox(height: 12),

              // ── Preset chips ────────────────────────────────────────────
              _PresetSelector(selected: eq.preset, onSelected: eq.setPreset),
              const SizedBox(height: 12),

              // ── EQ Bands ────────────────────────────────────────────────
              SizedBox(
                height: isMobile ? 180 : 160,
                child: _BandSliders(bands: eq.bands, accent: accent, onChanged: eq.setBand),
              ),
              const SizedBox(height: 12),

              // ── Bottom sections ─────────────────────────────────────────
              if (isMobile) ...[
                // Mobile: stacked
                _SectionCard(
                  colors: colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ToggleRow(icon: Icons.speaker_rounded, label: 'Bass Boost', value: eq.bassBoostEnabled, onChanged: eq.setBassBoostEnabled, colors: colors, accent: accent),
                      if (eq.bassBoostEnabled) ...[
                        const SizedBox(height: 8),
                        _LabeledSlider(label: '${eq.bassBoostGain.toStringAsFixed(0)} dB', value: eq.bassBoostGain, min: 0, max: 30, accent: accent, colors: colors, onChanged: eq.setBassBoostGain),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _SectionCard(
                  colors: colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.headphones_rounded, size: 18, color: colors.textSecondary),
                        const SizedBox(width: 8),
                        Text('Canal', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                      ]),
                      const SizedBox(height: 10),
                      _ChannelModeSelector(mode: eq.channelMode, onChanged: eq.setChannelMode, accent: accent, colors: colors),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _SectionCard(
                  colors: colors,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _ToggleRow(icon: Icons.volume_up_rounded, label: 'Potenciador de Audio', subtitle: 'Normalización EBU R128', value: eq.loudnessEnabled, onChanged: eq.setLoudnessEnabled, colors: colors, accent: accent),
                      const SizedBox(height: 12),
                      _buildBalanceRow(eq, colors, accent),
                    ],
                  ),
                ),
              ] else ...[
                // Desktop: side by side
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Bass Boost
                      Expanded(
                        child: _SectionCard(
                          colors: colors,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ToggleRow(icon: Icons.speaker_rounded, label: 'Bass Boost', value: eq.bassBoostEnabled, onChanged: eq.setBassBoostEnabled, colors: colors, accent: accent),
                              if (eq.bassBoostEnabled) ...[
                                const SizedBox(height: 6),
                                _LabeledSlider(label: '${eq.bassBoostGain.toStringAsFixed(0)} dB', value: eq.bassBoostGain, min: 0, max: 30, accent: accent, colors: colors, onChanged: eq.setBassBoostGain),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Channel
                      Expanded(
                        child: _SectionCard(
                          colors: colors,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.headphones_rounded, size: 18, color: colors.textSecondary),
                                const SizedBox(width: 8),
                                Text('Canal', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                              ]),
                              const SizedBox(height: 8),
                              _ChannelModeSelector(mode: eq.channelMode, onChanged: eq.setChannelMode, accent: accent, colors: colors),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Loudness & Balance
                      Expanded(
                        child: _SectionCard(
                          colors: colors,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _ToggleRow(icon: Icons.volume_up_rounded, label: 'Audio', subtitle: 'EBU R128', value: eq.loudnessEnabled, onChanged: eq.setLoudnessEnabled, colors: colors, accent: accent),
                              const SizedBox(height: 8),
                              _buildBalanceRow(eq, colors, accent),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
        ),
      ),
    );
  }

  Widget _buildBalanceRow(EqualizerProvider eq, SoneroColors colors, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.tune_rounded, size: 16, color: colors.textSecondary),
            const SizedBox(width: 6),
            Text('Balance', style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
            const Spacer(),
            Text(
              eq.balance == 0 ? 'Centro' : eq.balance < 0 ? 'L ${(-eq.balance * 100).toStringAsFixed(0)}%' : 'R ${(eq.balance * 100).toStringAsFixed(0)}%',
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text('L', style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
            Expanded(
              child: SliderTheme(
                data: _sliderTheme(accent, colors),
                child: Slider(value: eq.balance, min: -1.0, max: 1.0, onChanged: eq.setBalance),
              ),
            ),
            Text('R', style: TextStyle(color: colors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Private widgets
// ═══════════════════════════════════════════════════════════════════════════════

class _Header extends StatelessWidget {
  final bool enabled;
  final VoidCallback onToggle;
  final VoidCallback onReset;

  const _Header({required this.enabled, required this.onToggle, required this.onReset});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Icon(Icons.equalizer_rounded, color: enabled ? accent : colors.textSecondary, size: 24),
        const SizedBox(width: 10),
        Text(
          'Ecualizador',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const Spacer(),
        if (enabled)
          IconButton(
            icon: Icon(Icons.restart_alt_rounded, size: 20, color: colors.textSecondary),
            tooltip: 'Restablecer',
            onPressed: onReset,
            style: IconButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        const SizedBox(width: 4),
        Switch(
          value: enabled,
          onChanged: (_) => onToggle(),
          activeColor: accent,
        ),
      ],
    );
  }
}

class _PresetSelector extends StatelessWidget {
  final EqPreset selected;
  final ValueChanged<EqPreset> onSelected;

  const _PresetSelector({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final accent = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: EqPreset.values.length - 1, // skip 'custom'
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (ctx, i) {
          final preset = EqPreset.values[i];
          final isActive = preset == selected;
          return GestureDetector(
            onTap: () => onSelected(preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isActive ? accent : colors.surfaceAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isActive ? accent : colors.border.withOpacity(0.3),
                ),
              ),
              child: Text(
                preset.label,
                style: TextStyle(
                  color: isActive ? Colors.white : colors.textSecondary,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  fontSize: 13,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _BandSliders extends StatelessWidget {
  final List<double> bands;
  final Color accent;
  final void Function(int, double) onChanged;

  const _BandSliders({required this.bands, required this.accent, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border.withOpacity(0.15)),
      ),
      child: Column(
        children: [
          // dB labels
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('+12', style: TextStyle(fontSize: 9, color: colors.textSecondary)),
                Text('0 dB', style: TextStyle(fontSize: 9, color: colors.textSecondary, fontWeight: FontWeight.w600)),
                Text('-12', style: TextStyle(fontSize: 9, color: colors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // Sliders
          SizedBox(
            height: 160,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(10, (i) {
                return Expanded(
                  child: Column(
                    children: [
                      Expanded(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                              activeTrackColor: accent,
                              inactiveTrackColor: colors.border.withOpacity(0.3),
                              thumbColor: accent,
                              overlayColor: accent.withOpacity(0.15),
                            ),
                            child: Slider(
                              value: bands[i],
                              min: -12.0,
                              max: 12.0,
                              onChanged: (v) => onChanged(i, v),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        kEqBandLabels[i],
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelModeSelector extends StatelessWidget {
  final ChannelMode mode;
  final ValueChanged<ChannelMode> onChanged;
  final Color accent;
  final SoneroColors colors;

  const _ChannelModeSelector({
    required this.mode,
    required this.onChanged,
    required this.accent,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: ChannelMode.values.map((m) {
        final isActive = m == mode;
        final label = switch (m) {
          ChannelMode.mono        => 'Mono',
          ChannelMode.stereo      => 'Estéreo',
          ChannelMode.extraStereo => 'Extra Estéreo',
        };
        final icon = switch (m) {
          ChannelMode.mono        => Icons.looks_one_rounded,
          ChannelMode.stereo      => Icons.looks_two_rounded,
          ChannelMode.extraStereo => Icons.surround_sound_rounded,
        };
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isActive ? accent.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isActive ? accent : colors.border.withOpacity(0.25),
                ),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 18, color: isActive ? accent : colors.textSecondary),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? accent : colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final SoneroColors colors;
  final Widget child;

  const _SectionCard({required this.colors, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceAlt,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border.withOpacity(0.15)),
      ),
      child: child,
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final SoneroColors colors;
  final Color accent;

  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    required this.colors,
    required this.accent,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: value ? accent : colors.textSecondary),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              )),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                )),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: accent,
        ),
      ],
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final Color accent;
  final SoneroColors colors;
  final ValueChanged<double> onChanged;

  const _LabeledSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.accent,
    required this.colors,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SliderTheme(
            data: _sliderTheme(accent, colors),
            child: Slider(value: value, min: min, max: max, onChanged: onChanged),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            label,
            textAlign: TextAlign.end,
            style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

SliderThemeData _sliderTheme(Color accent, SoneroColors colors) {
  return SliderThemeData(
    trackHeight: 3,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
    activeTrackColor: accent,
    inactiveTrackColor: colors.border.withOpacity(0.3),
    thumbColor: accent,
    overlayColor: accent.withOpacity(0.15),
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Helper to show EQ as dialog or bottom-sheet
// ═══════════════════════════════════════════════════════════════════════════════

void showEqualizerDialog(BuildContext context) {
  final isMobile = MediaQuery.of(context).size.width < 600;

  if (isMobile) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      enableDrag: true,
      useSafeArea: true,
      builder: (_) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: context.colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.colors.border.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Expanded(child: EqualizerView()),
          ],
        ),
      ),
    );
  } else {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Ecualizador',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 350),
      pageBuilder: (_, __, ___) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 30),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.7,
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: Material(
              color: Colors.transparent,
              child: const EqualizerView(),
            ),
          ),
        ),
      ),
      transitionBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.15),
            end: Offset.zero,
          ).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }
}
