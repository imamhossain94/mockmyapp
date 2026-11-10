import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/device_filter.dart';
import '../../../data/assets/drawn_iphones.dart';
import '../../../data/assets/frame_catalog.dart';
import '../../../data/assets/studio_frames.dart';
import '../../../domain/models/store_target.dart';
import '../../../domain/providers/device_filter_provider.dart';
import '../../shared/widgets/widgets.dart';
import 'custom_device_frame.dart';
import 'drawn_iphone_frame.dart';
import 'frame_artwork.dart';
import 'programmatic_frame.dart';
import 'variant_card.dart' show StandInFrame;

typedef DeviceSelection = (String deviceId, String variantId);

/// Opens the device picker and resolves to the chosen `(deviceId, variantId)`,
/// or `null` if the sheet was dismissed.
///
/// [currentDeviceId] / [currentVariantId] are optional and purely presentational
/// — they mark the active device with an accent check and pre-expand its finish
/// strip. [target] is the set's store target, which decides what the list
/// opens on; see [DevicePickerList.target].
Future<DeviceSelection?> showDevicePicker(
  BuildContext context, {
  required FrameCatalog catalog,
  StoreTarget? target,
  String? currentDeviceId,
  String? currentVariantId,
}) {
  return showStudioSheet<DeviceSelection>(
    context,
    title: 'Choose a device',
    child: SizedBox(
      height: context.layout.modalContentHeight(0.74),
      child: DevicePickerList(
        catalog: catalog,
        target: target,
        currentDeviceId: currentDeviceId,
        currentVariantId: currentVariantId,
      ),
    ),
  );
}

/// The device list itself, without the sheet around it.
///
/// Public so the editor can dock it in its Devices panel, where a pick is
/// applied on the spot and the list stays open ([onSelected]). Inside a sheet
/// it pops with the choice instead.
///
/// One structure at every size — the 460px phone sheet and the desktop side
/// panel alike: a search field, then a single scrolling row of chips (the
/// form-factor menu, then one chip per maker), then the list. A second chip
/// row would cost a phone sheet a whole device row, and the form factor rarely
/// changes — the set decides it — so it lives behind one chip rather than a
/// row of its own. The rules behind every chip are in `device_filter.dart`.
class DevicePickerList extends ConsumerStatefulWidget {
  const DevicePickerList({
    super.key,
    required this.catalog,
    this.target,
    this.currentDeviceId,
    this.currentVariantId,
    this.onSelected,
  });

  final FrameCatalog catalog;

  /// The store target of the set being edited.
  ///
  /// It decides the form factor the list opens on (an iPad set opens on
  /// Tablets), which half of the catalog the maker is remembered for, and,
  /// for the targets that wear a handset, whether "Only {store} devices" is
  /// offered. Null opens on every device with no store scope.
  final StoreTarget? target;

  final String? currentDeviceId;
  final String? currentVariantId;

  /// Receives the chosen device and finish. Null pops the enclosing route.
  final ValueChanged<DeviceSelection>? onSelected;

  @override
  ConsumerState<DevicePickerList> createState() => _DevicePickerListState();
}

class _DevicePickerListState extends ConsumerState<DevicePickerList> {
  late final TextEditingController _search;
  final ScrollController _scroll = ScrollController();

  /// On the current device's row, so the list can be scrolled to it on open.
  final GlobalKey _currentKey = GlobalKey();

  String? _expandedDeviceId;

  /// Whether the user has opened or closed a row yet. Until then the current
  /// device is open only because the list opened that way.
  bool _toggled = false;

  /// A watch set opens on an explanation rather than a list: neither store
  /// wants a watch screenshot in a frame, and there are no watch frames to
  /// offer. Cleared by "Show all devices".
  late bool _watchNotice;

  final Set<String> _warmedAssets = {};
  bool _warmedOnce = false;

  String get _targetKey => widget.target?.id ?? '';

  /// The half of the catalog the maker is remembered for.
  FramePlatform get _platform =>
      widget.target?.catalogPlatform ?? FramePlatform.ios;

  bool get _scopeOffered => scopesByStore(widget.target);

