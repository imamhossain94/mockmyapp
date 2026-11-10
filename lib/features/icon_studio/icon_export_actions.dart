import 'package:flutter/material.dart';

import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../data/repositories/graphics_archive.dart';
import '../../domain/icons/icon_art.dart';
import '../../domain/icons/icon_export.dart';
import '../../domain/models/project.dart';
import '../shared/friendly_error.dart';
import '../shared/save_actions.dart';
import '../shared/widgets/widgets.dart';

/// Renders every icon file [project]'s icon makes, with the text files
/// beside them — what the export ZIP holds, and what a test checks.
Future<List<IconFile>> buildIconFiles(
  Project project, {
  void Function(int done, int total)? onProgress,
}) async {
  final icon = project.icon;
  if (icon == null) throw StateError('No icon to export');
  final art = await resolveIconArt(icon);
  return renderIconFiles(art, appName: project.name, onProgress: onProgress);
}

/// Exports [project]'s icon as one ZIP: asks where it goes, renders every
/// file with a progress bar, and hands the archive over.
Future<void> exportIconZip(BuildContext context, Project project) async {
  if (project.icon == null) {
    showStudioSnack(
      context,
      'Design an icon first: pick a concept to start from.',
      icon: StudioIcons.info,
    );
    return;
  }
  final fileName = iconArchiveName(project.name);
  final choice = await askSaveDestination(
    context,
    title: 'Export app icons',
    fileName: fileName,
    allowGallery: false,
    notice:
        '${IconExport.files.length} files for iOS, Google Play, Android, the '
        'web, Microsoft and Chrome, with a README that says where each goes.',
  );
  if (choice == null || !context.mounted) return;

  final progress = ValueNotifier<double>(0);
  final navigator = Navigator.of(context, rootNavigator: true);
  var open = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ProgressDialog(progress: progress),
  ).then((_) => open = false);

  final List<IconFile> files;
  try {
    files = await buildIconFiles(
      project,
      onProgress: (done, total) => progress.value = done / total,
    );
  } catch (error) {
    if (open) navigator.pop();
    progress.dispose();
    if (context.mounted) {
      showErrorSnack(context, 'Could not export the icons.', error);
    }
    return;
  }
  if (open) navigator.pop();
  progress.dispose();
  if (!context.mounted) return;

  await deliver(
    context,
    choice: choice,
    bytes: buildIconArchive(project.name, files),
    fileName: fileName,
    mimeType: GraphicsArchive.mimeType,
    shareSubject: '${project.name} icons',
    sharePositionOrigin: shareOriginOf(context),
  );
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress});

  final ValueNotifier<double> progress;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return PopScope(
      canPop: false,
      child: StudioDialog(
        title: 'Exporting icons',
        icon: StudioIcons.export,
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              StudioProgressBar(value: value),
              SizedBox(height: StudioSpace.m),
              Text(
                '${(value * IconExport.files.length).round()} of '
                '${IconExport.files.length} files',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
