import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../../data/assets/frame_catalog.dart';
import '../../data/assets/studio_frames.dart';
import 'screen_doc.dart';
import 'store_target.dart';

/// The canvas width every caption measurement in the app is quoted against.
///
/// `CaptionSpec.size` is "design px at a 1179-wide canvas" — see the width
/// scaling in `SceneView`'s caption layer — so a headline described as a
/// fraction of the page becomes a size by multiplying through this.
const double kCaptionReferenceWidth = 1179;

/// The share of the canvas height a device occupies before its own scale.
///
/// Fixed at the app's own default so a template carries its size entirely in
/// [Transform2D.scale]. Two numbers that both mean "how big is the phone" is
/// one too many to keep in step across a hundred screens.
const double kTemplatePagePercentage = 0.7;

/// The width-to-height ratio a handset frame is assumed to have when the
/// template does not name one — the same value the built-in template frames
/// use, and close enough to every modern phone that a template keeping the
/// user's own device still lands near the width it was measured at.
const double _kNominalFrameAspect = 0.4846;

/// The space a headline set above a device keeps between its last line and
/// the top of the device, as a share of page height, when it is shrunk to fit.
///
/// Small on purpose: it only has to stop a long headline touching the phone.
/// The designed gap is usually far bigger, and long copy may eat into it
/// before it starts to shrink, which costs a lot less than shrinking early.
const double _kCaptionDeviceGap = 0.012;

/// The outline a device is drawn in, as far as placing it is concerned: how
/// wide it is for its height, and where its display starts and stops down it.
///
/// A template is measured against its own drawn frame. When that frame is
/// withheld (an Android listing applied to an iPhone set keeps the iPhone),
/// solving against the template's proportions put a different handset on
/// the page about 3% wider than designed, and sized its display around 11%
/// narrower than the preview had shown. This is how the device actually worn
/// reaches the solver instead.
class WornFrame {
  const WornFrame(this.aspect, {this.screenTop = 0, this.screenBottom = 1});

  /// A built frame's proportions, read the way `CustomDeviceFrame` draws it:
  /// every bezel is a fraction of the frame's width, so it shrinks by the
  /// aspect when expressed against its height.
  factory WornFrame.of(FrameDesign design) => WornFrame(
    design.aspect,
    screenTop: design.top.clamp(0.0, 0.45) * design.aspect,
    screenBottom: 1 - design.bottom.clamp(0.0, 0.45) * design.aspect,
  );

  /// The frame [placement] is drawn in, resolved the way `SceneView` resolves
  /// it: the placement's own design, then the built design a dynamic handset
  /// ships, then the catalog's traced artwork. Null when none of those can be
  /// read, which leaves the solver to fall back on a nominal handset.
  static WornFrame? on(FramePlacement placement, FrameCatalog? catalog) {
    final design =
        placement.design ??
        studioDesignFor(placement.deviceId, placement.variantId);
    if (design != null) return WornFrame.of(design);
    if (catalog == null || catalog.devices.isEmpty) return null;
    final device = catalog.byId(placement.deviceId);
    return WornFrame(
      device.frameAspect,
      screenTop: device.screenRect.y,
      screenBottom: device.screenRect.y + device.screenRect.h,
    );
  }

  /// Width over height of the device's outline.
  final double aspect;

  /// Where its display starts and stops, as fractions of its height.
  final double screenTop;
  final double screenBottom;
}

/// Whether [template]'s own drawn handset goes on a set for [target].
///
/// One answer for the gallery and for applying, because they used to differ:
/// the gallery always previewed the template's drawn Android slab, while
/// applying kept the iPhone an Apple set opens with, so the device in the
/// preview was not the one the user got. The listing's handset belongs only on
/// a phone set of its own store. A watch, a tablet or a laptop keeps the body
/// it was made with (applying a phone listing to a Watch set drew a giant
/// Android phone on the watch), and a set for the other store keeps its own
/// phone rather than dressing an iPhone listing in a punch hole.
bool templateWearsFrame(StoreTarget target, ScreenTemplate template) {
  final platform = target.framePlatform;
  return target.formFactor == TargetFormFactor.phone &&
      template.framesFor(
        platform == null ? null : TemplatePlatform.values.byName(platform.name),
      );
}

/// One line of a headline that is not set like the rest of it.
///
/// Store art routinely sets a single word huge over a smaller second line, or
/// paints one line in an accent — so a template that could only carry one size
/// and one colour had to fake it, and did: one huge word over a small caption
/// came out as one size with 2.3x leading.
class TemplateLine {
  const TemplateLine({this.color, this.sizeScale});

  /// This line's colour, or null to take the headline's.
  final Color? color;

  /// A multiplier on the headline's size, so the line keeps its proportion
  /// when the caption is resized as a whole.
  final double? sizeScale;
}

/// The page a Play feature graphic is: one banner, one exact size.
const Size kFeatureGraphicCanvas = Size(1024, 500);

/// The stores a template's mockup is styled for.
///
/// Every template applies to every target; this says which one it was
/// *designed* for — an iPhone with a Dynamic Island or a handset with a punch
/// hole, the store's own conventions — and is what the gallery's iOS and
/// Android shelves filter on.
enum TemplatePlatform {
  ios('iOS'),
  android('Android');

  const TemplatePlatform(this.label);
  final String label;
}

/// What kind of app a template is for, the way the stores shelve them.
///
/// Persisted nowhere — the catalog is compiled in — so these may be renamed
/// freely; the order is the gallery's chip order.
enum TemplateCategory {
  social('Social'),
  productivity('Productivity'),
  finance('Finance'),
  shopping('Shopping'),
  food('Food & Drink'),
  travel('Travel'),
  health('Health & Fitness'),
  education('Education'),
  entertainment('Entertainment'),
  music('Music'),
  photoVideo('Photo & Video'),
  games('Games'),
  lifestyle('Lifestyle'),
  business('Business'),
  utilities('Utilities');

  const TemplateCategory(this.label);
  final String label;
}

/// A feature-graphic page to preview a template's banner on, carrying [from]'s
/// handset so the banner shows the device the user picked.
ScreenDoc featureGraphicSample(ScreenDoc from) => ScreenDoc(
  id: '${from.id}-banner',
  canvas: kFeatureGraphicCanvas,
  background: from.background,
  caption: const CaptionSpec(text: ''),
  frames: [
    if (from.frames.firstOrNull case final first?)
      FramePlacement(deviceId: first.deviceId, variantId: first.variantId)
    else
      const FramePlacement(
        deviceId: 'apple-iphone-16',
        variantId: '16---ultramarine',
      ),
  ],
);

