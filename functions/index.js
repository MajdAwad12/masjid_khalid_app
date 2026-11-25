"use strict";

const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const crypto = require("node:crypto");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getStorage} = require("firebase-admin/storage");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated, onDocumentDeleted,
} = require("firebase-functions/v2/firestore");
const {
  getFirestore, FieldValue, Timestamp,
} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const {defineSecret} = require("firebase-functions/params");
const nodemailer = require("nodemailer");

initializeApp();
setGlobalOptions({maxInstances: 10});

const auth = getAuth();
const db = getFirestore();

const gmailSenderEmail = defineSecret("GMAIL_SENDER_EMAIL");
const gmailAppPassword = defineSecret("GMAIL_APP_PASSWORD");

// Gmail SMTP transport. Keep credentials in Cloud Secret Manager, never in
// Flutter, Firestore, logs, or version control. Requires a Gmail App Password.
const sendGmail = async ({to, subject, text}) => {
  const sender = gmailSenderEmail.value().trim();
  const password = gmailAppPassword.value().replace(/\s/g, "");
  if (!sender || !password) {
    throw new Error("Gmail SMTP secrets are missing.");
  }
  const transport = nodemailer.createTransport({
    service: "gmail",
    auth: {user: sender, pass: password},
    connectionTimeout: 15000,
    greetingTimeout: 15000,
    socketTimeout: 20000,
  });
  return transport.sendMail({
    from: {name: "Masjid Khalid", address: sender},
    to: to,
    subject: subject,
    text: text,
  });
};

// Verify current administrator privileges in both Auth and Firestore.
const requireAdmin = async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access required.");
  }

  const adminUid = request.auth.uid;
  const admin = await auth.getUser(adminUid);
  if (admin.disabled || admin.customClaims?.admin !== true) {
    throw new HttpsError("permission-denied", "Admin access denied.");
  }

  const profile = await db.collection("users").doc(adminUid).get();
  if (!profile.exists || profile.data()?.role !== "admin") {
    throw new HttpsError(
        "permission-denied",
        "Administrator role is no longer active.",
    );
  }
  return adminUid;
};

const validateUid = (uid) => {
  if (typeof uid !== "string" || uid.length === 0 || uid.length > 128) {
    throw new HttpsError("invalid-argument", "Invalid user ID.");
  }
  return uid;
};

const findUser = async (uid) => {
  try {
    return await auth.getUser(uid);
  } catch (error) {
    if (error.code === "auth/user-not-found") {
      throw new HttpsError("not-found", "User not found.");
    }
    throw error;
  }
};

// Admin login cooldown. This is enforced by the callable sign-in endpoint.
// It is scoped to the network source IP, across all attempted usernames.
// NOTE: a shared network IP can affect multiple users on the same network.
// NOTE: Firebase's direct password sign-in endpoint is separately available;
// see README_ADMIN_LOGIN_COOLDOWN.md for the enforcement boundary.
const loginAttemptRecords = db.collection("security_admin_login_attempts");
const fifteenMinutesMs = 15 * 60 * 1000;
const oneDayMs = 24 * 60 * 60 * 1000;

const attemptRecord = (request) => {
  // Do not trust X-Forwarded-For supplied by a client. Cloud Functions
  // exposes the resolved peer IP here.
  const ip = request.rawRequest?.ip;
  if (typeof ip !== "string" || ip.length === 0) {
    throw new HttpsError("unavailable", "Unable to verify login source.");
  }
  const key = crypto.createHash("sha256")
      .update(`admin-login-source\0${ip}`).digest("hex");
  return loginAttemptRecords.doc(key);
};

const activePenalty = (data, now) => {
  const until = Number(data?.blockedUntilMs) || 0;
  if (until > now) {
    return {
      blockedUntilMs: until,
      waitSeconds: Math.ceil((until - now) / 1000),
    };
  }
  return null;
};

const loginBlocked = (penalty) => new HttpsError(
    "resource-exhausted", "Admin sign-in temporarily unavailable.",
    {waitSeconds: penalty.waitSeconds},
);

const ensureNotLoginBlocked = async (ref) => {
  const snapshot = await ref.get();
  const penalty = activePenalty(snapshot.data(), Date.now());
  if (penalty) throw loginBlocked(penalty);
};

// Every failed credential check is counted server-side in a transaction.
// 3 failures => 15 minute pause. A *further* failed attempt after the pause
// => 24 hour pause. After 24 hours of inactivity, the penalty escalator resets.
const noteAdminLoginFailure = async (ref) => {
  const now = Date.now();
  const penalty = await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const data = snapshot.data() || {};
    const existing = activePenalty(data, now);
    if (existing) return existing;

    let stage = Number(data.stage) || 0;
    const oldUntil = Number(data.blockedUntilMs) || 0;
    // First escalation window expires after an additional 24h of inactivity.
    if (stage === 1 && now > oldUntil + oneDayMs) stage = 0;
    // A completed 24-hour block always restarts at level zero.
    if (stage === 2 && now >= oldUntil) stage = 0;

    let failureCount = Number(data.failureCount) || 0;
    let blockedUntilMs = 0;
    if (stage === 1) {
      stage = 2;
      failureCount = 0;
      blockedUntilMs = now + oneDayMs;
    } else {
      failureCount += 1;
      if (failureCount >= 3) {
        stage = 1;
        failureCount = 0;
        blockedUntilMs = now + fifteenMinutesMs;
      }
    }
    tx.set(ref, {
      stage: stage,
      failureCount: failureCount,
      blockedUntilMs: blockedUntilMs,
      updatedAt: FieldValue.serverTimestamp(),
    });
    return blockedUntilMs > now ? {
      blockedUntilMs: blockedUntilMs,
      waitSeconds: Math.ceil((blockedUntilMs - now) / 1000),
    } : null;
  });
  return penalty;
};

