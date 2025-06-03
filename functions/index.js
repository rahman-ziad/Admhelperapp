const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();

exports.onUserCreate = functions.auth.user().onCreate(async (userRecord) => {
  try {
    if (!userRecord || !userRecord.uid) {
      console.error('Invalid user object:', userRecord);
      return null;
    }

    console.log(`New user created: ${userRecord.uid}`);

    await db.collection('users').doc(userRecord.uid).set({
      email: userRecord.email || '',
      name: '',
      club_id: '',
      userType: 'manager',
    }, { merge: true });

    return null;
  } catch (error) {
    console.error('Error creating user document:', error);
    return null;
  }
});
