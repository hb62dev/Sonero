import 'dart:io';
import 'package:path/path.dart' as p;

/// Manages local lyric files stored in `<musicFolder>/lyrics/`.
///
/// Naming convention: the lyric file shares the stem of the audio file.
///   my_song.mp3  →  lyrics/my_song.lrc   (synced)
///                   lyrics/my_song.txt   (plain fallback)
class LyricsService {
  // ── Paths ─────────────────────────────────────────────────────────────────

  static String lyricsDir(String musicFolder) =>
      p.join(musicFolder, 'lyrics');

  static String lrcPath(String musicFolder, String audioFilename) {
    final stem = p.basenameWithoutExtension(audioFilename);
    return p.join(lyricsDir(musicFolder), '$stem.lrc');
  }

  static String txtPath(String musicFolder, String audioFilename) {
    final stem = p.basenameWithoutExtension(audioFilename);
    return p.join(lyricsDir(musicFolder), '$stem.txt');
  }

  // ── Read ──────────────────────────────────────────────────────────────────

  /// Returns the content of the local `.lrc` file, or null if it doesn't exist.
  static String? readLrc(String musicFolder, String audioFilename) {
    if (musicFolder.isEmpty) return null;
    // 1. Try inside lyrics/ folder
    final fileInLyrics = File(lrcPath(musicFolder, audioFilename));
    if (fileInLyrics.existsSync()) return fileInLyrics.readAsStringSync();
    
    // 2. Try next to the audio file
    final stem = p.basenameWithoutExtension(audioFilename);
    final fileNextToAudio = File(p.join(p.dirname(p.join(musicFolder, audioFilename)), '$stem.lrc'));
    if (fileNextToAudio.existsSync()) return fileNextToAudio.readAsStringSync();
    
    return null;
  }

  /// Returns the content of the local `.txt` file, or null if it doesn't exist.
  static String? readTxt(String musicFolder, String audioFilename) {
    if (musicFolder.isEmpty) return null;
    // 1. Try inside lyrics/ folder
    final fileInLyrics = File(txtPath(musicFolder, audioFilename));
    if (fileInLyrics.existsSync()) return fileInLyrics.readAsStringSync();
    
    // 2. Try next to the audio file
    final stem = p.basenameWithoutExtension(audioFilename);
    final fileNextToAudio = File(p.join(p.dirname(p.join(musicFolder, audioFilename)), '$stem.txt'));
    if (fileNextToAudio.existsSync()) return fileNextToAudio.readAsStringSync();
    
    return null;
  }

  /// Returns true if any local lyric file exists for this track.
  static bool hasLocal(String musicFolder, String audioFilename) {
    if (musicFolder.isEmpty) return false;
    final fileInLyricsLrc = File(lrcPath(musicFolder, audioFilename));
    final fileInLyricsTxt = File(txtPath(musicFolder, audioFilename));
    if (fileInLyricsLrc.existsSync() || fileInLyricsTxt.existsSync()) return true;

    final stem = p.basenameWithoutExtension(audioFilename);
    final dir = p.dirname(p.join(musicFolder, audioFilename));
    return File(p.join(dir, '$stem.lrc')).existsSync() ||
        File(p.join(dir, '$stem.txt')).existsSync();
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  /// Saves [content] as a `.lrc` file (creates the `lyrics/` folder if needed).
  static Future<void> saveLrc(
      String musicFolder, String audioFilename, String content) async {
    if (musicFolder.isEmpty) return;
    final dir = Directory(lyricsDir(musicFolder));
    if (!dir.existsSync()) await dir.create(recursive: true);
    await File(lrcPath(musicFolder, audioFilename)).writeAsString(content);
  }

  /// Saves [content] as a plain `.txt` file.
  static Future<void> saveTxt(
      String musicFolder, String audioFilename, String content) async {
    if (musicFolder.isEmpty) return;
    final dir = Directory(lyricsDir(musicFolder));
    if (!dir.existsSync()) await dir.create(recursive: true);
    await File(txtPath(musicFolder, audioFilename)).writeAsString(content);
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  /// Deletes both the .lrc and .txt files for a track (if they exist).
  static void deleteLocal(String musicFolder, String audioFilename) {
    if (musicFolder.isEmpty) return;
    final lrc = File(lrcPath(musicFolder, audioFilename));
    final txt = File(txtPath(musicFolder, audioFilename));
    if (lrc.existsSync()) lrc.deleteSync();
    if (txt.existsSync()) txt.deleteSync();
  }
}
