"use strict";

// Local-only admin lifecycle integration test. SAFETY: aborts before writes
// unless Firebase Auth / Firestore / Functions emulators all respond on localhost.
// The public app has no registered user accounts.
const assert = require('node:assert/strict');
const path = require('node:path');
const {createRequire} = require('node:module');
const ROOT = path.resolve(__dirname, '..');
const requireFx = createRequire(path.join(ROOT, 'functions', 'package.json'));
const HOST = '127.0.0.1';
const PROJECT = 'masjid-khalid-app';
process.env.FIREBASE_AUTH_EMULATOR_HOST = `${HOST}:9099`;
process.env.FIRESTORE_EMULATOR_HOST = `${HOST}:8080`;
process.env.GCLOUD_PROJECT = PROJECT;
process.env.GOOGLE_CLOUD_PROJECT = PROJECT;
const {initializeApp} = requireFx('firebase-admin/app');
const {getAuth} = requireFx('firebase-admin/auth');
const {getFirestore, FieldValue} = requireFx('firebase-admin/firestore');
const BASE = `http://${HOST}:5001/${PROJECT}/us-central1`;
const AUTH_URL = `http://${HOST}:9099/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=emulator-key`;
const FIRESTORE_URL = `http://${HOST}:8080/v1/projects/${PROJECT}/databases/(default)/documents/users`;
const check = (ok, label) => { assert.ok(ok, label); console.log(`PASS: ${label}`); };
const json = async (resp) => resp.json().catch(() => ({}));
async function login(email, password) {
  const resp = await fetch(AUTH_URL, {
    method: 'POST', headers: {'Content-Type':'application/json'},
    body: JSON.stringify({email, password, returnSecureToken: true}),
  });
  const body = await json(resp);
  assert.ok(resp.ok && body.idToken, `Emulator login failed ${JSON.stringify(body)}`);
  return body.idToken;
}
async function call(name, data, token) {
  const headers = {'Content-Type':'application/json'};
  if (token) headers.Authorization = `Bearer ${token}`;
  const resp = await fetch(`${BASE}/${name}`, {
    method:'POST', headers, body:JSON.stringify({data}),
  });
  return {status:resp.status, body:await json(resp)};
}
async function listUsers(token) {
  const resp = await fetch(FIRESTORE_URL, {headers:{Authorization:`Bearer ${token}`}});
  return {status:resp.status, body:await json(resp)};
}
async function emulatorsReady() {
  const resp = await fetch(`http://${HOST}:4400/emulators`);
  assert.equal(resp.status, 200, 'Firebase local emulator hub missing');
  const available = await json(resp);
  for (const name of ['auth','functions','firestore']) check(Boolean(available[name]), `${name} emulator running`);
}
async function main() {
  await emulatorsReady();
  initializeApp({projectId:PROJECT});
  const auth=getAuth(), db=getFirestore();
  const stamp=`${Date.now()}_${Math.random().toString(36).slice(2,7)}`;
  const baseEmail=`qa_${stamp}@accounts.masjid-khalid.example`;
  const firstPass='LocalTestPassword#123';
  const created=[];
  try {
    const admin=await auth.createUser({email:baseEmail, password:firstPass});
    created.push(admin.uid);
    await auth.setCustomUserClaims(admin.uid,{admin:true});
    await db.collection('users').doc(admin.uid).set({
      username:`qa_${stamp}`.slice(0,20),role:'admin',
      createdAt:FieldValue.serverTimestamp(),
    });
    const token=await login(baseEmail,firstPass);
    check((await listUsers(token)).status===200,'active administrator may list users');
    await require('./test-registration-privacy-local.cjs').testRegistrationPrivacy({
      db, call, token, apiRoot: `http://${HOST}:8080/v1/projects/${PROJECT}/databases/(default)/documents`,
    });
    check((await call('createAdminAccount',{username:`a${stamp}`.slice(0,20),password:firstPass})).status>=400,
      'unauthenticated cannot create admin');
    const username=`q${stamp.replace(/[^a-z0-9_]/g,'')}`.slice(0,20);
    const createdResult=await call('createAdminAccount',{username,password:firstPass},token);
    check(createdResult.status===200 && createdResult.body.result?.success===true,'admin creates another admin');
    const uid=createdResult.body.result.uid;
    created.push(uid);
    const second=await auth.getUser(uid);
    check(second.customClaims?.admin===true,'new admin has custom claim');
    check((await db.collection('users').doc(uid).get()).data()?.role==='admin','new admin has role profile');
    const secondToken=await login(`${username}@accounts.masjid-khalid.example`,firstPass);
    check((await listUsers(secondToken)).status===200,'new admin can read users');
    const retiredRole=await call('changeUserRole',{targetUid:uid,role:'user'},token);
    check(retiredRole.status>=400,'retired public role management forbidden');
    const retiredReset=await call('resetUserPassword',{targetUid:uid,newPassword:'N3wPassword#123',identityVerified:true},token);
    check(retiredReset.status>=400,'retired public reset management forbidden');
    const deactivated=await call('deactivateAdminAccount',{targetUid:uid},token);
    check(deactivated.status===200 && deactivated.body.result?.success===true,'admin deactivates another admin');
    check((await auth.getUser(uid)).disabled===true,'deactivated admin is disabled in Auth');
    check((await db.collection('users').doc(uid).get()).data()?.role==='disabled','deactivated admin profile is disabled');
    check((await listUsers(secondToken)).status>=400,'stale token cannot list users after role revocation');
    for (const kind of ['Course','Activity']) {
      const stale = await call('manage'+kind+'Registration',{action:'erase'},secondToken);
      check(stale.status===403,'revoked staff cannot manage '+kind+' registrations');
    }
    check((await listUsers(token)).status===200,'remaining admin retains access');
    const recovery = db.collection('security_admin_recovery_emails').doc(admin.uid);
    const owner = db.collection('security_admin_recovery_email_owners').doc(stamp);
    await recovery.set({email: baseEmail});
    await owner.set({uid: admin.uid});
    const deletion = await call('deleteOwnAdminAccount', {}, token);
    check(deletion.status === 200, 'administrator requests their own erasure');
    check(!(await db.collection('users').doc(admin.uid).get()).exists, 'access removed immediately');
    for (let attempt = 0; attempt < 60 && (await owner.get()).exists; attempt++) {
      await new Promise(resolve => setTimeout(resolve, 500));
    }
    check(!(await owner.get()).exists && !(await recovery.get()).exists, 'recovery data erased');
    await assert.rejects(auth.getUser(admin.uid), {code:'auth/user-not-found'});
    check((await auth.getUser(uid)).disabled, 'another account survives erasure');
    console.log('ALL CURRENT ADMIN EMULATOR TESTS PASSED');
  } finally {
    for (const uid of created) {
      await db.collection('users').doc(uid).delete().catch(()=>{});
      await auth.deleteUser(uid).catch(()=>{});
    }
    // Remove local admin-management lock if left behind by a failed test.
    await db.collection('security_admin_management').doc('disable_lock').delete().catch(()=>{});
    console.log('Local QA accounts cleaned up.');
  }
}
main().catch(err=>{console.error('LOCAL ADMIN EMULATOR TEST FAILED:',err);process.exitCode=1;});
