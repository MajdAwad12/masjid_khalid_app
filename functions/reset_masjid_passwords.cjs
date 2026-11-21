'use strict';

// One-time recovery tool for the original Firebase Authentication users.
// Place this script in the project's functions/ directory before running.
// Keep the service-account JSON outside the project and never commit it.

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const readline = require('node:readline/promises');
const { stdin: input, stdout: output } = require('node:process');
const { initializeApp, cert } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');

const PROJECT_ID = 'masjid-khalid-app';
const EMAIL_DOMAIN = 'accounts.masjid-khalid.example';

async function main() {
  if (process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error('Firebase Auth emulator mode detected. Stop and run in production mode.');
  }

  const serviceAccountPath = process.argv[2];
  if (!serviceAccountPath) {
    throw new Error('Usage: node reset_masjid_passwords.cjs "C:\\path\\to\\service-account.json"');
  }

  const serviceAccount = JSON.parse(fs.readFileSync(path.resolve(serviceAccountPath), 'utf8'));
  if (serviceAccount.project_id !== PROJECT_ID) {
    throw new Error(`Wrong Firebase project: ${serviceAccount.project_id}. Expected ${PROJECT_ID}.`);
  }

  initializeApp({ credential: cert(serviceAccount), projectId: PROJECT_ID });
  const auth = getAuth();
  const rl = readline.createInterface({ input, output });

  try {
    console.log('\nRecovery for existing users — no accounts or Firestore documents will be deleted.');
    console.log(`Firebase project: ${PROJECT_ID}\n`);

    for (const label of ['ADMIN', 'REGULAR USER']) {
      const username = (await rl.question(`${label} username (without @...): `)).trim().toLowerCase();
      if (!/^[a-z0-9_]{3,20}$/.test(username)) {
        throw new Error(`Invalid username: ${username}`);
      }

      const email = `${username}@${EMAIL_DOMAIN}`;
      const user = await auth.getUserByEmail(email);
      console.log(`Found existing account: ${user.email} | UID: ${user.uid}`);
      console.log(`Current admin custom claim: ${user.customClaims?.admin === true ? 'true' : 'false'}`);
      const confirmation = (await rl.question('Type RESET to change only its password: ')).trim();
      if (confirmation !== 'RESET') {
        console.log('Skipped.');
        continue;
      }

      const newPassword = `${crypto.randomBytes(24).toString('base64url')}Aa1!`;
      await auth.updateUser(user.uid, { password: newPassword });
      await auth.revokeRefreshTokens(user.uid);
      console.log(`\nSUCCESS: ${label} (${username})`);
      console.log(`NEW PASSWORD: ${newPassword}`);
      console.log('Store it securely now; it will not be saved in any project file.\n');
      await rl.question('Press Enter after saving the password...');
    }
    console.log('\nFinished. Sign in to the Flutter app using each username and its new password.');
  } finally {
    rl.close();
  }
}

main().catch((error) => {
  console.error(`\nFAILED: ${error.message}`);
  process.exitCode = 1;
});
