import 'package:flutter/widgets.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'studio_tokens.dart';

/// The icon currency of the app. Every `icon:` parameter in the component
/// library takes one of these, and every value comes from [StudioIcons].
///
/// This is `font_awesome_flutter`'s [FaIconData], aliased here so no screen has
/// to import the package. From 11.x it is a deliberate *wrapper* around
/// [IconData] rather than a subclass — Flutter 3.44 made [IconData] a `final
/// class`, so subclassing it no longer compiles. The wrapper is also what stops
/// a FontAwesome glyph being handed to a plain [Icon], which would clip the
/// many non-square glyphs.
///
/// A raw [IconData] is deliberately *not* assignable here: that is what keeps
/// stray Material glyph references out of the UI at compile time.
typedef StudioIconData = FaIconData;

/// The single source of truth for every glyph in MockMyApp.
///
/// Screens and widgets must **never** reference the Material `Icons` class or
/// the `FontAwesomeIcons` class directly — always go through [StudioIcons] so
/// the icon language stays consistent and swappable.
///
/// Members are named for what the app *means* (`delete`, `export`,
/// `cornerRadius`), never for what the glyph *is* (`trashCan`, `download`,
/// `borderTopLeft`). That indirection is the whole point: a glyph can be
/// re-chosen here without touching a single screen.
///
/// ### Variant policy
/// In `font_awesome_flutter` an **unprefixed** name resolves to the
/// Regular (outlined) family when one exists. Outlined is preferred everywhere
/// — it matches the hairline, low-chrome aesthetic. Solid is used only where no
/// Regular variant exists, which is almost exclusively pure-geometry marks
/// (chevrons, arrows, plus/minus, align bars, sliders) where the distinction is
/// visually meaningless. Brand marks (Apple, Android, Google Play) necessarily
/// come from the Brands family.
abstract final class StudioIcons {
  // ---------------------------------------------------------------------------
  // Navigation & chrome
  // ---------------------------------------------------------------------------

  /// App bar / sheet back affordance.
  static const StudioIconData back = FontAwesomeIcons.arrowLeft;

  /// Forward navigation, mirrored of [back].
  static const StudioIconData forward = FontAwesomeIcons.arrowRight;

  /// Dismiss a sheet, dialog, chip or selection.
  static const StudioIconData close = FontAwesomeIcons.xmark;

  /// Confirm / selected state.
  static const StudioIconData check = FontAwesomeIcons.check;

  /// Overflow menu, horizontal.
  static const StudioIconData more = FontAwesomeIcons.ellipsis;

  /// Overflow menu, vertical (dense list rows).
  static const StudioIconData moreVertical = FontAwesomeIcons.ellipsisVertical;

  /// Disclosure affordance on a list row.
  ///
  static const StudioIconData chevronRight = FontAwesomeIcons.chevronRight;

  /// Mirrored disclosure / previous.
  static const StudioIconData chevronLeft = FontAwesomeIcons.chevronLeft;

  /// Open a collapsed section, dropdown caret.
  static const StudioIconData expand = FontAwesomeIcons.chevronDown;

  /// Close an expanded section.
  static const StudioIconData collapse = FontAwesomeIcons.chevronUp;

  // ---------------------------------------------------------------------------
  // Primitive actions
  // ---------------------------------------------------------------------------

  /// Generic add.
  static const StudioIconData add = FontAwesomeIcons.plus;

  /// Generic remove / decrement.
  static const StudioIconData remove = FontAwesomeIcons.minus;

  /// Prominent circular add (empty-state CTA).
  ///
  static const StudioIconData addCircle = FontAwesomeIcons.circlePlus;

  /// Destructive removal.
  static const StudioIconData delete = FontAwesomeIcons.trashCan;

  /// Rename / edit in place.
  static const StudioIconData edit = FontAwesomeIcons.penToSquare;

