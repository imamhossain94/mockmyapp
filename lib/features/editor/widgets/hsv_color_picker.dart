import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../shared/widgets/widgets.dart';
import 'scene_pick.dart';
import '../../../data/repositories/project_store.dart';
import '../../../domain/models/style_library.dart';
import '../../shared/project_scope.dart';

// -----------------------------------------------------------------------------
// Colour-space constants — deliberately NOT design tokens.
//
// The saturation/value field and the hue ramp are the user's *content*, not
// chrome: their stops are fixed points in colour space. Pure white and pure
// black must stay pure in both themes or the picker would lie about the colour
// being produced. The picker thumbs are pinned to the same two constants for
// the same reason — they sit on top of an arbitrary user colour, so they cannot
// follow the theme and stay legible.
// -----------------------------------------------------------------------------

const Color _kWhite = Color(0xFFFFFFFF);
const Color _kBlack = Color(0xFF000000);

const List<Color> _kHueStops = <Color>[
  Color(0xFFFF0000),
  Color(0xFFFFFF00),
  Color(0xFF00FF00),
  Color(0xFF00FFFF),
  Color(0xFF0000FF),
  Color(0xFFFF00FF),
  Color(0xFFFF0000),
];

/// Upper-cases as you type, preserving the caret.
///
/// `textCapitalization` is only a hint to the soft keyboard, so it does nothing
/// for a hardware one; without this a typed `aa3311` would sit in the field in
/// lower case until something else rewrote it.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => newValue.copyWith(text: newValue.text.toUpperCase());
}

/// Preset colours offered under the picker.
const _quickSwatches = [
  Color(0xFFFFFFFF),
  Color(0xFF000000),
  Color(0xFFEF4444),
  Color(0xFFF97316),
  Color(0xFFF2A93B),
  Color(0xFFEAB308),
  Color(0xFF22C55E),
  Color(0xFF14B8A6),
  Color(0xFF3B82F6),
  Color(0xFF5B5FEF),
  Color(0xFFA855F7),
  Color(0xFFEC4899),
];

/// Session-scoped recently-committed colours, newest first.
final List<Color> _recentColors = <Color>[];

const int _kMaxRecents = 8;

/// `RRGGBB`, uppercase. The picker has no alpha control, so alpha is never
/// surfaced here.
String _hexOf(Color c) =>
    c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

void _pushRecent(Color c) {
  final int argb = c.toARGB32();
  _recentColors.removeWhere((Color x) => x.toARGB32() == argb);
  _recentColors.insert(0, c);
  if (_recentColors.length > _kMaxRecents) {
    _recentColors.removeRange(_kMaxRecents, _recentColors.length);
  }
}

/// A Photoshop-style colour picker: a saturation/value field, a hue ramp, an
/// editable HEX readout and a strip of preset / recent swatches.
///
/// The colour maths and the [onChanged] contract are unchanged — every
/// interaction emits the live [Color] as the user drags.
///
/// **There is deliberately no alpha control.** Emitted colours flow straight
/// onto the document (background fills, caption colours, screenshot stroke and
/// shadow) and therefore into exported pixels, so alpha editing would be a new
/// document-mutating feature rather than a visual change. Alpha is passed
/// through untouched from the incoming [color]; committing a preset swatch or a
/// HEX entry resets it to opaque, exactly as it always has.
class HsvColorPicker extends ConsumerStatefulWidget {
  const HsvColorPicker({
    super.key,
    required this.color,
    required this.onChanged,
    this.projectId,
  });

  final Color color;
  final ValueChanged<Color> onChanged;

  /// The project whose saved colours to offer, if there is one in scope.
  ///
  /// Defaults to whatever [ProjectScope] publishes, which is how the seven
  /// call sites that never took a project id keep working without gaining a
  /// parameter they have no other use for.
  ///
  /// Null — no scope and none given — hides the whole section rather than
  /// showing an empty one: this picker is also opened where there is genuinely
  /// no project, and a "Saved" header with nothing under it and no way to add
  /// anything is worse than no header.
  final String? projectId;

  @override
  ConsumerState<HsvColorPicker> createState() => _HsvColorPickerState();
}

