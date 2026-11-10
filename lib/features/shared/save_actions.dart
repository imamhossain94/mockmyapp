import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/repositories/stored_image.dart';
import '../../data/services/device_storage.dart';
import '../../domain/models/screen_doc.dart';
import 'widgets/widgets.dart';
import 'friendly_error.dart';

/// Where the user chose to send a finished export.
enum SaveChoice {
  /// Photo gallery / camera roll.
  gallery,

  /// Public Downloads folder (app Documents on iOS).
  downloads,

  /// Hand off to the system share sheet.
  share,
}

/// A browser on a computer, as opposed to one on a phone or tablet.
bool get _desktopBrowser =>
    kIsWeb &&
    const {
      TargetPlatform.macOS,
      TargetPlatform.windows,
      TargetPlatform.linux,
    }.contains(defaultTargetPlatform);

/// A themed confirmation snackbar. Success is quiet; failures take the `danger`
/// token so they cannot be mistaken for a completed save.
///
/// It rides above whatever the screen has docked at the bottom — the library's
/// action bar, the editor's tool tab strip — by reading [StudioBottomChrome].
/// [Scaffold] does that for you only when the chrome is its
/// `bottomNavigationBar`, and none of ours is.
void showStudioSnack(
  BuildContext context,
  String message, {
  StudioIconData icon = StudioIcons.success,
  bool danger = false,

  /// An action offered alongside the message — in practice always "Undo".
  ///
  /// The toast is the only place a bulk action can offer one: the change has
  /// already happened by the time it appears, and a dialog in front of every
  /// restyle would tax the ninety-nine times it was meant for the one time it
  /// was not. Both must be supplied for the button to be drawn.
  String? actionLabel,
  VoidCallback? onAction,
}) {
  if (!context.mounted) return;
  final s = context.studio;
  final fg = danger ? s.onAccent : s.textPrimary;
  final dock = StudioBottomChrome.of(context);
  final hasAction = actionLabel != null && onAction != null;

  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: danger ? s.danger : s.panelAlt,
        elevation: 0,
        // Longer with an action on it. Four seconds is enough to read a
        // confirmation and not enough to notice a set of eight screens has
        // changed, decide that was wrong and reach for the button.
        duration: Duration(seconds: danger ? 5 : (hasAction ? 8 : 4)),
        // Flutter keeps a snack bar with an action on screen until it is
        // dismissed, which left every "Undo" toast parked over the canvas for
        // good. It times out like any other; a screen-reader user, who needs
        // the time to reach the button, still gets one that waits.
        persist: MediaQuery.accessibleNavigationOf(context),
        margin: EdgeInsets.fromLTRB(
          StudioSpace.xl,
          0,
          StudioSpace.xl,
          // The dock already absorbs the safe-area inset, so adding it again
          // here would float the toast a home-indicator too high.
          dock + StudioSpace.l,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.md),
        ),
        content: Row(
          children: [
            StudioIcon(danger ? StudioIcons.error : icon, size: 14, color: fg),
            SizedBox(width: StudioSpace.m),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: StudioText.body(context).copyWith(color: fg),
              ),
            ),
          ],
        ),
        action: hasAction
            ? SnackBarAction(
                label: actionLabel,
                textColor: danger ? s.onAccent : s.accent,
                onPressed: onAction,
              )
            : null,
      ),
    );
}

/// How many of [screens] would export a template's sample app, or zero.
///
/// A set made from a template carries the listing's own app UI in each phone
/// as a display fill, until a screenshot covers it. That is the right way to
/// open a fresh project, and the wrong thing to upload to a store: it is a
/// picture of somebody else's app. A sample is a bundled asset sitting in a
/// display with no capture of the user's over it, on a device that is shown.
int templateSampleCount(Iterable<ScreenDoc> screens) => screens
    .where(
      (doc) => doc.frames.any(
        (frame) =>
            !frame.hidden &&
            frame.screenshot.imagePath == null &&
            switch (frame.screenshot.fill) {
              ImageBackground(:final path) => StoredImage.isAsset(path),
              _ => false,
            },
      ),
    )
    .length;

