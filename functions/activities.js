"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

// Activities and excursions. Public users have no Firebase Auth account;
// only its own registrations are accessible with the installation secret.
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {onDocumentDeleted} = require("firebase-functions/v2/firestore");
const {getStorage} = require("firebase-admin/storage");
const {deleteLinkedRegistrations} = require("./deletion_cleanup");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {staffRegistrationAction, verificationReference, verifiedPage, syncPage,
  newDecision, deliverDecision, retryDecision, recoverDecisionUpdates,
  recoverDecisionCreates} =
    require("./registration_privacy");
const {countsRef, changeSeats, unverifiedDevice, initialRegistration,
  installationAllowance} =
    require("./registration_capacity");
const logger = require("firebase-functions/logger");
const states = new Set(["pending", "accepted", "rejected"]);
const hash = (text) => crypto.createHash("sha256").update(text).digest("hex");
const requireId = (v) => {
  if (typeof v !== "string" || !/^[a-zA-Z0-9]{10,40}$/.test(v)) {
    throw new HttpsError("invalid-argument", "Invalid activity ID.");
  }
  return v;
};
const requireRegId = (v) => {
  if (typeof v !== "string" || !/^[a-f0-9]{64}$/.test(v)) {
    throw new HttpsError("invalid-argument", "Invalid registration ID.");
  }
  return v;
};
const textField = (value, name, max, min = 0) => {
  if (value == null && min === 0) return "";
  if (typeof value !== "string" || value.trim().length < min ||
      value.trim().length > max) {
    throw new HttpsError("invalid-argument", `Invalid ${name}.`);
  }
  return value.trim();
};
const dateField = (value) => {
  if (value == null) return null;
  if (!Number.isSafeInteger(value) || value < Date.UTC(2020, 0, 1) ||
      value > Date.UTC(2100, 0, 1)) {
    throw new HttpsError("invalid-argument", "Invalid date.");
  }
  return Timestamp.fromMillis(value);
};
const deviceHash = (key) => {
  if (typeof key !== "string" || !/^[a-f0-9]{64}$/.test(key)) {
    throw new HttpsError("invalid-argument", "Invalid installation key.");
  }
  return hash(`activity-installation\0${key}`);
};
const tokenField = (v) => {
  if (v == null || v === "") return null;
  if (typeof v !== "string" || v.length < 20 || v.length > 4096) {
    throw new HttpsError("invalid-argument", "Invalid FCM token.");
  }
  return v;
};
const normalizedName = (v) => v.normalize("NFKC").trim()
    .replace(/\s+/gu, " ").toLowerCase();
const normalizedPhone = (v) => {
  if (typeof v !== "string" || !/^[+\d\s()-]{8,32}$/.test(v)) {
    throw new HttpsError("invalid-argument", "Invalid phone.");
  }
  let p = v.replace(/\D/g, "");
  if (p.startsWith("00972")) p = p.slice(2);
  if (p.startsWith("9720")) p = `972${p.slice(4)}`;
  if (p.startsWith("0") && p.length === 10) p = `972${p.slice(1)}`;
  if (p.length < 8 || p.length > 15) {
    throw new HttpsError("invalid-argument", "Invalid phone.");
  }
  return p;
};
const personId = (id, phone, name) => hash(
    `activity-registration\0${id}\0${phone}\0${normalizedName(name)}`);

