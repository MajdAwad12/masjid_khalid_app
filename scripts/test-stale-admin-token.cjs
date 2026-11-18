
"use strict";

const {createRequire} = require("node:module");
const {randomBytes} = require("node:crypto");
const path = require("node:path");

const projectId = "masjid-khalid-app";

process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";

const fxRequire = createRequire(
  path.resolve(__dirname, "../functions/package.json"),
);

const {initializeApp} = fxRequire("firebase-admin/app");
const {getAuth} = fxRequire("firebase-admin/auth");
const {getFirestore} = fxRequire("firebase-admin/firestore");

async function main() {
  // Verify local emulators before creating test data.
  const hub = await fetch("http://127.0.0.1:4400/emulators");
  if (!hub.ok) throw new Error("Emulator hub unavailable");

  const services = await hub.json();

  if (!services.auth || !services.firestore) {
    throw new Error("Authentication or Firestore emulator missing");
  }

  initializeApp({projectId});

  const auth = getAuth();
  const db = getFirestore();

  const username = `sec${randomBytes(5).toString("hex")}`;
  const email = `${username}@accounts.masjid-khalid.example`;
  const password = "LocalSecurity#2026!";

  let uid;

  try {
    // Create a temporary administrator.
    const account = await auth.createUser({
      email,
      password,
    });

    uid = account.uid;

    await auth.setCustomUserClaims(uid, {admin: true});

    await db.collection("users").doc(uid).set({
      firstName: "Security",
      lastName: "Test",
      username,
      phone: "0501234567",
      age: 25,
      city: "Test",
      role: "admin",
      createdAt: new Date(),
    });

    // Sign in and keep the original admin token.
    const login = await fetch(
      "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=local-test",
      {
        method: "POST",
        headers: {"Content-Type": "application/json"},
        body: JSON.stringify({
          email,
          password,
          returnSecureToken: true,
        }),
      },
    );

    const loginData = await login.json();

    if (!login.ok || !loginData.idToken) {
      throw new Error(`Login failed: ${JSON.stringify(loginData)}`);
    }

    const oldToken = loginData.idToken;
    const decoded = await auth.verifyIdToken(oldToken);

    if (decoded.admin !== true) {
      throw new Error("Original token has no admin claim");
    }

    const usersUrl =
      `http://127.0.0.1:8080/v1/projects/${projectId}` +
      "/databases/(default)/documents/users";

    async function listUsersWithOldToken() {
      return fetch(usersUrl, {
        headers: {
          Authorization: `Bearer ${oldToken}`,
        },
      });
    }

    // The active administrator should have access.
    const before = await listUsersWithOldToken();

    if (before.status !== 200) {
      throw new Error(
        `Expected admin access, got HTTP ${before.status}: ` +
        await before.text(),
      );
    }

    console.log("PASS: active admin can list users");

    // Demote the administrator without refreshing oldToken.
    await auth.setCustomUserClaims(uid, {});

    await db.collection("users").doc(uid).update({
      role: "user",
    });

    console.log("PASS: admin role removed in Auth and Firestore");

    // The old token still contains admin: true.
    const staleClaims = await auth.verifyIdToken(oldToken);

    if (staleClaims.admin !== true) {
      throw new Error("Test token is not stale");
    }

    console.log("PASS: old token still contains admin claim");

    // Firestore must reject that old token.
    const after = await listUsersWithOldToken();

    if (after.status !== 403) {
      throw new Error(
        `SECURITY FAILURE: expected HTTP 403, got ${after.status}: ` +
        await after.text(),
      );
    }

    console.log("PASS: old admin token denied by Firestore");
    console.log("STALE ADMIN TOKEN SECURITY TEST PASSED");
  } finally {
    // Remove only the temporary test account.
    if (uid) {
      await db.collection("users").doc(uid).delete();
      await auth.deleteUser(uid);
      console.log("Temporary test account cleaned up.");
    }
  }
}

main().catch((error) => {
  console.error("TEST FAILED:", error);
  process.exitCode = 1;
});
