import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/studio_fonts.dart';
import '../../../domain/models/caption_runs.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/widgets/widgets.dart';
import 'font_picker_sheet.dart';
import 'hsv_color_picker.dart';

/// Type size the editor and the panel preview draw the caption's *base* at.
///
/// The document's own `size` is in design pixels against a 1179-wide canvas —
/// 64 of them for a starter headline — so it cannot be used here. What has to
/// survive into the editor is the *relationship* between runs, and that is
/// carried by [CaptionRun.sizeScale], which is a multiplier on whatever base it
/// is given.
const double _kEditorBaseSize = 19;
const double _kPreviewBaseSize = 16;

/// A representative flat colour for [background].
///
/// The rich text editor paints the caption in its real ink, and a caption's
/// real ink is routinely white — which on a panel surface is invisible. So the
/// field is drawn over the artwork's own colour instead of the app's, and this
/// is how an arbitrary backdrop is reduced to one.
///
/// A photo backdrop has no single colour, so it yields the mid grey its overlay
/// is blended over: enough to keep both white and black type legible, which is
/// the only thing this value has to do.
Color captionBackdropOf(Background background) => switch (background) {
  SolidBackground(:final color) => color,
  GradientBackground(:final colorOne, :final colorTwo) =>
    Color.lerp(colorOne, colorTwo, 0.5) ?? colorOne,
  PatternBackground(:final colors) =>
    colors.isEmpty ? const Color(0xFF6E6E6E) : colors.first,
  ImageBackground(:final overlayColor, :final overlayOpacity) =>
    Color.alphaBlend(
      overlayColor.withValues(alpha: overlayOpacity.clamp(0.0, 1.0)),
      const Color(0xFF6E6E6E),
    ),
};

/// A [TextEditingController] that owns the caption's styled runs.
///
/// The runs are the document; the string is what a text field can hold. Keeping
/// both in one object is what makes the two stay in step: every write of
/// [value] carries the styling through the edit that produced it, and
/// [buildTextSpan] is how the field paints the result. Nothing else has to know
/// that a caption is more than a string.
class CaptionRunController extends TextEditingController {
  CaptionRunController({required List<CaptionRun> runs, required this.spec})
    : _runs = CaptionRuns.normalize(runs),
      super(text: CaptionRuns.textOf(runs));

  /// The caption's own type, which a run with no override of its own inherits.
  CaptionSpec spec;

  List<CaptionRun> _runs;

  /// The styled runs behind the current string. Always normalized.
  List<CaptionRun> get runs => _runs;

  @override
  set value(TextEditingValue newValue) {
    // Only a text change needs remapping; a caret move or a selection drag
    // rewrites `value` just as often and must leave the runs identical, because
    // the editor uses their identity to decide whether the document changed.
    if (newValue.text != text) {
      _runs = CaptionRuns.applyEdit(_runs, text, newValue.text);
    }
    super.value = newValue;
  }

  /// Replaces the styling without touching the string — what every toolbar
  /// action does.
  void restyle(List<CaptionRun> next) {
    _runs = CaptionRuns.normalize(next);
    notifyListeners();
  }

  /// The style one run paints with in the editor, over the field's base.
  TextStyle styleFor(CaptionRun? run, double baseSize, Color fallbackInk) =>
      StudioFonts.style(
        run?.fontFamily ?? spec.fontFamily,
        fontSize: baseSize * (run?.sizeScale ?? 1),
        color: run?.color ?? fallbackInk,
        fontWeight: (run?.bold ?? spec.bold)
            ? FontWeight.bold
            : FontWeight.normal,
        fontStyle: (run?.italic ?? spec.italic)
            ? FontStyle.italic
            : FontStyle.normal,
        decoration: (run?.underline ?? spec.underline)
            ? TextDecoration.underline
            : TextDecoration.none,
        decorationColor: run?.color ?? fallbackInk,
        // Tracking is deliberately not applied. It is stored in canvas design
        // pixels against a 64pt headline, and reproducing it under a 19pt
        // editor would space the letters two glyphs apart.
        height: 1.35,
      );

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final ink = style?.color ?? spec.color;
    final size = style?.fontSize ?? _kEditorBaseSize;

