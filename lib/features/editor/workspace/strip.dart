part of '../editor_screen.dart';

/// What can be done to one screen from its header on the strip.
enum _ScreenAction { addAfter, duplicate, moveLeft, moveRight, delete }

/// Where everything on the screen strip goes, in content coordinates.
///
/// Worked out from the viewport and nothing else, so the editor can ask the
/// same question the strip answers — "where is screen 3?" — when it wants to
/// bring a screen to the middle, without reaching into the strip's layout.
///
/// At zoom 1 a screen is as tall as the canvas area allows once its header and
/// the floating toolbar are cleared. A phone additionally caps it by width, so
/// the neighbours peek in at the edges and say "there is more this way".
class _StripGeometry {
  _StripGeometry({
    required this.viewport,
    required this.canvases,
    required this.compact,
    required this.withAddTile,
    this.continuous = false,
    bool? toolbar,
  }) : toolbar = toolbar ?? !compact {
    final base = math.max(80.0, viewport.height - top - header - bottom);
    var height = base;
    if (compact) {
      final widest = canvases.fold<double>(
        0,
        (m, c) => math.max(m, c.height <= 0 ? 0 : c.width / c.height),
      );
      if (widest > 0) height = math.min(height, viewport.width * 0.78 / widest);
    }
    screenHeight = height;

    var x = lead;
    for (final c in canvases) {
      final w = c.height <= 0 ? height : height * c.width / c.height;
      lefts.add(x);
      widths.add(w);
      x += w + gap;
    }
    // The add tile stands apart even when the screens touch: it is not a
    // panel of the artwork.
    addTileLeft = continuous && canvases.isNotEmpty
        ? x + (compact ? 20 : 40)
        : x;
    addTileWidth = canvases.isEmpty
        ? height * 0.46
        : math.min(widths.reduce((a, b) => a + b) / widths.length * 0.5, 200);
    contentWidth = (withAddTile ? addTileLeft + addTileWidth : x - gap) + lead;
  }

  final Size viewport;
  final List<Size> canvases;
  final bool compact;
  final bool withAddTile;

  /// Whether the floating canvas toolbar sits over the foot of the stage.
  /// It does wherever there is no bottom sheet, a phone on its side included.
  final bool toolbar;

  /// Screens edge to edge, as panels of one artwork. See
  /// [SubProject.continuous].
  final bool continuous;

  /// Height of the label row above each screen.
  static const double header = 32;

  double get top => compact ? 8 : 16;

  /// Room left under the screens for the floating canvas toolbar, when it is
  /// there. A landscape phone has it too, and gave it none: the bar covered
  /// the foot of every screen.
  double get bottom => toolbar ? 72 : 12;

  double get gap => continuous ? 0 : (compact ? 20 : 40);
  double get lead => compact ? 24 : 48;

  late final double screenHeight;
  final List<double> lefts = [];
  final List<double> widths = [];
  late final double addTileLeft;
  late final double addTileWidth;
  late final double contentWidth;

  double get screensTop => top + header;

  /// The rect to centre on to show screen [i]: its column, full height, so
  /// centring it at zoom 1 moves the strip sideways and never up or down.
  Rect focusRect(int i) {
    if (lefts.isEmpty) {
      return Rect.fromLTWH(addTileLeft, 0, addTileWidth, viewport.height);
    }
    final at = i.clamp(0, lefts.length - 1);
    return Rect.fromLTWH(lefts[at], 0, widths[at], viewport.height);
  }
}

/// Every screen of a target, side by side, one of them live.
///
/// The active screen is a full [SceneView] with its handles; the rest are the
/// same renderer with no handlers, and a tap on one makes it active. Dragging
/// anywhere that is not the active screen pans the canvas — the strip is
/// usually wider than the window, and on a touchscreen there is no wheel.
class _ScreenStrip extends StatefulWidget {
  const _ScreenStrip({
    required this.geometry,
    required this.screens,
    required this.activeId,
    required this.catalog,
    required this.preview,
    required this.hover,
    required this.activeScene,
    required this.onActivate,
    required this.onAction,
    required this.onAdd,
    required this.onBackgroundTap,
    required this.onPan,
    this.canAdd = true,
    this.continuous = false,
  });

  final _StripGeometry geometry;