/// The page a desktop or web screenshot is, for previewing a landscape design.
const Size kLandscapeSample = Size(1280, 800);

/// A landscape page carrying a browser window, to preview a template's
/// landscape designs on when the project's own page is portrait.
ScreenDoc landscapeSample(ScreenDoc from) => ScreenDoc(
  id: '${from.id}-landscape',
  canvas: kLandscapeSample,
  background: from.background,
  caption: const CaptionSpec(text: ''),
  frames: const [
    FramePlacement(deviceId: 'studio-browser-mac', variantId: 'mac-light'),
  ],
);

/// A second handset on a page that already has one.
///
/// Store art routinely shows two phones on a screen — the list behind, the
/// sheet it opens in front, overlapping — and a template that could place only
/// one device dropped the other, which was most of what made those screens
/// recognisable. Gesture Volume's banner pairs two that way.
///
/// Measured exactly like the screen's own device (see
/// [TemplateScreen.measured]) and worn in the same frame, because a listing
/// that pairs two phones draws them as the same handset.
class TemplateDevice {
  const TemplateDevice({
    required this.display,
    required this.deviceTopPct,
    required this.deviceWidthPct,
    this.deviceHeightPct,
    this.rotationDeg = 0,
    this.offsetXPct = 0,
    this.inFront = false,
    this.shadow,
    this.displayTone,
  });

  /// What this device's display shows, on the same terms as
  /// [TemplateScreen.display]: a picture only where the listing's own words
  /// are used too, a colour always.
  final Background display;

  /// The listing's screen colour, for when [display] is a picture that is
  /// held back. See [TemplateScreen.displayTone].
  final Background? displayTone;

  /// Top of the device, as a fraction of page **height**.
  final double deviceTopPct;

  /// How much of the page's **width** the device spans.
  final double deviceWidthPct;

  /// How much of the page's **height** the device spans, when the design says
  /// so — see [TemplateScreen.deviceHeightPct].
  final double? deviceHeightPct;
  final double rotationDeg;

  /// Sideways shift of the device's centre, as a fraction of page width.
  final double offsetXPct;

  /// Whether this device overlaps the screen's own one from in front. Most
  /// pairs put the second phone behind: it is the context, the first is the
  /// point.
  final bool inFront;

  /// A shadow of its own, or null to take the screen's.
  ///
  /// A frame's shadow turns with the frame, so two handsets tilted opposite
  /// ways under one light need two offsets to throw their shadows the same
  /// way across the page.
  final ShadowSpec? shadow;
}

/// One screen of a [ScreenTemplate]: a backdrop, a colour for the device's
/// display, a headline and a placement.
///
/// The unit a store listing is actually designed in. A listing is not one look
/// repeated — screen 1 is the hook, the middle ones each sell a feature, and
/// the last is often a plain card — so a template that could only say one thing
/// could not describe a real listing at all.
class TemplateScreen {
  const TemplateScreen({
    required this.background,
    required this.display,
    required this.caption,
    this.deviceTopPct = 0.24,
    this.deviceWidthPct = 0.86,
    this.deviceHeightPct,
    this.rotationDeg = 0,
    this.offsetXPct = 0,
    this.shadow = const ShadowSpec(opacity: 0.28, blur: 32),
    this.isCaptionAbove = true,
    this.fullBleed = false,
    this.frame,
    this.decor = const [],
    this.cover,
    this.extraDevices = const [],
    this.landscape = false,
    this.displayTone,
    this.displayVisiblePct,
  });

