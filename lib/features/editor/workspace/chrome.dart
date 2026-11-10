part of '../editor_screen.dart';

/// Which side of the canvas a pane sits on.
enum _PaneEdge { leading, trailing }

/// A docked pane that slides in and out along the horizontal axis.
///
/// The pane is always laid out at its full width and the *container* animates
/// between that and zero, clipping the excess — the same trick the bottom sheet
/// uses vertically. Animating the child's own width instead would reflow every
/// control inside it on every frame of the transition.
class _SlidePane extends StatelessWidget {
  const _SlidePane({
    required this.open,
    required this.width,
    required this.edge,
    required this.divider,
    required this.child,
  });

  final bool open;

  /// Width of the pane's content, excluding its divider.
  final double width;
  final _PaneEdge edge;
  final Widget divider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = width + StudioPaneDivider.width;
    final content = Row(
      children: edge == _PaneEdge.leading
          ? [SizedBox(width: width, child: child), divider]
          : [divider, SizedBox(width: width, child: child)],
    );

    return ClipRect(
      child: AnimatedContainer(
        duration: context.motion(StudioDuration.slow),
        curve: Curves.easeOutCubic,
        width: open ? total : 0,
        child: OverflowBox(
          // Anchored to the edge the box *keeps* as it shrinks, which is the
          // far side from the window edge the pane docks against. That is what
          // makes the content travel outwards: a trailing pane's box collapses
          // toward the right, so pinning the content's left to it walks the
          // whole pane off the right edge. Pinning the near side instead would
          // hold the content still and wipe it away column by column.
          alignment: edge == _PaneEdge.leading
              ? Alignment.centerRight
              : Alignment.centerLeft,
          minWidth: total,
          maxWidth: total,
          child: content,
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Top bar
// -----------------------------------------------------------------------------

/// What the Download menu offers.
enum _Download {
  screen,
  video,
  copy,
  target,
  targetZip,
  everyLanguage,
  allZip,
  everything,
  fastlane,
  options,
}

/// The project menu, under the project's name.
enum _ProjectMenu {
  shortcuts,
  preview,
  storePreview,
  storeCopy,
  appIcon,
  languages,
  translate,
  translateAll,
  rename,
  duplicate,
  backup,
  delete,
  lockCanvas,
  continuous,
}

/// The target menu's actions, under the target switcher.
enum _TargetMenu { add, canvas, copyScreens, move, copy, remove }

/// The studio's top bar.
///
/// Left to right, what the work *is* and then what to do with it: back, the
/// project, the target, history, preview, and Download. Download is the one
/// filled button on the bar because it is the point of the whole app.
class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.project,
    required this.sub,
    required this.compact,
    required this.preview,
    required this.busy,
    required this.canUndo,
    required this.canRedo,
    required this.canvasLocked,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onTogglePreview,
    required this.onSelectTarget,
    required this.onTargetAction,
    required this.onProjectAction,
    required this.onDownload,
    required this.hasOtherProjects,
    required this.language,
    required this.onLanguage,
    required this.onManageLanguages,
    required this.onTranslate,
    required this.onTranslateAll,
    required this.exportSummary,
    this.lockable = false,
    this.roomy = true,
  });

  /// The export format and scale, as the Download menu names them.
  final String exportSummary;

  /// A desktop's width. Anything narrower that is not [compact] — a tablet,
  /// a phone on its side — sheds the readouts it can live without: the canvas
  /// size is on the canvas toolbar anyway, and Preview keeps its glyph.
  final bool roomy;

  /// The language on show, as a store code.
  final String language;
  final ValueChanged<String> onLanguage;
  final VoidCallback onManageLanguages;
  final VoidCallback onTranslate;

  /// Fills in every missing translation, on the device.
  final VoidCallback onTranslateAll;

  final Project project;
  final SubProject sub;

  /// A phone: the project's name moves into the overflow menu and the
  /// controls lose their labels.
  final bool compact;
  final bool preview;
  final bool busy;
  final bool canUndo;
  final bool canRedo;

  /// Whether the phone sheet floats over the canvas instead of shrinking it.
  /// Offered only where there is a sheet, see [lockable].
  final bool canvasLocked;
  final bool lockable;

  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onTogglePreview;
  final ValueChanged<String> onSelectTarget;
  final ValueChanged<_TargetMenu> onTargetAction;
  final ValueChanged<_ProjectMenu> onProjectAction;
  final ValueChanged<_Download> onDownload;
  final bool hasOtherProjects;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Container(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(bottom: BorderSide(color: s.border)),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: StudioSizes.toolbar,
          child: Row(
            children: [
              SizedBox(width: StudioSpace.xs),
              StudioIconButton(
                icon: StudioIcons.back,
                iconSize: 18,
                tooltip: 'Back to projects',
                onPressed: onBack,
              ),
              if (!compact) ...[
                _ProjectButton(
                  project: project,
                  onAction: onProjectAction,
                  maxWidth: roomy ? 220 : 140,
                ),
                SizedBox(width: StudioSpace.s),
              ],
              // All the width the fixed controls leave, and aligned left inside
              // it: sharing that width with a spacer starved the switcher to a
              // sliver on a small phone, narrower than its own icons.
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _TargetButton(
                    project: project,
                    sub: sub,
                    compact: compact,
                    showSize: roomy && !compact,
                    hasOtherProjects: hasOtherProjects,
                    onSelect: onSelectTarget,
                    onAction: onTargetAction,
                  ),
                ),
              ),
              // On a phone too, once there is more than one language: after
              // the toast that announced the switch had gone, nothing on screen
              // said which language the words being edited belonged to.
              if (!compact || project.languages.length > 1) ...[
                _LanguageButton(
                  project: project,
                  language: language,
                  onLanguage: onLanguage,
                  onManage: onManageLanguages,
                  onTranslate: onTranslate,
                  onTranslateAll: onTranslateAll,
                ),
                SizedBox(width: StudioSpace.s),
              ],
              if (!preview) ...[
                StudioIconButton(
                  icon: StudioIcons.undo,
                  iconSize: 17,
                  tooltip: 'Undo',
                  onPressed: canUndo ? onUndo : null,
                ),
                StudioIconButton(
                  icon: StudioIcons.redo,
                  iconSize: 17,
                  tooltip: 'Redo',
                  onPressed: canRedo ? onRedo : null,
                ),
              ],
              SizedBox(width: StudioSpace.xs),
              // A phone has room for history, Download and the menu, and not
              // for a preview button besides — so Preview is in the menu, and
              // once in it the way back out takes history's place.
              if (compact && preview)
                StudioIconButton(
                  icon: StudioIcons.previewOff,
                  iconSize: 18,
                  selected: true,
                  tooltip: 'Back to editing',
                  onPressed: onTogglePreview,
                )
              else if (!compact && !roomy)
                StudioIconButton(
                  icon: preview ? StudioIcons.previewOff : StudioIcons.preview,
                  iconSize: 18,
                  selected: preview,
                  tooltip: preview ? 'Back to editing' : 'Preview',
                  onPressed: onTogglePreview,
                )
              else if (!compact)
                StudioChip(
                  label: preview ? 'Edit' : 'Preview',
                  icon: preview ? StudioIcons.previewOff : StudioIcons.preview,
                  selected: preview,
                  onTap: onTogglePreview,
                ),
              SizedBox(width: StudioSpace.s),
              _DownloadButton(
                sub: sub,
                targets: project.subProjects.length,
                languages: project.languages.length,
                // Offered once anything has a place in the layout: a set
                // fastlane can upload, or store copy deliver or supply reads.
                fastlane:
                    project.subProjects.any(
                      (set) =>
                          set.screens.isNotEmpty &&
                          FastlaneLayout.slotFor(
                                set.target,
                                set.canvas,
                                set.presetId,
                              ) !=
                              null,
                    ) ||
                    hasFastlaneText(project.storeCopy),
                summary: exportSummary,
                compact: compact,
                busy: busy,
                onSelected: onDownload,
              ),
              if (compact)
                _ProjectButton(
                  project: project,
                  onAction: onProjectAction,
                  language: language,
                  overflow: true,
                  lockable: lockable,
                  canvasLocked: canvasLocked,
                  // The canvas toolbar's switch, which a phone has no
                  // toolbar for. Offered once there are screens to join.
                  continuous: sub.screens.length > 1 ? sub.continuous : null,
                ),
              SizedBox(width: StudioSpace.s),
            ],
          ),
        ),
      ),
    );
  }
}

