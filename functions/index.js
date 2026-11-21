"use strict";

const {onCall, onRequest, HttpsError} = require("firebase-functions/v2/https");
const crypto = require("node:crypto");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");
const {defineSecret} = require("firebase-functions/params");
const nodemailer = require("nodemailer");

initializeApp();
setGlobalOptions({maxInstances: 10});

const auth = getAuth();
const db = getFirestore();

const gmailSenderEmail = defineSecret("GMAIL_SENDER_EMAIL");
const gmailAppPassword = defineSecret("GMAIL_APP_PASSWORD");
const resendTestEmail = defineSecret("RESEND_TEST_EMAIL");

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

// Change the user's role in Authentication and Firestore.
exports.changeUserRole = onCall(async (request) => {
  const adminUid = await requireAdmin(request);
  const targetUid = validateUid(request.data?.targetUid);
  const role = request.data?.role;
  if (role !== "admin" && role !== "user") {
    throw new HttpsError("invalid-argument", "Invalid role.");
  }
  if (targetUid === adminUid && role === "user") {
    throw new HttpsError(
        "failed-precondition",
        "You cannot remove your own admin role.",
    );
  }

  const target = await findUser(targetUid);
  const profileRef = db.collection("users").doc(targetUid);
  const profile = await profileRef.get();
  if (!profile.exists) {
    throw new HttpsError("not-found", "User profile not found.");
  }

  const previousClaims = {...(target.customClaims || {})};
  const newClaims = {...previousClaims};
  if (role === "admin") {
    newClaims.admin = true;
  } else {
    delete newClaims.admin;
  }

  await auth.setCustomUserClaims(targetUid, newClaims);
  try {
    await profileRef.update({role: role});
  } catch (error) {
    // Attempt to restore the previous claims if the profile update fails.
    try {
      await auth.setCustomUserClaims(targetUid, previousClaims);
    } catch (rollbackError) {
      logger.error("Role rollback failed", {
        targetUid: targetUid,
        error: rollbackError,
      });
    }
    logger.error("Role synchronization failed", {targetUid: targetUid});
    throw new HttpsError(
        "internal",
        "Could not synchronize user permissions.",
    );
  }

  logger.info("User role changed", {
    adminUid: adminUid,
    targetUid: targetUid,
    role: role,
  });
  return {success: true, role: role};
});

// Reset a regular user's password with admin approval and a 60-second cooldown.
exports.resetUserPassword = onCall(async (request) => {
  const adminUid = await requireAdmin(request);

  const authTime = Number(request.auth.token.auth_time);
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!Number.isFinite(authTime) ||
      authTime <= 0 ||
      nowSeconds - authTime > 600 ||
      authTime > nowSeconds + 60) {
    throw new HttpsError(
        "failed-precondition",
        "Administrator must sign in again before resetting passwords.",
    );
  }

  const targetUid = validateUid(request.data?.targetUid);
  const newPassword = request.data?.newPassword;
  const identityVerified = request.data?.identityVerified;
  if (identityVerified !== true) {
    throw new HttpsError(
        "failed-precondition",
        "Verify the user's identity before resetting.",
    );
  }
  if (typeof newPassword !== "string" ||
      newPassword.length < 12 ||
      newPassword.length > 128) {
    throw new HttpsError(
        "invalid-argument",
        "Password must contain 12-128 characters.",
    );
  }

  const target = await findUser(targetUid);
  const profile = await db.collection("users").doc(targetUid).get();
  if (!profile.exists) {
    throw new HttpsError("not-found", "User profile not found.");
  }
  if (target.customClaims?.admin === true ||
      profile.data()?.role !== "user") {
    throw new HttpsError(
        "permission-denied",
        "Only regular user passwords can be reset.",
    );
  }

  const cooldownRef = db
      .collection("security_password_reset_limits")
      .doc(targetUid);
  const nowMs = Date.now();
  const cooldownMs = 60 * 1000;

  // Persist the cooldown, which the Flutter UI also reads for its timer.
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(cooldownRef);
    const lastAttempt = snapshot.data()?.lastAttemptAtMs;
    if (typeof lastAttempt === "number" &&
        nowMs - lastAttempt < cooldownMs) {
      throw new HttpsError(
          "resource-exhausted",
          "Please wait before resetting this user's password again.",
      );
    }

    transaction.set(cooldownRef, {
      lastAttemptAtMs: nowMs,
      adminUid: adminUid,
    });
  });

  let passwordChanged = false;
  try {
    await auth.updateUser(targetUid, {password: newPassword});
    passwordChanged = true;
    await auth.revokeRefreshTokens(targetUid);
  } catch (error) {
    logger.error("Password reset failed or partially completed", {
      adminUid: adminUid,
      targetUid: targetUid,
      passwordChanged: passwordChanged,
    });
    throw new HttpsError("internal", "Could not complete password reset.");
  }

  logger.info("User password reset", {
    adminUid: adminUid,
    targetUid: targetUid,
  });
  return {success: true};
});

// TEMPORARY DEVELOPMENT TEST. Remove this callable before production.
// Only a signed-in, active admin can send to the fixed test mailbox.
exports.sendRecoveryTestEmail = onCall({
  region: "us-central1",
  // IAM lets Firebase SDK requests through; requireAdmin checks identity.
  invoker: "public",
  secrets: [gmailSenderEmail, gmailAppPassword, resendTestEmail],
}, async (request) => {
  const adminUid = await requireAdmin(request);
  const destination = resendTestEmail.value().trim();
  if (!destination || !destination.includes("@")) {
    throw new HttpsError("failed-precondition", "Missing test recipient.");
  }

  // One request per admin every two minutes. Only server code writes this.
  const limitRef = db.collection("security_email_test_limits").doc(adminUid);
  const nowMs = Date.now();
  await db.runTransaction(async (transaction) => {
    const previous = await transaction.get(limitRef);
    const last = previous.data()?.lastAttemptAtMs;
    if (typeof last === "number" && nowMs - last < 120000) {
      throw new HttpsError("resource-exhausted", "Try again in two minutes.");
    }
    transaction.set(limitRef, {lastAttemptAtMs: nowMs});
  });

  try {
    await sendGmail({
      to: destination,
      subject: "Masjid Khalid - Email Delivery Test",
      text: "This is a test email from Firebase Cloud Functions. " +
        "No password has been changed.",
    });
  } catch (error) {
    logger.error("Gmail SMTP test email failed", {
      adminUid: adminUid,
      code: error.code || "unknown",
    });
    throw new HttpsError("unavailable", "Test email could not be sent.");
  }
  logger.info("Gmail test email submitted", {adminUid: adminUid});
  return {success: true};
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
