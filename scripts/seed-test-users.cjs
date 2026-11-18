
"use strict";

const {createRequire} = require("node:module");
const path = require("node:path");

const projectId = "masjid-khalid-app";

// Force connections to the local Firebase emulators.
process.env.FIREBASE_AUTH_EMULATOR_HOST = "127.0.0.1:9099";
process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";

const fxRequire = createRequire(
  path.resolve(__dirname, "../functions/package.json"),
);

const {initializeApp} = fxRequire("firebase-admin/app");
const {getAuth} = fxRequire("firebase-admin/auth");
const {getFirestore, FieldValue} =
    fxRequire("firebase-admin/firestore");

async function main() {
  // Never run if the required local emulators are unavailable.
  const response = await fetch("http://127.0.0.1:4400/emulators");
  if (!response.ok) throw new Error("Emulators unavailable");

  const emulators = await response.json();
  for (const service of ["auth", "functions", "firestore"]) {
    if (!emulators[service]) {
      throw new Error(`${service} emulator is not running`);
    }
  }

  initializeApp({projectId});

  const auth = getAuth();
  const db = getFirestore();

  const accounts = [
    {
      username: "localadmin",
      password: "LocalAdmin#2026!",
      role: "admin",
      firstName: "Local",
      lastName: "Admin",
    },
    {
      username: "localuser",
      password: "LocalUser#2026!",
      role: "user",
      firstName: "Local",
      lastName: "User",
    },
  ];

  for (const account of accounts) {
    const email =
        `${account.username}@accounts.masjid-khalid.example`;

    let user;

    try {
      user = await auth.getUserByEmail(email);
      await auth.updateUser(user.uid, {
        password: account.password,
      });
    } catch (error) {
      if (error.code !== "auth/user-not-found") throw error;

      user = await auth.createUser({
        email,
        password: account.password,
      });
    }

    await auth.setCustomUserClaims(
      user.uid,
      account.role === "admin" ? {admin: true} : {},
    );

    await db.collection("users").doc(user.uid).set({
      firstName: account.firstName,
      lastName: account.lastName,
      username: account.username,
      phone: "0501234567",
      age: 25,
      city: "Test",
      role: account.role,
      createdAt: FieldValue.serverTimestamp(),
    });

    console.log(`CREATED: ${account.username} (${account.role})`);
  }

  console.log("LOCAL TEST ACCOUNTS READY!");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
