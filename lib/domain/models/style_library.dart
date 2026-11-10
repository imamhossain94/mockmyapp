import 'package:flutter/painting.dart';

import 'screen_doc.dart';

/// A named colour, saved on the project and reusable across every screen in it.
class ColorStyle {
  const ColorStyle({required this.id, required this.name, required this.color});

  final String id;
  final String name;
  final Color color;

  ColorStyle copyWith({String? name, Color? color}) =>
      ColorStyle(id: id, name: name ?? this.name, color: color ?? this.color);

  @override
  bool operator ==(Object other) =>
      other is ColorStyle &&
      other.id == id &&
      other.name == name &&
      other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}

/// A named caption look: the fields that make two captions read as the same
/// piece of typography, without the words.
///
/// Deliberately a subset of [CaptionSpec] rather than a whole one. A caption
/// carries its text, its position, its own background box and a dozen effects,
/// and none of those are what "the headline style" means — applying a saved
/// style has to change how a caption looks without moving it or rewriting it.
class TextStyleDef {
  const TextStyleDef({
    required this.id,
    required this.name,
    this.fontFamily = 'Roboto',
    this.size = 50,
    this.lineHeight = 60,
    this.letterSpacing = 0,
    this.color = const Color(0xFF1A1A1A),
    this.bold = true,
    this.italic = false,
    this.allUpCase = false,
  });

  final String id;
  final String name;
  final String fontFamily;
  final double size;
  final double lineHeight;
  final double letterSpacing;
  final Color color;
  final bool bold;
  final bool italic;
  final bool allUpCase;

  /// The look [caption] is currently wearing, named [name].
  factory TextStyleDef.from(
    CaptionSpec caption, {
    required String id,
    required String name,
  }) => TextStyleDef(
    id: id,
    name: name,
    fontFamily: caption.fontFamily,
    size: caption.size,
    lineHeight: caption.lineHeight,
    letterSpacing: caption.letterSpacing,
    color: caption.color,
    bold: caption.bold,
    italic: caption.italic,
    allUpCase: caption.allUpCase,
  );

  /// [caption] wearing this style, and tagged as wearing it.
  ///
  /// The tag is what lets a later edit to the style find this caption again.
  /// Everything the style does not name — the words, the position, the
  /// background box, the effects — is left exactly as it was.
  CaptionSpec applyTo(CaptionSpec caption) => caption.copyWith(
    fontFamily: fontFamily,
    size: size,
    lineHeight: lineHeight,
    letterSpacing: letterSpacing,
    color: color,
    bold: bold,
    italic: italic,
    allUpCase: allUpCase,
    styleId: id,
    // The style's size is a size somebody chose, like one set on the slider:
    // a template's fit box must not quietly shrink it back.
    clearFitHeightPct: true,
  );

  /// True when [caption] still looks the way this style says it should.
  ///
  /// A caption tagged with a style but edited away from it is "modified", and
  /// the panel says so rather than pretending the two still agree.
  bool matches(CaptionSpec caption) =>
      caption.fontFamily == fontFamily &&
      caption.size == size &&
      caption.lineHeight == lineHeight &&
      caption.letterSpacing == letterSpacing &&
      caption.color == color &&
      caption.bold == bold &&
      caption.italic == italic &&
      caption.allUpCase == allUpCase;

  TextStyleDef copyWith({String? name}) => TextStyleDef(
    id: id,
    name: name ?? this.name,
    fontFamily: fontFamily,
    size: size,
    lineHeight: lineHeight,
    letterSpacing: letterSpacing,
    color: color,
    bold: bold,
    italic: italic,
    allUpCase: allUpCase,
  );

  @override
  bool operator ==(Object other) =>
      other is TextStyleDef &&
      other.id == id &&
      other.name == name &&
      other.fontFamily == fontFamily &&
      other.size == size &&
      other.lineHeight == lineHeight &&
      other.letterSpacing == letterSpacing &&
      other.color == color &&
      other.bold == bold &&
      other.italic == italic &&
      other.allUpCase == allUpCase;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    fontFamily,
    size,
    lineHeight,
    letterSpacing,
    color,
    bold,
    italic,
    allUpCase,
  );
}

/// A named group of shapes a project can place on any screen.
///
/// The master is stored once; each placement stamps copies into the screen's
/// own `shapes` list, tagged so a later edit to the master can find them again.
/// The same push model as [StyleLibrary] and for the same reason — a screen has
/// to draw with no library in reach — but with one extra rule: an instance
/// keeps *where it was put*. A master edit rewrites what the shapes are and how
/// they sit relative to each other, and never moves the group.
class ComponentDef {
  const ComponentDef({
    required this.id,
    required this.name,
    required this.shapes,
  });

  final String id;
  final String name;

  /// The shapes, in paint order, positioned relative to [anchor].
  final List<ShapeSpec> shapes;

  /// The point a placement is measured from: the first shape's centre.
  ///
  /// Not the bounding box's centre, which would shift the whole group whenever
  /// a master edit changed the extent of any one shape in it — moving every
  /// instance on every screen as a side effect of recolouring a dot.
  Offset get anchor => shapes.isEmpty ? Offset.zero : shapes.first.center;

