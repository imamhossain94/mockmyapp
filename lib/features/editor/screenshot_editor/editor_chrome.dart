part of 'screenshot_editor_screen.dart';

// -----------------------------------------------------------------------------
// Top bar
// -----------------------------------------------------------------------------

/// Cancel on the left, Done on the right, and between them the only other
/// things that apply whatever tool is open: undo, redo and compare.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.subtitle,
    required this.canUndo,
    required this.canRedo,
    required this.canCompare,
    required this.busy,
    required this.onClose,
    required this.onUndo,
    required this.onRedo,
    required this.onCompare,
    required this.onDone,
  });

  final String subtitle;
  final bool canUndo;
  final bool canRedo;
  final bool canCompare;
  final bool busy;
  final VoidCallback onClose;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final ValueChanged<bool> onCompare;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final narrow = MediaQuery.sizeOf(context).width < 400;
    return Container(
      height: StudioSizes.toolbar,
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: Row(
        children: [
          SizedBox(width: StudioSpace.xs),
          StudioIconButton(
            icon: StudioIcons.close,
            iconSize: 16,
            tooltip: 'Cancel',
            onPressed: onClose,
          ),
          SizedBox(width: StudioSpace.xs),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Edit photo',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: StudioText.titleSmall(
                    context,
                  ).copyWith(color: s.textPrimary),
                ),
                if (!narrow)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioText.mono(
                      context,
                    ).copyWith(color: s.textTertiary),
                  ),
              ],
            ),
          ),
          StudioIconButton(
            icon: StudioIcons.undo,
            iconSize: 16,
            tooltip: 'Undo',
            onPressed: canUndo ? onUndo : null,
          ),
          StudioIconButton(
            icon: StudioIcons.redo,
            iconSize: 16,
            tooltip: 'Redo',
            onPressed: canRedo ? onRedo : null,
          ),
          _CompareButton(enabled: canCompare, onCompare: onCompare),
          SizedBox(width: StudioSpace.s),
          StudioButton(
            label: busy ? 'Saving…' : 'Done',
            icon: StudioIcons.check,
            dense: true,
            variant: StudioButtonVariant.primary,
            onPressed: busy ? null : onDone,
          ),
          SizedBox(width: StudioSpace.l),
        ],
      ),
    );
  }
}

/// Press and hold to see the photo as it was.
///
/// Held rather than toggled: a toggle left on is an editor that looks as if
/// every edit has stopped working.
class _CompareButton extends StatelessWidget {
  const _CompareButton({required this.enabled, required this.onCompare});

  final bool enabled;
  final ValueChanged<bool> onCompare;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Tooltip(
      message: 'Hold to compare with the original',
      // Hover only. Holding is the whole gesture here, and a long-press
      // tooltip would cover the "Original" badge it brings up.
      triggerMode: TooltipTriggerMode.manual,
      child: Listener(
        onPointerDown: enabled ? (_) => onCompare(true) : null,
        onPointerUp: enabled ? (_) => onCompare(false) : null,
        onPointerCancel: enabled ? (_) => onCompare(false) : null,
        child: SizedBox.square(
          dimension: StudioSizes.toolButton + StudioSpace.xs,
          child: Center(
            child: StudioIcon(
              StudioIcons.compare,
              size: 16,
              color: enabled ? s.textSecondary : s.textTertiary,
            ),
          ),
        ),
      ),
    );
  }
}

/// A small floating label over the photo.
class _Badge extends StatelessWidget {
  const _Badge({required this.label, this.icon});

