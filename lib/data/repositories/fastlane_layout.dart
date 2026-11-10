import 'package:flutter/painting.dart';

import '../../domain/models/store_target.dart';

/// Which fastlane action uploads a file.
enum FastlaneTool {
  /// `fastlane deliver`, for App Store Connect.
  deliver,

  /// `fastlane supply`, for the Play Console.
  supply,
}

/// Where one set's files go in a fastlane layout.
class FastlaneSlot {
  const FastlaneSlot.deliver({required this.folder, required this.displayType})
    : tool = FastlaneTool.deliver,
      single = false;

  const FastlaneSlot.supply({required this.folder, this.single = false})
    : tool = FastlaneTool.supply,
      displayType = null;

  final FastlaneTool tool;

  /// For deliver, the screenshots folder at the root of the layout —
  /// `screenshots`, or a sibling for a platform deliver uploads separately.
  /// For supply, the image type: a folder of screenshots
  /// (`phoneScreenshots`) or, when [single], the name of the one file
  /// (`featureGraphic`, `icon`).
  final String folder;

  /// App Store Connect's name for the device class — `APP_IPHONE_67` — which
  /// starts every file name. Null for supply.
  final String? displayType;

  /// Whether the slot takes one file rather than a numbered folder of them.
  final bool single;

  /// Where the file at [index] (zero-based) of this set goes, for
  /// [language] — a store locale code as the project names it.
  String pathFor({
    required String language,
    required int index,
    required String extension,
  }) {
    final ordinal = '${index + 1}'.padLeft(2, '0');
    return switch (tool) {
      FastlaneTool.deliver =>
        '$folder/${FastlaneLayout.appleLocale(language)}/'
            '${displayType}_$ordinal.$extension',
      FastlaneTool.supply =>
        'metadata/android/${FastlaneLayout.playLocale(language)}/images/'
            '${single ? '$folder.$extension' : '$folder/$ordinal.$extension'}',
    };
  }
}

/// The folder layouts `fastlane deliver` and `fastlane supply` read, so an
/// export unzips straight into a project's `fastlane/` directory and uploads
/// from CI.
///
/// deliver reads `screenshots/<locale>/` and tells the device class from each
/// file's resolution, uploading the files of a class in name order. The names
/// here start with App Store Connect's display type, which keeps each class
/// together and in order — and for iPad it is load-bearing: 2048 × 2732 is
/// both the 12.9-inch and the 13-inch class, and deliver files a shot under
/// the newer one only when its name carries `IPAD_PRO_3GEN_129`.
///
/// supply reads `metadata/android/<locale>/images/`, with a folder per kind
/// of screenshot and single files for the feature graphic and the icon.
///
/// Platform folders other than `screenshots` (`screenshots-macos` and the
/// like) are for the Apple platforms deliver uploads in a run of their own;
/// point that run's `screenshots_path` at them. Worth one dry run with
/// `fastlane deliver --verify_only` before relying on it in CI.
abstract final class FastlaneLayout {
  /// The archive's top folder, so the layout lands in `fastlane/` when it is
  /// unzipped at a project's root.
  static const root = 'fastlane';

  /// Where [target]'s set at [canvas] goes, or null when neither tool can
  /// upload it — see [skipReason].
  static FastlaneSlot? slotFor(
    StoreTarget target,
    Size canvas,
    String presetId,
  ) {
    switch (target.id) {
      case 'ios-iphone':
        final type = _iphoneType(canvas);
        return type == null
            ? null
            : FastlaneSlot.deliver(folder: 'screenshots', displayType: type);
      case 'ios-ipad':
        return _sizeIn(canvas, const [Size(2064, 2752), Size(2048, 2732)])
            ? const FastlaneSlot.deliver(
                folder: 'screenshots',
                displayType: 'APP_IPAD_PRO_3GEN_129',
              )
            : null;
      case 'apple-watch':
        final type = _watchType(canvas);
        return type == null
            ? null
            : FastlaneSlot.deliver(folder: 'screenshots', displayType: type);
      // One class each, so any size Apple lists for it will do — and a custom
      // canvas, which Apple does not list, has nowhere to go.
      case 'apple-tv':
        return _listed(target, canvas)
            ? const FastlaneSlot.deliver(
                folder: 'screenshots-tvos',
                displayType: 'APP_APPLE_TV',
              )
            : null;
      case 'vision-pro':
        return _listed(target, canvas)
            ? const FastlaneSlot.deliver(
                folder: 'screenshots-visionos',
                displayType: 'APP_APPLE_VISION_PRO',
              )
            : null;
      case 'mac':
        return _listed(target, canvas)
            ? const FastlaneSlot.deliver(
                folder: 'screenshots-macos',
                displayType: 'APP_DESKTOP',
              )
            : null;
      case 'android-phone':
        return const FastlaneSlot.supply(folder: 'phoneScreenshots');
      case 'android-tablet':
        // The 7-inch presets fill Play's 7-inch slot; every other tablet size
        // goes in the 10-inch one, which is what large-screen promotion reads.
        return FastlaneSlot.supply(
          folder: presetId.startsWith('android-tablet-7')
              ? 'sevenInchScreenshots'
              : 'tenInchScreenshots',
        );
      case 'android-feature-graphic':
        return const FastlaneSlot.supply(
          folder: 'featureGraphic',
          single: true,
        );
      case 'android-app-icon':
        return const FastlaneSlot.supply(folder: 'icon', single: true);
    }
    return null;
  }