class _HsvColorPickerState extends ConsumerState<HsvColorPicker> {
  late HSVColor _hsv = HSVColor.fromColor(widget.color);
  late final TextEditingController _hexController = TextEditingController(
    text: _hexOf(widget.color),
  );

  /// Whether the in-app hex keypad is showing.
  bool _hexPad = false;

  /// Whether the next keypad press starts a new code rather than appending.
  ///
  /// Stands in for "the text is selected", which a field driven by a custom
  /// keypad has no way to express.
  bool _hexReplace = false;

  /// The project whose saved colours this picker offers: the one it was given,
  /// or the one the surrounding screen published.
  String? get _projectId => widget.projectId ?? ProjectScope.of(context);

  /// Adopts a colour set from outside — an eyedropper pick, a preset applied by
  /// the panel around this picker, an undo.
  ///
  /// Guarded on the value actually differing, not just on the widget having
  /// been rebuilt: during a drag the parent echoes back the exact colour this
  /// picker just emitted, and re-deriving HSV from it would throw away the hue
  /// every time saturation or value passes through zero, where a colour no
  /// longer carries one.
  @override
  void didUpdateWidget(HsvColorPicker old) {
    super.didUpdateWidget(old);
    if (widget.color.toARGB32() == old.color.toARGB32()) return;
    if (widget.color.toARGB32() == _hsv.toColor().toARGB32()) return;
    setState(() {
      _hsv = HSVColor.fromColor(widget.color);
      _setHexText(_hexOf(widget.color));
    });
  }

  void _emit(HSVColor next) {
    setState(() {
      _hsv = next;
      _setHexText(_hexOf(next.toColor()));
    });
    widget.onChanged(next.toColor());
  }

