import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../app/layout/studio_layout.dart';
import '../../app/theme/studio_icons.dart';
import '../../app/theme/studio_tokens.dart';
import '../../app/theme/studio_typography.dart';
import '../../domain/engine/export_settings.dart';
import '../../domain/providers/settings_provider.dart';
import '../shared/save_actions.dart' show showStudioSnack;
import '../shared/widgets/widgets.dart';
import 'more_apps.dart';

// Settings, laid out as a JetBrains settings page: `textTertiary` eyebrows
// over flat grouped panels of hairline-separated rows.

/// Where MockMyApp's source code lives.
///
/// Shown and copied rather than opened: the app carries no plugin that hands
/// a link to the browser, so it starts no network request of its own, not
/// even this one.
const kSourceCodeUrl = 'https://github.com/imamhossain94/mockmyapp';

/// Puts [link] on the clipboard, and says so: the source code's address, or
/// one of the studio's other apps' store listings, which are copied for the
/// same reason the source is.
Future<void> _copyLink(BuildContext context, String link) async {
  await Clipboard.setData(ClipboardData(text: link));
  if (context.mounted) showStudioSnack(context, 'Link copied');
}

/// The version, read from the bundle rather than typed in.
///
/// It used to be the literal string `'CC 2026 (0.1.0)'` while pubspec said
/// `0.1.0+1` — the kind of drift nobody notices until a bug report cites a
/// version that was never shipped.
class _VersionRow extends StatelessWidget {
  const _VersionRow();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return StudioListRow(
          icon: StudioIcons.info,
          title: 'Version',
          trailing: _ValueReadout(
            info == null ? '—' : '${info.version} (${info.buildNumber})',
          ),
        );
      },
    );
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final exportSettings = ref.watch(exportSettingsProvider);
    final s = context.studio;

    return Scaffold(
      backgroundColor: s.canvas,
      appBar: AppBar(
        title: const Text('Settings'),
        titleSpacing: StudioSpace.l,
        toolbarHeight: StudioSizes.toolbar,
        backgroundColor: s.panel,
        foregroundColor: s.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: StudioText.titleLarge(context),
        // The hairline separates chrome from content — never a shadow.
        shape: Border(bottom: BorderSide(color: s.border)),
      ),
      // Capped and centred: settings is a single column of labelled rows, and
      // stretching it across a desktop window puts every control's label at one
      // end of the screen and its value at the other.
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: context.layout.readableWidth),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              StudioSpace.xl,
              StudioSpace.xxl,
              StudioSpace.xl,
              StudioSpace.xxl,
            ),
            children: [
              // ---------------------------------------------------------------
              // INTERFACE
              // ---------------------------------------------------------------
              const _Eyebrow('Interface'),
              _Group(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      StudioSpace.l,
                      StudioSpace.l,
                      StudioSpace.l,
                      StudioSpace.l,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Theme Mode',
                          style: StudioText.bodyStrong(context),
                        ),
                        SizedBox(height: StudioSpace.xxs),
                        Text(
                          'Light, dark, or follow the system setting',
                          style: StudioText.caption(context),
                        ),
                        SizedBox(height: StudioSpace.l),
                        StudioSegmented<ThemeMode>(
                          dense: true,
                          value: settings.themeMode,
                          segments: const [
                            StudioSegment(
                              ThemeMode.system,
                              'System',
                              icon: StudioIcons.themeSystem,
                            ),
                            StudioSegment(
                              ThemeMode.light,
                              'Light',
                              icon: StudioIcons.themeLight,
                            ),
                            StudioSegment(
                              ThemeMode.dark,
                              'Dark',
                              icon: StudioIcons.themeDark,
                            ),
                          ],
                          onChanged: (mode) {
                            ref
                                .read(settingsProvider.notifier)
                                .setThemeMode(mode);
                          },
                        ),
                      ],
                    ),
                  ),
                  if (Theme.of(context).platform == TargetPlatform.android) ...[
                    const StudioDivider(),
                    StudioListRow(
                      icon: StudioIcons.palette,
                      title: 'Dynamic Color',
                      subtitle: 'Material You wallpaper extraction',
                      onTap: () => ref
                          .read(settingsProvider.notifier)
                          .setDynamicColorEnabled(
                            !settings.dynamicColorEnabled,
                          ),
                      trailing: Switch(
                        value: settings.dynamicColorEnabled,
                        onChanged: (val) {
                          ref
                              .read(settingsProvider.notifier)
                              .setDynamicColorEnabled(val);
                        },
                      ),
                    ),
                  ],
                ],
              ),

              SizedBox(height: StudioSpace.xxxl),

              // ---------------------------------------------------------------
              // EXPORT & PERFORMANCE
              // ---------------------------------------------------------------
              const _Eyebrow('Export'),
              _Group(
                children: [
                  // A tap steps to the next choice: two formats and four
                  // scales are few enough that a picker would be ceremony.
                  StudioListRow(
                    icon: StudioIcons.image,
                    title: 'Export format',
                    subtitle: exportSettings.format == ExportFormat.png
                        ? 'Lossless — what both stores recommend'
                        : 'Smaller files, flattened onto white',
                    trailing: _ValueReadout(exportSettings.format.label),
                    onTap: () => ref
                        .read(exportSettingsProvider.notifier)
                        .set(
                          exportSettings.copyWith(
                            format: exportSettings.format == ExportFormat.png
                                ? ExportFormat.jpg
                                : ExportFormat.png,
                          ),
                        ),
                  ),
                  const StudioDivider(),
                  StudioListRow(
                    icon: StudioIcons.quality,
                    title: 'Export resolution',
                    subtitle: exportSettings.scale == 1
                        ? 'Exactly the store size'
                        : 'Not a store size — for press kits and print',
                    trailing: _ValueReadout(
                      exportSettings.summary.split(' · ').last,
                    ),
                    onTap: () {
                      const scales = ExportSettings.scales;
                      final at = scales.indexOf(exportSettings.scale);
                      ref
                          .read(exportSettingsProvider.notifier)
                          .set(
                            exportSettings.copyWith(
                              scale: scales[(at + 1) % scales.length],
                            ),
                          );
                    },
                  ),
                ],
              ),

              SizedBox(height: StudioSpace.xxxl),

              // ---------------------------------------------------------------
              // ABOUT
              // ---------------------------------------------------------------
              const _Eyebrow('About MockMyApp'),
              _Group(
                children: [
                  const _VersionRow(),
                  const StudioDivider(),
                  // Said here rather than linked: there is no policy to read
                  // beyond this, because there is nothing to collect.
                  const StudioListRow(
                    icon: StudioIcons.privacy,
                    title: 'Privacy',
                    subtitle:
                        'No account, no analytics, no server. Your projects '
                        'stay on this device.',
                  ),
                  const StudioDivider(),
                  StudioListRow(
                    icon: StudioIcons.code,
                    title: 'Source code',
                    subtitle: kSourceCodeUrl.replaceFirst('https://', ''),
                    trailing: const _RowGlyph(StudioIcons.duplicate),
                    onTap: () => _copyLink(context, kSourceCodeUrl),
                  ),
                  const StudioDivider(),
                  StudioListRow(
                    icon: StudioIcons.terms,
                    title: 'Open Source Licenses',
                    subtitle:
                        'MockMyApp is free software under the MIT License',
                    trailing: const _RowGlyph(StudioIcons.chevronRight),
                    // Flutter's own licence page, which collects the notices
                    // every bundled package requires — google_fonts,
                    // flutter_svg, font_awesome_flutter and the rest. The
                    // attribution obligation is real; the implementation is
                    // one line.
                    onTap: () => showLicensePage(
                      context: context,
                      applicationName: 'MockMyApp',
                      applicationLegalese:
                          'Copyright (c) 2026 Md. Imam Hossain (New Age Devs)\n'
                          'Released under the MIT License.',
                    ),
                  ),
                ],
              ),

              SizedBox(height: StudioSpace.xxxl),

              // ---------------------------------------------------------------
              // MORE FROM NEW AGE DEVS
              // ---------------------------------------------------------------
              // The studio's other apps, kept to a list in Settings: nothing
              // about them shows anywhere else, nothing pops up, and a tap
              // copies a store link rather than opening one.
              const _Eyebrow('More from New Age Devs'),
              _Group(
                children: [
                  for (final (i, app) in kStudioApps.indexed) ...[
                    if (i > 0) const StudioDivider(),
                    StudioListRow(
                      key: ValueKey('studio-app-${app.name}'),
                      leading: StudioAppIcon(app),
                      title: app.name,
                      subtitle: app.tagline,
                      trailing: const _RowGlyph(StudioIcons.duplicate),
                      onTap: () => _copyLink(context, app.link),
                    ),
                  ],
                ],
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  StudioSpace.xs,
                  StudioSpace.m,
                  StudioSpace.xs,
                  0,
                ),
                child: Text(
                  'Apps and games by the studio that makes MockMyApp. A tap '
                  'copies the Google Play link.',
                  style: StudioText.caption(
                    context,
                  ).copyWith(color: s.textTertiary),
                ),
              ),

              SizedBox(height: StudioSpace.huge),

              Center(
                child: Text(
                  '© 2026 New Age Devs · MIT License',
                  style: StudioText.mono(
                    context,
                  ).copyWith(color: s.textTertiary),
                ),
              ),
              SizedBox(height: StudioSpace.xxxl),
            ],
          ),
        ),
      ),
    );
  }
}

/// A `textTertiary` UPPERCASE eyebrow sitting above a [_Group].
class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return StudioSectionHeader(
      label: label,
      padding: EdgeInsets.only(left: StudioSpace.xs, bottom: StudioSpace.m),
    );
  }
}

/// A settings group: a flat [StudioPanel] whose rows run edge to edge, clipped
/// so row hover washes respect the panel's `md` corners.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(StudioRadius.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

/// A trailing numeric / literal value, set in JetBrains Mono.
class _ValueReadout extends StatelessWidget {
  const _ValueReadout(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      style: StudioText.mono(
        context,
      ).copyWith(color: context.studio.textSecondary),
    );
  }
}

/// A quiet trailing affordance glyph (a chevron, a copy mark).
class _RowGlyph extends StatelessWidget {
  const _RowGlyph(this.icon);

  final StudioIconData icon;

  @override
  Widget build(BuildContext context) {
    return StudioIcon(icon, size: 14, color: context.studio.textTertiary);
  }
}
