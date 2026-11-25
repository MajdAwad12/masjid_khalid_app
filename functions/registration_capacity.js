"use strict";
/* eslint-disable require-jsdoc */
const {HttpsError} = require("firebase-functions/v2/https");
const {FieldValue} = require("firebase-admin/firestore");

const installationAllowance = {course: 8, activity: 10};
const states = ["pending", "accepted", "rejected"];
const occupiesSeat = (status) => status === "pending" || status === "accepted";

function countsRef(db, kind, id) {
  return db.collection(kind + "_counts").doc(id);
}

async function rosterCounts(tx, roster) {
  const entries = await Promise.all(states.map(async (state) => {
    const total = await tx.get(roster.where("status", "==", state).count());
    return [state + "Count", total.data().count];
  }));
  return Object.fromEntries(entries);
}

// Every seat mutation locks the same private document, including the first
// reservation on older programs whose public counters may have drifted.
async function changeSeats(tx, program, from, to, options = {}) {
  const {device, publicSubmission, recount} = options;
  const db = program.ref.firestore;
  const kind = program.ref.parent.id === "courses" ? "course" : "activity";
  const ref = countsRef(db, kind, program.id);
  const roster = db.collection(kind + "_registrations")
      .where(kind + "Id", "==", program.id);
  const stored = await tx.get(ref);
  const counts = stored.exists && !recount ? stored.data() :
    await rosterCounts(tx, roster);
  if (!occupiesSeat(from) && occupiesSeat(to)) {
    const capacity = program.get("capacity");
    const occupied = counts.pendingCount + counts.acceptedCount;
    if (capacity > 0 && occupied >= capacity) {
      if (publicSubmission) return false;
      throw new HttpsError("resource-exhausted", "No available seats.");
    }
    if (device) {
      const matches = await tx.get(roster.where("deviceKeyHash", "==", device)
          .select("status", "deviceVerified"));
      const held = matches.docs.filter((doc) =>
        occupiesSeat(doc.get("status")) && doc.get("deviceVerified") !== true,
      ).length;
      if (held >= installationAllowance[kind]) {
        if (publicSubmission) return false;
        throw new HttpsError("resource-exhausted", "Installation seat limit.");
      }
    }
  }
  if (states.includes(from)) counts[from + "Count"]--;
  if (states.includes(to)) counts[to + "Count"]++;
  // Older clients disable enrollment using the historical parent fields.
  // Retire these on staff writes only. Public submissions never change the
  // public document, even the first time a private counter is initialized.
  if (!publicSubmission && states.some((state) =>
    program.get(state + "Count") !== undefined)) {
    tx.update(program.ref, {acceptedCount: FieldValue.delete(),
      pendingCount: FieldValue.delete(), rejectedCount: FieldValue.delete()});
  }
  tx.set(ref, counts);
  return counts;
}

function initialRegistration(status) {
  const automatic = status === "accepted";
  return {status, deviceVerified: false,
    decidedBy: automatic ? "automatic" : null,
    decidedAt: automatic ? FieldValue.serverTimestamp() : null,
    notificationState: automatic ? "ready" : "not-sent",
    ...(automatic ? {notifyAutomatic: true} : {})};
}

function unverifiedDevice(row) {
  return row?.get("deviceVerified") ? null : row?.get("deviceKeyHash");
}

module.exports = {countsRef, changeSeats, unverifiedDevice, initialRegistration,
  installationAllowance};