  /// Writes the readout without disturbing a caret that is already in the right
  /// place.
  ///
  /// Assigning to `TextEditingController.text` collapses the selection to
  /// offset zero. Typing the sixth character of a hex code applies it, which
  /// comes straight back here — so without this guard the caret would jump to
  /// the front of the field on the last keystroke of every code.
  void _setHexText(String value) {
    if (_hexController.text == value) return;
    _hexController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  /// Applies a committed colour (swatch tap / hex entry) and records it in the
  /// recents strip.
  void _commit(HSVColor next) {
    _pushRecent(next.toColor());
    _emit(next);
  }

  /// Arms the canvas eyedropper and gets out of its way.
  ///
  /// "Out of the way" depends on where this picker is. Opened as a modal it is
  /// covering the artwork the colour has to be lifted from — on a phone it *is*
  /// the screen — so it dismisses itself. Embedded inline in a panel (the solid
  /// background fill, the screenshot stroke) it is beside the canvas rather than
  /// over it, and popping there would take the whole editor route down with it.
  ///
  /// Hence the [PopupRoute] test rather than a bare `maybePop`: sheets, dialogs
  /// and side sheets are all popup routes, and the editor page is not.
  ///
  /// What gets armed is [HsvColorPicker.onChanged] — the panel's own setter,
  /// which outlives a dismissed sheet — and not `_commit`, which would call
  /// `setState` on a disposed state in exactly the modal case.
  void _pickFromScene() {
    final onChanged = widget.onChanged;
    ref.read(scenePickProvider.notifier).begin((color) {
      // Top-level, so the recents strip still records the pick even when the
      // picker that made it no longer exists.
      _pushRecent(color);
      onChanged(color);
    });
    if (ModalRoute.of(context) case final PopupRoute route) {
      Navigator.of(context).removeRoute(route);
    }
  }

  void _submitHex(String v) {
    final hex = int.tryParse(v, radix: 16);
    if (hex != null && v.length == 6) {
      // A 6-digit entry carries no alpha, so the result is opaque.
      _commit(HSVColor.fromColor(Color(0xFF000000 | hex)));
    } else {
      // Round-trip: an unparseable entry snaps back to the live colour.
      _setHexText(_hexOf(_hsv.toColor()));
    }
  }

  // ---------------------------------------------------------------------------
  // Hex keypad
  //
  // A hex code is six characters drawn from sixteen, and the system keyboard
  // offers a hundred-odd — most of them impossible here, none of A–F reachable
  // without a shift on a numeric layout, and the whole slab covers the colour
  // field you are trying to match. Sixteen keys, a delete and a done fit in
  // three slim rows and never hide the picker.
  // ---------------------------------------------------------------------------

  /// Opens the pad, leaving the current code on screen.
  ///
  /// The field always holds a full six characters, so the next key has to start
  /// a new code rather than append to a complete one. That used to be done by
  /// emptying the field on open, which read as the colour vanishing the moment
  /// you touched it — you could no longer see what you were replacing, and a
  /// mis-tap left you with nothing to go back to.
  ///
  /// The value stays; [_hexReplace] makes the first key overwrite it, which is
  /// what selecting the text and typing does everywhere else.
  void _openHexPad() {
    HapticFeedback.selectionClick();
    setState(() {
      _hexPad = true;
      _hexReplace = true;
    });
  }

  void _closeHexPad() {
    final text = _hexController.text;
    setState(() {
      _hexPad = false;
      _hexReplace = false;
    });
    // Anything short of six characters is not a colour; snap back rather than
    // leaving a truncated code sitting in the readout.
    if (text.length == 6) {
      _submitHex(text);
    } else {
      _setHexText(_hexOf(_hsv.toColor()));
    }
  }

  void _hexKey(String digit) {
    // The first key after opening the pad replaces the code that is showing;
    // everything after it appends to what has been typed so far.
    final base = _hexReplace ? '' : _hexController.text;
    if (base.length >= 6) return;
    HapticFeedback.selectionClick();
    final next = base + digit;
    setState(() {
      _hexReplace = false;
      _setHexText(next);
    });
    // Applied the moment it is a whole colour, so the field and the swatch
    // above agree without a separate confirm step.
    if (next.length == 6) _submitHex(next);
  }

  void _hexBackspace() {
    // Backspacing a code that is still showing whole clears it, rather than
    // silently lopping a character off a colour the user has not started
    // editing yet.
    final text = _hexReplace ? '' : _hexController.text;
    if (text.isEmpty && !_hexReplace) return;
    HapticFeedback.selectionClick();
    setState(() {
      _hexReplace = false;
      _setHexText(text.isEmpty ? '' : text.substring(0, text.length - 1));
    });
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final pureHue = HSVColor.fromAHSV(1, _hsv.hue, 1, 1).toColor();
    final current = _hsv.toColor();
    final opaque = current.withValues(alpha: 1);

    /// Whether a hex code can simply be typed.
    ///
    /// Read from the platform's primary input rather than from the window size:
    /// the custom keypad exists to keep the *system keyboard* off the colour
    /// field, and a desktop has no system keyboard to keep off it.
    final typed = context.layout.hasPointer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // --- Saturation / value field -----------------------------------
        AspectRatio(
          aspectRatio: 2.6,
          child: LayoutBuilder(
            builder: (context, constraints) {
              void updateFromLocal(Offset local) {
                final sat = (local.dx / constraints.maxWidth).clamp(0.0, 1.0);
                final val =
                    1 - (local.dy / constraints.maxHeight).clamp(0.0, 1.0);
                _emit(_hsv.withSaturation(sat).withValue(val));
              }

              final radius = BorderRadius.circular(StudioRadius.xs);

              return GestureDetector(
                onPanDown: (d) => updateFromLocal(d.localPosition),
                onPanUpdate: (d) => updateFromLocal(d.localPosition),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            colors: <Color>[_kWhite, pureHue],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[Color(0x00000000), _kBlack],
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: radius,
                            // Gradient-area frame is content: a soft edge so the
                            // colour field reads against the panel behind it.
                            border: Border.all(color: s.borderSubtle),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: _hsv.saturation * constraints.maxWidth - 9,
                      top: (1 - _hsv.value) * constraints.maxHeight - 9,
                      child: IgnorePointer(child: _SvThumb(color: opaque)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        SizedBox(height: StudioSpace.l),

        // --- Hue ramp ----------------------------------------------------
        _PickerRamp(
          gradient: const LinearGradient(colors: _kHueStops),
          position: _hsv.hue / 360,
          onChanged: (t) => _emit(_hsv.withHue(t * 360)),
        ),
        SizedBox(height: StudioSpace.l),

        // --- HEX readout -------------------------------------------------
        Row(
          children: [
            StudioSwatch(
              color: current,
              size: 24,
              tooltip: '#${_hexOf(current)}',
            ),
            Expanded(
              child: typed
                  // A hardware keyboard is present, so the reason the custom
                  // pad exists — the system keyboard covering the colour field
                  // — does not apply. An ordinary field gets an ordinary caret
                  // you can click into and drag a selection across, which is
                  // what a hex code being *edited* rather than retyped needs.
                  ? StudioTextField(
                      controller: _hexController,
                      icon: StudioIcons.hex,
                      hint: 'RRGGBB',
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp('[0-9a-fA-F]'),
                        ),
                        LengthLimitingTextInputFormatter(6),
                        _UpperCaseFormatter(),
                      ],
                      onChanged: (v) {
                        // Applied as soon as it is a whole colour, matching the
                        // keypad. Anything shorter is a code mid-typing.
                        if (v.length == 6) _submitHex(v);
                      },
                      onSubmitted: _submitHex,
                    )
                  // Touch: the app's own keypad supplies the characters, so the
                  // system keyboard never opens over the colour field.
                  : StudioTextField(
                      controller: _hexController,
                      icon: StudioIcons.hex,
                      hint: 'RRGGBB',
                      readOnly: true,
                      showCursor: true,
                      onTap: _openHexPad,
                    ),
            ),
            if (_hexPad) ...[
              SizedBox(width: StudioSpace.xs),
              StudioIconButton(
                icon: StudioIcons.collapse,
                iconSize: 13,
                tooltip: 'Close keypad',
                onPressed: _closeHexPad,
              ),
            ],
            // Only where there is a canvas behind this picker to sample.
            if (ref.watch(scenePickProvider).available) ...[
              SizedBox(width: StudioSpace.xs),
              StudioIconButton(
                icon: StudioIcons.dropper,
                iconSize: 15,
                tooltip: 'Pick a colour from the canvas',
                onPressed: _pickFromScene,
              ),
            ],
          ],
        ),
        if (_hexPad) ...[
          SizedBox(height: StudioSpace.m),
          _HexKeypad(
            onKey: _hexKey,
            onBackspace: _hexBackspace,
            onClear: () => setState(_hexController.clear),
            onDone: _closeHexPad,
          ),
        ],
        SizedBox(height: StudioSpace.l),

        // --- Quick picks ---------------------------------------------------
        // Not "Presets": the picker is embedded in panels that carry their own
        // preset library (background solids, for one), and two eyebrows reading
        // Presets on one screen leave no way to tell which list is which.
        const StudioSectionHeader(label: 'Quick picks'),
        SizedBox(height: StudioSpace.xs),
        _SwatchGrid(
          colors: _quickSwatches,
          current: current,
          onPick: (c) => _commit(HSVColor.fromColor(c)),
        ),

        // --- Saved -------------------------------------------------------
        //
        // Above Recents on purpose. Recents are what you happened to touch;
        // saved colours are what the project has decided it is, and the second
        // is the one you reach for on the fourth screen of a set.
        if (_projectId != null) ...[
          SizedBox(height: StudioSpace.m),
          _SavedColors(
            projectId: _projectId!,
            current: current,
            onPick: (c) => _emit(HSVColor.fromColor(c)),
          ),
        ],

        // --- Recents -----------------------------------------------------
        if (_recentColors.isNotEmpty) ...[
          SizedBox(height: StudioSpace.m),
          const StudioSectionHeader(label: 'Recent'),
          SizedBox(height: StudioSpace.xs),
          _SwatchGrid(
            colors: _recentColors,
            current: current,
            onPick: (c) => _emit(HSVColor.fromColor(c)),
          ),
        ],
      ],
    );
  }
}

/// The in-app hex keypad: sixteen digits, a delete and a done, in three rows.
///
/// Six columns is what makes it slim — `0-5 / 6-B / C-F ⌫ ✓` puts every
/// character one tap away without the pad ever being taller than the colour
/// field it sits under. A recessed `well` tray with raised `panelAlt` keys, the
/// same two-step tonal separation the segmented control uses.
class _HexKeypad extends StatelessWidget {
  const _HexKeypad({
    required this.onKey,
    required this.onBackspace,
    required this.onClear,
    required this.onDone,
  });

  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final VoidCallback onDone;

  static const List<String> _digits = <String>[
    '0', '1', '2', '3', '4', '5', //
    '6', '7', '8', '9', 'A', 'B', //
    'C', 'D', 'E', 'F', //
  ];

  static const int _columns = 6;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;

    Widget row(List<Widget> keys) => Row(
      children: <Widget>[
        for (var i = 0; i < keys.length; i++) ...[
          if (i > 0) SizedBox(width: StudioSpace.xs),
          Expanded(child: keys[i]),
        ],
      ],
    );

    return Container(
      padding: EdgeInsets.all(StudioSpace.xs),
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.md),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          row(<Widget>[
            for (final d in _digits.sublist(0, _columns))
              _HexKey(label: d, onTap: () => onKey(d)),
          ]),
          SizedBox(height: StudioSpace.xs),
          row(<Widget>[
            for (final d in _digits.sublist(_columns, _columns * 2))
              _HexKey(label: d, onTap: () => onKey(d)),
          ]),
          SizedBox(height: StudioSpace.xs),
          row(<Widget>[
            for (final d in _digits.sublist(_columns * 2))
              _HexKey(label: d, onTap: () => onKey(d)),
            _HexKey(
              icon: StudioIcons.back,
              tooltip: 'Delete — hold to clear',
              onTap: onBackspace,
              onLongPress: onClear,
            ),
            _HexKey(
              icon: StudioIcons.check,
              tooltip: 'Done',
              accent: true,
              onTap: onDone,
            ),
          ]),
        ],
      ),
    );
  }
}

