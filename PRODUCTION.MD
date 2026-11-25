# Masjid Khalid release guides

Start with [SETUP.MD](SETUP.MD) for the complete sequence from checkout to public launch. Each store guide includes a build procedure, Arabic listing copy, privacy form answers, artwork, reviewer instructions, testing and production rollout.

| Store | English instructions | Artwork |
| --- | --- | --- |
| Apple App Store | [TestFlight and production](PRODUCTION/APP-STORE.md) | [iPhone and iPad](PRODUCTION/app-store/) |
| Google Play | [Open testing and production](PRODUCTION/GOOGLE-PLAY.md) | [Phone, tablets, icon and feature graphic](PRODUCTION/google-play/) |

Checked November 25, 2026. Publication requires publisher-owned accounts, verified support and policy information, signed builds and review by each store. Apple artwork uses the shared Flutter UI captured on Android and requires matching against the iOS release candidate. The Shorebird app is registered and its configuration is bundled in Flutter assets. Devices receive OTA updates after installation of a signed base release built with the Shorebird engine.

The [registration privacy release checklist](PRODUCTION/REGISTRATION-PRIVACY.md) covers staff verification, individual erasure and the publisher decisions needed before rollout. The revised Arabic privacy, terms and deletion pages are prepared locally. The hosted copies require a coordinated update.

## Release readiness

| Check | Result from this checkout |
| --- | --- |
| Flutter | Static analysis passed. The Flutter suite covers offline Arabic legal pages, verified registration display, staff confirmations and the existing installation credential. |
| Firebase | Functions lint, notification/deletion logic tests and the local Auth/Firestore/Functions integration test passed. The integration test verified removal of the admin's role, Auth account and recovery data while keeping a second account. Both deletion functions were deployed to the production project. Real mail delivery and device push remain publisher checks. |
| Graphics | The asset checker verified dimensions, PNG formats and file sizes for 20 listing images, two store icons and the Play feature graphic. Native launcher icon sizes were checked. Rights and final iOS visual comparison remain open. |
| Android | JDK 21 opened the existing upload keystore and unlocked its private-key entry. Gradle passed `:app:validateSigningRelease`. The inspected intermediate AAB targeted API 36, requested 16 KB page alignment and contained 12 shared libraries with ELF load segments aligned to at least 16 KB. Compare the upload certificate with Play Console and repeat bundle and device checks on the signed Shorebird artifact. |
| Apple | Source config has an Arabic locale, iPhone/iPad targets, photo-library purpose string and Release APNs entitlement. The Firebase plist matches the Runner Bundle ID and appears once in its Copy Bundle Resources phase. A signed Xcode archive, its privacy report, TestFlight and physical-device checks are pending. |
| Publication | Arabic public pages were rendered with isolated test contacts. The publisher still needs to approve the operational policy, publish the pages at permanent URLs, complete both console questionnaires and submit the signed builds. |
