# From checkout to public release

Use this checklist in order for the first release of **Masjid Khalid Bin Al Waleed**. It takes you through Google Play Open testing and Apple TestFlight before public distribution. The two store guides contain the exact Arabic listing text, privacy answers, graphics and review instructions.

| Destination | Detailed guide | Files to upload |
| --- | --- | --- |
| Google Play | [Google Play guide](PRODUCTION/GOOGLE-PLAY.md) | [Play artwork](PRODUCTION/google-play/), signed Android App Bundle |
| Apple App Store | [App Store guide](PRODUCTION/APP-STORE.md) | [Apple artwork](PRODUCTION/app-store/), signed iOS IPA |

Run commands from the repository root. Blocks marked PowerShell run on Windows. Bash blocks run on the Mac. Example version `1.0.0+1`, version code `1` and build `1` refer to the repository's initial version. Replace them if either store already has that build.

## 1. Gather the publisher information

- Verify the Google Play developer account and Apple Developer Program organization. Confirm that the people submitting can manage releases, agreements and privacy declarations.
- Collect the approved legal operator name, public support email/telephone, rights holder, website, countries, price, review contact and intended user ages. Decide how guardians register children, how long registrations remain after programs end and who handles deletion requests.
- Confirm permission to use the mosque logo, course instructor name and photographs in the promotional material. Compare the marketed features with the production app.
- Arrange an appropriate reviewer experience. Ordinary visitors have no account. Staff accounts can access personal registrations and manage other staff. Reviewers need working credentials and safe representative data. Enter credentials only in the private review fields.

## 2. Set up the build hosts

Install Flutter 3.50.0, Node.js 24, Firebase CLI, Git and fastlane. Android also needs Android SDK 36, compatible build tools/NDK and JDK 21 for the Gradle process. iOS requires macOS, Xcode 26 or newer, an iOS 26+ SDK, signing certificates and the publisher's team. Install a current Ruby and fastlane on the upload host. [Apple build requirements](https://developer.apple.com/news/upcoming-requirements/) · [Google target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878)

~~~text
npm install -g firebase-tools
gem install fastlane
flutter --version
flutter doctor -v
node --version
firebase --version
fastlane --version
firebase login
~~~

On this Windows host JDK 21 is installed at the path below. On another host substitute its actual installation directory. Check the **Daemon JVM** in Gradle output and the Java binary shown by Flutter. JDK 17 caused release lint to fail in a dependency when calling `List.removeLast()`. Keep release lint enabled. The Android Java/Kotlin bytecode target can stay at 17.

~~~powershell
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'
flutter config --jdk-dir "$env:JAVA_HOME"
.\android\gradlew.bat -p android --version
~~~

## 3. Set the release identity

1. Keep Android application ID `com.masjidkhalidbinwaleed.masjid_khalid_app` and Apple bundle ID `com.masjidkhalidbinwaleed.masjidKhalidApp`. Both map to Firebase project `masjid-khalid-app`.
2. Choose the version and next unused build number in `pubspec.yaml`. Record the Git revision and use the same revision on both build hosts.
3. Copy the [public config template](PRODUCTION/config/store-config.example.json) to `store-config.json` in the repository root. Set `SUPPORT_MANAGER_NAME`, `SUPPORT_MANAGER_PHONE`, `SUPPORT_EMAIL` and `PRIVACY_POLICY_URL`. The last field must be the final HTTPS URL ending in `/privacy`. Build defines are visible to users of the app. Keep signing and API credentials outside this file and outside Git.

## 4. Publish and verify the legal pages

Approve the [Arabic privacy policy](assets/legal/privacy-ar.txt) and [terms of use](assets/legal/terms-ar.txt). Choose a dedicated Hosting site ID. In PowerShell set `$env:LEGAL_SITE_ID` to that ID. On macOS set `export LEGAL_SITE_ID=...` and use `"$LEGAL_SITE_ID"` in place of the PowerShell variable below. Run the site creation command only once for a new site.

~~~powershell
$env:LEGAL_SITE_ID = Read-Host 'Dedicated Firebase Hosting site ID'
firebase hosting:sites:create "$env:LEGAL_SITE_ID" --project masjid-khalid-app
firebase target:apply hosting legal "$env:LEGAL_SITE_ID" --project masjid-khalid-app
node scripts/prepare-store-site.cjs
firebase hosting:channel:deploy legal-qa --config firebase.legal.json --project masjid-khalid-app
firebase deploy --only hosting:legal --config firebase.legal.json --project masjid-khalid-app
~~~

Open the live site's `/privacy`, `/terms`, `/support` and `/delete` in a signed-out browser. Verify the contact links and a real request to the support inbox. Use the permanent live URL in both stores.

