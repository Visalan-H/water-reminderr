const { Router } = require('express');
const router = Router();
const { logAuth } = require('../middleware/auth-middleware');
const { Log } = require('../models/Log-model');

// POST /api/log — called by device, auth'd with x-log-secret
router.post('/', logAuth, async (req, res) => {
    const { event, deviceId, meta } = req.body;
    if (!event || typeof event !== 'string') {
        return res.status(400).json({ error: 'event required' });
    }
    try {
        await Log.create({ event, deviceId: deviceId ?? null, meta: meta ?? {} });
        return res.status(200).json({ ok: true });
    } catch (err) {
        console.error('Log write error:', err.message);
        return res.status(500).json({ error: err.message });
    }
});

// GET /api/log?limit=50 — returns recent logs newest-first
router.get('/', logAuth, async (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 50, 200);
    try {
        const logs = await Log.find().sort({ ts: -1 }).limit(limit).lean();
        return res.status(200).json(logs);
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

// DELETE /api/log — clears all logs
router.delete('/', logAuth, async (req, res) => {
    try {
        await Log.deleteMany({});
        return res.status(200).json({ ok: true });
    } catch (err) {
        return res.status(500).json({ error: err.message });
    }
});

module.exports = router;