/// One key. Either a character or a glyph, never both.
class _HexKey extends StatelessWidget {
  const _HexKey({
    this.label,
    this.icon,
    this.tooltip,
    this.accent = false,
    required this.onTap,
    this.onLongPress,
  });

  final String? label;
  final StudioIconData? icon;
  final String? tooltip;

  /// Fills with `accent` — reserved for the confirm key.
  final bool accent;

  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  static const double height = 34;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final fg = accent ? s.onAccent : s.textPrimary;

    Widget key = Material(
      color: accent ? s.accent : s.panelAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StudioRadius.sm),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: s.hoverBg,
        highlightColor: s.hoverBg,
        splashColor: s.hoverBg,
        child: SizedBox(
          height: height,
          child: Center(
            child: icon != null
                ? StudioIcon(icon!, size: 13, color: fg)
                : Text(
                    label!,
                    // Mono, because a hex code is a fixed-width value and the
                    // keys should read as the same alphabet as the field.
                    style: StudioText.mono(
                      context,
                    ).copyWith(color: fg, fontSize: 14),
                  ),
          ),
        ),
      ),
    );

    if (tooltip != null) key = Tooltip(message: tooltip!, child: key);
    return key;
  }
}

/// A wrapping row of [StudioSwatch]es.
class _SwatchGrid extends StatelessWidget {
  const _SwatchGrid({
    required this.colors,
    required this.current,
    required this.onPick,
  });