    // A span tree whose text disagrees with `value.text` asserts inside
    // `EditableText`, which would turn any bug up here into a crash while
    // typing. The runs are kept in step by the setter above; this is the belt
    // to that pair of braces.
    if (_runs.isEmpty || CaptionRuns.textOf(_runs) != text) {
      return TextSpan(text: text, style: styleFor(null, size, ink));
    }

    return TextSpan(
      style: styleFor(null, size, ink),
      children: [
        for (final run in _runs)
          TextSpan(text: run.text, style: styleFor(run, size, ink)),
      ],
    );
  }
}

/// Opens the caption in a rich text editor that carries the keyboard with it.
///
/// The same reasoning as [showStudioTextEditor], which this replaces for a rich
/// caption: typing in place raised the keyboard over the artwork the text is
/// being written against. Here only the input travels.
///
/// [onChanged] fires on every keystroke and every formatting change, so the
/// canvas behind the modal updates live.
Future<void> showRichCaptionEditor(
  BuildContext context, {
  required String title,
  required CaptionSpec spec,
  required Color backdrop,
  required ValueChanged<List<CaptionRun>> onChanged,
}) => showStudioSheet<void>(
  context,
  title: title,
  child: Builder(
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.s,
        StudioSpace.xl,
        StudioSpace.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RichCaptionEditor(
            spec: spec,
            backdrop: backdrop,
            autofocus: true,
            onChanged: onChanged,
          ),
          SizedBox(height: StudioSpace.l),
          StudioButton(
            label: 'Done',
            icon: StudioIcons.check,
            variant: StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: () => Navigator.of(sheetContext).maybePop(),
          ),
        ],
      ),
    ),
  ),
);

/// The caption, edited the way a word processor edits text: select some of it,
/// press a button, and only that part changes.
///
/// It replaces an editor that could only style a whole line at a time, and it
/// keeps that gesture rather than dropping it — with nothing selected, a
/// formatting button applies to the line the caret is in. So the old
/// line-by-line workflow is one tap, and styling three characters in the middle
/// of a word, which used to be impossible, is a drag and a tap.
class RichCaptionEditor extends StatefulWidget {
  const RichCaptionEditor({
    super.key,
    required this.spec,
    required this.backdrop,
    required this.onChanged,
    this.autofocus = false,
  });

  /// The caption being edited. Its runs seed the field and its own type is what
  /// a run with no override paints in.
  final CaptionSpec spec;

  /// The artwork's colour behind the field — see [captionBackdropOf].
  final Color backdrop;

  final ValueChanged<List<CaptionRun>> onChanged;

  final bool autofocus;

  @override
  State<RichCaptionEditor> createState() => _RichCaptionEditorState();
}

class _RichCaptionEditorState extends State<RichCaptionEditor> {
  late final CaptionRunController _controller = CaptionRunController(
    runs: widget.spec.runs,
    spec: widget.spec,
  );
  final _focus = FocusNode();

  /// The last run list handed upward, compared by identity.
  ///
  /// Every operation in [CaptionRuns] returns a fresh list and a selection
  /// change returns the same one, which is exactly the distinction needed:
  /// moving the caret must not mark the document dirty.
  ///
  /// Assigned in [initState] rather than in a `late` initialiser. A `late`
  /// field runs its initialiser on first *read*, and the first read is inside
  /// the change handler — by which point it would be reading the list that had
  /// just replaced it, call itself unchanged, and swallow the edit.
  late List<CaptionRun> _reported;

