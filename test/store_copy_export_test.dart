// Store copy out of the app: deliver's and supply's metadata files at the
// paths and locale codes fastlane reads, inside the fastlane ZIP, and the
// plain text "Copy all" puts on the clipboard.

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockmyapp/data/repositories/graphics_archive.dart';
import 'package:mockmyapp/domain/models/store_copy.dart';
import 'package:mockmyapp/domain/store_copy/copy_export.dart';
import 'package:mockmyapp/domain/store_copy/store_limits.dart';

final _copy = StoreCopy.empty
    .withFields(CopyStore.appStore, 'en-US', {
      'name': 'Wayfare: Trip Planner',
      'subtitle': 'Bookings, maps and tickets',
      'keywords': 'itinerary,travel,vacation',
      'promotionalText': 'Your whole trip in one place.',
      'description': 'Plan trips.\n\n• Offline maps',
      'whatsNew': 'In this version:\n• Shared trips',
    })
    .withFields(CopyStore.appStore, 'ja-JP', {'name': 'Wayfare: 旅行プランナー'})
    .withFields(CopyStore.appStore, 'nb-NO', {'subtitle': 'Alle reiser samlet'})
    .withFields(CopyStore.macAppStore, 'en-US', {'name': 'Wayfare for Mac'})
    .withFields(CopyStore.playStore, 'en-US', {
      'title': 'Wayfare: Trip Planner',
      'shortDescription': 'Every booking, map and ticket in one place.',
      'fullDescription': 'Plan trips.',
      'releaseNotes': 'Shared trips.',
      'altText': 'Your trips at a glance',
    })
    .withFields(CopyStore.playStore, 'zh-Hans', {'title': 'Wayfare 旅行'})
    .withFields(CopyStore.playStore, 'he-IL', {'title': 'Wayfare'})
    .withFields(CopyStore.galaxyStore, 'en-US', {'title': 'Wayfare'});

void main() {
  group('the fastlane layout', () {
    final files = {for (final f in fastlaneTextFiles(_copy)) f.path: f.text};

    test('puts App Store copy where deliver reads it', () {
      expect(
        files['fastlane/metadata/en-US/name.txt'],
        'Wayfare: Trip Planner',
      );
      expect(
        files['fastlane/metadata/en-US/subtitle.txt'],
        'Bookings, maps and tickets',
      );
      expect(
        files['fastlane/metadata/en-US/keywords.txt'],
        'itinerary,travel,vacation',
      );
      expect(
        files['fastlane/metadata/en-US/promotional_text.txt'],
        'Your whole trip in one place.',
      );
      expect(
        files['fastlane/metadata/en-US/description.txt'],
        'Plan trips.\n\n• Offline maps',
      );
      expect(
        files['fastlane/metadata/en-US/release_notes.txt'],
        'In this version:\n• Shared trips',
      );
    });

    test('names Apple locales the way App Store Connect does', () {
      expect(files['fastlane/metadata/ja/name.txt'], 'Wayfare: 旅行プランナー');
      expect(files['fastlane/metadata/no/subtitle.txt'], 'Alle reiser samlet');
      expect(files.keys.where((p) => p.contains('/ja-JP/')), isEmpty);
    });

    test('keeps Mac App Store copy beside the iPhone copy, not over it', () {
      expect(
        files['fastlane/metadata-macos/en-US/name.txt'],
        'Wayfare for Mac',
      );
      expect(
        files['fastlane/metadata/en-US/name.txt'],
        'Wayfare: Trip Planner',
      );
    });

    test('puts Play copy where supply reads it', () {
      expect(
        files['fastlane/metadata/android/en-US/title.txt'],
        'Wayfare: Trip Planner',
      );
      expect(
        files['fastlane/metadata/android/en-US/short_description.txt'],
        'Every booking, map and ticket in one place.',
      );
      expect(
        files['fastlane/metadata/android/en-US/full_description.txt'],
        'Plan trips.',
      );
      expect(
        files['fastlane/metadata/android/en-US/changelogs/default.txt'],
        'Shared trips.',
      );
    });

    test('names Play locales the way the Play Console does', () {
      expect(files['fastlane/metadata/android/zh-CN/title.txt'], 'Wayfare 旅行');
      expect(files['fastlane/metadata/android/iw-IL/title.txt'], 'Wayfare');
    });

    test('leaves out what fastlane does not upload', () {
      // Alt text has no metadata file; Samsung has no fastlane layout.
      expect(files.values, isNot(contains('Your trips at a glance')));
      expect(files.keys.where((p) => p.contains('galaxy')), isEmpty);
      expect(files.length, 15);
    });

    test('writes the text exactly, with no newline added', () {
      final zip = GraphicsArchive.bundleFiles([
        for (final f in fastlaneTextFiles(_copy))
          (path: f.path, bytes: utf8.encode(f.text)),
      ]);
      final archive = ZipDecoder().decodeBytes(zip);
      final keywords = archive.findFile(
        'fastlane/metadata/en-US/keywords.txt',
      )!;
      expect(
        utf8.decode(keywords.content as List<int>),
        'itinerary,travel,vacation',
      );
      final japanese = archive.findFile('fastlane/metadata/ja/name.txt')!;
      expect(utf8.decode(japanese.content as List<int>), 'Wayfare: 旅行プランナー');
    });

    test('is offered only when there is copy it carries', () {
      expect(hasFastlaneText(_copy), isTrue);
      expect(hasFastlaneText(StoreCopy.empty), isFalse);
      expect(
        hasFastlaneText(
          StoreCopy.empty.withText(
            CopyStore.galaxyStore,
            'en-US',
            'title',
            'X',
          ),
        ),
        isFalse,
      );
    });

    test('says which uploads will be refused for being too long', () {
      final long = _copy.withText(
        CopyStore.appStore,
        'en-US',
        'subtitle',
        'Every booking, map and ticket together',
      );
      final notes = fastlaneOverLimitNotes(long);
      expect(notes, hasLength(1));
      expect(notes.single, contains('App Store · English (US) · Subtitle'));
      expect(notes.single, contains('deliver will refuse it'));
      expect(fastlaneOverLimitNotes(_copy), isEmpty);
    });
  });

  test('"Copy all" lays out a store\'s copy as labelled text', () {
    final text = copyAllText(
      CopyStore.playStore,
      'en-US',
      _copy.fieldsOf(CopyStore.playStore, 'en-US'),
    );
    expect(
      text,
      'Google Play · English (US)\n\n'
      'App name\nWayfare: Trip Planner\n\n'
      'Short description\nEvery booking, map and ticket in one place.\n\n'
      'Full description\nPlan trips.\n\n'
      'Release notes\nShared trips.\n\n'
      'Screenshot alt text\nYour trips at a glance',
    );
  });
}
