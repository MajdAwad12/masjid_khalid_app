"use strict";
/* eslint-disable require-jsdoc */
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentCreated, onDocumentUpdated} =
    require("firebase-functions/v2/firestore");
const {FieldPath, FieldValue} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

const {changeSeats} = require("./registration_capacity");
const counted = ["pending", "accepted", "rejected"];
const finalStates = ["accepted", "rejected", "withdrawn"];
const pageSize = 50;
const digest = (value) => crypto.createHash("sha256").update(value)
    .digest("hex");

function verificationReference(keyHash) {
  return digest("staff-reference:" + keyHash).slice(0, 12);
}

function newDecision() {
  return {notificationState: "ready", notificationAttempts: 0,
    notificationAttemptId: null};
}

function canNotify(doc) {
  return doc.exists && Boolean(doc.get("deviceKeyHash")) &&
    finalStates.includes(doc.get("status")) &&
    (doc.get("status") !== "withdrawn" || doc.get("deviceVerified") === true) &&
    (doc.get("decidedBy") !== "automatic" ||
    doc.get("notifyAutomatic") === true);
}

// Reserve a specific decision before contacting FCM. An ambiguous hand-off
// must not be replayed: status remains available through verified lookup.
async function deliverDecision(db, ref) {
  const claim = await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!canNotify(doc)) return null;
    const state = doc.get("notificationState");
    if (state === "sent") return {sent: true};
    if (state === "sending") {
      // Also covers in-flight decisions written by the previous version.
      const since = doc.get("notificationStartedMs") || 0;
      if (Date.now() - since > 120000) {
        tx.update(ref, {notificationState: "uncertain"});
      }
      return null;
    }
    if (state === "reserved" &&
        Date.now() - doc.get("notificationStartedMs") < 120000) return null;
    if (!["reserved", "ready", "failed", "no-token", "not-sent"]
        .includes(state)) {
      return null;
    }
    const token = doc.get("fcmToken");
    if (!token) {
      if (state !== "no-token") tx.update(ref, {notificationState: "no-token"});
      return null;
    }
    const attempts = doc.get("notificationAttempts") || 0;
    if (attempts >= 3) {
      if (state === "reserved") tx.update(ref, {notificationState: "failed"});
      return null;
    }
    const attemptId = crypto.randomUUID();
    tx.update(ref, {notificationAttemptId: attemptId,
      notificationAttempts: attempts + 1, notificationState: "reserved",
      notificationStartedMs: Date.now()});
    return {attemptId, token};
  });
  if (!claim || claim.sent) return Boolean(claim?.sent);
  const dispatch = await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists || doc.get("notificationState") !== "reserved" ||
        doc.get("notificationAttemptId") !== claim.attemptId) return false;
    if (!canNotify(doc) ||
        doc.get("fcmToken") !== claim.token) {
      tx.update(ref, {notificationState: "ready"});
      return false;
    }
    tx.update(ref, {notificationState: "sending"});
    return true;
  });
  if (!dispatch) return false;
  let state = "sent";
  let invalid = false;
  try {
    await getMessaging().send({token: claim.token,
      notification: {title: "لديك تحديث جديد",
        body: "افتح التطبيق للاطلاع على التحديث."},
      data: {type: "registration_update"},
      android: {priority: "high"}, apns: {payload: {aps: {sound: "default"}}},
    });
  } catch (error) {
    invalid = ["messaging/registration-token-not-registered",
      "messaging/invalid-registration-token"].includes(error.code);
    if (invalid) state = "no-token";
    else if (["messaging/server-unavailable", "messaging/quota-exceeded"]
        .includes(error.code)) state = "failed";
    else state = "uncertain";
  }
  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists || doc.get("notificationAttemptId") !== claim.attemptId) {
      return;
    }
    const fields = {notificationState: state};
    if (state === "sent") fields.notifiedAt = FieldValue.serverTimestamp();
    if (invalid) {
      fields.invalidTokenHash = digest(claim.token);
      if (doc.get("fcmToken") === claim.token) {
        fields.fcmToken = null;
      } else if (doc.get("fcmToken")) {
        // A newer destination arrived while FCM rejected the old one.
        Object.assign(fields, newDecision());
      }
    }
    tx.update(ref, fields);
  });
  return state === "sent";
}

// The durable decision update also wakes a worker if the callable exited
// before handing the message to FCM. Every retry reads the current row.
async function recover(db, after) {
  if (!after || !canNotify(after) || !after.get("fcmToken") ||
        !["ready", "reserved", "failed"].includes(
            after.get("notificationState"))) return;
  await deliverDecision(db, after.ref);
  const current = await after.ref.get();
  if (!current.exists || !current.get("fcmToken") ||
        !canNotify(current)) return;
  const state = current.get("notificationState");
  if ((["ready", "reserved", "failed"].includes(state) &&
        (current.get("notificationAttempts") || 0) < 3) ||
        state === "sending") {
    // Eventarc backs off. Expired post-dispatch attempts become uncertain.
    throw new Error("Registration delivery pending.");
  }
}

function workerOptions(collection) {
  return {document: collection + "/{registrationId}", region: "me-west1",
    retry: true, maxInstances: 3};
}

function recoverDecisionUpdates(db, collection) {
  return onDocumentUpdated(workerOptions(collection),
      (event) => recover(db, event.data?.after));
}

function recoverDecisionCreates(db, collection) {
  return onDocumentCreated(workerOptions(collection),
      (event) => recover(db, event.data));
}