/// What the save sheet says about [screens] before they are exported, or null
/// when there is nothing to say. See [templateSampleCount].
String? templateSampleNotice(Iterable<ScreenDoc> screens) {
  final count = templateSampleCount(screens);
  if (count == 0) return null;
  return count == 1
      ? "1 screen still shows the template's sample app"
      : "$count screens still show the template's sample app";
}

/// Asks where a finished file should go.
///
/// [allowGallery] is false for documents — a JSON backup has no business in the
/// camera roll. [notice] is a line about what is being exported that is worth
/// knowing before it goes anywhere (see [templateSampleNotice]); it informs
/// and never blocks, since exporting a sample to look at it is fine.
///
/// [header] goes between the file name and the destinations — the store
/// export checklist, which has to be read before a destination is picked and
/// must never stand in the way of picking one.
Future<SaveChoice?> askSaveDestination(
  BuildContext context, {
  required String title,
  required String fileName,
  bool allowGallery = true,
  bool video = false,
  String? notice,
  Widget? header,
}) {
  return showStudioSheet<SaveChoice>(
    context,
    title: title,
    child: _DestinationList(
      fileName: fileName,
      allowGallery: allowGallery,
      video: video,
      notice: notice,
      header: header,
    ),
  );
}

class _DestinationList extends StatelessWidget {
  const _DestinationList({
    required this.fileName,
    required this.allowGallery,
    this.video = false,
    this.notice,
    this.header,
  });

  final String fileName;
  final bool allowGallery;

  /// See [askSaveDestination].
  final String? notice;

  /// Shown above the destinations. See [askSaveDestination].
  final Widget? header;

  /// A clip rather than a picture: on Android it goes to Movies, not
  /// Pictures, and the row says so.
  final bool video;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    // `Platform` is `dart:io`, which on the web is a stub that throws — asking
    // it anything would take the save sheet down before it ever painted.
    final isApple = !kIsWeb && !Platform.isAndroid;

    // Scrolls, because a checklist for a whole project can be taller than a
    // phone's sheet; without a header it is short enough never to need to.
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.l,
              StudioSpace.xl,
              StudioSpace.m,
            ),
            child: StudioNumericWell(text: fileName, width: double.infinity),
          ),
          // Above the destinations, so it is read before one is tapped.
          if (notice case final notice?) ...[
            StudioListRow(
              icon: StudioIcons.info,
              title: notice,
              subtitle: 'Drop your own screenshots in to replace the sample',
            ),
            const StudioDivider(),
          ],
          if (header case final header?)
            Padding(
              padding: EdgeInsets.fromLTRB(
                StudioSpace.xl,
                0,
                StudioSpace.xl,
                StudioSpace.m,
              ),
              child: header,
            ),
          // No photo library in a browser — there is one destination there, and
          // offering a second that cannot work is worse than offering one.
          if (allowGallery && !kIsWeb)
            StudioListRow(
              icon: StudioIcons.images,
              title: isApple ? 'Photo Library' : 'Gallery',
              subtitle: isApple
                  ? 'Photos › ${DeviceStorage.folder}'
                  : '${video ? 'Movies' : 'Pictures'}/${DeviceStorage.folder}',
              onTap: () => Navigator.pop(context, SaveChoice.gallery),
              trailing: StudioIcon(
                StudioIcons.chevronRight,
                size: 12,
                color: s.textTertiary,
              ),
            ),
          StudioListRow(
            icon: StudioIcons.export,
            title: kIsWeb ? 'Download' : (isApple ? 'Files' : 'Downloads'),
            subtitle: kIsWeb
                ? 'Wherever your browser saves files'
                : (isApple
                      ? 'On My iPhone › MockMyApp'
                      : 'Download/${DeviceStorage.folder}'),
            onTap: () => Navigator.pop(context, SaveChoice.downloads),
            trailing: StudioIcon(
              StudioIcons.chevronRight,
              size: 12,
              color: s.textTertiary,
            ),
          ),
          // Not in a desktop browser. Its share sheet, where there is one, rarely
          // takes files, and where there is none the request never settled: the
          // sheet closed on nothing and the Download button stayed disabled.
          // A phone's browser shares to Photos and to other apps, so it keeps it.
          if (!_desktopBrowser)
            StudioListRow(
              icon: StudioIcons.share,
              title: 'Share…',
              subtitle: 'Send to another app',
              onTap: () => Navigator.pop(context, SaveChoice.share),
              trailing: StudioIcon(
                StudioIcons.chevronRight,
                size: 12,
                color: s.textTertiary,
              ),
            ),
          SizedBox(height: StudioSpace.m),
        ],
      ),
    );
  }
}

