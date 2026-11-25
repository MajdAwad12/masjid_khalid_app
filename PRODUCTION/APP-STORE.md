# Apple App Store release guide

**Masjid Khalid Bin Al Waleed · November 25, 2026.** Follow sections 1–7 to prepare the app, section 8 for TestFlight and section 9 for public App Review. Build and sign on macOS.

[iPhone screenshots](app-store/iphone/) · [iPad screenshots](app-store/ipad-13/) · [App Store icon](app-store/icon-1024.png) · [TestFlight](#8-testflight-distribution) · [Production](#9-production-app-review-and-public-release)

## 1. Confirm the release inputs

Run terminal commands from the repository root. Use Flutter 3.50.0 / Dart 3.14, Node.js 24 and the committed dependency lock files. The current app version is `1.0.0+1`. Check the store history first. Set the marketing version and the next unused, increasing build number in `pubspec.yaml` **before** building. Keep the tested binary, source revision and exact build configuration together.

The publisher must approve the legal entity, public support email and telephone, countries, free/paid status, intended ages, guardian consent process, retention and rights for the mosque logo, instructor name and published images. Verify whether attendance is used to infer religious beliefs. Confirm live database access, backup/log retention and a monitored registration-deletion process. These decisions affect both the public policy and the console answers.

## 2. Publish the Arabic legal and support pages

The app bundles `assets/legal/privacy-ar.txt` and `assets/legal/terms-ar.txt` for offline reading under Settings. The website generator uses the same copy. Review the texts with the operator. Registration records are removed when the parent course or activity is deleted. Hiding an activity or reaching its end date keeps its records. The operator must define and carry out a recurring removal schedule if promising a time limit.

1. Select an available Firebase Hosting site ID dedicated to these pages in project `masjid-khalid-app`, or use an existing dedicated site you control. Set `LEGAL_SITE_ID` in your shell to that ID. The production address is `https://SITE_ID.web.app` or a connected HTTPS custom domain.
2. Run `cp PRODUCTION/config/store-config.example.json store-config.json` on first setup. Enter real public values for `SUPPORT_MANAGER_NAME` (operator or named contact), `SUPPORT_MANAGER_PHONE`, `SUPPORT_EMAIL` and `PRIVACY_POLICY_URL` (full HTTPS address ending in `/privacy`). Save UTF-8 JSON. Only public values belong here. Archive the same file privately with each release so patches use identical build inputs.
3. Use the following commands. Run `hosting:sites:create` only for a new site. The dedicated Hosting target prevents a legal-site deployment from replacing an unrelated website. The predeploy hook regenerates the pages.

~~~bash
printf 'Dedicated Firebase Hosting site ID: '
IFS= read -r LEGAL_SITE_ID
export LEGAL_SITE_ID
firebase hosting:sites:create "$LEGAL_SITE_ID" --project masjid-khalid-app
firebase target:apply hosting legal "$LEGAL_SITE_ID" --project masjid-khalid-app
node scripts/prepare-store-site.cjs
firebase hosting:channel:deploy legal-qa --config firebase.legal.json --project masjid-khalid-app
firebase deploy --only hosting:legal --config firebase.legal.json --project masjid-khalid-app
~~~

4. Open permanent paths `/privacy`, `/terms`, `/support` and `/delete` on a signed-out device. Check Arabic text, working email and phone links, public access, and that a request reaches the operator. Enter these permanent URLs in the store forms. Another static HTTPS host can serve `build/store-site` provided it maps those paths to their generated HTML pages.

## 3. Verify the app and its backend

~~~bash
flutter doctor -v
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

The last command writes disposable local emulator data. Before making the app available, verify the deployed Firestore/Storage rules, services, IAM, billing, Gmail SMTP secrets, event triggers and scheduled jobs. Test real registration, status on the originating device, denied notifications, staff image upload, recovery and account erasure with designated test data. Check that hidden entries and private registrations are protected, including existing media download links. Staff self-deletion requires the two new Functions. After checking the target project, deploy the worker first, then the public callable. Confirm the worker completes, removes Auth and recovery records, and leaves other accounts intact. Monitor failed events and outstanding `security_account_deletions` documents.

~~~bash
firebase deploy --only functions:finishAccountDeletion --project masjid-khalid-app --force
firebase deploy --only functions:deleteOwnAdminAccount --project masjid-khalid-app
~~~

Both functions were deployed to the production Firebase project on November 25, 2026. Repeat these two commands only for a new environment or a reviewed backend update. The worker retries failed erasures. Firebase CLI requires acknowledgement for this retry policy on first deployment. The scoped `--force` option above applies only to that named worker.

If the rest of the backend has never been deployed, configure the production Firebase apps, Firestore database, Storage bucket, Auth email/password provider, operator accounts, push and verified SMTP first. Set `GMAIL_SENDER_EMAIL` and `GMAIL_APP_PASSWORD` using `firebase functions:secrets:set NAME --project masjid-khalid-app`. Compare production rules/functions with source before a full `firebase deploy --only "firestore:rules,storage,functions" --project masjid-khalid-app`. Existing installations may require the administrator course visibility migration. Run a registration through each visible program type on the actual backend. Never seed example accounts into production.

## 4. Enable OTA for the store binary

Install the official Shorebird CLI. From the project root on a fresh host run `git clone --depth 1 --branch stable https://github.com/shorebirdtech/shorebird.git build/tools/shorebird`. If already installed, reuse the installation. For a project-local clone, run `export PATH="$PWD/build/tools/shorebird/bin:$PATH"` in this terminal. Then use the mosque's organization for sign-in. This repository includes the registered `shorebird.yaml` and its Flutter asset entry. Verify access to **Masjid Khalid Bin Al Waleed**, app ID `65702c27-6d22-4342-a9a8-8ccc469862bc`, on each build host. Default automatic updates check the stable track on startup and activate downloaded fixes on a later launch. [Shorebird setup](https://docs.shorebird.dev/getting-started/) · [Release and patch model](https://docs.shorebird.dev/code-push/)

~~~bash
shorebird --version
shorebird login
shorebird doctor
shorebird apps list
shorebird flutter versions list
~~~

Install fastlane on the build/upload host and run `fastlane --version`. A maintained Ruby and `gem install fastlane` work on a configured host. macOS also supports `brew install fastlane`. Windows can build the Android AAB and transfer that exact file to a macOS/Linux upload host if Ruby/fastlane is unavailable. [fastlane setup](https://docs.fastlane.tools/getting-started/ios/setup/)

## 5. Create the Apple app and configure signing

1. On a Mac install Xcode 26 or later with an iOS 26 or later SDK and command-line tools. Accept the Xcode license, complete first launch and enroll the correct legal entity in the Apple Developer Program. The account holder accepts pending agreements. Configure EU trader status and business/contact verification where applicable. [Apple SDK deadlines](https://developer.apple.com/news/upcoming-requirements/) · [App Store Connect workflow](https://developer.apple.com/help/app-store-connect/get-started/app-store-connect-workflow/)
2. In Certificates, Identifiers & Profiles, register or select the explicit App ID `com.masjidkhalidbinwaleed.masjidKhalidApp`. Enable Push Notifications. Prepare Apple Distribution signing and an App Store Connect distribution provisioning profile, or use automatic signing. The Runner target supports iPhone **and iPad**, deployment target iOS 15.
3. In App Store Connect → Apps → **+** → New App, select iOS, primary language Arabic, the exact registered bundle ID, a unique internal SKU (suggested `MK-IOS-001`), the Arabic name below, and appropriate user access. Use an existing app record for this bundle ID if it already exists. [Create an app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
4. Run the commands below. In Xcode → Runner target → Signing & Capabilities, select the publisher team on all configurations. Verify Push Notifications, Background Modes → Remote notifications, Release entitlements `aps-environment=production` and the signing profile. Verify the Firebase iOS app and bundle ID against `lib/firebase_options.dart`. The registered native config is already present at `ios/Runner/GoogleService-Info.plist`. In Xcode choose File → Add Files to Runner, select this existing file, choose the Runner target, and verify it appears once in Build Phases → Copy Bundle Resources. Skip Add Files if the resource is already included. The project uses explicit resource membership. In Firebase Cloud Messaging configure the correct Apple Team, key ID and APNs authentication key for production.
5. Install a current fastlane and create an App Store Connect team API key with roles for the actions below, or use an appropriately authorized Apple ID in Xcode. Store the key outside the repository. Set `ASC_API_KEY_PATH` to the local fastlane API key JSON containing `key_id`, `issuer_id` and the private key contents in `key`. This key authenticates uploads. The distribution identity and provisioning profile sign the binary. [fastlane API keys](https://docs.fastlane.tools/app-store-connect-api/)

~~~bash
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
flutter doctor -v
flutter pub get
open ios/Runner.xcworkspace
~~~

## 6. Build the release IPA on macOS

Run `shorebird release` once for this iOS base. It builds the signed archive, exports the IPA and registers the patch baseline. The shared helper `pwsh -File scripts/store-release.ps1 -Platform ios -Action Release` runs the same release command after checking the public config. Native macOS terminal equivalent:

~~~bash
node scripts/prepare-store-site.cjs
shorebird release ios --flutter-version=3.50.0 --dart-define-from-file=store-config.json
find build/ios/ipa -name '*.ipa' -print
~~~

Read the artifact path printed by **this release**. Set `IPA` to that exact file. Save the archive, dSYMs, source revision, release identifier and config. In Xcode Organizer validate the archive and generate its privacy report. Check embedded SDK signatures, required-reason API declarations, included SDK privacy manifests, icons and release entitlements. Inspect on the Mac:

~~~bash
printf 'Private fastlane App Store Connect API-key JSON path: '
IFS= read -r ASC_API_KEY_PATH
export ASC_API_KEY_PATH
printf 'Exact signed IPA path printed by Shorebird: '
IFS= read -r IPA
export IPA
test -f "$ASC_API_KEY_PATH" && test -f "$IPA"
~~~

~~~bash
export BUNDLE_ID=com.masjidkhalidbinwaleed.masjidKhalidApp
export VERSION=1.0.0
export BUILD=1
codesign -d --entitlements :- build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
find build/ios/archive/Runner.xcarchive -name PrivacyInfo.xcprivacy -print
/usr/libexec/PlistBuddy -c "Print :BUNDLE_ID" build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app/GoogleService-Info.plist
shasum -a 256 "$IPA"
~~~

Use the values actually built for `VERSION` and `BUILD`. Test on physical iPhone and iPad: cold launch, RTL, rotation/layout, declined notifications, background APNs delivery, limited photo library, admin recovery and deletion. In-app support/privacy links must work in the signed build.

## 7. Complete the App Store listing and compliance

Choose the iOS version in App Store Connect → Distribution. Set primary language Arabic, name/subtitle (30 characters each), full description (up to 4,000), keywords (100 UTF-8 bytes), support URL `/support`, privacy URL `/privacy`, optional marketing URL, confirmed copyright year and rights holder, primary category, price and territories. Use Apple's standard EULA unless the publisher has an approved custom license. The app's Arabic terms are available in Settings and at `/terms`.

| Store field | Arabic value |
| --- | --- |
| Name | مسجد خالد بن الوليد |
| Subtitle | أخبار المسجد ودوراته وأنشطته |
| Keywords | مسجد,دورات,أنشطة,تعليم,تسجيل,قرآن,واجبات |
| Category | Education (proposed) |
| Release notes | الإصدار الأول لمتابعة أخبار المسجد والتسجيل في الدورات والأنشطة. |

**Description to paste**

تابع أخبار مسجد خالد بن الوليد وبرامجه من مكان واحد. تصفّح الدورات والأنشطة والرحلات، واطّلع على الوظائف البيتية التي تنشرها الإدارة.

يمكنك إرسال طلب مشاركة باسم المشارك ورقم الهاتف، ثم متابعة حالته من «تسجيلاتي» على الجهاز الذي أرسلت منه الطلب. لا يحتاج الزائر إلى إنشاء حساب. ويمكنك اختيار تلقي إشعارات المسجد وتغيير تفضيلاتك من الإعدادات.

**Reviewer instructions to paste in English**

Public content opens immediately in Arabic. The bottom tabs, from right to left, are Home, News, Courses, Activities, Homework and Settings. In Courses or Activities open an available program, register a sample participant, then check My Registrations on the same installation. Notifications are optional. Find Privacy Policy and Terms under Settings. Staff sign in using the administrator link at the bottom of Settings. Signed-in staff can publish content, manage registrations and permanently delete their own account under Settings.

Place working review credentials in the store's private review field. Current admins can view all registration records and manage other admins. A new admin on a populated production database has the same access. Use an isolated review experience with representative data before giving reviewers credentials. Provide a reachable review contact and verify access throughout review, including after account deletion testing.


**Screenshots and app icon.** Upload four PNGs from `app-store/iphone/` (1179 × 2556, iPhone with Dynamic Island) and four from `app-store/ipad-13/` (2064 × 2752, 13-inch iPad). The 1024 × 1024 opaque icon in `app-store/icon-1024.png` is a reference copy of the icon delivered in the Xcode asset catalog. Video previews are optional. Apple accepts 1–10 screenshots per required size. If Connect asks for a different display slot, choose the matching size in Media Manager or capture that specific device. [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/) · [Upload artwork](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)

**Artwork provenance.** The supplied Arabic compositions use actual public Flutter screens rendered on Android at phone/tablet viewports with OS chrome removed. Compare every screen to the iOS candidate, including layout, visible content and rights. For native replacement captures use an iPhone 15 Pro simulator (1179 × 2556) and a 13-inch iPad Pro M4 simulator (2064 × 2752), or equivalent accepted sizes. Boot an identified device, open the same source version, navigate to each public screen with safe review data, then capture. Repeat using `ipad-13` and its UDID. A simulator build is used only for capture; the signed IPA is used for distribution.

~~~bash
xcrun simctl list devices available
xcrun simctl boot "$SIMULATOR_ID"
open -a Simulator
flutter run -d "$SIMULATOR_ID" --dart-define-from-file=store-config.json
# In a second terminal after navigating to the named screen:
sh scripts/capture-apple-screen.sh iphone 01-home
sh scripts/capture-apple-screen.sh iphone 02-courses
sh scripts/capture-apple-screen.sh iphone 03-activities
sh scripts/capture-apple-screen.sh iphone 04-homework
~~~

Set and export `SIMULATOR_ID` first. Navigate between each capture. Inspect `build/apple-captures`, pixel size, orientation and transparency before upload. Switch to a native capture if the supplied design differs from iOS. Fill App Review contact and sign-in details, content rights, age questionnaire, content controls, advertising/tracking responses and export compliance according to the actual archive and territories. TLS and authentication are present. Review the bundled cryptography before making any export-exemption declaration. Confirm availability, price, business/trader disclosures and agreements. [Review guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Export compliance](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/)

## Apple App Privacy (nutrition labels)

In App Store Connect → Apps → this app → App Privacy, enter the public privacy URL, select **Yes, we collect data**, add each applicable type, select purposes, answer linkage and tracking, then publish. The purpose of participant and staff data is **App Functionality**, including authentication, service messages, security and support. The source has no ad network, IDFA use, cross-company advertising linkage or tracking SDK. Select **No tracking** if the shipped build and processors confirm this.

| Apple data type | What leaves the device | Proposed linkage and purpose |
| --- | --- | --- |
| Contact Info → Name, Phone Number | Participant name and phone, also supplied on behalf of family members | Linked through the registration, App Functionality |
| Contact Info → Email Address | Staff recovery email, internal account login alias, support email if retained | Linked, App Functionality |
| Identifiers → User ID | Staff Firebase UID and username, author/decision IDs | Linked, App Functionality |
| Identifiers → Device ID | Per-install registration key/hash, Firebase installation/FCM and APNs identifiers. The registration can associate identifiers with a named participant. Shorebird also uses a per-install ID | Select linked where any such association exists, App Functionality |
| User Content → Photos or Videos, Other User Content | Admin-selected images and authored news, activities, homework and course details. Image selection is optional | Linked through staff actions where attributable, App Functionality |
| Usage Data → Product Interaction | Program selected, registration event, acceptance status and participation history | Linked to the named registration, App Functionality |
| Sensitive Info | Enrollment in a named religious course may reveal religious affiliation. No explicit belief question is asked | Include when the organization records or infers beliefs from attendance. Confirm use with the operator before filing |
| Diagnostics → Other Diagnostic Data and other technical data | SDK/device/version metadata, update-check and install outcomes, server/security logs and IP-derived abuse counters | App Functionality. Add Analytics if the operator uses these for analytics. Determine linkage for retained logs from actual identifiers. Evaluate IP by use, including Coarse Location if used to derive location |
| User Content → Customer Support | Users can send the operator an identifiable support or deletion request | Include when applicable to the support workflow and Apple's optional-disclosure conditions |

No payment, precise location, contacts address book, microphone, camera capture, health or advertising features were identified. Inspect optional SDK integrations, delivery metrics export, crash/analytics collection and the final Xcode privacy report before saving. Own use of required-reason APIs and SDK manifests are archive checks. The App Privacy answers are a separate submission. [Apple definitions](https://developer.apple.com/app-store/app-privacy-details/) · [Firebase Apple disclosures](https://firebase.google.com/docs/ios/app-store-data-collection) · [SDK requirements](https://developer.apple.com/support/third-party-SDK-requirements/) · [Shorebird data](https://docs.shorebird.dev/system/what-shorebird-collects/)

## Permissions and review evidence

- Only staff pick a single photo through the system gallery. Broad photo/video, storage, location, microphone and camera access are unnecessary for these flows. iOS includes an Arabic photo-library explanation. Test limited-library access, cancellation, large files and denied access. Both picker calls disable requests for full metadata.
- Notifications are optional for browsing and registration. Test first launch, refusal, registration without push, permission changes, public-topic opt-out, foreground/background/cold-start delivery, token rotation and private registration messages. Use an actual iPhone with production APNs and an Android 13+ device. The general news switch controls the public topic; private decisions use a separate delivery path.
- Access rules require an admin claim and an active profile for privileged data. Validate the deployed rules, Storage cross-service IAM and access to previously issued download URLs for hidden media. Test release network behavior, live mail recovery and deletion with disposable data. Restrict Apple/Google review credentials to a data set suitable for reviewers.
- Determine intended audience and age bands with the operator. School homework and family registration make this material. Complete Apple's updated age-rating questionnaire and Play's Target audience, IARC content rating and Families requirements where applicable. Confirm guardian/consent practices, media rights and any jurisdiction-specific retention obligations before publishing either policy or form. [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Play Families](https://support.google.com/googleplay/android-developer/answer/9893335)



## 8. TestFlight distribution

1. Upload the exact store IPA **once**. Export `ASC_API_KEY_PATH` and `IPA` in this terminal before running:

~~~bash
fastlane pilot upload --api_key_path "$ASC_API_KEY_PATH" --app_identifier "$BUNDLE_ID" --ipa "$IPA" --skip_submission
~~~

2. Wait for processing. Resolve Invalid Binary, missing compliance or export questions. Open TestFlight → Internal Testing, create a group, add permitted App Store Connect team members, select the processed build and install via TestFlight.
3. For external users, create an external group, enter What to Test, feedback email, beta description and working Beta App Review credentials. Add that same build, submit for Beta App Review when requested, then invite testers or enable its public link after approval. Confirm push and privacy behavior on the actual TestFlight build. Beta approval and App Store approval are separate decisions. [TestFlight](https://developer.apple.com/testflight/) · [pilot](https://docs.fastlane.tools/actions/pilot/)

## 9. Production App Review and public release

1. Open the Distribution version, complete the listing, finish App Privacy and select the **same processed `VERSION` / `BUILD`** tested above. Confirm production backend, countries, rights and reviewer access. Record the tested archive checksum.
2. In Connect use Add for Review → Submit to App Review. Alternatively, after the metadata is saved, this command submits that specific build for production review with automatic release after approval:

~~~bash
fastlane deliver --api_key_path "$ASC_API_KEY_PATH" --app_identifier "$BUNDLE_ID" --app_version "$VERSION" --build_number "$BUILD" --skip_binary_upload --skip_metadata --skip_screenshots --submit_for_review --automatic_release --force
~~~

3. For a controlled launch, choose manual release in Connect, submit in the UI and click **Release This Version** after approval. Monitor review messages, fix rejected items, and increment the build number if another binary is required. Verify the public listing, Apple download, first launch, registering, optional push and privacy links in the intended storefront. [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/) · [deliver](https://docs.fastlane.tools/actions/deliver/)

## OTA fixes after the base release

Use the _same_ Shorebird app ID, target platform, build defines, dependencies and original base version. A normal `flutter build` binary cannot receive these patches. Android and iOS releases can have different patch numbers. Select the actual entry in `patches list`; the numbers below illustrate base `1.0.0+1`, patch `1`. Changing native plugins, permissions, Flutter engine, packaged assets, privacy behavior or introducing features goes through a new store build and review. Use OTA for compatible Dart fixes within the already reviewed functionality. Review the store's code update rules for the specific change.

~~~bash
shorebird patch ios --release-version=1.0.0+1 --track=staging --dart-define-from-file=store-config.json
shorebird preview --release-version 1.0.0+1 --track staging
shorebird patches list --release-version 1.0.0+1
shorebird patches info --release-version 1.0.0+1 --patch-number 1
shorebird patches promote --release-version 1.0.0+1 --patch-number 1
~~~

Preview on the intended platform/device. Launch twice, verify the intended fix, offline startup and registration/notifications before promoting. A store testing track controls access to a binary. Shorebird staging is selected by `preview --track staging`; ordinary store installations of the same base check stable, including installations from a store test track. Verify the listening track before distributing a patch. For a bad patch:

~~~bash
shorebird patches rollback --release-version 1.0.0+1 --patch-number 1
~~~

Verify recovery on a subsequent check and restart. A rollback also needs connectivity. Record platform, release, patch, change, test result and rollback outcome. [Patch](https://docs.shorebird.dev/code-push/patch/) · [Tracks](https://docs.shorebird.dev/code-push/tracks/) · [Rollback](https://docs.shorebird.dev/code-push/rollback/)
