const admin = require('firebase-admin');

if (!admin.apps.length) {
    const rawKey = process.env.FIREBASE_PRIVATE_KEY;
    if (!rawKey) throw new Error('FIREBASE_PRIVATE_KEY env var is missing');

    admin.initializeApp({
        credential: admin.credential.cert({
            projectId: process.env.FIREBASE_PROJECT_ID,
            clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
            privateKey: rawKey.replace(/\\n/g, '\n'),
        }),
    });
}

module.exports = { messaging: admin.messaging() };