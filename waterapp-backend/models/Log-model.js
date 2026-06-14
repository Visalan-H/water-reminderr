const { Schema, model } = require('mongoose');

const logSchema = new Schema({
    event: { type: String, required: true },   // e.g. 'bg_handler_fired', 'notification_shown', 'overlay_shown', 'overlay_failed', 'overlay_skipped'
    deviceId: { type: String, default: null },
    meta: { type: Schema.Types.Mixed, default: {} },
    ts: { type: Date, default: Date.now },
});

logSchema.index({ ts: -1 });
logSchema.index({ ts: 1 }, { expireAfterSeconds: 60 * 60 * 24 * 3 }); // auto-delete after 3 days

module.exports = { Log: model('Log', logSchema) };
