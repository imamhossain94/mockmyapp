import 'package:flutter/material.dart';

import '../../../app/theme/studio_icons.dart';
import '../../../app/theme/studio_tokens.dart';
import '../../../domain/models/screen_doc.dart';
import '../../shared/widgets/studio_button.dart';

/// A 3x3 alignment grid — the frame-align tool.
///
/// Nine [StudioToolButton]s laid out on the spacing scale. The active cell
/// takes the shared accent-selected treatment (`accentSubtle` fill, 1px
/// `accent` border, `accent` glyph). Position within the grid carries the
/// meaning, so every cell shows the same neutral square marker.
class AlignGrid extends StatelessWidget {
  const AlignGrid({super.key, required this.value, required this.onChanged});

  final Align2D value;
  final ValueChanged<Align2D> onChanged;

  /// Matches `StudioToolButton`'s unlabelled square, which is also the 44px
  /// minimum touch target.
  static const double _cell = 44;

  static const List<String> _labels = <String>[
    'Top left',
    'Top',
    'Top right',
    'Left',
    'Center',
    'Right',
    'Bottom left',
    'Bottom',
    'Bottom right',
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _cell * 3 + StudioSpace.xs * 2,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (row) {
          return Padding(
            padding: EdgeInsets.only(bottom: row == 2 ? 0 : StudioSpace.xs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (col) {
                final i = row * 3 + col;
                final x = (col - 1).toDouble();
                final y = (row - 1).toDouble();
                final selected = value.x == x && value.y == y;
                return Padding(
                  padding: EdgeInsets.only(
                    right: col == 2 ? 0 : StudioSpace.xs,
                  ),
                  child: StudioToolButton(
                    icon: StudioIcons.solidFill,
                    selected: selected,
                    tooltip: _labels[i],
                    onPressed: () => onChanged(Align2D(x, y)),
                  ),
                );
              }),
            ),
          );
        }),
      ),
    );
  }
}