const parseActivity = (d, id) => {
  const title = textField(d.title, "title", 100, 1);
  if (!["activity", "trip"].includes(d.kind)) {
    throw new HttpsError("invalid-argument", "Invalid activity kind.");
  }
  const capacity = d.capacity == null || d.capacity === "" ? null : d.capacity;
  if (capacity !== null && (!Number.isInteger(capacity) ||
      capacity < 1 || capacity > 2000)) {
    throw new HttpsError("invalid-argument", "Invalid capacity.");
  }
  if (!["automatic", "approval"].includes(d.registrationMode) ||
      typeof d.isOpen !== "boolean" || typeof d.isVisible !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid settings.");
  }
  const departureAt = dateField(d.departureAtMs);
  const returnAt = dateField(d.returnAtMs);
  const hideAt = dateField(d.hideAtMs);
  if (departureAt && returnAt && returnAt.toMillis() < departureAt.toMillis()) {
    throw new HttpsError("invalid-argument", "Return is before departure.");
  }
  const imagePath = textField(d.imagePath, "imagePath", 240);
  if (imagePath !== "" && !new RegExp(
      `^activities/${id}/images/[a-zA-Z0-9_-]{8,90}\\.(jpg|png|webp)$`)
      .test(imagePath)) {
    throw new HttpsError("invalid-argument", "Invalid image path.");
  }
  return {
    title, kind: d.kind,
    description: textField(d.description, "description", 6000),
    organizer: textField(d.organizer, "organizer", 100),
    location: textField(d.location, "location", 160),
    departureAt, returnAt,
    hideAt, capacity, imagePath,
    registrationMode: d.registrationMode,
    isOpen: d.isOpen,
    isVisible: d.isVisible && (!hideAt || hideAt.toMillis() > Date.now()),
  };
};

async function rateLimit(db, req, credentialHash) {
  const ip = req.rawRequest?.ip;
  if (typeof ip !== "string" || ip.length < 2) {
    throw new HttpsError("unavailable", "Cannot verify request source.");
  }
  const hour = Math.floor(Date.now() / 3600000);
  const rules = [
    {id: hash(`act-ip\0${ip}\0${hour}`), max: 60},
    {id: hash(`act-device\0${credentialHash}\0${hour}`),
      max: installationAllowance.activity},
  ];
  const refs = rules.map((rule) => db.collection(
      "security_activity_limits").doc(rule.id));
  await db.runTransaction(async (tx) => {
    const docs = await Promise.all(refs.map((ref) => tx.get(ref)));
    for (let i = 0; i < rules.length; i++) {
      if ((Number(docs[i].get("count")) || 0) >= rules[i].max) {
        throw new HttpsError("resource-exhausted", "Too many attempts.");
      }
    }
    refs.forEach((ref, i) => tx.set(ref, {
      count: (Number(docs[i].get("count")) || 0) + 1,
      expiresAt: Timestamp.fromMillis((hour + 2) * 3600000),
    }));
  });
}