  /// Duplicate an item.
  static const StudioIconData duplicate = FontAwesomeIcons.copy;

  /// Push the current settings onto every screenshot.
  static const StudioIconData applyToAll = FontAwesomeIcons.checkDouble;

  /// Reorder / nudge one slot toward the start.
  static const StudioIconData moveLeft = FontAwesomeIcons.arrowLeft;

  /// Reorder / nudge one slot toward the end.
  static const StudioIconData moveRight = FontAwesomeIcons.arrowRight;

  /// Reset a control back to its default value.
  static const StudioIconData reset = FontAwesomeIcons.arrowsRotate;

  /// The Move tool — drags move the artwork.
  static const StudioIconData toolMove = FontAwesomeIcons.arrowPointer;

  /// The Hand tool — drags move the view.
  static const StudioIconData toolHand = FontAwesomeIcons.hand;

  /// Re-roll a generated value — a palette, a pattern's layout.
  ///
  /// Distinct from [reset], which puts something *back*. This produces
  /// something new, so it must not wear the same glyph.
  static const StudioIconData shuffle = FontAwesomeIcons.shuffle;

  // ---------------------------------------------------------------------------
  // Viewport
  // ---------------------------------------------------------------------------

  /// Magnify the canvas.
  static const StudioIconData zoomIn = FontAwesomeIcons.magnifyingGlassPlus;

  /// Shrink the canvas.
  static const StudioIconData zoomOut = FontAwesomeIcons.magnifyingGlassMinus;

  /// Show or hide a docked side pane.
  static const StudioIconData sidePanel = FontAwesomeIcons.tableColumns;

  /// The canvas holds its size while a panel opens over it.
  static const StudioIconData lock = FontAwesomeIcons.lock;

  /// The canvas resizes to make room for a panel.
  static const StudioIconData lockOpen = FontAwesomeIcons.lockOpen;

  /// Sample a colour from what is painted on screen.
  ///
  /// The eyedropper belongs to this action alone. It used to double as the
  /// leading glyph of the hex field ([colorPicker]), which put two identical
  /// droppers side by side in the picker — one that samples the canvas and one
  /// that is decoration on a text box. The field takes [hex] instead.
  static const StudioIconData dropper = FontAwesomeIcons.eyeDropper;

  /// A colour written as a hex code — the leading glyph of the HEX field.
  static const StudioIconData hex = FontAwesomeIcons.hashtag;

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  /// Undo the last edit.
  ///
  /// Deliberately the flat elbow arrow, not the circular `arrowRotateLeft`:
  /// beside a toolbar of straight-edged marks a pair of rings reads as a
  /// refresh control, and the app already spends the circular arrow on [reset].
  static const StudioIconData undo = FontAwesomeIcons.reply;

  /// Redo the last undone edit — [undo] mirrored.
  static const StudioIconData redo = FontAwesomeIcons.share;

  // ---------------------------------------------------------------------------
  // Visibility
  // ---------------------------------------------------------------------------

  /// Enter preview / show layer.
  static const StudioIconData preview = FontAwesomeIcons.eye;

  /// Leave preview / hide layer.
  static const StudioIconData previewOff = FontAwesomeIcons.eyeSlash;

  // ---------------------------------------------------------------------------
  // Import / export
  // ---------------------------------------------------------------------------

  /// Export the rendered screenshots.
  static const StudioIconData export = FontAwesomeIcons.download;

  /// Save to disk / persist.
  static const StudioIconData save = FontAwesomeIcons.floppyDisk;

  /// A set packed into one file — the graphics zip.
  static const StudioIconData archive = FontAwesomeIcons.fileZipper;

  /// Share sheet.
  static const StudioIconData share = FontAwesomeIcons.shareFromSquare;

  /// Share to a specific destination (social / link).
  static const StudioIconData shareTo = FontAwesomeIcons.shareNodes;

