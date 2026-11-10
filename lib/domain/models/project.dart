import '../../data/assets/frame_catalog.dart';
import '../../data/serialization.dart';
import 'icon_doc.dart';
import 'listing_brief.dart';
import 'locales.dart';
import 'screen_doc.dart';
import 'store_copy.dart';
import 'style_library.dart';
import 'store_target.dart';
import 'sub_project.dart';

export 'locales.dart' show kDefaultLanguage;

/// A project groups everything one app needs to ship its store listings.
///
/// It holds a [SubProject] per store target rather than a flat list of screens,
/// because a listing is never one canvas: Apple wants a 6.9-inch iPhone set and
/// a 13-inch iPad set, Google wants phone screenshots and a feature graphic,
/// and a cross-platform app adds Mac, Microsoft Store and Chrome Web Store on
/// top. Each of those is its own canvas holding its own work, and all of it
/// belongs to one app.
class Project {
  const Project({
    required this.id,
    required this.name,
    required this.subProjects,
    required this.createdAt,
    this.styles = StyleLibrary.empty,
    this.languages = const [kDefaultLanguage],
    this.brief = ListingBrief.empty,
    this.storeCopy = StoreCopy.empty,
    this.icon,
  });

  /// The app's icon, designed on the Icon page — or null until one is. Every
  /// store's icon file is derived from it, and the store preview shows it.
  final IconDoc? icon;

  /// What the app is — the "Generate with AI" wizard's analysis, or what the
  /// person wrote on the Store copy page — so copy can be drafted from it.
  final ListingBrief brief;

  /// The listing's words outside the screenshots, per store and language.
  final StoreCopy storeCopy;

  /// The languages the listing is made in, as store locale codes. The first
  /// is the default: the words every caption and label holds of its own, and
  /// what any language without a translation falls back to.
  final List<String> languages;

  String get defaultLanguage =>
      languages.isEmpty ? kDefaultLanguage : languages.first;

  final String id;
  final String name;

  /// The named looks this project reuses across its screens.
  ///
  /// On the project rather than on a target: a headline style is the same
  /// headline whether it is going on an iPhone listing or an iPad one, and a
  /// library that stopped at the target boundary would have to be rebuilt for
  /// every set in the project.
  final StyleLibrary styles;

  /// The target sets, in the order the user added them. The first is what the
  /// project page opens on.
  final List<SubProject> subProjects;

  final DateTime createdAt;

  /// Every screen in the project, across all targets — for counts, for the
  /// library's thumbnails, and for a whole-project export.
  Iterable<ScreenDoc> get allScreens => subProjects.expand((s) => s.screens);

  int get screenCount =>
      subProjects.fold(0, (sum, s) => sum + s.screens.length);

  SubProject? subProjectById(String id) =>
      subProjects.where((s) => s.id == id).firstOrNull;

  /// The set [screenId] belongs to.
  ///
  /// Screen ids are uuids, so this is unambiguous — which is what lets the
  /// editor keep addressing a document by id alone, without a target in its
  /// route or in every store mutator's signature.
  SubProject? subProjectOf(String screenId) {
    for (final sub in subProjects) {
      for (final screen in sub.screens) {
        if (screen.id == screenId) return sub;
      }
    }
    return null;
  }

  Project copyWith({
    String? name,
    List<SubProject>? subProjects,
    StyleLibrary? styles,
    List<String>? languages,
    ListingBrief? brief,
    StoreCopy? storeCopy,
    IconDoc? icon,
    bool clearIcon = false,
  }) => Project(
    id: id,
    name: name ?? this.name,
    subProjects: subProjects ?? this.subProjects,
    createdAt: createdAt,
    styles: styles ?? this.styles,
    languages: languages ?? this.languages,
    brief: brief ?? this.brief,
    storeCopy: storeCopy ?? this.storeCopy,
    icon: clearIcon ? null : (icon ?? this.icon),
  );

  /// Replaces one sub-project in place, keeping the order.
  Project withSubProject(String subId, SubProject Function(SubProject) fn) =>
      copyWith(
        subProjects: [
          for (final sub in subProjects)
            if (sub.id == subId) fn(sub) else sub,
        ],
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subProjects': subProjects.map((s) => s.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'styles': styleLibraryToJson(styles),
    // Only when there is more than the default, so a one-language project's
    // JSON is what it always was.
    if (languages.length > 1 || languages.firstOrNull != kDefaultLanguage)
      'languages': languages,
    // Last and only when there is something in them, for the same reason: a
    // project with no brief and no copy writes exactly what it always did.
    if (!brief.isEmpty) 'brief': brief.toJson(),
    if (!storeCopy.isEmpty) 'storeCopy': storeCopy.toJson(),
    // The same again for the icon: absent until one is designed.
    if (icon case final doc?) 'icon': doc.toJson(),
  };

  /// Reads both the current shape and the one that came before it.
  ///
  /// Before targets, a project was a single `platform` over a flat `screens`
  /// list. Those documents are still on disk and inside every backup taken up
  /// to now, so they load into exactly one sub-project, with the target and
  /// preset recovered by [StoreTargets.forLegacy] from the platform and the
  /// first screen's canvas.
  factory Project.fromJson(Map<String, dynamic> j) {
    final raw = j['subProjects'] as List?;
    return Project(
      id: j['id'] as String,
      name: j['name'] as String,
      subProjects: raw != null
          ? raw
                .map((e) => SubProject.fromJson(e as Map<String, dynamic>))
                .toList()
          : _legacySubProjects(j),
      createdAt: DateTime.parse(j['createdAt'] as String),
      styles: styleLibraryFromJson(j['styles'] as Map<String, dynamic>?),
      languages: switch (j['languages']) {
        final List<dynamic> list when list.isNotEmpty => [
          for (final l in list) l as String,
        ],
        _ => const [kDefaultLanguage],
      },
      // Absent on every project saved before they existed: no brief, no copy.
      brief: ListingBrief.fromJson(j['brief']),
      storeCopy: StoreCopy.fromJson(j['storeCopy']),
      // Absent on every project saved before icons existed: no icon.
      icon: IconDoc.fromJson(j['icon']),
    );
  }

  /// One sub-project from a pre-target document.
  ///
  /// The sub-project reuses the project's own id. It is unique by construction,
  /// it needs no uuid dependency down here in the model, and it makes a
  /// migrated project recognisable in a bundle.
  static List<SubProject> _legacySubProjects(Map<String, dynamic> j) {
    final screens = (j['screens'] as List? ?? const [])
        .map((e) => screenDocFromJson(e as Map<String, dynamic>))
        .toList();
    final platform = j['platform'] == 'ios'
        ? FramePlatform.ios
        : FramePlatform.android;
    final canvas =
        screens.firstOrNull?.canvas ??
        (platform == FramePlatform.ios
            ? StoreTargets.iphone.defaultPreset.size
            : StoreTargets.androidPhone.defaultPreset.size);

    final (target, preset) = StoreTargets.forLegacy(platform, canvas);
    return [
      SubProject(
        id: j['id'] as String,
        targetId: target.id,
        presetId: preset.id,
        canvas: canvas,
        screens: screens,
      ),
    ];
  }
}