  /// A screen described the way a listing is measured, rather than the way the
  /// renderer stores it.
  ///
  /// Everything here is a fraction of the page, which is what you get from
  /// looking at a screenshot with a ruler — and what the measuring pass in
  /// `tool/` reports. The conversion into [Transform2D] and [CaptionSpec] lives
  /// here, once, so the catalog reads as a list of observations instead of a
  /// list of solved equations.
  factory TemplateScreen.measured({
    required Background background,
    required Background display,

    /// The listing's screen colour, sampled from its display. See
    /// [TemplateScreen.displayTone].
    Background? displayTone,

    /// How far down [display]'s picture the real artwork goes. See
    /// [TemplateScreen.displayVisiblePct].
    double? displayVisiblePct,
    required String text,
    required Color textColor,

    /// The face the listing is set in, as `StudioFonts` spells it.
    ///
    /// Not decoration: a headline's typeface is most of what makes a listing
    /// recognisable, and the fallback here — Roboto — is a face no store
    /// listing in this catalog actually uses. Identified rather than guessed;
    /// `integration_test/font_fingerprint_test.dart` measures the candidates
    /// against the published ink.
    String fontFamily = 'Roboto',

    /// Font size as a fraction of the page **width**.
    required double sizePct,
    double lineRatio = 1.15,

    /// Tracking as a fraction of the page **width**, like [sizePct].
    ///
    /// Store art tracks its type constantly and in both directions — a heavy
    /// display lockup is routinely set a few percent tight, and a small caps
    /// eyebrow a long way loose — and a template that could not say so had to
    /// pick between a headline at the published size that ran too wide and one
    /// cut to the published width that was too small. See
    /// [CaptionSpec.letterSpacing], which has carried this all along.
    double trackingPct = 0,
    bool bold = true,

    /// A heavier cut than the face's bold, when the listing is set in one —
    /// see [CaptionSpec.weight].
    int? weight,
    bool upper = false,
    double alignX = 0,
    bool captionAbove = true,

    /// Top and bottom of the headline block, as fractions of page height.
    required double textTopPct,
    double? textBottomPct,

    /// The lowest a headline set above may reach before it is set smaller, as
    /// a fraction of page height, on a screen with no device under it to say
    /// so: the foot of the band an edge-to-edge listing sets its words on.
    ///
    /// Somebody's longer words wrapped past the band and onto the game below
    /// it, where they were neither on the band nor legible. Null leaves a
    /// device-less headline to set at its own size, as it always has.
    double? fitBottomPct,

    /// Whether a device is drawn at all. False is a full-bleed screen: the
    /// user's screenshot fills the page with no bezel around it.
    bool hasDevice = true,

    /// Top of the device, as a fraction of page height.
    double deviceTopPct = 0.24,

    /// How much of the page's **width** the device spans, including any part
    /// cropped off the edge.
    double deviceWidthPct = 0.86,

    /// How much of the page's **height** it spans instead.
    ///
    /// Width is what a phone listing is composed against, and the height
    /// follows from the handset's own proportions. A landscape design cannot
    /// work that way: it places whatever the target wears — a laptop, a
    /// browser window, a tablet — and their proportions differ by a factor of
    /// three. Sized by height, one landscape design fits all of them.
    double? deviceHeightPct,
    double rotationDeg = 0,
    double offsetXPct = 0,
    ShadowSpec? shadow = const ShadowSpec(opacity: 0.28, blur: 32),
    FrameDesign? frame,

    /// The listing's own decorations — badges, cards, rules, scattered motifs.
    List<ShapeSpec> decor = const [],

    /// Per-line overrides, when the headline is not set in one size and one
    /// colour.
    ///
    /// Indexed against the lines of [text]. A listing that sets one word huge
    /// over a small second line — or one line white and the next in an accent —
    /// is extremely common in store art, and squeezing it into a single size
    /// and colour is what produced headlines with absurd leading and lines
    /// painted the wrong colour.
    List<TemplateLine>? lines,

    /// The headline as explicit styled runs, when [lines] cannot say it.
    ///
    /// Per-line styling covers most store art — a white line over a yellow one
    /// — but not all of it: "to **move.**" sets one word of one line in an
    /// accent and underlines it, and a per-line override has no way to express
    /// half a line. Runs concatenate back into [text] exactly, newlines
    /// included, or the caption renderer paints a lost line break.
    List<CaptionRun>? runs,

    /// Whether a screen with no device is a composed cover (no screenshot
    /// anywhere on it) or an edge-to-edge screenshot with the headline over
    /// it. Null keeps the inference — a device-less screen carrying
    /// decorations is a cover — which is right for most listings and wrong
    /// for two kinds: a cover that is nothing but a headline on a backdrop,
    /// and a full-bleed photograph with a drawn outline over it.
    bool? cover,

    /// Sideways shift of the headline, as a fraction of page width.
    ///
    /// A left-aligned headline is drawn from the caption's own inset, and a
    /// listing that sets its copy well in from the edge — Messenger's cover
    /// starts 14% in — needs the block moved, not just aligned.
    double textOffsetXPct = 0,

    /// A drop shadow under the headline, in the caption's own design-px units
    /// (see [kCaptionReferenceWidth]). Zero blur and zero offset is none.
    double textShadowBlur = 0,
    double textShadowOffsetY = 0,
    Color textShadowColor = const Color(0x66000000),

    /// An outline drawn under the headline's fill, in the same design-px
    /// units as [textShadowBlur]. Zero is none.
    ///
    /// Game listings set their headlines in candy lettering — a thick dark
    /// outline round a light fill — and the same words set flat over a busy
    /// game scene read as a different listing, and a less legible one.
    double textStrokeWidth = 0,
    Color textStrokeColor = const Color(0xFF000000),

    /// The other handsets on the page, measured like this one.
    List<TemplateDevice> extraDevices = const [],

    /// Designed on a landscape page — a feature graphic — rather than the
    /// portrait one a store listing is.
    bool landscape = false,
  }) {
    // The caption anchors 4.5% from the top of the page when it sits above and
    // 4.5% from the bottom when it sits below, and `offsetPct.dy` moves it from
    // there — downward in both cases, which is why the two are not symmetric.
    const anchor = 0.045;
    final captionDy = captionAbove
        ? textTopPct - anchor
        : anchor - (1 - (textBottomPct ?? textTopPct));

    final size = sizePct * kCaptionReferenceWidth;

    // The room the headline may fill before it is set smaller: from its own
    // top down to just short of the highest device under it. Measured listings
    // set their copy to fit their own words, so somebody's longer headline at
    // the listing's size wrapped onto a third line and ran into the phone.
    //
    // Never less than the listing's own copy takes, so the words a design was
    // measured with are never the ones shrunk. Only for a headline set above a
    // device on a portrait page: one set below grows upward from a bottom
    // anchor towards a device whose foot depends on the canvas, and a cover has
    // nothing to run into.
    double? fitHeightPct;
    if (captionAbove && hasDevice && !landscape) {
      final deviceTop = [
        deviceTopPct,
        for (final extra in extraDevices) extra.deviceTopPct,
      ].reduce(math.min);
      fitHeightPct = math.max(
        deviceTop - _kCaptionDeviceGap - textTopPct,
        _ownHeightPct(text, sizePct, lineRatio, lines, runs),
      );
    } else if (captionAbove && fitBottomPct != null && !landscape) {
      // The same rule with the band's foot standing in for the device's top.
      fitHeightPct = math.max(
        fitBottomPct - textTopPct,
        _ownHeightPct(text, sizePct, lineRatio, lines, runs),
      );
    }

    return TemplateScreen(
      background: background,
      display: display,
      displayTone: displayTone,
      displayVisiblePct: displayVisiblePct,
      isCaptionAbove: captionAbove,
      fullBleed: !hasDevice,
      cover: cover,
      frame: frame,
      caption: CaptionSpec(
        text: text,
        fontFamily: fontFamily,
        size: size,
        lineHeight: size * lineRatio,
        letterSpacing: trackingPct * kCaptionReferenceWidth,
        color: textColor,
        bold: bold,
        weight: weight,
        allUpCase: upper,
        align: Align2D(alignX, 0),
        offsetPct: Offset(textOffsetXPct, captionDy),
        runs: runs ?? _runsFor(text, lines),
        shadowBlur: textShadowBlur,
        shadowOffsetY: textShadowOffsetY,
        shadowColor: textShadowColor,
        strokeWidth: textStrokeWidth,
        strokeColor: textStrokeColor,
        fitHeightPct: fitHeightPct,
      ),
      shadow: shadow,
      decor: decor,
      deviceTopPct: deviceTopPct,
      deviceWidthPct: deviceWidthPct,
      deviceHeightPct: deviceHeightPct,
      rotationDeg: rotationDeg,
      offsetXPct: offsetXPct,
      extraDevices: extraDevices,
      landscape: landscape,
    );
  }

