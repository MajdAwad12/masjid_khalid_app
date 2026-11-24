# Admin login cooldown patch — Stage 2

## Behavior

* 3 incorrect attempts from the same network origin and requested username → 15 minute lockout.
* After the 15 minute lockout expires, **one more** incorrect attempt → 24 hour lockout.
* After the 24 hour lockout expires, the escalation resets. A successful login clears this origin/username history.
* No permanent admin account disablement. Public users are never asked to sign in.

The state is stored only server-side in `security_admin_login_attempts` Firestore collection. The existing deny-by-default Firestore rules already prevent clients reading or writing it; the Admin SDK can access it. Never create client write rules for this collection.

## IMPORTANT security boundary

The login dialog is backed by a Firebase Cloud Function that validates passwords itself with the Firebase Authentication REST endpoint, so false login attempts are recorded without relying on Flutter reporting them. **However, a determined attacker can call Firebase Authentication's direct password endpoint**, bypassing this app-specific cooldown; Firebase's own protection/rate limiting still applies. Hard enforcement for *all* sign-in methods requires an Identity Platform authorization blocking function or another comprehensive identity-layer design. Treat this as an app-level safeguard, **not** a replacement for App Check, multifactor authentication, server authorization, or monitoring.

Lockouts are scoped to an IP+username fingerprint to reduce (not eliminate) deliberate lockouts of administrator accounts. A shared network may cause collateral short lockouts, and changing IP can bypass the app-specific restriction. Passwords, IPs, ID tokens and refresh tokens are not written to Firestore or logs. The REST call is HTTPS; no credential is saved by this code.

## Install on Windows

1. Stay on Git branch `redesign-public-app` and verify git status.
2. Extract zip into root of project (overwrites just 2 code files):

```powershell
cd C:\development\projects\masjid_khalid_app
git branch --show-current
Expand-Archive -LiteralPath "$env:USERPROFILE\Downloads\masjid_admin_login_cooldown.zip" -DestinationPath . -Force
dart format lib\auth\auth_service.dart
flutter analyze
cd functions
npm ci
npm run lint
cd ..
```

3. Deploy **the new callable function only** after lint passes and before testing login. Other functions must remain untouched for the moment:

```powershell
firebase deploy --only functions:loginAdminWithCooldown
```

4. Run Flutter and test: intentionally fail 3 times, verify 15-min message; **do not have to wait 15 minutes** just to test — check Firestore document or use the Firebase Emulator for clock-driven unit tests. Verify real admin login separately from a fresh network/source. Do not attempt to disable existing admins to test lockout. No Firestore rules deployment needed for the new server-only collection, and do not delete existing `users` documents.

5. Check `git diff`, `git status` before committing. Do not deploy until confirming correct Firebase project.

### NOTE

A direct Firebase SDK login from another client remains possible unless the identity-level access route is separately restricted. For stronger protection set up Firebase App Check and consider Identity Platform blocking functions. Do not switch App Check enforcement on before configuring providers and debug tokens for emulator testing.
