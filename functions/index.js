// Pin to the v1 API explicitly: keeps this a 1st-gen callable so the client's
// hardcoded https://us-central1-<project>.cloudfunctions.net/lookupUserByEmail
// URL stays valid. (firebase-functions v6 makes the root import v2.)
const functions = require("firebase-functions/v1");
const admin = require("firebase-admin");

admin.initializeApp();

/**
 * Resolve an email to a minimal public profile. Keeps user profiles private:
 * clients cannot read the users collection directly; this runs with admin
 * privileges and returns only uid/displayName/photoURL.
 */
exports.lookupUserByEmail = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Must be signed in.");
  }
  const email = String((data && data.email) || "").trim().toLowerCase();
  if (!email) {
    throw new functions.https.HttpsError("invalid-argument", "Email required.");
  }
  const snap = await admin.firestore()
      .collection("users")
      .where("email", "==", email)
      .limit(1)
      .get();
  if (snap.empty) {
    return null;
  }
  const doc = snap.docs[0];
  const d = doc.data();
  return {
    uid: doc.id,
    displayName: d.displayName || "",
    photoURL: d.photoURL || null,
  };
});
