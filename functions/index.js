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

/**
 * Send a push to every registered token of `uid`. Prunes tokens FCM reports dead.
 */
async function sendPushToUser(uid, notification, data) {
  const col = admin.firestore().collection("users").doc(uid).collection("fcmTokens");
  const snap = await col.get();
  const tokens = snap.docs.map((d) => d.id);
  if (tokens.length === 0) return;

  const resp = await admin.messaging().sendEachForMulticast({
    tokens,
    notification,
    data: data || {},
    apns: {payload: {aps: {sound: "default"}}},
  });

  const dead = [];
  resp.responses.forEach((r, i) => {
    if (!r.success) {
      const code = r.error && r.error.code;
      if (code === "messaging/registration-token-not-registered" ||
          code === "messaging/invalid-argument") {
        dead.push(tokens[i]);
      }
    }
  });
  await Promise.all(dead.map((t) => col.doc(t).delete()));
}

/** New friend request → notify the recipient. */
exports.onFriendRequestCreated = functions.firestore
    .document("friendRequests/{requestId}")
    .onCreate(async (snap) => {
      const req = snap.data();
      if (req.status !== "pending") return;
      await sendPushToUser(
          req.toUid,
          {title: "New friend request", body: `${req.fromName || "Someone"} wants to connect`},
          {type: "friendRequest"},
      );
    });

/** Friend request accepted → notify the original sender. */
exports.onFriendRequestUpdated = functions.firestore
    .document("friendRequests/{requestId}")
    .onUpdate(async (change) => {
      const before = change.before.data();
      const after = change.after.data();
      if (before.status !== "accepted" && after.status === "accepted") {
        await sendPushToUser(
            after.fromUid,
            {title: "Friend request accepted", body: `${after.toName || "Your friend"} accepted your request`},
            {type: "friendAccepted"},
        );
      }
    });