  /// Where the device sits on a page of [canvas], as `SceneView` wants it.
  ///
  /// Solved per canvas rather than once at construction, because the renderer
  /// measures a frame against the page's *height* while a listing composes
  /// against its *width* — see [deviceWidthPct]. Converting here is what lets
  /// one template look right on a 9:16 Play page, a 9:19.5 iPhone page and an
  /// iPad's 3:4 without carrying three sets of numbers.
  ///
  /// [worn] is the device actually drawn, when it is not this screen's own
  /// [frame]. [showsArt] is whether the display is showing the listing's
  /// picture, which may move the device down: see [displayVisiblePct].
  Transform2D transformFor(
    Size canvas, {
    WornFrame? worn,
    bool showsArt = false,
  }) => _solve(
    canvas,
    topPct: deviceTopPct,
    widthPct: deviceWidthPct,
    heightPct: deviceHeightPct,
    rotationDeg: rotationDeg,
    offsetXPct: offsetXPct,
    shape: worn ?? _ownFrame,
    visiblePct: showsArt ? displayVisiblePct : null,
  );

  /// Where one of [extraDevices] sits on a page of [canvas] — the same
  /// solution as [transformFor], in the same frame.
  Transform2D transformForExtra(
    TemplateDevice device,
    Size canvas, {
    WornFrame? worn,
  }) => _solve(
    canvas,
    topPct: device.deviceTopPct,
    widthPct: device.deviceWidthPct,
    heightPct: device.deviceHeightPct,
    rotationDeg: device.rotationDeg,
    offsetXPct: device.offsetXPct,
    shape: worn ?? _ownFrame,
  );

  /// This screen's drawn frame as the solver reads it, or null for none.
  WornFrame? get _ownFrame => frame == null ? null : WornFrame.of(frame!);

  Transform2D _solve(
    Size canvas, {
    required double topPct,
    required double widthPct,
    double? heightPct,
    required double rotationDeg,
    required double offsetXPct,
    WornFrame? shape,
    double? visiblePct,
  }) {
    // The frame's own proportions decide how tall it must be to span the width
    // asked for. A device whose frame cannot be read here — no catalog to look
    // it up in — has a nominal modern handset stand in for it, unless the
    // design gave a height outright, which is how a landscape design places a
    // laptop or a browser it knows nothing else about.
    final frameAspect = shape?.aspect ?? _kNominalFrameAspect;
    final height =
        heightPct ?? widthPct * (canvas.width / canvas.height) / frameAspect;

    // The listing's picture stops short of the bottom of the display: the
    // published screenshot was cropped at the page edge, and what was never
    // published is a flat pad. On the 9:16 page the listings were measured on
    // the page edge hides it, but a taller page shows more of the device and
    // the pad showed as a band of whatever colour the crop cut through. While
    // the picture is on show the device sinks just far enough to keep that
    // band below the page edge, which costs a wider gap under the headline on
    // tall pages and nothing on the page the listing was designed for. It
    // rises back once a capture covers the picture: see [settleTemplateArt].
    var top = topPct;
    if (visiblePct != null && heightPct == null) {
      final screenTop = shape?.screenTop ?? 0;
      final screenBottom = shape?.screenBottom ?? 1;
      final artEnds = screenTop + visiblePct * (screenBottom - screenTop);
      top = math.max(top, 1 - artEnds * height);
    }

    return Transform2D(
      pagePercentage: kTemplatePagePercentage,
      scale: height / kTemplatePagePercentage,
      rotationDeg: rotationDeg,
      // `SceneView` puts the top of a centred device at
      // `(1 - pagePercentage * scale) / 2 + offsetPct.dy`, so the nudge is
      // whatever is left over once the size is accounted for.
      offsetPct: Offset(offsetXPct, top - (1 - height) / 2),
    );
  }

  /// How tall the listing's own headline sets, as a share of a 9:16 page's
  /// height: one line of leading per line, each at its own size.
  ///
  /// An estimate, from the numbers alone: it cannot know where a line wraps.
  /// It only has to keep the fit box from ever being smaller than the copy the
  /// listing was measured with.
  static double _ownHeightPct(
    String text,
    double sizePct,
    double lineRatio,
    List<TemplateLine>? lines,
    List<CaptionRun>? runs,
  ) {
    final count = text.split('\n').length;
    final scales = List<double>.filled(count, 1);
    if (lines != null && lines.length == count) {
      for (var i = 0; i < count; i++) {
        scales[i] = lines[i].sizeScale ?? 1;
      }
    } else if (runs != null && runs.isNotEmpty) {
      // A line takes the biggest run on it, since that is what its leading is
      // set off.
      scales.fillRange(0, count, 0);
      var line = 0;
      for (final run in runs) {
        final parts = run.text.split('\n');
        for (var j = 0; j < parts.length; j++) {
          if (j > 0) line = math.min(line + 1, count - 1);
          scales[line] = math.max(scales[line], run.sizeScale ?? 1);
        }
      }
      for (var i = 0; i < count; i++) {
        if (scales[i] == 0) scales[i] = 1;
      }
    }
    final sum = scales.fold<double>(0, (a, b) => a + b);
    return sizePct * lineRatio * sum * 1080 / 1920;
  }

  /// The headline's lines as styled runs, or empty when it is set as one
  /// block.
  ///
  /// The newline stays on the end of each run but the last, because that is
  /// what makes the runs concatenate back into [text] exactly — the caption
  /// renderer paints the runs, and a lost newline is a lost line break.
  static List<CaptionRun> _runsFor(String text, List<TemplateLine>? lines) {
    if (lines == null || lines.isEmpty) return const [];
    final parts = text.split('\n');
    if (parts.length != lines.length) return const [];
    if (lines.every((l) => l.color == null && l.sizeScale == null)) {
      return const [];
    }
    return [
      for (var i = 0; i < parts.length; i++)
        CaptionRun(
          i == parts.length - 1 ? parts[i] : '${parts[i]}\n',
          color: lines[i].color,
          sizeScale: lines[i].sizeScale,
        ),
    ];
  }

  final Background background;

  /// What the device's display shows under the screenshot.
  ///
  /// A calibrated listing's display is a picture of its app. It reaches a
  /// document wherever the listing's own words do (see `withDisplay` on
  /// [applyTo]), and [displayTone] stands in for it everywhere else.
  final Background display;

  /// The listing's screen colour: the tone its display was sampled at.
  ///
  /// What the phone wears when [display] is a picture that is held back. It
  /// used to wear nothing, which drew the grey "add a picture" plate in every
  /// phone of a set that had just been given a colourful template, and read as
  /// a template that had failed to load.
  final Background? displayTone;

