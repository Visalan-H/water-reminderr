function cronAuth(req, res, next) {
    if (req.headers['x-secret'] !== process.env.CRON_SECRET) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
}

function registerAuth(req, res, next) {
    if (req.headers['x-register-secret'] !== process.env.REGISTER_SECRET) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
}

module.exports = { cronAuth, registerAuth };