  final List<Color> colors;
  final Color current;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    final int currentArgb = current.withValues(alpha: 1).toARGB32();
    return Wrap(
      children: <Widget>[
        for (final Color c in colors)
          StudioSwatch(
            color: c,
            size: 28,
            selected: c.withValues(alpha: 1).toARGB32() == currentArgb,
            tooltip: '#${_hexOf(c)}',
            onTap: () => onPick(c),
          ),
      ],
    );
  }
}

/// A horizontal 1-D ramp: radius `xs`, 1px `border`, and a draggable handle.
class _PickerRamp extends StatelessWidget {
  const _PickerRamp({
    required this.gradient,
    required this.position,
    required this.onChanged,
  });

  /// The ramp fill. Colour-space content, never a decorative gradient.
  final Gradient gradient;

  /// Handle position in `[0, 1]`.
  final double position;

  /// Fires continuously while dragging with the normalised position.
  final ValueChanged<double> onChanged;

  static const double height = 16;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final radius = BorderRadius.circular(StudioRadius.xs);

    return LayoutBuilder(
      builder: (context, constraints) {
        void update(Offset local) =>
            onChanged((local.dx / constraints.maxWidth).clamp(0.0, 1.0));

        return GestureDetector(
          onPanDown: (d) => update(d.localPosition),
          onPanUpdate: (d) => update(d.localPosition),
          child: SizedBox(
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: radius,
                    child: DecoratedBox(
                      decoration: BoxDecoration(gradient: gradient),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        // Hue-ramp frame is content: a soft edge, not a chrome
                        // outline.
                        border: Border.all(color: s.borderSubtle),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: position.clamp(0.0, 1.0) * constraints.maxWidth - 5,
                  top: -3,
                  child: const IgnorePointer(child: _RampThumb()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The saturation/value handle: a filled dot ringed in white then black so it
/// stays visible against every corner of the field.
class _SvThumb extends StatelessWidget {
  const _SvThumb({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: _kWhite, width: 2),
      ),
      child: const DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.fromBorderSide(BorderSide(color: _kBlack)),
        ),
      ),
    );
  }
}

/// The ramp handle: a slim white bar with a black hairline, overhanging the
/// ramp top and bottom so it reads at 16px.
class _RampThumb extends StatelessWidget {
  const _RampThumb();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: _PickerRamp.height + 6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(StudioRadius.xs),
        border: Border.all(color: _kWhite, width: 2),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(StudioRadius.xs - 2),
          border: const Border.fromBorderSide(BorderSide(color: _kBlack)),
        ),
      ),
    );
  }
}

