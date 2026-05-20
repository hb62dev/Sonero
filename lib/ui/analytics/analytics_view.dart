import 'package:flutter/material.dart';
import '../theme.dart';

class AnalyticsView extends StatelessWidget {
  const AnalyticsView({super.key});

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    return Scaffold(
      backgroundColor: context.colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Analíticas de Consumo', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isMobile ? 16.0 : 24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tus Hábitos',
              style: TextStyle(
                fontSize: isMobile ? 20 : 24,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),

            // ── Stat cards: Row en desktop, Grid 2-col en mobile ──────────
            isMobile
                ? _buildMobileStatsGrid(context)
                : _buildDesktopStatsRow(context),

            const SizedBox(height: 32),
            Text(
              'Historial Reciente (Benrio)',
              style: TextStyle(
                fontSize: isMobile ? 16 : 20,
                fontWeight: FontWeight.bold,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.analytics_outlined, size: 64, color: context.colors.textSecondary),
                    const SizedBox(height: 16),
                    Text(
                      'Aquí se integrarán los datos desde el backend cuando se implemente la conexión con Benrio.',
                      style: TextStyle(color: context.colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Mobile: grid de 2 columnas (2 arriba + 1 centrada abajo) ─────────────
  Widget _buildMobileStatsGrid(BuildContext context) {
    final stats = [
      _StatData('Horas de reproducción', '12.5 h', Icons.timer),
      _StatData('Videos Completados',    '34',     Icons.check_circle_outline),
      _StatData('Música Escuchada',      '128',    Icons.music_note),
    ];

    return Column(
      children: [
        // Fila 1: 2 tarjetas
        Row(
          children: [
            Expanded(child: _buildStatCard(context, stats[0], mobile: true)),
            const SizedBox(width: 12),
            Expanded(child: _buildStatCard(context, stats[1], mobile: true)),
          ],
        ),
        const SizedBox(height: 12),
        // Fila 2: 1 tarjeta centrada (ancho 50%)
        Row(
          children: [
            Expanded(child: _buildStatCard(context, stats[2], mobile: true)),
            const SizedBox(width: 12),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }

  // ── Desktop: row original de 3 tarjetas ───────────────────────────────────
  Widget _buildDesktopStatsRow(BuildContext context) {
    final stats = [
      _StatData('Horas de reproducción', '12.5 h', Icons.timer),
      _StatData('Videos Completados',    '34',     Icons.check_circle_outline),
      _StatData('Música Escuchada',      '128',    Icons.music_note),
    ];

    return Row(
      children: [
        Expanded(child: _buildStatCard(context, stats[0])),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(context, stats[1])),
        const SizedBox(width: 16),
        Expanded(child: _buildStatCard(context, stats[2])),
      ],
    );
  }

  Widget _buildStatCard(BuildContext context, _StatData data, {bool mobile = false}) {
    return Container(
      padding: EdgeInsets.all(mobile ? 14 : 20),
      decoration: BoxDecoration(
        color: context.colors.surfaceAlt,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(data.icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 10),
          Text(
            data.value,
            style: TextStyle(
              fontSize: mobile ? 22 : 28,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.title,
            style: TextStyle(
              fontSize: mobile ? 12 : 14,
              color: context.colors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatData {
  final String title;
  final String value;
  final IconData icon;
  const _StatData(this.title, this.value, this.icon);
}