  DeviceKind? _kind(DeviceFilterState prefs) {
    final target = widget.target;
    return prefs.kindFor(
      _targetKey,
      target == null ? null : defaultKindFor(target, widget.catalog),
    );
  }

  bool _scoped(DeviceFilterState prefs) => _scopeOffered && prefs.scope;

  DeviceFilterResult _resultFor(DeviceFilterState prefs) => DeviceFilter(
    kind: _kind(prefs),
    maker: prefs.makerFor(_platform),
    query: prefs.query,
    scope: _scoped(prefs) ? widget.target!.framePlatform : null,
    twinPlatform: widget.target?.catalogPlatform,
  ).apply(widget.catalog, currentDeviceId: widget.currentDeviceId);

  FrameDevice? _deviceById(String? id) {
    if (id == null) return null;
    for (final d in widget.catalog.devices) {
      if (d.id == id) return d;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(deviceFilterProvider);
    _search = TextEditingController(text: prefs.query);
    _watchNotice = widget.target?.formFactor == TargetFormFactor.watch;

    final current = _deviceById(widget.currentDeviceId);
    if (current != null) {
      _expandedDeviceId = current.id;
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealCurrent());
    } else {
      final devices = _resultFor(prefs).devices;
      if (devices.isNotEmpty) _expandedDeviceId = devices.first.id;
    }
  }

  @override
  void didUpdateWidget(DevicePickerList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The editor keeps this list when the user moves to another set, so the
    // watch explanation follows the set rather than the first one shown.
    if (oldWidget.target?.id != widget.target?.id) {
      _watchNotice = widget.target?.formFactor == TargetFormFactor.watch;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_warmedOnce) {
      _warmedOnce = true;
      final expanded = _deviceById(_expandedDeviceId);
      if (expanded != null) _warmVariants([expanded]);
    }
  }

  /// Scrolls the current device into view when the list opened with it out
  /// of sight — a Xiaomi at the bottom of an Android list, say. Left alone
  /// whenever its row is already on screen, so the list does not lurch past
  /// the store line at its head for a row the user can already see.
  void _revealCurrent() {
    final context = _currentKey.currentContext;
    if (!mounted || context == null || !_scroll.hasClients) return;
    final box = context.findRenderObject();
    if (box is! RenderBox) return;
    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return;
    final position = _scroll.position;
    final top = viewport.getOffsetToReveal(box, 0).offset;
    final bottom = top + box.size.height;
    if (bottom <= position.pixels + position.viewportDimension) return;
    position.jumpTo(
      (top - StudioSpace.xl).clamp(0.0, position.maxScrollExtent),
    );
  }

  /// Decodes each variant's artwork ahead of the editor needing it, so
  /// selecting a device never stalls on a cold asset.
  void _warmVariants(List<FrameDevice> devices) {
    for (final device in devices) {
      for (final v in device.variants) {
        if (v.asset.isEmpty || !_warmedAssets.add(v.asset)) continue;
        if (v.isVector) {
          final loader = SvgAssetLoader(v.asset);
          svg.cache.putIfAbsent(
            loader.cacheKey(null),
            () => loader.loadBytes(null),
          );
        } else {
          precacheImage(AssetImage(v.asset), context);
        }
      }
    }
  }

  /// Opens or closes [device]'s finishes. [shown] is whether they are open
  /// on screen now, which is not always what [_expandedDeviceId] says — see
  /// [_deviceRow]'s `quiet`.
  void _toggle(FrameDevice device, {required bool shown}) {
    HapticFeedback.selectionClick();
    setState(() {
      _toggled = true;
      _expandedDeviceId = shown ? null : device.id;
    });
    if (_expandedDeviceId == device.id) _warmVariants([device]);
  }