  final String label;
  final StudioIconData? icon;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.l,
        vertical: StudioSpace.s,
      ),
      decoration: BoxDecoration(
        color: s.overlay,
        borderRadius: BorderRadius.circular(StudioRadius.lg),
        border: Border.all(color: s.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            StudioIcon(icon!, size: 12, color: s.accent),
            SizedBox(width: StudioSpace.s),
          ],
          Text(
            label,
            style: StudioText.bodyStrong(
              context,
            ).copyWith(color: s.textPrimary),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Dock: the open tool's panel over the tool bar
// -----------------------------------------------------------------------------

class _Dock extends StatelessWidget {
  const _Dock({
    required this.tool,
    required this.onTool,
    required this.panel,
    required this.collapsed,
    required this.onCollapsed,
  });

  final PhotoTool? tool;
  final ValueChanged<PhotoTool> onTool;
  final Widget? panel;

  /// Whether the panel is tucked away, leaving the handle and the tool bar.
  final bool collapsed;
  final ValueChanged<bool> onCollapsed;

  /// The grab handle across the top of the dock.
  static const double handleHeight = 22;

  /// The room every panel is designed to fit — two strips and a slider, or
  /// three strips — padding included.
  ///
  /// The panel area is always this tall, open tool or not, and a panel sits at
  /// its top. So nothing moves when a tool opens, and a row that appears under
  /// a choice — Extend's fills — never slides the choice out from under the
  /// finger that made it.
  static const double panelHeight = 174;

  /// What the dock takes from the bottom of the screen with no panel taller
  /// than [panelHeight] open.
  static double floor(EdgeInsets safeArea, {bool collapsed = false}) =>
      _ToolBar.height +
      handleHeight +
      (collapsed ? 0 : panelHeight) +
      1 +
      safeArea.bottom;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        top: false,
        child: Center(
          // A comfortable reading width on a desktop window, where a panel
          // stretched edge to edge puts its slider a metre from its label.
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DockHandle(collapsed: collapsed, onChanged: onCollapsed),
                if (!collapsed)
                  AnimatedSize(
                    duration: context.motion(StudioDuration.fast),
                    curve: Curves.easeOut,
                    alignment: Alignment.topCenter,
                    child: Container(
                      constraints: const BoxConstraints(minHeight: panelHeight),
                      alignment: panel == null
                          ? Alignment.center
                          : Alignment.topCenter,
                      padding: EdgeInsets.fromLTRB(
                        StudioSpace.l,
                        StudioSpace.xxs,
                        StudioSpace.l,
                        StudioSpace.s,
                      ),
                      child:
                          panel ??
                          const _Hint(
                            'Pick a tool below to crop, adjust, draw, add text '
                            'or hide something private.',
                            center: true,
                          ),
                    ),
                  ),
                _ToolBar(selected: tool, onTool: onTool),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Side layout: the tools down the left, the open tool's panel on the right
// -----------------------------------------------------------------------------

/// The tools down the left edge, for a window with width to spare and no
/// height to give away — a desktop, a tablet, a phone on its side.
class _ToolRail extends StatelessWidget {
  const _ToolRail({required this.selected, required this.onTool});

  final PhotoTool? selected;
  final ValueChanged<PhotoTool> onTool;

  static const double width = 76;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(right: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        top: false,
        right: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // As tall as the window allows: a phone on its side has about 40
            // a tool — with the full width of the rail, still a fair target —
            // and a desktop plenty.
            final each = (constraints.maxHeight / PhotoTool.values.length)
                .clamp(40.0, 64.0);
            return ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final tool in PhotoTool.values)
                  SizedBox(
                    height: each,
                    child: _ToolButton(
                      tool: tool,
                      width: width,
                      selected: tool == selected,
                      tight: each < 52,
                      onTap: () => onTool(tool),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The open tool's panel, as a column beside the photo.
///
/// Always there, open tool or not, for the reason the dock keeps its height:
/// opening a tool must not re-fit the photo being judged.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.tool,
    required this.panel,
    required this.onCollapse,
  });

  final PhotoTool? tool;
  final Widget? panel;

  /// Tucks the panel away, leaving a [_PanelTab] to bring it back.
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final tool = this.tool;
    final panel = this.panel;
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(left: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        top: false,
        left: false,
        child: tool == null || panel == null
            ? Center(
                child: Padding(
                  padding: EdgeInsets.all(StudioSpace.xl),
                  child: const _Hint(
                    'Pick a tool on the left to crop, adjust, draw, add text '
                    'or hide something private.',
                    center: true,
                  ),
                ),
              )
            : _WrapStrips(
                child: ListView(
                  padding: EdgeInsets.all(StudioSpace.l),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            tool.label,
                            style: StudioText.titleSmall(
                              context,
                            ).copyWith(color: s.textPrimary),
                          ),
                        ),
                        StudioIconButton(
                          icon: StudioIcons.chevronRight,
                          iconSize: 12,
                          tooltip: 'Hide the panel',
                          onPressed: onCollapse,
                        ),
                      ],
                    ),
                    SizedBox(height: StudioSpace.s),
                    panel,
                  ],
                ),
              ),
      ),
    );
  }
}

