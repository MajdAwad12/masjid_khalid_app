"use strict";

// Registration documents live outside the deleted parent document.
const deleteLinkedRegistrations = async (db, collection, parentField, id) => {
  let deleted = 0;
  for (;;) {
    const page = await db.collection(collection)
        .where(parentField, "==", id).limit(200).get();
    if (page.empty) return deleted;
    const batch = db.batch();
    for (const doc of page.docs) batch.delete(doc.ref);
    await batch.commit();
    deleted += page.size;
  }
};

module.exports = {deleteLinkedRegistrations};