const clearLoginFailureOnSuccess = async (ref) => {
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const penalty = activePenalty(snapshot.data(), Date.now());
    if (penalty) throw loginBlocked(penalty);
    if (snapshot.exists) tx.delete(ref);
  });
};

// Authenticate credentials against Firebase Auth on the server so incorrect
// passwords are counted even if a modified client omits a failure callback.
// An API key is a public Firebase application identifier, not a secret.
exports.loginAdminWithCooldown = onCall({
  region: "us-central1",
  invoker: "public",
  maxInstances: 5,
}, async (request) => {
  const username = typeof request.data?.username === "string" ?
    request.data.username.trim().toLowerCase() : "";
  const password = request.data?.password;
  const apiKey = request.data?.apiKey;
  if (username.length > 128 ||
      typeof password !== "string" || password.length === 0 ||
      password.length > 128 ||
      typeof apiKey !== "string" || apiKey.length < 20 ||
      apiKey.length > 256) {
    throw new HttpsError("invalid-argument", "Invalid sign-in request.");
  }

  const ref = attemptRecord(request);
  await ensureNotLoginBlocked(ref);
  // Count all submitted credentials, including unknown or malformed usernames.
  // Never reveal whether a particular administrator username exists.
  if (!/^[a-z0-9_]{3,20}$/.test(username)) {
    const penalty = await noteAdminLoginFailure(ref);
    if (penalty) throw loginBlocked(penalty);
    throw new HttpsError(
        "permission-denied", "Invalid username or password.");
  }
  let result;
  try {
    const signInUrl =
        "https://identitytoolkit.googleapis.com/v1/" +
        "accounts:signInWithPassword" +
        `?key=${encodeURIComponent(apiKey)}`;
    const response = await fetch(signInUrl, {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({
        email: `${username}@${internalDomain}`,
        password: password,
        returnSecureToken: true,
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (response.status === 400) {
      const penalty = await noteAdminLoginFailure(ref);
      if (penalty) throw loginBlocked(penalty);
      throw new HttpsError(
          "permission-denied", "Invalid username or password.");
    }
    if (!response.ok) {
      throw new HttpsError(
          "unavailable", "Authentication service unavailable.");
    }
    result = await response.json();
    if (typeof result.idToken !== "string") {
      throw new HttpsError("unavailable", "No valid authentication token.");
    }
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.warn("Administrator authentication request failed", {
      code: error.code || "network-error",
    });
    throw new HttpsError(
        "unavailable", "Authentication temporarily unavailable.");
  }

  try {
    // Validates project, audience, signature and expiration of the ID token.
    const identity = await auth.verifyIdToken(result.idToken);
    const account = await auth.getUser(identity.uid);
    const profile = await db.collection("users").doc(identity.uid).get();
    if (account.disabled || account.customClaims?.admin !== true ||
        profile.data()?.role !== "admin") {
      const penalty = await noteAdminLoginFailure(ref);
      if (penalty) throw loginBlocked(penalty);
      throw new HttpsError(
          "permission-denied", "Invalid username or password.");
    }
    await clearLoginFailureOnSuccess(ref);
    // Never return the password, ID token or refresh token from the REST call.
    const customToken = await auth.createCustomToken(identity.uid);
    return {customToken: customToken};
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    logger.error("Admin sign-in verification failed", {
      code: error.code || "unknown",
    });
    throw new HttpsError(
        "unavailable", "Could not complete administrator login.");
  }
});

// Legacy endpoints are kept temporarily so deployment disables them safely.
// Public user accounts and promotions are no longer part of this application.
exports.changeUserRole = onCall({
  region: "us-central1", invoker: "public",
}, async (request) => {
  await requireAdmin(request);
  throw new HttpsError("failed-precondition", "Use admin management instead.");
});

exports.resetUserPassword = onCall({
  region: "us-central1", invoker: "public",
}, async (request) => {
  await requireAdmin(request);
  throw new HttpsError("failed-precondition", "Public accounts are retired.");
});

// Creating an admin never uses the client FirebaseAuth.createUser API, which
// would replace the signed-in admin. The server is the only account creator.
const adminUsernamePattern = /^[a-z0-9_]{3,20}$/;
const internalDomain = "accounts.masjid-khalid.example";

const requireRecentAdmin = async (request) => {
  const uid = await requireAdmin(request);
  const authTime = Number(request.auth.token.auth_time);
  const now = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(authTime) || authTime <= 0 ||
      now - authTime > 600 || authTime > now + 60) {
    throw new HttpsError(
        "failed-precondition", "Sign in again before managing admins.");
  }
  return uid;
};

exports.createAdminAccount = onCall({
  region: "us-central1", invoker: "public",
}, async (request) => {
  const adminUid = await requireRecentAdmin(request);
  const username = typeof request.data?.username === "string" ?
    request.data.username.trim().toLowerCase() : "";
  const password = request.data?.password;
  if (!adminUsernamePattern.test(username) ||
      typeof password !== "string" ||
      password.length < 12 || password.length > 128) {
    throw new HttpsError("invalid-argument", "Invalid credentials.");
  }
  let created;
  try {
    created = await auth.createUser({
      email: `${username}@${internalDomain}`,
      password: password,
      disabled: false,
    });
  } catch (error) {
    if (error.code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", "Username is already in use.");
    }
    logger.error("Admin Auth creation failed", {code: error.code || "unknown"});
    throw new HttpsError("internal", "Could not create administrator.");
  }

  const profileRef = db.collection("users").doc(created.uid);
  try {
    await auth.setCustomUserClaims(created.uid, {admin: true});
    // Only the four agreed profile fields are stored in users/{uid}.
    // Passwords and Auth claims live in Firebase Authentication; recovery
    // email details remain in the server-only security_* collections.
    await profileRef.set({
      username: username,
      role: "admin",
      createdAt: FieldValue.serverTimestamp(),
      createdBy: adminUid,
    });
  } catch (error) {
    // Compensate if one system succeeds and the other fails.
    try {
      await profileRef.delete();
      await auth.deleteUser(created.uid);
    } catch (rollbackError) {
      logger.error("Admin creation rollback failed", {
        uid: created.uid,
        code: rollbackError.code || "unknown",
      });
    }
    logger.error("Admin creation failed", {code: error.code || "unknown"});
    throw new HttpsError("internal", "Could not finish admin creation.");
  }
  logger.info("Administrator created", {
    actorUid: adminUid, targetUid: created.uid,
  });
  return {success: true, uid: created.uid};
});

// Serializes deactivations so two admins cannot disable each other in parallel.
// The lock is server-only and has a lease to recover after interrupted calls.
const adminDisableLock = db.collection("security_admin_management")
    .doc("disable_lock");
exports.deactivateAdminAccount = onCall({
  region: "us-central1", invoker: "public",
}, async (request) => {
  const adminUid = await requireRecentAdmin(request);
  const targetUid = validateUid(request.data?.targetUid);
  if (targetUid === adminUid) {
    throw new HttpsError(
        "failed-precondition", "Cannot disable your own account.");
  }
  const lockId = crypto.randomUUID();
  await db.runTransaction(async (tx) => {
    const lock = await tx.get(adminDisableLock);
    const acquired = Number(lock.data()?.atMs) || 0;
    if (acquired > Date.now() - 120000) {
      throw new HttpsError("resource-exhausted", "Admin change in progress.");
    }
    tx.set(adminDisableLock, {lockId: lockId, atMs: Date.now()});
  });

  try {
    // Verify the caller still has privileges after waiting for the lock.
    await requireAdmin(request);
    const adminDocs = await db.collection("users")
        .where("role", "==", "admin").get();
    if (adminDocs.size <= 1) {
      throw new HttpsError(
          "failed-precondition", "Last admin cannot be disabled.");
    }
    const profileRef = db.collection("users").doc(targetUid);
    const profile = await profileRef.get();
    const target = await findUser(targetUid);
    if (!profile.exists || profile.data()?.role !== "admin" ||
        target.disabled || target.customClaims?.admin !== true) {
      throw new HttpsError("failed-precondition", "Active admin not found.");
    }
    const originalClaims = {...(target.customClaims || {})};
    const newClaims = {...originalClaims};
    delete newClaims.admin;
    try {
      await auth.updateUser(targetUid, {disabled: true});
      await auth.setCustomUserClaims(targetUid, newClaims);
      // Deactivation must not add fields outside the agreed schema.
      // Audit actors are already recorded in the server logs.
      await profileRef.update({role: "disabled"});
    } catch (error) {
      // Best effort rollback: preserve working admin if Firestore fails.
      try {
        await auth.setCustomUserClaims(targetUid, originalClaims);
        await auth.updateUser(targetUid, {disabled: false});
      } catch (rollbackError) {
        logger.error("Admin disable rollback failed", {
          targetUid: targetUid,
          code: rollbackError.code || "unknown",
        });
      }
      logger.error("Admin disable failed", {code: error.code || "unknown"});
      throw new HttpsError("internal", "Could not disable administrator.");
    }
    logger.info("Administrator deactivated", {
      actorUid: adminUid, targetUid: targetUid,
    });
    return {success: true};
  } finally {
    try {
      await db.runTransaction(async (tx) => {
        const lock = await tx.get(adminDisableLock);
        if (lock.data()?.lockId === lockId) tx.delete(adminDisableLock);
      });
    } catch (error) {
      logger.error("Admin management lock release failed", {
        code: error.code || "unknown",
      });
    }
  }
});

// --- Personal recovery-email enrollment (not password reset) ---
// Addresses are stored in server-only collections and never trusted from
// client-editable user profile fields.
const recoveryRecords = db.collection("security_admin_recovery_emails");
const recoveryPending = db.collection("security_admin_recovery_pending");
const recoveryOwners = db.collection("security_admin_recovery_email_owners");
const recoveryLimits = db.collection("security_admin_recovery_limits");
const verifyLinkLifetimeMs = 20 * 60 * 1000;
const verifySendCooldownMs = 2 * 60 * 1000;

const normalizeEmail = (value) => {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", "Invalid recovery email.");
  }
  const email = value.trim().toLowerCase();
  if (email.length < 6 || email.length > 254 ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Invalid recovery email.");
  }
  return email;
};
const emailFingerprint = (email) =>
  crypto.createHash("sha256").update(email, "utf8").digest("hex");
const tokenFingerprint = (token) =>
  crypto.createHash("sha256").update(token, "utf8").digest("hex");

// Used by the admin's Settings screen to display a real verified status.
exports.getAdminRecoveryEmailStatus = onCall({
  region: "us-central1",
  invoker: "public",
}, async (request) => {
  const uid = await requireAdmin(request);
  const [record, pending] = await Promise.all([
    recoveryRecords.doc(uid).get(),
    recoveryPending.doc(uid).get(),
  ]);
  const pendingData = pending.data();
  return {
    verified: record.exists && record.data()?.verified === true,
    verifiedEmail: record.data()?.verified === true ?
      record.data().email : null,
    pendingEmail: pendingData && pendingData.expiresAtMs > Date.now() ?
      pendingData.email : null,
  };
});

// Admin must have signed in recently before changing recovery credentials.
exports.requestAdminRecoveryEmailVerification = onCall({
  region: "us-central1",
  invoker: "public",
  secrets: [gmailSenderEmail, gmailAppPassword],
}, async (request) => {
  const uid = await requireAdmin(request);
  const authTime = Number(request.auth.token.auth_time);
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(authTime) || authTime <= 0 ||
      nowSeconds - authTime > 600 || authTime > nowSeconds + 60) {
    throw new HttpsError(
        "failed-precondition", "Sign in again before updating recovery email.");
  }

  const email = normalizeEmail(request.data?.email);
  const uidRef = recoveryRecords.doc(uid);
  const record = await uidRef.get();
  if (record.data()?.verified === true && record.data()?.email === email) {
    throw new HttpsError("failed-precondition", "Email already verified.");
  }

  const token = crypto.randomBytes(32).toString("hex");
  const nowMs = Date.now();
  const pendingRef = recoveryPending.doc(uid);
  const limitRef = recoveryLimits.doc(uid);

  await db.runTransaction(async (tx) => {
    const limit = await tx.get(limitRef);
    const lastSentAtMs = limit.data()?.lastSentAtMs;
    if (typeof lastSentAtMs === "number" &&
        nowMs - lastSentAtMs < verifySendCooldownMs) {
      throw new HttpsError(
          "resource-exhausted", "Wait before requesting another link.");
    }
    tx.set(limitRef, {lastSentAtMs: nowMs});
    tx.set(pendingRef, {
      email: email,
      tokenHash: tokenFingerprint(token),
      expiresAtMs: nowMs + verifyLinkLifetimeMs,
      createdAtMs: nowMs,
    });
  });

  const project = process.env.GCLOUD_PROJECT || "masjid-khalid-app";
  const verificationUrl =
      `https://us-central1-${project}.cloudfunctions.net/` +
      "verifyAdminRecoveryEmail" +
      `?uid=${encodeURIComponent(uid)}&token=${token}`;

  try {
    await sendGmail({
      to: email,
      subject: "تأكيد بريد استعادة حساب مسؤول المسجد",
      text: "لتأكيد بريد استعادة حساب المسؤول، افتح الرابط التالي " +
        "واضغط على زر التأكيد خلال 20 دقيقة:\n\n" +
        verificationUrl + "\n\n" +
        "إذا لم تطلب ذلك، تجاهل هذه الرسالة.",
    });
  } catch (error) {
    logger.error("Gmail SMTP verification email failed", {
      uid: uid,
      code: error.code || "unknown",
    });
    throw new HttpsError("unavailable", "Could not send verification email.");
  }
  logger.info("Recovery verification email submitted", {uid});
  return {success: true};
});

const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (c) => ({
  "&": "&amp;",
  "<": "&lt;",
  ">": "&gt;",
  "\"": "&quot;",
  "'": "&#39;",
})[c]);