/// The way back to a side panel tucked away: a tab on the edge it went off.
///
/// Tapping the open tool on the rail brings it back too, but nothing says so,
/// and a panel that vanished with no trace of where it went reads as lost.
class _PanelTab extends StatelessWidget {
  const _PanelTab({required this.tool, required this.onOpen});

  static const double width = 32;

  final PhotoTool tool;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final label = 'Show the ${tool.label} panel';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: Material(
          color: s.panel,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(StudioRadius.lg),
            ),
            // A hairline: it floats over the photo.
            side: BorderSide(color: s.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onOpen();
            },
            child: SizedBox(
              width: width,
              height: 76,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  StudioIcon(
                    StudioIcons.chevronLeft,
                    size: 11,
                    color: s.textSecondary,
                  ),
                  SizedBox(height: StudioSpace.m),
                  StudioIcon(tool.icon, size: 14, color: s.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reports its child's height after any layout that changes it — how the
/// screen learns that the dock has grown past the room kept for it.
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.onHeight, required super.child});

  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderHeightReporter(onHeight);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHeightReporter renderObject,
  ) => renderObject.onHeight = onHeight;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.onHeight);

  ValueChanged<double> onHeight;
  double? _reported;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    if (_reported == height) return;
    _reported = height;
    // After the frame: a rebuild cannot be asked for from inside layout.
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(height));
  }
}

/// The strip across the top of the dock that tucks the panel away and brings
/// it back — by a tap, or by a swipe the way a sheet is flicked.
class _DockHandle extends StatelessWidget {
  const _DockHandle({required this.collapsed, required this.onChanged});

  final bool collapsed;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Semantics(
      button: true,
      label: collapsed ? 'Show the tool panel' : 'Hide the tool panel',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(!collapsed);
        },
        onVerticalDragEnd: (details) {
          final v = details.primaryVelocity ?? 0;
          if (v.abs() < 50) return;
          HapticFeedback.selectionClick();
          onChanged(v > 0);
        },
        child: SizedBox(
          height: _Dock.handleHeight,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: s.borderStrong,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: StudioSpace.s),
                StudioIcon(
                  collapsed ? StudioIcons.collapse : StudioIcons.expand,
                  size: 10,
                  color: s.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The tools, as a row of icons with their names under them.
class _ToolBar extends StatelessWidget {
  const _ToolBar({required this.selected, required this.onTool});

  final PhotoTool? selected;
  final ValueChanged<PhotoTool> onTool;

  static const double height = 64;
  static const double _toolWidth = 64;

  /// The narrowest a tool gets before the bar scrolls instead: every tool in
  /// view matters more than roomy ones, down to a fingertip's width.
  static const double _minToolWidth = 44;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final share = constraints.maxWidth / PhotoTool.values.length;
          final fits = share >= _minToolWidth;
          final width = fits ? share : _toolWidth;
          final tools = [
            for (final tool in PhotoTool.values)
              _ToolButton(
                tool: tool,
                width: width,
                selected: tool == selected,
                onTap: () => onTool(tool),
              ),
          ];
          if (fits) return Row(children: tools);
          // A very narrow screen scrolls the last ones in; the one cut in half
          // at the edge says there is more.
          return ScrollConfiguration(
            behavior: const _DragAnything(),
            child: ListView(scrollDirection: Axis.horizontal, children: tools),
          );
        },
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.tool,
    required this.width,
    required this.selected,
    required this.onTap,
    this.tight = false,
  });

  final PhotoTool tool;
  final double width;
  final bool selected;
  final VoidCallback onTap;

  /// Close to a fingertip tall, as on a phone's rail on its side: the icon
  /// and its name keep their room, and the margin around them gives way.
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final fg = selected ? s.onAccent : s.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: tool.label,
      child: SizedBox(
        width: width,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: StudioSpace.xxs,
            vertical: tight ? StudioSpace.xxs : StudioSpace.s,
          ),
          child: Material(
            color: selected ? s.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(StudioRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              hoverColor: s.hoverBg,
              child: ExcludeSemantics(
                // Scaled down, never cut off: a phone's rail on its side and a
                // large system text size both ask for more than the button's
                // height, and a shrunk label beats a clipped one.
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: StudioSpace.xxs),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StudioIcon(tool.icon, size: 18, color: fg),
                        SizedBox(height: StudioSpace.xxs),
                        Text(
                          tool.label,
                          maxLines: 1,
                          style: StudioText.micro(context).copyWith(color: fg),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shared panel controls
// -----------------------------------------------------------------------------

/// Marks a panel laid out in a column beside the photo, where there is height
/// to spare: its strips wrap onto more lines rather than scrolling sideways,
/// so every option is in view at once.
class _WrapStrips extends InheritedWidget {
  const _WrapStrips({required super.child});

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_WrapStrips>() != null;

  @override
  bool updateShouldNotify(_WrapStrips oldWidget) => false;
}

/// Lets a mouse drag a sideways strip along, as a finger can. Flutter leaves
/// the mouse out by default, which in a narrow desktop browser window put
/// every option past the panel's edge out of reach.
class _DragAnything extends MaterialScrollBehavior {
  const _DragAnything();

  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
}

/// A horizontally scrolling row — every option one tap away however narrow
/// the phone, without wrapping onto a second line that would push the photo
/// up.
class _Strip extends StatelessWidget {
  const _Strip({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (_WrapStrips.of(context)) {
      return Wrap(
        spacing: StudioSpace.s,
        runSpacing: StudioSpace.s,
        children: [
          for (final child in children) SizedBox(height: 40, child: child),
        ],
      );
    }
    return SizedBox(
      height: 40,
      child: ScrollConfiguration(
        behavior: const _DragAnything(),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: children.length,
          separatorBuilder: (_, _) => SizedBox(width: StudioSpace.s),
          itemBuilder: (_, i) => children[i],
        ),
      ),
    );
  }
}

/// Choices that share a row equally — the pages of one tool, every one of
/// them in view however narrow the phone, where a strip would scroll the last
/// out of sight.
class _Segments extends StatelessWidget {
  const _Segments({required this.children});

  final List<_Choice> children;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Row(
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) SizedBox(width: StudioSpace.s),
          Expanded(child: child.stretched()),
        ],
      ],
    ),
  );
}

