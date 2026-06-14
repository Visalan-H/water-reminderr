const { Schema, model } = require("mongoose");

const tokenSchema = new Schema({
    deviceId: { type: String, required: true, unique: true },
    fcmToken: { type: String, required: true, index: true },
    intervalMinutes: { type: Number, required: true, default: 60, min: 1 },
    timezoneOffsetMinutes: { type: Number, default: 0 },
    lastSentAt: { type: Date, default: null },
}, { timestamps: true });

const Token = model('Token', tokenSchema);

module.exports = { Token };