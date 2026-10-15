import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Android/desktop: saves the PNG to the Downloads folder when the platform
/// has one, otherwise to the app's documents folder. Returns the file path.
Future<String?> saveImageBytes(Uint8List bytes, String filename) async {
  Directory? dir;
  try {
    dir = await getDownloadsDirectory();
  } catch (_) {}
  dir ??= await getApplicationDocumentsDirectory();
  await dir.create(recursive: true);
  final file = File(p.join(dir.path, filename));
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
