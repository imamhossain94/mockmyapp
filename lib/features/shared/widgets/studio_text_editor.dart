import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import 'studio_button.dart';
import 'studio_fields.dart';
import 'studio_sheet.dart';

/// Opens [controller]'s text in a modal that carries the keyboard with it.
///
/// The pattern the caption panel established, made available to every field
/// that edits document content. Typing in place meant the keyboard resized the
/// whole workspace: the canvas jumped, the mockup shrank, and the one thing you
/// were looking at while typing — how the text sits on the artwork — was the
/// thing that moved. Here only the input travels; the composition behind it
/// stays exactly where it was.
///
/// Pair it with a `readOnly` [StudioTextField] whose `onTap` calls this, so the
/// inline field becomes a preview of its own value:
///
/// ```dart
/// StudioTextField(
///   controller: controller,
///   readOnly: true,
///   onTap: () => showStudioTextEditor(context, title: 'Line 1', ...),
/// )
/// ```
///
/// [onChanged] fires on every keystroke so the canvas updates live behind the
/// modal, which is the point of moving the input rather than the workspace.
/// The modal itself is placed by [showStudioSheet], so it is a bottom sheet on
/// a phone held upright, a side sheet in landscape and a dialog on a desktop —
/// the caller does not choose.
Future<void> showStudioTextEditor(
  BuildContext context, {
  required String title,
  required TextEditingController controller,
  required ValueChanged<String> onChanged,
  String? hint,
  int maxLines = 4,
  int minLines = 2,
  TextCapitalization textCapitalization = TextCapitalization.sentences,
}) {
  return showStudioSheet<void>(
    context,
    title: title,
    child: _TextEditorBody(
      source: controller,
      onChanged: onChanged,
      hint: hint,
      maxLines: maxLines,
      minLines: minLines,
      textCapitalization: textCapitalization,
    ),
  );
}

/// The sheet's field, typing into a controller of its own.
///
/// The sheet's future completes the moment it is dismissed, but its closing
/// animation goes on building the field for a few frames more. A caller that
/// disposed the controller it passed in as soon as the sheet returned — the
/// natural thing to do with one made just for the edit — took those frames
/// down with it. This one lives exactly as long as the field does, and every
/// keystroke is copied back to the caller's, so a preview bound to that one
/// still follows the typing.
class _TextEditorBody extends StatefulWidget {
  const _TextEditorBody({
    required this.source,
    required this.onChanged,
    required this.hint,
    required this.maxLines,
    required this.minLines,
    required this.textCapitalization,
  });

  final TextEditingController source;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int maxLines;
  final int minLines;
  final TextCapitalization textCapitalization;

  @override
  State<_TextEditorBody> createState() => _TextEditorBodyState();
}

class _TextEditorBodyState extends State<_TextEditorBody> {
  late final TextEditingController _field = TextEditingController.fromValue(
    widget.source.value,
  );

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.l,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioTextField(
            controller: _field,
            hint: widget.hint,
            autofocus: true,
            maxLines: widget.maxLines,
            minLines: widget.minLines,
            textCapitalization: widget.textCapitalization,
            onChanged: (words) {
              widget.source.value = _field.value;
              widget.onChanged(words);
            },
          ),
          SizedBox(height: StudioSpace.l),
          StudioButton(
            label: 'Done',
            icon: StudioIcons.check,
            variant: StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}