  /// Whether the screens are panels of one artwork, each drawn with its
  /// neighbours' reach. See [composeScreen].
  final bool continuous;
  final List<ScreenDoc> screens;
  final String? activeId;
  final FrameCatalog catalog;
  final bool preview;

  /// Whether there is a pointer to hover with. Without one, a screen's actions
  /// show on the active screen only, instead of on whichever is under the
  /// pointer.
  final bool hover;

  /// The interactive scene for the active screen, built by the editor because
  /// it owns the selection and the gestures.
  final Widget? activeScene;

  final ValueChanged<String> onActivate;
  final void Function(_ScreenAction action, ScreenDoc screen) onAction;
  final VoidCallback onAdd;

  /// Whether the set takes more screens. A feature graphic is one image —
  /// the store has one slot for it — so it offers no add tile and no copy.
  final bool canAdd;
  final VoidCallback onBackgroundTap;

  /// A drag on the strip, in content coordinates.
  final ValueChanged<Offset> onPan;

  @override
  State<_ScreenStrip> createState() => _ScreenStripState();
}

class _ScreenStripState extends State<_ScreenStrip> {
  /// The scene built for each idle screen, reused while its document is the
  /// same object.
  ///
  /// Every edit writes the active screen back to the store, which hands this
  /// strip a new list on every frame of a drag. Rebuilding eight idle scenes
  /// for each of those frames is how a slider starts to stutter; handing
  /// Flutter the *same* widget instance lets it skip them outright.
  ///
  /// In a continuous set a screen also shows what reaches in from its
  /// neighbours, so its scene is kept while *they* are unchanged too — the
  /// screen, the two either side, and the first, whose background they all
  /// share. A layer reaching in from two screens away is rare enough to be
  /// picked up on that screen's next rebuild rather than on every frame.
  final Map<String, (List<ScreenDoc?>, Widget)> _idle = {};

  List<ScreenDoc?> _inputsOf(int i) {
    final screens = widget.screens;
    if (!widget.continuous) return [screens[i]];
    return [
      screens[i],
      i > 0 ? screens[i - 1] : null,
      i + 1 < screens.length ? screens[i + 1] : null,
      screens.first,
    ];
  }

  static bool _same(List<ScreenDoc?> a, List<ScreenDoc?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!identical(a[i], b[i])) return false;
    }
    return true;
  }

  Widget _idleScene(int i) {
    final screen = widget.screens[i];
    final inputs = _inputsOf(i);
    final cached = _idle[screen.id];
    if (cached != null && _same(cached.$1, inputs)) return cached.$2;
    final built = RepaintBoundary(
      key: ValueKey('idle-${screen.id}'),
      child: IgnorePointer(
        child: SceneView.composed(
          composeScreen(widget.screens, i, continuous: widget.continuous),
          catalog: widget.catalog,
        ),
      ),
    );
    _idle[screen.id] = (inputs, built);
    return built;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.geometry;
    final screens = widget.screens;
    // Forget screens that are gone, so a deleted screen's scene is not kept.
    _idle.removeWhere((id, _) => !screens.any((s) => s.id == id));

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onBackgroundTap,
            onPanUpdate: (d) => widget.onPan(d.delta),
          ),
        ),
        for (var i = 0; i < screens.length; i++)
          Positioned(
            left: g.lefts[i],
            top: g.top,
            width: g.widths[i],
            height: _StripGeometry.header + g.screenHeight,
            child: _StripItem(
              key: ValueKey(screens[i].id),
              index: i,
              total: screens.length,
              canAdd: widget.canAdd,
              active: screens[i].id == widget.activeId,
              preview: widget.preview,
              hover: widget.hover,
              onActivate: () => widget.onActivate(screens[i].id),
              onAction: (a) => widget.onAction(a, screens[i]),
              onPan: widget.onPan,
              scene: screens[i].id == widget.activeId
                  ? (widget.activeScene ?? _idleScene(i))
                  : _idleScene(i),
            ),
          ),
        if (!widget.preview && widget.canAdd)
          Positioned(
            left: g.addTileLeft,
            top: g.screensTop,
            width: g.addTileWidth,
            height: g.screenHeight,
            child: _AddScreenTile(onTap: widget.onAdd),
          ),
      ],
    );
  }
}

/// One screen on the strip: its number and actions, over the artwork.
class _StripItem extends StatefulWidget {
  const _StripItem({
    super.key,
    required this.index,
    required this.total,
    this.canAdd = true,
    required this.active,
    required this.preview,
    required this.hover,
    required this.onActivate,
    required this.onAction,
    required this.onPan,
    required this.scene,
  });

