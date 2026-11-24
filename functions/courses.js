"use strict";

/* eslint-disable require-jsdoc, valid-jsdoc */

// Course registration is available without Firebase Authentication.
// Only server code can write courses and registrations; admins are checked
// against BOTH Firebase custom claims and the admin profile in index.js.
const crypto = require("node:crypto");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {FieldValue, Timestamp} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");
const logger = require("firebase-functions/logger");

const hash = (value) => crypto.createHash("sha256")
    .update(value).digest("hex");
const keyPattern = /^[a-f0-9]{64}$/;
const tokenPattern = /^.{20,4096}$/s;
const registrationStates = ["pending", "accepted", "rejected"];

/** Validate a required user-entered text field. */
function limitedText(value, field, max, min = 1) {
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  const text = value.trim();
  if (text.length < min || text.length > max) {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  return text;
}

/** Validate and hash the installation credential. */
function validDeviceKey(value) {
  if (typeof value !== "string" || !keyPattern.test(value)) {
    throw new HttpsError("invalid-argument",
        "Invalid device registration key.");
  }
  return hash(`course-device\0${value}`);
}

/** Validate the optional FCM registration token. */
function validToken(value) {
  if (value === null || value === undefined || value === "") return null;
  if (typeof value !== "string" || !tokenPattern.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid notification token.");
  }
  return value;
}

/** Normalize a submitted phone number for duplicate suppression. */
function normalizePhone(value) {
  if (typeof value !== "string" || value.length > 32 ||
      !/^[+\d\s()-]+$/.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid phone number.");
  }
  let digits = value.replace(/\D/g, "");
  // Standardize common Israeli local/international spellings for duplicates.
  if (digits.startsWith("00972")) digits = digits.substring(2);
  if (digits.startsWith("9720")) digits = `972${digits.substring(4)}`;
  if (digits.startsWith("0") && digits.length === 10) {
    digits = `972${digits.substring(1)}`;
  }
  if (digits.length < 8 || digits.length > 15) {
    throw new HttpsError("invalid-argument", "Invalid phone number.");
  }
  return digits;
}

/** Canonical per-person identity so relatives can share a phone number. */
function canonicalName(value) {
  return value.normalize("NFKC").trim().replace(/\s+/gu, " ").toLowerCase();
}

/** Registration IDs created before the per-person enrollment update. */
function legacyRegistrationId(courseId, phone) {
  return hash(`course-registration\0${courseId}\0${phone}`);
}

/** New IDs distinguish two people registering from the same phone. */
function personRegistrationId(courseId, phone, fullName) {
  return hash(`course-person-registration-v2\0${courseId}\0${phone}\0` +
      canonicalName(fullName));
}

/** Count historical rejected registrations if course lacks rejectedCount. */
async function rejectedCountInTransaction(tx, db, courseSnap) {
  const stored = courseSnap.get("rejectedCount");
  if (Number.isInteger(stored) && stored >= 0) return stored;
  const results = await tx.get(db.collection("course_registrations")
      .where("courseId", "==", courseSnap.id));
  return results.docs.filter((doc) => doc.get("status") === "rejected")
      .length;
}

/** Update the three persisted state counters atomically with one decision. */
async function updateStateCounters(tx, db, course, courseRef,
    fromState, toState) {
  const accepted = Number(course.get("acceptedCount")) || 0;
  const pending = Number(course.get("pendingCount")) || 0;
  const rejected = await rejectedCountInTransaction(tx, db, course);
  const next = {acceptedCount: accepted, pendingCount: pending,
    rejectedCount: rejected};
  if (registrationStates.includes(fromState)) {
    const field = `${fromState}Count`;
    next[field] = Math.max(0, next[field] - 1);
  }
  if (registrationStates.includes(toState)) {
    next[`${toState}Count`] += 1;
  }
  tx.update(courseRef, next);
}

/** Validate a server-generated course document ID. */
function requireCourseId(value) {
  if (typeof value !== "string" || !/^[a-zA-Z0-9]{10,40}$/.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid course ID.");
  }
  return value;
}

/** Validate a hash-derived registration ID. */
function requireRegistrationId(value) {
  if (typeof value !== "string" || !/^[a-f0-9]{64}$/.test(value)) {
    throw new HttpsError("invalid-argument", "Invalid registration ID.");
  }
  return value;
}

// The rate limiter does not store raw IP addresses, phone numbers, or tokens.
// A shared mosque Wi-Fi may have many users, hence the fairly generous limit.
/** Limit public enrollment submissions per hour. */
async function rateLimitPublicRegistration(db, request, deviceKeyHash) {
  const ip = request.rawRequest?.ip;
  if (typeof ip !== "string" || ip.length < 2) {
    throw new HttpsError("unavailable", "Unable to verify request origin.");
  }
  const now = Date.now();
  const hourlyWindow = Math.floor(now / 3600000);
  const limits = [
    {id: hash(`course-ip\0${ip}\0${hourlyWindow}`), max: 60},
    {id: hash(`course-device-limit\0${deviceKeyHash}\0${hourlyWindow}`),
      max: 8},
  ];
  const refs = limits.map((item) => db.collection(
      "security_course_registration_limits").doc(item.id));
  await db.runTransaction(async (tx) => {
    const snapshots = await Promise.all(refs.map((ref) => tx.get(ref)));
    for (let i = 0; i < refs.length; i++) {
      const count = Number(snapshots[i].get("count")) || 0;
      if (count >= limits[i].max) {
        throw new HttpsError("resource-exhausted", "Too many registrations.");
      }
    }
    for (let i = 0; i < refs.length; i++) {
      tx.set(refs[i], {
        count: (Number(snapshots[i].get("count")) || 0) + 1,
        expiresAt: Timestamp.fromMillis((hourlyWindow + 2) * 3600000),
      });
    }
  });
}

/** An empty field is genuinely optional, but nonempty values are limited. */
function optionalText(value, field, max) {
  if (value == null || value === "") return "";
  if (typeof value !== "string") {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  const text = value.trim();
  if (text.length > max) {
    throw new HttpsError("invalid-argument", `Invalid ${field}.`);
  }
  return text;
}

/** Validate a course edited by an administrator. */
function parseCourse(data) {
  const title = limitedText(data.title, "title", 90, 1);
  const description = optionalText(data.description, "description", 1200);
  const teacher = optionalText(data.teacher, "teacher", 80);
  const location = optionalText(data.location, "location", 120);
  const capacity = data.capacity == null || data.capacity === "" ? null :
    data.capacity;
  if (capacity !== null && (!Number.isInteger(capacity) ||
      capacity < 1 || capacity > 1000)) {
    throw new HttpsError("invalid-argument", "Invalid capacity.");
  }
  const ms = data.startAtMs == null || data.startAtMs === "" ? null :
    data.startAtMs;
  if (ms !== null && (!Number.isSafeInteger(ms) ||
      ms < Date.UTC(2020, 0, 1) || ms > Date.UTC(2100, 0, 1))) {
    throw new HttpsError("invalid-argument", "Invalid start date.");
  }
  if (!["automatic", "approval"].includes(data.registrationMode)) {
    throw new HttpsError("invalid-argument", "Invalid registration mode.");
  }
  if (typeof data.isOpen !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid course status.");
  }
  // Older installed clients may omit visibility: preserve it on edits.
  if (data.isVisible !== undefined &&
      typeof data.isVisible !== "boolean") {
    throw new HttpsError("invalid-argument", "Invalid visibility.");
  }
  return {
    title, description, teacher, location,
    capacity,
    startAt: ms === null ? null : Timestamp.fromMillis(ms),
    registrationMode: data.registrationMode,
    isOpen: data.isOpen,
    ...(data.isVisible === undefined ? {} : {isVisible: data.isVisible}),
  };
}

/** Send an FCM decision notification; record delivery request status. */
async function sendDecision(db, courseId, registrationId, registration) {
  const ref = db.collection("course_registrations").doc(registrationId);
  const token = registration.fcmToken;
  if (typeof token !== "string" || !token) {
    await ref.update({notificationState: "no-token"});
    return false;
  }
  const accepted = registration.status === "accepted";
  const title = accepted ? "تم قبول تسجيلك في الدورة" :
    "تم رفض طلب التسجيل في الدورة";
  const body = accepted ? "يسعدنا انضمامك إلى الدورة. أهلاً بك!" :
    "نعتذر، لم تتم الموافقة على طلب تسجيلك.";
  try {
    await getMessaging().send({
      token,
      notification: {title, body},
      data: {type: "course_decision", courseId, registrationId,
        status: registration.status},
      android: {priority: "high"},
      apns: {payload: {aps: {sound: "default"}}},
    });
    await ref.update({notificationState: "sent",
      notifiedAt: FieldValue.serverTimestamp()});
    return true;
  } catch (error) {
    logger.warn("Course decision push failed", {
      registrationId, code: error.code || "unknown",
    });
    await ref.update({notificationState: "failed"});
    return false;
  }
}

/** Bind all course Cloud Functions to the existing admin checker and DB. */
function makeCourseFunctions({db, requireAdmin}) {
  return {
    // Idempotent one-time upgrade: existing courses remain public by default.
    // Administrator-only, invoked when the admin first opens the courses tab.
    initializeCourseVisibility: onCall({region: "us-central1",
      maxInstances: 2, timeoutSeconds: 120}, async (request) => {
      await requireAdmin(request);
      const migrationRef = db.collection("security_course_migrations")
          .doc("visibility_v1");
      const state = await migrationRef.get();
      if (state.get("completed") === true) {
        return {updated: 0, alreadyComplete: true};
      }
      let after = null;
      let updated = 0;
      let hasMore = true;
      while (hasMore) {
        let query = db.collection("courses").orderBy("__name__").limit(150);
        if (after !== null) query = query.startAfter(after);
        const page = await query.get();
        if (page.empty) break;
        // Re-read inside a transaction so an admin's simultaneous visibility
        // change cannot be overwritten by the legacy migration.
        const changed = await db.runTransaction(async (tx) => {
          const snapshots = await Promise.all(page.docs.map(
              (doc) => tx.get(doc.ref)));
          let count = 0;
          for (const doc of snapshots) {
            if (doc.exists && typeof doc.get("isVisible") !== "boolean") {
              tx.update(doc.ref, {isVisible: true});
              count++;
            }
          }
          return count;
        });
        updated += changed;
        after = page.docs[page.docs.length - 1];
        hasMore = page.size === 150;
      }
      await migrationRef.set({completed: true,
        completedAt: FieldValue.serverTimestamp(), updated});
      return {updated, alreadyComplete: false};
    }),

    // Course writes are all validated and authorized server-side.
    saveCourse: onCall({region: "us-central1", maxInstances: 10},
        async (request) => {
          const adminUid = await requireAdmin(request);
          const data = request.data || {};
          const validated = parseCourse(data);
          const courseId = data.courseId == null ? null :
            requireCourseId(data.courseId);
          const ref = courseId ? db.collection("courses").doc(courseId) :
            db.collection("courses").doc();
          await db.runTransaction(async (tx) => {
            const snap = await tx.get(ref);
            if (courseId && !snap.exists) {
              throw new HttpsError("not-found", "Course not found.");
            }
            // Existing registrations are preserved even when an admin lowers
            // capacity. The course is then full, never auto-removes people.
            if (snap.exists) {
              tx.update(ref, {...validated, updatedBy: adminUid,
                updatedAt: FieldValue.serverTimestamp()});
            } else {
              tx.create(ref, {...validated,
                isVisible: validated.isVisible ?? true,
                acceptedCount: 0, pendingCount: 0, rejectedCount: 0,
                createdAt: FieldValue.serverTimestamp(),
                updatedAt: FieldValue.serverTimestamp(),
                createdBy: adminUid, updatedBy: adminUid});
            }
          });
          return {courseId: ref.id};
        }),

    // A phone number may be shared by family members. Deduplicate by
    // course + normalized phone + participant name, without losing legacy
    // phone-only registrations already saved in Firestore.
    registerForCourse: onCall({region: "us-central1", maxInstances: 10},
        async (request) => {
          const data = request.data || {};
          const courseId = requireCourseId(data.courseId);
          const fullName = limitedText(data.fullName, "fullName", 80, 3);
          const phone = normalizePhone(data.phone);
          const deviceKeyHash = validDeviceKey(data.deviceKey);
          const fcmToken = validToken(data.fcmToken);
          const regId = personRegistrationId(courseId, phone, fullName);
          const legacyId = legacyRegistrationId(courseId, phone);
          await rateLimitPublicRegistration(db, request, deviceKeyHash);
          const courseRef = db.collection("courses").doc(courseId);
          const registrationRef = db.collection("course_registrations")
              .doc(regId);
          const legacyRef = db.collection("course_registrations")
              .doc(legacyId);
          const result = await db.runTransaction(async (tx) => {
            const [course, existing, legacy] = await Promise.all([
              tx.get(courseRef), tx.get(registrationRef), tx.get(legacyRef),
            ]);
            if (existing.exists || (legacy.exists &&
                canonicalName(legacy.get("fullName") || "") ===
                    canonicalName(fullName))) {
              throw new HttpsError("already-exists",
                  "This person is already registered for the course.");
            }
            if (!course.exists || course.get("isOpen") !== true ||
                course.get("isVisible") === false) {
              throw new HttpsError("failed-precondition",
                  "Course is unavailable for registration.");
            }
            const startAt = course.get("startAt");
            if (startAt instanceof Timestamp &&
                startAt.toMillis() <= Date.now()) {
              throw new HttpsError("failed-precondition",
                  "Course registration has closed.");
            }
            const accepted = Number(course.get("acceptedCount")) || 0;
            const pending = Number(course.get("pendingCount")) || 0;
            const capacity = course.get("capacity");
            if (typeof capacity === "number" && capacity > 0 &&
                accepted + pending >= capacity) {
              throw new HttpsError("resource-exhausted", "Course is full.");
            }
            const isAuto = course.get("registrationMode") === "automatic";
            const status = isAuto ? "accepted" : "pending";
            tx.create(registrationRef, {
              courseId, courseTitle: course.get("title") || "",
              fullName, phone, deviceKeyHash, fcmToken,
              status, removed: false, notificationState: "not-sent",
              createdAt: FieldValue.serverTimestamp(),
              decidedAt: isAuto ? FieldValue.serverTimestamp() : null,
              decidedBy: isAuto ? "automatic" : null,
            });
            tx.update(courseRef, isAuto ? {
              acceptedCount: FieldValue.increment(1),
            } : {pendingCount: FieldValue.increment(1)});
            return {registrationId: regId, status};
          });
          return result;
        }),

    // Admin can enroll a named person, even if another family member uses
    // the same phone. An existing request for the SAME person is reused.
    adminAddCourseParticipant: onCall({region: "us-central1",
      maxInstances: 10}, async (request) => {
      const adminUid = await requireAdmin(request);
      const data = request.data || {};
      const courseId = requireCourseId(data.courseId);
      const fullName = limitedText(data.fullName, "fullName", 80, 1);
      const phone = data.phone == null || data.phone === "" ||
          (typeof data.phone === "string" && data.phone.trim() === "") ?
        null : normalizePhone(data.phone);
      const manualNonce = crypto.randomBytes(32).toString("hex");
      const newId = phone ? personRegistrationId(courseId, phone, fullName) :
        hash(`course-manual\0${courseId}\0${manualNonce}`);
      const legacyId = phone ? legacyRegistrationId(courseId, phone) : null;
      const courseRef = db.collection("courses").doc(courseId);
      const newRef = db.collection("course_registrations").doc(newId);
      const legacyRef = legacyId ? db.collection("course_registrations")
          .doc(legacyId) : null;
      const result = await db.runTransaction(async (tx) => {
        const [course, previous, legacy] = await Promise.all([
          tx.get(courseRef), tx.get(newRef),
          legacyRef ? tx.get(legacyRef) : Promise.resolve(null),
        ]);
        if (!course.exists) {
          throw new HttpsError("not-found", "Course not found.");
        }
        const sameLegacy = legacy?.exists &&
            canonicalName(legacy.get("fullName") || "") ===
                canonicalName(fullName);
        const existing = previous.exists ? previous :
          (sameLegacy ? legacy : null);
        const regRef = existing?.ref || newRef;
        const previousState = existing?.get("status") || null;
        if (previousState === "accepted") {
          throw new HttpsError("already-exists", "Already enrolled.");
        }
        await updateStateCounters(tx, db, course, courseRef,
            previousState, "accepted");
        if (existing) {
          tx.update(regRef, {
            fullName, courseTitle: course.get("title") || "",
            status: "accepted", removed: false, decidedBy: adminUid,
            decidedAt: FieldValue.serverTimestamp(),
            notificationState: "sending", updatedBy: adminUid,
          });
        } else {
          tx.create(regRef, {
            courseId, courseTitle: course.get("title") || "",
            fullName, phone,
            deviceKeyHash: null, fcmToken: null,
            source: "admin", status: "accepted", removed: false,
            notificationState: "no-token",
            createdAt: FieldValue.serverTimestamp(),
            decidedAt: FieldValue.serverTimestamp(),
            decidedBy: adminUid,
          });
        }
        return {registrationId: regRef.id,
          prior: existing ? existing.data() : null};
      });
      const notified = result.prior?.fcmToken ?
        await sendDecision(db, courseId, result.registrationId,
            {...result.prior, status: "accepted"}) : false;
      return {registrationId: result.registrationId, notified};
    }),

    // The 256-bit per-installation key authorizes updating ONLY notification
    // destinations and reading status summaries; no PII is returned.
    syncCourseDeviceToken: onCall({region: "us-central1", maxInstances: 10},
        async (request) => {
          const deviceKeyHash = validDeviceKey(request.data?.deviceKey);
          const fcmToken = validToken(request.data?.fcmToken);
          if (!fcmToken) {
            throw new HttpsError("invalid-argument", "Token required.");
          }
          const snapshots = await db.collection("course_registrations")
              .where("deviceKeyHash", "==", deviceKeyHash).limit(100).get();
          const batch = db.batch();
          let updated = 0;
          for (const item of snapshots.docs) {
            if (registrationStates.includes(item.get("status")) &&
                item.get("fcmToken") !== fcmToken) {
              batch.update(item.ref, {fcmToken});
              updated++;
            }
          }
          if (updated > 0) await batch.commit();
          return {updated};
        }),

    // The unguessable per-installation key grants the registering device
    // read access to the NAMES it submitted and their latest statuses.
    // Phone numbers and FCM credentials are NEVER returned publicly.
    myCourseRegistrations: onCall({region: "us-central1", maxInstances: 10},
        async (request) => {
          const deviceKeyHash = validDeviceKey(request.data?.deviceKey);
          const snapshots = await db.collection("course_registrations")
              .where("deviceKeyHash", "==", deviceKeyHash).limit(100).get();
          const courseIds = [...new Set(snapshots.docs
              .map((item) => item.get("courseId"))
              .filter((id) => typeof id === "string" &&
                  /^[a-zA-Z0-9]{10,40}$/.test(id)))];
          const currentTitles = new Map();
          await Promise.all(courseIds.map(async (courseId) => {
            const course = await db.collection("courses").doc(courseId).get();
            if (course.exists) {
              currentTitles.set(courseId, course.get("title") || "");
            }
          }));
          return {registrations: snapshots.docs.map((item) => ({
            courseId: item.get("courseId"),
            courseTitle: currentTitles.get(item.get("courseId")) ||
              item.get("courseTitle") || "",
            fullName: item.get("fullName") || "",
            status: item.get("status"),
            registrationId: item.id,
          }))};
        }),

    // Admin can correct a prior decision, including accepted -> rejected.
    // All transitions update counters and notify the registering device.
    decideCourseRegistration: onCall({region: "us-central1",
      maxInstances: 10}, async (request) => {
      const adminUid = await requireAdmin(request);
      const data = request.data || {};
      const courseId = requireCourseId(data.courseId);
      const registrationId = requireRegistrationId(data.registrationId);
      if (!["accepted", "rejected"].includes(data.decision)) {
        throw new HttpsError("invalid-argument", "Invalid decision.");
      }
      const regRef = db.collection("course_registrations")
          .doc(registrationId);
      const courseRef = db.collection("courses").doc(courseId);
      const decision = await db.runTransaction(async (tx) => {
        const [registration, course] = await Promise.all([
          tx.get(regRef), tx.get(courseRef),
        ]);
        if (!registration.exists || registration.get("courseId") !==
            courseId || !course.exists) {
          throw new HttpsError("not-found", "Registration not found.");
        }
        const previousState = registration.get("status");
        if (!registrationStates.includes(previousState)) {
          throw new HttpsError("failed-precondition", "Invalid state.");
        }
        if (previousState === data.decision &&
            registration.get("removed") !== true) {
          return {changed: false, registration: registration.data()};
        }
        if (previousState !== data.decision) {
          await updateStateCounters(tx, db, course, courseRef,
              previousState, data.decision);
        }
        tx.update(regRef, {status: data.decision, removed: false,
          decidedAt: FieldValue.serverTimestamp(), decidedBy: adminUid,
          notificationState: "sending", updatedBy: adminUid});
        return {changed: true,
          registration: {...registration.data(), status: data.decision}};
      });
      const notified = decision.changed ? await sendDecision(db, courseId,
          registrationId, decision.registration) : false;
      return {notified, changed: decision.changed};
    }),

    // One-time/administrative reconciliation also repairs older courses
    // created before rejectedCount existed. It reads from the shared database.
    reconcileCourseCounts: onCall({region: "us-central1",
      maxInstances: 3}, async (request) => {
      await requireAdmin(request);
      const courseId = requireCourseId(request.data?.courseId);
      const courseRef = db.collection("courses").doc(courseId);
      return db.runTransaction(async (tx) => {
        const course = await tx.get(courseRef);
        if (!course.exists) {
          throw new HttpsError("not-found", "Course not found.");
        }
        const snapshot = await tx.get(db.collection("course_registrations")
            .where("courseId", "==", courseId));
        const totals = {acceptedCount: 0, pendingCount: 0,
          rejectedCount: 0};
        for (const doc of snapshot.docs) {
          const state = doc.get("status");
          if (registrationStates.includes(state)) {
            totals[`${state}Count`] += 1;
          }
        }
        tx.update(courseRef, totals);
        return {...totals};
      });
    }),

    resendCourseDecision: onCall({region: "us-central1", maxInstances: 10},
        async (request) => {
          await requireAdmin(request);
          const courseId = requireCourseId(request.data?.courseId);
          const registrationId = requireRegistrationId(
              request.data?.registrationId);
          const regRef = db.collection("course_registrations")
              .doc(registrationId);
          const registration = await db.runTransaction(async (tx) => {
            const snapshot = await tx.get(regRef);
            if (!snapshot.exists || snapshot.get("courseId") !== courseId ||
                !["accepted", "rejected"].includes(snapshot.get("status"))) {
              throw new HttpsError("failed-precondition", "No final decision.");
            }
            const last = snapshot.get("lastResendAt");
            if (last instanceof Timestamp &&
                Date.now() - last.toMillis() < 60000) {
              throw new HttpsError("resource-exhausted", "Retry in a minute.");
            }
            tx.update(regRef, {lastResendAt: FieldValue.serverTimestamp(),
              notificationState: "sending"});
            return snapshot.data();
          });
          const notified = await sendDecision(db, courseId,
              registrationId, registration);
          return {notified};
        }),
  };
}

module.exports = {makeCourseFunctions};