const verificationPage = (message, form = "") =>
  "<!doctype html><html lang=\"ar\" dir=\"rtl\">" +
  "<head><meta charset=\"UTF-8\"><meta name=\"viewport\" " +
  "content=\"width=device-width,initial-scale=1\">" +
  "<title>تأكيد بريد الاسترداد</title><style>" +
  "body{font-family:system-ui,sans-serif;background:#f6f5f2;" +
  "padding:2rem;max-width:34rem;margin:5vh auto;color:#1e2524}" +
  "section{background:white;border:1px solid #ddd;border-radius:16px;" +
  "padding:2rem}button{background:#196c52;color:#fff;border:0;" +
  "border-radius:9px;padding:12px 24px;font-size:1rem;cursor:pointer}" +
  "</style></head><body><section><h2>مسجد خالد بن الوليد</h2><p>" +
  escapeHtml(message) + "</p>" + form + "</section></body></html>";

// GET only shows a confirmation page (to avoid email security scanners
// consuming links). Actual verification is a user-initiated POST.
exports.verifyAdminRecoveryEmail = onRequest({
  region: "us-central1",
  invoker: "public",
}, async (req, res) => {
  res.set("Cache-Control", "no-store, max-age=0");
  res.set("Referrer-Policy", "no-referrer");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("Content-Security-Policy", "default-src 'none'; " +
    "style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'");
  res.type("html");

  let uid;
  let token;
  if (req.method === "GET") {
    uid = req.query.uid;
    token = req.query.token;
  } else if (req.method === "POST") {
    // Use the raw URL-encoded form submitted by the confirmation page.
    const params = new URLSearchParams(req.rawBody?.toString("utf8") || "");
    uid = params.get("uid");
    token = params.get("token");
  } else {
    return res.status(405).send(verificationPage("الطريقة غير مدعومة."));
  }

  if (typeof uid !== "string" ||
      !/^[a-zA-Z0-9_-]{1,128}$/.test(uid) ||
      typeof token !== "string" || !/^[a-f0-9]{64}$/.test(token)) {
    return res.status(400).send(verificationPage("رابط التحقق غير صالح."));
  }

  if (req.method === "GET") {
    const form = "<form method=\"post\">" +
      `<input type="hidden" name="uid" value="${escapeHtml(uid)}">` +
      `<input type="hidden" name="token" value="${escapeHtml(token)}">` +
      "<button type=\"submit\">تأكيد البريد الإلكتروني</button></form>";
    return res.status(200).send(verificationPage(
        "اضغط على الزر لتأكيد بريد استعادة كلمة المرور.", form));
  }

  try {
    const target = await auth.getUser(uid);
    if (target.disabled || target.customClaims?.admin !== true) {
      return res.status(403).send(
          verificationPage("هذا الحساب ليس مسؤولًا نشطًا."));
    }

    const pendingRef = recoveryPending.doc(uid);
    const recordRef = recoveryRecords.doc(uid);
    const userRef = db.collection("users").doc(uid);
    const tokenHash = tokenFingerprint(token);
    await db.runTransaction(async (tx) => {
      const [pending, profile, existing] = await Promise.all([
        tx.get(pendingRef), tx.get(userRef), tx.get(recordRef),
      ]);
      const value = pending.data();
      if (!value || value.expiresAtMs < Date.now() ||
          typeof value.tokenHash !== "string" ||
          value.tokenHash.length !== tokenHash.length ||
          !crypto.timingSafeEqual(
              Buffer.from(value.tokenHash), Buffer.from(tokenHash)) ||
          !profile.exists || profile.data()?.role !== "admin") {
        throw new Error("invalid-or-expired");
      }

      const ownerRef = recoveryOwners.doc(emailFingerprint(value.email));
      const oldEmail = existing.data()?.email;
      const oldOwnerRef = oldEmail && oldEmail !== value.email ?
        recoveryOwners.doc(emailFingerprint(oldEmail)) : null;
      const owner = await tx.get(ownerRef);
      const oldOwner = oldOwnerRef ? await tx.get(oldOwnerRef) : null;
      if (owner.exists && owner.data()?.uid !== uid) {
        throw new Error("email-in-use");
      }

      // Every read above precedes all writes as Firestore requires.
      tx.set(recordRef, {
        email: value.email,
        verified: true,
        verifiedAtMs: Date.now(),
      });
      tx.set(ownerRef, {uid: uid});
      if (oldOwnerRef && oldOwner?.data()?.uid === uid) {
        tx.delete(oldOwnerRef);
      }
      tx.delete(pendingRef);
    });
  } catch (error) {
    const message = error.message === "email-in-use" ?
      "هذا البريد مسجّل لمسؤول آخر. استخدم بريدًا شخصيًا مختلفًا." :
      "الرابط منتهي الصلاحية أو سبق استخدامه. اطلب رابطًا جديدًا من الإعدادات.";
    return res.status(400).send(verificationPage(message));
  }
  logger.info("Admin recovery email verified", {uid});
  return res.status(200).send(verificationPage(
      "تم تأكيد بريدك الإلكتروني بنجاح. ارجع إلى التطبيق وحدّث حالة التحقق."));
});

