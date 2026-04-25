const { Router } = require('express');
const router = Router();
const { cronAuth } = require('../middleware/auth-middleware');
const { Token } = require('../models/Token-model');
const { messaging } = require('../config/firebase');

const DEAD_TOKEN_CODES = [
    'messaging/invalid-registration-token',
    'messaging/registration-token-not-registered',
    'messaging/invalid-argument',
];

router.post('/', cronAuth, async (req, res) => {
    try {
        const now = new Date();

        const dueDevices = await Token.find({
            $or: [
                { lastSentAt: null },
                {
                    $expr: {
                        $lte: [
                            { $add: ['$lastSentAt', { $multiply: ['$intervalMinutes', 60000] }] },
                            now,
                        ],
                    },
                },
            ],
        }).lean();

        if (dueDevices.length === 0) {
            return res.status(200).json({ message: 'No devices due' });
        }

        const tokens = dueDevices.map(d => d.fcmToken);

        // Pure data message — no `notification` key at any level.
        // With a notification message Android intercepts delivery when the app is
        // background/killed and posts its own tray notification, bypassing the
        // Flutter background handler entirely. A data-only message is always
        // delivered to the handler so the full-screen / overlay flow stays in control.
        const response = await messaging.sendEachForMulticast({
            data: {
                type: 'water_reminder',
                title: '💧 Drink Water!',
                body: 'Your body needs hydration.',
                channelId: 'water_reminder',
            },
            android: {
                priority: 'high',
            },
            tokens,
        });

        const deadTokens = [];
        const sentDeviceIds = [];

        response.responses.forEach((r, i) => {
            if (r.success) {
                sentDeviceIds.push(dueDevices[i].deviceId);
            } else if (DEAD_TOKEN_CODES.includes(r.error?.code)) {
                deadTokens.push(tokens[i]);
            }
        });

        if (sentDeviceIds.length > 0) {
            await Token.updateMany(
                { deviceId: { $in: sentDeviceIds } },
                { $set: { lastSentAt: now } }
            );
        }

        if (deadTokens.length > 0) {
            await Token.deleteMany({ fcmToken: { $in: deadTokens } });
        }

        return res.status(200).json({
            due: dueDevices.length,
            sent: response.successCount,
            failed: response.failureCount,
            cleaned: deadTokens.length,
        });
    } catch (err) {
        console.error('Remind error:', err.message);
        return res.status(500).json({ error: err.message });
    }
});

module.exports = router;