  /// How far down [display]'s picture the real artwork goes, as a fraction of
  /// its height, or null when all of it is real (or it is not a picture).
  ///
  /// The rest is the flat pad the extractor filled in below the published
  /// crop. See [_solve] for how a device keeps it off the page.
  final double? displayVisiblePct;

  /// The headline's typography, placement, and the listing's own sample copy.
  ///
  /// The words are carried so a preview tile can show the screen as it was
  /// designed. Whether they reach a document is the caller's decision — see
  /// `withCopy` on [applyTo].
  final CaptionSpec caption;

  /// Top of the device, as a fraction of page **height**.
  final double deviceTopPct;

  /// How much of the page's **width** the device spans.
  ///
  /// Width, not height, and that distinction is the whole reason this is a
  /// measurement rather than a finished [Transform2D]. `SceneView` sizes a
  /// frame as a share of the canvas *height*, so a device described that way
  /// keeps its height and changes its width whenever the page's proportions
  /// change: the same number that fills 89% of a 9:16 Android page spills to
  /// 109% of a 9:19.5 iPhone page, overflowing it. Width is what a listing is
  /// actually composed against, and it is stable across every canvas the app
  /// exports — so the height is derived, per canvas, in [transformFor].
  final double deviceWidthPct;

  /// The share of the page's **height** the device spans, when the design is
  /// sized that way — see the `deviceHeightPct` argument of [measured].
  final double? deviceHeightPct;

  final double rotationDeg;

  /// Sideways shift of the device's centre, as a fraction of page width.
  final double offsetXPct;

  final ShadowSpec? shadow;
  final bool isCaptionAbove;

  /// The bezel this listing draws around its screenshot, when the mockup is
  /// part of the look rather than incidental to it.
  ///
  /// Null means **keep whatever device the user picked**, which is the right
  /// default: they chose a handset in the new-project form, and a template has
  /// no business overruling that to sell a colour scheme. It is set only where
  /// the listing's own mockup is doing real work — a plain dark slab with a
  /// huge corner radius, a white phone on a white page — because reproducing
  /// the palette while dropping the chrome it was designed against is how a
  /// clone stops looking like the thing it cloned.
  ///
  /// A built frame, not a catalog pick: these listings mostly use generic
  /// rounded rectangles rather than a specific handset, and [FrameDesign] is
  /// exactly the app's own way of saying that. The user can still swap to any
  /// real device afterwards — it lands in the Frame panel as a design they can
  /// edit, not as a lock.
  final FrameDesign? frame;

  /// Everything on the page that is neither the device nor the headline.
  ///
  /// A listing's opening screen is often not a phone with a caption over it at
  /// all — it is a composed cover: an eyebrow, a two-tone headline, a row of
  /// badges, a card tilted a few degrees with a legend on it. None of that is
  /// expressible as a background plus two blocks of type, which is why shapes
  /// can carry words (see [ShapeLabel]) and why a template can carry shapes.
  ///
  /// **Never overwrites the user's own.** See [applyTo] for when these land.
  final List<ShapeSpec> decor;

  /// The listing's other handsets, when a screen shows more than one.
  ///
  /// **Grown, never forced.** A screen with a single device gets these added
  /// to it, empty, so the design arrives whole; one whose devices already
  /// number exactly as many as this screen shows gets each put back in its
  /// place; any other arrangement is somebody's own composition and keeps its
  /// geometry. See [applyTo].
  final List<TemplateDevice> extraDevices;

  /// Whether this design was composed on a landscape page.
  ///
  /// Its geometry only means something on a page of the same orientation, so
  /// a landscape design places devices on a banner and a portrait one on a
  /// screenshot, and each leaves the other's pages' geometry alone.
  final bool landscape;

  /// A composed page with no device on it at all.
  ///
  /// The distinction [fullBleed] alone could not draw. Both mean "no bezel",
  /// but an edge-to-edge *screenshot* still wants the user's capture blown up
  /// to fill the page, while a cover — an eyebrow over a two-tone headline over
  /// a row of badges — wants no phone and no capture anywhere near it. A
  /// listing that goes to the trouble of drawing one is not asking for a
  /// screenshot behind its artwork.
  ///
  /// Inferred from [fullBleed] and [decor] unless the constructor was told
  /// outright: a headline alone on a gradient is a cover too, and a photograph
  /// with an outline drawn over it is not.
  bool get isCover => cover ?? (fullBleed && decor.isNotEmpty);

  /// Whether this device-less screen shows no screenshot at all, when the
  /// listing has said so; null leaves it to [isCover] to infer.
  final bool? cover;

  /// The screenshot fills the page with no bezel around it.
  ///
  /// Real listings do this for an opening hook — an edge-to-edge photograph or
  /// app shot with the headline set over it — and there is no device to place,
  /// so the placement above is ignored in favour of covering the canvas.
  final bool fullBleed;

