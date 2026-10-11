import 'package:flutter/material.dart';
import 'package:sonero_app/l10n/app_localizations.dart';
import '../../services/tv_backend.dart';
import '../theme.dart';

/// "Reproducir en TV": lets the user pick a connected Sonero TV and sends it
/// [filenames] (library filenames) starting at [index], optionally at
/// [position] seconds. Returns true if the TV accepted the queue.
Future<bool> showCastToTvDialog(
  BuildContext context, {
  required String apiUrl,
  required List<String> filenames,
  int index = 0,
  double? position,
}) async {
  final backend = TvBackend(apiUrl);
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);

  List<TvDevice> tvs;
  try {
    tvs = (await backend.status()).devices.where((d) => d.isTv && d.online).toList();
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.tvError(e.toString().replaceFirst('Exception: ', '')))));
    return false;
  }
  if (!context.mounted) return false;

  if (tvs.isEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.castNoTvs), duration: const Duration(seconds: 5)));
    return false;
  }

  final tv = tvs.length == 1
      ? tvs.first
      : await showDialog<TvDevice>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: Text(l10n.castPickTv),
            children: [
              for (final d in tvs)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, d),
                  child: Row(
                    children: [
                      Icon(Icons.tv_rounded, color: Theme.of(ctx).colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text(
                              d.nowPlaying?.title.isNotEmpty == true ? d.nowPlaying!.title : l10n.tvNothingPlaying,
                              style: TextStyle(fontSize: 12, color: ctx.colors.textSecondary),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
  if (tv == null) return false;

  try {
    await backend.command(tv.id, 'play', filenames: filenames, index: index, position: position);
    messenger.showSnackBar(SnackBar(content: Text(l10n.castSent(tv.name))));
    return true;
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.tvError(e.toString().replaceFirst('Exception: ', '')))));
    return false;
  }
}
