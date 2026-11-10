import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Offers [bytes] to the user as a download named [fileName].
///
/// The browser's only "save a file" affordance: wrap the bytes in a blob, point
/// a hidden anchor at it, and click it. Where the file lands is the browser's
/// business — its download folder, or a prompt, depending on the user's own
/// settings — which is why the caller cannot report a path afterwards.
Future<void> downloadBytes(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  final blob = web.Blob(
    <JSAny>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: mimeType),
  );
  final url = web.URL.createObjectURL(blob);

  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = fileName;
  // Attached, clicked, removed: a detached anchor's click is ignored by some
  // browsers, and leaving it behind would litter the document with one node
  // per export.
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();

  // The blob would otherwise be held for the life of the page — and these are
  // whole PNG sets, not kilobytes.
  web.URL.revokeObjectURL(url);
}
