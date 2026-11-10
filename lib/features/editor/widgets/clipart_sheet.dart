import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../app/layout/studio_layout.dart';
import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../app/theme/studio_typography.dart';
import '../../../data/assets/clipart_catalog.dart';
import '../../shared/widgets/widgets.dart';

/// Asks which piece of clip art to place.
///
/// A sheet, for the same reason the shape gallery is one: picking art is a
/// single decision taken once, not a mode to switch back out of. Unlike the
/// shape gallery it needs categories — 37 stickers in one wrap is a wall — so
/// the tabs carry the grouping the manifest already declares rather than a
/// second list maintained here.
///
/// Returns null on an ordinary dismissal.
Future<Sticker?> showClipartSheet(BuildContext context) =>
    showStudioSheet<Sticker>(
      context,
      title: 'Choose clip art',
      child: SizedBox(
        height: context.layout.modalContentHeight(0.66),
        child: const _ClipartGallery(),
      ),
    );

class _ClipartGallery extends ConsumerStatefulWidget {
  const _ClipartGallery();

  @override
  ConsumerState<_ClipartGallery> createState() => _ClipartGalleryState();
}

class _ClipartGalleryState extends ConsumerState<_ClipartGallery> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    final async = ref.watch(clipartCatalogProvider);

    return async.when(
      loading: () => Center(
        child: SizedBox.square(
          dimension: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: s.accent),
        ),
      ),
      // The pack is bundled, so a failure here is a broken install rather than
      // a missing network — say so plainly. The exception is for the log, not
      // the screen.
      error: (e, _) {
        debugPrint('Clip art unavailable: $e');
        return const StudioEmptyState(
          icon: StudioIcons.error,
          title: 'Clip art unavailable',
          message:
              'The clip art that ships with MockMyApp did not load. Restart '
              'the app; if it keeps happening, reinstall it.',
        );
      },
      data: (catalog) {
        final categories = catalog.categories;
        if (categories.isEmpty) {
          return const StudioEmptyState(
            icon: StudioIcons.error,
            title: 'The clip-art pack is empty',
            message: 'Run tool/generate_clipart.py to build it.',
          );
        }
        final tab = _tab.clamp(0, categories.length - 1);
        final stickers = catalog.inCategory(categories[tab]);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Scrollable rather than segmented: seven categories will not fit
            // as equal cells on a 320dp phone, and a segmented control that
            // scrolls is neither one control nor the other.
            SizedBox(
              // A chip's full touch target where touch is primary.
              height: context.layout.isTouchPrimary
                  ? StudioSizes.touchTarget
                  : 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: categories.length,
                separatorBuilder: (_, _) => SizedBox(width: StudioSpace.s),
                itemBuilder: (context, i) => StudioChip(
                  label: categories[i],
                  selected: i == tab,
                  onTap: () => setState(() => _tab = i),
                ),
              ),
            ),
            SizedBox(height: StudioSpace.l),
            Expanded(
              child: GridView.builder(
                padding: EdgeInsets.only(bottom: StudioSpace.xl),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 84,
                  childAspectRatio: 0.86,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: stickers.length,
                itemBuilder: (context, i) => _StickerTile(
                  sticker: stickers[i],
                  onTap: () => Navigator.pop(context, stickers[i]),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// One sticker: its art over its name.
///
/// Many-coloured art is drawn in its own colours: those colours are the
/// sticker, so a themed preview would be a preview of something else. Art in
/// one colour — the arrows, the plain bubbles — is drawn in the theme's ink,
/// as the shape gallery's tiles are: its colour is only a starting point, the
/// editor recolours it to show on the photo it lands on, and in its own navy it
/// vanished into a dark tile.
class _StickerTile extends StatelessWidget {
  const _StickerTile({required this.sticker, required this.onTap});

  final Sticker sticker;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = context.studio;
    return Tooltip(
      message: sticker.name,
      child: Material(
        color: s.well,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(StudioRadius.sm),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          hoverColor: s.hoverBg,
          highlightColor: s.hoverBg,
          splashColor: s.hoverBg,
          child: Padding(
            padding: EdgeInsets.all(StudioSpace.s),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: SvgPicture.asset(
                    sticker.asset,
                    fit: BoxFit.contain,
                    colorFilter: sticker.tintable
                        ? ColorFilter.mode(s.textPrimary, BlendMode.srcIn)
                        : null,
                  ),
                ),
                SizedBox(height: StudioSpace.xs),
                Text(
                  sticker.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: StudioText.micro(
                    context,
                  ).copyWith(color: s.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