  /// Why [target]'s set has no place in the layout, for the checklist — or
  /// null when it has one.
  static String? skipReason(StoreTarget target, Size canvas, String presetId) {
    if (slotFor(target, canvas, presetId) != null) return null;
    final size = '${canvas.width.round()} × ${canvas.height.round()}';
    return switch (target.id) {
      'ios-iphone' ||
      'ios-ipad' ||
      'apple-watch' ||
      'apple-tv' ||
      'vision-pro' ||
      'mac' =>
        "$size isn't a size App Store Connect files under a "
            'device class.',
      'ios-iphone-duo-inner' ||
      'ios-iphone-duo-outer' => 'App Store Connect has no iPhone Duo slot yet.',
      'ios-creative-assets' ||
      'ios-event-card' ||
      'ios-event-details' => 'deliver does not upload this artwork.',
      'chromebook' ||
      'android-xr' => 'supply has no slot for ${target.label} screenshots.',
      _ => "fastlane doesn't upload to ${target.storeLabel}.",
    };
  }

  static bool _listed(StoreTarget target, Size canvas) =>
      _sizeIn(canvas, target.exactSizes ?? const []);

  static bool _sizeIn(Size canvas, List<Size> sizes) => sizes.any(
    (s) =>
        (s.width == canvas.width && s.height == canvas.height) ||
        (s.width == canvas.height && s.height == canvas.width),
  );

  /// App Store Connect's display type for an iPhone canvas. Its API has no
  /// 6.9-inch or 6.3-inch type: those upload as the 6.7-inch and 6.1-inch
  /// classes they replaced.
  static String? _iphoneType(Size canvas) {
    const types = [
      ('APP_IPHONE_67', [Size(1320, 2868), Size(1290, 2796), Size(1260, 2736)]),
      ('APP_IPHONE_65', [Size(1284, 2778), Size(1242, 2688)]),
      ('APP_IPHONE_61', [Size(1206, 2622), Size(1179, 2556), Size(1170, 2532)]),
      ('APP_IPHONE_58', [Size(1125, 2436), Size(1080, 2340)]),
      ('APP_IPHONE_55', [Size(1242, 2208)]),
    ];
    for (final (type, sizes) in types) {
      if (_sizeIn(canvas, sizes)) return type;
    }
    return null;
  }

  static String? _watchType(Size canvas) {
    const types = [
      ('APP_WATCH_ULTRA', [Size(422, 514), Size(410, 502)]),
      ('APP_WATCH_SERIES_10', [Size(416, 496)]),
      ('APP_WATCH_SERIES_7', [Size(396, 484)]),
      ('APP_WATCH_SERIES_4', [Size(368, 448)]),
    ];
    for (final (type, sizes) in types) {
      if (_sizeIn(canvas, sizes)) return type;
    }
    return null;
  }

  /// [code] as App Store Connect names the locale, for deliver's folders.
  ///
  /// The project keeps one code per language (`ja-JP`, `nb-NO`), and the two
  /// consoles disagree about most of them: Apple writes many without a region
  /// (`ja`, `no`). A code neither table knows is passed through as it is.
  static String appleLocale(String code) => _apple[code] ?? code;

  /// [code] as the Play Console names the locale, for supply's folders:
  /// `zh-Hans` is `zh-CN` there, Hebrew is still `iw-IL`.
  static String playLocale(String code) => _play[code] ?? code;

  static const _apple = {
    'it-IT': 'it',
    'ja-JP': 'ja',
    'ko-KR': 'ko',
    'ru-RU': 'ru',
    'tr-TR': 'tr',
    'he-IL': 'he',
    'hi-IN': 'hi',
    'id-ID': 'id',
    'ms-MY': 'ms',
    'th-TH': 'th',
    'vi-VN': 'vi',
    'pl-PL': 'pl',
    'uk-UA': 'uk',
    'cs-CZ': 'cs',
    'sk-SK': 'sk',
    'hu-HU': 'hu',
    'ro-RO': 'ro',
    'el-GR': 'el',
    'sv-SE': 'sv',
    'da-DK': 'da',
    'nb-NO': 'no',
    'fi-FI': 'fi',
    'hr-HR': 'hr',
    'ca-ES': 'ca',
  };

  static const _play = {
    'es-MX': 'es-419',
    'zh-Hans': 'zh-CN',
    'zh-Hant': 'zh-TW',
    'ar-SA': 'ar',
    'he-IL': 'iw-IL',
    'id-ID': 'id',
    'th-TH': 'th',
    'vi-VN': 'vi',
    'uk-UA': 'uk',
    'sk-SK': 'sk',
    'ro-RO': 'ro',
    'nb-NO': 'no-NO',
    'hr-HR': 'hr',
    'ca-ES': 'ca',
  };
}