  /// This component's shapes, stamped at [at] and tagged as one placement.
  ///
  /// [base] is where the backmost shape of the placement lands; the rest stack
  /// up from there in the component's own order. The master's [ShapeSpec.z]
  /// values are *ranked* rather than copied, because they were read off
  /// whatever screen the component was saved from — and a screen that has been
  /// rearranged carries small, dense numbers that would drop the whole
  /// placement behind everything on any other screen.
  ///
  /// Which is the same division [at] already makes: the order among its own
  /// shapes is the only part of the stacking a component owns, and where the
  /// placement sits is the screen's business.
  List<ShapeSpec> stamp({
    required Offset at,
    required String instanceId,
    required int base,
  }) {
    final delta = at - anchor;
    final rank = _stackRanks();
    return [
      for (var i = 0; i < shapes.length; i++)
        shapes[i].copyWith(
          center: shapes[i].center + delta,
          componentId: id,
          instanceId: instanceId,
          slot: i,
          z: base + rank[i],
        ),
    ];
  }

  /// Each shape's place in the component's own back-to-front order, ties broken
  /// by position in [shapes] exactly as a screen breaks them.
  List<int> _stackRanks() {
    final order = List.generate(shapes.length, (i) => i)
      ..sort(
        (a, b) => shapes[a].z != shapes[b].z
            ? shapes[a].z.compareTo(shapes[b].z)
            : a.compareTo(b),
      );
    final rank = List.filled(shapes.length, 0);
    for (var i = 0; i < order.length; i++) {
      rank[order[i]] = i;
    }
    return rank;
  }

  ComponentDef copyWith({String? name, List<ShapeSpec>? shapes}) =>
      ComponentDef(
        id: id,
        name: name ?? this.name,
        shapes: shapes ?? this.shapes,
      );

  @override
  bool operator ==(Object other) =>
      other is ComponentDef &&
      other.id == id &&
      other.name == name &&
      other.shapes.length == shapes.length;

  @override
  int get hashCode => Object.hash(id, name, shapes.length);
}

/// Every named look a project owns.
///
/// **Styles push, they do not pull.** Editing one rewrites every caption
/// tagged with it, there and then, and the documents go on holding concrete
/// values. The alternative — a caption holding only an id and the renderer
/// resolving it — would have made a screen meaningless without its project,
/// and this app moves screens between projects, exports them to archives, and
/// re-renders them offscreen in an exporter that is handed a document and
/// nothing else. A document that cannot be drawn on its own would break all
/// three.
///
/// The cost is that a style edit is a single mutation over the whole project
/// rather than free at paint time, and that is the right trade for a library
/// that changes rarely and renders constantly.
class StyleLibrary {
  const StyleLibrary({
    this.colors = const [],
    this.texts = const [],
    this.components = const [],
  });

  final List<ColorStyle> colors;
  final List<TextStyleDef> texts;
  final List<ComponentDef> components;

  static const empty = StyleLibrary();

  bool get isEmpty => colors.isEmpty && texts.isEmpty && components.isEmpty;

  ComponentDef? componentById(String? id) =>
      id == null ? null : components.where((c) => c.id == id).firstOrNull;

  ColorStyle? colorById(String? id) =>
      id == null ? null : colors.where((c) => c.id == id).firstOrNull;

  TextStyleDef? textById(String? id) =>
      id == null ? null : texts.where((t) => t.id == id).firstOrNull;

  StyleLibrary copyWith({
    List<ColorStyle>? colors,
    List<TextStyleDef>? texts,
    List<ComponentDef>? components,
  }) => StyleLibrary(
    colors: colors ?? this.colors,
    texts: texts ?? this.texts,
    components: components ?? this.components,
  );

  /// Adds [component], or replaces the one that already has its id.
  StyleLibrary withComponent(ComponentDef component) {
    final at = components.indexWhere((c) => c.id == component.id);
    if (at < 0) return copyWith(components: [...components, component]);
    return copyWith(components: [...components]..[at] = component);
  }

  StyleLibrary withoutComponent(String id) =>
      copyWith(components: components.where((c) => c.id != id).toList());

  /// Adds [style], or replaces the one that already has its id.
  StyleLibrary withText(TextStyleDef style) {
    final at = texts.indexWhere((t) => t.id == style.id);
    if (at < 0) return copyWith(texts: [...texts, style]);
    return copyWith(texts: [...texts]..[at] = style);
  }

  StyleLibrary withColor(ColorStyle style) {
    final at = colors.indexWhere((c) => c.id == style.id);
    if (at < 0) return copyWith(colors: [...colors, style]);
    return copyWith(colors: [...colors]..[at] = style);
  }

  StyleLibrary withoutText(String id) =>
      copyWith(texts: texts.where((t) => t.id != id).toList());

  StyleLibrary withoutColor(String id) =>
      copyWith(colors: colors.where((c) => c.id != id).toList());
}
