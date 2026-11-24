"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

// Public-only FCM broadcasts. No personal registration records or user IDs
// are sent to the topic. All writes to the delivery ledger are Admin SDK only.
const {onDocumentWritten} = require("firebase-functions/v2/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const logger = require("firebase-functions/logger");

const PUBLIC_TOPIC = "masjid_public_updates_v1";
const DELIVERY_COLLECTION = "security_public_notification_deliveries";

const kinds = {
  announcements: {
    functionName: "notifyNewAnnouncement",
    title: "📢 إعلان جديد من المسجد",
    section: "1",
  },
  courses: {
    functionName: "notifyNewCourse",
    title: "📚 دورة جديدة في المسجد",
    section: "2",
  },
  activities: {
    functionName: "notifyNewActivity",
    title: "🚌 نشاط أو رحلة جديدة",
    section: "3",
  },
  homework: {
    functionName: "notifyNewHomework",
    title: "✏️ وظيفة بيتية جديدة",
    section: "4",
  },
};

function notExpired(value, nowMs) {
  return !(value instanceof Timestamp) || value.toMillis() > nowMs;
}

function publiclyVisible(kind, data, nowMs) {
  if (!data || typeof data.title !== "string" || !data.title.trim()) {
    return false;
  }
  if (kind === "announcements") {
    return notExpired(data.expiresAt, nowMs);
  }
  if (data.isVisible !== true) return false;
  if (kind === "activities" && !notExpired(data.hideAt, nowMs)) {
    return false;
  }
  return true;
}

function messageFor(kind, data, itemId) {
  const config = kinds[kind];
  const name = data.title.trim();
  const body = name.length > 110 ? `${name.slice(0, 107)}…` : name;
  const prefix = kind === "activities" && data.kind === "trip" ?
    "🚌 رحلة جديدة" : config.title;
  return {
    topic: PUBLIC_TOPIC,
    notification: {title: prefix, body},
    data: {type: "new_public_item", section: config.section,
      itemId, kind},
    android: {priority: "high"},
    apns: {payload: {aps: {sound: "default"}}},
  };
}

// A document gets only one publication alert, even if it is edited or hidden
// and shown again. The ledger prevents repeated sends from duplicate events.
// FCM is best-effort and does not guarantee exactly-once device delivery.
async function publishOnce(db, kind, itemId, data, send = (message) =>
  getMessaging().send(message)) {
  const ledger = db.collection(DELIVERY_COLLECTION)
      .doc(`${kind}_${itemId}`);
  const claimed = await db.runTransaction(async (tx) => {
    const before = await tx.get(ledger);
    if (before.exists) return false;
    tx.create(ledger, {kind, itemId, state: "claimed",
      startedAt: FieldValue.serverTimestamp()});
    return true;
  });
  if (!claimed) return false;
  try {
    const id = await send(messageFor(kind, data, itemId));
    await ledger.update({state: "sent", messageId: id,
      sentAt: FieldValue.serverTimestamp()});
    return true;
  } catch (error) {
    // A failed attempt is recorded for investigation. Do not automatically
    // retry an ambiguous send: the remote service might have accepted it.
    logger.error("Public content notification failed", {kind, itemId,
      code: error.code || "unknown"});
    try {
      await ledger.update({state: "failed",
        failedAt: FieldValue.serverTimestamp(),
        errorCode: String(error.code || "unknown").slice(0, 80)});
    } catch (updateError) {
      logger.warn("Notification delivery ledger update failed", {kind,
        itemId, code: updateError.code || "unknown"});
    }
    return false;
  }
}

// The trigger fires when a record becomes publicly visible for the first
// time (creation or first publication of a draft). Editing an existing visible
// record does not generate new notifications.
async function handleWrite(db, kind, event) {
  const after = event.data?.after;
  if (!after?.exists) return;
  const next = after.data();
  const nowMs = Date.now();
  if (!publiclyVisible(kind, next, nowMs)) return;
  const previous = event.data?.before?.exists ?
    event.data.before.data() : null;
  if (publiclyVisible(kind, previous, nowMs)) return;
  await publishOnce(db, kind, event.params.itemId, next);
}

function makePublicNotificationFunctions({db}) {
  const output = {};
  for (const [kind, config] of Object.entries(kinds)) {
    output[config.functionName] = onDocumentWritten({
      document: `${kind}/{itemId}`,
      region: "us-central1",
      maxInstances: 5,
    }, (event) => handleWrite(db, kind, event));
  }
  return output;
}

module.exports = {makePublicNotificationFunctions, PUBLIC_TOPIC,
  publiclyVisible, messageFor, publishOnce};