/// Writes [bytes] wherever [choice] says, and reports the outcome inline.
///
/// Returns true when the bytes reached storage (a cancelled share counts as
/// success — the file was handed to the OS).
Future<bool> deliver(
  BuildContext context, {
  required SaveChoice choice,
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
  String? subFolder,
  String shareSubject = 'MockMyApp',
  Rect? sharePositionOrigin,
}) async {
  try {
    switch (choice) {
      case SaveChoice.gallery:
        final at = mimeType.startsWith('video/')
            ? await DeviceStorage.saveVideo(
                bytes,
                fileName: fileName,
                mimeType: mimeType,
                subFolder: subFolder,
              )
            : await DeviceStorage.saveImage(
                bytes,
                fileName: fileName,
                mimeType: mimeType,
                subFolder: subFolder,
              );
        if (context.mounted) showStudioSnack(context, 'Saved to $at');
      case SaveChoice.downloads:
        final at = await DeviceStorage.saveDocument(
          bytes,
          fileName: fileName,
          mimeType: mimeType,
          subFolder: subFolder,
        );
        if (context.mounted) showStudioSnack(context, 'Saved to $at');
      case SaveChoice.share:
        await shareBytes(
          bytes,
          fileName: fileName,
          mimeType: mimeType,
          subject: shareSubject,
          positionOrigin: sharePositionOrigin,
        );
    }
    return true;
  } on DeviceStorageException catch (e) {
    if (context.mounted) showStudioSnack(context, e.message, danger: true);
    return false;
  } catch (e) {
    if (context.mounted) showErrorSnack(context, 'Could not save the file.', e);
    return false;
  }
}

/// One file ready for the share sheet.
///
/// On a device the bytes are staged in the cache directory, because the share
/// sheet hands other apps a *path*. In a browser there is no cache directory
/// and no path to hand over, so the bytes travel in the `XFile` itself.
Future<XFile> _stage(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
}) async {
  final safeName = DeviceStorage.sanitizeFileName(fileName);
  if (kIsWeb) {
    return XFile.fromData(bytes, name: safeName, mimeType: mimeType);
  }
  final dir = await getTemporaryDirectory();
  final file = File(p.join(dir.path, safeName));
  await file.writeAsBytes(bytes, flush: true);
  return XFile(file.path, mimeType: mimeType);
}

/// Stages [bytes] and opens the system share sheet.
Future<void> shareBytes(
  Uint8List bytes, {
  required String fileName,
  required String mimeType,
  String subject = 'MockMyApp',
  Rect? positionOrigin,
}) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [await _stage(bytes, fileName: fileName, mimeType: mimeType)],
      subject: subject,
      sharePositionOrigin: positionOrigin,
    ),
  );
}

/// Stages a whole set and shares it in one sheet.
Future<void> shareManyBytes(
  List<({Uint8List bytes, String fileName})> files, {
  required String mimeType,
  String subject = 'MockMyApp',
  Rect? positionOrigin,
}) async {
  if (files.isEmpty) return;
  final staged = [
    for (final entry in files)
      await _stage(entry.bytes, fileName: entry.fileName, mimeType: mimeType),
  ];
  await SharePlus.instance.share(
    ShareParams(
      files: staged,
      subject: subject,
      sharePositionOrigin: positionOrigin,
    ),
  );
}

/// The share-sheet anchor iPad needs; harmless everywhere else.
Rect? shareOriginOf(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
