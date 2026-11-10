/// The handset a new set starts on, for each store.
///
/// Once, here. It used to be written out in three places — the new-project
/// form, the project store's starter screens and the listing generator — and
/// the three had drifted to the point of all still opening Android sets on a
/// 2019 Galaxy Note 10+ with square screen corners.
library;

import '../../domain/models/store_target.dart';
import 'frame_catalog.dart';

/// The iPhone 16 in Ultramarine.
const kDefaultIosHandset = (
  deviceId: 'apple-iphone-16',
  variantId: '16---ultramarine',
);

/// The Galaxy S26 Ultra in Black: Samsung's current flagship and one of the
/// best-selling phones of 2026, flat-screened so a screenshot sits in it
/// undistorted, in a finish that does not compete with the picture.
const kDefaultAndroidHandset = (
  deviceId: 'samsung-galaxy-s26-ultra',
  variantId: 'black',
);

/// The default handset's ids for [platform].
({String deviceId, String variantId}) defaultHandsetFor(
  FramePlatform platform,
) =>
    platform == FramePlatform.ios ? kDefaultIosHandset : kDefaultAndroidHandset;

/// The device a new [target] set starts on, resolved against [catalog].
///
/// Falls back through: the store's default handset, then any device of that
/// platform with the target's form factor, then any device of that platform —
/// so a catalog that ships without the default still resolves to something
/// valid rather than to nothing. Null for a target that wears no handset.
(FrameDevice, FrameVariant)? defaultDeviceFor(
  StoreTarget target,
  FrameCatalog catalog,
) {
  final platform = target.framePlatform;
  if (platform == null) return null;
  final wanted = defaultHandsetFor(platform);
  final candidates = catalog.forPlatform(platform);
  if (candidates.isEmpty) return null;
  final formFactor = target.formFactor == TargetFormFactor.tablet
      ? 'tablet'
      : 'phone';
  final device =
      candidates.where((d) => d.id == wanted.deviceId).firstOrNull ??
      candidates.where((d) => d.formFactor == formFactor).firstOrNull ??
      candidates.first;
  final variant =
      device.variants.where((v) => v.id == wanted.variantId).firstOrNull ??
      device.variants.first;
  return (device, variant);
}