// --- Admin-only self-service password recovery ---
// Public entry point: callers learn nothing about account existence.
// Only a CURRENT admin with a previously VERIFIED recovery email is eligible.
// Reset tokens are single use, short lived, stored hashed and tied to the
// specific verified email. No Firebase Auth synthetic email is changed.
const passwordRecoveryTokens = db.collection(
    "security_admin_password_recovery_tokens");
const passwordRecoveryLimits = db.collection(
    "security_admin_password_recovery_limits");
const passwordRecoveryIpLimits = db.collection(
    "security_admin_password_recovery_ip_limits");
const passwordRecoveryLifetimeMs = 15 * 60 * 1000;
const passwordRecoveryCooldownMs = 10 * 60 * 1000;
// Remove access and durably schedule erasure together. Only the caller's
// verified UID can select an account. The queue has no client access.
const deletionQueue = db.collection("security_account_deletions");
exports.deleteOwnAdminAccount = onCall({
  region: "us-central1", invoker: "public",
}, async (req) => {
  const uid = await requireRecentAdmin(req);
  const batch = db.batch();
  batch.delete(db.collection("users").doc(uid));
  batch.set(deletionQueue.doc(uid), {
    requestedAt: FieldValue.serverTimestamp(),
  });
  await batch.commit();
  return {accepted: true};
});

