import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

/// Web: triggers a browser download of the PNG. Returns null (no file path).
Future<String?> saveImageBytes(Uint8List bytes, String filename) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: 'image/png'));
  final url = web.URL.createObjectURL(blob);
  (web.HTMLAnchorElement()
        ..href = url
        ..download = filename)
      .click();
  web.URL.revokeObjectURL(url);
  return null;
}