## 5. Run the checks and prepare production Firebase

~~~text
flutter pub get --enforce-lockfile
npm ci --prefix functions
npm --prefix functions run lint
flutter analyze
flutter test
node scripts/release-smoke.cjs
node scripts/test-notifications-local.cjs
node scripts/test-deletion-local.cjs
node scripts/verify-store-assets.cjs
firebase emulators:exec --only auth,functions,firestore --project masjid-khalid-app "node scripts/test-firebase-local.cjs"
~~~

Verify the production database, bucket, access rules, Storage-to-Firestore IAM, administrator setup, SMTP secrets, FCM, event triggers and scheduled jobs. For a first backend deployment use section 3 of either store guide. For an existing installation deploy the deletion worker before the callable, then test a disposable account. Confirm erasure in Auth and Firestore.

~~~text
firebase deploy --only functions:finishAccountDeletion --project masjid-khalid-app --force
firebase deploy --only functions:deleteOwnAdminAccount --project masjid-khalid-app
~~~

Both functions were deployed to the production Firebase project on November 25, 2026. Repeat these two commands only for a new environment or a reviewed backend update. The worker retries failed erasures. Firebase CLI requires acknowledgement for this retry policy on first deployment. The scoped `--force` option above applies only to that named worker.

## 6. Connect to the registered OTA app

