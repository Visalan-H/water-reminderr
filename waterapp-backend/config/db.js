const mongoose = require('mongoose');

async function connectDb() {
    try {
        await mongoose.connect(process.env.MONGODB_URI);
        console.log('MongoDB connected');
    } catch (error) {
        throw new Error('MongoDB connection failed: ' + error.message);
    }
}

module.exports = { connectDb };