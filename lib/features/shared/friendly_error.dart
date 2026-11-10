import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../data/repositories/project_archive.dart';
import '../../data/services/device_storage.dart';
import '../../data/services/on_device_ai.dart';
import '../../data/services/video_encoder.dart';
import 'save_actions.dart';

/// One sentence a person can act on, for an error the app caught.
///
/// Twenty-odd places used to put the exception itself in front of the user —
/// "Could not import that file: FormatException: Unexpected character (at
/// offset 0)" — which names the bug and not the problem. Callers say what
/// failed ("Could not import that file.") and append this, which says why in
/// words and what to do next. The raw error goes to the debug log and, through
/// [showErrorSnack], to the clipboard on request, for a bug report.
///
/// Reads [friendlyErrorTable] top to bottom; the first rule that matches
/// wins, and anything no rule knows gets a plain "try again".
String friendlyError(Object error) => _match(error).describe(error);

/// Whether [friendlyError] recognised [error], rather than falling back to the
/// generic sentence. An unrecognised error is the one worth a bug report.
bool isKnownError(Object error) => _match(error) != _fallback;

/// Shows "[what] [why]" as a danger toast, logging the raw [error].
///
/// [what] is the failure in the caller's own words, as a sentence: "Could not
/// import that file." An error no rule recognises also offers "Copy details",
/// which puts the raw error on the clipboard — the one thing a person can send
/// that says what actually happened.
void showErrorSnack(BuildContext context, String what, Object error) {
  debugPrint('$what $error');
  final known = isKnownError(error);
  showStudioSnack(
    context,
    '$what ${friendlyError(error)}',
    danger: true,
    actionLabel: known ? null : 'Copy details',
    onAction: known
        ? null
        : () => Clipboard.setData(ClipboardData(text: '$what\n$error')),
  );
}

/// A rule of [friendlyErrorTable]: which errors it covers and what to say.
@immutable
class FriendlyErrorRule {
  const FriendlyErrorRule(this.name, this.matches, this.describe);

  /// What the rule is for, for a reader of the table and a failing test.
  final String name;
  final bool Function(Object error) matches;
  final String Function(Object error) describe;
}

/// The mapping, most specific first.
final List<FriendlyErrorRule> friendlyErrorTable = [
  // Thrown with a message already written for the user.
  FriendlyErrorRule(
    'project backup',
    (e) => e is ProjectArchiveException,
    (e) => _sentence((e as ProjectArchiveException).message),
  ),
  FriendlyErrorRule(
    'device storage',
    (e) => e is DeviceStorageException,
    (e) => _sentence((e as DeviceStorageException).message),
  ),
  // These carry the engine's own words, which are often a platform message
  // or a stack of them, so they are summarised instead of shown.
  FriendlyErrorRule(
    'on-device AI',
    (e) => e is OnDeviceAiException,
    (_) => 'The on-device model could not finish. Try again in a moment.',
  ),
  FriendlyErrorRule(
    'video encoder',
    (e) => e is VideoEncoderException,
    (_) => 'The video encoder on this device stopped. Try again.',
  ),
  FriendlyErrorRule(
    'file system',
    (e) => e is FileSystemException,
    (e) => _fileSystem(e as FileSystemException),
  ),
  FriendlyErrorRule(
    'unreadable format',
    (e) => e is FormatException,
    (_) => 'The file is not in a format MockMyApp can read.',
  ),
  FriendlyErrorRule(
    'network',
    (e) => e is SocketException || e is HttpException || e is TlsException,
    (_) => 'Could not connect. Check your internet connection and try again.',
  ),
  FriendlyErrorRule(
    'timeout',
    (e) => e is TimeoutException,
    (_) => 'That took too long. Check your connection and try again.',
  ),
  FriendlyErrorRule(
    'out of memory',
    (e) => e is OutOfMemoryError,
    (_) =>
        'There was not enough memory to finish. Close other apps and try '
        'again.',
  ),
  FriendlyErrorRule(
    'platform',
    (e) => e is PlatformException && _platformCodes.containsKey(e.code),
    (e) => _platformCodes[(e as PlatformException).code]!,
  ),
  FriendlyErrorRule(
    'permission',
    (e) =>
        e is PlatformException &&
        (e.code.contains('denied') || e.code.contains('permission')),
    (_) =>
        'MockMyApp needs permission for that. Allow it in your device '
        'settings, then try again.',
  ),
];

/// Platform channel codes with a known meaning — image_picker's and the app's
/// own storage bridge's.
const Map<String, String> _platformCodes = {
  'photo_access_denied':
      'MockMyApp needs access to your photos. Allow it in your device '
      'settings, then try again.',
  'camera_access_denied':
      'MockMyApp needs access to the camera. Allow it in your device '
      'settings, then try again.',
  'invalid_image': 'That image could not be opened. Try a PNG or a JPEG.',
  'multiple_request': 'A picker is already open. Finish with that one first.',
  'no_available_camera': 'This device has no camera MockMyApp can use.',
};

const _fallback = FriendlyErrorRule('anything else', _always, _tryAgain);

bool _always(Object _) => true;

String _tryAgain(Object _) => 'Something unexpected went wrong. Try again.';

FriendlyErrorRule _match(Object error) {
  for (final rule in friendlyErrorTable) {
    if (rule.matches(error)) return rule;
  }
  return _fallback;
}

/// The cause of a file failure, from the OS error code. The numbers differ
/// between Windows and everything else, so each is read on its own terms:
/// POSIX 5 is an I/O error, where on Windows it is "access denied".
String _fileSystem(FileSystemException e) {
  final code = e.osError?.errorCode;
  final windows = !kIsWeb && Platform.isWindows;
  // ENOENT; ERROR_FILE_NOT_FOUND and ERROR_PATH_NOT_FOUND.
  final notFound = windows ? const {2, 3} : const {2};
  // EPERM and EACCES; ERROR_ACCESS_DENIED.
  final denied = windows ? const {5} : const {1, 13};
  // ENOSPC; ERROR_HANDLE_DISK_FULL and ERROR_DISK_FULL.
  final full = windows ? const {39, 112} : const {28};
  if (notFound.contains(code)) {
    return 'The file is no longer where it was. Choose it again.';
  }
  if (denied.contains(code)) {
    return 'MockMyApp is not allowed to open that file. Choose another, or '
        'check its permissions.';
  }
  if (full.contains(code)) {
    return 'This device is out of storage space. Free some up and try again.';
  }
  return 'The file could not be read or written. Try again, or choose '
      'another.';
}

/// [text] as a sentence: trimmed, ending in a full stop.
String _sentence(String text) {
  final t = text.trim();
  if (t.isEmpty) return _tryAgain(t);
  return RegExp(r'[.!?]$').hasMatch(t) ? t : '$t.';
}
