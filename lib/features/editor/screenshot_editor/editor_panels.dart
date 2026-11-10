part of 'screenshot_editor_screen.dart';

/// Each tool's panel.
///
/// Built here rather than as widgets with a dozen callbacks each: every panel
/// is a few rows of the shared controls in `editor_chrome.dart`, wired straight
/// to the screen's own methods, and reading them top to bottom is reading what
/// the tool can do.
extension _Panels on _ScreenshotEditorScreenState {
  Widget _panelFor(PhotoTool tool) => switch (tool) {
    PhotoTool.crop => _cropPanel(),
    PhotoTool.adjust => _adjustPanel(),
    PhotoTool.filters => _filtersPanel(),
    PhotoTool.draw => _drawPanel(),
    PhotoTool.text => _textPanel(),
    PhotoTool.stickers => _stickersPanel(),
    PhotoTool.hide => _hidePanel(),
    PhotoTool.cutout => _cutoutPanel(),
  };

  static String _degrees(double v) => '${v.round()}°';
  static String _percent(double v) => '${v > 0 ? '+' : ''}${(v * 100).round()}';

  Widget _rows(List<Widget> rows) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (final (i, row) in rows.indexed) ...[
        if (i > 0) SizedBox(height: StudioSpace.m),
        row,
      ],
    ],
  );

  // ---------------------------------------------------------------------------
  // Crop
  // ---------------------------------------------------------------------------

  Widget _cropPanel() {
    final o = _orientation;
    const ratios = <(String, double)>[
      ('1:1', 1.0),
      ('4:5', 0.8),
      ('3:4', 0.75),
      ('9:16', 9 / 16),
      ('16:9', 16 / 9),
    ];
    return _rows([
      _Strip(
        children: [
          _Choice(
            label: 'Rotate',
            icon: StudioIcons.rotateLeft,
            selected: false,
            onTap: () => _reorient(o.rotated(-1)),
          ),
          _Choice(
            label: 'Flip',
            icon: StudioIcons.flipHorizontal,
            selected: o.flipH,
            onTap: () => _reorient(o.copyWith(flipH: !o.flipH)),
          ),
          _Choice(
            label: 'Flip vertical',
            icon: StudioIcons.flipVertical,
            selected: o.flipV,
            onTap: () => _reorient(o.copyWith(flipV: !o.flipV)),
          ),
          _Choice(
            label: 'Reset',
            icon: StudioIcons.reset,
            selected: false,
            onTap: _resetCrop,
          ),
        ],
      ),
      _ValueSlider(
        label: 'Straighten',
        value: o.angle,
        min: -45,
        max: 45,
        origin: 0,
        display: _degrees,
        onChanged: _straighten,
        onChangeEnd: (_) => _update(_flushLive),
        onReset: () => _reorient(o.copyWith(angle: 0)),
      ),
      _Strip(
        children: [
          _Choice(
            label: _frameLabel,
            icon: StudioIcons.ratioLocked,
            selected: _cropLocked && _aspectOverride == null,
            onTap: () => _setAspect(null),
          ),
          _Choice(
            label: 'Free',
            icon: StudioIcons.ratioFree,
            selected: !_cropLocked,
            onTap: _setFreeCrop,
          ),
          for (final (label, value) in ratios)
            _Choice(
              label: label,
              selected: _cropLocked && _aspectOverride == value,
              onTap: () => _setAspect(value),
            ),
          _Choice(
            label: 'Extend',
            icon: StudioIcons.scale,
            selected: _expand,
            onTap: () => _setExpand(!_expand),
          ),
        ],
      ),
      if (_expand)
        _Strip(
          children: [
            for (final (fill, label) in const [
              (ExpandFill.edge, 'Stretch edges'),
              (ExpandFill.mirror, 'Mirror'),
              (ExpandFill.blur, 'Blur'),
              (ExpandFill.solid, 'Colour'),
            ])
              _Choice(
                label: label,
                selected: _fill == fill,
                onTap: () => _update(() {
                  _record();
                  _fill = fill;
                }),
              ),
          ],
        ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Adjust
  // ---------------------------------------------------------------------------

  Widget _adjustPanel() {
    final control = _adjustControl;
    final value = control.of(_adjust);
    final anything = _adjust != _adjust.withoutSliders();
    return _rows([
      _Strip(
        children: [
          _Choice(
            label: 'Auto',
            icon: StudioIcons.filters,
            selected: false,
            onTap: _autoEnhance,
          ),
          for (final c in AdjustControl.values)
            _Choice(
              label: c.label,
              icon: c.icon,
              selected: c == control,
              marked: c.of(_adjust) != 0,
              onTap: () => _update(() => _adjustControl = c),
            ),
          if (anything)
            _Choice(
              label: 'Reset all',
              icon: StudioIcons.reset,
              selected: false,
              onTap: () => _setAdjustNow(_adjust.withoutSliders()),
            ),
        ],
      ),
      _ValueSlider(
        label: control.label,
        value: value,
        min: control.min,
        max: 1,
        origin: 0,
        display: _percent,
        onChanged: (v) => _setAdjust(control.set(_adjust, v)),
        onChangeEnd: (_) => _update(_flushLive),
        onReset: () => _setAdjustNow(control.set(_adjust, 0)),
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Filters
  // ---------------------------------------------------------------------------

  Widget _filtersPanel() {
    final current = _adjust.look;
    return _rows([
      Builder(
        builder: (context) {
          final tiles = [
            for (final look in PhotoFilter.values)
              _filterTile(context, look, selected: look == current),
          ];
          if (_WrapStrips.of(context)) {
            return Wrap(
              spacing: StudioSpace.m,
              runSpacing: StudioSpace.m,
              children: tiles,
            );
          }
          return SizedBox(
            height: 84,
            child: ScrollConfiguration(
              behavior: const _DragAnything(),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: tiles.length,
                separatorBuilder: (_, _) => SizedBox(width: StudioSpace.m),
                itemBuilder: (_, i) => tiles[i],
              ),
            ),
          );
        },
      ),
      if (current != PhotoFilter.none)
        _ValueSlider(
          label: 'Strength',
          value: _adjust.lookStrength,
          min: 0,
          max: 1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => _setAdjust(_adjust.copyWith(lookStrength: v)),
          onChangeEnd: (_) => _update(_flushLive),
        ),
    ]);
  }

  /// One look, previewed on the photo itself.
  Widget _filterTile(
    BuildContext context,
    PhotoFilter look, {
    required bool selected,
  }) {
    final s = context.studio;
    final thumb = _thumb;
    return Semantics(
      button: true,
      selected: selected,
      label: look.label,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          _setAdjustNow(_adjust.copyWith(look: look, lookStrength: 1));
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 64,
              decoration: BoxDecoration(
                color: s.well,
                borderRadius: BorderRadius.circular(StudioRadius.md),
                border: Border.all(
                  color: selected ? s.accent : Colors.transparent,
                  width: 2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: thumb == null
                  ? null
                  : ColorFiltered(
                      colorFilter: look.matrix.toFilter(),
                      child: RawImage(
                        image: thumb,
                        fit: BoxFit.cover,
                        // A tall screenshot's middle is often a plain
                        // background; its top has the colour a look can be
                        // judged by.
                        alignment: thumb.height > thumb.width * 1.3
                            ? const Alignment(0, -0.7)
                            : Alignment.center,
                      ),
                    ),
            ),
            SizedBox(height: StudioSpace.xs),
            Text(
              look.label,
              style: StudioText.micro(
                context,
              ).copyWith(color: selected ? s.accent : s.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Draw
  // ---------------------------------------------------------------------------

  Widget _drawPanel() {
    final erasing = _drawTool == DrawTool.eraser;
    return _rows([
      _Strip(
        children: [
          for (final t in DrawTool.values)
            _Choice(
              label: t.label,
              icon: t.icon,
              selected: t == _drawTool,
              iconOnly: t != _drawTool,
              onTap: () => _update(() => _drawTool = t),
            ),
        ],
      ),
      if (erasing)
        const _Hint('Drag across a drawing to rub it out.')
      else
        _ColourRow(
          color: _drawColor,
          onPick: (c) => _update(() => _drawColor = c),
          dropperArmed: _picking == _PickFor.draw,
          onDropper: () => _armPicker(_PickFor.draw),
          onCustom: () =>
              _customColour(_drawColor, (c) => _update(() => _drawColor = c)),
        ),
      if (!erasing)
        _ValueSlider(
          label: 'Size',
          value: _drawWidth,
          min: 0.003,
          max: 0.05,
          display: (v) => '${(v * 1000).round()}',
          onChanged: (v) => _update(() => _drawWidth = v),
        ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Text
  // ---------------------------------------------------------------------------

  Widget _textPanel() {
    final op = _selectedText;
    if (op == null) {
      return _rows([
        StudioButton(
          label: 'Add text',
          icon: StudioIcons.add,
          fullWidth: true,
          variant: StudioButtonVariant.primary,
          onPressed: _addText,
        ),
        const _Hint(
          'Tap a text to select it, tap it again to change the words. Drag a '
          'corner to resize it, the dot above it to turn it.',
        ),
      ]);
    }
    final alignIcon = switch (op.align) {
      TextAlign.left => StudioIcons.textAlignLeft,
      TextAlign.right => StudioIcons.textAlignRight,
      _ => StudioIcons.textAlignCenter,
    };
    final nextAlign = switch (op.align) {
      TextAlign.left => TextAlign.center,
      TextAlign.center => TextAlign.right,
      _ => TextAlign.left,
    };
    final onAccent = _onAccent(op);
    return _rows([
      _Strip(
        children: [
          _Choice(
            label: 'Edit',
            icon: StudioIcons.edit,
            selected: false,
            onTap: () => _editWords(op),
          ),
          _Choice(
            label: StudioFonts.displayName(op.fontFamily),
            icon: StudioIcons.font,
            selected: false,
            onTap: _pickFont,
          ),
          _Choice(
            label: 'Bold',
            icon: StudioIcons.bold,
            selected: op.bold,
            iconOnly: true,
            onTap: () => _styleText((o) => o.copyWith(bold: !o.bold)),
          ),
          _Choice(
            label: 'Align',
            icon: alignIcon,
            selected: false,
            iconOnly: true,
            onTap: () => _styleText((o) => o.copyWith(align: nextAlign)),
          ),
          _Choice(
            label: 'Delete',
            icon: StudioIcons.delete,
            selected: false,
            iconOnly: true,
            onTap: _deleteSelected,
          ),
          _Choice(
            label: 'Duplicate',
            icon: StudioIcons.duplicate,
            selected: false,
            iconOnly: true,
            onTap: _duplicateSelected,
          ),
        ],
      ),
      _Strip(
        children: [
          for (final (look, label) in const [
            (TextLook.plain, 'Plain'),
            (TextLook.box, 'Box'),
            (TextLook.outline, 'Outline'),
            (TextLook.shadow, 'Shadow'),
          ])
            _Choice(
              label: label,
              selected: op.look == look,
              onTap: () => _styleText((o) => _withLook(o, look)),
            ),
        ],
      ),
      _ColourRow(
        leading: op.look.hasAccent
            ? _ColourTarget(
                accentLabel: op.look == TextLook.box ? 'Box' : 'Outline',
                text: op.color,
                accent: op.accent,
                onAccent: onAccent,
                onChanged: (v) => _update(() => _textAccent = v),
              )
            : null,
        color: onAccent ? op.accent : op.color,
        onPick: (c) => _styleText((o) => _recolourText(o, c)),
        dropperArmed: _picking == _PickFor.text,
        onDropper: () => _armPicker(_PickFor.text),
        onCustom: () => _customColour(
          onAccent ? op.accent : op.color,
          (c) => _styleText((o) => _recolourText(o, c)),
        ),
      ),
    ]);
  }

  // ---------------------------------------------------------------------------
  // Stickers
  // ---------------------------------------------------------------------------

  Widget _stickersPanel() {
    final op = _selected;
    final adders = [
      _Choice(
        label: 'Elements',
        icon: StudioIcons.shapes,
        selected: false,
        onTap: _placeElement,
      ),
      _Choice(
        label: 'Clip art',
        icon: StudioIcons.stickers,
        selected: false,
        onTap: _placeSticker,
      ),
      _Choice(
        label: 'Image',
        icon: StudioIcons.image,
        selected: false,
        onTap: _placeImage,
      ),
    ];
    if (op == null || op is TextOp) {
      return _rows([
        _Strip(children: adders),
        const _Hint(
          'Add an element, clip art or a picture. Drag it into place; a corner '
          'resizes it, a side stretches it — or crops a picture.',
        ),
      ]);
    }
    return _rows([
      _Strip(
        children: [
          _Choice(
            label: 'Add',
            icon: StudioIcons.add,
            selected: false,
            // Back to the list of things to add; the selection has the rest
            // of the row.
            onTap: () => _update(() => _selectedId = null),
          ),
          _Choice(
            label: 'Delete',
            icon: StudioIcons.delete,
            selected: false,
            iconOnly: true,
            onTap: _deleteSelected,
          ),
          _Choice(
            label: 'Duplicate',
            icon: StudioIcons.duplicate,
            selected: false,
            iconOnly: true,
            onTap: _duplicateSelected,
          ),
          if (op is ImageOp || op is StickerOp)
            _Choice(
              label: 'Flip',
              icon: StudioIcons.flipHorizontal,
              selected: false,
              iconOnly: true,
              onTap: _flipSelected,
            ),
          // Named: on their own, these chevrons read as expand and collapse.
          _Choice(
            label: 'Back',
            icon: StudioIcons.sendBackward,
            selected: false,
            onTap: () => _restackSelected(toFront: false),
          ),
          _Choice(
            label: 'Front',
            icon: StudioIcons.bringForward,
            selected: false,
            onTap: () => _restackSelected(toFront: true),
          ),
        ],
      ),
      if (op is ImageOp) ..._imageRows(op),
      if (op is ShapeOp)
        _ColourRow(
          color: op.spec.fill,
          onPick: _recolourSelected,
          dropperArmed: _picking == _PickFor.object,
          onDropper: () => _armPicker(_PickFor.object),
          onCustom: () => _customColour(op.spec.fill, _recolourSelected),
        )
      else if (op is StickerOp && _isTintable(op))
        _ColourRow(
          // Untinted art is in the colour it was drawn in, which no swatch
          // claims to be.
          color: op.tint,
          onPick: _recolourSelected,
          dropperArmed: _picking == _PickFor.object,
          onDropper: () => _armPicker(_PickFor.object),
          onCustom: () => _customColour(
            op.tint ?? const Color(0xFF111111),
            _recolourSelected,
          ),
        ),
      if (op is! ImageOp)
        _ValueSlider(
          label: 'Opacity',
          value: op.opacity,
          min: 0.05,
          max: 1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) =>
              _editSelectedLive((o) => o.withPlacement(opacity: v)),
          onChangeEnd: (_) => _update(_flushLive),
        ),
    ]);
  }

  /// A selected picture's settings: which one, then its control.
  List<Widget> _imageRows(ImageOp op) {
    final property = _imageProperty;
    // The largest radius and rim the box can take, in the photo-width units
    // both are stored in.
    final shortSide = math.min(op.width, op.height);
    final maxRadius = shortSide / 2;
    final maxBorder = shortSide * 0.15;
    void editImage(ImageOp Function(ImageOp) change, {bool live = false}) {
      PlacedOp apply(PlacedOp o) => o is ImageOp ? change(o) : o;
      live ? _editSelectedLive(apply) : _editSelected(apply);
    }

    const ratios = <(String, double?)>[
      ('Original', null),
      ('1:1', 1),
      ('4:5', 0.8),
      ('3:4', 0.75),
      ('9:16', 9 / 16),
      ('16:9', 16 / 9),
    ];
    return [
      _Strip(
        children: [
          for (final p in _ImageProperty.values)
            _Choice(
              label: p.label,
              icon: p.icon,
              selected: p == property,
              marked: switch (p) {
                _ImageProperty.crop => op.isCropped,
                _ImageProperty.corners => op.cornerRadius > 0,
                _ImageProperty.border => op.borderWidth > 0,
                _ImageProperty.borderColour => false,
                _ImageProperty.opacity => op.opacity < 1,
              },
              onTap: () => _update(() => _imageProperty = p),
            ),
        ],
      ),
      switch (property) {
        _ImageProperty.crop => _Strip(
          children: [
            for (final (label, aspect) in ratios)
              _Choice(
                label: label,
                icon: aspect == null ? StudioIcons.reset : null,
                selected: aspect == null && !op.isCropped,
                onTap: () => editImage((o) => o.croppedTo(aspect)),
              ),
          ],
        ),
        _ImageProperty.corners => _ValueSlider(
          label: 'Corners',
          value: maxRadius <= 0 ? 0 : op.cornerRadius / maxRadius,
          min: 0,
          max: 1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => editImage(
            (o) => o.copyWith(cornerRadius: v * maxRadius),
            live: true,
          ),
          onChangeEnd: (_) => _update(_flushLive),
        ),
        _ImageProperty.border => _ValueSlider(
          label: 'Border',
          value: maxBorder <= 0 ? 0 : op.borderWidth / maxBorder,
          min: 0,
          max: 1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) => editImage(
            (o) => o.copyWith(borderWidth: v * maxBorder),
            live: true,
          ),
          onChangeEnd: (_) => _update(_flushLive),
        ),
        _ImageProperty.borderColour => _ColourRow(
          color: op.borderColor,
          // A colour chosen for a rim that is not there yet adds one.
          onPick: (c) => editImage(
            (o) => o.copyWith(
              borderColor: c,
              borderWidth: o.borderWidth > 0 ? null : maxBorder * 0.25,
            ),
          ),
          dropperArmed: _picking == _PickFor.object,
          onDropper: () => _armPicker(_PickFor.object),
          onCustom: () => _customColour(
            op.borderColor,
            (c) => editImage((o) => o.copyWith(borderColor: c)),
          ),
        ),
        _ImageProperty.opacity => _ValueSlider(
          label: 'Opacity',
          value: op.opacity,
          min: 0.05,
          max: 1,
          display: (v) => '${(v * 100).round()}%',
          onChanged: (v) =>
              _editSelectedLive((o) => o.withPlacement(opacity: v)),
          onChangeEnd: (_) => _update(_flushLive),
        ),
      },
    ];
  }

  // ---------------------------------------------------------------------------
  // Hide
  // ---------------------------------------------------------------------------

  Widget _hidePanel() {
    // A phone's bars only for a phone's screenshot; a laptop or a browser
    // window has neither.
    final bars = widget.statusBarStyle != null;
    return ConstrainedBox(
      // Every page as tall as the tallest — four rows, one a slider — so
      // turning from one to another never re-fits the photo under them.
      constraints: BoxConstraints(
        minHeight: bars ? 3 * 40 + _ValueSlider.height + 3 * StudioSpace.m : 0,
      ),
      child: _hidePages(bars),
    );
  }

  Widget _hidePages(bool bars) {
    return _rows([
      if (bars)
        _Segments(
          children: [
            for (final page in _HidePage.values)
              _Choice(
                label: page.label,
                icon: page.icon,
                selected: _hidePage == page,
                // A bar that is on says so from the other pages.
                marked: switch (page) {
                  _HidePage.statusBar => _statusBar != null,
                  _HidePage.navBar => _navBar != null,
                  _HidePage.areas => false,
                },
                onTap: () => _setHidePage(page),
              ),
          ],
        ),
      ...switch (bars ? _hidePage : _HidePage.areas) {
        _HidePage.areas => _areaRows(),
        _HidePage.statusBar => _statusBarRows(),
        _HidePage.navBar => _navBarRows(),
      },
    ]);
  }

  /// The ways of hiding an area, what the selected one is set to, and the
  /// outline the next one is drawn with.
  List<Widget> _areaRows() {
    final selected = _selected;
    final area = selected is HideOp ? selected : null;
    return [
      _Strip(
        children: [
          for (final style in HideStyle.values)
            _Choice(
              label: style.label,
              icon: style.icon,
              selected: _hideStyle == style,
              onTap: () => _setHideStyle(style),
            ),
        ],
      ),
      switch (_hideStyle) {
        HideStyle.blur => _ValueSlider(
          label: 'Blur strength',
          value: area?.blur ?? _blurStrength,
          min: 0.008,
          max: 0.08,
          display: (v) => '${(v * 1000).round()}',
          onChanged: (v) => _setHideStrength(blur: v),
          onChangeEnd: (_) => _update(_flushLive),
        ),
        HideStyle.pixelate => _ValueSlider(
          label: 'Block size',
          value: area?.block ?? _pixelSize,
          min: 0.015,
          max: 0.08,
          display: (v) => '${(v * 1000).round()}',
          onChanged: (v) => _setHideStrength(block: v),
          onChangeEnd: (_) => _update(_flushLive),
        ),
        HideStyle.cover => _ColourRow(
          color: area?.color ?? _coverColor,
          onPick: _setCoverColour,
          dropperArmed: _picking == _PickFor.cover,
          onDropper: () => _armPicker(_PickFor.cover),
          onCustom: () =>
              _customColour(area?.color ?? _coverColor, _setCoverColour),
        ),
      },
      Row(
        children: [
          for (final shape in HideShape.values) ...[
            _Choice(
              label: shape.label,
              icon: shape.icon,
              selected: _hideShape == shape,
              iconOnly: true,
              onTap: () => _setHideShape(shape),
            ),
            SizedBox(width: StudioSpace.s),
          ],
          if (area != null) ...[
            _Choice(
              label: 'Delete',
              icon: StudioIcons.delete,
              selected: false,
              iconOnly: true,
              onTap: _deleteSelected,
            ),
            SizedBox(width: StudioSpace.s),
            _Choice(
              label: 'Duplicate',
              icon: StudioIcons.duplicate,
              selected: false,
              iconOnly: true,
              onTap: _duplicateSelected,
            ),
            SizedBox(width: StudioSpace.m),
          ] else
            SizedBox(width: StudioSpace.xs),
          Expanded(
            child: _Hint(
              area != null
                  ? 'Drag it, or pull a side or corner.'
                  : _hideShape == HideShape.freehand
                  ? 'Draw round anything private, like a lasso.'
                  : 'Drag over anything private — a name, a face, a number.',
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _statusBarRows() {
    final bar = _statusBar;
    return [
      _Strip(
        children: [
          _Choice(label: 'Off', selected: bar == null, onTap: _removeStatusBar),
          // The phone the picture is going into first.
          for (final style in {
            ?widget.statusBarStyle,
            ...StatusBarStyle.values,
          })
            _Choice(
              label: style.label,
              selected: bar?.style == style,
              onTap: () => _setStatusBar(style),
            ),
        ],
      ),
      if (bar == null)
        const _Hint(
          'Pick a phone to draw a clean status bar over the captured one — '
          '9:41, full signal, full battery.',
        )
      else ...[
        _ValueSlider(
          label: 'Height',
          value: bar.height,
          min: 0.03,
          max: 0.3,
          display: (v) => '${(v * _pictureWidth).round()} px',
          onChanged: (v) =>
              _editOp<StatusBarOp>((b) => b.copyWith(height: v), live: true),
          onChangeEnd: (_) => _update(_flushLive),
        ),
        _ColourRow(
          color: bar.background,
          onPick: _recolourStatusBar,
          dropperArmed: _picking == _PickFor.statusBar,
          onDropper: () => _armPicker(_PickFor.statusBar),
          onCustom: () => _customColour(bar.background, _recolourStatusBar),
        ),
      ],
    ];
  }

  void _recolourStatusBar(Color colour) => _editOp<StatusBarOp>(
    (b) => b.copyWith(background: colour, foreground: _inkOn(colour)),
  );

  List<Widget> _navBarRows() {
    final bar = _navBar;
    final clear = bar != null && bar.background.a == 0;
    return [
      _Strip(
        children: [
          _Choice(label: 'Off', selected: bar == null, onTap: _removeNavBar),
          for (final style in {
            ?switch (widget.statusBarStyle) {
              StatusBarStyle.ios => NavBarStyle.ios,
              StatusBarStyle.samsung => NavBarStyle.samsung,
              StatusBarStyle.android => NavBarStyle.gesture,
              null => null,
            },
            ...NavBarStyle.values,
          })
            _Choice(
              label: style.label,
              selected: bar?.style == style,
              onTap: () => _setNavBar(style),
            ),
        ],
      ),
      if (bar == null)
        const _Hint(
          'Pick one to draw a navigation bar along the bottom — a gesture '
          'handle, an iPhone\'s home indicator or three buttons.',
        )
      else ...[
        _ValueSlider(
          label: 'Height',
          value: bar.height,
          min: 0.02,
          max: 0.25,
          display: (v) => '${(v * _pictureWidth).round()} px',
          onChanged: (v) =>
              _editOp<NavBarOp>((b) => b.copyWith(height: v), live: true),
          onChangeEnd: (_) => _update(_flushLive),
        ),
        _ColourRow(
          // No bar behind the handle — it sits over the app.
          leading: SizedBox(
            height: 36,
            child: _Choice(
              label: 'None',
              selected: clear,
              onTap: () => _editOp<NavBarOp>(
                (b) => b.copyWith(
                  background: const Color(0x00000000),
                  foreground: _inkOn(_underNavBar(b.style)),
                ),
              ),
            ),
          ),
          color: clear ? null : bar.background,
          onPick: _recolourNavBar,
          dropperArmed: _picking == _PickFor.navBar,
          onDropper: () => _armPicker(_PickFor.navBar),
          onCustom: () => _customColour(
            clear ? _underNavBar(bar.style) : bar.background,
            _recolourNavBar,
          ),
        ),
      ],
    ];
  }

  void _recolourNavBar(Color colour) => _editOp<NavBarOp>(
    (b) => b.copyWith(background: colour, foreground: _inkOn(colour)),
  );

  // ---------------------------------------------------------------------------
  // Cutout
  // ---------------------------------------------------------------------------

  Widget _cutoutPanel() {
    final busy = _removingBackground;
    return _rows([
      if (_hasCutout)
        StudioButton(
          label: 'Restore the background',
          icon: StudioIcons.reset,
          fullWidth: true,
          variant: StudioButtonVariant.secondary,
          onPressed: _restoreBackground,
        )
      else
        StudioButton(
          label: busy ? 'Removing…' : 'Remove background',
          icon: StudioIcons.removeBackground,
          fullWidth: true,
          variant: StudioButtonVariant.primary,
          onPressed: busy ? null : _removeBackground,
        ),
      const _Hint(
        'Clears the plain colour around the edges. Best for an icon, a logo '
        'or a product shot on a flat background.',
      ),
    ]);
  }
}