  @override
  void initState() {
    super.initState();
    _reported = _controller.runs;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(RichCaptionEditor old) {
    super.didUpdateWidget(old);
    // The caption's own type can change under the editor — the panel's typeface
    // row and colour picker are still live behind the sheet — and every run
    // that never overrode it paints from here.
    _controller.spec = widget.spec;
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final runs = _controller.runs;
    if (!identical(runs, _reported)) {
      _reported = runs;
      widget.onChanged(runs);
    }
    // The toolbar's lit state is a function of the selection, so it has to
    // follow a bare caret move as well as an edit.
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // What a formatting action applies to
  // ---------------------------------------------------------------------------

  /// The `[start, end)` the toolbar acts on.
  ///
  /// A real selection is itself. A bare caret takes the line it sits in, which
  /// is what makes "style this line" a single tap. An empty line — or no
  /// selection at all, which is where the field starts — takes the whole
  /// caption, so a press is never silently a no-op.
  (int, int) get _range {
    final value = _controller.value;
    final selection = value.selection;
    if (!selection.isValid) return (0, value.text.length);
    if (!selection.isCollapsed) return (selection.start, selection.end);
    final (start, end) = CaptionRuns.lineBoundsAt(value.text, selection.start);
    return start == end ? (0, value.text.length) : (start, end);
  }

  /// Whether the whole range already reads [on].
  bool _isOn(bool Function(CaptionRun) on, bool fallback) {
    final (start, end) = _range;
    if (_controller.runs.isEmpty || end <= start) return fallback;
    return CaptionRuns.everyIn(_controller.runs, start, end, on);
  }

  /// What the range agrees on, or null where it does not.
  T? _uniform<T>(T? Function(CaptionRun) read) {
    final (start, end) = _range;
    final within = CaptionRuns.slice(_controller.runs, start, end);
    if (within.isEmpty) return null;
    final first = read(within.first);
    for (final run in within) {
      if (read(run) != first) return null;
    }
    return first;
  }

  void _apply(CaptionRun Function(CaptionRun) fn) {
    final (start, end) = _range;
    if (end <= start) return;
    HapticFeedback.selectionClick();
    _controller.restyle(CaptionRuns.restyle(_controller.runs, start, end, fn));
  }

  /// Toggles one boolean override across the range.
  ///
  /// Landing back on the caption's own value *clears* the override rather than
  /// writing it explicitly. That is what lets the run merge back into its
  /// neighbours, and what keeps a later change to the caption as a whole — the
  /// Bold switch in the panel — still reaching text that was toggled on and off
  /// again here.
  void _toggle({
    required bool Function(CaptionRun) read,
    required bool base,
    required CaptionRun Function(CaptionRun, bool) write,
    required CaptionRun Function(CaptionRun) clear,
  }) {
    final next = !_isOn(read, base);
    _apply((run) => next == base ? clear(run) : write(run, next));
  }

  void _nudgeSize(double delta) => _apply((run) {
    final raw = ((run.sizeScale ?? 1) + delta).clamp(0.3, 2.5);
    final value = (raw * 100).roundToDouble() / 100;
    return value == 1
        ? run.copyWith(clearSizeScale: true)
        : run.copyWith(sizeScale: value);
  });

  Future<void> _pickColour() async {
    final current = _uniform((r) => r.color) ?? widget.spec.color;
    await showStudioSheet<void>(
      context,
      title: 'Colour for the selection',
      child: SingleChildScrollView(
        padding: EdgeInsets.all(StudioSpace.xl),
        child: HsvColorPicker(
          color: current,
          onChanged: (c) => _apply((run) => run.copyWith(color: c)),
        ),
      ),
    );
  }

  Future<void> _pickFont() async {
    final current = _uniform((r) => r.fontFamily) ?? widget.spec.fontFamily;
    final family = await showFontPicker(context, current: current);
    if (family == null) return;
    _apply((run) => run.copyWith(fontFamily: family));
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final spec = widget.spec;
    final scale = _uniform((r) => r.sizeScale) ?? 1.0;
    final ink = _uniform((r) => r.color) ?? spec.color;
    final (start, end) = _range;
    final selected = _controller.value.selection;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── The type itself ─────────────────────────────────────────────────
        //
        // Not a `StudioTextField`: this one is a preview of the artwork, so it
        // is filled with the artwork's own colour rather than the app's `well`,
        // and the type inside it is the caption's rather than the app's body
        // face. Everything else — radius, padding, the focus ring — is the
        // shared field's, so it still reads as one of them.
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpace.m,
            vertical: StudioSpace.s,
          ),
          decoration: BoxDecoration(
            color: widget.backdrop,
            borderRadius: BorderRadius.circular(StudioRadius.sm),
            border: Border.all(color: s.border),
          ),
          child: TextField(
            controller: _controller,
            focusNode: _focus,
            autofocus: widget.autofocus,
            maxLines: 6,
            minLines: 3,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: spec.color,
            cursorWidth: 1.5,
            textAlign: spec.align.x < 0
                ? TextAlign.left
                : spec.align.x > 0
                ? TextAlign.right
                : TextAlign.center,
            // The base every run is measured against, and the ink every run
            // that never picked one of its own is painted in.
            style: TextStyle(fontSize: _kEditorBaseSize, color: spec.color),
            decoration: InputDecoration(
              // The theme fills every field with `well`. Here that painted a
              // dark slab over the artwork's own colour, leaving dark headline
              // type unreadable inside a pale ring of the backdrop.
              filled: false,
              isDense: true,
              isCollapsed: true,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Type your text…',
              hintStyle: TextStyle(
                fontSize: _kEditorBaseSize,
                color: spec.color.withValues(alpha: 0.45),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        SizedBox(height: StudioSpace.s),

        // ── What the next press will land on ────────────────────────────────
        Text(
          !selected.isValid || end <= start
              ? 'Formatting applies to the whole text.'
              : selected.isCollapsed
              ? 'Formatting applies to this line. Select text to style part of '
                    'it.'
              : 'Formatting applies to the ${end - start} selected '
                    '${end - start == 1 ? 'character' : 'characters'}.',
          style: StudioText.caption(context).copyWith(color: s.textTertiary),
        ),
        SizedBox(height: StudioSpace.s),

        // ── The toolbar ─────────────────────────────────────────────────────
        //
        // Inside a [TextFieldTapRegion], which is what keeps the field focused
        // when one of these is pressed. Without it every press is a tap
        // *outside* the field as far as `EditableText` is concerned, so it
        // unfocuses: the keyboard drops, the selection highlight goes, and
        // bolding the phrase you had just selected means selecting it again
        // first.
        TextFieldTapRegion(
          child: Wrap(
            spacing: StudioSpace.xs,
            runSpacing: StudioSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StudioToolGroup(
                children: [
                  StudioIconButton(
                    icon: StudioIcons.bold,
                    tooltip: 'Bold',
                    selected: _isOn((r) => r.bold ?? spec.bold, spec.bold),
                    onPressed: () => _toggle(
                      read: (r) => r.bold ?? spec.bold,
                      base: spec.bold,
                      write: (r, v) => r.copyWith(bold: v),
                      clear: (r) => r.copyWith(clearBold: true),
                    ),
                  ),
                  StudioIconButton(
                    icon: StudioIcons.italic,
                    tooltip: 'Italic',
                    selected: _isOn(
                      (r) => r.italic ?? spec.italic,
                      spec.italic,
                    ),
                    onPressed: () => _toggle(
                      read: (r) => r.italic ?? spec.italic,
                      base: spec.italic,
                      write: (r, v) => r.copyWith(italic: v),
                      clear: (r) => r.copyWith(clearItalic: true),
                    ),
                  ),
                  StudioIconButton(
                    icon: StudioIcons.underline,
                    tooltip: 'Underline',
                    selected: _isOn(
                      (r) => r.underline ?? spec.underline,
                      spec.underline,
                    ),
                    onPressed: () => _toggle(
                      read: (r) => r.underline ?? spec.underline,
                      base: spec.underline,
                      write: (r, v) => r.copyWith(underline: v),
                      clear: (r) => r.copyWith(clearUnderline: true),
                    ),
                  ),
                ],
              ),
              StudioToolGroup(
                children: [
                  StudioIconButton(
                    icon: StudioIcons.remove,
                    tooltip: 'Smaller',
                    onPressed: () => _nudgeSize(-0.1),
                  ),
                  StudioNumericWell(
                    text: '${(scale * 100).round()}%',
                    width: 52,
                  ),
                  StudioIconButton(
                    icon: StudioIcons.add,
                    tooltip: 'Larger',
                    onPressed: () => _nudgeSize(0.1),
                  ),
                ],
              ),
              StudioToolGroup(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: StudioSpace.xs),
                    child: StudioSwatch(
                      color: ink,
                      size: 26,
                      tooltip: 'Colour',
                      onTap: _pickColour,
                    ),
                  ),
                  StudioIconButton(
                    icon: StudioIcons.font,
                    tooltip: 'Typeface',
                    onPressed: _pickFont,
                  ),
                  StudioIconButton(
                    icon: StudioIcons.clearFormat,
                    tooltip: 'Clear formatting',
                    onPressed: () => _apply(
                      (run) => run.copyWith(
                        clearColor: true,
                        clearSizeScale: true,
                        clearBold: true,
                        clearItalic: true,
                        clearUnderline: true,
                        clearFontFamily: true,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The caption as it will be painted, at panel scale, on the artwork's colour.
///
/// The read-only half of the pair the editor establishes: the panel shows what
/// the caption looks like and a tap opens the modal that changes it. A plain
/// [StudioTextField] cannot stand in for this — the whole point of a rich
/// caption is that its parts differ, and a field renders one style.
class CaptionRunsPreview extends StatelessWidget {
  const CaptionRunsPreview({
    super.key,
    required this.spec,
    required this.backdrop,
    this.onTap,
  });

  final CaptionSpec spec;
  final Color backdrop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    TextStyle styleFor(CaptionRun? run) => StudioFonts.style(
      run?.fontFamily ?? spec.fontFamily,
      fontSize: _kPreviewBaseSize * (run?.sizeScale ?? 1),
      color: run?.color ?? spec.color,
      fontWeight: (run?.bold ?? spec.bold)
          ? FontWeight.bold
          : FontWeight.normal,
      fontStyle: (run?.italic ?? spec.italic)
          ? FontStyle.italic
          : FontStyle.normal,
      decoration: (run?.underline ?? spec.underline)
          ? TextDecoration.underline
          : TextDecoration.none,
      decorationColor: run?.color ?? spec.color,
      height: 1.35,
    );

    final empty = spec.plainText.trim().isEmpty;

    return Material(
      color: backdrop,
      borderRadius: BorderRadius.circular(StudioRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: EdgeInsets.all(StudioSpace.m),
          alignment: spec.align.x < 0
              ? Alignment.centerLeft
              : spec.align.x > 0
              ? Alignment.centerRight
              : Alignment.center,
          child: empty
              ? Text(
                  'Type your text…',
                  style: styleFor(
                    null,
                  ).copyWith(color: spec.color.withValues(alpha: 0.45)),
                )
              : Text.rich(
                  TextSpan(
                    style: styleFor(null),
                    children: [
                      for (final run in spec.runs)
                        TextSpan(
                          text: spec.allUpCase
                              ? run.text.toUpperCase()
                              : run.text,
                          style: styleFor(run),
                        ),
                    ],
                  ),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  textAlign: spec.align.x < 0
                      ? TextAlign.left
                      : spec.align.x > 0
                      ? TextAlign.right
                      : TextAlign.center,
                ),
        ),
      ),
    );
  }
}