  /// Bring an external file into the project.
  static const StudioIconData import = FontAwesomeIcons.fileImport;

  /// Upload / replace an existing asset.
  static const StudioIconData upload = FontAwesomeIcons.upload;

  /// Leave the app for a web page.
  static const StudioIconData openExternal =
      FontAwesomeIcons.arrowUpRightFromSquare;

  // ---------------------------------------------------------------------------
  // App-level / settings / about
  // ---------------------------------------------------------------------------

  /// Settings screen.
  static const StudioIconData settings = FontAwesomeIcons.gear;

  /// Search / filter field.
  static const StudioIconData search = FontAwesomeIcons.magnifyingGlass;

  /// About / informational row.
  static const StudioIconData info = FontAwesomeIcons.circleInfo;

  /// Privacy policy.
  static const StudioIconData privacy = FontAwesomeIcons.shieldHalved;

  /// Terms of service / long-form document.
  static const StudioIconData terms = FontAwesomeIcons.fileLines;

  /// Open-source licences.
  static const StudioIconData licenses = FontAwesomeIcons.scaleBalanced;

  /// Render / memory budget diagnostics.
  static const StudioIconData memory = FontAwesomeIcons.microchip;

  /// Export quality selector.
  static const StudioIconData quality = FontAwesomeIcons.gem;

  /// Source code / developer link.
  static const StudioIconData code = FontAwesomeIcons.code;

  /// Fine-grained adjustment group.
  static const StudioIconData adjust = FontAwesomeIcons.sliders;

  // ---------------------------------------------------------------------------
  // Theme
  // ---------------------------------------------------------------------------

  /// Force light theme.
  static const StudioIconData themeLight = FontAwesomeIcons.sun;

  /// Force dark theme.
  static const StudioIconData themeDark = FontAwesomeIcons.moon;

  /// Follow the platform theme.
  static const StudioIconData themeSystem = FontAwesomeIcons.circleHalfStroke;

  // ---------------------------------------------------------------------------
  // Project & content structure
  // ---------------------------------------------------------------------------

  /// A single project.
  static const StudioIconData project = FontAwesomeIcons.folder;

  /// The project library.
  static const StudioIconData projects = FontAwesomeIcons.folderOpen;

  /// The set of screens inside a project.
  static const StudioIconData screens = FontAwesomeIcons.images;

  /// One composed screenshot / screen.
  static const StudioIconData screenshot = FontAwesomeIcons.fileImage;

  /// Add a new screenshot slot.
  static const StudioIconData addScreenshot = FontAwesomeIcons.squarePlus;

  /// Attach an image to the current screen.
  ///
  static const StudioIconData addImage = FontAwesomeIcons.squarePlus;

  /// Pick from camera / capture.
  static const StudioIconData addPhoto = FontAwesomeIcons.camera;

  /// A single image asset.
  static const StudioIconData image = FontAwesomeIcons.image;

  /// A collection of image assets.
  static const StudioIconData images = FontAwesomeIcons.images;

  /// Stacked layers panel.
  static const StudioIconData layers = FontAwesomeIcons.layerGroup;

  // ---------------------------------------------------------------------------
  // Devices & platforms
  // ---------------------------------------------------------------------------

  /// Device picker entry point.
  static const StudioIconData device = FontAwesomeIcons.mobileScreenButton;

  /// Plural device catalogue.
  static const StudioIconData devices = FontAwesomeIcons.mobileScreenButton;

  /// iOS hardware.
  static const StudioIconData deviceIos = FontAwesomeIcons.mobileScreenButton;

  /// Android hardware.
  static const StudioIconData deviceAndroid = FontAwesomeIcons.mobileScreen;

  /// Phone form factor.
  static const StudioIconData phone = FontAwesomeIcons.mobileScreenButton;

  /// Tablet form factor.
  static const StudioIconData tablet = FontAwesomeIcons.tabletScreenButton;

