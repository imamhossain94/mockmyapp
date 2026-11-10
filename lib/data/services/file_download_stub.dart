import 'dart:typed_data';

/// Offers [bytes] to the user as a download named [fileName].
///
/// Never called off the web: every other platform has somewhere real to write,
/// and [DeviceStorage] routes there instead. The throw is a contract violation
/// rather than a degraded path.
Future<void> downloadBytes(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) {
  throw UnsupportedError(
    'downloadBytes is the web implementation of saving a file; '
    'this platform writes to storage instead.',
  );
}
