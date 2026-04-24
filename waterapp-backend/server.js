require('dotenv').config();
const express = require('express');
const { connectDb } = require('./config/db');

const app = express();
app.use(express.json());

app.use('/api/register', require('./routes/register'));
app.use('/api/remind', require('./routes/remind'));

app.get('/health', (req, res) => res.json({ ok: true }));

const startApp = async () => {
    await connectDb();

    if (process.env.NODE_ENV !== 'production') {
        const PORT = process.env.PORT || 3000;
        app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
    }
};

startApp().catch(err => {
    console.error('Startup failed:', err.message);
    process.exit(1);
});

module.exports = app;