exports.finishAccountDeletion = onDocumentCreated({
  document: "security_account_deletions/{uid}", region: "us-central1",
  retry: true,
}, async (event) => {
  const uid = event.params.uid;
  try {
    await auth.deleteUser(uid);
  } catch (error) {
    if (error.code !== "auth/user-not-found") throw error;
  }
  // An owner index is keyed by email hash. Only remove entries still
  // owned by this UID, including when an event is delivered twice.
  await db.runTransaction(async (tx) => {
    const owners = await tx.get(recoveryOwners.where("uid", "==", uid));
    for (const owner of owners.docs) tx.delete(owner.ref);
    for (const records of [recoveryRecords, recoveryPending, recoveryLimits,
      passwordRecoveryTokens, passwordRecoveryLimits,
      db.collection("security_password_reset_limits")]) {
      tx.delete(records.doc(uid));
    }
    tx.delete(deletionQueue.doc(uid));
  });
});
const recoveryGenericResponse = {
  success: true,
  message: "If this is an active administrator with a verified " +
      "recovery email, a message will be sent.",
};

// Limit anonymous request traffic without recording raw IP addresses.
const checkRecoveryIpLimit = async (request) => {
  const ip = request.rawRequest?.ip ||
      request.rawRequest?.socket?.remoteAddress || "unknown";
  const ipHash = crypto.createHash("sha256")
      .update(`admin-recovery-v1:${ip}`).digest("hex");
  const ref = passwordRecoveryIpLimits.doc(ipHash);
  const nowMs = Date.now();
  return db.runTransaction(async (tx) => {
    const current = await tx.get(ref);
    const data = current.data() || {};
    const start = typeof data.windowStartMs === "number" ?
      data.windowStartMs : 0;
    const activeWindow = nowMs - start < 60 * 60 * 1000;
    const count = activeWindow ? (data.count || 0) : 0;
    if (count >= 12) return false;
    tx.set(ref, {
      windowStartMs: activeWindow ? start : nowMs,
      count: count + 1,
      expiresAtMs: nowMs + 25 * 60 * 60 * 1000,
    });
    return true;
  });
};