  /// [doc] wearing this screen's look.
  ///
  /// Keeps everything the document says and shows: the screenshots in the
  /// frame, the shapes on the page, and — unless [withCopy] — the words in the
  /// headline. See [ScreenTemplate.applyTo] for why the words are held back.
  ///
  /// [catalog] is where a device the template does not draw itself is looked
  /// up, so it is placed by its own proportions. See [WornFrame].
  ScreenDoc applyTo(
    ScreenDoc doc, {
    bool withCopy = false,
    bool withDisplay = false,
    bool withFrame = true,
    FrameCatalog? catalog,
  }) {
    // A composition the user built is not a placement this can second-guess:
    // two phones side by side share one anchor, and moving both onto it stacks
    // them. A page of the other orientation is a different shape from the one
    // this design was composed on, so its geometry says nothing true there
    // either. Both still take the colours and the type, which is most of a
    // look.
    //
    // The exception is a set of devices that matches this screen's one for
    // one — typically the set an earlier application of this same listing
    // grew — which has a slot for every frame and no guessing to do.
    final slots = 1 + extraDevices.length;
    final docLandscape = doc.canvas.width > doc.canvas.height;
    final canPlace =
        docLandscape == landscape &&
        (doc.frames.length == 1 || doc.frames.length == slots);
    final placesExtras = canPlace && !fullBleed && extraDevices.isNotEmpty;

    // The device each placement will be drawn in once this has run: the
    // listing's own frame when it is put on, the placement's own otherwise.
    WornFrame? wornBy(FramePlacement placement) => frame != null && withFrame
        ? _ownFrame
        : WornFrame.on(placement, catalog) ?? _ownFrame;

    return doc.copyWith(
      background: background,
      isCaptionAbove: isCaptionAbove,
      caption: _restyle(doc.caption, withCopy: withCopy),
      subCaption: _restyleSub(doc.subCaption),
      // Decorations are content, like the copy — so they arrive on the same
      // terms. A screen with shapes already on it keeps exactly those: this
      // runs across a whole set at once with no undo behind it, and silently
      // replacing somebody's annotations with a listing's badges is not a
      // restyle, it is a deletion. An empty screen has nothing to lose and
      // everything to gain, and `withCopy` is only ever passed where the
      // content is placeholder anyway — a preview tile, or a new project.
      shapes: (withCopy || doc.shapes.isEmpty) && decor.isNotEmpty
          ? decor
          : doc.shapes,
      frames: [
        for (final (i, placement) in doc.frames.indexed)
          placesExtras && i > 0
              ? _placeExtra(
                  extraDevices[i - 1],
                  i - 1,
                  placement,
                  doc.canvas,
                  withDisplay: withDisplay,
                  withFrame: withFrame,
                  worn: wornBy(placement),
                )
              : _place(
                  placement,
                  doc.canvas,
                  canPlace: canPlace,
                  withDisplay: withDisplay,
                  withFrame: withFrame,
                  worn: wornBy(placement),
                ),
        // A lone device on a screen designed for several grows the rest —
        // empty, in the same handset — so a project made from the listing has
        // somewhere to put every screenshot its design shows.
        if (placesExtras && doc.frames.length == 1)
          for (final (i, device) in extraDevices.indexed)
            _placeExtra(
              device,
              i,
              _spare(doc.frames.single),
              doc.canvas,
              withDisplay: withDisplay,
              withFrame: withFrame,
              worn: wornBy(doc.frames.single),
            ),
      ],
    );
  }

  /// What a display shows: [display] where pictures are wanted or it is not
  /// one, [tone] in place of a picture otherwise, and nothing when there is no
  /// tone to stand in.
  ///
  /// A colour is a look; a picture is a screenshot. The listing's artwork is a
  /// picture of *an app*, the thing the user came here to replace, so it only
  /// arrives where the listing's own words do: a preview tile, a new project
  /// made from the template, the AI wizard. There it is a fill, under the
  /// user's capture, so the first screenshot dropped in covers it, and the
  /// export sheet says when one is about to ship. Applying a look to a set
  /// that already has its own words takes the listing's screen colour instead.
  static ScreenshotSpec _dressDisplay(
    ScreenshotSpec screenshot,
    Background display,
    Background? tone, {
    required bool withDisplay,
  }) {
    if (withDisplay || display is! ImageBackground) {
      return screenshot.copyWith(fill: display);
    }
    return tone == null
        ? screenshot.copyWith(clearFill: true)
        : screenshot.copyWith(fill: tone);
  }

  /// [placed] turned out of the page the way [from] was.
  ///
  /// A template knows where a device goes, not how somebody has tilted it in
  /// 3D, so a fresh placement kept dropping the tilt they had dialled in.
  static Transform2D _keepTilt(Transform2D placed, Transform2D from) =>
      placed.copyWith(tiltX: from.tiltX, tiltY: from.tiltY);

  /// An empty device in the same handset as [first], for a slot the document
  /// has no frame for.
  ///
  /// Nothing of [first]'s screenshot comes with it: a second phone showing the
  /// first phone's capture is a duplicate to clear off, not a design.
  static FramePlacement _spare(FramePlacement first) => FramePlacement(
    deviceId: first.deviceId,
    variantId: first.variantId,
    design: first.design,
    frameHidden: first.frameHidden,
    cutoutHidden: first.cutoutHidden,
  );

  /// [placement] put where [device] goes, [index] among [extraDevices].
  FramePlacement _placeExtra(
    TemplateDevice device,
    int index,
    FramePlacement placement,
    Size canvas, {
    required bool withDisplay,
    required bool withFrame,
    WornFrame? worn,
  }) {
    final shade = device.shadow ?? shadow;
    final placed = placement.copyWith(
      // The same rule as the screen's own display: see [_dressDisplay].
      screenshot: _dressDisplay(
        placement.screenshot,
        device.display,
        device.displayTone,
        withDisplay: withDisplay,
      ),
      shadow: shade,
      clearShadow: shade == null,
      transform: _keepTilt(
        transformForExtra(device, canvas, worn: worn),
        placement.transform,
      ),
      // Either side of the screen's own device, which keeps the default
      // [kStackFrames]; stepping away from it keeps several on one side in the
      // order they were listed.
      z: device.inFront ? kStackFrames + 1 + index : kStackFrames - 1 - index,
    );
    return frame == null || !withFrame
        ? placed
        : placed.copyWith(design: frame, frameHidden: false);
  }

  FramePlacement _place(
    FramePlacement placement,
    Size canvas, {
    required bool canPlace,
    required bool withDisplay,
    required bool withFrame,
    WornFrame? worn,
  }) {
    final dressed = placement.copyWith(
      screenshot: _dressDisplay(
        placement.screenshot,
        display,
        displayTone,
        withDisplay: withDisplay,
      ),
      shadow: shadow,
      clearShadow: shadow == null,
    );
    if (!canPlace) return dressed;

    if (!fullBleed) {
      // The listing's picture is on show only while nobody's capture covers
      // it, and only then does its pad need keeping off the page. A capture
      // that arrives later puts the device back: see [settleTemplateArt].
      final showsArt =
          withDisplay &&
          display is ImageBackground &&
          placement.screenshot.imagePath == null;
      final placed = dressed.copyWith(
        transform: _keepTilt(
          transformFor(canvas, worn: worn, showsArt: showsArt),
          placement.transform,
        ),
      );
      // The listing's own mockup, when it has one worth keeping. `frameHidden`
      // is cleared explicitly: a set that was frameless before this template
      // must actually grow the bezel the template asks for.
      return frame == null || !withFrame
          ? placed
          : placed.copyWith(design: frame, frameHidden: false);
    }

    // A cover takes the device off the page rather than blowing a screenshot
    // up to fill it. Hidden, not dropped: `FramePlacement.hidden` keeps the
    // device, its screenshots and everything dialled in around them, so the
    // layers list's eye switches the phone back on with nothing lost.
    if (isCover) return dressed.copyWith(hidden: true);

    // Edge to edge: a zero-thickness frame at the canvas's own proportions, so
    // the aperture *is* the page. The same construction the Play feature
    // graphic is seeded with, and for the same reason — it is the only way to
    // get a full-bleed picture out of a renderer that draws every screenshot
    // inside a device's screen rect.
    return dressed.copyWith(
      frameHidden: true,
      design: FrameDesign(
        thickness: 0,
        topThickness: 0,
        bottomThickness: 0,
        aspect: canvas.width / canvas.height,
      ),
      screenshot: dressed.screenshot.copyWith(cornerRadiusPct: 0),
      transform: const Transform2D(pagePercentage: 1),
      clearShadow: true,
    );
  }

