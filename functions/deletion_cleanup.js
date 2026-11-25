"use strict";

// A Firestore deletion trigger runs this cleanup with retries enabled.
// Registration documents live in separate top-level collections, so deleting
// a course/activity document does not automatically delete them.
async function deleteLinkedRegistrations(db, collection, parentField, id) {
  let deleted = 0;
  while (true) {
    const page = await db.collection(collection)
        .where(parentField, "==", id).limit(200).get();
    if (page.empty) return deleted;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += page.size;
  }
}

module.exports = {deleteLinkedRegistrations};
