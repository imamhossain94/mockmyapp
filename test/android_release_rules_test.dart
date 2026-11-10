import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The R8 rule that keeps ML Kit working in an Android release build.
///
/// Nothing under `flutter test` shrinks code, so the failure this guards
/// against cannot be reproduced here — it only showed on a phone, as
/// "translation fails", from a release APK. What can be checked is that the
/// rule is still where the Flutter Gradle plugin picks it up.
void main() {
  test('release builds keep ML Kit\'s component registrar constructors', () {
    final rules = File('android/app/proguard-rules.pro');
    expect(
      rules.existsSync(),
      isTrue,
      reason:
          'The Flutter Gradle plugin only adds android/app/proguard-rules.pro '
          'to a release build when the file exists.',
    );
    // Without `<init>()` R8's full mode strips the no-argument constructors
    // ML Kit's component discovery calls reflectively, and translation and
    // screen reading break in release while working in debug.
    final text = rules
        .readAsStringSync()
        .split('\n')
        .where((line) => !line.trimLeft().startsWith('#'))
        .join('\n');
    expect(
      RegExp(
        r'-keep class \* implements com\.google\.firebase\.components\.ComponentRegistrar\s*\{\s*<init>\(\);\s*\}',
      ).hasMatch(text),
      isTrue,
    );
  });
}
