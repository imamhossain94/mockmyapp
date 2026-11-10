import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import 'studio_button.dart';
import 'studio_fields.dart';
import 'studio_surface.dart';

/// A themed replacement for [AlertDialog]: an `overlay` surface with radius
/// `lg`, a 1px `border` and a single tight shadow (dialogs are one of the few
/// places a shadow is allowed).
///
/// Provide either [message] for a plain sentence or [content] for arbitrary
/// widgets, and lay the footer out with [actions] (usually `StudioButton`s,
/// last one primary). Used for rename, delete, discard and error prompts.
class StudioDialog extends StatelessWidget {
  const StudioDialog({
    super.key,
    required this.title,
    this.message,
    this.content,
    this.actions = const <Widget>[],
    this.icon,
    this.danger = false,
  });

  /// Dialog headline, rendered as `titleSmall`.
  final String title;

  /// Optional body sentence. Ignored when [content] is supplied.
  final String? message;

  /// Optional custom body, replacing [message].
  final Widget? content;

  /// Footer buttons, laid out end-aligned.
  final List<Widget> actions;

  /// Optional glyph beside the title. Must come from `StudioIcons`.
  final StudioIconData? icon;

  /// Tints the title glyph `danger` — for destructive prompts.
  final bool danger;

  /// The one shadow a floating overlay gets: 16 blur, 4 down, 18% black. A
  /// dialog and the wide form of [showStudioSheet] used to differ — one had
  /// it, one did not — so they read as two kinds of window.
  static List<BoxShadow> overlayShadow(BuildContext context) => [
    BoxShadow(
      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.18),
      blurRadius: 16,
      offset: const Offset(0, 4),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.all(StudioSpace.xxl),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        padding: EdgeInsets.all(StudioSpace.xl),
        decoration: BoxDecoration(
          color: s.overlay,
          border: Border.all(color: s.border),
          borderRadius: BorderRadius.circular(StudioRadius.lg),
          boxShadow: overlayShadow(context),
        ),
        child: StudioSurface(color: s.overlay, child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = context.studio;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              StudioIcon(
                icon!,
                size: 16,
                color: danger ? s.dangerText : s.accentText,
              ),
              SizedBox(width: StudioSpace.m),
            ],
            Expanded(
              child: Text(
                title,
                style: StudioText.titleSmall(
                  context,
                ).copyWith(color: s.textPrimary),
              ),
            ),
          ],
        ),
        if (content != null) ...[
          SizedBox(height: StudioSpace.l),
          content!,
        ] else if (message != null) ...[
          SizedBox(height: StudioSpace.m),
          Text(
            message!,
            style: StudioText.body(context).copyWith(color: s.textSecondary),
          ),
        ],
        if (actions.isNotEmpty) ...[
          SizedBox(height: StudioSpace.xl),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) SizedBox(width: StudioSpace.m),
                actions[i],
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// Shows a two-button confirmation built on [StudioDialog] and resolves to
/// `true` only when the user confirms (dismissing resolves to `false`).
///
/// Set [danger] for destructive confirmations — the confirm button switches to
/// the `danger` variant. Used before deleting a project or a screen and before
/// discarding unsaved edits.
Future<bool> showStudioConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
  StudioIconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => StudioDialog(
      title: title,
      message: message,
      icon: icon,
      danger: danger,
      actions: [
        StudioButton(
          label: cancelLabel,
          variant: StudioButtonVariant.ghost,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        StudioButton(
          label: confirmLabel,
          variant: danger
              ? StudioButtonVariant.danger
              : StudioButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for one line of text and returns it, or null if the user backed out.
///
/// The third copy of this dialog is what made it worth having: the project
/// screen, the layers panel and the caption styles all needed "name this
/// thing", and each had grown its own controller, its own two buttons and its
/// own submit handling. The differences between them were accidental — one
/// trimmed the result, one did not; one submitted on the keyboard's done key,
/// one only on the button.
Future<String?> showStudioPrompt(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
  String cancelLabel = 'Cancel',
  StudioIconData icon = StudioIcons.edit,
  bool allowEmpty = false,
}) async {
  final result = await showDialog<String>(
    context: context,
    builder: (context) => _PromptDialog(
      title: title,
      label: label,
      initial: initial,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      icon: icon,
    ),
  );

  // An empty answer usually means the same as backing out — nothing wants an
  // untitled project or a nameless style, and every caller was checking for
  // it. [allowEmpty] is for the one place where clearing the field is a real
  // answer: a layer emptied of its name goes back to being called after its
  // kind, and folding that into "cancelled" would make the name unclearable.
  final trimmed = result?.trim();
  if (trimmed == null) return null;
  if (trimmed.isEmpty && !allowEmpty) return null;
  return trimmed;
}

/// The prompt's body, stateful only so that it owns its controller.
///
/// The controller cannot be created beside `showDialog` and disposed when the
/// future completes: the route is still playing its exit animation at that
/// point and goes on rebuilding the field, which asserts with "a
/// TextEditingController was used after being disposed". Owning it here hands
/// the lifetime to the element tree, which disposes it once the route is
/// actually gone.
class _PromptDialog extends StatefulWidget {
  const _PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.icon,
  });

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;
  final String cancelLabel;
  final StudioIconData icon;

  @override
  State<_PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<_PromptDialog> {
  late final TextEditingController
  _controller = TextEditingController(text: widget.initial)
    ..selection = TextSelection(
      baseOffset: 0,
      // Selected rather than merely present, so typing replaces the old name —
      // which is what renaming almost always is.
      extentOffset: widget.initial.length,
    );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StudioDialog(
      title: widget.title,
      icon: widget.icon,
      content: StudioTextField(
        controller: _controller,
        autofocus: true,
        label: widget.label,
        height: StudioSizes.listRow,
        textInputAction: TextInputAction.done,
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        StudioButton(
          label: widget.cancelLabel,
          variant: StudioButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        StudioButton(
          label: widget.confirmLabel,
          variant: StudioButtonVariant.primary,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
    );
  }
}