exports.requestAdminPasswordRecovery = onCall({
  region: "us-central1",
  invoker: "public",
  secrets: [gmailSenderEmail, gmailAppPassword],
}, async (request) => {
  const username = request.data?.username;
  if (typeof username !== "string" ||
      !/^[a-z0-9_]{3,20}$/.test(username)) {
    throw new HttpsError("invalid-argument", "Invalid username.");
  }

  // No account details, email address, or role ever leave this endpoint.
  const allowedByIp = await checkRecoveryIpLimit(request);
  if (!allowedByIp) return recoveryGenericResponse;

  let target;
  try {
    target = await auth.getUserByEmail(
        `${username}@accounts.masjid-khalid.example`);
  } catch (error) {
    if (error.code !== "auth/user-not-found") {
      logger.error("Recovery account lookup failed", {
        code: error.code || "unknown",
      });
    }
    return recoveryGenericResponse;
  }

  const uid = target.uid;
  if (target.disabled || target.customClaims?.admin !== true) {
    return recoveryGenericResponse;
  }
  const [profile, record] = await Promise.all([
    db.collection("users").doc(uid).get(),
    recoveryRecords.doc(uid).get(),
  ]);
  const email = record.data()?.email;
  if (profile.data()?.role !== "admin" ||
      record.data()?.verified !== true ||
      typeof email !== "string") {
    return recoveryGenericResponse;
  }

  const nowMs = Date.now();
  const token = crypto.randomBytes(32).toString("hex");
  const limitRef = passwordRecoveryLimits.doc(uid);
  const tokenRef = passwordRecoveryTokens.doc(uid);
  const reserved = await db.runTransaction(async (tx) => {
    const previous = await tx.get(limitRef);
    const info = previous.data() || {};
    const last = info.lastSentAtMs || 0;
    if (nowMs - last < passwordRecoveryCooldownMs) return false;
    const dayWindow = typeof info.dayStartMs === "number" &&
        nowMs - info.dayStartMs < 24 * 60 * 60 * 1000;
    const count = dayWindow ? (info.dayCount || 0) : 0;
    if (count >= 4) return false;

    tx.set(limitRef, {
      lastSentAtMs: nowMs,
      dayStartMs: dayWindow ? info.dayStartMs : nowMs,
      dayCount: count + 1,
    });
    // A new request invalidates any old unused password-reset link.
    tx.set(tokenRef, {
      tokenHash: tokenFingerprint(token),
      emailHash: emailFingerprint(email),
      createdAtMs: nowMs,
      expiresAtMs: nowMs + passwordRecoveryLifetimeMs,
      consumed: false,
    });
    return true;
  });
  if (!reserved) return recoveryGenericResponse;

  const project = process.env.GCLOUD_PROJECT || "masjid-khalid-app";
  // Fragment is intentionally not sent in HTTP requests or server logs.
  // The browser will POST the token from the page, not via its URL.
  const resetUrl = `https://us-central1-${project}.cloudfunctions.net/` +
      "finishAdminPasswordRecovery" +
      `#uid=${encodeURIComponent(uid)}&token=${token}`;

  try {
    await sendGmail({
      to: email,
      subject: "رابط استعادة كلمة مرور مسؤول المسجد",
      text: "طلب استعادة كلمة المرور لحساب مسؤول مسجد خالد بن الوليد.\n" +
        "افتح الرابط خلال 15 دقيقة لتعيين كلمة مرور جديدة:\n\n" +
        resetUrl + "\n\n" +
        "إذا لم تطلب ذلك، تجاهل هذه الرسالة.",
    });
  } catch (error) {
    logger.error("Gmail SMTP password recovery email failed", {
      code: error.code || "unknown",
    });
  }
  return recoveryGenericResponse;
});