/// A choice in a strip: icon and label, filled when it is the current one.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.marked = false,
    this.iconOnly = false,
    this.stretch = false,
  });

  /// Whether this fills the width it is given, its label centred and — on a
  /// phone too narrow for it — made smaller rather than cut off.
  final bool stretch;

  _Choice stretched() => _Choice(
    label: label,
    selected: selected,
    onTap: onTap,
    icon: icon,
    marked: marked,
    iconOnly: iconOnly,
    stretch: true,
  );

  final String label;
  final StudioIconData? icon;
  final bool selected;

  /// Just the icon, with [label] as its tooltip — for the actions everyone
  /// knows by their icon (bold, delete, duplicate), and for the tools of a
  /// strip other than the chosen one, so a phone fits the whole set.
  final bool iconOnly;

  /// A dot for a choice that has been changed from its default — the Adjust
  /// tool's way of showing which sliders are in play.
  final bool marked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final fg = selected ? s.onAccent : s.textSecondary;
    final glyph = icon;
    final compact = iconOnly && glyph != null;
    final chip = Semantics(
      button: true,
      selected: selected,
      label: compact ? label : null,
      child: Material(
        color: selected ? s.accent : s.well,
        borderRadius: BorderRadius.circular(StudioRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: compact
              ? SizedBox.square(
                  dimension: 40,
                  child: Center(child: StudioIcon(glyph, size: 15, color: fg)),
                )
              : Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: stretch ? StudioSpace.s : StudioSpace.l,
                  ),
                  child: _fitted(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (glyph != null) ...[
                          StudioIcon(glyph, size: 13, color: fg),
                          SizedBox(width: StudioSpace.s),
                        ],
                        Text(
                          label,
                          style: StudioText.bodyStrong(
                            context,
                          ).copyWith(color: fg),
                        ),
                        if (marked) ...[
                          SizedBox(width: StudioSpace.s),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: selected ? s.onAccent : s.accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
        ),
      ),
    );
    return compact ? Tooltip(message: label, child: chip) : chip;
  }

  Widget _fitted(Widget content) => stretch
      ? Center(
          child: FittedBox(fit: BoxFit.scaleDown, child: content),
        )
      : content;
}

/// Which of a text's two colours the swatches set: the letters, or the box or
/// outline around them.
class _ColourTarget extends StatelessWidget {
  const _ColourTarget({
    required this.accentLabel,
    required this.text,
    required this.accent,
    required this.onAccent,
    required this.onChanged,
  });

