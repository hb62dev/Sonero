import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/downloads_provider.dart';
import '../theme.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final downloads = context.watch<DownloadsProvider>();
    
    return Container(
      color: context.colors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          Divider(height: 1, color: context.colors.border),
          Expanded(
            child: downloads.jobs.isEmpty
                ? _buildEmptyState(context)
                : _buildList(context, downloads),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: [
          Icon(Icons.download_rounded, color: context.colors.textPrimary, size: 28),
          const SizedBox(width: 16),
          Text(
            'Gestor de Descargas',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: context.colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_done, size: 64, color: context.colors.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 24),
          Text(
            'No hay descargas',
            style: TextStyle(
              fontSize: 18,
              color: context.colors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, DownloadsProvider downloads) {
    return ListView.separated(
      padding: const EdgeInsets.all(32),
      itemCount: downloads.jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (context, index) {
        final job = downloads.jobs[index];
        return _JobCard(
          job: job,
          onPause: () => downloads.pauseJob(job['job_id']),
          onResume: () => downloads.resumeJob(job['job_id']),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  final Map<String, dynamic> job;
  final VoidCallback onPause;
  final VoidCallback onResume;

  const _JobCard({
    required this.job,
    required this.onPause,
    required this.onResume,
  });

  @override
  Widget build(BuildContext context) {
    final status = job['status'] as String?;
    final step = job['step'] as String? ?? '';
    final progress = (job['progress'] as num?)?.toDouble() ?? 0.0;
    final error = job['error'] as String?;
    
    final track = job['track'] as Map<String, dynamic>?;
    final title = track?['title'] ?? 'Descarga #${job['job_id']}';

    IconData icon;
    Color iconColor;

    if (status == 'done') {
      icon = Icons.check_circle_rounded;
      iconColor = Colors.green;
    } else if (status == 'failed') {
      icon = Icons.error_rounded;
      iconColor = Colors.red;
    } else if (status == 'paused') {
      icon = Icons.pause_circle_filled_rounded;
      iconColor = Colors.orange;
    } else {
      icon = Icons.downloading_rounded;
      iconColor = Theme.of(context).colorScheme.primary;
    }

    final isRunning = status == 'pending' || status == 'downloading';
    final isPaused = status == 'paused';

    return Container(
      padding: const EdgeInsets.all(20),
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
              Icon(icon, color: iconColor, size: 28),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isRunning)
                IconButton(
                  icon: const Icon(Icons.pause_rounded),
                  color: context.colors.textSecondary,
                  tooltip: 'Pausar',
                  onPressed: onPause,
                ),
              if (isPaused)
                IconButton(
                  icon: const Icon(Icons.play_arrow_rounded),
                  color: Theme.of(context).colorScheme.primary,
                  tooltip: 'Reanudar',
                  onPressed: onResume,
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (isRunning || isPaused) ...[
            LinearProgressIndicator(
              value: progress > 0 ? progress / 100 : null,
              backgroundColor: context.colors.border,
              valueColor: AlwaysStoppedAnimation<Color>(
                isPaused ? Colors.orange : Theme.of(context).colorScheme.primary
              ),
              borderRadius: BorderRadius.circular(4),
              minHeight: 6,
            ),
            const SizedBox(height: 12),
          ],
          Text(
            error ?? step,
            style: TextStyle(
              fontSize: 14,
              color: status == 'failed' ? Colors.red : context.colors.textSecondary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