  void _select(FrameDevice device, FrameVariant variant) {
    HapticFeedback.mediumImpact();
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected((device.id, variant.id));
    } else {
      Navigator.of(context).pop((device.id, variant.id));
    }
  }

  DeviceFilterNotifier get _filter => ref.read(deviceFilterProvider.notifier);

  /// Back to the top after anything that changes what the list holds: a
  /// scroll offset into the old list means nothing in the new one.
  void _toTop() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _pickMaker(String? maker) {
    HapticFeedback.selectionClick();
    _filter.setMaker(_platform, maker);
    _toTop();
    // Motorola and Sony have one device each. Picking one of them is asking
    // for that device, so its finishes open without a second tap.
    final devices = _resultFor(ref.read(deviceFilterProvider)).devices;
    if (devices.length == 1) {
      setState(() => _expandedDeviceId = devices.single.id);
      _warmVariants(devices);
    }
  }

  void _pickKind(DeviceKind? kind) {
    _filter.setKind(_targetKey, kind);
    _toTop();
  }

  void _onQuery(String query) {
    _filter.setQuery(query);
    _toTop();
  }

  void _clearQuery() {
    _search.clear();
    _onQuery('');
  }

  void _setScope(bool scope) {
    HapticFeedback.selectionClick();
    _filter.setScope(scope);
    _toTop();
  }

  /// Every kind, maker and store, keeping the search — the way out of every
  /// empty state.
  void _showEverything() {
    setState(() => _watchNotice = false);
    _filter.showEverything(_platform, _targetKey);
    _toTop();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(deviceFilterProvider);
    final result = _resultFor(prefs);
    final kind = _kind(prefs);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          // A short gap underneath: the chip row's touch padding is the rest
          // of it.
          padding: EdgeInsets.fromLTRB(
            StudioSpace.xl,
            StudioSpace.l,
            StudioSpace.xl,
            StudioSpace.xxs,
          ),
          child: StudioTextField(
            controller: _search,
            hint: _hint(result, kind),
            icon: StudioIcons.search,
            textInputAction: TextInputAction.search,
            onChanged: _onQuery,
            trailing: prefs.query.isEmpty
                ? null
                : StudioIconButton(
                    icon: StudioIcons.close,
                    iconSize: 12,
                    tooltip: 'Clear search',
                    onPressed: _clearQuery,
                  ),
          ),
        ),
        _chipRow(result, prefs, kind),
        SizedBox(height: StudioSpace.xxs),
        const StudioDivider(),
        Expanded(child: _body(result, prefs, kind)),
      ],
    );
  }

  /// "Search 24 phones" — the count says how much is behind the filters.
  String _hint(DeviceFilterResult result, DeviceKind? kind) {
    final n = result.searchable;
    if (n == 0) return 'Search devices';
    final noun = kind?.noun(n) ?? (n == 1 ? 'device' : 'devices');
    final maker = result.maker;
    return 'Search $n ${maker == null ? '' : '$maker '}$noun';
  }

  // ---------------------------------------------------------------------------
  // The chip row
  // ---------------------------------------------------------------------------

  Widget _chipRow(
    DeviceFilterResult result,
    DeviceFilterState prefs,
    DeviceKind? kind,
  ) {
    final s = context.studio;
    final makers = result.makers;
    return SizedBox(
      height: _chipRowHeight,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: StudioSpace.xl),
        children: [
          Builder(
            builder: (chipContext) {
              void open() => _openKindMenu(chipContext, result, prefs, kind);
              return _touchTarget(
                onTap: open,
                child: StudioChip(
                  label: kind?.label ?? 'All devices',
                  icon: _kindIcon(kind),
                  trailing: StudioIcon(
                    StudioIcons.expand,
                    size: 10,
                    color: s.textSecondary,
                  ),
                  onTap: open,
                ),
              );
            },
          ),
          // Spaced off rather than ruled off: the menu chip is a different
          // control from the maker chips after it, and the gap says so
          // without a hairline.
          SizedBox(width: StudioSpace.l),
          // Chips for makers only when there is a choice between them. An App
          // Store phone set is Apple and nothing else, and a row reading "All"
          // and "Apple" with the same count offers nothing to choose.
          if (makers.length > 1) ...[
            _makerChip(
              label: 'All',
              count: result.makerTotal,
              selected: result.maker == null,
              onTap: () => _pickMaker(null),
            ),
            for (final (maker, count) in makers) ...[
              SizedBox(width: StudioSpace.s),
              _makerChip(
                label: maker,
                count: count,
                selected: result.maker == maker,
                onTap: () => _pickMaker(maker),
              ),
            ],
          ] else if (makers case [(final maker, final count)])
            Center(
              child: Text(
                '$maker · $count '
                '${kind?.noun(count) ?? (count == 1 ? 'device' : 'devices')}',
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  /// The chip row's height: a full touch target, with the 30px chips centred
  /// in it.
  static const double _chipRowHeight = 44;

  /// Gives a chip the whole height of the row to be tapped in.
  ///
  /// The painted chip is 30px, under the 44px a finger needs. A tap on the
  /// chip itself still lands on the chip's own ink — the innermost recogniser
  /// wins — and one just above or below it lands here instead. Kept out of the
  /// semantics tree, which the chip already describes.
  Widget _touchTarget({required VoidCallback onTap, required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: onTap,
      child: Center(child: child),
    );
  }

  /// A maker chip: the name, then how many devices it has under the current
  /// form factor, store and search. Text only — no logos, which are other
  /// companies' trademarks and which most makers here have no glyph for.
  Widget _makerChip({
    required String label,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final s = context.studio;
    return _touchTarget(
      onTap: onTap,
      child: StudioChip(
        label: label,
        selected: selected,
        onTap: onTap,
        trailing: Text(
          '$count',
          style: StudioText.caption(
            context,
          ).copyWith(color: selected ? s.onAccentSubtle : s.textSecondary),
        ),
      ),
    );
  }

  static StudioIconData _kindIcon(DeviceKind? kind) => switch (kind) {
    null => StudioIcons.allDevices,
    DeviceKind.phone => StudioIcons.phone,
    DeviceKind.foldable => StudioIcons.foldable,
    DeviceKind.tablet => StudioIcons.tablet,
    DeviceKind.computer => StudioIcons.desktop,
    DeviceKind.browser => StudioIcons.web,
    DeviceKind.marketing => StudioIcons.marketingFrame,
  };

  /// The form-factor menu: every kind with something in it, each with its
  /// count, then the store scope as a checkable entry where the set offers
  /// one. Anchored under the chip, so it reads as the chip's own dropdown
  /// rather than a second sheet over the first.
  Future<void> _openKindMenu(
    BuildContext chipContext,
    DeviceFilterResult result,
    DeviceFilterState prefs,
    DeviceKind? kind,
  ) async {
    HapticFeedback.selectionClick();
    final chip = chipContext.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(chipContext).context.findRenderObject()! as RenderBox;
    final anchor = Rect.fromPoints(
      chip.localToGlobal(chip.size.bottomLeft(Offset.zero), ancestor: overlay),
      chip.localToGlobal(chip.size.bottomRight(Offset.zero), ancestor: overlay),
    );
    final target = widget.target;

    final pick = await showMenu<_MenuPick>(
      context: context,
      clipBehavior: Clip.antiAlias,
      position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
      items: [
        PopupMenuItem(
          value: const _MenuPick.kind(null),
          child: _MenuRow(
            icon: _kindIcon(null),
            label: 'All devices',
            count: result.allKindsCount,
            checked: kind == null,
          ),
        ),
        for (final k in DeviceKind.values)
          if ((result.kindCounts[k] ?? 0) > 0 || k == kind)
            PopupMenuItem(
              value: _MenuPick.kind(k),
              child: _MenuRow(
                icon: _kindIcon(k),
                label: k.label,
                count: result.kindCounts[k] ?? 0,
                checked: kind == k,
              ),
            ),
        if (_scopeOffered && target != null) ...[
          const PopupMenuDivider(),
          PopupMenuItem(
            value: const _MenuPick.scope(),
            child: _MenuRow(
              icon: _storeIcon(target),
              label: 'Only ${storeScopeName(target)} devices',
              checked: prefs.scope,
            ),
          ),
        ],
      ],
    );
    if (pick == null || !mounted) return;
    if (pick.toggleScope) {
      _setScope(!prefs.scope);
    } else {
      _pickKind(pick.kind);
    }
  }

  static StudioIconData _storeIcon(StoreTarget target) =>
      target.framePlatform == FramePlatform.ios
      ? StudioIcons.platformApple
      : StudioIcons.platformAndroid;

  // ---------------------------------------------------------------------------
  // The list
  // ---------------------------------------------------------------------------

  Widget _body(
    DeviceFilterResult result,
    DeviceFilterState prefs,
    DeviceKind? kind,
  ) {
    if (_watchNotice && prefs.query.trim().isEmpty) {
      return StudioEmptyState(
        compact: true,
        icon: StudioIcons.devices,
        title: 'Watch screenshots go without a frame',
        message:
            'Apple shows the bare screen, and Google Play asks for Wear OS '
            'screenshots outside device frames.',
        primaryAction: StudioButton(
          label: 'Show all devices',
          variant: StudioButtonVariant.primary,
          dense: true,
          onPressed: _showEverything,
        ),
      );
    }

    final lead = <Widget>[
      if (_scopeOffered) _scopeLine(prefs),
      // The device on this screen is never filtered out of sight: when the
      // filters would hide it, it is pinned above them. Shut over an empty
      // list until asked, so its finishes do not push the empty state —
      // which is the answer to what was just asked — off the bottom of a
      // phone sheet.
      if (result.hiddenCurrent case final current?) ...[
        _header('On this screen'),
        _deviceRow(current, quiet: result.isEmpty),
      ],
    ];

    if (result.isEmpty) {
      // Scrollable, because the pinned row can be opened onto its finishes
      // and a phone sheet has no room for that and an empty state both. The
      // empty state takes whatever height is left, and never less than it
      // needs for its message and action. The `SizedBox` is that floor, and
      // also what the sliver measures: the empty state sizes itself to its
      // box, so it has no intrinsic height of its own to report.
      return CustomScrollView(
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: lead,
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: false,
            child: SizedBox(height: 150, child: _empty(result, prefs, kind)),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      // A plain column rather than a lazy list: the catalog is about fifty
      // rows, and every one of them has to be laid out for the current
      // device's row to be found and scrolled to on open.
      controller: _scroll,
      padding: EdgeInsets.only(bottom: StudioSpace.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...lead,
          for (final group in result.groups) ...[
            if (group.label case final label?)
              _header('$label · ${group.devices.length}'),
            for (final device in group.devices) _deviceRow(device),
          ],
        ],
      ),
    );
  }

  /// The store scope, said in a line at the head of the list with its way
  /// out beside it. On the list rather than in the header so it costs the
  /// phone sheet nothing once scrolled past, and stated rather than tucked in
  /// the menu so nobody wonders where the Pixels went.
  Widget _scopeLine(DeviceFilterState prefs) {
    final s = context.studio;
    final target = widget.target!;
    final store = storeScopeName(target);
    final on = prefs.scope;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.m,
        StudioSpace.xl,
        0,
      ),
      child: Container(
        // Recessed `well`, the same tone as the search field and the finish
        // drawer: a note about the list, not another control on it.
        decoration: BoxDecoration(
          color: s.well,
          borderRadius: BorderRadius.circular(StudioRadius.md),
        ),
        padding: EdgeInsets.fromLTRB(
          StudioSpace.l,
          StudioSpace.xxs,
          StudioSpace.xxs,
          StudioSpace.xxs,
        ),
        child: Row(
          children: [
            StudioIcon(_storeIcon(target), size: 12, color: s.textSecondary),
            SizedBox(width: StudioSpace.m),
            Expanded(
              child: Text(
                on ? 'Only $store devices' : 'Every store',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: StudioText.caption(
                  context,
                ).copyWith(color: s.textSecondary),
              ),
            ),
            StudioButton(
              label: on ? 'Show all' : 'Only $store',
              variant: StudioButtonVariant.ghost,
              dense: true,
              onPressed: () => _setScope(!on),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(
    DeviceFilterResult result,
    DeviceFilterState prefs,
    DeviceKind? kind,
  ) {
    final query = prefs.query.trim();
    if (widget.catalog.devices.isEmpty) {
      return const StudioEmptyState(
        compact: true,
        icon: StudioIcons.devices,
        title: 'No devices found',
        message: 'This catalog has no device frames yet.',
      );
    }

    if (query.isNotEmpty && result.matchesEverywhere == 0) {
      return StudioEmptyState(
        compact: true,
        icon: StudioIcons.search,
        title: 'Nothing matches “$query”',
        message:
            'Try a model, a maker or a finish, like “s25”, “pixel” or '
            '“titanium”.',
        primaryAction: StudioButton(
          label: 'Clear search',
          variant: StudioButtonVariant.primary,
          dense: true,
          onPressed: _clearQuery,
        ),
      );
    }

    final what = [?result.maker, kind?.plural ?? 'devices'].join(' ');
    final String title;
    final String? message;
    final String action;
    if (query.isNotEmpty) {
      final n = result.matchesEverywhere;
      title = 'No $what match “$query”';
      message = '$n ${n == 1 ? 'match' : 'matches'} in all devices.';
      action = 'Search all devices';
    } else {
      final target = widget.target;
      title = _scoped(prefs) && target != null
          ? 'No $what for ${storeScopeName(target)} sets'
          : 'No $what here';
      message = null;
      action = 'Show all devices';
    }
    return StudioEmptyState(
      compact: true,
      icon: StudioIcons.devices,
      title: title,
      message: message,
      primaryAction: StudioButton(
        label: action,
        variant: StudioButtonVariant.primary,
        dense: true,
        onPressed: _showEverything,
      ),
    );
  }

  Widget _header(String label) {
    return StudioSectionHeader(
      label: label,
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.xl,
        StudioSpace.xl,
        StudioSpace.m,
      ),
    );
  }

  /// The row's glyph: what the device is, by maker for a handset and by
  /// form factor for everything else.
  ///
  /// Not by platform. The Windows laptop, monitor and browser are filed under
  /// Android's half of the catalog, and wore the Android robot for it.
  static StudioIconData _glyph(FrameDevice device) {
    final kind = kindOf(device);
    switch (kind) {
      case DeviceKind.computer:
        return StudioIcons.desktop;
      case DeviceKind.browser:
        return StudioIcons.web;
      case DeviceKind.marketing:
        return StudioIcons.marketingFrame;
      case DeviceKind.phone || DeviceKind.foldable || DeviceKind.tablet:
        if (device.maker == 'Apple') return StudioIcons.platformApple;
        if (device.maker != kGenericMaker &&
            device.platform == FramePlatform.android) {
          return StudioIcons.platformAndroid;
        }
        return switch (kind) {
          DeviceKind.phone => StudioIcons.phone,
          DeviceKind.foldable => StudioIcons.foldable,
          _ => StudioIcons.tablet,
        };
    }
  }

  /// The row's second line.
  ///
  /// A handset says its series and year, traced or drawn — every iPhone is
  /// drawn now. The editable twins of the Galaxy Note 20 Ultra and the
  /// OnePlus 13 say "Editable", which is their series, and is what sets each
  /// apart from the traced phone listed beside it under the same name. A
  /// browser says whose window it is, which is the only difference between
  /// the two. Everything else drawn says what it is; a release year on a
  /// generic laptop would be invented.
  static String _subtitle(FrameDevice device) {
    if (!device.isProgrammatic) {
      return '${device.series} · ${device.releaseYear}';
    }
    return switch (kindOf(device)) {
      DeviceKind.phone => '${device.series} · ${device.releaseYear}',
      DeviceKind.browser =>
        device.platform == FramePlatform.ios
            ? 'macOS window'
            : 'Windows window',
      _ => device.series,
    };
  }

  /// One device and, when open, its finishes. A [quiet] row does not show
  /// the finishes it opened with until the user opens a row themselves.
  Widget _deviceRow(FrameDevice device, {bool quiet = false}) {
    final s = context.studio;
    final expanded = _expandedDeviceId == device.id && (!quiet || _toggled);
    final isCurrent = widget.currentDeviceId == device.id;
    final finishes = pickerVariants(
      device,
      currentVariantId: isCurrent ? widget.currentVariantId : null,
    );

    Widget row = StudioListRow(
      key: isCurrent ? _currentKey : null,
      title: device.model,
      subtitle: _subtitle(device),
      icon: _glyph(device),
      selected: isCurrent,
      padding: EdgeInsets.symmetric(
        horizontal: StudioSpace.xl,
        vertical: StudioSpace.m,
      ),
      onTap: () => _toggle(device, shown: expanded),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCurrent) ...[
            StudioIcon(StudioIcons.check, size: 14, color: s.accent),
            SizedBox(width: StudioSpace.xs),
          ],
          // How many finishes wait behind the chevron. Replaces a `9:19.5`
          // readout that read the same for every phone and nonsensically for
          // anything landscape.
          if (finishes.length > 1) ...[
            Text(
              '${finishes.length} finishes',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
            SizedBox(width: StudioSpace.s),
          ],
          StudioIcon(
            expanded ? StudioIcons.collapse : StudioIcons.expand,
            size: 12,
            color: s.textTertiary,
          ),
        ],
      ),
    );
    if (device.isProgrammatic && kindOf(device) == DeviceKind.phone) {
      row = Tooltip(
        message:
            'Drawn from numbers: recolour and reshape it in the Frame tool',
        waitDuration: const Duration(milliseconds: 600),
        child: row,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        if (expanded) _variantStrip(device, finishes),
        StudioDivider(inset: StudioSpace.xl, color: s.borderSubtle),
      ],
    );
  }

  Widget _variantStrip(FrameDevice device, List<FrameVariant> finishes) {
    final s = context.studio;
    return Container(
      width: double.infinity,
      // Filled recessed drawer under the expanded device row — no hairlines.
      decoration: BoxDecoration(color: s.well),
      padding: EdgeInsets.fromLTRB(
        StudioSpace.xl,
        StudioSpace.l,
        StudioSpace.xl,
        StudioSpace.l,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const StudioSectionHeader(label: 'Finish'),
          SizedBox(height: StudioSpace.m),
          Wrap(
            spacing: StudioSpace.m,
            runSpacing: StudioSpace.l,
            children: [
              for (final variant in finishes) _variantTile(device, variant),
            ],
          ),
        ],
      ),
    );
  }

  /// The preview box every tile reserves. Constant, so a row of finishes lines
  /// up whatever shape the bodies inside it are.
  static const double _previewHeight = 76;

  /// How wide a finish tile has to be for [device] to show whole.
  ///
  /// A phone is taller than it is wide, so 88 has always been generous. The
  /// drawn laptop, monitor, iMac and browser bodies are *landscape*, and at 88
  /// they shrank to a legible height of about forty pixels — a picker where the
  /// entries you cannot identify are exactly the ones you have never seen
  /// before. Sizing off the body's own aspect gives each one the width its
  /// shape asks for, and leaves every handset exactly as it was.
  double _tileWidth(FrameDevice device) {
    const padding = StudioSpace.m * 2;
    final needed = _previewHeight * device.frameAspect + padding;
    return needed.clamp(88.0, 190.0);
  }

  Widget _variantTile(FrameDevice device, FrameVariant variant) {
    final s = context.studio;
    final selected =
        widget.currentDeviceId == device.id &&
        widget.currentVariantId == variant.id;

    return SizedBox(
      width: _tileWidth(device),
      child: Material(
        // Filled tile: the device preview sits on a raised `panelAlt`; selection
        // fills `accentSubtle` and adds an accent ring (a content tile keeps a
        // ring so the choice is unmistakable).
        color: selected ? s.accentSubtle : s.panelAlt,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.md),
          side: selected
              ? BorderSide(color: s.accent, width: 2)
              : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _select(device, variant),
          hoverColor: s.hoverBg,
          highlightColor: s.hoverBg,
          splashColor: s.hoverBg,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.m,
              StudioSpace.m,
              StudioSpace.m,
              StudioSpace.s,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // The actual device frame — not a flat colour swatch. This is
                // the fix for the picker showing black boxes: every variant's
                // `frameColor` is #000000 in the manifest, so the old swatch was
                // always black.
                SizedBox(
                  height: _previewHeight,
                  child: _FramePreview(device: device, variant: variant),
                ),
                SizedBox(height: StudioSpace.s),
                Text(
                  displayFinishName(device, variant),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  // `onAccentSubtle` on the selected wash: plain accent on
                  // its own wash misses AA in the dark theme.
                  style: StudioText.micro(context).copyWith(
                    color: selected ? s.onAccentSubtle : s.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What the form-factor menu returns: a kind (null for every kind), or the
/// store-scope toggle.
class _MenuPick {
  const _MenuPick.kind(this.kind) : toggleScope = false;
  const _MenuPick.scope() : kind = null, toggleScope = true;

  final DeviceKind? kind;
  final bool toggleScope;
}

/// One entry in the form-factor menu: a glyph, a label, an optional count and
/// a check on the entry in force.
class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.count,
    this.checked = false,
  });

  final StudioIconData icon;
  final String label;
  final int? count;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Semantics(
      checked: checked,
      // Full width with the label taking the slack, so the counts line up
      // down the menu's right edge instead of trailing each label.
      child: Row(
        children: [
          StudioIcon(icon, size: 14, color: s.textSecondary),
          SizedBox(width: StudioSpace.m),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: StudioText.body(context).copyWith(color: s.textPrimary),
            ),
          ),
          if (count != null) ...[
            SizedBox(width: StudioSpace.l),
            Text(
              '$count',
              style: StudioText.caption(
                context,
              ).copyWith(color: s.textSecondary),
            ),
          ],
          SizedBox(width: StudioSpace.m),
          // Reserved even when unchecked, so the counts stay in one column.
          SizedBox(
            width: 14,
            child: checked
                ? StudioIcon(StudioIcons.check, size: 12, color: s.accent)
                : null,
          ),
        ],
      ),
    );
  }
}

/// A compact, contained render of a single device variant's real frame artwork
/// (SVG/PNG), backed by a neutral screen so the silhouette reads on any tile.
///
/// Mirrors the frame-building logic in `VariantCard` but without the card
/// chrome — used by the device picker so each finish shows the *device*, not a
/// flat colour chip.
class _FramePreview extends StatelessWidget {
  const _FramePreview({required this.device, required this.variant});

  final FrameDevice device;
  final FrameVariant variant;

  @override
  Widget build(BuildContext context) {
    final color = Color(variant.frameColor);

    const double frameWidth = 100.0;
    final double frameHeight = frameWidth / device.frameAspect;

    final rect = device.screenRect;
    final screenW = rect.w * frameWidth;
    final screenH = rect.h * frameHeight;
    final radius = device.cornerRadiusPct * screenW;

    // Neutral warm-white screen so even very dark or very light finishes are
    // clearly silhouetted against the tile.
    const screenshotWidget = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFFFFF), Color(0xFFECEFF4)],
        ),
      ),
    );

    Widget frameWidget;
    if (variant.asset.isNotEmpty) {
      frameWidget = SizedBox(
        width: frameWidth,
        height: frameHeight,
        child: Stack(
          children: [
            Positioned(
              left: (rect.x * frameWidth) - 1.0,
              top: (rect.y * frameHeight) - 1.0,
              width: screenW + 2.0,
              height: screenH + 2.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: screenshotWidget,
              ),
            ),
            Positioned.fill(
              child: FrameArtwork(
                variant: variant,
                placeholderBuilder: (_) =>
                    StandInFrame(color: color, radius: frameWidth * 0.10),
              ),
            ),
          ],
        ),
      );
    } else if (drawnIPhoneFor(device.id) case final iphone?) {
      frameWidget = DrawnIPhoneFrame(
        spec: iphone,
        frameColor: color,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        screenshot: screenshotWidget,
      );
    } else if (studioDesignFor(device.id, variant.id) case final design?) {
      // A dynamic handset: no artwork, but a `FrameDesign` the catalog supplies.
      // Drawn through the same widget a user's own built frame goes through, so
      // the tile previews exactly what the scene will composite.
      frameWidget = CustomDeviceFrame(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        design: design,
        screenshot: screenshotWidget,
      );
    } else {
      // Older devices with no bundled artwork fall back to the drawn frame.
      frameWidget = ProgrammaticDeviceFrame(
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        frameColor: color,
        screenshot: screenshotWidget,
        cutout: device.cutout,
        style: device.frameStyle,
        variantId: variant.id,
      );
    }

    return FittedBox(fit: BoxFit.contain, child: frameWidget);
  }
}