  /// This screen's typography over [target]'s own words — or over this
  /// screen's, when the caller has asked for the copy too.
  ///
  /// [lineStyles] carries the listing's per-line styling onto the target's
  /// words; see the runs below.
  CaptionSpec? _restyle(
    CaptionSpec? target, {
    required bool withCopy,
    bool lineStyles = true,
  }) {
    if (target == null) return null;
    return caption.copyWith(
      text: withCopy ? caption.text : target.plainText,
      // Runs carry the words *inside* them, so they travel with whichever copy
      // is being used. The listing's own when its copy is taken. Otherwise the
      // user's words, styled line by line after the listing's: a template
      // expresses a two-tone headline only as runs over its own words, so
      // keeping the user's runs as they were (which is what this did) set Arrow
      // Rush's yellow second line, or a coloured last word, flat the moment
      // the template met somebody else's copy. A listing set in one
      // style leaves the user's own runs alone.
      runs: withCopy
          ? caption.runs
          : !lineStyles || caption.runs.isEmpty
          ? target.runs
          : CaptionSpec.runsByLine(caption.runs, target.plainText),
      // The user's words keep their translations. Starting from the listing's
      // caption, which has none, silently deleted every language of a set the
      // moment a look was applied to it.
      translations: withCopy ? const {} : target.translations,
      enabled: target.enabled,
      clearBackgroundColor: caption.backgroundColor == null,
      // The tag would be a lie: the caption no longer looks like the saved
      // style it named.
      clearStyleId: true,
    );
  }

  /// The subcaption, set to sit under the headline rather than to match it.
  ///
  /// Derived from [caption] rather than carried separately: a second line is
  /// the same face and colour at a smaller, lighter setting, and giving every
  /// screen a second full [CaptionSpec] to keep in step is how the two drift.
  CaptionSpec? _restyleSub(CaptionSpec? target) {
    if (target == null) return null;
    return _restyle(target, withCopy: false, lineStyles: false)?.copyWith(
      size: caption.size * 0.52,
      lineHeight: caption.lineHeight * 0.52,
      bold: false,
      allUpCase: false,
      color: caption.color.withValues(alpha: 0.82),
      // The headline's nudge is measured from its own anchor and the
      // subcaption sits at a different one; inheriting it would push the two
      // apart by exactly the amount the headline was moved.
      offsetPct: Offset.zero,
      // Likewise its fit box, which is the room above the device measured from
      // the headline's top.
      clearFitHeightPct: true,
    );
  }
}

/// A whole store listing's worth of design: several screens that read as one
/// set.
///
/// Modelled on what a Play listing actually is — the original App Mockup's
/// template sets were each an array of screens for exactly this reason. A
/// template carries no shapes and **never replaces a
/// screenshot**, so applying one to a project already full of work restyles it
/// rather than emptying it.
///
/// What a calibrated listing does carry is that app's own UI as the display's
/// [TemplateScreen.display] — the layer under the user's capture, not over it.
/// A set with screenshots in it keeps showing them; a set without one shows the
/// listing as it was published, which is the whole point of previewing a
/// template before applying it.
class ScreenTemplate {
  const ScreenTemplate({
    required this.id,
    required this.name,
    required this.blurb,
    required this.screens,
    this.category,
    this.platforms = const {TemplatePlatform.ios, TemplatePlatform.android},
    this.featureGraphic,
    this.landscapeScreens = const [],
  });

  final String id;

  /// What the picker calls it — the app the look was taken from.
  final String name;

  /// A few words on what makes it distinctive, under the name in the picker.
  final String blurb;

  /// The screens, in listing order. Never empty.
  final List<TemplateScreen> screens;

  /// The shelf the gallery files it on, or null for none but "All".
  final TemplateCategory? category;

  /// The stores its mockup is styled for. See [TemplatePlatform].
  final Set<TemplatePlatform> platforms;

  /// The listing's banner: the one landscape design a Play feature graphic
  /// takes, in the same palette and type as [screens].
  ///
  /// A set of screenshots and its banner are one campaign, and a template
  /// that dressed six screenshots and left the banner to be designed from
  /// scratch was half a template. Null keeps the old behaviour on a banner —
  /// its colours and type are restyled and nothing is placed.
  final TemplateScreen? featureGraphic;

  /// The same listing composed on a landscape page: a Mac, Windows or Chrome
  /// Web Store shot, or a handset turned on its side.
  ///
  /// Empty means the listing has no landscape designs, and a landscape page
  /// takes its colours and type but keeps its own geometry — the old
  /// behaviour. These place their device by height (see
  /// [TemplateScreen.deviceHeightPct]), so one set fits a laptop, a browser
  /// window and a tablet alike.
  final List<TemplateScreen> landscapeScreens;

  int get length => screens.length;

  /// The designs that dress a page of [canvas]'s shape.
  ///
  /// [banner] is the caller's answer to the one question the page cannot
  /// settle: a Play feature graphic and an iPhone laid on its side are both
  /// landscape and about the same shape, and only the project knows which it
  /// is holding. Left null, anything wider than 1.9:1 is taken for a banner.
  List<TemplateScreen> designsFor(Size canvas, {bool? banner}) {
    if (canvas.width <= canvas.height) return screens;
    final isBanner = banner ?? canvas.width / canvas.height >= 1.9;
    // A banner takes a banner's design or none. Dressing it in a screenshot's
    // portrait design is what left feature graphics undesigned — and applied
    // to a feature-graphic set, it grew the store's one banner into as many
    // as the listing has screens.
    if (isBanner) return featureGraphic == null ? const [] : [featureGraphic!];
    if (landscapeScreens.isNotEmpty) return landscapeScreens;
    return screens;
  }

