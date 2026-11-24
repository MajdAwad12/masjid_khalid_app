# Stage 4 — آخر الأخبار: optional expiry and automatic cleanup

Changes:
- `lib/screens/announcements_page.dart`: optional expiration date + time, displays old announcements normally when no expiry is set. Public view hides an expired item (periodic 10-second display refresh). Manager can edit expiration / remove it.
- `firestore.rules`: checks that any expiresAt value is a Firestore timestamp or null. Admin-only write permission is unchanged.
- `functions/index.js`: two new functions:
  * `deleteExpiredAnnouncements` — scheduled every 5 minutes; removes expired Firestore documents, re-checking the expiration timestamp transactionally before deletion.
  * `cleanupDeletedAnnouncementImage` — Firestore on-delete event in `me-west1`; deletes the document's own `imagePath` from Firebase Storage with retries for transient failures, including for manual deletions.

Existing announcements missing expiresAt remain permanent; explicit `expiresAt: null` is also permanent.

Install from project root (no files should be deleted first):
  Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\masjid_news_expiration_patch.zip" -DestinationPath . -Force
  dart format lib
  flutter analyze
  flutter test
  cd functions
  npm run lint
  cd ..

DO NOT DEPLOY until those checks pass.
When ready, deploy from project root:
  firebase deploy --project masjid-khalid-app --only firestore:rules
  firebase deploy --project masjid-khalid-app --only functions:deleteExpiredAnnouncements,functions:cleanupDeletedAnnouncementImage

NOTE: Deployment of a scheduled function provisions a Cloud Scheduler job and may incur usage charges. Firebase billing must remain enabled. The function that deletes Storage images runs in me-west1 matching the Firestore database, and requires Eventarc/Storage IAM permissions for the deployed service account.

Test after deployment: publish temporary news WITH an image, set expiration 3-4 minutes ahead, then wait until it is expired, confirm public listing hides it, and after a scheduler run confirm its Firestore document and image object are gone. Also test that a permanent news item remains visible. Do not use an important production item for this test.

Caveat: Flutter and ESLint checks cannot be run in the patch-building environment; JavaScript syntax was checked with node --check. Firebase has NOT been modified.