  final String accentLabel;
  final Color text;
  final Color accent;

  /// Whether the swatches are setting [accent] rather than [text].
  final bool onAccent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    Widget side(String label, Color colour, bool selected, bool value) {
      final fg = selected ? s.onAccent : s.textSecondary;
      return Semantics(
        button: true,
        selected: selected,
        label: '$label colour',
        child: Material(
          color: selected ? s.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(StudioRadius.md),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(value);
            },
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: StudioSpace.m),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colour,
                      shape: BoxShape.circle,
                      border: Border.all(color: s.borderStrong),
                    ),
                  ),
                  SizedBox(width: StudioSpace.s),
                  ExcludeSemantics(
                    child: Text(
                      label,
                      style: StudioText.bodyStrong(context).copyWith(color: fg),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 36,
      padding: EdgeInsets.all(StudioSpace.xxs),
      decoration: BoxDecoration(
        color: s.well,
        borderRadius: BorderRadius.circular(StudioRadius.lg),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          side('Text', text, !onAccent, false),
          side(accentLabel, accent, onAccent, true),
        ],
      ),
    );
  }
}

/// A slider sized for a thumb rather than a pointer: its name and value on one
/// line, and the panel's whole width for the track under them.
///
/// A control whose untouched value sits inside its range — brightness,
/// straighten — fills from that point rather than from the left end, so which
/// way it has been moved, and how far, reads at a glance. While it is away
/// from there, the value doubles as its reset.
class _ValueSlider extends StatelessWidget {
  const _ValueSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.onChangeEnd,
    this.origin,
    this.onReset,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String Function(double value) display;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  /// The untouched value, where the fill starts; the left end when null.
  final double? origin;

  /// Puts the value back to [origin]. Offered only while it is elsewhere.
  final VoidCallback? onReset;

  static const double height = 58;
  static const double _thumbRadius = 10;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final span = max - min;
    final v = value.clamp(min, max).toDouble();
    final from = (origin ?? min).clamp(min, max).toDouble();
    final moved = (v - from).abs() > span * 1e-4;
    final readout = ExcludeSemantics(
      child: Text(
        display(v),
        style: StudioText.mono(
          context,
        ).copyWith(color: moved ? s.textPrimary : s.textTertiary),
      ),
    );
    final reset = onReset;

    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 24,
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: StudioText.bodyStrong(
                        context,
                      ).copyWith(color: s.textSecondary),
                    ),
                  ),
                ),
                if (reset != null && moved)
                  Semantics(
                    button: true,
                    label: 'Reset ${label.toLowerCase()}',
                    child: Material(
                      color: s.well,
                      borderRadius: BorderRadius.circular(StudioRadius.lg),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          reset();
                        },
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: StudioSpace.m,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StudioIcon(
                                StudioIcons.reset,
                                size: 11,
                                color: s.textSecondary,
                              ),
                              SizedBox(width: StudioSpace.s),
                              readout,
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: EdgeInsets.only(right: StudioSpace.xxs),
                    child: readout,
                  ),
              ],
            ),
          ),
          Expanded(
            // The caption is excluded above and the name given to the control
            // itself, so a screen reader says it once, bound to its value.
            child: Semantics(
              label: label,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  activeTrackColor: s.accent,
                  inactiveTrackColor: s.borderStrong,
                  thumbColor: s.accent,
                  overlayColor: s.accent.withValues(alpha: 0.16),
                  trackShape: _OriginTrack(
                    span <= 0 ? 0 : (from - min) / span,
                    tickColor: s.textTertiary,
                  ),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: _thumbRadius,
                    elevation: 0,
                    pressedElevation: 0,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 17,
                  ),
                  showValueIndicator: ShowValueIndicator.never,
                ),
                child: Slider(
                  value: v,
                  min: min,
                  max: max,
                  onChanged: (next) {
                    // A detent at the untouched value: without one, getting
                    // back to exactly zero by thumb is a matter of luck.
                    if (origin != null && (next - from).abs() < span * 0.015) {
                      if (moved) HapticFeedback.selectionClick();
                      next = from;
                    }
                    onChanged(next);
                  },
                  onChangeEnd: onChangeEnd,
                  semanticFormatterCallback: display,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A slider track filled from [origin] — a fraction of its length — to the
/// thumb, with a tick at the origin when it is not an end.
///
/// It runs to the thumb's edge rather than the overlay's, so the slider lines
/// up with the caption over it and the whole width of the panel is travel.
class _OriginTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _OriginTrack(this.origin, {required this.tickColor});

  final double origin;
  final Color tickColor;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final inset =
        sliderTheme.thumbShape!.getPreferredSize(isEnabled, isDiscrete).width /
        2;
    final height = sliderTheme.trackHeight!;
    return Rect.fromLTWH(
      offset.dx + inset,
      offset.dy + (parentBox.size.height - height) / 2,
      math.max(0, parentBox.size.width - inset * 2),
      height,
    );
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final track = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final canvas = context.canvas;
    final round = Radius.circular(track.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(track, round),
      Paint()..color = sliderTheme.inactiveTrackColor!,
    );
    final start = track.left + track.width * origin.clamp(0.0, 1.0);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          math.min(start, thumbCenter.dx),
          track.top,
          math.max(start, thumbCenter.dx),
          track.bottom,
        ),
        round,
      ),
      Paint()..color = sliderTheme.activeTrackColor!,
    );
    if (origin > 0 && origin < 1) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(start, track.center.dy),
            width: 2,
            height: track.height + 8,
          ),
          const Radius.circular(1),
        ),
        Paint()..color = tickColor,
      );
    }
  }
}

