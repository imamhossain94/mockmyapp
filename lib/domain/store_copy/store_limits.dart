/// What each store lets a listing say, field by field: what the counters and
/// the export check against. A const table, because it costs nothing to look
/// up in a text field's `onChanged`.
///
/// The figures are the consoles' own. Re-check them in App Store Connect and
/// the Play Console before relying on a change, and change them only here.
///
/// Limits are characters — grapheme clusters, so an emoji or an accented
/// letter is one — unless [CopyUnit.bytes]: Apple's keyword field and every
/// Samsung field count UTF-8 bytes, which is what makes a Japanese or Bengali
/// keyword list run out three times sooner than an English one.
library;

import 'dart:convert';

import 'package:flutter/widgets.dart' show StringCharacters;

import '../models/store_target.dart';

/// How a store measures a field.
enum CopyUnit { chars, bytes }

/// [text]'s length as a store counts it.
int measureCopy(String text, CopyUnit unit) => switch (unit) {
  CopyUnit.bytes => utf8.encode(text).length,
  CopyUnit.chars => text.characters.length,
};

/// One field a store console has, with the limit the console enforces.
class CopyFieldSpec {
  const CopyFieldSpec({
    required this.id,
    required this.label,
    required this.limit,
    required this.unit,
    required this.verified,
    this.min,
    this.maxItems,
    this.minItems,
    this.keywords = false,
    this.house = false,
    this.perScreenshot = false,
  });

  /// The field's id, and the key the text is saved under. Persisted: never
  /// renamed.
  final String id;

  /// What the console calls it.
  final String label;

  /// The most it may hold, in [unit] — per item, for a list.
  final int limit;
  final CopyUnit unit;

  /// The least it must hold, when the console says.
  final int? min;

  /// A list field — one item per line — holds at most this many items.
  final int? maxItems;
  final int? minItems;

  /// Apple's keyword field: comma-separated terms packed without spaces.
  final bool keywords;

  /// Whether the limit was confirmed against the store's own documentation.
  final bool verified;

  /// A limit of MockMyApp's own, where the store states none.
  final bool house;

  /// Text that belongs to one screenshot each, in order — Play's alt text,
  /// Microsoft's captions. Written and checked here; a draft of the
  /// listing's own fields never writes it.
  final bool perScreenshot;

  bool get isList => maxItems != null;

  /// "30 characters", "100 bytes", "80 characters each".
  String get limitLabel {
    final unitWord = unit == CopyUnit.bytes ? 'bytes' : 'characters';
    return isList ? '$limit $unitWord each' : '$limit $unitWord';
  }
}

/// The stores a listing's words are written for.
///
/// Persisted by [name], so the names never change, and the order is free.
/// Separate from [StoreKind], which is about where artwork goes: Amazon has
/// no screenshot target here, and the Chrome Web Store has no store copy.
enum CopyStore {
  appStore('App Store'),
  macAppStore('Mac App Store'),
  playStore('Google Play'),
  microsoftStore('Microsoft Store'),
  galaxyStore('Galaxy Store'),
  huaweiAppGallery('AppGallery'),
  amazonAppstore('Amazon Appstore');

  const CopyStore(this.label);

  final String label;

  /// Apple's two stores, which share their fields and their review rules
  /// (guidelines 2.3.7 and 2.3.10).
  bool get isApple => this == appStore || this == macAppStore;

  /// The fields the store's console has, in the console's order.
  List<CopyFieldSpec> get fields => kStoreCopyFields[this]!;

  /// The per-screenshot text the store takes, when it takes any.
  CopyFieldSpec? get screenshotText => kScreenshotText[this];

  /// Every field this page shows: the console's own, then the screenshots'.
  List<CopyFieldSpec> get allFields => [...fields, ?screenshotText];

  CopyFieldSpec? field(String id) =>
      allFields.where((f) => f.id == id).firstOrNull;

  /// Whether the app offers this store: every limit verified, or one of our
  /// own where the store states none. Huawei's figures are third-party, so
  /// it waits until someone checks them in AppGallery Connect.
  bool get offered => allFields.every((f) => f.verified || f.house);

  /// The screenshot store this copy goes with, for picking the stores a
  /// project's targets point at. Null for Amazon, which has no target.
  StoreKind? get storeKind => switch (this) {
    appStore => StoreKind.appStore,
    macAppStore => StoreKind.macAppStore,
    playStore => StoreKind.playStore,
    microsoftStore => StoreKind.microsoftStore,
    galaxyStore => StoreKind.galaxyStore,
    huaweiAppGallery => StoreKind.huaweiAppGallery,
    amazonAppstore => null,
  };

  static CopyStore? byName(String name) =>
      values.where((s) => s.name == name).firstOrNull;
}

