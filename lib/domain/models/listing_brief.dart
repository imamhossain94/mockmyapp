import 'package:flutter/foundation.dart';

import '../../data/services/on_device_ai.dart' show CaptionTone;
import '../listing/listing_analysis.dart';
import 'screen_template.dart';

/// What the app is, kept with the project so its store copy — and later its
/// captions and backgrounds — can be written from it at any time.
///
/// The "Generate with AI" wizard used to work all of this out and then throw
/// it away once the project existed; now its analysis lands here. A project
/// made any other way starts with an empty brief, filled in on the Store copy
/// page.
///
/// Persisted with the project, and only what is set: an empty brief writes
/// nothing, and each empty field inside one writes nothing, so every project
/// saved before briefs existed reads back and saves byte for byte.
@immutable
class ListingBrief {
  const ListingBrief({
    this.appName = '',
    this.description = '',
    this.audience = '',
    this.category,
    this.keywords = const [],
    this.tone = CaptionTone.bold,
    this.features = const [],
    this.usps = const [],
  });

  static const empty = ListingBrief();

  /// The wizard's analysis of [description], kept.
  factory ListingBrief.fromAnalysis(
    ListingAnalysis analysis, {
    required String description,
    CaptionTone tone = CaptionTone.bold,
  }) => ListingBrief(
    appName: analysis.appName.trim(),
    description: description.trim(),
    audience: analysis.audience.trim(),
    category: analysis.category,
    keywords: [
      for (final k in analysis.keywords)
        if (k.trim().isNotEmpty) k.trim(),
    ],
    tone: tone,
    features: [
      for (final f in analysis.features)
        if (f.title.trim().isNotEmpty) f,
    ],
    usps: [
      for (final u in analysis.usps)
        if (u.trim().isNotEmpty) u.trim(),
    ],
  );

  /// The app's name as the person writes it.
  final String appName;

  /// What the app does, in the person's own words — the wizard's product
  /// description.
  final String description;

  /// Who it is for, as one sentence.
  final String audience;

  /// The kind of app, or null when nobody said.
  final TemplateCategory? category;

  /// The words people would search the stores with, lower case.
  final List<String> keywords;

  /// The voice its copy is written in.
  final CaptionTone tone;

  /// What it does, a screenshot's worth at a time — the wizard's features.
  final List<ListingFeature> features;

  /// What sets it apart, as short phrases.
  final List<String> usps;

  /// Whether nothing has been said about the app at all. The tone counts:
  /// somebody who only chose a voice has still said something.
  bool get isEmpty =>
      appName.trim().isEmpty &&
      description.trim().isEmpty &&
      audience.trim().isEmpty &&
      category == null &&
      keywords.isEmpty &&
      tone == CaptionTone.bold &&
      features.isEmpty &&
      usps.isEmpty;

  ListingBrief copyWith({
    String? appName,
    String? description,
    String? audience,
    TemplateCategory? category,
    bool clearCategory = false,
    List<String>? keywords,
    CaptionTone? tone,
    List<ListingFeature>? features,
    List<String>? usps,
  }) => ListingBrief(
    appName: appName ?? this.appName,
    description: description ?? this.description,
    audience: audience ?? this.audience,
    category: clearCategory ? null : (category ?? this.category),
    keywords: keywords ?? this.keywords,
    tone: tone ?? this.tone,
    features: features ?? this.features,
    usps: usps ?? this.usps,
  );

  /// Only what is set, so an untouched field costs nothing on disk and a
  /// brief read back writes exactly what it was read from.
  Map<String, dynamic> toJson() => {
    if (appName.isNotEmpty) 'appName': appName,
    if (description.isNotEmpty) 'description': description,
    if (audience.isNotEmpty) 'audience': audience,
    'category': ?category?.name,
    if (keywords.isNotEmpty) 'keywords': keywords,
    if (tone != CaptionTone.bold) 'tone': tone.name,
    if (features.isNotEmpty)
      'features': [
        for (final f in features)
          {
            'title': f.title,
            if (f.detail.isNotEmpty) 'detail': f.detail,
            if (f.importance != 7) 'importance': f.importance,
          },
      ],
    if (usps.isNotEmpty) 'usps': usps,
  };

  /// Reads a saved brief; anything absent, of the wrong type or unknown to
  /// this build — a category or tone a newer one added — takes the empty
  /// default rather than throwing, so one odd field never costs a project.
  factory ListingBrief.fromJson(Object? json) {
    if (json is! Map) return empty;
    String text(Object? v) => v is String ? v : '';
    List<String> strings(Object? v) => [
      if (v is List)
        for (final s in v)
          if (s is String && s.isNotEmpty) s,
    ];
    final category = json['category'];
    final tone = json['tone'];
    return ListingBrief(
      appName: text(json['appName']),
      description: text(json['description']),
      audience: text(json['audience']),
      category: TemplateCategory.values
          .where((c) => c.name == category)
          .firstOrNull,
      keywords: strings(json['keywords']),
      tone:
          CaptionTone.values.where((t) => t.name == tone).firstOrNull ??
          CaptionTone.bold,
      features: [
        if (json['features'] case final List list)
          for (final f in list)
            if (f is Map && f['title'] is String && f['title'] != '')
              ListingFeature(
                title: f['title'] as String,
                detail: text(f['detail']),
                importance: switch (f['importance']) {
                  final num n => n.round().clamp(1, 10),
                  _ => 7,
                },
              ),
      ],
      usps: strings(json['usps']),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ListingBrief &&
      other.appName == appName &&
      other.description == description &&
      other.audience == audience &&
      other.category == category &&
      listEquals(other.keywords, keywords) &&
      other.tone == tone &&
      listEquals(other.features, features) &&
      listEquals(other.usps, usps);

  @override
  int get hashCode => Object.hash(
    appName,
    description,
    audience,
    category,
    Object.hashAll(keywords),
    tone,
    Object.hashAll(features),
    Object.hashAll(usps),
  );
}
