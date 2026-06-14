const { Router } = require('express');
const router = Router();
const { registerAuth } = require('../middleware/auth-middleware');
const { Token } = require('../models/Token-model');

router.post('/', registerAuth, async (req, res) => {
    const { deviceId, fcmToken, intervalMinutes, timezoneOffsetMinutes } = req.body;

    if (!deviceId || typeof deviceId !== 'string' || deviceId.length < 5) {
        return res.status(400).json({ error: 'Invalid deviceId' });
    }
    if (!fcmToken || typeof fcmToken !== 'string' || fcmToken.length < 10) {
        return res.status(400).json({ error: 'Invalid fcmToken' });
    }
    if (!Number.isFinite(intervalMinutes) || intervalMinutes < 1 || intervalMinutes > 1440) {
        return res.status(400).json({ error: 'intervalMinutes must be between 1 and 1440' });
    }

    const tzOffset = Number.isFinite(timezoneOffsetMinutes) ? timezoneOffsetMinutes : 0;

    try {
        await Token.findOneAndUpdate(
            { deviceId },
            { deviceId, fcmToken, intervalMinutes, timezoneOffsetMinutes: tzOffset },
            { upsert: true, new: true }
        );
        return res.status(200).json({ ok: true });
    } catch (err) {
        console.error('Register error:', err.message);
        return res.status(500).json({ error: 'Failed to save token' });
    }
});

module.exports = router;
