import 'dart:io';
import 'package:path/path.dart' as p;
import '../models/track.dart';

class CsvService {
  /// Exports all tracks in a playlist folder to a CSV file.
  /// Returns the path of the generated CSV file.
  static Future<String> exportPlaylistCsv({
    required String playlistName,
    required List<Track> tracks,
    required String outputDir,
  }) async {
    final safe = playlistName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final csvPath = p.join(outputDir, '$safe.csv');
    final file = File(csvPath);

    final lines = <String>['Title,Artist,Album,Genre,Year,Filename,Downloaded,Size(MB)'];
    for (final t in tracks) {
      lines.add([
        _esc(t.title),
        _esc(t.artist),
        _esc(t.album),
        _esc(t.genre),
        _esc(t.year),
        _esc(t.filename),
        _esc(t.downloaded),
        t.sizeMb.toStringAsFixed(2),
      ].join(','));
    }

    await file.writeAsString(lines.join('\n'), encoding: systemEncoding);
    return csvPath;
  }

  /// Escapes a CSV field value (wraps in quotes if it contains commas or quotes).
  static String _esc(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