  /// Desktop form factor — a Mac or Windows screenshot.
  ///
  /// A monitor rather than either vendor's mark, because the store target lists
  /// name their console on the group heading above the row. A row that wore a
  /// logo where its neighbours wear hardware would be answering a different
  /// question from the rest of the column.
  static const StudioIconData desktop = FontAwesomeIcons.desktop;

  /// The browser as a form factor — a Chrome Web Store screenshot, which is a
  /// page rather than a machine.
  static const StudioIconData web = FontAwesomeIcons.globe;

  /// The device frame wrapped around a screenshot.
  static const StudioIconData frame = FontAwesomeIcons.mobileScreenButton;

  /// A foldable, as a form factor — a book held open is the shape of one.
  static const StudioIconData foldable = FontAwesomeIcons.bookOpen;

  /// Frames that depict no real device — the marketing slab and a frame the
  /// user builds — as a form factor. Drafting tools, because the second of
  /// those is designed rather than chosen.
  static const StudioIconData marketingFrame = FontAwesomeIcons.penRuler;

  /// Every form factor at once, in the device picker's form-factor menu.
  static const StudioIconData allDevices = FontAwesomeIcons.tableCellsLarge;

  /// Apple / App Store platform mark.
  static const StudioIconData platformApple = FontAwesomeIcons.apple;

  /// Android platform mark.
  static const StudioIconData platformAndroid = FontAwesomeIcons.android;

  /// Google Play store mark.
  static const StudioIconData platformPlayStore = FontAwesomeIcons.googlePlay;

  /// Store preview: a shopfront, which reads as "how the listing looks" for
  /// every store. Google Play's mark here read as a "play video" triangle.
  static const StudioIconData storePreview = FontAwesomeIcons.store;

  /// The Store copy page: a listing's words, written.
  static const StudioIconData storeCopy = FontAwesomeIcons.penNib;

  /// The Icon page: the app's own icon, designed and exported for every
  /// store. A cluster of small marks — solid only.
  static const StudioIconData appIcon = FontAwesomeIcons.icons;

  // ---------------------------------------------------------------------------
  // Editor tabs & tools
  // ---------------------------------------------------------------------------

  /// Background editor tab.
  static const StudioIconData background = FontAwesomeIcons.panorama;

  /// Caption editor tab.
  static const StudioIconData caption = FontAwesomeIcons.heading;

  /// Secondary caption line.
  static const StudioIconData subcaption = FontAwesomeIcons.closedCaptioning;

  /// Freeform text tool.
  static const StudioIconData text = FontAwesomeIcons.paragraph;

  /// Layout preset picker.
  static const StudioIconData layout = FontAwesomeIcons.objectGroup;

  /// Grid / gallery view mode.
  static const StudioIconData grid = FontAwesomeIcons.tableCellsLarge;

  /// A watch face — the Apple Watch target, which used to borrow a phone.
  static const StudioIconData watch = FontAwesomeIcons.clock;

  /// A television — the Apple TV target, which used to borrow a desktop.
  static const StudioIconData tv = FontAwesomeIcons.tv;

  /// A headset — the Vision Pro target, which used to borrow a desktop.
  static const StudioIconData headset = FontAwesomeIcons.vrCardboard;

  /// List view mode — the other half of the [grid] toggle. It used to borrow
  /// [layers], which says "stacking order", not "rows".
  static const StudioIconData listView = FontAwesomeIcons.list;

  /// Screenshot border colour/width.
  static const StudioIconData border = FontAwesomeIcons.borderAll;

  // ---------------------------------------------------------------------------
  // Shapes
  // ---------------------------------------------------------------------------

  /// Shapes editor tab. Overlapping figures, which is what the tool draws and
  /// what distinguishes it from the single-square `solidFill` glyph.
  static const StudioIconData shapes = FontAwesomeIcons.shapes;

  /// Rectangle / square primitive.
  static const StudioIconData shapeRectangle = FontAwesomeIcons.square;