/// Apple's fields, shared by the App Store and the Mac App Store.
const _apple = [
  CopyFieldSpec(
    id: 'name',
    label: 'Name',
    limit: 30,
    min: 2,
    unit: CopyUnit.chars,
    verified: true,
  ),
  CopyFieldSpec(
    id: 'subtitle',
    label: 'Subtitle',
    limit: 30,
    unit: CopyUnit.chars,
    verified: true,
  ),
  CopyFieldSpec(
    id: 'keywords',
    label: 'Keywords',
    limit: 100,
    unit: CopyUnit.bytes,
    keywords: true,
    verified: true,
  ),
  CopyFieldSpec(
    id: 'promotionalText',
    label: 'Promotional text',
    limit: 170,
    unit: CopyUnit.chars,
    verified: true,
  ),
  CopyFieldSpec(
    id: 'description',
    label: 'Description',
    limit: 4000,
    unit: CopyUnit.chars,
    verified: true,
  ),
  CopyFieldSpec(
    id: 'whatsNew',
    label: "What's New",
    limit: 4000,
    unit: CopyUnit.chars,
    verified: true,
  ),
];

/// Every store's console fields.
const kStoreCopyFields = <CopyStore, List<CopyFieldSpec>>{
  CopyStore.appStore: _apple,
  CopyStore.macAppStore: _apple,
  CopyStore.playStore: [
    CopyFieldSpec(
      id: 'title',
      label: 'App name',
      limit: 30,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'shortDescription',
      label: 'Short description',
      limit: 80,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'fullDescription',
      label: 'Full description',
      limit: 4000,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'releaseNotes',
      label: 'Release notes',
      limit: 500,
      unit: CopyUnit.chars,
      verified: true,
    ),
  ],
  CopyStore.microsoftStore: [
    CopyFieldSpec(
      id: 'shortTitle',
      label: 'Short title',
      limit: 50,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'shortDescription',
      label: 'Short description',
      limit: 1000,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'description',
      label: 'Description',
      limit: 10000,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'whatsNew',
      label: "What's new",
      limit: 1500,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'features',
      label: 'Product features',
      limit: 200,
      unit: CopyUnit.chars,
      maxItems: 20,
      verified: true,
    ),
  ],
  CopyStore.galaxyStore: [
    CopyFieldSpec(
      id: 'title',
      label: 'App title',
      limit: 100,
      unit: CopyUnit.bytes,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'shortDescription',
      label: 'Short description',
      limit: 40,
      unit: CopyUnit.bytes,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'description',
      label: 'Long description',
      limit: 4000,
      unit: CopyUnit.bytes,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'whatsNew',
      label: 'New features',
      limit: 4000,
      unit: CopyUnit.bytes,
      verified: true,
    ),
  ],
  CopyStore.huaweiAppGallery: [
    CopyFieldSpec(
      id: 'name',
      label: 'App name',
      limit: 64,
      min: 3,
      unit: CopyUnit.chars,
      verified: false,
    ),
    CopyFieldSpec(
      id: 'briefIntro',
      label: 'Brief introduction',
      limit: 80,
      unit: CopyUnit.chars,
      verified: false,
    ),
    CopyFieldSpec(
      id: 'introduction',
      label: 'Introduction',
      limit: 8000,
      min: 100,
      unit: CopyUnit.chars,
      verified: false,
    ),
    CopyFieldSpec(
      id: 'releaseNotes',
      label: 'Release notes',
      limit: 1000,
      unit: CopyUnit.chars,
      verified: false,
    ),
  ],
  CopyStore.amazonAppstore: [
    CopyFieldSpec(
      id: 'shortDescription',
      label: 'Short description',
      limit: 2000,
      unit: CopyUnit.bytes,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'description',
      label: 'Long description',
      limit: 4000,
      unit: CopyUnit.chars,
      verified: true,
    ),
    CopyFieldSpec(
      id: 'features',
      label: 'Feature bullets',
      limit: 250,
      unit: CopyUnit.chars,
      maxItems: 5,
      minItems: 3,
      verified: false,
      house: true,
    ),
  ],
};

/// The per-screenshot text each store takes — the JSON's
/// `stores.<store>.screenshotText`.
const kScreenshotText = <CopyStore, CopyFieldSpec>{
  CopyStore.playStore: CopyFieldSpec(
    id: 'altText',
    label: 'Screenshot alt text',
    limit: 140,
    unit: CopyUnit.chars,
    maxItems: 8,
    verified: true,
    perScreenshot: true,
  ),
  CopyStore.microsoftStore: CopyFieldSpec(
    id: 'screenshotCaptions',
    label: 'Screenshot captions',
    limit: 200,
    unit: CopyUnit.chars,
    maxItems: 10,
    verified: true,
    perScreenshot: true,
  ),
};
