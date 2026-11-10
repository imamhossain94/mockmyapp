/// The languages a listing can be made in.
///
/// Store locale codes, as App Store Connect and the Play Console name them —
/// so an export folder called `de-DE` drops straight into the slot it is for.
library;

/// The language a new project is made in.
const kDefaultLanguage = 'en-US';

/// One language a store accepts.
class StoreLocale {
  const StoreLocale(this.code, this.name, {this.rtl = false});

  final String code;
  final String name;

  /// Written right to left. The editor keeps the layout, but a caption's
  /// alignment reads the other way round.
  final bool rtl;

  /// A short tag for tight spaces: `EN`, `DE`, `PT-BR`, `ZH-HANS`.
  String get short {
    final parts = code.split('-');
    if (parts.length == 1) return parts.first.toUpperCase();
    // Region only where it tells two languages apart.
    const regional = {
      'en-GB',
      'en-AU',
      'en-CA',
      'es-MX',
      'pt-BR',
      'pt-PT',
      'fr-CA',
      'zh-Hans',
      'zh-Hant',
    };
    return regional.contains(code)
        ? code.toUpperCase()
        : parts.first.toUpperCase();
  }
}

/// Every language offered, roughly by how many listings are made in it.
const storeLocales = <StoreLocale>[
  StoreLocale('en-US', 'English (US)'),
  StoreLocale('en-GB', 'English (UK)'),
  StoreLocale('es-ES', 'Spanish (Spain)'),
  StoreLocale('es-MX', 'Spanish (Mexico)'),
  StoreLocale('pt-BR', 'Portuguese (Brazil)'),
  StoreLocale('pt-PT', 'Portuguese (Portugal)'),
  StoreLocale('fr-FR', 'French'),
  StoreLocale('fr-CA', 'French (Canada)'),
  StoreLocale('de-DE', 'German'),
  StoreLocale('it-IT', 'Italian'),
  StoreLocale('nl-NL', 'Dutch'),
  StoreLocale('ja-JP', 'Japanese'),
  StoreLocale('ko-KR', 'Korean'),
  StoreLocale('zh-Hans', 'Chinese (Simplified)'),
  StoreLocale('zh-Hant', 'Chinese (Traditional)'),
  StoreLocale('ru-RU', 'Russian'),
  StoreLocale('tr-TR', 'Turkish'),
  StoreLocale('ar-SA', 'Arabic', rtl: true),
  StoreLocale('he-IL', 'Hebrew', rtl: true),
  StoreLocale('hi-IN', 'Hindi'),
  StoreLocale('bn-BD', 'Bengali'),
  StoreLocale('id-ID', 'Indonesian'),
  StoreLocale('ms-MY', 'Malay'),
  StoreLocale('th-TH', 'Thai'),
  StoreLocale('vi-VN', 'Vietnamese'),
  StoreLocale('pl-PL', 'Polish'),
  StoreLocale('uk-UA', 'Ukrainian'),
  StoreLocale('cs-CZ', 'Czech'),
  StoreLocale('sk-SK', 'Slovak'),
  StoreLocale('hu-HU', 'Hungarian'),
  StoreLocale('ro-RO', 'Romanian'),
  StoreLocale('el-GR', 'Greek'),
  StoreLocale('sv-SE', 'Swedish'),
  StoreLocale('da-DK', 'Danish'),
  StoreLocale('nb-NO', 'Norwegian'),
  StoreLocale('fi-FI', 'Finnish'),
  StoreLocale('hr-HR', 'Croatian'),
  StoreLocale('ca-ES', 'Catalan'),
  StoreLocale('en-AU', 'English (Australia)'),
  StoreLocale('en-CA', 'English (Canada)'),
];

/// The locale for [code], or a plain one named by the code itself for a
/// language this build does not list.
StoreLocale localeFor(String code) => storeLocales.firstWhere(
  (l) => l.code == code,
  orElse: () => StoreLocale(code, code),
);