  /// Ellipse / circle primitive.
  static const StudioIconData shapeCircle = FontAwesomeIcons.circle;

  /// Triangle, and the regular polygons generally.
  static const StudioIconData shapeTriangle = FontAwesomeIcons.play;

  /// Star and burst figures.
  static const StudioIconData shapeStar = FontAwesomeIcons.star;

  /// A plain straight line.
  static const StudioIconData shapeLine = FontAwesomeIcons.minus;

  /// A line with a head on it.
  static const StudioIconData shapeArrow = FontAwesomeIcons.arrowRightLong;

  /// Freehand drawing — the tool that makes a custom shape.
  static const StudioIconData draw = FontAwesomeIcons.pencil;

  /// Raise a layer one place in the stack.
  static const StudioIconData bringForward = FontAwesomeIcons.angleUp;

  /// Lower a layer one place in the stack.
  static const StudioIconData sendBackward = FontAwesomeIcons.angleDown;

  /// A layer that is currently drawn.
  ///
  /// Deliberately not the same glyph as [preview], which is a *mode* the whole
  /// workspace enters. This is a per-row state, and a row that shared the
  /// toolbar's glyph would read as "preview this layer".
  static const StudioIconData layerVisible = FontAwesomeIcons.solidEye;

  /// A layer held back from the canvas and from the export.
  static const StudioIconData layerHidden = FontAwesomeIcons.solidEyeSlash;

  /// The canvas backdrop, as a row in the layers list.
  static const StudioIconData canvas = FontAwesomeIcons.square;

  // ---------------------------------------------------------------------------
  // Alignment
  // ---------------------------------------------------------------------------

  /// Generic alignment group.
  static const StudioIconData align = FontAwesomeIcons.alignCenter;

  /// Align content to the left edge.
  static const StudioIconData alignLeft = FontAwesomeIcons.alignLeft;

  /// Align content horizontally centred.
  static const StudioIconData alignCenter = FontAwesomeIcons.alignCenter;

  /// Align content to the right edge.
  static const StudioIconData alignRight = FontAwesomeIcons.alignRight;

  /// Anchor content to the top.
  static const StudioIconData alignTop = FontAwesomeIcons.arrowUp;

  /// Anchor content to the bottom.
  static const StudioIconData alignBottom = FontAwesomeIcons.arrowDown;

  // ---------------------------------------------------------------------------
  // Transform
  // ---------------------------------------------------------------------------

  /// Transform group heading.
  static const StudioIconData transform =
      FontAwesomeIcons.arrowsUpDownLeftRight;

  /// Reposition tool.
  static const StudioIconData move = FontAwesomeIcons.upDownLeftRight;

  /// Rotate counter-clockwise.
  static const StudioIconData rotateLeft = FontAwesomeIcons.rotateLeft;

  /// Rotate clockwise.
  static const StudioIconData rotateRight = FontAwesomeIcons.rotateRight;

  /// Mirror left-to-right.
  static const StudioIconData flipHorizontal =
      FontAwesomeIcons.arrowRightArrowLeft;

  /// Scale / zoom control.
  static const StudioIconData scale = FontAwesomeIcons.expand;

  /// Output aspect-ratio selector.
  static const StudioIconData aspectRatio = FontAwesomeIcons.cropSimple;

  /// A proportion is pinned and cannot drift (crop locked to the device screen).
  static const StudioIconData ratioLocked = FontAwesomeIcons.lock;

  /// The same proportion released — resize each axis on its own.
  static const StudioIconData ratioFree = FontAwesomeIcons.lockOpen;

  /// Corner rounding control.
  static const StudioIconData cornerRadius = FontAwesomeIcons.borderTopLeft;

  // ---------------------------------------------------------------------------
  // Crop
  // ---------------------------------------------------------------------------

