"use strict";
/* eslint-disable require-jsdoc, valid-jsdoc */

const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getStorage} = require("firebase-admin/storage");
const logger = require("firebase-functions/logger");

const idField = (id) => {
  if (typeof id !== "string" || !/^[A-Za-z0-9]{10,40}$/.test(id)) {
    throw new HttpsError("invalid-argument", "Invalid homework ID.");
  }
  return id;
};
const stringField = (value, name, max, required = false) => {
  if (value == null && !required) return "";
  if (typeof value !== "string" || value.trim().length > max ||
      (required && !value.trim())) {
    throw new HttpsError("invalid-argument", `Invalid ${name}.`);
  }
  return value.trim();
};

function makeHomeworkFunctions({db, requireAdmin}) {
  const homework = db.collection("homework");
  return {
    saveHomework: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          const uid = await requireAdmin(req);
          const d = req.data || {};
          const id = idField(d.homeworkId);
          if (typeof d.isVisible !== "boolean") {
            throw new HttpsError("invalid-argument", "Invalid visibility.");
          }
          const raw = d.dueAtMs;
          if (raw != null && (!Number.isSafeInteger(raw) ||
              raw < Date.UTC(2020, 0, 1) || raw > Date.UTC(2100, 0, 1))) {
            throw new HttpsError("invalid-argument", "Invalid due date.");
          }
          const imagePath = stringField(d.imagePath, "imagePath", 240);
          if (imagePath && !new RegExp(
              `^homework/${id}/images/[A-Za-z0-9_-]{8,90}\\.(jpg|png|webp)$`)
              .test(imagePath)) {
            throw new HttpsError("invalid-argument", "Invalid image path.");
          }
          const data = {
            title: stringField(d.title, "title", 120, true),
            body: stringField(d.body, "body", 20000),
            groupName: stringField(d.groupName, "groupName", 120),
            dueAt: raw == null ? null : Timestamp.fromMillis(raw),
            imagePath, isVisible: d.isVisible,
          };
          const ref = homework.doc(id);
          await db.runTransaction(async (tx) => {
            const before = await tx.get(ref);
            if (before.exists) {
              tx.update(ref, {...data, updatedBy: uid,
                updatedAt: FieldValue.serverTimestamp()});
            } else {
              tx.create(ref, {...data, createdBy: uid,
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp()});
            }
          });
          return {homeworkId: id};
        }),
    deleteHomework: onCall({region: "us-central1", maxInstances: 10},
        async (req) => {
          await requireAdmin(req);
          const id = idField(req.data?.homeworkId);
          const ref = homework.doc(id);
          const doc = await ref.get();
          if (!doc.exists) throw new HttpsError("not-found", "Not found.");
          const path = doc.get("imagePath");
          await ref.delete();
          if (typeof path === "string" && path.startsWith(
              `homework/${id}/images/`)) {
            try {
              await getStorage().bucket("masjid-khalid-app.firebasestorage.app")
                  .file(path).delete({ignoreNotFound: true});
            } catch (error) {
              logger.warn("Homework image cleanup failed", {
                id, code: error.code || "unknown"});
            }
          }
          return {deleted: true};
        }),
  };
}
module.exports = {makeHomeworkFunctions};