/// The project's name, opening the project menu — or, on a phone, the
/// overflow glyph opening the same menu with the name at its head.
class _ProjectButton extends StatelessWidget {
  const _ProjectButton({
    required this.project,
    required this.onAction,
    this.overflow = false,
    this.lockable = false,
    this.canvasLocked = false,
    this.language,
    this.maxWidth = 220,
    this.continuous,
  });

  /// Whether the set is one continuous artwork, or null to leave the switch
  /// out of the menu.
  final bool? continuous;

  /// How wide the name may run before it ellipsises.
  final double maxWidth;

  /// The language on show, named in the overflow menu's language entry.
  final String? language;

  final Project project;
  final ValueChanged<_ProjectMenu> onAction;
  final bool overflow;
  final bool lockable;
  final bool canvasLocked;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return PopupMenuButton<_ProjectMenu>(
      tooltip: 'Project',
      clipBehavior: Clip.antiAlias,
      onSelected: onAction,
      itemBuilder: (context) => [
        if (overflow)
          PopupMenuItem<_ProjectMenu>(
            enabled: false,
            child: Text(
              project.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StudioText.bodyStrong(
                context,
              ).copyWith(color: s.textPrimary),
            ),
          ),
        if (overflow) ...[
          const PopupMenuItem(
            value: _ProjectMenu.preview,
            child: MenuEntry(icon: StudioIcons.preview, label: 'Preview'),
          ),
          const PopupMenuItem(
            value: _ProjectMenu.storePreview,
            child: MenuEntry(
              icon: StudioIcons.storePreview,
              label: 'Store preview',
            ),
          ),
          // And the language chip, which a phone's bar has no room for.
          PopupMenuItem(
            value: _ProjectMenu.languages,
            child: MenuEntry(
              icon: StudioIcons.web,
              label:
                  'Languages · ${localeFor(language ?? kDefaultLanguage).short}',
            ),
          ),
          if (project.languages.length > 1) ...[
            const PopupMenuItem(
              value: _ProjectMenu.translate,
              child: MenuEntry(
                icon: StudioIcons.text,
                label: 'Translate texts…',
              ),
            ),
            const PopupMenuItem(
              value: _ProjectMenu.translateAll,
              child: MenuEntry(
                icon: StudioIcons.filters,
                label: 'Translate automatically…',
              ),
            ),
          ],
          if (continuous case final on?)
            PopupMenuItem(
              value: _ProjectMenu.continuous,
              child: MenuEntry(
                icon: on ? StudioIcons.check : StudioIcons.layout,
                label: on ? 'Continuous canvas · on' : 'Continuous canvas',
              ),
            ),
        ],
        // The listing's words, on every form factor: the one page that
        // writes the name, subtitle, keywords and descriptions.
        const PopupMenuItem(
          value: _ProjectMenu.storeCopy,
          child: MenuEntry(icon: StudioIcons.storeCopy, label: 'Store copy'),
        ),
        // And the icon every store shows beside them, designed once and
        // exported for all of them.
        const PopupMenuItem(
          value: _ProjectMenu.appIcon,
          child: MenuEntry(icon: StudioIcons.appIcon, label: 'App icon'),
        ),
        if (lockable)
          PopupMenuItem(
            value: _ProjectMenu.lockCanvas,
            child: MenuEntry(
              icon: canvasLocked ? StudioIcons.lock : StudioIcons.lockOpen,
              label: canvasLocked
                  ? 'Unlock the canvas size'
                  : 'Lock the canvas size',
            ),
          ),
        // Not on a phone, which has no keyboard to press them on.
        if (!overflow)
          const PopupMenuItem(
            value: _ProjectMenu.shortcuts,
            child: MenuEntry(
              icon: StudioIcons.info,
              label: 'Keyboard shortcuts',
            ),
          ),
        const PopupMenuItem(
          value: _ProjectMenu.rename,
          child: MenuEntry(icon: StudioIcons.edit, label: 'Rename project'),
        ),
        const PopupMenuItem(
          value: _ProjectMenu.duplicate,
          child: MenuEntry(
            icon: StudioIcons.duplicate,
            label: 'Duplicate project',
          ),
        ),
        const PopupMenuItem(
          value: _ProjectMenu.backup,
          child: MenuEntry(icon: StudioIcons.save, label: 'Back up project'),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: _ProjectMenu.delete,
          child: MenuEntry(
            icon: StudioIcons.delete,
            label: 'Delete project',
            danger: true,
          ),
        ),
      ],
      child: overflow
          ? SizedBox.square(
              dimension: StudioSizes.toolButton + StudioSpace.xs,
              child: Center(
                child: StudioIcon(
                  StudioIcons.moreVertical,
                  size: 18,
                  color: s.textSecondary,
                ),
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: StudioSpace.s,
                  vertical: StudioSpace.s,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        project.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: StudioText.titleSmall(
                          context,
                        ).copyWith(color: s.textPrimary),
                      ),
                    ),
                    SizedBox(width: StudioSpace.xs),
                    StudioIcon(
                      StudioIcons.expand,
                      size: 11,
                      color: s.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The target switcher: which store deliverable is on the canvas, and every
/// action that is about a target rather than a screen.
class _TargetButton extends StatelessWidget {
  const _TargetButton({
    required this.project,
    required this.sub,
    required this.compact,
    required this.hasOtherProjects,
    required this.onSelect,
    required this.onAction,
    this.showSize = true,
  });

  final Project project;
  final SubProject sub;
  final bool compact;

  /// Whether the canvas size rides along beside the target's name.
  final bool showSize;
  final bool hasOtherProjects;
  final ValueChanged<String> onSelect;
  final ValueChanged<_TargetMenu> onAction;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final others = project.subProjects.length > 1;
    final size = '${sub.canvas.width.round()} × ${sub.canvas.height.round()}';

    return PopupMenuButton<Object>(
      tooltip: 'Store target',
      clipBehavior: Clip.antiAlias,
      onSelected: (value) => switch (value) {
        final String id => onSelect(id),
        final _TargetMenu action => onAction(action),
        _ => null,
      },
      itemBuilder: (context) => [
        for (final other in project.subProjects)
          PopupMenuItem<Object>(
            value: other.id,
            child: Row(
              children: [
                StudioIcon(
                  _formFactorIcon(other.target.formFactor),
                  size: 14,
                  color: other.id == sub.id ? s.accent : s.textSecondary,
                ),
                SizedBox(width: StudioSpace.m),
                Expanded(
                  child: Text(
                    other.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: StudioText.body(context).copyWith(
                      color: other.id == sub.id ? s.accent : s.textPrimary,
                    ),
                  ),
                ),
                SizedBox(width: StudioSpace.m),
                Text(
                  '${other.screens.length}',
                  style: StudioText.mono(
                    context,
                  ).copyWith(color: s.textSecondary),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem<Object>(
          value: _TargetMenu.add,
          child: MenuEntry(icon: StudioIcons.add, label: 'Add target…'),
        ),
        const PopupMenuItem<Object>(
          value: _TargetMenu.canvas,
          child: MenuEntry(
            icon: StudioIcons.aspectRatio,
            label: 'Canvas size…',
          ),
        ),
        if (others)
          const PopupMenuItem<Object>(
            value: _TargetMenu.copyScreens,
            child: MenuEntry(
              icon: StudioIcons.duplicate,
              label: 'Copy screens from…',
            ),
          ),
        if (hasOtherProjects && others)
          PopupMenuItem<Object>(
            value: _TargetMenu.move,
            child: MenuEntry(
              icon: StudioIcons.moveRight,
              label: 'Move ${sub.label} to another project…',
            ),
          ),
        if (hasOtherProjects)
          PopupMenuItem<Object>(
            value: _TargetMenu.copy,
            child: MenuEntry(
              icon: StudioIcons.duplicate,
              label: 'Copy ${sub.label} to another project…',
            ),
          ),
        if (others)
          PopupMenuItem<Object>(
            value: _TargetMenu.remove,
            child: MenuEntry(
              icon: StudioIcons.delete,
              label: 'Remove ${sub.label}',
              danger: true,
            ),
          ),
      ],
      child: Container(
        height: StudioSizes.buttonCompact,
        padding: EdgeInsets.symmetric(horizontal: StudioSpace.m),
        decoration: BoxDecoration(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // The label names the target already; on a phone the glyph is the
            // width the label needs more.
            if (!compact) ...[
              StudioIcon(
                _formFactorIcon(sub.target.formFactor),
                size: 13,
                color: s.textSecondary,
              ),
              SizedBox(width: StudioSpace.s),
            ],
            Flexible(
              child: Text(
                sub.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioText.body(context).copyWith(color: s.textPrimary),
              ),
            ),
            if (showSize) ...[
              SizedBox(width: StudioSpace.s),
              Text(
                size,
                style: StudioText.mono(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ],
            SizedBox(width: StudioSpace.xs),
            StudioIcon(StudioIcons.expand, size: 11, color: s.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// The glyph for a target's form factor.
StudioIconData _formFactorIcon(TargetFormFactor form) => switch (form) {
  TargetFormFactor.phone => StudioIcons.phone,
  TargetFormFactor.tablet => StudioIcons.tablet,
  TargetFormFactor.desktop => StudioIcons.cropLandscape,
  TargetFormFactor.graphic => StudioIcons.image,
  TargetFormFactor.watch => StudioIcons.device,
};

/// The filled Download button and its menu.
class _DownloadButton extends StatelessWidget {
  const _DownloadButton({
    required this.sub,
    required this.targets,
    required this.compact,
    required this.busy,
    required this.onSelected,
    this.languages = 1,
    this.summary = 'PNG · 1×',
    this.fastlane = false,
  });

  final SubProject sub;
  final int targets;

  /// Whether any set in the project has a place in a fastlane layout, which is
  /// when the fastlane ZIP is worth offering.
  final bool fastlane;

  /// The format and scale exports are written at, e.g. `PNG · 1×`.
  final String summary;

  /// How many languages the project is made in.
  final int languages;
  final bool compact;
  final bool busy;
  final ValueChanged<_Download> onSelected;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final n = sub.screens.length;
    final empty = n == 0;

    return PopupMenuButton<_Download>(
      tooltip: 'Download',
      enabled: !busy,
      clipBehavior: Clip.antiAlias,
      onSelected: onSelected,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _Download.screen,
          enabled: !empty,
          child: MenuEntry(
            icon: StudioIcons.image,
            label: 'This screen · ${summary.split(' · ').first}',
          ),
        ),
        // The screen with its devices moving — the 3D bodies turning, as a
        // loop. MP4 where the device has an encoder, a GIF where it does not.
        PopupMenuItem(
          value: _Download.video,
          enabled: !empty,
          child: const MenuEntry(
            icon: StudioIcons.video,
            label: 'This screen as video…',
          ),
        ),
        PopupMenuItem(
          value: _Download.copy,
          enabled: !empty,
          child: const MenuEntry(
            icon: StudioIcons.duplicate,
            label: 'Copy this screen',
          ),
        ),
        PopupMenuItem(
          value: _Download.target,
          enabled: !empty,
          child: MenuEntry(
            icon: StudioIcons.images,
            label:
                'All $n ${sub.label} screens · ${summary.split(' · ').first}',
          ),
        ),
        PopupMenuItem(
          value: _Download.targetZip,
          enabled: !empty,
          child: MenuEntry(
            icon: StudioIcons.archive,
            label: 'All $n ${sub.label} screens · ZIP',
          ),
        ),
        if (languages > 1)
          PopupMenuItem(
            value: _Download.everyLanguage,
            enabled: !empty,
            child: MenuEntry(
              icon: StudioIcons.archive,
              label: 'Every language ($languages) · ZIP',
            ),
          ),
        if (targets > 1)
          PopupMenuItem(
            value: _Download.allZip,
            child: MenuEntry(
              icon: StudioIcons.archive,
              label: 'Every target ($targets) · ZIP',
            ),
          ),
        if (targets > 1 && languages > 1)
          const PopupMenuItem(
            value: _Download.everything,
            child: MenuEntry(
              icon: StudioIcons.archive,
              label: 'Everything: every target, every language · ZIP',
            ),
          ),
        // Every App Store and Play set, every language, in the folders
        // `fastlane deliver` and `fastlane supply` upload from.
        if (fastlane)
          const PopupMenuItem(
            value: _Download.fastlane,
            child: MenuEntry(
              icon: StudioIcons.archive,
              label: 'fastlane layout · ZIP',
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _Download.options,
          child: MenuEntry(
            icon: StudioIcons.settings,
            label: 'Format: $summary…',
          ),
        ),
      ],
      child: Container(
        // Taller where touch is primary: 30px is a desktop target.
        height: context.layout.isTouchPrimary
            ? StudioSizes.buttonTouchDense
            : StudioSizes.buttonCompact,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? StudioSpace.m : StudioSpace.l,
        ),
        decoration: BoxDecoration(
          // Busy stays the accent, faded, under a spinner. It used to fade to
          // the accent wash, which put the white label at 1.23:1 on the light
          // theme — the button went blank for exactly as long as an export
          // took, with nothing to say it was working.
          color: busy ? s.accent.withValues(alpha: 0.7) : s.accent,
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              SizedBox.square(
                dimension: 21,
                child: Center(
                  child: SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: context.reduceMotion ? 0.75 : null,
                      color: s.onAccent,
                    ),
                  ),
                ),
              )
            else
              StudioIcon(StudioIcons.export, size: 14, color: s.onAccent),
            if (!compact) ...[
              SizedBox(width: StudioSpace.s),
              Text(
                'Download',
                style: StudioText.bodyStrong(
                  context,
                ).copyWith(color: s.onAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Panels
// -----------------------------------------------------------------------------

/// A docked side panel: a titled column with a close button.
class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.title,
    required this.onClose,
    required this.child,
  });

  final String title;
  final VoidCallback onClose;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return ColoredBox(
      color: s.panel,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            StudioPaneHeader(
              title: title,
              actions: [
                StudioIconButton(
                  icon: StudioIcons.close,
                  iconSize: 15,
                  tooltip: 'Hide panel',
                  onPressed: onClose,
                ),
              ],
            ),
            Expanded(
              // Height requests are a phone-sheet concept — a side panel is
              // already as tall as the window.
              child: NotificationListener<ToolSheetHeightRequest>(
                onNotification: (_) => true,
                // The inspector's tone, published so its controls take the
                // `control` fill rather than guessing the canvas.
                child: StudioSurface(color: s.panel, child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The floating bar under the canvas: its size, and the zoom.
class _CanvasToolbar extends StatelessWidget {
  const _CanvasToolbar({
    required this.canvas,
    required this.zoom,
    required this.onCanvas,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onFit,
    required this.onReset,
    required this.continuous,
    required this.onContinuous,
    required this.onStorePreview,
  });

  final Size canvas;

  /// Opens the set inside a mock store listing.
  final VoidCallback onStorePreview;

  /// Whether the set is one continuous artwork; see [SubProject.continuous].
  final bool continuous;

  /// Null when the set has a single screen, where continuity means nothing.
  final VoidCallback? onContinuous;
  final double zoom;
  final VoidCallback onCanvas;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onFit;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    Widget separator() => Container(
      width: 1,
      height: 18,
      margin: EdgeInsets.symmetric(horizontal: StudioSpace.xs),
      color: s.border,
    );

    return Container(
      height: StudioSizes.button,
      padding: EdgeInsets.symmetric(horizontal: StudioSpace.xs),
      decoration: BoxDecoration(
        color: s.overlay,
        borderRadius: BorderRadius.circular(StudioRadius.md),
        // A floating overlay, so it keeps its hairline.
        border: Border.all(color: s.border),
        boxShadow: [
          BoxShadow(
            color: StudioInk.scrim.withValues(alpha: 0.18),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Canvas size',
            child: InkWell(
              onTap: onCanvas,
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: StudioSpace.m,
                  vertical: StudioSpace.s,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    StudioIcon(
                      StudioIcons.aspectRatio,
                      size: 13,
                      color: s.textSecondary,
                    ),
                    SizedBox(width: StudioSpace.s),
                    Text(
                      '${canvas.width.round()} × ${canvas.height.round()}',
                      style: StudioText.mono(
                        context,
                      ).copyWith(color: s.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          separator(),
          StudioIconButton(
            icon: StudioIcons.zoomOut,
            iconSize: 13,
            tooltip: 'Zoom out',
            onPressed: onZoomOut,
          ),
          Tooltip(
            message: 'Back to the active screen',
            child: InkWell(
              onTap: onReset,
              borderRadius: BorderRadius.circular(StudioRadius.sm),
              child: SizedBox(
                width: 48,
                child: Center(
                  child: Text(
                    '${(zoom * 100).round()}%',
                    style: StudioText.mono(
                      context,
                    ).copyWith(color: s.textPrimary),
                  ),
                ),
              ),
            ),
          ),
          StudioIconButton(
            icon: StudioIcons.zoomIn,
            iconSize: 13,
            tooltip: 'Zoom in',
            onPressed: onZoomIn,
          ),
          separator(),
          StudioIconButton(
            icon: StudioIcons.screens,
            iconSize: 14,
            tooltip: 'Fit every screen',
            onPressed: onFit,
          ),
          separator(),
          StudioIconButton(
            icon: StudioIcons.layout,
            iconSize: 14,
            selected: continuous,
            tooltip: continuous
                ? 'Continuous canvas is on — screens share one artwork'
                : 'Continuous canvas: let layers and the background run across '
                      'screens',
            onPressed: onContinuous,
          ),
          // A storefront, not the Play logo: beside a video export the logo
          // read as a "play" triangle.
          StudioIconButton(
            icon: StudioIcons.storePreview,
            iconSize: 14,
            tooltip: 'Store preview',
            onPressed: onStorePreview,
          ),
        ],
      ),
    );
  }
}

/// A phone's one sheet: a library over the tab bar of libraries, or the
/// selection's properties over a bar about the selection.
///
/// The selection's bar *replaces* the tab bar rather than stacking on it, at
/// the same height. A second bar would come out of the panel's own height, and
/// on a small phone that is the difference between a layer list of three rows
/// and one of two. It is also where the eye already is: the bottom edge is
/// where a phone keeps what the current thing can do.
class _PhoneSheet extends StatelessWidget {
  const _PhoneSheet({
    required this.library,
    required this.onLibrary,
    required this.propertiesTitle,
    required this.onCloseProperties,
    required this.onLayers,
    required this.layersSelected,
    required this.onLayersTab,
    required this.expanded,
    required this.onToggleExpanded,
    required this.child,
  });

  final _Library library;
  final ValueChanged<_Library> onLibrary;

  /// Whether the sheet is showing the layers list, which the tab bar offers
  /// beside the libraries: on a phone it is the only way to the layers that
  /// does not go through a selection first.
  final bool layersSelected;
  final VoidCallback onLayersTab;

  /// The selection's name, or null while the sheet shows a library.
  final String? propertiesTitle;
  final VoidCallback onCloseProperties;
  final VoidCallback onLayers;

  /// Whether the sheet is pulled up, showing the panel above the title bar.
  final bool expanded;

  /// Pulls the panel up or tucks it away, so the whole canvas can be seen
  /// without letting go of the selection.
  final VoidCallback onToggleExpanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final title = propertiesTitle;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: s.panel,
        border: Border(top: BorderSide(color: s.border)),
      ),
      child: Column(
        children: [
          // The sheet's tone, published so its controls take the `control`
          // fill rather than guessing the canvas.
          Expanded(
            child: StudioSurface(color: s.panel, child: child),
          ),
          SafeArea(
            top: false,
            child: title == null
                ? StudioTabStrip(
                    // Always captioned: the glyphs alone left "¶" and a
                    // landscape to be guessed at. Seven captioned tabs do not
                    // fit a phone, so the strip scrolls rather than shrinking
                    // "Background" until it can no longer be read.
                    showLabels: true,
                    minTabWidth: 64,
                    // Layers first: it is this screen's own contents rather
                    // than a library to add from, and it is never the tab
                    // hidden off the end.
                    //
                    // No tab is lit while the sheet is tucked away: a filled
                    // Templates tab over a collapsed sheet said "this is open"
                    // about something nobody could see.
                    currentIndex: !expanded
                        ? -1
                        : layersSelected
                        ? 0
                        : library.index + 1,
                    items: [
                      const StudioTabItem(StudioIcons.layers, 'Layers'),
                      for (final l in _Library.values)
                        StudioTabItem(l.icon, l.label),
                    ],
                    onChanged: (i) => i == 0
                        ? onLayersTab()
                        : onLibrary(_Library.values[i - 1]),
                  )
                : Container(
                    height: StudioSizes.tabStrip,
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: s.border)),
                    ),
                    padding: EdgeInsets.symmetric(horizontal: StudioSpace.m),
                    child: Row(
                      children: [
                        StudioIconButton(
                          icon: StudioIcons.back,
                          iconSize: 16,
                          tooltip: 'Back to the libraries',
                          onPressed: onCloseProperties,
                        ),
                        SizedBox(width: StudioSpace.s),
                        Expanded(
                          // The whole title is a handle: a tap anywhere on it
                          // shows or hides the tools, like the chevron beside it.
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: onToggleExpanded,
                            child: SizedBox(
                              height: StudioSizes.tabStrip,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: StudioText.titleSmall(
                                    context,
                                  ).copyWith(color: s.textPrimary),
                                ),
                              ),
                            ),
                          ),
                        ),
                        StudioIconButton(
                          icon: expanded
                              ? StudioIcons.expand
                              : StudioIcons.collapse,
                          iconSize: 14,
                          tooltip: expanded ? 'Hide tools' : 'Show tools',
                          onPressed: onToggleExpanded,
                        ),
                        StudioIconButton(
                          icon: StudioIcons.layers,
                          iconSize: 16,
                          tooltip: 'Layers',
                          onPressed: onLayers,
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// Which language the set is shown and edited in, and the way into managing
/// and translating languages.
class _LanguageButton extends StatelessWidget {
  const _LanguageButton({
    required this.project,
    required this.language,
    required this.onLanguage,
    required this.onManage,
    required this.onTranslate,
    required this.onTranslateAll,
  });

  final Project project;
  final String language;
  final ValueChanged<String> onLanguage;
  final VoidCallback onManage;
  final VoidCallback onTranslate;
  final VoidCallback onTranslateAll;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    const manage = '\u0000manage';
    const translate = '\u0000translate';
    const translateAll = '\u0000translateAll';
    return PopupMenuButton<String>(
      tooltip: 'Language',
      clipBehavior: Clip.antiAlias,
      onSelected: (v) => switch (v) {
        manage => onManage(),
        translate => onTranslate(),
        translateAll => onTranslateAll(),
        _ => onLanguage(v),
      },
      itemBuilder: (context) => [
        for (final (i, code) in project.languages.indexed)
          PopupMenuItem(
            value: code,
            child: Row(
              children: [
                SizedBox(
                  width: 18,
                  child: code == language
                      ? StudioIcon(StudioIcons.check, size: 13, color: s.accent)
                      : null,
                ),
                SizedBox(width: StudioSpace.s),
                Expanded(
                  child: Text(
                    localeFor(code).name,
                    style: StudioText.body(context).copyWith(
                      color: code == language ? s.accent : s.textPrimary,
                    ),
                  ),
                ),
                if (i == 0)
                  Text(
                    'Default',
                    style: StudioText.caption(
                      context,
                    ).copyWith(color: s.textSecondary),
                  ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: manage,
          child: MenuEntry(icon: StudioIcons.add, label: 'Languages…'),
        ),
        if (project.languages.length > 1) ...[
          const PopupMenuItem(
            value: translate,
            child: MenuEntry(icon: StudioIcons.text, label: 'Translate texts…'),
          ),
          const PopupMenuItem(
            value: translateAll,
            child: MenuEntry(
              icon: StudioIcons.filters,
              label: 'Translate automatically…',
            ),
          ),
        ],
      ],
      child: Container(
        height: StudioSizes.buttonCompact,
        padding: EdgeInsets.symmetric(horizontal: StudioSpace.m),
        decoration: BoxDecoration(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StudioIcon(StudioIcons.web, size: 13, color: s.textSecondary),
            SizedBox(width: StudioSpace.s),
            Text(
              localeFor(language).short,
              style: StudioText.mono(context).copyWith(color: s.textPrimary),
            ),
            SizedBox(width: StudioSpace.xs),
            StudioIcon(StudioIcons.expand, size: 11, color: s.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Format, resolution and quality for exports. Resolves to the new settings,
/// or null if dismissed.
Future<ExportSettings?> _showExportOptions(
  BuildContext context,
  ExportSettings current,
) => showStudioSheet<ExportSettings>(
  context,
  title: 'Export format',
  child: _ExportOptions(initial: current),
);

class _ExportOptions extends StatefulWidget {
  const _ExportOptions({required this.initial});

  final ExportSettings initial;

  @override
  State<_ExportOptions> createState() => _ExportOptionsState();
}

class _ExportOptionsState extends State<_ExportOptions> {
  late ExportSettings _settings = widget.initial;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
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
          const StudioSectionHeader(label: 'Format'),
          SizedBox(height: StudioSpace.s),
          StudioSegmented<ExportFormat>(
            dense: true,
            segments: const [
              StudioSegment(ExportFormat.png, 'PNG'),
              StudioSegment(ExportFormat.jpg, 'JPG'),
            ],
            value: _settings.format,
            onChanged: (f) =>
                setState(() => _settings = _settings.copyWith(format: f)),
          ),
          SizedBox(height: StudioSpace.s),
          Text(
            _settings.format == ExportFormat.png
                ? 'Lossless. What both stores recommend.'
                : 'Smaller files. Transparency is flattened onto white.',
            style: StudioText.caption(context).copyWith(color: s.textTertiary),
          ),
          if (_settings.format == ExportFormat.jpg) ...[
            SizedBox(height: StudioSpace.m),
            StudioSlider(
              label: 'Quality',
              value: _settings.jpegQuality.toDouble(),
              min: 50,
              max: 100,
              step: 1,
              display: (v) => '${v.round()}',
              onChanged: (v) => setState(
                () => _settings = _settings.copyWith(jpegQuality: v.round()),
              ),
            ),
          ],
          SizedBox(height: StudioSpace.l),
          const StudioSectionHeader(label: 'Resolution'),
          SizedBox(height: StudioSpace.s),
          Wrap(
            spacing: StudioSpace.s,
            children: [
              for (final scale in ExportSettings.scales)
                StudioChip(
                  label: scale == 0.5 ? '½×' : '${scale.toInt()}×',
                  selected: _settings.scale == scale,
                  onTap: () => setState(
                    () => _settings = _settings.copyWith(scale: scale),
                  ),
                ),
            ],
          ),
          SizedBox(height: StudioSpace.s),
          Text(
            _settings.scale == 1
                ? 'Exactly the canvas size — what the stores accept.'
                : 'For single screens: press kits, print and previews. Sets '
                      'and ZIPs always export at 1×, the size the stores take.',
            style: StudioText.caption(context).copyWith(
              color: _settings.scale == 1 ? s.textTertiary : s.warning,
            ),
          ),
          SizedBox(height: StudioSpace.xl),
          StudioButton(
            label: 'Use ${_settings.summary}',
            variant: StudioButtonVariant.primary,
            fullWidth: true,
            onPressed: () => Navigator.pop(context, _settings),
          ),
        ],
      ),
    );
  }
}

/// What the layer context menu offers.
enum _LayerMenu {
  copy,
  duplicate,
  paste,
  front,
  forward,
  backward,
  back,
  lock,
  unlock,
  hide,
  delete,
}

/// Where the floating canvas toolbar sits in the workspace.
///
/// Centred on the workspace — everything right of the tool rail — rather than
/// on the canvas between the panels. The canvas narrows each time a panel
/// slides open beside it, which is every time a layer is selected, and a bar
/// centred on it walked half a panel's width across the screen and back while
/// the screens behind it stayed where they were. Now it moves only as far as
/// an open panel would otherwise cover it.
class _ToolbarPlacement extends SingleChildLayoutDelegate {
  const _ToolbarPlacement({
    required this.start,
    required this.left,
    required this.right,
  });

  /// Where the workspace begins: the tool rail's width.
  final double start;

  /// The canvas's own left edge, past the rail and any open panel beside it.
  final double left;

  /// How much of the right-hand side an open panel takes.
  final double right;

  static const double _margin = StudioSpace.l;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(
        Size(
          math.max(0, constraints.maxWidth - left - right - 2 * _margin),
          constraints.maxHeight,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final centre = start + (size.width - start) / 2;
    final lowest = left + _margin;
    final highest = math.max(
      lowest,
      size.width - right - _margin - childSize.width,
    );
    return Offset(
      (centre - childSize.width / 2).clamp(lowest, highest),
      size.height - childSize.height - _margin,
    );
  }

  @override
  bool shouldRelayout(_ToolbarPlacement oldDelegate) =>
      oldDelegate.start != start ||
      oldDelegate.left != left ||
      oldDelegate.right != right;
}

/// Every keyboard shortcut, for the `?` key and the project menu.
Future<void> _showShortcuts(BuildContext context) {
  final mod =
      defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.iOS
      ? '⌘'
      : 'Ctrl+';
  final rows = <(String, String)>[
    ('Undo / redo', '${mod}Z  ·  $mod⇧Z'),
    ('Copy, cut, paste', '${mod}C  ·  ${mod}X  ·  ${mod}V'),
    ('Duplicate', '${mod}D'),
    ('Delete the selected layer', 'Delete'),
    ('Nudge 1 px / 10 px', 'Arrows  ·  ⇧ Arrows'),
    ('Drag without snapping', 'Hold Alt'),
    ('Save this screen', '${mod}S'),
    ('Zoom in / out', '$mod+  ·  $mod−'),
    ('Back to the active screen', '${mod}0'),
    ('Fit every screen', '⇧1'),
    ('Pan', 'Space + drag  ·  scroll'),
    ('Open a library', '1 – 7'),
    ('Preview', 'P'),
    ('Deselect, close', 'Esc'),
    ('This list', '?'),
  ];
  return showStudioSheet<void>(
    context,
    title: 'Keyboard shortcuts',
    child: Builder(
      builder: (sheet) {
        final s = sheet.studio;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.m,
            StudioSpace.xl,
            StudioSpace.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (what, keys) in rows)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: StudioSpace.s),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          what,
                          style: StudioText.body(
                            sheet,
                          ).copyWith(color: s.textPrimary),
                        ),
                      ),
                      Text(
                        keys,
                        style: StudioText.mono(
                          sheet,
                        ).copyWith(color: s.textSecondary),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}
