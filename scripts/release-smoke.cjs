'use strict';

// Read-only release preflight checks. Never talks to production Firebase.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const ROOT = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(ROOT, file), 'utf8');
const verify = (condition, description) => {
  assert.ok(condition, description);
  console.log(`PASS: ${description}`);
};
const gradle = read('android/app/build.gradle.kts');
const pubspec = read('pubspec.yaml');
const main = read('lib/main.dart');
const storage = read('storage.rules');
const pbx = read('ios/Runner.xcodeproj/project.pbxproj');
verify(!gradle.includes('signingConfigs.getByName("debug")'), 'no debug release signing');
verify(gradle.includes('signingConfigs.getByName("release")'), 'release signing configured');
verify(pubspec.includes('flutter_localizations:'), 'Flutter localization dependency');
verify(main.includes("Locale('ar')"), 'Arabic application locale');
verify(storage.includes('firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data.role'), 'Storage admin role check');
verify(pbx.includes('CODE_SIGN_ENTITLEMENTS = Runner/RunnerRelease.entitlements;'), 'iOS release push entitlements');
verify(fs.existsSync(path.join(ROOT, 'ios/Runner/RunnerRelease.entitlements')), 'iOS entitlements exist');
verify(fs.existsSync(path.join(ROOT, 'release-assets/play_icon_512.png')), 'Store icon exists');
console.log('PASS: local release smoke checks completed');
