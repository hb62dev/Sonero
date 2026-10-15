import 'dart:js_interop';
import 'package:web/web.dart' as web;

/// Updates the browser favicon to the given data URI (base64 PNG).
void setFaviconDataUri(String dataUri) {
  try {
    final head = web.document.head;
    if (head == null) return;

    // Remove existing favicon links
    final existing = web.document.querySelectorAll('link[rel="icon"]');
    for (var i = 0; i < existing.length; i++) {
      existing.item(i)?.parentNode?.removeChild(existing.item(i)!);
    }

    // Create new favicon link
    final link = web.document.createElement('link') as web.HTMLLinkElement;
    link.rel = 'icon';
    link.type = 'image/png';
    link.href = dataUri;
    head.appendChild(link);
  } catch (_) {}
}

/// Restores the default favicon.
void restoreDefaultFavicon() {
  try {
    final head = web.document.head;
    if (head == null) return;

    final existing = web.document.querySelectorAll('link[rel="icon"]');
    for (var i = 0; i < existing.length; i++) {
      existing.item(i)?.parentNode?.removeChild(existing.item(i)!);
    }

    final link = web.document.createElement('link') as web.HTMLLinkElement;
    link.rel = 'icon';
    link.type = 'image/png';
    link.href = 'favicon.png';
    head.appendChild(link);
  } catch (_) {}
}
