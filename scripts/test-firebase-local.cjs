'use strict';

// Local-only integration test: never targets production Firebase.
// Run from the Flutter project root while auth/functions/firestore emulators run.
const path = require('node:path');
const assert = require('node:assert/strict');
const {createRequire} = require('node:module');

const PROJECT = 'masjid-khalid-app';
const HOST = '127.0.0.1';
const ROOT = path.resolve(__dirname, '..');
const fxRequire = createRequire(path.join(ROOT, 'functions', 'package.json'));

process.env.FIREBASE_AUTH_EMULATOR_HOST = `${HOST}:9099`;
process.env.FIRESTORE_EMULATOR_HOST = `${HOST}:8080`;
process.env.GCLOUD_PROJECT = PROJECT;
process.env.GOOGLE_CLOUD_PROJECT = PROJECT;

const {initializeApp} = fxRequire('firebase-admin/app');
const {getAuth} = fxRequire('firebase-admin/auth');
const {getFirestore, FieldValue} = fxRequire('firebase-admin/firestore');

const ROOT_URL = `http://${HOST}:5001/${PROJECT}/us-central1`;
const AUTH_URL = `http://${HOST}:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-key`;
const FIRESTORE_URL = `http://${HOST}:8080/v1/projects/${PROJECT}/databases/(default)/documents/users`;

function check(value, message) {
  assert.ok(value, message);
  console.log('PASS:', message);
}

async function responseJson(response) {
  return response.json().catch(() => ({}));
}

async function signIn(email, password) {
  const response = await fetch(AUTH_URL, {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  const body = await responseJson(response);
  if (!response.ok || !body.idToken) {
    throw new Error(`Emulator sign-in failed (${response.status}): ${JSON.stringify(body)}`);
  }
  return body.idToken;
}

async function callFunction(name, data, idToken) {
  const headers = {'Content-Type': 'application/json'};
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(`${ROOT_URL}/${name}`, {
    method: 'POST', headers, body: JSON.stringify({data}),
  });
  return {status: response.status, body: await responseJson(response)};
}

async function listUsers(idToken) {
  const response = await fetch(FIRESTORE_URL, {
    headers: {Authorization: `Bearer ${idToken}`},
  });
  return {status: response.status, body: await responseJson(response)};
}

async function checkEmulators() {
  const response = await fetch(`http://${HOST}:4400/emulators`);
  assert.equal(response.status, 200, 'Emulator hub not available');
  const state = await responseJson(response);
  for (const service of ['auth', 'functions', 'firestore']) {
    assert.ok(state[service], `Missing ${service} emulator`);
  }
  console.log('PASS: all three local emulators detected');
}

async function main() {
  // Abort before any Admin SDK writes unless ALL local emulators are running.
  await checkEmulators();
  initializeApp({projectId: PROJECT});
  const auth = getAuth();
  const db = getFirestore();
  const stamp = `${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  const adminEmail = `local_admin_${stamp}@accounts.masjid-khalid.example`;
  const userEmail = `local_user_${stamp}@accounts.masjid-khalid.example`;
  const originalPassword = 'LocalTestPassword#123';
  const replacementPassword = 'LocalNewPassword#456';
  const createdIds = [];

  try {
    const adminUser = await auth.createUser({email: adminEmail, password: originalPassword});
    createdIds.push(adminUser.uid);
    const normalUser = await auth.createUser({email: userEmail, password: originalPassword});
    createdIds.push(normalUser.uid);

    await auth.setCustomUserClaims(adminUser.uid, {admin: true});
    await Promise.all([
      db.collection('users').doc(adminUser.uid).set({
        firstName: 'Local', lastName: 'Admin', username: `admin_${stamp}`,
        phone: '0501234567', age: 30, city: 'Test', role: 'admin',
        createdAt: FieldValue.serverTimestamp(),
      }),
      db.collection('users').doc(normalUser.uid).set({
        firstName: 'Local', lastName: 'User', username: `user_${stamp}`,
        phone: '0501234567', age: 25, city: 'Test', role: 'user',
        createdAt: FieldValue.serverTimestamp(),
      }),
    ]);

    const adminToken = await signIn(adminEmail, originalPassword);
    const userToken = await signIn(userEmail, originalPassword);

    const unauthed = await callFunction('changeUserRole', {
      targetUid: normalUser.uid, role: 'admin',
    });
    check(unauthed.status >= 400, 'unauthenticated role change denied');

    const denied = await callFunction('changeUserRole', {
      targetUid: normalUser.uid, role: 'admin',
    }, userToken);
    check(denied.status >= 400, 'regular user cannot promote themself');

    const deniedList = await listUsers(userToken);
    check(deniedList.status >= 400, 'Firestore denies user list to regular user');

    const allowedList = await listUsers(adminToken);
    check(allowedList.status === 200, 'Firestore allows user list to admin');

    const promoted = await callFunction('changeUserRole', {
      targetUid: normalUser.uid, role: 'admin',
    }, adminToken);
    check(promoted.status === 200 && promoted.body.result?.success === true,
        'admin promotes user through Cloud Function');
    check((await auth.getUser(normalUser.uid)).customClaims?.admin === true &&
        (await db.collection('users').doc(normalUser.uid).get()).data()?.role === 'admin',
        'promotion synced in Auth Custom Claims and Firestore');

    const demoted = await callFunction('changeUserRole', {
      targetUid: normalUser.uid, role: 'user',
    }, adminToken);
    check(demoted.status === 200 && demoted.body.result?.success === true,
        'admin demotes user through Cloud Function');
    check((await auth.getUser(normalUser.uid)).customClaims?.admin !== true &&
        (await db.collection('users').doc(normalUser.uid).get()).data()?.role === 'user',
        'demotion synced in Auth Custom Claims and Firestore');

    const selfDemotion = await callFunction('changeUserRole', {
      targetUid: adminUser.uid, role: 'user',
    }, adminToken);
    check(selfDemotion.status >= 400, 'admin cannot demote themself');

    const noConfirmation = await callFunction('resetUserPassword', {
      targetUid: normalUser.uid, newPassword: replacementPassword,
      identityVerified: false,
    }, adminToken);
    check(noConfirmation.status >= 400, 'password reset requires identity confirmation');

    const reset = await callFunction('resetUserPassword', {
      targetUid: normalUser.uid, newPassword: replacementPassword,
      identityVerified: true,
    }, adminToken);
    check(reset.status === 200 && reset.body.result?.success === true,
        'authorized password reset succeeded');
    await signIn(userEmail, replacementPassword);
    check(true, 'new password works in Authentication Emulator');

    console.log('\nALL LOCAL INTEGRATION TESTS PASSED');
  } finally {
    for (const uid of createdIds) {
      await db.collection('users').doc(uid).delete().catch(() => {});
      await auth.deleteUser(uid).catch(() => {});
    }
    console.log('Local test users cleaned up.');
  }
}

main().catch((error) => {
  console.error('\nLOCAL TEST FAILED:', error.message);
  process.exitCode = 1;
});