const adminResetPage = (nonce) => `<!doctype html>
<html lang="ar" dir="rtl"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>استعادة كلمة مرور المسؤول</title>
<style>
body{font:16px system-ui,sans-serif;background:#f9f6ef;color:#24221f;
max-width:420px;padding:18px;margin:8vh auto}
main{background:white;border-radius:16px;border:1px solid #e6dfd0;
padding:24px;box-shadow:0 2px 12px #0000000a}
h1{font-size:23px;margin:0 0 14px}label{display:block;margin:14px 0}
input{width:100%;box-sizing:border-box;font:inherit;padding:12px;
border:1px solid #b8ae9c;border-radius:8px;margin-top:7px}
button{font:inherit;background:#a96e09;color:white;border:0;
border-radius:9px;padding:13px;width:100%;cursor:pointer}
button:disabled{opacity:.55}p{line-height:1.6}#status{min-height:24px}
</style></head><body><main>
<h1>مسجد خالد بن الوليد</h1>
<p>تعيين كلمة مرور جديدة للمسؤول (12 حرفًا على الأقل).</p>
<form id="reset-form">
<label>كلمة المرور الجديدة
<input id="password" type="password" autocomplete="new-password"
minlength="12" maxlength="128" required></label>
<label>تأكيد كلمة المرور
<input id="confirm" type="password" autocomplete="new-password"
minlength="12" maxlength="128" required></label>
<button id="submit" type="submit">حفظ كلمة المرور الجديدة</button>
</form><p id="status" role="status" aria-live="polite"></p>
</main><script nonce="${nonce}">
(() => {
 const fragment = new URLSearchParams(location.hash.slice(1));
 const uid = fragment.get('uid');
 const token = fragment.get('token');
 history.replaceState(null, '', location.pathname);
 const form = document.getElementById('reset-form');
 const status = document.getElementById('status');
 const button = document.getElementById('submit');
 if (!uid || !token || !/^[a-f0-9]{64}$/.test(token)) {
   form.hidden = true;
   status.textContent = 'رابط الاستعادة غير صالح. اطلب رابطًا جديدًا.';
   return;
 }
 form.addEventListener('submit', async (event) => {
   event.preventDefault();
   const password = document.getElementById('password').value;
   const confirm = document.getElementById('confirm').value;
   if (password !== confirm) {
     status.textContent = 'كلمتا المرور غير متطابقتين.';
     return;
   }
   if (password.length < 12 || password.length > 128) {
     status.textContent = 'استخدم كلمة مرور من 12 إلى 128 حرفًا.';
     return;
   }
   button.disabled = true;
   status.textContent = 'جارٍ تغيير كلمة المرور...';
   try {
     const response = await fetch(location.pathname, {
       method: 'POST',
       headers: {'Content-Type': 'application/json'},
       body: JSON.stringify({uid, token, password}),
     });
     const body = await response.json();
     if (!response.ok || !body.success) {
       status.textContent = 'الرابط غير صالح أو منتهي الصلاحية. ' +
           'اطلب رابطًا جديدًا من التطبيق.';
       button.disabled = false;
       return;
     }
     form.hidden = true;
     status.textContent = 'تم تغيير كلمة المرور بنجاح. ' +
         'ارجع إلى التطبيق وسجّل الدخول بكلمة المرور الجديدة.';
   } catch (_) {
     status.textContent = 'تعذر الاتصال بالخادم. حاول مرة أخرى.';
     button.disabled = false;
   }
 });
})();
</script></body></html>`;

exports.finishAdminPasswordRecovery = onRequest({
  region: "us-central1",
  invoker: "public",
}, async (req, res) => {
  res.set("Cache-Control", "no-store, max-age=0");
  res.set("Referrer-Policy", "no-referrer");
  res.set("X-Content-Type-Options", "nosniff");
  res.set("X-Frame-Options", "DENY");

  if (req.method === "GET") {
    const nonce = crypto.randomBytes(16).toString("base64");
    res.set("Content-Security-Policy", "default-src 'none'; " +
        `script-src 'nonce-${nonce}'; style-src 'unsafe-inline'; ` +
        "connect-src 'self'; form-action 'none'; " +
        "base-uri 'none'; frame-ancestors 'none'");
    return res.type("html").status(200).send(adminResetPage(nonce));
  }
  if (req.method !== "POST") {
    return res.status(405).json({success: false});
  }

  // No CORS headers are enabled; only same-origin browser requests are
  // intended. No token is ever accepted from URL query parameters.
  const origin = req.get("origin");
  const project = process.env.GCLOUD_PROJECT || "masjid-khalid-app";
  const allowedOrigin = `https://us-central1-${project}.cloudfunctions.net`;
  if (origin && origin !== allowedOrigin) {
    return res.status(403).json({success: false});
  }
  if (!req.is("application/json")) {
    return res.status(415).json({success: false});
  }
  const allowedByIp = await checkRecoveryIpLimit({rawRequest: req});
  if (!allowedByIp) {
    return res.status(429).json({success: false});
  }
  const {uid, token, password} = req.body || {};
  if (typeof uid !== "string" || !/^[a-zA-Z0-9_-]{1,128}$/.test(uid) ||
      typeof token !== "string" || !/^[a-f0-9]{64}$/.test(token) ||
      typeof password !== "string" || password.length < 12 ||
      password.length > 128) {
    return res.status(400).json({success: false});
  }

  const tokenRef = passwordRecoveryTokens.doc(uid);
  const profileRef = db.collection("users").doc(uid);
  const verifiedRef = recoveryRecords.doc(uid);
  try {
    // Claims must still be admin NOW, even if the email was verified earlier.
    const current = await auth.getUser(uid);
    if (current.disabled || current.customClaims?.admin !== true) {
      return res.status(400).json({success: false});
    }

    const submittedHash = tokenFingerprint(token);
    await db.runTransaction(async (tx) => {
      const [saved, profile, recovery] = await Promise.all([
        tx.get(tokenRef), tx.get(profileRef), tx.get(verifiedRef),
      ]);
      const info = saved.data();
      const verifiedEmail = recovery.data()?.email;
      const expectedHash = info?.tokenHash;
      if (!info || info.consumed === true ||
          info.expiresAtMs <= Date.now() ||
          typeof expectedHash !== "string" ||
          !/^[a-f0-9]{64}$/.test(expectedHash) ||
          !crypto.timingSafeEqual(
              Buffer.from(expectedHash, "hex"),
              Buffer.from(submittedHash, "hex")) ||
          profile.data()?.role !== "admin" ||
          recovery.data()?.verified !== true ||
          typeof verifiedEmail !== "string" ||
          info.emailHash !== emailFingerprint(verifiedEmail)) {
        throw new Error("invalid-recovery-token");
      }
      // Consumed before updating Auth; cannot reuse or race this token.
      tx.update(tokenRef, {consumed: true, consumedAtMs: Date.now()});
    });

    // Prevent a token issued to a formerly-active admin being used after
    // demotion (including demotion after the Firestore transaction).
    const latest = await auth.getUser(uid);
    const latestProfile = await profileRef.get();
    if (latest.disabled || latest.customClaims?.admin !== true ||
        latestProfile.data()?.role !== "admin") {
      return res.status(400).json({success: false});
    }
    await auth.updateUser(uid, {password: password});
    await auth.revokeRefreshTokens(uid);
    logger.info("Admin password recovered", {uid});
    return res.status(200).json({success: true});
  } catch (error) {
    logger.warn("Admin password recovery was rejected or failed", {
      code: error.code || "invalid-or-expired",
    });
    return res.status(400).json({success: false});
  }
});

