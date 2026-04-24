const { Schema, model } = require("mongoose");

const tokenSchema = new mongoose.Schema({
    deviceId: { type: String, required: true, unique: true },
    fcmToken: { type: String, required: true },
    intervalMinutes: { type: Number, required: true, default: 60, min: 10 },
    lastSentAt: { type: Date, default: null },
}, { timestamps: true });

const Token = model('Token', tokenSchema);

module.exports = { Token };