  final int index;
  final int total;
  final bool canAdd;
  final bool active;
  final bool preview;
  final bool hover;
  final VoidCallback onActivate;
  final ValueChanged<_ScreenAction> onAction;
  final ValueChanged<Offset> onPan;
  final Widget scene;

  @override
  State<_StripItem> createState() => _StripItemState();
}

class _StripItemState extends State<_StripItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final active = widget.active;
    final showActions =
        !widget.preview && (active || (widget.hover && _hovered));

    Widget screen = widget.scene;
    if (!active || widget.preview) {
      screen = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onActivate,
        onPanUpdate: (d) => widget.onPan(d.delta),
        child: screen,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        label: 'Screen ${widget.index + 1} of ${widget.total}',
        selected: active,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _StripGeometry.header,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onActivate,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = _available();
                    // A screen shrunk by an open sheet can be a hundred
                    // points wide, and five buttons need 130: past that the
                    // row folds them into one menu instead of overflowing.
                    final fits =
                        constraints.maxWidth >= 28 + actions.length * 26;
                    return Row(
                      children: [
                        Text(
                          '${widget.index + 1}',
                          style: StudioText.mono(context).copyWith(
                            color: active ? s.accent : s.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (showActions)
                          if (fits)
                            for (final a in actions) _button(a)
                          else
                            _menu(actions),
                      ],
                    );
                  },
                ),
              ),
            ),
            Expanded(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: screen),
                  if (active && !widget.preview)
                    Positioned(
                      left: -3,
                      top: -3,
                      right: -3,
                      bottom: -3,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              StudioRadius.xs,
                            ),
                            border: Border.all(color: s.accent, width: 2),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The actions that apply to this screen where it stands.
  List<_ScreenAction> _available() {
    final i = widget.index;
    return [
      if (i > 0) _ScreenAction.moveLeft,
      if (i < widget.total - 1) _ScreenAction.moveRight,
      if (widget.canAdd) _ScreenAction.duplicate,
      if (widget.canAdd) _ScreenAction.addAfter,
      if (widget.total > 1) _ScreenAction.delete,
    ];
  }

  static (StudioIconData, String) _describe(_ScreenAction action) =>
      switch (action) {
        _ScreenAction.moveLeft => (StudioIcons.moveLeft, 'Move left'),
        _ScreenAction.moveRight => (StudioIcons.moveRight, 'Move right'),
        _ScreenAction.duplicate => (StudioIcons.duplicate, 'Duplicate'),
        _ScreenAction.addAfter => (
          StudioIcons.add,
          'Add a screen after this one',
        ),
        _ScreenAction.delete => (StudioIcons.delete, 'Delete'),
      };

  Widget _button(_ScreenAction action) {
    final (icon, tip) = _describe(action);
    return SizedBox.square(
      dimension: 26,
      child: StudioIconButton(
        icon: icon,
        iconSize: 13,
        tooltip: tip,
        onPressed: () => widget.onAction(action),
      ),
    );
  }

  Widget _menu(List<_ScreenAction> actions) {
    final s = context.studio;
    return PopupMenuButton<_ScreenAction>(
      tooltip: 'Screen actions',
      clipBehavior: Clip.antiAlias,
      onSelected: widget.onAction,
      itemBuilder: (context) => [
        for (final a in actions)
          PopupMenuItem(
            value: a,
            child: MenuEntry(
              icon: _describe(a).$1,
              label: _describe(a).$2,
              danger: a == _ScreenAction.delete,
            ),
          ),
      ],
      child: SizedBox.square(
        dimension: 26,
        child: Center(
          child: StudioIcon(StudioIcons.more, size: 13, color: s.textSecondary),
        ),
      ),
    );
  }
}

/// The "+" at the end of the strip.
class _AddScreenTile extends StatelessWidget {
  const _AddScreenTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Semantics(
      button: true,
      label: 'Add a screen',
      child: Material(
        color: s.panel,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: s.hoverBg,
          // Scaled down rather than clipped: with a sheet open the tile can be
          // shorter than its own label.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                StudioIcon(StudioIcons.add, size: 22, color: s.textSecondary),
                SizedBox(height: StudioSpace.s),
                Text(
                  'Add screen',
                  textAlign: TextAlign.center,
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