// Expiring news: announcements without expiresAt remain published forever.
// The UI hides expired items immediately, while this job deletes expired
// Firestore documents at most a few minutes later. In each transaction we
// re-read the document so a manager's recent edit is not accidentally lost.
exports.deleteExpiredAnnouncements = onSchedule({
  schedule: "every 5 minutes",
  region: "us-central1",
  timeZone: "Etc/UTC",
  maxInstances: 1,
}, async () => {
  const now = Timestamp.now();
  const expired = await db.collection("announcements")
      .where("expiresAt", "<=", now)
      .orderBy("expiresAt")
      .limit(100).get();
  let removed = 0;
  for (const snapshot of expired.docs) {
    try {
      const didDelete = await db.runTransaction(async (tx) => {
        const current = await tx.get(snapshot.ref);
        if (!current.exists) return false;
        const expiration = current.get("expiresAt");
        if (!(expiration instanceof Timestamp) ||
            expiration.toMillis() > Date.now()) {
          return false;
        }
        tx.delete(snapshot.ref);
        return true;
      });
      if (didDelete) removed += 1;
    } catch (error) {
      logger.error("Could not remove expired announcement", {
        announcementId: snapshot.id,
        code: error.code || "unknown",
      });
    }
  }
  logger.info("Expired announcement cleanup completed", {
    scanned: expired.size,
    removed: removed,
  });
});

// Clean Storage on ANY announcement deletion (manual or scheduled).
// Missing files are harmless; with retry enabled, transient errors are
// retried instead of silently leaving an orphaned image.
exports.cleanupDeletedAnnouncementImage = onDocumentDeleted({
  document: "announcements/{announcementId}",
  region: "me-west1", // Same region as this project's Firestore database.
  retry: true,
  maxInstances: 3,
}, async (event) => {
  const id = event.params.announcementId;
  const path = event.data?.get("imagePath");
  if (typeof path !== "string" ||
      !path.startsWith(`announcements/${id}/images/`)) {
    return;
  }
  try {
    await getStorage().bucket("masjid-khalid-app.firebasestorage.app")
        .file(path).delete({ignoreNotFound: true});
  } catch (error) {
    logger.error("Failed to delete announcement image", {
      announcementId: id,
      code: error.code || "unknown",
    });
    throw error;
  }
});

// Public course enrollment and strictly admin-only course administration.
Object.assign(exports, require("./courses").makeCourseFunctions({
  db, requireAdmin,
}));

// Public excursions/activity enrollment; admin requires verified access.
Object.assign(exports, require("./activities").makeActivityFunctions({
  db, requireAdmin,
}));

// Homework publishing and private drafts, without public-user accounts.
Object.assign(exports, require("./homework").makeHomeworkFunctions({
  db, requireAdmin,
}));

// Automatic VISIBILITY expiration, never destructive deletion: preserves
// participation records and permits the admin to re-publish later.
exports.autoHideActivities = onSchedule({
  schedule: "every 15 minutes",
  region: "me-west1",
  maxInstances: 1,
}, async () => {
  const activities = db.collection("activities");
  let hidden = 0;
  for (let pass = 0; pass < 10; pass++) {
    const due = await activities.where("hideAt", "<=", Timestamp.now())
        .limit(200).get();
    if (due.empty) break;
    const batch = db.batch();
    for (const doc of due.docs) {
      batch.update(doc.ref, {hideAt: null, isVisible: false,
        autoHiddenAt: FieldValue.serverTimestamp()});
      hidden++;
    }
    await batch.commit();
    if (due.size < 200) break;
  }
  if (hidden) logger.info("Activities hidden at deadline", {hidden});
});


// Server-side publication notifications. Only a newly PUBLIC item triggers a
// broadcast. Edits and hidden drafts do not notify devices.
Object.assign(exports, require("./public_notifications")
    .makePublicNotificationFunctions({db}));