/// The project's named colours, with the one way to add another.
///
/// A saved colour is a name and a value on the project — see [ColorStyle] — so
/// the same brand blue is one tap away on every screen instead of a hex code
/// somebody has to remember. Unlike a text style it does not push: a colour has
/// no instances to rewrite, because what a caption or a shape holds is the
/// colour itself.
class _SavedColors extends ConsumerWidget {
  const _SavedColors({
    required this.projectId,
    required this.current,
    required this.onPick,
  });

  final String projectId;
  final Color current;
  final ValueChanged<Color> onPick;

  Future<void> _save(BuildContext context, WidgetRef ref) async {
    final name = await showStudioPrompt(
      context,
      title: 'Save colour',
      label: 'Name',
      initial: 'Brand',
    );
    if (name == null) return;
    ref
        .read(projectStoreProvider.notifier)
        .saveColorStyle(
          projectId,
          ColorStyle(
            id: 'col-${DateTime.now().microsecondsSinceEpoch}',
            name: name,
            color: current,
          ),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = context.studio;
    final saved =
        ref
            .watch(projectStoreProvider)
            .where((p) => p.id == projectId)
            .firstOrNull
            ?.styles
            .colors ??
        const <ColorStyle>[];
    final already = saved.any((c) => c.color.toARGB32() == current.toARGB32());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: StudioSectionHeader(label: 'Saved')),
            StudioIconButton(
              icon: StudioIcons.add,
              iconSize: 13,
              tooltip: already
                  ? 'This colour is already saved'
                  : 'Save this colour to the project',
              onPressed: already ? null : () => _save(context, ref),
            ),
          ],
        ),
        SizedBox(height: StudioSpace.xs),
        if (saved.isEmpty)
          Text(
            'Save a colour here to reuse it across the project.',
            style: StudioText.caption(context).copyWith(color: s.textTertiary),
          )
        else
          Wrap(
            spacing: StudioSpace.s,
            runSpacing: StudioSpace.s,
            children: [
              for (final style in saved)
                StudioSwatch(
                  color: style.color,
                  size: 28,
                  selected: style.color.toARGB32() == current.toARGB32(),
                  // The name, not the hex: that is the whole point of saving
                  // it, and it is what a screen reader reads out.
                  semanticLabel: style.name,
                  tooltip: style.name,
                  onTap: () => onPick(style.color),
                ),
            ],
          ),
      ],
    );
  }
}
