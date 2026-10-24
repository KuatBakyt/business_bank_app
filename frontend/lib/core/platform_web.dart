import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:web/web.dart' as web;

void savePending(String user, String? value) {
  try {
    if (value == null) {
      web.window.sessionStorage.removeItem('bank-pending-$user');
    } else {
      web.window.sessionStorage.setItem('bank-pending-$user', value);
    }
  } catch (_) {
    /* Storage may be disabled. In-memory recovery remains available. */
  }
}

String? readPending(String user) {
  try {
    return web.window.sessionStorage.getItem('bank-pending-$user');
  } catch (_) {
    return null;
  }
}

void downloadBytes(Uint8List bytes, String filename) {
  final blob = web.Blob(
      [bytes.toJS].toJS, web.BlobPropertyBag(type: 'application/octet-stream'));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body?.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
}