  /// How many designs this template has for a page of [canvas]'s shape: one
  /// for a banner it has a design for and none for one it has not, its
  /// landscape set for a landscape page that has one, its screens otherwise.
  int lengthFor(Size canvas, {bool? banner}) =>
      designsFor(canvas, banner: banner).length;

  /// The look for the [index]th screen of a set, wrapping when the set is
  /// longer than the template.
  ///
  /// Wrapping rather than stopping: a listing designed with six screens has
  /// said everything it has to say about how screen seven should look, and
  /// leaving the tail undressed would be worse than repeating.
  TemplateScreen screenAt(int index) => screens[index % screens.length];

  /// [doc] wearing the [index]th screen of this template.
  ///
  /// **The words stay by default.** The template supplies size, weight, colour,
  /// case and position, and not a syllable of copy — this runs across a whole
  /// target at once and the project screen has no undo to walk it back.
  ///
  /// [withCopy] is for screens that have no words worth keeping: the ones a
  /// project is created with, whose headlines are the store's own placeholder
  /// text. There, the listing's copy is strictly better than "Highlight
  /// feature 2".
  ///
  /// A landscape page takes [featureGraphic] when there is one, whatever its
  /// index: a banner is one image, and dressing it in screenshot [index]'s
  /// portrait design is what left feature graphics undesigned.
  ///
  /// [withFrame] false keeps the set's own device instead of the listing's
  /// drawn one — see [framesFor] and [templateWearsFrame] — and [catalog] is
  /// where that device's proportions are read, so it is placed at the width
  /// the listing was designed for.
  ScreenDoc applyTo(
    ScreenDoc doc, {
    int index = 0,
    bool withCopy = false,
    bool withDisplay = false,
    bool? banner,
    bool withFrame = true,
    FrameCatalog? catalog,
  }) {
    final designs = designsFor(doc.canvas, banner: banner);
    // Nothing designed for this page — a banner, from a listing without one —
    // leaves it as it is.
    if (designs.isEmpty) return doc;
    return designs[index % designs.length].applyTo(
      doc,
      withCopy: withCopy,
      withDisplay: withDisplay,
      withFrame: withFrame,
      catalog: catalog,
    );
  }

  /// Whether this listing's drawn device belongs on a set for [platform].
  ///
  /// The mockup a listing was measured in is the handset its store sells. On a
  /// set for the other store it dressed an iPhone listing in an Android phone —
  /// a punch-hole bezel over the real iPhone — which App Review rejects. There
  /// the set keeps its own device and takes everything else: the colours, the
  /// type, the layout. A set with no device, or a listing that names no
  /// platform, has nothing to disagree about.
  bool framesFor(TemplatePlatform? platform) =>
      platform == null || platforms.isEmpty || platforms.contains(platform);
}

/// [after], an edit to [before], with every device a template lowered for its
/// artwork moved to where that template wants it now.
///
/// On a page taller than the one a listing was measured on, a phone showing
/// the listing's artwork sits low enough to keep the artwork's filled-in foot
/// off the page (see [TemplateScreen.displayVisiblePct]). The price is a wider
/// gap under the headline, worth paying only while the artwork is what shows.
/// Left there once somebody's capture covered it, every phone of a set made
/// from a template kept a gap the listing never had, to be closed by hand
/// screen by screen. So an edit that covers the artwork puts the phone back
/// where the listing designed it, and one that uncovers it lowers it again.
///
/// Only a phone still exactly where the template put it moves (its 3D tilt
/// aside, which applying keeps too): one somebody has placed since is their
/// composition, and stays. [templates] are the listings the artwork is
/// recognised from, and [catalog] is where the worn device is looked up, as
/// applying looked it up.
ScreenDoc settleTemplateArt(
  ScreenDoc before,
  ScreenDoc after, {
  required Iterable<ScreenTemplate> templates,
  FrameCatalog? catalog,
}) {
  // Devices added, removed or reordered, or a page resized, are a different
  // composition rather than a capture arriving.
  if (before.frames.length != after.frames.length ||
      before.canvas != after.canvas) {
    return after;
  }
  List<FramePlacement>? settled;
  for (var i = 0; i < after.frames.length; i++) {
    final was = before.frames[i];
    final now = after.frames[i];
    final art = _artOf(now);
    final showed = was.screenshot.imagePath == null;
    final shows = now.screenshot.imagePath == null;
    if (art == null || art != _artOf(was) || showed == shows) continue;
    for (final design in _designsShowing(art, templates)) {
      final worn = WornFrame.on(now, catalog) ?? design._ownFrame;
      final lowered = design.transformFor(
        after.canvas,
        worn: worn,
        showsArt: true,
      );
      final designed = design.transformFor(after.canvas, worn: worn);
      // Nothing was lowered on this page, so there is nothing to undo.
      if (_samePlace(lowered, designed)) continue;
      if (!_samePlace(now.transform, showed ? lowered : designed)) continue;
      (settled ??= [...after.frames])[i] = now.copyWith(
        transform: TemplateScreen._keepTilt(
          shows ? lowered : designed,
          now.transform,
        ),
      );
      break;
    }
  }
  return settled == null ? after : after.copyWith(frames: settled);
}

/// The listing artwork [placement]'s display is filled with, if any.
String? _artOf(FramePlacement placement) => switch (placement.screenshot.fill) {
  ImageBackground(:final path) => path,
  _ => null,
};

/// Every design among [templates] whose display is the artwork at [path].
Iterable<TemplateScreen> _designsShowing(
  String path,
  Iterable<ScreenTemplate> templates,
) sync* {
  for (final template in templates) {
    for (final design in [
      ...template.screens,
      ...template.landscapeScreens,
      ?template.featureGraphic,
    ]) {
      if (design.display case ImageBackground(path: final p) when p == path) {
        yield design;
      }
    }
  }
}

/// Whether [a] and [b] put a device in the same place, tilt aside.
bool _samePlace(Transform2D a, Transform2D b) {
  bool near(double x, double y) => (x - y).abs() < 1e-9;
  return near(a.scale, b.scale) &&
      near(a.pagePercentage, b.pagePercentage) &&
      near(a.rotationDeg, b.rotationDeg) &&
      near(a.offsetPct.dx, b.offsetPct.dx) &&
      near(a.offsetPct.dy, b.offsetPct.dy) &&
      near(a.align.x, b.align.x) &&
      near(a.align.y, b.align.y);
}