  /// Crop tool.
  static const StudioIconData crop = FontAwesomeIcons.crop;

  /// Portrait output orientation.
  static const StudioIconData cropPortrait = FontAwesomeIcons.mobileScreen;

  /// Landscape output orientation.
  static const StudioIconData cropLandscape = FontAwesomeIcons.windowMaximize;

  // ---------------------------------------------------------------------------
  // Colour & effects
  // ---------------------------------------------------------------------------

  /// Colour palette / theme colours.
  static const StudioIconData palette = FontAwesomeIcons.palette;

  /// Flat single-colour fill.
  static const StudioIconData solidFill = FontAwesomeIcons.square;

  /// Multi-stop gradient fill.
  static const StudioIconData gradientFill = FontAwesomeIcons.swatchbook;

  /// Eyedropper / custom colour entry.
  static const StudioIconData colorPicker = FontAwesomeIcons.eyeDropper;

  /// Alpha / transparency control.
  static const StudioIconData opacity = FontAwesomeIcons.droplet;

  /// Drop shadow controls.
  static const StudioIconData shadow = FontAwesomeIcons.clone;

  /// A device turned out of the page as a solid — the Frame panel's 3D tab.
  /// Solid only: the cube has no Regular variant.
  static const StudioIconData depth = FontAwesomeIcons.cube;

  /// A clip rather than a still — the video export. Solid only, like the cube.
  static const StudioIconData video = FontAwesomeIcons.film;

  /// Blur / softening amount.
  static const StudioIconData blur = FontAwesomeIcons.braille;

  /// Knock the flat backdrop out of an image, leaving the subject floating.
  static const StudioIconData removeBackground =
      FontAwesomeIcons.wandMagicSparkles;

  // ---------------------------------------------------------------------------
  // Photo editor
  // ---------------------------------------------------------------------------

  /// One-tap looks, and the automatic fix.
  static const StudioIconData filters = FontAwesomeIcons.wandMagicSparkles;

  /// Anything the AI does for you — the generator, its buttons, its cards.
  /// The same glyph [filters] borrowed, under one name, so "AI" means one
  /// thing everywhere it appears.
  static const StudioIconData ai = FontAwesomeIcons.wandMagicSparkles;

  /// Cut the subject out of its background.
  static const StudioIconData cutout = FontAwesomeIcons.scissors;

  /// Stickers and shapes laid over a photo.
  static const StudioIconData stickers = FontAwesomeIcons.faceSmile;

  /// The pen in the photo editor's Draw tool.
  static const StudioIconData pen = FontAwesomeIcons.pen;

  /// The translucent highlighter.
  static const StudioIconData marker = FontAwesomeIcons.highlighter;

  /// Rubs out what was drawn.
  static const StudioIconData eraser = FontAwesomeIcons.eraser;

  /// A straight arrow drawn on a photo.
  static const StudioIconData markupArrow = FontAwesomeIcons.arrowRightLong;

  /// Mirror top to bottom.
  static const StudioIconData flipVertical = FontAwesomeIcons.arrowsUpDown;

  /// A mosaic over something private.
  static const StudioIconData pixelate = FontAwesomeIcons.chessBoard;

  /// Replace a status bar with a clean one.
  static const StudioIconData statusBar = FontAwesomeIcons.signal;

  /// Add a phone's navigation bar — the round home button of three.
  static const StudioIconData navBar = FontAwesomeIcons.circleDot;

  /// Hold to see the photo before the edit.
  static const StudioIconData compare = FontAwesomeIcons.tableColumns;

