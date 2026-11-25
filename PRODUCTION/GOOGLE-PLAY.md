# Google Play release guide

**Masjid Khalid Bin Al Waleed · November 25, 2026.** Follow sections 1–7 to prepare the app, section 8 for Open testing and section 9 for Production. Examples use Windows PowerShell.

[Phone screenshots](google-play/phone/) · [7-inch](google-play/tablet-7/) · [10-inch](google-play/tablet-10/) · [Icon](google-play/icon-512.png) · [Feature graphic](google-play/feature-graphic.png) · [Open testing](#8-open-testing-on-google-play) · [Production](#9-production-on-google-play)

See [registration privacy and release checks](REGISTRATION-PRIVACY.md) for the staff verification flow, individual erasure, retention decisions, and release evidence.

## 1. Confirm the release inputs

Run terminal commands from the repository root. Use Flutter 3.50.0 / Dart 3.14, Node.js 24 and the committed dependency lock files. The current app version is `1.0.0+1`. Check the store history first. Set the marketing version and the next unused, increasing build number in `pubspec.yaml` **before** building. Keep the tested binary, source revision and exact build configuration together.

The publisher must approve the legal entity, public support email and telephone, countries, free/paid status, intended ages, guardian consent process, retention and rights for the mosque logo, instructor name and published images. Verify whether attendance is used to infer religious beliefs. Confirm live database access, backup/log retention and a monitored registration-deletion process. These decisions affect both the public policy and the console answers.

## 2. Publish the Arabic legal and support pages

The app bundles `assets/legal/privacy-ar.txt` and `assets/legal/terms-ar.txt` for offline reading under Settings. The website generator uses the same copy. Review the texts with the operator. Registration records are removed when the parent course or activity is deleted. Hiding an activity or reaching its end date keeps its records. The operator must define and carry out a recurring removal schedule if promising a time limit.

1. Select an available Firebase Hosting site ID dedicated to these pages in project `masjid-khalid-app`, or use an existing dedicated site you control. Set `LEGAL_SITE_ID` in your shell to that ID. The production address is `https://SITE_ID.web.app` or a connected HTTPS custom domain.
2. Run `Copy-Item PRODUCTION/config/store-config.example.json store-config.json` on first setup. Enter real public values for `SUPPORT_MANAGER_NAME` (operator or named contact), `SUPPORT_MANAGER_PHONE`, `SUPPORT_EMAIL` and `PRIVACY_POLICY_URL` (full HTTPS address ending in `/privacy`). Save UTF-8 JSON. Only public values belong here. Archive the same file privately with each release so patches use identical build inputs.
3. Use the following commands. Run `hosting:sites:create` only for a new site. The dedicated Hosting target prevents a legal-site deployment from replacing an unrelated website. The predeploy hook regenerates the pages.

~~~powershell
$env:LEGAL_SITE_ID = Read-Host 'Dedicated Firebase Hosting site ID'
firebase hosting:sites:create "$env:LEGAL_SITE_ID" --project masjid-khalid-app
firebase target:apply hosting legal "$env:LEGAL_SITE_ID" --project masjid-khalid-app
node scripts/prepare-store-site.cjs
firebase hosting:channel:deploy legal-qa --config firebase.legal.json --project masjid-khalid-app
firebase deploy --only hosting:legal --config firebase.legal.json --project masjid-khalid-app
~~~

4. Open permanent paths `/privacy`, `/terms`, `/support` and `/delete` on a signed-out device. Check Arabic text, working email and phone links, public access, and that a request reaches the operator. Enter these permanent URLs in the store forms. Another static HTTPS host can serve `build/store-site` provided it maps those paths to their generated HTML pages.

## 3. Verify the app and its backend

~~~powershell
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

The last command writes disposable local emulator data. Before making the app available, verify the deployed Firestore/Storage rules, services, IAM, billing, Gmail SMTP secrets, event triggers and scheduled jobs. Test real registration, status on the staff-verified originating installation, denied notifications, staff image upload, recovery and account erasure with designated test data. Check that hidden entries and private registrations are protected, including existing media download links. Staff self-deletion requires the two new Functions. After checking the target project, deploy the worker first, then the public callable. Confirm the worker completes, removes Auth and recovery records, and leaves other accounts intact. Monitor failed events and outstanding `security_account_deletions` documents.

~~~powershell
firebase deploy --only functions:finishAccountDeletion --project masjid-khalid-app --force
firebase deploy --only functions:deleteOwnAdminAccount --project masjid-khalid-app
~~~

Both functions were deployed to the production Firebase project on November 25, 2026. Repeat these two commands only for a new environment or a reviewed backend update. The worker retries failed erasures. Firebase CLI requires acknowledgement for this retry policy on first deployment. The scoped `--force` option above applies only to that named worker.

If the rest of the backend has never been deployed, configure the production Firebase apps, Firestore database, Storage bucket, Auth email/password provider, operator accounts, push and verified SMTP first. Set `GMAIL_SENDER_EMAIL` and `GMAIL_APP_PASSWORD` using `firebase functions:secrets:set NAME --project masjid-khalid-app`. Compare production rules/functions with source before a full `firebase deploy --only "firestore:rules,storage,functions" --project masjid-khalid-app`. Existing installations may require the administrator course visibility migration. Run a registration through each visible program type on the actual backend. Never seed example accounts into production.

## 4. Enable OTA for the store binary

Install the official Shorebird CLI. From the project root on a fresh host run `git clone --depth 1 --branch stable https://github.com/shorebirdtech/shorebird.git C:/development/shorebird`. If already installed, reuse the installation. Use a short Windows install path so that SDK archive extraction succeeds. For this clone, run `$env:Path = "C:\development\shorebird\bin;$env:Path"` in this terminal. Then use the mosque's organization for sign-in. This repository includes the registered `shorebird.yaml` and its Flutter asset entry. Verify access to **Masjid Khalid Bin Al Waleed**, app ID `65702c27-6d22-4342-a9a8-8ccc469862bc`, on each build host. Default automatic updates check the stable track on startup and activate downloaded fixes on a later launch. [Shorebird setup](https://docs.shorebird.dev/getting-started/) · [Release and patch model](https://docs.shorebird.dev/code-push/)

~~~powershell
shorebird --version
shorebird login
shorebird doctor
shorebird apps list
shorebird flutter versions list
~~~

Install fastlane on the build/upload host and run `fastlane --version`. A maintained Ruby and `gem install fastlane` work on a configured host. macOS also supports `brew install fastlane`. Windows can build the Android AAB and transfer that exact file to a macOS/Linux upload host if Ruby/fastlane is unavailable. [fastlane setup](https://docs.fastlane.tools/getting-started/ios/setup/)

## 5. Create the Google Play app

1. Sign into the publisher's verified Play Console account. Confirm legal entity, identity, public developer contacts, agreements and developer verification/territory requirements in the account dashboard. Choose **All apps → Create app**. Set the name shown below, default language Arabic, App, and the confirmed price (suggested Free). Accept the declarations and create the app. If the package already has a record, open that record.
2. Android package/application ID is `com.masjidkhalidbinwaleed.masjid_khalid_app`. The first artifact establishes this identity. Enable Play App Signing. Distinguish the upload key kept by the publisher from the app signing key managed by Google. For an existing listing use its registered upload key. Verify the release signing certificate fingerprints in Play Console and add applicable SHA fingerprints to the matching Firebase Android app.
3. This project already has a verified JKS upload key. On a fresh build host, restore it from publisher-controlled storage outside the repository. Supply the ignored `android/key.properties` privately using the fields in `android/key.properties.example`. Preserve the exact passwords when populating Java properties. To check the public certificate locally, set `UPLOAD_KEYSTORE` to the path of the existing keystore and enter the store password at the prompt.

~~~powershell
keytool -list -v -storetype JKS -keystore "$env:UPLOAD_KEYSTORE" -alias upload
~~~

4. Install Android platform 36 or higher as required by the build, Android SDK Build Tools, Java compatible with Gradle and a compatible NDK. The local Flutter SDK and the generated Release manifest target API 36. Google requires API 36+ for ordinary new mobile submissions as of this check. Inspect the signed AAB because Shorebird builds with its own Flutter toolchain. [Target API requirements](https://support.google.com/googleplay/android-developer/answer/11926878) · [Play App Signing](https://developer.android.com/studio/publish/app-signing)

## 6. Build and inspect the release Android App Bundle

Use JDK 21 for this project's Gradle release build. JDK 17 can crash Android lint in dependency analysis with `java.util.List.removeLast()`. In PowerShell on this build host, set `$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21'`, run `flutter config --jdk-dir "$env:JAVA_HOME"` and verify the Gradle daemon JVM with `.\android\gradlew.bat -p android --version`. Use the actual JDK path on other hosts. Keep the Java/Kotlin compilation target at 17.

~~~powershell
.\scripts\store-release.ps1 -Platform android -Action Release
$pkg = 'com.masjidkhalidbinwaleed.masjid_khalid_app'
$aab = (Resolve-Path 'build/app/outputs/bundle/release/app-release.aab').Path
Get-FileHash -Algorithm SHA256 $aab
jarsigner -verify -verbose -certs $aab
keytool -printcert -jarfile $aab
~~~

Verify the exact output path in the Shorebird release log, the certificate fingerprint against the registered upload key, and the SHA-256 of the file transferred to the upload host. The helper builds with `shorebird release android --flutter-version=3.50.0 --dart-define-from-file=store-config.json`. Keep that AAB, source revision and config. The older `scripts/prepare-android-release.ps1` builds a conventional Flutter binary without OTA.

Install Google's bundletool and set `BUNDLETOOL_JAR` to its jar. Inspect the signed manifest, package ID, target SDK, exported components, actual requested permissions, version code and the bundle configuration. The app ships native Flutter and Firebase libraries. Validate 16 KB zip **and** ELF segment alignment, install on a 16 KB page-size Android device/emulator, and inspect the Play App Bundle Explorer warnings. Confirm edge-to-edge navigation, Android back behavior, tablets and orientation on Android 16+. [16 KB verification steps](https://developer.android.com/guide/practices/page-sizes)

~~~powershell
java -jar "$env:BUNDLETOOL_JAR" validate "--bundle=$aab"
java -jar "$env:BUNDLETOOL_JAR" dump manifest "--bundle=$aab" --module=base
java -jar "$env:BUNDLETOOL_JAR" dump config "--bundle=$aab" | Select-String PAGE_ALIGNMENT
adb shell getconf PAGE_SIZE
~~~

Expect 16384 on the 16 KB test device. In the Console, upload native debug symbols/mapping when generated, inspect pre-launch reports and fix crashes, ANRs, accessibility issues and policy errors before promotion.

## 7. Fill Store listing and App content

In Grow users → Store presence → Main store listing, select Arabic. Enter title (30 characters), short description (80), full description (4,000), confirmed public contact email and website `/support`. Add the app category and relevant tags, country distribution and store settings. In Policy and programs → App content complete Privacy Policy (`/privacy`), Data safety, App access, Ads declaration, IARC content rating and Target audience and content. Review any console questions about advertising ID, government affiliation, news, financial features, health and restricted permissions against the actual binary. Mosque announcements are an in-app feature; describe the publisher's editorial role accurately. No ads SDK, in-app purchases, health features or government services were identified in source. Verify the shipped app and third-party SDKs.

| Store field | Arabic value |
| --- | --- |
| Name | مسجد خالد بن الوليد |
| Short description | تابع أخبار المسجد ودوراته وأنشطته، وسجّل للمشاركة من هاتفك. |
| Category | Education (proposed) |
| Release notes | الإصدار الأول لمتابعة أخبار المسجد والتسجيل في الدورات والأنشطة. |

**Description to paste**

تابع أخبار مسجد خالد بن الوليد وبرامجه من مكان واحد. تصفّح الدورات والأنشطة والرحلات، واطّلع على الوظائف البيتية التي تنشرها الإدارة.

يمكنك إرسال طلب مشاركة باسم المشارك ورقم الهاتف، ثم متابعة حالته من «تسجيلاتي» على الجهاز الذي أرسلت منه الطلب. لا يحتاج الزائر إلى إنشاء حساب. ويمكنك اختيار تلقي إشعارات المسجد وتغيير تفضيلاتك من الإعدادات.

**Reviewer instructions to paste in English**

Public content opens immediately in Arabic. The bottom tabs, from right to left, are Home, News, Courses, Activities, Homework and Settings. In Courses or Activities open an available program, register a sample participant, then ask staff to verify the participant and device reference, then check My Registrations on the same installation. Notifications are optional. Find Privacy Policy and Terms under Settings. Staff sign in using the administrator link at the bottom of Settings. Signed-in staff can publish content, manage registrations and permanently delete their own account under Settings.

Place working review credentials in the store's private review field. Current admins can view all registration records and manage other admins. A new admin on a populated production database has the same access. Use an isolated review experience with representative data before giving reviewers credentials. Provide a reachable review contact and verify access throughout review, including after account deletion testing.


**Store assets.** In Graphics upload `google-play/icon-512.png` (512 × 512, 32-bit PNG, under 1 MB) and `google-play/feature-graphic.png` (1024 × 500, opaque 24-bit PNG). Add four 1080 × 1920 screenshots from `google-play/phone/`. Add the four corresponding portrait captures from `google-play/tablet-7/` (1296 × 2304) and `google-play/tablet-10/` (1620 × 2880) to their tablet groups. All capture groups use the running public Flutter UI. Check content rights, locale, lettering, navigation and absence of personal registration data against the store build before upload. The phone set satisfies the four-shot, 9:16 recommendation. No promo video is required for this mobile app. No Wear, TV, Auto or XR target is configured. [Google Play asset specifications](https://support.google.com/googleplay/android-developer/answer/9866151)

## Google Play Data safety

Play Console → Policy and programs → App content → Data safety. Answer **Yes** to collection. For supported flows data leaves the device over HTTPS/TLS. Confirm every production endpoint and select encrypted in transit accordingly. Registration, account and media records persist on the server. Mark these **not ephemeral**. Stored hashes used for rate limiting also persist. Assess ephemeral processing per type using all copies and log retention.

| Play data type | Collection, optionality and purpose |
| --- | --- |
| Personal info → Name, Phone number | Optional for browsing, required to submit a public registration. App functionality |
| Personal info → Email address, User IDs | Staff-only login alias, UID, username and optional recovery email. Account management, app functionality, security |
| Device or other IDs | Installation keys, FCM and OTA identifiers. Mark required if initialization or update checks send an identifier without an opt-out. Denying notifications only controls delivery. App functionality, security as applicable |
| App activity → App interactions, Other user-generated content | Registration, decision and program association, staff-authored text and the content users submit. Optional to browsing. App functionality |
| Photos and videos → Photos | Staff may select an image and publish it. Optional. App functionality |
| Personal info → Political or religious beliefs | Review named religious-course attendance with the operator. Select if the app records or infers religious belief. Treat identifiable attendance as sensitive |
| App info and performance → Diagnostics; other types per measured use | Release/patch number, installation result, device/software details and retained operational diagnostics. Verify actual SDK behavior and select Diagnostics or Other app performance data as applicable. App functionality and any verified analytics purpose |
| Messages → Emails, if applicable | Assess support correspondence and any user-authored messages actually collected in the service. Automated recovery mail uses the recipient address; recovery codes are authentication data |

For **shared**, examine Google Firebase, Gmail SMTP and Shorebird under actual contracts. A processor acting solely on the publisher's behalf can qualify for the service-provider exception. A public photo intentionally published by a staff member can qualify for user-initiated transfer. Verify the conditions separately. Independent third-party use must be declared. Document the decision for each row. Avoid blanket “no data shared” or independent security review certification without evidence. No sale of data or advertising integration was identified in source.

No public signup. Administrators create additional accounts in the app and use username/password authentication. Disclose this account creation path. Provide the public `/delete` URL. In-app self-deletion removes the staff role, login, recovery email/index and recovery tokens. Registration removal requests from visitors use the same public page and an operator-verified process. Confirm that real requests are monitored, fulfilled and acknowledged. Retain unrelated mosque publications and legally required records only under approved policy. Check logs, backups, optional Firebase TTL policies and appeal handling with the owner. [Play Data safety definitions](https://support.google.com/googleplay/android-developer/answer/10787469) · [Play User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311) · [Firebase Android disclosures](https://firebase.google.com/docs/android/play-data-disclosure)

## Permissions and review evidence

- Android source declares INTERNET and POST_NOTIFICATIONS. The locally generated Release manifest also contains ACCESS_NETWORK_STATE, WAKE_LOCK, FCM RECEIVE, legacy Google services read permission and a package-scoped receiver permission. Check the signed AAB in App Bundle Explorer. A component protected by a permission and a requested uses-permission are different manifest entries.
- Only staff pick a single photo through the system gallery. Broad photo/video, storage, location, microphone and camera access are unnecessary for these flows. iOS includes an Arabic photo-library explanation. Test limited-library access, cancellation, large files and denied access. Both picker calls disable requests for full metadata.
- Notifications are optional for browsing and registration. Test first launch, refusal, registration without push, permission changes, public-topic opt-out, foreground/background/cold-start delivery, token rotation and private registration messages. Use an actual iPhone with production APNs and an Android 13+ device. The general news switch controls the public topic; private decisions use a separate delivery path.
- Access rules require an admin claim and an active profile for privileged data. Validate the deployed rules, Storage cross-service IAM and access to previously issued download URLs for hidden media. Test release network behavior, live mail recovery and deletion with disposable data. Restrict Apple/Google review credentials to a data set suitable for reviewers.
- Determine intended audience and age bands with the operator. School homework and family registration make this material. Complete Apple's updated age-rating questionnaire and Play's Target audience, IARC content rating and Families requirements where applicable. Confirm guardian/consent practices, media rights and any jurisdiction-specific retention obligations before publishing either policy or form. [Apple review guidelines](https://developer.apple.com/app-store/review/guidelines/) · [Play Families](https://support.google.com/googleplay/android-developer/answer/9893335)



## 8. Open testing on Google Play

1. Check account eligibility. Personal developer accounts created after November 13, 2023 must generally run a **closed test with at least 12 testers continuously opted in for 14 days**, then apply for and obtain production access. On affected accounts open testing becomes available with production access. Internal or open testing does not replace the closed-test requirement. Read the account dashboard for any additional requirements. [Testing access rules](https://support.google.com/googleplay/android-developer/answer/14151465)
2. For the first release, establish the app and upload the signed AAB through Play Console (Internal testing, Closed testing if required, or Open testing if eligible). Complete Play App Signing, listing and app content. Use **Add from library** if this version code is already uploaded. If required to start with a draft, finish the dashboard tasks and submit it from Publishing overview.
3. Open Test and release → Testing → Open testing. Set countries, tester cap if desired, feedback email/URL and release notes. Choose Create new release, select the tested bundle, review and roll out to Open testing. Send the generated opt-in link to intended testers. Verify public install through that link and collect feedback.
4. For terminal delivery after the initial Console upload/record setup, enable the Google Play Android Developer API in Google Cloud. Give a service account app-specific release permissions in Play Console → Users and permissions. Set `PLAY_SERVICE_ACCOUNT_JSON` to the private JSON file path (outside the repository). Test the key. Use the exact accepted version code; `1` below matches the repository's initial `+1`.

~~~powershell
$env:PLAY_SERVICE_ACCOUNT_JSON = Read-Host 'Full path to your private Play service account JSON'
if (-not (Test-Path -LiteralPath $env:PLAY_SERVICE_ACCOUNT_JSON -PathType Leaf)) { throw 'Service account JSON file missing' }
~~~

~~~powershell
$pkg = 'com.masjidkhalidbinwaleed.masjid_khalid_app'
$code = '1'
fastlane run validate_play_store_json_key "json_key:$env:PLAY_SERVICE_ACCOUNT_JSON"
~~~

If uploading a **new, unused** version code directly to Open testing:

~~~powershell
fastlane supply --package_name "$pkg" --json_key "$env:PLAY_SERVICE_ACCOUNT_JSON" --aab "$aab" --track beta --release_status completed --skip_upload_metadata --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs
~~~

If the tested version is already in the internal track, promote the existing AAB instead. Use the exact closed-track identifier for a closed → open promotion. The default Play API open track is `beta`.

~~~powershell
fastlane supply --package_name "$pkg" --json_key "$env:PLAY_SERVICE_ACCOUNT_JSON" --track internal --track_promote_to beta --version_code "$code" --track_promote_release_status completed --skip_upload_aab --skip_upload_apk --skip_upload_metadata --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs
~~~

## 9. Production on Google Play

1. Confirm production access, resolved pre-launch reports, Data safety and signed release identity. Select countries/regions and verify the version code used in the open test. In Production → Create new release use Add from library or the tested release's Promote action. Copy the final Arabic release notes, check the app signing identity and review the release summary.
2. With the service account granted production rights, this terminal command promotes the **same tested code** to full production. Check for other active builds in the source track before promotion. The alternative Console action is Review release → Start rollout to Production.

~~~powershell
fastlane supply --package_name "$pkg" --json_key "$env:PLAY_SERVICE_ACCOUNT_JSON" --track beta --track_promote_to production --version_code "$code" --track_promote_release_status completed --skip_upload_aab --skip_upload_apk --skip_upload_metadata --skip_upload_images --skip_upload_screenshots --skip_upload_changelogs
~~~

3. Open Publishing overview, send any pending changes for review, and release approved changes if Managed publishing is enabled. Confirm the public listing in an enabled country, install from Play, and test cold launch, registration, rejection/acceptance notices, consent and deletion. Monitor Android vitals and policy inbox. An upload or a completed API edit is not a review decision. [fastlane supply](https://docs.fastlane.tools/actions/supply/) · [Play release workflow](https://support.google.com/googleplay/android-developer/answer/9859348)

## OTA fixes after the base release

Use the _same_ Shorebird app ID, target platform, build defines, dependencies and original base version. A normal `flutter build` binary cannot receive these patches. Android and iOS releases can have different patch numbers. Select the actual entry in `patches list`; the numbers below illustrate base `1.0.0+1`, patch `1`. Changing native plugins, permissions, Flutter engine, packaged assets, privacy behavior or introducing features goes through a new store build and review. Use OTA for compatible Dart fixes within the already reviewed functionality. Review the store's code update rules for the specific change.

~~~powershell
.\scripts\store-release.ps1 -Platform android -Action Patch -ReleaseVersion 1.0.0+1
shorebird preview --release-version 1.0.0+1 --track staging
shorebird patches list --release-version 1.0.0+1
shorebird patches info --release-version 1.0.0+1 --patch-number 1
shorebird patches promote --release-version 1.0.0+1 --patch-number 1
~~~

Preview on the intended platform/device. Launch twice, verify the intended fix, offline startup and registration/notifications before promoting. A store testing track controls access to a binary. Shorebird staging is selected by `preview --track staging`; ordinary store installations of the same base check stable, including installations from a store test track. Verify the listening track before distributing a patch. For a bad patch:

~~~powershell
shorebird patches rollback --release-version 1.0.0+1 --patch-number 1
~~~

Verify recovery on a subsequent check and restart. A rollback also needs connectivity. Record platform, release, patch, change, test result and rollback outcome. [Patch](https://docs.shorebird.dev/code-push/patch/) · [Tracks](https://docs.shorebird.dev/code-push/tracks/) · [Rollback](https://docs.shorebird.dev/code-push/rollback/)
