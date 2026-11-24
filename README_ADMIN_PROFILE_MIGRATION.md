# Admin profile schema — 4 fields (Masjid Khalid)

## What changed
- `functions/index.js`: new administrators now have exactly `username`, `role`, `createdAt`, `createdBy` in `users/{uid}`. Deactivating an admin only changes `role` to `disabled`.
- Added **temporary** admin-only callable `normalizeAdminProfiles` with a preview (`apply: false`) and explicit apply (`apply: true`). It processes **active admins only** and replaces each eligible legacy admin document with the four-field schema. It does not delete Firebase Auth accounts or touch the server-only recovery-email collections.
- `lib/services/admin_service.dart` and `lib/screens/admins_management_page.dart`: one-time cleanup button `توحيد بيانات المسؤولين القديمة` within admin management, showing the count and requiring confirmation before the server edits existing profiles.

## Install and check (PowerShell, project root)
```powershell
Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\masjid_admin_profiles_4fields_patch.zip" -DestinationPath . -Force
dart format lib
flutter analyze
cd functions
npm run lint
cd ..
```
**Do not deploy until analysis and lint pass.** Node syntax and basic normalization logic were checked during patch preparation, but Flutter/analyzer and full Firebase integration were not run here.

## Deployment, after checks pass
```powershell
firebase deploy --project masjid-khalid-app --only functions:createAdminAccount,functions:deactivateAdminAccount,functions:normalizeAdminProfiles
```
Restart the app. Sign in as an active administrator *recently* (within 10 minutes), open `إدارة المسؤولين`, press `توحيد بيانات المسؤولين القديمة`, review the preview, and confirm. Before pressing Confirm, make a **fresh backup of the current Firestore data**, because administrators were created after the earlier backup.

## Verify
Open Firebase Console > Firestore > `users` and inspect each active admin. Each should contain exactly these fields:
`username`, `role`, `createdAt`, `createdBy`. For a legacy original administrator without a recorded creator, `createdBy` is `null`. The original `createdAt` timestamp is preserved where available, else the Auth account creation timestamp is used. Passwords remain in Firebase Auth and verified recovery email records remain in the separate `security_admin_recovery_*` collections.

Legacy documents with `role: disabled` and historical regular-user records are **not modified** by this cleanup. The Cloud Function explicitly checks active Auth admin claims before changing any document. Do not manually delete records or remove the `users` collection.

## Security follow-up
After cleanup is verified, remove the temporary cleanup button, its `AdminService` method, and `normalizeAdminProfiles` function, then deploy the cleanup removal. Keep `createAdminAccount` and `deactivateAdminAccount`.