Install the [official Shorebird CLI](https://docs.shorebird.dev/getting-started/). On Windows use a short install path such as `C:/development/shorebird` and add its `bin` directory to the terminal PATH. Deep project paths can cause the Flutter SDK extraction to fail. The app is registered as **Masjid Khalid Bin Al Waleed**. Use the included `shorebird.yaml` on both hosts. Verify access to app ID `65702c27-6d22-4342-a9a8-8ccc469862bc`. The Windows release SDK 3.50.0 is installed.

~~~text
shorebird login
shorebird doctor
shorebird apps list
shorebird flutter versions list
~~~

Confirm Flutter 3.50.0 is available. Use `shorebird release` for **both** store binaries so they can receive compatible patches. Neither store automatically receives the files created by Shorebird.

## 7. Create the store records and signing identities

| Google Play Console | App Store Connect |
| --- | --- |
| All apps → Create app. Choose Arabic, App, the approved name and price. Enable Play App Signing and prepare the publisher's upload key. Configure `android/key.properties` from the example. Verify its certificate against Play. | Register the explicit App ID with Push Notifications. Apps → **+** → New App → iOS. Set Arabic, name, bundle ID, unique SKU and access. In Xcode select the team, App Store provisioning and production push entitlement. Add the supplied `ios/Runner/GoogleService-Info.plist` to Runner → Copy Bundle Resources once and configure APNs in Firebase. |
| Enable the Android Publisher API and give the release service account app-level testing/production rights. Set `PLAY_SERVICE_ACCOUNT_JSON` to its private JSON path. | Create an App Store Connect API key with appropriate access. Set `ASC_API_KEY_PATH` to the fastlane API-key JSON path. Verify the distribution identity and provisioning separately. |

See [Google signing and key generation](PRODUCTION/GOOGLE-PLAY.md#5-create-the-google-play-app) and [Apple signing and account setup](PRODUCTION/APP-STORE.md#5-create-the-apple-app-and-configure-signing).

## 8. Build once per platform

**Android, PowerShell**

~~~powershell
.\scripts\store-release.ps1 -Platform android -Action Release
$aab = (Resolve-Path 'build/app/outputs/bundle/release/app-release.aab').Path
$pkg = 'com.masjidkhalidbinwaleed.masjid_khalid_app'
$code = '1'
Get-FileHash -Algorithm SHA256 "$aab"
jarsigner -verify -verbose -certs "$aab"
~~~

Inspect the final manifest, upload certificate and 16 KB native-library compatibility as described in the Play guide.

**iOS, macOS Terminal**

~~~bash
xcodebuild -version
open ios/Runner.xcworkspace
node scripts/prepare-store-site.cjs
shorebird release ios --flutter-version=3.50.0 --dart-define-from-file=store-config.json
find build/ios/ipa -name '*.ipa' -print
export BUNDLE_ID=com.masjidkhalidbinwaleed.masjidKhalidApp
export VERSION=1.0.0
export BUILD=1
~~~

Set `IPA` to the exact file path printed by this release. Validate the archive in Xcode Organizer. Check signing, entitlements, SDK privacy manifests and archive privacy report. Keep the IPA, AAB, dSYMs, checksums and release config together.

In the same Mac terminal, load the two private file paths for TestFlight upload:

~~~bash
printf 'Private fastlane App Store Connect API-key JSON path: '
IFS= read -r ASC_API_KEY_PATH
export ASC_API_KEY_PATH
printf 'Exact signed IPA path printed by Shorebird: '
IFS= read -r IPA
export IPA
test -f "$ASC_API_KEY_PATH" && test -f "$IPA"
~~~

In the Windows release terminal, set the matching Play API credential:

~~~powershell
$env:PLAY_SERVICE_ACCOUNT_JSON = Read-Host 'Full path to your private Play service account JSON'
if (-not (Test-Path -LiteralPath $env:PLAY_SERVICE_ACCOUNT_JSON -PathType Leaf)) { throw 'Service account JSON file missing' }
~~~

## 9. Fill in the listings and declarations

1. Copy the Arabic name, descriptions, release notes and reviewer navigation from section 7 of each store guide. Add the verified public support details, countries, price, rights, age ratings and working reviewer credentials.
2. **Google Play:** upload the 512 px icon, 1024 × 500 feature graphic, and four screenshots per phone/tablet group. Complete App access, Ads, Target audience, IARC, applicable app-content declarations and Data safety. Include the permanent deletion page. [Play fields and Data safety worksheet](PRODUCTION/GOOGLE-PLAY.md#7-fill-store-listing-and-app-content)
3. **Apple:** compare the provided shared-UI artwork with the iPhone and iPad candidate. It was composed from Android captures at corresponding viewports. Capture Apple-native replacements where needed. Upload four images per device family and use the icon embedded in the signed build. Complete App Privacy nutrition labels, content rights, age ratings, export compliance, trader status where applicable, and Review Information. [Apple fields and privacy worksheet](PRODUCTION/APP-STORE.md#7-complete-the-app-store-listing-and-compliance)
4. Reconcile actual SDKs/processors, security logs, optional data, identifiers, named course participation, retention and account deletion with both forms. Save and publish the declarations in the consoles.

## 10. Distribute to testers

**Google Open testing.** Establish a new app's first bundle in Play Console. If a new personal account is subject to the closed-test gate, complete at least 12 continuously opted-in testers for 14 days and obtain production access before open testing. Choose Open testing → Create release → Add from library, select the exact AAB, add notes, countries and feedback contact, roll out and verify the opt-in link. For an already uploaded internal build the API equivalent is:

~~~powershell
fastlane supply --package_name "$pkg" --json_key "$env:PLAY_SERVICE_ACCOUNT_JSON" --track internal --track_promote_to beta --version_code "$code" --track_promote_release_status completed --skip_upload_aab --skip_upload_apk --skip_upload_metadata --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs
~~~

**Apple TestFlight.** Upload the exact signed IPA once:

~~~bash
fastlane pilot upload --api_key_path "$ASC_API_KEY_PATH" --app_identifier "$BUNDLE_ID" --ipa "$IPA" --skip_submission
~~~

Wait for processing and resolve export questions. In TestFlight add the build to an internal group. For external testers add an external group, What to Test, feedback email and Beta App Review details, then request external review and distribute after approval.

On both platforms confirm Arabic layout, offline startup, registration, optional push, delivery with the app closed, admin photo upload, recovery, deletion and public links. Use Play pre-launch reports, TestFlight feedback and physical devices. Correct any blocking issues before proceeding.

## 11. Submit those tested builds to production

**Google Play.** Confirm the approved open-track version code, countries and production access. Run the promotion below or choose the same release from the library in Production. Check Publishing overview, submit pending changes for review and publish approved changes if Managed publishing is enabled.

~~~powershell
fastlane supply --package_name "$pkg" --json_key "$env:PLAY_SERVICE_ACCOUNT_JSON" --track beta --track_promote_to production --version_code "$code" --track_promote_release_status completed --skip_upload_aab --skip_upload_apk --skip_upload_metadata --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs
~~~

**Apple App Store.** Select the TestFlight-tested build under the production version. After the metadata and privacy answers are complete, this command submits that build to App Review and requests automatic public release after approval:

~~~bash
fastlane deliver --api_key_path "$ASC_API_KEY_PATH" --app_identifier "$BUNDLE_ID" --app_version "$VERSION" --build_number "$BUILD" --skip_binary_upload --skip_metadata --skip_screenshots --submit_for_review --automatic_release --force
~~~

For manual timing, choose manual release in Connect and submit through Add for Review → Submit to App Review. After approval choose Release This Version. Respond to reviewer questions in the relevant console. Increment the build number if either store requires a new binary.

## 12. Confirm the public launch

Open each live listing from a supported country with a non-tester account. Install from the public store, check the version, complete a registration, receive a notification on a physical device and open the privacy and support links. Record both public listing URLs, build numbers and release date. Monitor Android vitals, Apple feedback and backend failures. For subsequent compatible Dart fixes use the staging, preview, promotion and rollback commands at the end of the relevant store guide.