/// The paint colours, the eyedropper and a custom colour, in one strip.
class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.color,
    required this.onPick,
    required this.onDropper,
    required this.onCustom,
    this.dropperArmed = false,
    this.leading,
  });

  /// Shown before the swatches — which colour they set, when there are two.
  final Widget? leading;

  /// The current colour, or null for one no swatch stands for — art still in
  /// the colours it was drawn in.
  final Color? color;
  final ValueChanged<Color> onPick;
  final VoidCallback onDropper;
  final VoidCallback onCustom;
  final bool dropperArmed;

  /// Paint colours, not chrome — literal on purpose.
  static const swatches = <Color>[
    Color(0xFFFFFFFF),
    Color(0xFF111111),
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFFFACC15),
    Color(0xFF22C55E),
    Color(0xFF06B6D4),
    Color(0xFF3574F0),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final argb = color?.toARGB32();
    final shown = color ?? s.well;
    final items = <Widget>[
      if (leading case final leading?) ...[
        Center(widthFactor: 1, child: leading),
        SizedBox(width: StudioSpace.s),
      ],
      StudioIconButton(
        icon: StudioIcons.colorPicker,
        iconSize: 14,
        tooltip: 'Pick a colour from the photo',
        selected: dropperArmed,
        onPressed: onDropper,
      ),
      for (final swatch in swatches)
        Padding(
          padding: EdgeInsets.symmetric(horizontal: StudioSpace.xxs),
          child: StudioSwatch(
            color: swatch,
            size: 28,
            selected: swatch.toARGB32() == argb,
            onTap: () => onPick(swatch),
          ),
        ),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: StudioSpace.xxs),
        child: StudioSwatch(
          color: shown,
          size: 28,
          tooltip: 'Any colour',
          onTap: onCustom,
          child: StudioIcon(
            StudioIcons.palette,
            size: 11,
            color: shown.computeLuminance() > 0.5
                ? const Color(0xFF000000)
                : const Color(0xFFFFFFFF),
          ),
        ),
      ),
      if (argb != null) ...[
        SizedBox(width: StudioSpace.s),
        Center(
          widthFactor: 1,
          child: Text(
            '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
            style: StudioText.mono(context).copyWith(color: s.textTertiary),
          ),
        ),
      ],
    ];
    if (_WrapStrips.of(context)) {
      return Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: StudioSpace.xs,
        children: [
          for (final item in items)
            if (item is SizedBox) item else SizedBox(height: 40, child: item),
        ],
      );
    }
    return SizedBox(
      height: 40,
      child: ScrollConfiguration(
        behavior: const _DragAnything(),
        child: ListView(scrollDirection: Axis.horizontal, children: items),
      ),
    );
  }
}

/// A line of guidance under a panel's controls.
class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.center = false});

  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Text(
      text,
      // Beside the photo there is height to spare; under it, two lines.
      maxLines: _WrapStrips.of(context) ? 5 : 2,
      overflow: TextOverflow.ellipsis,
      textAlign: center ? TextAlign.center : null,
      style: StudioText.caption(context).copyWith(color: s.textTertiary),
    );
  }
}