function makeActivityFunctions({db, requireAdmin}) {
  const activities = db.collection("activities");
  const registrations = db.collection("activity_registrations");
  return {
    notifyAutomaticActivityDecision: recoverDecisionCreates(db,
        "activity_registrations"),
    recoverActivityDecisionDelivery: recoverDecisionUpdates(db,
        "activity_registrations"),
    manageActivityRegistration: staffRegistrationAction({db, requireAdmin,
      kind: "activity", parentId: requireId, regId: requireRegId,
    }),
    saveActivity: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          const uid = await requireAdmin(req);
          const id = requireId(req.data?.activityId);
          const item = parseActivity(req.data || {}, id);
          const ref = activities.doc(id);
          await db.runTransaction(async (tx) => {
            const existing = await tx.get(ref);
            if (existing.exists) {
              tx.update(ref, {...item, updatedBy: uid,
                updatedAt: FieldValue.serverTimestamp()});
            } else {
              tx.create(ref, {...item, createdBy: uid,
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp()});
            }
          });
          return {activityId: id};
        }),
    // Deleting the parent document makes enrollment impossible immediately.
    // The deletion trigger below cleans up the separately stored registrations
    // and the image after the card disappears from users' screens.
    deleteActivity: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          await requireAdmin(req);
          const id = requireId(req.data?.activityId);
          const ref = activities.doc(id);
          await db.runTransaction(async (tx) => {
            const activity = await tx.get(ref);
            if (!activity.exists) {
              throw new HttpsError("not-found", "Activity not found.");
            }
            tx.delete(countsRef(db, "activity", ref.id));
            tx.delete(ref);
          });
          return {deleted: true};
        }),

    // Idempotent and retryable even if registration cleanup or Storage fails.
    cleanupDeletedActivityAssets: onDocumentDeleted({
      document: "activities/{activityId}",
      region: "me-west1",
      retry: true,
      maxInstances: 3,
    }, async (event) => {
      const id = event.params.activityId;
      const removed = await deleteLinkedRegistrations(db,
          "activity_registrations", "activityId", id);
      const path = event.data?.get("imagePath");
      const ownedPrefix = `activities/${id}/images/`;
      const filename = typeof path === "string" &&
          path.startsWith(ownedPrefix) ? path.substring(ownedPrefix.length) :
          "";
      if (/^[a-zA-Z0-9_-]{8,90}\.(jpg|png|webp)$/.test(filename)) {
        await getStorage().bucket("masjid-khalid-app.firebasestorage.app")
            .file(path).delete({ignoreNotFound: true});
      }
      logger.info("Deleted activity assets", {activityId: id, removed});
    }),

    registerForActivity: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          const d = req.data || {};
          const id = requireId(d.activityId);
          const fullName = textField(d.fullName, "fullName", 80, 3);
          const phone = normalizedPhone(d.phone);
          const hashKey = deviceHash(d.deviceKey);
          const fcmToken = tokenField(d.fcmToken);
          await rateLimit(db, req, hashKey);
          const ref = registrations.doc(personId(id, phone, fullName));
          const actRef = activities.doc(id);
          return db.runTransaction(async (tx) => {
            const [act, existing] = await Promise.all([
              tx.get(actRef), tx.get(ref),
            ]);

            if (!act.exists || act.get("isVisible") !== true ||
                act.get("isOpen") !== true ||
                (act.get("hideAt") instanceof Timestamp &&
                  act.get("hideAt").toMillis() <= Date.now()) ||
                (act.get("departureAt") instanceof Timestamp &&
                  act.get("departureAt").toMillis() <= Date.now())) {
              throw new HttpsError(
                  "failed-precondition", "Registration closed.");
            }
            if (existing.exists) return {status: "submitted"};
            const status = act.get("registrationMode") === "automatic" ?
              "accepted" : "pending";
            if (!await changeSeats(tx, act, null, status,
                {device: hashKey, publicSubmission: true})) {
              return {status: "submitted"};
            }
            tx.create(ref, {activityId: id,
              activityTitle: act.get("title") || "", fullName, phone,
              deviceKeyHash: hashKey, fcmToken,
              ...initialRegistration(status), source: "public",
              createdAt: FieldValue.serverTimestamp(),
            });
            return {status: "submitted"};
          });
        }),
    adminAddActivityParticipant: onCall({region: "us-central1",
      maxInstances: 10}, async (req) => {
      const uid = await requireAdmin(req);
      const id = requireId(req.data?.activityId);
      const name = textField(req.data?.fullName, "fullName", 80, 1);
      const phone = req.data?.phone ? normalizedPhone(req.data.phone) : null;
      const registrationId = phone ? personId(id, phone, name) :
        hash(`activity-manual\0${id}\0` +
          crypto.randomBytes(32).toString("hex"));
      const regRef = registrations.doc(registrationId);
      const actRef = activities.doc(id);
      const result = await db.runTransaction(async (tx) => {
        const [act, old] = await Promise.all([tx.get(actRef), tx.get(regRef)]);
        if (!act.exists) throw new HttpsError("not-found", "Activity missing.");
        const before = old.exists ? old.get("status") : null;
        if (before === "accepted") {
          throw new HttpsError("already-exists", "Already accepted.");
        }
        await changeSeats(tx, act, before, "accepted",
            {device: unverifiedDevice(old)});
        if (old.exists) {
          tx.update(regRef, {status: "accepted", decidedBy: uid,
            decidedAt: FieldValue.serverTimestamp(),
            activityTitle: act.get("title") || "", ...newDecision()});
        } else {
          tx.create(regRef, {activityId: id,
            activityTitle: act.get("title") || "", fullName: name,
            phone, status: "accepted", source: "admin",
            deviceKeyHash: null, fcmToken: null,
            notificationState: "no-token", decidedBy: uid,
            decidedAt: FieldValue.serverTimestamp(),
            createdAt: FieldValue.serverTimestamp()});
        }
        return {previous: old.exists ? old.data() : null};
      });
      const notified = Boolean(result.previous) &&
          await deliverDecision(db, regRef);
      return {notified};
    }),
    decideActivityRegistration: onCall({region: "us-central1",
      maxInstances: 10}, async (req) => {
      const uid = await requireAdmin(req);
      const id = requireId(req.data?.activityId);
      const regId = requireRegId(req.data?.registrationId);
      const status = req.data?.decision;
      if (!["accepted", "rejected"].includes(status)) {
        throw new HttpsError("invalid-argument", "Invalid decision.");
      }
      const actRef = activities.doc(id);
      const regRef = registrations.doc(regId);
      const result = await db.runTransaction(async (tx) => {
        const [act, reg] = await Promise.all([tx.get(actRef), tx.get(regRef)]);
        if (!act.exists || !reg.exists || reg.get("activityId") !== id) {
          throw new HttpsError("not-found", "Registration not found.");
        }
        const old = reg.get("status");
        if (!states.has(old)) {
          throw new HttpsError("failed-precondition", "Invalid state.");
        }
        if (old === status) return {changed: false, reg: reg.data()};
        await changeSeats(tx, act, old, status,
            {device: unverifiedDevice(reg)});
        tx.update(regRef, {status, decidedBy: uid,
          decidedAt: FieldValue.serverTimestamp(),
          ...newDecision()});
        return {changed: true, reg: {...reg.data(), status}};
      });
      const notified = result.changed && await deliverDecision(db, regRef);
      return {changed: result.changed, notified};
    }),
    myActivityRegistrations: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          const keyHash = deviceHash(req.data?.deviceKey);
          const snapshot = await verifiedPage(db, "activity_registrations",
              keyHash, req.data?.cursor);
          const ids = [...new Set(snapshot.docs.map((x) => x.get("activityId"))
              .filter((id) => typeof id === "string"))];
          const titles = new Map();
          await Promise.all(ids.map(async (id) => {
            const doc = await activities.doc(id).get();
            if (doc.exists) titles.set(id, doc.get("title") || "");
          }));
          return {reference: verificationReference(keyHash),
            nextCursor: snapshot.nextCursor,
            registrations: snapshot.docs.map((doc) => ({
              deviceVerified: true,
              activityId: doc.get("activityId"),
              activityTitle: titles.get(doc.get("activityId")) ||
              doc.get("activityTitle") || "",
              fullName: doc.get("fullName") || "",
              status: doc.get("status"),
            }))};
        }),
    syncActivityDeviceToken: onCall({region: "us-central1", maxInstances: 10,
      timeoutSeconds: 300},
    async (req) => {
      const keyHash = deviceHash(req.data?.deviceKey);
      const token = tokenField(req.data?.fcmToken);
      if (!token) {
        throw new HttpsError("invalid-argument", "Token missing.");
      }
      return syncPage(db, "activity_registrations", keyHash, token);
    }),
    resendActivityDecision: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          await requireAdmin(req);
          const id = requireId(req.data?.activityId);
          const regId = requireRegId(req.data?.registrationId);
          const ref = registrations.doc(regId);
          return {notified: await retryDecision(db, ref, "activityId", id)};
        }),
  };
}
module.exports = {makeActivityFunctions};
