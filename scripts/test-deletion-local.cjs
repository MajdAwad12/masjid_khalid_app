"use strict";

// Dependency-free tests for the new course/activity deletion endpoints.
// These use fake Firestore and Cloud Functions; they do not touch production.
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

class HttpsError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

function fakeDb() {
  const tables = new Map();
  const table = (name) => {
    if (!tables.has(name)) tables.set(name, new Map());
    return tables.get(name);
  };
  const ref = (name, id) => ({
    id,
    get: async () => ({id, exists: table(name).has(id),
      data: () => table(name).get(id),
      get: (field) => table(name).get(id)?.[field]}),
    _delete: () => table(name).delete(id),
  });
  return {
    seed(name, id, doc) {table(name).set(id, doc);},
    count(name) {return table(name).size;},
    has(name, id) {return table(name).has(id);},
    collection(name) {
      return {
        doc(id) {return ref(name, id);},
        where(field, comparison, value) {
          assert.equal(comparison, "==");
          return {
            limit(limit) {
              return {
                async get() {
                  const docs = [...table(name)]
                      .filter(([, data]) => data[field] === value)
                      .slice(0, limit)
                      .map(([id, data]) => ({id, ref: ref(name, id),
                        get: (key) => data[key]}));
                  return {docs, empty: docs.length === 0, size: docs.length};
                },
              };
            },
          };
        },
      };
    },
    async runTransaction(callback) {
      return callback({
        get: (docRef) => docRef.get(),
        delete: (docRef) => docRef._delete(),
      });
    },
    batch() {
      const deletes = [];
      return {delete: (docRef) => deletes.push(docRef),
        async commit() {deletes.forEach((item) => item._delete());}};
    },
  };
}

function loadModule(filename, fakeStorage) {
  const fullPath = path.join(__dirname, "..", "functions", filename);
  const module = {exports: {}};
  const functions = {
    "firebase-functions/v2/https": {onCall: (_options, handler) => handler,
      HttpsError},
    "firebase-functions/v2/firestore": {
      onDocumentDeleted: (_options, handler) => handler,
    },
    "firebase-admin/firestore": {
      FieldValue: {serverTimestamp: () => new Date()},
      Timestamp: class Timestamp {},
    },
    "firebase-admin/messaging": {getMessaging: () => ({send: async () => {}})},
    "firebase-admin/storage": {getStorage: () => fakeStorage},
    "firebase-functions/logger": {info: () => {}, warn: () => {}},
  };
  const localRequire = (id) => {
    if (id === "./registration_capacity") {
      return require(path.join(__dirname, "..", "functions", "registration_capacity.js"));
    }
    if (id === "./registration_privacy") {
      // Individual records are exercised by the emulator suite.
      return {recoverDecisionCreates: () => () => {}, recoverDecisionUpdates: () => () => {}, staffRegistrationAction: () => () => { throw new Error("Unexpected registration action"); }};
    }
    if (id === "./deletion_cleanup") {
      return require(path.join(__dirname, "..", "functions", "deletion_cleanup.js"));
    }
    if (functions[id]) return functions[id];
    return require(id);
  };
  vm.runInNewContext(fs.readFileSync(fullPath, "utf8"), {
    module, exports: module.exports, require: localRequire,
    __dirname: path.dirname(fullPath), console, Date,
    setTimeout, clearTimeout,
  }, {filename: fullPath});
  return module.exports;
}

(async () => {
  const id = "abc123def456ghi789";
  const storageDeletions = [];
  const storage = {bucket: (bucketName) => {
    assert.equal(bucketName, "masjid-khalid-app.firebasestorage.app");
    return {file: (filePath) => ({
      delete: async () => storageDeletions.push(filePath),
    })};
  }};
  const db = fakeDb();
  let admin = false;
  const requireAdmin = async () => {
    if (!admin) throw new HttpsError("permission-denied", "Admin only");
    return "test-admin";
  };
  const courses = loadModule("courses.js", storage)
      .makeCourseFunctions({db, requireAdmin});
  const activities = loadModule("activities.js", storage)
      .makeActivityFunctions({db, requireAdmin});

  assert.equal(typeof courses.deleteCourse, "function");
  assert.equal(typeof courses.cleanupDeletedCourseRegistrations, "function");
  assert.equal(typeof activities.deleteActivity, "function");
  assert.equal(typeof activities.cleanupDeletedActivityAssets, "function");
  await assert.rejects(courses.deleteCourse({data: {courseId: id}}),
      (err) => err.code === "permission-denied");
  await assert.rejects(activities.deleteActivity({data: {activityId: id}}),
      (err) => err.code === "permission-denied");
  admin = true;
  await assert.rejects(courses.deleteCourse({data: {courseId: "../bad"}}),
      (err) => err.code === "invalid-argument");
  await assert.rejects(activities.deleteActivity({data: {activityId: id}}),
      (err) => err.code === "not-found");

  db.seed("course_counts", id, {pendingCount: 1});
  db.seed("activity_counts", id, {acceptedCount: 1});
  db.seed("courses", id, {title: "test"});
  db.seed("activities", id, {title: "test"});
  for (let i = 0; i < 457; i++) {
    db.seed("course_registrations", `c-${i}`, {courseId: id});
    db.seed("activity_registrations", `a-${i}`, {activityId: id});
  }
  db.seed("course_registrations", "unrelated-course", {courseId: "another-id"});
  db.seed("activity_registrations", "unrelated-activity", {activityId: "another-id"});
  await courses.deleteCourse({data: {courseId: id}});
  await activities.deleteActivity({data: {activityId: id}});
  assert.equal(db.has("course_counts", id), false);
  assert.equal(db.has("activity_counts", id), false);
  assert.equal(db.has("courses", id), false);
  assert.equal(db.has("activities", id), false);
  await courses.cleanupDeletedCourseRegistrations({params: {courseId: id}});
  await activities.cleanupDeletedActivityAssets({params: {activityId: id},
    data: {get: () => `activities/${id}/images/validimage2026.jpg`}});
  assert.equal(db.count("course_registrations"), 1);
  assert.equal(db.count("activity_registrations"), 1);
  assert.deepEqual(storageDeletions,
      [`activities/${id}/images/validimage2026.jpg`]);
  // Duplicate delivery/retry is harmless.
  await courses.cleanupDeletedCourseRegistrations({params: {courseId: id}});
  await activities.cleanupDeletedActivityAssets({params: {activityId: id},
    data: {get: () => "not-an-owned-image"}});
  assert.equal(storageDeletions.length, 1);
  console.log("PASS: 14 checks (private counts, admin access, invalid IDs, absent docs, " +
      "parent deletion, 457 linked registrations, unrelated records, " +
      "image safety, retry idempotency)");
})().catch((error) => {console.error(error); process.exitCode = 1;});