async function retryDecision(db, ref, parentField, parentId) {
  await db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    if (!doc.exists || doc.get(parentField) !== parentId ||
        !finalStates.includes(doc.get("status"))) {
      throw new HttpsError("failed-precondition", "No final decision.");
    }
    const last = doc.get("lastResendAt");
    if (last && Date.now() - last.toMillis() < 60000) {
      throw new HttpsError("resource-exhausted", "Retry later.");
    }
    tx.update(ref, {lastResendAt: FieldValue.serverTimestamp()});
  });
  return deliverDecision(db, ref);
}

async function verifiedPage(db, collection, keyHash, cursor) {
  let query = db.collection(collection).where("deviceKeyHash", "==", keyHash)
      .where("deviceVerified", "==", true).orderBy(FieldPath.documentId());
  if (cursor != null) {
    if (typeof cursor !== "string" || !/^[a-f0-9]{64}$/.test(cursor)) {
      throw new HttpsError("invalid-argument", "Invalid page cursor.");
    }
    query = query.startAfter(cursor);
  }
  const {docs} = await query.limit(pageSize).get();
  return {docs, nextCursor: docs.length === pageSize ? docs.at(-1).id : null};
}

async function syncPage(db, collection, keyHash, token) {
  const sync = async (doc) => {
    await db.runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      if (!fresh.exists || fresh.get("deviceKeyHash") !== keyHash ||
          fresh.get("invalidTokenHash") === digest(token)) return;
      if (fresh.get("fcmToken") === token) return;
      const fields = {fcmToken: token};
      if (["failed", "no-token"].includes(fresh.get("notificationState"))) {
        Object.assign(fields, newDecision());
      }
      tx.update(doc.ref, fields);
    });
    if (canNotify(doc) && doc.get("notificationState") !== "sent") {
      await deliverDecision(db, doc.ref);
    }
  };
  const query = db.collection(collection).where("deviceKeyHash", "==", keyHash)
      .orderBy(FieldPath.documentId()).limit(pageSize);
  let cursor = null;
  for (;;) {
    const page = await (cursor ? query.startAfter(cursor) : query).get();
    for (let offset = 0; offset < page.docs.length; offset += 5) {
      await Promise.all(page.docs.slice(offset, offset + 5).map(sync));
    }
    if (page.docs.length < pageSize) break;
    cursor = page.docs.at(-1).id;
  }
  return {synced: true};
}

function staffRegistrationAction({db, requireAdmin, kind, parentId, regId}) {
  return onCall({region: "us-central1", maxInstances: 10}, async (req) => {
    const uid = await requireAdmin(req);
    const data = req.data || {};
    const field = kind + "Id";
    const id = parentId(data[field]);
    const parent = db.collection(kind === "course" ? "courses" : "activities")
        .doc(id);
    const ref = db.collection(kind + "_registrations")
        .doc(regId(data.registrationId));
    const action = data.action;
    if (!["prepare", "verify", "withdraw", "erase"].includes(action)) {
      throw new HttpsError("invalid-argument", "Invalid action.");
    }
    if (action !== "prepare" && (data.identityChecked !== true ||
        typeof data.generation !== "string" || !data.generation)) {
      throw new HttpsError("failed-precondition", "Verification required.");
    }
    const result = await db.runTransaction(async (tx) => {
      const [doc, program] = await Promise.all([tx.get(ref), tx.get(parent)]);
      if (!doc.exists && action === "erase") return {changed: false};
      if (!doc.exists || doc.get(field) !== id || !program.exists) {
        throw new HttpsError("not-found", "Registration unavailable.");
      }
      const generation = doc.createTime.seconds + ":" +
          doc.createTime.nanoseconds;
      if (action === "prepare") return {generation};
      if (data.generation !== generation) {
        throw new HttpsError("failed-precondition", "Registration changed.");
      }
      const old = doc.get("status");
      if (action === "erase") {
        await changeSeats(tx, program, old, null, {recount: true});
        tx.delete(ref);
        return {changed: true};
      }
      if (action === "withdraw") {
        if (old === "withdrawn") return {changed: false};
        if (counted.includes(old)) await changeSeats(tx, program, old, null);
        tx.update(ref, {status: "withdrawn", decidedBy: uid,
          decidedAt: FieldValue.serverTimestamp(), ...newDecision()});
        return {changed: true};
      }
      const key = doc.get("deviceKeyHash");
      if (!key || data.reference !== verificationReference(key)) {
        throw new HttpsError("failed-precondition", "Device check failed.");
      }
      if (doc.get("deviceVerified") === true) return {changed: false};
      const values = {deviceVerified: true, verifiedBy: uid,
        verifiedAt: FieldValue.serverTimestamp()};
      if (old === "unverified") {
        const deadlines = kind === "course" ? ["startAt"] :
          ["departureAt", "hideAt"];
        if (program.get("isVisible") !== true ||
            program.get("isOpen") !== true || deadlines.some((name) =>
          program.get(name)?.toMillis?.() <= Date.now())) {
          throw new HttpsError("failed-precondition", "Registration closed.");
        }
        const automatic = program.get("registrationMode") === "automatic";
        values.status = automatic ? "accepted" : "pending";
        if (automatic) {
          Object.assign(values, newDecision(), {notifyAutomatic: true});
          values.decidedBy = "automatic";
          values.decidedAt = FieldValue.serverTimestamp();
        }
        await changeSeats(tx, program, null, values.status);
      }
      tx.update(ref, values);
      return {changed: true};
    });
    if (action === "withdraw" && result.changed) await deliverDecision(db, ref);
    return result;
  });
}

module.exports = {staffRegistrationAction, verificationReference, verifiedPage,
  syncPage, newDecision, deliverDecision, retryDecision,
  recoverDecisionUpdates, recoverDecisionCreates};