  // One per adjustment.
  static const StudioIconData brightness = FontAwesomeIcons.sun;
  static const StudioIconData contrast = FontAwesomeIcons.circleHalfStroke;
  static const StudioIconData exposure = FontAwesomeIcons.lightbulb;
  static const StudioIconData highlights = FontAwesomeIcons.cloudSun;
  static const StudioIconData shadows = FontAwesomeIcons.moon;
  static const StudioIconData saturation = FontAwesomeIcons.droplet;
  static const StudioIconData warmth = FontAwesomeIcons.temperatureHalf;
  static const StudioIconData tint = FontAwesomeIcons.swatchbook;
  static const StudioIconData fade = FontAwesomeIcons.cloud;
  static const StudioIconData vignette = FontAwesomeIcons.circleDot;

  // ---------------------------------------------------------------------------
  // Typography
  // ---------------------------------------------------------------------------

  /// Typeface picker.
  ///
  static const StudioIconData font = FontAwesomeIcons.font;

  /// Type size control.
  static const StudioIconData fontSize = FontAwesomeIcons.textHeight;

  /// Bold weight toggle.
  static const StudioIconData bold = FontAwesomeIcons.bold;

  /// Italic slant toggle.
  static const StudioIconData italic = FontAwesomeIcons.italic;

  /// Underline toggle.
  static const StudioIconData underline = FontAwesomeIcons.underline;

  /// Drops a run's overrides and returns it to the caption's own type.
  static const StudioIconData clearFormat = FontAwesomeIcons.eraser;

  /// Rich text — a caption styled a selection at a time.
  static const StudioIconData richText = FontAwesomeIcons.highlighter;

  /// Left-aligned text.
  static const StudioIconData textAlignLeft = FontAwesomeIcons.alignLeft;

  /// Centred text.
  static const StudioIconData textAlignCenter = FontAwesomeIcons.alignCenter;

  /// Right-aligned text.
  static const StudioIconData textAlignRight = FontAwesomeIcons.alignRight;

  /// Leading between text lines.
  static const StudioIconData lineHeight = FontAwesomeIcons.arrowsUpDown;

  /// Tracking between glyphs.
  static const StudioIconData letterSpacing = FontAwesomeIcons.textWidth;

  // ---------------------------------------------------------------------------
  // Affordances & status
  // ---------------------------------------------------------------------------

  /// Reorder grip on a draggable row.
  static const StudioIconData dragHandle = FontAwesomeIcons.gripLines;

  /// Reorder grip on a draggable column/tile.
  static const StudioIconData dragHandleVertical =
      FontAwesomeIcons.gripVertical;

  /// Empty-state hero glyph.
  static const StudioIconData empty = FontAwesomeIcons.boxOpen;

  /// Non-blocking caution.
  static const StudioIconData warning = FontAwesomeIcons.triangleExclamation;

  /// Operation completed.
  static const StudioIconData success = FontAwesomeIcons.circleCheck;

  /// Operation failed.
  static const StudioIconData error = FontAwesomeIcons.circleXmark;
}

/// Renders a [StudioIcons] glyph.
///
/// Always use this instead of a raw [Icon] or [FaIcon]. FontAwesome glyphs have
/// variable advance widths — a `check` is far narrower than a `mobileScreen` —
/// which makes icon rows visibly jitter when the glyph changes. Wrapping every
/// icon in a fixed `size * 1.5` square with centred alignment normalises the
/// footprint so toolbars, list rows and tool strips stay optically stable.
class StudioIcon extends StatelessWidget {
  const StudioIcon(
    this.icon, {
    super.key,
    this.size = 16,
    this.color,
    this.semanticLabel,
  });

  /// The glyph to paint — always a [StudioIcons] member.
  final StudioIconData icon;

  /// Glyph height in logical pixels. See the icon scale: 14 dense, 16 standard,
  /// 18 toolbar, 20 tab, 28+ empty state.
  final double size;

  /// Overrides the default `context.studio.textSecondary`.
  final Color? color;

  /// Accessibility label for screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size * 1.5,
      child: Center(
        child: FaIcon(
          icon,
          size: size,
          color: color ?? context.studio.textSecondary,
          semanticLabel: semanticLabel,
        ),
      ),
    );
  }
}
