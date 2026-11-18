"use strict";

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {setGlobalOptions} = require("firebase-functions/v2");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");
const {getFirestore} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

initializeApp();
setGlobalOptions({maxInstances: 10});

const auth = getAuth();
const db = getFirestore();

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
