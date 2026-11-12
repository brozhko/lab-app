const express = require('express');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3000;

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

app.get('/health', (req, res) => res.send('OK'));

app.get('/api/users', async (req, res) => {
  try {
    const result = await pool.query('SELECT NOW() as time');
    res.json({ status: 'success', db_time: result.rows[0].time });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});
app.get('/', (req, res) => {
  res.send('Azure Container App is running and connected to PostgreSQL!');
});
app.listen(port, () => console.log(`App running on port ${port}`));